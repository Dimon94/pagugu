# Current System Map

Status: runnable discovery（Claude Code / Codex / Pi）、Host Profile 同名冲突只读诊断、调用面配置实时只读呈现（含 Unsupported/读取失败）、Registry v2 Visibility Claim headless 持久化、通用 JSON HostConfigWriter headless 合并/备份/恢复/分歧机制、全量手动 Check Run、freshness 重推导、安全 Update Run 成功/失败/取消路径、App 级 run 互斥、12 态裁决、目录状态投影、manual source mapping 与主窗口全流程 UI 接线（更新确认、结果区六类反馈、多检出当次选择）

本文件描述当前可验证的系统边界。产品动机、目标用户与目标体验见 repo://docs/product/vision.md。规划中的 Skill 扫描和更新能力不冒充现状。

## 当前事实

- 产品：Pagugu，本地 macOS Agent Skill 管理与安全同步应用。
- 当前阶段：可运行发现目录（四个 Personal Skill Root；覆盖 Claude Code、Codex 与 Pi）、按 Host Profile 派生的同名共存组徽标与 Claude 遮蔽/Codex-Pi 歧义诊断、从 Claude JSON / Codex TOML+YAML / Pi 独占 JSON 实时读取逐宿主调用面档位并呈现 Unsupported/读取失败、逐检出实时 Git Fact、全量手动 Check Run、观察 freshness 与重启重推导、安全 Update Run（重查、冻结精确 SHA、确认/取消、ff-only、post-verify、九类失败、完整刷新）、Update start/terminal 与确认前 terminal-only 审计、审计呈现三语义面（工具栏「最近活动」摘要、详情、清空）与孤儿「结果未知（已中断）」呈现、审计损坏 fail-open「历史不可用」、Registry 重置 quarantine 备份路径呈现、App 级 Check/Update 单一互斥、12 态裁决、详情卡片、目录逐态短语/五档静默排序、Project Scan Root 管理与复制 Installation 的人工来源映射、主窗口 Update Run 全流程接线（逐检出更新 intent、多 Eligible 检出当次选择、冻结计划确认页含影响范围名单、结果区六类反馈横幅）。正式 Logo 已接入 AppIcon、状态栏和欢迎页；全部 app-owned 界面固定浅色并使用 DesignTokens 中的暖米白主题与品牌配色。ChunUI 兼容性验证已完成（不引入，见 docs/product/chunui-compatibility.md）。
- 技术栈：原生 Xcode macOS App、SwiftUI、Swift 6、macOS 14+。
- 运行入口：`Pagugu/App/PaguguApp.swift`；稳定本地入口为 `script/build_and_run.sh`。
- 分发：本地构建；App Sandbox 关闭。签名、公证和 GitHub Releases 尚未实现。
- 持久状态：Persistence actor 读写 `~/Library/Application Support/com.dimon.pagugu/registry.json` 与物理独立的 `audit-history.json`。Registry v2 已接通 Project Scan Root、来源映射、逐检出观察单槽与 Visibility Claim；合法 v1 会保留单份迁移前证据并原子迁移到 v2，未知未来版本绝不覆写。Audit 已接通来源映射、Check Run terminal，以及 Update Run started / success / cancelled / failed terminal；run 聚合态、确认计划、当次检出选择与调用面分歧仍为瞬态。
- 外部系统：通过唯一 Git seam 调用本机 `git`，全部命令非交互、屏蔽仓库 hooks，且带单调时钟秒级 timeout；Check Run 只顺序 fetch，Update Run 只 fetch 单 upstream 并对被选工作树执行 `merge --ff-only <精确 SHA>`。App 退出时通过同一 seam 尽力终止在途 Git 子进程；重启不恢复 run。公开 GitHub 仓库只用于 Issues；本地代码尚未推送。

