#!/usr/bin/env bash
# CI only (compile-check.yml, the three UI-test jobs; #24 A). The run on fa00af8 lost EVERY picture: one xcodebuild call ran
# all of a job's tests into one result bundle, the time budget stopped it, and the incomplete bundle ("Info.plist ... does
# not exist") could not be exported. Now:
#   - each test method is its own `xcodebuild test-without-building -only-testing:.../<test>` call (scripts/ci-sim.sh test,
#     with the time budget and the one simulator retry) with its own result bundle, $OUT/xcresult/<test>.xcresult;
#   - right after each call, that test's pictures are copied into DEST, so a later test that hangs, crashes or is stopped
#     cannot take them with it; a failed test does not stop the tests after it;
#   - when the budget is used up, the running test is stopped (SIGINT first) and the rest are not started; DEST/index.md
#     then says "TEST STOPPED BY THE TIME BUDGET: pictures up to <name>".
#
# Usage: ci-ui-tests.sh DEST TEST...      (TEST = a ScreenshotTests method name, e.g. test01_FirstLaunchAndEmptyScreens)
# Needs SIM_UDID and OUT; CI_TEST_BUDGET_SECONDS for the budget. CI_UI_XCODEBUILD (default: xcodebuild), CI_SIM_DEVICES
# (default: ~/Library/Developer/CoreSimulator/Devices) and CI_UI_EXPORT (default: 1) are for scripts/test-ci-ui-tests.sh.
#
# Where a test's pictures come from, in this order (a later source only adds names the earlier ones lack):
#   1. $OUT/screenshot-files/<test>/   the runner writes there when it gets SCREENSHOT_DIR (passed as
#      TEST_RUNNER_SCREENSHOT_DIR; the TEST_RUNNER_ prefix rule is from `man xcodebuild`, from memory) AND the host folder
#      can be written from the simulator. Neither is stated on an Apple web page; the next run's log says which route
#      worked ("SCREENSHOT FILES: <folder>" from the runner, "pictures from: ..." here).
#   2. the simulator's data folder: .../data/Containers/Data/Application/*/tmp/vp-screenshots/<test>/, the runner's own
#      temporary folder (UITests/ScreenshotTests.swift falls back to it). Simulator data lives on the Mac's disk, so a
#      `find` there needs no bundle id (the folder layout is from memory, unverified).
#   3. the result bundle, only when it is complete (Info.plist present): xcresulttool export attachments.
# Notes (.txt: NOT-REACHED, UNCHANGED, TABBAR, HIERARCHY) go to DEST/notes/. Every picture's source is in
# $OUT/ui-tests-sources.txt; the per-test results are in $OUT/ui-tests.tsv (ci-stage.sh --summary prints them).
# Exit status: 0 when every test passed, 1 otherwise (the export check and the uploads run anyway: if: always()).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dest="${1:?usage: ci-ui-tests.sh DEST TEST...}"; shift
[ "$#" -gt 0 ] || { echo "ci-ui-tests.sh: no test named" >&2; exit 2; }
out="${OUT:-build/ci}"
case "$out" in /*) ;; *) out="${GITHUB_WORKSPACE:-$PWD}/$out" ;; esac
xcb="${CI_UI_XCODEBUILD:-xcodebuild}"
devices="${CI_SIM_DEVICES:-$HOME/Library/Developer/CoreSimulator/Devices}"
mkdir -p "$dest/notes" "$out/xcresult" "$out/screenshot-files" "$out/attachments"
tsv="$out/ui-tests.tsv"; sources="$out/ui-tests-sources.txt"
printf 'test\tresult\tseconds\tpictures\n' > "$tsv"; : > "$sources"
rm -f "$out/time-budget-stopped" "$out/ui-tests-stopped.txt"

# Copies the pictures and notes in folder $1 that DEST does not have yet; prints how many pictures it copied.
take() {
  local from="$1" label="$2" n=0 f base
  [ -d "$from" ] || { echo 0; return; }
  for f in "$from"/*.png "$from"/*.jpg; do
    [ -f "$f" ] || continue; base="$(basename "$f")"
    [ -e "$dest/$base" ] && continue
    cp "$f" "$dest/$base" && n=$((n + 1)) && printf '%s\t%s\n' "$base" "$label" >> "$sources"
  done
  for f in "$from"/*.txt; do
    [ -f "$f" ] || continue; base="$(basename "$f")"
    [ -e "$dest/notes/$base" ] || cp "$f" "$dest/notes/$base"
  done
  echo "$n"
}

status=0; stopped=""
for t in "$@"; do
  if [ -n "$stopped" ]; then
    printf '%s\tnot started (time budget)\t0\t0\n' "$t" >> "$tsv"; continue
  fi
  echo "================ UI TEST $t ================"
  files="$out/screenshot-files"; bundle="$out/xcresult/$t.xcresult"
  rm -rf "$files/$t" "$bundle"
  start="$(date +%s)"
  TEST_RUNNER_SCREENSHOT_DIR="$files" bash "$here/ci-sim.sh" test "$out/test.log" -- "$xcb" test-without-building \
    -project VideoPlayer.xcodeproj -scheme VideoPlayerUITests -configuration Debug \
    -destination "platform=tvOS Simulator,id=${SIM_UDID:?SIM_UDID is not set}" \
    -clonedSourcePackagesDirPath build/SourcePackages -derivedDataPath build/DerivedData \
    -resultBundlePath "$bundle" -parallel-testing-enabled NO \
    -only-testing:"VideoPlayerUITests/ScreenshotTests/$t"
  rc=$?
  secs=$(( $(date +%s) - start ))
  if [ -e "$out/time-budget-stopped" ]; then result="stopped by the time budget"; stopped="$t"
  elif [ "$rc" -eq 124 ] && tail -n 3 "$out/test.log" | grep -q 'TIME BUDGET: not started'; then
    result="not started (time budget)"; stopped="$t"
  elif [ "$rc" -eq 0 ]; then result="passed"
  else result="failed (exit $rc)"; fi
  [ "$rc" -eq 0 ] || status=1

  # The pictures, at once (see the header for the three sources).
  n1="$(take "$files/$t" "host folder (SCREENSHOT_DIR)")"
  n2=0
  if [ -d "$devices" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      k="$(take "$d" "simulator data folder ($d)")"; n2=$((n2 + k))
    done < <(find "$devices" -type d -path "*/tmp/vp-screenshots/$t" 2>/dev/null)
  fi
  n3=0
  if [ -f "$bundle/Info.plist" ] && [ "${CI_UI_EXPORT:-1}" = 1 ]; then
    raw="$out/attachments/$t"; rm -rf "$raw" "$raw-sorted"; mkdir -p "$raw"
    if xcrun xcresulttool export attachments --path "$bundle" --output-path "$raw" >> "$out/export.log" 2>&1; then
      python3 "$here/ci-screenshots-index.py" "$raw" "$raw-sorted" > /dev/null 2>&1
      n3="$(take "$raw-sorted" "result bundle")"
      find "$raw" -type f \( -name '*.ips' -o -name '*.crash' -o -name '*.mp4' \) -exec cp {} "$out/attachments/" \; 2>/dev/null
    fi
    bundle_state="complete"
  elif [ -d "$bundle" ]; then bundle_state="INCOMPLETE (no Info.plist)"
  else bundle_state="none"; fi
  pics=$((n1 + n2 + n3))
  echo "pictures from: host folder $n1, simulator data folder $n2, result bundle $n3 (bundle: $bundle_state)"
  printf '%s\t%s\t%s\t%s\n' "$t" "$result" "$secs" "$pics" >> "$tsv"
  echo "================ UI TEST $t: $result, ${secs} s, $pics pictures ================"
done
[ -n "$stopped" ] && echo "$stopped" > "$out/ui-tests-stopped.txt"

python3 "$here/ci-ui-index.py" "$dest" "$here/screenshot-plan.tsv" "$tsv" "$@" || status=1
# Keep DEST under about 45 MB (JPEG copies when the PNGs are bigger; sips is on the macOS runner only).
size="$(du -sm "$dest" | cut -f1)"
if [ "$size" -gt 45 ] && command -v sips > /dev/null; then
  for f in "$dest"/*.png; do [ -f "$f" ] && sips -s format jpeg -s formatOptions 80 "$f" --out "${f%.png}.jpg" > /dev/null && rm "$f"; done
  python3 "$here/ci-ui-index.py" "$dest" "$here/screenshot-plan.tsv" "$tsv" "$@" > /dev/null
  echo "Converted to JPEG: now $(du -sm "$dest" | cut -f1) MB" | tee -a "$dest/index.md"
fi
{ echo "## Screenshots: $(basename "$dest")"; echo; sed -n '1,40p' "$dest/index.md"; } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
exit "$status"
