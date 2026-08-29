# Identity 模块合同（L2）

模块职责: owns Skill Source Key 规范化、Projection Type 派生、人工来源映射重验证、按 Skill Identity 聚合 Installation、按 Skill Source 分组目录、同一 Source Key 多检出保留、复制投影按内容指纹聚合呈现组。它消费 HostProfile 的宿主归因，并在逐 Installation 上保留 Personal/Project scope。全部纯函数、零副作用。does not own 宿主规则或同名冲突诊断（归 HostProfile）、文件系统遍历（归 Discovery）、Registry 写入、Git 子进程、Checkout Git State 或 UI 呈现。

成员清单:
- `SkillIdentity.swift`：`SkillSourceKey`、`SkillIdentity`、`SourceMappingEvaluator`。
- `SkillDirectoryEntry.swift`：`ProjectionType`、`SkillInstallation`（含逐安装 canonicalPath 与 Personal/Project scope）、`SkillDirectoryEntry`、`SkillSourceCheckout`、`CheckoutSkillInventory`、`SkillSourceItem`、`UnattributedInstallationItem`、`SkillDirectoryContents`；每个物理检出的 Skill 成员清单单独保留。
- `SkillDirectory.swift`：`SkillDirectory.contents(from:gitFactsByCheckoutPath:mappings:)` 分组与映射投影入口；有效 origin 升级为规范化 remote key，否则保留 canonical path key。

反模式: 不读文件系统、不调用 Git；不复制 HostProfile 归因规则；frontmatter `name`、安装目录名与同名共存组不参与身份；复制投影不做启发式自动归因；人工映射键只能是具体 Installation canonical path，不能是名称、内容指纹或呈现组；失效记录不静默删除，部分扫描不判失效；复制投影只按内容指纹聚合呈现组——禁止只按名称合并，指纹缺失（读取不完整）不合并，零安装的纯来源发现永不合并（ADR-0001 §4，#16 修正；安装产生规则归 #18：Personal Root 入口或带宿主归因才产生 Installation）。

测试锚点: repo://PaguguTests/IdentityTests.swift（Source Key 规范化表、HostProfile 归因接线、目录分组聚合表、指纹聚合表）。
