# AppModel 模块合同（L2）

模块职责: @MainActor composition root（ADR-0009 §7）。owns Skill Read Model 只读投影、受限恢复与主张动作错误投影（RegistryRecovery / ProjectScanRootError）、目录收起 UI 状态（瞬态不持久）、全部 UI intent 唯一入口、启动与刷新流水线编排（先载 Registry，正常态才 Discovery）。does not own 直接 Git/文件系统/持久 IO（经 Registry/Discovery seam）、业务规则重建（归 Identity 纯函数）。

成员清单:
- `AppModel.swift`：公开入口 `start()`、`rescan()`、`addProjectScanRoot(_:)`、`removeProjectScanRoot(canonicalPath:)`、`resetRegistry(confirmed:)`、`toggleSourceCollapsed(_:)`、`skillMarkdown(canonicalPath:)`；公开只读投影 `readModel`、`registryRecovery`、`registryReady`、`projectScanRootError`、`collapsedSources`。
- `SkillReadModel.swift`：`SkillReadModel`（sources + unattributedInstallations + issues + scanOutcome + projectScanRoots）、`directoryNodes(collapsedSources:)` 平铺目录节点派生、`SkillDirectoryNode` 选择模型、按节点解析入口。

反模式: View 不绕过 AppModel 直接 IO 或重建业务规则；收起状态不持久化、不进 App Registry；投影不反向成为第二真相；受限恢复态不制造内存 fallback。

测试锚点: repo://PaguguTests/AppModelTests.swift（Registry gate、Project Scan Root intent、目录投影与 intent 路由 smoke；全部用构造注入的临时 Persistence 目录）。
