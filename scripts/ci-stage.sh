#!/usr/bin/env bash
# CI only (compile-check.yml, every job). Where the time goes, per stage.
#   ci-stage.sh "NAME"              records that the stage NAME starts now (first line of each step)
#   ci-stage.sh --summary "TITLE"   writes a table "stage | minutes:seconds" to the step summary and to $OUT/stage-times.md
# A stage lasts from its start to the start of the next stage; the last one to the moment --summary runs. A step that
# failed or hit its time limit therefore still gets its time. Steps without a marker (checkout, uploads) are counted
# into the stage before them. Uses only `date +%s`; never fails the job.
out="${OUT:-build/ci}"
# A step with its own working-directory (the package tests) must still write into the job's folder.
case "$out" in /*) ;; *) out="${GITHUB_WORKSPACE:-.}/$out" ;; esac
mkdir -p "$out" 2>/dev/null
log="$out/stage-times.txt"
if [ "${1:-}" != "--summary" ]; then
  printf '%s\t%s\n' "$(date +%s)" "${1:-unnamed}" >> "$log" 2>/dev/null
  exit 0
fi
title="${2:-Job}"
now="$(date +%s)"
{
  echo "## Stage times: $title"
  echo
  echo "| Stage | Time (min:s) |"
  echo "|---|---|"
  if [ -s "$log" ]; then
    first="$(head -n 1 "$log" | cut -f1)"
    # Pair every start with the next start (or now).
    awk -F'\t' -v now="$now" '
      { t[NR] = $1; n[NR] = $2 }
      END {
        for (i = 1; i <= NR; i++) {
          end = (i < NR) ? t[i + 1] : now
          d = end - t[i]; if (d < 0) d = 0
          printf "| %s | %d:%02d |\n", n[i], int(d / 60), d % 60
        }
      }' "$log"
    total=$((now - first))
    printf '| **Total from the first stage** | **%d:%02d** |\n' $((total / 60)) $((total % 60))
  else
    echo "| (no stage was recorded) | |"
  fi
} | tee "$out/stage-times.md" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
cat "$out/stage-times.md"
exit 0
