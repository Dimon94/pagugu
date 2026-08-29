import XCTest
@testable import Pagugu

// Skill Source Key 规范化表测试（ADR-0001 §1：忽略协议与认证、去 .git、host 小写、路径大小写不归一；fork 是不同来源）。
final class IdentityTests: XCTestCase {
    func testSourceMappingValidityTableAndAutomaticRevival() {
        let identity = SkillIdentity(
            sourceKey: .localPath("/projects/repo"),
            repositoryRelativePath: "skills/example"
        )
        let installationPath = "/installations/example"
        let validFacts = (
            copies: Set([installationPath]),
            sources: Set([identity.sourceKey]),
            skills: Set([identity])
        )

        XCTAssertEqual(
            SourceMappingEvaluator.evaluate(
                installationCanonicalPath: installationPath,
                targetIdentity: identity,
                scanOutcome: .complete,
                copyInstallationPaths: validFacts.copies,
                discoveredSourceKeys: validFacts.sources,
                discoveredSkillIdentities: validFacts.skills
            ),
            .valid
        )
        XCTAssertEqual(
            SourceMappingEvaluator.evaluate(
                installationCanonicalPath: installationPath,
                targetIdentity: identity,
                scanOutcome: .complete,
                copyInstallationPaths: [],
                discoveredSourceKeys: validFacts.sources,
                discoveredSkillIdentities: validFacts.skills
            ),
            .invalid(.installationNotCopy)
        )
        XCTAssertEqual(
            SourceMappingEvaluator.evaluate(
                installationCanonicalPath: installationPath,
                targetIdentity: identity,
                scanOutcome: .complete,
                copyInstallationPaths: validFacts.copies,
                discoveredSourceKeys: [],
                discoveredSkillIdentities: []
            ),
            .invalid(.sourceNotFound)
        )
        XCTAssertEqual(
            SourceMappingEvaluator.evaluate(
                installationCanonicalPath: installationPath,
                targetIdentity: identity,
                scanOutcome: .complete,
                copyInstallationPaths: validFacts.copies,
                discoveredSourceKeys: validFacts.sources,
                discoveredSkillIdentities: []
            ),
            .invalid(.skillNotFound)
        )
        for outcome in [ScanOutcome.partial, .failed] {
            XCTAssertEqual(
                SourceMappingEvaluator.evaluate(
                    installationCanonicalPath: installationPath,
                    targetIdentity: identity,
                    scanOutcome: outcome,
                    copyInstallationPaths: [],
                    discoveredSourceKeys: [],
                    discoveredSkillIdentities: []
                ),
                .unverified
            )
        }
    }
    func testSourceKeyNormalizationUnifiesProtocolAndAuthForms() {
        let forms = [
            "https://github.com/Dimon94/pagugu.git",
            "http://github.com/Dimon94/pagugu.git",
            "git@github.com:Dimon94/pagugu.git",
            "ssh://git@github.com/Dimon94/pagugu.git",
            "git://github.com/Dimon94/pagugu",
            "https://dimon:token@github.com/Dimon94/pagugu/",
        ]
        let keys = forms.map { SkillSourceKey.normalize(remoteURL: $0) }
        XCTAssertEqual(keys, Array(repeating: .remoteURL("github.com/Dimon94/pagugu"), count: forms.count))
    }

    func testSourceKeyNormalizationLowercasesHostButPreservesPathCase() {
        XCTAssertEqual(
            SkillSourceKey.normalize(remoteURL: "HTTPS://GITHUB.COM/Dimon94/PaGuGu.GIT"),
            .remoteURL("github.com/Dimon94/PaGuGu")
        )
    }

    func testSourceKeyNormalizationTreatsForkAsDistinctSource() {
        let upstream = SkillSourceKey.normalize(remoteURL: "https://github.com/Owner/repo.git")
        let fork = SkillSourceKey.normalize(remoteURL: "https://github.com/Dimon94/repo.git")
        XCTAssertNotEqual(upstream, fork)
    }

    func testSourceKeyNormalizationRejectsUnusableInput() {
        XCTAssertNil(SkillSourceKey.normalize(remoteURL: ""))
        XCTAssertNil(SkillSourceKey.normalize(remoteURL: "not a url"))
        XCTAssertNil(SkillSourceKey.normalize(remoteURL: "https://github.com/"))
    }

