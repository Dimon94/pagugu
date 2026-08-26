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
        let runner = CheckRunner(
            gitInspector: client,
            gitExecutor: client,
            registry: registry,
            audit: AuditEvidence(persistence: persistence)
        )
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

    func testCheckRunAppendsOneTerminalAuditRecordWithOutcomeAndScopeCountsOnly() async throws {
        let path = "/checked"
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let checkedFacts = facts(path: path, remoteTipSHA: "remote-tip", relativePosition: .behindOnly(1))
        let client = FakeGitClient(factsAfterFetch: [path: checkedFacts])
        let persistence = Persistence(directoryURL: temporaryDirectory)
        let registry = AppRegistry(persistence: persistence, personalRoots: [])
        _ = await registry.load()
        let runner = CheckRunner(
            gitInspector: client,
            gitExecutor: client,
            registry: registry,
            audit: AuditEvidence(persistence: persistence)
        )

        _ = await collect(runner.startCheck(scope: [
            CheckRunTarget(sourceKey: sourceKey, facts: facts(path: path)),
        ]))

        let audit = await persistence.loadAuditEvidence()
        let record = try XCTUnwrap(audit.records.first)
        XCTAssertEqual(audit.records.count, 1)
        XCTAssertEqual(record.action, .checkRun)
        XCTAssertEqual(record.outcome, .complete)
        XCTAssertEqual(record.checkRunScope, AuditRecord.CheckRunScope(
            checkableCount: 1,
            succeededCount: 1,
            failedCount: 0,
            skippedCount: 0
        ))
        XCTAssertNil(record.installationCanonicalPath)
        XCTAssertNil(record.target)
        let bytes = try Data(contentsOf: temporaryDirectory.appendingPathComponent("audit-history.json"))
        let json = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(json.contains(path), "Check Run 审计不得保存检出或失败清单")
        XCTAssertFalse(json.contains("stdout"))
        XCTAssertFalse(json.contains("stderr"))
        XCTAssertFalse(json.contains("exitCode"))
    }

    func testAuditWriteFailureDoesNotChangeCompletedCheckOutcomeOrObservation() async throws {
        let path = "/checked"
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let checkedFacts = facts(path: path, remoteTipSHA: "remote-tip", relativePosition: .behindOnly(1))
        let client = FakeGitClient(factsAfterFetch: [path: checkedFacts])
        let persistence = Persistence(directoryURL: temporaryDirectory)
        let registry = AppRegistry(persistence: persistence, personalRoots: [])
        _ = await registry.load()
        try FileManager.default.createDirectory(
            at: temporaryDirectory.appendingPathComponent("audit-history.json"),
            withIntermediateDirectories: true
        )
        let runner = CheckRunner(
            gitInspector: client,
            gitExecutor: client,
            registry: registry,
            audit: AuditEvidence(persistence: persistence)
        )

        let events = await collect(runner.startCheck(scope: [
            CheckRunTarget(sourceKey: sourceKey, facts: facts(path: path)),
        ]))

        XCTAssertEqual(events.last, .finished(CheckRunSummary(
            outcome: .complete,
            succeeded: 1,
            failed: 0,
            skipped: 0
        )))
        let observations = await registry.checkoutObservations()
        XCTAssertEqual(observations[path]?.remoteTipSHA, "remote-tip")
    }

    func testCorruptAuditReadFailsOpenAndCheckWritesNewTerminalHistory() async throws {
        let path = "/checked"
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let checkedFacts = facts(path: path, remoteTipSHA: "remote-tip", relativePosition: .behindOnly(1))
        let client = FakeGitClient(factsAfterFetch: [path: checkedFacts])
        let persistence = Persistence(directoryURL: temporaryDirectory)
        let registry = AppRegistry(persistence: persistence, personalRoots: [])
        _ = await registry.load()
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: temporaryDirectory.appendingPathComponent("audit-history.json"))
        let runner = CheckRunner(
            gitInspector: client,
            gitExecutor: client,
            registry: registry,
            audit: AuditEvidence(persistence: persistence)
        )

        let events = await collect(runner.startCheck(scope: [
            CheckRunTarget(sourceKey: sourceKey, facts: facts(path: path)),
        ]))

        XCTAssertEqual(events.last, .finished(CheckRunSummary(
            outcome: .complete,
            succeeded: 1,
            failed: 0,
            skipped: 0
        )))
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.map(\.outcome), [.complete])
        let files = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("audit-history.corrupt-") })
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
        let runner = CheckRunner(
            gitInspector: client,
            gitExecutor: client,
            registry: registry,
            audit: AuditEvidence(persistence: persistence)
        )

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
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.last?.outcome, .failed)
        XCTAssertEqual(audit.records.last?.checkRunScope, AuditRecord.CheckRunScope(
            checkableCount: 1,
            succeededCount: 0,
            failedCount: 1,
            skippedCount: 0
        ))
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
        let persistence = Persistence(directoryURL: temporaryDirectory)
        let registry = AppRegistry(
            persistence: persistence,
            personalRoots: []
        )
        _ = await registry.load()
        let client = FakeGitClient(factsAfterFetch: [path: changedFacts])
        let runner = CheckRunner(
            gitInspector: client,
            gitExecutor: client,
            registry: registry,
            audit: AuditEvidence(persistence: persistence)
        )

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
        let persistence = Persistence(directoryURL: temporaryDirectory)
        let registry = AppRegistry(persistence: persistence, personalRoots: [])
        _ = await registry.load()
        let runner = CheckRunner(
            gitInspector: client,
            gitExecutor: client,
            registry: registry,
            audit: AuditEvidence(persistence: persistence)
        )

        let events = await collect(runner.startCheck(scope: [
            CheckRunTarget(sourceKey: sourceKey, facts: facts(path: successPath)),
            CheckRunTarget(sourceKey: sourceKey, facts: facts(path: failedPath)),
        ]))

        XCTAssertEqual(events.last, .finished(CheckRunSummary(
            outcome: .partial, succeeded: 1, failed: 1, skipped: 0
        )))
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.last?.outcome, .partial)
        XCTAssertEqual(audit.records.last?.checkRunScope, AuditRecord.CheckRunScope(
            checkableCount: 2,
            succeededCount: 1,
            failedCount: 1,
            skippedCount: 0
        ))
    }

    func testEveryUpdateFailureHasStableCodeChineseNameAndRecoveryDirection() {
        XCTAssertEqual(
            UpdateRunFailureReason.allCases.map(\.rawValue),
            [
                "lock-busy", "identity-changed", "fetch-failure", "precondition-changed",
                "tip-changed", "ff-rejected", "command-failure", "verification-failed",
                "interrupted-unknown",
            ]
        )
        for reason in UpdateRunFailureReason.allCases {
            XCTAssertFalse(reason.displayName.isEmpty)
            XCTAssertFalse(reason.recoveryDirection.isEmpty)
        }
        XCTAssertTrue(
            UpdateRunFailureReason.tipChanged.recoveryDirection.contains("重新发起更新")
        )
    }

    func testPrepareUpdateReturnsNoPlanForNoopOrBlockingRecheckState() async throws {
        let path = "/checkout"
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let identity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let requestFacts = facts(path: path, remoteTipSHA: String(repeating: "b", count: 40), relativePosition: .behindOnly(1))
        let affectedSkills = [UpdateAffectedSkill(identity: identity, displayName: "One")]
        let persistence = Persistence(directoryURL: temporaryDirectory.appendingPathComponent("prepare-data"))

        let noopClient = FakeGitClient(factsAfterFetch: [
            path: facts(path: path, remoteTipSHA: String(repeating: "a", count: 40), relativePosition: .upToDate),
        ])
        let noopRunner = UpdateRunner(
            gitInspector: noopClient,
            gitExecutor: noopClient,
            audit: AuditEvidence(persistence: persistence)
        )
        let noop = try await noopRunner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: identity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: requestFacts),
            affectedSkills: affectedSkills
        ))
        XCTAssertEqual(noop, .upToDate)

        let blockedClient = FakeGitClient(factsAfterFetch: [
            path: replacing(
                requestFacts,
                dirty: GitDirtyFacts(untracked: true),
                relativePosition: .behindOnly(1)
            ),
        ])
        let blockedRunner = UpdateRunner(
            gitInspector: blockedClient,
            gitExecutor: blockedClient,
            audit: AuditEvidence(persistence: persistence)
        )
        let blocked = try await blockedRunner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: identity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: requestFacts),
            affectedSkills: affectedSkills
        ))
        XCTAssertEqual(blocked, .blocked(.dirty))
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.count, 1, "确认前阻断只写 terminal failed，不得写 start")
        XCTAssertEqual(audit.records.first?.updateRunPhase, .terminal)
        XCTAssertEqual(audit.records.first?.outcome, .failed)
        XCTAssertEqual(
            audit.records.first?.updateFailureReason,
            UpdateRunFailureReason.preconditionChanged.rawValue
        )
        XCTAssertNil(audit.records.first?.updateRunPlan)
    }

    func testCancelPreparedWritesTerminalOnlyCancelledAuditWithFrozenPlan() async throws {
        let path = "/checkout"
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let identity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let oldHead = String(repeating: "a", count: 40)
        let targetSHA = String(repeating: "b", count: 40)
        let requestFacts = facts(
            path: path,
            headSHA: oldHead,
            remoteTipSHA: targetSHA,
            relativePosition: .behindOnly(1)
        )
        let client = FakeGitClient(factsAfterFetch: [path: requestFacts])
        let persistence = Persistence(directoryURL: temporaryDirectory.appendingPathComponent("cancel-data"))
        let runner = UpdateRunner(
            gitInspector: client,
            gitExecutor: client,
            audit: AuditEvidence(persistence: persistence)
        )
        let preparation = try await runner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: identity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: requestFacts),
            affectedSkills: [UpdateAffectedSkill(identity: identity, displayName: "One")]
        ))
        guard case .ready(let plan) = preparation else { return XCTFail("预期确认计划") }

        await runner.cancelPrepared(plan)

        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.count, 1)
        XCTAssertEqual(audit.records.first?.updateRunID, plan.runID)
        XCTAssertEqual(audit.records.first?.updateRunPhase, .terminal)
        XCTAssertEqual(audit.records.first?.outcome, .cancelled)
        XCTAssertNil(audit.records.first?.updateFailureReason)
        XCTAssertEqual(audit.records.first?.updateRunPlan?.targetSHA, targetSHA)
    }

    func testPrepareUpdateClassifiesFetchFailureAndWritesTerminalOnlyAudit() async throws {
        let path = "/checkout"
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let identity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let requestFacts = facts(
            path: path,
            headSHA: String(repeating: "a", count: 40),
            remoteTipSHA: String(repeating: "b", count: 40),
            relativePosition: .behindOnly(1)
        )
        let client = FakeGitClient(factsAfterFetch: [path: requestFacts], fetchFailures: [path])
        let persistence = Persistence(directoryURL: temporaryDirectory.appendingPathComponent("fetch-failure-data"))
        let runner = UpdateRunner(
            gitInspector: client,
            gitExecutor: client,
            audit: AuditEvidence(persistence: persistence)
        )

        do {
            _ = try await runner.prepareUpdate(request: UpdateRunRequest(
                skillIdentity: identity,
                target: CheckRunTarget(sourceKey: sourceKey, facts: requestFacts),
                affectedSkills: [UpdateAffectedSkill(identity: identity, displayName: "One")]
            ))
            XCTFail("fetch 失败必须归一化")
        } catch let failure as UpdateRunFailure {
            XCTAssertEqual(failure.reason, .fetchFailure)
        } catch {
            XCTFail("fetch 失败必须返回稳定失败类，实际为 \(error)")
        }

        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.count, 1)
        XCTAssertEqual(audit.records.first?.updateRunPhase, .terminal)
        XCTAssertEqual(audit.records.first?.outcome, .failed)
        XCTAssertEqual(audit.records.first?.updateFailureReason, "fetch-failure")
        XCTAssertNil(audit.records.first?.updateRunPlan)
    }

    func testExecuteConfirmedFailsClosedWhenHeadDriftsBeforeFastForward() async throws {
        let path = "/checkout"
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let oldHead = String(repeating: "a", count: 40)
        let targetSHA = String(repeating: "b", count: 40)
        let baseFacts = CheckoutGitFacts(
            checkoutPath: path,
            gitCommonDirectory: path + "/.git",
            head: .branch(name: "main", sha: oldHead),
            originRemoteURL: "https://example.com/team/skills.git",
            upstream: GitUpstream(
                ref: "origin/main",
                remoteName: "origin",
                remoteURL: "https://example.com/team/skills.git",
                sha: targetSHA
            ),
            dirty: .clean,
            relativePosition: .behindOnly(1),
            worktrees: [GitWorktree(path: path, branch: "main")],
            siblingBranchConflict: false,
            inspectionFailure: nil
        )
        let driftedFacts = CheckoutGitFacts(
            checkoutPath: path,
            gitCommonDirectory: path + "/.git",
            head: .branch(name: "main", sha: String(repeating: "c", count: 40)),
            originRemoteURL: baseFacts.originRemoteURL,
            upstream: baseFacts.upstream,
            dirty: .clean,
            relativePosition: .behindOnly(1),
            worktrees: baseFacts.worktrees,
            siblingBranchConflict: false,
            inspectionFailure: nil
        )
        let git = SequencedUpdateGitClient(inspections: [baseFacts, driftedFacts])
        let runner = UpdateRunner(
            gitInspector: git,
            gitExecutor: git,
            audit: AuditEvidence(persistence: Persistence(
                directoryURL: temporaryDirectory.appendingPathComponent("drift-data")
            ))
        )
        let identity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let preparation = try await runner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: identity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: baseFacts),
            affectedSkills: [UpdateAffectedSkill(identity: identity, displayName: "One")]
        ))
        guard case .ready(let plan) = preparation else { return XCTFail("预期确认计划") }

        do {
            _ = try await runner.executeConfirmed(plan)
            XCTFail("确认后 HEAD 漂移必须 fail closed")
        } catch let failure as UpdateRunFailure {
            XCTAssertEqual(failure.reason, .preconditionChanged)
            XCTAssertFalse(failure.recoveryDirection.isEmpty)
        } catch {
            XCTFail("HEAD 漂移必须保留稳定 typed failure，实际为 \(error)")
        }
        let fastForwardCount = await git.fastForwardCount
        XCTAssertEqual(fastForwardCount, 0)
        let audit = await Persistence(
            directoryURL: temporaryDirectory.appendingPathComponent("drift-data")
        ).loadAuditEvidence()
        XCTAssertEqual(audit.records.map(\.updateRunPhase), [.started, .terminal])
        XCTAssertEqual(audit.records.last?.outcome, .failed)
        XCTAssertEqual(audit.records.last?.updateFailureReason, "precondition-changed")
    }

    func testPostVerifyRejectsSuccessWhenSiblingConflictAppears() async throws {
        let path = "/checkout"
        let sourceKey = SkillSourceKey.remoteURL("example.com/team/skills")
        let oldHead = String(repeating: "4", count: 40)
        let targetSHA = String(repeating: "5", count: 40)
        let baseFacts = CheckoutGitFacts(
            checkoutPath: path,
            gitCommonDirectory: path + "/.git",
            head: .branch(name: "main", sha: oldHead),
            originRemoteURL: "https://example.com/team/skills.git",
            upstream: GitUpstream(
                ref: "origin/main",
                remoteName: "origin",
                remoteURL: "https://example.com/team/skills.git",
                sha: targetSHA
            ),
            dirty: .clean,
            relativePosition: .behindOnly(1),
            worktrees: [GitWorktree(path: path, branch: "main")],
            siblingBranchConflict: false,
            inspectionFailure: nil
        )
        let conflictedPostFacts = CheckoutGitFacts(
            checkoutPath: path,
            gitCommonDirectory: path + "/.git",
            head: .branch(name: "main", sha: targetSHA),
            originRemoteURL: baseFacts.originRemoteURL,
            upstream: baseFacts.upstream,
            dirty: .clean,
            relativePosition: .upToDate,
            worktrees: [
                GitWorktree(path: path, branch: "main"),
                GitWorktree(path: "/sibling", branch: "main"),
            ],
            siblingBranchConflict: true,
            inspectionFailure: nil
        )
        let git = SequencedUpdateGitClient(inspections: [baseFacts, baseFacts, conflictedPostFacts])
        let persistence = Persistence(directoryURL: temporaryDirectory.appendingPathComponent("sibling-data"))
        let runner = UpdateRunner(
            gitInspector: git,
            gitExecutor: git,
            audit: AuditEvidence(persistence: persistence)
        )
        let identity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let preparation = try await runner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: identity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: baseFacts),
            affectedSkills: [UpdateAffectedSkill(identity: identity, displayName: "One")]
        ))
        guard case .ready(let plan) = preparation else { return XCTFail("预期确认计划") }

        do {
            _ = try await runner.executeConfirmed(plan)
            XCTFail("post-verify 状态不是 up-to-date 时不得写成功")
        } catch let failure as UpdateRunFailure {
            XCTAssertEqual(failure.reason, .verificationFailed)
        } catch {
            XCTFail("post-verify 必须返回稳定 typed failure，实际为 \(error)")
        }
        let fastForwardCount = await git.fastForwardCount
        XCTAssertEqual(fastForwardCount, 1)
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.map(\.updateRunPhase), [.started, .terminal])
        XCTAssertNil(audit.records.first?.outcome)
        XCTAssertEqual(audit.records.last?.outcome, .failed)
        XCTAssertEqual(audit.records.last?.updateFailureReason, "verification-failed")
    }

    func testUpdateRunScratchClassifiesOccupiedIndexLockWithoutMovingHeadOrRetrying() async throws {
        let repository = try makeUpdateRepository(named: "update-lock-busy")
        let client = GitClient()
        try await client.fetch(remote: "origin", upstreamRef: "origin/main", at: repository.checkout.path)
        let entranceFacts = await client.inspectCheckout(
            at: repository.checkout.path,
            scope: .afterSuccessfulCheck
        )
        let sourceKey = try XCTUnwrap(SkillSourceKey.normalize(remoteURL: repository.remoteURL))
        let identity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let persistence = Persistence(directoryURL: temporaryDirectory.appendingPathComponent("lock-data"))
        let runner = UpdateRunner(
            gitInspector: client,
            gitExecutor: client,
            audit: AuditEvidence(persistence: persistence)
        )
        let preparation = try await runner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: identity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: entranceFacts),
            affectedSkills: [UpdateAffectedSkill(identity: identity, displayName: "One")]
        ))
        guard case .ready(let plan) = preparation else { return XCTFail("预期确认计划") }
        let lock = try updateGitPath("index.lock", in: repository.checkout)
        try Data().write(to: lock)
        defer { try? FileManager.default.removeItem(at: lock) }

        do {
            _ = try await runner.executeConfirmed(plan)
            XCTFail("外部 index.lock 必须阻止更新")
        } catch let failure as UpdateRunFailure {
            XCTAssertEqual(failure.reason, .lockBusy)
        } catch {
            XCTFail("锁冲突必须返回稳定失败类，实际为 \(error)")
        }

        XCTAssertEqual(
            try updateGit(["rev-parse", "HEAD"], at: repository.checkout)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            plan.currentHeadSHA
        )
        XCTAssertEqual(try updateGit(["status", "--porcelain"], at: repository.checkout), "")
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.map(\.updateRunPhase), [.started, .terminal])
        XCTAssertEqual(audit.records.last?.updateFailureReason, "lock-busy")
        let bytes = try Data(
            contentsOf: temporaryDirectory.appendingPathComponent("lock-data/audit-history.json")
        )
        let json = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(json.contains("index.lock"), "审计不得持久化原始 Git 错误")
        XCTAssertFalse(json.contains("stderr"))
        XCTAssertFalse(json.contains("exitCode"))
    }

    func testUpdateRunScratchClassifiesDirtyAfterFastForwardFailureAsPreconditionChanged() async throws {
        let repository = try makeUpdateRepository(named: "update-precondition-dirty")
        let client = GitClient()
        try await client.fetch(remote: "origin", upstreamRef: "origin/main", at: repository.checkout.path)
        let entranceFacts = await client.inspectCheckout(
            at: repository.checkout.path,
            scope: .afterSuccessfulCheck
        )
        let sourceKey = try XCTUnwrap(SkillSourceKey.normalize(remoteURL: repository.remoteURL))
        let identity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let executor = RacingUpdateGitExecutor(
            client: client,
            checkout: repository.checkout,
            intervention: .dirtyBeforeFailedFastForward
        )
        let persistence = Persistence(
            directoryURL: temporaryDirectory.appendingPathComponent("precondition-dirty-data")
        )
        let runner = UpdateRunner(
            gitInspector: client,
            gitExecutor: executor,
            audit: AuditEvidence(persistence: persistence)
        )
        let preparation = try await runner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: identity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: entranceFacts),
            affectedSkills: [UpdateAffectedSkill(identity: identity, displayName: "One")]
        ))
        guard case .ready(let plan) = preparation else { return XCTFail("预期确认计划") }

        do {
            _ = try await runner.executeConfirmed(plan)
            XCTFail("ff 失败后重查命中 dirty 必须按前置条件变化处理")
        } catch let failure as UpdateRunFailure {
            XCTAssertEqual(failure.reason, .preconditionChanged)
            XCTAssertEqual(failure.blockingState, .dirty)
            XCTAssertEqual(failure.displayName, "更新前置条件已变化")
            XCTAssertEqual(failure.recoveryDirection, CheckoutGitState.dirty.recoveryDirection)
            XCTAssertNotEqual(failure.recoveryDirection, UpdateRunFailureReason.commandFailure.recoveryDirection)
        } catch {
            XCTFail("dirty 阻断必须返回稳定 typed failure，实际为 \(error)")
        }

        let currentFacts = await client.inspectCheckout(
            at: repository.checkout.path,
            scope: .afterSuccessfulCheck
        )
        XCTAssertEqual(CheckoutEligibility.evaluate(facts: currentFacts, sourceKey: sourceKey), .dirty)
        XCTAssertEqual(currentFacts.head?.sha, plan.currentHeadSHA)
        let fastForwardCount = await executor.fastForwardCount
        XCTAssertEqual(fastForwardCount, 1, "失败不得自动重试")
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.last?.updateFailureReason, "precondition-changed")
    }

    func testUpdateRunScratchClassifiesInstantDivergenceAsFastForwardRejectedWithoutRollback() async throws {
        let repository = try makeUpdateRepository(named: "update-ff-rejected")
        let client = GitClient()
        try await client.fetch(remote: "origin", upstreamRef: "origin/main", at: repository.checkout.path)
        let entranceFacts = await client.inspectCheckout(
            at: repository.checkout.path,
            scope: .afterSuccessfulCheck
        )
        let sourceKey = try XCTUnwrap(SkillSourceKey.normalize(remoteURL: repository.remoteURL))
        let identity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let executor = RacingUpdateGitExecutor(
            client: client,
            checkout: repository.checkout,
            intervention: .divergeBeforeFastForward
        )
        let persistence = Persistence(directoryURL: temporaryDirectory.appendingPathComponent("ff-rejected-data"))
        let runner = UpdateRunner(
            gitInspector: client,
            gitExecutor: executor,
            audit: AuditEvidence(persistence: persistence)
        )
        let preparation = try await runner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: identity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: entranceFacts),
            affectedSkills: [UpdateAffectedSkill(identity: identity, displayName: "One")]
        ))
        guard case .ready(let plan) = preparation else { return XCTFail("预期确认计划") }

        do {
            _ = try await runner.executeConfirmed(plan)
            XCTFail("执行瞬间分叉必须拒绝 ff-only")
        } catch let failure as UpdateRunFailure {
            XCTAssertEqual(failure.reason, .fastForwardRejected)
        } catch {
            XCTFail("分叉必须返回稳定失败类，实际为 \(error)")
        }

        let currentFacts = await client.inspectCheckout(
            at: repository.checkout.path,
            scope: .afterSuccessfulCheck
        )
        guard case .diverged = currentFacts.relativePosition else {
            return XCTFail("外部分叉事实必须保留，实际为 \(currentFacts.relativePosition)")
        }
        XCTAssertFalse(currentFacts.dirty.isDirty)
        XCTAssertNotEqual(currentFacts.head?.sha, plan.targetSHA, "Pagugu 不得自动回滚外部提交")
        let fastForwardCount = await executor.fastForwardCount
        XCTAssertEqual(fastForwardCount, 1, "失败不得自动重试")
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.last?.updateFailureReason, "ff-rejected")
    }

    func testUpdateRunScratchClassifiesIncompletePostVerifyAfterExitZeroWithoutRollback() async throws {
        let repository = try makeUpdateRepository(named: "update-verification-failed")
        let client = GitClient()
        try await client.fetch(remote: "origin", upstreamRef: "origin/main", at: repository.checkout.path)
        let entranceFacts = await client.inspectCheckout(
            at: repository.checkout.path,
            scope: .afterSuccessfulCheck
        )
        let sourceKey = try XCTUnwrap(SkillSourceKey.normalize(remoteURL: repository.remoteURL))
        let identity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let executor = RacingUpdateGitExecutor(
            client: client,
            checkout: repository.checkout,
            intervention: .dirtyAfterSuccessfulFastForward
        )
        let persistence = Persistence(directoryURL: temporaryDirectory.appendingPathComponent("verification-data"))
        let runner = UpdateRunner(
            gitInspector: client,
            gitExecutor: executor,
            audit: AuditEvidence(persistence: persistence)
        )
        let preparation = try await runner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: identity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: entranceFacts),
            affectedSkills: [UpdateAffectedSkill(identity: identity, displayName: "One")]
        ))
        guard case .ready(let plan) = preparation else { return XCTFail("预期确认计划") }

        do {
            _ = try await runner.executeConfirmed(plan)
            XCTFail("ff exit 0 但 post-verify 不全时必须失败")
        } catch let failure as UpdateRunFailure {
            XCTAssertEqual(failure.reason, .verificationFailed)
        } catch {
            XCTFail("post-verify 必须返回稳定失败类，实际为 \(error)")
        }

        XCTAssertEqual(
            try updateGit(["rev-parse", "HEAD"], at: repository.checkout)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            plan.targetSHA,
            "已完成的 ff 不得因验证失败自动回滚"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: repository.checkout.appendingPathComponent("external-residue.txt").path
            ),
            "外部残留必须保留给实时 Git Fact 呈现"
        )
        let fastForwardCount = await executor.fastForwardCount
        XCTAssertEqual(fastForwardCount, 1, "验证失败不得自动重试")
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.last?.updateFailureReason, "verification-failed")
    }

    func testUpdateRunScratchClassifiesTipChangeAfterConfirmationWithoutMovingHead() async throws {
        let repository = try makeUpdateRepository(named: "update-tip-changed")
        let client = GitClient()
        try await client.fetch(remote: "origin", upstreamRef: "origin/main", at: repository.checkout.path)
        let entranceFacts = await client.inspectCheckout(
            at: repository.checkout.path,
            scope: .afterSuccessfulCheck
        )
        let sourceKey = try XCTUnwrap(SkillSourceKey.normalize(remoteURL: repository.remoteURL))
        let identity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let persistence = Persistence(directoryURL: temporaryDirectory.appendingPathComponent("tip-data"))
        let runner = UpdateRunner(
            gitInspector: client,
            gitExecutor: client,
            audit: AuditEvidence(persistence: persistence)
        )
        let preparation = try await runner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: identity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: entranceFacts),
            affectedSkills: [UpdateAffectedSkill(identity: identity, displayName: "One")]
        ))
        guard case .ready(let plan) = preparation else { return XCTFail("预期确认计划") }

        try writeUpdateFile("second remote advance", to: repository.peer.appendingPathComponent("tracked.txt"))
        try updateGit(["add", "tracked.txt"], at: repository.peer)
        try updateGit(["commit", "-m", "second remote advance"], at: repository.peer)
        try updateGit(["push", "origin", "main"], at: repository.peer)
        try await client.fetch(remote: "origin", upstreamRef: "origin/main", at: repository.checkout.path)

        do {
            _ = try await runner.executeConfirmed(plan)
            XCTFail("确认后 remote tip 漂移必须 fail closed")
        } catch let failure as UpdateRunFailure {
            XCTAssertEqual(failure.reason, .tipChanged)
            XCTAssertTrue(failure.recoveryDirection.contains("重新发起更新"))
        } catch {
            XCTFail("tip 漂移必须返回稳定失败类，实际为 \(error)")
        }

        XCTAssertEqual(
            try updateGit(["rev-parse", "HEAD"], at: repository.checkout)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            plan.currentHeadSHA
        )
        XCTAssertEqual(try updateGit(["status", "--porcelain"], at: repository.checkout), "")
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.last?.updateFailureReason, "tip-changed")
    }

    func testUpdateRunScratchSuccessBindsExactPlanFastForwardsOneCheckoutAndWritesTwoAuditRecords() async throws {
        let repository = try makeUpdateRepository(named: "update-success")
        let client = GitClient()
        try await client.fetch(remote: "origin", upstreamRef: "origin/main", at: repository.checkout.path)
        let entranceFacts = await client.inspectCheckout(
            at: repository.checkout.path,
            scope: .afterSuccessfulCheck
        )
        let sourceKey = try XCTUnwrap(SkillSourceKey.normalize(remoteURL: repository.remoteURL))
        XCTAssertEqual(CheckoutEligibility.evaluate(facts: entranceFacts, sourceKey: sourceKey), .updateAvailable)
        let selectedIdentity = SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/one")
        let affectedSkills = [
            UpdateAffectedSkill(identity: selectedIdentity, displayName: "One"),
            UpdateAffectedSkill(
                identity: SkillIdentity(sourceKey: sourceKey, repositoryRelativePath: "skills/two"),
                displayName: "Two"
            ),
        ]
        let copiedInstallation = temporaryDirectory.appendingPathComponent("copied-installation/SKILL.md")
        try writeUpdateFile("unchanged copy", to: copiedInstallation)
        let copiedBytesBefore = try Data(contentsOf: copiedInstallation)
        let postMergeEvidence = temporaryDirectory.appendingPathComponent("post-merge-ran")
        let hook = try updateGitPath("hooks/post-merge", in: repository.checkout)
        try writeUpdateFile("#!/bin/sh\ntouch '\(postMergeEvidence.path)'\n", to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        let persistence = Persistence(directoryURL: temporaryDirectory.appendingPathComponent("data"))
        let runner = UpdateRunner(
            gitInspector: client,
            gitExecutor: client,
            audit: AuditEvidence(persistence: persistence)
        )

        let preparation = try await runner.prepareUpdate(request: UpdateRunRequest(
            skillIdentity: selectedIdentity,
            target: CheckRunTarget(sourceKey: sourceKey, facts: entranceFacts),
            affectedSkills: affectedSkills
        ))
        guard case .ready(let plan) = preparation else {
            return XCTFail("behind-only 检出重查后应进入精确计划确认")
        }
        let expectedTarget = try updateGit(["rev-parse", "origin/main"], at: repository.checkout)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(plan.skillIdentity, selectedIdentity)
        XCTAssertEqual(plan.checkoutCanonicalPath, repository.checkout.path)
        XCTAssertEqual(plan.branchName, "main")
        XCTAssertEqual(plan.upstreamRefName, "origin/main")
        XCTAssertEqual(plan.currentHeadSHA, entranceFacts.head?.sha)
        XCTAssertEqual(plan.targetSHA, expectedTarget)
        XCTAssertEqual(plan.behindCount, 1)
        XCTAssertEqual(plan.affectedSkills, affectedSkills)
        XCTAssertEqual(plan.impactStatement, "仅 fast-forward 此工作树；不动其他检出，不写任何安装目录。")

        let success = try await runner.executeConfirmed(plan)

        XCTAssertEqual(success.postVerificationFacts.head?.sha, expectedTarget)
        XCTAssertEqual(
            CheckoutEligibility.evaluate(facts: success.postVerificationFacts, sourceKey: sourceKey),
            .upToDate
        )
        XCTAssertFalse(success.postVerificationFacts.dirty.isDirty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: postMergeEvidence.path))
        XCTAssertEqual(try Data(contentsOf: copiedInstallation), copiedBytesBefore)
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.count, 2)
        XCTAssertEqual(audit.records.map(\.action), [.updateRun, .updateRun])
        XCTAssertEqual(audit.records.map(\.updateRunID), [plan.runID, plan.runID])
        XCTAssertEqual(audit.records.map(\.updateRunPhase), [.started, .terminal])
        XCTAssertNil(audit.records[0].outcome)
        XCTAssertEqual(audit.records[1].outcome, .success)
        XCTAssertEqual(audit.records[0].updateRunPlan?.targetSHA, expectedTarget)
        XCTAssertEqual(audit.records[0].updateRunPlan?.affectedSkills.count, 2)
    }

    private func collect(_ stream: AsyncStream<CheckRunEvent>) async -> [CheckRunEvent] {
        var events: [CheckRunEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private func facts(
        path: String,
        headSHA: String = "head",
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
            head: .branch(name: "main", sha: headSHA),
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

    private struct UpdateRepository {
        let checkout: URL
        let peer: URL
        let remoteURL: String
    }

    private func makeUpdateRepository(named name: String) throws -> UpdateRepository {
        let checkout = temporaryDirectory.appendingPathComponent(name)
        let remote = temporaryDirectory.appendingPathComponent("\(name)-remote.git")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try updateGit(["init", "-b", "main"], at: checkout)
        try updateGit(["config", "user.name", "Pagugu Test"], at: checkout)
        try updateGit(["config", "user.email", "pagugu@example.invalid"], at: checkout)
        try writeUpdateFile("initial", to: checkout.appendingPathComponent("tracked.txt"))
        try writeUpdateFile("---\nname: one\n---\n", to: checkout.appendingPathComponent("skills/one/SKILL.md"))
        try writeUpdateFile("---\nname: two\n---\n", to: checkout.appendingPathComponent("skills/two/SKILL.md"))
        try updateGit(["add", "tracked.txt", "skills"], at: checkout)
        try updateGit(["commit", "-m", "initial"], at: checkout)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try updateGit(["init", "--bare"], at: remote)
        let remoteURL = "file://localhost\(remote.path)"
        try updateGit(["remote", "add", "origin", remoteURL], at: checkout)
        try updateGit(["push", "-u", "origin", "main"], at: checkout)

        let peer = temporaryDirectory.appendingPathComponent("\(name)-peer")
        try updateGit(["clone", "--branch", "main", remoteURL, peer.path], at: temporaryDirectory)
        try updateGit(["config", "user.name", "Pagugu Test"], at: peer)
        try updateGit(["config", "user.email", "pagugu@example.invalid"], at: peer)
        try writeUpdateFile("remote advance", to: peer.appendingPathComponent("tracked.txt"))
        try updateGit(["add", "tracked.txt"], at: peer)
        try updateGit(["commit", "-m", "remote advance"], at: peer)
        try updateGit(["push", "origin", "main"], at: peer)
        return UpdateRepository(checkout: checkout, peer: peer, remoteURL: remoteURL)
    }

    private func updateGitPath(_ name: String, in repository: URL) throws -> URL {
        let path = try updateGit(["rev-parse", "--git-path", name], at: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : repository.appendingPathComponent(path)
    }

    @discardableResult
    private func updateGit(_ arguments: [String], at directory: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "UpdateGitTest",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr]
            )
        }
        return stdout
    }

    private func writeUpdateFile(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }

    private actor RacingUpdateGitExecutor: GitExecuting {
        enum Intervention: Sendable {
            case dirtyBeforeFailedFastForward
            case divergeBeforeFastForward
            case dirtyAfterSuccessfulFastForward
        }

        let client: GitClient
        let checkout: URL
        let intervention: Intervention
        private(set) var fastForwardCount = 0

        init(client: GitClient, checkout: URL, intervention: Intervention) {
            self.client = client
            self.checkout = checkout
            self.intervention = intervention
        }

        func fetch(remote: String, upstreamRef: String, at checkoutPath: String) async throws {
            try await client.fetch(remote: remote, upstreamRef: upstreamRef, at: checkoutPath)
        }

        func fastForward(to targetSHA: String, at checkoutPath: String) async throws {
            fastForwardCount += 1
            switch intervention {
            case .dirtyBeforeFailedFastForward:
                try Self.write("external local change", to: checkout.appendingPathComponent("tracked.txt"))
                try await client.fastForward(to: targetSHA, at: checkoutPath)
            case .divergeBeforeFastForward:
                try Self.write("external local advance", to: checkout.appendingPathComponent("tracked.txt"))
                try Self.git(["add", "tracked.txt"], at: checkout)
                try Self.git(["commit", "-m", "external local advance"], at: checkout)
                try await client.fastForward(to: targetSHA, at: checkoutPath)
            case .dirtyAfterSuccessfulFastForward:
                try await client.fastForward(to: targetSHA, at: checkoutPath)
                try Self.write("external residue", to: checkout.appendingPathComponent("external-residue.txt"))
            }
        }

        private static func git(_ arguments: [String], at directory: URL) throws {
            let process = Process()
            let error = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = error
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let stderr = String(
                    decoding: error.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                )
                throw NSError(
                    domain: "RacingUpdateGitExecutor",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: stderr]
                )
            }
        }

        private static func write(_ value: String, to url: URL) throws {
            try Data(value.utf8).write(to: url)
        }
    }

    private actor SequencedUpdateGitClient: GitInspecting, GitExecuting {
        let inspections: [CheckoutGitFacts]
        private var inspectionIndex = 0
        private(set) var fastForwardCount = 0

        init(inspections: [CheckoutGitFacts]) {
            self.inspections = inspections
        }

        func fetch(remote: String, upstreamRef: String, at checkoutPath: String) async throws {}

        func fastForward(to targetSHA: String, at checkoutPath: String) async throws {
            fastForwardCount += 1
        }

        func inspectCheckout(at checkoutPath: String, scope: GitInspectionScope) async -> CheckoutGitFacts {
            let index = min(inspectionIndex, inspections.count - 1)
            inspectionIndex += 1
            return inspections[index]
        }
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

        func fastForward(to targetSHA: String, at checkoutPath: String) async throws {
            throw FetchFailure.expected
        }

        func inspectCheckout(at checkoutPath: String, scope: GitInspectionScope) async -> CheckoutGitFacts {
            factsAfterFetch[checkoutPath]!
        }
    }
}
