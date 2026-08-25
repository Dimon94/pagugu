import XCTest
@testable import Pagugu

final class CheckRunTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    func testFullCheckSkipsLocalBlockerAndPublishesEachSuccessBeforeCompletion() async throws {
        let remoteKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let checkedPath = "/checked"
        let skippedPath = "/local"
        let appearedPath = "/appeared-during-run"
        let client = FakeGitClient(factsAfterFetch: [
            checkedPath: facts(path: checkedPath, remoteTipSHA: "remote-tip", relativePosition: .behindOnly(1)),
            appearedPath: facts(path: appearedPath, remoteTipSHA: "later-tip"),
        ])
        let persistence = Persistence(directoryURL: temporaryDirectory)
        let registry = AppRegistry(persistence: persistence, personalRoots: [])
        _ = await registry.load()
        let runner = CheckRunner(gitInspector: client, gitExecutor: client, registry: registry)
        var scope = [
            CheckRunTarget(sourceKey: remoteKey, facts: facts(path: checkedPath)),
            CheckRunTarget(sourceKey: .localPath(skippedPath), facts: facts(path: skippedPath, remoteURL: nil, upstream: nil)),
        ]
        let stream = runner.startCheck(scope: scope)
        scope.append(CheckRunTarget(sourceKey: remoteKey, facts: facts(path: appearedPath)))
        var itemPaths: [String] = []
        var summary: CheckRunSummary?

        for await event in stream {
            switch event {
            case .started(let progress):
                XCTAssertEqual(progress, CheckRunProgress(completed: 0, total: 1))
            case .item(let item, let progress):
                itemPaths.append(item.checkoutPath)
                if item.checkoutPath == checkedPath {
                    XCTAssertEqual(item.outcome, .success)
                    let observations = await registry.checkoutObservations()
                    XCTAssertEqual(observations[checkedPath]?.remoteTipSHA, "remote-tip")
                    XCTAssertEqual(progress, CheckRunProgress(completed: 1, total: 1))
                } else {
                    XCTAssertEqual(item.outcome, .notApplicable(.noRemote))
                }
            case .finished(let value):
                summary = value
            }
        }

        XCTAssertEqual(itemPaths, [skippedPath, checkedPath])
        let fetchedPaths = await client.fetchedPaths
        XCTAssertEqual(fetchedPaths, [checkedPath])
        XCTAssertEqual(summary, CheckRunSummary(outcome: .complete, succeeded: 1, failed: 0, skipped: 1))

