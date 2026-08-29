import XCTest
@testable import Pagugu

final class DiscoveryPiRootsTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    func testDefaultPersonalRootsIncludePiAndSharedAgentsRoots() {
        let roots = Set(Discovery.personalSkillRoots)

        XCTAssertTrue(roots.contains(("~/.pi/agent/skills" as NSString).expandingTildeInPath))
        XCTAssertTrue(roots.contains(("~/.agents/skills" as NSString).expandingTildeInPath))
        XCTAssertEqual(roots.count, 4)
        XCTAssertEqual(Set(HostProfiles.all.map(\.host)), Set(AgentHost.allCases))
        XCTAssertEqual(Set(AgentHost.allCases), [.claude, .codex, .pi])
        XCTAssertTrue(HostProfiles.pi.projectRootRelativePaths.isEmpty)
        XCTAssertTrue(
            HostProfiles.hosts(for: "~/Code/repo/.pi/agent/skills/pi-only", scope: .project).isEmpty,
            "Pi 当前没有 Project Skill Root，不能复用 Personal Root 规则"
        )
    }

    func testPiAndSharedRootsProduceCorrectHostInstallations() throws {
        let piRoot = temporaryDirectory.appendingPathComponent("home/.pi/agent/skills")
        let sharedRoot = temporaryDirectory.appendingPathComponent("home/.agents/skills")
        try writeSkill(at: piRoot.appendingPathComponent("pi-only"), name: "pi-only")
        try writeSkill(at: sharedRoot.appendingPathComponent("shared"), name: "shared")

        let result = Discovery.scanPersonalRoots([piRoot.path, sharedRoot.path])
        let contents = SkillDirectory.contents(from: result)
        let itemsByName = Dictionary(uniqueKeysWithValues: contents.unattributedInstallations.map {
            ($0.displayName, $0)
        })

        XCTAssertEqual(itemsByName["pi-only"]?.hosts, [.pi])
        XCTAssertEqual(itemsByName["shared"]?.hosts, [.codex, .pi])
    }

    private func writeSkill(at directory: URL, name: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: Discovery test\n---\n".write(
            to: directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}
