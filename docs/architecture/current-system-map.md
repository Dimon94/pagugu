# Current System Map

Status: runnable discovery、全量手动 Check Run、freshness 重推导、安全 Update Run 成功/失败/取消路径、App 级 run 互斥、12 态裁决、目录状态投影、manual source mapping 与主窗口全流程 UI 接线（更新确认、结果区六类反馈、多检出当次选择）

本文件描述当前可验证的系统边界。产品动机、目标用户与目标体验见 repo://docs/product/vision.md。规划中的 Skill 扫描和更新能力不冒充现状。

## 当前事实

- 产品：Pagugu，本地 macOS Agent Skill 管理与安全同步应用。
- 当前阶段：可运行发现目录、逐检出实时 Git Fact、全量手动 Check Run、观察 freshness 与重启重推导、安全 Update Run（重查、冻结精确 SHA、确认/取消、ff-only、post-verify、九类失败、完整刷新）、Update start/terminal 与确认前 terminal-only 审计、审计呈现三语义面（工具栏「最近活动」摘要、详情、清空）与孤儿「结果未知（已中断）」呈现、审计损坏 fail-open「历史不可用」、Registry 重置 quarantine 备份路径呈现、App 级 Check/Update 单一互斥、12 态裁决、详情卡片、目录逐态短语/五档静默排序、Project Scan Root 管理与复制 Installation 的人工来源映射、主窗口 Update Run 全流程接线（逐检出更新 intent、多 Eligible 检出当次选择、冻结计划确认页含影响范围名单、结果区六类反馈横幅）。ChunUI 兼容性验证已完成（不引入，见 docs/product/chunui-compatibility.md）。主窗口视觉令牌集中于 DesignTokens，原生 SwiftUI 令牌化打磨见 docs/product/ui-polish-review.md。
- 技术栈：原生 Xcode macOS App、SwiftUI、Swift 6、macOS 14+。
- 运行入口：`Pagugu/App/PaguguApp.swift`；稳定本地入口为 `script/build_and_run.sh`。
- 分发：本地构建；App Sandbox 关闭。签名、公证和 GitHub Releases 尚未实现。
- 持久状态：Persistence actor 读写 `~/Library/Application Support/com.dimon.pagugu/registry.json` 与物理独立的 `audit-history.json`。Registry 已接通 Project Scan Root、来源映射与逐检出观察单槽；Audit 已接通来源映射、Check Run terminal，以及 Update Run started / success / cancelled / failed terminal；run 聚合态、确认计划与当次检出选择仍为瞬态。
- 外部系统：通过唯一 Git seam 调用本机 `git`，全部命令非交互、屏蔽仓库 hooks，且带单调时钟秒级 timeout；Check Run 只顺序 fetch，Update Run 只 fetch 单 upstream 并对被选工作树执行 `merge --ff-only <精确 SHA>`。App 退出时通过同一 seam 尽力终止在途 Git 子进程；重启不恢复 run。公开 GitHub 仓库只用于 Issues；本地代码尚未推送。

## 当前链路

    Codex Run / shell
      -> script/build_and_run.sh
      -> xcodebuild
      -> Pagugu.app
      -> Persistence.loadRegistry
      -> 正常态继续 / 受限恢复全窗口阻断
      -> Registry 投影 Project Scan Root 可用性
      -> Discovery 扫描 Personal + Project Scan Root
      -> Git 逐候选检出 local-only inspection
      -> Identity 以 Git origin 规范化 Source Key，聚合 Skill、保留全部物理检出并重验证来源映射
      -> Registry 读观察单槽；Eligibility 校验身份与新鲜度
      -> 新鲜成功观察触发 after-successful-check inspection 并按固定 precedence 裁决
      -> Registry durable 来源映射/观察单槽 + Audit best-effort 映射与 Check Run terminal 证据
      -> AppModel 发布 Skill Read Model（逐态目录短语；需要处理 → 可更新 → 尚未检查 → 无需更新 → 仅本地）
      -> Update intent 当次选择 Eligible Checkout
      -> AppModel 获取 App 级单一 run 互斥；Check/Update 入口同步禁用并解释
      -> Runs fetch 重查 → ready/noop/blocked；确认前阻断或失败写 terminal-only failed
      -> ready UpdatePlan 冻结身份、精确 SHA 与目标检出 Skill 成员清单
      -> cancel 标记目标检出需重新检查 + 写 terminal-only cancelled → 忽略 fresh 旧观察并刷新为 check-unknown → 释放互斥
      -> confirm 写审计 start → 漂移比对 → ff-only 精确 SHA → post-verify → success/failed terminal
      -> 九类失败立即停止，不自动重试、不自动回滚；AppModel 发布中文失败类与恢复方向
      -> 成功时 AppModel 保留结果 → 完整 Discovery 刷新；post-verify facts 仅作为该次刷新一次性证据
      -> 一次性事实不写 Observation、不跨刷新保留；刷新失败独立呈现且不回滚
      -> WindowGroup + MenuBarExtra
      -> ContentView / MenuBarView

