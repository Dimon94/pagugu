import Foundation

// L3 COORD: Pagugu/Identity/SkillDirectory.swift
// POS: Identity 模块（纯函数，ADR-0009 §2）。owns 按 Skill Identity 聚合 Installation 为 Skill 目录条目。
// TEST: repo://PaguguTests/IdentityTests.swift（归因聚合表测试追加）。
// IN: ScanResult（来自 Discovery）+ 当前无人工来源映射（#15 不含 Registry）；
// OUT: [SkillDirectoryEntry]（Skill Read Model 消费）。

enum SkillDirectory {
    /// 将 Discovery Scan 的结果聚合为按 Skill Identity 组织的目录条目。
    /// 同一 canonical path（即同一 Skill Source Key）聚合为一个 Skill 条目，
    /// 每个 as-found 路径产生一个 Installation（ADR-0001 §3）。
    /// 复制投影不产生条目（#15 不展示「来源不明」行，后续票补）。
    static func entries(from result: ScanResult) -> [SkillDirectoryEntry] {
        // 按 canonical path 分组：同一 Skill Source 的多个 as-found 入口聚合为一个条目
        var byCanonical: [String: (name: String, installations: [SkillInstallation])] = [:]

        for skill in result.skills {
            let hosts = HostAttribution.hosts(for: skill.asFoundPath)
            let asFoundExpanded = (skill.asFoundPath as NSString).expandingTildeInPath
            let installation = SkillInstallation(
                asFoundPath: skill.asFoundPath,
                hosts: hosts,
                isSymlink: asFoundExpanded != skill.canonicalPath
            )
            if var existing = byCanonical[skill.canonicalPath] {
                existing.installations.append(installation)
                byCanonical[skill.canonicalPath] = existing
            } else {
                byCanonical[skill.canonicalPath] = (name: skill.name, installations: [installation])
            }
        }

        return byCanonical
            .map { canonicalPath, value in
                SkillDirectoryEntry(
                    id: SkillIdentity(
                        sourceKey: .localPath(canonicalPath),
                        repositoryRelativePath: ""
                    ),
                    displayName: value.name,
                    installations: value.installations
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }

    /// 从 DiscoveredSkill 推导 Skill Source Key（#15 只处理 Personal Root 内的顶层 Skill）。
    private static func sourceKey(for skill: DiscoveredSkill) -> SkillSourceKey {
        // 有 origin 远程的 Skill Source 由 Git seam 产出（#19 后续票接通）。
        // #15 阶段：所有 Skill 均视为本地来源，以 canonical 绝对路径为键（ADR-0001 §2）。
        .localPath(skill.canonicalPath)
    }
}
