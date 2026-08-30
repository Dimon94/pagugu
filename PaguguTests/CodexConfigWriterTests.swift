import XCTest
@testable import Pagugu

final class CodexConfigWriterTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var homeDirectory: URL!
    private var configurationURL: URL!
    private var policyURL: URL!
    private var skillDirectory: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        homeDirectory = temporaryDirectory.appendingPathComponent("home")
        configurationURL = homeDirectory.appendingPathComponent(".codex/config.toml")
        policyURL = homeDirectory.appendingPathComponent(".codex/agents/openai.yaml")
        skillDirectory = homeDirectory.appendingPathComponent(".agents/skills/helper")
        try! fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    func testSwitchesThreeLevelsWithMinimalFormattingChangesAndRestoresBackups() throws {
        let skillMarkdownPath = skillDirectory.appendingPathComponent("SKILL.md").path
        let originalConfiguration = """
        # keep root comment
        model = "gpt-5" # keep root field

        [[skills.config]]
        path = "/other/SKILL.md"
        enabled = true # keep other entry

        # keep target comment
        [[skills.config]]
        path = "\(skillMarkdownPath)" # target
        enabled    = true    # keep enabled comment
        vendor = "keep until target entry is removed"
        """
        let originalPolicy = """
        # keep policy comment
        display_name: OpenAI # keep unknown field
        allow_implicit_invocation: preserve-top-level # same-name unknown field
        policy:
          network: restricted # keep nested field
          allow_implicit_invocation: true # keep key comment
        footer: keep
        """
        try write(originalConfiguration, to: configurationURL)
        try write(originalPolicy, to: policyURL)
        let writer = CodexConfigWriter(homeDirectory: homeDirectory)

        try writer.apply(
            exposureLevel: .fullyDisabled,
            forSkillNamed: "helper",
            installations: [installation()]
        )

        let disabledConfiguration = try contents(of: configurationURL)
        XCTAssertEqual(
            disabledConfiguration,
            originalConfiguration.replacingOccurrences(
                of: "enabled    = true    # keep enabled comment",
                with: "enabled    = false    # keep enabled comment"
            )
        )
        XCTAssertEqual(try contents(of: policyURL), originalPolicy)
        XCTAssertEqual(
            try Data(contentsOf: configurationURL.appendingPathExtension("pagugu-backup")),
            Data(originalConfiguration.utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: policyURL.appendingPathExtension("pagugu-backup")),
            Data(originalPolicy.utf8)
        )
        XCTAssertEqual(
            try writer.claimState(
                expecting: .fullyDisabled,
                forSkillNamed: "helper",
                installations: [installation()]
            ),
            .consistent
        )

        try writer.apply(
            exposureLevel: .explicitOnly,
            forSkillNamed: "helper",
            installations: [installation()]
        )

        let explicitConfiguration = try contents(of: configurationURL)
        let explicitPolicy = try contents(of: policyURL)
        XCTAssertTrue(explicitConfiguration.contains("# keep root comment"))
        XCTAssertTrue(explicitConfiguration.contains("# keep other entry"))
        XCTAssertTrue(explicitConfiguration.contains("# keep target comment"))
        XCTAssertTrue(explicitConfiguration.contains("/other/SKILL.md"))
        XCTAssertFalse(explicitConfiguration.contains(skillMarkdownPath))
        XCTAssertFalse(explicitConfiguration.contains("vendor ="))
        XCTAssertEqual(
            explicitPolicy,
            originalPolicy.replacingOccurrences(
                of: "allow_implicit_invocation: true # keep key comment",
                with: "allow_implicit_invocation: false # keep key comment"
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: configurationURL.appendingPathExtension("pagugu-backup")),
            Data(disabledConfiguration.utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: policyURL.appendingPathExtension("pagugu-backup")),
            Data(originalPolicy.utf8)
        )
        XCTAssertEqual(
            try writer.claimState(
                expecting: .explicitOnly,
                forSkillNamed: "other",
                installations: [SkillInstallation(
                    asFoundPath: "/other",
                    canonicalPath: "/other",
                    hosts: [.codex],
                    scope: .personal,
                    projectionType: .copy,
                    sourceMapping: nil
                )]
            ),
            .consistent,
            "用户级 Codex policy 的全 Skill 影响必须显式锁定"
        )

        try writer.apply(
            exposureLevel: .fullyExposed,
            forSkillNamed: "helper",
            installations: [installation()]
        )

        let exposedPolicy = try contents(of: policyURL)
        XCTAssertTrue(exposedPolicy.contains("# keep policy comment"))
        XCTAssertTrue(exposedPolicy.contains("display_name: OpenAI # keep unknown field"))
        XCTAssertTrue(exposedPolicy.contains("network: restricted # keep nested field"))
        XCTAssertTrue(exposedPolicy.contains("footer: keep"))
        XCTAssertTrue(exposedPolicy.contains(
            "allow_implicit_invocation: preserve-top-level # same-name unknown field"
        ))
        XCTAssertFalse(exposedPolicy.contains("  allow_implicit_invocation:"))
        XCTAssertEqual(
            try writer.claimState(
                expecting: .fullyExposed,
                forSkillNamed: "helper",
                installations: [installation()]
            ),
            .consistent
        )
        XCTAssertEqual(
            try Data(contentsOf: configurationURL.appendingPathExtension("pagugu-backup")),
            Data(explicitConfiguration.utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: policyURL.appendingPathExtension("pagugu-backup")),
            Data(explicitPolicy.utf8)
        )

        try writer.restoreConfiguration()

        XCTAssertEqual(try contents(of: configurationURL), explicitConfiguration)
        XCTAssertEqual(try contents(of: policyURL), explicitPolicy)
        XCTAssertEqual(
            try writer.claimState(
                expecting: .explicitOnly,
                forSkillNamed: "helper",
                installations: [installation()]
            ),
            .consistent
        )
        XCTAssertEqual(
            try writer.claimState(
                expecting: .fullyExposed,
                forSkillNamed: "helper",
                installations: [installation()]
            ),
            .divergent
        )
    }

    func testExternalEditFailsClosedAndManualEditProducesDivergence() throws {
        let externalBytes = Data("# host edit\nmodel = \"external\"\n".utf8)
        let configurationURL = try XCTUnwrap(configurationURL)
        let hostConfigWriter = HostConfigWriter(beforeCommit: {
            try externalBytes.write(to: configurationURL)
        })
        let writerDuringExternalChange = CodexConfigWriter(
            homeDirectory: homeDirectory,
            writer: hostConfigWriter
        )

        XCTAssertThrowsError(
            try writerDuringExternalChange.apply(
                exposureLevel: .fullyDisabled,
                forSkillNamed: "helper",
                installations: [installation()]
            )
        ) { error in
            XCTAssertEqual(error as? HostConfigWriterError, .externallyModified)
        }
        XCTAssertEqual(try Data(contentsOf: configurationURL), externalBytes)
        XCTAssertFalse(fileManager.fileExists(
            atPath: configurationURL.appendingPathExtension("pagugu-backup").path
        ))

        try write("policy:\n  allow_implicit_invocation: false\n", to: policyURL)
        let writer = CodexConfigWriter(homeDirectory: homeDirectory)
        XCTAssertEqual(
            try writer.claimState(
                expecting: .explicitOnly,
                forSkillNamed: "helper",
                installations: [installation()]
            ),
            .consistent
        )

        try write("policy:\n  allow_implicit_invocation: true\n", to: policyURL)
        XCTAssertEqual(
            try writer.claimState(
                expecting: .explicitOnly,
                forSkillNamed: "helper",
                installations: [installation()]
            ),
            .divergent
        )

        let sourcePolicyURL = skillDirectory.appendingPathComponent("agents/openai.yaml")
        try write("policy:\n  allow_implicit_invocation: false\n", to: sourcePolicyURL)
        XCTAssertThrowsError(
            try writer.apply(
                exposureLevel: .fullyExposed,
                forSkillNamed: "helper",
                installations: [installation()]
            )
        ) { error in
            XCTAssertEqual(error as? HostConfigWriterError, .effectiveConfigurationMismatch)
        }
        XCTAssertEqual(
            try writer.claimState(
                expecting: .fullyExposed,
                forSkillNamed: "helper",
                installations: [installation()]
            ),
            .divergent,
            "只读 Installation policy 阻止目标档位时不得冒充成功"
        )
    }

    private func installation() -> SkillInstallation {
        SkillInstallation(
            asFoundPath: skillDirectory.path,
            canonicalPath: skillDirectory.path,
            hosts: [.codex],
            scope: .personal,
            projectionType: .copy,
            sourceMapping: nil
        )
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func write(_ contents: String, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
