# Pagugu 产品愿景

Status: confirmed product intent

本文是 Pagugu 产品动机、目标用户、目标体验和品牌方向的 canonical owner。当前实现状态以 repo://docs/architecture/current-system-map.md 为准。

## 为何存在

Codex、Claude Code 与 Pi 等 Agent Host 会从个人目录、项目目录和托管插件加载 Skill。用户同时使用多个 Agent Host、多个项目和多台 Mac 后，需要手工判断以下信息：

- 系统里安装了哪些 Skill。
- 同一个 Skill 被哪些 Agent Host 使用。
- Skill Installation 对应哪个 Skill Source。
- 远程是否有更新，本地是否安全可更新。

这些关系分散在 `.claude`、`.agents`、`.codex`、软链接和 Git 仓库中。直接覆盖安装目录可能破坏本地修改、来源所有权或同名异源内容。

各 Agent Host 围绕 Skill 的可见性与调用规则同样各自为政：同名 precedence、隐式曝光开关与禁用机制分散在宿主配置、SKILL.md frontmatter 和第三方扩展中，能力与语义逐宿主不同。

Pagugu 把这些关系与规则整理成一个本地、可解释、可安全操作的 macOS 产品。

## 目标用户

首位目标用户是同时使用 Codex、Claude Code 与 Pi，并维护自有及第三方 Skill 的个人开发者。用户希望在多台电脑间保持 Skill 最新，但不愿逐个目录和仓库执行检查。

未来可服务具有相同工作方式的 Agent Skill 重度用户。团队协作、云端账户和集中式 Skill 托管不属于当前产品方向。

## 第一成功体验

用户打开 Pagugu 后，可以完成一条闭环：

1. 看见个人目录和已选择项目目录内的 Skill。
2. 看见每个 Skill 的 Agent Host、安装位置、Skill Source 和 Git 状态。
3. 打开详情，理解状态原因并维护来源映射。
4. 对 Eligible Update 执行一次安全更新。
5. 对被阻止的更新，看见明确原因和人工恢复动作。

用户不需要先理解软链接、插件缓存或 Git 分支细节。

## MVP 1.0

MVP 1.0 验证“单机安全更新闭环”。用户在一台 Mac 上可以：

1. 发现三个 Personal Skill Root 和明确选择的 Project Scan Root 中的 Skill。
2. 看清 Agent Host、Skill Installation、Skill Source 与 Git 状态的关系。
3. 维护来源映射，并理解同名异源或来源不明的阻断原因。
4. 手动检查更新，对一个 Eligible Update 执行安全 fast-forward。
5. 在更新被阻止或失败时，看见明确原因和人工恢复动作。

MVP 1.0 使用主窗口承载完整闭环。现有状态栏入口只负责打开主窗口和退出应用。

以下能力延后到 MVP 1.0 之后：托管插件来源、多机或云端同步、自动推送 Skill Source、每日后台检查与系统通知、完整状态栏工作流、批量更新、签名、公证和发布。

## 产品期待

### 统一发现

- 自动扫描 `~/.claude/skills`、`~/.agents/skills` 与 `~/.codex/skills`。
- 递归扫描用户明确选择并保存的 Project Scan Root，发现其中的项目级安装与源码仓库内的 Skill（后者可以没有安装）。
- 同时覆盖自有 Skill 与第三方开源 Skill。
- 同一个 Skill 安装到多个 Agent Host 时聚合为一个条目（聚合全部安装位置与宿主槽位）；内容完全一致的复制安装聚合为一个只读「来源不明」呈现组，不做来源推断。
- 按 Agent Host、Skill Source 和 Skill Installation 展示关系，而不是只列目录名。
- 识别真实 `SKILL.md`、frontmatter、软链接和 Git 来源。托管插件的首批范围仍为 Unknown。

### 状态与详情

- 主窗口包含多个清晰板块，并支持在多个 Agent Host 间查看和筛选。
- 每个 Skill 显示稳定、可解释的状态。
- Skill 详情显示安装位置、来源仓库、远程链接、使用它的 Agent Host、上次检查时间和状态原因。
- 用户可以维护来源映射。Pagugu 不把来源映射编辑等同于直接修改 Skill 内容。
- 界面明确区分“已安装”“有更新”“可安全更新”和“需要人工处理”。

### 安全同步

