import Foundation

// L3 COORD: Pagugu/Runs/CheckRun.swift
// POS: Runs 模块（ADR-0009 §5）。owns 全量 Check Run，以及 Update Run 的 fetch 重查、
//      精确 SHA 计划、确认后漂移比对、ff-only、post-verify 与 start/success 审计调用。
// TEST: repo://PaguguTests/CheckRunTests.swift（Check Run + 零网络 scratch Update Run 成功路径）。

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

    fileprivate var auditPlan: UpdateAuditPlan {
        UpdateAuditPlan(
            skillIdentity: auditIdentity(skillIdentity),
            checkoutCanonicalPath: checkoutCanonicalPath,
            branchName: branchName,
            upstreamRefName: upstreamRefName,
            currentHeadSHA: currentHeadSHA,
            targetSHA: targetSHA,
            behindCount: behindCount,
            affectedSkills: affectedSkills.map { auditIdentity($0.identity) }
        )
    }

    private func auditIdentity(_ identity: SkillIdentity) -> UpdateAuditPlan.SkillIdentityValue {
        UpdateAuditPlan.SkillIdentityValue(
            skillSourceKey: identity.sourceKey.registryValue,
            repositoryRelativePath: identity.repositoryRelativePath
        )
    }
}

enum UpdatePreparation: Equatable, Sendable {
    case ready(UpdatePlan)
    case upToDate
    case blocked(CheckoutGitState)
}

struct UpdateExecutionSuccess: Equatable, Sendable {
    let plan: UpdatePlan
    let postVerificationFacts: CheckoutGitFacts
}

enum UpdateRunContractError: Error, Equatable, Sendable {
    case invalidRequest
    case identityChanged
    case preconditionChanged
    case tipChanged
    case verificationFailed

    var recoveryDirection: String {
        switch self {
        case .invalidRequest:
            return "重新扫描并从当前 Skill 状态重新发起更新。"
        case .identityChanged:
            return "重新扫描后重新检查。"
        case .preconditionChanged, .tipChanged:
            return "重新发起更新，让 Pagugu 重新重查并确认计划。"
        case .verificationFailed:
            return "在终端核对该工作树状态后重新扫描。"
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
    // FAIL: 输入/身份漂移抛 UpdateRunContractError；Git 失败保留 GitCommandError 因果。零执行副作用。
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
              let upstream = request.target.facts.upstream else {
            throw UpdateRunContractError.invalidRequest
        }

        try await gitExecutor.fetch(
            remote: upstream.remoteName,
            upstreamRef: upstream.ref,
            at: request.target.facts.checkoutPath
        )
        let facts = await gitInspector.inspectCheckout(
            at: request.target.facts.checkoutPath,
            scope: .afterSuccessfulCheck
        )
        guard CheckoutEligibility.identityDigest(
            facts: facts,
            sourceKey: request.target.sourceKey
        ) == entranceIdentity else {
            throw UpdateRunContractError.identityChanged
        }

        let state = CheckoutEligibility.evaluate(facts: facts, sourceKey: request.target.sourceKey)
        if state == .upToDate { return .upToDate }
        guard state == .updateAvailable else { return .blocked(state) }
        guard let head = facts.head,
              let branchName = head.branchName,
              let currentUpstream = facts.upstream,
              let targetSHA = currentUpstream.sha,
              case .behindOnly(let behindCount) = facts.relativePosition else {
            throw UpdateRunContractError.invalidRequest
        }

        return .ready(UpdatePlan(
            runID: UUID().uuidString,
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

    // L4 IN: plan 是 prepareUpdate 返回且由用户明确确认的冻结值。
    // OUT: 仅在精确 SHA ff 与 post-verify 成功后返回事实，并写同 run ID 的 start/success 审计。
    // FAIL: 漂移/验证失败抛稳定 UpdateRunContractError；Git 错误保留因果。失败零重试零回滚。
    // TEST: repo://PaguguTests/CheckRunTests.swift（HEAD 漂移 fail closed、scratch 成功与审计）。
    // L6 CHAIN: 确认绑定写 start → 漂移/资格重查 → 精确 SHA ff-only → post-verify →
    //           成功 terminal 审计。失败九类与 terminal 记录由后续 #24 收口。
    func executeConfirmed(_ plan: UpdatePlan) async throws -> UpdateExecutionSuccess {
        await audit.recordUpdateStarted(runID: plan.runID, plan: plan.auditPlan)
        let executionFacts = await gitInspector.inspectCheckout(
            at: plan.checkoutCanonicalPath,
            scope: .afterSuccessfulCheck
        )
        guard CheckoutEligibility.identityDigest(
            facts: executionFacts,
            sourceKey: plan.sourceKey
        ) == plan.identityDigest else {
            throw UpdateRunContractError.identityChanged
        }
        guard executionFacts.head?.sha == plan.currentHeadSHA else {
            throw UpdateRunContractError.preconditionChanged
        }
        guard executionFacts.upstream?.sha == plan.targetSHA else {
            throw UpdateRunContractError.tipChanged
        }
        guard CheckoutEligibility.evaluate(
            facts: executionFacts,
            sourceKey: plan.sourceKey
        ) == .updateAvailable else {
            throw UpdateRunContractError.preconditionChanged
        }

        try await gitExecutor.fastForward(to: plan.targetSHA, at: plan.checkoutCanonicalPath)
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
            throw UpdateRunContractError.verificationFailed
        }

        await audit.recordUpdateSucceeded(runID: plan.runID, plan: plan.auditPlan)
        return UpdateExecutionSuccess(plan: plan, postVerificationFacts: postFacts)
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
