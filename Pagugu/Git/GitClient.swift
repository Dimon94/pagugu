import Darwin
import Foundation
import os

// L3 COORD: Pagugu/Git/GitClient.swift
// POS: Git 模块（ADR-0009 §4）。owns Git 子进程 seam 与正交 Checkout Git Fact。
//      does not own Checkout Git State 与 Eligible Update 裁决。
// TEST: repo://PaguguTests/GitEligibilityTests.swift（真实 scratch Git 与非交互失败）。

enum GitInspectionFailure: Equatable, Sendable {
    case notAWorkTree
    case launchFailed
    case timedOut
    case commandFailed(exitCode: Int32, stderr: String)
}

enum GitHead: Equatable, Sendable {
    case branch(name: String, sha: String)
    case detached(sha: String)

    var branchName: String? {
        if case .branch(let name, _) = self { return name }
        return nil
    }

    var sha: String {
        switch self {
        case .branch(_, let sha), .detached(let sha): return sha
        }
    }
}

struct GitUpstream: Equatable, Sendable {
    let ref: String
    let remoteName: String
    let remoteURL: String?
    let sha: String?

    init(ref: String, remoteName: String, remoteURL: String?, sha: String? = nil) {
        self.ref = ref
        self.remoteName = remoteName
        self.remoteURL = remoteURL
        self.sha = sha
    }
}

enum GitOperation: String, Hashable, Sendable {
    case merge
    case rebase
    case cherryPick
}

struct GitDirtyFacts: Equatable, Sendable {
    let staged: Bool
    let unstaged: Bool
    let untracked: Bool
    let unmerged: Bool
    let submodule: Bool
    let operations: Set<GitOperation>

    static let clean = GitDirtyFacts()

    init(
        staged: Bool = false,
        unstaged: Bool = false,
        untracked: Bool = false,
        unmerged: Bool = false,
        submodule: Bool = false,
        operations: Set<GitOperation> = []
    ) {
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.unmerged = unmerged
        self.submodule = submodule
        self.operations = operations
    }

    var isDirty: Bool {
        staged || unstaged || untracked || unmerged || submodule || !operations.isEmpty
    }
}

enum GitRelativePosition: Equatable, Sendable {
    case unknown
    case upToDate
    case aheadOnly(Int)
    case behindOnly(Int)
    case diverged(ahead: Int, behind: Int)
}

struct GitWorktree: Equatable, Sendable {
    let path: String
    let branch: String?
}

struct CheckoutGitFacts: Equatable, Sendable {
    let checkoutPath: String
    let gitCommonDirectory: String?
    let head: GitHead?
    let originRemoteURL: String?
    let upstream: GitUpstream?
    let dirty: GitDirtyFacts
    let relativePosition: GitRelativePosition
    let worktrees: [GitWorktree]
    let siblingBranchConflict: Bool
    let inspectionFailure: GitInspectionFailure?
}

enum GitInspectionScope: Sendable {
    case localOnly
    case afterSuccessfulCheck
}

protocol GitInspecting: Sendable {
    func inspectCheckout(at checkoutPath: String, scope: GitInspectionScope) async -> CheckoutGitFacts
}

// L4 IN: fetch 接收同一 upstream 的 remote/ref；fastForward 接收 Git 返回的完整精确 SHA。
// OUT: fetch 只移动单个 remote-tracking ref；fastForward 只对目标工作树执行 ff-only；
//      terminateInFlight 尽力终止本进程登记的在途 Git 子进程。
// INVARIANT: 全部命令非交互并屏蔽 hooks；不改 Git 配置，不 reset/force/stash/checkout。
// FAIL: 非交互失败抛 GitCommandError；caller 决定恢复语义。
// TEST: repo://PaguguTests/GitEligibilityTests.swift（单分支 fetch、精确 SHA ff、hook 屏蔽）。
protocol GitExecuting: Sendable {
    func fetch(remote: String, upstreamRef: String, at checkoutPath: String) async throws
    func fastForward(to targetSHA: String, at checkoutPath: String) async throws
    func terminateInFlight()
}

