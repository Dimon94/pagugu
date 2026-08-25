# Runs 模块合同（L2）

模块职责: owns Check Run 的全量冻结 scope、顺序 fetch、身份复核、逐项发布与 complete/partial/failed 汇总。run 瞬态不持久。

成员清单:
- `CheckRun.swift`：`CheckRunner.startCheck(scope:)`、稳定失败码与 Check Run 事件值类型。

依赖: Git、Eligibility、Registry。does not own Git 裁决、观察槽物理 IO、UI 投影或第二把互斥锁。

反模式: 不持久 run；不新增局部检查；不移动工作树或本地 branch；不在身份变化后落槽。

测试锚点: repo://PaguguTests/CheckRunTests.swift。
