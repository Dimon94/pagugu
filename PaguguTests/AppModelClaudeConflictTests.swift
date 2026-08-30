import XCTest
@testable import Pagugu

final class AppModelClaudeConflictTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var homeDirectory: URL!
    private var dataDirectory: URL!
    private var configurationURL: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        homeDirectory = temporaryDirectory.appendingPathComponent("home")
        dataDirectory = temporaryDirectory.appendingPathComponent("data")
        configurationURL = homeDirectory.appendingPathComponent(".claude/settings.json")
        try! fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    @MainActor
    func testExternalEditCanBeReappliedAdoptedAndRestored() async throws {
        let model = try await makeStartedModel(configuration: #"{"theme":"dark"}"#)
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)

        let setExplicitOnly = await model.setClaudeExposureLevel(.explicitOnly, for: skill.id)
        XCTAssertTrue(setExplicitOnly)
        XCTAssertEqual(try overrideValue(for: "helper"), "user-invocable-only")
        assertClaudeSurface(
            in: model,
            skillIdentity: skill.id,
            current: .explicitOnly,
            claim: .explicitOnly,
            hasDivergence: false
        )

        try writeConfiguration(#"{"theme":"external","skillOverrides":{"helper":"off"}}"#)
        await model.rescan()
        assertClaudeSurface(
            in: model,
            skillIdentity: skill.id,
            current: .fullyDisabled,
            claim: .explicitOnly,
            hasDivergence: true
        )

        let reapplied = await model.reapplyClaudeVisibilityClaim(for: skill.id)
        XCTAssertTrue(reapplied)
        XCTAssertEqual(try overrideValue(for: "helper"), "user-invocable-only")
        assertClaudeSurface(
            in: model,
            skillIdentity: skill.id,
            current: .explicitOnly,
            claim: .explicitOnly,
            hasDivergence: false
        )

        try writeConfiguration(#"{"theme":"external","skillOverrides":{"helper":"name-only"}}"#)
        await model.rescan()
        let adopted = await model.adoptClaudeDiskConfiguration(for: skill.id)
        XCTAssertTrue(adopted)
        XCTAssertEqual(try overrideValue(for: "helper"), "name-only")
        assertClaudeSurface(
            in: model,
            skillIdentity: skill.id,
            current: .nameOnly,
            claim: nil,
            hasDivergence: false
        )

        let setFullyDisabled = await model.setClaudeExposureLevel(.fullyDisabled, for: skill.id)
        XCTAssertTrue(setFullyDisabled)
        XCTAssertEqual(try overrideValue(for: "helper"), "off")
        let restored = await model.restoreClaudeConfiguration()
        XCTAssertTrue(restored)
        XCTAssertEqual(try overrideValue(for: "helper"), "name-only")
        assertClaudeSurface(
            in: model,
            skillIdentity: skill.id,
            current: .nameOnly,
            claim: .fullyDisabled,
            hasDivergence: true
        )
    }

    @MainActor
    func testProjectOverrideMakesUserLevelWriteFailInsteadOfReturningFalseSuccess() async throws {
        let repository = temporaryDirectory.appendingPathComponent("project-repository")
        let projectSkill = repository.appendingPathComponent(".claude/skills/helper")
        try fileManager.createDirectory(
            at: repository.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: projectSkill, withIntermediateDirectories: true)
        try "---\nname: helper\ndescription: Project Test\n---\n".write(
            to: projectSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"skillOverrides":{"helper":"off"}}"#.write(
            to: repository.appendingPathComponent(".claude/settings.json"),
            atomically: true,
            encoding: .utf8
        )
        try writeConfiguration(#"{"theme":"dark"}"#)
        let model = AppModel(
            personalRoots: [],
            persistence: Persistence(directoryURL: dataDirectory),
            hostConfigReader: HostConfigReader(homeDirectory: homeDirectory),
            claudeConfigWriter: ClaudeConfigWriter(homeDirectory: homeDirectory)
        )
        await model.start()
        await model.addProjectScanRoot(repository)
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)

        let changed = await model.setClaudeExposureLevel(.fullyExposed, for: skill.id)

        XCTAssertFalse(changed, "项目级 override 遮蔽用户写入时不得返回成功")
        XCTAssertEqual(
            model.visibilityClaimError,
            .hostConfiguration(.effectiveConfigurationMismatch)
        )
        XCTAssertEqual(try overrideValue(for: "helper"), "on")
        assertClaudeSurface(
            in: model,
            skillIdentity: skill.id,
            current: .fullyDisabled,
            claim: .fullyExposed,
            hasDivergence: true
        )
    }

    @MainActor
    func testSameClaudeNameAcrossDifferentIdentitiesFailsClosed() async throws {
        let claudeRoot = homeDirectory.appendingPathComponent(".claude/skills")
        for (repositoryName, installationName) in [("first", "first-install"), ("second", "second-install")] {
            let repository = temporaryDirectory.appendingPathComponent(repositoryName)
            let sourceSkill = repository.appendingPathComponent("skills/helper")
            try fileManager.createDirectory(
                at: repository.appendingPathComponent(".git"),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(at: sourceSkill, withIntermediateDirectories: true)
            try "---\nname: helper\ndescription: \(repositoryName)\n---\n".write(
                to: sourceSkill.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
            try fileManager.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(
                at: claudeRoot.appendingPathComponent(installationName),
                withDestinationURL: sourceSkill
            )
        }
        try writeConfiguration(#"{"theme":"dark"}"#)
        let model = AppModel(
            personalRoots: [claudeRoot.path],
            persistence: Persistence(directoryURL: dataDirectory),
            hostConfigReader: HostConfigReader(homeDirectory: homeDirectory),
            claudeConfigWriter: ClaudeConfigWriter(homeDirectory: homeDirectory)
        )
        await model.start()
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)

        let changed = await model.setClaudeExposureLevel(.explicitOnly, for: skill.id)

        XCTAssertFalse(changed)
        XCTAssertEqual(model.visibilityClaimError, .ambiguousSkillName)
        XCTAssertNil(try overrideValue(for: "helper"))
        XCTAssertNil(claudeSurface(in: model, skillIdentity: skill.id).claimLevel)
    }

    @MainActor
    func testWriteFailureKeepsClaimAndPresentsRecoveryDirection() async throws {
        let invalidConfiguration = "{ invalid json"
        let model = try await makeStartedModel(configuration: invalidConfiguration)
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)

        let changed = await model.setClaudeExposureLevel(.explicitOnly, for: skill.id)
        XCTAssertFalse(changed)

        XCTAssertEqual(try String(contentsOf: configurationURL, encoding: .utf8), invalidConfiguration)
        XCTAssertEqual(model.visibilityClaimError, .hostConfiguration(.invalidConfiguration))
        XCTAssertTrue(model.visibilityClaimError?.reason.contains("修复") == true)
        let claim = try XCTUnwrap(claudeSurface(in: model, skillIdentity: skill.id).claimLevel)
        XCTAssertEqual(claim, .explicitOnly, "Registry 已先落盘的主张必须保留，以便显式恢复")
    }

    @MainActor
    private func makeStartedModel(configuration: String) async throws -> AppModel {
        let repository = temporaryDirectory.appendingPathComponent("repository")
        let sourceSkill = repository.appendingPathComponent("skills/helper")
        try fileManager.createDirectory(
            at: repository.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: sourceSkill, withIntermediateDirectories: true)
        try "---\nname: helper\ndescription: Test\n---\n".write(
            to: sourceSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let claudeSkill = homeDirectory.appendingPathComponent(".claude/skills/helper")
        try fileManager.createDirectory(
            at: claudeSkill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(at: claudeSkill, withDestinationURL: sourceSkill)
        try writeConfiguration(configuration)

        let model = AppModel(
            personalRoots: [homeDirectory.appendingPathComponent(".claude/skills").path],
            persistence: Persistence(directoryURL: dataDirectory),
            hostConfigReader: HostConfigReader(homeDirectory: homeDirectory),
            claudeConfigWriter: ClaudeConfigWriter(homeDirectory: homeDirectory)
        )
        await model.start()
        return model
    }

    @MainActor
    private func assertClaudeSurface(
        in model: AppModel,
        skillIdentity: SkillIdentity,
        current: ExposureLevel,
        claim: ExposureLevel?,
        hasDivergence: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let surface = claudeSurface(in: model, skillIdentity: skillIdentity)
        XCTAssertEqual(surface.state, .level(current), file: file, line: line)
        XCTAssertEqual(surface.claimLevel, claim, file: file, line: line)
        XCTAssertEqual(surface.hasDivergence, hasDivergence, file: file, line: line)
    }

    @MainActor
    private func claudeSurface(
        in model: AppModel,
        skillIdentity: SkillIdentity
    ) -> HostInvocationSurface {
        try! XCTUnwrap(
            model.readModel.invocationSurfaces(for: skillIdentity).first { $0.host == .claude }
        )
    }

    private func writeConfiguration(_ contents: String) throws {
        try fileManager.createDirectory(
            at: configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: configurationURL, atomically: true, encoding: .utf8)
    }

    private func overrideValue(for skillName: String) throws -> String? {
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL)) as? [String: Any]
        )
        return (root["skillOverrides"] as? [String: Any])?[skillName] as? String
    }
}
