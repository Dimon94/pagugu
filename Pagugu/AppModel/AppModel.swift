import Foundation

// L3 COORD: Pagugu/AppModel/AppModel.swift
// POS: AppModel 模块（ADR-0009 §7）。@MainActor composition root：
//      owns Skill Read Model、受限恢复模式投影、目录收起与 Check Run 瞬态、全部 UI intent
//      与启动/刷新编排。does not own 直接 Git/文件系统/持久 IO（经 Git/Discovery/Registry/Runs seam）、
//      业务规则重建。
// TEST: repo://PaguguTests/AppModelTests.swift（Registry gate、Project Scan Root intent、
//      目录投影与 intent 路由 smoke）。

@MainActor
final class AppModel: ObservableObject {

    // MARK: - 公开只读投影

    @Published private(set) var readModel: SkillReadModel = .empty()
    @Published private(set) var registryRecovery: RegistryRecovery?
    @Published private(set) var registryReady = false
    @Published private(set) var projectScanRootError: ProjectScanRootError?
    @Published private(set) var checkRunProgress: CheckRunProgress?
    @Published private(set) var checkRunSummary: CheckRunSummary?

    /// 收起的来源仓库行集合（默认全部展开）。瞬态 UI 状态，不持久化。
    @Published private(set) var collapsedSources: Set<SkillSourceKey> = []

    // MARK: - 内部依赖（构造注入）

    private let personalRoots: [String]
    private let registry: AppRegistry
    private let gitInspector: any GitInspecting
    private let gitExecutor: any GitExecuting
    private var checkScope: [CheckRunTarget] = []
    private var checkRunTargetsByPath: [String: CheckRunTarget] = [:]
    private var checkItemOutcomes: [String: CheckRunItemOutcome] = [:]

    init(
        personalRoots: [String] = Discovery.personalSkillRoots,
        persistence: Persistence = .live,
        gitInspector: any GitInspecting = GitClient(),
        gitExecutor: any GitExecuting = GitClient()
    ) {
        self.personalRoots = personalRoots
        self.registry = AppRegistry(persistence: persistence, personalRoots: personalRoots)
        self.gitInspector = gitInspector
        self.gitExecutor = gitExecutor
    }

    // MARK: - 启动流水线（ADR-0009 §13）

    /// 先载 Registry。受限恢复时阻断全部业务；正常态才执行 Discovery。
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
        }
    }

    private func publishDiscovery() async {
        let projectScanRoots = await registry.projectScanRoots()
        let scanResult = Discovery.scanAll(
            personalRoots: personalRoots,
            projectRoots: projectScanRoots.filter(\.passesGuardrails).map(\.canonicalPath)
        )
        let checkoutPaths = Set(scanResult.skills.compactMap(\.repositoryRootPath)).sorted()
        var factsByCheckoutPath: [String: CheckoutGitFacts] = [:]
        for path in checkoutPaths {
            // local-only 先读实时身份与 remote-tracking SHA；新鲜成功观察才解锁相对位置。
            factsByCheckoutPath[path] = await gitInspector.inspectCheckout(at: path, scope: .localOnly)
        }
        let contents = SkillDirectory.contents(
            from: scanResult,
            gitFactsByCheckoutPath: factsByCheckoutPath
        )
        let observations = await registry.checkoutObservations()
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
                return CheckoutCardReadModel(
                    facts: facts,
                    state: CheckoutEligibility.evaluate(facts: facts, sourceKey: source.id),
                    observation: observations[checkout.canonicalPath],
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
        guard registryReady, registryRecovery == nil, checkRunProgress == nil else { return false }
        if case .complete = readModel.scanOutcome { return true }
        return false
    }

    var checkRunDisabledReason: String {
        if checkRunProgress != nil { return "检查正在运行。请等待本次全量检查完成。" }
        if case .complete = readModel.scanOutcome { return "" }
        return "Discovery Scan 不完整。请重新扫描或处理 Scan Issue 后再检查。"
    }

    /// MVP 唯一手动检查入口。scope 在调用时复制冻结；run 瞬态不持久。
    func checkNow() async {
        guard canStartCheckRun else { return }
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
            registry: registry
        )
        for await event in runner.startCheck(scope: frozenScope) {
            switch event {
            case .started(let progress):
                checkRunProgress = progress
                await publishDiscovery()
            case .item(let item, let progress):
                checkItemOutcomes[item.checkoutPath] = item.outcome
                checkRunProgress = progress
                await publishDiscovery()
            case .finished(let summary):
                checkRunSummary = summary
                checkRunProgress = nil
            }
        }
    }

    func dismissCheckRunSummary() {
        checkRunSummary = nil
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

    /// 显式确认后清空三类 Registry 主张；成功后恢复完整扫描。
    func resetRegistry(confirmed: Bool) async {
        do {
            _ = try await registry.reset(confirmed: confirmed)
            registryRecovery = nil
            registryReady = true
            projectScanRootError = nil
            await publishDiscovery()
        } catch let error as ProjectScanRootError {
            if case .persistence(.writeFailed(let recovery)) = error {
                projectScanRootError = error
                registryRecovery = recovery
                registryReady = false
                readModel = .empty()
                return
            }
            handleProjectScanRootError(error)
        } catch {
            // 未确认与其他失败保持现有阻断态，不制造内存 fallback。
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
}
