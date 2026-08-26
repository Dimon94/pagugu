import Foundation

// L3 COORD: Pagugu/Runs/CheckRun.swift
// POS: Runs 模块（ADR-0009 §5）。owns 全量 Check Run，以及 Update Run 的 fetch 重查、
//      精确 SHA 计划、确认取消、漂移比对、ff-only、post-verify、九类失败与 terminal 审计调用。
// TEST: repo://PaguguTests/CheckRunTests.swift（Check Run + 零网络 scratch Update Run 成功/失败路径）。

struct CheckRunTarget: Sendable {
    let sourceKey: SkillSourceKey
    let facts: CheckoutGitFacts

    func matches(_ other: CheckRunTarget) -> Bool {
        guard sourceKey == other.sourceKey, facts.checkoutPath == other.facts.checkoutPath else {
            return false
        }
        let identity = CheckoutEligibility.identityDigest(facts: facts, sourceKey: sourceKey)
        let otherIdentity = CheckoutEligibility.identityDigest(facts: other.facts, sourceKey: other.sourceKey)
        if identity != nil || otherIdentity != nil { return identity == otherIdentity }
        return facts.gitCommonDirectory == other.facts.gitCommonDirectory &&
            facts.head?.branchName == other.facts.head?.branchName &&
            facts.upstream?.ref == other.facts.upstream?.ref
    }
}

struct CheckRunProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
}

enum CheckRunFailure: String, Equatable, Sendable {
    case fetchFailed = "fetch-failed"
    case observationWriteFailed = "observation-write-failed"

    var message: String {
        switch self {
        case .fetchFailed: return "检查失败。请检查网络与远端权限后重新检查。"
        case .observationWriteFailed: return "观察保存失败。请检查磁盘空间与目录权限后重新检查。"
        }
    }
}

enum CheckRunItemOutcome: Equatable, Sendable {
    case success
    case notApplicable(CheckoutGitState)
    case failed(CheckRunFailure)
    case discarded
}

struct CheckRunItemResult: Equatable, Sendable {
    let checkoutPath: String
    let outcome: CheckRunItemOutcome
}

enum CheckRunOutcome: String, Equatable, Sendable {
    case complete
    case partial
    case failed
}

struct CheckRunSummary: Equatable, Sendable {
    let outcome: CheckRunOutcome
    let succeeded: Int
    let failed: Int
    let skipped: Int
}

enum CheckRunEvent: Equatable, Sendable {
    case started(CheckRunProgress)
    case item(CheckRunItemResult, CheckRunProgress)
    case finished(CheckRunSummary)
}

final class CheckRunner: Sendable {
    private let gitInspector: any GitInspecting
    private let gitExecutor: any GitExecuting
    private let registry: AppRegistry
    private let audit: AuditEvidence

    init(
        gitInspector: any GitInspecting,
        gitExecutor: any GitExecuting,
        registry: AppRegistry,
        audit: AuditEvidence
    ) {
        self.gitInspector = gitInspector
        self.gitExecutor = gitExecutor
        self.registry = registry
        self.audit = audit
    }

    static func notApplicableState(for target: CheckRunTarget) -> CheckoutGitState? {
        let state = CheckoutEligibility.evaluate(facts: target.facts, sourceKey: target.sourceKey)
        return skipStates.contains(state) ? state : nil
    }

