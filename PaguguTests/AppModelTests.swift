import XCTest
@testable import Pagugu

// AppModel smoke 测试（ADR-0009 §14 第 6 层：SwiftUI smoke——启动、投影渲染、intent 路由存在）。
// 全部测试用构造注入的临时 Persistence 目录，永不触碰真实 Application Support。
final class AppModelTests: XCTestCase {

    private enum TestWriteFailure: Error {
        case beforeReplace
    }

    private var tmp: URL!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: tmp)
        super.tearDown()
    }

    private func writeSkill(at dir: URL, name: String) throws {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let content = "---\nname: \(name)\ndescription: Test\n---\n"
        try content.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    private func makeWorkTree(at dir: URL) throws {
        try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
    }

    @MainActor
    private func makeModel(personalRoots: [String]) -> AppModel {
        AppModel(
            personalRoots: personalRoots,
            persistence: Persistence(directoryURL: tmp.appendingPathComponent("data"))
        )
    }

    // MARK: - 空 Registry 启动 = 正常态（S1）

    @MainActor
    func testStartWithEmptyRootsProducesEmptyReadModel() async {
        let missing = tmp.appendingPathComponent("nonexistent")
        let model = makeModel(personalRoots: [missing.path])
        XCTAssertFalse(model.registryReady)
        await model.start()

        XCTAssertTrue(model.registryReady)
        XCTAssertTrue(model.readModel.isEmpty)
        XCTAssertTrue(model.readModel.sources.isEmpty)
        XCTAssertTrue(model.readModel.unattributedInstallations.isEmpty)
        XCTAssertTrue(model.readModel.issues.isEmpty)
        switch model.readModel.scanOutcome {
        case .complete: break
        case .partial, .failed: XCTFail("Missing root should be normal empty state")
        }
    }

    // MARK: - 扫描后投影包含发现的 Skill

    @MainActor
    func testStartPublishesDiscoveredSkills() async throws {
        let root = tmp.appendingPathComponent("skills")
        try writeSkill(at: root.appendingPathComponent("my-skill"), name: "my-skill")

        let model = makeModel(personalRoots: [root.path])
        await model.start()

        XCTAssertFalse(model.readModel.isEmpty)
        XCTAssertEqual(model.readModel.unattributedInstallations.count, 1, "无工作树的复制投影单列")
        XCTAssertEqual(model.readModel.unattributedInstallations.first?.displayName, "my-skill")
    }

    // MARK: - Variant F：套件仓库分组为来源仓库行

    @MainActor
    func testStartGroupsWorkTreeSkillsIntoSourceRows() async throws {
        let root = tmp.appendingPathComponent("skills")
        let repo = root.appendingPathComponent("suite-repo")
        try makeWorkTree(at: repo)
        try writeSkill(at: repo.appendingPathComponent("skills/skill-a"), name: "skill-a")
        try writeSkill(at: repo.appendingPathComponent("skills/skill-b"), name: "skill-b")
        try writeSkill(at: root.appendingPathComponent("plain-copy"), name: "plain-copy")

        let model = makeModel(personalRoots: [root.path])
        await model.start()

        XCTAssertEqual(model.readModel.sources.count, 1)
        let source = try XCTUnwrap(model.readModel.sources.first)
        XCTAssertEqual(source.displayName, "suite-repo")
        XCTAssertEqual(source.skills.count, 2, "仓库行下挂 2 个子 Skill")
        XCTAssertEqual(Set(source.skills.map(\.displayName)), ["skill-a", "skill-b"])
        XCTAssertEqual(model.readModel.unattributedInstallations.count, 1, "无仓库复制投影独立成行")
    }

    // MARK: - 目录节点投影：默认展开，收起隐藏子 Skill 行

    @MainActor
    func testDirectoryNodesReflectCollapseState() async throws {
        let root = tmp.appendingPathComponent("skills")
        let repo = root.appendingPathComponent("suite-repo")
        try makeWorkTree(at: repo)
        try writeSkill(at: repo.appendingPathComponent("skill-a"), name: "skill-a")

        let model = makeModel(personalRoots: [root.path])
        await model.start()
        let source = try XCTUnwrap(model.readModel.sources.first)
        let skill = try XCTUnwrap(source.skills.first)

        let expanded = model.readModel.directoryNodes(collapsedSources: [])
        XCTAssertEqual(expanded, [.source(source.id), .skill(skill.id)], "默认展开：仓库行 + 子 Skill 行")

        let collapsed = model.readModel.directoryNodes(collapsedSources: [source.id])
        XCTAssertEqual(collapsed, [.source(source.id)], "收起后只剩仓库行")
    }

    func testDirectoryStatusPhraseTable() throws {
        let cases: [(CheckoutGitState, String)] = [
            (.inspectionFailed, "检查失败"),
            (.noRemote, "仅本地"),
            (.detached, "HEAD 已分离"),
            (.noUpstream, "未配置上游"),
            (.upstreamMismatch, "上游来源不一致"),
            (.siblingConflict, "兄弟检出冲突"),
            (.checkUnknown, "尚未检查"),
            (.dirty, "有未提交改动"),
            (.diverged, "本地与上游已分叉"),
            (.aheadOnly, "本地领先"),
            (.updateAvailable, "可更新"),
            (.upToDate, "已是最新"),
        ]

        for (state, expected) in cases {
            let readModel = makeDirectoryReadModel([(name: "source", states: [state])])
            let source = try XCTUnwrap(readModel.sources.first)
            XCTAssertEqual(readModel.directoryStatusPhrase(for: source.id), expected, state.rawValue)
        }

        let readModel = makeDirectoryReadModel([
            (
                name: "mixed",
                states: [.noRemote, .upToDate, .checkUnknown, .updateAvailable, .dirty, .dirty]
            ),
        ])
        let source = try XCTUnwrap(readModel.sources.first)
        XCTAssertEqual(
            readModel.directoryStatusPhrase(for: source.id),
            "2 个有未提交改动 · 1 个可更新 · 1 个尚未检查 · 1 个已是最新 · 1 个仅本地"
        )
        XCTAssertEqual(readModel.checkoutCards(for: source.id).count, 6, "短语计数与详情卡片一一对应")
    }

    func testDirectoryNodesUseFiveQuietPrioritiesAndRefreshWithStates() {
        let cases: [(
            rows: [(name: String, states: [CheckoutGitState])],
            expectedNames: [String]
        )] = [
            (
                rows: [
                    ("local", [.noRemote]),
                    ("settled", [.upToDate]),
                    ("unknown", [.checkUnknown]),
                    ("update", [.updateAvailable]),
                    ("dirty", [.dirty]),
                ],
                expectedNames: ["dirty", "update", "unknown", "settled", "local"]
            ),
            (
                rows: [
                    ("diverged", [.diverged]),
                    ("detached", [.detached]),
                    ("dirty", [.dirty]),
                    ("inspection", [.inspectionFailed]),
                    ("mismatch", [.upstreamMismatch]),
                    ("no-upstream", [.noUpstream]),
                    ("sibling", [.siblingConflict]),
                ],
                expectedNames: [
                    "inspection", "detached", "no-upstream", "mismatch", "sibling", "dirty", "diverged",
                ]
            ),
            (
                rows: [
                    ("mixed-attention", [.upToDate, .dirty]),
                    ("mixed-update", [.noRemote, .updateAvailable]),
                    ("ahead", [.aheadOnly]),
                    ("current", [.upToDate]),
                ],
                expectedNames: ["mixed-attention", "mixed-update", "ahead", "current"]
            ),
            (
                rows: [
                    ("a", [.upToDate]),
                    ("b", [.updateAvailable]),
                ],
                expectedNames: ["b", "a"]
            ),
            (
                rows: [
                    ("a", [.dirty]),
                    ("b", [.updateAvailable]),
                ],
                expectedNames: ["a", "b"]
            ),
        ]

        for testCase in cases {
            let readModel = makeDirectoryReadModel(testCase.rows)
            let names = directoryRootNames(in: readModel)
            XCTAssertEqual(names, testCase.expectedNames)
        }

        let mixedRoots = makeDirectoryReadModel(
            [
                ("update", [.updateAvailable]),
                ("dirty", [.dirty]),
                ("missing-cards", []),
            ],
            unattributedNames: ["copy"]
        )
        XCTAssertEqual(
            directoryRootNames(in: mixedRoots),
            ["dirty", "missing-cards", "copy", "update"]
        )
    }

    // MARK: - UI Intents：收起/展开与 rescan 路由存在

    @MainActor
    func testToggleSourceCollapsedIntent() async throws {
        let root = tmp.appendingPathComponent("skills")
        let repo = root.appendingPathComponent("suite-repo")
        try makeWorkTree(at: repo)
        try writeSkill(at: repo.appendingPathComponent("skill-a"), name: "skill-a")

        let model = makeModel(personalRoots: [root.path])
        await model.start()
        let source = try XCTUnwrap(model.readModel.sources.first)

        XCTAssertTrue(model.collapsedSources.isEmpty, "默认全部展开")
        model.toggleSourceCollapsed(source.id)
        XCTAssertEqual(model.collapsedSources, [source.id])
        model.toggleSourceCollapsed(source.id)
        XCTAssertTrue(model.collapsedSources.isEmpty)
    }

    @MainActor
    func testRescanRefreshesReadModel() async throws {
        let root = tmp.appendingPathComponent("skills")
        let model = makeModel(personalRoots: [root.path])
        await model.start()
        XCTAssertTrue(model.readModel.isEmpty)

        // 添加 Skill 后 rescan
        try writeSkill(at: root.appendingPathComponent("new-skill"), name: "new-skill")
        await model.rescan()

        XCTAssertFalse(model.readModel.isEmpty)
        XCTAssertEqual(model.readModel.unattributedInstallations.count, 1)
    }

    // MARK: - SKILL.md 原文 intent（只读展示）

    @MainActor
    func testSkillMarkdownIntentReturnsFileContent() async throws {
        let root = tmp.appendingPathComponent("skills")
        let skillDir = root.appendingPathComponent("my-skill")
        try writeSkill(at: skillDir, name: "my-skill")

        let model = makeModel(personalRoots: [root.path])
        await model.start()
        let item = try XCTUnwrap(model.readModel.unattributedInstallations.first)

        let markdown = model.skillMarkdown(canonicalPath: item.canonicalPath)
        XCTAssertEqual(markdown, "---\nname: my-skill\ndescription: Test\n---\n")
        XCTAssertNil(model.skillMarkdown(canonicalPath: tmp.appendingPathComponent("missing").path))
    }

    // MARK: - 跨 Agent Host 复制安装聚合（#16 修正：内容完全一致 → 一个来源不明条目）

    /// 写入含多文件的复制 Skill（SKILL.md + scripts/run.sh），frontmatter name 与目录名解耦。
    private func writeCopySkill(at dir: URL, frontmatterName: String, runScript: String = "echo hello\n") throws {
        let scripts = dir.appendingPathComponent("scripts")
        try fm.createDirectory(at: scripts, withIntermediateDirectories: true)
        let md = "---\nname: \(frontmatterName)\ndescription: Copy test\n---\n# Body\n"
        try md.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try runScript.write(to: scripts.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func testIdenticalCopiesAcrossHostsMergeIntoOneUnattributedEntry() async throws {
        // 同一个实际 Skill 复制安装到 Claude 与 Codex 两个 Personal Skill Root（内容完全一致）
        let claudeSkill = tmp.appendingPathComponent(".claude/skills/helper")
        let codexSkill = tmp.appendingPathComponent(".codex/skills/helper")
        try writeCopySkill(at: claudeSkill, frontmatterName: "helper")
        try writeCopySkill(at: codexSkill, frontmatterName: "helper")

        let model = makeModel(personalRoots: [
            tmp.appendingPathComponent(".claude/skills").path,
            tmp.appendingPathComponent(".codex/skills").path,
        ])
        await model.start()

        XCTAssertEqual(
            model.readModel.unattributedInstallations.count, 1,
            "内容完全一致的复制安装必须聚合为一个来源不明条目"
        )
        let item = try XCTUnwrap(model.readModel.unattributedInstallations.first)
        XCTAssertEqual(item.displayName, "helper")
        XCTAssertEqual(item.installations.count, 2, "聚合全部 Skill Installation")
        XCTAssertEqual(item.hosts, [.claude, .codex], "两个 Agent Host 槽位都点亮")
        XCTAssertEqual(
            Set(item.installations.map(\.asFoundPath)),
            [claudeSkill.path, codexSkill.path],
            "保留每个 Installation 的 as-found 路径"
        )
        XCTAssertEqual(
            Set(item.installations.map(\.canonicalPath)).count, 2,
            "保留每个 Installation 各自的 canonical path"
        )
    }

    @MainActor
    func testSameNameDifferentContentCopiesStaySeparate() async throws {
        // 同名但内容不同：禁止只按名称合并
        let claudeSkill = tmp.appendingPathComponent(".claude/skills/helper")
        let codexSkill = tmp.appendingPathComponent(".codex/skills/helper")
        try writeCopySkill(at: claudeSkill, frontmatterName: "helper", runScript: "echo a\n")
        try writeCopySkill(at: codexSkill, frontmatterName: "helper", runScript: "echo b\n")

        let model = makeModel(personalRoots: [
            tmp.appendingPathComponent(".claude/skills").path,
            tmp.appendingPathComponent(".codex/skills").path,
        ])
        await model.start()

        XCTAssertEqual(model.readModel.unattributedInstallations.count, 2, "同名不同内容 = 2 个条目")
        XCTAssertEqual(Set(model.readModel.unattributedInstallations.map(\.displayName)), ["helper"])
    }

    @MainActor
    func testUnreadableCopyContentFailsClosedWithoutMerging() async throws {
        // 内容无法完整读取：fail closed——不自动合并、记录 Scan Issue
        let claudeSkill = tmp.appendingPathComponent(".claude/skills/helper")
        let codexSkill = tmp.appendingPathComponent(".codex/skills/helper")
        try writeCopySkill(at: claudeSkill, frontmatterName: "helper")
        try writeCopySkill(at: codexSkill, frontmatterName: "helper")
        let secret = codexSkill.appendingPathComponent("scripts/run.sh")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: secret.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secret.path) }

        let model = makeModel(personalRoots: [
            tmp.appendingPathComponent(".claude/skills").path,
            tmp.appendingPathComponent(".codex/skills").path,
        ])
        await model.start()

        XCTAssertEqual(model.readModel.unattributedInstallations.count, 2, "读取不完整不合并")
        XCTAssertTrue(
            model.readModel.issues.contains { $0.path == codexSkill.path },
            "记录可恢复 Scan Issue"
        )
        switch model.readModel.scanOutcome {
        case .partial: break
        case .complete, .failed: XCTFail("读取不完整应标记 partial")
        }
    }

    // MARK: - Registry 启动门（#17）

    @MainActor
    func testCorruptRegistryBlocksDiscoveryUntilConfirmedReset() async throws {
        let root = tmp.appendingPathComponent("skills")
        try writeSkill(at: root.appendingPathComponent("blocked"), name: "blocked")
        let dataDirectory = tmp.appendingPathComponent("data")
        try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: dataDirectory.appendingPathComponent("registry.json"))
        let persistence = Persistence(directoryURL: dataDirectory)
        let model = AppModel(personalRoots: [root.path], persistence: persistence)
        XCTAssertFalse(model.registryReady)

        await model.start()

        XCTAssertFalse(model.registryReady)
        let recovery = try XCTUnwrap(model.registryRecovery)
        XCTAssertEqual(recovery.kind, .corrupt)
        XCTAssertTrue(recovery.evidenceURL.lastPathComponent.hasPrefix("registry.corrupt-"))
        XCTAssertTrue(model.readModel.isEmpty)

        await model.rescan()
        XCTAssertTrue(model.readModel.isEmpty)

        await model.resetRegistry(confirmed: true)
        XCTAssertTrue(model.registryReady)
        XCTAssertNil(model.registryRecovery)
        XCTAssertEqual(model.readModel.unattributedInstallations.first?.displayName, "blocked")
    }

    @MainActor
    func testFutureRegistryPublishesUpgradeRecoveryWithoutOverwritingFile() async throws {
        let dataDirectory = tmp.appendingPathComponent("data")
        try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let registryURL = dataDirectory.appendingPathComponent("registry.json")
        let futureData = Data(
            #"{"schemaVersion":2,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{}}"#.utf8
        )
        try futureData.write(to: registryURL)
        let model = AppModel(
            personalRoots: [],
            persistence: Persistence(directoryURL: dataDirectory)
        )

        await model.start()

        XCTAssertEqual(model.registryRecovery?.kind, .unknownFutureVersion)
        XCTAssertEqual(model.registryRecovery?.evidenceURL, registryURL)
        XCTAssertEqual(try Data(contentsOf: registryURL), futureData)
    }

    // MARK: - Project Scan Root 管理（#18）

    @MainActor
    func testAddAndRemoveProjectScanRootRefreshesPureSourceSkill() async throws {
        let root = tmp.appendingPathComponent("project-root")
        try writeSkill(at: root.appendingPathComponent("source-only"), name: "source-only")
        let model = makeModel(personalRoots: [])
        await model.start()

        await model.addProjectScanRoot(root)

        XCTAssertNil(model.projectScanRootError)
        XCTAssertEqual(model.readModel.projectScanRoots.map(\.asFoundPath), [root.path])
        XCTAssertTrue(model.readModel.sources.isEmpty, "无工作树不进来源仓库行")
        XCTAssertEqual(model.readModel.unattributedInstallations.map(\.displayName), ["source-only"])
        XCTAssertTrue(
            model.readModel.unattributedInstallations.first?.installations.isEmpty == true,
            "纯来源 Skill 保持零 Installation"
        )

        await model.removeProjectScanRoot(canonicalPath: root.path)

        XCTAssertTrue(model.readModel.projectScanRoots.isEmpty)
        XCTAssertTrue(model.readModel.sources.isEmpty)
        XCTAssertTrue(model.readModel.unattributedInstallations.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: root.path))
    }

    @MainActor
    func testProjectScanRootWriteFailurePublishesRecoveryWithoutMemoryFallback() async throws {
        let root = tmp.appendingPathComponent("project-root")
        try writeSkill(at: root.appendingPathComponent("hidden"), name: "hidden")
        let persistence = Persistence(directoryURL: tmp.appendingPathComponent("data")) {
            throw TestWriteFailure.beforeReplace
        }
        let model = AppModel(personalRoots: [], persistence: persistence)
        await model.start()

        await model.addProjectScanRoot(root)

        XCTAssertEqual(model.projectScanRootError?.reason, "Registry 写入失败。请检查磁盘空间与目录权限后重试。")
        XCTAssertTrue(model.readModel.projectScanRoots.isEmpty)
        XCTAssertTrue(model.readModel.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: tmp.appendingPathComponent("data/registry.json").path))
    }

    @MainActor
    func testLoadedForbiddenProjectRootIsNotScanned() async throws {
        let container = tmp.appendingPathComponent("project-container")
        let personalRoot = container.appendingPathComponent("personal/skills")
        try fm.createDirectory(at: personalRoot, withIntermediateDirectories: true)
        try writeSkill(at: container.appendingPathComponent("source-only"), name: "must-not-scan")
        let dataDirectory = tmp.appendingPathComponent("data")
        let persistence = Persistence(directoryURL: dataDirectory)
        _ = await persistence.loadRegistry()
        try await persistence.saveRegistry(RegistryDocument(
            schemaVersion: RegistryDocument.currentSchemaVersion,
            projectScanRoots: [
                ProjectScanRootRecord(canonicalPath: container.path, asFoundPath: container.path),
            ],
            sourceMappings: [:],
            checkoutObservations: [:]
        ))
        let model = AppModel(personalRoots: [personalRoot.path], persistence: persistence)

        await model.start()

        XCTAssertTrue(model.readModel.sources.isEmpty)
        XCTAssertTrue(model.readModel.unattributedInstallations.isEmpty)
        XCTAssertFalse(try XCTUnwrap(model.readModel.projectScanRoots.first).isAvailable)
    }

    @MainActor
    func testUnavailableProjectRootKeepsScanIncomplete() async throws {
        let personalRoot = tmp.appendingPathComponent("personal/skills")
        try fm.createDirectory(at: personalRoot, withIntermediateDirectories: true)
        let missingProjectRoot = tmp.appendingPathComponent("missing-project-root")
        let dataDirectory = tmp.appendingPathComponent("data")
        let persistence = Persistence(directoryURL: dataDirectory)
        _ = await persistence.loadRegistry()
        try await persistence.saveRegistry(RegistryDocument(
            schemaVersion: RegistryDocument.currentSchemaVersion,
            projectScanRoots: [
                ProjectScanRootRecord(
                    canonicalPath: missingProjectRoot.path,
                    asFoundPath: missingProjectRoot.path
                ),
            ],
            sourceMappings: [:],
            checkoutObservations: [:]
        ))
        let model = AppModel(personalRoots: [personalRoot.path], persistence: persistence)

        await model.start()

        XCTAssertEqual(model.readModel.issues.map(\.path), [missingProjectRoot.path])
        if case .partial = model.readModel.scanOutcome {
            // 预期结果
        } else {
            XCTFail("合法但不可用的 Project Scan Root 必须让扫描保持不完整")
        }
    }

    @MainActor
    func testResetWriteFailurePublishesCurrentRecovery() async throws {
        let dataDirectory = tmp.appendingPathComponent("data")
        try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: dataDirectory.appendingPathComponent("registry.json"))
        let persistence = Persistence(directoryURL: dataDirectory) {
            throw TestWriteFailure.beforeReplace
        }
        let model = AppModel(personalRoots: [], persistence: persistence)
        await model.start()
        XCTAssertEqual(model.registryRecovery?.kind, .corrupt)

        await model.resetRegistry(confirmed: true)

        XCTAssertEqual(model.registryRecovery?.kind, .writeFailed)
        XCTAssertFalse(model.registryReady)
        XCTAssertTrue(model.readModel.isEmpty)
    }

    // MARK: - Git Fact 与逐检出卡片（#19）

    @MainActor
    func testTwoCheckoutsOfSameRemoteStaySeparateAndUnobservedIsCheckUnknown() async throws {
        let repoA = tmp.appendingPathComponent("repo-a")
        let repoB = tmp.appendingPathComponent("repo-b")
        try makeWorkTree(at: repoA)
        try makeWorkTree(at: repoB)
        try writeSkill(at: repoA.appendingPathComponent("skills/helper"), name: "helper")
        try writeSkill(at: repoB.appendingPathComponent("skills/helper"), name: "helper")
        let remoteURL = "https://example.com/team/skills.git"
        let facts = [
            repoA.path: checkoutFacts(path: repoA.path, remoteURL: remoteURL),
            repoB.path: checkoutFacts(
                path: repoB.path,
                remoteURL: remoteURL,
                head: .detached(sha: "bbbb")
            ),
        ]
        let model = AppModel(
            personalRoots: [repoA.path, repoB.path],
            persistence: Persistence(directoryURL: tmp.appendingPathComponent("data")),
            gitInspector: FakeGitInspector(factsByPath: facts)
        )

        await model.start()

        let source = try XCTUnwrap(model.readModel.sources.first)
        XCTAssertEqual(model.readModel.sources.count, 1, "同一规范化 remote = 一个 Skill Source")
        XCTAssertEqual(source.id, .remoteURL("example.com/team/skills"))
        XCTAssertEqual(Set(source.checkouts.map(\.canonicalPath)), [repoA.path, repoB.path])
        XCTAssertEqual(source.skills.count, 1, "同一 Skill Identity 不因多检出重复")
        let cards = model.readModel.checkoutCards(for: source.id)
        XCTAssertEqual(Set(cards.map(\.id)), [repoA.path, repoB.path])
        XCTAssertEqual(cards.first { $0.id == repoA.path }?.state, .checkUnknown)
        XCTAssertEqual(cards.first { $0.id == repoB.path }?.state, .detached)
        XCTAssertEqual(cards.first { $0.id == repoA.path }?.facts.originRemoteURL, remoteURL)
    }

    private func checkoutFacts(
        path: String,
        remoteURL: String,
        head: GitHead = .branch(name: "main", sha: "aaaa")
    ) -> CheckoutGitFacts {
        CheckoutGitFacts(
            checkoutPath: path,
            gitCommonDirectory: path + "/.git",
            head: head,
            originRemoteURL: remoteURL,
            upstream: head.branchName.map {
                GitUpstream(ref: "origin/\($0)", remoteName: "origin", remoteURL: remoteURL)
            },
            dirty: .clean,
            relativePosition: .unknown,
            worktrees: [GitWorktree(path: path, branch: head.branchName)],
            siblingBranchConflict: false,
            inspectionFailure: nil
        )
    }

    private func makeDirectoryReadModel(
        _ rows: [(name: String, states: [CheckoutGitState])],
        unattributedNames: [String] = []
    ) -> SkillReadModel {
        let sources = rows.map { row in
            let key = SkillSourceKey.remoteURL("example.com/\(row.name)")
            return SkillSourceItem(
                id: key,
                displayName: row.name,
                skills: [],
                checkouts: row.states.indices.map {
                    SkillSourceCheckout(canonicalPath: "/\(row.name)/\($0)")
                }
            )
        }
        let cards = Dictionary(uniqueKeysWithValues: zip(sources, rows).map { source, row in
            (
                source.id,
                row.states.enumerated().map { index, state in
                    CheckoutCardReadModel(
                        facts: checkoutFacts(
                            path: "/\(row.name)/\(index)",
                            remoteURL: "https://example.com/\(row.name).git"
                        ),
                        state: state
                    )
                }
            )
        })
        return SkillReadModel(
            sources: sources,
            unattributedInstallations: unattributedNames.map {
                UnattributedInstallationItem(
                    id: $0,
                    displayName: $0,
                    canonicalPath: "/\($0)",
                    installations: []
                )
            },
            issues: [],
            scanOutcome: .complete,
            checkoutCardsBySource: cards
        )
    }

    private func directoryRootNames(in readModel: SkillReadModel) -> [String] {
        readModel.directoryNodes(collapsedSources: []).compactMap { node in
            switch node {
            case .source(let key):
                return readModel.sourceItem(for: key)?.displayName
            case .unattributedInstallation(let id):
                return readModel.unattributedItem(for: id)?.displayName
            case .skill:
                return nil
            }
        }
    }

    private struct FakeGitInspector: GitInspecting {
        let factsByPath: [String: CheckoutGitFacts]

        func inspectCheckout(at checkoutPath: String, scope: GitInspectionScope) async -> CheckoutGitFacts {
            factsByPath[checkoutPath] ?? CheckoutGitFacts(
                checkoutPath: checkoutPath,
                gitCommonDirectory: nil,
                head: nil,
                originRemoteURL: nil,
                upstream: nil,
                dirty: .clean,
                relativePosition: .unknown,
                worktrees: [],
                siblingBranchConflict: false,
                inspectionFailure: .notAWorkTree
            )
        }
    }
}
