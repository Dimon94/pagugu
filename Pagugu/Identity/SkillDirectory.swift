import Foundation

// L3 COORD: Pagugu/Identity/SkillDirectory.swift
// POS: Identity 模块（纯函数，ADR-0009 §2）。owns 按 Skill Identity 聚合 Installation、
//      按 Skill Source 分组目录（Variant F：来源仓库行 + 无仓库可归行）、
//      同一 remote 多检出保留、复制投影指纹呈现组与人工来源映射事实投影。
// TEST: repo://PaguguTests/IdentityTests.swift（分组、检出与映射生命周期表测试）。
// IN: ScanResult + 每个候选检出根的实时 Git Fact + Registry 来源映射主张；
// OUT: SkillDirectoryContents（Skill Read Model 消费）。

enum SkillDirectory {
    private struct SourceAccumulator {
        var checkoutsByPath: [String: SkillSourceCheckout] = [:]
        var entriesByIdentity: [SkillIdentity: SkillDirectoryEntry] = [:]
    }

    /// 将 Discovery Scan 聚合为 Variant F 目录。Git Fact 只决定 Source Key；
    /// 映射只把复制 Installation 投影到既有 Skill Identity，不改变来源或检出事实。
    static func contents(
        from result: ScanResult,
        gitFactsByCheckoutPath: [String: CheckoutGitFacts] = [:],
        mappings: [String: SourceMappingRecord] = [:]
    ) -> SkillDirectoryContents {
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

        var sourcesByKey: [SkillSourceKey: SourceAccumulator] = [:]
        var unattributedByGroup: [String: (name: String, representativeCanonical: String, installations: [SkillInstallation])] = [:]

        for (canonicalPath, value) in byCanonical {
            guard let root = value.repositoryRoot else { continue }
            let key = sourceKey(checkoutPath: root, facts: gitFactsByCheckoutPath[root])
            let relativePath = canonicalPath == root
                ? ""
                : String(canonicalPath.dropFirst(root.count + 1))
            let identity = SkillIdentity(sourceKey: key, repositoryRelativePath: relativePath)
            let installations = value.installations.sorted { $0.asFoundPath < $1.asFoundPath }
            var source = sourcesByKey[key] ?? SourceAccumulator()
            source.checkoutsByPath[root] = SkillSourceCheckout(canonicalPath: root)
            if let existing = source.entriesByIdentity[identity] {
                source.entriesByIdentity[identity] = SkillDirectoryEntry(
                    id: identity,
                    displayName: existing.displayName,
                    canonicalPath: min(existing.canonicalPath, canonicalPath),
                    installations: (existing.installations + installations).sorted { $0.asFoundPath < $1.asFoundPath }
                )
            } else {
                source.entriesByIdentity[identity] = SkillDirectoryEntry(
                    id: identity,
                    displayName: value.name,
                    canonicalPath: canonicalPath,
                    installations: installations
                )
            }
            sourcesByKey[key] = source
        }

        let copyPaths = Set(byCanonical.compactMap { path, value in
            value.repositoryRoot == nil && value.installations.contains { $0.projectionType == .copy }
                ? path
                : nil
        })
        let candidateRoots = result.candidateSourceRoots.union(result.skills.compactMap(\.repositoryRootPath))
        let discoveredSourceKeys = Set(candidateRoots.map {
            sourceKey(checkoutPath: $0, facts: gitFactsByCheckoutPath[$0])
        })
        let discoveredSkillIdentities = Set(sourcesByKey.values.flatMap { $0.entriesByIdentity.keys })
        var projectionsByPath: [String: SourceMappingProjection] = [:]
        for (path, record) in mappings {
            guard let key = SkillSourceKey(registryValue: record.skillSourceKey) else { continue }
            let identity = SkillIdentity(sourceKey: key, repositoryRelativePath: record.repositoryRelativePath)
            projectionsByPath[path] = SourceMappingProjection(
                installationCanonicalPath: path,
                targetIdentity: identity,
                validity: SourceMappingEvaluator.evaluate(
                    installationCanonicalPath: path,
                    targetIdentity: identity,
                    scanOutcome: result.outcome,
                    copyInstallationPaths: copyPaths,
                    discoveredSourceKeys: discoveredSourceKeys,
                    discoveredSkillIdentities: discoveredSkillIdentities
                )
            )
        }

        for (canonicalPath, value) in byCanonical where value.repositoryRoot == nil {
            let projection = projectionsByPath[canonicalPath]
            let installations = value.installations
                .map { installation($0, sourceMapping: projection) }
                .sorted { $0.asFoundPath < $1.asFoundPath }

            if projection?.validity == .valid,
               let target = projection?.targetIdentity,
               var source = sourcesByKey[target.sourceKey],
               let entry = source.entriesByIdentity[target] {
                source.entriesByIdentity[target] = SkillDirectoryEntry(
                    id: entry.id,
                    displayName: entry.displayName,
                    canonicalPath: entry.canonicalPath,
                    installations: (entry.installations + installations).sorted { $0.asFoundPath < $1.asFoundPath }
                )
                sourcesByKey[target.sourceKey] = source
            } else {
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

        let sources = sourcesByKey.map { key, source in
            SkillSourceItem(
                id: key,
                displayName: (key.displayString as NSString).lastPathComponent,
                skills: source.entriesByIdentity.values.sorted {
                    $0.id.repositoryRelativePath != $1.id.repositoryRelativePath
                        ? $0.id.repositoryRelativePath < $1.id.repositoryRelativePath
                        : $0.displayName < $1.displayName
                },
                checkouts: source.checkoutsByPath.values.sorted { $0.canonicalPath < $1.canonicalPath }
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
            unattributedInstallations: unattributed,
            mappingTargets: sources.flatMap(\.skills),
            invalidMappings: projectionsByPath.values
                .filter { if case .invalid = $0.validity { return true }; return false }
                .sorted { $0.installationCanonicalPath < $1.installationCanonicalPath }
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
            projectionType: projectionType(of: skill),
            sourceMapping: nil
        )
    }

    private static func installation(
        _ installation: SkillInstallation,
        sourceMapping: SourceMappingProjection?
    ) -> SkillInstallation {
        SkillInstallation(
            asFoundPath: installation.asFoundPath,
            canonicalPath: installation.canonicalPath,
            hosts: installation.hosts,
            projectionType: installation.projectionType,
            sourceMapping: sourceMapping
        )
    }

    /// 有可用 origin 时升级为规范化 remote key；否则保持 checkout path key。
    private static func sourceKey(
        checkoutPath: String,
        facts: CheckoutGitFacts?
    ) -> SkillSourceKey {
        guard facts?.inspectionFailure == nil,
              let remoteURL = facts?.originRemoteURL,
              let remoteKey = SkillSourceKey.normalize(remoteURL: remoteURL) else {
            return .localPath(checkoutPath)
        }
        return remoteKey
    }

    private static func projectionType(of skill: DiscoveredSkill) -> ProjectionType {
        let expanded = (skill.asFoundPath as NSString).expandingTildeInPath
        if expanded != skill.canonicalPath { return .symlink }
        return skill.repositoryRootPath != nil ? .repositorySelf : .copy
    }
}
