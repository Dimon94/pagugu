# 检出 Git 状态与 Eligible Update 合同

Status: accepted

Related: Dimon94/pagugu#5、Dimon94/pagugu#6、Dimon94/pagugu#7、repo://docs/adr/0001-skill-identity.md、repo://docs/adr/0003-skill-source-checkout-update-target.md、repo://CONTEXT.md

## Context

MVP 1.0 需要把「本地是否安全可更新」落成稳定、互斥、可解释的合同。已锁定的事实锚点：Eligible Update 按单个 Skill Source Checkout 裁决，多检出不做虚假聚合（ADR-0003）；状态裁决与更新目标单一真相，Skill Read Model 只读派生（ADR-0001 第 6 节）；部分或失败 Scan Result 不得参与更新资格裁决（Dimon94/pagugu#3）；批量更新与自动推送 Skill Source 在地图 Out of scope。本合同将被检查生命周期（#6）、更新执行（#7）、App Registry schema（#8）与后续界面票消费，改向成本高。

Git 行为事实已在一次性 scratch 仓库实测（git 2.52.0，命令可复现）：porcelain 报告 staged/unstaged/untracked（非 ignored）/unmerged/submodule 任意变化，不报告 ignored 文件；ff-only merge 只在触碰到脏 tracked 文件或覆盖 untracked 文件时中止，无关 untracked/ignored 文件放行；`git worktree add -f` 可把同一 branch 强制检出到第二个 linked worktree，之后任一侧的 ff-only merge 静默移动共享 branch ref，另一 worktree 呈现假脏，git 运行时不拦截。

## Decision

### 1. 三层单向真相链

Git 事实层对单个 Skill Source Checkout 做实时只读检查，产出 Git Fact；裁决层是确定性纯函数，输入 Git Fact、已确认的 Skill Identity 与检查结果，输出该检出的 Checkout Git State；呈现层（Skill Read Model）只读消费。App Registry、UI、缓存、日志与上次观察结果不得回写或充当 Git Fact。被否决：由持久观察结果充当当前 Git 状态——陈旧快照冒充真相，违反 fail closed。

### 2. 正交 Git Fact + 单一互斥主状态

每个检出持有少量正交 Git Fact：检出有效性、HEAD 形态（on branch / detached）、origin 存在性、upstream 配置、upstream 身份一致性、严格 dirty、相对位置（behind-only / up-to-date / ahead-only / diverged）、检查结果三态、兄弟 worktree 冲突、inspection 失败。每个检出恰好命中一个互斥 Checkout Git State，多条件同时成立时按固定 precedence 取主恢复方向；全部 Git Fact 仍逐检出保留并呈现。被否决：组合状态枚举——状态爆炸且不可解释。被否决：只保留主状态——dirty 与检查失败并存时吞掉可诊断事实。

### 3. 严格 dirty 口径

以下任何一类可观察变化即判 dirty 并 fail closed：staged、unstaged、untracked（非 ignored）、unmerged 路径、submodule 任意变化（新提交 / tracked 内容修改 / 内部未跟踪内容）、进行中的 merge、rebase 或 cherry-pick（即使工作区恰好干净）。ignored 文件不算 dirty，与 Git 语义一致。被否决：git 原生口径（无关 untracked 放行，只在 ff 实际被阻断时报错）——放行边界依赖对 merge 触碰路径的预判，随远端 diff 变化，无法向用户稳定解释。

### 4. 更新目标 = 当前 branch 的 upstream

ahead/behind 只对 upstream 度量。裁决前校验：upstream 所属 remote 的规范化 URL 必须等于该检出的 Skill Source Key，不一致即阻断（upstream-mismatch），防止从身份之外的 remote 拉取。无 origin 的 path-key 来源判 no-remote，永不可更新（ADR-0001 第 2 节）。当前 branch 无 upstream 判 no-upstream，恢复是用户自行配置，Pagugu 不代设。被否决：代设 upstream 或以 origin 默认分支为更新目标——写用户 git 配置违反操作克制，默认分支猜测会制造错误更新目标。

### 5. 检查结果三态输入

裁决消费的检查结果只有三态：成功（含远端 tip commit 证据）、失败、从未检查。Eligible Update 要求存在成功结果；失败或缺失时相对位置判 Unknown，fail closed 不可更新。结果是否过期、何时重查与 freshness 呈现全部归 Dimon94/pagugu#6，本合同不定义「过期」。

### 6. 互斥主状态与 precedence

