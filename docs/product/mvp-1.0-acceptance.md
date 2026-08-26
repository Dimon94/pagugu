# MVP 1.0 验收合同与实现交接边界

Status: frozen（Dimon94/pagugu#11 HITL 冻结，2026-08-24）

本文是 MVP 1.0「单机安全更新闭环」的外部可观察验收合同与实现规划交接物。领域语义与产品不变量的 canonical owner 是 repo://CONTEXT.md、repo://docs/product/vision.md、repo://docs/architecture/current-system-map.md 与 repo://docs/adr/0001 至 0009；本文不复制其条文，只冻结验收边界并指回锚点。主窗口原型裁决见 repo://Pagugu/Prototype/DECISION.md（throwaway planning evidence，不得晋升生产）。

## 1. 验收场景（外部可观察）

**S1 首次启动与扫描范围**：空 Registry 为正常态，右侧详情区显示欢迎引导与「添加 Project Scan Root」；三个 Personal Skill Root 已自动发现并列出（root 不存在为正常空态）。添加 Project Scan Root 后，其内发现的 Skill（含无 Installation 的纯来源 Skill）进入目录；非法选择（文件系统根、Home、Personal Skill Root 本身及其祖先）保存时被拒并给出原因。

**S2 发现与关系**：目录显示仓库条目（含子 Skill 行）与无仓库 Skill 行；宿主 logo 点亮/灰显与安装事实一致；同名异源按仓库行天然区分。

**S3 状态收敛**：12 个 Checkout Git State 在检出层逐条呈现，主状态 + 一句人工恢复方向；目录行短语如实并列组合状态（如「1 个可更新 · 1 个需处理」），无聚合假状态；目录按行动优先级静默排序（需要处理 → 可更新 → 尚未检查 → 无需更新 → 仅本地），同档按最严重检出态，无分组标题、无筛选 UI；历史证据不覆盖当前状态。

**S4 手动检查闭环**：检查更新 → 进度态「检查中 x/y」→ 逐项发布 → 完成/部分完成横幅 + 审计记录；本地可判阻断态跳过网络检查、标注「不适用」且不计入成败；失败项回「尚未检查」并给原因；部分/失败扫描时如实呈现 Scan Issue 与受影响范围，检查与更新入口禁用并解释（恢复动作 = 重新扫描或处理 Scan Issue）；run 进行中检查与更新动作均禁用并解释；重启后无「检查中」残留态，上次观察按 freshness 合同实时重推导——有效即正常显示状态与观察时间、可直接驱动更新入口，无效回「尚未检查」。

**S5 安全更新成功**：更新… → fetch 重查 → 确认计划（Skill Identity、目标检出路径、branch/upstream、当前 HEAD → 精确 target SHA、behind 数、影响范围声明、「同一仓库的 N 个 Skill 将一起前进」名单；双 Eligible 检出在确认页当次选择一个、不持久化）→ 确认 → 成功横幅、状态变最新、审计开始 + 终态两段记录；成功后触发完整 Discovery Scan 刷新，刷新失败独立于更新结果呈现、绝不回滚。

**S6 noop**：重查时已最新 → 不弹确认，横幅告知。

**S7 取消**：确认页取消 → 即使旧 Checkout Observation 仍满足 freshness，检出也回「尚未检查」；横幅说明需重新检查才能恢复 + 审计 cancelled 记录。

**S8 失败恢复**：失败弹窗 = 失败类中文名 + 一句人工恢复方向；零自动重试、零自动回滚；tip-changed 提示重新发起即可。

**S9 来源映射**：来源不明行 → 指定来源（可筛选、按来源分组的 Skill 列表；无已发现 Skill 时引导先添加 Project Scan Root）→ 成功后该行获得身份并移出无仓库行；失效映射呈现原因、保留、显式删除（确认对话框）；来源移回自动复活。

