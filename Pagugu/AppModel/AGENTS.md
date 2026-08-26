# AppModel 模块合同（L2）

模块职责: @MainActor composition root（ADR-0009 §7）。owns Skill Read Model 只读投影（含人工来源映射、目录逐检出状态短语与五档静默排序）、受限恢复与主张动作错误投影（RegistryRecovery / ProjectScanRootError / SourceMappingError）、目录收起、App 级 Check/Update 单一互斥、Check Run/Update 瞬态与失败/取消投影、审计历史投影（auditHistory，只服务呈现）、全部 UI intent 唯一入口、启动与刷新流水线编排（Registry → Discovery → Git inspection → Identity → Eligibility）。每次发布按实时身份与 remote-tracking ref 重推导观察 freshness；失效成功观察保留在 Registry 但不投影观察时间。确认页取消后，目标检出在本次 App 会话新的成功检查前不再消费旧观察，固定投影为 check-unknown。does not own 直接 Git/文件系统/持久 IO（经 Git/Registry/Audit/Discovery/Runs seam）或 Checkout Git State/更新资格重建。

成员清单:
- `AppModel.swift`：公开入口含启动、刷新、全量手动检查、Update 检出候选/prepare/confirm/cancel、Project Scan Root 与来源映射创建/删除、`clearAuditHistory(confirmed:)`、审计失败详情导航解析 `skillIdentity(matchingSnapshotSourceKey:repositoryRelativePath:)`；`activeRun` 是 App 级互斥唯一真相，区分 preparing / awaiting-confirmation / executing / cancelling，并在每个首次 `await` 前原子转换；只有 awaiting-confirmation 可取消。检查与更新入口共用禁用原因。更新选择当次计算且不持久化；失败/取消清空 plan 并释放互斥；取消额外标记目标检出需重新检查，新的成功检查才解除；成功先保留结果再独立完整刷新。post-verify facts 只作为该次刷新的一次性证据，需与刷新时 local-only 身份/HEAD/upstream/dirty/sibling 事实一致；不写 Observation、不跨刷新保留。公开只读投影含 `readModel`、Check Run 进度/汇总、冻结 `pendingUpdatePlan`、更新结果/刷新失败与 Registry 状态。Registry reset 成功后呈现 quarantine 备份路径（registryResetBackupPath，一次性可关闭）。
- `SkillReadModel.swift`：`SkillReadModel`（目录、映射、扫描、Project Scan Root、逐来源检出卡片、目录状态短语与排序）、`CheckoutCardReadModel`（观察与本次检查投影）、目录节点与选择解析入口。
- `RegistryResetting`：AppModel 内部 reset seam。生产只由 `AppRegistry` 实现；测试注入取消或未分类失败，穿过 `resetRegistry(confirmed:)` 验证稳定投影。

反模式: View 不绕过 AppModel 直接 IO 或重建业务规则；AppModel 不解析 Git 输出或复制 Eligibility precedence；不以多个布尔值或 Runs 内锁复制 `activeRun`；收起状态、run 瞬态与 Git Fact 不持久化；投影不反向成为第二真相；受限恢复态不制造内存 fallback。

测试锚点: repo://PaguguTests/AppModelTests.swift（Registry gate、Project Scan Root intent、目录状态短语/排序表、Check Run 投影与 intent 路由 smoke、取消后 fresh 旧观察不再解锁更新；全部用构造注入的临时 Persistence 目录）。