extension GitExecuting {
    func terminateInFlight() {}
}

struct GitCommandOutput: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum GitCommandError: Error, Equatable, Sendable {
    case launchFailed(String)
    case timedOut(seconds: Double)
    case commandFailed(exitCode: Int32, stderr: String)

    /// Git 在固定 C locale 下报告 index/ref 锁冲突的协议级归一化。
    /// Runs 只消费此事实，不解析原始 stderr，也不把原始输出写入审计。
    var indicatesLockBusy: Bool {
        guard case .commandFailed(_, let stderr) = self else { return false }
        let message = stderr.lowercased()
        return message.contains(".lock") && (
            message.contains("file exists") ||
                message.contains("unable to create") ||
                message.contains("cannot lock ref") ||
                message.contains("could not lock")
        )
    }
}

private final class GitProcessRegistry: Sendable {
    static let shared = GitProcessRegistry()

    private let processes = OSAllocatedUnfairLock(initialState: [UUID: Process]())

    func insert(_ process: Process, id: UUID) {
        processes.withLock { $0[id] = process }
    }

    func remove(id: UUID) {
        processes.withLock { $0[id] = nil }
    }

    func terminateAll() {
        let running = processes.withLock { Array($0.values) }
        for process in running where process.isRunning {
            process.terminate()
        }
    }
}

struct GitClient: GitInspecting, GitExecuting, Sendable {
    // L5 PARAM: timeoutSeconds 为单条 Git 命令上限；默认 3 秒。超时终止并 fail closed。
    let timeoutSeconds: Double

    init(timeoutSeconds: Double = 3) {
        self.timeoutSeconds = timeoutSeconds
    }

    func terminateInFlight() {
        GitProcessRegistry.shared.terminateAll()
    }

    func inspectCheckout(at checkoutPath: String, scope: GitInspectionScope) async -> CheckoutGitFacts {
        await Task.detached {
            GitClient.inspect(checkoutPath: checkoutPath, scope: scope, timeoutSeconds: timeoutSeconds)
        }.value
    }

    // L5 PAIR: upstreamRef 必须以 `remote/` 开头；不匹配时拒绝启动 Git。
    func fetch(remote: String, upstreamRef: String, at checkoutPath: String) async throws {
        let prefix = remote + "/"
        guard upstreamRef.hasPrefix(prefix), upstreamRef.count > prefix.count else {
            throw GitCommandError.commandFailed(exitCode: -1, stderr: "上游分支与 remote 不匹配")
        }
        let branch = upstreamRef.dropFirst(prefix.count)
        let refspec = "+refs/heads/\(branch):refs/remotes/\(upstreamRef)"
        _ = try await Task.detached {
            try GitClient.runGit(
                ["fetch", "--no-tags", "--", remote, refspec],
                at: checkoutPath,
                timeoutSeconds: timeoutSeconds
            )
        }.value
    }

    // L5 PARAM: targetSHA 只接受 40/64 位十六进制完整对象名，拒绝 ref 与类选项输入。
    func fastForward(to targetSHA: String, at checkoutPath: String) async throws {
        guard [40, 64].contains(targetSHA.count), targetSHA.allSatisfy(\.isHexDigit) else {
            throw GitCommandError.commandFailed(exitCode: -1, stderr: "目标 SHA 不是完整 Git 对象名")
        }
        _ = try await Task.detached {
            try GitClient.runGit(
                ["merge", "--ff-only", "--", targetSHA],
                at: checkoutPath,
                timeoutSeconds: timeoutSeconds
            )
        }.value
    }