**S10 Registry 五语义**：空 Registry 正常；Scan Root 不可用为派生态（记录保留、可删除、恢复自动复活）；写失败 fail closed 横幅（动作失败、磁盘 last-good 完好、给恢复指引）；损坏/未来版本受限恢复模式（quarantine 路径 + 重置为空 / 退出自行修复，未来版本附加升级指引）；重置与清空审计均有显式确认与影响范围声明。

**S11 审计呈现**：最近活动列表 / 单条详情（「当时记录」标注、reason 中文名 + 一句恢复方向；失败详情无原始 stderr、无命令复制、无一键重试，只导航到相关 Skill）/ 清空确认；孤儿 Update start 显示「结果未知（已中断）」；审计集合损坏 fail-open——丢弃重建、呈现「历史不可用」、不阻断任何功能，审计写失败不阻断动作本身（与 S10 的 Registry fail closed 形成用户可观察对照）。

**S12 MenuBarExtra**：只打开主窗口与退出，不承载工作流。

## 2. 主窗口呈现合同（Variant F IA 语义）

冻结（外部可观察 IA 语义）：

- 主从结构：左侧目录，右侧详情。
- 目录条目 = 来源仓库行（可收起/展开子 Skill 行，默认展开，chevron 独立热区）；无仓库可归的 Skill（来源不明的复制安装）以 Skill 本身为行，内容完全一致的多个复制安装聚合为一个只读来源不明条目（聚合全部安装位置与宿主槽位），内容不同或读取不完整时各自单列。仓库行是呈现分组；身份与去重的 canonical 条目仍是 Skill（ADR-0001 §3 不动），更新单位是物理检出（ADR-0003 不动）。
- 平铺目录，无分组标题；静默五档排序与同档最严重检出态优先（见 S3）。
- 行状态 = 检出状态，逐条如实并列，无聚合假状态；动作可用性永远按检出层真实资格。
- Skill 详情六块：状态与检出（逐检出卡片：状态 + 上次观察时间 + 恢复方向 + 更新按钮）、安装位置（路径 + 宿主 + 投影/归因）、来源标识、SKILL.md 原文（只读、可选中）、相关记录、更新动作。
- 宿主 logo 槽位：目录行与详情均显示 Claude / Codex 槽位，点亮 = 该平台已安装，灰显 = 未安装；前期只实现这两个槽位，视觉资源归实现期。
- 次要对象（最近活动、扫描范围）收进工具栏（带文字标签）；首次启动引导在右侧详情区；Registry 故障全窗口阻断接管（ADR-0008 §19）。
- 结果反馈统一进结果区：信息/警示分级、可关闭；覆盖成功、noop、取消后果、写失败、刷新失败、检查总结六类。
- 按钮与禁用：动作按钮文案去 SHA 化；禁用统一给出原因（受限恢复 / 部分扫描 / run 互斥）；sheet 必须有显式关闭；破坏性次要动作（删除失效映射、清空历史）降次要位置 + 确认对话框。
- 映射 sheet = 可筛选、按来源分组的 Skill 列表；无已发现 Skill 时引导先添加 Project Scan Root。

不冻结（实现期可逆细节）：

- SwiftUI 内部结构、组件拆分、stub 类型与原型代码组织。
- 样式数值：间距、圆角、阴影、颜色具体值、暗色模式精确取值。
- 结果区最终形态与位置（顶部通栏 vs toast vs inline）。
- 真实数据规模下的密度与截断策略。
- 宿主 logo 的视觉资源（官方 logo / 占位图形 / 文字标签）。
- `Pagugu/Prototype/**` 全部为 throwaway planning evidence，不得直接晋升生产。

## 3. 安全不变量（引用）

实现必须保持的不变量以 repo://docs/architecture/current-system-map.md「产品不变量」与下列 accepted ADR 为 canonical owner，本合同不复制条文：

