# AppModel 模块合同（L2）

模块职责: @MainActor composition root（ADR-0009 §7）。owns Skill Read Model 只读投影（含人工来源映射、目录逐检出状态短语与五档静默排序）、受限恢复与主张动作错误投影（RegistryRecovery / ProjectScanRootError / SourceMappingError）、目录收起与 Check Run 瞬态、全部 UI intent 唯一入口、启动与刷新流水线编排（Registry → Discovery → Git inspection → Identity → Eligibility）。每次发布按实时身份与 remote-tracking ref 重推导观察 freshness；失效成功观察保留在 Registry 但不投影观察时间。does not own 直接 Git/文件系统/持久 IO（经 Git/Registry/Audit/Discovery/Runs seam）或 Checkout Git State/更新资格重建。

成员清单:
- `AppModel.swift`：公开入口含启动、刷新、全量手动检查、Project Scan Root 与来源映射创建/删除；映射写前从当前投影重查具体 Installation 与目标 Skill。公开只读投影含 `readModel`、Check Run 进度/汇总与 Registry 状态。
- `SkillReadModel.swift`：`SkillReadModel`（目录、映射、扫描、Project Scan Root、逐来源检出卡片、目录状态短语与排序）、`CheckoutCardReadModel`（观察与本次检查投影）、目录节点与选择解析入口。

反模式: View 不绕过 AppModel 直接 IO 或重建业务规则；AppModel 不解析 Git 输出或复制 Eligibility precedence；收起状态、run 瞬态与 Git Fact 不持久化；投影不反向成为第二真相；受限恢复态不制造内存 fallback。

测试锚点: repo://PaguguTests/AppModelTests.swift（Registry gate、Project Scan Root intent、目录状态短语/排序表、Check Run 投影与 intent 路由 smoke；全部用构造注入的临时 Persistence 目录）。