    private static func inspect(
        checkoutPath: String,
        scope: GitInspectionScope,
        timeoutSeconds: Double
    ) -> CheckoutGitFacts {
        let canonicalPath = canonical(checkoutPath)
        let topLevel: String
        do {
            topLevel = try runGit(
                ["rev-parse", "--show-toplevel"],
                at: canonicalPath,
                timeoutSeconds: timeoutSeconds
            ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as GitCommandError {
            let failure: GitInspectionFailure
            if case .commandFailed = error {
                failure = .notAWorkTree
            } else {
                failure = inspectionFailure(from: error)
            }
            return failedFacts(path: canonicalPath, failure: failure)
        } catch {
            return failedFacts(path: canonicalPath, failure: .launchFailed)
        }

        do {
            let root = canonical(topLevel)
            let status = try runGit(
                ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all", "--ignore-submodules=none"],
                at: root,
                timeoutSeconds: timeoutSeconds
            )
            let parsed = parseStatus(status.stdout)
            guard let head = parsed.head else {
                return failedFacts(path: root, failure: .commandFailed(exitCode: 0, stderr: "无法读取 HEAD"))
            }

            let origin = try optionalConfig("remote.origin.url", at: root, timeoutSeconds: timeoutSeconds)
            let upstream = try readUpstream(
                branchName: head.branchName,
                ref: parsed.upstreamRef,
                at: root,
                timeoutSeconds: timeoutSeconds
            )
            let commonDirectory = try gitPath(
                try runGit(["rev-parse", "--git-common-dir"], at: root, timeoutSeconds: timeoutSeconds).stdout,
                relativeTo: root
            )
            let worktrees = parseWorktrees(
                try runGit(["worktree", "list", "--porcelain"], at: root, timeoutSeconds: timeoutSeconds).stdout
            )
            let siblingConflict = head.branchName.map { branch in
                worktrees.contains { $0.path != root && $0.branch == branch }
            } ?? false
            let operations = try readOperations(at: root, timeoutSeconds: timeoutSeconds)
            let dirty = GitDirtyFacts(
                staged: parsed.dirty.staged,
                unstaged: parsed.dirty.unstaged,
                untracked: parsed.dirty.untracked,
                unmerged: parsed.dirty.unmerged,
                submodule: parsed.dirty.submodule,
                operations: operations
            )
            let relativePosition = scope == .afterSuccessfulCheck
                ? parsed.relativePosition
                : .unknown

            return CheckoutGitFacts(
                checkoutPath: root,
                gitCommonDirectory: commonDirectory,
                head: head,
                originRemoteURL: origin,
                upstream: upstream,
                dirty: dirty,
                relativePosition: relativePosition,
                worktrees: worktrees,
                siblingBranchConflict: siblingConflict,
                inspectionFailure: nil
            )
        } catch let error as GitCommandError {
            return failedFacts(path: canonicalPath, failure: inspectionFailure(from: error))
        } catch {
            return failedFacts(path: canonicalPath, failure: .launchFailed)
        }
    }

    private struct ParsedStatus {
        let head: GitHead?
        let upstreamRef: String?
        let relativePosition: GitRelativePosition
        let dirty: GitDirtyFacts
    }

    private static func parseStatus(_ output: String) -> ParsedStatus {
        var oid: String?
        var branchName: String?
        var detached = false
        var upstreamRef: String?
        var ahead: Int?
        var behind: Int?
        var staged = false
        var unstaged = false
        var untracked = false
        var unmerged = false
        var submodule = false

        for record in output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init) {
            if record.hasPrefix("# branch.oid ") {
                oid = String(record.dropFirst("# branch.oid ".count))
            } else if record.hasPrefix("# branch.head ") {
                let value = String(record.dropFirst("# branch.head ".count))
                detached = value == "(detached)"
                branchName = detached ? nil : value
            } else if record.hasPrefix("# branch.upstream ") {
                upstreamRef = String(record.dropFirst("# branch.upstream ".count))
            } else if record.hasPrefix("# branch.ab ") {
                let values = record.dropFirst("# branch.ab ".count).split(separator: " ")
                ahead = values.first.flatMap { Int($0.dropFirst()) }
                behind = values.dropFirst().first.flatMap { Int($0.dropFirst()) }
            } else if record.hasPrefix("? ") {
                untracked = true
            } else if record.hasPrefix("u ") {
                unmerged = true
            } else if record.hasPrefix("1 ") || record.hasPrefix("2 ") {
                let fields = record.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                guard fields.count >= 3 else { continue }
                let xy = fields[1]
                if xy.first != "." { staged = true }
                if xy.dropFirst().first != "." { unstaged = true }
                if fields[2] != "N..." { submodule = true }
            }
        }

        let head: GitHead? = oid.map {
            detached ? GitHead.detached(sha: $0) : GitHead.branch(name: branchName ?? "", sha: $0)
        }
        let position: GitRelativePosition
        switch (ahead, behind) {
        case (.some(0), .some(0)): position = .upToDate
        case (.some(let value), .some(0)) where value > 0: position = .aheadOnly(value)
        case (.some(0), .some(let value)) where value > 0: position = .behindOnly(value)
        case (.some(let local), .some(let remote)) where local > 0 && remote > 0:
            position = .diverged(ahead: local, behind: remote)
        default: position = .unknown
        }

        return ParsedStatus(
            head: head,
            upstreamRef: upstreamRef,
            relativePosition: position,
            dirty: GitDirtyFacts(
                staged: staged,
                unstaged: unstaged,
                untracked: untracked,
                unmerged: unmerged,
                submodule: submodule
            )
        )
    }

    private static func readUpstream(
        branchName: String?,
        ref: String?,
        at checkoutPath: String,
        timeoutSeconds: Double
    ) throws -> GitUpstream? {
        guard let branchName, let ref else { return nil }
        let remoteName = try optionalConfig(
            "branch.\(branchName).remote",
            at: checkoutPath,
            timeoutSeconds: timeoutSeconds
        ) ?? ""
        let remoteURL = remoteName.isEmpty || remoteName == "."
            ? nil
            : try optionalConfig("remote.\(remoteName).url", at: checkoutPath, timeoutSeconds: timeoutSeconds)
        let sha = try optionalRefSHA(ref, at: checkoutPath, timeoutSeconds: timeoutSeconds)
        return GitUpstream(ref: ref, remoteName: remoteName, remoteURL: remoteURL, sha: sha)
    }

    private static func optionalRefSHA(
        _ ref: String,
        at checkoutPath: String,
        timeoutSeconds: Double
    ) throws -> String? {
        let output = try runGit(
            ["rev-parse", "--verify", "--quiet", ref],
            at: checkoutPath,
            timeoutSeconds: timeoutSeconds,
            acceptedExitCodes: [0, 1]
        )
        guard output.exitCode == 0 else { return nil }
        let sha = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    private static func optionalConfig(
        _ key: String,
        at checkoutPath: String,
        timeoutSeconds: Double
    ) throws -> String? {
        let output = try runGit(
            ["config", "--get", key],
            at: checkoutPath,
            timeoutSeconds: timeoutSeconds,
            acceptedExitCodes: [0, 1]
        )
        guard output.exitCode == 0 else { return nil }
        let value = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func readOperations(at checkoutPath: String, timeoutSeconds: Double) throws -> Set<GitOperation> {
        let fm = FileManager.default
        var operations = Set<GitOperation>()
        if fm.fileExists(atPath: try resolvedGitPath("MERGE_HEAD", at: checkoutPath, timeoutSeconds: timeoutSeconds)) {
            operations.insert(.merge)
        }
        let rebaseMerge = try resolvedGitPath("rebase-merge", at: checkoutPath, timeoutSeconds: timeoutSeconds)
        let rebaseApply = try resolvedGitPath("rebase-apply", at: checkoutPath, timeoutSeconds: timeoutSeconds)
        if fm.fileExists(atPath: rebaseMerge) || fm.fileExists(atPath: rebaseApply) {
            operations.insert(.rebase)
        }
        if fm.fileExists(atPath: try resolvedGitPath("CHERRY_PICK_HEAD", at: checkoutPath, timeoutSeconds: timeoutSeconds)) {
            operations.insert(.cherryPick)
        }
        return operations
    }

    private static func resolvedGitPath(_ name: String, at checkoutPath: String, timeoutSeconds: Double) throws -> String {
        try gitPath(
            runGit(["rev-parse", "--git-path", name], at: checkoutPath, timeoutSeconds: timeoutSeconds).stdout,
            relativeTo: checkoutPath
        )
    }

    private static func gitPath(_ output: String, relativeTo checkoutPath: String) throws -> String {
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw GitCommandError.commandFailed(exitCode: 0, stderr: "Git 路径为空") }
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: checkoutPath).appendingPathComponent(path)
        return canonical(url.path)
    }

    private static func parseWorktrees(_ output: String) -> [GitWorktree] {
        var result: [GitWorktree] = []
        var path: String?
        var branch: String?

        func appendCurrent() {
            if let path {
                result.append(GitWorktree(path: canonical(path), branch: branch))
            }
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("worktree ") {
                appendCurrent()
                path = String(line.dropFirst("worktree ".count))
                branch = nil
            } else if line.hasPrefix("branch refs/heads/") {
                branch = String(line.dropFirst("branch refs/heads/".count))
            }
        }
        appendCurrent()
        return result
    }

    private static func failedFacts(path: String, failure: GitInspectionFailure) -> CheckoutGitFacts {
        CheckoutGitFacts(
            checkoutPath: path,
            gitCommonDirectory: nil,
            head: nil,
            originRemoteURL: nil,
            upstream: nil,
            dirty: .clean,
            relativePosition: .unknown,
            worktrees: [],
            siblingBranchConflict: false,
            inspectionFailure: failure
        )
    }

    private static func inspectionFailure(from error: GitCommandError) -> GitInspectionFailure {
        switch error {
        case .launchFailed: return .launchFailed
        case .timedOut: return .timedOut
        case .commandFailed(let exitCode, let stderr):
            return .commandFailed(exitCode: exitCode, stderr: stderr)
        }
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    // L6 CHAIN: 固定非交互环境 → 启动 → 秒级等待 → timeout 终止 → 单次 exit/stderr 归一化。
    private static func runGit(
        _ arguments: [String],
        at checkoutPath: String,
        timeoutSeconds: Double,
        acceptedExitCodes: Set<Int32> = [0]
    ) throws -> GitCommandOutput {
        let fm = FileManager.default
        let captureDirectory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: captureDirectory) }
        let stdoutURL = captureDirectory.appendingPathComponent("stdout")
        let stderrURL = captureDirectory.appendingPathComponent("stderr")
        _ = fm.createFile(atPath: stdoutURL.path, contents: nil)
        _ = fm.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.hooksPath=/dev/null", "-C", checkoutPath] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        var environment = currentEnvironment()
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/false"
        environment["SSH_ASKPASS"] = "/usr/bin/false"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=yes"
        environment["LC_ALL"] = "C"
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw GitCommandError.launchFailed(error.localizedDescription)
        }
        let processID = UUID()
        GitProcessRegistry.shared.insert(process, id: processID)
        defer { GitProcessRegistry.shared.remove(id: processID) }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        while process.isRunning && clock.now < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = clock.now.advanced(by: .milliseconds(100))
            while process.isRunning && clock.now < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw GitCommandError.timedOut(seconds: timeoutSeconds)
        }
        process.waitUntilExit()
        try stdoutHandle.synchronize()
        try stderrHandle.synchronize()

        let stdout = String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self)
        let stderr = String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let output = GitCommandOutput(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
        guard acceptedExitCodes.contains(output.exitCode) else {
            throw GitCommandError.commandFailed(exitCode: output.exitCode, stderr: output.stderr)
        }
        return output
    }

    private static func currentEnvironment() -> [String: String] {
        var result: [String: String] = [:]
        var cursor = environ
        while let entry = cursor.pointee {
            let value = String(cString: entry)
            if let separator = value.firstIndex(of: "=") {
                result[String(value[..<separator])] = String(value[value.index(after: separator)...])
            }
            cursor = cursor.advanced(by: 1)
        }
        return result
    }
}
