import Foundation

// L3 COORD: Pagugu/AppModel/AppModel.swift
// OUTPUT: AppModel UI intent/只读投影，以及只供 composition root 注入的 RegistryResetting reset seam。
// POS: AppModel 模块（ADR-0009 §7）。@MainActor composition root：
//      owns Skill Read Model、受限恢复与来源映射错误投影、目录收起、Check/Update 瞬态、全部 UI intent
//      与启动/刷新编排；每次发布按实时事实重推导观察 freshness。取消确认后，目标检出在新的成功检查前
//      不再消费旧观察。审计历史投影只服务「最近活动」呈现；
//      Registry reset 成功后呈现 quarantine 备份路径；受限恢复「退出自行修复」经 requestQuit 发出应用退出 intent。
//      does not own 直接 Git/文件系统/持久 IO
//      （经 Git/Discovery/Registry/Audit/Runs seam）、
//      业务规则重建。
// TEST: repo://PaguguTests/AppModelTests.swift（Registry gate、requestQuit 退出 intent、Project Scan Root intent、
//      目录投影与 intent 路由 smoke、审计呈现投影）。

enum AppRun: Equatable, Sendable {
    case check
    case updatePreparing
    case updateAwaitingConfirmation
    case updateExecuting
    case updateCancelling

    var disabledReason: String {
        switch self {
        case .check:
            return "全量检查正在运行。请等待完成后再发起检查或更新。"
        case .updatePreparing:
            return "更新正在重查。请等待重查完成。"
        case .updateAwaitingConfirmation:
            return "更新等待确认。请先确认或取消当前更新。"
        case .updateExecuting:
            return "更新正在执行。请等待执行完成。"
        case .updateCancelling:
            return "正在取消更新。请等待当前操作完成。"
        }
    }
}

enum UpdateResult: Equatable, Sendable {
    static let cancellationConsequence = "已取消更新。该检出已回到“尚未检查”；重新检查后可恢复更新判断。"

    case success(checkoutPath: String, targetSHA: String)
    case upToDate
    case cancelled(checkoutPath: String)
    case failed(UpdateRunFailure)
}

struct UpdateRefreshFailure: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case partial
        case failed
    }

    let outcome: Outcome
    let issueCount: Int
}

/// AppModel 的 Registry reset seam。生产使用 AppRegistry；测试注入失败只验证 intent 投影。
protocol RegistryResetting: Sendable {
    func reset(confirmed: Bool) async throws -> URL?
}

extension AppRegistry: RegistryResetting {}

@MainActor
final class AppModel: ObservableObject {

    // MARK: - 公开只读投影

    @Published private(set) var readModel: SkillReadModel = .empty()
    @Published private(set) var registryRecovery: RegistryRecovery?
    @Published private(set) var registryReady = false
    @Published private(set) var projectScanRootError: ProjectScanRootError?
    @Published private(set) var checkRunProgress: CheckRunProgress?
    @Published private(set) var checkRunSummary: CheckRunSummary?
    @Published private(set) var sourceMappingError: SourceMappingError?
    @Published private(set) var pendingUpdatePlan: UpdatePlan?
    @Published private(set) var activeRun: AppRun?
    @Published private(set) var updateResult: UpdateResult?
    @Published private(set) var updateRefreshFailure: UpdateRefreshFailure?
    /// 审计历史投影。只服务「最近活动」呈现；永不参与裁决、freshness 或执行许可。
    @Published private(set) var auditHistory = AuditHistoryProjection(isUnavailable: false, items: [])
    /// Registry 重置成功后的 quarantine 备份路径（一次性呈现）。
    @Published private(set) var registryResetBackupPath: String?

    /// 收起的来源仓库行集合（默认全部展开）。瞬态 UI 状态，不持久化。
    @Published private(set) var collapsedSources: Set<SkillSourceKey> = []

    // MARK: - 内部依赖（构造注入）

