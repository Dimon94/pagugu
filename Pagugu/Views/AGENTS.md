# Views 模块合同（L2）

模块职责: 主窗口 Variant F IA 呈现（repo://docs/product/mvp-1.0-acceptance.md §2）。左侧平铺目录保持来源仓库行 + 子 Skill + 来源不明/失效映射行，显示 AppModel 给出的逐态状态短语与五档静默顺序。右侧 Skill 详情呈现「状态与检出」、安装位置、来源标识、SKILL.md 原文与「更新动作」；检出卡逐检出显示主状态、观察时间、检查结果、恢复方向与全部正交 Git Fact，不造来源级聚合状态。更新 intent 逐检出发起（仅 update-available 可用，其余禁用并给出原因），确认页列出精确计划与影响范围名单，多 Eligible 检出当次选择不持久化。结果区统一承载六类反馈（成功、noop、取消后果、写失败、刷新失败、检查总结），信息/警示分级、可关闭。无仓库可归行逐 Installation 指定来源；映射目标 sheet 只列当前已发现 Skill，可筛选、不可自由输入；删除必须确认。工具栏提供唯一手动「检查更新」、进度/结果横幅、扫描范围管理与「最近活动」；Registry 故障全窗口阻断接管。只消费 Skill Read Model、只发 AppModel intent。

成员清单:
- `DesignTokens.swift`：主窗口视觉令牌唯一来源（间距、圆角、尺寸、字号、语义状态色、表面材质、按压反馈）。目录、详情、结果区与 sheet 一律消费令牌；ChunUI 不引入（repo://docs/product/chunui-compatibility.md）。
- `ContentView.swift`：主从结构、目录行、详情五块、逐检出卡片（含「更新…」intent）、宿主 logo 槽位、结果区（六类反馈横幅）、更新确认 sheet（多检出当次选择 + 冻结计划确认）、扫描范围管理、受限恢复视图（「退出自行修复」只发 `AppModel.requestQuit`）与「最近活动」sheet（摘要列表 + 单条详情 + 清空确认；详情标注「当时记录」，失败不提供 stderr/命令复制/重试，只导航到相关 Skill；损坏呈现「历史不可用」；Registry 重置后呈现 quarantine 备份路径横幅）。
- `MenuBarView.swift`：打开主窗口与退出，不承载工作流（S12）。

反模式: View 不做文件系统/Git/持久 IO，受限恢复「退出自行修复」不直接 `NSApplication.shared.terminate`，不裁决 Checkout Git State、Check Run 结果或重建目录排序；不引入分组标题与主目录筛选 UI；不按呈现组批量创建映射；不允许自由输入目标或无确认删除；frontmatter name 不同只警告、不阻断；行状态不聚合假状态；「相关记录」经工具栏「最近活动」承载、不建第二处详情块；受限恢复态必须全窗口阻断；历史呈现不冒充当前实时状态，失败详情不提供一键重试；不逐组件手写与 DesignTokens 冲突的间距/圆角/字号/状态色；不引入 ChunUI。

测试锚点: repo://PaguguTests/AppModelTests.swift（投影渲染与 intent 路由 smoke）、repo://PaguguTests/PaguguTests.swift（ContentView 构造、受限恢复退出不直接 terminate、更新结果反馈 smoke、确认页完整 SHA、DesignTokens 按压/缩进/状态色）；视觉核对走 `script/build_and_run.sh` 与 repo://docs/product/ui-polish-review.md。
