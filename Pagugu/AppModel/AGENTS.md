# AppModel 模块合同（L2）

模块职责: @MainActor composition root（ADR-0009 §7）。owns Skill Read Model 只读投影（含目录逐检出状态短语与五档静默排序）、受限恢复与主张动作错误投影、目录收起与 Check Run 瞬态、全部 UI intent 唯一入口、启动与刷新流水线编排（Registry → Discovery → Git inspection → Identity → Eligibility）。does not own 直接 Git/文件系统/持久 IO（经 Git/Registry/Discovery/Runs seam）或 Checkout Git State/更新资格重建。

成员清单:
- `AppModel.swift`：公开入口 `start()`、`rescan()`、`checkNow()` 与既有 UI intents；公开只读投影含 `readModel`、Check Run 进度/汇总与 Registry 状态。
- `SkillReadModel.swift`：`SkillReadModel`（目录、扫描、Project Scan Root、逐来源检出卡片、目录状态短语与排序）、`CheckoutCardReadModel`（观察与本次检查投影）、目录节点与选择解析入口。

反模式: View 不绕过 AppModel 直接 IO 或重建业务规则；AppModel 不解析 Git 输出或复制 Eligibility precedence；收起状态、run 瞬态与 Git Fact 不持久化；投影不反向成为第二真相；受限恢复态不制造内存 fallback。

测试锚点: repo://PaguguTests/AppModelTests.swift（Registry gate、Project Scan Root intent、目录状态短语/排序表、Check Run 投影与 intent 路由 smoke；全部用构造注入的临时 Persistence 目录）。
