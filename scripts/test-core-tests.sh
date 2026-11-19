#!/usr/bin/env bash
# Self-test for scripts/test-core.sh (#28 item 1): a failing test must give a non-zero exit, a skipped test must be
# reported as skipped and never fail the run, and a clean run must exit 0. Uses the fixture package in
# scripts/test-core-fixtures/Mixed (one passing, one skipped, and one test that fails only when VP_FIXTURE_FAIL=1).
# Needs Swift (Linux or WSL), like test-core.sh. Without Swift it prints a SKIPPED line and exits 3, so nothing can
# mistake "not run" for "passed".
# Prints one line per check and "test-core tests: passed N, failed M" last; exit 1 on any failure.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
if ! command -v swift >/dev/null 2>&1; then
  echo "test-core tests: SKIPPED (no Swift toolchain here; run in WSL or Linux)"
  exit 3
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P=0; X=0
check() { # description result(0/1)
  if [ "$2" -eq 0 ]; then P=$((P + 1)); echo "ok    $1"; else X=$((X + 1)); echo "FAIL  $1"; echo "$OUT" | tail -15 | sed 's/^/      /'; fi
}
run() { # extra env assignment (or empty)
  OUT="$(env $1 VP_PACKAGE_DIR="$HERE/scripts/test-core-fixtures/Mixed" VP_BUILD_DIR="$TMP/build" VP_CORE_LOG="$TMP/core.log" \
    bash "$HERE/scripts/test-core.sh" 2>&1)"; RC=$?
  LAST="$(printf '%s\n' "$OUT" | grep '^test-core: ' | tail -1)"
}

run "VP_FIXTURE_FAIL=0"
[ "$RC" -eq 0 ]; check "clean run (1 pass, 1 skip): exit 0 (got $RC)" $?
[ "$LAST" = "test-core: passed 2, skipped 1, failed 0 (swift test exit 0)" ]; check "clean run: summary line reports the skip separately ($LAST)" $?

run "VP_FIXTURE_FAIL=1"
[ "$RC" -ne 0 ]; check "one failing test: non-zero exit (got $RC)" $?
printf '%s\n' "$LAST" | grep -q "failed 1"; check "one failing test: summary says failed 1 ($LAST)" $?
printf '%s\n' "$LAST" | grep -q "skipped 1"; check "one failing test: the skip is still reported separately" $?

# A log with no result lines at all (a build that printed nothing) must fail even if swift exits 0: checked through the
# counter directly, because the fixture cannot make swift print nothing.
: >"$TMP/empty.log"
T="$(VP_TESTS_DIR="$HERE/scripts/test-core-fixtures/Mixed/Tests" bash "$HERE/scripts/test-counts.sh" --totals "$TMP/empty.log")"
[ "$T" = "passed 0, skipped 0, failed 0" ]; check "an empty log counts as no results (test-core.sh then exits 1)" $?
grep -q 'NO TEST RESULTS FOUND' "$HERE/scripts/test-core.sh"; check "test-core.sh treats no results as a failure" $?

echo "test-core tests: passed $P, failed $X"
[ "$X" -eq 0 ]