    // L6 CHAIN: 冻结 scope → 先发布不适用项 → 顺序 fetch → 重读身份 → durable 落槽 → 逐项发布
    //           → 汇总 → best-effort terminal 审计 → finished。审计失败不改变 summary。
    func startCheck(scope: [CheckRunTarget]) -> AsyncStream<CheckRunEvent> {
        AsyncStream { continuation in
            Task {
                let skipped = scope.compactMap { target -> (CheckRunTarget, CheckoutGitState)? in
                    Self.notApplicableState(for: target).map { (target, $0) }
                }
                let targets = scope.filter { target in
                    Self.notApplicableState(for: target) == nil
                }
                var progress = CheckRunProgress(completed: 0, total: targets.count)
                continuation.yield(.started(progress))
                for (target, state) in skipped {
                    continuation.yield(.item(
                        CheckRunItemResult(checkoutPath: target.facts.checkoutPath, outcome: .notApplicable(state)),
                        progress
                    ))
                }

                var succeeded = 0
                var failed = 0
                for target in targets {
                    let outcome = await check(target)
                    if outcome == .success { succeeded += 1 } else { failed += 1 }
                    progress = CheckRunProgress(completed: progress.completed + 1, total: progress.total)
                    continuation.yield(.item(
                        CheckRunItemResult(checkoutPath: target.facts.checkoutPath, outcome: outcome),
                        progress
                    ))
                }

                let outcome: CheckRunOutcome = failed == 0 ? .complete : (succeeded == 0 ? .failed : .partial)
                let summary = CheckRunSummary(
                    outcome: outcome,
                    succeeded: succeeded,
                    failed: failed,
                    skipped: skipped.count
                )
                await audit.recordCheckRun(
                    outcome: outcome.auditOutcome,
                    checkableCount: targets.count,
                    succeededCount: succeeded,
                    failedCount: failed,
                    skippedCount: skipped.count
                )
                continuation.yield(.finished(summary))
                continuation.finish()
            }
        }
    }

    private func check(_ target: CheckRunTarget) async -> CheckRunItemOutcome {
        guard let identity = CheckoutEligibility.identityDigest(
            facts: target.facts,
            sourceKey: target.sourceKey
        ), let upstream = target.facts.upstream else {
            return .discarded
        }
        do {
            try await gitExecutor.fetch(
                remote: upstream.remoteName,
                upstreamRef: upstream.ref,
                at: target.facts.checkoutPath
            )
        } catch {
            let currentFacts = await gitInspector.inspectCheckout(
                at: target.facts.checkoutPath,
                scope: .localOnly
            )
            guard CheckoutEligibility.identityDigest(
                facts: currentFacts,
                sourceKey: target.sourceKey
            ) == identity else {
                return .discarded
            }
            let observation = CheckoutObservation(
                result: .failure,
                completedAt: Date(),
                remoteTipSHA: nil,
                identityDigest: identity
            )
            do {
                try await registry.recordCheckoutObservation(observation)
            } catch {
                return .failed(.observationWriteFailed)
            }
            return .failed(.fetchFailed)
        }

        let facts = await gitInspector.inspectCheckout(
            at: target.facts.checkoutPath,
            scope: .afterSuccessfulCheck
        )
        guard CheckoutEligibility.identityDigest(facts: facts, sourceKey: target.sourceKey) == identity,
              let remoteTipSHA = facts.upstream?.sha else {
            return .discarded
        }
        let observation = CheckoutObservation(
            result: .success,
            completedAt: Date(),
            remoteTipSHA: remoteTipSHA,
            identityDigest: identity
        )
        do {
            try await registry.recordCheckoutObservation(observation)
            return .success
        } catch {
            return .failed(.observationWriteFailed)
        }
    }

    private static let skipStates: Set<CheckoutGitState> = [
        .noRemote, .detached, .noUpstream, .upstreamMismatch, .siblingConflict,
    ]
}

struct UpdateAffectedSkill: Equatable, Sendable {
    let identity: SkillIdentity
    let displayName: String
}

struct UpdateRunRequest: Sendable {
    let skillIdentity: SkillIdentity
    let target: CheckRunTarget
    let affectedSkills: [UpdateAffectedSkill]
}

struct UpdatePlan: Equatable, Sendable {
    static let impactStatementText = "仅 fast-forward 此工作树；不动其他检出，不写任何安装目录。"

    let runID: String
    let skillIdentity: SkillIdentity
    let checkoutCanonicalPath: String
    let branchName: String
    let upstreamRefName: String
    let currentHeadSHA: String
    let targetSHA: String
    let behindCount: Int
    let affectedSkills: [UpdateAffectedSkill]
    let impactStatement: String
    fileprivate let sourceKey: SkillSourceKey
    fileprivate let identityDigest: CheckoutIdentityDigest

