# 主窗口 UI 打磨评审（#28）

Status: evidence-complete，存在已知验收失败（2026-08-26）

Mode: `full`。Scope: Variant F 主窗口（目录、详情、结果区横幅、更新确认 / 扫描范围 / 来源映射 / 最近活动 sheet、欢迎与空态、Registry 受限恢复）。Stack: 原生 SwiftUI、macOS 14+、系统动态语义色。ChunUI 不引入（repo://docs/product/chunui-compatibility.md）。边界：不做主窗口筛选 UI、不做完整可及性审计、不做多语言本地化；IA 语义与中文文案冻结。评审顺序按 better-interface：Accessibility → Layout → Writing → Typography → Colors → UI。

## Scope and Coverage

| Domain | Evidence inspected | Result |
| --- | --- | --- |
| Accessibility | 目录 chevron、横幅关闭、宿主 logo 槽位、删除/映射 icon-only、禁用「更新…」help、sheet 显式关闭；源码 + 启动主窗口 | Clear（完整 VoiceOver 走查不在范围） |
| Layout | `ContentView` 目录密度、详情 `Space.section=16` 对 `Space.block=8`、结果区与详情分界、sheet 内边距 | Clear |
| Writing | 中文按钮「更新…」「确认更新」「关闭」、空态下一步、失败恢复方向；不改冻结合同文案 | Clear |
| Typography | `DesignTokens.Fonts` 梯度；标题 tail / 路径 middle / 横幅不截断；进度 `monospacedDigit` | Clear |
| Colors | `DesignTokens.Status` 系统动态色；状态名+图标+文案并存；明暗随系统色 | Clear |
| UI | 令牌消费、卡片材质 vs 横幅状态描边、按压 0.96、无高频自定义动画 | Clear |

## Findings

No actionable visual interface findings. S2、S4-S8、S10-S11 仍有合同失败，见 Verification；本记录不把 sibling 修复票的已知缺陷改写成视觉通过。

HIGH 视觉发现已清零。打磨过程中已处理：逐组件手写字号/间距改为令牌；详情块 `Divider` 与 `Space.section` 叠加改为只靠 2× 间距分组；宿主 logo 由透明度改为实心/描边双提示并提供组合无障碍标签；按压在 Reduce Motion 下改透明度、取消缩放动画。

## Considered but Rejected

| Location | Candidate | Rejected because |
| --- | --- | --- |
| SPM / 工程依赖 | 引入 liseami/ChunUI 组件与令牌 | #27 编译级验证失败；源码依赖 UIKit。见 repo://docs/product/chunui-compatibility.md |
| `DesignTokens.Status` | 自建 OKLCH 色板替换系统 `.green/.orange/.red/.blue` | 项目无自有色板；系统动态色已覆盖明暗两态；完整对比度审计不在范围 |
| `Radius.card` vs `Radius.inset` | 强迫 `card = inset + padding` 或落地未消费的 `concentric` helper | 两枚半径用于兄弟表面（卡片 vs SKILL.md 块），并非嵌套；better-ui 允许独立表面自选半径。嵌套圆角出现时再按 outer = inner + padding 计算 |
| `Size.disclosureHotspot` 18pt | 一律抬到 24×24 或 44×44 | 票排除完整可及性审计；18pt 独立热区来自冻结原型，抬升会改目录密度 |
| `MarkdownSourceBlock` | 长文 `65ch` 行宽帽 | SKILL.md 是只读证据，不是正文阅读面；截断或窄列会藏合同文本 |
| 成功/失败色 | 按中文金融习惯对调绿/红 | Pagugu 不是涨跌界面；绿=通路/成功、红=失败与现有中文文案一致 |

## Verification

### 环境与方法