    private let personalRoots: [String]
    private let registry: AppRegistry
    private let registryResetter: any RegistryResetting
    private let audit: AuditEvidence
    private let gitInspector: any GitInspecting
    private let gitExecutor: any GitExecuting
    private let terminateApplication: () -> Void
    private var checkScope: [CheckRunTarget] = []
    private var checkRunTargetsByPath: [String: CheckRunTarget] = [:]
    private var checkItemOutcomes: [String: CheckRunItemOutcome] = [:]
    /// 用户取消确认后，旧观察不能再次解锁可更新；新的成功检查才移除此瞬态约束。
    private var checkoutPathsRequiringCheckAfterCancellation: Set<String> = []

    init(
        personalRoots: [String] = Discovery.personalSkillRoots,
        persistence: Persistence = .live,
        gitInspector: any GitInspecting = GitClient(),
        gitExecutor: any GitExecuting = GitClient(),
        registryResetter: (any RegistryResetting)? = nil,
        terminateApplication: @escaping () -> Void = {}
    ) {
        let registry = AppRegistry(persistence: persistence, personalRoots: personalRoots)
        self.personalRoots = personalRoots
        self.registry = registry
        self.registryResetter = registryResetter ?? registry
        self.audit = AuditEvidence(persistence: persistence)
        self.gitInspector = gitInspector
        self.gitExecutor = gitExecutor
        self.terminateApplication = terminateApplication
    }

    // MARK: - 启动流水线（ADR-0009 §13）

    /// 先载 Registry 与 Audit。Registry 受限恢复时阻断全部业务；Audit 损坏 fail-open。
    func start() async {
        switch await registry.load() {
        case .ready:
            registryRecovery = nil
            registryReady = true
            await publishDiscovery()
        case .restricted(let recovery):
            registryRecovery = recovery
            registryReady = false
            readModel = .empty()
            checkScope = []
            pendingUpdatePlan = nil
            activeRun = nil
        }
        auditHistory = await audit.history()
    }

