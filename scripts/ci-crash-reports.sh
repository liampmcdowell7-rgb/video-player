#!/usr/bin/env bash
# R416 (run #27, item 4 a): test12 ended with "com.liamp.videoplayer crashed", and nothing in the artifacts named the
# crashing line. This copies the app's crash reports into the job's small log artifact, so the next run names it.
#
# Usage: ci-crash-reports.sh OUT_DIR [SEARCH_DIR ...]
#   OUT_DIR      where the reports go (created): OUT_DIR/crash-reports/<file>, and OUT_DIR/crash-reports.txt, which lists
#                them (or says none was found).
#   SEARCH_DIR   folders to look in (default: the Mac's ~/Library/Logs/DiagnosticReports and every simulator device's
#                data/Library/Logs/DiagnosticReports under ~/Library/Developer/CoreSimulator/Devices). Where tvOS Simulator
#                writes an app's crash report is not on any Apple page read (Apple's "Acquiring crash reports and diagnostic
#                logs" covers devices and the Crashes organizer only): UNVERIFIED, so both places are searched.
# Only the app's own reports: a file name starting with "VideoPlayer" (the app's binary name), ending in .ips or .crash.
# Always exits 0: a missing report must never fail a job.
set -uo pipefail

out="${1:?usage: ci-crash-reports.sh OUT_DIR [SEARCH_DIR ...]}"
shift
dirs=("$@")
if [ "${#dirs[@]}" -eq 0 ]; then
  dirs=("$HOME/Library/Logs/DiagnosticReports")
  for d in "$HOME"/Library/Developer/CoreSimulator/Devices/*/data/Library/Logs/DiagnosticReports; do
    [ -d "$d" ] && dirs+=("$d")
  done
fi

mkdir -p "$out/crash-reports"
list="$out/crash-reports.txt"
: > "$list"
found=0
for d in "${dirs[@]}"; do
  [ -d "$d" ] || { echo "not a folder: $d" >> "$list"; continue; }
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    cp "$f" "$out/crash-reports/$base" 2>/dev/null || continue
    found=$((found + 1))
    echo "copied: $f" >> "$list"
  done < <(find "$d" -maxdepth 2 -type f \( -iname 'VideoPlayer*.ips' -o -iname 'VideoPlayer*.crash' \) -print0 2>/dev/null)
done
if [ "$found" -eq 0 ]; then
  echo "no crash report of the app found (searched: ${dirs[*]})" >> "$list"
else
  echo "$found crash report(s) of the app copied to crash-reports/" >> "$list"
fi
cat "$list"

# R423: a readable summary of each report (scripts/ci-crash-summary.py), in OUT_DIR/crash-summary.md and, on GitHub, in
# the job summary ($GITHUB_STEP_SUMMARY), so a crash can be read without downloading the 1 GB log artifact. Without
# python3, the first 60 lines of each report.
summary="$out/crash-summary.md"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
  python3 -I "$here/ci-crash-summary.py" "$out/crash-reports" > "$summary" 2>/dev/null || : > "$summary"
fi
if [ ! -s "$summary" ]; then
  {
    echo "## Crash reports of the app (R416, R423)"; echo
    if [ "$found" -eq 0 ]; then echo "No crash report of the app"; fi
    for f in "$out"/crash-reports/*; do
      [ -f "$f" ] || continue
      echo "### $(basename "$f")"; echo; echo "- not summarised (no python3); the first 60 lines of the file:"; echo
      echo '```text'; head -n 60 "$f" | sed 's/```/'"'''"'/g'; echo '```'; echo
    done
  } > "$summary"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then cat "$summary" >> "$GITHUB_STEP_SUMMARY"; fi
exit 0
