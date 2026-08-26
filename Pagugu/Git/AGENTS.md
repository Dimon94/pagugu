# Git 模块合同（L2）

模块职责: owns 唯一 Git 子进程 seam、非交互环境、仓库 hook 屏蔽、单调时钟秒级 timeout、exit/stderr 与锁冲突原语的单次归一化、在途进程尽力终止及正交 `CheckoutGitFacts`；只读 inspection 同时读取本地 remote-tracking SHA。does not own Checkout Git State、九类失败、Eligible Update、检查运行或更新编排。

成员清单:
- `GitClient.swift`：`GitInspecting`、`GitExecuting.fetch(remote:upstreamRef:at:)`、`fastForward(to:at:)`、`terminateInFlight()`、`CheckoutGitFacts`、typed command error 与生产 `GitClient`；两个公开面共享唯一内部 runner，全部生产 Git 命令统一登记到同一在途进程表。fast-forward 只接受完整精确 SHA。

反模式: 不裁决业务状态；不读取 App Registry；不让第二个 `Process` runner 绕过本模块。

测试锚点: repo://PaguguTests/GitEligibilityTests.swift（真实 git + file:// scratch；覆盖 fetch/ff-only、锁冲突原语与在途进程终止；零外网）。
