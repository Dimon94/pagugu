import Foundation

// L3 COORD: Pagugu/Audit/Audit.swift
// INPUT: 已 durable 的映射变更、Check Run terminal，或已确认 UpdatePlan 的 start/success terminal。
// OUTPUT: 唯一窄 append 入口；写失败 fail-open，不回滚主动作或改变 run outcome。
// POS: Audit 语义 owner。物理 IO 复用 Persistence。
// TEST: repo://PaguguTests/RegistryTests.swift、repo://PaguguTests/CheckRunTests.swift。

struct UpdateAuditPlan: Equatable, Sendable {
    struct SkillIdentityValue: Equatable, Sendable {
        let skillSourceKey: String
        let repositoryRelativePath: String
    }

    let skillIdentity: SkillIdentityValue
    let checkoutCanonicalPath: String
    let branchName: String
    let upstreamRefName: String
    let currentHeadSHA: String
    let targetSHA: String
    let behindCount: Int
    let affectedSkills: [SkillIdentityValue]

    fileprivate var persistenceValue: AuditRecord.UpdateRunPlan {
        AuditRecord.UpdateRunPlan(
            skillIdentity: .init(
                skillSourceKey: skillIdentity.skillSourceKey,
                repositoryRelativePath: skillIdentity.repositoryRelativePath
            ),
            checkoutCanonicalPath: checkoutCanonicalPath,
            branchName: branchName,
            upstreamRefName: upstreamRefName,
            currentHeadSHA: currentHeadSHA,
            targetSHA: targetSHA,
            behindCount: behindCount,
            affectedSkills: affectedSkills.map {
                .init(
                    skillSourceKey: $0.skillSourceKey,
                    repositoryRelativePath: $0.repositoryRelativePath
                )
            }
        )
    }
}

struct AuditEvidence: Sendable {
    private let persistence: Persistence

    init(persistence: Persistence) {
        self.persistence = persistence
    }

    func recordSourceMapping(
        outcome: AuditRecord.Outcome,
        installationCanonicalPath: String,
        target: SourceMappingRecord
    ) async {
        let record = AuditRecord(
            id: UUID().uuidString,
            recordedAt: Date(),
            outcome: outcome,
            installationCanonicalPath: installationCanonicalPath,
            target: target
        )
        try? await persistence.appendAuditEvidence(record)
    }

    // L4 IN: runID 与 plan 来自用户已确认的同一冻结 UpdatePlan。
    // OUT: best-effort append 一条无 outcome 的 start；失败不阻断执行。
    // TEST: repo://PaguguTests/CheckRunTests.swift::testUpdateRunScratchSuccessBindsExactPlanFastForwardsOneCheckoutAndWritesTwoAuditRecords。
    func recordUpdateStarted(runID: String, plan: UpdateAuditPlan) async {
        let record = AuditRecord(
            id: UUID().uuidString,
            recordedAt: Date(),
            updateRunID: runID,
            phase: .started,
            plan: plan.persistenceValue
        )
        try? await persistence.appendAuditEvidence(record)
    }

    // L4 IN: 仅在 ff-only 与 post-verify 全部成功后调用，runID/plan 必须与 start 相同。
    // OUT: best-effort append success terminal；失败不改变已验证的 Git 结果。
    // TEST: repo://PaguguTests/CheckRunTests.swift::testUpdateRunScratchSuccessBindsExactPlanFastForwardsOneCheckoutAndWritesTwoAuditRecords。
    func recordUpdateSucceeded(runID: String, plan: UpdateAuditPlan) async {
        let record = AuditRecord(
            id: UUID().uuidString,
            recordedAt: Date(),
            updateRunID: runID,
            phase: .terminal,
            plan: plan.persistenceValue,
            outcome: .success
        )
        try? await persistence.appendAuditEvidence(record)
    }

    func recordCheckRun(
        outcome: AuditRecord.Outcome,
        checkableCount: Int,
        succeededCount: Int,
        failedCount: Int,
        skippedCount: Int
    ) async {
        let record = AuditRecord(
            id: UUID().uuidString,
            recordedAt: Date(),
            outcome: outcome,
            checkRunScope: AuditRecord.CheckRunScope(
                checkableCount: checkableCount,
                succeededCount: succeededCount,
                failedCount: failedCount,
                skippedCount: skippedCount
            )
        )
        try? await persistence.appendAuditEvidence(record)
    }
}
