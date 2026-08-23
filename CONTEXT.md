# Pagugu Context

本文件保存 Pagugu 的统一语言。代码、测试、issue 和文档使用以下 canonical term。

## 已确认词汇

**Pagugu**
: 面向 Codex 与 Claude Code 的本地 macOS Agent Skill 管理与安全同步应用。本次仓库只有可运行技术基线，尚未实现扫描和更新。

**Agent Host**
: 加载 Skill 的宿主环境。首批宿主为 Codex 与 Claude Code。
_Avoid_: 把 `.agents`、`.claude` 或 `.codex` 目录本身当成 Agent。

**Skill**
: Skill Source 内一个仓内路径下的 Skill 内容单元，由 Skill Identity 标识。它是列表的 canonical 条目，聚合自身全部 Skill Installation。在 Project Scan Root 中发现的 Skill 可以没有任何 Skill Installation（仅来源条目）。
_Avoid_: 把单个 Skill Installation 或安装目录当成 Skill 本身。

**Skill Source**
: 拥有一个或多个 Skill 内容的 canonical Git 仓库。它是 Skill 内容的唯一真相。
_Avoid_: 每个 Skill 必须对应独立仓库、按安装目录猜远程来源。

**Skill Source Key**
: Skill Source 的稳定标识。有 `origin` 远程时为规范化远程 URL（归一到 host 与仓库路径：忽略协议与认证方式、去 `.git` 尾缀、host 小写、路径大小写不归一）；无远程时为仓库 canonical 绝对路径。fork 是不同的 Skill Source。
_Avoid_: 把未规范化的远程 URL 原文当键、按安装目录反推来源、把 fork 合并为同一来源。

**Skill Source Checkout**
: 一个 Skill Source Key 在本机的一个物理 Git 工作树，以其工作树根的 Canonical Path 标识。独立 clone 与 Git worktree 链接工作树都是 Skill Source Checkout；多个检出是否共享同一 Git 仓库由 Git 事实派生。重叠 Scan Root 命中同一工作树根，只产生同一检出的多个 as-found 入口。
_Avoid_: 副本、拷贝；用 Worktree 统称全部物理检出。

**Skill Installation**
: Agent Host 可读取的 Skill 投影。它可以是软链接、复制内容或受托管插件提供的有效来源。
_Avoid_: 把安装投影反向当成 Skill Source、覆盖同名异源内容。

**Projection Type**
: Skill Installation 的形态分类：软链接、复制、仓库本体（安装路径即 Skill Source 工作树）。软链接完全解析后归因到目标所在的 Skill Source；复制不自动归因。

**Unattributed Installation**
: 无法唯一归因到 Skill Source 的 Skill Installation（界面标注「来源不明」）：软链接目标不在任何已发现 Skill Source 内，或复制投影没有有效的来源映射。不参与去重合并、不可更新，维护有效来源映射后获得身份。
_Avoid_: 用内容哈希或相似度启发式自动归因复制投影（MVP 1.0 不做）。

**Skill Identity**
: 判定同一个 Skill 的稳定事实，由 Skill Source Key 与 Skill 在仓库内的相对路径构成。frontmatter `name` 与安装目录名只是展示元数据，不参与身份判定。
_Avoid_: 用 frontmatter `name`、安装目录名或安装位置作去重主键。

**Personal Skill Root**
: Pagugu 自动发现个人 Skill Installation 的受支持根目录。首批为 `~/.claude/skills`、`~/.agents/skills` 与 `~/.codex/skills`。

**Project Scan Root**
: 用户明确选择并保存的项目父目录。Pagugu 只在这些目录内递归发现任意含 SKILL.md 的目录，不遍历整个 Home。保存时校验：不得为文件系统根、Home 目录、Personal Skill Root 本身或其祖先。

**Scan Root**
: Personal Skill Root 与 Project Scan Root 的统称。Pagugu 的全部发现动作只发生在 Scan Root 内。

**Discovery Scan**
: 遍历全部 Scan Root 发现 Skill 与 Skill Installation 的动作。它跟随软链接并以 Canonical Path 去重，产出 Scan Result。
_Avoid_: 用缓存或上次观察结果替代实时遍历。

**Scan Result**
: 一次 Discovery Scan 的产物，分完整、部分、失败三态。部分或失败结果不得充当完整真相参与更新资格裁决。

**Scan Issue**
: Discovery Scan 中跳过的单项问题（不可读目录、断链、不可解析的 SKILL.md 等），含路径与原因。它不计为 Skill，不参与去重与裁决。
_Avoid_: 把 Scan Issue 当成 Skill 状态。

