<module>
模块职责：Persistence 是 registry.json 与 audit-history.json 的唯一物理 IO owner。它拥有持久记录类型、schema 校验、兼容分发、v1→v2 迁移、原子写、quarantine 与 Registry 外部修改检测。
不拥有：Project Scan Root、来源映射、Checkout Observation、Visibility Claim 与审计记录的业务语义；Git、Discovery、Eligibility、宿主配置或 UI 规则。
公开入口：Registry load/save/reset；Audit load/append/clear（`loadAuditDocument()` 损坏返回 nil，`loadAuditEvidence()` fail-open 返回空）。测试通过构造器注入临时目录。
依赖：Foundation、Darwin，以及 HostProfile 拥有的 `AgentHost` / `ExposureLevel` canonical 值类型与支持矩阵纯函数；只用能力矩阵拒绝不受支持的持久主张，不依赖 Git、扫描或 UI。AppModel 只消费 typed 结果，不解析错误字符串。
成员：`Persistence.swift` 保存 Registry v2 / Audit v1 schema、受限恢复结果与唯一 durable 写入实现。Registry v2 增加零时间戳的 `visibilityClaims`；合法 v1 先严格校验，再保留 `registry.v1.pre-migration-*.json`，并在替换 registry.json 的 commit-time 重读比对迁移前字节，未漂移才 durable 写入 v2；漂移保留外部字节并进入 `externallyModified` 受限恢复；未知未来版本绝不覆写。Audit v1 记录以 action 区分来源映射、Check Run terminal 与 Update Run；Update started / success / cancelled / failed terminal 以同一 run ID 关联，failed reason 只接受 schema 自有的九个稳定 wire code；测试锁定该集合与 Runs 的 `UpdateRunFailureReason.rawValue` 完全一致，Persistence 不拥有分类语义。确认前失败保存 target 快照，确认后记录保存冻结计划。
反模式：禁止 Registry/Audit 第二写路径、文件锁、watcher、内存 fallback、静默覆写未来版本、把派生状态或宿主文件事实写入 Registry；Audit 损坏或写失败不得阻断主动作。
测试锚点：repo://PaguguTests/PersistenceTests.swift、repo://PaguguTests/RegistryV2Tests.swift。
</module>
