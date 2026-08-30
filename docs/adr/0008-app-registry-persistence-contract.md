# App Registry 持久合同（Registry v2）

Status: accepted

Related: Dimon94/pagugu#8、Dimon94/pagugu#9、Dimon94/pagugu#10、Dimon94/pagugu#53、repo://docs/adr/0001-skill-identity.md、repo://docs/adr/0002-skill-source-mapping.md、repo://docs/adr/0003-skill-source-checkout-update-target.md、repo://docs/adr/0004-checkout-git-state-and-eligible-update.md、repo://docs/adr/0005-check-run-and-checkout-observation.md、repo://docs/adr/0006-update-run-execution-and-recovery.md、repo://docs/adr/0007-audit-evidence-and-recovery-presentation.md、repo://docs/adr/0010-invocation-surface-write-channel-and-host-config-ownership.md、repo://CONTEXT.md

## Context

MVP 1.0 需要把 App Registry 的持久边界落成稳定合同：物理位置、owns 清单、记录形状、JSON schema、版本兼容、迁移、损坏恢复、原子写、单写者、写失败、删除与重置。已锁定的事实锚点：人工来源映射是每次完整扫描重验证的主张、失效保留并自动复活（ADR-0002 §5、§7）；Checkout Observation 必须持久的内容为五项，freshness 完全派生、无 TTL（ADR-0005 §7、§10）；Check Run 与 Update Run 瞬态不持久（ADR-0005 §1、ADR-0006 §1）；不持久 sticky 更新目标（ADR-0003 §3、§4）；审计证据语义独立、append-only FIFO 200、损坏 fail-open（ADR-0007）；App Sandbox 关闭，签名与公证在地图 Out of scope。持久 schema 落盘即成为难回退合同；审计语义已由 ADR-0007 冻结，本 ADR 只裁决其物理持久边界，两者互不成为第二真相。

Foundation/macOS 事实锚点：`Data.write(.atomic)` 是同目录临时文件加 rename 的原子替换但不做 fsync；JSONDecoder 默认忽略未知键、缺失非可选键与类型不符均抛错；LaunchServices 默认单实例，但直接执行二进制可起第二实例；`flock` 仅为 advisory，挡不住不检查锁的编辑器。

## Decision

### 1. 物理位置与文件权限

App Registry 是单个本地 JSON：`~/Library/Application Support/com.dimon.pagugu/registry.json`，目录按需创建，文件权限 0600、目录权限 0700。被否决：自建隐藏目录（非原生约定）；按主张类型拆多个文件（扩大写面与并发面，无 MVP 需求）。

### 2. owns 清单恰好四类

Registry v2 中 App Registry 恰好拥有：Project Scan Root 集合、人工来源映射集合、逐 Skill Source Checkout 单槽上次观察结果、Visibility Claim 集合（ADR-0010 §5）。Visibility Claim 形状为 Skill Identity（`skillSourceKey` + `repositoryRelativePath`）× Agent Host × Exposure Level；零时间戳、零有效/分歧标志位，文件事实优先。「检查计划」不属于 owns：MVP 只有手动 Check Run（ADR-0005 §2），不存在任何计划实体；未来新增持久主张仍需新决策并 bump schema version。除四类外无任何其他当前用户选择持久化。

### 3. 明确不持久、不拥有

Scan Result 本体、Skill Read Model、Git Fact、Checkout Git State、Eligible Update 结论、freshness/validity/hasDivergence 标志位、宿主配置文件事实、run 聚合态、Check/Update 进行中状态、当次多检出人工选择、当前错误文案与原始输出、任何缓存、Skill 内容与 frontmatter、secrets、环境变量。以上全部由实时事实与持久输入确定性派生（ADR-0004 §1、ADR-0005 §10、ADR-0010 §3），落盘即第二真相。

### 4. 记录形状

- Project Scan Root：`{canonicalPath, asFoundPath}`，JSON 数组序即添加/显示顺序。可用性与合法性每次扫描实时派生，不落盘。路径不存在或被移动：记录保留、扫描时派生不可用、事实恢复自动复活、只能由用户显式删除；不做自动删除与移动追踪改写。被否决：持久可用性标志与 addedAt（派生态落盘即第二真相，时间戳无消费者）。
- 人工来源映射：键 `Installation Canonical Path` → `{skillSourceKey, repositoryRelativePath}`。零时间戳、零元数据（ADR-0002 §8 无映射历史）；有效/失效永不落盘（ADR-0002 §7 完全派生）。
- Checkout Observation：严格五项——`result`（success/failure）、`completedAt`、成功时 `remoteTipSHA`、身份摘要（Checkout Canonical Path、git 共同目录标识、规范化 remote URL、branch 名、upstream ref 名）。被否决：持久失败原因 code——fetch 类失败实测 exit 均为 128、子类不可分（ADR-0006 Context），单值 code 不携带超出 `result=failed` 的信息；原始 stderr 被敏感边界禁止（§16）。
- 访问语义：只存规范化绝对路径；不引入 security-scoped bookmark（沙箱关闭，未来启用时立新 ADR）、不复制用户文件、不缓存权限凭证。

