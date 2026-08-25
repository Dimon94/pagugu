<module>
模块职责：Audit 拥有审计记录的业务语义与窄 append 入口。当前接收来源映射创建/删除终态与 Check Run terminal。
不拥有：audit-history.json 物理 IO、Registry 当前主张、恢复、重试、回滚或执行许可。
公开入口：`AuditEvidence.recordSourceMapping(...)`、`recordCheckRun(...)`。写失败 fail-open，不回滚已落盘主动作，也不改变 Check Run outcome。
依赖：Foundation 与 Persistence。不得另建文件写路径或把历史证据当当前事实。
成员：`Audit.swift` 构造来源映射与 Check Run terminal 审计记录并委托 Persistence。
反模式：禁止先写审计再写主张、自动重试、静默改变主动作结果、记录 no-op、失败检出清单或原始 stdout/stderr/exit code。
测试锚点：repo://PaguguTests/RegistryTests.swift、repo://PaguguTests/CheckRunTests.swift。
</module>
