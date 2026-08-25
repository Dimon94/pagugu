<module>
模块职责：Persistence 是 registry.json 与 audit-history.json 的唯一物理 IO owner。它拥有持久记录类型、schema 校验、兼容分发、原子写、quarantine 与 Registry 外部修改检测。
不拥有：Project Scan Root、来源映射、Checkout Observation 与审计记录的业务语义；Git、Discovery、Eligibility 与 UI 规则。
公开入口：Registry load/save/reset；Audit load/append。测试通过构造器注入临时目录。
依赖：仅 Foundation 与 Darwin。不得 import 业务模块。AppModel 只消费 typed 结果，不解析错误字符串。
成员：`Persistence.swift` 保存 Registry/Audit v1 schema、受限恢复结果与唯一 durable 写入实现。Audit v1 记录以 action 区分来源映射与 Check Run terminal；后者只存稳定 outcome 与 scope 计数。
反模式：禁止第二写路径、文件锁、watcher、内存 fallback、静默覆写未来版本、把派生状态写入 Registry；Audit 损坏或写失败不得阻断主动作。
测试锚点：repo://PaguguTests/PersistenceTests.swift。
</module>