    private func publishDiscovery(updateRunFacts: CheckoutGitFacts? = nil) async {
        let projectScanRoots = await registry.projectScanRoots()
        let scanResult = Discovery.scanAll(
            personalRoots: personalRoots,
            projectRoots: projectScanRoots.filter(\.passesGuardrails).map(\.canonicalPath)
        )
        let checkoutPaths = scanResult.candidateSourceRoots
            .union(scanResult.skills.compactMap(\.repositoryRootPath))
            .sorted()
        var factsByCheckoutPath: [String: CheckoutGitFacts] = [:]
        for path in checkoutPaths {
            // local-only 先读实时身份与 remote-tracking SHA；新鲜成功观察才解锁相对位置。
            factsByCheckoutPath[path] = await gitInspector.inspectCheckout(at: path, scope: .localOnly)
        }
        let mappings = await registry.sourceMappings()
        let contents = SkillDirectory.contents(
            from: scanResult,
            gitFactsByCheckoutPath: factsByCheckoutPath,
            mappings: mappings
        )
        if let updateRunFacts,
           let source = contents.sources.first(where: { source in
               source.checkouts.contains { $0.canonicalPath == updateRunFacts.checkoutPath }
           }),
           let currentFacts = factsByCheckoutPath[updateRunFacts.checkoutPath],
           let updateIdentity = CheckoutEligibility.identityDigest(
               facts: updateRunFacts,
               sourceKey: source.id
           ),
           CheckoutEligibility.identityDigest(facts: currentFacts, sourceKey: source.id) == updateIdentity,
           currentFacts.head == updateRunFacts.head,
           currentFacts.upstream?.sha == updateRunFacts.upstream?.sha,
           currentFacts.dirty == updateRunFacts.dirty,
           currentFacts.siblingBranchConflict == updateRunFacts.siblingBranchConflict,
           currentFacts.inspectionFailure == nil {
            // Update Run 的重查或 post-verify 是本次刷新一次性事实；不写 Observation，也不跨刷新保留。
            factsByCheckoutPath[updateRunFacts.checkoutPath] = updateRunFacts
        }
        let observations = await registry.checkoutObservations().filter { checkoutPath, _ in
            !checkoutPathsRequiringCheckAfterCancellation.contains(checkoutPath)
        }
        for source in contents.sources {
            for checkout in source.checkouts {
                guard let observation = observations[checkout.canonicalPath],
                      let localFacts = factsByCheckoutPath[checkout.canonicalPath],
                      CheckoutEligibility.observationIsFresh(
                          observation,
                          facts: localFacts,
                          sourceKey: source.id
                      ) else { continue }
                let checkedFacts = await gitInspector.inspectCheckout(
                    at: checkout.canonicalPath,
                    scope: .afterSuccessfulCheck
                )
                if CheckoutEligibility.observationIsFresh(
                    observation,
                    facts: checkedFacts,
                    sourceKey: source.id
                ) {
                    factsByCheckoutPath[checkout.canonicalPath] = checkedFacts
                }
            }
        }
        let checkoutCardsBySource = Dictionary(uniqueKeysWithValues: contents.sources.map { source in
            let cards = source.checkouts.compactMap { checkout -> CheckoutCardReadModel? in
                guard let facts = factsByCheckoutPath[checkout.canonicalPath] else { return nil }
                let currentTarget = CheckRunTarget(sourceKey: source.id, facts: facts)
                let belongsToDisplayedRun = checkRunTargetsByPath[checkout.canonicalPath]?
                    .matches(currentTarget) ?? false
                let checkOutcome = belongsToDisplayedRun
                    ? checkItemOutcomes[checkout.canonicalPath]
                    : nil
                let storedObservation = observations[checkout.canonicalPath]
                let displayedObservation: CheckoutObservation? = storedObservation.flatMap { observation -> CheckoutObservation? in
                    guard CheckoutEligibility.observationMatchesIdentity(
                        observation,
                        facts: facts,
                        sourceKey: source.id
                    ) else { return nil }
                    return observation.result == .failure || CheckoutEligibility.observationIsFresh(
                        observation,
                        facts: facts,
                        sourceKey: source.id
                    ) ? observation : nil
                }
                return CheckoutCardReadModel(
                    facts: facts,
                    state: CheckoutEligibility.evaluate(facts: facts, sourceKey: source.id),
                    observation: displayedObservation,
                    checkOutcome: checkOutcome,
                    isChecking: checkRunProgress != nil &&
                        belongsToDisplayedRun && checkOutcome == nil &&
                        CheckRunner.notApplicableState(for: currentTarget) == nil
                )
            }
            return (source.id, cards)
        })
        readModel = SkillReadModel(
            sources: contents.sources,
            unattributedInstallations: contents.unattributedInstallations,
            mappingTargets: contents.mappingTargets,
            invalidMappings: contents.invalidMappings,
            issues: scanResult.issues,
            scanOutcome: scanResult.outcome,
            projectScanRoots: projectScanRoots,
            checkoutCardsBySource: checkoutCardsBySource
        )
        checkScope = contents.sources.flatMap { source in
            source.checkouts.compactMap { checkout in
                factsByCheckoutPath[checkout.canonicalPath].map {
                    CheckRunTarget(sourceKey: source.id, facts: $0)
                }
            }
        }
    }

    // MARK: - UI Intents

    /// 用户请求重新扫描。
    func rescan() async {
        guard registryReady, registryRecovery == nil else { return }
        await publishDiscovery()
    }

    var canStartCheckRun: Bool {
        guard registryReady, registryRecovery == nil, activeRun == nil else { return false }
        if case .complete = readModel.scanOutcome { return true }
        return false
    }

    var canStartUpdateRun: Bool {
        guard registryReady, registryRecovery == nil, activeRun == nil else { return false }
        if case .complete = readModel.scanOutcome { return true }
        return false
    }

    var checkRunDisabledReason: String {
        if let activeRun { return activeRun.disabledReason }
        guard registryReady, registryRecovery == nil else {
            return "Registry 处于受限恢复模式。请先完成恢复。"
        }
        if case .complete = readModel.scanOutcome { return "" }
        return "Discovery Scan 不完整。请重新扫描或处理 Scan Issue 后再检查。"
    }

    var updateRunDisabledReason: String {
        if let activeRun { return activeRun.disabledReason }
        guard registryReady, registryRecovery == nil else {
            return "Registry 处于受限恢复模式。请先完成恢复。"
        }
        if case .complete = readModel.scanOutcome { return "" }
        return "Discovery Scan 不完整。请重新扫描或处理 Scan Issue 后再更新。"
    }

