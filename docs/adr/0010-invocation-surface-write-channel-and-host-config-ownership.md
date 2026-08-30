# 调用面写通道与宿主配置所有权

Status: accepted

Related: repo://CONTEXT.md、repo://docs/adr/0002-skill-source-mapping.md、repo://docs/adr/0007-audit-evidence-and-recovery-presentation.md、repo://docs/adr/0008-app-registry-persistence-contract.md

## Context

调用面调控要求 Pagugu 修改 Agent Host 的配置文件：Claude Code 的 settings.json（`skillOverrides`，四档：`on` / `name-only` / `user-invocable-only` / `off`，v2.1.129+）与 Codex 的用户级 `~/.codex/config.toml`（`[[skills.config]] enabled = false`，全禁用）及用户级 `~/.codex/agents/openai.yaml`（`policy.allow_implicit_invocation = false`，仅显式）。Codex 两条字段 schema 已由官方 Agent Skills 文档核实；具体用户级写入位置由后续 Ticket #55 在“不写 Skill 内容”边界内裁决。Claude `skillOverrides` 已由官方 Claude Code Skills 文档核实。写通道仍必须保持本 ADR 的结构化合并与保全约束。

宿主配置文件是共享所有权：用户会手改，宿主自己会重写。Pagugu 的可见性主张与文件事实可能分歧。需要裁决写入方式、原始配置保全、恢复能力与冲突语义。Pi 侧不写宿主配置，见 repo://docs/adr/0011-pagugu-owned-pi-extension.md。

## Decision

### 1. 结构化合并写入是底线

Pagugu 只增删自己负责的 key（如 `skillOverrides` 中由 Pagugu 写入的条目），文件中所有未知 key 与其他配置值保持不变。JSON 通道使用类型安全的完整结构解析与单 key-path 合并；提交前重读并与最初字节比对，漂移即 fail closed，不生成备份、不覆写；未漂移才原子替换目标。不承诺保留空白、缩进或 key 顺序等非语义格式。被否决：由具体宿主 adapter 构造并整文件覆盖配置（丢失用户与宿主写入的内容）。

### 2. 单槽备份与单动作恢复

每次写入前把目标文件完整字节原子覆盖到 `<file>.pagugu-backup`（每文件只保留最近一份），再原子替换目标。恢复底层入口把该备份完整覆盖回目标文件并保留备份本身；每个宿主配置后续提供一个「恢复到 Pagugu 写入前」的 UI 动作，不做备份列表浏览与逐快照挑选。初步版本刻意从简；未来扩为多份 FIFO 是纯加法，不破坏合同。

### 3. 文件事实优先，分歧只呈现不覆盖

可见性主张与文件事实分歧时（用户手改或宿主重写导致），Pagugu 检测并呈现「主张与当前配置不一致」，不静默覆盖、不自动重应用。用户显式选择「重新应用主张」或「放弃主张」。失效语义复用 ADR-0002 失效映射：事实优先、标注保留、不静默删除。被否决：主张优先自动写回（与用户和宿主抢文件）；后写者赢（UI 呈现假状态）。与 Registry 外部修改检测、审计「永不充当自动恢复依据」同构。

### 4. 能力缺口 fail closed

宿主不支持某调用面档位时，该档写入口禁用并标注原因（如 Codex 与 Pi 不支持「降级曝光」）；Registry mutation 与 v2 schema 校验也拒绝不受支持的主张，绝不静默降级为其他档位（如用「全禁用」冒充「仅显式」）。当前 Host Profile：Claude Code 支持四档；Codex 支持完全暴露、仅显式、全禁用；ADR-0011 spike 已验证 Pi 扩展可阻断显式调用，因此 Pi 支持完全暴露、仅显式、全禁用，只不支持降级曝光。

### 5. 可见性主张是 App Registry 的第四类 owns

分歧检测与「重新应用主张」要求主张持久化。可见性主张集合（Skill × Agent Host × 调用面档位）已按 ADR-0008 §2 扩展为 Registry v2 的 `visibilityClaims`。主张记录形状与 Registry 既有风格一致：零时间戳、零派生标志位；同一 Skill Identity × Agent Host 至多一条，档位变化原位替换；有效性与分歧每次读取时由文件事实派生。Pi 侧例外：主张的 canonical 是 Pagugu 独占文件本身，不入 Registry（ADR-0011 §2）。

### 6. 永不写 Skill 内容

调用面调控不修改 SKILL.md 或任何 Skill Source 内容。需要改 frontmatter 才能达到的效果（如 `disable-model-invocation`）一律不做或只给操作指引：写 Skill 内容会让检出变 dirty，腐蚀 ADR-0004 的 12 态更新裁决基础。

## Consequences

### 正面

- 用户获得跨 Agent Host 统一的调用面控制，分歧可解释、误操作可恢复。
- 能力缺口显式可见，为宿主侧能力演进留出加法路径。

### 负面 / 成本

- Pagugu 首次获得对宿主配置的写 seam；通用 JSON 核心集中合并写、备份、恢复与分歧检测，具体宿主 adapter 仍需提供档位映射。
- Registry 已升级至 v2 并提供严格 v1→v2 迁移；ADR-0008 的未知未来版本不覆写原则不变。

### 边界

- 本 ADR 冻结：合并写底线、`<file>.pagugu-backup` 单槽备份与单动作恢复、文件事实优先、能力缺口 fail closed、Registry 第四类 owns、不写 Skill 内容。
- 不裁决：UI 形态，以及 Claude/Codex/Pi 的具体档位映射与非 JSON 格式保全实现（归后续票据）。
- 宿主未来变更配置 schema 时立新 ADR supersede 本记录；写通道必须基于实现时的官方合同继续核实保格式修改边界。
