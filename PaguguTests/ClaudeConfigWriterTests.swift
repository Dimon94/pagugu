import XCTest
@testable import Pagugu

final class ClaudeConfigWriterTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var homeDirectory: URL!
    private var configurationURL: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        homeDirectory = temporaryDirectory.appendingPathComponent("home")
        configurationURL = homeDirectory.appendingPathComponent(".claude/settings.json")
        try! fileManager.createDirectory(
            at: configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    func testWritesEveryExposureLevelAndRemovesOverrideWithSingleSlotBackup() throws {
        let originalBytes = Data(
            #"{"theme":"dark","skillOverrides":{"other":"off"}}"#.utf8
        )
        try originalBytes.write(to: configurationURL)
        let writer = ClaudeConfigWriter(homeDirectory: homeDirectory)

        let mappings: [(ExposureLevel, String)] = [
            (.fullyExposed, "on"),
            (.nameOnly, "name-only"),
            (.explicitOnly, "user-invocable-only"),
            (.fullyDisabled, "off"),
        ]
        for (level, rawValue) in mappings {
            try writer.apply(exposureLevel: level, forSkillNamed: "helper")
            XCTAssertEqual(try overrideValue(for: "helper"), rawValue)
            XCTAssertEqual(try topLevelValue(for: "theme") as? String, "dark")
        }

        let bytesBeforeRemoval = try Data(contentsOf: configurationURL)
        try writer.apply(exposureLevel: nil, forSkillNamed: "helper")

        XCTAssertNil(try overrideValue(for: "helper"))
        XCTAssertEqual(
            try Data(contentsOf: configurationURL.appendingPathExtension("pagugu-backup")),
            bytesBeforeRemoval,
            "清除主张前的配置必须成为当前单槽备份"
        )
    }

    func testExternalEditProducesDivergenceAndBackupCanRestorePreviousConfiguration() throws {
        try Data(#"{"skillOverrides":{"helper":"on"}}"#.utf8).write(to: configurationURL)
        let writer = ClaudeConfigWriter(homeDirectory: homeDirectory)
        try writer.apply(exposureLevel: .explicitOnly, forSkillNamed: "helper")

        try Data(#"{"skillOverrides":{"helper":"off"}}"#.utf8).write(to: configurationURL)
        XCTAssertEqual(
            try writer.claimState(expecting: .explicitOnly, forSkillNamed: "helper"),
            .divergent
        )

        try writer.restoreConfiguration()

        XCTAssertEqual(try overrideValue(for: "helper"), "on")
        XCTAssertEqual(
            try writer.claimState(expecting: .explicitOnly, forSkillNamed: "helper"),
            .divergent,
            "恢复写前配置后，仍应按实时文件事实派生与当前主张的分歧"
        )
    }

    private func overrideValue(for skillName: String) throws -> String? {
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL)) as? [String: Any]
        )
        return (root["skillOverrides"] as? [String: Any])?[skillName] as? String
    }

    private func topLevelValue(for key: String) throws -> Any? {
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL)) as? [String: Any]
        )
        return root[key]
    }
}
