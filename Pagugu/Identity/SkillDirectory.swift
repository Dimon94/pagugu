import Foundation

// L3 COORD: Pagugu/Identity/SkillDirectory.swift
// POS: Identity 模块（纯函数，ADR-0009 §2）。owns 按 Skill Identity 聚合 Installation 为 Skill 目录条目。
// TEST: repo://PaguguTests/IdentityTests.swift（归因聚合表测试追加）。
// IN: ScanResult（含 Discovery Origin）+ 当前无人工来源映射；
// OUT: [SkillDirectoryEntry]（Skill Read Model 消费）。

enum SkillDirectory {
    /// 将 Discovery Scan 的结果聚合为按 Skill Identity 组织的目录条目。
    /// 同一 canonical path（即同一 Skill Source Key）聚合为一个 Skill 条目，
    /// Personal Skill Root 与 Project Scan Root 内宿主目录产生 Installation；纯来源 Skill 保持零 Installation。
    /// 复制投影不产生条目（#15 不展示「来源不明」行，后续票补）。
    static func entries(from result: ScanResult) -> [SkillDirectoryEntry] {
        // 按 canonical path 分组：同一 Skill Source 的多个 as-found 入口聚合为一个条目
        var byCanonical: [String: (name: String, installations: [SkillInstallation])] = [:]

        for skill in result.skills {
            let hosts = HostAttribution.hosts(for: skill.asFoundPath)
            if var existing = byCanonical[skill.canonicalPath] {
                if skill.origin == .personalSkillRoot || !hosts.isEmpty {
                    existing.installations.append(installation(for: skill, hosts: hosts))
                }
                byCanonical[skill.canonicalPath] = existing
            } else {
                let installations = skill.origin == .personalSkillRoot || !hosts.isEmpty
                    ? [installation(for: skill, hosts: hosts)]
                    : []
                byCanonical[skill.canonicalPath] = (name: skill.name, installations: installations)
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

    private static func installation(
        for skill: DiscoveredSkill,
        hosts: Set<AgentHost>
    ) -> SkillInstallation {
        let asFoundExpanded = (skill.asFoundPath as NSString).expandingTildeInPath
        return SkillInstallation(
            asFoundPath: skill.asFoundPath,
            hosts: hosts,
            isSymlink: asFoundExpanded != skill.canonicalPath
        )
    }

    /// 从 DiscoveredSkill 推导 Skill Source Key（#15 只处理 Personal Root 内的顶层 Skill）。
    private static func sourceKey(for skill: DiscoveredSkill) -> SkillSourceKey {
        // 有 origin 远程的 Skill Source 由 Git seam 产出（#19 后续票接通）。
        // #15 阶段：所有 Skill 均视为本地来源，以 canonical 绝对路径为键（ADR-0001 §2）。
        .localPath(skill.canonicalPath)
    }
}
