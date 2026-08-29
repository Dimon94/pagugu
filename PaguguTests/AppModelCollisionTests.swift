import XCTest
@testable import Pagugu

final class AppModelCollisionTests: XCTestCase {
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

    @MainActor
    func testAppModelPublishesCollisionBadgeAndHostDiagnostics() async throws {
        let claudeRoot = temporaryDirectory.appendingPathComponent("home/.claude/skills")
        let agentsRoot = temporaryDirectory.appendingPathComponent("home/.agents/skills")
        let codexRoot = temporaryDirectory.appendingPathComponent("home/.codex/skills")
        let piRoot = temporaryDirectory.appendingPathComponent("home/.pi/agent/skills")
        let projectRoot = temporaryDirectory.appendingPathComponent("projects")
        let personalClaudeSkill = claudeRoot.appendingPathComponent("personal-helper")

        try writeSkill(at: personalClaudeSkill, name: " Helper ", variant: "personal-claude")
        try writeSkill(at: agentsRoot.appendingPathComponent("shared-helper"), name: "helper", variant: "agents")
        try writeSkill(at: codexRoot.appendingPathComponent("codex-helper"), name: "HELPER", variant: "codex")
        try writeSkill(at: piRoot.appendingPathComponent("pi-helper"), name: "helper", variant: "pi")
        try writeSkill(
            at: projectRoot.appendingPathComponent("demo/.claude/skills/project-helper"),
            name: "helper",
            variant: "project-claude"
        )

        let model = AppModel(
            personalRoots: [claudeRoot.path, agentsRoot.path, codexRoot.path, piRoot.path],
            persistence: Persistence(directoryURL: temporaryDirectory.appendingPathComponent("data"))
        )
        await model.start()
        await model.addProjectScanRoot(projectRoot)

        let personalItem = try XCTUnwrap(model.readModel.unattributedInstallations.first { item in
            item.installations.contains { $0.asFoundPath == personalClaudeSkill.path }
        })
        let collision = try XCTUnwrap(
            model.readModel.nameCollision(forUnattributedInstallationID: personalItem.id)
        )

        XCTAssertEqual(collision.badgeText, "同名共存组 · 5")
        XCTAssertEqual(
            collision.diagnosticTexts,
            [
                "Claude Code：Personal Skill 覆盖同名 Project Skill；Project Skill 被遮蔽。",
                "Codex：多个同名 Skill 歧义共存。",
                "Pi：多个同名 Skill 歧义共存。",
            ]
        )
    }

    func testCollisionProjectionDoesNotChangeIdentityOrCheckoutEligibility() throws {
        let firstSourceKey = SkillSourceKey.remoteURL("example.com/owner/first")
        let secondSourceKey = SkillSourceKey.remoteURL("example.com/owner/second")
        let firstIdentity = SkillIdentity(sourceKey: firstSourceKey, repositoryRelativePath: "skills/helper")
        let secondIdentity = SkillIdentity(sourceKey: secondSourceKey, repositoryRelativePath: "skills/helper")
        let firstCheckoutPath = "/repos/first"

        let firstSource = sourceItem(
            key: firstSourceKey,
            identity: firstIdentity,
            canonicalPath: firstCheckoutPath + "/skills/helper",
            location: HostSkillLocation(host: .claude, scope: .personal)
        )
        let secondSource = sourceItem(
            key: secondSourceKey,
            identity: secondIdentity,
            canonicalPath: "/repos/second/skills/helper",
            location: HostSkillLocation(host: .claude, scope: .project)
        )
        let facts = CheckoutGitFacts(
            checkoutPath: firstCheckoutPath,
            gitCommonDirectory: firstCheckoutPath + "/.git",
            head: .branch(name: "main", sha: "aaaa"),
            originRemoteURL: "https://example.com/owner/first.git",
            upstream: GitUpstream(
                ref: "origin/main",
                remoteName: "origin",
                remoteURL: "https://example.com/owner/first.git"
            ),
            dirty: .clean,
            relativePosition: .behindOnly(1),
            worktrees: [GitWorktree(path: firstCheckoutPath, branch: "main")],
            siblingBranchConflict: false,
            inspectionFailure: nil
        )
        let readModel = SkillReadModel(
            sources: [firstSource, secondSource],
            unattributedInstallations: [],
            issues: [],
            scanOutcome: .complete,
            checkoutCardsBySource: [
                firstSourceKey: [CheckoutCardReadModel(facts: facts, state: .updateAvailable)]
            ]
        )

        XCTAssertNotEqual(firstIdentity, secondIdentity, "同名异源保持两个 Skill Identity")
        XCTAssertNotNil(readModel.nameCollision(for: firstIdentity))
        XCTAssertEqual(readModel.checkoutCards(for: firstSourceKey).map(\.state), [.updateAvailable])
    }

    @MainActor
    func testAppModelUsesInstallationDirectoryWhenFrontmatterNameIsMissing() async throws {
        let agentsRoot = temporaryDirectory.appendingPathComponent("home/.agents/skills")
        let piRoot = temporaryDirectory.appendingPathComponent("home/.pi/agent/skills")
        let fallbackSkill = piRoot.appendingPathComponent("helper")

        try writeSkill(at: agentsRoot.appendingPathComponent("shared-helper"), name: "HELPER", variant: "agents")
        try writeSkillWithoutName(at: fallbackSkill, variant: "pi-without-name")

        let model = AppModel(
            personalRoots: [agentsRoot.path, piRoot.path],
            persistence: Persistence(directoryURL: temporaryDirectory.appendingPathComponent("data"))
        )
        await model.start()

        let fallbackItem = try XCTUnwrap(model.readModel.unattributedInstallations.first { item in
            item.installations.contains { $0.asFoundPath == fallbackSkill.path }
        })
        XCTAssertEqual(fallbackItem.displayName, "helper")
        XCTAssertFalse(model.readModel.issues.contains { $0.path == fallbackSkill.path })

        let collision = try XCTUnwrap(
            model.readModel.nameCollision(forUnattributedInstallationID: fallbackItem.id)
        )
        XCTAssertEqual(collision.badgeText, "同名共存组 · 2")
        XCTAssertEqual(collision.diagnosticTexts, ["Pi：多个同名 Skill 歧义共存。"])
    }

    private func sourceItem(
        key: SkillSourceKey,
        identity: SkillIdentity,
        canonicalPath: String,
        location: HostSkillLocation
    ) -> SkillSourceItem {
        let installation = SkillInstallation(
            asFoundPath: canonicalPath,
            canonicalPath: canonicalPath,
            hosts: [location.host],
            scope: location.scope,
            projectionType: .repositorySelf,
            sourceMapping: nil
        )
        let checkoutPath = ((canonicalPath as NSString).deletingLastPathComponent as NSString)
            .deletingLastPathComponent
        return SkillSourceItem(
            id: key,
            displayName: key.displayString,
            skills: [
                SkillDirectoryEntry(
                    id: identity,
                    displayName: "helper",
                    canonicalPath: canonicalPath,
                    installations: [installation]
                )
            ],
            checkouts: [SkillSourceCheckout(canonicalPath: checkoutPath)]
        )
    }

    private func writeSkill(at directory: URL, name: String, variant: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: \(variant)\n---\n".write(
            to: directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeSkillWithoutName(at directory: URL, variant: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\ndescription: \(variant)\n---\n".write(
            to: directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}
