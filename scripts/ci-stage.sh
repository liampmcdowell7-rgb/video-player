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
  # #24 B: the UI-test jobs (scripts/ci-ui-tests.sh): every test with its time and seconds per picture.
  if [ -s "$out/ui-tests.tsv" ]; then
    echo
    echo "### UI tests (one xcodebuild call each)"
    echo
    echo "| Test | Result | Time (min:s) | Pictures | Seconds per picture |"
    echo "|---|---|---|---|---|"
    awk -F'\t' 'NR > 1 { s = $3 + 0; p = $4 + 0
      printf "| %s | %s | %d:%02d | %d | %s |\n", $1, $2, int(s / 60), s % 60, p, (p > 0 ? sprintf("%.1f", s / p) : "-") }' "$out/ui-tests.tsv"
    awk -F'\t' 'NR > 1 { s += $3; p += $4 } END { printf "| **All UI tests** | | **%d:%02d** | **%d** | **%s** |\n", int(s / 60), s % 60, p, (p > 0 ? sprintf("%.1f", s / p) : "-") }' "$out/ui-tests.tsv"
  fi
  # #24 B: what this job costs. GitHub bills each job in whole minutes, rounded up; a standard runner in a public
  # repository is free. The checkout before the first stage marker is not in this total (a few seconds).
  if [ -s "$log" ]; then
    echo
    echo "Job time from the first stage: $((total / 60)):$(printf '%02d' $((total % 60))). Runner minutes for this job (rounded up): $(( (total + 59) / 60 ))."
  fi
  # Jobs that use the simulator (scripts/ci-sim.sh): how long it took to be ready, whether it was retried, the runtimes.
  if [ -s "$out/sim-ready.txt" ]; then
    echo
    echo "### Simulator"
    echo
    sed 's/$/  /' "$out/sim-ready.txt"
  fi
  if [ -s "$out/sim-runtimes.txt" ]; then
    echo
    echo "<details><summary>Simulator runtimes on this runner</summary>"
    echo
    echo '```'
    cat "$out/sim-runtimes.txt"
    echo '```'
    echo
    echo "</details>"
  fi
} | tee "$out/stage-times.md" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
cat "$out/stage-times.md"
exit 0
