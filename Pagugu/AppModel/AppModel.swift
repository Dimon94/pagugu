import Foundation

// L3 COORD: Pagugu/AppModel/AppModel.swift
// POS: AppModel 模块（ADR-0009 §7）。@MainActor composition root：
//      owns Skill Read Model 只读投影、全部 UI intent 唯一入口、启动与刷新流水线编排。
//      does not own 直接 Git/文件系统/持久 IO、业务规则重建。
// TEST: repo://PaguguTests/AppModelTests.swift（启动投影与 intent 路由 smoke）。

@MainActor
final class AppModel: ObservableObject {

    // MARK: - 公开只读投影

    @Published private(set) var readModel: SkillReadModel = .empty()

    // MARK: - 内部依赖（构造注入，仅 Discovery 层 seam）

    private let personalRoots: [String]

    init(personalRoots: [String] = Discovery.personalSkillRoots) {
        self.personalRoots = personalRoots
    }

    // MARK: - 启动流水线（ADR-0009 §13 简化版：#15 只走 Discovery → Identity → 发布）

    /// 启动时执行一次完整 Discovery Scan 并发布投影。
    /// 扫描是同步的（MVP 1.0 单线程模型），空 Registry 视为正常态。
    func start() {
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
    func rescan() {
        start()
    }
}
