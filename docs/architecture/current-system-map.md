# Current System Map

Status: runnable baseline

本文件描述当前可验证的系统边界。产品动机、目标用户与目标体验见 repo://docs/product/vision.md。规划中的 Skill 扫描和更新能力不冒充现状。

## 当前事实

- 产品：Pagugu，本地 macOS Agent Skill 管理与安全同步应用。
- 当前阶段：可运行技术基线。
- 技术栈：原生 Xcode macOS App、SwiftUI、Swift 6、macOS 14+。
- 运行入口：`Pagugu/App/PaguguApp.swift`；稳定本地入口为 `script/build_and_run.sh`。
- 分发：本地构建；App Sandbox 关闭。签名、公证和 GitHub Releases 尚未实现。
- 持久状态：当前应用不读写持久状态。规划中的 App Registry 尚未实现。
- 外部系统：当前运行时无外部系统。公开 GitHub 仓库已创建并用于 Issues；本地仓库尚未配置 remote 或推送代码，远程默认分支和 Actions 运行均不存在。

## 当前链路

    Codex Run / shell
      -> script/build_and_run.sh
      -> xcodebuild
      -> Pagugu.app
      -> WindowGroup + MenuBarExtra
      -> ContentView / MenuBarView

## 当前模块

| Module | Owns | Does not own | Public interface | Depends on | Verification |
| --- | --- | --- | --- | --- | --- |
| PaguguApp | 应用生命周期、主窗口与状态栏场景 | Skill 扫描、Git 状态、持久化 | macOS App 入口 | SwiftUI、AppKit | `script/build_and_run.sh --verify` |
| ContentView | 基线主窗口内容 | Skill Read Model | SwiftUI `View` | SwiftUI | App build |
| MenuBarView | 打开主窗口与退出动作 | 更新状态和后台调度 | SwiftUI `View` | SwiftUI、AppKit | App build + launch |
| AppIdentity | 产品展示名、Bundle ID、主窗口 ID | 用户配置 | 静态常量 | Swift 标准库 | `PaguguTests.testProductIdentity` |
| build_and_run.sh | kill、build、launch、进程验证 | 签名、公证、发布 | `run|--debug|--logs|--telemetry|--verify` | `xcodebuild`、macOS CLI | `--verify` |

## 产品不变量

未来实现扫描与更新时必须保持：

- Skill Source 的 canonical owner 是 Git 仓库；Skill Installation 只是投影。
- 只有 Checkout Git State 为 update-available 的 Skill Source Checkout 才允许更新：inspection 成功、upstream 身份与 Skill Source Key 一致、无兄弟 worktree 冲突、严格干净、存在成功检查结果且 behind-only。一次更新只作用于一个明确选定的物理工作树，禁止自动同步全部 clone 与 worktree。
- 其余 11 个 Checkout Git State（inspection-failed、no-remote、detached、no-upstream、upstream-mismatch、sibling-conflict、check-unknown、dirty、diverged、ahead-only、up-to-date），以及 Unattributed Installation、失效映射与不完整 Scan Result，必须 fail closed，各配人工恢复方向；同名异源与同一 Skill Source Key 下其他检出的状态本身不阻断更新。
- Pagugu 不直接覆盖未知所有权的安装目录。
- UI、缓存、日志和 App Registry 均不能成为 Skill 内容或 Git 状态的第二真相；Checkout Git State 由实时 Git Fact 确定性派生，上次观察结果不充当当前 Git 事实。
- 人工来源映射是对文件系统与 Git 事实的主张：每次完整 Discovery Scan 重验证，事实优先；失效不静默删除，只能由用户显式删除。

## 明确未实现

- Personal Skill Root 与 Project Scan Root 扫描。
- `SKILL.md` frontmatter、软链接与插件来源识别。
- Skill Read Model、每日检查、一键更新与通知。
- App Registry JSON。
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
