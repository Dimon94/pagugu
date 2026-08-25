import Foundation

// L3 COORD: Pagugu/Identity/SkillIdentity.swift
// POS: Identity 模块（纯函数，ADR-0009 §2）。owns Skill Identity、Skill Source Key 规范化、
//      归因与聚合；does not own 文件系统遍历（归 Discovery）、Git 子进程、任何副作用。
// IN: Discovery 产出的 Scan Result 值类型；OUT: Skill Read Model 消费的 Skill 目录条目。
// TEST: repo://PaguguTests/IdentityTests.swift（Source Key 规范化表测试）；后续切片补归因表测试。

/// Skill Source Key（ADR-0001 §1）：有 origin 远程时为规范化远程 URL；无远程时为仓库 canonical 绝对路径。
enum SkillSourceKey: Hashable, Sendable {
    case remoteURL(String)
    case localPath(String)

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

        var parts = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let host = parts[0].lowercased()
        var path = String(parts[1])
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix(".git") { path.removeLast(4) }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        return .remoteURL(host + "/" + path)
    }
}

/// Skill Identity（ADR-0001 §1）：Skill Source Key + 仓内相对路径。
struct SkillIdentity: Hashable, Sendable {
    let sourceKey: SkillSourceKey
    let repositoryRelativePath: String
}
