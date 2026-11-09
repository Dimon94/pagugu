#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------
# [L3][COORD] repo://tools/check-structure.sh
# [INPUT]  当前目录所在 git 仓库的跟踪文件（读工作树内容）。
# [OUTPUT] stdout 每条违规一行，最后一行是汇总；退出码见 [L5] --strict。
# [POS]    与技术栈无关的结构阈值检查，只管文件行数和目录直接文件数。
#          嵌套深度与函数长度归各技术栈 lint。阈值合同：repo://docs/agents/coding-standards.md 第 4 节。
# [PROTOCOL] 变更时更新此头部、repo://tools/check-structure.test.sh 与 repo://tools/AGENTS.md
# ---------------------------------------------------------------------
# [L5] 阈值与参数
# MAX_FILE_LINES=800  单文件行数上限，含空行与注释。git 判定为二进制的文件不计。
# MAX_DIR_FILES=8     目录直接包含的代码文件数上限。子目录内的文件不计入本层；仓库根记为 "."。
# CODE_EXT            代码文件扩展名白名单。文档、图片、配置数据不计入目录计数，只受行数上限约束。
# --strict            有违规时 exit 1。缺省只报告，exit 0。
# --exclude PATTERN   可重复。排除只在命令行配置，调用行（如 CI job）即唯一配置处。
#                     PATTERN 是 git glob pathspec，相对仓库根：'*' 不跨 '/'，
#                     '**/pnpm-lock.yaml' 匹配任意层（含根），'dist/**' 排除整个目录。
# [FAIL]  参数错误 exit 2；不在 git 仓库内时 git 报错并以非 0 退出。
# ---------------------------------------------------------------------
# 输出格式（合同，测试锁定）：
#   files <文件数> <目录>
#   lines <行数> <路径>
#   summary lines=<N> files=<M>
# 违规按种类、路径排序（LC_ALL=C）。
# ---------------------------------------------------------------------

MAX_FILE_LINES=800
MAX_DIR_FILES=8
CODE_EXT='ts|tsx|js|jsx|mjs|cjs|vue|svelte|py|go|rs|swift|kt|java|rb|c|h|cc|cpp|m|mm|sh'
STRICT=0
PATHSPECS=(".")

usage_error() {
  printf 'error: %s\nusage: tools/check-structure.sh [--strict] [--exclude PATTERN]...\n' "$1" >&2
  exit 2
}

parse_args() {
  while (($#)); do
    case "$1" in
      --strict) STRICT=1; shift ;;
      --exclude)
        (($# >= 2)) || usage_error "--exclude 缺少 PATTERN"
        PATHSPECS+=(":(exclude,glob)$2"); shift 2 ;;
      *) usage_error "未知参数 $1" ;;
    esac
  done
}

# git grep -c '' 输出 "路径:行数"；-I 跳过二进制。无匹配文件时 git grep 返回 1，不算失败。
report_long_files() {
  git grep -I -c -e '' -- "${PATHSPECS[@]}" || test $? -eq 1
}

filter_long_files() {
  awk -v max="$MAX_FILE_LINES" '{
    n = $0; sub(/^.*:/, "", n); path = $0; sub(/:[0-9]+$/, "", path)
    if (n + 0 > max) print "lines", n, path
  }'
}

report_crowded_dirs() {
  git -c core.quotePath=false ls-files -- "${PATHSPECS[@]}" \
    | { grep -E "\.(${CODE_EXT})\$" || test $? -eq 1; } \
    | awk -v max="$MAX_DIR_FILES" '
    { dir = "."; if (match($0, /\/[^\/]*$/)) dir = substr($0, 1, RSTART - 1); count[dir]++ }
    END { for (dir in count) if (count[dir] > max) print "files", count[dir], dir }'
}

main() {
  parse_args "$@"
  cd "$(git rev-parse --show-toplevel)"
  local violations
  violations="$({ report_long_files | filter_long_files; report_crowded_dirs; } | LC_ALL=C sort -k1,1 -k3)"
  printf '%s' "$violations" | awk '{ print; n[$1]++ }
    END { printf "summary lines=%d files=%d\n", n["lines"], n["files"] }'
  if ((STRICT)) && [[ -n "$violations" ]]; then
    exit 1
  fi
}

main "$@"