### 5. 观察槽生命周期

新失败覆盖旧成功（ADR-0005 §6 不变）。检出暂时从完整 Scan Result 消失时槽保留：槽以 Checkout Canonical Path 为键自然休眠，重新发现且身份摘要匹配时按 freshness 合同重新生效，与失效映射保留-复活同构（ADR-0002 §7）。orphan 槽不自动清理；删除 Project Scan Root 不级联删观察；观察槽唯一删除途径是重置 App Registry；MVP 不提供逐槽删除。

### 6. 顶层最小 schema

```json
{
  "schemaVersion": 2,
  "projectScanRoots": [
    { "canonicalPath": "…", "asFoundPath": "…" }
  ],
  "sourceMappings": {
    "<Installation Canonical Path>": {
      "skillSourceKey": "…",
      "repositoryRelativePath": "…"
    }
  },
  "checkoutObservations": {
    "<Checkout Canonical Path>": {
      "result": "success | failure",
      "completedAt": "<RFC3339/ISO-8601 UTC>",
      "remoteTipSHA": "…（仅 result=success 时存在）",
      "identityDigest": {
        "checkoutCanonicalPath": "…",
        "gitCommonDirIdentifier": "…",
        "normalizedRemoteURL": "…",
        "branchName": "…",
        "upstreamRefName": "…"
      }
    }
  },
  "visibilityClaims": [
    {
      "skillSourceKey": "…",
      "repositoryRelativePath": "…",
      "host": "claude | codex",
      "exposureLevel": "fullyExposed | nameOnly | explicitOnly | fullyDisabled"
    }
  ]
}
```

键名为稳定英文 camelCase。`remoteTipSHA` 条件存在：success 必填、failure 缺席，解码器强制该配对。同一 Skill Identity × Agent Host 至多一条 Visibility Claim；数组序保持首次添加顺序，档位变化原位替换；Host Profile 不支持的档位拒绝持久化；Pi 按 ADR-0011 §2 不入 Registry。不引入 registry identity UUID（单文件无同步对象）、writtenAt/claim timestamp（无消费者）、有效或分歧标志位、checksum（完整性由 JSON 解析加严格字段校验承担，非对抗场景）。字段判据：每个字段都有冻结语义的消费者。

### 7. 版本与兼容矩阵

七种入口情形：① 缺文件：首次启动空 Registry，正常路径非错误；② 空文件、不可解析、结构校验失败：损坏路径（§9）；③ 已知旧版本：迁移路径（§8）；④ 未知未来版本：fail closed 受限恢复模式——不读主张、绝不写入、绝不静默降级覆写，仅允许升级 App 或显式重置（重置保留 quarantine）；⑤ 已知版本内必填字段缺失：校验失败，损坏路径；⑥ 未知字段：忽略，重写时不保留——配套不变量是同版本内只允许新增可安全丢弃的可选字段（§17）；⑦ 类型不符：校验失败，损坏路径。Registry 永不静默吞掉不理解的数据。

### 8. 迁移语义

v1 → v2 是唯一已知迁移：先按 v1 合同完整严格校验三类集合，在内存中纯转换并加入空 `visibilityClaims`，把原字节 durable 保留为 `registry.v1.pre-migration-<timestamp>.json`，再原子替换写入 v2；既有 Project Scan Root、来源映射与 Checkout Observation 全部保持。备份或替换任一步失败即 fail closed，不发布迁移后内存投影，原 registry.json 保持 last-good。每对版本转换必须是显式、独立测试的纯函数；未来新增转换按同一顺序实现。被否决：通用 migration framework（当前只有一对版本转换）。

### 9. 损坏恢复：fail closed + quarantine

