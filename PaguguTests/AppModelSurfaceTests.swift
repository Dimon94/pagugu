import XCTest
@testable import Pagugu

final class AppModelSurfaceTests: XCTestCase {
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

    @MainActor
    func testAppModelPublishesAndRefreshesInvocationSurfaceProjection() async throws {
        let repository = temporaryDirectory.appendingPathComponent("repository")
        let sourceSkill = repository.appendingPathComponent("skills/helper")
        try fileManager.createDirectory(
            at: repository.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try writeSkill(at: sourceSkill)

        let claudeSkill = homeDirectory.appendingPathComponent(".claude/skills/helper")
        let codexSkill = homeDirectory.appendingPathComponent(".agents/skills/helper")
        let piSkill = homeDirectory.appendingPathComponent(".pi/agent/skills/helper")
        for installation in [claudeSkill, codexSkill, piSkill] {
            try fileManager.createDirectory(
                at: installation.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createSymbolicLink(at: installation, withDestinationURL: sourceSkill)
        }
        try write(
            #"{"skillOverrides":{"helper":"user-invocable-only"}}"#,
            to: homeDirectory.appendingPathComponent(".claude/settings.json")
        )
        try write(
            """
            [[skills.config]]
            name = "helper"
            enabled = false
            """,
            to: homeDirectory.appendingPathComponent(".codex/config.toml")
        )
        try write(
            #"{"skills":{"helper":"fullyDisabled"}}"#,
            to: homeDirectory.appendingPathComponent(".pi/agent/pagugu/visibility.json")
        )

        let model = AppModel(
            personalRoots: [
                homeDirectory.appendingPathComponent(".claude/skills").path,
                homeDirectory.appendingPathComponent(".agents/skills").path,
                homeDirectory.appendingPathComponent(".pi/agent/skills").path,
            ],
            persistence: Persistence(directoryURL: temporaryDirectory.appendingPathComponent("data")),
            hostConfigReader: HostConfigReader(homeDirectory: homeDirectory)
        )
        await model.start()

        let skill = try XCTUnwrap(model.readModel.sources.first?.skills.first)
        var surfaces = model.readModel.invocationSurfaces(for: skill.id)
        XCTAssertEqual(surfaces.map(\.host), [.claude, .codex, .pi])
        XCTAssertEqual(surface(for: .claude, in: surfaces).state, .level(.explicitOnly))
        XCTAssertEqual(surface(for: .codex, in: surfaces).state, .level(.fullyDisabled))
        XCTAssertEqual(surface(for: .pi, in: surfaces).state, .unsupported(.fullyDisabled))

        try write(
            #"{"skillOverrides":{"helper":"off"}}"#,
            to: homeDirectory.appendingPathComponent(".claude/settings.json")
        )
        await model.rescan()

        surfaces = model.readModel.invocationSurfaces(for: skill.id)
        XCTAssertEqual(surface(for: .claude, in: surfaces).state, .level(.fullyDisabled))
    }

    private func surface(
        for host: AgentHost,
        in surfaces: [HostInvocationSurface]
    ) -> HostInvocationSurface {
        try! XCTUnwrap(surfaces.first { $0.host == host })
    }

    private func writeSkill(at directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: helper\ndescription: Test\n---\n".write(
            to: directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func write(_ contents: String, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
