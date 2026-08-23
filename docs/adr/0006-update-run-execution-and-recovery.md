# Update Run：确认、执行、失败恢复与刷新合同

Status: accepted

Related: Dimon94/pagugu#7、Dimon94/pagugu#5、Dimon94/pagugu#6、repo://docs/adr/0003-skill-source-checkout-update-target.md、repo://docs/adr/0004-checkout-git-state-and-eligible-update.md、repo://docs/adr/0005-check-run-and-checkout-observation.md、repo://CONTEXT.md

## Context

MVP 1.0 需要把「对一个 Eligible Update 从确认到失败恢复与刷新」落成端到端合同。已锁定的事实锚点：Eligible Update 的唯一充要条件是前置 L0–L3 通过且 Checkout Git State = update-available（ADR-0004 §8）；Checkout Observation 永不充当执行许可，执行前必须 fetch 并按同一合同重查，以重查快照为唯一执行计划（ADR-0004 §9、ADR-0005 §11）；更新副作用只允许对共享仓库的 fetch 与在被选检出工作树内的 ff-only（ADR-0003 §6）；一次更新只修改一个明确选定的物理工作树（ADR-0003 §7）；批量更新、自动 push、多检出同步在地图 Out of scope。

Git 行为事实已在一次性 scratch 仓库实测（git 2.52.0，命令可复现）：`merge --ff-only <精确SHA>` 在 remote tip 已超越该 SHA 时静默成功，tip 漂移不能靠 merge 报错发现；HEAD 已在目标时 exit 0 输出 "Already up to date."；ff merge 触发 post-merge hook（pre-merge-commit 不触发），`-c core.hooksPath=/dev/null` 可屏蔽；index.lock 被外部占用时 exit 1 且 HEAD 不动；分叉时 exit 128 且 HEAD 不动；`fetch <remote> <branch>` 只移动该分支的 tracking ref；`GIT_TERMINAL_PROMPT=0` 与 SSH BatchMode 下认证/网络失败秒级返回，且 fetch 类失败 exit 均为 128，无法用 exit code 区分子类。

本合同将被 App Registry schema（#8）、模块 seam（#9）与界面呈现（#10）消费，改向成本高。

## Decision

### 1. Update Run 瞬态不持久，无持久更新记录

一次更新动作是 Update Run：fetch 并重查目标检出、用户确认精确 target SHA、ff-only 应用、post-verify 与刷新。瞬态、不持久；不新增任何持久记录。更新后的状态完全由实时 Git Fact 与既有 Checkout Observation 的 freshness 派生（成功后 HEAD == upstream tip == 观察记录 tip），失败同理。被否决：持久化 run 记录与更新结果——可完全派生的真相一旦落盘即成第二真相，与 ADR-0005 §1 同一理由。

### 2. 端到端时序：重查 → 确认 → 执行

点击更新后：① fetch 目标检出的 upstream 分支；② 重读目标检出身份摘要与全部 Git Fact，按 ADR-0004 同一合同重新裁决（不重跑 Discovery Scan，L0–L2 以入口时刻为准）；③ 仅当重查为 update-available 才弹出确认，确认绑定重查快照中的精确 target SHA；④ 确认后执行前做最后一次轻量比对（HEAD、身份摘要、remote tip 未漂移），任何漂移 fail closed 回到重查；⑤ ff-only 应用到该精确 SHA；⑥ post-verify；⑦ 刷新。确认永不超时自动执行。被否决：先确认后重查——确认绑定陈旧观察，tip 变化时仍需二次确认，确认不再反映真实执行计划。

已接受的代价：确认前的 fetch 会移动 remote-tracking ref；若 tip 恰在此前变化，用户取消确认后该检出按 freshness 合同（ADR-0005 §7）回落 check-unknown，恢复动作是重新检查。这是诚实呈现真实远端变化，不是状态丢失。

### 3. 重查状态映射

重查结果为 up-to-date：直接告知「已是最新」，noop，不弹确认。为其余 10 个非 update-available 态：阻断，呈现该主状态与既定人工恢复方向，不弹确认。为 update-available：进入确认。映射是 12 态合同（ADR-0004 §6）在更新流程上的直接投影，不新增状态语义。

### 4. 确认事实清单

确认至少呈现并绑定：Skill Identity（Skill Source Key + 仓内相对路径）、目标 Skill Source Checkout 的 Canonical Path、branch 名与 upstream ref 名、当前 HEAD SHA、目标 tip SHA、behind 数，以及一句影响范围声明（仅 fast-forward 此工作树；不动其他检出、不写任何安装目录）。全部取自重查快照，无新增采集；布局与文案归 #10。

