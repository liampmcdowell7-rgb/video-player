#!/usr/bin/env bash
# Runs the VideoPlayerCore unit tests on Linux (for example inside WSL). Copies the package
# to a local folder first because builds on a Windows-mounted drive are slow.
# Usage: bash scripts/test-core.sh [extra swift test arguments, for example --filter SegmentTests]
#
# Exit code (#28 item 1): non-zero when `swift test` fails, when any test failed, or when no test result was found at all
# (a build that "succeeds" with nothing run must not look like a pass). Skipped tests never fail the run; they are reported
# on their own in the last line:
#   test-core: passed P, skipped S, failed F (swift test exit N)
# The counts come from scripts/test-counts.sh --totals (individual result lines, robust to broken lines, R153).
# Self-test: scripts/test-core-tests.sh (a tiny fixture package with a passing, a failing and a skipped test).
#
# Overrides (used by the self-test): VP_PACKAGE_DIR (package to test, default Packages/VideoPlayerCore), VP_BUILD_DIR
# (copy to build in), VP_CORE_LOG (where the full output is kept, default <build dir>.log).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
[ "$(uname -s)" = Linux ] && bash "$HERE/scripts/setup-sqlite.sh"   # LibraryIndex links the system SQLite on Linux
PKG="${VP_PACKAGE_DIR:-$HERE/Packages/VideoPlayerCore}"
WORK="${VP_BUILD_DIR:-$HOME/video-player-core-build}"
LOGFILE="${VP_CORE_LOG:-$WORK.log}"
mkdir -p "$WORK"
rsync -a --delete --exclude .build "$PKG/" "$WORK/" 2>/dev/null || { rm -rf "$WORK"; mkdir -p "$WORK"; cp -r "$PKG/." "$WORK/"; }
cd "$WORK"
# AttributionNoticeTests reads App/Support/Attribution.swift, which is not inside the copied package.
set +e
VP_PROJECT_ROOT="$HERE" swift test "$@" 2>&1 | tee "$LOGFILE"
SWIFT_RC=${PIPESTATUS[0]}
set -e

TOTALS="$(VP_TESTS_DIR="$PKG/Tests" bash "$HERE/scripts/test-counts.sh" --totals "$LOGFILE" 2>/dev/null)" || TOTALS=""
[ -n "$TOTALS" ] || TOTALS="passed 0, skipped 0, failed 0"
FAILED="$(printf '%s\n' "$TOTALS" | sed -n 's/.*failed \([0-9][0-9]*\).*/\1/p')"
PASSED="$(printf '%s\n' "$TOTALS" | sed -n 's/^passed \([0-9][0-9]*\).*/\1/p')"
SKIPPED="$(printf '%s\n' "$TOTALS" | sed -n 's/.*skipped \([0-9][0-9]*\).*/\1/p')"
FAILED="${FAILED:-0}"; PASSED="${PASSED:-0}"; SKIPPED="${SKIPPED:-0}"

RC=0
[ "$SWIFT_RC" -ne 0 ] && RC=1
[ "$FAILED" -gt 0 ] && RC=1
if [ $((PASSED + FAILED + SKIPPED)) -eq 0 ]; then
  echo "test-core: NO TEST RESULTS FOUND in $LOGFILE (counted as a failure)"
  RC=1
fi
echo "test-core: passed $PASSED, skipped $SKIPPED, failed $FAILED (swift test exit $SWIFT_RC)"
exit "$RC"
