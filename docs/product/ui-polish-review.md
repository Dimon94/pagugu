# 主窗口 UI 打磨评审（#28）

Status: verified（2026-08-26）

Mode: `full`。Scope: Variant F 主窗口（目录、详情、结果区横幅、更新确认 / 扫描范围 / 来源映射 / 最近活动 sheet、欢迎与空态、Registry 受限恢复）。Stack: 原生 SwiftUI、macOS 14+、系统动态语义色。ChunUI 不引入（repo://docs/product/chunui-compatibility.md）。边界：不做主窗口筛选 UI、不做完整可及性审计、不做多语言本地化；IA 语义与中文文案冻结。评审顺序按 better-interface：Accessibility → Layout → Writing → Typography → Colors → UI。

## Scope and Coverage

| Domain | Evidence inspected | Result |
| --- | --- | --- |
| Accessibility | 目录 chevron、横幅关闭、宿主 logo 槽位、删除/映射 icon-only、禁用「更新…」help、sheet 显式关闭；源码 + 启动主窗口 | Clear（完整 VoiceOver 走查不在范围） |
| Layout | `ContentView` 目录密度、详情 `Space.section=16` 对 `Space.block=8`、结果区与详情分界、sheet 内边距 | Clear |
| Writing | 中文按钮「更新…」「确认更新」「关闭」、空态下一步、失败恢复方向；不改冻结合同文案 | Clear |
| Typography | `DesignTokens.Fonts` 梯度；标题 tail / 路径 middle / 横幅不截断；进度 `monospacedDigit` | Clear |
| Colors | `DesignTokens.Status` 系统动态色；状态名+图标+文案并存；明暗随系统色 | Clear |
| UI | 令牌消费、卡片材质 vs 横幅状态描边、按压 0.96、无高频自定义动画 | Clear |

## Findings

No actionable interface findings.

HIGH 已清零。打磨过程中已处理：逐组件手写字号/间距改为令牌；详情块 `Divider` 与 `Space.section` 叠加改为只靠 2× 间距分组；宿主 logo 由透明度改为实心/描边双提示并提供组合无障碍标签；按压在 Reduce Motion 下改透明度、取消缩放动画。

## Considered but Rejected

| Location | Candidate | Rejected because |
| --- | --- | --- |
| SPM / 工程依赖 | 引入 liseami/ChunUI 组件与令牌 | #27 编译级验证失败；源码依赖 UIKit。见 repo://docs/product/chunui-compatibility.md |
| `DesignTokens.Status` | 自建 OKLCH 色板替换系统 `.green/.orange/.red/.blue` | 项目无自有色板；系统动态色已覆盖明暗两态；完整对比度审计不在范围 |
| `Radius.card` vs `Radius.inset` | 强迫 `card = inset + padding` 或落地未消费的 `concentric` helper | 两枚半径用于兄弟表面（卡片 vs SKILL.md 块），并非嵌套；better-ui 允许独立表面自选半径。嵌套圆角出现时再按 outer = inner + padding 计算 |
| `Size.disclosureHotspot` 18pt | 一律抬到 24×24 或 44×44 | 票排除完整可及性审计；18pt 独立热区来自冻结原型，抬升会改目录密度 |
| `MarkdownSourceBlock` | 长文 `65ch` 行宽帽 | SKILL.md 是只读证据，不是正文阅读面；截断或窄列会藏合同文本 |
| 成功/失败色 | 按中文金融习惯对调绿/红 | Pagugu 不是涨跌界面；绿=通路/成功、红=失败与现有中文文案一致 |

## Verification

- `xcodebuild test -project Pagugu.xcodeproj -scheme Pagugu -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO`：142 tests passed（含 pressScale=0.96、childIndent、状态色抽样、既有 S 路径回归）。
- `script/build_and_run.sh --verify`：build succeeded，进程存活。
- 源码核对：目录/详情/结果区/sheet 视觉常量均指向 `DesignTokens`；高频路径无自定义 enter/stagger；状态变化均有颜色+图标或文案。
- 明暗两态：状态色使用 SwiftUI 系统动态色，随 Appearance 变化；未做独立深色截图像素对比。**Not verified**：逐屏人工切换 Appearance 的像素级对比。
- 大规模条目滚动密度：List 系统虚拟化；行垂直内边距 `rowVertical=2`。**Not verified**：上千行真实数据滚动。

## Verdict

Approve
