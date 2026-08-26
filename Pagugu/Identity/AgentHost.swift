import Foundation

// L3 COORD: Pagugu/Identity/AgentHost.swift
// POS: Identity 模块（纯函数，ADR-0009 §2）。owns Agent Host 归因表。
// TEST: repo://PaguguTests/IdentityTests.swift（host attribution 表测试追加）。

/// Agent Host 枚举（首批两个：Claude Code 与 Codex）。
enum AgentHost: String, CaseIterable, Hashable, Sendable, Comparable {
    case claude = "claude"
    case codex = "codex"

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    static func < (lhs: AgentHost, rhs: AgentHost) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Agent Host 归因表：根据 Skill Installation 的 as-found 路径与发现入口判断宿主。
/// 规则来自 #3 resolution §6：个人或项目 `.claude/skills` → Claude，个人 `.codex/skills` → Codex，
/// 个人或项目 `.agents/skills` → Codex；项目 `.codex/skills` 的宿主语义仍为 Unknown。
/// 归因表可扩展且不进入 Skill Identity。
enum HostAttribution {
    /// 目录名 → Agent Host。key 是 host 目录的精确名称（含前导点）。
    private static let directoryToHost: [String: AgentHost] = [
        ".claude": .claude,
        ".codex": .codex,
        ".agents": .codex,
    ]

    /// 返回发现入口下路径所属的 Agent Host 集合；不在任何已知规则内返回空集。
    static func hosts(for asFoundPath: String, origin: DiscoveryOrigin) -> Set<AgentHost> {
        let expanded = (asFoundPath as NSString).expandingTildeInPath
        var hosts = Set<AgentHost>()

        for (directory, host) in directoryToHost {
            if origin == .projectScanRoot, directory == ".codex" {
                continue
            }
            // 匹配 `/<dir>/skills/` 或恰好以 `/<dir>/skills` 结尾
            let pattern = "/\(directory)/skills"
            if expanded.contains(pattern + "/") || expanded.hasSuffix(pattern) {
                hosts.insert(host)
            }
        }
        return hosts
    }
}