Registry 是安全关键当前主张，不适用审计的 fail-open 丢弃。不可解析或校验失败时：原文件原子 rename 到同目录 quarantine（`registry.corrupt-<timestamp>.json`，权限保留；rename 失败则原位保留并呈现路径）；App 进入阻断式受限恢复模式，呈现 quarantine 路径与两个动作——「重置为空 Registry」（显式确认后写入空 v2，quarantine 永不自动删除）与「退出自行修复」（用户修复 quarantine 文件后放回原路径）。MVP 不做降级浏览：Registry 不可读时四类主张不可见，降级视图会静默呈现数据丢失假象，违反状态可解释。覆盖时机唯一：显式重置动作，绝不静默覆盖。被否决：fail-open 丢弃重建——静默丢弃用户主张，正是安全关键持久物不可接受的失败模式。

### 10. 原子写与 durable success

写路径固定：同目录唯一临时文件 → 完整编码 → 写入并 fsync 文件 → 原子 rename 到目标 → fsync 目录。写成功的最小可观察条件 = rename 完成且文件与目录 fsync 成功。不做常规读回校验（rename 加双 fsync 已是最小充分条件）。写频率是用户动作级，双 fsync 成本可忽略。

### 11. 单写者与并发

App 内单一内存 owner 串行执行全部 mutation（设置改动、观察落槽、重置），多窗口共享同一 owner；模块形状归 #9。run 侧互斥已由 ADR-0005 §9 与 ADR-0006 §7 覆盖，写侧由 owner 串行覆盖。第二实例与外部编辑检测：每次写前比对磁盘内容与本进程上次读/写的已知字节，不一致即 fail closed——动作失败，恢复动作是重启 App 重载或显式重置。不引入文件锁（advisory 锁挡不住编辑器，锁不是真相，与 ADR-0006 §7 同哲学）、文件 watcher 或跨进程分布式锁。

### 12. 写失败语义

磁盘是唯一 canonical，内存是 last-good 投影。动作流程：构造新文档 → durable write（§10）→ 仅成功后提交内存投影。写失败：内存投影从未应用（无需回滚）、磁盘 last-good 完好（原子写无撕裂）、动作向用户报告失败并给恢复指引（检查磁盘空间与目录权限后重试）；不降级为内存态、不静默重试。观察落槽失败则该观察不生效，检出按旧观察或从未检查处理。失败姿态严格分离：Registry 写失败 fail closed（动作失败）；Audit 写失败 fail open（动作照成，ADR-0007 §3）。

### 13. Registry 与 Audit 提交顺序

Registry 当前主张/观察 durable success 在先，Audit append best-effort 在后。Audit 失败永不回滚 Registry 或副作用，动作结果不变。两文件各自独立原子写，无联动回滚、无两阶段提交、无跨文件事务伪装。Update Run 开始记录在确认绑定时刻写（best-effort，失败不阻断执行），terminal 记录在动作终态写（ADR-0007 §3 不变）。

### 14. 审计集合的物理布局与格式

审计集合是同目录独立文件 `~/Library/Application Support/com.dimon.pagugu/audit-history.json`，权限 0600。不放入 registry.json 内独立顶层：Registry owns 清单不扩大（ADR-0007 §6）；损坏域互相隔离——审计损坏 fail-open 不影响 Registry，Registry quarantine 与重置不动审计文件。格式为单一 JSON 文档 `{ "schemaVersion": 1, "records": [ … ] }`，records 按追加顺序排列；append = 读 → 校验 → 追加 → 超 200 条淘汰最旧 → 整体原子重写（与 §10 同一写路径）。被否决：JSONL 追加加压实——200 条上限下整体重写成本可忽略，且无部分行与压实窗口等额外损坏模式，写路径与 Registry 零差异复用。版本兼容策略与 §7 相同；损坏即丢弃重建为空并呈现「历史不可用」（ADR-0007 §6）；清空 = 原子重写为空 records、无墓碑；记录写入后永不更新、合并或改写。

### 15. 删除与重置语义

删除 Project Scan Root 只删主张记录：随后扫描不再覆盖；其下映射仅在自身事实按 ADR-0002 §6 独立失效时失效保留，不级联删除；观察槽按 §5 保留。删除映射只删记录（ADR-0002 §8），Installation 回到 Unattributed Installation。重置 App Registry = 四类主张全清：显式确认与影响范围声明，执行前无条件 quarantine 当前文件（即使未损坏）并呈现备份路径，写入空 v2 后触发完整 Discovery Scan 重建只读投影；不可恢复项明确告知——Scan Root 列表、映射与 Visibility Claim 需人工重建，观察证据可经重新检查重建。清空 Audit Evidence 只清空审计集合（ADR-0007 §6）。全部删除与重置动作一律不触碰用户 Skill Source、Skill Installation、宿主配置或 Git 工作树。

