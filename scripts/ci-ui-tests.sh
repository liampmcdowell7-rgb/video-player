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
#        ci-ui-tests.sh --collect DEST TEST...
#   --collect runs no test: it only copies what the tests left (the three sources below) and writes index.md again. The
#   workflow runs it with if: always() after the test step, for the case the step's own time limit killed this script in
#   the middle of a test; that test is then listed as "cut off (the step's time limit)".
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
# #33 F (1): hang capture. While a test runs, a watcher reads the new lines of $OUT/test.log; at the first
# "main thread busy" or "Timed out while evaluating UI query" (the two hang failures of the run of 20 Nov, test12 and
# test13) it runs `sample <pid> 5 -file ...` on the app process (found with `pgrep -x`, name CI_HANG_PROCESS, default
# VideoPlayer) WHILE the app is still hung, and keeps DEST/notes/hang-sample-<test>.txt (a header, then sample's report or
# the reason there is none). The `sample` arguments (a pid or partial process name, a duration in seconds, -file) are from
# memory of `man sample`, which could not be read here (no Mac); unverified until the next hang. The capture never changes
# the job's result: every step of it ends in `|| true`. CI_SAMPLE (default: sample) is for scripts/test-ci-ui-tests.sh.
# #34 4 (R242, PROVISIONAL mitigation, not a diagnosis; the hang capture above stays): CI_FRESH_SIM_BEFORE names tests
# (space separated) that get a clean simulator first: `ci-sim.sh fresh` (shut down, erase, boot), inside the time budget.
# Its output and seconds go to DEST/notes/fresh-simulator-<test>.txt. It never changes the job's result by itself.
# CI_SIM_FRESH (default: bash scripts/ci-sim.sh fresh) is for scripts/test-ci-ui-tests.sh.
# Exit status: 0 when every test passed, 1 otherwise (the export check and the uploads run anyway: if: always()).
# --collect always exits 0.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
collect_only=""
if [ "${1:-}" = --collect ]; then collect_only=1; shift; fi
dest="${1:?usage: ci-ui-tests.sh [--collect] DEST TEST...}"; shift
[ "$#" -gt 0 ] || { echo "ci-ui-tests.sh: no test named" >&2; exit 2; }
out="${OUT:-build/ci}"
case "$out" in /*) ;; *) out="${GITHUB_WORKSPACE:-$PWD}/$out" ;; esac
xcb="${CI_UI_XCODEBUILD:-xcodebuild}"
devices="${CI_SIM_DEVICES:-$HOME/Library/Developer/CoreSimulator/Devices}"
mkdir -p "$dest/notes" "$out/xcresult" "$out/screenshot-files" "$out/attachments"
tsv="$out/ui-tests.tsv"; sources="$out/ui-tests-sources.txt"
TAB="$(printf '\t')"
if [ -z "$collect_only" ]; then
  echo "test${TAB}result${TAB}seconds${TAB}pictures" > "$tsv"; : > "$sources"
  rm -f "$out/time-budget-stopped" "$out/ui-tests-stopped.txt"
else
  [ -s "$tsv" ] || echo "test${TAB}result${TAB}seconds${TAB}pictures" > "$tsv"
  touch "$sources"
fi

# Copies the pictures and notes in folder $1 that DEST does not have yet; prints how many pictures it copied.
take() {
  local from="$1" label="$2" n=0 f base
  [ -d "$from" ] || { echo 0; return; }
  for f in "$from"/*.png "$from"/*.jpg; do
    [ -f "$f" ] || continue; base="$(basename "$f")"
    [ -e "$dest/$base" ] && continue
    cp "$f" "$dest/$base" && n=$((n + 1)) && echo "$base${TAB}$label" >> "$sources"
  done
  for f in "$from"/*.txt; do
    [ -f "$f" ] || continue; base="$(basename "$f")"
    [ -e "$dest/notes/$base" ] || cp "$f" "$dest/notes/$base"
  done
  echo "$n"
}

# Copies one test's pictures from the three sources (see the header); prints the number copied. Says where from on stderr.
collect() {
  local t="$1" bundle="$out/xcresult/$1.xcresult" n1 n2=0 n3=0 k d raw state
  n1="$(take "$out/screenshot-files/$t" "host folder (SCREENSHOT_DIR)")"
  if [ -d "$devices" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      k="$(take "$d" "simulator data folder ($d)")"; n2=$((n2 + k))
    done < <(find "$devices" -type d -path "*/tmp/vp-screenshots/$t" 2>/dev/null)
  fi
  if [ -f "$bundle/Info.plist" ]; then
    state="complete"
    if [ "${CI_UI_EXPORT:-1}" = 1 ]; then
      raw="$out/attachments/$t"; rm -rf "$raw" "$raw-sorted"; mkdir -p "$raw"
      if xcrun xcresulttool export attachments --path "$bundle" --output-path "$raw" >> "$out/export.log" 2>&1; then
        python3 "$here/ci-screenshots-index.py" "$raw" "$raw-sorted" > /dev/null 2>&1
        n3="$(take "$raw-sorted" "result bundle")"
        find "$raw" -type f \( -name '*.ips' -o -name '*.crash' -o -name '*.mp4' \) -exec cp {} "$out/attachments/" \; 2>/dev/null
      fi
    fi
  elif [ -d "$bundle" ]; then state="INCOMPLETE (no Info.plist)"
  else state="none"; fi
  echo "pictures from: host folder $n1, simulator data folder $n2, result bundle $n3 (bundle: $state)" >&2
  echo $((n1 + n2 + n3))
}

