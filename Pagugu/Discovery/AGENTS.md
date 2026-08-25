# Discovery 模块合同（L2）

模块职责: owns Discovery Scan：遍历 Scan Root、发现入口标注（DiscoveryOrigin）、软链接解析、Canonical Path 去重防环、SKILL.md 解析校验与原文读取、Git 工作树根检测（`.git` 存在性，纯文件系统事实）、复制投影内容指纹（SHA-256、确定性、fail closed）、Scan Issue。does not own 身份归因与指纹聚合（归 Identity）、Git 子进程（归 Git seam，#19）、持久化。

成员清单:
- `SkillDiscovery.swift`：`ScanOutcome`、`ScanIssue`、`DiscoveryOrigin`、`DiscoveredSkill`、`ScanResult` 值类型与 `Discovery` 命名空间。
- 公开入口：`Discovery.scanAll(personalRoots:projectRoots:)`、`scanPersonalRoots(_:)`、`scanProjectRoot(_:)`、`skillMarkdown(atCanonicalPath:)`、`contentFingerprint(ofSkillAtCanonicalPath:)`。
- 关键事实：`DiscoveredSkill.name` = frontmatter `name`（展示元数据）；`repositoryRootPath` = 最内层工作树根 canonical 路径（nil = 复制投影）；`ScanResult.candidateSourceRoots` 保留扫描中发现的 `.git` 工作树根，即使其 Skill 暂时为空；`contentFingerprint` 只为复制投影计算，覆盖全部常规文件的相对路径与字节，软链接只记目标字符串不跟随，读取不完整 = nil + Scan Issue（partial）；扫描不递归 `.git`；root 不存在 = 正常空态。

反模式: 不调用 git 子进程；不把 Scan Issue 当 Skill；不用缓存或上次观察替代实时遍历；不在 Discovery 做身份归因或指纹聚合；内容指纹永不用于来源归因；读取不完整不得产出可合并指纹。

测试锚点: repo://PaguguTests/DiscoveryTests.swift（临时目录 scratch：软链接、防环、工作树根检测、`.git` 不递归、内容指纹确定性与 fail closed、Scan Issue）。
