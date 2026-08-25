import XCTest
@testable import Pagugu

// Discovery scratch 测试：临时目录 + 软链接 + 深度保险 + Scan Issue 记录。
// 沿用 ADR-0009 §14 第 2 层：文件系统 scratch 测试。
final class DiscoveryTests: XCTestCase {

    // MARK: - helpers

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

    private func writeSkill(at dir: URL, name: String = "test-skill", file: String = #file, line: UInt = #line) throws {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let content = "---\nname: \(name)\ndescription: A test skill\n---\n# \(name)\n"
        try content.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    // MARK: - root 不存在 = 正常空态

    func testMissingRootProducesNoSkillsAndNoError() {
        let missing = tmp.appendingPathComponent("nonexistent")
        let result = Discovery.scanPersonalRoots([missing.path])
        XCTAssertTrue(result.skills.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
        switch result.outcome {
        case .complete: break
        case .partial, .failed: XCTFail("Missing root should not affect completeness")
        }
    }

    // MARK: - 发现有效 SKILL.md

    func testDiscoverSkillInPersonalRoot() throws {
        let root = tmp.appendingPathComponent("skills")
        let skillDir = root.appendingPathComponent("my-skill")
        try writeSkill(at: skillDir, name: "my-skill")

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.count, 1)
        XCTAssertEqual(result.skills.first?.name, "my-skill", "frontmatter name 即展示名")
    }

    func testDiscoveredSkillCarriesNearestRepositoryLocation() throws {
        let repository = tmp.appendingPathComponent("repository")
        try fm.createDirectory(at: repository, withIntermediateDirectories: true)
        try "gitdir: /tmp/worktree-git\n".write(
            to: repository.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        let skill = repository.appendingPathComponent("skills/example")
        try writeSkill(at: skill)

        let result = Discovery.scanProjectRoot(repository.appendingPathComponent("skills").path)

        XCTAssertEqual(result.skills.first?.repositoryRootPath, repository.path)
        XCTAssertEqual(result.skills.first?.canonicalPath, skill.path)
        XCTAssertEqual(result.skills.first?.name, "test-skill")
        XCTAssertEqual(result.candidateSourceRoots, [repository.path])
    }

    // MARK: - 软链接解析 + 单 root 内 Canonical Path 防环

    func testSymlinkWithinSameRootDeduplicates() throws {
        let root = tmp.appendingPathComponent("skills")
        let real = root.appendingPathComponent("real-skill")
        try writeSkill(at: real, name: "real")

        // symlink within the same root pointing to a sibling skill
        let link = root.appendingPathComponent("link-skill")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.count, 1, "same-root symlink should dedup by canonical path")
        XCTAssertEqual(result.skills.first?.canonicalPath, real.path)
    }

    func testSymlinkAcrossRootsProducesSeparateInstallations() throws {
        // 跨 root 不内嵌去重（ADR-0001 §3：Identity 层聚合）
        let root = tmp.appendingPathComponent("skills")
        let real = root.appendingPathComponent("real-skill")
        try writeSkill(at: real, name: "real")

        let root2 = tmp.appendingPathComponent("skills2")
        let link = root2.appendingPathComponent("link-skill")
        try fm.createDirectory(at: root2, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let result = Discovery.scanPersonalRoots([root.path, root2.path])
        XCTAssertEqual(result.skills.count, 2, "cross-root symlink should produce 2 installations for Identity aggregation")
        XCTAssertEqual(Set(result.skills.map(\.canonicalPath)), [real.path])
    }

    func testDirectorySymlinkCycleStopsWithoutIssue() throws {
        let root = tmp.appendingPathComponent("skills")
        let nested = root.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: nested.appendingPathComponent("back-to-root"),
            withDestinationURL: root
        )

        let result = Discovery.scanProjectRoot(root.path)

        XCTAssertTrue(result.skills.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
        if case .complete = result.outcome {
            // 预期结果
        } else {
            XCTFail("目录软链接环应安全结束")
        }
    }

    // MARK: - 不可解析 SKILL.md = Scan Issue

    func testUnparseableSkillMDRecordsScanIssue() throws {
        let root = tmp.appendingPathComponent("skills")
        let bad = root.appendingPathComponent("bad-skill")
        try fm.createDirectory(at: bad, withIntermediateDirectories: true)
        try "not yaml at all {{{".write(
            to: bad.appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertTrue(result.skills.isEmpty, "unparseable SKILL.md should not be a Skill")
        XCTAssertFalse(result.issues.isEmpty, "should record Scan Issue")
        XCTAssertEqual(result.issues.first?.path, bad.path)
    }

    // MARK: - 无 SKILL.md 的目录不被发现

    func testDirectoryWithoutSkillMDIsIgnored() throws {
        let root = tmp.appendingPathComponent("skills")
        let noSkill = root.appendingPathComponent("not-a-skill")
        try fm.createDirectory(at: noSkill, withIntermediateDirectories: true)
        try "just text".write(
            to: noSkill.appendingPathComponent("README.md"),
            atomically: true, encoding: .utf8
        )

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertTrue(result.skills.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
    }

    // MARK: - Git 工作树根检测（ADR-0001 §2/§4：工作树内 = 可归因 Skill Source；之外 = 复制投影）

    private func makeWorkTree(at dir: URL, gitIsFile: Bool = false) throws {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if gitIsFile {
            // 链接 worktree / submodule 形式：.git 是指向 gitdir 的文件
            try "gitdir: /elsewhere/repo.git".write(
                to: dir.appendingPathComponent(".git"),
                atomically: true, encoding: .utf8
            )
        } else {
            try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        }
    }

    func testSkillInsideWorkTreeRecordsRepositoryRoot() throws {
        let root = tmp.appendingPathComponent("skills")
        let repo = root.appendingPathComponent("suite-repo")
        try makeWorkTree(at: repo)
        try writeSkill(at: repo.appendingPathComponent("skills/skill-a"), name: "skill-a")
        try writeSkill(at: repo.appendingPathComponent("skills/skill-b"), name: "skill-b")

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.count, 2)
        let expectedRoot = Discovery.resolveCanonical(repo.path)
        for skill in result.skills {
            XCTAssertEqual(skill.repositoryRootPath, expectedRoot, "工作树内 Skill 应记录仓库根 canonical 路径")
        }
    }

    func testSkillAtWorkTreeRootRecordsItselfAsRepositoryRoot() throws {
        let root = tmp.appendingPathComponent("skills")
        let repo = root.appendingPathComponent("single-skill-repo")
        try makeWorkTree(at: repo)
        try writeSkill(at: repo, name: "root-skill")

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.count, 1)
        XCTAssertEqual(result.skills.first?.repositoryRootPath, Discovery.resolveCanonical(repo.path))
    }

    func testGitFileAlsoMarksWorkTreeRoot() throws {
        let root = tmp.appendingPathComponent("skills")
        let worktree = root.appendingPathComponent("linked-worktree")
        try makeWorkTree(at: worktree, gitIsFile: true)
        try writeSkill(at: worktree.appendingPathComponent("skill-a"), name: "skill-a")

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.count, 1)
        XCTAssertEqual(
            result.skills.first?.repositoryRootPath,
            Discovery.resolveCanonical(worktree.path),
            ".git 文件（链接 worktree）同样是工作树根"
        )
    }

    func testNestedWorkTreeUsesInnermostRoot() throws {
        let root = tmp.appendingPathComponent("skills")
        let outer = root.appendingPathComponent("outer-repo")
        try makeWorkTree(at: outer)
        let inner = outer.appendingPathComponent("packages/inner-repo")
        try makeWorkTree(at: inner)
        try writeSkill(at: inner.appendingPathComponent("skill-a"), name: "skill-a")

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.count, 1)
        XCTAssertEqual(
            result.skills.first?.repositoryRootPath,
            Discovery.resolveCanonical(inner.path),
            "嵌套工作树取最内层根"
        )
    }

