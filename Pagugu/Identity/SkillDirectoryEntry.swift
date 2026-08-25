import Foundation

// L3 COORD: Pagugu/Identity/SkillDirectoryEntry.swift
// POS: Identity 模块（纯函数，ADR-0009 §2）。owns Skill 目录条目聚合（ADR-0001 §3：列表条目 = Skill）。
// TEST: repo://PaguguTests/IdentityTests.swift（归因聚合表测试追加）。

/// 一条 Skill 目录条目（Skill Identity + 聚合属性）。
struct SkillDirectoryEntry: Identifiable, Hashable, Sendable {
    let id: SkillIdentity
    let displayName: String
    let installations: [SkillInstallation]
}

/// 一个 Skill Installation：as-found 路径、Agent Host 集合、投影类型。
struct SkillInstallation: Hashable, Sendable {
    let asFoundPath: String
    let hosts: Set<AgentHost>
    let isSymlink: Bool
}
