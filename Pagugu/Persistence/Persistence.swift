import Darwin
import Foundation

// L3 COORD: Pagugu/Persistence/Persistence.swift
// INPUT: Application Support 目录或测试注入目录中的 registry.json 与 audit-history.json。
// OUTPUT: RegistryDocument 当前主张、阻断式 RegistryRecovery，或 fail-open AuditDocument。
// POS: Persistence 物理 owner。只依赖 Foundation，不拥有主张语义。
// TEST: repo://PaguguTests/PersistenceTests.swift、repo://PaguguTests/CheckRunTests.swift。

// L5 PARAM: Registry schemaVersion 只接受 JSON 整数字面量 1；Audit schemaVersion 当前只接受 1；Audit FIFO 上限 200。
// Audit action 为 source-mapping / check-run / update-run；Update start 无 outcome，terminal 使用 success/cancelled/failed；
// failed reason 只接受审计 schema 列出的九个稳定 wire code，并由测试锁定为 Runs 的同一 rawValue 集合。
// Registry 顶层恰好编码三类集合；未知字段可忽略且重写不保留。
// PAIR: CheckoutObservation success 必须有 remoteTipSHA；failure 必须没有。
// FAIL: 缺字段、类型不符、路径/身份配对无效均走损坏 quarantine。
private struct RegistrySchemaHeader: Decodable {
    let schemaVersion: Int
}

struct RegistryDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let empty = RegistryDocument(
        schemaVersion: currentSchemaVersion,
        projectScanRoots: [],
        sourceMappings: [:],
        checkoutObservations: [:]
    )

    let schemaVersion: Int
    let projectScanRoots: [ProjectScanRootRecord]
    let sourceMappings: [String: SourceMappingRecord]
    let checkoutObservations: [String: CheckoutObservation]

    fileprivate func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw RegistryValidationError.invalidSchemaVersion
        }

        let rootPaths = projectScanRoots.map(\.canonicalPath)
        guard Set(rootPaths).count == rootPaths.count,
              projectScanRoots.allSatisfy({
                  isNormalizedAbsolutePath($0.canonicalPath) && isNormalizedAbsolutePath($0.asFoundPath)
              }) else {
            throw RegistryValidationError.invalidProjectScanRoot
        }

        guard sourceMappings.allSatisfy({ key, value in
            isNormalizedAbsolutePath(key) && isNormalizedSkillSourceKey(value.skillSourceKey) &&
                isNormalizedRelativePath(value.repositoryRelativePath)
        }) else {
            throw RegistryValidationError.invalidSourceMapping
        }

        guard checkoutObservations.allSatisfy({ key, observation in
            isNormalizedAbsolutePath(key) &&
                key == observation.identityDigest.checkoutCanonicalPath && observation.isValid
        }) else {
            throw RegistryValidationError.invalidCheckoutObservation
        }
    }
}

struct ProjectScanRootRecord: Codable, Equatable, Sendable {
    let canonicalPath: String
    let asFoundPath: String
}

struct SourceMappingRecord: Codable, Equatable, Sendable {
    let skillSourceKey: String
    let repositoryRelativePath: String
}

struct CheckoutObservation: Codable, Equatable, Sendable {
    enum Result: String, Codable, Equatable, Sendable {
        case success
        case failure
    }

    let result: Result
    let completedAt: Date
    let remoteTipSHA: String?
    let identityDigest: CheckoutIdentityDigest

    fileprivate var isValid: Bool {
        let digestValues = [
            identityDigest.checkoutCanonicalPath,
            identityDigest.gitCommonDirIdentifier,
            identityDigest.normalizedRemoteURL,
            identityDigest.branchName,
            identityDigest.upstreamRefName,
        ]
        let hasRequiredTip = result == .success ? !(remoteTipSHA?.isEmpty ?? true) : remoteTipSHA == nil
        return hasRequiredTip && isNormalizedAbsolutePath(identityDigest.checkoutCanonicalPath) &&
            digestValues.allSatisfy { !$0.isEmpty }
    }
}

struct CheckoutIdentityDigest: Codable, Equatable, Sendable {
    let checkoutCanonicalPath: String
    let gitCommonDirIdentifier: String
    let normalizedRemoteURL: String
    let branchName: String
    let upstreamRefName: String
}

