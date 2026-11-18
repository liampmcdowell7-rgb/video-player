#!/usr/bin/env bash
# CI only. The same error summary the "compile" job writes, for any job: compiler and linker errors with a file position as
# "file:line: message" (errors.txt), other error lines (errors-other.txt), shown in the job summary.
# Usage: ci-summarise-errors.sh <title> <build log> [more logs searched for other error lines...]   (OUT must be set)
set -uo pipefail
title="$1"; log="$2"; shift 2
: "${OUT:?}"
touch "$log"
grep -E '(^|[[:space:]])(/[^:]+):([0-9]+):([0-9]+:)? (fatal )?error: ' "$log" \
  | sed -E 's#^[^/]*(/[^:]+):([0-9]+):([0-9]+:)? (fatal )?error: (.*)$#\1:\2: \5#' \
  | sed -E "s#^${GITHUB_WORKSPACE:-/nonexistent}/##" \
  | sort -u > "$OUT/errors.txt" || true
grep -hE '^(error|xcodebuild: error|ld: |clang: error|.*error: )' "$log" "$@" 2>/dev/null \
  | grep -vE '(^|[[:space:]])/[^:]+:[0-9]+:([0-9]+:)? (fatal )?error: ' | sort -u > "$OUT/errors-other.txt" || true
n=$(wc -l < "$OUT/errors.txt" | tr -d ' ')
m=$(wc -l < "$OUT/errors-other.txt" | tr -d ' ')
{
  echo "## $title: $n compiler errors with a file position, $m other error lines"
  echo
  echo '```'
  head -n 150 "$OUT/errors.txt"
  [ "$n" -gt 150 ] && echo "... ($n in total; all of them are in errors.txt in the artifact)"
  echo '--- other error lines ---'
  head -n 50 "$OUT/errors-other.txt"
  echo '```'
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
exit 0