# #33 F (1): one sample of the hung app into $2 (see the header). Never fails.
hang_sample() {
  local t="$1" file="$2" name="${CI_HANG_PROCESS:-VideoPlayer}" pid tool="${CI_SAMPLE:-sample}"
  pid="$(pgrep -x "$name" 2>/dev/null | head -n 1)" || true
  {
    echo "HANG SAMPLE for $t at $(date -u +%Y-%m-%dT%H:%M:%SZ): the test log reported a busy main thread."
    echo "process $name: ${pid:-not found by pgrep -x}"
  } > "$file" 2>/dev/null || true
  if ! command -v "$tool" > /dev/null 2>&1; then echo "no $tool command on this machine: no sample taken" >> "$file"; return 0; fi
  "$tool" "${pid:-$name}" 5 -file "$file.report" > "$file.out" 2>&1 || echo "$tool exited non-zero" >> "$file"
  { cat "$file.out"; echo "---- report ----"; cat "$file.report" 2>/dev/null || echo "(no report written)"; } >> "$file" 2>/dev/null || true
  rm -f "$file.out" "$file.report" 2>/dev/null || true
  echo "HANG SAMPLE written: $file"
}

# Watches the lines of $2 after line $3 until it is killed; samples once on the first hang line.
hang_watch() {
  local t="$1" log="$2" from="$3"
  while :; do
    if [ -f "$log" ] && tail -n +"$((from + 1))" "$log" 2>/dev/null | grep -qE 'main thread busy|Timed out while evaluating UI query'; then
      hang_sample "$t" "$dest/notes/hang-sample-$t.txt" || true
      return 0
    fi
    sleep 2
  done
}

if [ -n "$collect_only" ]; then
  for t in "$@"; do
    n="$(collect "$t")"
    if ! cut -f1 "$tsv" | grep -qx "$t"; then
      if [ -d "$out/xcresult/$t.xcresult" ] || [ -d "$out/screenshot-files/$t" ] || [ "$n" -gt 0 ]; then
        echo "$t${TAB}cut off (the step's time limit)${TAB}0${TAB}$n" >> "$tsv"
      else
        echo "$t${TAB}not started (the step ended first)${TAB}0${TAB}0" >> "$tsv"
      fi
    fi
  done
  python3 "$here/ci-ui-index.py" "$dest" "$here/screenshot-plan.tsv" "$tsv" "$@" > /dev/null
  echo "ci-ui-tests.sh --collect: $(find "$dest" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' \) | wc -l | tr -d ' ') pictures in $dest"
  exit 0
fi