## 当前模块

| Module | Owns | Does not own | Public interface | Depends on | Verification |
| --- | --- | --- | --- | --- | --- |
| PaguguApp | 应用生命周期、主窗口与状态栏场景 | Skill 扫描、Git 状态、持久化 | macOS App 入口 | SwiftUI、AppKit | `script/build_and_run.sh --verify` |
| ContentView | 主窗口 Variant F IA；显示目录状态短语、唯一手动检查入口、结果区六类反馈横幅与逐检出卡片（含更新 intent）；更新确认 sheet（多检出当次选择 + 冻结计划 + 影响范围名单）；逐 Installation 来源映射、失效原因与删除确认；扫描范围管理、「最近活动」三语义面与 Registry 故障阻断 | Skill Read Model 派生、Checkout Git State/Run 裁决、目录排序、审计投影派生、IO、视觉令牌定义 | SwiftUI `View` | SwiftUI、AppModel、DesignTokens | App build |
| MenuBarView | 打开主窗口与退出动作 | 更新状态和后台调度 | SwiftUI `View` | SwiftUI、AppKit | App build + launch |
| DesignTokens | 主窗口视觉令牌（间距、圆角、尺寸、字号、语义状态色、表面材质、按压反馈） | 业务状态裁决、ChunUI、IA 语义 | `DesignTokens` enum、`PressFeedbackButtonStyle` | SwiftUI | `PaguguTests` 令牌不变量 |
| AppIdentity | 产品展示名、Bundle ID、主窗口 ID | 用户配置 | 静态常量 | Swift 标准库 | `PaguguTests.testProductIdentity` |
| Discovery | Discovery Scan：遍历全部 Scan Root、发现入口标注；Project Scan Root 集中排除 `.git`、依赖与构建产物目录并设 10 层深度保险，denylist 命中记 Scan Issue 但仍为 complete，第 11 层截断记 Issue/partial；软链接解析、Canonical Path 去重防环、SKILL.md 解析校验与原文读取、Git 工作树根检测（`.git` 存在性）、复制投影内容指纹（SHA-256，fail closed） | 身份归因与指纹聚合（归 Identity）、Git 子进程 | `Discovery.scanAll(personalRoots:projectRoots:)`、`scanPersonalRoots(_:)`、`scanProjectRoot(_:)`、`skillMarkdown(atCanonicalPath:)`、`contentFingerprint(ofSkillAtCanonicalPath:)` | Foundation、CryptoKit | `PaguguTests/DiscoveryTests.swift` |
| Identity | Skill Source Key 规范化、人工映射重验证、归因与聚合、Skill Source Checkout、同一 remote 多检出及逐检出 Skill 成员清单（全部纯函数） | 文件系统遍历、Git 调用、状态裁决与主张写入 | `SkillSourceKey.normalize(remoteURL:)`、`SkillDirectory.contents(from:gitFactsByCheckoutPath:mappings:)` | Foundation、Discovery/Git/Persistence 值类型 | `PaguguTests/IdentityTests.swift`、`AppModelTests.swift` |
| Git | 唯一 Git 子进程 seam；非交互环境、timeout、exit/stderr 与锁冲突原语归一化；实时正交 Checkout Git Fact、单 upstream fetch、精确 SHA ff-only、在途进程尽力终止 | Checkout Git State、失败九类与 Eligible Update 裁决、检查/更新编排 | `GitInspecting.inspectCheckout(at:scope:)`、`GitExecuting.fetch(remote:upstreamRef:at:)`、`fastForward(to:at:)`、`terminateInFlight()` | Foundation、OS、本机 git | `PaguguTests/GitEligibilityTests.swift` |
| Eligibility | 12 态固定 precedence、观察身份摘要匹配与 freshness 裁决（纯函数） | Git 调用、持久化、UI | `evaluate(facts:sourceKey:)`、`identityDigest(facts:sourceKey:)`、`observationMatchesIdentity`、`observationIsFresh` | Git/Identity/Persistence 值类型 | `PaguguTests/GitEligibilityTests.swift`、`CheckRunTests.swift` |
| Registry | Project Scan Root 与来源映射串行 mutation、护栏、显式删除、当前主张投影与观察单槽 durable-first 替换 | registry.json 物理 IO、Discovery、Check Run 编排、UI、映射有效性裁决 | Project Scan Root CRUD、来源映射 CRUD、`checkoutObservations()`、`recordCheckoutObservation(_:)` | Persistence、Audit、Foundation | `PaguguTests/RegistryTests.swift`、`CheckRunTests.swift` |
| Persistence | registry.json 与 audit-history.json 的唯一物理 IO、v1 持久记录、双 fsync 原子写、quarantine、Registry 外部修改检测；Update started/terminal 以 run ID 关联并校验 phase/outcome/payload 配对，failed reason 只接受 schema 的九个稳定 wire code（测试锁定与 Runs rawValue 集合一致） | 三类主张、失败九类与审计记录的业务语义、Git/Discovery/Eligibility | Registry load/save/reset、Audit load/append/clear | Foundation、Darwin | `PaguguTests/PersistenceTests.swift`、`RegistryTests.swift` |
| Audit | 来源映射、Check Run terminal 与 Update Run started/success/cancelled/failed terminal 的窄 append 语义入口；写入/读取失败 fail-open；呈现投影派生（两段折叠、孤儿 interrupted-unknown、「历史不可用」） | 文件 IO、当前主张、恢复、执行许可 | `recordSourceMapping(...)`、`recordCheckRun(...)`、`recordUpdateStarted(...)`、`recordUpdateSucceeded(...)`、`recordUpdateCancelled(...)`、`recordUpdateFailed(...)`、`history()`、`clearHistory()`、`AuditPresentation.project(_:)` | Persistence、Foundation | `PaguguTests/RegistryTests.swift`、`CheckRunTests.swift`、`AppModelTests.swift` |
| Runs | Check Run 编排；Update Run fetch 重查、精确计划、确认取消、漂移比对、ff-only、post-verify、九类失败归一化与 terminal 审计；run 瞬态 | Git/观察物理 IO、UI 投影、第二把互斥锁 | `CheckRunner.startCheck(scope:)`、`UpdateRunner.prepareUpdate(request:)`、`cancelPrepared(_:)`、`executeConfirmed(_:)` | Git、Eligibility、Registry、Audit | `PaguguTests/CheckRunTests.swift` |
| AppModel | @MainActor composition root：启动/刷新、App 级单一 run 互斥（preparing / awaiting-confirmation / executing / cancelling）、Check/Update intent、取消/失败/禁用原因投影，按实时事实重推导 freshness；确认页取消后在新的成功检查前忽略目标检出的旧观察并固定投影 check-unknown；发布逐检出、映射、目录逐态短语与五档静默排序投影；审计历史投影与清空 intent、重置备份路径呈现；受限恢复退出 intent | 直接 Git/文件系统/持久 IO、Checkout Git State/映射有效性/执行规则重建 | 启动/重扫、`checkNow()`、Eligible 检出候选、`prepareUpdate(...)`、`confirmUpdate()`、`cancelUpdate()`、Project Scan Root/来源映射 CRUD、Registry reset、`requestQuit()`、`clearAuditHistory(confirmed:)` | Registry、Audit、Discovery、Git、Identity、Eligibility、Runs | `PaguguTests/AppModelTests.swift` |
| build_and_run.sh | kill、build、launch、进程验证 | 签名、公证、发布 | `run|--debug|--logs|--telemetry|--verify` | `xcodebuild`、macOS CLI | `--verify` |

