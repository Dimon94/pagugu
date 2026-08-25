<module>
模块职责：Registry 拥有 Project Scan Root 串行 mutation、护栏校验、主张添加顺序、显式删除与合法性/可用性派生。
不拥有：registry.json 物理 IO、Discovery Scan、Skill Read Model、来源映射和观察槽的后续业务入口。
公开入口：`AppRegistry.load()`、`addProjectScanRoot(_:)`、`removeProjectScanRoot(canonicalPath:)`、`projectScanRoots()`、`reset(confirmed:)`。
依赖：Foundation 与 Persistence。不得直接写文件，不得删除用户目录，不得级联删除来源映射或观察槽。
成员：`Registry.swift` 保存 Project Scan Root 语义、稳定错误与只读可用性投影。
反模式：禁止持久化可用性、自动删除不可用记录、把写失败降级为内存态、重复实现 Persistence 写路径。
测试锚点：repo://PaguguTests/RegistryTests.swift。
</module>
