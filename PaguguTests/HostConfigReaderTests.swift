import XCTest
@testable import Pagugu

final class HostConfigReaderTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var homeDirectory: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        homeDirectory = temporaryDirectory.appendingPathComponent("home")
        try! fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    func testReadsClaudeCodexAndPiLevelsWithCapabilityGaps() throws {
        let projectSkill = temporaryDirectory.appendingPathComponent("project/.claude/skills/helper")
        let codexSkill = homeDirectory.appendingPathComponent(".agents/skills/helper")
        let piSkill = homeDirectory.appendingPathComponent(".pi/agent/skills/helper")
        try write(
            #"{"skillOverrides":{"helper":"on"}}"#,
            to: homeDirectory.appendingPathComponent(".claude/settings.json")
        )
        try write(
            #"{"skillOverrides":{"helper":"name-only"}}"#,
            to: temporaryDirectory.appendingPathComponent("project/.claude/settings.json")
        )
        try write(
            """
            [[skills.config]]
            path = "\(codexSkill.appendingPathComponent("SKILL.md").path)"
            enabled = false
            """,
            to: homeDirectory.appendingPathComponent(".codex/config.toml")
        )
        try write(
            """
            policy:
              allow_implicit_invocation: false
            """,
            to: homeDirectory.appendingPathComponent(".codex/agents/openai.yaml")
        )
        try write(
            #"{"hiddenSkills":["helper"],"disabledSkills":[]}"#,
            to: homeDirectory.appendingPathComponent(".pi/agent/pagugu/visibility.json")
        )

        let reader = HostConfigReader(homeDirectory: homeDirectory)
        let surfaces = reader.invocationSurfaces(
            skillName: "helper",
            installations: [
                installation(path: projectSkill, host: .claude, scope: .project),
                installation(path: codexSkill, host: .codex, scope: .personal),
                installation(path: piSkill, host: .pi, scope: .personal),
            ]
        )

        XCTAssertEqual(surface(for: .claude, in: surfaces).state, .level(.nameOnly))
        XCTAssertEqual(surface(for: .codex, in: surfaces).state, .level(.fullyDisabled))
        XCTAssertEqual(surface(for: .pi, in: surfaces).state, .level(.explicitOnly))
        XCTAssertTrue(surface(for: .claude, in: surfaces).unsupportedLevels.isEmpty)
        XCTAssertEqual(surface(for: .codex, in: surfaces).unsupportedLevels, [.nameOnly])
        XCTAssertEqual(surface(for: .pi, in: surfaces).unsupportedLevels, [.nameOnly])

        let yamlOnly = reader.invocationSurfaces(
            skillName: "yaml-only",
            installations: [
                installation(
                    path: homeDirectory.appendingPathComponent(".agents/skills/yaml-only"),
                    host: .codex,
                    scope: .personal
                ),
            ]
        )
        XCTAssertEqual(surface(for: .codex, in: yamlOnly).state, .level(.explicitOnly))
    }

    func testClaudeProjectOverridesUserAndMultipleContextsUseMostRestrictiveLevel() throws {
        let projectSkill = temporaryDirectory.appendingPathComponent("project/.claude/skills/deploy")
        try write(
            #"{"skillOverrides":{"deploy":"off"}}"#,
            to: homeDirectory.appendingPathComponent(".claude/settings.json")
        )
        try write(
            #"{"skillOverrides":{"deploy":"on"}}"#,
            to: temporaryDirectory.appendingPathComponent("project/.claude/settings.json")
        )
        let reader = HostConfigReader(homeDirectory: homeDirectory)

        var surfaces = reader.invocationSurfaces(
            skillName: "deploy",
            installations: [installation(path: projectSkill, host: .claude, scope: .project)]
        )
        XCTAssertEqual(surface(for: .claude, in: surfaces).state, .level(.fullyExposed))

        let personalSkill = homeDirectory.appendingPathComponent(".claude/skills/deploy")
        surfaces = reader.invocationSurfaces(
            skillName: "deploy",
            installations: [
                installation(path: personalSkill, host: .claude, scope: .personal),
                installation(path: projectSkill, host: .claude, scope: .project),
            ]
        )
        XCTAssertEqual(surface(for: .claude, in: surfaces).state, .level(.fullyDisabled))
    }

    func testMissingFilesDefaultToFullyExposedAndMalformedFilesFailClosed() throws {
        let installations = [
            installation(
                path: homeDirectory.appendingPathComponent(".claude/skills/helper"),
                host: .claude,
                scope: .personal
            ),
            installation(
                path: homeDirectory.appendingPathComponent(".agents/skills/helper"),
                host: .codex,
                scope: .personal
            ),
            installation(
                path: homeDirectory.appendingPathComponent(".pi/agent/skills/helper"),
                host: .pi,
                scope: .personal
            ),
        ]
        let reader = HostConfigReader(homeDirectory: homeDirectory)

        var surfaces = reader.invocationSurfaces(skillName: "helper", installations: installations)
        XCTAssertTrue(surfaces.allSatisfy { $0.state == .level(.fullyExposed) })

        try write("{", to: homeDirectory.appendingPathComponent(".claude/settings.json"))
        try write(
            """
            [[skills.config]]
            name = "helper"
            enabled = "sometimes"
            """,
            to: homeDirectory.appendingPathComponent(".codex/config.toml")
        )
        try write(
            """
            policy:
              allow_implicit_invocation: sometimes
            """,
            to: homeDirectory.appendingPathComponent(".codex/agents/openai.yaml")
        )
        try write(
            #"{"hiddenSkills":["helper"],"disabledSkills":["helper"]}"#,
            to: homeDirectory.appendingPathComponent(".pi/agent/pagugu/visibility.json")
        )

        surfaces = reader.invocationSurfaces(skillName: "helper", installations: installations)
        XCTAssertEqual(surface(for: .claude, in: surfaces).state, .readFailed)
        XCTAssertEqual(surface(for: .codex, in: surfaces).state, .readFailed)
        XCTAssertEqual(surface(for: .pi, in: surfaces).state, .readFailed)

        try write(
            """
            [[skills.config]]
            name = "helper"
            enabled = false
            """,
            to: homeDirectory.appendingPathComponent(".codex/config.toml")
        )
        surfaces = reader.invocationSurfaces(skillName: "helper", installations: installations)
        XCTAssertEqual(
            surface(for: .codex, in: surfaces).state,
            .readFailed,
            "全禁用事实也不能掩盖同一宿主的损坏 YAML"
        )
    }

    func testLegacyReadOnlyPiPlaceholderSchemaIsRejectedByCleanBreak() throws {
        let piSkill = homeDirectory.appendingPathComponent(".pi/agent/skills/helper")
        try write(
            #"{"skills":{"helper":"explicitOnly"}}"#,
            to: homeDirectory.appendingPathComponent(".pi/agent/pagugu/visibility.json")
        )
        let surfaces = HostConfigReader(homeDirectory: homeDirectory).invocationSurfaces(
            skillName: "helper",
            installations: [installation(path: piSkill, host: .pi, scope: .personal)]
        )

        XCTAssertEqual(surface(for: .pi, in: surfaces).state, .readFailed)
    }

    func testInaccessibleExistingConfigIsReadFailure() throws {
        let piSkill = homeDirectory.appendingPathComponent(".pi/agent/skills/helper")
        let piURL = homeDirectory.appendingPathComponent(".pi/agent/pagugu/visibility.json")
        try write(#"{"hiddenSkills":[],"disabledSkills":[]}"#, to: piURL)
        let piDirectoryURL = piURL.deletingLastPathComponent()
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: piDirectoryURL.path)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: piDirectoryURL.path)
        }

        let surfaces = HostConfigReader(homeDirectory: homeDirectory).invocationSurfaces(
            skillName: "helper",
            installations: [installation(path: piSkill, host: .pi, scope: .personal)]
        )
        XCTAssertEqual(surface(for: .pi, in: surfaces).state, .readFailed)
    }

    private func installation(
        path: URL,
        host: AgentHost,
        scope: HostSkillScope
    ) -> SkillInstallation {
        SkillInstallation(
            asFoundPath: path.path,
            canonicalPath: path.path,
            hosts: [host],
            scope: scope,
            projectionType: .copy,
            sourceMapping: nil
        )
    }

    private func surface(
        for host: AgentHost,
        in surfaces: [HostInvocationSurface]
    ) -> HostInvocationSurface {
        try! XCTUnwrap(surfaces.first { $0.host == host })
    }

    private func write(_ contents: String, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
