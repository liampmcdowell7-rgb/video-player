#!/usr/bin/env bash
# Tests for scripts/test-counts.sh (OPEN_QUESTIONS R153): a build-tool warning written into the middle of a result line must
# not hide a test, a failure hidden that way must still be reported, and a stage that really ran too few tests must still fail.
# Fixtures: scripts/test-counts-fixtures (logs, a two-target Tests folder that is never compiled, floor files).
# Prints one line per check and "test-counts tests: passed N, failed M" last; exit 1 on any failure.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="$HERE/scripts/test-counts-fixtures"
P=0; X=0
run() { # floors log -> sets OUT and RC
  OUT="$(VP_TESTS_DIR="$F/Tests" VP_FLOORS_FILE="$F/$1" bash "$HERE/scripts/test-counts.sh" fixture "$F/$2" 2>&1)"; RC=$?
}
check() { # description condition-result(0/1)
  if [ "$2" -eq 0 ]; then P=$((P + 1)); echo "ok    $1"; else X=$((X + 1)); echo "FAIL  $1"; echo "$OUT" | sed 's/^/      /'; fi
}
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }

run floors.txt midline-warning.log
has "FixtureTargetTests: passed 3, skipped 0, failed 0"; check "mid-line warning: the broken passed line is still counted (3 passed)" $?
[ "$RC" -eq 0 ]; check "mid-line warning: floor of 3 is met, exit 0" $?
! has "disagree"; check "mid-line warning: result lines and XCTest summary agree" $?

run floors.txt midline-warning-no-summary.log
has "FixtureTargetTests: passed 3, skipped 0, failed 0" && [ "$RC" -eq 0 ]; check "mid-line warning without any summary line: still 3, exit 0" $?

run floors.txt result-line-lost.log
[ "$RC" -eq 0 ]; check "result line lost entirely: the XCTest summary (3 ran) keeps the floor met" $?
has "XCTest summary says 3 ran"; check "result line lost entirely: the disagreement is printed" $?

run floors.txt really-short.log
[ "$RC" -eq 1 ]; check "really only 2 ran: below the floor of 3, exit 1" $?
has "BELOW FLOOR: FixtureTargetTests ran 2 by result lines and 2 by XCTest summary, floor is 3"; check "really only 2 ran: both counts named" $?

run floors.txt midline-warning-failed.log
has "FixtureTargetTests: passed 2, skipped 0, failed 1"; check "a failed line broken by the warning is reported as failed" $?
OUT="$(VP_TESTS_DIR="$F/Tests" bash "$HERE/scripts/test-counts.sh" --totals "$F/midline-warning-failed.log" 2>&1)"
[ "$OUT" = "passed 2, skipped 0, failed 1" ]; check "--totals reports the hidden failure too" $?

run floors-two-targets.txt warning-before-result.log
has "FixtureTargetTests: passed 2, skipped 1, failed 0" && has "OtherTargetTests: passed 1, skipped 0, failed 0" && [ "$RC" -eq 0 ]
check "warning printed before the result text on the same line; skipped test; two targets" $?

run floors.txt warning-after-quote.log
has "FixtureCaseTests" >/dev/null; has "FixtureTargetTests: passed 3, skipped 0, failed 0" && [ "$RC" -eq 0 ] && ! has "disagree"
check "warning right after the closing quote (seen in a real SFTP run): still 3 passed, exit 0" $?

run floors.txt warning-late-split.log
has "FixtureTargetTests: passed 2, skipped 0, failed 0" && has "XCTest summary says 3 ran" && [ "$RC" -eq 0 ]
check "split too late to tell the result: line count 2, the XCTest summary (3) keeps the floor met" $?

echo "test-counts tests: passed $P, failed $X"
[ "$X" -eq 0 ]
