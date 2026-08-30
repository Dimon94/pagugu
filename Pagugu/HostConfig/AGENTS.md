# HostConfig 模块合同（L2）

模块职责: owns 三个 Agent Host 的调用面配置只读 adapter、通用 JSON 宿主配置写通道，以及 Claude Code 用户级 `skillOverrides` adapter。Reader 结合 HostProfile 能力矩阵输出实时文件事实；通用 Writer 只修改 caller 指定的 Pagugu-owned key，原子替换目标、维护单槽备份、恢复并派生主张一致/分歧；Claude adapter 集中映射四档并固定用户级配置路径。does not own Codex/Pi 具体写入映射、Visibility Claim 持久化、文件监听、Skill Identity、UI 呈现或其他持久状态。

成员清单:
- `HostConfigReader.swift`：`HostConfigReader.invocationSurfaces(skillName:installations:)` 是唯一宿主事实读取入口；`ExposureLevel` 与宿主支持矩阵由 repo://Pagugu/HostProfile/HostProfile.swift owns。
- `HostConfigWriter.swift`：`merge(_:at:in:)` 对非空 JSON key path 增删一个叶子 key；提交前重读并比对最初读取字节，外部漂移时 fail closed；原文件存在且未漂移时，写前完整覆盖 `<file>.pagugu-backup`，再用 Foundation 原子替换目标。`restoreBackup(for:)` 原子覆盖恢复且保留备份；`claimState(expecting:at:in:)` 每次实时读盘，只派生 `consistent` / `divergent`。
- `ClaudeConfigWriter.swift`：唯一 Claude Code 写 adapter。`apply(exposureLevel:forSkillNamed:)` 只写用户级 `~/.claude/settings.json` 的 `skillOverrides.<skill name>`；四档映射为 `on` / `name-only` / `user-invocable-only` / `off`，nil 删除 key；`claimState(expecting:forSkillNamed:)` 实时比较映射值；`restoreConfiguration()` 恢复同文件单槽备份。Project settings 仍只读，不由本票写入。
- Claude Code JSON 只读 schema：顶层 `skillOverrides` 对象，key 为 Skill name，value 只接受 `on` / `name-only` / `user-invocable-only` / `off`。项目 settings URL 只从 Project Installation 的 `.../.claude/skills/...` 路径派生；项目 key 覆盖用户 key，不存在时继承用户值；同一 Skill Identity 进入多个 Installation 上下文时取最严格档位，避免假报更宽暴露。
- Pi 独占 JSON 只读 schema：顶层 `skills` 对象，key 为 Skill name，value 为 `fullyExposed` / `nameOnly` / `explicitOnly` / `fullyDisabled`。不存在的文件或 key 表示 `fullyExposed`；`nameOnly` 与当前仍为 Unknown 的 `fullyDisabled` 如实返回 Unsupported。
- Codex 兼容 `[[skills.config]]` 的 `path` 与现存旧式 `name` 标识；`enabled = false` 优先派生 `fullyDisabled`。`policy.allow_implicit_invocation = false` 派生 `explicitOnly`。

反模式: Reader 不写宿主配置；通用 Writer 不决定 key 所有权或具体宿主档位映射、不整文件替换为 caller 自建文档、不静默重应用 Registry Claim；Claude adapter 不写 Project settings；不把缺失文件当读取错误；不把已存在但不可读/损坏文件默认为完全暴露；不把 Unsupported 静默映射为相邻档位；不把读取结果或分歧状态存入 Registry 或缓存为第二真相；不在 JSON 核心中实现 TOML/YAML 解析器。

测试锚点: repo://PaguguTests/HostConfigReaderTests.swift（格式、默认值、能力缺口与 fail-closed）；repo://PaguguTests/HostConfigWriterTests.swift（通用合并保全、单槽备份、恢复与实时分歧）；repo://PaguguTests/ClaudeConfigWriterTests.swift（Claude 四档映射、删除、备份、恢复与分歧）；repo://PaguguTests/AppModelSurfaceTests.swift（AppModel 实时聚合与发布）。
