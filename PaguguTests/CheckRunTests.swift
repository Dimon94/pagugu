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
        XCTAssertTrue(audit.records.isEmpty, "确认前 noop/阻断不得写 start")
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
        } catch let error as UpdateRunContractError {
            XCTAssertEqual(error, .preconditionChanged)
            XCTAssertFalse(error.recoveryDirection.isEmpty)
        } catch {
            XCTFail("HEAD 漂移必须保留稳定 typed error，实际为 \(error)")
        }
        let fastForwardCount = await git.fastForwardCount
        XCTAssertEqual(fastForwardCount, 0)
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
        } catch let error as UpdateRunContractError {
            XCTAssertEqual(error, .verificationFailed)
        } catch {
            XCTFail("post-verify 必须返回稳定 typed error，实际为 \(error)")
        }
        let fastForwardCount = await git.fastForwardCount
        XCTAssertEqual(fastForwardCount, 1)
        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.map(\.updateRunPhase), [.started])
        XCTAssertNil(audit.records.first?.outcome)
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

    private struct UpdateRepository {
        let checkout: URL
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
        return UpdateRepository(checkout: checkout, remoteURL: remoteURL)
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