### 5. 命令与副作用顺序：分离 fetch + ff-only 精确 SHA

执行序列：捕获 expected old HEAD → `git fetch <remote> <upstream-branch>`（单分支，最小副作用，实测不动其他 tracking ref）→ 重查并取 upstream tip 为 target SHA → 确认 → `git merge --ff-only <精确 target SHA>` → post-verify。被否决：`git pull` 或合并 FETCH_HEAD——FETCH_HEAD 可被并发 fetch 覆写，且行为受用户 pull 配置影响；被否决：按 merge 报错检测 tip 漂移——实测 ff 到旧 SHA 静默成功，必须显式比对 target SHA 与 fetch 后 upstream tip。

### 6. 非交互执行边界，hook 必须屏蔽

全部 Git 子进程非交互运行：`GIT_TERMINAL_PROMPT=0`、置空 `GIT_ASKPASS`、`SSH_ASKPASS_REQUIRE=never` 或等价 BatchMode；任何交互需求（凭证、passphrase、host key 确认）一律表现为失败而非挂起，恢复方向是用户在终端修复。merge 附加 `-c core.hooksPath=/dev/null` 屏蔽 post-merge hook（实测 ff 会触发）。被否决：允许 post-merge hook 运行——hook 可写任意文件，违反 ADR-0003 §6 副作用边界。Pagugu 不改用户任何 Git 配置、不写 credential。

### 7. 并发保护：App 级单一互斥，锁不是真相

Update Run 与 Check Run 互斥、Update Run 之间互斥；任一 run 进行中，检查与更新动作均禁用，不 join、不取消、不替换（沿用 ADR-0005 §9）。同一 Skill Source Key 的 linked worktree 不做特殊锁定，sibling-conflict 裁决（ADR-0004 §7）已在事实层覆盖。被否决：按检出或按 git-common-dir 细粒度锁——MVP 只有一个全量检查入口与一个更新动作，细粒度只增加组合状态。

外部 Git 进程（用户终端、其他工具、第二个应用实例）不受 App 锁约束：锁永不当真相。防御全部由事实承担——执行边界重读身份摘要、HEAD、branch/upstream、严格 dirty、sibling-conflict 与 remote tip；任何不一致落入失败分类。跨进程安全最终靠 Git 自身锁（index.lock/ref lock，实测 fail closed 且 HEAD 不动）+ 精确 SHA 绑定 + post-verify。

### 8. 成功充要条件与 noop

post-verify 六项全部成立才算成功：merge exit 0；HEAD == 精确 target SHA；严格 clean（ADR-0004 §3 口径）；branch 名与 upstream 配置不变；身份摘要不变；无进行中 Git 操作标记。任一不满足即 verification-failed，即使 exit 0。HEAD 已等于 target 的 "Already up to date" 视为成功 noop——结果等于意图。

### 9. 失败九类，各配稳定恢复方向

| 失败类 | 触发 | 人工恢复方向 |
| --- | --- | --- |
| lock-busy | index.lock/ref lock 被外部进程占用 | 确认无其他 Git 进程后重试 |
| identity-changed | 检出被替换/移动，或 origin/branch/upstream 变更 | 重新扫描后重新检查 |
| fetch-failure | 认证、网络或远端分支消失（原始 stderr 呈现，exit code 不区分子类） | 终端验证网络与凭证后重试 |
| precondition-changed | 重查命中 dirty/diverged 等阻断态 | 按该态既定恢复方向处理 |
| tip-changed | 确认后执行前 remote tip 漂移 | 重新发起更新（自动重查并重新确认） |
| ff-rejected | 执行瞬间出现分叉 | 终端处理分叉后重新检查 |
| command-failure | 其他 Git 非零退出 | 查看原始原因后重试 |
| verification-failed | exit 0 但成功条件不全 | 终端核对仓库状态 |
| interrupted-unknown | App 崩溃、退出或子进程被杀 | 重新扫描，按当前 Git 事实处理 |

失败类按发生阶段互斥；不模式匹配 stderr 细分 fetch 子类（实测 exit 均为 128，匹配脆弱），原始信息直接呈现。

### 10. 零自动重试、零自动回滚

