import Foundation

// L3 COORD: Pagugu/AppModel/AppModel.swift
// POS: AppModel 模块（ADR-0009 §7）。@MainActor composition root：
//      owns Skill Read Model、受限恢复模式投影、全部 UI intent 与启动/刷新编排。
//      does not own 直接 Git/文件系统/持久 IO、业务规则重建。
// TEST: repo://PaguguTests/AppModelTests.swift（Persistence gate、启动投影与 intent 路由 smoke）。

@MainActor
final class AppModel: ObservableObject {

    // MARK: - 公开只读投影

    @Published private(set) var readModel: SkillReadModel = .empty()
    @Published private(set) var registryRecovery: RegistryRecovery?
    @Published private(set) var registryReady = false

    // MARK: - 内部依赖（构造注入，仅 Discovery 层 seam）

    private let personalRoots: [String]
    private let persistence: Persistence

    init(
        personalRoots: [String] = Discovery.personalSkillRoots,
        persistence: Persistence = .live
    ) {
        self.personalRoots = personalRoots
        self.persistence = persistence
    }

    // MARK: - 启动流水线（ADR-0009 §13：#17 接通 Persistence gate）

    /// 先载 Registry。受限恢复时阻断全部业务；正常态才执行 Discovery。
    func start() async {
        switch await persistence.loadRegistry() {
        case .ready:
            registryRecovery = nil
            registryReady = true
            publishDiscovery()
        case .restricted(let recovery):
            registryRecovery = recovery
            registryReady = false
            readModel = .empty()
        }
    }

    private func publishDiscovery() {
        let scanResult = Discovery.scanPersonalRoots(personalRoots)
        let entries = SkillDirectory.entries(from: scanResult)
        readModel = SkillReadModel(
            entries: entries,
            issues: scanResult.issues,
            scanOutcome: scanResult.outcome
        )
    }

    // MARK: - UI Intents（#15 仅路由；#16+ 接通动作）

    /// 用户请求重新扫描。
    func rescan() async {
        guard registryReady, registryRecovery == nil else { return }
        publishDiscovery()
    }

    /// 显式确认后清空三类 Registry 主张；成功后恢复完整扫描。
    func resetRegistry(confirmed: Bool) async {
        do {
            _ = try await persistence.resetRegistry(confirmed: confirmed)
            registryRecovery = nil
            registryReady = true
            publishDiscovery()
        } catch PersistenceError.writeFailed(let recovery) {
            registryRecovery = recovery
            registryReady = false
            readModel = .empty()
        } catch {
            // 未确认与其他失败保持现有阻断态，不制造内存 fallback。
        }
    }
}
