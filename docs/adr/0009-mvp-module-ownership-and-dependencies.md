# MVP 1.0 模块所有权与依赖方向

Status: accepted

Related: Dimon94/pagugu#9、Dimon94/pagugu#10、repo://docs/adr/0001-skill-identity.md、repo://docs/adr/0002-skill-source-mapping.md、repo://docs/adr/0003-skill-source-checkout-update-target.md、repo://docs/adr/0004-checkout-git-state-and-eligible-update.md、repo://docs/adr/0005-check-run-and-checkout-observation.md、repo://docs/adr/0006-update-run-execution-and-recovery.md、repo://docs/adr/0007-audit-evidence-and-recovery-presentation.md、repo://docs/adr/0008-app-registry-persistence-contract.md、repo://CONTEXT.md、repo://docs/agents/architecture-standards.md

## Context

MVP 1.0 需要把 ADR-0001 至 0008 冻结的领域合同落成模块结构：哪些模块分别拥有发现、身份归因、Git 事实与执行、状态裁决、检查与更新编排、持久状态、审计与 UI 投影；公开 interface、依赖方向、外部 seam、并发隔离与测试面如何划分。已锁定的事实锚点：全部状态 owner 与第二真相禁区（ADR-0001 至 0008）；一个物理持久 owner 服务 Registry/Audit 两个语义 owner、审计窄 append 入口 fail-open（ADR-0007 §8、ADR-0008 §18）；Check Run 与 Update Run 瞬态不持久（ADR-0005 §1、ADR-0006 §1）；三层单向真相链（ADR-0004 §1）；检查/更新互斥粒度为 App 级单一互斥（ADR-0005 §9、ADR-0006 §7）；当前基线是单 Xcode app target（Pagugu/App、Support、Views），无 Services 层、无持久化代码。模块边界将被 #10 原型与后续实现票并行消费，改向成本高。

## Decision

### 1. 拆分判据

按稳定状态唯一 owner、纯逻辑边界与副作用 seam 三条切分；不按页面、文件类型或未来扩展点切分。每个模块必须回答 owns / does not own / public interface / dependencies / output / verification 六问并通过 deletion test（repo://docs/agents/architecture-standards.md §4、§5）。被否决：按层机械拆（每函数一 interface）——architecture-standards §10 明确拒绝；被否决：预合并成少数大模块——无法通过 deletion test，状态 owner 不再唯一。

### 2. 九模块清单

| 模块 | owns | does not own |
| --- | --- | --- |
| Discovery | Discovery Scan：遍历 Scan Root、软链接解析、Canonical Path 去重防环、深度保险、denylist、SKILL.md 解析校验、Scan Issue、候选检出根探测（`.git` 存在性） | 身份、归因、聚合、Git 子进程 |
| Identity | Skill Identity、Skill Source Key 规范化、去重聚合、软链接/仓库本体/人工映射归因、Agent Host 归因表、映射有效/失效派生（全部纯函数） | 文件系统遍历、Git 调用、任何副作用 |
| Git | 唯一 Git 子进程 seam：`GitInspecting` 与 `GitExecuting` 两个公开 protocol；内部唯一命令 runner（非交互环境、timeout、hook 屏蔽、exit/stderr 归一化各实现一次） | Checkout Git State 裁决、Eligible 判断、业务状态 |
| Eligibility | Checkout Git State 12 态裁决与 precedence、Eligible Update L0–L4 gate、observation freshness 派生、reason code 与恢复方向文案（全部纯函数） | Git 调用、持久化、UI |
| Runs | Check Run 与 Update Run 编排：scope 冻结快照、本地可判阻断态跳过、逐项发布、重查时序、post-verify、失败九类映射、审计写入点调用、退出时子进程终止 | 裁决规则、观察槽持久语义、第二把互斥锁 |
| Registry（语义） | 三类主张的规则：Scan Root 护栏校验、来源映射 CRUD 语义、观察槽生命周期（单槽、失败覆盖成功、槽保留） | 物理 IO、文件布局 |
| Audit（语义） | 审计记录形状、唯一窄 append 入口、UI 读面、清空语义、写入/读取 fail-open 包装 | 物理 IO、裁决与 freshness |
| Persistence（物理） | registry.json 与 audit-history.json 全部物理 IO：单写者 actor 串行、原子写双 fsync、quarantine、七情形兼容矩阵、迁移纯函数、外部修改检测、FIFO 200 淘汰；owns 全部持久记录类型 | 主张语义、记录语义、业务规则 |
| AppModel | @MainActor composition root：Skill Read Model 只读投影、全部 UI intent 唯一入口、启动与刷新流水线编排、受限恢复模式态 | 直接 Git/文件系统/持久 IO、业务规则重建 |

