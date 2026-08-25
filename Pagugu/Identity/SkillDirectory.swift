import Foundation

// L3 COORD: Pagugu/Identity/SkillDirectory.swift
// POS: Identity 模块（纯函数，ADR-0009 §2）。owns 按 Skill Identity 聚合 Installation、
//      按 Skill Source 分组目录（Variant F：来源仓库行 + 无仓库可归行）、
//      复制投影按内容指纹聚合呈现组。
// TEST: repo://PaguguTests/IdentityTests.swift（分组聚合表测试）。
// IN: ScanResult（含 Discovery Origin，来自 Discovery）+ 当前无人工来源映射；
// OUT: SkillDirectoryContents（Skill Read Model 消费）。

enum SkillDirectory {
    /// 将 Discovery Scan 的结果聚合为 Variant F 目录：
    /// - 工作树内的 Skill 按 Skill Source Key（仓库根 canonical 路径）分组为来源仓库行，
    ///   同一 canonical path 的多个 as-found 入口聚合为一个 Skill 的多个 Installation（ADR-0001 §3）；
    /// - 不在任何工作树内的复制投影：内容指纹一致才聚合为一个只读呈现组，
    ///   内容不同或指纹缺失（读取不完整）按安装 Canonical Path 各自单列（ADR-0001 §4，#16 修正）；
    ///   零 Installation 的纯来源发现（Project Scan Root 内无宿主可归）永不合并、按自身路径单列。
    /// Installation 产生规则（#18）：Personal Skill Root 入口或带宿主归因的 as-found 路径
    /// 才产生 Installation；指纹只用于复制投影之间的呈现聚合，永不用于来源归因。
    static func contents(from result: ScanResult) -> SkillDirectoryContents {
        // 第一遍：按 canonical path 聚合 Installation（同一物理目录的多个 as-found 入口）
        var byCanonical: [String: (name: String, repositoryRoot: String?, fingerprint: String?, installations: [SkillInstallation])] = [:]

        for skill in result.skills {
            let hosts = HostAttribution.hosts(for: skill.asFoundPath)
            let producesInstallation = skill.origin == .personalSkillRoot || !hosts.isEmpty
            if var existing = byCanonical[skill.canonicalPath] {
                if producesInstallation {
                    existing.installations.append(installation(for: skill, hosts: hosts))
                }
                byCanonical[skill.canonicalPath] = existing
            } else {
                byCanonical[skill.canonicalPath] = (
                    name: skill.name,
                    repositoryRoot: skill.repositoryRootPath,
                    fingerprint: skill.contentFingerprint,
                    installations: producesInstallation ? [installation(for: skill, hosts: hosts)] : []
                )
            }
        }

        // 第二遍：按工作树根分组为来源仓库行；复制投影按内容指纹聚合呈现组
        var entriesByRoot: [String: [SkillDirectoryEntry]] = [:]
        var unattributedByGroup: [String: (name: String, representativeCanonical: String, installations: [SkillInstallation])] = [:]

        for (canonicalPath, value) in byCanonical {
            let installations = value.installations.sorted { $0.asFoundPath < $1.asFoundPath }
            if let root = value.repositoryRoot {
                let relativePath = canonicalPath == root
                    ? ""
                    : String(canonicalPath.dropFirst(root.count + 1))
                let entry = SkillDirectoryEntry(
                    id: SkillIdentity(sourceKey: .localPath(root), repositoryRelativePath: relativePath),
                    displayName: value.name,
                    canonicalPath: canonicalPath,
                    installations: installations
                )
                entriesByRoot[root, default: []].append(entry)
            } else {
                // 有安装的复制投影才可合并（以内容指纹为键）；指纹缺失 fail closed 单列；
                // 零安装的纯来源发现永不合并（身份即自身位置，内容一致不推断同一 Skill）
                let mergeable = !installations.isEmpty
                let groupKey = (mergeable ? value.fingerprint : nil).map { "sha256:" + $0 } ?? canonicalPath
                if var group = unattributedByGroup[groupKey] {
                    group.installations.append(contentsOf: installations)
                    group.representativeCanonical = min(group.representativeCanonical, canonicalPath)
                    unattributedByGroup[groupKey] = group
                } else {
                    unattributedByGroup[groupKey] = (
                        name: value.name,
                        representativeCanonical: canonicalPath,
                        installations: installations
                    )
                }
            }
        }

        let sources = entriesByRoot.map { root, entries in
            SkillSourceItem(
                id: .localPath(root),
                displayName: (root as NSString).lastPathComponent,
                skills: entries.sorted {
                    $0.id.repositoryRelativePath != $1.id.repositoryRelativePath
                        ? $0.id.repositoryRelativePath < $1.id.repositoryRelativePath
                        : $0.displayName < $1.displayName
                }
            )
        }
        .sorted {
            $0.displayName != $1.displayName
                ? $0.displayName < $1.displayName
                : $0.id.displayString < $1.id.displayString
        }

        let unattributed = unattributedByGroup.map { groupKey, group in
            UnattributedInstallationItem(
                id: groupKey,
                displayName: group.name,
                canonicalPath: group.representativeCanonical,
                installations: group.installations.sorted { $0.asFoundPath < $1.asFoundPath }
            )
        }
        .sorted {
            $0.displayName != $1.displayName
                ? $0.displayName < $1.displayName
                : $0.id < $1.id
        }

        return SkillDirectoryContents(
            sources: sources,
            unattributedInstallations: unattributed
        )
    }

    private static func installation(
        for skill: DiscoveredSkill,
        hosts: Set<AgentHost>
    ) -> SkillInstallation {
        SkillInstallation(
            asFoundPath: skill.asFoundPath,
            canonicalPath: skill.canonicalPath,
            hosts: hosts,
            projectionType: projectionType(of: skill)
        )
    }

    /// Projection Type 派生（ADR-0001 §4）：asFound 完全解析后与 canonical 不同 = 软链接；
    /// 相同且在工作树内 = 仓库本体；相同且无工作树 = 复制。
    private static func projectionType(of skill: DiscoveredSkill) -> ProjectionType {
        let expanded = (skill.asFoundPath as NSString).expandingTildeInPath
        if expanded != skill.canonicalPath { return .symlink }
        return skill.repositoryRootPath != nil ? .repositorySelf : .copy
    }
}
