import Foundation

// L3 COORD: Pagugu/Audit/Audit.swift
// INPUT: 已 durable 的映射变更、Check Run terminal，或 Update Run 的 target/plan 与 started/terminal 语义。
// OUTPUT: 唯一窄 append 入口；写失败 fail-open，不回滚主动作或改变 run outcome；
//         读取只服务 UI；清空只删审计集合。
// POS: Audit 语义 owner（ADR-0007）。owns 呈现投影派生（孤儿判定、outcome/reason 显示）；物理 IO 复用 Persistence。
// TEST: repo://PaguguTests/RegistryTests.swift、repo://PaguguTests/CheckRunTests.swift、
//       repo://PaguguTests/AppModelTests.swift（呈现派生）。

/// 「最近活动」一条摘要项：Update Run 两段记录折叠为一项，孤儿开始折叠为「结果未知（已中断）」。
/// 呈现快照：outcome/reason 中文名与恢复方向在 View 按 code 取当前合同文案（ADR-0007 §4）。
struct AuditActivityItem: Identifiable, Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case record(AuditRecord.Outcome)
        /// 只有开始没有终态的 Update 记录。永不解释为正在运行，重启后不补完改写。
        case interruptedUnknown
    }

    let record: AuditRecord
    let outcome: Outcome

    var id: String { record.id }
    var action: AuditRecord.Action { record.action }
    var recordedAt: Date { record.recordedAt }

    /// 失败原因 code；孤儿开始固定为 interrupted-unknown。
    var failureReasonCode: String? {
        switch outcome {
        case .interruptedUnknown:
            return UpdateRunFailureReason.interruptedUnknown.rawValue
        case .record:
            return record.updateFailureReason
        }
    }

    /// 关联 Skill 的导航身份快照；Check Run 无单一对象。
    var skillIdentity: (sourceKey: String, repositoryRelativePath: String)? {
        let snapshot = record.updateRunPlan?.skillIdentity ?? record.updateRunTarget?.skillIdentity
        guard let snapshot else { return nil }
        return (snapshot.skillSourceKey, snapshot.repositoryRelativePath)
    }

    var title: String {
        switch record.action {
        case .checkRun: return "全量检查"
        case .updateRun: return "更新"
        case .sourceMapping:
            return record.outcome == .deleted ? "删除来源映射" : "创建来源映射"
        }
    }

    var outcomeDisplayName: String {
        switch outcome {
        case .interruptedUnknown: return "结果未知（已中断）"
        case .record(let value):
            switch value {
            case .complete: return "完成"
            case .partial: return "部分完成"
            case .failed: return "失败"
            case .success: return "成功"
            case .cancelled: return "已取消"
            case .created: return "已创建"
            case .deleted: return "已删除"
            }
        }
    }
}

/// 审计历史的 UI 投影。unavailable = 集合损坏已丢弃重建，呈现「历史不可用」（fail-open）。
struct AuditHistoryProjection: Equatable, Sendable {
    static let unavailableMessage = "历史不可用"

    let isUnavailable: Bool
    /// 最新在前。
    let items: [AuditActivityItem]
}