    // MARK: - Host Attribution（#3 resolution §6）

    func testHostAttributionClaudeCode() {
        let hosts = HostProfiles.hosts(
            for: "~/.claude/skills/my-skill",
            scope: .personal
        )
        XCTAssertEqual(hosts, [.claude])
    }

    func testHostAttributionCodex() {
        let hosts = HostProfiles.hosts(
            for: "~/.codex/skills/my-skill",
            scope: .personal
        )
        XCTAssertEqual(hosts, [.codex])
    }

    func testHostAttributionPersonalAgentsGoesToCodexAndPi() {
        // Personal .agents/skills 是 Codex 与 Pi 的共享根。
        let hosts = HostProfiles.hosts(
            for: "~/.agents/skills/my-skill",
            scope: .personal
        )
        XCTAssertEqual(hosts, [.codex, .pi])
    }

    func testHostAttributionProjectAgentsGoesToCodex() {
        let hosts = HostProfiles.hosts(
            for: "~/Code/repo/.agents/skills/my-skill",
            scope: .project
        )
        XCTAssertEqual(hosts, [.codex])
    }

    func testHostAttributionUnknownPathReturnsEmpty() {
        let hosts = HostProfiles.hosts(
            for: "~/random/path/skills",
            scope: .project
        )
        XCTAssertTrue(hosts.isEmpty)
    }

    // MARK: - Skill 目录分组（ADR-0001 §3：列表条目 = Skill；Variant F：仓库行是呈现分组）

    func testContentsGroupsSkillsOfSameSourceIntoOneRepositoryRow() {
        // 套件型仓库：同一工作树根下的多个 Skill 聚合为一行来源仓库（ADR-0001 §2：本地键 = 仓库 canonical 路径）
        let root = ("~/suite-repo" as NSString).expandingTildeInPath
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/suite-repo/skills/skill-a",
                canonicalPath: root + "/skills/skill-a",
                name: "skill-a",
                repositoryRootPath: root
            ),
            DiscoveredSkill(
                asFoundPath: "~/suite-repo/skills/skill-b",
                canonicalPath: root + "/skills/skill-b",
                name: "skill-b",
                repositoryRootPath: root
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        XCTAssertEqual(contents.sources.count, 1, "同一工作树根 = 一个来源仓库行")
        XCTAssertEqual(contents.unattributedInstallations.count, 0)
        let source = try! XCTUnwrap(contents.sources.first)
        XCTAssertEqual(source.id, .localPath(root))
        XCTAssertEqual(source.displayName, "suite-repo")
        XCTAssertEqual(source.skills.count, 2, "仓库行下挂全部子 Skill")
        XCTAssertEqual(
            Set(source.skills.map(\.id)),
            [
                SkillIdentity(sourceKey: .localPath(root), repositoryRelativePath: "skills/skill-a"),
                SkillIdentity(sourceKey: .localPath(root), repositoryRelativePath: "skills/skill-b"),
            ],
            "Skill Identity =（Skill Source Key，仓内相对路径）"
        )
    }

