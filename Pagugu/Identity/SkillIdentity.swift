import Foundation

// L3 COORD: Pagugu/Identity/SkillIdentity.swift
// POS: Identity 模块（纯函数，ADR-0009 §2）。owns Skill Identity、Skill Source Key 规范化、
//      来源映射失效原因与基于扫描事实的重验证；does not own Registry 写入、文件系统遍历、
//      Git 子进程或任何副作用。
// IN: Installation/Source/Skill 扫描事实与持久映射目标；OUT: SourceMappingValidity。
// TEST: repo://PaguguTests/IdentityTests.swift（Source Key 规范化与映射有效/失效/复活表测试）。

/// Skill Source Key（ADR-0001 §1）：有 origin 远程时为规范化远程 URL；无远程时为仓库 canonical 绝对路径。
enum SkillSourceKey: Hashable, Sendable {
    case remoteURL(String)
    case localPath(String)

    /// 展示用字符串：规范化远程 URL 或本地 canonical 路径。
    var displayString: String {
        switch self {
        case .remoteURL(let url): return url
        case .localPath(let path): return path
        }
    }

    /// 规范化远程 URL：忽略协议与认证方式、去 `.git` 尾缀、host 小写、路径大小写不归一。
    /// 无法解析出 host 与仓库路径时返回 nil（Discovery 层据此不生成来源）。
    static func normalize(remoteURL raw: String) -> SkillSourceKey? {
        var rest = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }

        if let schemeRange = rest.range(of: "://") {
            rest = String(rest[schemeRange.upperBound...])
        } else {
            // scp 风格：git@github.com:owner/repo.git
            let first = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard first.count == 2, first[0].contains("@") else { return nil }
            rest = first[0] + "/" + first[1]
        }

        if let atIndex = rest.lastIndex(of: "@") {
            rest = String(rest[rest.index(after: atIndex)...])
        }

        let parts = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let host = parts[0].lowercased()
        var path = String(parts[1])
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix(".git") { path.removeLast(4) }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        return .remoteURL(host + "/" + path)
    }

    init?(registryValue: String) {
        guard !registryValue.isEmpty else { return nil }
        self = registryValue.hasPrefix("/") ? .localPath(registryValue) : .remoteURL(registryValue)
    }

    var registryValue: String {
        switch self {
        case .remoteURL(let value), .localPath(let value): value
        }
    }
}

/// Skill Identity（ADR-0001 §1）：Skill Source Key + 仓内相对路径。
struct SkillIdentity: Hashable, Sendable {
    let sourceKey: SkillSourceKey
    let repositoryRelativePath: String
}

enum SourceMappingInvalidReason: String, Hashable, Sendable {
    case installationNotCopy
    case sourceNotFound
    case skillNotFound

    var message: String {
        switch self {
        case .installationNotCopy:
            return "Installation 已不存在，或已改为软链接/仓库本体。"
        case .sourceNotFound:
            return "目标 Skill Source 已移出扫描范围、被移动或来源标识已变化。"
        case .skillNotFound:
            return "目标 Skill 的仓内相对路径已不存在。"
        }
    }
}

enum SourceMappingValidity: Hashable, Sendable {
    case valid
    case invalid(SourceMappingInvalidReason)
    case unverified
}

enum SourceMappingEvaluator {
    /// 只在完整 Scan Result 下判失效；依赖事实恢复后，同一记录会重新变为 valid。
    static func evaluate(
        installationCanonicalPath: String,
        targetIdentity: SkillIdentity,
        scanOutcome: ScanOutcome,
        copyInstallationPaths: Set<String>,
        discoveredSourceKeys: Set<SkillSourceKey>,
        discoveredSkillIdentities: Set<SkillIdentity>
    ) -> SourceMappingValidity {
        guard case .complete = scanOutcome else { return .unverified }
        guard copyInstallationPaths.contains(installationCanonicalPath) else {
            return .invalid(.installationNotCopy)
        }
        guard discoveredSourceKeys.contains(targetIdentity.sourceKey) else {
            return .invalid(.sourceNotFound)
        }
        guard discoveredSkillIdentities.contains(targetIdentity) else {
            return .invalid(.skillNotFound)
        }
        return .valid
    }
}
