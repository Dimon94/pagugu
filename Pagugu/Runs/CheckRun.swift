import Foundation

// L3 COORD: Pagugu/Runs/CheckRun.swift
// POS: Runs 模块（ADR-0009 §5）。owns 全量 Check Run 的冻结 scope、顺序 fetch、身份复核与逐项事件。
// TEST: repo://PaguguTests/CheckRunTests.swift。

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

    init(
        gitInspector: any GitInspecting,
        gitExecutor: any GitExecuting,
        registry: AppRegistry
    ) {
        self.gitInspector = gitInspector
        self.gitExecutor = gitExecutor
        self.registry = registry
    }

    static func notApplicableState(for target: CheckRunTarget) -> CheckoutGitState? {
        let state = CheckoutEligibility.evaluate(facts: target.facts, sourceKey: target.sourceKey)
        return skipStates.contains(state) ? state : nil
    }

    // L6 CHAIN: 冻结 scope → 先发布不适用项 → 顺序 fetch → 重读身份 → durable 落槽 → 逐项发布 → 汇总。
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
                continuation.yield(.finished(CheckRunSummary(
                    outcome: outcome,
                    succeeded: succeeded,
                    failed: failed,
                    skipped: skipped.count
                )))
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