    /// MVP 唯一手动检查入口。scope 在调用时复制冻结；run 瞬态不持久。
    func checkNow() async {
        guard canStartCheckRun else { return }
        activeRun = .check
        defer {
            checkRunProgress = nil
            activeRun = nil
        }
        let frozenScope = checkScope
        checkRunSummary = nil
        checkItemOutcomes = [:]
        checkRunTargetsByPath = frozenScope.reduce(into: [:]) { result, target in
            result[target.facts.checkoutPath] = target
        }
        checkRunProgress = CheckRunProgress(
            completed: 0,
            total: frozenScope.count { CheckRunner.notApplicableState(for: $0) == nil }
        )
        let runner = CheckRunner(
            gitInspector: gitInspector,
            gitExecutor: gitExecutor,
            registry: registry,
            audit: audit
        )
        for await event in runner.startCheck(scope: frozenScope) {
            switch event {
            case .started(let progress):
                checkRunProgress = progress
                await publishDiscovery()
            case .item(let item, let progress):
                checkItemOutcomes[item.checkoutPath] = item.outcome
                if item.outcome == .success {
                    checkoutPathsRequiringCheckAfterCancellation.remove(item.checkoutPath)
                }
                checkRunProgress = progress
                await publishDiscovery()
            case .finished(let summary):
                checkRunSummary = summary
                auditHistory = await audit.history()
            }
        }
    }

    func dismissCheckRunSummary() {
        checkRunSummary = nil
    }

    /// 同一 Skill Source 下当前 Eligible 检出候选。每次从 Read Model 计算，不持久化选择。
    func eligibleUpdateCheckoutPaths(for skillIdentity: SkillIdentity) -> [String] {
        guard case .complete = readModel.scanOutcome,
              let source = readModel.sourceItem(for: skillIdentity.sourceKey),
              source.skills.contains(where: { $0.id == skillIdentity }) else { return [] }
        return readModel.checkoutCards(for: source.id)
            .filter { $0.state == .updateAvailable }
            .map(\.id)
            .sorted()
    }

    // L4 IN: Skill Identity 与 checkoutPath 必须来自当前完整 Read Model 的 Eligible 候选。
    // OUT: 重查 noop/阻断先发布事实刷新，再发布结果；ready 发布 pendingUpdatePlan。选择不持久化。
    // FAIL: stale intent 抛合同错误；运行失败发布稳定 UpdateRunFailure，并按实时事实刷新投影。
    // TEST: repo://PaguguTests/AppModelTests.swift（候选、计划事实、noop/阻断/失败刷新链路）。
    // L6 CHAIN: Runs fetch 重查 → ready 等待确认；或 noop/阻断重读事实 → 完整 Discovery 发布 → 释放互斥。
    //             重查失败 → 结果发布 → 完整 Discovery；旧观察仅按 canonical freshness 合同失效。
    func prepareUpdate(skillIdentity: SkillIdentity, checkoutPath: String) async throws {
        guard activeRun == nil else { throw UpdateRunContractError.runInProgress }
        guard eligibleUpdateCheckoutPaths(for: skillIdentity).contains(checkoutPath),
              let source = readModel.sourceItem(for: skillIdentity.sourceKey),
              let card = readModel.checkoutCards(for: source.id).first(where: { $0.id == checkoutPath }) else {
            throw UpdateRunContractError.invalidRequest
        }
        let affectedEntries = source.skills(atCheckoutCanonicalPath: checkoutPath)
        guard affectedEntries.contains(where: { $0.id == skillIdentity }) else {
            throw UpdateRunContractError.invalidRequest
        }
        activeRun = .updatePreparing
        pendingUpdatePlan = nil
        updateResult = nil
        updateRefreshFailure = nil
        let runner = UpdateRunner(
            gitInspector: gitInspector,
            gitExecutor: gitExecutor,
            audit: audit
        )
        do {
            let preparation = try await runner.prepareUpdate(request: UpdateRunRequest(
                skillIdentity: skillIdentity,
                target: CheckRunTarget(sourceKey: source.id, facts: card.facts),
                affectedSkills: affectedEntries.map {
                    UpdateAffectedSkill(identity: $0.id, displayName: $0.displayName)
                }
            ))
            switch preparation {
            case .ready(let plan):
                pendingUpdatePlan = plan
                activeRun = .updateAwaitingConfirmation
            case .upToDate:
                let recheckedFacts = await gitInspector.inspectCheckout(
                    at: checkoutPath,
                    scope: .afterSuccessfulCheck
                )
                await publishDiscovery(updateRunFacts: recheckedFacts)
                updateResult = .upToDate
                activeRun = nil
            case .blocked(let state):
                let recheckedFacts = await gitInspector.inspectCheckout(
                    at: checkoutPath,
                    scope: .afterSuccessfulCheck
                )
                await publishDiscovery(updateRunFacts: recheckedFacts)
                updateResult = .failed(UpdateRunFailure(
                    reason: .preconditionChanged,
                    blockingState: state
                ))
                activeRun = nil
            }
        } catch let failure as UpdateRunFailure {
            pendingUpdatePlan = nil
            updateResult = .failed(failure)
            await publishDiscovery()
            activeRun = nil
        } catch {
            pendingUpdatePlan = nil
            await publishDiscovery()
            activeRun = nil
            throw error
        }
    }