## 产品不变量

未来实现扫描与更新时必须保持：

- Skill Source 的 canonical owner 是 Git 仓库；Skill Installation 只是投影。
- 只有 Checkout Git State 为 update-available 的 Skill Source Checkout 才允许更新：inspection 成功、upstream 身份与 Skill Source Key 一致、无兄弟 worktree 冲突、严格干净、存在成功检查结果且 behind-only。一次更新只作用于一个明确选定的物理工作树，禁止自动同步全部 clone 与 worktree。
- 其余 11 个 Checkout Git State（inspection-failed、no-remote、detached、no-upstream、upstream-mismatch、sibling-conflict、check-unknown、dirty、diverged、ahead-only、up-to-date），以及 Unattributed Installation、失效映射与不完整 Scan Result，必须 fail closed，各配人工恢复方向；同名异源与同一 Skill Source Key 下其他检出的状态本身不阻断更新。
- Pagugu 不直接覆盖未知所有权的安装目录。
- UI、缓存、日志和 App Registry 均不能成为 Skill 内容或 Git 状态的第二真相；Checkout Git State 由实时 Git Fact 确定性派生，上次观察结果不充当当前 Git 事实。
- 审计证据（Audit Evidence）是 append-only 历史证据集合，只记录用户发起的 Update Run、Check Run 与来源映射维护动作及其终态结果；它永不充当当前 Git 状态、Eligible Update、Checkout Observation freshness、执行许可、自动恢复、自动重试或回滚依据（repo://docs/adr/0007-audit-evidence-and-recovery-presentation.md）。
- App Registry 的持久合同：单个本地 JSON 恰好拥有 Project Scan Root、来源映射与逐检出单槽上次观察三类当前主张；原子写且磁盘为唯一 canonical；损坏 quarantine 并 fail closed，未知未来版本绝不覆写；审计证据为物理独立的 append-only 文件，FIFO 200、损坏 fail-open（repo://docs/adr/0008-app-registry-persistence-contract.md）。
- 人工来源映射是对文件系统与 Git 事实的主张：每次完整 Discovery Scan 重验证，事实优先；失效不静默删除，只能由用户显式删除。
- Update Run 瞬态不持久：执行前必须 fetch 并重查目标检出，确认绑定重查快照的精确 target SHA；副作用只允许 fetch 与被选检出内 `merge --ff-only <精确SHA>`；post-verify 六项（exit 0、HEAD == target、严格干净、branch/upstream 不变、身份不变、无进行中 Git 操作）全部成立，且最终实时裁决为 up-to-date，才发布成功。失败九类各配人工恢复方向，零自动重试、零自动回滚，永不 reset/force/stash/checkout 覆盖（repo://docs/adr/0006-update-run-execution-and-recovery.md）。
- 更新成功后重读 Git Fact 并触发完整 Discovery Scan 刷新 Skill Read Model；刷新失败独立于更新结果呈现，绝不回滚；复制投影不被更新写入、不传播。

## 明确未实现

- `SKILL.md` frontmatter 的完整 Agent Skills 规范校验（name/description 字段违规标注）。
- 宿主真实 logo 资源（当前为占位圆点）；签名、公证与发布。

## 验证

```bash
xcodebuild test \
  -project Pagugu.xcodeproj \
  -scheme Pagugu \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO

./script/build_and_run.sh --verify
```

`.github/workflows/ci.yml` 已配置相同测试入口；远程 workflow 运行仍为 Unknown。

## PROTOCOL

产品意图变化时先更新 repo://docs/product/vision.md。根合同变化时同步更新 repo://CONTEXT.md、repo://AGENTS.md 与命中模块的 L2-L6 合同。难回退且存在真实取舍的决定才写 accepted ADR。