    func testContentsAggregatesInstallationsAcrossRootsForSameSkill() {
        // 跨 root 发现同一 canonical path（软链接指向仓库内 Skill）→ 1 个 Skill、2 个 Installation（ADR-0001 §3）
        let asFoundRoot = "/var/folders/pagugu-ci/suite-repo"
        let root = "/private/var/folders/pagugu-ci/suite-repo"
        let skills = [
            DiscoveredSkill(
                asFoundPath: asFoundRoot + "/skills/git-commit",
                canonicalPath: root + "/skills/git-commit",
                name: "git-commit",
                repositoryRootPath: root
            ),
            DiscoveredSkill(
                asFoundPath: "~/.claude/skills/git-commit",
                canonicalPath: root + "/skills/git-commit", // 软链接完全解析到同一 canonical path
                name: "git-commit",
                repositoryRootPath: root
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        XCTAssertEqual(contents.sources.count, 1)
        let entry = try! XCTUnwrap(contents.sources.first?.skills.first)
        XCTAssertEqual(entry.installations.count, 2, "2 个 as-found 路径 = 2 个 Installation")
        XCTAssertEqual(
            entry.installations.flatMap(\.hosts).sorted(),
            [.claude],
            "宿主归因按 as-found 路径"
        )
        let linked = entry.installations.first { $0.asFoundPath == "~/.claude/skills/git-commit" }
        XCTAssertEqual(linked?.projectionType, .symlink, "asFound ≠ canonical → 软链接投影")
        let own = entry.installations.first { $0.asFoundPath == asFoundRoot + "/skills/git-commit" }
        XCTAssertEqual(
            own?.projectionType,
            .repositorySelf,
            "/var 与 /private/var 只是系统路径别名，不代表 Skill Installation 是软链接"
        )
    }

    func testContentsSeparatesSameNameDifferentSource() {
        // 同名异源：name 相同但仓库根不同 → 各自成行，来源标识不串行（ADR-0001 §5）
        let repoA = ("~/repo-a" as NSString).expandingTildeInPath
        let repoB = ("~/repo-b" as NSString).expandingTildeInPath
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/repo-a/skills/helper",
                canonicalPath: repoA + "/skills/helper",
                name: "helper",
                repositoryRootPath: repoA
            ),
            DiscoveredSkill(
                asFoundPath: "~/repo-b/skills/helper",
                canonicalPath: repoB + "/skills/helper",
                name: "helper",
                repositoryRootPath: repoB
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        XCTAssertEqual(contents.sources.count, 2, "同名异源 = 2 个来源仓库行")
        XCTAssertEqual(Set(contents.sources.map(\.displayName)), ["repo-a", "repo-b"])
        for source in contents.sources {
            XCTAssertEqual(source.skills.count, 1)
            XCTAssertEqual(source.skills.first?.id.sourceKey, source.id, "子 Skill 来源标识与所在仓库行一致，不串行")
        }
    }

    func testContentsMergesIdenticalCopiesByContentFingerprint() {
        // 内容完全一致（指纹相同）的复制投影聚合为一个只读来源不明条目（#16 修正）
        let claudePath = ("~/.claude/skills/helper" as NSString).expandingTildeInPath
        let codexPath = ("~/.codex/skills/helper" as NSString).expandingTildeInPath
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/.claude/skills/helper",
                canonicalPath: claudePath,
                name: "helper",
                contentFingerprint: "aa11"
            ),
            DiscoveredSkill(
                asFoundPath: "~/.codex/skills/helper",
                canonicalPath: codexPath,
                name: "helper",
                contentFingerprint: "aa11"
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        XCTAssertEqual(contents.unattributedInstallations.count, 1, "指纹一致 → 聚合为一个条目")
        let item = try! XCTUnwrap(contents.unattributedInstallations.first)
        XCTAssertEqual(item.installations.count, 2, "聚合全部 Installation")
        XCTAssertEqual(item.hosts, [.claude, .codex], "宿主槽位按安装事实点亮")
        XCTAssertEqual(
            Set(item.installations.map(\.canonicalPath)),
            [claudePath, codexPath],
            "每个 Installation 保留各自 canonical path"
        )
        XCTAssertTrue(item.installations.allSatisfy { $0.projectionType == .copy })
        XCTAssertEqual(item.id, "sha256:aa11", "呈现组以内容指纹为稳定标识")
    }

    func testContentsDoesNotMergeByNameAlone() {
        // 禁止只按名称合并：同名但内容不同（指纹不同）仍然分开
        let claudePath = ("~/.claude/skills/helper" as NSString).expandingTildeInPath
        let codexPath = ("~/.codex/skills/helper" as NSString).expandingTildeInPath
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/.claude/skills/helper",
                canonicalPath: claudePath,
                name: "helper",
                contentFingerprint: "aa11"
            ),
            DiscoveredSkill(
                asFoundPath: "~/.codex/skills/helper",
                canonicalPath: codexPath,
                name: "helper",
                contentFingerprint: "bb22"
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        XCTAssertEqual(contents.unattributedInstallations.count, 2, "同名不同内容 = 2 个条目")
        XCTAssertEqual(Set(contents.unattributedInstallations.map(\.displayName)), ["helper"])
    }

    func testContentsNeverMergesWhenFingerprintMissing() {
        // fail closed：内容无法完整读取（无指纹）时不自动合并，即使同名同指纹缺失
        let claudePath = ("~/.claude/skills/helper" as NSString).expandingTildeInPath
        let codexPath = ("~/.codex/skills/helper" as NSString).expandingTildeInPath
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/.claude/skills/helper",
                canonicalPath: claudePath,
                name: "helper"
            ),
            DiscoveredSkill(
                asFoundPath: "~/.codex/skills/helper",
                canonicalPath: codexPath,
                name: "helper"
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        XCTAssertEqual(contents.sources.count, 0, "无工作树根不进来源仓库行")
        XCTAssertEqual(contents.unattributedInstallations.count, 2, "无指纹不合并，按安装 Canonical Path 各自单列")
        for item in contents.unattributedInstallations {
            XCTAssertEqual(item.id, item.canonicalPath, "不可合并单例以安装 Canonical Path 为标识")
            XCTAssertEqual(item.installations.count, 1)
            XCTAssertEqual(item.installations.first?.projectionType, .copy, "asFound == canonical 且无工作树 → 复制投影")
        }
    }

    func testContentsKeepsSkillAtWorkTreeRootWithEmptyRelativePath() {
        // SKILL.md 位于仓库根：仓内相对路径为空串，身份仍稳定
        let root = "/Users/dimon/single-skill-repo"
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/.claude/skills/single-skill-repo",
                canonicalPath: root,
                name: "single-skill-repo",
                repositoryRootPath: root
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        XCTAssertEqual(contents.sources.count, 1)
        XCTAssertEqual(
            contents.sources.first?.skills.first?.id,
            SkillIdentity(sourceKey: .localPath(root), repositoryRelativePath: "")
        )
    }

    // MARK: - Discovery Origin 安装产生规则（#18）：纯来源 Skill 保持零 Installation

    func testContentsProducesNoInstallationForProjectRootSkillWithoutHosts() {
        // Project Scan Root 内、无宿主归因的 as-found 路径不产生 Installation（纯来源 Skill）
        let root = "/Users/dimon/suite-repo"
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/Code/suite-repo/skills/skill-a",
                canonicalPath: root + "/skills/skill-a",
                name: "skill-a",
                origin: .projectScanRoot,
                repositoryRootPath: root
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        XCTAssertEqual(contents.sources.count, 1)
        let entry = try! XCTUnwrap(contents.sources.first?.skills.first)
        XCTAssertTrue(entry.installations.isEmpty, "纯来源 Skill 保持零 Installation")
        XCTAssertTrue(entry.hosts.isEmpty, "无安装则宿主槽位全灰")
    }

    func testContentsDoesNotInferCodexHostForProjectCodexDirectory() {
        let root = "/Users/dimon/suite-repo"
        let skills = [
            DiscoveredSkill(
                asFoundPath: root + "/.codex/skills/skill-a",
                canonicalPath: root + "/.codex/skills/skill-a",
                name: "skill-a",
                origin: .projectScanRoot,
                repositoryRootPath: root
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        let entry = try! XCTUnwrap(contents.sources.first?.skills.first)
        XCTAssertTrue(entry.installations.isEmpty, "项目 .codex/skills 的宿主语义仍为 Unknown")
        XCTAssertTrue(entry.hosts.isEmpty, "项目 .codex/skills 不点亮 Codex")
    }

    func testContentsProducesInstallationForProjectRootSkillWithHostAttribution() {
        // Project Scan Root 内的宿主目录（如镜像的 .claude/skills）仍产生 Installation
        let root = "/Users/dimon/suite-repo"
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/Backup/.claude/skills/skill-a",
                canonicalPath: root + "/skills/skill-a",
                name: "skill-a",
                origin: .projectScanRoot,
                repositoryRootPath: root
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        let entry = try! XCTUnwrap(contents.sources.first?.skills.first)
        XCTAssertEqual(entry.installations.count, 1, "带宿主归因的 project 入口产生 Installation")
        XCTAssertEqual(entry.hosts, [.claude])
    }

    func testContentsNeverMergesZeroInstallationRepoLessSkills() {
        // 零安装的纯来源发现永不按指纹合并：身份即自身位置，内容一致不推断同一 Skill
        let installedPath = ("~/.claude/skills/helper" as NSString).expandingTildeInPath
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/Code/work-in-progress/helper",
                canonicalPath: "/Users/dimon/Code/work-in-progress/helper",
                name: "helper",
                origin: .projectScanRoot,
                contentFingerprint: "aa11"
            ),
            DiscoveredSkill(
                asFoundPath: "~/.claude/skills/helper",
                canonicalPath: installedPath,
                name: "helper",
                contentFingerprint: "aa11"
            ),
        ]
        let contents = SkillDirectory.contents(from: ScanResult(outcome: .complete, skills: skills, issues: []))

        XCTAssertEqual(contents.unattributedInstallations.count, 2, "零安装纯来源发现不与安装复制合并")
        let installed = contents.unattributedInstallations.first { !$0.installations.isEmpty }
        let sourceOnly = contents.unattributedInstallations.first { $0.installations.isEmpty }
        XCTAssertNotNil(installed)
        XCTAssertNotNil(sourceOnly)
        XCTAssertEqual(sourceOnly?.id, "/Users/dimon/Code/work-in-progress/helper", "零安装单例以安装 Canonical Path 为标识")
    }

    func testMappingOneInstallationSplitsIdenticalCrossHostPresentationGroup() throws {
        let root = "/projects/repo"
        let target = SkillIdentity(
            sourceKey: .localPath(root),
            repositoryRelativePath: "skills/source"
        )
        let claudePath = "/Users/dimon/.claude/skills/helper"
        let codexPath = "/Users/dimon/.codex/skills/helper"
        let result = ScanResult(
            outcome: .complete,
            skills: [
                DiscoveredSkill(
                    asFoundPath: root + "/skills/source",
                    canonicalPath: root + "/skills/source",
                    name: "source",
                    origin: .projectScanRoot,
                    repositoryRootPath: root
                ),
                DiscoveredSkill(
                    asFoundPath: claudePath,
                    canonicalPath: claudePath,
                    name: "helper",
                    contentFingerprint: "aa11"
                ),
                DiscoveredSkill(
                    asFoundPath: codexPath,
                    canonicalPath: codexPath,
                    name: "helper",
                    contentFingerprint: "aa11"
                ),
            ],
            issues: [],
            candidateSourceRoots: [root]
        )

        let contents = SkillDirectory.contents(
            from: result,
            mappings: [
                claudePath: SourceMappingRecord(
                    skillSourceKey: target.sourceKey.registryValue,
                    repositoryRelativePath: target.repositoryRelativePath
                ),
            ]
        )

        let source = try XCTUnwrap(contents.sources.first?.skills.first)
        XCTAssertEqual(source.installations.map(\.canonicalPath), [claudePath])
        XCTAssertTrue(source.installations.first?.isManuallyMapped == true)
        let remaining = try XCTUnwrap(contents.unattributedInstallations.first)
        XCTAssertEqual(remaining.installations.map(\.canonicalPath), [codexPath])
        XCTAssertEqual(remaining.id, "sha256:aa11", "指纹只保留呈现分组，不成为映射键")
    }

    func testManualMappingCannotOverrideUnattributedSymlink() throws {
        let root = "/projects/repo"
        let target = SkillIdentity(
            sourceKey: .localPath(root),
            repositoryRelativePath: "skills/source"
        )
        let linkedTarget = "/outside/copied-skill"
        let result = ScanResult(
            outcome: .complete,
            skills: [
                DiscoveredSkill(
                    asFoundPath: root + "/skills/source",
                    canonicalPath: root + "/skills/source",
                    name: "source",
                    origin: .projectScanRoot,
                    repositoryRootPath: root
                ),
                DiscoveredSkill(
                    asFoundPath: "/Users/dimon/.claude/skills/linked",
                    canonicalPath: linkedTarget,
                    name: "linked"
                ),
            ],
            issues: [],
            candidateSourceRoots: [root]
        )

        let contents = SkillDirectory.contents(
            from: result,
            mappings: [
                linkedTarget: SourceMappingRecord(
                    skillSourceKey: target.sourceKey.registryValue,
                    repositoryRelativePath: target.repositoryRelativePath
                ),
            ]
        )

        XCTAssertEqual(contents.invalidMappings.first?.validity, .invalid(.installationNotCopy))
        XCTAssertEqual(contents.sources.first?.skills.first?.installations.count, 0)
        XCTAssertEqual(contents.unattributedInstallations.first?.installations.first?.projectionType, .symlink)
    }
}