### 3. 扫描与归因分离

Discovery 只产事实：as-found 路径、Canonical Path、是否软链接、frontmatter 校验结果、Scan Issue、候选检出根。Identity 以纯函数消费 Scan Result + Registry 主张 + Git Fact，完成归因、去重聚合与映射有效性派生；检出归属用 Canonical Path 包含关系纯计算，Identity 不碰磁盘、不重解析 SKILL.md。被否决：合并为一个「发现与归因」模块——扫描是副作用 seam、归因是纯逻辑，变化原因不同，且两个模块各自递归文件系统是明确禁止的失败模式。

### 4. Git 单模块双公开面

`GitInspecting`（只读：worktree 解析、remote URL、branch/upstream、严格 dirty 口径、ahead/behind、worktree list 与 sibling 检测、identity digest 原材料）与 `GitExecuting`（fetch 单分支、ff-only 精确 SHA、terminateInFlight）两个 protocol；生产 adapter 一个类型实现两者、共享内部 runner；内存 fake 供编排层测试（外部协议隔离已证明 seam 成立，双 adapter 不触发假想 seam 禁令）。Git 产出原始 remote URL；规范化为 Skill Source Key 归 Identity 纯函数；Git 永不 import Identity，identity digest 组装在调用方（AppModel/Runs）完成。被否决：Inspector/Executor 拆两模块——runner、非交互环境与 hook 屏蔽必须只实现一次，拆分迫使共享件下沉为第三个内部模块或复制。

### 5. Runs 单一编排 owner 与两段式更新接口

Check Run 与 Update Run 同归 Runs：两者共享 scope 冻结、身份重查、逐项发布、审计写入点与互斥语义。Update 公开面两段式：`prepareUpdate` 执行 ADR-0006 §2 的 fetch + 重读重裁决，产出绑定精确 target SHA 的 UpdatePlan（含 §4 确认事实清单），重查非 update-available 时返回阻断态而非计划；`executeConfirmed(plan)` 执行 §2 的漂移比对、ff-only 与 post-verify，返回 AsyncStream 事件；取消 = 不调用 execute，无暂停状态、无超时自动执行。Check 公开面：`startCheck(scope:)` 返回 AsyncStream 逐项事件。互斥真相只在 AppModel 主 actor（run 进行中 intent 禁用 + Runs 入口 guard），Runs 为非隔离 final class、不持第二把锁。被否决：Check/Update 拆两模块——互斥合同横跨两者（ADR-0005 §9、ADR-0006 §7），拆分制造第二个锁真相；被否决：单流暂停式更新接口——跨 actor 续传状态机复杂度不抵收益，两段式让「确认绑定重查快照」由 plan 值类型直接表达。

### 6. 持久三层：一个物理 owner + 两个语义 owner

Persistence 是 actor，编译器承担 ADR-0008 §11 单写者串行；目录路径构造注入（测试指向 temp 目录）。Registry 与 Audit 是语义模块：owns 规则与生命周期，调用 Persistence 唯一物理写路径。全部持久记录类型（ScanRootRecord、SourceMappingRecord、CheckoutObservation、AuditRecord、Registry/Audit Document 与 schemaVersion）归 Persistence owns——字段全是值语义（路径、规范化 key、SHA、时间戳、稳定 code 字符串），不引用业务模块类型，依赖保持 Registry→Persistence、Audit→Persistence 单向。被否决：DTO 分离（语义类型归语义模块、Persistence 只见 DTO）——MVP 下映射层是纯转发 Middle Man，schema 演进需双处同步；被否决：三层并一——Scan Root 护栏、观察槽规则与审计 fail-open 姿态会散进 UI 与 Runs，不过 deletion test。

### 7. AppModel 单一 composition root

