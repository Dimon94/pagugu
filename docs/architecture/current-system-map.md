# Current System Map

Status: runnable baseline

本文件描述当前可验证的系统边界。规划中的 Skill 扫描和更新能力不冒充现状。

## 当前事实

- 产品：Pagugu，本地 macOS Agent Skill 管理与安全同步应用。
- 当前阶段：可运行技术基线。
- 技术栈：原生 Xcode macOS App、SwiftUI、Swift 6、macOS 14+。
- 运行入口：`Pagugu/App/PaguguApp.swift`；稳定本地入口为 `script/build_and_run.sh`。
- 分发：本地构建；App Sandbox 关闭。签名、公证和 GitHub Releases 尚未实现。
- 持久状态：当前应用不读写持久状态。规划中的 App Registry 尚未实现。
- 外部系统：当前运行时无外部系统。GitHub 仅用于计划中的公开托管与现有 CI 配置，远程仓库尚未创建。

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
- 只有干净且可 fast-forward 的已识别 Skill Source 才允许自动更新。
- 脏仓库、分叉、无远程或同名异源必须 fail closed，并提供人工恢复动作。
- Pagugu 不直接覆盖未知所有权的安装目录。
- UI、缓存、日志和 App Registry 均不能成为 Skill 内容的第二真相。

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

根合同变化时同步更新 repo://CONTEXT.md、repo://AGENTS.md 与命中模块的 L2-L6 合同。难回退且存在真实取舍的决定才写 accepted ADR。
