# Views 模块合同（L2）

模块职责: 主窗口 Variant F IA 呈现（repo://docs/product/mvp-1.0-acceptance.md §2）。左侧平铺目录：来源仓库行（可收起/展开子 Skill 行，默认展开，chevron 独立热区）+ 无仓库可归行（标注「来源不明」）；无分组标题、无筛选 UI。右侧详情：Skill 三块（安装位置 = 路径 + 宿主 + 投影/归因、来源标识、SKILL.md 原文只读可选中）；空选择回欢迎引导（含添加 Project Scan Root 入口）。工具栏「扫描范围」管理 sheet；Registry 故障全窗口阻断接管（ADR-0008 §19）。只消费 Skill Read Model、只发 AppModel intent。

成员清单:
- `ContentView.swift`：主从结构、目录行、详情三块、宿主 logo 槽位（占位图形，真实资源归后续票）、扫描范围管理与受限恢复视图。
- `MenuBarView.swift`：打开主窗口与退出，不承载工作流（S12）。

反模式: View 不做文件系统/Git/持久 IO；不引入分组标题与筛选 UI；行状态不聚合假状态（状态短语与五档排序归 #20）；「状态与检出」「相关记录」「更新动作」三块尚未接通，不提前占位实现；受限恢复态必须全窗口阻断，不允许部分可用。

测试锚点: repo://PaguguTests/AppModelTests.swift（投影渲染与 intent 路由 smoke）；视觉核对走 `script/build_and_run.sh`。
