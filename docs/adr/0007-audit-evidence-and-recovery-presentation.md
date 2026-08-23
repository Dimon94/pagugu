# 审计证据是只回答用户动作与结果的 append-only 历史

Status: accepted

Related: Dimon94/pagugu#13、Dimon94/pagugu#8、Dimon94/pagugu#9、Dimon94/pagugu#10、repo://docs/adr/0001-skill-identity.md、repo://docs/adr/0002-skill-source-mapping.md、repo://docs/adr/0004-checkout-git-state-and-eligible-update.md、repo://docs/adr/0005-check-run-and-checkout-observation.md、repo://docs/adr/0006-update-run-execution-and-recovery.md、repo://CONTEXT.md

## Context

MVP 1.0 需要为用户保留最小运行证据，支撑「我做过什么、结果是什么、下一步怎么办」的可追溯与故障恢复呈现。已锁定的事实锚点：Check Run 与 Update Run 均瞬态不持久（ADR-0005 §1、ADR-0006 §1）；Checkout Observation 只持久逐检出单槽上次观察（ADR-0005 §10）；三层单向真相链禁止任何持久物充当 Git 事实（ADR-0004 §1）；来源映射是每次完整扫描重验证的人工主张，失效与复活完全派生（ADR-0002 §5、§7）；检查聚合三态与更新失败九类已稳定（ADR-0005 §6、ADR-0006 §9）；ADR-0002 §8 与 ADR-0006 §13 将映射历史与审计证据指向本票。审计记录一旦持久化并被界面消费，其范围、粒度与留存语义即成为 #8 持久合同与 #10 呈现合同的地基，改向成本高。

## Decision

### 1. 定位与术语

审计证据（Audit Evidence）是 Pagugu 保留的最小历史证据整体；审计记录（Audit Record）是其中单条。它只回答三类用户问题：我做过什么、结果是什么、下一步怎么办。它永不充当当前 Git 状态、Eligible Update、Checkout Observation freshness、执行许可、当前运行态、自动恢复、自动重试或回滚的依据。被否决：把审计当作运行日志或恢复队列——历史证据一旦参与裁决即成为第二真相入口，违反三层单向真相链（ADR-0004 §1）。

### 2. 记录范围

进入记录的用户发起动作只有三类：Update Run（单次更新尝试）、Check Run（单次全量检查）、人工来源映射的创建与显式删除。明确不记录：Discovery Scan（纯读高频动作）、UI 浏览与筛选、自动归因结果，以及全部派生状态变化——含映射失效/复活、观察 freshness 失效、Checkout Git State 迁移。判据：只记用户发起且改变或尝试改变现实的动作；能由实时事实重算的一律不进。被否决：记录映射失效/复活——失效原因是当前状态呈现（每次完整扫描重算、实时可见），写进历史即制造映射状态的第二真相；被否决：记录扫描——每次启动与刷新都发生，只产噪音。

### 3. 事件形状

Check Run 与映射动作为 terminal-only：动作终态写一条记录。Update Run 为两段式：确认绑定时刻写开始记录（内容即 ADR-0006 §4 确认事实清单的执行计划快照），terminal 时刻再写一条；两条 append-only，以唯一 run 标识关联。确认前被重查阻断是 terminal-only failed 记录；确认弹窗取消是 terminal-only cancelled 记录（带计划快照）；确认后无取消路径。只有开始没有 terminal 的孤儿记录呈现为「结果未知（已中断）」，复用 interrupted-unknown 语义：永不解释为正在运行，永不驱动续跑、重试或回滚，重启后不随实时状态补完改写。审计写入是 best-effort：写入失败不阻断动作本身。被否决：全部动作 terminal-only——崩溃中的更新尝试在历史中完全消失，恰是最需要证据的失败场景。被否决：点击更新即写开始——开始记录的语义定为「用户已确认的执行计划」，重查阻断与取消不应产生孤儿。被否决：持久 run 状态机——两段记录只服务呈现，不构成运行态。

### 4. outcome 与 reason 合同

审计记录只引用既有稳定集合，不造同义状态或平行分类：Check Run terminal outcome = complete / partial / failed（ADR-0005 §6）；Update Run terminal outcome = success / cancelled / failed，failed 的 reason 只用 ADR-0006 §9 九类（lock-busy、identity-changed、fetch-failure、precondition-changed、tip-changed、ff-rejected、command-failure、verification-failed、interrupted-unknown），noop 作为 success 附注而非独立 outcome；映射动作 = created / deleted，只记实际落盘的变更。记录只存稳定 reason code；恢复方向文案在呈现时按 code 取当前合同——恢复建议是当下建议，不随历史快照腐烂。不存 exit code（reason code 已承载；实测 exit 不区分 fetch 子类，ADR-0006 Context）。新增 cancelled 的理由：取消有已知后果（确认前 fetch 可能使观察失效回 check-unknown，ADR-0006 §2），留痕可解释后续状态变化。被否决：为审计新建状态词表——平行 taxonomy 必然漂移。

### 5. 字段与敏感边界