    fileprivate var auditTarget: UpdateAuditTarget {
        UpdateAuditTarget(
            skillIdentity: updateAuditIdentity(skillIdentity),
            checkoutCanonicalPath: checkoutCanonicalPath,
            branchName: branchName,
            upstreamRefName: upstreamRefName
        )
    }

    fileprivate var auditPlan: UpdateAuditPlan {
        UpdateAuditPlan(
            skillIdentity: updateAuditIdentity(skillIdentity),
            checkoutCanonicalPath: checkoutCanonicalPath,
            branchName: branchName,
            upstreamRefName: upstreamRefName,
            currentHeadSHA: currentHeadSHA,
            targetSHA: targetSHA,
            behindCount: behindCount,
            affectedSkills: affectedSkills.map { updateAuditIdentity($0.identity) }
        )
    }
}

private func updateAuditIdentity(_ identity: SkillIdentity) -> UpdateAuditPlan.SkillIdentityValue {
    UpdateAuditPlan.SkillIdentityValue(
        skillSourceKey: identity.sourceKey.registryValue,
        repositoryRelativePath: identity.repositoryRelativePath
    )
}

enum UpdatePreparation: Equatable, Sendable {
    case ready(UpdatePlan)
    case upToDate
    case blocked(CheckoutGitState)
}

// L4 OUT: Update Run 的稳定失败分类。UI 与 Audit 只消费 raw reason code，
//         中文名和恢复方向始终从当前 Runs 合同派生，不持久化文案或原始 Git 输出。
// TEST: repo://PaguguTests/CheckRunTests.swift::testEveryUpdateFailureHasStableCodeChineseNameAndRecoveryDirection。
enum UpdateRunFailureReason: String, CaseIterable, Equatable, Sendable {
    case lockBusy = "lock-busy"
    case identityChanged = "identity-changed"
    case fetchFailure = "fetch-failure"
    case preconditionChanged = "precondition-changed"
    case tipChanged = "tip-changed"
    case fastForwardRejected = "ff-rejected"
    case commandFailure = "command-failure"
    case verificationFailed = "verification-failed"
    case interruptedUnknown = "interrupted-unknown"

    var displayName: String {
        switch self {
        case .lockBusy: return "Git 锁被占用"
        case .identityChanged: return "检出身份已变化"
        case .fetchFailure: return "远端获取失败"
        case .preconditionChanged: return "更新前置条件已变化"
        case .tipChanged: return "远端目标已变化"
        case .fastForwardRejected: return "快速前进被拒绝"
        case .commandFailure: return "Git 命令失败"
        case .verificationFailed: return "更新验证失败"
        case .interruptedUnknown: return "更新结果未知"
        }
    }

    var recoveryDirection: String {
        switch self {
        case .lockBusy:
            return "确认无其他 Git 进程后重新发起更新。"
        case .identityChanged:
            return "重新扫描后重新检查。"
        case .fetchFailure:
            return "在终端验证网络、凭证与远端分支后重新发起更新。"
        case .preconditionChanged:
            return "按当前检出状态的恢复方向处理后重新检查。"
        case .tipChanged:
            return "重新发起更新；Pagugu 会重新重查并确认计划。"
        case .fastForwardRejected:
            return "在终端处理分叉后重新检查。"
        case .commandFailure:
            return "在终端核对 Git 失败原因与仓库状态后重新发起更新。"
        case .verificationFailed:
            return "在终端核对该工作树状态后重新扫描。"
        case .interruptedUnknown:
            return "重新扫描，并按当前 Git 事实处理。"
        }
    }
}

struct UpdateRunFailure: Error, Equatable, Sendable {
    let reason: UpdateRunFailureReason
    let blockingState: CheckoutGitState?

    init(reason: UpdateRunFailureReason, blockingState: CheckoutGitState? = nil) {
        self.reason = reason
        self.blockingState = blockingState
    }

    var displayName: String { reason.displayName }

    var recoveryDirection: String {
        if reason == .preconditionChanged, let blockingState {
            return blockingState.recoveryDirection
        }
        return reason.recoveryDirection
    }
}

