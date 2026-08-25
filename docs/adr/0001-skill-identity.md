# Skill 身份以来源键与仓内路径判定

Status: accepted

Related: Dimon94/pagugu#2、repo://CONTEXT.md

## Context

MVP 1.0 需要判定两个 Skill Installation 是否指向同一个 Skill，并在此基础上做去重、聚合、状态裁决与更新目标选择。已锁定的事实锚点：Skill Source 是内容唯一真相，且一个 Source 可含多个 Skill；frontmatter `name` 可撞名，同名异源是常态；安装目录名可被用户修改；复制投影自身不带来源信息。App Registry 未来将持久化来源映射，身份键一旦进入持久数据，改键意味着重映射。

## Decision

### 1. Skill Identity 由 Skill Source Key 与仓内相对路径构成

Skill Source Key：有 `origin` 远程时为规范化远程 URL（归一到 host 与仓库路径：忽略协议与认证方式、去 `.git` 尾缀、host 小写、路径大小写不归一）；无远程时为仓库 canonical 绝对路径。fork 是不同的 Skill Source。frontmatter `name` 与安装目录名只是展示元数据。

被否决：用 frontmatter `name` 或安装目录名作键——可撞、可变的事实不能当主键。被否决：remote URL 原文不规范化——SSH 与 HTTPS 混用会把同一仓库判成异源，制造假阻断。

### 2. 无远程 Skill Source 拥有稳定身份

以 canonical 绝对路径作降级键，参与去重与分组，但不可更新。被否决：无远程即来源不明——会把常态开局（自有 Skill 尚未推送）错误地异常化。

### 3. 列表条目是 Skill，Installation 聚合为属性

同一 Skill Identity 的多个 Skill Installation 不产生独立列表条目，聚合为条目的 Agent Host、安装位置与 Projection Type 属性。被否决：条目等于 Installation——同一来源状态在多行重复出现，诱导逐安装操作，滋生第二真相。

### 4. 软链接完全解析归因，复制不自动归因

软链接解析到底：目标落在某 Skill Source 工作树内即归因到该 Source；否则为 Unattributed Installation。安装路径本身是 Git 工作树时为仓库本体投影。复制投影不做来源归因；未维护来源映射即为 Unattributed Installation：不更新、来源保持 Unknown。内容完全一致的多个复制安装（完整内容指纹相同）自动聚合为一个只读呈现组——一个条目聚合全部安装位置与 Agent Host 槽位；内容不同或无法完整读取时不合并、按安装 Canonical Path 各自单列。聚合仅是呈现，不推断 Skill Source 或更新目标。被否决：启发式自动归因——错配会静默错认来源并把更新写错仓库，违反来源优先与操作克制；被否决：只按名称合并——同名异源必须分开。

（2026-08-25 #16 修正：用户确认「同一个实际 Skill 安装到多个 Agent Host 是常态」，本节原「不去重、按自身路径单列」的呈现口径被 supersede 为内容指纹呈现聚合；复制投影的自动归因禁令不变。）

### 5. 同名异源不阻断更新

Eligible Update 的阻断条件为：脏、分叉、无远程的 Skill Source，以及 Unattributed Installation。同名异源只要求展示层消歧呈现。被否决：撞名即阻断——误伤合法更新，且与身份聚合语义冲突。

### 6. 状态裁决与更新目标单一真相

更新目标永远是 Skill Source 工作树（git fast-forward），永不写 Skill Installation 路径。可更新性在 Skill Source 层裁决一次；安装层只有归因状态。Skill Read Model 派生只读；App Registry 不回写身份或状态。

## Consequences

### 正面

- 去重、聚合、状态裁决与更新目标消费同一身份事实，不产生第二真相。
- 无远程自有 Skill 有一等身份；来源映射是显式人工动作，不是异常恢复。
- 阻断面收窄到真实风险（归属不确定），合法更新不被同名误伤。

### 负面 / 成本

- 无远程 Skill Source 移动目录会改变降级键，表现为旧条目消失、新条目出现；身份连续性策略仍为 Unknown，归 Dimon94/pagugu#4。
- 复制投影在维护映射前不可用，用户需承担一次人工映射成本。
- fork 判为异源，内容相同的多 fork 不合并展示。

### 边界

本 ADR 冻结 Skill 身份键、归因规则与裁决所有权。不裁决：状态枚举与详情字段（归 Dimon94/pagugu#5）、检查与观察结果语义（归 #6）、来源映射的冲突处理细节（归 #4）、筛选组合（目录 IA 由 #11 冻结，复制投影呈现聚合见 §4）。若未来引入托管插件来源或复制启发式归因，需立新 ADR supersede 本记录的相关小节。
