# Pagugu Context

本文件保存 Pagugu 的统一语言。代码、测试、issue 和文档使用以下 canonical term。

## 已确认词汇

**Pagugu**
: 面向 Codex 与 Claude Code 的本地 macOS Agent Skill 管理与安全同步应用。本次仓库只有可运行技术基线，尚未实现扫描和更新。

**Agent Host**
: 加载 Skill 的宿主环境。首批宿主为 Codex 与 Claude Code。
_Avoid_: 把 `.agents`、`.claude` 或 `.codex` 目录本身当成 Agent。

**Skill Source**
: 拥有一个或多个 Skill 内容的 canonical Git 仓库。它是 Skill 内容的唯一真相。
_Avoid_: 每个 Skill 必须对应独立仓库、按安装目录猜远程来源。

**Skill Installation**
: Agent Host 可读取的 Skill 投影。它可以是软链接、复制内容或受托管插件提供的有效来源。
_Avoid_: 把安装投影反向当成 Skill Source、覆盖同名异源内容。

**Personal Skill Root**
: Pagugu 自动发现个人 Skill Installation 的受支持根目录。首批为 `~/.claude/skills`、`~/.agents/skills` 与 `~/.codex/skills`。

**Project Scan Root**
: 用户明确选择并保存的项目父目录。Pagugu 只在这些目录内递归发现项目级 Skill，不遍历整个 Home。

**App Registry**
: Pagugu 未来在 Application Support 中保存的单个本地 JSON。它只拥有 Project Scan Root、来源映射、检查计划和上次观察结果，不拥有 Skill 内容。

**Eligible Update**
: 已识别 Skill Source 处于干净状态，并且能够 fast-forward 到远程目标。脏仓库、分叉、无远程或同名异源均不符合条件。

**Skill Read Model**
: Pagugu 从 Skill Source、Skill Installation 与 Git 状态生成的只读 UI 投影。它不能反向成为第二真相。

## 仍为 Unknown

- Skill 状态枚举和详情字段的最终公开合同。
- 托管插件来源的首批支持范围。
- 签名、公证与 GitHub Releases 发布流程。
- 专业商标可用性。