AppModel @MainActor：拥有 Skill Read Model 投影，暴露全部 intent（rescan、addScanRoot、removeScanRoot、createMapping、deleteMapping、checkNow、prepareUpdate、confirmUpdate、cancelUpdate、clearAudit、resetRegistry），编排启动与刷新流水线。SwiftUI View 只渲染投影、只发 intent，永不直接调用 Git、文件系统或持久层。被否决：独立 Pipeline/Orchestrator 模块——MVP 流水线是固定直线调用，独立层删除后只少一层命名转发。

### 8. 依赖方向与反向禁令

```text
Views ─▶ AppModel ─▶ Runs ─▶ Git, Eligibility, Registry, Audit
                ─▶ Discovery, Identity, Eligibility, Registry, Audit
Identity ─▶（仅类型）Discovery, Git, Registry
Eligibility ─▶（仅类型）Git, Identity, Registry
Registry ─▶ Persistence
Audit ─▶ Persistence
Discovery / Git / Persistence ─▶ 仅 Foundation
```

反向禁令：Git、Discovery、Persistence 不 import 任何业务模块；Identity、Eligibility 不发起任何副作用（无文件、无子进程、无 IO）；低层不回调高层——Runs 的结果经返回值与 AsyncStream 由 AppModel 消费，更新成功后的完整重扫由 AppModel 编排（ADR-0006 §12），Runs 不知道 Discovery 存在。

### 9. 值类型归生产者

跨模块值类型各由生产它的模块 owns 并导出：Scan Result←Discovery；Skill Identity、Skill Source Key、Skill Source Checkout←Identity；CheckoutGitFacts←Git；CheckoutGitState、Eligible Update、UpdatePlan←Eligibility/Runs 各自产出面；CheckoutObservation、ScanRootRecord、SourceMappingRecord、AuditRecord、两个 Document←Persistence（§6）；Audit 记录内容由调用方定型传入（ADR-0007 §8）。消费方直接使用，不设共享 Types 模块——共享类型桶把所有模块耦合到一个共同依赖，且类型语义本属生产者合同。

### 10. 并发模型

AppModel 与全部 UI 状态 @MainActor；Persistence 为 actor；Git runner 非隔离（Process 子进程），调用方以结构化并发调度；Check Run 逐检出顺序执行——fetch 秒级且逐项发布已保证 UI 渐进刷新，并行留 MVP 后；不引入 clock seam——全部合同无 TTL（ADR-0005 §7），时间戳只在写入时捕获、仅作展示（coding-standards §9：时间只在成为可观察输入时注入）；禁 `nonisolated(unsafe)` 与 `@unchecked Sendable`。被否决：Check Run 并行 fetch——组合进度与错误归因复杂度不抵 MVP 收益。

### 11. 错误归一化与 reason code owner

错误在各 seam 边界一次归一化为 typed error：Discovery→Scan Issue 与根级错误；Git→typed 原语（非零退出含 stderr、timeout、启动失败），由 Runs 映射为 ADR-0006 §9 失败九类；Persistence→typed（corrupt、unknownFutureVersion、externallyModified、writeFailed）。稳定 reason code 归各语义 owner：12 态←Eligibility；失败九类与检查聚合三态←Runs；审计 outcome 复用既有集合不新造（ADR-0007 §4）。code→中文显示名与恢复方向文案的映射由 Eligibility/Runs 合同单一持有，呈现时按 code 取当前文案。UI 只消费 code 与投影，永不解析错误字符串；日志只作证。被否决：全局错误枚举或错误模块——全部模块反向依赖一个低层类型桶，违反错误在 owner module 形成稳定语义（coding-standards §6）。

### 12. 目录落点：单 app target + 每模块文件夹

```text
Pagugu/
  App/          PaguguApp、AppDelegate（现有）
  Views/        SwiftUI（现有）
  Support/      AppIdentity（现有）
  AppModel/     composition root、Read Model、intents
  Discovery/    扫描
  Identity/     身份、归因、聚合（纯）
  Git/          runner、Inspecting/Executing、Process adapter
  Eligibility/  裁决、freshness、reason code（纯）
  Runs/         Check/Update 编排
  Registry/     主张语义
  Audit/        审计语义
  Persistence/  actor、schema、原子写、quarantine
PaguguTests/    按模块分测试文件
```

被否决：Swift Package 编译器强制边界——无第二消费方与跨仓复用，只增构建与迭代摩擦；边界由本 ADR、实现期 L2 AGENTS.md 与 review 承载，未来约定守不住时再拆（纯目录移动）。本票只冻结清单，不创建空文件夹；实现票各自落地并补 L2。

