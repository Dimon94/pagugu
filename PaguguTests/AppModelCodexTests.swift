import XCTest
@testable import Pagugu

final class AppModelCodexTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var homeDirectory: URL!
    private var dataDirectory: URL!
    private var configurationURL: URL!
    private var policyURL: URL!
    private var skillDirectory: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        homeDirectory = temporaryDirectory.appendingPathComponent("home")
        dataDirectory = temporaryDirectory.appendingPathComponent("data")
        configurationURL = homeDirectory.appendingPathComponent(".codex/config.toml")
        policyURL = homeDirectory.appendingPathComponent(".codex/agents/openai.yaml")
        skillDirectory = homeDirectory.appendingPathComponent(".agents/skills/helper")
        try! fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    @MainActor
    func testThreeLevelsCanBeSwitchedReappliedAdoptedAndRestored() async throws {
        let model = try await makeStartedModel(
            configuration: "# keep\nmodel = \"gpt-5\"\n",
            policy: "policy:\n  network: restricted\n  allow_implicit_invocation: true # keep\n"
        )
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)
        let skillMarkdownPath = skillDirectory.appendingPathComponent("SKILL.md").path

        let setExplicitOnly = await model.setCodexExposureLevel(.explicitOnly, for: skill.id)
        XCTAssertTrue(setExplicitOnly)
        XCTAssertTrue(try contents(of: policyURL).contains(
            "allow_implicit_invocation: false # keep"
        ))
        assertCodexSurface(
            in: model,
            skillIdentity: skill.id,
            current: .explicitOnly,
            claim: .explicitOnly,
            hasDivergence: false
        )

        let beforeUnsupported = try Data(contentsOf: policyURL)
        let setNameOnly = await model.setCodexExposureLevel(.nameOnly, for: skill.id)
        XCTAssertFalse(setNameOnly)
        XCTAssertEqual(model.visibilityClaimError, .registry(.unsupportedExposureLevel))
        XCTAssertEqual(try Data(contentsOf: policyURL), beforeUnsupported)
        model.clearVisibilityClaimError()

        let setFullyDisabled = await model.setCodexExposureLevel(.fullyDisabled, for: skill.id)
        XCTAssertTrue(setFullyDisabled)
        let disabledConfiguration = try contents(of: configurationURL)
        XCTAssertTrue(
            disabledConfiguration.contains(skillMarkdownPath),
            "expected \(skillMarkdownPath) in:\n\(disabledConfiguration)"
        )
        XCTAssertTrue(try contents(of: configurationURL).contains("enabled = false"))
        assertCodexSurface(
            in: model,
            skillIdentity: skill.id,
            current: .fullyDisabled,
            claim: .fullyDisabled,
            hasDivergence: false
        )

        let setFullyExposed = await model.setCodexExposureLevel(.fullyExposed, for: skill.id)
        XCTAssertTrue(setFullyExposed)
        XCTAssertFalse(try contents(of: configurationURL).contains(skillMarkdownPath))
        XCTAssertFalse(try contents(of: policyURL).contains("allow_implicit_invocation"))
        assertCodexSurface(
            in: model,
            skillIdentity: skill.id,
            current: .fullyExposed,
            claim: .fullyExposed,
            hasDivergence: false
        )

        try append(
            "\n[[skills.config]]\npath = \"\(skillMarkdownPath)\"\nenabled = false\n",
            to: configurationURL
        )
        await model.rescan()
        assertCodexSurface(
            in: model,
            skillIdentity: skill.id,
            current: .fullyDisabled,
            claim: .fullyExposed,
            hasDivergence: true
        )

        let reapplied = await model.reapplyCodexVisibilityClaim(for: skill.id)
        XCTAssertTrue(reapplied)
        XCTAssertFalse(try contents(of: configurationURL).contains(skillMarkdownPath))
        assertCodexSurface(
            in: model,
            skillIdentity: skill.id,
            current: .fullyExposed,
            claim: .fullyExposed,
            hasDivergence: false
        )

        try write("policy:\n  allow_implicit_invocation: false\n", to: policyURL)
        await model.rescan()
        let adopted = await model.adoptCodexDiskConfiguration(for: skill.id)
        XCTAssertTrue(adopted)
        assertCodexSurface(
            in: model,
            skillIdentity: skill.id,
            current: .explicitOnly,
            claim: nil,
            hasDivergence: false
        )

        let setDisabledBeforeRestore = await model.setCodexExposureLevel(.fullyDisabled, for: skill.id)
        XCTAssertTrue(setDisabledBeforeRestore)
        let restored = await model.restoreCodexConfiguration()
        XCTAssertTrue(restored)
        assertCodexSurface(
            in: model,
            skillIdentity: skill.id,
            current: .explicitOnly,
            claim: .fullyDisabled,
            hasDivergence: true
        )
    }

    @MainActor
    func testWriteFailureKeepsClaimAndPresentsRecoveryDirection() async throws {
        let invalidConfiguration = """
        [[skills.config]]
        name = "helper"
        enabled = sometimes
        """
        let originalPolicy = "policy:\n  allow_implicit_invocation: true\n"
        let model = try await makeStartedModel(
            configuration: invalidConfiguration,
            policy: originalPolicy
        )
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)

        let changed = await model.setCodexExposureLevel(.explicitOnly, for: skill.id)
        XCTAssertFalse(changed)

        XCTAssertEqual(try contents(of: configurationURL), invalidConfiguration)
        XCTAssertEqual(try contents(of: policyURL), originalPolicy, "预检失败不得产生跨文件部分写入")
        XCTAssertEqual(model.visibilityClaimError, .hostConfiguration(.invalidConfiguration))
        XCTAssertTrue(model.visibilityClaimError?.reason.contains("修复") == true)
        let surface = codexSurface(in: model, skillIdentity: skill.id)
        XCTAssertEqual(surface.state, .readFailed)
        XCTAssertEqual(surface.claimLevel, .explicitOnly, "Registry durable-first 主张必须保留")
    }

    @MainActor
    private func makeStartedModel(configuration: String, policy: String) async throws -> AppModel {
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
        try fileManager.createDirectory(
            at: skillDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(at: skillDirectory, withDestinationURL: sourceSkill)
        try write(configuration, to: configurationURL)
        try write(policy, to: policyURL)

        let model = AppModel(
            personalRoots: [homeDirectory.appendingPathComponent(".agents/skills").path],
            persistence: Persistence(directoryURL: dataDirectory),
            hostConfigReader: HostConfigReader(homeDirectory: homeDirectory),
            codexConfigWriter: CodexConfigWriter(homeDirectory: homeDirectory)
        )
        await model.start()
        return model
    }

    @MainActor
    private func assertCodexSurface(
        in model: AppModel,
        skillIdentity: SkillIdentity,
        current: ExposureLevel,
        claim: ExposureLevel?,
        hasDivergence: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let surface = codexSurface(in: model, skillIdentity: skillIdentity)
        XCTAssertEqual(surface.state, .level(current), file: file, line: line)
        XCTAssertEqual(surface.claimLevel, claim, file: file, line: line)
        XCTAssertEqual(surface.hasDivergence, hasDivergence, file: file, line: line)
    }

    @MainActor
    private func codexSurface(
        in model: AppModel,
        skillIdentity: SkillIdentity
    ) -> HostInvocationSurface {
        try! XCTUnwrap(
            model.readModel.invocationSurfaces(for: skillIdentity).first { $0.host == .codex }
        )
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func append(_ contents: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        handle.write(contents.data(using: .utf8)!)
        try handle.close()
    }

    private func write(_ contents: String, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
