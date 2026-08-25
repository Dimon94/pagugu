# Current System Map

Status: runnable discovery（Variant F 目录 IA）and Project Scan Root management

本文件描述当前可验证的系统边界。产品动机、目标用户与目标体验见 repo://docs/product/vision.md。规划中的 Skill 扫描和更新能力不冒充现状。

## 当前事实

- 产品：Pagugu，本地 macOS Agent Skill 管理与安全同步应用。
- 当前阶段：可运行发现目录（Variant F IA：来源仓库行 + 无仓库可归行）与 Project Scan Root 管理。
- 技术栈：原生 Xcode macOS App、SwiftUI、Swift 6、macOS 14+。
- 运行入口：`Pagugu/App/PaguguApp.swift`；稳定本地入口为 `script/build_and_run.sh`。
- 分发：本地构建；App Sandbox 关闭。签名、公证和 GitHub Releases 尚未实现。
- 持久状态：Persistence actor 读写 `~/Library/Application Support/com.dimon.pagugu/registry.json`。Registry 已接通 Project Scan Root 主张的添加、删除与按序读回；来源映射与观察槽的业务写入方由后续票接通。
- 外部系统：当前运行时无外部系统。公开 GitHub 仓库已创建并用于 Issues；本地仓库尚未配置 remote 或推送代码，远程默认分支和 Actions 运行均不存在。

## 当前链路

    Codex Run / shell
      -> script/build_and_run.sh
      -> xcodebuild
      -> Pagugu.app
      -> Persistence.loadRegistry
      -> 正常态继续 / 受限恢复全窗口阻断
      -> Registry 投影 Project Scan Root 可用性
      -> Discovery 扫描 Personal + Project Scan Root
      -> Identity 归因聚合为 Variant F 目录（来源仓库行 + 无仓库可归行）
      -> WindowGroup + MenuBarExtra
      -> ContentView / MenuBarView

## 当前模块

| Module | Owns | Does not own | Public interface | Depends on | Verification |
| --- | --- | --- | --- | --- | --- |
| PaguguApp | 应用生命周期、主窗口与状态栏场景 | Skill 扫描、Git 状态、持久化 | macOS App 入口 | SwiftUI、AppKit | `script/build_and_run.sh --verify` |
| ContentView | 主窗口 Variant F IA：平铺目录（来源仓库行可收起/展开 + 子 Skill 行 + 来源不明行）、Skill 详情三块（安装位置、来源标识、SKILL.md 原文）、欢迎引导与添加入口、工具栏扫描范围管理、Registry 故障全窗口阻断接管 | Skill Read Model 派生与主张规则、IO（经 AppModel intent） | SwiftUI `View` | SwiftUI、AppModel | App build |
| MenuBarView | 打开主窗口与退出动作 | 更新状态和后台调度 | SwiftUI `View` | SwiftUI、AppKit | App build + launch |
| AppIdentity | 产品展示名、Bundle ID、主窗口 ID | 用户配置 | 静态常量 | Swift 标准库 | `PaguguTests.testProductIdentity` |
| Discovery | Discovery Scan：遍历全部 Scan Root、发现入口标注、软链接解析、Canonical Path 去重防环、SKILL.md 解析校验与原文读取、Git 工作树根检测（`.git` 存在性）、复制投影内容指纹（SHA-256，fail closed）、Scan Issue | 身份归因与指纹聚合（归 Identity）、Git 子进程 | `Discovery.scanAll(personalRoots:projectRoots:)`、`scanPersonalRoots(_:)`、`scanProjectRoot(_:)`、`skillMarkdown(atCanonicalPath:)`、`contentFingerprint(ofSkillAtCanonicalPath:)` | Foundation、CryptoKit | `PaguguTests/DiscoveryTests.swift` |
| Identity | Skill Source Key 规范化、HostAttribution 归因表、Projection Type 派生、按 Skill Identity 聚合 Installation（零 Installation 纯来源保留）、按 Skill Source 分组目录、复制投影按内容指纹聚合呈现组（全部纯函数） | 文件系统遍历、Git 调用、任何副作用 | `SkillSourceKey.normalize(remoteURL:)`、`HostAttribution.hosts(for:)`、`SkillDirectory.contents(from:)` | Foundation、Discovery 值类型 | `PaguguTests/IdentityTests.swift` |
| Registry | Project Scan Root 串行 mutation、护栏、按序主张添加、显式删除与合法性/可用性派生 | registry.json 物理 IO、Discovery、UI、来源映射与观察槽的后续入口 | `AppRegistry.load()`、`addProjectScanRoot(_:)`、`removeProjectScanRoot(canonicalPath:)`、`projectScanRoots()` | Persistence、Foundation | `PaguguTests/RegistryTests.swift` |
| Persistence | registry.json 的物理 IO、v1 持久记录类型、兼容分发、双 fsync 原子写、quarantine、外部修改检测 | 三类主张与审计记录的业务语义、Git/Discovery/Eligibility | `loadRegistry()`、`saveRegistry(_:)`、`resetRegistry(confirmed:)` | Foundation、Darwin | `PaguguTests/PersistenceTests.swift` |
| AppModel | @MainActor composition root：Skill Read Model、受限恢复与主张动作错误投影、目录收起 UI 状态、UI intent 唯一入口、启动与刷新流水线编排 | 直接 Git/文件系统/持久 IO、业务规则重建 | `start()`、`rescan()`、`addProjectScanRoot(_:)`、`removeProjectScanRoot(canonicalPath:)`、`resetRegistry(confirmed:)`、`toggleSourceCollapsed(_:)`、`skillMarkdown(canonicalPath:)` | Registry、Discovery、Identity | `PaguguTests/AppModelTests.swift` |
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
- Update Run 瞬态不持久：执行前必须 fetch 并重查目标检出，确认绑定重查快照的精确 target SHA；副作用只允许 fetch 与被选检出内 `merge --ff-only <精确SHA>`；post-verify 六项充要条件（exit 0、HEAD == target、严格干净、branch/upstream 不变、身份不变、无进行中 Git 操作）全部成立才算成功。失败九类各配人工恢复方向，零自动重试、零自动回滚，永不 reset/force/stash/checkout 覆盖（repo://docs/adr/0006-update-run-execution-and-recovery.md）。
- 更新成功后重读 Git Fact 并触发完整 Discovery Scan 刷新 Skill Read Model；刷新失败独立于更新结果呈现，绝不回滚；复制投影不被更新写入、不传播。

## 明确未实现

- `SKILL.md` frontmatter 的完整 Agent Skills 规范校验（name/description 字段违规标注）。
- Git 状态裁决、检查、更新与审计（#19–#26 后续票）。Git 子进程 seam（`GitInspecting`/`GitExecuting`）接通后，有远程的 Skill Source Key 由本地路径键升级为规范化远程 URL；当前来源仓库行全部使用本地 canonical 路径键。
- Skill 详情「状态与检出」「相关记录」「更新动作」三块与目录行状态短语、五档静默排序（#19–#20 后续票）。
- 来源映射维护与失效生命周期（#25 后续票）；当前无仓库可归行只呈现「来源不明」事实（内容完全一致的复制安装聚合为只读呈现组，ADR-0001 §4）。
- 审计证据（Audit Evidence）持久集合。
- Logo、签名、公证与发布。

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
