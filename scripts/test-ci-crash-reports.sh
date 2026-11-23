#!/usr/bin/env bash
# Tests for scripts/ci-crash-reports.sh (R416) on fake report folders made here.
# Prints one line per check and "crash-reports tests: passed N, failed M" last; exit 1 on any failure.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COPY="$HERE/scripts/ci-crash-reports.sh"
P=0; X=0
check() { if [ "$2" -eq 0 ]; then P=$((P + 1)); echo "ok    $1"; else X=$((X + 1)); echo "FAIL  $1"; echo "$OUT" | sed 's/^/      /'; fi; }
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# The app's reports are copied, other apps' and other files are not.
R="$TMP/reports"; mkdir -p "$R/Retired"
echo '{"app":"VideoPlayer"}' >"$R/VideoPlayer-2026-11-22-164601.ips"
echo 'crash' >"$R/Retired/VideoPlayer-2026-11-22-164700.crash"
echo '{}' >"$R/OtherApp-2026-11-22-164601.ips"
echo 'note' >"$R/VideoPlayer-notes.txt"
OUT="$(bash "$COPY" "$TMP/out" "$R" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ -f "$TMP/out/crash-reports/VideoPlayer-2026-11-22-164601.ips" ] && [ -f "$TMP/out/crash-reports/VideoPlayer-2026-11-22-164700.crash" ]
check "the app's .ips and .crash reports are copied (one folder down too)" $?
[ ! -e "$TMP/out/crash-reports/OtherApp-2026-11-22-164601.ips" ] && [ ! -e "$TMP/out/crash-reports/VideoPlayer-notes.txt" ]
check "another app's report and a non-report file are left out" $?
has "2 crash report(s) of the app copied" && grep -qF "2 crash report(s) of the app copied" "$TMP/out/crash-reports.txt"
check "crash-reports.txt counts them" $?

# None found, and a folder that does not exist: still exit 0, and the list says so.
E="$TMP/empty"; mkdir -p "$E"
OUT="$(bash "$COPY" "$TMP/out2" "$E" "$TMP/missing" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && has "no crash report of the app found" && has "not a folder: $TMP/missing"
check "no report: exit 0, and the list says none was found" $?

echo "crash-reports tests: passed $P, failed $X"
[ "$X" -eq 0 ]
