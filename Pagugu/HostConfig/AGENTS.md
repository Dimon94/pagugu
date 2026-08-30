# HostConfig 模块合同（L2）

模块职责: owns 三个 Agent Host 的调用面配置只读 adapter：Claude Code `settings.json`、Codex `config.toml`/`agents/openai.yaml`、Pi 独占 `visibility.json`；结合 HostProfile 能力矩阵输出 `HostInvocationSurface`。每次调用实时读盘。does not own 配置写入、Visibility Claim、备份、分歧检测、文件监听、Skill Identity、UI 呈现或持久状态。

成员清单:
- `HostConfigReader.swift`：`HostConfigReader.invocationSurfaces(skillName:installations:)` 是唯一读取入口；`ExposureLevel` 与宿主支持矩阵由 repo://Pagugu/HostProfile/HostProfile.swift owns。
- Claude Code JSON 只读 schema：顶层 `skillOverrides` 对象，key 为 Skill name，value 只接受 `on` / `name-only` / `user-invocable-only` / `off`。项目 settings URL 只从 Project Installation 的 `.../.claude/skills/...` 路径派生；项目 key 覆盖用户 key，不存在时继承用户值；同一 Skill Identity 进入多个 Installation 上下文时取最严格档位，避免假报更宽暴露。
- Pi 独占 JSON 只读 schema：顶层 `skills` 对象，key 为 Skill name，value 为 `fullyExposed` / `nameOnly` / `explicitOnly` / `fullyDisabled`。不存在的文件或 key 表示 `fullyExposed`；`nameOnly` 与当前仍为 Unknown 的 `fullyDisabled` 如实返回 Unsupported。
- Codex 兼容 `[[skills.config]]` 的 `path` 与现存旧式 `name` 标识；`enabled = false` 优先派生 `fullyDisabled`。`policy.allow_implicit_invocation = false` 派生 `explicitOnly`。

反模式: 不写宿主配置；不把缺失文件当错误；不把已存在但不可读/损坏文件默认为完全暴露；不把 Unsupported 静默映射为相邻档位；不把读取结果存入 Registry 或缓存为第二真相；不实现通用 TOML/YAML 解析器。

测试锚点: repo://PaguguTests/HostConfigReaderTests.swift（格式、默认值、能力缺口与 fail-closed）；repo://PaguguTests/AppModelSurfaceTests.swift（AppModel 实时聚合与发布）。