struct UpdateExecutionSuccess: Equatable, Sendable {
    let plan: UpdatePlan
    let postVerificationFacts: CheckoutGitFacts
}

enum UpdateRunContractError: Error, Equatable, Sendable {
    case invalidRequest
    case runInProgress

    var recoveryDirection: String {
        switch self {
        case .invalidRequest:
            return "重新扫描并从当前 Skill 状态重新发起更新。"
        case .runInProgress:
            return "等待当前运行完成，或先取消待确认的更新。"
        }
    }
}

final class UpdateRunner: Sendable {
    private let gitInspector: any GitInspecting
    private let gitExecutor: any GitExecuting
    private let audit: AuditEvidence

    init(
        gitInspector: any GitInspecting,
        gitExecutor: any GitExecuting,
        audit: AuditEvidence
    ) {
        self.gitInspector = gitInspector
        self.gitExecutor = gitExecutor
        self.audit = audit
    }

    // L4 IN: request 必须来自当前完整 Scan Result 的 update-available 卡片，且影响 Skill 属于目标检出。
    // OUT: fetch 后按实时事实返回 ready 精确计划、upToDate noop 或一个既有阻断态。
    // FAIL: 输入无效抛合同错误；运行失败归一到九类 UpdateRunFailure 并写 terminal-only failed。
    // TEST: repo://PaguguTests/CheckRunTests.swift（noop、阻断、scratch ready）。
    // L6 CHAIN: 入口事实校验 → 单 upstream fetch → 全事实重查 → 同一 12 态裁决 →
    //           update-available 冻结精确 SHA 计划；up-to-date/阻断态不产生计划。
    func prepareUpdate(request: UpdateRunRequest) async throws -> UpdatePreparation {
        guard request.skillIdentity.sourceKey == request.target.sourceKey,
              !request.affectedSkills.isEmpty,
              request.affectedSkills.contains(where: { $0.identity == request.skillIdentity }),
              request.affectedSkills.allSatisfy({ $0.identity.sourceKey == request.target.sourceKey }),
              CheckoutEligibility.evaluate(
                  facts: request.target.facts,
                  sourceKey: request.target.sourceKey
              ) == .updateAvailable,
              let entranceIdentity = CheckoutEligibility.identityDigest(
                  facts: request.target.facts,
                  sourceKey: request.target.sourceKey
              ),
              let entranceHead = request.target.facts.head,
              let branchName = entranceHead.branchName,
              let upstream = request.target.facts.upstream else {
            throw UpdateRunContractError.invalidRequest
        }
        let runID = UUID().uuidString
        let auditTarget = UpdateAuditTarget(
            skillIdentity: updateAuditIdentity(request.skillIdentity),
            checkoutCanonicalPath: request.target.facts.checkoutPath,
            branchName: branchName,
            upstreamRefName: upstream.ref
        )

        do {
            try await gitExecutor.fetch(
                remote: upstream.remoteName,
                upstreamRef: upstream.ref,
                at: request.target.facts.checkoutPath
            )
        } catch is CancellationError {
            let failure = UpdateRunFailure(reason: .interruptedUnknown)
            await audit.recordUpdateFailed(
                runID: runID,
                target: auditTarget,
                reasonCode: failure.reason.rawValue
            )
            throw failure
        } catch let error as GitCommandError {
            let failure = UpdateRunFailure(
                reason: error.indicatesLockBusy ? .lockBusy : .fetchFailure
            )
            await audit.recordUpdateFailed(
                runID: runID,
                target: auditTarget,
                reasonCode: failure.reason.rawValue
            )
            throw failure
        } catch {
            let failure = UpdateRunFailure(reason: .fetchFailure)
            await audit.recordUpdateFailed(
                runID: runID,
                target: auditTarget,
                reasonCode: failure.reason.rawValue
            )
            throw failure
        }
        let facts = await gitInspector.inspectCheckout(
            at: request.target.facts.checkoutPath,
            scope: .afterSuccessfulCheck
        )
        guard !Task.isCancelled else {
            let failure = UpdateRunFailure(reason: .interruptedUnknown)
            await audit.recordUpdateFailed(
                runID: runID,
                target: auditTarget,
                reasonCode: failure.reason.rawValue
            )
            throw failure
        }
        guard CheckoutEligibility.identityDigest(
            facts: facts,
            sourceKey: request.target.sourceKey
        ) == entranceIdentity else {
            let failure = UpdateRunFailure(reason: identityMismatchReason(facts))
            await audit.recordUpdateFailed(
                runID: runID,
                target: auditTarget,
                reasonCode: failure.reason.rawValue
            )
            throw failure
        }

        let state = CheckoutEligibility.evaluate(facts: facts, sourceKey: request.target.sourceKey)
        if state == .upToDate { return .upToDate }
        guard state == .updateAvailable else {
            await audit.recordUpdateFailed(
                runID: runID,
                target: auditTarget,
                reasonCode: UpdateRunFailureReason.preconditionChanged.rawValue
            )
            return .blocked(state)
        }
        guard let head = facts.head,
              let branchName = head.branchName,
              let currentUpstream = facts.upstream,
              let targetSHA = currentUpstream.sha,
              case .behindOnly(let behindCount) = facts.relativePosition else {
            let failure = UpdateRunFailure(reason: .commandFailure)
            await audit.recordUpdateFailed(
                runID: runID,
                target: auditTarget,
                reasonCode: failure.reason.rawValue
            )
            throw failure
        }

        return .ready(UpdatePlan(
            runID: runID,
            skillIdentity: request.skillIdentity,
            checkoutCanonicalPath: facts.checkoutPath,
            branchName: branchName,
            upstreamRefName: currentUpstream.ref,
            currentHeadSHA: head.sha,
            targetSHA: targetSHA,
            behindCount: behindCount,
            affectedSkills: request.affectedSkills,
            impactStatement: UpdatePlan.impactStatementText,
            sourceKey: request.target.sourceKey,
            identityDigest: entranceIdentity
        ))
    }