### 16. 敏感与安全边界

持久内容仅为：路径、规范化 remote URL、SHA、Checkout Observation 与审计所需时间戳、branch/upstream 名、Agent Host 与 Exposure Level。Visibility Claim 不带时间戳。明确不落盘：宿主配置文件内容或事实、Skill 内容、frontmatter、secrets、环境变量、原始命令输出、hostname。Registry 与审计内容永不上传外部服务（与 ADR-0007 §5 同级姿态，无新增外发面）。

### 17. 格式演进不变量

同 schemaVersion 内只允许新增可安全忽略且可丢弃的可选字段；不改既有字段含义、不删字段、旧记录含义永不改写（与审计 append-only 同构）。破坏性变化必须 schemaVersion bump + 显式迁移函数（§8）+ 立新 ADR supersede 本记录相关小节。

### 18. 对 #9 的输出边界

一个物理持久 owner 拥有 registry.json 与 audit-history.json 的全部物理 IO：单写者、串行 mutation、原子写、quarantine、版本、v1→v2 迁移与兼容处理。语义 owner 分离：Registry 主张语义归 App Registry 能力，审计语义归审计能力（ADR-0007 §8 窄 append 入口，调用方传入已定型记录内容），两者共用唯一物理写路径；HostConfigWriter 只拥有宿主配置 IO，不得写 registry.json 或 audit-history.json。依赖方向单向：执行流程与设置动作 → 语义 owner → 物理持久 owner；持久层不依赖裁决、Git、扫描的内部状态。测试面：schema 校验、七情形兼容矩阵、显式 v1→v2 无损迁移、原子写与 durable 条件、quarantine、写失败 fail closed、外部修改检测、FIFO 200、审计损坏 fail open、清空/重置边界。本 ADR 不定义模块清单与 Swift public interface。

### 19. 对 #10 的输出边界

五条稳定用户语义：① 首次启动空 Registry 为正常态，无错误呈现；② Scan Root 不可用是派生呈现态，记录保留、可显式删除、恢复自动复活；③ 写失败：动作未成功、磁盘 last-good 完好、呈现恢复动作；④ 损坏与未知未来版本：受限恢复模式，呈现 quarantine 路径与「重置为空 / 退出自行修复」两动作，未来版本情形附加「升级 App」指引；⑤ 清空审计与重置 Registry：显式确认、影响范围声明与 quarantine 备份路径呈现。本 ADR 不定义布局、组件、颜色与图标。

## Consequences

### 正面

- Registry 在结构上不可能成为第二真相：owns 收窄为四类当前主张；Visibility Claim 不携带宿主文件事实或分歧，负面清单进入合同。
- 损坏、未知未来版本与外部修改全部 fail closed 且保留证据（quarantine/last-good）；审计 fail-open 与之严格不混。
- 一条原子写路径服务两个文件；无通用 framework、无锁、无 watcher、无推测扩展点。
- #9 与 #10 的接缝收窄为最小面：接缝合同加测试面清单、五条稳定用户语义。

### 负面 / 成本

- 阻断式恢复模式牺牲降级浏览：损坏后用户只能显式重置或退出自行修复。
- 写前内容比对不能防止「写后外部立刻再改」的竞态，只能在下一次写时检测；MVP 接受（advisory 锁同样挡不住编辑器）。
- 未知字段重写不保留要求未来同版本新增字段必须可丢弃，否则必须 bump version。
- 观察槽永不自动清理，orphan 随真实使用规模缓慢累积；MVP 以重置为唯一出口。

### 边界

本 ADR 冻结 App Registry 的物理位置、四类 owns 清单、Registry v2 记录形状、顶层 schema、版本兼容矩阵、v1→v2 迁移、损坏恢复、原子写与 durable 条件、单写者与并发检测、写失败语义、Registry/Audit 提交顺序、审计物理布局与格式、删除与重置语义、敏感边界、格式演进不变量，以及对 #9/#10 的输出。不裁决：模块清单、公开 interface 与依赖图（归 Dimon94/pagugu#9）；布局、组件、文案与完整交互原型（归 Dimon94/pagugu#10）；检查、观察、更新与审计的领域语义（ADR-0002/0005/0006/0007 已冻结，本 ADR 只做物理落地）；宿主配置写入与分歧语义（归 ADR-0010）。若未来引入 security-scoped bookmark、每日检查计划字段、TTL、sticky 检出偏好、通用 migration framework、文件锁或 watcher、观察历史槽、第五类 Registry owns 或把审计并入 Registry owns，需立新 ADR supersede 本记录相应小节。
