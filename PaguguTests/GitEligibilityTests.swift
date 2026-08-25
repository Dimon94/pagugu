import Darwin
import XCTest
@testable import Pagugu

final class GitEligibilityTests: XCTestCase {
    private let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testCheckoutStatePrecedenceMatchesADR0004() {
        let dirty = GitDirtyFacts(staged: true)
        let cases: [(CheckoutGitFacts, SkillSourceKey, CheckoutGitState)] = [
            (facts(inspectionFailure: .notAWorkTree), .localPath("/repo"), .inspectionFailed),
            (facts(head: .detached(sha: "head")), .localPath("/repo"), .noRemote),
            (facts(head: .detached(sha: "head"), upstream: nil), sourceKey, .detached),
            (facts(upstream: nil), sourceKey, .noUpstream),
            (facts(upstream: GitUpstream(ref: "fork/main", remoteName: "fork", remoteURL: "https://example.com/fork/skills.git")), sourceKey, .upstreamMismatch),
            (facts(relativePosition: .unknown, siblingBranchConflict: true), sourceKey, .siblingConflict),
            (facts(dirty: dirty, relativePosition: .unknown), sourceKey, .checkUnknown),
            (facts(dirty: dirty, relativePosition: .diverged(ahead: 1, behind: 1)), sourceKey, .dirty),
            (facts(relativePosition: .diverged(ahead: 1, behind: 1)), sourceKey, .diverged),
            (facts(relativePosition: .aheadOnly(1)), sourceKey, .aheadOnly),
            (facts(relativePosition: .behindOnly(1)), sourceKey, .updateAvailable),
            (facts(relativePosition: .upToDate), sourceKey, .upToDate),
        ]

        XCTAssertEqual(cases.map { CheckoutEligibility.evaluate(facts: $0.0, sourceKey: $0.1) }, cases.map { $0.2 })
    }

    func testEveryCheckoutStateHasStableCodeChineseNameAndRecovery() {
        XCTAssertEqual(
            CheckoutGitState.allCases.map(\.rawValue),
            [
                "inspection-failed", "no-remote", "detached", "no-upstream",
                "upstream-mismatch", "sibling-conflict", "check-unknown", "dirty",
                "diverged", "ahead-only", "update-available", "up-to-date",
            ]
        )
        for state in CheckoutGitState.allCases {
            XCTAssertFalse(state.displayName.isEmpty)
            XCTAssertFalse(state.recoveryDirection.isEmpty)
        }
    }

