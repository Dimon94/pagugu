# Pagugu 自带 Pi 可见性扩展

Status: accepted

Related: repo://CONTEXT.md、repo://docs/adr/0010-invocation-surface-write-channel-and-host-config-ownership.md、repo://docs/adr/0004-checkout-git-state-and-eligible-update.md

## Context

Pi 原生没有设置级的 Skill 隐藏开关。`disable-model-invocation` frontmatter 能达到「仅显式」效果，但只能写进 SKILL.md——即写 Skill Source 内容，会让检出变 dirty，直接触发 ADR-0004 的 dirty 阻断，腐蚀更新裁决基础（排除）。第三方扩展 pi-skillful（MIT）实现了 settings 驱动的 hiddenSkills，但把第三方扩展的配置当合同面太脆：扩展升级、卸载或配置格式变化都会让 Pagugu 的写入失效（排除直接依赖）。

已核实的 Pi 事实（本机官方文档 docs/extensions.md、docs/skills.md）：扩展放置于 `~/.pi/agent/extensions/`（`*.ts` 或 `*/index.ts`）即自动发现，`/reload` 可热加载；扩展是有完整系统权限的任意 TypeScript 代码，`node:fs` 可用；`systemPromptOptions` 钩子让扩展参与 system prompt 组装，可检查并修改 Pi 已加载的 skills。

## Decision

### 1. Pagugu 复刻 pi-skillful 的 hiddenSkills 机制为自带扩展

Pagugu 分发并维护自己的 Pi 扩展（安装到 `~/.pi/agent/extensions/` 下），在 system prompt 组装时把配置列表中的 Skill 从模型上下文剔除，保留 `/skill:name` 显式调用。只复刻 hiddenSkills 能力；pi-skillful 的祖先发现与 `/skill:name` 内联调用与可见性无关，不复刻。pi-skillful 为 MIT 许可，复刻合法并保留许可声明。

### 2. 配置为 Pagugu 独占文件，文件即主张

扩展读取 Pagugu 独占的配置文件（不入 Pi 的 settings.json）。Pagugu 是唯一写者，天然免除共享所有权的外部修改检测；文件本身就是可见性主张的 canonical，不入 App Registry（ADR-0010 §5 的例外）。Pi 侧生效时机为 Pi 启动、新会话或 `/reload`，Pagugu 在写入后提示用户重载。被否决：写入 Pi settings.json（引入合并写与冲突检测，而该配置的唯一消费者是 Pagugu 自己的扩展，无收益）。

### 3. 扩展是 Pagugu 管理的新交付物

扩展自身的安装、升级、卸载与 Pi 扩展 API 兼容性由 Pagugu 负责。扩展缺失或版本不兼容时，Pi 侧调用面只读呈现并给出修复指引，写入口禁用（fail closed，与 ADR-0010 §4 同款）。

## Consequences

### 正面

- Pi 获得「仅显式」档，机制两端（扩展 + 配置）都由 Pagugu 自控，无第三方依赖。
- 独占文件单写者，天然免除共享所有权的冲突检测。

### 负面 / 成本

- 新交付物生命周期：扩展的安装、升级、卸载与 Pi 扩展 API 兼容性归 Pagugu 管理；分发面从单个 App 扩为 App + 扩展文件。
- 生效依赖 Pi 启动、新会话或 `/reload`，非即时。

### 边界

- 本 ADR 冻结：自带扩展复刻 hiddenSkills、配置为 Pagugu 独占文件且文件即主张、不写 SKILL.md、不复刻无关能力。
- 不裁决：扩展实现细节与升级通道（默认假设随 App 更新重装，归实现票）。
- 开工第一个 spike：验证 `systemPromptOptions` 能否移除 skill 条目，以及能否阻断 `/skill:name` 显式调用（决定 Pi 是否支持「全禁用」档，当前 Unknown）。
- 未来 Pi 原生提供设置级可见性控制时，自带扩展退役为只读适配，立新 ADR supersede 本记录。
