<module>
模块职责：Registry 拥有 Project Scan Root 串行 mutation、护栏校验、主张生命周期与逐检出观察单槽替换。
不拥有：registry.json 物理 IO、Discovery Scan、Skill Read Model、Check Run 编排或来源映射业务入口。
公开入口：`AppRegistry.load()`、Project Scan Root 既有入口、`checkoutObservations()`、`recordCheckoutObservation(_:)`、`reset(confirmed:)`。
依赖：Foundation 与 Persistence。不得直接写文件，不得删除用户目录，不得级联删除来源映射或观察槽。
成员：`Registry.swift` 保存 Project Scan Root 语义、稳定错误、只读可用性投影与观察的 durable-first 单槽替换。
反模式：禁止持久化可用性、自动删除不可用记录、把写失败降级为内存态、重复实现 Persistence 写路径。
测试锚点：repo://PaguguTests/RegistryTests.swift。
</module>
