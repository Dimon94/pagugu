import XCTest
@testable import Pagugu

// Skill Source Key 规范化表测试（ADR-0001 §1：忽略协议与认证、去 .git、host 小写、路径大小写不归一；fork 是不同来源）。
final class IdentityTests: XCTestCase {
    func testSourceKeyNormalizationUnifiesProtocolAndAuthForms() {
        let forms = [
            "https://github.com/Dimon94/pagugu.git",
            "http://github.com/Dimon94/pagugu.git",
            "git@github.com:Dimon94/pagugu.git",
            "ssh://git@github.com/Dimon94/pagugu.git",
            "git://github.com/Dimon94/pagugu",
            "https://dimon:token@github.com/Dimon94/pagugu/",
        ]
        let keys = forms.map { SkillSourceKey.normalize(remoteURL: $0) }
        XCTAssertEqual(keys, Array(repeating: .remoteURL("github.com/Dimon94/pagugu"), count: forms.count))
    }

    func testSourceKeyNormalizationLowercasesHostButPreservesPathCase() {
        XCTAssertEqual(
            SkillSourceKey.normalize(remoteURL: "HTTPS://GITHUB.COM/Dimon94/PaGuGu.GIT"),
            .remoteURL("github.com/Dimon94/PaGuGu")
        )
    }

    func testSourceKeyNormalizationTreatsForkAsDistinctSource() {
        let upstream = SkillSourceKey.normalize(remoteURL: "https://github.com/Owner/repo.git")
        let fork = SkillSourceKey.normalize(remoteURL: "https://github.com/Dimon94/repo.git")
        XCTAssertNotEqual(upstream, fork)
    }

    func testSourceKeyNormalizationRejectsUnusableInput() {
        XCTAssertNil(SkillSourceKey.normalize(remoteURL: ""))
        XCTAssertNil(SkillSourceKey.normalize(remoteURL: "not a url"))
        XCTAssertNil(SkillSourceKey.normalize(remoteURL: "https://github.com/"))
    }

    // MARK: - Host Attribution（#3 resolution §6）

    func testHostAttributionClaudeCode() {
        let hosts = HostAttribution.hosts(for: "~/.claude/skills/my-skill")
        XCTAssertEqual(hosts, [.claude])
    }

    func testHostAttributionCodex() {
        let hosts = HostAttribution.hosts(for: "~/.codex/skills/my-skill")
        XCTAssertEqual(hosts, [.codex])
    }

    func testHostAttributionAgentsGoesToCodex() {
        // .agents/skills → Codex（#3 resolution §6）
        let hosts = HostAttribution.hosts(for: "~/.agents/skills/my-skill")
        XCTAssertEqual(hosts, [.codex])
    }

    func testHostAttributionUnknownPathReturnsEmpty() {
        let hosts = HostAttribution.hosts(for: "~/random/path/skills")
        XCTAssertTrue(hosts.isEmpty)
    }

    // MARK: - Skill 目录聚合（ADR-0001 §3：列表条目 = Skill，Installation 聚合为属性）