struct AuditDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let empty = AuditDocument(schemaVersion: currentSchemaVersion, records: [])

    let schemaVersion: Int
    let records: [AuditRecord]

    fileprivate func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              Set(records.map(\.id)).count == records.count,
              records.allSatisfy(\.isValid) else {
            throw AuditValidationError.invalidDocument
        }
    }
}

struct AuditRecord: Codable, Equatable, Sendable {
    enum Action: String, Codable, Equatable, Sendable {
        case sourceMapping = "source-mapping"
        case checkRun = "check-run"
        case updateRun = "update-run"
    }

    enum Outcome: String, Codable, Equatable, Sendable {
        case created
        case deleted
        case complete
        case partial
        case failed
        case success
        case cancelled
    }

    enum UpdateRunPhase: String, Codable, Equatable, Sendable {
        case started
        case terminal
    }

    enum UpdateFailureReasonCode: String, CaseIterable, Equatable, Sendable {
        case lockBusy = "lock-busy"
        case identityChanged = "identity-changed"
        case fetchFailure = "fetch-failure"
        case preconditionChanged = "precondition-changed"
        case tipChanged = "tip-changed"
        case fastForwardRejected = "ff-rejected"
        case commandFailure = "command-failure"
        case verificationFailed = "verification-failed"
        case interruptedUnknown = "interrupted-unknown"
    }

    struct CheckRunScope: Codable, Equatable, Sendable {
        let checkableCount: Int
        let succeededCount: Int
        let failedCount: Int
        let skippedCount: Int

        fileprivate var isValid: Bool {
            [checkableCount, succeededCount, failedCount, skippedCount].allSatisfy { $0 >= 0 } &&
                checkableCount == succeededCount + failedCount
        }
    }

    struct SkillIdentitySnapshot: Codable, Equatable, Sendable {
        let skillSourceKey: String
        let repositoryRelativePath: String

        fileprivate var isValid: Bool {
            isNormalizedSkillSourceKey(skillSourceKey) &&
                isNormalizedRelativePath(repositoryRelativePath)
        }
    }

    struct UpdateRunTarget: Codable, Equatable, Sendable {
        let skillIdentity: SkillIdentitySnapshot
        let checkoutCanonicalPath: String
        let branchName: String
        let upstreamRefName: String

        fileprivate var isValid: Bool {
            skillIdentity.isValid &&
                isNormalizedAbsolutePath(checkoutCanonicalPath) &&
                !branchName.isEmpty && !upstreamRefName.isEmpty
        }
    }

    struct UpdateRunPlan: Codable, Equatable, Sendable {
        let skillIdentity: SkillIdentitySnapshot
        let checkoutCanonicalPath: String
        let branchName: String
        let upstreamRefName: String
        let currentHeadSHA: String
        let targetSHA: String
        let behindCount: Int
        let affectedSkills: [SkillIdentitySnapshot]

        fileprivate var target: UpdateRunTarget {
            UpdateRunTarget(
                skillIdentity: skillIdentity,
                checkoutCanonicalPath: checkoutCanonicalPath,
                branchName: branchName,
                upstreamRefName: upstreamRefName
            )
        }

        fileprivate var isValid: Bool {
            skillIdentity.isValid &&
                isNormalizedAbsolutePath(checkoutCanonicalPath) &&
                !branchName.isEmpty && !upstreamRefName.isEmpty &&
                isFullGitSHA(currentHeadSHA) && isFullGitSHA(targetSHA) &&
                currentHeadSHA != targetSHA && behindCount > 0 &&
                !affectedSkills.isEmpty && affectedSkills.allSatisfy(\.isValid) &&
                affectedSkills.allSatisfy({ $0.skillSourceKey == skillIdentity.skillSourceKey }) &&
                Set(affectedSkills.map { "\($0.skillSourceKey)\u{0}\($0.repositoryRelativePath)" }).count == affectedSkills.count &&
                affectedSkills.contains(skillIdentity)
        }
    }

    let id: String
    let recordedAt: Date
    let action: Action
    let outcome: Outcome?
    let installationCanonicalPath: String?
    let target: SourceMappingRecord?
    let checkRunScope: CheckRunScope?
    let updateRunID: String?
    let updateRunPhase: UpdateRunPhase?
    let updateRunTarget: UpdateRunTarget?
    let updateRunPlan: UpdateRunPlan?
    let updateFailureReason: String?