enum AuditPresentation {
    // L4 IN: Persistence 的原始记录集合（nil = 损坏已 quarantine）。
    // OUT: 最新在前的摘要投影；terminal 记录吞掉同 run 的 started；孤儿 started 折叠为
    //      interruptedUnknown。永不把历史当作当前状态或运行态。
    // TEST: repo://PaguguTests/AppModelTests.swift::testAuditProjectionCollapsesTerminalAndFlagsOrphanStartedAsInterrupted。
    static func project(_ document: AuditDocument?) -> AuditHistoryProjection {
        guard let document else {
            return AuditHistoryProjection(isUnavailable: true, items: [])
        }
        // 磁盘 append 顺序即发生顺序；recordedAt 精度有限，不参与排序。
        // 每个 run 的 terminal 吞掉同 run 的 started（同 run 只留最新一项）；无 terminal 的
        // 孤儿 started 折叠为 interruptedUnknown。started 在 terminal 之后写入时按 recordedAt 取最新。
        var terminalRunIDs: Set<String> = []
        for record in document.records where record.updateRunPhase == .terminal {
            if let runID = record.updateRunID { terminalRunIDs.insert(runID) }
        }
        var collapsedByRunID: [String: AuditActivityItem] = [:]
        var orderedItems: [AuditActivityItem] = []
        for record in document.records {
            switch record.action {
            case .checkRun, .sourceMapping:
                guard let outcome = record.outcome else { continue }
                orderedItems.append(AuditActivityItem(record: record, outcome: .record(outcome)))
            case .updateRun:
                guard let runID = record.updateRunID else { continue }
                switch record.updateRunPhase {
                case .terminal:
                    guard let outcome = record.outcome else { continue }
                    let item = AuditActivityItem(record: record, outcome: .record(outcome))
                    collapsedByRunID[runID] = item
                    if let index = orderedItems.firstIndex(where: { $0.record.updateRunID == runID }) {
                        orderedItems[index] = item
                    } else {
                        orderedItems.append(item)
                    }
                case .started:
                    guard !terminalRunIDs.contains(runID), collapsedByRunID[runID] == nil else { continue }
                    let item = AuditActivityItem(record: record, outcome: .interruptedUnknown)
                    collapsedByRunID[runID] = item
                    orderedItems.append(item)
                case .none:
                    continue
                }
            }
        }
        return AuditHistoryProjection(isUnavailable: false, items: orderedItems.reversed())
    }
}

struct UpdateAuditTarget: Equatable, Sendable {
    let skillIdentity: UpdateAuditPlan.SkillIdentityValue
    let checkoutCanonicalPath: String
    let branchName: String
    let upstreamRefName: String

    fileprivate var persistenceValue: AuditRecord.UpdateRunTarget {
        AuditRecord.UpdateRunTarget(
            skillIdentity: .init(
                skillSourceKey: skillIdentity.skillSourceKey,
                repositoryRelativePath: skillIdentity.repositoryRelativePath
            ),
            checkoutCanonicalPath: checkoutCanonicalPath,
            branchName: branchName,
            upstreamRefName: upstreamRefName
        )
    }
}

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

    fileprivate var target: UpdateAuditTarget {
        UpdateAuditTarget(
            skillIdentity: skillIdentity,
            checkoutCanonicalPath: checkoutCanonicalPath,
            branchName: branchName,
            upstreamRefName: upstreamRefName
        )
    }

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

    // L4 IN: plan 来自 prepareUpdate 的冻结确认值，且用户尚未确认执行。
    // OUT: best-effort append terminal-only cancelled；不写 start，不触发 Git 副作用。
    func recordUpdateCancelled(runID: String, plan: UpdateAuditPlan) async {
        let record = AuditRecord(
            id: UUID().uuidString,
            recordedAt: Date(),
            updateRunID: runID,
            phase: .terminal,
            plan: plan.persistenceValue,
            outcome: .cancelled
        )
        try? await persistence.appendAuditEvidence(record)
    }

    // L4 IN: reason 必须来自 Runs 的九类稳定集合；确认前允许只有 target，确认后同时带 plan。
    // OUT: best-effort append terminal failed；不保存原始 Git 输出、exit code 或恢复文案。
    func recordUpdateFailed(
        runID: String,
        target: UpdateAuditTarget,
        plan: UpdateAuditPlan? = nil,
        reasonCode: String
    ) async {
        let record = AuditRecord(
            id: UUID().uuidString,
            recordedAt: Date(),
            updateRunID: runID,
            phase: .terminal,
            target: plan == nil ? target.persistenceValue : nil,
            plan: plan?.persistenceValue,
            outcome: .failed,
            failureReason: reasonCode
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

    /// 读取只服务 UI 呈现；读取失败 fail-open，由呈现层标注「历史不可用」。
    func history() async -> AuditHistoryProjection {
        AuditPresentation.project(await persistence.loadAuditDocument())
    }

    /// 清空只删审计集合：不动 Registry、Skill Source 或 Git，不留墓碑；写失败 fail-open。
    func clearHistory() async {
        try? await persistence.clearAuditEvidence()
    }
}
