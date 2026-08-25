# Views 模块合同（L2）

模块职责: 主窗口 Variant F IA 呈现（repo://docs/product/mvp-1.0-acceptance.md §2）。左侧平铺目录保持来源仓库行 + 子 Skill + 来源不明行，显示 AppModel 给出的逐态状态短语与五档静默顺序。右侧 Skill 详情呈现「状态与检出」、安装位置、来源标识、SKILL.md 原文；检出卡逐检出显示主状态、恢复方向与全部正交 Git Fact，不造来源级聚合状态。工具栏管理扫描范围；Registry 故障全窗口阻断接管。只消费 Skill Read Model、只发 AppModel intent。

成员清单:
- `ContentView.swift`：主从结构、目录行、详情四块、逐检出卡片、宿主 logo 槽位、扫描范围管理与受限恢复视图。
- `MenuBarView.swift`：打开主窗口与退出，不承载工作流（S12）。

反模式: View 不做文件系统/Git/持久 IO，不裁决 Checkout Git State 或重建目录排序；不引入分组标题与筛选 UI；行状态不聚合假状态；「相关记录」「更新动作」归后续票；受限恢复态必须全窗口阻断。

测试锚点: repo://PaguguTests/AppModelTests.swift（投影渲染与 intent 路由 smoke）；视觉核对走 `script/build_and_run.sh`。
