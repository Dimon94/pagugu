import Foundation

// L3 COORD: Pagugu/Registry/Registry.swift
// INPUT: 用户选择的目录 URL、Personal Skill Root 与 Persistence 的 RegistryDocument。
// OUTPUT: 按序、无丢失持久化的 Project Scan Root、来源映射、Checkout Observation 与实时投影；
//         来源映射写成功后 best-effort 记录审计。
// POS: Registry 语义 owner。拥有串行 mutation、护栏、主张生命周期与观察单槽；
//      不拥有物理 IO、Discovery、映射有效性裁决与 UI。
// TEST: repo://PaguguTests/RegistryTests.swift。

struct ProjectScanRoot: Identifiable, Equatable, Sendable {
    var id: String { canonicalPath }

    let canonicalPath: String
    let asFoundPath: String
    let passesGuardrails: Bool
    let isAvailable: Bool
    let unavailableReason: String?
}

enum ProjectScanRootError: Error, Equatable, Sendable {
    case fileSystemRoot
    case homeDirectory
    case personalSkillRoot
    case personalSkillRootAncestor
    case unavailable
    case duplicate
    case notLoaded
    case persistence(PersistenceError)

    var reason: String {
        switch self {
        case .fileSystemRoot:
            return "不能选择文件系统根目录。请选择更具体的项目父目录。"
        case .homeDirectory:
            return "不能选择 Home 目录。请选择 Home 下更具体的项目父目录。"
        case .personalSkillRoot:
            return "不能选择 Personal Skill Root 本身。该目录已由 Pagugu 自动扫描。"
        case .personalSkillRootAncestor:
            return "不能选择 Personal Skill Root 的祖先目录。请选择不会覆盖 Personal Skill Root 的项目父目录。"
        case .unavailable:
            return "所选路径不是可用目录。请重新选择现有目录。"
        case .duplicate:
            return "该 Project Scan Root 已添加。请选择其他目录。"
        case .notLoaded:
            return "App Registry 尚未载入。请稍后重试。"
        case .persistence(.writeFailed):
            return "Registry 写入失败。请检查磁盘空间与目录权限后重试。"
        case .persistence(.externallyModified):
            return "Registry 已被外部修改。请退出并重新打开 Pagugu 后重试。"
        case .persistence(.recoveryRequired):
            return "App Registry 需要恢复。请先按页面指引恢复。"
        case .persistence(.notLoaded), .persistence(.invalidDocument):
            return "Registry 无法保存该主张。请退出并重新打开 Pagugu 后重试。"
        case .persistence(.resetConfirmationRequired):
            return "重置前需要显式确认。"
        }
    }
}

enum SourceMappingError: Error, Equatable, Sendable {
    case notLoaded
    case alreadyMapped
    case installationUnavailable
    case targetUnavailable
    case persistence(PersistenceError)

    var reason: String {
        switch self {
        case .notLoaded:
            return "App Registry 尚未载入。请稍后重试。"
        case .alreadyMapped:
            return "该 Skill Installation 已有来源映射。请先显式删除原映射。"
        case .installationUnavailable:
            return "该来源不明 Installation 已不在当前扫描结果中。请重新扫描后再试。"
        case .targetUnavailable:
            return "所选 Skill 已不在当前扫描结果中。请重新选择来源。"
        case .persistence(.writeFailed):
            return "Registry 写入失败。请检查磁盘空间与目录权限后重试。"
        case .persistence(.externallyModified):
            return "Registry 已被外部修改。请退出并重新打开 Pagugu 后重试。"
        case .persistence(.recoveryRequired):
            return "App Registry 需要恢复。请先按页面指引恢复。"
        case .persistence(.notLoaded), .persistence(.invalidDocument):
            return "Registry 无法保存该来源映射。请退出并重新打开 Pagugu 后重试。"
        case .persistence(.resetConfirmationRequired):
            return "该动作不应触发 Registry 重置。"
        }
    }
}