    // L4 IN: plan 是 prepareUpdate 返回、但用户在确认页显式取消的冻结值。
    // OUT: 只写 terminal-only cancelled 审计；不写 start，不执行 Git，不保留 run 态。
    func cancelPrepared(_ plan: UpdatePlan) async {
        await audit.recordUpdateCancelled(runID: plan.runID, plan: plan.auditPlan)
    }

    // L4 IN: plan 是 prepareUpdate 返回且由用户明确确认的冻结值。
    // OUT: 仅在精确 SHA ff 与 post-verify 成功后返回事实，并写同 run ID 的 started/success terminal 审计。
    // FAIL: 漂移、命令与验证失败归一到九类 UpdateRunFailure；失败零重试零回滚。
    // TEST: repo://PaguguTests/CheckRunTests.swift（HEAD 漂移 fail closed、scratch 成功与审计）。
    // L6 CHAIN: 确认绑定写 start → 漂移/资格重查 → 精确 SHA ff-only → post-verify →
    //           success/failed terminal 审计。任一失败立即停止，不重试、不回滚。
    func executeConfirmed(_ plan: UpdatePlan) async throws -> UpdateExecutionSuccess {
        await audit.recordUpdateStarted(runID: plan.runID, plan: plan.auditPlan)
        guard !Task.isCancelled else {
            throw await recordFailure(.interruptedUnknown, plan: plan)
        }
        let executionFacts = await gitInspector.inspectCheckout(
            at: plan.checkoutCanonicalPath,
            scope: .afterSuccessfulCheck
        )
        guard !Task.isCancelled else {
            throw await recordFailure(.interruptedUnknown, plan: plan)
        }
        guard CheckoutEligibility.identityDigest(
            facts: executionFacts,
            sourceKey: plan.sourceKey
        ) == plan.identityDigest else {
            throw await recordFailure(identityMismatchReason(executionFacts), plan: plan)
        }
        guard executionFacts.head?.sha == plan.currentHeadSHA else {
            throw await recordFailure(.preconditionChanged, plan: plan)
        }
        guard executionFacts.upstream?.sha == plan.targetSHA else {
            throw await recordFailure(.tipChanged, plan: plan)
        }
        guard CheckoutEligibility.evaluate(
            facts: executionFacts,
            sourceKey: plan.sourceKey
        ) == .updateAvailable else {
            throw await recordFailure(
                .preconditionChanged,
                blockingState: CheckoutEligibility.evaluate(facts: executionFacts, sourceKey: plan.sourceKey),
                plan: plan
            )
        }

        do {
            try await gitExecutor.fastForward(to: plan.targetSHA, at: plan.checkoutCanonicalPath)
        } catch is CancellationError {
            throw await recordFailure(.interruptedUnknown, plan: plan)
        } catch let error as GitCommandError {
            guard !error.indicatesLockBusy else {
                throw await recordFailure(.lockBusy, plan: plan)
            }
            let classification = await classificationAfterFastForwardFailure(plan)
            throw await recordFailure(
                classification.reason,
                blockingState: classification.blockingState,
                plan: plan
            )
        } catch {
            let classification = await classificationAfterFastForwardFailure(plan)
            throw await recordFailure(
                classification.reason,
                blockingState: classification.blockingState,
                plan: plan
            )
        }
        let postFacts = await gitInspector.inspectCheckout(
            at: plan.checkoutCanonicalPath,
            scope: .afterSuccessfulCheck
        )
        guard postFacts.head?.sha == plan.targetSHA,
              postFacts.upstream?.sha == plan.targetSHA,
              !postFacts.dirty.isDirty,
              postFacts.dirty.operations.isEmpty,
              CheckoutEligibility.identityDigest(
                  facts: postFacts,
                  sourceKey: plan.sourceKey
              ) == plan.identityDigest,
              CheckoutEligibility.evaluate(facts: postFacts, sourceKey: plan.sourceKey) == .upToDate else {
            throw await recordFailure(.verificationFailed, plan: plan)
        }

        await audit.recordUpdateSucceeded(runID: plan.runID, plan: plan.auditPlan)
        return UpdateExecutionSuccess(plan: plan, postVerificationFacts: postFacts)
    }