    func testSkillOutsideWorkTreeHasNoRepositoryRoot() throws {
        let root = tmp.appendingPathComponent("skills")
        try writeSkill(at: root.appendingPathComponent("plain-copy"), name: "plain-copy")

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.count, 1)
        XCTAssertNil(result.skills.first?.repositoryRootPath, "不在任何工作树内 = 复制投影，无仓库根")
    }

    func testScanDoesNotDescendIntoDotGit() throws {
        let root = tmp.appendingPathComponent("skills")
        let repo = root.appendingPathComponent("suite-repo")
        try makeWorkTree(at: repo)
        // .git 内部出现 SKILL.md 不得被发现为 Skill
        try writeSkill(at: repo.appendingPathComponent(".git/hooks/demo-skill"), name: "ghost")
        try writeSkill(at: repo.appendingPathComponent("skill-a"), name: "skill-a")

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.count, 1, ".git 内部不递归")
        XCTAssertEqual(result.skills.first?.name, "skill-a")
    }

    // MARK: - 展示名来自 frontmatter name（不是安装目录 basename）

    func testSkillNameComesFromFrontmatterNotDirectoryName() throws {
        let root = tmp.appendingPathComponent("skills")
        let dir = root.appendingPathComponent("renamed-dir")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let content = "---\nname: frontmatter-name\ndescription: Test\n---\n"
        try content.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.first?.name, "frontmatter-name", "展示元数据使用 frontmatter name，不冒充目录名")
    }

    // MARK: - 内容指纹（复制投影聚合的事实基础；fail closed）

    private func writeCopy(at dir: URL, runScript: String = "echo hello\n") throws {
        let scripts = dir.appendingPathComponent("scripts")
        try fm.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "---\nname: copy\ndescription: Test\n---\n# Body\n".write(
            to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        try runScript.write(to: scripts.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)
    }

    func testContentFingerprintDeterministicAndByteSensitive() throws {
        let a = tmp.appendingPathComponent("a")
        let b = tmp.appendingPathComponent("b")
        let c = tmp.appendingPathComponent("c")
        try writeCopy(at: a)
        try writeCopy(at: b)
        try writeCopy(at: c, runScript: "echo bye\n")

        let fa = Discovery.contentFingerprint(ofSkillAtCanonicalPath: a.path)
        let fb = Discovery.contentFingerprint(ofSkillAtCanonicalPath: b.path)
        let fc = Discovery.contentFingerprint(ofSkillAtCanonicalPath: c.path)
        XCTAssertNotNil(fa)
        XCTAssertEqual(fa, fb, "完整内容一致 → 指纹相同")
        XCTAssertNotEqual(fa, fc, "任一文件字节不同 → 指纹不同")
    }

    func testContentFingerprintCoversRelativePathsNotOnlyBytes() throws {
        let a = tmp.appendingPathComponent("a")
        let b = tmp.appendingPathComponent("b")
        try writeCopy(at: a)
        try writeCopy(at: b)
        // 同样字节移到不同相对路径 → 指纹必须不同
        try fm.moveItem(
            at: b.appendingPathComponent("scripts/run.sh"),
            to: b.appendingPathComponent("scripts/run2.sh")
        )

        let fa = Discovery.contentFingerprint(ofSkillAtCanonicalPath: a.path)
        let fb = Discovery.contentFingerprint(ofSkillAtCanonicalPath: b.path)
        XCTAssertNotEqual(fa, fb, "相对路径参与指纹")
    }

    func testContentFingerprintNeverFollowsSymlinks() throws {
        let outside = tmp.appendingPathComponent("outside.txt")
        try "outside-bytes".write(to: outside, atomically: true, encoding: .utf8)

        // copy A：link.sh 是指向 Skill 目录外的软链接
        let a = tmp.appendingPathComponent("a")
        try writeCopy(at: a)
        try fm.createSymbolicLink(
            at: a.appendingPathComponent("scripts/link.sh"),
            withDestinationURL: outside
        )
        // copy B：link.sh 是内容相同的常规文件
        let b = tmp.appendingPathComponent("b")
        try writeCopy(at: b)
        try "outside-bytes".write(
            to: b.appendingPathComponent("scripts/link.sh"), atomically: true, encoding: .utf8
        )
        // copy C：与 A 相同的软链接
        let c = tmp.appendingPathComponent("c")
        try writeCopy(at: c)
        try fm.createSymbolicLink(
            at: c.appendingPathComponent("scripts/link.sh"),
            withDestinationURL: outside
        )

        let fa = Discovery.contentFingerprint(ofSkillAtCanonicalPath: a.path)
        let fb = Discovery.contentFingerprint(ofSkillAtCanonicalPath: b.path)
        let fc = Discovery.contentFingerprint(ofSkillAtCanonicalPath: c.path)
        XCTAssertNotEqual(fa, fb, "软链接只记录链接目标字符串，不跟随读取目录外内容")
        XCTAssertEqual(fa, fc, "相同软链接结构 → 指纹相同")
    }

    func testContentFingerprintDoesNotDescendIntoSymlinkedDirectories() throws {
        // 指向 Skill 目录外的目录软链接：不跟随、不枚举其内容
        let extDir = tmp.appendingPathComponent("external-dir")
        try fm.createDirectory(at: extDir, withIntermediateDirectories: true)
        try "inner".write(to: extDir.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)

        // copy A：extra 是目录软链接 → 外部目录
        let a = tmp.appendingPathComponent("a")
        try writeCopy(at: a)
        try fm.createSymbolicLink(at: a.appendingPathComponent("extra"), withDestinationURL: extDir)
        // copy B：extra 是真实目录且内容相同
        let b = tmp.appendingPathComponent("b")
        try writeCopy(at: b)
        try fm.createDirectory(at: b.appendingPathComponent("extra"), withIntermediateDirectories: true)
        try "inner".write(to: b.appendingPathComponent("extra/inner.txt"), atomically: true, encoding: .utf8)

        let fa = Discovery.contentFingerprint(ofSkillAtCanonicalPath: a.path)
        let fb = Discovery.contentFingerprint(ofSkillAtCanonicalPath: b.path)
        XCTAssertNotNil(fa)
        XCTAssertNotEqual(fa, fb, "目录软链接不跟随枚举外部内容；与真实目录不等价")
    }

    func testContentFingerprintReturnsNilWhenAnyFileUnreadable() throws {
        let a = tmp.appendingPathComponent("a")
        try writeCopy(at: a)
        let secret = a.appendingPathComponent("scripts/run.sh")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: secret.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secret.path) }

        XCTAssertNil(
            Discovery.contentFingerprint(ofSkillAtCanonicalPath: a.path),
            "读取不完整 → 不产出可合并指纹（fail closed）"
        )
    }

    func testScanRecordsIssueAndSkipsFingerprintWhenCopyContentUnreadable() throws {
        let root = tmp.appendingPathComponent("skills")
        let skill = root.appendingPathComponent("broken-copy")
        try writeCopy(at: skill)
        let secret = skill.appendingPathComponent("scripts/run.sh")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: secret.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secret.path) }

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.count, 1, "Skill 仍被发现")
        XCTAssertNil(result.skills.first?.contentFingerprint, "不产出可合并指纹")
        XCTAssertTrue(result.issues.contains { $0.path == skill.path }, "记录可恢复 Scan Issue")
        switch result.outcome {
        case .partial: break
        case .complete, .failed: XCTFail("读取不完整应标记 partial")
        }
    }

    func testScanComputesFingerprintOnlyForRepoLessCopies() throws {
        let root = tmp.appendingPathComponent("skills")
        let repo = root.appendingPathComponent("suite-repo")
        try makeWorkTree(at: repo)
        try writeCopy(at: repo.appendingPathComponent("skill-a"))
        let plain = root.appendingPathComponent("plain-copy")
        try writeCopy(at: plain)

        let result = Discovery.scanPersonalRoots([root.path])
        let attributed = result.skills.first { $0.repositoryRootPath != nil }
        let copy = result.skills.first { $0.repositoryRootPath == nil }
        XCTAssertNil(attributed?.contentFingerprint, "已归因 Skill 的身份由 Skill Identity 裁决，不需要内容指纹")
        XCTAssertNotNil(copy?.contentFingerprint, "复制投影需要内容指纹用于聚合")
    }
}
