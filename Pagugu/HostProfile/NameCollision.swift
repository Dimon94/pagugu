import Foundation

// L3 COORD: Pagugu/HostProfile/NameCollision.swift
// POS: HostProfile 模块。owns 同名共存组与逐宿主遮蔽/歧义共存诊断的纯函数派生。
// TEST: repo://PaguguTests/NameCollisionTests.swift。

/// 一个 Skill 在某个 Agent Host 下的安装范围事实。
struct HostSkillLocation: Hashable, Sendable {
    let host: AgentHost
    let scope: HostSkillScope
}

/// 同名共存组派生所需的最小 Skill 输入。
struct NameCollisionCandidate: Hashable, Sendable {
    let id: String
    let frontmatterName: String?
    let installationDirectoryName: String
    let locations: Set<HostSkillLocation>
}

enum CollisionDiagnosticKind: Hashable, Sendable {
    case shadowed
    case ambiguous
}

/// 一个同名共存组在单个 Agent Host 下的客观诊断。
struct CollisionDiagnostic: Hashable, Sendable {
    let host: AgentHost
    let kind: CollisionDiagnosticKind

    var message: String {
        switch kind {
        case .shadowed:
            return "\(host.displayName)：Personal Skill 覆盖同名 Project Skill；Project Skill 被遮蔽。"
        case .ambiguous:
            return "\(host.displayName)：多个同名 Skill 歧义共存。"
        }
    }
}

/// 基于展示名聚合的同名共存组。它与 Skill Identity 正交，不参与归因或更新资格。
struct NameCollisionGroup: Hashable, Sendable {
    let normalizedName: String
    let displayName: String
    let memberIDs: [String]
    let diagnostics: [CollisionDiagnostic]
}

enum NameCollisionEngine {
    /// 同名规则的 canonical normalization。写入共享 name-key 前也必须复用该规则检查歧义。
    static func normalizedName(_ displayName: String) -> String? {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return trimmedName.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    /// 基于 trim + 大小写折叠聚合；frontmatter name 缺失或空白时回退安装目录名。
    /// 只有至少两个不同 Skill 候选的名称才产出同名共存组。
    static func groups(from candidates: [NameCollisionCandidate]) -> [NameCollisionGroup] {
        let namedCandidates = candidates.compactMap { candidate -> (String, String, NameCollisionCandidate)? in
            let frontmatterName = candidate.frontmatterName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String
            if let frontmatterName, !frontmatterName.isEmpty {
                displayName = frontmatterName
            } else {
                displayName = candidate.installationDirectoryName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let normalizedName = normalizedName(displayName) else { return nil }
            return (normalizedName, displayName, candidate)
        }

        return Dictionary(grouping: namedCandidates, by: { $0.0 })
            .compactMap { normalizedName, namedMembers -> NameCollisionGroup? in
                let candidatesByID = Dictionary(
                    namedMembers.map { ($0.2.id, $0.2) },
                    uniquingKeysWith: { first, _ in first }
                )
                let members = candidatesByID.values.sorted { $0.id < $1.id }
                guard members.count > 1 else { return nil }

                return NameCollisionGroup(
                    normalizedName: normalizedName,
                    displayName: namedMembers.map(\.1).sorted().first ?? normalizedName,
                    memberIDs: members.map(\.id),
                    diagnostics: diagnostics(for: members)
                )
            }
            .sorted { $0.normalizedName < $1.normalizedName }
    }

    private static func diagnostics(for candidates: [NameCollisionCandidate]) -> [CollisionDiagnostic] {
        HostProfiles.all.compactMap { profile in
            let hostCandidates = candidates.filter { candidate in
                candidate.locations.contains { $0.host == profile.host }
            }
            guard hostCandidates.count > 1 else { return nil }

            switch profile.nameCollisionRule {
            case .personalShadowsProject:
                let scopes = Set(hostCandidates.flatMap { candidate in
                    candidate.locations.filter { $0.host == profile.host }.map(\.scope)
                })
                guard scopes.contains(.personal), scopes.contains(.project) else { return nil }
                return CollisionDiagnostic(host: profile.host, kind: .shadowed)
            case .ambiguousCoexistence:
                return CollisionDiagnostic(host: profile.host, kind: .ambiguous)
            }
        }
    }
}
