#!/usr/bin/env bash
# CI only (compile-check.yml, jobs "screenshots" and "accessibility-screenshots").
# Usage: ci-export-screenshots.sh RESULT.xcresult OUT_DIR
# Exports the attachments of one result bundle and puts the screenshots in viewing order (01-..., 02-...) with index.md in
# OUT_DIR (scripts/ci-screenshots-index.py). Crash reports, screen recordings and text attachments go to $OUT/attachments
# (the job's logs artifact). Keeps OUT_DIR under about 45 MB (JPEG copies when the PNGs are bigger).
# Exit status: 0 when at least one screenshot was copied.
set -uo pipefail
bash "$(dirname "$0")/ci-stage.sh" "Export $(basename "$1")"
result="${1:?result bundle}"; dest="${2:?output folder}"
mkdir -p "$dest" "$OUT/attachments"
# The tool's own help goes into the log first, so a changed command line is visible in the run.
xcrun xcresulttool help export > "$OUT/xcresulttool-help.txt" 2>&1 || true
xcrun xcresulttool export attachments --help >> "$OUT/xcresulttool-help.txt" 2>&1 || true
[ -d "$result" ] || { echo "::error::no $result"; exit 1; }
raw="$RUNNER_TEMP/attachments-$(basename "$result" .xcresult)"
mkdir -p "$raw"
xcrun xcresulttool export attachments --path "$result" --output-path "$raw" 2>&1 | tee -a "$OUT/export.log"
python3 scripts/ci-screenshots-index.py "$raw" "$dest"
status=$?
# Crash evidence: every crash report (.ips), screen recording (.mp4) and text attachment, and the first 60 lines of
# every crash report in this log.
find "$raw" -type f \( -name '*.ips' -o -name '*.mp4' -o -name '*.txt' -o -name '*.crash' -o -name 'manifest.json' \) \
  -exec cp {} "$OUT/attachments/" \;
for f in "$raw"/*.ips "$raw"/*.crash; do
  [ -f "$f" ] || continue
  echo "----- $(basename "$f") (first 60 lines)"
  sed -n '1,60p' "$f"
done
size=$(du -sm "$dest" | cut -f1)
echo "$dest: ${size} MB"
if [ "$size" -gt 45 ]; then
  for f in "$dest"/*.png; do [ -f "$f" ] && sips -s format jpeg -s formatOptions 80 "$f" --out "${f%.png}.jpg" >/dev/null && rm "$f"; done
  sed -i '' 's/\.png)/.jpg)/g' "$dest/index.md"
  echo "Converted to JPEG: now $(du -sm "$dest" | cut -f1) MB" | tee -a "$dest/index.md"
fi
{ echo "## Screenshots: $dest"; echo; sed -n '1,200p' "$dest/index.md"; } >> "$GITHUB_STEP_SUMMARY"
exit $status