**Canonical Path**
: 完全解析软链接后的绝对路径。归因、去重与无远程 Skill Source Key 使用 Canonical Path；界面展示使用 as-found 路径。
_Avoid_: 用 as-found 路径做归因或去重。

**来源映射**
: 用户为复制投影维护的归因主张：Skill Installation 的 Canonical Path 指向一个 Skill Identity。只对 Unattributed Installation 开放，一个 Installation 至多一条；软链接与仓库本体的自动归因不可覆盖。映射目标必须是当前已发现的 Skill。它是主张而非事实：每次完整 Discovery Scan 重验证，当前文件系统与 Git 事实优先。
_Avoid_: 人工覆盖软链接或仓库本体的归因、把映射指向未发现的来源、用映射记录反推磁盘事实。

**失效映射**
: 依赖事实不再成立的来源映射：Installation 不再作为复制投影的 Skill Installation 被发现、目标 Skill Source Key 不再被发现，或仓内相对路径不存在。失效判定只在完整 Scan Result 下进行；Installation 回到 Unattributed Installation；记录保留并呈现原因，事实重新成立时自动复活，只能由用户显式删除。
_Avoid_: 静默删除失效记录、用部分或失败 Scan Result 判定失效、引入人工确认复活中间态。

**App Registry**
: Pagugu 未来在 Application Support 中保存的单个本地 JSON。它只拥有 Project Scan Root、来源映射、检查计划和上次观察结果，不拥有 Skill 内容。

**Git Fact**
: 对单个 Skill Source Checkout 实时只读检查得到的正交原始事实，是 Checkout Git State 裁决的唯一输入。缓存、日志、UI 与 App Registry 不得充当 Git Fact。
_Avoid_: 用上次观察结果或 UI 投影替代实时 Git 事实。

**Check Run**
: 一次手动触发、对启动时刻完整 Scan Result 快照中全部应检查 Skill Source Checkout 执行检查的过程。瞬态不持久，scope 在启动时冻结；run 中身份变化的检出在发布校验时丢弃其观察，不错绑到另一个物理检出。
_Avoid_: 单检出或局部检查入口（MVP 1.0 只有全量）、持久化 run 聚合状态。

**Checkout Observation**
: Check Run 对单个 Skill Source Checkout 的完成结果：成功（含远端 tip sha 证据）或失败，附完成时间与身份摘要。App Registry 只持久逐检出单槽的上次观察结果；有效性由实时身份摘要与 remote-tracking ref 比对完全派生，无 TTL，永不充当当前 Git 真相。
_Avoid_: 用上次观察结果替代实时 Git Fact、持久化 Checkout Git State 或 Eligible 结论、引入 TTL 过期字段或有效/失效标志位。

**Checkout Git State**
: 由 Git Fact 与检查结果确定性派生的单个 Skill Source Checkout 互斥主状态。共 12 态，按固定 precedence 取主恢复方向：inspection-failed > no-remote > detached > no-upstream > upstream-mismatch > sibling-conflict > check-unknown > dirty > diverged > ahead-only > update-available > up-to-date。每个阻断态配一句人工恢复方向；全部 Git Fact 仍逐检出保留。
_Avoid_: 把 UI 投影、Scan Issue 或检查结果当作检出状态；用组合状态枚举替代互斥主状态。

**Eligible Update**
: 针对单个 Skill Source Checkout 裁决的更新资格：Scan Result 完整、归因与 Skill 身份成立、按既定规则选定检出后，该检出的 Checkout Git State 为 update-available 是唯一充要条件。其余 11 态均不可更新，各配人工恢复方向。同一 Skill Source Key 下其他检出的状态不影响本检出的资格。同名异源本身不阻断更新，只在展示层要求消歧呈现。
_Avoid_: 用 Installation 层状态或多检出聚合状态充当更新资格。

**Skill Read Model**
: Pagugu 从 Skill Source、Skill Installation 与 Git 状态生成的只读 UI 投影。可更新性在 Skill Source Checkout 层逐检出裁决，Skill Installation 层只有归因状态。它不能反向成为第二真相。

## 仍为 Unknown

- Skill 呈现层状态聚合与详情字段的最终公开合同（Git 层 Checkout Git State 枚举已由 Dimon94/pagugu#5 冻结）。
- 托管插件来源的首批支持范围。
- 签名、公证与 GitHub Releases 发布流程。
- 专业商标可用性。
- 各 Agent Host 对 skills 目录的精确加载规则（递归深度、隐藏目录、无效 frontmatter 容错）官方未完整写明；Codex 是否读取项目内 `.codex/skills` 未知。
