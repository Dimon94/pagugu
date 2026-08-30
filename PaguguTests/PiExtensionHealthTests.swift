import JavaScriptCore
import XCTest
@testable import Pagugu

final class PiExtensionHealthTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var homeDirectory: URL!
    private var sourceURL: URL!
    private var installationURL: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        homeDirectory = temporaryDirectory.appendingPathComponent("home")
        sourceURL = temporaryDirectory.appendingPathComponent("bundled-index.ts")
        installationURL = homeDirectory.appendingPathComponent(
            ".pi/agent/extensions/pagugu-visibility/index.ts"
        )
        try! fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try! extensionSource(version: PiExtensionManager.currentVersion).write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    @MainActor
    func testMissingExtensionDisablesAppModelWritesUntilInstalled() async throws {
        let manager = PiExtensionManager(homeDirectory: homeDirectory, sourceURL: sourceURL)
        let model = try await makeStartedModel(extensionManager: manager)
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)

        XCTAssertEqual(model.piExtensionHealth, .missing)
        XCTAssertFalse(model.canWritePiVisibility)
        XCTAssertTrue(model.piExtensionHealth.recoverySuggestion?.contains("安装") == true)
        let changedWhileMissing = await model.setPiExposureLevel(.explicitOnly, for: skill.id)
        XCTAssertFalse(changedWhileMissing)
        XCTAssertTrue(model.visibilityClaimError?.reason.contains("安装") == true)

        let installed = await model.installOrUpdatePiExtension()
        XCTAssertTrue(installed)
        XCTAssertEqual(model.piExtensionHealth, .healthy)
        XCTAssertTrue(model.canWritePiVisibility)
        let changedAfterInstall = await model.setPiExposureLevel(.explicitOnly, for: skill.id)
        XCTAssertTrue(changedAfterInstall)
        XCTAssertTrue(model.piReloadRequired)
        XCTAssertEqual(
            try visibilityDocument(),
            ["hiddenSkills": ["helper"], "disabledSkills": []]
        )
    }

    @MainActor
    func testPiVisibilityCanRestoreConfigurationThatDidNotExistBeforePaguguWrite() async throws {
        let manager = PiExtensionManager(homeDirectory: homeDirectory, sourceURL: sourceURL)
        XCTAssertTrue(try manager.installOrUpdate())
        let model = try await makeStartedModel(extensionManager: manager)
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)

        let changed = await model.setPiExposureLevel(.explicitOnly, for: skill.id)
        XCTAssertTrue(changed)
        XCTAssertTrue(fileManager.fileExists(atPath: configurationURL.path))

        let restored = await model.restorePiConfiguration()

        XCTAssertTrue(restored)
        XCTAssertFalse(
            fileManager.fileExists(atPath: configurationURL.path),
            "Pi 恢复必须回到 Pagugu 写入前文件不存在的状态"
        )
        XCTAssertTrue(model.piReloadRequired)
    }

    @MainActor
    func testPiRestoreRejectsMissingExtensionWithoutChangingConfiguration() async throws {
        let manager = PiExtensionManager(homeDirectory: homeDirectory, sourceURL: sourceURL)
        XCTAssertTrue(try manager.installOrUpdate())
        let model = try await makeStartedModel(extensionManager: manager)
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)
        let changed = await model.setPiExposureLevel(.explicitOnly, for: skill.id)
        XCTAssertTrue(changed)
        let configurationBeforeRestore = try Data(contentsOf: configurationURL)
        try fileManager.removeItem(at: installationURL)

        let restored = await model.restorePiConfiguration()

        XCTAssertFalse(restored)
        XCTAssertEqual(model.piExtensionHealth, .missing)
        XCTAssertEqual(try Data(contentsOf: configurationURL), configurationBeforeRestore)
        XCTAssertTrue(model.visibilityClaimError?.reason.contains("安装") == true)
    }

    @MainActor
    func testPiRestoreRejectsIncompatibleExtensionWithoutChangingConfiguration() async throws {
        let manager = PiExtensionManager(homeDirectory: homeDirectory, sourceURL: sourceURL)
        XCTAssertTrue(try manager.installOrUpdate())
        let model = try await makeStartedModel(extensionManager: manager)
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)
        let changed = await model.setPiExposureLevel(.fullyDisabled, for: skill.id)
        XCTAssertTrue(changed)
        let configurationBeforeRestore = try Data(contentsOf: configurationURL)
        try extensionSource(version: "0").write(
            to: installationURL,
            atomically: true,
            encoding: .utf8
        )

        let restored = await model.restorePiConfiguration()

        XCTAssertFalse(restored)
        XCTAssertEqual(model.piExtensionHealth, .incompatible(installedVersion: "0"))
        XCTAssertEqual(try Data(contentsOf: configurationURL), configurationBeforeRestore)
        XCTAssertTrue(model.visibilityClaimError?.reason.contains("更新") == true)
    }

    @MainActor
    func testIncompatibleExtensionDisablesWritesAndCanBeUpgradedIdempotently() async throws {
        try fileManager.createDirectory(
            at: installationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try extensionSource(version: "0").write(
            to: installationURL,
            atomically: true,
            encoding: .utf8
        )
        let manager = PiExtensionManager(homeDirectory: homeDirectory, sourceURL: sourceURL)
        let model = try await makeStartedModel(extensionManager: manager)
        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)

        XCTAssertEqual(model.piExtensionHealth, .incompatible(installedVersion: "0"))
        XCTAssertFalse(model.canWritePiVisibility)
        XCTAssertTrue(model.piExtensionHealth.recoverySuggestion?.contains("更新") == true)
        let changedWhileIncompatible = await model.setPiExposureLevel(.fullyDisabled, for: skill.id)
        XCTAssertFalse(changedWhileIncompatible)
        XCTAssertFalse(fileManager.fileExists(atPath: configurationURL.path))

        let upgraded = await model.installOrUpdatePiExtension()
        XCTAssertTrue(upgraded)
        XCTAssertEqual(model.piExtensionHealth, .healthy)
        XCTAssertEqual(try Data(contentsOf: installationURL), try Data(contentsOf: sourceURL))
        XCTAssertFalse(try manager.installOrUpdate(), "重复安装相同版本必须是 no-op")
    }

    func testBundledExtensionAssetMatchesManagerVersion() throws {
        let bundledSourceURL = try XCTUnwrap(
            Bundle.main.url(forResource: "index", withExtension: "ts")
        )
        let manager = PiExtensionManager(
            homeDirectory: homeDirectory,
            sourceURL: bundledSourceURL
        )

        XCTAssertTrue(try manager.installOrUpdate())
        XCTAssertEqual(manager.health(), .healthy)
    }

    func testBundledExtensionFiltersAndBlocksConfiguredSkillsButFailsOpenForDamage() throws {
        let sourceURL = try XCTUnwrap(
            Bundle.main.url(forResource: "index", withExtension: "ts")
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let executableStart = try XCTUnwrap(
            source.range(of: "export const PAGUGU_PI_EXTENSION_VERSION")
        ).lowerBound
        let executableSource = String(source[executableStart...])
            .replacingOccurrences(of: "export const", with: "const")
            .replacingOccurrences(of: "export default function", with: "function")
        let script = """
        var mockConfiguration = "";
        function readFileSync() { return mockConfiguration; }
        function homedir() { return "/tmp/home"; }
        function join(...segments) { return segments.join("/"); }
        function formatSkillsForPrompt(skills) {
            return skills.map((skill) => `<name>${skill.name}</name>`).join("\\n");
        }
        \(executableSource)
        function registerHandlers() {
            const handlers = {};
            paguguVisibilityExtension({
                on(name, handler) { handlers[name] = handler; }
            });
            return handlers;
        }
        const skills = ["visible", "hidden", "disabled"].map((name) => ({ name }));
        const prompt = `prefix\\n${formatSkillsForPrompt(skills)}\\nsuffix`;
        mockConfiguration = JSON.stringify({
            hiddenSkills: ["hidden"],
            disabledSkills: ["disabled"]
        });
        const configured = registerHandlers();
        const filtered = configured.before_agent_start({
            systemPrompt: prompt,
            systemPromptOptions: { skills }
        });
        const hiddenAction = configured.input(
            { text: "/skill:hidden" },
            { hasUI: false }
        ).action;
        const disabledAction = configured.input(
            { text: "/skill:disabled argument" },
            { hasUI: false }
        ).action;
        mockConfiguration = "{";
        const damaged = registerHandlers();
        const damagedPromptResult = damaged.before_agent_start({
            systemPrompt: prompt,
            systemPromptOptions: { skills }
        });
        const damagedInputAction = damaged.input(
            { text: "/skill:disabled" },
            { hasUI: false }
        ).action;
        JSON.stringify({
            filteredPrompt: filtered.systemPrompt,
            hiddenAction,
            disabledAction,
            damagedPromptFailsOpen: damagedPromptResult === undefined,
            damagedInputAction
        });
        """
        let context = try XCTUnwrap(JSContext())
        let result = context.evaluateScript(script)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "JavaScript 执行失败")
        let reportString = try XCTUnwrap(result?.toString())
        let report = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(reportString.utf8)) as? [String: Any]
        )
        let filteredPrompt = try XCTUnwrap(report["filteredPrompt"] as? String)

        XCTAssertTrue(filteredPrompt.contains("<name>visible</name>"))
        XCTAssertFalse(filteredPrompt.contains("<name>hidden</name>"))
        XCTAssertFalse(filteredPrompt.contains("<name>disabled</name>"))
        XCTAssertEqual(report["hiddenAction"] as? String, "continue")
        XCTAssertEqual(report["disabledAction"] as? String, "handled")
        XCTAssertEqual(report["damagedPromptFailsOpen"] as? Bool, true)
        XCTAssertEqual(report["damagedInputAction"] as? String, "continue")
    }

    @MainActor
    private func makeStartedModel(extensionManager: PiExtensionManager) async throws -> AppModel {
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
        let piRoot = homeDirectory.appendingPathComponent(".pi/agent/skills")
        try fileManager.createDirectory(at: piRoot, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: piRoot.appendingPathComponent("helper"),
            withDestinationURL: sourceSkill
        )
        let model = AppModel(
            personalRoots: [piRoot.path],
            persistence: Persistence(directoryURL: temporaryDirectory.appendingPathComponent("data")),
            hostConfigReader: HostConfigReader(homeDirectory: homeDirectory),
            piVisibilityWriter: PiVisibilityWriter(homeDirectory: homeDirectory),
            piExtensionManager: extensionManager
        )
        await model.start()
        return model
    }

    private var configurationURL: URL {
        homeDirectory.appendingPathComponent(".pi/agent/pagugu/visibility.json")
    }

    private func visibilityDocument() throws -> [String: [String]] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: configurationURL))
                as? [String: [String]]
        )
    }

    private func extensionSource(version: String) -> String {
        """
        export const PAGUGU_PI_EXTENSION_VERSION = \"\(version)\";
        export default function () {}
        """
    }
}