    // L4 IN: pendingUpdatePlan 必须仍是用户当前确认的冻结计划。
    // OUT: 首次 await 前原子转入 executing 并清除可取消 plan；成功结果先发布，再以
    //      post-verify 一次性事实执行完整 Discovery 刷新；刷新失败独立投影。
    // FAIL: 运行失败发布稳定 UpdateRunFailure，并按实时事实刷新投影；不重试、不回滚。
    // TEST: repo://PaguguTests/AppModelTests.swift（成功、失败后旧 Observation、刷新失败隔离）。
    // L6 CHAIN: 成功发布 post-verify 事实；执行失败发布结果后完整 Discovery，旧观察仅按 freshness 失效。
    func confirmUpdate() async throws {
        guard activeRun == .updateAwaitingConfirmation else {
            throw activeRun == nil ? UpdateRunContractError.invalidRequest : .runInProgress
        }
        guard let plan = pendingUpdatePlan else {
            activeRun = nil
            throw UpdateRunContractError.invalidRequest
        }
        activeRun = .updateExecuting
        pendingUpdatePlan = nil
        let runner = UpdateRunner(
            gitInspector: gitInspector,
            gitExecutor: gitExecutor,
            audit: audit
        )
        do {
            let success = try await runner.executeConfirmed(plan)
            auditHistory = await audit.history()
            pendingUpdatePlan = nil
            updateResult = .success(
                checkoutPath: success.plan.checkoutCanonicalPath,
                targetSHA: success.plan.targetSHA
            )
            await publishDiscovery(updateRunFacts: success.postVerificationFacts)
            switch readModel.scanOutcome {
            case .complete:
                updateRefreshFailure = nil
            case .partial:
                updateRefreshFailure = UpdateRefreshFailure(
                    outcome: .partial,
                    issueCount: readModel.issues.count
                )
            case .failed:
                updateRefreshFailure = UpdateRefreshFailure(
                    outcome: .failed,
                    issueCount: readModel.issues.count
                )
            }
            activeRun = nil
        } catch let failure as UpdateRunFailure {
            pendingUpdatePlan = nil
            updateResult = .failed(failure)
            auditHistory = await audit.history()
            await publishDiscovery()
            activeRun = nil
        } catch {
            pendingUpdatePlan = nil
            await publishDiscovery()
            activeRun = nil
            throw error
        }
    }

    // L4 IN: 仅 awaiting-confirmation 且冻结 plan 存在时可取消。
    // OUT: 发布 cancelled 结果与 terminal-only cancelled 审计，并把目标检出投影为 check-unknown。
    // INVARIANT: executing 不可取消；即使旧观察仍 fresh，也不能继续支撑 update-available。
    // TEST: repo://PaguguTests/AppModelTests.swift::testCancelUpdateIgnoresFreshObservationUntilNewCheckAndWritesCancelledAudit。
    // L6 CHAIN: 待确认 plan → 首次 await 前转入 cancelling 并清空 plan → 标记目标检出需重新检查 →
    //           terminal-only cancelled 审计 → 完整事实刷新为 check-unknown → 释放互斥。新的成功检查解除标记。
    func cancelUpdate() async {
        guard activeRun == .updateAwaitingConfirmation, let plan = pendingUpdatePlan else { return }
        activeRun = .updateCancelling
        pendingUpdatePlan = nil
        checkoutPathsRequiringCheckAfterCancellation.insert(plan.checkoutCanonicalPath)
        let runner = UpdateRunner(
            gitInspector: gitInspector,
            gitExecutor: gitExecutor,
            audit: audit
        )
        await runner.cancelPrepared(plan)
        auditHistory = await audit.history()
        pendingUpdatePlan = nil
        updateResult = .cancelled(checkoutPath: plan.checkoutCanonicalPath)
        updateRefreshFailure = nil
        await publishDiscovery()
        activeRun = nil
    }