- 基线：`f8603555d25ec690bd92dc4477bb0479183db204`；macOS 26.5.1（25F80）、arm64、3024×1964 Retina 显示器。
- App 通过 `CFFIXED_USER_HOME=/tmp/pagugu-issue34-evidence/home` 使用隔离 Registry；没有读写用户的真实 Application Support。fixture 包含：空 Registry、来源不明复制 Installation、一个可更新 `file://` scratch remote、一个 Project `.codex/skills` 反例、一个含 1000 个合法 Skill 的本地 Git 来源。
- 人工路径：真实 App 窗口 + macOS Accessibility action。截图位于 `/tmp/pagugu-issue34-evidence/screens/`；16 张明暗截图的 SHA-256 清单位于 `/tmp/pagugu-issue34-evidence/logs/screens.sha256`。这些是一次性运行证据，不进入仓库。
- 自动验证：`xcodebuild test -project Pagugu.xcodeproj -scheme Pagugu -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO`：142 tests passed。`script/build_and_run.sh --verify`：build succeeded，进程存活。
- 源码核对：目录、详情、结果区和 sheet 的视觉常量均指向 `DesignTokens`；高频路径无自定义 enter/stagger；状态变化均有颜色+图标或文案。

复跑步骤（一次性文件可删除；命令会重建隔离数据）：

```bash
E=/tmp/pagugu-issue34-evidence
APP="$PWD/.build/DerivedData/Build/Products/Debug/Pagugu.app/Contents/MacOS/Pagugu"
rm -rf "$E" && mkdir -p "$E/home/.claude/skills/copied-skill" "$E/projects/large-source/skills" "$E/screens" "$E/logs"
printf '%s\n' '---' 'name: copied-skill' 'description: copied fixture' '---' > "$E/home/.claude/skills/copied-skill/SKILL.md"
git -C "$E/projects/large-source" init -q
for i in $(seq -w 1 1000); do
  d="$E/projects/large-source/skills/skill-$i"; mkdir -p "$d"
  printf '%s\n' '---' "name: scale-skill-$i" 'description: scale fixture' '---' > "$d/SKILL.md"
done
mkdir -p "$E/projects/project-codex/.codex/skills/project-only"
printf '%s\n' '---' 'name: project-codex-unknown-host' 'description: host fixture' '---' > "$E/projects/project-codex/.codex/skills/project-only/SKILL.md"
git -C "$E/projects/large-source" -c user.name=Evidence -c user.email=evidence@example.invalid add skills
git -C "$E/projects/large-source" -c user.name=Evidence -c user.email=evidence@example.invalid commit -qm fixture
D="$E/home/Library/Application Support/com.dimon.pagugu"; mkdir -p "$D"
python3 - <<'PY'
from pathlib import Path
import json
root = '/tmp/pagugu-issue34-evidence/projects'
doc = {'schemaVersion': 1, 'projectScanRoots': [{'canonicalPath': root, 'asFoundPath': root}], 'sourceMappings': {}, 'checkoutObservations': {}}
Path('/tmp/pagugu-issue34-evidence/home/Library/Application Support/com.dimon.pagugu/registry.json').write_text(json.dumps(doc))
PY
CFFIXED_USER_HOME="$E/home" "$APP" > "$E/logs/app.log" 2>&1 &
find "$E/projects/large-source/skills" -name SKILL.md | wc -l
```

在该隔离窗口依次执行「检查更新 → 更新… → 重查并确认 → 取消 → 最近活动」，并打开「扫描范围」与来源不明行的「来源映射」。切换 Appearance 后以 `screencapture -x -l "$WINDOW_ID"` 保存同态明暗 pair；`WINDOW_ID` 取自 `CGWindowListCopyWindowInfo` 中该隔离 PID 的主窗口。截图完成后运行 `shasum -a 256 "$E"/screens/*.png > "$E/logs/screens.sha256"`。滚动核对把主目录 `AXScrollArea` 的 vertical scrollbar `AXValue` 依次设为 `0`、`1`，循环五次并用 `ps -o pid,rss,%cpu,etime -p "$PID"` 记录 RSS 与存活。受限恢复用第二个 `CFFIXED_USER_HOME`，在启动前写入损坏的 `registry.json`。可更新 scratch remote 复跑则沿用测试入口 `CheckRunTests.testUpdateRunScratchSuccessBindsExactPlanFastForwardsOneCheckoutAndWritesTwoAuditRecords` 的 `file://` 仓库搭建方式。

### S1-S12 逐条结论

