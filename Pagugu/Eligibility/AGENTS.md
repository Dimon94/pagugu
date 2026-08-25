# Eligibility 模块合同（L2）

模块职责: owns 12 个互斥 Checkout Git State、ADR-0004 precedence、稳定 reason code、中文名与一句恢复方向。全部纯函数。does not own Git 调用、持久化、检查运行或 UI。

成员清单:
- `CheckoutEligibility.swift`：`CheckoutGitState` 与 `CheckoutEligibility.evaluate(facts:sourceKey:)`。

反模式: 不调用 Git；不从 UI、缓存或 App Registry 重建当前状态；不造来源级聚合状态。

测试锚点: repo://PaguguTests/GitEligibilityTests.swift（12 态与 precedence 表）。
