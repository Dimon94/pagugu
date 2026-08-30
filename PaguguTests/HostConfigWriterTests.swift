import XCTest
@testable import Pagugu

final class HostConfigWriterTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var configurationURL: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        configurationURL = temporaryDirectory.appendingPathComponent("settings.json")
        try! fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    func testMergeOnlyChangesOwnedKeyAndSingleSlotBackupRestoresPreviousConfiguration() throws {
        let originalBytes = Data(
            #"{"theme":"dark","telemetry":{"enabled":true,"sample":0.125},"skillOverrides":{"other":"off"}}"#.utf8
        )
        try originalBytes.write(to: configurationURL)
        let writer = HostConfigWriter()
        let keyPath = ["skillOverrides", "helper"]

        try writer.merge(.string("user-invocable-only"), at: keyPath, in: configurationURL)

        XCTAssertEqual(try value(at: ["theme"], in: configurationURL), .string("dark"))
        XCTAssertEqual(
            try value(at: ["telemetry"], in: configurationURL),
            .object(["enabled": .bool(true), "sample": .number(Decimal(string: "0.125")!)])
        )
        XCTAssertEqual(try value(at: ["skillOverrides", "other"], in: configurationURL), .string("off"))
        XCTAssertEqual(
            try value(at: keyPath, in: configurationURL),
            .string("user-invocable-only")
        )
        let backupURL = configurationURL.appendingPathExtension("pagugu-backup")
        XCTAssertEqual(try Data(contentsOf: backupURL), originalBytes)

        let firstWrittenBytes = try Data(contentsOf: configurationURL)
        try writer.merge(nil, at: keyPath, in: configurationURL)

        XCTAssertNil(try value(at: keyPath, in: configurationURL))
        XCTAssertEqual(
            try Data(contentsOf: backupURL),
            firstWrittenBytes,
            "第二次写入必须覆盖单槽备份，只保留最近一次写前配置"
        )

        try writer.restoreBackup(for: configurationURL)

        XCTAssertEqual(try Data(contentsOf: configurationURL), firstWrittenBytes)
        XCTAssertEqual(
            try value(at: keyPath, in: configurationURL),
            .string("user-invocable-only")
        )
    }

    func testManualEditProducesDivergenceAgainstClaim() throws {
        try Data(#"{"skillOverrides":{"helper":"on"}}"#.utf8).write(to: configurationURL)
        let writer = HostConfigWriter()
        let keyPath = ["skillOverrides", "helper"]

        let consistent = try writer.claimState(
            expecting: .string("on"),
            at: keyPath,
            in: configurationURL
        )
        XCTAssertEqual(consistent, .consistent)
        XCTAssertFalse(consistent.hasDivergence)

        try Data(#"{"skillOverrides":{"helper":"off"}}"#.utf8).write(to: configurationURL)

        let divergent = try writer.claimState(
            expecting: .string("on"),
            at: keyPath,
            in: configurationURL
        )
        XCTAssertEqual(divergent, .divergent)
        XCTAssertTrue(divergent.hasDivergence)

        let externallyModifiedBytes = Data(
            #"{"theme":"host-write","skillOverrides":{"helper":"off"}}"#.utf8
        )
        let configurationURL = try XCTUnwrap(configurationURL)
        let writerDuringExternalChange = HostConfigWriter(beforeCommit: {
            try externallyModifiedBytes.write(to: configurationURL)
        })

        XCTAssertThrowsError(
            try writerDuringExternalChange.merge(.string("on"), at: keyPath, in: configurationURL)
        ) { error in
            XCTAssertEqual(error as? HostConfigWriterError, .externallyModified)
        }
        XCTAssertEqual(try Data(contentsOf: configurationURL), externallyModifiedBytes)
        XCTAssertFalse(fileManager.fileExists(
            atPath: configurationURL.appendingPathExtension("pagugu-backup").path
        ))
    }

    private func value(at keyPath: [String], in url: URL) throws -> HostConfigValue? {
        var current = try JSONDecoder().decode(HostConfigValue.self, from: Data(contentsOf: url))
        for key in keyPath {
            guard case .object(let object) = current,
                  let next = object[key] else { return nil }
            current = next
        }
        return current
    }
}