### 13. 启动与刷新时序

`AppModel.start()` 固定序列：① Persistence 载 Registry，七情形分发（ADR-0008 §7）——损坏与未知未来版本进入阻断式受限恢复模式，业务 intent 全禁用；② 载 Audit，损坏即投影标注「历史不可用」fail-open 继续；③ Discovery 全量扫描；④ Git 逐检出 inspection（顺序）；⑤ Identity 归因聚合；⑥ Eligibility 裁决 + freshness 派生；⑦ 发布 Skill Read Model。故障隔离：扫描部分/失败→投影如实呈现 + L0 gate 禁用检查与更新 intent；单检出 inspection 失败→该检出 inspection-failed，不扩散。刷新入口恰好四个：启动、更新成功后（ADR-0006 §12）、Scan Root/映射变更后、手动 rescan。无定时器、无后台调度；freshness 实时派生发生在每次投影重组。

### 14. 测试金字塔与确定性

六层：纯 domain 表测试（身份/归因/映射有效性、12 态 precedence 真值表、L0–L4 gate、freshness）；文件系统 scratch 测试（软链接成环去重、深度保险记 Scan Issue 不静默截断）；Git scratch 仓库测试（sibling 冲突检出、hook 屏蔽断言、非交互认证失败不挂起）——真实 git + `file://` remote，零网络，不可 mock；Persistence 测试（七情形矩阵、外部修改检测 fail closed、损坏 quarantine、原子写无撕裂、FIFO 200）——构造注入 temp 目录，永不触碰真实 `~/Library`；Update Run 集成测试（scratch repo 端到端：成功 ff、noop、lock-busy）；SwiftUI smoke（启动、投影渲染、intent 路由存在）。编排层单测用 Git seam 内存 fake。每个模块至少一个「错误实现会失败」的检查，逐模块映射在实现票按 Q19 等价清单落地。

### 15. 对 #10 的输出边界

Read models：Skill 列表条目（Skill Identity、Installations + Agent Host 集合、逐检出 Checkout Git State + reason code + 恢复方向 + 观察完成时间）、Scan Issue 列表、Unattributed Installation 列表、失效映射 + 失效原因、最近活动（含孤儿「结果未知」）、run 进行瞬态、受限恢复模式态、UpdatePlan 确认事实清单（ADR-0006 §4 全字段）。Intents：§7 清单。Reasons：12 态 code、失败九类、检查聚合三态、审计 outcome，稳定英文 code + 中文显示名 + 一句恢复方向。不定义布局、组件、颜色与图标；#10 原型与本票的呈现语义冲突由 #11 验收合同协调。

## Consequences

### 正面

- ADR-0001 至 0008 的每条输出边界都有唯一模块坐标；状态 owner 在模块层无一重复。
- 纯逻辑（Identity、Eligibility）与副作用（Discovery、Git、Persistence）完全分离：表测试与 scratch 测试各自确定，编排层可用 fake。
- 单一互斥真相（AppModel 主 actor）、无 clock seam、无全局错误桶：并发与错误语义各只有一个 owner。
- #10 与实现票的接缝收窄为 §15 三面清单与 §2 owns 表。

### 负面 / 成本

- 九模块对 MVP 偏多；文件夹边界无编译器强制，纪律靠本 ADR、L2 合同与 review 维持。
- 顺序 Check Run 在安装基数大时总时长线性增长；并行化需立新决策。
- 持久记录类型归物理层：语义规则与类型分放两处，读代码需跨 Registry/Audit 与 Persistence 两个文件夹。

### 边界

本 ADR 冻结模块清单与 owns 边界、四个 contested 接缝选择、依赖方向与反向禁令、值类型归属、接口形状、并发隔离、错误归属、目录落点、启动时序、测试面与对 #10 输出。不裁决：模块内实现细节与精确类型签名（归实现票）；UI 布局、交互与文案排版（归 #10）；每日检查、批量更新等地图 Out of scope 项。实现票落地时更新 System Map 模块表（L1）与各模块 L2 AGENTS.md，System Map 在实现前不预写规划态。若未来拆 Swift Package、Check Run 并行化、合并或拆分模块、引入 clock seam 或改变互斥姿态，需立新 ADR supersede 本记录相应小节。