    func testRealGitScratchRepositoriesReachAllTwelveStates() async throws {
        let client = GitClient()

        let invalid = await client.inspectCheckout(
            at: scratch.appendingPathComponent("missing").path,
            scope: .localOnly
        )
        XCTAssertEqual(CheckoutEligibility.evaluate(facts: invalid, sourceKey: .localPath(invalid.checkoutPath)), .inspectionFailed)

        let local = try makeRepository(named: "local", withRemote: false)
        let localFacts = await client.inspectCheckout(at: local.repo.path, scope: .localOnly)
        XCTAssertEqual(CheckoutEligibility.evaluate(facts: localFacts, sourceKey: .localPath(local.repo.path)), .noRemote)

        let detached = try makeRepository(named: "detached")
        try git(["checkout", "--detach"], at: detached.repo)
        let detachedState = try await state(of: detached, client: client)
        XCTAssertEqual(detachedState, .detached)

        let noUpstream = try makeRepository(named: "no-upstream")
        try git(["branch", "--unset-upstream"], at: noUpstream.repo)
        let noUpstreamState = try await state(of: noUpstream, client: client)
        XCTAssertEqual(noUpstreamState, .noUpstream)

        let mismatch = try makeRepository(named: "mismatch")
        let mismatchFacts = await client.inspectCheckout(at: mismatch.repo.path, scope: .afterSuccessfulCheck)
        XCTAssertEqual(
            CheckoutEligibility.evaluate(facts: mismatchFacts, sourceKey: .remoteURL("example.com/other/source")),
            .upstreamMismatch
        )

        let sibling = try makeRepository(named: "sibling")
        let siblingPath = scratch.appendingPathComponent("sibling-linked")
        try git(["worktree", "add", "-f", siblingPath.path, "main"], at: sibling.repo)
        let siblingState = try await state(of: sibling, client: client)
        XCTAssertEqual(siblingState, .siblingConflict)

        let unknown = try makeRepository(named: "unknown")
        let unknownFacts = await client.inspectCheckout(at: unknown.repo.path, scope: .localOnly)
        XCTAssertEqual(CheckoutEligibility.evaluate(facts: unknownFacts, sourceKey: try sourceKey(of: unknown)), .checkUnknown)

        let dirty = try makeRepository(named: "dirty")
        try write("changed", to: dirty.repo.appendingPathComponent("tracked.txt"))
        let dirtyState = try await state(of: dirty, client: client)
        XCTAssertEqual(dirtyState, .dirty)

        let diverged = try makeRepository(named: "diverged")
        try commitChange("local", in: diverged.repo)
        try advanceRemote(diverged)
        try git(["fetch", "origin"], at: diverged.repo)
        let divergedState = try await state(of: diverged, client: client)
        XCTAssertEqual(divergedState, .diverged)

        let ahead = try makeRepository(named: "ahead")
        try commitChange("local", in: ahead.repo)
        let aheadState = try await state(of: ahead, client: client)
        XCTAssertEqual(aheadState, .aheadOnly)

        let behind = try makeRepository(named: "behind")
        try advanceRemote(behind)
        try git(["fetch", "origin"], at: behind.repo)
        let behindState = try await state(of: behind, client: client)
        XCTAssertEqual(behindState, .updateAvailable)

        let current = try makeRepository(named: "current")
        let currentState = try await state(of: current, client: client)
        XCTAssertEqual(currentState, .upToDate)
    }

    func testStrictDirtyCoversEveryRequiredKindAndIgnoresIgnoredFiles() async throws {
        let client = GitClient()

        let staged = try makeRepository(named: "dirty-staged")
        try write("staged", to: staged.repo.appendingPathComponent("tracked.txt"))
        try git(["add", "tracked.txt"], at: staged.repo)
        let stagedFacts = await client.inspectCheckout(at: staged.repo.path, scope: .afterSuccessfulCheck)
        XCTAssertTrue(stagedFacts.dirty.staged)

        let unstaged = try makeRepository(named: "dirty-unstaged")
        try write("unstaged", to: unstaged.repo.appendingPathComponent("tracked.txt"))
        let unstagedFacts = await client.inspectCheckout(at: unstaged.repo.path, scope: .afterSuccessfulCheck)
        XCTAssertTrue(unstagedFacts.dirty.unstaged)

        let untracked = try makeRepository(named: "dirty-untracked")
        try write("new", to: untracked.repo.appendingPathComponent("new.txt"))
        let untrackedFacts = await client.inspectCheckout(at: untracked.repo.path, scope: .afterSuccessfulCheck)
        XCTAssertTrue(untrackedFacts.dirty.untracked)

        let unmerged = try makeRepository(named: "dirty-unmerged")
        try git(["checkout", "-b", "side"], at: unmerged.repo)
        try commitChange("side", in: unmerged.repo)
        try git(["checkout", "main"], at: unmerged.repo)
        try commitChange("main", in: unmerged.repo)
        _ = try git(["merge", "side"], at: unmerged.repo, acceptedExitCodes: [0, 1])
        let unmergedFacts = await client.inspectCheckout(at: unmerged.repo.path, scope: .afterSuccessfulCheck)
        XCTAssertTrue(unmergedFacts.dirty.unmerged)

        let parent = try makeRepository(named: "dirty-submodule")
        let child = try makeRepository(named: "submodule-child", withRemote: false)
        try git(["-c", "protocol.file.allow=always", "submodule", "add", child.repo.path, "Modules/child"], at: parent.repo)
        try git(["commit", "-am", "add submodule"], at: parent.repo)
        try write("submodule change", to: parent.repo.appendingPathComponent("Modules/child/tracked.txt"))
        let submoduleFacts = await client.inspectCheckout(at: parent.repo.path, scope: .afterSuccessfulCheck)
        XCTAssertTrue(submoduleFacts.dirty.submodule)

        for (name, marker, operation) in [
            ("merge", "MERGE_HEAD", GitOperation.merge),
            ("rebase", "rebase-merge", GitOperation.rebase),
            ("cherry", "CHERRY_PICK_HEAD", GitOperation.cherryPick),
        ] {
            let repository = try makeRepository(named: "dirty-operation-\(name)")
            let markerURL = try gitPath(marker, in: repository.repo)
            if marker == "rebase-merge" {
                try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: true)
            } else {
                try write("marker", to: markerURL)
            }
            let facts = await client.inspectCheckout(at: repository.repo.path, scope: .afterSuccessfulCheck)
            XCTAssertTrue(facts.dirty.operations.contains(operation), "必须检测 \(name) 进行中")
        }

