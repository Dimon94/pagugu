# Git 模块合同（L2）

模块职责: owns 唯一 Git 子进程 seam、非交互环境、仓库 hook 屏蔽、单调时钟秒级 timeout、exit/stderr 单次归一化与正交 `CheckoutGitFacts`；只读 inspection 同时读取本地 remote-tracking SHA。does not own Checkout Git State、Eligible Update、检查运行或更新编排。

成员清单:
- `GitClient.swift`：`GitInspecting`、单 upstream 分支 `GitExecuting.fetch(remote:upstreamRef:at:)`、`CheckoutGitFacts`、typed command error 与生产 `GitClient`；两个公开面共享唯一内部 runner。

反模式: 不裁决业务状态；不读取 App Registry；不让第二个 `Process` runner 绕过本模块。

测试锚点: repo://PaguguTests/GitEligibilityTests.swift（真实 git + file:// scratch；覆盖 fetch 不改工作树和本地 branch；零外网）。