    init(
        id: String,
        recordedAt: Date,
        outcome: Outcome,
        installationCanonicalPath: String,
        target: SourceMappingRecord
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.action = .sourceMapping
        self.outcome = outcome
        self.installationCanonicalPath = installationCanonicalPath
        self.target = target
        self.checkRunScope = nil
        self.updateRunID = nil
        self.updateRunPhase = nil
        self.updateRunTarget = nil
        self.updateRunPlan = nil
        self.updateFailureReason = nil
    }

    init(
        id: String,
        recordedAt: Date,
        outcome: Outcome,
        checkRunScope: CheckRunScope
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.action = .checkRun
        self.outcome = outcome
        self.installationCanonicalPath = nil
        self.target = nil
        self.checkRunScope = checkRunScope
        self.updateRunID = nil
        self.updateRunPhase = nil
        self.updateRunTarget = nil
        self.updateRunPlan = nil
        self.updateFailureReason = nil
    }

    init(
        id: String,
        recordedAt: Date,
        updateRunID: String,
        phase: UpdateRunPhase,
        target: UpdateRunTarget? = nil,
        plan: UpdateRunPlan? = nil,
        outcome: Outcome? = nil,
        failureReason: String? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.action = .updateRun
        self.outcome = outcome
        self.installationCanonicalPath = nil
        self.target = nil
        self.checkRunScope = nil
        self.updateRunID = updateRunID
        self.updateRunPhase = phase
        self.updateRunTarget = target
        self.updateRunPlan = plan
        self.updateFailureReason = failureReason
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case recordedAt
        case action
        case outcome
        case installationCanonicalPath
        case target
        case checkRunScope
        case updateRunID
        case updateRunPhase
        case updateRunTarget
        case updateRunPlan
        case updateFailureReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
        outcome = try container.decodeIfPresent(Outcome.self, forKey: .outcome)
        installationCanonicalPath = try container.decodeIfPresent(
            String.self,
            forKey: .installationCanonicalPath
        )
        target = try container.decodeIfPresent(SourceMappingRecord.self, forKey: .target)
        checkRunScope = try container.decodeIfPresent(CheckRunScope.self, forKey: .checkRunScope)
        updateRunID = try container.decodeIfPresent(String.self, forKey: .updateRunID)
        updateRunPhase = try container.decodeIfPresent(UpdateRunPhase.self, forKey: .updateRunPhase)
        updateRunTarget = try container.decodeIfPresent(UpdateRunTarget.self, forKey: .updateRunTarget)
        updateRunPlan = try container.decodeIfPresent(UpdateRunPlan.self, forKey: .updateRunPlan)
        updateFailureReason = try container.decodeIfPresent(String.self, forKey: .updateFailureReason)
        action = try container.decodeIfPresent(Action.self, forKey: .action) ?? .sourceMapping
    }

    fileprivate var isValid: Bool {
        guard !id.isEmpty else { return false }
        switch action {
        case .sourceMapping:
            guard outcome == .created || outcome == .deleted,
                  let installationCanonicalPath,
                  let target,
                  checkRunScope == nil,
                  updateRunID == nil, updateRunPhase == nil, updateRunTarget == nil,
                  updateRunPlan == nil, updateFailureReason == nil else { return false }
            return isNormalizedAbsolutePath(installationCanonicalPath) &&
                isNormalizedSkillSourceKey(target.skillSourceKey) &&
                isNormalizedRelativePath(target.repositoryRelativePath)
        case .checkRun:
            guard let outcome, [.complete, .partial, .failed].contains(outcome),
                  installationCanonicalPath == nil,
                  target == nil,
                  let checkRunScope,
                  checkRunScope.isValid,
                  updateRunID == nil, updateRunPhase == nil, updateRunTarget == nil,
                  updateRunPlan == nil, updateFailureReason == nil else { return false }
            switch outcome {
            case .complete:
                return checkRunScope.failedCount == 0
            case .partial:
                return checkRunScope.succeededCount > 0 && checkRunScope.failedCount > 0
            case .failed:
                return checkRunScope.succeededCount == 0 && checkRunScope.failedCount > 0
            case .created, .deleted, .success, .cancelled:
                return false
            }
        case .updateRun:
            guard installationCanonicalPath == nil, target == nil, checkRunScope == nil,
                  let updateRunID, !updateRunID.isEmpty,
                  let updateRunPhase,
                  updateRunTarget?.isValid ?? true,
                  updateRunPlan?.isValid ?? true,
                  updateRunTarget == nil || updateRunPlan == nil || updateRunTarget == updateRunPlan?.target,
                  updateRunTarget != nil || updateRunPlan != nil else { return false }
            switch updateRunPhase {
            case .started:
                return outcome == nil && updateRunPlan != nil && updateFailureReason == nil
            case .terminal:
                switch outcome {
                case .success, .cancelled:
                    return updateRunPlan != nil && updateFailureReason == nil
                case .failed:
                    return updateFailureReason.map {
                        UpdateFailureReasonCode(rawValue: $0) != nil
                    } ?? false
                case .none, .created, .deleted, .complete, .partial:
                    return false
                }
            }
        }
    }
}

