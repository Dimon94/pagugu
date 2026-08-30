# HostProfile 模块合同（L2）

模块职责: owns 三个 Agent Host 的规则档案：宿主标识、Personal/Project Skill Root 归因表、默认 Personal Skill Root 集合、同名共存组规则、四档 Exposure Level 与逐宿主支持能力矩阵。全部为确定性值类型与纯函数。does not own 文件系统遍历（归 Discovery）、Skill Identity 或 Installation 聚合（归 Identity）、UI 投影（归 AppModel）、宿主配置读写与当前调用面档位（归 HostConfig）。

成员清单:
- `HostProfile.swift`：`AgentHost`、`ExposureLevel`、`HostSkillScope`、`HostProfile`、`HostProfiles`。`AgentHost` / `ExposureLevel` rawValue 是 Registry v2 稳定编码值；`HostProfiles.personalSkillRoots()` 是 Discovery 默认根的 canonical owner；`HostProfiles.hosts(for:scope:)` 只按档案归因；`HostProfile.supports(_:)` 裁决档位能力。Claude Code 支持四档；Codex 不支持 `nameOnly`；Pi 不支持 `nameOnly`，且 `fullyDisabled` 仍按 repo://docs/adr/0011-pagugu-owned-pi-extension.md 的 Unknown fail closed。
- `NameCollision.swift`：`HostSkillLocation`、`NameCollisionCandidate`、`NameCollisionGroup`、`CollisionDiagnostic` 与 `NameCollisionEngine.groups(from:)`。它按 trim + 大小写折叠后的 frontmatter `name` 分组；name 缺失或空白时回退安装目录名。
- 固定规则：Claude Code 的 Personal 与 Project 同名时 Personal 遮蔽 Project；Codex 与 Pi 的同名位置共存时结果歧义。Personal `~/.agents/skills` 同时归 Codex 与 Pi；Project `.agents/skills` 只归 Codex。Pi 私有 Personal Root 是 `~/.pi/agent/skills`，当前没有 Pi Project Root。

反模式: 不按同名合并 Skill Identity、Installation 或 Source；不让冲突诊断或调用面档位改变更新资格；不读写磁盘；不把一个宿主的规则套给其他宿主；不让候选输入顺序改变输出；不在这里实现调用面配置读取或写入。

测试锚点: repo://PaguguTests/DiscoveryPiRootsTests.swift（四个默认 Personal Root 与 Pi/共享根归因）、repo://PaguguTests/NameCollisionTests.swift（名称规范化、目录名回退、Claude 遮蔽、Codex/Pi 歧义）、repo://PaguguTests/IdentityTests.swift（逐路径宿主归因）、repo://PaguguTests/HostConfigReaderTests.swift（调用面支持矩阵与 Unsupported）、repo://PaguguTests/RegistryV2Tests.swift（持久编码）。