    func testDirectoryEntriesAggregateSameCanonicalPathIntoOneSkill() {
        // 跨 root 发现同一 canonical path（如 .claude 和 .agents 各自有独立副本或 symlink 指向同一目标）
        // → 聚合为 1 个 Skill 条目、2 个 Installation（ADR-0001 §3）
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/.claude/skills/git-commit",
                canonicalPath: "/Users/dimon/.claude/skills/git-commit",
                name: "git-commit"
            ),
            DiscoveredSkill(
                asFoundPath: "~/.agents/skills/git-commit",
                canonicalPath: "/Users/dimon/.claude/skills/git-commit", // 同一 canonical path
                name: "git-commit"
            ),
        ]
        let result = ScanResult(outcome: .complete, skills: skills, issues: [])
        let entries = SkillDirectory.entries(from: result)

        XCTAssertEqual(entries.count, 1, "同一 canonical path 聚合为 1 个 Skill")
        XCTAssertEqual(entries.first?.installations.count, 2, "2 个 as-found 路径 = 2 个 Installation")
        XCTAssertEqual(
            entries.first?.installations.flatMap(\.hosts).sorted(),
            [.claude, .codex],
            "Claude 和 Codex 宿主都点亮"
        )
    }

    func testDirectoryEntriesCarryHostAttributionPerInstallation() {
        // Discovery 层已按 canonical path 去重；Identity 层按 (sourceKey, path) 聚合。
        // #15 阶段每个 DiscoveredSkill 对应独立本地来源，各自成行。
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/.claude/skills/git-commit",
                canonicalPath: "/Users/dimon/.claude/skills/git-commit",
                name: "git-commit"
            ),
            DiscoveredSkill(
                asFoundPath: "~/.codex/skills/git-commit",
                canonicalPath: "/Users/dimon/.codex/skills/git-commit",
                name: "git-commit"
            ),
        ]
        let result = ScanResult(outcome: .complete, skills: skills, issues: [])
        let entries = SkillDirectory.entries(from: result)

        XCTAssertEqual(entries.count, 2, "不同 canonical path = 不同来源 = 各自单列")
        let claudeEntry = entries.first { $0.installations.first?.hosts.contains(.claude) == true }
        let codexEntry = entries.first { $0.installations.first?.hosts.contains(.codex) == true }
        XCTAssertNotNil(claudeEntry)
        XCTAssertNotNil(codexEntry)
        XCTAssertEqual(claudeEntry?.installations.first?.asFoundPath, "~/.claude/skills/git-commit")
        XCTAssertEqual(codexEntry?.installations.first?.asFoundPath, "~/.codex/skills/git-commit")
    }

    func testDirectoryEntriesSeparateSameNameDifferentSource() {
        // 同名异源：name 相同但 canonical path 不同 → 各自单列（ADR-0001 §5）
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/.claude/skills/helper",
                canonicalPath: "/Users/dimon/.claude/skills/helper",
                name: "helper"
            ),
            DiscoveredSkill(
                asFoundPath: "~/.agents/skills/helper",
                canonicalPath: "/Users/dimon/other-repo/skills/helper",
                name: "helper"
            ),
        ]
        let result = ScanResult(outcome: .complete, skills: skills, issues: [])
        let entries = SkillDirectory.entries(from: result)

        XCTAssertEqual(entries.count, 2, "same name but different canonical path → 2 entries")
        XCTAssertEqual(Set(entries.map(\.displayName)), ["helper"])
    }

    func testDirectoryEntriesMarkSymlinkInstallations() {
        let skills = [
            DiscoveredSkill(
                asFoundPath: "~/.claude/skills/real-skill",
                canonicalPath: "/Users/dimon/.claude/skills/real-skill",
                name: "real-skill"
            ),
            DiscoveredSkill(
                asFoundPath: "~/.agents/skills/linked-skill",
                canonicalPath: "/Users/dimon/.claude/skills/real-skill", // symlink resolves to same canonical
                name: "linked-skill"
            ),
        ]
        let result = ScanResult(outcome: .complete, skills: skills, issues: [])
        let entries = SkillDirectory.entries(from: result)

        // 同一 canonical path 聚合为 1 个条目，2 个 Installation
        XCTAssertEqual(entries.count, 1)
        let entry = try! XCTUnwrap(entries.first)
        XCTAssertEqual(entry.installations.count, 2)

        let linked = entry.installations.first { $0.asFoundPath == "~/.agents/skills/linked-skill" }
        XCTAssertEqual(linked?.isSymlink, true, "asFound ≠ canonical → isSymlink = true")
        let real = entry.installations.first { $0.asFoundPath == "~/.claude/skills/real-skill" }
        XCTAssertEqual(real?.isSymlink, false, "asFound == canonical → isSymlink = false")
    }
}
