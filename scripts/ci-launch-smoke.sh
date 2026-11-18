#!/usr/bin/env bash
# CI only (compile-check.yml, job "screenshots", step "Launch smoke"). Launches the installed app once on the booted
# simulator, waits, and checks that its process is still alive. Everything that explains a crash goes into the JOB LOG
# (the log archive is what gets attached, not always the artifacts) and into $OUT/launch-smoke-<label>/.
#
# Usage: bash scripts/ci-launch-smoke.sh <simulator UDID> <label> [launch arguments...]
#   label: a short name for this launch (plain, uitest-empty); the arguments are passed to the app.
# Prints "LAUNCH OK (<label>)" and exits 0 when the app is still running after $WAIT seconds; otherwise prints
# "LAUNCH FAILED (<label>)", the newest crash reports (first 120 lines of each .ips: exception type, termination reason, the
# crashed thread), the app's unified-log lines and the last 100 lines of its console output, and exits 1.
set -uo pipefail
UDID="${1:?simulator UDID}"
LABEL="${2:?label}"
shift 2
BID="com.liamp.videoplayer"
PROCESS="VideoPlayer"
WAIT="${WAIT:-8}"
OUT="${OUT:-build/ci}"
D="$(pwd)/$OUT/launch-smoke-$LABEL"
mkdir -p "$D"
touch "$D/.start"          # crash reports newer than this file belong to this launch

echo "=== LAUNCH SMOKE ($LABEL) on $UDID, arguments: ${*:-(none)}"
xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
# --stdout/--stderr: the app's own console output into files (documented options of `xcrun simctl launch`; the tool's help
# is printed by the workflow step before this script runs, so a changed command line is visible in the log).
LAUNCH_OUT="$(xcrun simctl launch --stdout="$D/stdout.txt" --stderr="$D/stderr.txt" "$UDID" "$BID" "$@" 2>&1)"
LAUNCH_RC=$?
echo "simctl launch (exit $LAUNCH_RC): $LAUNCH_OUT"
PID="$(printf '%s\n' "$LAUNCH_OUT" | sed -nE 's/^.*: ([0-9]+)$/\1/p' | tail -n 1)"

sleep "$WAIT"

ALIVE=no
# Simulator apps run as processes of the Mac, so the PID simctl printed can be checked directly.
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then ALIVE=yes; fi
xcrun simctl spawn "$UDID" launchctl list > "$D/launchctl.txt" 2>&1 || true
echo "launchctl entry inside the simulator (PID column \"-\" means not running):"
grep -F "$BID" "$D/launchctl.txt" || echo "  (no launchctl entry for $BID)"

# The app's own lines, crash or not (CloudKitGate logs "iCloud container could not be created: ..." here).
xcrun simctl spawn "$UDID" log show --style compact --last 2m \
  --predicate "process == \"$PROCESS\" OR eventMessage CONTAINS \"$BID\"" > "$D/unified-log.txt" 2>&1 || true

if [ "$ALIVE" = yes ]; then
  echo "LAUNCH OK ($LABEL): $PROCESS (pid $PID) is still running after ${WAIT} s"
  echo "--- last 30 lines of its console output (stderr, then stdout):"
  tail -n 30 "$D/stderr.txt" 2>/dev/null || true
  tail -n 30 "$D/stdout.txt" 2>/dev/null || true
  xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
  exit 0
fi

echo "::error::LAUNCH FAILED ($LABEL): $PROCESS is not running ${WAIT} s after launch (pid ${PID:-unknown}, simctl exit $LAUNCH_RC)"
echo "LAUNCH FAILED ($LABEL)"

echo "=== Crash reports written since this launch (first 120 lines of each)"
found=0
for dir in "$HOME/Library/Logs/DiagnosticReports" "$HOME/Library/Logs/CoreSimulator/$UDID" \
           "$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Logs"; do
  [ -d "$dir" ] || continue
  while IFS= read -r f; do
    found=1
    cp "$f" "$D/" 2>/dev/null || true
    echo "----- $f"
    sed -n '1,120p' "$f"
  done < <(find "$dir" -type f \( -name '*.ips' -o -name '*.crash' \) -newer "$D/.start" 2>/dev/null | grep -i -e "$PROCESS" -e videoplayer)
done
[ "$found" -eq 1 ] || echo "(no crash report found in DiagnosticReports or the simulator's log folders)"

echo "=== CoreSimulator system log for this device (last 60 lines mentioning the app)"
SYSLOG="$HOME/Library/Logs/CoreSimulator/$UDID/system.log"
if [ -f "$SYSLOG" ]; then grep -i -e "$PROCESS" -e "$BID" "$SYSLOG" | tail -n 60; else echo "(no $SYSLOG)"; fi

echo "=== Unified log of the app, last 100 lines"
tail -n 100 "$D/unified-log.txt"

echo "=== Console output of the app, last 100 lines (stderr, then stdout)"
tail -n 100 "$D/stderr.txt" 2>/dev/null || echo "(no stderr file)"
tail -n 100 "$D/stdout.txt" 2>/dev/null || echo "(no stdout file)"
exit 1
