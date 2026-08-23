# Pagugu Context

本文件保存 Pagugu 的统一语言。代码、测试、issue 和文档使用以下 canonical term。

## 已确认词汇

**Pagugu**
: 面向 Codex 与 Claude Code 的本地 macOS Agent Skill 管理与安全同步应用。本次仓库只有可运行技术基线，尚未实现扫描和更新。

**Agent Host**
: 加载 Skill 的宿主环境。首批宿主为 Codex 与 Claude Code。
_Avoid_: 把 `.agents`、`.claude` 或 `.codex` 目录本身当成 Agent。

**Skill**
: Skill Source 内一个仓内路径下的 Skill 内容单元，由 Skill Identity 标识。它是列表的 canonical 条目，聚合自身全部 Skill Installation。
_Avoid_: 把单个 Skill Installation 或安装目录当成 Skill 本身。

**Skill Source**
: 拥有一个或多个 Skill 内容的 canonical Git 仓库。它是 Skill 内容的唯一真相。
_Avoid_: 每个 Skill 必须对应独立仓库、按安装目录猜远程来源。

**Skill Source Key**
: Skill Source 的稳定标识。有 `origin` 远程时为规范化远程 URL（归一到 host 与仓库路径：忽略协议与认证方式、去 `.git` 尾缀、host 小写、路径大小写不归一）；无远程时为仓库 canonical 绝对路径。fork 是不同的 Skill Source。
_Avoid_: 把未规范化的远程 URL 原文当键、按安装目录反推来源、把 fork 合并为同一来源。

**Skill Installation**
: Agent Host 可读取的 Skill 投影。它可以是软链接、复制内容或受托管插件提供的有效来源。
_Avoid_: 把安装投影反向当成 Skill Source、覆盖同名异源内容。

**Projection Type**
: Skill Installation 的形态分类：软链接、复制、仓库本体（安装路径即 Skill Source 工作树）。软链接完全解析后归因到目标所在的 Skill Source；复制不自动归因。

**Unattributed Installation**
: 无法唯一归因到 Skill Source 的 Skill Installation（界面标注「来源不明」）：软链接目标不在任何已发现 Skill Source 内，或复制投影尚未维护来源映射。不参与去重合并、不可更新，维护来源映射后获得身份。
_Avoid_: 用内容哈希或相似度启发式自动归因复制投影（MVP 1.0 不做）。

**Skill Identity**
: 判定同一个 Skill 的稳定事实，由 Skill Source Key 与 Skill 在仓库内的相对路径构成。frontmatter `name` 与安装目录名只是展示元数据，不参与身份判定。
_Avoid_: 用 frontmatter `name`、安装目录名或安装位置作去重主键。

**Personal Skill Root**
: Pagugu 自动发现个人 Skill Installation 的受支持根目录。首批为 `~/.claude/skills`、`~/.agents/skills` 与 `~/.codex/skills`。

**Project Scan Root**
: 用户明确选择并保存的项目父目录。Pagugu 只在这些目录内递归发现项目级 Skill，不遍历整个 Home。

**App Registry**
: Pagugu 未来在 Application Support 中保存的单个本地 JSON。它只拥有 Project Scan Root、来源映射、检查计划和上次观察结果，不拥有 Skill 内容。

**Eligible Update**
: 已识别 Skill Source 处于干净状态，并且能够 fast-forward 到远程目标。脏仓库、分叉或无远程的 Skill Source，以及 Unattributed Installation，均不符合条件。同名异源本身不阻断更新，只在展示层要求消歧呈现。

**Skill Read Model**
: Pagugu 从 Skill Source、Skill Installation 与 Git 状态生成的只读 UI 投影。可更新性在 Skill Source 层裁决一次，Skill Installation 层只有归因状态。它不能反向成为第二真相。

## 仍为 Unknown

- Skill 状态枚举和详情字段的最终公开合同。
- 无远程 Skill Source 移动目录后的身份连续性策略。
- 托管插件来源的首批支持范围。
- 签名、公证与 GitHub Releases 发布流程。
- 专业商标可用性。