每条记录自带对象身份快照，历史可独立阅读：Skill Identity（规范化 Skill Source Key + 仓内相对路径）；Update Run 另含 Checkout Canonical Path 与 branch/upstream 名。Check Run 记录存 scope 计数（应检查/成功/失败/跳过），不存失败检出清单——最新失败详情在逐检出观察单槽（当前状态证据，ADR-0005 §10）。Update Run 开始记录存 old HEAD SHA、target SHA、behind 数；terminal 记录存 outcome 与 reason code。统一省略：原始 stdout/stderr（只在当次失败瞬态呈现，ADR-0006 §9 的呈现义务不变）、exit code、环境变量、hostname、secrets、Skill 内容与 frontmatter、恢复方向文案快照。身份快照与路径本地留存、永不上传——与 App Registry 同级姿态，无新增外发面。被否决：落盘原始命令输出——内容不稳定且可能携带敏感信息，长期证据只要稳定 code。

### 6. 留存与生命周期

审计记录持久保存，语义上是独立于 App Registry 的 append-only 历史集合：Registry 拥有「当前主张」（Project Scan Root、来源映射、上次观察），审计集合拥有「历史证据」；CONTEXT.md 中 Registry 的 owns 清单不扩大。单条记录写入后永不更新、合并或改写含义。容量有界 FIFO：上限 200 条，超限淘汰最旧；无 TTL（纯时间不是证据，同 ADR-0005 §7 哲学）。用户清空只删审计集合：不动 Registry、Skill Source 或 Git；清空不留墓碑记录。审计集合损坏（不可解析）即丢弃重建为空并呈现「历史不可用」，不阻断任何功能、不尝试修复——历史不是安全关键，fail-open。App 卸载随 Application Support 留存（macOS 删除 .app 不清支持目录），MVP 不提供卸载清理。导出、搜索、过滤与系统级日志镜像推迟到 MVP 后。被否决：TTL——过期时刻与证据价值无关；被否决：损坏修复流程——修复成本高于历史价值，且修复本身可能制造假象。

### 7. 呈现与恢复动作边界

三个 UI 语义面：主窗口「最近活动」摘要板块、单条详情、清空动作。呈现不变量：历史快照标注「当时记录」，与「当前实时状态」明确区分；历史永不覆盖或参与当前裁决呈现。详情内容：动作类型、对象身份快照、时间、outcome、reason 中文显示名与一句恢复方向（按 code 取当前合同文案）；Update Run 另示计划快照；失败详情不提供原始 stderr（瞬态窗口已过；重看原始错误的路径是重新发起动作让失败再现）。不生成、不复制终端命令；不提供「一键重试」按钮——重试是用户从对象当前状态照常重新发起整个动作（幂等可重入，ADR-0006 §10），失败详情只提供导航到相关 Skill。推迟：完整时间线页、导出、全文搜索、过滤、通知、遥测。被否决：命令复制——命令建议是不可验证的副作用暗示且随场景漂移；被否决：独立重试入口——与既有更新入口平行即第二入口。

### 8. 对 #8、#9、#10 的输出边界

对 #8：必须持久 = 审计记录集合（append-only、FIFO 200 条、清空只删历史、损坏丢弃重建、格式演进只增不改、旧记录含义不变）；明确不得持久 = 原始 stdout/stderr、exit code、环境变量、secrets、Skill 内容与 frontmatter、恢复文案快照、失败检出清单、run 聚合态、Checkout Git State、Eligible 结论、任何「进行中」运行态。语义 owner 是审计能力；物理布局、JSON 字段名、schema version、原子写入、迁移与损坏恢复实现全部归 #8。对 #9：审计写入点是唯一窄 append 入口，由 Check Run（terminal 时刻）、Update Run（确认绑定时刻与 terminal 时刻）与映射维护（落盘时刻）调用；读取只服务 UI；依赖方向单向（执行流程 → 写入点），审计不读裁决、Git、扫描的内部状态，只接收调用方传入的已定型记录内容；写入与读取失败 fail-open，不阻断主流程；审计永不回流裁决、freshness、Eligible 或执行许可。对 #10：稳定语义为第 7 节三语义面、呈现不变量、outcome/reason 内容与孤儿呈现；不定义布局、组件、颜色、图标与板块条数。

## Consequences

### 正面

- 崩溃与强退场景有最小证据：孤儿开始呈现「结果未知」，引导人工核验而不伪装运行态。
- 审计在结构上不可能成为第二真相：范围收窄到用户动作，派生状态与原始输出一律不进。
- #8/#9/#10 接缝收窄为最小面：语义清单、单向写入点、呈现不变量。

### 负面 / 成本

- Update Run 多一段开始记录与孤儿派生规则；确认窗口外崩溃无 start（best-effort）。
- 历史不含失败检出清单与原始 stderr：事后诊断依赖当前观察单槽或重新发起动作。
- 200 条 FIFO 会淘汰最旧历史；MVP 无导出手段。

### 边界

本 ADR 冻结审计证据的术语、记录范围、事件形状、outcome/reason 合同、字段与敏感边界、留存与生命周期语义、呈现与恢复动作边界，以及对 #8/#9/#10 的输出。不裁决：App Registry 与审计集合的物理布局、JSON schema、字段名、版本、原子写入、迁移与损坏恢复实现（归 #8）；模块清单、公开 interface 与依赖图（归 #9）；布局、组件、颜色、图标、板块条数与完整交互原型（归 #10）。若未来引入遥测平台、事件溯源、持久 run 状态机、审计参与裁决或执行许可、导出/搜索/系统日志，需立新 ADR supersede 本记录的相应小节。