status=0; stopped=""
for t in "$@"; do
  if [ -n "$stopped" ]; then
    echo "$t${TAB}not started (time budget)${TAB}0${TAB}0" >> "$tsv"; continue
  fi
  echo "================ UI TEST $t ================"
  case " ${CI_FRESH_SIM_BEFORE:-} " in
    *" $t "*)
      fstart="$(date +%s)"
      if [ -n "${CI_SIM_FRESH:-}" ]; then $CI_SIM_FRESH; else bash "$here/ci-sim.sh" fresh; fi > "$dest/notes/fresh-simulator-$t.txt" 2>&1 || true
      echo "clean simulator before $t: $(( $(date +%s) - fstart )) s (notes/fresh-simulator-$t.txt)" | tee -a "$dest/notes/fresh-simulator-$t.txt"
      ;;
  esac
  rm -rf "$out/screenshot-files/$t" "$out/xcresult/$t.xcresult"
  start="$(date +%s)"
  log_lines="$( (wc -l < "$out/test.log") 2>/dev/null | tr -d ' ')"; log_lines="${log_lines:-0}"
  hang_watch "$t" "$out/test.log" "$log_lines" &
  watcher=$!
  TEST_RUNNER_SCREENSHOT_DIR="$out/screenshot-files" bash "$here/ci-sim.sh" test "$out/test.log" -- "$xcb" test-without-building \
    -project VideoPlayer.xcodeproj -scheme VideoPlayerUITests -configuration Debug \
    -destination "platform=tvOS Simulator,id=${SIM_UDID:?SIM_UDID is not set}" \
    -clonedSourcePackagesDirPath build/SourcePackages -derivedDataPath build/DerivedData \
    -resultBundlePath "$out/xcresult/$t.xcresult" -parallel-testing-enabled NO \
    -only-testing:"VideoPlayerUITests/ScreenshotTests/$t"
  rc=$?
  # A sample in progress gets its 5 s to finish; then the watcher stops.
  if tail -n +"$((log_lines + 1))" "$out/test.log" 2>/dev/null | grep -qE 'main thread busy|Timed out while evaluating UI query' &&      ! grep -q -- '---- report ----\|no .* command on this machine' "$dest/notes/hang-sample-$t.txt" 2>/dev/null; then sleep 8; fi
  kill "$watcher" 2> /dev/null || true; wait "$watcher" 2> /dev/null || true
  secs=$(( $(date +%s) - start ))
  # After the one simulator retry ci-sim.sh may use another simulator (next runtime); it writes the new id to
  # $GITHUB_ENV, which only later STEPS read. The tests after this one must use it too.
  if [ -n "${GITHUB_ENV:-}" ] && [ -f "$GITHUB_ENV" ]; then
    u="$(grep '^SIM_UDID=' "$GITHUB_ENV" | tail -n 1 | cut -d= -f2-)"
    if [ -n "$u" ] && [ "$u" != "$SIM_UDID" ]; then echo "Simulator changed by the retry: $SIM_UDID -> $u"; SIM_UDID="$u"; fi
  fi
  if [ -e "$out/time-budget-stopped" ]; then result="stopped by the time budget"; stopped="$t"
  elif [ "$rc" -eq 124 ] && tail -n 3 "$out/test.log" | grep -q 'TIME BUDGET: not started'; then
    result="not started (time budget)"; stopped="$t"
  elif [ "$rc" -eq 0 ]; then result="passed"
  else result="failed (exit $rc)"; fi
  [ "$rc" -eq 0 ] || status=1
  pics="$(collect "$t")"   # the pictures, at once
  echo "$t${TAB}$result${TAB}$secs${TAB}$pics" >> "$tsv"
  echo "================ UI TEST $t: $result, ${secs} s, $pics pictures ================"
done
[ -n "$stopped" ] && echo "$stopped" > "$out/ui-tests-stopped.txt"

python3 "$here/ci-ui-index.py" "$dest" "$here/screenshot-plan.tsv" "$tsv" "$@" > /dev/null || status=1
# Keep DEST under about 45 MB (JPEG copies when the PNGs are bigger; sips is on the macOS runner only).
size="$(du -sm "$dest" | cut -f1)"
if [ "$size" -gt 45 ] && command -v sips > /dev/null; then
  for f in "$dest"/*.png; do [ -f "$f" ] && sips -s format jpeg -s formatOptions 80 "$f" --out "${f%.png}.jpg" > /dev/null && rm "$f"; done
  python3 "$here/ci-ui-index.py" "$dest" "$here/screenshot-plan.tsv" "$tsv" "$@" > /dev/null
  echo "Converted to JPEG: now $(du -sm "$dest" | cut -f1) MB" | tee -a "$dest/index.md"
fi
{ echo "## Screenshots: $(basename "$dest")"; echo; sed -n '1,40p' "$dest/index.md"; } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
exit "$status"