- ADR-0001 身份与归因：更新只写 Skill Source 工作树；同名异源不阻断；Unattributed Installation 阻断。
- ADR-0002 来源映射：事实优先、每次完整扫描重验证、失效保留、自动复活。
- ADR-0003 多检出与单一更新目标：一次更新只写一个明确选定的工作树；副作用边界只 fetch + ff-only。
- ADR-0004 状态裁决与 Eligible 充要条件：严格 dirty、upstream 身份校验、sibling-conflict fail closed、12 态 precedence。
- ADR-0005 检查与观察：全量单一口径、只 fetch、freshness 完全派生无 TTL、观察永不充当执行许可。
- ADR-0006 更新执行：重查 → 确认精确 SHA → ff-only → post-verify；失败九类；零自动重试、零自动回滚；非交互执行与 hook 屏蔽。
- ADR-0007 审计证据：append-only；永不充当当前状态、执行许可或自动恢复依据。
- ADR-0008 持久合同：Registry fail closed / 审计 fail-open 严格分离；原子写；quarantine。
- ADR-0009 模块所有权与依赖方向：九模块 owns 边界、单向依赖、测试面。

## 4. 明确非目标

map #1 Out of scope（冻结时点）：托管插件来源；多机或云端同步；自动推送 Skill Source；每日后台检查、系统通知和完整状态栏工作流；批量更新；Logo 完稿、签名、公证和发布；复制投影的哈希/相似度启发式自动归因；单检出/局部检查与失败项单独重试；审计证据的完整时间线页、导出、全文搜索、过滤、通知与遥测。

本票新增：

- 主窗口筛选 UI：MVP 1.0 无筛选器；宿主可见性由宿主 logo 槽位与静默排序承担；MVP 后按需重开。
- 辅助功能审计（VoiceOver、键盘导航完整性）与多语言本地化：归 MVP 后。MVP 1.0 UI 语言为简体中文；不主动破坏 SwiftUI 原生默认可及性。

## 5. 实现规划输入

- 可验证入口：`repo://script/build_and_run.sh --verify`；`xcodebuild test`（参数见 repo://docs/architecture/current-system-map.md「验证」节）。
- 测试面参照：ADR-0009 §14 六层测试金字塔（纯 domain 表测试、文件系统 scratch、Git scratch 仓库零网络、Persistence temp 目录、Update Run 集成、SwiftUI smoke）。
- Artifact pointers：repo://CONTEXT.md；repo://docs/product/vision.md；repo://docs/architecture/current-system-map.md；repo://docs/adr/0001 至 0009；repo://Pagugu/Prototype/DECISION.md 与 repo://Pagugu/Prototype/README.md（throwaway，不得晋升生产）。
- 实现期可逆细节清单：见第 2 节「不冻结」。
- 本合同明确不含：模块私有接口与类型签名、实现步骤、implementation tickets 拆分（归后续 spec/tickets 阶段）。

## 6. Unknown 处置表

| 原型遗留 Unknown | 处置 |
| --- | --- |
| Skill 级聚合状态公开合同 | 本票冻结（S3 与第 2 节）：不引入聚合状态枚举；如实并列；静默五档排序；动作按检出真实资格。 |
| 首次启动引导是否需独立决策票 | 不需要：S1 即冻结边界；更丰富的 onboarding 归 MVP 后增强。 |
| 结果横幅最终形态与位置 | 实现期可逆细节；语义已冻结（第 2 节结果区六类覆盖）。 |
| 宿主 logo 真实资源与商标合规 | 视觉资源归实现期；商标合规随「发布」留在 map Out of scope。 |
| 暗色模式精确取值 | 实现期可逆细节；要求明暗两态状态可辨。 |
| 真实数据规模下的密度与截断策略 | 实现期可逆细节。 |
| 辅助功能与本地化 | 明确非目标（第 4 节）。 |

CONTEXT.md 其余 Unknown（托管插件首批支持范围、签名/公证/发布流程、专业商标可用性、各 Agent Host 精确加载规则）不在本票边界内，保持 Unknown。

## PROTOCOL

本合同冻结后，变更验收场景、呈现合同、非目标或实现规划输入范围时，更新本文并在 Dimon94/pagugu#1 的 Decisions so far 同步 gist。领域语义变化先更新 canonical owner（CONTEXT.md / vision.md / System Map / ADR），本合同只指回不复制。