    func dismissUpdateResult() {
        updateResult = nil
        updateRefreshFailure = nil
    }

    func dismissRegistryResetBackupPath() {
        registryResetBackupPath = nil
    }

    /// App 退出时只尽力终止当前 Git 子进程；run 不持久、不补写 terminal。
    /// 已写 start 而未写 terminal 的 Update 审计在重启后按 interrupted-unknown 呈现。
    func terminateInFlightGitProcesses() {
        gitExecutor.terminateInFlight()
    }

    // L4 IN: 受限恢复「退出自行修复」经此发出应用退出 intent。
    // OUT: 请求应用退出；不重置 Registry、不发布工作流。生产入口由 PaguguApp 注入 NSApplication.terminate。
    // INVARIANT: View 不直接 terminate；退出仍走 applicationWillTerminate → terminateInFlightGitProcesses。
    // TEST: repo://PaguguTests/AppModelTests.swift::testRequestQuitTerminatesApplicationWithoutEnteringWorkflow
    //       repo://PaguguTests/PaguguTests.swift::testContentViewRecoveryQuitDoesNotCallNSApplicationTerminate
    func requestQuit() {
        terminateApplication()
    }

    func addProjectScanRoot(_ url: URL) async {
        do {
            try await registry.addProjectScanRoot(url)
            projectScanRootError = nil
            await publishDiscovery()
        } catch let error as ProjectScanRootError {
            handleProjectScanRootError(error)
        } catch {
            projectScanRootError = .notLoaded
        }
    }

    func removeProjectScanRoot(canonicalPath: String) async {
        do {
            try await registry.removeProjectScanRoot(canonicalPath: canonicalPath)
            projectScanRootError = nil
            await publishDiscovery()
        } catch let error as ProjectScanRootError {
            handleProjectScanRootError(error)
        } catch {
            projectScanRootError = .notLoaded
        }
    }

    func clearProjectScanRootError() {
        projectScanRootError = nil
    }

    /// 写前按当前 Installation 事实与目标 Skill 重查；呈现组和内容指纹都不能成为映射键。
    func createSourceMapping(
        installationCanonicalPath: String,
        targetIdentity: SkillIdentity
    ) async -> Bool {
        let installation = readModel.unattributedInstallations
            .flatMap(\.installations)
            .first {
                $0.canonicalPath == installationCanonicalPath && $0.projectionType == .copy
            }
        guard let installation, installation.sourceMapping == nil else {
            sourceMappingError = .installationUnavailable
            return false
        }
        guard readModel.mappingTargets.contains(where: { $0.id == targetIdentity }) else {
            sourceMappingError = .targetUnavailable
            return false
        }

        do {
            let changed = try await registry.createSourceMapping(
                installationCanonicalPath: installationCanonicalPath,
                target: SourceMappingRecord(
                    skillSourceKey: targetIdentity.sourceKey.registryValue,
                    repositoryRelativePath: targetIdentity.repositoryRelativePath
                )
            )
            sourceMappingError = nil
            if changed { await publishDiscovery() }
            if changed { auditHistory = await audit.history() }
            return changed
        } catch let error as SourceMappingError {
            handleSourceMappingError(error)
            return false
        } catch {
            sourceMappingError = .notLoaded
            return false
        }
    }

