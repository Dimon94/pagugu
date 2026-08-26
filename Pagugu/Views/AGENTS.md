# Views 模块合同（L2）

模块职责: 主窗口 Variant F IA 呈现（repo://docs/product/mvp-1.0-acceptance.md §2）。左侧平铺目录保持来源仓库行 + 子 Skill + 来源不明/失效映射行，显示 AppModel 给出的逐态状态短语与五档静默顺序。右侧 Skill 详情呈现「状态与检出」、安装位置、来源标识、SKILL.md 原文；检出卡逐检出显示主状态、观察时间、检查结果、恢复方向与全部正交 Git Fact，不造来源级聚合状态。无仓库可归行逐 Installation 指定来源；映射目标 sheet 只列当前已发现 Skill，可筛选、不可自由输入；删除必须确认。工具栏提供唯一手动「检查更新」、进度/结果横幅、扫描范围管理与「最近活动」；Registry 故障全窗口阻断接管。只消费 Skill Read Model、只发 AppModel intent。

成员清单:
- `ContentView.swift`：主从结构、目录行、详情四块、逐检出卡片、宿主 logo 槽位、扫描范围管理、受限恢复视图与「最近活动」sheet（摘要列表 + 单条详情 + 清空确认；详情标注「当时记录」，失败不提供 stderr/命令复制/重试，只导航到相关 Skill；损坏呈现「历史不可用」；Registry 重置后呈现 quarantine 备份路径横幅）。
- `MenuBarView.swift`：打开主窗口与退出，不承载工作流（S12）。

反模式: View 不做文件系统/Git/持久 IO，不裁决 Checkout Git State、Check Run 结果或重建目录排序；不引入分组标题与主目录筛选 UI；不按呈现组批量创建映射；不允许自由输入目标或无确认删除；frontmatter name 不同只警告、不阻断；行状态不聚合假状态；「相关记录」「更新动作」归后续票；受限恢复态必须全窗口阻断；历史呈现不冒充当前实时状态，失败详情不提供一键重试。

测试锚点: repo://PaguguTests/AppModelTests.swift（投影渲染与 intent 路由 smoke）；视觉核对走 `script/build_and_run.sh`。
