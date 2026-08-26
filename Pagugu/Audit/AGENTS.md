<module>
模块职责：Audit 拥有审计记录的业务语义与窄 append 入口。当前接收来源映射创建/删除终态、Check Run terminal，以及 Update Run 的 started / success / cancelled / failed terminal；确认前失败只有 target 快照，确认后终态复用冻结 plan。
不拥有：audit-history.json 物理 IO、Registry 当前主张、恢复、重试、回滚或执行许可。
公开入口：`AuditEvidence.recordSourceMapping(...)`、`recordCheckRun(...)`、`recordUpdateStarted(...)`、`recordUpdateSucceeded(...)`、`recordUpdateCancelled(...)`、`recordUpdateFailed(...)`；读取 `history()` 与清空 `clearHistory()` 只服务 UI，均 fail-open。写失败 fail-open，不回滚主动作，也不改变 run outcome。
依赖：Foundation 与 Persistence。不得另建文件写路径或把历史证据当当前事实。
成员：`Audit.swift` 定义原语化 `UpdateAuditTarget` / `UpdateAuditPlan`，构造映射、Check Run 与 Update Run 审计记录并委托 Persistence；`AuditPresentation.project(_:)` 是纯函数呈现投影（ADR-0007 §7）：Update Run 两段记录折叠为一项，terminal 吞掉同 run started，孤儿 started 呈现「结果未知（已中断）」，损坏集合投影为「历史不可用」。
反模式：禁止先写审计再写主张、自动重试、静默改变主动作结果、记录 no-op、失败检出清单或原始 stdout/stderr/exit code；呈现永不把孤儿解释为正在运行、不生成/复制终端命令、不提供一键重试。
测试锚点：repo://PaguguTests/RegistryTests.swift、repo://PaguguTests/CheckRunTests.swift、repo://PaguguTests/AppModelTests.swift（呈现投影与清空）。
</module>
