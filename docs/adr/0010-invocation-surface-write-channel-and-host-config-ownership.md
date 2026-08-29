# 调用面写通道与宿主配置所有权

Status: accepted

Related: repo://CONTEXT.md、repo://docs/adr/0002-skill-source-mapping.md、repo://docs/adr/0007-audit-evidence-and-recovery-presentation.md、repo://docs/adr/0008-app-registry-persistence-contract.md

## Context

调用面调控要求 Pagugu 修改 Agent Host 的配置文件：Claude Code 的 settings.json（`skillOverrides`，四档：`on` / `name-only` / `user-invocable-only` / `off`，v2.1.129+）与 Codex 的 `~/.codex/config.toml`（`[[skills.config]] enabled = false`，仅全禁用；「仅显式」通道 `allow_implicit_invocation` 文档与 issue 相互矛盾，标 Unknown 不做）。这些 schema 当前来自搜索合成，实现前必须对官方文档原文核实。

宿主配置文件是共享所有权：用户会手改，宿主自己会重写。Pagugu 的可见性主张与文件事实可能分歧。需要裁决写入方式、原始配置保全、恢复能力与冲突语义。Pi 侧不写宿主配置，见 repo://docs/adr/0011-pagugu-owned-pi-extension.md。

## Decision

### 1. 结构化合并写入是底线

Pagugu 只增删自己负责的 key（如 `skillOverrides` 中由 Pagugu 写入的条目），文件中所有未知 key 与其他配置原样保留。被否决：整文件重写（丢失用户与宿主写入的内容）。

### 2. 单槽备份与单动作恢复（初步版本）

每次写入前把目标文件完整复制为单槽备份（每文件只保留最近一份）。每个宿主配置提供一个「恢复到 Pagugu 写入前」的 UI 动作，不做备份列表浏览与逐快照挑选。初步版本刻意从简；未来扩为多份 FIFO 是纯加法，不破坏合同。

### 3. 文件事实优先，分歧只呈现不覆盖

可见性主张与文件事实分歧时（用户手改或宿主重写导致），Pagugu 检测并呈现「主张与当前配置不一致」，不静默覆盖、不自动重应用。用户显式选择「重新应用主张」或「放弃主张」。失效语义复用 ADR-0002 失效映射：事实优先、标注保留、不静默删除。被否决：主张优先自动写回（与用户和宿主抢文件）；后写者赢（UI 呈现假状态）。与 Registry 外部修改检测、审计「永不充当自动恢复依据」同构。

### 4. 能力缺口 fail closed

宿主不支持某调用面档位时，该档写入口禁用并标注原因（如「Codex 不支持仅显式」）；绝不静默降级为其他档位（如用「全禁用」冒充「仅显式」）。Unknown 通道不实现。Codex 将来证实新通道时为其 Host Profile 加档，是纯加法。

### 5. 可见性主张是 App Registry 的第四类 owns

分歧检测与「重新应用主张」要求主张持久化。可见性主张集合（Skill × Agent Host × 调用面档位）按 ADR-0008 §2 的扩展条款引入字段并 bump schema version。主张记录形状与 Registry 既有风格一致：零时间戳、零派生标志位，有效性每次读取时由文件事实派生。Pi 侧例外：主张的 canonical 是 Pagugu 独占文件本身，不入 Registry（ADR-0011 §2）。

### 6. 永不写 Skill 内容

调用面调控不修改 SKILL.md 或任何 Skill Source 内容。需要改 frontmatter 才能达到的效果（如 `disable-model-invocation`）一律不做或只给操作指引：写 Skill 内容会让检出变 dirty，腐蚀 ADR-0004 的 12 态更新裁决基础。

## Consequences

### 正面

- 用户获得跨 Agent Host 统一的调用面控制，分歧可解释、误操作可恢复。
- 能力缺口显式可见，为宿主侧能力演进留出加法路径。

### 负面 / 成本

- Pagugu 首次获得对宿主配置的写 seam；每个宿主的写入器需要合并写、备份、分歧检测三个部件。
- Registry schema 需要版本迁移路径（ADR-0008 的未知未来版本不覆写原则不变）。

### 边界

- 本 ADR 冻结：合并写底线、单槽备份与单动作恢复、文件事实优先、能力缺口 fail closed、Registry 第四类 owns、不写 Skill 内容。
- 不裁决：UI 形态、各宿主写入器实现细节、备份文件的具体命名与位置（归后续票据）。
- 配置 schema 未对官方原文核实前，写通道实现不得开工；只读呈现不受此限。宿主未来变更配置 schema 时立新 ADR supersede 本记录。