## 当前链路

    Codex Run / shell
      -> script/build_and_run.sh
      -> xcodebuild
      -> Pagugu.app
      -> Persistence.loadRegistry
      -> 缺文件为空 v2 / 合法 v1 保留迁移前证据并迁移 / 正常 v2 继续 / 受限恢复全窗口阻断
      -> Registry 投影 Project Scan Root 可用性
      -> HostProfile 提供四个 Personal Skill Root 与逐路径宿主归因
      -> Discovery 扫描 Personal + Project Scan Root
      -> Git 逐候选检出 local-only inspection
      -> Identity 以 Git origin 规范化 Source Key，聚合 Skill、保留全部物理检出与 Personal/Project scope，并重验证来源映射
      -> Registry 读观察单槽；Eligibility 校验身份与新鲜度
      -> 新鲜成功观察触发 after-successful-check inspection 并按固定 precedence 裁决
      -> Registry durable 来源映射/观察单槽 + Audit best-effort 映射与 Check Run terminal 证据
      -> HostProfile 纯函数按规范化名称产生同名共存组/逐宿主诊断，并提供调用面能力矩阵
      -> HostConfigReader 每次发布重读宿主配置，派生逐已安装宿主档位 / Unsupported / 读取失败
      -> AppModel 发布 Skill Read Model（同名共存组徽标/诊断；调用面只读投影；逐态目录短语；需要处理 → 可更新 → 尚未检查 → 无需更新 → 仅本地）
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
| PaguguApp | 应用生命周期、固定浅色主窗口、正式 AppIcon 与可着色状态栏窗口场景 | Skill 扫描、Git 状态、持久化 | macOS App 入口 | SwiftUI、AppKit、Assets.xcassets | `script/build_and_run.sh --verify` |
| ContentView | 主窗口 Variant F IA、暖米白根画布与窗口工具栏；在 Skill 与来源不明详情显示同名共存组诊断，以及逐宿主调用面档位、Unsupported 缺口与读取失败；显示目录状态短语、唯一手动检查入口、结果区六类反馈横幅与逐检出卡片（含更新 intent）；更新确认 sheet（多检出当次选择 + 冻结计划 + 影响范围名单）；逐 Installation 来源映射、失效原因与删除确认；扫描范围管理、「最近活动」三语义面与 Registry 故障阻断 | Skill Read Model 派生、HostProfile/HostConfig 规则重建、Checkout Git State/Run 裁决、目录排序、审计投影派生、IO、视觉令牌定义 | SwiftUI `View` | SwiftUI、AppModel、DesignTokens | App build |
| MenuBarView | 暖米白状态栏窗口内的打开主窗口与退出动作 | 更新状态和后台调度 | SwiftUI `View` | SwiftUI、AppKit、DesignTokens | App build + launch |
| DesignTokens | app-owned 界面视觉令牌（品牌与暖米白全局画布、间距、圆角、尺寸、字号、语义状态色、表面材质、按压反馈） | 业务状态裁决、ChunUI、IA 语义 | `DesignTokens` enum、`PressFeedbackButtonStyle` | SwiftUI | `PaguguTests` 令牌不变量 |
| AppIdentity | 产品展示名、Bundle ID、主窗口 ID | 用户配置 | 静态常量 | Swift 标准库 | `PaguguTests.testProductIdentity` |
| HostProfile | Claude Code、Codex、Pi 的宿主标识、Personal/Project 根归因、默认 Personal Skill Root 集合、同名共存组规则、四档 Exposure Level 与逐宿主能力矩阵（全部纯函数） | 文件系统扫描、Skill Identity/Installation 聚合、UI 投影、宿主配置读写与当前档位 | `HostProfiles.personalSkillRoots()`、`HostProfiles.hosts(for:scope:)`、`HostProfile.supports(_:)`、`NameCollisionEngine.groups(from:)` | Foundation | `PaguguTests/DiscoveryPiRootsTests.swift`、`NameCollisionTests.swift`、`HostConfigReaderTests.swift` |
| HostConfig | Claude Code `settings.json`、Codex `config.toml`/`agents/openai.yaml` 与 Pi 独占 `visibility.json` 的实时窄读取；结合 HostProfile 输出档位、Unsupported 或读取失败；通用 JSON key-path 原子合并、提交前外部漂移检测、`<file>.pagugu-backup` 单槽备份、恢复与 Registry Claim 映射值的实时一致/分歧派生 | 具体宿主写入映射、Visibility Claim 持久化、自动重应用、缓存、文件监听、UI | `HostConfigReader.invocationSurfaces(skillName:installations:)`、`HostConfigWriter.merge(_:at:in:)`、`restoreBackup(for:)`、`claimState(expecting:at:in:)` | Foundation、HostProfile/Identity 值类型 | `PaguguTests/HostConfigReaderTests.swift`、`HostConfigWriterTests.swift`、`AppModelSurfaceTests.swift` |
| Discovery | Discovery Scan：遍历全部 Scan Root、发现入口标注；Project Scan Root 集中排除 `.git`、依赖与构建产物目录并设 10 层深度保险，denylist 命中记 Scan Issue 但仍为 complete，第 11 层截断记 Issue/partial；软链接解析、Canonical Path 去重防环、SKILL.md 解析校验（name 缺失/空白时回退安装目录名）与原文读取、Git 工作树根检测（`.git` 存在性）、复制投影内容指纹（SHA-256，fail closed） | 宿主规则与冲突诊断（归 HostProfile）、身份归因与指纹聚合（归 Identity）、Git 子进程 | `Discovery.personalSkillRoots`、`scanAll(personalRoots:projectRoots:)`、`scanPersonalRoots(_:)`、`scanProjectRoot(_:)`、`skillMarkdown(atCanonicalPath:)`、`contentFingerprint(ofSkillAtCanonicalPath:)` | Foundation、CryptoKit、HostProfile | `PaguguTests/DiscoveryTests.swift`、`DiscoveryPiRootsTests.swift` |
| Identity | Skill Source Key 规范化、人工映射重验证、消费 HostProfile 归因并保留逐 Installation scope、按身份聚合、Skill Source Checkout、同一 remote 多检出及逐检出 Skill 成员清单（全部纯函数） | 宿主规则与冲突诊断、文件系统遍历、Git 调用、状态裁决与主张写入 | `SkillSourceKey.normalize(remoteURL:)`、`SkillDirectory.contents(from:gitFactsByCheckoutPath:mappings:)` | Foundation、HostProfile/Discovery/Git/Persistence 值类型 | `PaguguTests/IdentityTests.swift`、`AppModelTests.swift` |
| Git | 唯一 Git 子进程 seam；非交互环境、timeout、exit/stderr 与锁冲突原语归一化；实时正交 Checkout Git Fact、单 upstream fetch、精确 SHA ff-only、在途进程尽力终止 | Checkout Git State、失败九类与 Eligible Update 裁决、检查/更新编排 | `GitInspecting.inspectCheckout(at:scope:)`、`GitExecuting.fetch(remote:upstreamRef:at:)`、`fastForward(to:at:)`、`terminateInFlight()` | Foundation、OS、本机 git | `PaguguTests/GitEligibilityTests.swift` |
| Eligibility | 12 态固定 precedence、观察身份摘要匹配与 freshness 裁决（纯函数） | Git 调用、持久化、UI | `evaluate(facts:sourceKey:)`、`identityDigest(facts:sourceKey:)`、`observationMatchesIdentity`、`observationIsFresh` | Git/Identity/Persistence 值类型 | `PaguguTests/GitEligibilityTests.swift`、`CheckRunTests.swift` |
| Registry | Project Scan Root、来源映射与 Visibility Claim 串行 mutation、护栏、显式删除、当前主张投影与观察单槽 durable-first 替换；同一 Skill Identity × Agent Host 单槽 upsert | registry.json 物理 IO、宿主配置事实/写入与分歧、Discovery、Check Run 编排、UI、映射有效性裁决 | Project Scan Root CRUD、来源映射 CRUD、Visibility Claim 读/set/delete、`checkoutObservations()`、`recordCheckoutObservation(_:)` | Persistence、Audit、HostProfile 值类型、Foundation | `PaguguTests/RegistryTests.swift`、`RegistryV2Tests.swift`、`CheckRunTests.swift` |
| Persistence | registry.json 与 audit-history.json 的唯一物理 IO、Registry v2 / Audit v1 持久记录、HostProfile 支持矩阵约束的 Visibility Claim 校验、严格 v1→v2 迁移、双 fsync 原子写、quarantine、Registry 外部修改检测；Update started/terminal 以 run ID 关联并校验 phase/outcome/payload 配对，failed reason 只接受 schema 的九个稳定 wire code（测试锁定与 Runs rawValue 集合一致） | 四类当前主张、失败九类与审计记录的业务语义、宿主配置、Git/Discovery/Eligibility | Registry load/save/reset、Audit load/append/clear | Foundation、Darwin、HostProfile canonical 值类型 | `PaguguTests/PersistenceTests.swift`、`RegistryV2Tests.swift`、`RegistryTests.swift` |
| Audit | 来源映射、Check Run terminal 与 Update Run started/success/cancelled/failed terminal 的窄 append 语义入口；写入/读取失败 fail-open；呈现投影派生（两段折叠、孤儿 interrupted-unknown、「历史不可用」） | 文件 IO、当前主张、恢复、执行许可 | `recordSourceMapping(...)`、`recordCheckRun(...)`、`recordUpdateStarted(...)`、`recordUpdateSucceeded(...)`、`recordUpdateCancelled(...)`、`recordUpdateFailed(...)`、`history()`、`clearHistory()`、`AuditPresentation.project(_:)` | Persistence、Foundation | `PaguguTests/RegistryTests.swift`、`CheckRunTests.swift`、`AppModelTests.swift` |
| Runs | Check Run 编排；Update Run fetch 重查、精确计划、确认取消、漂移比对、ff-only、post-verify、九类失败归一化与 terminal 审计；run 瞬态 | Git/观察物理 IO、UI 投影、第二把互斥锁 | `CheckRunner.startCheck(scope:)`、`UpdateRunner.prepareUpdate(request:)`、`cancelPrepared(_:)`、`executeConfirmed(_:)` | Git、Eligibility、Registry、Audit | `PaguguTests/CheckRunTests.swift` |
| AppModel | @MainActor composition root：启动/刷新、App 级单一 run 互斥（preparing / awaiting-confirmation / executing / cancelling）、Check/Update intent、取消/失败/禁用原因投影，按实时事实重推导 freshness；确认页取消后在新的成功检查前忽略目标检出的旧观察并固定投影 check-unknown；每次发布经 HostConfigReader 重读并发布逐 Skill/来源不明条目的调用面只读投影，同时发布逐检出、映射、同名共存组、目录逐态短语与五档静默排序投影；审计历史投影与清空 intent、重置备份路径呈现；受限恢复退出 intent | 直接 Host 配置/Git/文件系统/持久 IO、调用面/Checkout Git State/映射有效性/执行规则重建 | 启动/重扫、`checkNow()`、Eligible 检出候选、`prepareUpdate(...)`、`confirmUpdate()`、`cancelUpdate()`、Project Scan Root/来源映射 CRUD、Registry reset、`requestQuit()`、`clearAuditHistory(confirmed:)` | Registry、Audit、HostConfig、HostProfile、Discovery、Git、Identity、Eligibility、Runs | `PaguguTests/AppModelTests.swift`、`AppModelCollisionTests.swift`、`AppModelSurfaceTests.swift` |
| build_and_run.sh | kill、build、launch、进程验证 | 签名、公证、发布 | `run|--debug|--logs|--telemetry|--verify` | `xcodebuild`、macOS CLI | `--verify` |

