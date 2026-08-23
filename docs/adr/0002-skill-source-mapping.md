# Skill 来源映射是每次扫描重验证的人工主张

Status: accepted

Related: Dimon94/pagugu#4、Dimon94/pagugu#2、repo://docs/adr/0001-skill-identity.md、repo://CONTEXT.md

## Context

MVP 1.0 中，复制投影自身不带来源信息，需要人工来源映射获得身份。已锁定的事实锚点：Skill Identity =（Skill Source Key，仓内相对路径）；软链接完全解析归因、复制不做启发式自动归因（ADR-0001）；扫描保留 as-found 路径与 Canonical Path，归因与去重使用 Canonical Path（Dimon94/pagugu#3）；App Registry 不回写身份或状态，Skill Read Model 只读派生。映射一旦进入 App Registry 持久数据，其键与生命周期语义即成为难回退合同。

## Decision

### 1. 人工映射只对 Unattributed Installation 开放

软链接与仓库本体的归因是文件系统事实，每次扫描即时推导，不接受人工覆盖。不认同自动归因的修复动作在文件系统层（改软链接、移目录），不在 Pagugu 内写与磁盘矛盾的记录。被否决：人工映射可覆盖自动归因——App Registry 会成为身份的第二真相，覆盖与磁盘事实冲突时没有裁决依据，违反来源优先与操作克制。

### 2. 映射键：Installation Canonical Path → Skill Identity

一条映射绑定一个 Skill Installation 的 Canonical Path 到一个 Skill Identity（Skill Source Key + 仓内相对路径）。一个 Installation 至多一条映射；多条 Installation 可映射到同一 Skill。被否决：只绑定 Skill Source 不指定仓内路径——一个 Source 可含多个 Skill，身份只能由内容猜，退化为已否决的启发式。被否决：按父目录批量映射——批量是 UI 组合，不改变逐 Installation 的合同。

### 3. 映射目标必须是当前已发现的 Skill

建立映射只允许选择当前 Scan Result 中已发现的 Skill（Skill Source 已发现且仓内相对路径存在），不允许自由输入 URL 或路径。想映射未发现的来源，先把目录加入 Project Scan Root。被否决：自由输入——产生不可验证的记录；Eligible Update 的目标必须是已发现工作树，不可核实来源永远无法安全更新。

### 4. 建立时只校验目标身份存在

frontmatter `name` 与目标不匹配时给非阻断提示，不比较文件内容。被否决：`name` 不匹配即阻断——`name` 是可变的展示元数据，不参与身份（ADR-0001）。被否决：内容哈希或相似度校验——已否决的启发式路线的回潮。

### 5. 当前事实优先，映射是每次扫描重验证的主张

文件系统与 Git 的当前事实永远优先于 App Registry；映射是对事实的主张，每次 Discovery Scan 重验证。自动归因不落盘，App Registry 只拥有人工映射记录。被否决：Registry 映射优先、按记录推断事实——持久记录反噬磁盘真相，扫描层无法再充当事实源。

### 6. 失效触发器仅三条，且只在完整 Scan Result 下判定

映射在且仅在以下事实不再成立时失效：Installation 不再作为复制投影的 Skill Installation 被发现（路径消失、`SKILL.md` 缺失或不可解析、被替换为软链接或仓库本体）；目标 Skill Source Key 不再被发现（Source 删除、移出全部 Scan Root、无远程 Source 移动、origin URL 变更）；目标 Skill 的仓内相对路径在 Source 中不存在。失效判定只在完整 Scan Result 下进行，部分或失败结果不得触发失效（沿用 #3 的裁决护栏）。

### 7. 失效不静默删除，事实恢复自动复活

失效后 Installation 回到 Unattributed Installation，映射记录保留并呈现原因。有效/失效是完全派生状态：依赖事实重新成立时映射自动复活，无人工确认中间态。映射只能由用户显式删除。被否决：失效后自动删除记录——静默丢弃用户数据，移动-移回场景会反复丢失映射。被否决：「待确认」中间态——引入第二台状态机与需持久化的确认位，与只读派生原则冲突。

### 8. 删除只动记录，重新映射 = 删除 + 新建

删除映射只移除 App Registry 记录，不动 Skill 内容与 Installation 内容；Installation 仍在且无法自动归因时回到 Unattributed Installation。不引入独立的「改绑」原语，MVP 1.0 不保存映射历史。被否决：改绑原语与映射历史——删除加新建已覆盖全部场景；审计证据归地图 Not yet specified，非本票。

### 9. 无远程 Skill Source 移动目录不做自动身份连续性

无远程 Source 的键是 canonical 绝对路径，移动即换键：旧条目消失、新条目出现，指向旧路径的映射按第 6 节失效并呈现「来源目录不存在或已移动」，由人工重新映射。有远程的 Source 移动目录不受影响：键是规范化远程 URL，身份自动连续。被否决：用 Git 证据自动重连——与「复制不做哈希/相似度自动归因」同一理由，启发式错认违反来源优先，错连会把更新写错仓库。被否决：MVP 1.0 内置「建议候选」提示——提示本身依赖身份级启发式，留作 MVP 后增强。

## Consequences

### 正面

- 映射合同不产生第二真相：自动归因来自磁盘，人工映射是每次扫描重验证的主张，Skill Read Model 继续只读派生。
- 失效面收窄到三条可验证触发器，部分或失败扫描不会制造假失效。
- 移动-移回、Scan Root 增删等常见操作不丢用户数据：记录保留、自动复活。
- 同名异源不阻断、更新只写 Skill Source 工作树等 ADR-0001 锚点保持不动。

### 负面 / 成本

- 无远程 Source 移动目录后，用户需承担人工重新映射成本；MVP 1.0 没有建议候选提示。
- 失效映射长期保留，需要界面呈现失效原因与删除动作（呈现归 Dimon94/pagugu#5）。
- 映射到未发现来源必须先把目录加入 Project Scan Root，多一步显式动作。

### 边界

本 ADR 冻结来源映射的作用域、映射键、建立校验、事实优先级、失效/复活/删除语义与无远程 Skill Source 的身份连续性。不裁决：App Registry 的持久 schema、迁移与原子写入（归 Dimon94/pagugu#8）；同一 Skill Source Key 的多 clone/worktree 与 canonical 更新目标（归 Dimon94/pagugu#12）；失效在 Skill 状态枚举与详情字段中的呈现（归 Dimon94/pagugu#5）；映射历史与审计证据（归地图 Not yet specified）。若 MVP 后引入启发式自动归因或自动身份连续性，需立新 ADR supersede 本记录的第 4、9 节。
