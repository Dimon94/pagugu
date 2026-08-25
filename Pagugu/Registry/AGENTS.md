<module>
模块职责：Registry 拥有 Project Scan Root 与来源映射的串行 mutation、护栏、显式删除、当前主张投影与逐检出观察单槽替换。
不拥有：registry.json 物理 IO、Discovery Scan、Skill Read Model、Check Run 编排或来源映射有效性裁决。
公开入口：`AppRegistry.load()`、Project Scan Root CRUD、`sourceMappings()`、来源映射 CRUD、`checkoutObservations()`、`recordCheckoutObservation(_:)`、`reset(confirmed:)`。
依赖：Foundation、Persistence 与 Audit。不得直接写文件，不得删除用户目录、Skill Source 或 Git 工作树。
成员：`Registry.swift` 保存主张语义、稳定错误、只读投影与观察的 durable-first 单槽替换；来源映射 durable 后才调用 Audit 窄入口。
反模式：禁止持久化可用性、自动删除不可用记录、把写失败降级为内存态、重复实现 Persistence 写路径。
测试锚点：repo://PaguguTests/RegistryTests.swift；映射创建/删除只审计实际落盘变更。
</module>
