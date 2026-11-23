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
grep -qxF "No crash report of the app" "$TMP/out2/crash-summary.md"
check "no report: the summary says No crash report of the app (R423)" $?

# R423: the summary of a readable report. A small made-up .ips (no real report): a header line, then a JSON body with
# 35 frames on the crashed thread (thread 2), so only the first 30 may be listed.
S="$TMP/sample"; mkdir -p "$S"
python3 - "$S/VideoPlayer-2026-11-22-170000.ips" <<'PY'
import json, sys
frames = [{"imageIndex": 0, "imageOffset": 4096 + i, "symbol": "sampleFrame%02d" % i} for i in range(35)]
frames[0].update(sourceFile="SampleView.swift", sourceLine=42)
body = {"exception": {"type": "EXC_BREAKPOINT", "signal": "SIGTRAP"},
        "termination": {"indicator": "Trace/BPT trap: 5"},
        "asi": {"libswiftCore.dylib": ["Fatal error: sample message"]},
        "faultingThread": 2,
        "threads": [{"frames": []}, {"frames": []}, {"triggered": True, "frames": frames}],
        "usedImages": [{"name": "VideoPlayer"}]}
with open(sys.argv[1], "w") as handle:
    handle.write(json.dumps({"app_name": "VideoPlayer", "bug_type": "309"}) + "\n" + json.dumps(body, indent=2))
PY
# A broken .ips: 70 lines that are not JSON, so the summary shows the first 60 only.
for i in $(seq -w 1 70); do echo "broken-line-$i"; done >"$S/VideoPlayer-2026-11-22-170100.ips"
SUMFILE="$TMP/step-summary.md"; echo "earlier step" >"$SUMFILE"
OUT="$(GITHUB_STEP_SUMMARY="$SUMFILE" bash "$COPY" "$TMP/out3" "$S" 2>&1)"; RC=$?
OUT="$(cat "$SUMFILE")"
[ "$RC" -eq 0 ] && has "earlier step" && has "## Crash reports of the app (R416, R423)"
check "the summary is appended to \$GITHUB_STEP_SUMMARY" $?
has "### VideoPlayer-2026-11-22-170000.ips" && has "- exception type: EXC_BREAKPOINT SIGTRAP" \
  && has "- reason: Trace/BPT trap: 5; Fatal error: sample message" && has "- crashed thread: 2"
check "sample .ips: file name, exception type, reason and crashed thread" $?
has "- first 30 frames of the crashed thread (of 35):" && has '```text' \
  && has "sampleFrame00 (SampleView.swift:42)" && has "sampleFrame29" && ! has "sampleFrame30"
check "sample .ips: the first 30 frames of the crashed thread, in a code block" $?
has "### VideoPlayer-2026-11-22-170100.ips" && has "could not be read as a crash report's JSON; the first 60 lines" \
  && has "broken-line-01" && has "broken-line-60" && ! has "broken-line-61"
check "broken .ips: falls back to the first 60 lines of the file" $?

echo "crash-reports tests: passed $P, failed $X"
[ "$X" -eq 0 ]
