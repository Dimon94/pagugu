import XCTest
@testable import Pagugu

// AppModel smoke 测试（ADR-0009 §14 第 6 层：SwiftUI smoke——启动、投影渲染、intent 路由存在）。
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

    // MARK: - 空 Registry 启动 = 正常态（S1）

    @MainActor
    func testStartWithEmptyRootsProducesEmptyReadModel() async {
        let missing = tmp.appendingPathComponent("nonexistent")
        let persistence = Persistence(directoryURL: tmp.appendingPathComponent("data"))
        let model = AppModel(personalRoots: [missing.path], persistence: persistence)
        XCTAssertFalse(model.registryReady)
        await model.start()

        XCTAssertTrue(model.registryReady)
        XCTAssertTrue(model.readModel.isEmpty)
        XCTAssertTrue(model.readModel.entries.isEmpty)
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

        let persistence = Persistence(directoryURL: tmp.appendingPathComponent("data"))
        let model = AppModel(personalRoots: [root.path], persistence: persistence)
        await model.start()

        XCTAssertFalse(model.readModel.isEmpty)
        XCTAssertEqual(model.readModel.entries.count, 1)
        XCTAssertEqual(model.readModel.entries.first?.displayName, "my-skill")
    }

    // MARK: - rescan intent 路由存在

    @MainActor
    func testRescanRefreshesReadModel() async throws {
        let root = tmp.appendingPathComponent("skills")
        let persistence = Persistence(directoryURL: tmp.appendingPathComponent("data"))
        let model = AppModel(personalRoots: [root.path], persistence: persistence)
        await model.start()
        XCTAssertTrue(model.readModel.isEmpty)

        // 添加 Skill 后 rescan
        try writeSkill(at: root.appendingPathComponent("new-skill"), name: "new-skill")
        await model.rescan()

        XCTAssertFalse(model.readModel.isEmpty)
        XCTAssertEqual(model.readModel.entries.count, 1)
    }

    @MainActor
    func testCorruptRegistryBlocksDiscoveryUntilConfirmedReset() async throws {
        let root = tmp.appendingPathComponent("skills")
        try writeSkill(at: root.appendingPathComponent("hidden-while-blocked"), name: "blocked")
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
        XCTAssertTrue(model.readModel.entries.isEmpty)

        await model.rescan()
        XCTAssertTrue(model.readModel.entries.isEmpty)

        await model.resetRegistry(confirmed: true)
        XCTAssertTrue(model.registryReady)
        XCTAssertNil(model.registryRecovery)
        XCTAssertEqual(model.readModel.entries.first?.displayName, "hidden-while-blocked")
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

    @MainActor
    func testAddAndRemoveProjectScanRootRefreshesPureSourceSkill() async throws {
        let root = tmp.appendingPathComponent("project-root")
        try writeSkill(at: root.appendingPathComponent("source-only"), name: "source-only")
        let model = AppModel(
            personalRoots: [],
            persistence: Persistence(directoryURL: tmp.appendingPathComponent("data"))
        )
        await model.start()

        await model.addProjectScanRoot(root)

        XCTAssertNil(model.projectScanRootError)
        XCTAssertEqual(model.readModel.projectScanRoots.map(\.asFoundPath), [root.path])
        XCTAssertEqual(model.readModel.entries.map(\.displayName), ["source-only"])
        XCTAssertTrue(model.readModel.entries.first?.installations.isEmpty == true)

        await model.removeProjectScanRoot(canonicalPath: root.path)

        XCTAssertTrue(model.readModel.projectScanRoots.isEmpty)
        XCTAssertTrue(model.readModel.entries.isEmpty)
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
        XCTAssertTrue(model.readModel.entries.isEmpty)
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

        XCTAssertTrue(model.readModel.entries.isEmpty)
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
        XCTAssertTrue(model.readModel.entries.isEmpty)
    }
}