struct RegistryRecovery: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case corrupt
        case unknownFutureVersion
        case externallyModified
        case writeFailed
    }

    let kind: Kind
    let evidenceURL: URL
}

enum RegistryLoadResult: Equatable, Sendable {
    case ready(RegistryDocument)
    case restricted(RegistryRecovery)
}

enum PersistenceError: Error, Equatable, Sendable {
    case notLoaded
    case invalidDocument
    case recoveryRequired(RegistryRecovery)
    case externallyModified(RegistryRecovery)
    case writeFailed(RegistryRecovery)
    case resetConfirmationRequired
}

private enum RegistryValidationError: Error {
    case invalidSchemaVersion
    case invalidProjectScanRoot
    case invalidSourceMapping
    case invalidCheckoutObservation
}

private enum AuditValidationError: Error {
    case invalidDocument
}

private func isNormalizedAbsolutePath(_ path: String) -> Bool {
    path.hasPrefix("/") && (path as NSString).standardizingPath == path
}

private func isNormalizedRelativePath(_ path: String) -> Bool {
    path.isEmpty || (!path.hasPrefix("/") && path != "." &&
        !(path as NSString).pathComponents.contains("..") &&
        (path as NSString).standardizingPath == path)
}

private func isFullGitSHA(_ value: String) -> Bool {
    [40, 64].contains(value.count) && value.allSatisfy(\.isHexDigit)
}

private func isNormalizedSkillSourceKey(_ value: String) -> Bool {
    if value.hasPrefix("/") { return isNormalizedAbsolutePath(value) }
    guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.contains(where: \.isWhitespace),
          !value.contains("://"), !value.contains("@"), !value.contains(":"),
          !value.hasPrefix("/"), !value.hasSuffix("/"),
          !value.lowercased().hasSuffix(".git") else {
        return false
    }
    let parts = value.split(separator: "/", omittingEmptySubsequences: false)
    return parts.count >= 2 && parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) &&
        parts[0] == parts[0].lowercased()
}

