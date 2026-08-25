import XCTest
@testable import Pagugu

final class RegistryTests: XCTestCase {
    private enum TestWriteFailure: Error {
        case beforeReplace
    }

    private var temporaryDirectory: URL!
    private var dataDirectory: URL!
    private var homeDirectory: URL!
    private var personalRoot: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        dataDirectory = temporaryDirectory.appendingPathComponent("data")
        homeDirectory = temporaryDirectory.appendingPathComponent("home")
        personalRoot = temporaryDirectory.appendingPathComponent("agent/skills")
        try! fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try! fileManager.createDirectory(at: personalRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    func testGuardrailsRejectFourForbiddenSelectionsWithChineseReasons() async throws {
        let persistence = Persistence(directoryURL: dataDirectory)
        let registry = AppRegistry(
            persistence: persistence,
            homeDirectory: homeDirectory,
            personalRoots: [personalRoot.path]
        )
        _ = await registry.load()

        let cases: [(URL, ProjectScanRootError)] = [
            (URL(fileURLWithPath: "/"), .fileSystemRoot),
            (homeDirectory, .homeDirectory),
            (personalRoot, .personalSkillRoot),
            (personalRoot.deletingLastPathComponent(), .personalSkillRootAncestor),
        ]

        for (url, expectedError) in cases {
            do {
                try await registry.addProjectScanRoot(url)
                XCTFail("\(url.path) 应被拒绝")
            } catch let error as ProjectScanRootError {
                XCTAssertEqual(error, expectedError)
                XCTAssertFalse(error.reason.isEmpty)
                XCTAssertTrue(error.reason.contains("请选择") || error.reason.contains("自动扫描"))
            }
        }
        let roots = await registry.projectScanRoots()
        XCTAssertTrue(roots.isEmpty)
    }

    func testGuardrailsRejectAsFoundAncestorOfSymlinkedPersonalRoot() async throws {
        let realPersonalRoot = try makeDirectory("real-personal-root")
        let asFoundParent = try makeDirectory("agent-host")
        let linkedPersonalRoot = asFoundParent.appendingPathComponent("skills")
        try fileManager.createSymbolicLink(
            at: linkedPersonalRoot,
            withDestinationURL: realPersonalRoot
        )
        let persistence = Persistence(directoryURL: dataDirectory)
        let registry = AppRegistry(
            persistence: persistence,
            homeDirectory: homeDirectory,
            personalRoots: [linkedPersonalRoot.path]
        )
        _ = await registry.load()

        do {
            try await registry.addProjectScanRoot(asFoundParent)
            XCTFail("Personal Skill Root 的 as-found 祖先必须被拒绝")
        } catch let error as ProjectScanRootError {
            XCTAssertEqual(error, .personalSkillRootAncestor)
        }

        let aliasParent = temporaryDirectory.appendingPathComponent("agent-host-alias")
        try fileManager.createSymbolicLink(at: aliasParent, withDestinationURL: asFoundParent)
        do {
            try await registry.addProjectScanRoot(aliasParent)
            XCTFail("Personal Skill Root 的别名祖先必须被拒绝")
        } catch let error as ProjectScanRootError {
            XCTAssertEqual(error, .personalSkillRootAncestor)
        }
        let roots = await registry.projectScanRoots()
        XCTAssertTrue(roots.isEmpty)

        try await persistence.saveRegistry(RegistryDocument(
            schemaVersion: RegistryDocument.currentSchemaVersion,
            projectScanRoots: [
                ProjectScanRootRecord(
                    canonicalPath: asFoundParent.path,
                    asFoundPath: asFoundParent.path
                ),
            ],
            sourceMappings: [:],
            checkoutObservations: [:]
        ))
        let reloaded = AppRegistry(
            persistence: persistence,
            homeDirectory: homeDirectory,
            personalRoots: [linkedPersonalRoot.path]
        )
        _ = await reloaded.load()
        let reloadedRoots = await reloaded.projectScanRoots()
        XCTAssertFalse(try XCTUnwrap(reloadedRoots.first).passesGuardrails)
    }

    func testAddPersistsOrderAcrossReload() async throws {
        let first = try makeDirectory("projects-first")
        let second = try makeDirectory("projects-second")
        let registry = makeRegistry()
        _ = await registry.load()

        try await registry.addProjectScanRoot(first)
        try await registry.addProjectScanRoot(second)

        let reloaded = makeRegistry()
        _ = await reloaded.load()
        let roots = await reloaded.projectScanRoots()
        XCTAssertEqual(roots.map(\.asFoundPath), [first.path, second.path])
    }

    func testUnavailableRootIsRetainedAndAutomaticallyRevives() async throws {
        let root = try makeDirectory("movable")
        let registry = makeRegistry()
        _ = await registry.load()
        try await registry.addProjectScanRoot(root)

        try fileManager.removeItem(at: root)
        let unavailableRoots = await registry.projectScanRoots()
        let unavailable = try XCTUnwrap(unavailableRoots.first)
        XCTAssertFalse(unavailable.isAvailable)
        XCTAssertEqual(unavailable.unavailableReason, "目录不存在或不可读")

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let revivedRoots = await registry.projectScanRoots()
        let revived = try XCTUnwrap(revivedRoots.first)
        XCTAssertTrue(revived.isAvailable)
        XCTAssertNil(revived.unavailableReason)
    }

    func testRemovePreservesMappingsObservationsAndUserDirectory() async throws {
        let root = try makeDirectory("kept-on-disk")
        let persistence = Persistence(directoryURL: dataDirectory)
        _ = await persistence.loadRegistry()
        let observation = CheckoutObservation(
            result: .failure,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            remoteTipSHA: nil,
            identityDigest: CheckoutIdentityDigest(
                checkoutCanonicalPath: "/checkout",
                gitCommonDirIdentifier: "git-common",
                normalizedRemoteURL: "example.com/repo",
                branchName: "main",
                upstreamRefName: "origin/main"
            )
        )
        try await persistence.saveRegistry(RegistryDocument(
            schemaVersion: RegistryDocument.currentSchemaVersion,
            projectScanRoots: [ProjectScanRootRecord(canonicalPath: root.path, asFoundPath: root.path)],
            sourceMappings: [
                "/installation": SourceMappingRecord(
                    skillSourceKey: "example.com/repo",
                    repositoryRelativePath: "skills/example"
                ),
            ],
            checkoutObservations: ["/checkout": observation]
        ))
        let registry = AppRegistry(
            persistence: persistence,
            homeDirectory: homeDirectory,
            personalRoots: [personalRoot.path]
        )
        _ = await registry.load()

        try await registry.removeProjectScanRoot(canonicalPath: root.path)

        guard case .ready(let document) = await Persistence(directoryURL: dataDirectory).loadRegistry() else {
            return XCTFail("删除后 Registry 应可重新载入")
        }
        XCTAssertTrue(document.projectScanRoots.isEmpty)
        XCTAssertEqual(document.sourceMappings.count, 1)
        XCTAssertEqual(document.checkoutObservations.count, 1)
        XCTAssertTrue(fileManager.fileExists(atPath: root.path))
    }

    func testWriteFailureKeepsDiskAndProjectionAtLastGood() async throws {
        let first = try makeDirectory("first")
        let second = try makeDirectory("second")
        let initial = makeRegistry()
        _ = await initial.load()
        try await initial.addProjectScanRoot(first)

        let interrupted = AppRegistry(
            persistence: Persistence(directoryURL: dataDirectory) {
                throw TestWriteFailure.beforeReplace
            },
            homeDirectory: homeDirectory,
            personalRoots: [personalRoot.path]
        )
        _ = await interrupted.load()

        do {
            try await interrupted.addProjectScanRoot(second)
            XCTFail("写失败必须让动作失败")
        } catch let error as ProjectScanRootError {
            guard case .persistence(.writeFailed) = error else {
                return XCTFail("错误类型不符：\(error)")
            }
            XCTAssertTrue(error.reason.contains("磁盘空间"))
        }

        let roots = await interrupted.projectScanRoots()
        XCTAssertEqual(roots.map(\.canonicalPath), [first.path])
        guard case .ready(let reloaded) = await Persistence(directoryURL: dataDirectory).loadRegistry() else {
            return XCTFail("last-good 应保持可载入")
        }
        XCTAssertEqual(reloaded.projectScanRoots.map(\.canonicalPath), [first.path])
    }

    func testConcurrentAddsDoNotLoseClaims() async throws {
        let roots = try (0..<20).map { try makeDirectory("concurrent-\($0)") }
        let registry = makeRegistry()
        _ = await registry.load()

        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for root in roots {
                group.addTask {
                    do {
                        try await registry.addProjectScanRoot(root)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertTrue(results.allSatisfy { $0 })
        let savedRoots = await registry.projectScanRoots()
        XCTAssertEqual(Set(savedRoots.map(\.canonicalPath)), Set(roots.map(\.path)))
    }

    func testLoadedForbiddenRootIsUnavailable() async throws {
        let container = try makeDirectory("project-container")
        let nestedPersonalRoot = container.appendingPathComponent("personal/skills")
        try fileManager.createDirectory(at: nestedPersonalRoot, withIntermediateDirectories: true)
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
        let registry = AppRegistry(
            persistence: persistence,
            homeDirectory: homeDirectory,
            personalRoots: [nestedPersonalRoot.path]
        )
        _ = await registry.load()

        let projectedRoots = await registry.projectScanRoots()
        let root = try XCTUnwrap(projectedRoots.first)
        XCTAssertFalse(root.isAvailable)
        XCTAssertTrue(try XCTUnwrap(root.unavailableReason).contains("祖先目录"))
    }

    private func makeRegistry() -> AppRegistry {
        AppRegistry(
            persistence: Persistence(directoryURL: dataDirectory),
            homeDirectory: homeDirectory,
            personalRoots: [personalRoot.path]
        )
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
