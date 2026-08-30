import XCTest
@testable import Pagugu

final class PiVisibilityWriterTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var homeDirectory: URL!
    private var configurationURL: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        homeDirectory = temporaryDirectory.appendingPathComponent("home")
        configurationURL = homeDirectory.appendingPathComponent(".pi/agent/pagugu/visibility.json")
        try! fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    func testAtomicallyWritesAllSupportedPiExposureLevels() throws {
        let writer = PiVisibilityWriter(homeDirectory: homeDirectory)

        try writer.apply(exposureLevel: .explicitOnly, forSkillNamed: "helper")
        XCTAssertEqual(
            try document(),
            ["hiddenSkills": ["helper"], "disabledSkills": []]
        )

        try writer.apply(exposureLevel: .fullyDisabled, forSkillNamed: "helper")
        XCTAssertEqual(
            try document(),
            ["hiddenSkills": [], "disabledSkills": ["helper"]]
        )

        try writer.apply(exposureLevel: .fullyExposed, forSkillNamed: "helper")
        XCTAssertEqual(
            try document(),
            ["hiddenSkills": [], "disabledSkills": []]
        )
    }

    func testMalformedDocumentIsPreservedAndFailsWithRepairDirection() throws {
        let malformedBytes = Data("{".utf8)
        try fileManager.createDirectory(
            at: configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try malformedBytes.write(to: configurationURL)
        let writer = PiVisibilityWriter(homeDirectory: homeDirectory)

        XCTAssertThrowsError(
            try writer.apply(exposureLevel: .explicitOnly, forSkillNamed: "helper")
        ) { error in
            XCTAssertEqual(error as? PiVisibilityWriterError, .invalidConfiguration)
            XCTAssertTrue(
                (error as? PiVisibilityWriterError)?.recoverySuggestion.contains("visibility.json") == true
            )
        }
        XCTAssertEqual(try Data(contentsOf: configurationURL), malformedBytes)
    }

    private func document() throws -> [String: [String]] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL))
                as? [String: [String]]
        )
    }
}
