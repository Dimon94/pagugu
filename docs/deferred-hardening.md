# 延后加固清单

用途：登记当前阶段不执行的加固工作，让延后成为可检查的记录。阶段定义、延后边界和退出提醒归根 repo://AGENTS.md `<stage>`，本文件只承载条目。

## 维护规则

- 每次对话的工作收口时更新本文件：登记本次发现的新条目，或更新既有条目的证据与严重度。本次没有新发现时，写一行日期加“无新增”。
- 一条条目只登记一个可独立执行的加固动作。“补测试”“做安全审计”这类整体愿望必须拆开。
- 严重度用 repo://docs/agents/quality-standards.md 第 2 节的 P0-P3，由影响和可触发性决定。
- 证据坐标写文件加可搜索符号，或可复跑的命令与运行证据。没有证据时写 Unknown，不写猜测影响。
- 条目在本阶段被用户要求执行后，状态改 Done 并写验证命令；判定为不需要时改 Dropped 并写理由。两种都不删行。
- 清单出现 P0 或 P1 条目是阶段退出信号，按根 repo://AGENTS.md `<stage>` 处理。

## 类别

深度测试、安全扫描、网络安全、生产加固、性能与容量、可观测性、合规。类别之外的延后项先确认它是否属于本清单职责，不扩表。

## 条目

| 日期 | 条目 | 类别 | 触发场景与影响 | 证据坐标 | 严重度 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-08-27 | 无新增 | — | 本次只落地品牌资产、AppIcon 与主题色，未发现需延后加固的问题。 | repo://Pagugu/Assets.xcassets、repo://Pagugu/Views/DesignTokens.swift | — | — |
| 2026-08-27 | 无新增 | — | 本次修复暖米白主题全域覆盖，未发现需延后加固的问题。 | repo://Pagugu/Views/ContentView.swift、repo://Pagugu/Views/MenuBarView.swift | — | — |
| 2026-08-28 | 无新增 | — | 本次为调用面调控设计收敛，只改文档（vision、CONTEXT、ADR-0010、ADR-0011），未触及运行代码，未发现需延后加固的问题。 | repo://docs/product/vision.md、repo://CONTEXT.md、repo://docs/adr/0010-invocation-surface-write-channel-and-host-config-ownership.md、repo://docs/adr/0011-pagugu-owned-pi-extension.md | — | — |
| 2026-08-30 | 无新增 | — | 本次落地 Pi/共享根发现、三宿主 HostProfile 与同名共存只读诊断，未发现需延后加固的问题。 | repo://Pagugu/HostProfile、repo://Pagugu/AppModel/SkillReadModel.swift、repo://Pagugu/Views/ContentView.swift | — | — |
