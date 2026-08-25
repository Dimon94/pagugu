import Foundation

// L3 COORD: Pagugu/AppModel/AppModel.swift
// POS: AppModel 模块（ADR-0009 §7）。@MainActor composition root：
//      owns Skill Read Model、受限恢复模式投影、全部 UI intent 与启动/刷新编排。
//      does not own 直接 Git/文件系统/持久 IO、业务规则重建。
// TEST: repo://PaguguTests/AppModelTests.swift（Registry gate、Project Scan Root intent 与扫描刷新 smoke）。

@MainActor
final class AppModel: ObservableObject {

    // MARK: - 公开只读投影

    @Published private(set) var readModel: SkillReadModel = .empty()
    @Published private(set) var registryRecovery: RegistryRecovery?
    @Published private(set) var registryReady = false
    @Published private(set) var projectScanRootError: ProjectScanRootError?

    // MARK: - 内部依赖（构造注入）

    private let personalRoots: [String]
    private let registry: AppRegistry

    init(
        personalRoots: [String] = Discovery.personalSkillRoots,
        persistence: Persistence = .live
    ) {
        self.personalRoots = personalRoots
        self.registry = AppRegistry(persistence: persistence, personalRoots: personalRoots)
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
        }
    }

    private func publishDiscovery() async {
        let projectScanRoots = await registry.projectScanRoots()
        let scanResult = Discovery.scanAll(
            personalRoots: personalRoots,
            projectRoots: projectScanRoots.filter(\.passesGuardrails).map(\.canonicalPath)
        )
        let entries = SkillDirectory.entries(from: scanResult)
        readModel = SkillReadModel(
            entries: entries,
            issues: scanResult.issues,
            scanOutcome: scanResult.outcome,
            projectScanRoots: projectScanRoots
        )
    }

    // MARK: - UI Intents

    /// 用户请求重新扫描。
    func rescan() async {
        guard registryReady, registryRecovery == nil else { return }
        await publishDiscovery()
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