    func deleteSourceMapping(installationCanonicalPath: String) async -> Bool {
        do {
            let changed = try await registry.deleteSourceMapping(
                installationCanonicalPath: installationCanonicalPath
            )
            sourceMappingError = nil
            if changed { await publishDiscovery() }
            if changed { auditHistory = await audit.history() }
            return changed
        } catch let error as SourceMappingError {
            handleSourceMappingError(error)
            return false
        } catch {
            sourceMappingError = .notLoaded
            return false
        }
    }

    func clearSourceMappingError() {
        sourceMappingError = nil
    }

    /// 显式确认后清空审计集合：只删历史，不动 Registry 与用户仓库，不留墓碑。写失败 fail-open。
    func clearAuditHistory(confirmed: Bool) async {
        guard confirmed else { return }
        await audit.clearHistory()
        auditHistory = await audit.history()
    }

    /// 「最近活动」失败详情只提供导航：按身份快照解析当前已发现 Skill。
    func skillIdentity(
        matchingSnapshotSourceKey sourceKey: String,
        repositoryRelativePath: String
    ) -> SkillIdentity? {
        readModel.sources
            .first { $0.id.registryValue == sourceKey }
            .flatMap { source in
                source.skills.first { $0.id.repositoryRelativePath == repositoryRelativePath }?.id
            }
    }

    // L4 IN: confirmed 只接受显式确认结果。
    // OUT: 成功后呈现 quarantine 备份路径并恢复完整扫描。
    // FAIL: 未确认与任务取消不改变现有受限恢复态；其余错误必须投影稳定反馈。
    // TEST: repo://PaguguTests/AppModelTests.swift（未确认、取消、未分类错误与写失败）。
    func resetRegistry(confirmed: Bool) async {
        do {
            let backupURL = try await registryResetter.reset(confirmed: confirmed)
            registryRecovery = nil
            registryReady = true
            projectScanRootError = nil
            sourceMappingError = nil
            registryResetBackupPath = backupURL?.path
            await publishDiscovery()
        } catch let error as ProjectScanRootError
            where error == .persistence(.resetConfirmationRequired) {
            // 未确认是调用合同内的预期结果。保持现有受限恢复态。
        } catch let error as ProjectScanRootError {
            if case .persistence(.writeFailed(let recovery)) = error {
                projectScanRootError = error
                registryRecovery = recovery
                registryReady = false
                readModel = .empty()
                return
            }
            handleProjectScanRootError(error)
        } catch is CancellationError {
            // 任务取消不冒充 Registry 写失败。保持调用前状态。
        } catch {
            projectScanRootError = .notLoaded
        }
    }

    /// 收起/展开来源仓库行的子 Skill 列表（chevron 独立热区触发的纯 UI intent）。
    func toggleSourceCollapsed(_ key: SkillSourceKey) {
        if collapsedSources.contains(key) {
            collapsedSources.remove(key)
        } else {
            collapsedSources.insert(key)
        }
    }

    /// 读取所选条目的 SKILL.md 原文（只读、可选中展示）；读取失败返回 nil。
    func skillMarkdown(canonicalPath: String) -> String? {
        Discovery.skillMarkdown(atCanonicalPath: canonicalPath)
    }

    private func handleProjectScanRootError(_ error: ProjectScanRootError) {
        projectScanRootError = error
        switch error {
        case .persistence(.externallyModified(let recovery)),
             .persistence(.recoveryRequired(let recovery)):
            registryRecovery = recovery
            registryReady = false
            readModel = .empty()
        case .fileSystemRoot, .homeDirectory, .personalSkillRoot,
             .personalSkillRootAncestor, .unavailable, .duplicate, .notLoaded,
             .persistence(.writeFailed), .persistence(.invalidDocument),
             .persistence(.notLoaded), .persistence(.resetConfirmationRequired):
            break
        }
    }

    private func handleSourceMappingError(_ error: SourceMappingError) {
        sourceMappingError = error
        switch error {
        case .persistence(.externallyModified(let recovery)),
             .persistence(.recoveryRequired(let recovery)):
            registryRecovery = recovery
            registryReady = false
            readModel = .empty()
        case .notLoaded, .alreadyMapped, .installationUnavailable, .targetUnavailable,
             .persistence(.writeFailed), .persistence(.invalidDocument),
             .persistence(.notLoaded), .persistence(.resetConfirmationRequired):
            break
        }
    }
}
