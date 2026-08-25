# Identity 模块合同（L2）

模块职责: owns Skill Source Key 规范化、HostAttribution 归因表、Projection Type 派生、按 Skill Identity 聚合 Installation、按 Skill Source 分组目录（Variant F：来源仓库行 + 无仓库可归行）、复制投影按内容指纹聚合呈现组。全部纯函数、零副作用。does not own 文件系统遍历（归 Discovery）、Git 子进程、UI 呈现。

成员清单:
- `SkillIdentity.swift`：`SkillSourceKey`（含 `normalize(remoteURL:)` 与 `displayString`）、`SkillIdentity`。
- `AgentHost.swift`：`AgentHost`（claude/codex）、`HostAttribution` 归因表。
- `SkillDirectoryEntry.swift`：`ProjectionType`、`SkillInstallation`（含逐安装 canonicalPath）、`SkillDirectoryEntry`（canonical 条目）、`SkillSourceItem`（来源仓库行）、`UnattributedInstallationItem`（无仓库可归行/呈现组）、`SkillDirectoryContents`。
- `SkillDirectory.swift`：`SkillDirectory.contents(from:)` 分组入口。

反模式: 不读文件系统、不调用 Git；frontmatter `name` 与安装目录名不参与身份；复制投影不做启发式自动归因；复制投影只按内容指纹聚合呈现组——禁止只按名称合并，指纹缺失（读取不完整）不合并，零安装的纯来源发现永不合并（ADR-0001 §4，#16 修正；安装产生规则归 #18：Personal Root 入口或带宿主归因才产生 Installation）。

测试锚点: repo://PaguguTests/IdentityTests.swift（Source Key 规范化表、宿主归因表、目录分组聚合表、指纹聚合表）。