        let reloaded = AppRegistry(
            persistence: Persistence(directoryURL: temporaryDirectory),
            personalRoots: []
        )
        _ = await reloaded.load()
        let reloadedObservations = await reloaded.checkoutObservations()
        XCTAssertEqual(reloadedObservations[checkedPath]?.remoteTipSHA, "remote-tip", "观察必须跨重启读回")
    }

    func testSkipSetContainsOnlyTheFiveLocalBlockers() {
        let source = SkillSourceKey.remoteURL("example.com/team/skills")
        let base = facts(path: "/base")
        let targets = [
            CheckRunTarget(sourceKey: .localPath("/local"), facts: facts(path: "/local", remoteURL: nil, upstream: nil)),
            CheckRunTarget(sourceKey: source, facts: replacing(base, head: .detached(sha: "head"))),
            CheckRunTarget(sourceKey: source, facts: replacing(base, upstream: nil)),
            CheckRunTarget(sourceKey: source, facts: replacing(base, upstream: GitUpstream(
                ref: "fork/main", remoteName: "fork", remoteURL: "https://example.com/fork/skills.git"
            ))),
            CheckRunTarget(sourceKey: source, facts: replacing(base, siblingBranchConflict: true)),
        ]

        XCTAssertEqual(targets.compactMap(CheckRunner.notApplicableState), [
            .noRemote, .detached, .noUpstream, .upstreamMismatch, .siblingConflict,
        ])
        XCTAssertNil(CheckRunner.notApplicableState(for: CheckRunTarget(
            sourceKey: source,
            facts: replacing(base, dirty: GitDirtyFacts(unstaged: true), relativePosition: .behindOnly(1))
        )))
    }

    func testRunTargetMatchingRejectsNewOrReboundCheckout() {
        let source = SkillSourceKey.remoteURL("example.com/team/skills")
        let target = CheckRunTarget(sourceKey: source, facts: facts(path: "/checkout"))

        XCTAssertTrue(target.matches(CheckRunTarget(
            sourceKey: source,
            facts: replacing(target.facts, head: .branch(name: "main", sha: "new-head"))
        )))
        XCTAssertFalse(target.matches(CheckRunTarget(sourceKey: source, facts: facts(path: "/new"))))
        XCTAssertFalse(target.matches(CheckRunTarget(
            sourceKey: source,
            facts: replacing(target.facts, upstream: GitUpstream(
                ref: "origin/other", remoteName: "origin", remoteURL: "https://example.com/team/skills.git"
            ))
        )))
    }

    func testFetchFailureOverwritesPreviousSuccessObservation() async throws {
        let path = "/checkout"
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let initialFacts = facts(path: path, remoteTipSHA: "old-tip")
        let persistence = Persistence(directoryURL: temporaryDirectory)
        let registry = AppRegistry(persistence: persistence, personalRoots: [])
        _ = await registry.load()
        let digest = try XCTUnwrap(CheckoutEligibility.identityDigest(facts: initialFacts, sourceKey: sourceKey))
        try await registry.recordCheckoutObservation(CheckoutObservation(
            result: .success,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            remoteTipSHA: "old-tip",
            identityDigest: digest
        ))
        let client = FakeGitClient(factsAfterFetch: [path: initialFacts], fetchFailures: [path])
        let runner = CheckRunner(gitInspector: client, gitExecutor: client, registry: registry)

        let events = await collect(runner.startCheck(scope: [CheckRunTarget(sourceKey: sourceKey, facts: initialFacts)]))

        let observations = await registry.checkoutObservations()
        let observation = try XCTUnwrap(observations[path])
        XCTAssertEqual(observation.result, .failure)
        XCTAssertNil(observation.remoteTipSHA)
        XCTAssertTrue(events.contains { event in
            guard case .item(let item, _) = event else { return false }
            return item.outcome == .failed(.fetchFailed)
        })
        XCTAssertEqual(events.last, .finished(CheckRunSummary(outcome: .failed, succeeded: 0, failed: 1, skipped: 0)))
    }

    func testIdentityChangeDiscardsObservationInsteadOfRebindingPath() async throws {
        let path = "/checkout"
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let initialFacts = facts(path: path)
        let changedFacts = facts(
            path: path,
            upstream: GitUpstream(
                ref: "origin/other",
                remoteName: "origin",
                remoteURL: "https://example.com/team/skills.git"
            ),
            remoteTipSHA: "other-tip"
        )
        let registry = AppRegistry(
            persistence: Persistence(directoryURL: temporaryDirectory),
            personalRoots: []
        )
        _ = await registry.load()
        let client = FakeGitClient(factsAfterFetch: [path: changedFacts])
        let runner = CheckRunner(gitInspector: client, gitExecutor: client, registry: registry)

        let events = await collect(runner.startCheck(scope: [CheckRunTarget(sourceKey: sourceKey, facts: initialFacts)]))

        let observations = await registry.checkoutObservations()
        XCTAssertTrue(observations.isEmpty)
        XCTAssertTrue(events.contains { event in
            guard case .item(let item, _) = event else { return false }
            return item.outcome == .discarded
        })
        XCTAssertEqual(events.last, .finished(CheckRunSummary(outcome: .failed, succeeded: 0, failed: 1, skipped: 0)))
    }

    func testMixedResultsProducePartialSummary() async throws {
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let successPath = "/success"
        let failedPath = "/failed"
        let client = FakeGitClient(
            factsAfterFetch: [
                successPath: facts(path: successPath, remoteTipSHA: "tip"),
                failedPath: facts(path: failedPath),
            ],
            fetchFailures: [failedPath]
        )
        let registry = AppRegistry(persistence: Persistence(directoryURL: temporaryDirectory), personalRoots: [])
        _ = await registry.load()
        let runner = CheckRunner(gitInspector: client, gitExecutor: client, registry: registry)

        let events = await collect(runner.startCheck(scope: [
            CheckRunTarget(sourceKey: sourceKey, facts: facts(path: successPath)),
            CheckRunTarget(sourceKey: sourceKey, facts: facts(path: failedPath)),
        ]))

        XCTAssertEqual(events.last, .finished(CheckRunSummary(
            outcome: .partial, succeeded: 1, failed: 1, skipped: 0
        )))
    }

    private func collect(_ stream: AsyncStream<CheckRunEvent>) async -> [CheckRunEvent] {
        var events: [CheckRunEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private func facts(
        path: String,
        remoteURL: String? = "https://example.com/team/skills.git",
        upstream: GitUpstream? = GitUpstream(
            ref: "origin/main",
            remoteName: "origin",
            remoteURL: "https://example.com/team/skills.git"
        ),
        remoteTipSHA: String? = nil,
        relativePosition: GitRelativePosition = .unknown
    ) -> CheckoutGitFacts {
        CheckoutGitFacts(
            checkoutPath: path,
            gitCommonDirectory: path + "/.git",
            head: .branch(name: "main", sha: "head"),
            originRemoteURL: remoteURL,
            upstream: upstream.map {
                GitUpstream(ref: $0.ref, remoteName: $0.remoteName, remoteURL: $0.remoteURL, sha: remoteTipSHA)
            },
            dirty: .clean,
            relativePosition: relativePosition,
            worktrees: [GitWorktree(path: path, branch: "main")],
            siblingBranchConflict: false,
            inspectionFailure: nil
        )
    }

    private func replacing(
        _ facts: CheckoutGitFacts,
        head: GitHead? = .branch(name: "main", sha: "head"),
        upstream: GitUpstream? = GitUpstream(
            ref: "origin/main",
            remoteName: "origin",
            remoteURL: "https://example.com/team/skills.git"
        ),
        dirty: GitDirtyFacts = .clean,
        relativePosition: GitRelativePosition = .unknown,
        siblingBranchConflict: Bool = false
    ) -> CheckoutGitFacts {
        CheckoutGitFacts(
            checkoutPath: facts.checkoutPath,
            gitCommonDirectory: facts.gitCommonDirectory,
            head: head,
            originRemoteURL: facts.originRemoteURL,
            upstream: upstream,
            dirty: dirty,
            relativePosition: relativePosition,
            worktrees: facts.worktrees,
            siblingBranchConflict: siblingBranchConflict,
            inspectionFailure: facts.inspectionFailure
        )
    }

    private actor FakeGitClient: GitInspecting, GitExecuting {
        private enum FetchFailure: Error { case expected }

        let factsAfterFetch: [String: CheckoutGitFacts]
        let fetchFailures: Set<String>
        private(set) var fetchedPaths: [String] = []

        init(factsAfterFetch: [String: CheckoutGitFacts], fetchFailures: Set<String> = []) {
            self.factsAfterFetch = factsAfterFetch
            self.fetchFailures = fetchFailures
        }

        func fetch(remote: String, upstreamRef: String, at checkoutPath: String) async throws {
            fetchedPaths.append(checkoutPath)
            if fetchFailures.contains(checkoutPath) { throw FetchFailure.expected }
        }

        func inspectCheckout(at checkoutPath: String, scope: GitInspectionScope) async -> CheckoutGitFacts {
            factsAfterFetch[checkoutPath]!
        }
    }
}