任何阶段失败即止于稳定态并给出恢复方向；重试永远是用户重新发起整个 Update Run，该动作幂等可重入。永不做自动 reset、force、checkout 覆盖或 stash：ff-only 要么整体移动 ref、要么不动（实测失败时 HEAD 不动）；进程被杀的极端残留（半更新工作树、遗留 index.lock）以 Git 事实如实呈现，由用户在终端处置。被否决：自动重试 fetch——失败语义不再稳定可解释，收益不抵成本；被否决：失败自动回滚——MVP 优先不丢数据，任何覆盖性操作违反 fail closed。

### 11. 崩溃与退出：不持久、不重放

Update Run 退出即中断，尽力终止进行中的 Git 子进程。重启后不存在「更新中」状态，无未完成操作恢复流程：一切由实时 Git Fact 重推导——ff 要么已完成（呈现 up-to-date）、要么未发生（原状）、要么留下 Git 层可见残留（dirty/lock，按既有状态语义呈现）。与 ADR-0005 §8 的 Check Run 崩溃语义同构。被否决：持久 Update Run 与恢复状态机——Git 操作秒级，持久化只制造第二真相。

### 12. 更新后刷新：事实重读 + 完整扫描，失败不回滚

成功后：① 立即重读目标检出 Git Fact，状态派生为 up-to-date；② 既有 Checkout Observation 不删不动，freshness 派生下仍有效（身份摘要未变、tracking ref == 记录 tip）；③ 触发一次完整 Discovery Scan 刷新 Skill Read Model（ff 可能增删改 SKILL.md，归因与聚合需重算）；④ 刷新失败（扫描部分/失败）独立于更新结果呈现——已验证成功的更新不被伪装成失败，绝不回滚；⑤ 复制投影不被写入、不传播、不触发批量同步（ADR-0001 §4、ADR-0003 §7 不变）；软链接与仓库本体投影即时读到新内容，无需任何传播动作。被否决：局部重读代替完整扫描——引入第二刷新路径，与「全量单一口径」（ADR-0005 §2）哲学冲突；被否决：刷新失败回滚更新——伪装失败并破坏真实成功状态。

### 13. 输出边界与审计证据去向

对 #8：更新语义零新增持久需求；最小审计证据若需持久，归独立 follow-up 决策票「定义 MVP 1.0 的最小审计证据与故障恢复呈现」，本票不偷渡 schema。对 #9：一个 Update Run seam 的语义边界——负责时序编排、互斥、失败分类与 post-verify，消费 Git Fact 层与 ADR-0004/0005 合同，永不以观察为执行许可；不定义模块清单与公开 interface。对 #10：稳定呈现语义为确认事实清单（§4）、cancel 后果（§2）、失败九类与恢复方向（§9）、noop 语义（§3、§8）、刷新失败与更新结果分离（§12）；不定义布局、组件、颜色与图标。

## Consequences

### 正面

- tip 漂移显式可检测：确认绑定精确 SHA，执行前比对，不依赖 merge 报错（实测不可靠）。
- 确认永远反映将要真实执行的计划；二次确认路径不存在。
- 失败面收敛为九个稳定类，各配人工恢复方向；零自动写恢复动作，不丢用户数据。
- 无持久 run、无 TTL、无恢复状态机：更新生命周期全部由实时 Git Fact 重推导。
- #8/#9/#10 接缝收窄为最小面：零新持久需求、一个 seam 语义、一组稳定呈现语义。

### 负面 / 成本

- 确认前 fetch 可能使旧观察失效：取消后检出回 check-unknown，需一次重新检查（可解释、fail closed）。
- 零自动重试把瞬时网络抖动留给用户重新发起。
- 成功后完整 Discovery Scan 比局部重读贵；本地操作，成本可接受。
- post-merge hook 被屏蔽：依赖该 hook 的工作流在 Pagugu 发起的更新中不触发；是否需要记录归审计证据 follow-up 票。

### 边界

本 ADR 冻结 Update Run 术语与瞬态性、端到端时序与精确 SHA 绑定、重查范围与状态映射、确认事实清单、命令与副作用顺序、非交互与 hook 边界、并发粒度与外部进程姿态、成功充要条件、失败九类与恢复方向、零重试零回滚、崩溃语义与更新后刷新。不裁决：App Registry JSON schema、字段名、迁移版本与原子写入（归 #8）；模块清单、公开 interface 与依赖图（归 #9）；布局、组件、文案与完整交互原型（归 #10）；审计证据的留存、粒度与呈现（归 follow-up 决策票）。若未来引入自动重试、自动回滚、批量更新、持久 Update Run 或把观察用作执行许可，需立新 ADR supersede 本记录的相应小节。