        let ignored = try makeRepository(named: "dirty-ignored")
        try write("ignored", to: ignored.repo.appendingPathComponent("ignored.tmp"))
        let ignoredFacts = await client.inspectCheckout(at: ignored.repo.path, scope: .afterSuccessfulCheck)
        XCTAssertFalse(ignoredFacts.dirty.isDirty)
    }

    func testInteractiveTransportFailsWithinSecondsWithoutReadingTerminal() async throws {
        let repository = try makeRepository(named: "noninteractive", withRemote: false)
        let bin = scratch.appendingPathComponent("bin")
        let ssh = bin.appendingPathComponent("ssh")
        let evidence = scratch.appendingPathComponent("ssh-environment.txt")
        try write(
            """
            #!/bin/sh
            printf '%s\n%s\n%s\n%s\n' "$GIT_TERMINAL_PROMPT" "$GIT_ASKPASS" "$SSH_ASKPASS" "$*" > "$PAGUGU_GIT_ENV_EVIDENCE"
            if read answer; then exit 78; fi
            parent=$PPID
            while kill -0 "$parent" 2>/dev/null; do sleep 0.05; done
            exit 77
            """,
            to: ssh
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ssh.path)
        let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        setenv("PATH", "\(bin.path):\(originalPath)", 1)
        setenv("PAGUGU_GIT_ENV_EVIDENCE", evidence.path, 1)
        defer {
            setenv("PATH", originalPath, 1)
            unsetenv("PAGUGU_GIT_ENV_EVIDENCE")
        }
        try git(["remote", "add", "origin", "ssh://example.invalid/team/skills.git"], at: repository.repo)
        let client = GitClient(timeoutSeconds: 1)
        let started = ContinuousClock.now

        do {
            try await client.fetch(remote: "origin", at: repository.repo.path)
            XCTFail("需要终端输入的 transport 必须失败")
        } catch let error as GitCommandError {
            XCTAssertEqual(error, .timedOut(seconds: 1))
            XCTAssertLessThan(started.duration(to: .now), .seconds(3))
        } catch {
            XCTFail("错误类型应为 GitCommandError.timedOut：\(error)")
        }

        let lines = try String(contentsOf: evidence, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.prefix(3), ["0", "/usr/bin/false", "/usr/bin/false"])
        let sshArguments = try XCTUnwrap(lines.last)
        XCTAssertTrue(sshArguments.contains("BatchMode=yes"))
        XCTAssertTrue(sshArguments.contains("ConnectTimeout=2"))
        XCTAssertTrue(sshArguments.contains("StrictHostKeyChecking=yes"))
    }

    func testFetchDisablesRepositoryHooks() async throws {
        let repository = try makeRepository(named: "hooks")
        let evidence = scratch.appendingPathComponent("hook-ran")
        let hook = try gitPath("hooks/reference-transaction", in: repository.repo)
        try write("#!/bin/sh\ntouch '\(evidence.path)'\n", to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try git(["update-ref", "refs/heads/hook-proof", "HEAD"], at: repository.repo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: evidence.path), "测试仓库的 hook 必须可执行")
        try FileManager.default.removeItem(at: evidence)
        try advanceRemote(repository)

        try await GitClient().fetch(remote: "origin", at: repository.repo.path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: evidence.path))
    }

    func testFetchTreatsRemoteAsAValueNotAnOption() async throws {
        let repository = try makeRepository(named: "option-like-remote")

        do {
            try await GitClient().fetch(remote: "--all", at: repository.repo.path)
            XCTFail("类选项 remote 不得扩大为 fetch --all")
        } catch let error as GitCommandError {
            guard case .commandFailed = error else {
                return XCTFail("应按单 remote 失败，实际为 \(error)")
            }
        }
    }

    private func facts(
        inspectionFailure: GitInspectionFailure? = nil,
        head: GitHead = .branch(name: "main", sha: "head"),
        upstream: GitUpstream? = GitUpstream(
            ref: "origin/main",
            remoteName: "origin",
            remoteURL: "https://example.com/team/skills.git"
        ),
        dirty: GitDirtyFacts = .clean,
        relativePosition: GitRelativePosition = .upToDate,
        siblingBranchConflict: Bool = false
    ) -> CheckoutGitFacts {
        CheckoutGitFacts(
            checkoutPath: "/repo",
            gitCommonDirectory: "/repo/.git",
            head: head,
            originRemoteURL: "https://example.com/team/skills.git",
            upstream: upstream,
            dirty: dirty,
            relativePosition: relativePosition,
            worktrees: [GitWorktree(path: "/repo", branch: "main")],
            siblingBranchConflict: siblingBranchConflict,
            inspectionFailure: inspectionFailure
        )
    }

    private func state(of repository: Repository, client: GitClient) async throws -> CheckoutGitState {
        let facts = await client.inspectCheckout(at: repository.repo.path, scope: .afterSuccessfulCheck)
        return CheckoutEligibility.evaluate(facts: facts, sourceKey: try sourceKey(of: repository))
    }

    private func sourceKey(of repository: Repository) throws -> SkillSourceKey {
        try XCTUnwrap(SkillSourceKey.normalize(remoteURL: repository.remoteURL))
    }

    private struct Repository {
        let repo: URL
        let remoteURL: String
    }

    private func makeRepository(named name: String, withRemote: Bool = true) throws -> Repository {
        let repo = scratch.appendingPathComponent(name)
        let remote = scratch.appendingPathComponent("\(name)-remote.git")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try git(["init", "-b", "main"], at: repo)
        try git(["config", "user.name", "Pagugu Test"], at: repo)
        try git(["config", "user.email", "pagugu@example.invalid"], at: repo)
        try write("ignored.tmp\n", to: repo.appendingPathComponent(".gitignore"))
        try write("initial", to: repo.appendingPathComponent("tracked.txt"))
        try git(["add", ".gitignore", "tracked.txt"], at: repo)
        try git(["commit", "-m", "initial"], at: repo)
        if withRemote {
            try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
            try git(["init", "--bare"], at: remote)
            try git(["remote", "add", "origin", "file://localhost\(remote.path)"], at: repo)
            try git(["push", "-u", "origin", "main"], at: repo)
        }
        return Repository(repo: repo, remoteURL: "file://localhost\(remote.path)")
    }

    private func advanceRemote(_ repository: Repository) throws {
        let peer = scratch.appendingPathComponent(UUID().uuidString)
        try git(["clone", "--branch", "main", repository.remoteURL, peer.path], at: scratch)
        try git(["config", "user.name", "Pagugu Test"], at: peer)
        try git(["config", "user.email", "pagugu@example.invalid"], at: peer)
        try commitChange("remote", in: peer)
        try git(["push", "origin", "main"], at: peer)
    }

    private func commitChange(_ value: String, in repo: URL) throws {
        try write(value, to: repo.appendingPathComponent("tracked.txt"))
        try git(["add", "tracked.txt"], at: repo)
        try git(["commit", "-m", value], at: repo)
    }

    private func gitPath(_ name: String, in repo: URL) throws -> URL {
        let output = try git(["rev-parse", "--git-path", name], at: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.hasPrefix("/") ? URL(fileURLWithPath: output) : repo.appendingPathComponent(output)
    }

    @discardableResult
    private func git(
        _ arguments: [String],
        at directory: URL,
        acceptedExitCodes: Set<Int32> = [0]
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard acceptedExitCodes.contains(process.terminationStatus) else {
            throw NSError(domain: "GitTest", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: stderr])
        }
        return stdout
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