- 自有 Skill 推送到远程后，其他电脑可以在 Pagugu 中检查并一键同步。
- 第三方 Skill 也使用相同的检查和更新体验。
- 一键更新只作用于已识别、干净且可 fast-forward 的 Skill Source。
- 脏仓库、分叉、无远程、来源不明或同名异源时，Pagugu 阻止更新并解释恢复动作。
- “一键”表示减少重复操作，不表示跳过安全检查。

### 调用面调控

- Pagugu 内化各 Agent Host 的 Skill 加载与可见性规则（宿主规则档案），以统一的可视化方式呈现并调控每个 Skill 对每个宿主的调用面档位：完全暴露、降级曝光（name-only）、仅显式、全禁用。
- 同名共存组如实呈现，并按宿主语义解释（遮蔽或歧义共存）；它不参与 Skill 身份判定。
- 调控只写 Agent Host 配置或 Pagugu 独占文件，永不写 SKILL.md 等 Skill 内容。
- Agent Host 配置文件的事实优先：主张与事实分歧时呈现不覆盖，恢复由用户显式触发。
- 宿主不支持的档位如实呈现为缺口，不静默降级。

### 主动提醒

- Pagugu 每日执行本地检查。
- 发现更新时，通过应用内状态和系统通知提醒用户。
- 状态栏入口显示简要状态，并提供打开主窗口和处理更新的短路径。
- 检查计划与上次观察结果可以持久化；它们不成为 Skill 内容的第二真相。

### 原生产品体验

- 产品是原生 macOS 应用。核心工作流同时适合主窗口和状态栏入口。
- 信息层级清楚。状态、来源和下一步动作可以快速辨认。
- CC Switch 只作为多板块、状态概览和原生工具体验的参考，不要求复刻其其他功能。
- 视觉设计需要支持 Skill 浏览、筛选和选择，不把安全状态藏在装饰之后。

## 产品原则

- **本地优先。** 扫描、状态判断、配置和更新在本机完成。
- **来源优先。** Skill Source 拥有内容真相；Skill Installation 是 Agent Host 可读取的投影。
- **安全优先。** 更新条件不确定时 fail closed，并给出恢复动作。
- **关系透明。** 用户可以追溯 Skill、安装位置、Agent Host 与远程来源。
- **状态可解释。** 界面说明为什么能更新或为什么被阻止。
- **操作克制。** Pagugu 只操作用户选择的 Project Scan Root 和所有权明确的 Skill Source。

## 品牌方向

- 产品名：`Pagugu`。
- 中文角色名：`帕咕咕`。
- 品牌 IP：寄居蟹（Hermit Crab）。
- 名称来源：寄居蟹属名 `Pagurus`，采用“动物词根 + 三音节 + 尾音重复 + 开口元音”的宠物化命名逻辑。
- 产品隐喻：同一个 Skill 可以进入不同 Agent Host 的“外壳”；Pagugu 帮助用户识别、检查并安全维护这些关系。
- 正式 Logo：C1-T4「探壳」寄居蟹。暖金黄身体与双钳 `#EFB63E`，午夜靛紫壳与眼睛 `#29245C`。
- 主题色：暖米白 `#F4EBDD`。它作为 Logo 纯色背景与产品主背景；午夜靛紫作为交互强调色。
- 正式资产：正方形、圆角矩形、圆形三种完整彩色版本，另含 macOS AppIcon 与单色状态栏模板图标。坐标为 repo://docs/product/assets/brand 与 repo://Pagugu/Assets.xcassets。

寄居蟹轮廓用于 App 图标、状态栏小图标和后续角色视觉。完整视觉规范和专业商标可用性仍为 Unknown。

## 明确边界

Pagugu 不替代 Codex、Claude Code 或 Git。它不遍历整个 Home，不托管 Skill 内容，不写 SKILL.md 等 Skill 内容，不覆盖来源不明的安装目录，也不以 UI、缓存、日志或 App Registry 作为 Skill 内容真相。

## PROTOCOL

变更产品定位、目标用户、用户问题、第一成功体验、核心能力、体验原则或品牌方向时，更新本文。

若变更 canonical term，同步更新 repo://CONTEXT.md。若变更当前模块、状态所有权、依赖或运行边界，同步更新 repo://docs/architecture/current-system-map.md。难回退且存在真实取舍的决定写入 accepted ADR。
