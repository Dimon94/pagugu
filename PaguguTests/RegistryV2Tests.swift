import XCTest
@testable import Pagugu

final class RegistryV2Tests: XCTestCase {
    private var directoryURL: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        directoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: directoryURL)
        super.tearDown()
    }

    func testVisibilityClaimPersistsWithoutTimestamp() async throws {
        let registry = AppRegistry(
            persistence: Persistence(directoryURL: directoryURL),
            personalRoots: []
        )
        _ = await registry.load()
        let claim = VisibilityClaim(
            skillSourceKey: "github.com/Owner/repo",
            repositoryRelativePath: "skills/example",
            host: .claude,
            exposureLevel: .explicitOnly
        )

        let changed = try await registry.setVisibilityClaim(claim)
        let duplicateChanged = try await registry.setVisibilityClaim(claim)
        XCTAssertTrue(changed)
        XCTAssertFalse(duplicateChanged, "相同主张应是无写入的 no-op")

        let unsupported = VisibilityClaim(
            skillSourceKey: "github.com/Owner/repo",
            repositoryRelativePath: "skills/example",
            host: .codex,
            exposureLevel: .nameOnly
        )
        do {
            _ = try await registry.setVisibilityClaim(unsupported)
            XCTFail("宿主不支持的档位不得成为 Registry Claim")
        } catch let error as VisibilityClaimError {
            XCTAssertEqual(error, .unsupportedExposureLevel)
        }

        let reloaded = AppRegistry(
            persistence: Persistence(directoryURL: directoryURL),
            personalRoots: []
        )
        _ = await reloaded.load()
        let reloadedClaims = await reloaded.visibilityClaims()
        XCTAssertEqual(reloadedClaims, [claim])

        let registryURL = directoryURL.appendingPathComponent("registry.json")
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any]
        )
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        let claims = try XCTUnwrap(json["visibilityClaims"] as? [[String: Any]])
        XCTAssertEqual(
            Set(try XCTUnwrap(claims.first).keys),
            ["skillSourceKey", "repositoryRelativePath", "host", "exposureLevel"],
            "Visibility Claim 必须保持零时间戳、零派生标志位"
        )
    }

    func testV1MigratesToV2WithoutLosingExistingRegistryCollections() async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let registryURL = directoryURL.appendingPathComponent("registry.json")
        let v1Bytes = Data(
            #"{"schemaVersion":1,"projectScanRoots":[{"canonicalPath":"/projects","asFoundPath":"/projects"}],"sourceMappings":{"/installation":{"skillSourceKey":"github.com/Owner/repo","repositoryRelativePath":"skills/example"}},"checkoutObservations":{"/checkout":{"result":"success","completedAt":"2026-08-30T00:00:00Z","remoteTipSHA":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","identityDigest":{"checkoutCanonicalPath":"/checkout","gitCommonDirIdentifier":"git-common","normalizedRemoteURL":"github.com/Owner/repo","branchName":"main","upstreamRefName":"origin/main"}}}}"#.utf8
        )
        try v1Bytes.write(to: registryURL)

        let result = await Persistence(directoryURL: directoryURL).loadRegistry()

        guard case .ready(let document) = result else {
            return XCTFail("合法 v1 Registry 应迁移为 ready v2")
        }
        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.projectScanRoots.map(\.canonicalPath), ["/projects"])
        XCTAssertEqual(document.sourceMappings["/installation"]?.repositoryRelativePath, "skills/example")
        XCTAssertEqual(document.checkoutObservations["/checkout"]?.remoteTipSHA, String(repeating: "a", count: 40))
        XCTAssertTrue(document.visibilityClaims.isEmpty)

        let migratedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any]
        )
        XCTAssertEqual(migratedJSON["schemaVersion"] as? Int, 2)
        XCTAssertNotNil(migratedJSON["visibilityClaims"])
        let migrationBackups = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("registry.v1.pre-migration-") }
        XCTAssertEqual(migrationBackups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(migrationBackups.first)), v1Bytes)
    }

    func testV1MigrationFailsClosedWhenRegistryChangesBeforeMigrationWrite() async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let registryURL = directoryURL.appendingPathComponent("registry.json")
        let v1Bytes = Data(
            #"{"schemaVersion":1,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{}}"#.utf8
        )
        let externalBytes = Data(#"{"externalEdit":"must remain"}"#.utf8)
        try v1Bytes.write(to: registryURL)
        let persistence = Persistence(directoryURL: directoryURL) {
            try externalBytes.write(to: registryURL)
        }

        let result = await persistence.loadRegistry()

        guard case .restricted(let recovery) = result else {
            return XCTFail("迁移写入前发生外部漂移时必须进入受限恢复模式")
        }
        XCTAssertEqual(recovery.kind, .externallyModified)
        XCTAssertEqual(recovery.evidenceURL, registryURL)
        XCTAssertEqual(
            try Data(contentsOf: registryURL),
            externalBytes,
            "迁移不得覆写外部修改"
        )
    }

    func testUnknownFutureVersionIsNeverOverwritten() async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let registryURL = directoryURL.appendingPathComponent("registry.json")
        let futureBytes = Data(
            #"{"schemaVersion":3,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{},"visibilityClaims":[],"futureClaim":{"mustRemain":true}}"#.utf8
        )
        try futureBytes.write(to: registryURL)
        let persistence = Persistence(directoryURL: directoryURL)

        guard case .restricted(let recovery) = await persistence.loadRegistry() else {
            return XCTFail("未知未来版本必须进入受限恢复模式")
        }
        XCTAssertEqual(recovery.kind, .unknownFutureVersion)

        do {
            try await persistence.saveRegistry(.empty)
            XCTFail("未知未来版本不得被覆写")
        } catch let error as PersistenceError {
            guard case .recoveryRequired(let saveRecovery) = error else {
                return XCTFail("错误类型不符：\(error)")
            }
            XCTAssertEqual(saveRecovery.kind, .unknownFutureVersion)
        }
        XCTAssertEqual(try Data(contentsOf: registryURL), futureBytes)
    }
}