| Scenario | Verdict | 人工 / 冒烟证据与已知缺陷 |
| --- | --- | --- |
| S1 | Pass | 隔离空 Registry 显示欢迎与空目录；合法 Project Scan Root 加载成功。`AppModelTests.testStartWithEmptyRootsProducesEmptyReadModel`、Project Scan Root CRUD 与四类 guardrail 测试通过。 |
| S2 | Fail | 仓库行、子 Skill、来源不明行与同名分隔均可见；但 Project Scan Root 下 `.codex/skills` 的 AX 输出为「Claude未安装，Codex已安装」，错误点亮 Codex。精确修复票：#43。 |
| S3 | Pass | 目录实测显示 `update-available`、`no-remote` 与恢复方向；`GitEligibilityTests.testRealGitScratchRepositoriesReachAllTwelveStates` 覆盖 12 态，中文名/恢复方向与五档静默排序测试通过。 |
| S4 | Fail | 真实手动检查完成为「成功 1 · 失败 0 · 不适用 1」，结果横幅与审计记录可见；但 denylist/深度截断、非法 frontmatter、损坏软链接的 Scan Issue 合同仍失败。精确修复票：#37、#38、#39。 |
| S5 | Fail | scratch update 成功路径测试通过；真实确认页显示 Skill、检出、branch/upstream、behind 与影响声明，但 HEAD/target 只显示 7 位，不能确认精确 SHA。精确修复票：#35。 |
| S6 | Fail | noop 编排测试通过；重查后旧 `update-available` 仍可能留在卡片。精确修复票：#36。 |
| S7 | Fail | 真实确认页取消后出现后果横幅和 cancelled 审计；卡片实测仍为「可更新」，没有回到「尚未检查」。精确修复票：#42。 |
| S8 | Fail | 九类失败名与恢复方向表测试通过；fast-forward 失败后重查命中 dirty 时仍可能错误归为 `command-failure`。精确修复票：#33；失败后旧资格发布缺口见 #36。 |
| S9 | Pass | 真实来源映射 sheet 显示筛选、按来源分组、名称差异警告、显式关闭；映射创建、失效、复活与删除测试通过。 |
| S10 | Fail | 损坏 Registry 实测进入全窗口受限恢复，显示 quarantine 路径、重置与退出；兼容矩阵、last-good、确认重置测试通过。但 schema 边界仍宽松，且重置会吞未分类错误。精确修复票：#31、#32。 |
| S11 | Fail | 真实最近活动 sheet 显示检查与取消记录、完整历史 SHA、「当时记录」、清空与显式关闭；但已存在且不可读的审计文件可能伪装为空历史，未知失败 reason 可能静默消失。精确修复票：#40、#41。 |
| S12 | Pass | 真实 MenuBarExtra AX 树只有「打开 Pagugu」与「退出 Pagugu」两个 MenuItem；`MenuBarView` 未承载检查、更新或映射工作流。 |

### 明暗两态逐屏像素核对

在同一真实状态下切换系统 Appearance。逐对检查文本、图标、状态色、描边、材质、层级、截断和关闭动作。16 张截图均非空，明暗 pair 的 SHA-256 均不同。

| Surface | 明色 / 深色证据 | Verdict |
| --- | --- | --- |
| 欢迎与空态 | `light-welcome-empty.png` / `dark-welcome-empty.png` | Pass：标题、说明、空态图标与主按钮均可辨。 |
| 目录 | `light-directory-large-bottom.png` / `dark-directory-detail-large-bottom.png` | Pass：1000 行末段、选中行、仓库层级、宿主槽位与状态短语均可辨。 |
| 详情 | `light-directory-large-bottom.png` / `dark-directory-detail-large-bottom.png` | Pass：状态卡、路径、Git Fact、SKILL.md 与更新区层级清楚；长路径采用既定 middle truncation。 |
| 结果区 | `light-result-area-check-summary.png` / `dark-result-area-check-summary.png` | Pass：成功色、checkmark、完整文案与关闭图标并存。 |
| 更新确认 sheet | `light-sheet-update-confirmation.png` / `dark-sheet-update-confirmation.png` | Pass（视觉）；当前 7 位 SHA 是 S5 合同 Fail，归 #35，不冒充视觉问题。 |
| 扫描范围 sheet | `light-sheet-scan-range.png` / `dark-sheet-scan-range.png` | Pass：路径、删除次要动作、影响说明、添加按钮与显式关闭均可辨。 |
| 来源映射 sheet | `light-sheet-mapping.png` / `dark-sheet-mapping.png` | Pass：筛选框、来源组、行分隔、警告色与显式关闭均可辨。 |
| 最近活动 sheet | `light-sheet-recent-activity.png` / `dark-sheet-recent-activity.png` | Pass：选中态、结果色、历史详情、清空次要动作与显式关闭均可辨。 |
| Registry 受限恢复 | `light-restricted-recovery.png` / `dark-restricted-recovery.png` | Pass：阻断层级、quarantine 路径和两个恢复动作均可辨。 |

