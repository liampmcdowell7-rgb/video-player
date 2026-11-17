#!/usr/bin/env bash
# Counts the individual test results in a `swift test` log, PER TEST TARGET, and checks them against the recorded floors.
#
#   bash scripts/test-counts.sh STAGE LOGFILE            print the counts, check the floors, exit 1 when any is below its floor
#   bash scripts/test-counts.sh --record STAGE LOGFILE   write this log's counts as the new floors (a person decides when)
#   bash scripts/test-counts.sh --totals LOGFILE         print only "passed P, skipped S, failed F" (used by test-all.sh)
#
# Why: a stage that "runs" but silently discovers fewer tests (a target with 0 discovered tests happened for the SFTP
# tests under the default build system, OPEN_QUESTIONS.md R68) must fail loudly instead of printing a small, clean number.
#
# How: XCTest on Linux prints `Test Case 'Class.testName' passed|skipped|failed`, with no target name, so each class is mapped
# to its target from the class declarations under Packages/VideoPlayerCore/Tests/<Target>/. Floors live in scripts/test-floors.txt
# (or $VP_FLOORS_FILE) as `stage target minimum` lines; the minimum applies to everything that ran.
#
# Two independent counts per target (OPEN_QUESTIONS R153), because another process (swift build printing a deprecation
# warning) can write into the middle of a result line, so the line breaks in two and the regex no longer sees it:
#   1. result lines: `Test Case '…' passed|skipped|failed`, found anywhere in a line. A line that starts with `' passed (`,
#      `' skipped (` or `' failed (` is the broken-off end of a result line; it is credited to the test that most recently
#      started and has no result yet (XCTest runs one test at a time, so that is the test it belongs to).
#   2. XCTest's own summary: `Test Suite 'Class' passed|failed at …` followed by `Executed N tests, with … F failures`.
# A target is below its floor only when BOTH counts are below it. The failed count reported is the larger of the two, so a
# failure hidden by a broken line is still reported. A target with a floor and neither kind of line counts as 0 and fails.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="${VP_TESTS_DIR:-$HERE/Packages/VideoPlayerCore/Tests}"
FLOORS="${VP_FLOORS_FILE:-$HERE/scripts/test-floors.txt}"
RECORD=0; TOTALS=0
if [ "${1:-}" = "--record" ]; then RECORD=1; shift; fi
if [ "${1:-}" = "--totals" ]; then TOTALS=1; shift; set -- totals "${1:-}"; fi
STAGE="${1:?usage: test-counts.sh [--record|--totals] STAGE LOGFILE}"; LOGFILE="${2:?usage: test-counts.sh [--record] STAGE LOGFILE}"
[ -f "$LOGFILE" ] || { echo "$STAGE: no log file $LOGFILE" >&2; exit 2; }