Checkout Git State 共 12 态，precedence 从高到低：`inspection-failed`（Git 只读检查本身失败）> `no-remote` > `detached` > `no-upstream` > `upstream-mismatch` > `sibling-conflict` > `check-unknown`（无成功检查结果）> `dirty` > `diverged` > `ahead-only` > `update-available` > `up-to-date`。排序原则：信息缺失高于目标安全，目标安全高于执行安全，执行安全高于本地未提交工作，本地未提交工作高于远端结构关系。detached、no-upstream、upstream-mismatch 在事实层互斥（无 branch 即无 upstream），其相对顺序仅为可读性。check-unknown 高于 diverged/ahead-only，因为相对位置的计算依赖检查成功；dirty 高于 diverged/ahead-only，因为解决分叉的动作可能破坏未提交工作，先提示保护本地数据。

### 7. 兄弟 worktree 冲突 proactive 检测

裁决输入事实：本检出的当前 branch 是否同时被同一 Git 仓库（`git rev-parse --git-common-dir` 解析后相同）的另一个 linked worktree checkout（经 `git worktree list --porcelain` 枚举）。是即判 sibling-conflict 并 fail closed，恢复方向是用户自行处理另一 worktree。检测必须在裁决期 proactive 完成，不能依赖 git 运行时拦截——实测 git 不拦截强制双检出后的 ref 移动（见 Context）。具体命令、锁与执行前重查时序归 Dimon94/pagugu#7。

### 8. Eligible Update 充要条件

前置 gate 链依次为：L0 Scan Result 完整 → L1 归因成立（Unattributed Installation 与失效映射在此层阻断）→ L2 Skill 身份确认 → L3 检出选择（ADR-0003 规则）→ L4 检出 Git 裁决。通过 L0–L3 后，Checkout Git State 为 update-available 是 Eligible Update 的唯一充要条件：inspection 成功、有 origin、当前 branch 有 upstream 且身份一致、无兄弟 worktree 冲突、严格干净、存在成功检查结果、behind>0 且 ahead=0。up-to-date 与 ahead-only 不可更新但不是故障；其余阻断态各配一句人工恢复方向。非 Git 阻断归属 L0–L1 层，绝不伪装成 Checkout Git State。

### 9. 输出边界

对 UI 与后续票：每个 Checkout Git State 对应一个稳定英文 reason code（即第 6 节 12 个 code，机器可读、永久稳定）、中文显示名与一句人工恢复方向；正交 Git Fact 全量供详情层逐检出呈现；不定义字段名、schema、列表分组与布局（归 Dimon94/pagugu#8 与界面票）。对 #7：执行目标是主状态为 update-available 的检出；裁决与执行之间事实可变，执行时必须以满足同一合同的重查快照为准；副作用边界沿用 ADR-0003 第 6 节不变。对 #6：裁决输入即第 5 节三态，检查生命周期由 #6 完整拥有。

## Consequences

### 正面

- 主状态互斥且确定派生：组合风险只呈现一个主恢复动作，其余事实不丢，状态可解释直接落地。
- 严格 dirty 与 upstream 身份校验把「丢本地工作」与「拉错来源」两类风险全部前置到裁决期，执行期（#7）无需新增安全判断。
- #6 与 #7 的接缝收窄为三态输入与重查快照，两侧合同不互相侵入。

### 负面 / 成本

- 严格 dirty 比 git 原生更保守：无关 untracked 文件也阻断更新，用户需清理或加入 ignore 后重新检查。
- 当前 branch 无 upstream 的检出需要用户一次性手工配置，MVP 1.0 不提供引导。
- precedence 是产品约定而非 Git 事实；未来新增主状态必须重审全序并立新 ADR。

### 边界

本 ADR 冻结 Git Fact 清单、12 个 Checkout Git State 与 precedence、Eligible Update 充要条件、严格 dirty 口径、upstream 身份校验、兄弟 worktree 冲突检测事实与检查结果三态输入。不裁决：检查生命周期、freshness 与重查 UX（归 #6）；确认 UI、执行锁、fetch/pull 命令序列、执行前重查时序与失败补偿（归 #7）；App Registry 持久 schema、迁移与原子写入（归 #8）；Skill 呈现层状态聚合、详情字段、列表分组与布局（归后续界面票）；多 Eligible 检出选择沿用 ADR-0003，不重开。若未来放宽 dirty 口径（如 git 原生放行）、允许代设 upstream 或新增主状态，需立新 ADR supersede 本记录的第 3、4、6 节。
