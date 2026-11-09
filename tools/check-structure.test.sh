#!/usr/bin/env bash
set -euo pipefail

# 锁定 check-structure.sh 的阈值边界、本层计数、只数代码文件、二进制跳过、排除与退出码合同。
# 在临时 git 仓库内构造夹具，不触碰调用方仓库。

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-structure.sh"
REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

write_lines() {
  mkdir -p "$(dirname "$REPO/$1")"
  seq "$2" >"$REPO/$1"
}

touch_files() {
  local dir="$1" count="$2" ext="$3" i
  mkdir -p "$REPO/$dir"
  for ((i = 1; i <= count; i++)); do
    : >"$REPO/$dir/f$i.$ext"
  done
}

build_fixture() {
  git -C "$REPO" init -q
  write_lines long/at-limit.txt 800
  write_lines long/over-limit.txt 801
  write_lines pnpm-lock.yaml 900
  write_lines nested/pnpm-lock.yaml 900
  printf 'a\0b\n%.0s' $(seq 900) >"$REPO/blob.bin"
  touch_files crowded 9 ts
  touch_files full 8 py
  touch_files full/sub 3 go
  touch_files full 5 md
  touch_files docs 12 md
  touch_files public 12 png
  git -C "$REPO" add -A
}

run_check() {
  (cd "$REPO/full" && bash "$SCRIPT" "$@")
}

assert_output() {
  local expected="$1"; shift
  local actual
  actual="$(run_check "$@")" || fail "report mode must exit 0 (args: $*)"
  [[ "$actual" == "$expected" ]] || fail "unexpected output for args: $*
--- expected
$expected
--- actual
$actual"
}

build_fixture

assert_output "files 9 crowded
lines 801 long/over-limit.txt
lines 900 nested/pnpm-lock.yaml
lines 900 pnpm-lock.yaml
summary lines=3 files=1"

assert_output "files 9 crowded
lines 801 long/over-limit.txt
summary lines=1 files=1" --exclude '**/pnpm-lock.yaml'

if run_check --strict --exclude '**/pnpm-lock.yaml' >/dev/null; then
  fail "--strict must exit non-zero when violations exist"
fi

clean="$(run_check --strict --exclude '**/pnpm-lock.yaml' --exclude 'crowded/**' --exclude 'long/over-limit.txt')" \
  || fail "--strict must exit 0 without violations"
[[ "$clean" == "summary lines=0 files=0" ]] || fail "clean summary mismatch: $clean"

if run_check --bogus >/dev/null 2>&1; then
  fail "unknown argument must be rejected"
fi

printf 'PASS: check-structure thresholds, per-level code-file counting, excludes and exit codes\n'
