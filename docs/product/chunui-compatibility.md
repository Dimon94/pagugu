# ChunUI 兼容性验证（#27 前置验证）

Status: verified（2026-08-26，本票执行）

## 结论

**不引入。** liseami/ChunUI（MIT）以 Swift Package 形式解析成功，但对 macOS 14+ 目标编译级验证失败；按 #27 冻结条款，兼容性验证不通过时保持原生 SwiftUI，不强行引入。本结论为后续打磨票（#28）的引入决策提供输入。

## 验证方法

以独立 SwiftPM executable probe（`platforms: [.macOS(.v14)]`，swift-tools-version 5.9）声明对 `https://github.com/liseami/ChunUI.git`（branch: `main`）的包依赖，执行 `swift package resolve` 与 `swift build` / `xcodebuild -destination 'platform=macOS,arch=arm64' build`。

## 证据

1. **包解析成功**：`swift package resolve` 正常完成，解析到 ChunUI `main`（commit `c8f0af0`）与其唯一第三方依赖 Pow（EmergeTools，MIT）`1.0.6`。
2. **macOS 编译失败**：`swift build` 报错 `the library 'ChunUI' requires macos 10.13, but depends on the product 'Pow' which requires macos 12.0`；`xcodebuild` 复现同一错误（`The package product 'Pow' requires minimum platform version 12.0 for the macOS platform, but this target supports 10.13 (in target 'ChunUI' from project 'ChunUI')`）。
3. **根因**：ChunUI 的 `Package.swift`（swift-tools-version 6.2）`platforms` 仅声明 `.iOS("18.6")`，未声明任何 macOS 版本；SwiftPM 对未声明平台回退到默认最低版本（macOS 10.13），与 Pow 的 macOS 12.0 下限冲突，导致依赖图不可解。
4. **源码面**：`Sources/ChunUI` 大量使用 UIKit（`import UIKit`、`UIImage+`、`UIScreen+`、`CCPHPicker`、`PhotoSlector`、`SquareCropPicker`、`CCVideo` 等），仅个别文件（`CCColors.swift`）有 `canImport(UIKit)` 条件编译；主体组件面向 iOS，无 macOS 适配层。
5. **许可证**：仓库含 `LICENSE`，MIT，Copyright (c) 2026 liseami（赵纯想）；许可证本身不构成引入障碍。

## 不可用原因汇总

- 包清单未声明 macOS 平台，依赖图在 macOS 目标下不可解（阻断）。
- 源码主体依赖 UIKit，无 macOS 适配层（即使解除清单限制也无法直接编译）。

## 可用组件面

无。macOS 14+ 目标下无任何可编译使用的 ChunUI 组件。

## 对后续票的输入

- #28 视觉打磨不引入 ChunUI，继续使用原生 SwiftUI 组件与系统材质。
- 若未来上游为 ChunUI 补充 macOS 平台声明与 AppKit 适配，可重新评估；当前无此信号。