    private func identityMismatchReason(_ facts: CheckoutGitFacts) -> UpdateRunFailureReason {
        switch facts.inspectionFailure {
        case .none, .notAWorkTree:
            return .identityChanged
        case .launchFailed, .timedOut, .commandFailed:
            return .commandFailure
        }
    }

    private func classificationAfterFastForwardFailure(
        _ plan: UpdatePlan
    ) async -> (reason: UpdateRunFailureReason, blockingState: CheckoutGitState?) {
        let currentFacts = await gitInspector.inspectCheckout(
            at: plan.checkoutCanonicalPath,
            scope: .afterSuccessfulCheck
        )
        if case .notAWorkTree = currentFacts.inspectionFailure {
            return (.identityChanged, nil)
        }
        guard CheckoutEligibility.identityDigest(
            facts: currentFacts,
            sourceKey: plan.sourceKey
        ) == plan.identityDigest else {
            let reason: UpdateRunFailureReason = currentFacts.inspectionFailure == nil
                ? .identityChanged
                : .commandFailure
            return (reason, nil)
        }
        if case .diverged = currentFacts.relativePosition {
            return (.fastForwardRejected, nil)
        }
        let state = CheckoutEligibility.evaluate(facts: currentFacts, sourceKey: plan.sourceKey)
        if state == .dirty {
            return (.preconditionChanged, state)
        }
        return (.commandFailure, nil)
    }

    private func recordFailure(
        _ reason: UpdateRunFailureReason,
        blockingState: CheckoutGitState? = nil,
        plan: UpdatePlan
    ) async -> UpdateRunFailure {
        let failure = UpdateRunFailure(reason: reason, blockingState: blockingState)
        await audit.recordUpdateFailed(
            runID: plan.runID,
            target: plan.auditTarget,
            plan: plan.auditPlan,
            reasonCode: reason.rawValue
        )
        return failure
    }
}

private extension CheckRunOutcome {
    var auditOutcome: AuditRecord.Outcome {
        switch self {
        case .complete: return .complete
        case .partial: return .partial
        case .failed: return .failed
        }
    }
}
