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
        try writeSkill(at: skillDir)

        let result = Discovery.scanPersonalRoots([root.path])
        XCTAssertEqual(result.skills.count, 1)
        XCTAssertEqual(result.skills.first?.name, "my-skill")
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
}
