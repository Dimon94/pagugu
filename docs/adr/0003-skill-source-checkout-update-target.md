# 同一 Skill Source Key 的多物理检出与单一更新目标

Status: accepted

Related: Dimon94/pagugu#12、Dimon94/pagugu#2、Dimon94/pagugu#3、Dimon94/pagugu#4、repo://docs/adr/0001-skill-identity.md、repo://docs/adr/0002-skill-source-mapping.md、repo://CONTEXT.md

## Context

MVP 1.0 中，同一个 Skill Source Key 可以通过多个独立 clone、Git worktree 链接工作树或重叠 Scan Root 被同时发现。已锁定的事实锚点：Skill Identity =（Skill Source Key，仓内相对路径）（ADR-0001）；扫描以 Canonical Path 去重、as-found 路径只用于展示（Dimon94/pagugu#3）；更新永远只作用于所有权明确的 Skill Source 工作树，永不写 Skill Installation 路径（ADR-0001 第 6 节）；来源映射键是 Installation Canonical Path → Skill Identity，不可改写为检出选择器（ADR-0002）。同一 Source Key 的多物理检出不得被身份去重静默隐藏。更新目标合同进入 Skill Read Model 与更新确认流程，后续状态枚举、持久 schema 与执行流程全部建立在本合同上，改向成本高。

## Decision

### 1. Skill Source Checkout 是一等物理概念

一个 Skill Source Key 在本机的一个物理 Git 工作树是一个 Skill Source Checkout，以其工作树根的 Canonical Path 标识。独立 clone 与 Git worktree 链接工作树都是 Checkout；多个检出是否共享同一 Git 仓库由 Git 事实在运行时派生，不做持久分类。重叠 Scan Root 命中同一工作树根，只产生同一检出的多个 as-found 入口，不产生第二个检出。

### 2. 聚合不吞检出

列表条目仍是 Skill（ADR-0001 第 3 节不变）；条目下全量保留该 Source Key 全部已发现检出与各自状态。任何层级禁止把多检出压成单一虚假聚合状态；每个检出的 branch、dirty、diverged、behind 等 Git 事实是独立事实，分别保留、分别呈现。状态枚举与详情字段的组合归 Dimon94/pagugu#5。

### 3. Eligible Update 按检出裁决，更新目标按可判定性选择

Eligible Update 的裁决单元是单个 Skill Source Checkout。恰好一个检出 Eligible 时，它自动成为更新目标，无需人工选择；多个检出 Eligible 时，用户在发起更新时显式选择一个；零个 Eligible 时阻断，逐检出呈现阻断原因与人工恢复动作。被否决：检出数大于一即强制人工选择——误伤「另一检出本来就不符合条件」的常见场景，增加无信息量的操作。被否决：持久化 sticky 首选检出——引入与来源映射平行的第二套主张-失效-复活状态机，扩大 App Registry schema 与验证面，MVP 1.0 收益不抵成本。

### 4. 人工选择不持久化

人工选择只发生在当次更新动作的确认环节；App Registry 不新增更新目标记录，无失效、复活、删除语义需要定义。确认环节的呈现与流程归 Dimon94/pagugu#7。

### 5. 非目标检出零影响

同一 Source Key 下其他检出的 dirty、diverged、behind 等状态不参与目标检出的资格裁决，只作为明细呈现。被否决：来源级聚合一票否决——兄弟检出的脏状态会误伤干净检出，与「同名异源不阻断」的阻断面原则冲突。

### 6. 共享 Git 仓库的副作用边界

更新只允许两类副作用：对共享仓库的 fetch（只移动 remote-tracking refs，对兄弟 worktree 的工作树零影响）；在被选检出自己的工作树内执行 fast-forward only 合并。任何会移动「当前 checkout 在另一个 linked worktree 上的分支 ref」的操作一律 fail closed，并给出人工恢复动作。具体命令序列、锁与失败恢复归 Dimon94/pagugu#7。

### 7. 单工作树更新不变量

一次更新动作只修改一个明确选定的物理工作树。禁止自动同步全部 clone 与 worktree；批量更新维持地图 Out of scope，本票不重开。

### 8. 投影与检出的关联

软链接完全解析后目标落在某检出工作树内，即归因到该 Skill Source，目标路径同时按包含关系标识具体检出；仓库本体投影的路径本身就是检出工作树根；复制投影只通过来源映射归因到 Skill Identity，永不归因到具体检出，来源映射合同（ADR-0002）一字不改。复制投影对应 Skill 有多个 Eligible 检出时，更新目标选择按第 3 节照常适用。

## Consequences

### 正面

- 去重不隐藏冲突：多检出全量可见，状态差异不被聚合抹平。
- 更新目标永远唯一且明确；单检出用户的「一键更新」体验零新增操作。
- 阻断面收窄到目标检出自身的真实风险，兄弟检出状态不误伤。
- App Registry 不新增记录类型，#8 的 schema 面不因本票扩大。

### 负面 / 成本

- 多个 Eligible 检出的用户每次更新都要选择一次；MVP 1.0 无 sticky 记忆。
- Skill Read Model 需要承载逐检出状态明细，详情呈现复杂度归 #5 消化。

### 边界

本 ADR 冻结 Skill Source Checkout 概念、更新目标选择规则、副作用边界与无虚假聚合原则。不裁决：Git 状态枚举与 Eligible Update 真值表（归 Dimon94/pagugu#5）；App Registry 持久 schema、迁移与原子写入（归 #8）；更新确认、执行锁、fetch/pull 命令序列与失败恢复流程（归 #7）；多检出的列表分组与详情字段呈现（归 #5 与后续界面票）。若 MVP 后引入 sticky 更新目标偏好或自动同步多检出，需立新 ADR supersede 本记录的第 3、4、7 节。
