import Foundation

// L3 COORD: Pagugu/Audit/Audit.swift
// INPUT: 调用方传入已 durable 的来源映射变更。
// OUTPUT: 唯一窄 append 入口；写失败 fail-open，不回滚 Registry 主张。
// POS: Audit 语义 owner。物理 IO 复用 Persistence。
// TEST: repo://PaguguTests/RegistryTests.swift。

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
}