## 产品不变量

未来实现扫描与更新时必须保持：

- Skill Source 的 canonical owner 是 Git 仓库；Skill Installation 只是投影。
- 只有 Checkout Git State 为 update-available 的 Skill Source Checkout 才允许更新：inspection 成功、upstream 身份与 Skill Source Key 一致、无兄弟 worktree 冲突、严格干净、存在成功检查结果且 behind-only。一次更新只作用于一个明确选定的物理工作树，禁止自动同步全部 clone 与 worktree。
- 其余 11 个 Checkout Git State（inspection-failed、no-remote、detached、no-upstream、upstream-mismatch、sibling-conflict、check-unknown、dirty、diverged、ahead-only、up-to-date），以及 Unattributed Installation、失效映射与不完整 Scan Result，必须 fail closed，各配人工恢复方向；同一 Skill Source Key 下其他检出的状态本身不阻断更新。
- 同名共存组按 trim + 大小写折叠后的 frontmatter `name` 聚合；name 缺失或空白时回退安装目录名。它只做展示与诊断，不参与 Skill Identity、来源归因、去重、映射或更新资格。同名异源本身不阻断更新。Claude Code 的 Personal 同名安装遮蔽 Project；Codex 与 Pi 的同名位置共存为歧义。`~/.agents/skills` 在 Personal scope 同时服务 Codex 与 Pi，在 Project scope 只归 Codex。
- 调用面只读投影每次刷新都以宿主文件为当前事实；文件缺失表示宿主默认完全暴露，已存在但不可读或损坏必须呈现「读取失败」。Host Profile 不支持的档位必须呈现 Unsupported，不得静默降级；读取结果不写 Registry、不改变 Skill Identity 或更新资格。
- Pagugu 不直接覆盖未知所有权的安装目录。
- UI、缓存、日志和 App Registry 均不能成为 Skill 内容或 Git 状态的第二真相；Checkout Git State 由实时 Git Fact 确定性派生，上次观察结果不充当当前 Git 事实。
- 审计证据（Audit Evidence）是 append-only 历史证据集合，只记录用户发起的 Update Run、Check Run 与来源映射维护动作及其终态结果；它永不充当当前 Git 状态、Eligible Update、Checkout Observation freshness、执行许可、自动恢复、自动重试或回滚依据（repo://docs/adr/0007-audit-evidence-and-recovery-presentation.md）。
- App Registry 的持久合同：单个本地 JSON v2 恰好拥有 Project Scan Root、来源映射、逐检出单槽上次观察与 Visibility Claim 四类当前主张；Visibility Claim 零时间戳、零派生标志位，宿主文件事实优先；原子写且磁盘为唯一 canonical；合法 v1 先保留迁移前证据再迁移，损坏 quarantine 并 fail closed，未知未来版本绝不覆写；审计证据为物理独立的 append-only 文件，FIFO 200、损坏 fail-open（repo://docs/adr/0008-app-registry-persistence-contract.md、repo://docs/adr/0010-invocation-surface-write-channel-and-host-config-ownership.md）。
- 人工来源映射是对文件系统与 Git 事实的主张：每次完整 Discovery Scan 重验证，事实优先；失效不静默删除，只能由用户显式删除。
- Update Run 瞬态不持久：执行前必须 fetch 并重查目标检出，确认绑定重查快照的精确 target SHA；副作用只允许 fetch 与被选检出内 `merge --ff-only <精确SHA>`；post-verify 六项（exit 0、HEAD == target、严格干净、branch/upstream 不变、身份不变、无进行中 Git 操作）全部成立，且最终实时裁决为 up-to-date，才发布成功。失败九类各配人工恢复方向，零自动重试、零自动回滚，永不 reset/force/stash/checkout 覆盖（repo://docs/adr/0006-update-run-execution-and-recovery.md）。
- 更新成功后重读 Git Fact 并触发完整 Discovery Scan 刷新 Skill Read Model；刷新失败独立于更新结果呈现，绝不回滚；复制投影不被更新写入、不传播。

## 明确未实现

- HostConfigWriter 尚未接入具体 Claude/Codex/Pi 档位映射、AppModel 或 UI；TOML/YAML 写通道也未实现。
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
