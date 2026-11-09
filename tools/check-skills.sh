#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------
# [L3][COORD] repo://tools/check-skills.sh
# [INPUT]  REQUIRED_SKILLS 清单；运行时 Skill 目录（环境变量可覆盖，见 [L5]）。
# [OUTPUT] 每个缺口一行，最后一行是汇总；全部就绪 exit 0，有缺口 exit 1。
# [POS]    本仓指针指向的用户级 Skill 的存在性检查。Skill 正文不复制进本仓，
#          缺了就明确失败，不让 agent 静默改用手工流程。
# [PROTOCOL] 变更时更新此头部、repo://tools/check-skills.test.sh 与 repo://tools/AGENTS.md
# ---------------------------------------------------------------------
# [L5] 清单与参数
# REQUIRED_SKILLS     本仓文档按名字指向、执行时必须可用的 Skill。新增指针时同步加名字。
# CLAUDE_SKILLS_DIR   默认 ~/.claude/skills（Claude Code）。
# AGENTS_SKILLS_DIR   默认 ~/.agents/skills（Codex、pi 等兼容运行时）。
#                     两个变量名与 my-skills 的 scripts/link-skills.sh 一致。
# [FAIL]  任一 Skill 在任一运行时目录缺 <name>/SKILL.md 即 exit 1。
# ---------------------------------------------------------------------
# 输出格式（合同，测试锁定）：
#   missing <name> in <dir>
#   fix: 在 my-skills 主目录运行 bash scripts/link-skills.sh
#   summary missing=<N>
# ---------------------------------------------------------------------

REQUIRED_SKILLS=(git-worktree principle-boundary-discipline)
DIRS=("${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}" "${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}")

missing=0
for dir in "${DIRS[@]}"; do
  for name in "${REQUIRED_SKILLS[@]}"; do
    [ -f "$dir/$name/SKILL.md" ] && continue
    printf 'missing %s in %s\n' "$name" "$dir"
    missing=$((missing + 1))
  done
done

[ "$missing" -gt 0 ] && echo 'fix: 在 my-skills 主目录运行 bash scripts/link-skills.sh'
echo "summary missing=$missing"
[ "$missing" -eq 0 ]
