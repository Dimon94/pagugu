# 手动检查运行与检出观察语义

Status: accepted

Related: Dimon94/pagugu#6、Dimon94/pagugu#5、Dimon94/pagugu#7、Dimon94/pagugu#8、repo://docs/adr/0003-skill-source-checkout-update-target.md、repo://docs/adr/0004-checkout-git-state-and-eligible-update.md、repo://CONTEXT.md

## Context

MVP 1.0 需要把「用户何时触发检查、检查中与已检查如何表示、结果何时过期、部分失败与重新检查如何处理、上次观察结果如何持久」落成稳定合同。已锁定的事实锚点：三层单向真相链与检查结果三态输入（ADR-0004 §1、§5）；Eligible Update 充要条件与执行前重查快照（ADR-0004 §8、§9）；fetch 只移动 remote-tracking refs、对兄弟 worktree 工作树零影响（ADR-0003 §6，ADR-0004 Context 实测）；部分或失败 Scan Result 不得参与更新资格裁决（Dimon94/pagugu#3）；每日后台检查、系统通知与批量更新在地图 Out of scope。远端变化本地无感，只能 fetch 获知；观察结果一旦持久化并被界面消费，「观察冒充 Git 真相」是最难回退的失败模式。本合同被更新执行（#7）、持久 schema（#8）与后续界面票消费，改向成本高。

## Decision

### 1. Check Run 与 Checkout Observation 是检查语义的 canonical owner

Check Run 是一次手动触发、对一批 Skill Source Checkout 执行检查的过程，瞬态不持久。Checkout Observation 是 Check Run 对单个检出的完成结果：成功（含远端 tip sha 证据）或失败，附完成时间与身份摘要。持久化的只有逐检出单槽的上次观察结果；运行态与持久观察严格分离。被否决：持久化 run 记录与聚合状态——run 是过程不是证据，持久化会制造第二真相入口。

### 2. 单一全量 scope，完整 Scan Result 前置 gate，启动时冻结快照

MVP 1.0 只有一个手动检查动作：对启动时刻完整 Scan Result 中的全部应检查检出执行检查。不存在单检出或局部检查入口；失败项随下次全量自然重试。启动 gate：当前 Scan Result 必须完整；部分或失败时检查动作不可用，恢复动作是重新扫描或处理 Scan Issue——与 Eligible 的 L0 gate（ADR-0004 §8）同一条线。scope 在启动时冻结为快照：run 中磁盘变化不加入也不移除本次对象。被否决：单检出/局部检查——引入第二 scope 类型与并发组合，MVP 收益不抵复杂度。被否决：部分扫描下允许检查——scope 不可信且产出的观察无法驱动 Eligible（L0 已阻断），只制造困惑。

### 3. 本地可判阻断态跳过网络检查

no-remote、detached、no-upstream、upstream-mismatch、sibling-conflict 由实时本地 Git Fact 终局裁决（precedence 均高于 check-unknown，ADR-0004 §6），观察对它们的裁决零影响：run 中跳过网络检查，逐项标记不适用，不产生观察、不计入成败统计。dirty 检出照常 fetch——它需要 behind/ahead 度量才能离开 check-unknown。被否决：对全部检出无差别 fetch——对无 remote/upstream 的检出无对象可拉，且会把非网络对象错算成网络失败，污染部分失败语义。

### 4. side effect 边界：只 fetch

Check Run 只允许 fetch（移动 remote-tracking refs 与 FETCH_HEAD）；不移动工作树与本地 branch、不 stash、不配置 remote/upstream。沿用 ADR-0003 §6 副作用边界不变；具体命令实现归 #7。

### 5. 逐项完成立即发布，发布校验身份摘要

每个检出完成即落槽并刷新其裁决与展示；未完成的检出继续显示上次观察并标注检查中。run 中旧观察在被替换前按第 7 节 freshness 合同保持有效，可支撑 Eligible 展示。观察落槽前比对当前身份摘要与 run 启动时快照：不一致（检出消失、仓库被替换、origin/branch/upstream 在 run 中改变）即丢弃，绝不错绑到另一个物理检出；该检出按从未检查处理。run 中新出现的检出不加入本次 scope。被否决：run 完成后原子发布——全程持有双份投影，列表长时间停在旧状态，与逐检出裁决（ADR-0003 §3）不同构。

### 6. 部分失败：逐项独立生效，失败覆盖旧观察

成功观察完成即独立生效，不等待 run 结束。失败检出的新失败观察覆盖旧观察（单槽），该检出按失败进入 check-unknown，恢复动作是重新检查。聚合 run 态（瞬态，永不持久）：complete（全部应检查检出成功，跳过不计）/ partial（有成功有失败）/ failed（全部失败或 run 级错误）。被否决：失败时保留旧成功（双槽）——远端被删除导致持续失败时，检出会凭陈旧成功证据一直显示 update-available，正是本合同要消灭的观察冒充真相。

### 7. freshness 合同：身份绑定 + 实时重算，无 TTL

