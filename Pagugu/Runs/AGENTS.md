# Runs 模块合同（L2）

模块职责: owns Check Run 的全量冻结 scope、顺序 fetch、身份复核、逐项发布与汇总；owns Update Run 两段式成功路径（fetch 重查、精确 SHA 计划、确认后漂移比对、ff-only、post-verify 与最终 up-to-date 裁决）及对应审计调用。run 瞬态不持久。

成员清单:
- `CheckRun.swift`：`CheckRunner.startCheck(scope:)`、`UpdateRunner.prepareUpdate(request:)`、`executeConfirmed(_:)`、`UpdatePlan` 与两类 run 的事件/结果值类型。

依赖: Git、Eligibility、Registry、Audit。does not own Git 裁决、观察/审计物理 IO、UI 投影或第二把互斥锁。

反模式: 不持久 run；不新增局部检查；UpdatePlan 之外不保存当次目标；不按 ref 合并或移动其他检出；不在身份漂移后执行；不自动重试、回滚、reset、force、stash 或 checkout。失败九类、取消与互斥归 #24。

测试锚点: repo://PaguguTests/CheckRunTests.swift（含零网络 scratch Update Run 成功路径）。