actor Persistence {
    typealias AtomicWriteHook = @Sendable () throws -> Void

    static let live: Persistence = {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return Persistence(
            directoryURL: applicationSupport.appendingPathComponent("com.dimon.pagugu", isDirectory: true)
        )
    }()

    static let resetImpact = "将清空全部 Project Scan Root、来源映射与逐检出上次观察。前两项需人工重建；观察可通过重新检查重建。不会删除 Skill Source、Skill Installation 或 Git 工作树。"

    private let directoryURL: URL
    private let registryURL: URL
    private let auditURL: URL
    private let beforeAtomicReplace: AtomicWriteHook
    private var loadResult: RegistryLoadResult?
    private var knownRegistryBytes: Data?

    init(
        directoryURL: URL,
        beforeAtomicReplace: @escaping AtomicWriteHook = {}
    ) {
        self.directoryURL = directoryURL
        self.registryURL = directoryURL.appendingPathComponent("registry.json")
        self.auditURL = directoryURL.appendingPathComponent("audit-history.json")
        self.beforeAtomicReplace = beforeAtomicReplace
    }

    /// L4 IN: 首次调用固定本进程的 last-good 字节基线。
    /// OUT: 缺文件返回正常空态；损坏文件先 quarantine；未来版本保持原位。
    /// FAIL: 任何不能完整理解的 Registry 均进入阻断式受限恢复模式。
    func loadRegistry() -> RegistryLoadResult {
        if let loadResult {
            return loadResult
        }

        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            return remember(.ready(.empty), bytes: nil)
        }

        let bytes: Data
        do {
            bytes = try Data(contentsOf: registryURL)
        } catch {
            return remember(
                .restricted(RegistryRecovery(kind: .corrupt, evidenceURL: registryURL)),
                bytes: nil
            )
        }

        do {
            let schemaVersion = try decodeSchemaVersion(from: bytes)
            if schemaVersion > RegistryDocument.currentSchemaVersion {
                return remember(
                    .restricted(
                        RegistryRecovery(kind: .unknownFutureVersion, evidenceURL: registryURL)
                    ),
                    bytes: bytes
                )
            }

            guard schemaVersion == RegistryDocument.currentSchemaVersion else {
                throw RegistryValidationError.invalidSchemaVersion
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(RegistryDocument.self, from: bytes)
            try document.validate()
            return remember(.ready(document), bytes: bytes)
        } catch {
            let evidenceURL = quarantineCorruptRegistry()
            return remember(
                .restricted(RegistryRecovery(kind: .corrupt, evidenceURL: evidenceURL)),
                bytes: nil
            )
        }
    }

    /// L4 IN: 必须先完成 loadRegistry；document 必须满足 v1 schema。
    /// OUT: 双 fsync 与 rename 全部成功后才更新 last-good 内存投影。
    /// FAIL: 磁盘字节漂移时绝不覆写；写失败保留原磁盘与原内存投影。
    func saveRegistry(_ document: RegistryDocument) throws {
        guard let loadResult else {
            throw PersistenceError.notLoaded
        }
        guard case .ready = loadResult else {
            if case .restricted(let recovery) = loadResult {
                throw PersistenceError.recoveryRequired(recovery)
            }
            throw PersistenceError.notLoaded
        }

        do {
            try document.validate()
        } catch {
            throw PersistenceError.invalidDocument
        }

        let diskBytes: Data?
        do {
            diskBytes = FileManager.default.fileExists(atPath: registryURL.path)
                ? try Data(contentsOf: registryURL)
                : nil
        } catch {
            let recovery = RegistryRecovery(kind: .writeFailed, evidenceURL: registryURL)
            throw PersistenceError.writeFailed(recovery)
        }

        guard diskBytes == knownRegistryBytes else {
            let recovery = RegistryRecovery(kind: .externallyModified, evidenceURL: registryURL)
            self.loadResult = .restricted(recovery)
            throw PersistenceError.externallyModified(recovery)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes: Data
        do {
            bytes = try encoder.encode(document)
            try ensureDirectory()
            try writeDurably(bytes, to: registryURL)
        } catch {
            let recovery = RegistryRecovery(kind: .writeFailed, evidenceURL: registryURL)
            throw PersistenceError.writeFailed(recovery)
        }

        knownRegistryBytes = bytes
        self.loadResult = .ready(document)
    }

    /// L4 IN: confirmed 必须由显式确认对话框传入。
    /// OUT: 先 quarantine 当前 registry.json，再原子写入空 v1；返回保留的证据路径。
    /// FAIL: 未确认零副作用；quarantine 或写入失败时不提交空内存投影。
    func resetRegistry(confirmed: Bool) throws -> URL? {
        guard confirmed else {
            throw PersistenceError.resetConfirmationRequired
        }
        guard let loadResult else {
            throw PersistenceError.notLoaded
        }

        var evidenceURL: URL?
        if FileManager.default.fileExists(atPath: registryURL.path) {
            do {
                try ensureDirectory()
                evidenceURL = try quarantineRegistry(prefix: "registry.reset")
            } catch {
                let recovery = RegistryRecovery(kind: .writeFailed, evidenceURL: registryURL)
                throw PersistenceError.writeFailed(recovery)
            }
        } else if case .restricted(let recovery) = loadResult,
                  recovery.evidenceURL != registryURL,
                  FileManager.default.fileExists(atPath: recovery.evidenceURL.path) {
            evidenceURL = recovery.evidenceURL
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes: Data
        do {
            bytes = try encoder.encode(RegistryDocument.empty)
            try ensureDirectory()
            try writeDurably(bytes, to: registryURL)
        } catch {
            let recovery = RegistryRecovery(
                kind: .writeFailed,
                evidenceURL: evidenceURL ?? registryURL
            )
            throw PersistenceError.writeFailed(recovery)
        }

        knownRegistryBytes = bytes
        self.loadResult = .ready(.empty)
        return evidenceURL
    }

    /// L4 OUT: 缺文件返回正常空历史；已有文件读取、解码或校验失败时返回 nil。
    /// L6 CHAIN: 已有文件失败先 quarantine，再由调用方呈现「历史不可用」；不阻断 Registry 动作。
    func loadAuditDocument() -> AuditDocument? {
        guard FileManager.default.fileExists(atPath: auditURL.path) else {
            return .empty
        }

        let bytes: Data
        do {
            bytes = try Data(contentsOf: auditURL)
        } catch {
            _ = try? quarantineAudit()
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(AuditDocument.self, from: bytes)
            try document.validate()
            return document
        } catch {
            _ = try? quarantineAudit()
            return nil
        }
    }

    /// 审计损坏时 fail-open：保留损坏文件并返回空历史，不阻断 Registry 动作。
    func loadAuditEvidence() -> AuditDocument {
        loadAuditDocument() ?? .empty
    }

    /// L4 IN: 必须由显式确认触发；只针对 audit-history.json。
    /// OUT: 清空审计集合（含损坏 quarantine 前的残留），不动 Registry 与用户仓库，不留墓碑。
    func clearAuditEvidence() throws {
        do {
            let encoder = JSONEncoder()
            try ensureDirectory()
            try writeDurably(
                encoder.encode(AuditDocument.empty),
                to: auditURL
            )
        } catch {
            throw AuditValidationError.invalidDocument
        }
    }

    /// L4 IN: record 必须满足 action/outcome/payload 配对；不得包含原始命令输出。
    /// OUT: append-only，超过 200 条时淘汰最旧记录；复用 Registry 的 durable write。
    /// FAIL: 读取损坏或写入失败均留在审计故障域，不改变调用方主动作。
    func appendAuditEvidence(_ record: AuditRecord) throws {
        guard record.isValid else { throw AuditValidationError.invalidDocument }
        let current = loadAuditEvidence()
        let records = Array((current.records + [record]).suffix(200))
        let document = AuditDocument(schemaVersion: AuditDocument.currentSchemaVersion, records: records)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try ensureDirectory()
            try writeDurably(encoder.encode(document), to: auditURL)
        } catch {
            throw AuditValidationError.invalidDocument
        }
    }

    private func remember(_ result: RegistryLoadResult, bytes: Data?) -> RegistryLoadResult {
        loadResult = result
        knownRegistryBytes = bytes
        return result
    }

    private func decodeSchemaVersion(from data: Data) throws -> Int {
        let header = try JSONDecoder().decode(RegistrySchemaHeader.self, from: data)
        guard schemaVersionUsesIntegerToken(in: data) else {
            throw RegistryValidationError.invalidSchemaVersion
        }
        return header.schemaVersion
    }

    private func schemaVersionUsesIntegerToken(in data: Data) -> Bool {
        let bytes = [UInt8](data)
        var index = 0
        var depth = 0

        while index < bytes.count {
            switch bytes[index] {
            case 0x22:
                let stringStart = index
                guard let stringEnd = jsonStringEnd(startingAt: index, in: bytes) else {
                    return false
                }
                index = stringEnd + 1
                guard depth == 1 else { continue }

                var delimiterIndex = index
                skipJSONWhitespace(in: bytes, from: &delimiterIndex)
                guard delimiterIndex < bytes.count, bytes[delimiterIndex] == 0x3A else {
                    continue
                }
                guard let key = try? JSONDecoder().decode(
                    String.self,
                    from: Data(bytes[stringStart...stringEnd])
                ), key == "schemaVersion" else {
                    continue
                }

                var valueIndex = delimiterIndex + 1
                skipJSONWhitespace(in: bytes, from: &valueIndex)
                return isJSONIntegerToken(in: bytes, startingAt: valueIndex)
            case 0x7B, 0x5B:
                depth += 1
                index += 1
            case 0x7D, 0x5D:
                depth -= 1
                index += 1
            default:
                index += 1
            }
        }
        return false
    }

    private func jsonStringEnd(startingAt start: Int, in bytes: [UInt8]) -> Int? {
        var index = start + 1
        var isEscaped = false
        while index < bytes.count {
            if isEscaped {
                isEscaped = false
            } else if bytes[index] == 0x5C {
                isEscaped = true
            } else if bytes[index] == 0x22 {
                return index
            }
            index += 1
        }
        return nil
    }

    private func skipJSONWhitespace(in bytes: [UInt8], from index: inout Int) {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
            index += 1
        }
    }

    private func isJSONIntegerToken(in bytes: [UInt8], startingAt start: Int) -> Bool {
        guard start < bytes.count else { return false }
        var index = start
        if bytes[index] == 0x2D {
            index += 1
            guard index < bytes.count else { return false }
        }

        if bytes[index] == 0x30 {
            index += 1
        } else {
            guard (0x31...0x39).contains(bytes[index]) else { return false }
            repeat { index += 1 } while index < bytes.count && (0x30...0x39).contains(bytes[index])
        }

        guard index < bytes.count else { return true }
        return [0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x7D].contains(bytes[index])
    }

    private func quarantineCorruptRegistry() -> URL {
        (try? quarantineRegistry(prefix: "registry.corrupt")) ?? registryURL
    }

    private func quarantineRegistry(prefix: String) throws -> URL {
        let suffix = "\(Int(Date().timeIntervalSince1970 * 1_000))-\(UUID().uuidString)"
        let quarantineURL = directoryURL.appendingPathComponent("\(prefix)-\(suffix).json")
        guard rename(registryURL.path, quarantineURL.path) == 0 else {
            throw POSIXFailure(code: errno)
        }
        return quarantineURL
    }

    private func quarantineAudit() throws -> URL {
        let suffix = "\(Int(Date().timeIntervalSince1970 * 1_000))-\(UUID().uuidString)"
        let quarantineURL = directoryURL.appendingPathComponent("audit-history.corrupt-\(suffix).json")
        guard rename(auditURL.path, quarantineURL.path) == 0 else {
            throw POSIXFailure(code: errno)
        }
        return quarantineURL
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(directoryURL.path, 0o700) == 0 else {
            throw POSIXFailure(code: errno)
        }
    }

    /// L6 CHAIN: 同目录临时文件 → 完整写入 → fsync 文件 → rename → fsync 目录。
    /// Registry 与 Audit 必须复用本函数，不得另建写路径。
    private func writeDurably(_ data: Data, to destinationURL: URL) throws {
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        var descriptor = open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else {
            throw POSIXFailure(code: errno)
        }
        defer {
            if descriptor >= 0 {
                close(descriptor)
            }
            unlink(temporaryURL.path)
        }
        guard fchmod(descriptor, 0o600) == 0 else {
            throw POSIXFailure(code: errno)
        }

        try data.withUnsafeBytes { rawBuffer in
            guard var address = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.write(descriptor, address, remaining)
                if written < 0 && errno == EINTR {
                    continue
                }
                guard written > 0 else {
                    throw POSIXFailure(code: errno)
                }
                remaining -= written
                address = address.advanced(by: written)
            }
        }

        guard fsync(descriptor) == 0 else {
            throw POSIXFailure(code: errno)
        }
        guard close(descriptor) == 0 else {
            throw POSIXFailure(code: errno)
        }
        descriptor = -1

        try beforeAtomicReplace()
        guard rename(temporaryURL.path, destinationURL.path) == 0 else {
            throw POSIXFailure(code: errno)
        }

        let directoryDescriptor = open(directoryURL.path, O_RDONLY)
        guard directoryDescriptor >= 0 else {
            throw POSIXFailure(code: errno)
        }
        defer { close(directoryDescriptor) }
        guard fsync(directoryDescriptor) == 0 else {
            throw POSIXFailure(code: errno)
        }
    }
}

private struct POSIXFailure: Error {
    let code: Int32
}