### 1000 条目滚动运行证据

- fixture 计数：`find .../large-source/skills -name SKILL.md` = 1000。
- 真实窗口从 `scale-skill-0001` 滚到 `scale-skill-1000`，末行进入可见区并加载详情；再执行 5 轮 top → bottom。Accessibility 滚动动作每次 0.06-0.53 秒，进程全程存活。
- 五轮前后 RSS：93,808 KB → 108,896 KB（+15,088 KB）；没有崩溃、空白行、层级错位或滚动后选择错绑。运行日志：`/tmp/pagugu-issue34-evidence/logs/large-scroll-runtime.txt`。
- 结论：Pass。这里记录真实 1000 条运行结果，不用框架实现推断替代运行证据。

### 证据完整性检查

下列最小检查在首次补文档前因缺少 S1-S12 verdict row 而失败；加强后又先因详情行未显式列出明暗 pair 而失败，补齐后通过。它要求每个场景恰好出现一次、Verdict 只能是 Pass/Fail、Fail 必须引用 ticket、九个界面均有显式明暗截图，并核对 1000 条运行标记。

```bash
python3 - <<'PY'
from pathlib import Path
import re

text = Path('docs/product/ui-polish-review.md').read_text()
placeholder = 'Not ' + 'verified'
assert placeholder not in text, 'placeholder remains'

scenario_text = text.split('### S1-S12 逐条结论', 1)[1].split('### 明暗两态逐屏像素核对', 1)[0]
scenario_rows = re.findall(r'^\| (S\d+) \| (Pass|Fail) \| (.+) \|$', scenario_text, re.M)
assert len(scenario_rows) == 12, f'expected 12 scenario rows, got {len(scenario_rows)}'
assert {name for name, _, _ in scenario_rows} == {f'S{i}' for i in range(1, 13)}
for name, verdict, evidence in scenario_rows:
    if verdict == 'Fail':
        assert re.search(r'#\d+', evidence), f'{name} Fail lacks sibling ticket'

visual_text = text.split('### 明暗两态逐屏像素核对', 1)[1].split('### 1000 条目滚动运行证据', 1)[0]
visual_rows = re.findall(r'^\| ([^|]+) \| ([^|]+) \| (Pass[^|]*) \|$', visual_text, re.M)
required = {'欢迎与空态', '目录', '详情', '结果区', '更新确认 sheet', '扫描范围 sheet', '来源映射 sheet', '最近活动 sheet', 'Registry 受限恢复'}
assert {name.strip() for name, _, _ in visual_rows} == required
for name, evidence, _ in visual_rows:
    assert evidence.count('.png') >= 2 and 'light-' in evidence and 'dark-' in evidence, f'{name.strip()} lacks explicit light/dark pair'

scale_text = text.split('### 1000 条目滚动运行证据', 1)[1].split('### 证据完整性检查', 1)[0]
for marker in ['= 1000', 'scale-skill-1000', '5 轮', 'RSS', '进程全程存活']:
    assert marker in scale_text, f'missing scale marker: {marker}'
print('ui evidence completeness: PASS')
PY
```

## Verdict

Request changes：视觉核对与大规模滚动通过；S2、S4-S8、S10-S11 仍 Fail，按表中 sibling ticket 修复后复验。