MAP="$(mktemp)"; COUNTS="$(mktemp)"; trap 'rm -f "$MAP" "$COUNTS"' EXIT
for dir in "$TESTS"/*/; do
  target="$(basename "$dir")"
  grep -rhoE --include='*.swift' '^[[:space:]]*((final|open|public|internal) )*class [A-Za-z0-9_]+' "$dir" 2>/dev/null \
    | sed -E 's/.*class //' | sort -u | sed "s/\$/ $target/" >>"$MAP"
done

# Output: "target passed skipped failed summaryRun summaryFailed" per target.
tr -d '\r' <"$LOGFILE" | awk -v map="$MAP" '
  BEGIN { while ((getline line < map) > 0) { split(line, a, " "); target[a[1]] = a[2] } }
  # The end of a result line that another process broke: some tail of "\047 passed (", "\047 skipped (" or "\047 failed ("
  # followed by the duration. The tail must be at least 6 characters ("ssed (", "pped (", "iled ("), so it still says which
  # result it was; a shorter tail is left to the XCTest summary count.
  function orphan(line,   i, w, full, k, sfx) {
    split("passed skipped failed", words, " ")
    for (i = 1; i <= 3; i++) {
      w = words[i]; full = "\047 " w " ("
      for (k = 1; k <= length(full) - 5; k++) {
        sfx = substr(full, k)
        if (substr(line, 1, length(sfx)) == sfx && substr(line, length(sfx) + 1) ~ /^[0-9.]+ seconds\)/) return substr(w, 1, 1)
      }
    }
    return ""
  }
  function tgt(cls) { return (cls in target) ? target[cls] : "(unmapped:" cls ")" }
  function credit(name, res,   dot, cls, t) {
    dot = index(name, "."); cls = (dot > 0) ? substr(name, 1, dot - 1) : name
    t = tgt(cls); n[t, res]++; seen[t] = 1
  }
  {
    line = $0
    # 2. XCTest summary of one class.
    if (match(line, /Test Suite \047[^\047]*\047 (passed|failed) at/)) {
      s = substr(line, RSTART + 12); suite = substr(s, 1, index(s, "\047") - 1); next
    }
    if (suite != "" && match(line, /Executed [0-9]+ tests?, with /)) {
      split(substr(line, RSTART + 9), w, " "); run = w[1] + 0
      fails = 0; if (match(line, /[0-9]+ failures?/)) fails = substr(line, RSTART, RLENGTH) + 0
      if (suite in target) { t = target[suite]; sumRun[t] += run; sumFail[t] += fails; seen[t] = 1 }
      suite = ""; next
    }
    # 1a. Broken-off end of a result line.
    res = orphan(line)
    if (res != "") {
      if (last != "" && (last in open)) { credit(last, res); delete open[last] }
      next
    }
    # 1b. Result or start line, anywhere in the line.
    p = index(line, "Test Case \047"); if (p == 0) next
    s = substr(line, p + 11); q = index(s, "\047"); if (q == 0) next
    name = substr(s, 1, q - 1); rest = substr(s, q + 1)
    if (rest ~ /^ started/) { open[name] = 1; last = name; next }
    res = ""
    if (rest ~ /^ passed/) res = "p"; else if (rest ~ /^ skipped/) res = "s"; else if (rest ~ /^ failed/) res = "f"
    if (res == "") next
    credit(name, res); delete open[name]
  }
  END {
    for (t in seen) printf "%s %d %d %d %d %d\n", t, n[t, "p"] + 0, n[t, "s"] + 0, n[t, "f"] + 0, sumRun[t] + 0, sumFail[t] + 0
  }' | sort >"$COUNTS"

total_p=0; total_s=0; total_f=0
while read -r t p s f r sf; do
  [ "$sf" -gt "$f" ] && f="$sf"
  total_p=$((total_p + p)); total_s=$((total_s + s)); total_f=$((total_f + f))
  [ "$TOTALS" = 1 ] && continue
  note=""; [ "$r" -gt 0 ] && [ "$r" -ne "$((p + s + f))" ] && note=" (XCTest summary says $r ran; the result lines and the summary disagree, see the log)"
  echo "$STAGE  $t: passed $p, skipped $s, failed $f$note"
done <"$COUNTS"
if [ "$TOTALS" = 1 ]; then echo "passed $total_p, skipped $total_s, failed $total_f"; exit 0; fi
echo "$STAGE  TOTAL: passed $total_p, skipped $total_s, failed $total_f"
[ "$((total_p + total_s + total_f))" -gt 0 ] || { echo "$STAGE  FAILED: NO TEST RESULT LINES AT ALL (the build or the server failed; read the log)"; exit 1; }

if [ "$RECORD" = 1 ]; then
  { grep -v "^$STAGE " "$FLOORS" 2>/dev/null || true; while read -r t p s f r sf; do echo "$STAGE $t $((p + s + f))"; done <"$COUNTS"; } | sort >"$FLOORS.new"
  mv "$FLOORS.new" "$FLOORS"; echo "$STAGE: floors recorded in $FLOORS"; exit 0
fi

bad=0
if [ -f "$FLOORS" ]; then
  while read -r st t floor; do
    [ "$st" = "$STAGE" ] || continue
    lines="$(awk -v t="$t" '$1 == t { print $2 + $3 + $4 }' "$COUNTS")"; lines="${lines:-0}"
    summ="$(awk -v t="$t" '$1 == t { print $5 }' "$COUNTS")"; summ="${summ:-0}"
    if [ "$lines" -lt "$floor" ] && [ "$summ" -lt "$floor" ]; then
      echo "$STAGE  BELOW FLOOR: $t ran $lines by result lines and $summ by XCTest summary, floor is $floor"; bad=1
    fi
  done <"$FLOORS"
else
  echo "$STAGE  NO FLOORS RECORDED ($FLOORS missing): counts are not checked"
fi
if grep -q '(unmapped:' "$COUNTS"; then echo "$STAGE  WARNING: results for classes that belong to no test target (see above)"; fi
[ "$bad" -eq 0 ] || { echo "$STAGE  FAILED: a target ran fewer tests than its floor"; exit 1; }
exit 0
