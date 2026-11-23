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
exit 0
