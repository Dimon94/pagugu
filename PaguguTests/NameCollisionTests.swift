import XCTest
@testable import Pagugu

final class NameCollisionTests: XCTestCase {
    func testProfilesDiagnoseNormalizedNameCollisionGroup() throws {
        let candidates = [
            NameCollisionCandidate(
                id: "personal",
                frontmatterName: "  Helper ",
                installationDirectoryName: "personal-directory",
                locations: [
                    HostSkillLocation(host: .claude, scope: .personal),
                    HostSkillLocation(host: .codex, scope: .personal),
                    HostSkillLocation(host: .pi, scope: .personal),
                ]
            ),
            NameCollisionCandidate(
                id: "project",
                frontmatterName: "helper",
                installationDirectoryName: "project-directory",
                locations: [
                    HostSkillLocation(host: .claude, scope: .project),
                    HostSkillLocation(host: .codex, scope: .project),
                ]
            ),
            NameCollisionCandidate(
                id: "pi-fallback",
                frontmatterName: nil,
                installationDirectoryName: "HELPER",
                locations: [HostSkillLocation(host: .pi, scope: .personal)]
            ),
            NameCollisionCandidate(
                id: "unique",
                frontmatterName: "unique",
                installationDirectoryName: "unique",
                locations: [HostSkillLocation(host: .claude, scope: .personal)]
            ),
        ]

        let groups = NameCollisionEngine.groups(from: candidates)
        let group = try XCTUnwrap(groups.first)

        XCTAssertEqual(groups.count, 1, "只有两个及以上同名条目才形成同名共存组")
        XCTAssertEqual(group.normalizedName, "helper")
        XCTAssertEqual(group.memberIDs, ["personal", "pi-fallback", "project"])
        XCTAssertEqual(group.diagnostics.map(\.host), [.claude, .codex, .pi])
        XCTAssertEqual(group.diagnostics.map(\.kind), [.shadowed, .ambiguous, .ambiguous])
        XCTAssertEqual(
            group.diagnostics.map(\.message),
            [
                "Claude Code：Personal Skill 覆盖同名 Project Skill；Project Skill 被遮蔽。",
                "Codex：多个同名 Skill 歧义共存。",
                "Pi：多个同名 Skill 歧义共存。",
            ]
        )
    }
}