actor AppRegistry {
    private let persistence: Persistence
    private let audit: AuditEvidence
    private let homeCanonicalPath: String
    private let personalRootAsFoundPaths: [String]
    private let personalRootCanonicalPaths: [String]
    private var document: RegistryDocument?
    private var mutationInProgress = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        persistence: Persistence = .live,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        personalRoots: [String] = Discovery.personalSkillRoots
    ) {
        self.persistence = persistence
        self.audit = AuditEvidence(persistence: persistence)
        self.homeCanonicalPath = Self.canonicalPath(homeDirectory.path)
        self.personalRootAsFoundPaths = personalRoots.map(Self.standardizedPath)
        self.personalRootCanonicalPaths = personalRoots.map(Self.canonicalPath)
    }

    func load() async -> RegistryLoadResult {
        await beginMutation()
        defer { endMutation() }
        let result = await persistence.loadRegistry()
        if case .ready(let document) = result {
            self.document = document
        } else {
            document = nil
        }
        return result
    }

    /// L4 IN: url 来自系统目录选择器。边界统一规范化并按 canonical 路径校验。
    /// OUT: durable write 成功后才提交内存投影；数组顺序保持添加顺序。
    /// FAIL: 非法选择和写失败均零主张变更，并返回稳定中文恢复方向。
    func addProjectScanRoot(_ url: URL) async throws {
        await beginMutation()
        defer { endMutation() }
        guard let document else {
            throw ProjectScanRootError.notLoaded
        }

        let asFoundPath = url.standardizedFileURL.path
        let canonicalPath = Self.canonicalPath(asFoundPath)
        try validate(canonicalPath: canonicalPath, asFoundPath: asFoundPath)
        guard !document.projectScanRoots.contains(where: { $0.canonicalPath == canonicalPath }) else {
            throw ProjectScanRootError.duplicate
        }

        let record = ProjectScanRootRecord(
            canonicalPath: canonicalPath,
            asFoundPath: asFoundPath
        )
        try await save(documentWithRoots: document.projectScanRoots + [record])
    }

    /// 只删除 Project Scan Root 主张。来源映射、观察槽与用户目录保持不动。
    func removeProjectScanRoot(canonicalPath: String) async throws {
        await beginMutation()
        defer { endMutation() }
        guard let document else {
            throw ProjectScanRootError.notLoaded
        }
        let roots = document.projectScanRoots.filter { $0.canonicalPath != canonicalPath }
        guard roots.count != document.projectScanRoots.count else { return }
        try await save(documentWithRoots: roots)
    }

    func projectScanRoots() -> [ProjectScanRoot] {
        document?.projectScanRoots.map { record in
            let guardrailError = guardrailError(
                canonicalPath: record.canonicalPath,
                asFoundPath: record.asFoundPath
            )
            let isAvailable = guardrailError == nil && Self.isAvailableDirectory(record.canonicalPath)
            return ProjectScanRoot(
                canonicalPath: record.canonicalPath,
                asFoundPath: record.asFoundPath,
                passesGuardrails: guardrailError == nil,
                isAvailable: isAvailable,
                unavailableReason: guardrailError?.reason ?? (isAvailable ? nil : "目录不存在或不可读")
            )
        } ?? []
    }

    func checkoutObservations() -> [String: CheckoutObservation] {
        document?.checkoutObservations ?? [:]
    }

    /// 逐检出单槽替换。durable write 成功后才提交内存投影。
    func recordCheckoutObservation(_ observation: CheckoutObservation) async throws {
        await beginMutation()
        defer { endMutation() }
        guard let document else { throw PersistenceError.notLoaded }
        var observations = document.checkoutObservations
        observations[observation.identityDigest.checkoutCanonicalPath] = observation
        let updated = RegistryDocument(
            schemaVersion: document.schemaVersion,
            projectScanRoots: document.projectScanRoots,
            sourceMappings: document.sourceMappings,
            checkoutObservations: observations
        )
        try await persistence.saveRegistry(updated)
        self.document = updated
    }

    func sourceMappings() -> [String: SourceMappingRecord] {
        document?.sourceMappings ?? [:]
    }

    /// L4 IN: AppModel 已确认 Installation 当前为来源不明复制投影，目标身份当前存在。
    /// OUT: durable write 成功后提交主张，再 best-effort 写 created 审计；相同记录为 no-op。
    func createSourceMapping(
        installationCanonicalPath: String,
        target: SourceMappingRecord
    ) async throws -> Bool {
        await beginMutation()
        defer { endMutation() }
        guard let document else { throw SourceMappingError.notLoaded }
        if let existing = document.sourceMappings[installationCanonicalPath] {
            guard existing != target else { return false }
            throw SourceMappingError.alreadyMapped
        }

        var mappings = document.sourceMappings
        mappings[installationCanonicalPath] = target
        let updated = RegistryDocument(
            schemaVersion: document.schemaVersion,
            projectScanRoots: document.projectScanRoots,
            sourceMappings: mappings,
            checkoutObservations: document.checkoutObservations
        )
        try await save(updated, as: SourceMappingError.self)
        await audit.recordSourceMapping(
            outcome: .created,
            installationCanonicalPath: installationCanonicalPath,
            target: target
        )
        return true
    }

    /// 只删除映射主张。Installation、Skill Source 与 Git 工作树保持不动。
    func deleteSourceMapping(installationCanonicalPath: String) async throws -> Bool {
        await beginMutation()
        defer { endMutation() }
        guard let document else { throw SourceMappingError.notLoaded }
        guard let removed = document.sourceMappings[installationCanonicalPath] else { return false }

        var mappings = document.sourceMappings
        mappings.removeValue(forKey: installationCanonicalPath)
        let updated = RegistryDocument(
            schemaVersion: document.schemaVersion,
            projectScanRoots: document.projectScanRoots,
            sourceMappings: mappings,
            checkoutObservations: document.checkoutObservations
        )
        try await save(updated, as: SourceMappingError.self)
        await audit.recordSourceMapping(
            outcome: .deleted,
            installationCanonicalPath: installationCanonicalPath,
            target: removed
        )
        return true
    }

    func reset(confirmed: Bool) async throws -> URL? {
        await beginMutation()
        defer { endMutation() }
        do {
            let evidenceURL = try await persistence.resetRegistry(confirmed: confirmed)
            document = .empty
            return evidenceURL
        } catch let error as PersistenceError {
            throw ProjectScanRootError.persistence(error)
        }
    }

    private func validate(canonicalPath: String, asFoundPath: String) throws {
        if let error = guardrailError(canonicalPath: canonicalPath, asFoundPath: asFoundPath) {
            throw error
        }
        guard Self.isAvailableDirectory(canonicalPath) else {
            throw ProjectScanRootError.unavailable
        }
    }

    private func guardrailError(
        canonicalPath: String,
        asFoundPath: String
    ) -> ProjectScanRootError? {
        if canonicalPath == "/" { return .fileSystemRoot }
        if canonicalPath == homeCanonicalPath { return .homeDirectory }
        let candidatePaths = [canonicalPath, asFoundPath]
        let personalRootPaths = personalRootCanonicalPaths + personalRootAsFoundPaths
        if candidatePaths.contains(where: personalRootPaths.contains) {
            return .personalSkillRoot
        }
        if candidatePaths.contains(where: { candidate in
            personalRootPaths.contains(where: { Self.isAncestor(candidate, of: $0) })
        }) {
            return .personalSkillRootAncestor
        }
        return nil
    }

    private func beginMutation() async {
        if !mutationInProgress {
            mutationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
        }
    }

    private func endMutation() {
        guard !mutationWaiters.isEmpty else {
            mutationInProgress = false
            return
        }
        mutationWaiters.removeFirst().resume()
    }

    private func save(documentWithRoots roots: [ProjectScanRootRecord]) async throws {
        guard let document else {
            throw ProjectScanRootError.notLoaded
        }
        let updated = RegistryDocument(
            schemaVersion: document.schemaVersion,
            projectScanRoots: roots,
            sourceMappings: document.sourceMappings,
            checkoutObservations: document.checkoutObservations
        )
        try await save(updated, as: ProjectScanRootError.self)
    }

    private func save(_ updated: RegistryDocument, as _: ProjectScanRootError.Type) async throws {
        do {
            try await persistence.saveRegistry(updated)
            document = updated
        } catch let error as PersistenceError {
            throw ProjectScanRootError.persistence(error)
        }
    }

    private func save(_ updated: RegistryDocument, as _: SourceMappingError.Type) async throws {
        do {
            try await persistence.saveRegistry(updated)
            document = updated
        } catch let error as PersistenceError {
            throw SourceMappingError.persistence(error)
        }
    }

    private static func canonicalPath(_ path: String) -> String {
        let resolved = (path as NSString).resolvingSymlinksInPath
        return URL(fileURLWithPath: resolved).standardizedFileURL.path
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private static func isAncestor(_ ancestor: String, of path: String) -> Bool {
        path != ancestor && path.hasPrefix(ancestor.hasSuffix("/") ? ancestor : ancestor + "/")
    }

    private static func isAvailableDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) &&
            isDirectory.boolValue && FileManager.default.isReadableFile(atPath: path)
    }
}
