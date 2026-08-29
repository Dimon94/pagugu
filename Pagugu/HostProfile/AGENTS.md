# HostProfile 模块合同（L2）

模块职责: owns 三个 Agent Host 的规则档案：宿主标识、Personal/Project Skill Root 归因表、默认 Personal Skill Root 集合，以及同名共存组的纯函数分组与逐宿主诊断。全部为确定性值类型与纯函数。does not own 文件系统遍历（归 Discovery）、Skill Identity 或 Installation 聚合（归 Identity）、UI 投影（归 AppModel）、宿主配置读写与调用面档位。

成员清单:
- `HostProfile.swift`：`AgentHost`、`HostSkillScope`、`HostProfile`、`HostProfiles`。`HostProfiles.personalSkillRoots()` 是 Discovery 默认根的 canonical owner；`HostProfiles.hosts(for:scope:)` 只按档案归因。
- `NameCollision.swift`：`HostSkillLocation`、`NameCollisionCandidate`、`NameCollisionGroup`、`CollisionDiagnostic` 与 `NameCollisionEngine.groups(from:)`。它按 trim + 大小写折叠后的 frontmatter `name` 分组；name 缺失或空白时回退安装目录名。
- 固定规则：Claude Code 的 Personal 与 Project 同名时 Personal 遮蔽 Project；Codex 与 Pi 的同名位置共存时结果歧义。Personal `~/.agents/skills` 同时归 Codex 与 Pi；Project `.agents/skills` 只归 Codex。Pi 私有 Personal Root 是 `~/.pi/agent/skills`，当前没有 Pi Project Root。

反模式: 不按同名合并 Skill Identity、Installation 或 Source；不让冲突诊断改变更新资格；不读写磁盘；不把一个宿主的遮蔽规则套给其他宿主；不让候选输入顺序改变输出；不在这里实现调用面配置读写。

测试锚点: repo://PaguguTests/DiscoveryPiRootsTests.swift（四个默认 Personal Root 与 Pi/共享根归因）、repo://PaguguTests/NameCollisionTests.swift（名称规范化、目录名回退、Claude 遮蔽、Codex/Pi 歧义）、repo://PaguguTests/IdentityTests.swift（逐路径宿主归因）。