成功观察作为 ADR-0004 §5「成功检查输入」的条件是有效性完全派生，无持久标志位：实时本地事实与观察记录的身份摘要一致（Checkout Canonical Path 指向同一 git 仓库、规范化 remote URL 等于 Skill Source Key、当前 branch 名与 upstream ref 名不变），且当前 upstream remote-tracking ref sha 等于观察记录的远端 tip。任一不一致即失效，按从未检查处理；失效不删除记录，事实恢复即重新有效（沿用 ADR-0002 §7 的派生哲学）。HEAD 与 dirty 不是失效条件：它们是实时 Git Fact，裁决时实时重算相对位置。观察不设时间 TTL——纯时间不是远端变化的证据；观察完成时间永远伴随显示，供人判断。远端静默变化本地不可检测，最终安全边界是 #7 执行前按同一合同重查；观察永不充当执行许可。被否决：TTL 过期——无证据的任意定时器，过期时刻与远端真实变化无关。被否决：把 HEAD 纳入失效条件——HEAD 变化由实时重算正确覆盖（本地 commit 实时判出 diverged，手动 pull 实时判出 up-to-date），失效只会制造多余的 check-unknown。

### 8. 崩溃与重启：run 不持久，观察跨 session 重推导

进行中的 Check Run 不持久、不恢复；App 退出即中断，已完成检出的观察已落槽保留，未完成的保留各自旧观察。重启后不存在检查中状态；上次观察结果按第 7 节同一 freshness 合同对实时事实重推导：有效即正常参与裁决、可直接支撑 Eligible 展示与更新入口（始终显示观察时间），无效按从未检查处理。已确认的风险边界：重启后旧观察可驱动更新入口，远端静默变化的最终拦截完全由 #7 执行前重查承担。被否决：重启后一律 check-unknown——身份摘要与远端 ref 双重比对已是强证据，无证据的保守让每次重启丢失全部状态展示，违背打开即见状态的愿景。

### 9. 重新检查与并发：全量单一口径，run 中禁用

重新检查只有全量一种，scope 取启动时刻新的完整 Scan Result 快照；无失败项单独重试、无单检出重查。run 进行中检查动作禁用：不 join、不取消、不替换；无取消按钮，App 退出即中断（第 8 节）。被否决：重试失败项入口——第二 scope 类型；fetch 是秒级操作，收益不抵状态机复杂度。

### 10. 对 #8 的持久边界：只存本地无法重读的证据

必须持久：逐检出单槽上次观察结果——结果（成功/失败）、完成时间、成功时远端 tip sha、身份摘要（Checkout Canonical Path、git 共同目录标识、规范化 remote URL、branch 名、upstream ref 名）。明确不能持久：run 聚合态、检查中 overlay、Checkout Git State、Eligible 结论、Scan Result 本体——全部实时派生。不引入观察历史槽、TTL 字段、有效/失效标志位。本票不定义 JSON schema、字段名、迁移版本与原子写入（归 #8）。

### 11. 对 #7 与界面票的输出边界

对 #7：观察永不充当执行许可；执行前必须 fetch 目标检出 upstream 并按 ADR-0004 与本合同重新裁决，以重查快照为准；本票不定义确认 UI、执行锁、命令序列、重查时序与失败补偿。对界面票：稳定语义为检查中瞬态、不适用标注、观察时间常显、check-unknown 恢复动作是手动检查、失败观察显示原因、聚合 run 总结区分 complete/partial/failed；不定义列表分组、筛选、详情布局、颜色与图标。

## Consequences

### 正面

- 观察在结构上不可能冒充 Git 真相：它只保存本地无法重读的远端 tip 证据，其余全部实时派生，有效性无可持久标志位可腐烂。
- 无定时器、无历史槽、无恢复状态机：检查生命周期全部语义由一条规则覆盖——身份摘要与远端 ref 比对。
- #7 与 #8 的接缝收窄为最小面：#7 拿到「重查是唯一安全边界」，#8 拿到「单槽观察证据」。

### 负面 / 成本

- 用户在终端手动 fetch 后，remote-tracking ref 与观察记录不一致，观察失效回 check-unknown，需要一次重新检查恢复（可解释、fail closed）。
- 一次网络抖动使失败检出覆盖旧成功观察回 check-unknown，恢复动作是一次全量重新检查。
- 重启后旧观察直接驱动更新入口，依赖 #7 执行前重查兜底；若 #7 弱化重查，本合同的安全叙事同步失效。

### 边界

本 ADR 冻结 Check Run/Checkout Observation 术语、scope 与启动 gate、跳过集合、side effect 边界、发布与部分失败语义、freshness 合同、崩溃/重启语义、重新检查并发规则与对 #7/#8/界面票的输出边界。不裁决：确认 UI、执行锁、fetch/pull 命令序列、执行前重查时序与失败补偿（归 #7）；App Registry JSON schema、字段名、迁移版本、并发与原子写入（归 #8）；列表分组、筛选、详情布局、颜色与图标（归后续界面票）。若未来引入 TTL 或后台调度、双槽/历史观察、单检出或局部检查、把观察用作执行许可，需立新 ADR supersede 本记录的第 2、6、7、9 节。
