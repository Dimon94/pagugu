# PiExtension 模块合同（L2）

模块职责: owns Pagugu 自带 Pi 可见性扩展资产，以及该资产在 `~/.pi/agent/extensions/pagugu-visibility/index.ts` 的健康检查、幂等原子安装与版本升级。扩展独占读取 `~/.pi/agent/pagugu/visibility.json`：在 `before_agent_start` 从模型上下文剔除 `hiddenSkills` 与 `disabledSkills`，在 `input` 阻断 `disabledSkills` 的 `/skill:name`。配置缺失、不可读或损坏时 Pi 侧 fail open，不阻断 Pi 启动。does not own `visibility.json` 写入、Pi `settings.json`、Skill 内容、Registry Claim、UI 或自动 reload。

成员清单:
- `index.ts`：Pi 自动发现入口，内嵌 `PAGUGU_PI_EXTENSION_VERSION`；只接受互斥、非空且无重复的 `hiddenSkills` / `disabledSkills` 数组。扩展加载时读取独占配置；无效配置回退为空策略。隐藏机制复用 Pi 官方 `formatSkillsForPrompt`，并保留 pi-skillful MIT attribution。
- `PiExtensionManager.swift`：`health()` 实时读取固定安装路径的版本常量，区分 healthy / missing / incompatible / unreadable；`installOrUpdate()` 校验 Bundle 资产版本，内容一致时 no-op，否则原子替换目标。异常给出稳定修复方向。

反模式: 不写 Pi `settings.json`；不写或修改任何 `SKILL.md`；不从第三方扩展读取合同；不让扩展配置损坏阻断 Pi 启动；不在扩展不健康时允许 Pagugu 写可见性配置；不自动触发 Pi `/reload` 或重启；不把扩展健康缓存为持久真相。

测试锚点: repo://PaguguTests/PiExtensionHealthTests.swift（Bundle 资产、缺失/不兼容 fail-closed、修复与幂等升级，以及用 JavaScriptCore 执行实际 Bundle 源码验证隐藏/阻断/fail-open）；运行时边界按 Pi 官方扩展 API 与 repo://docs/adr/0011-pagugu-owned-pi-extension.md。
