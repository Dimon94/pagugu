#!/usr/bin/env bash
set -euo pipefail

# 锁定 check-skills.sh 的合同：依赖 Skill 在每个运行时目录都存在才通过；
# 缺一个就退出 1，并在输出里点名缺口和修复命令。夹具目录用临时目录，不碰真实运行时。

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-skills.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

install_skill() {
  mkdir -p "$TMP/$1/$2"
  : >"$TMP/$1/$2/SKILL.md"
}

# 清单从脚本自己的缺口报告读出，测试不重复维护清单
required() {
  run | sed -n "s|^missing \(.*\) in $TMP/claude\$|\1|p" || true
}

run() {
  CLAUDE_SKILLS_DIR="$TMP/claude" AGENTS_SKILLS_DIR="$TMP/agents" bash "$SCRIPT"
}

# 两个运行时目录都是空的：失败，点名缺口，给出修复命令
mkdir -p "$TMP/claude" "$TMP/agents"
names="$(required)"
grep -qx git-worktree <<<"$names" || fail "required list should include git-worktree: $names"
out="$(run)" && fail "empty runtime dirs should exit 1"
grep -q "missing git-worktree in $TMP/claude" <<<"$out" || fail "should name missing skill and dir: $out"
grep -q "link-skills.sh" <<<"$out" || fail "should print the fix command: $out"

# 只装进一个运行时：仍失败，只报另一个
install_skill claude git-worktree
out="$(run)" && fail "one runtime missing should exit 1"
grep -q "missing git-worktree in $TMP/claude" <<<"$out" && fail "installed runtime reported missing: $out"
grep -q "missing git-worktree in $TMP/agents" <<<"$out" || fail "should report the other runtime: $out"

# 其余依赖都装好，只剩 agents/git-worktree 目录在但没有 SKILL.md：不算装好
for name in $names; do
  install_skill claude "$name"
  [ "$name" = git-worktree ] || install_skill agents "$name"
done
mkdir -p "$TMP/agents/git-worktree"
run >/dev/null && fail "dir without SKILL.md should not count"

# 补上最后一个 SKILL.md：通过
install_skill agents git-worktree
run >/dev/null || fail "all installed should exit 0"

echo "check-skills.test.sh: ok"
