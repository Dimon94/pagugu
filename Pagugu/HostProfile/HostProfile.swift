import Foundation

// L3 COORD: Pagugu/HostProfile/HostProfile.swift
// POS: HostProfile 模块。owns Agent Host、受支持 Skill 根与同名冲突规则值类型，
//      以及路径到 Agent Host 的确定性归属。does not own Discovery 遍历、Skill Identity 或 UI 投影。
// TEST: repo://PaguguTests/DiscoveryPiRootsTests.swift、repo://PaguguTests/NameCollisionTests.swift。

/// 首批支持的 Agent Host。
enum AgentHost: String, CaseIterable, Hashable, Sendable, Comparable {
    case claude = "claude"
    case codex = "codex"
    case pi = "pi"

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .pi: return "Pi"
        }
    }

    static func < (lhs: AgentHost, rhs: AgentHost) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Host Profile 判断 Skill 路径时使用的发现范围。
enum HostSkillScope: Hashable, Sendable {
    case personal
    case project
}

/// 一个 Agent Host 对同名 Skill 的裁决规则。
enum NameCollisionRule: Hashable, Sendable {
    case personalShadowsProject
    case ambiguousCoexistence
}

/// 单个 Agent Host 的只读规则档案。
struct HostProfile: Hashable, Sendable {
    let host: AgentHost
    /// 相对 Home 的 Personal Skill Root。不同宿主可共享同一个根。
    let personalRootRelativePaths: [String]
    /// Project Scan Root 内可归因给该宿主的 Skill 根。
    let projectRootRelativePaths: [String]
    let nameCollisionRule: NameCollisionRule

    fileprivate func containsSkill(at path: String, scope: HostSkillScope) -> Bool {
        let supportedRoots = scope == .personal
            ? personalRootRelativePaths
            : projectRootRelativePaths
        let expandedPath = (path as NSString).expandingTildeInPath
        return supportedRoots.contains { relativePath in
            let rootComponent = "/" + relativePath
            return expandedPath.contains(rootComponent + "/") || expandedPath.hasSuffix(rootComponent)
        }
    }
}

/// 三大宿主规则的 canonical owner。
enum HostProfiles {
    static let claudeCode = HostProfile(
        host: .claude,
        personalRootRelativePaths: [".claude/skills"],
        projectRootRelativePaths: [".claude/skills"],
        nameCollisionRule: .personalShadowsProject
    )

    static let codex = HostProfile(
        host: .codex,
        personalRootRelativePaths: [".agents/skills", ".codex/skills"],
        projectRootRelativePaths: [".agents/skills"],
        nameCollisionRule: .ambiguousCoexistence
    )

    static let pi = HostProfile(
        host: .pi,
        personalRootRelativePaths: [".pi/agent/skills", ".agents/skills"],
        projectRootRelativePaths: [],
        nameCollisionRule: .ambiguousCoexistence
    )

    static let all: [HostProfile] = [claudeCode, codex, pi]

    /// Discovery 默认扫描的 Personal Skill Root。共享根只返回一次。
    static func personalSkillRoots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        var seen = Set<String>()
        return all.flatMap(\.personalRootRelativePaths).compactMap { relativePath in
            let path = homeDirectory.appendingPathComponent(relativePath).path
            return seen.insert(path).inserted ? path : nil
        }
    }

    /// 根据 as-found 路径与发现范围派生全部 Agent Host；共享根可返回多个宿主。
    static func hosts(for asFoundPath: String, scope: HostSkillScope) -> Set<AgentHost> {
        Set(all.compactMap { profile in
            profile.containsSkill(at: asFoundPath, scope: scope) ? profile.host : nil
        })
    }
}
