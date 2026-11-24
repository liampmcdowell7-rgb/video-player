#!/usr/bin/env bash
# Self-test for scripts/ci-ui-tests.sh and scripts/ci-ui-index.py (#24 A, D) on Linux or macOS, with a fake xcodebuild
# (nothing real runs). Usage: bash scripts/test-ci-ui-tests.sh -> "ci-ui-tests self-test: passed N, failed M", exit 1 on
# any failure. The fake writes the pictures the way UITests/ScreenshotTests.swift does: NN-name.png and notes into
# $SCREENSHOT_DIR/<test>/ (here from TEST_RUNNER_SCREENSHOT_DIR), or into a fake simulator data folder.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
passed=0; failed=0
check() { if eval "$2"; then echo "ok    $1"; passed=$((passed + 1)); else echo "FAIL  $1"; failed=$((failed + 1)); sed 's/^/      /' "$S/stdout" | tail -n 25; fi; }

# Knob: $S/behaviour, one line per test: "<test> <what>", what = ok | fail | hang | simdata | nothing.
setup() {
  S="$(mktemp -d)"; mkdir -p "$S/bin" "$S/out" "$S/devices"
  cat > "$S/bin/fake-xcodebuild" <<'EOF'
#!/usr/bin/env bash
S="$(dirname "$(dirname "$0")")"
prev=""; bundle=""; test=""
for a in "$@"; do
  [ "$prev" = -resultBundlePath ] && bundle="$a"
  case "$a" in -only-testing:*) test="${a##*/}" ;; esac
  prev="$a"
done
mkdir -p "$bundle"
echo "$*" >> "$S/xb-args"
what="$(awk -v t="$test" '$1 == t {print $2}' "$S/behaviour")"
folder="$TEST_RUNNER_SCREENSHOT_DIR/$test"
[ "$what" = simdata ] && folder="$S/devices/UDID-1/data/Containers/Data/Application/ABC/tmp/vp-screenshots/$test"
mkdir -p "$folder"
names="$(awk -F'\t' -v t="$test" '$1 == t {print $2}' "$S/plan.tsv")"
first="$(echo "$names" | head -n 1)"; second="$(echo "$names" | sed -n 2p)"
echo "running $test ($what)"
case "$what" in
  ok|simdata) for n in $first $second; do printf 'PNG %s' "$n" > "$folder/$n.png"; done
     printf 'Identical to %s' "$first" > "$folder/$second-UNCHANGED.txt"
     printf 'end of scroll: identical to the picture before' > "$folder/$first-END-OF-SCROLL.txt"
     echo plist > "$bundle/Info.plist"; echo "** TEST SUCCEEDED **"; exit 0 ;;
  fail) printf 'PNG' > "$folder/$first.png"; printf 'PNG' > "$folder/$second-NOT-REACHED.png"
     printf 'The row could not be focused.' > "$folder/$second-NOT-REACHED.txt"
     echo plist > "$bundle/Info.plist"; echo "** TEST FAILED **"; exit 65 ;;
  hang) printf 'PNG' > "$folder/$first.png"; exec sleep 30 ;;   # killed by the budget; the bundle has no Info.plist
  busy) printf 'PNG' > "$folder/$first.png"; echo "Failed to get matching snapshot: main thread busy for 30.0s"; sleep 4
     echo plist > "$bundle/Info.plist"; echo "** TEST FAILED **"; exit 65 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$S/bin/fake-xcodebuild"
  cp "$here/screenshot-plan.tsv" "$S/plan.tsv"
}
run() {  # run TEST...   (DEST is $S/dest)
  PATH="$S/bin:$PATH" OUT="$S/out" SIM_UDID=UDID-1 CI_UI_XCODEBUILD=fake-xcodebuild CI_SIM_DEVICES="$S/devices" CI_UI_EXPORT=0 \
    GITHUB_STEP_SUMMARY="$S/summary" bash "$here/ci-ui-tests.sh" "$S/dest" "$@" > "$S/stdout" 2>&1
}
T1=test01_FirstLaunchAndEmptyScreens; T2=test02_AddASource; T3=test03_Settings; T5=test05_FilesSearchDiscover

# Every test passes: two pictures each, one call per test, each with its own result bundle.
setup; printf '%s ok\n' $T1 $T2 > "$S/behaviour"; run $T1 $T2; rc=$?
check "all pass: exit 0, pictures of both tests in DEST" "[ $rc -eq 0 ] && [ -f '$S/dest/02-home-empty.png' ] && [ -f '$S/dest/03-movies-empty.png' ] && [ -f '$S/dest/10-add-source-types.png' ]"
check "all pass: one xcodebuild call per test, its own result bundle" "[ -d '$S/out/xcresult/$T1.xcresult' ] && [ -d '$S/out/xcresult/$T2.xcresult' ] && [ \$(grep -c 'running test' '$S/stdout') -eq 2 ]"
check "index.md: tests table with seconds per picture" "grep -qF '| $T1 | passed |' '$S/dest/index.md' && grep -qE '\| $T1 \| passed \| 0:0[0-9] \| 2 \|' '$S/dest/index.md'"
check "index.md: every picture with its size" "grep -qE '^- \[02-home-empty\]\(02-home-empty.png\) [0-9]+ KB' '$S/dest/index.md'"
check "index.md: counts against the plan (22 planned for test01+test02, 4 taken; #36 group 3 added 11-form-webdav-keyboard-name, R331 11-form-webdav-entry-name, R326 12-form-smb-network-search and -found, R329 10-add-source-about-webdav)" "grep -qF 'Planned: 25. Taken: 4. Missing: 21. Failed (not reached): 0. Warnings (unchanged): 2.' '$S/dest/index.md'"
check "index.md: an unchanged picture is a WARNING line, and the picture is kept" "grep -qF -- '- WARNING: 03-movies-empty: Identical to 02-home-empty' '$S/dest/index.md' && [ -f '$S/dest/03-movies-empty.png' ] && [ -f '$S/dest/notes/03-movies-empty-UNCHANGED.txt' ]"
check "index.md: an end-of-scroll note is listed apart, not counted as a warning (#36 group 1 c)" "grep -qF -- '- 02-home-empty: end of scroll: identical to the picture before' '$S/dest/index.md' && grep -qF '## End of scroll (not a warning)' '$S/dest/index.md' && ! grep -qF -- '- WARNING: 02-home-empty' '$S/dest/index.md'"
check "results file has one row per test" "[ \$(grep -c '	passed	' '$S/out/ui-tests.tsv') -eq 2 ]"
check "the main-set artifact check passes on DEST" "bash '$here/ci-artifact-contents.sh' '$S/dest' main > /dev/null 2>&1"

# A failed test in the middle: the tests after it still run, its pictures and its NOT-REACHED note are kept.
setup; printf '%s ok\n%s fail\n%s ok\n' $T1 $T2 $T3 > "$S/behaviour"; run $T1 $T2 $T3; rc=$?
check "failed test in the middle: exit 1, the test after it still ran" "[ $rc -eq 1 ] && [ -f '$S/dest/30-settings.png' ] && grep -qF '| $T3 | passed |' '$S/dest/index.md'"
check "failed test in the middle: its result is 'failed (exit 65)', its picture kept" "grep -qF '| $T2 | failed (exit 65) |' '$S/dest/index.md' && [ -f '$S/dest/10-add-source-types.png' ]"
check "failed test in the middle: the NOT-REACHED reason is in index.md and counted as failed" "grep -qF -- '- 11-form-webdav: NOT REACHED. The row could not be focused.' '$S/dest/index.md' && grep -qF 'Failed (not reached): 1.' '$S/dest/index.md'"
check "failed test in the middle: the what-was-on-screen picture is marked not in the plan" "grep -qF '11-form-webdav-NOT-REACHED.png) ' '$S/dest/index.md' && grep -qF '(not in the plan)' '$S/dest/index.md'"

# The deadline: the running test is stopped with an INCOMPLETE bundle; its pictures still come out, the rest do not start.
setup; printf '%s ok\n%s hang\n%s ok\n' $T1 $T2 $T3 > "$S/behaviour"
t0=$(date +%s); CI_TEST_BUDGET_SECONDS=3 CI_STOP_GRACE_SECONDS=2 run $T1 $T2 $T3; rc=$?; took=$(( $(date +%s) - t0 ))
check "deadline: stopped within seconds, exit 1" "[ $rc -eq 1 ] && [ $took -lt 15 ]"
check "deadline: the stopped test's bundle is incomplete (no Info.plist), its picture still copied" "[ -d '$S/out/xcresult/$T2.xcresult' ] && ! [ -f '$S/out/xcresult/$T2.xcresult/Info.plist' ] && [ -f '$S/dest/10-add-source-types.png' ] && grep -q 'bundle: INCOMPLETE' '$S/stdout'"
check "deadline: index.md says TEST STOPPED BY THE TIME BUDGET with the last picture" "grep -qF 'TEST STOPPED BY THE TIME BUDGET: pictures up to 10-add-source-types** (stopped in $T2; not run: $T3)' '$S/dest/index.md'"
check "deadline: the next test was not started, and says so" "! [ -d '$S/out/xcresult/$T3.xcresult' ] && grep -qF '| $T3 | not started (time budget) |' '$S/dest/index.md'"
check "deadline: the earlier test's pictures are there" "[ -f '$S/dest/02-home-empty.png' ] && [ -f '$S/dest/03-movies-empty.png' ]"

# The step's own time limit kills the runner in the middle of a test (no budget stop): --collect still copies that test's
# pictures and says the test was cut off; the test after it is listed as not started.
setup; printf '%s ok\n%s hang\n%s ok\n' $T1 $T2 $T3 > "$S/behaviour"
PATH="$S/bin:$PATH" OUT="$S/out" SIM_UDID=UDID-1 CI_UI_XCODEBUILD=fake-xcodebuild CI_SIM_DEVICES="$S/devices" CI_UI_EXPORT=0 \
  timeout -s KILL 4 bash "$here/ci-ui-tests.sh" "$S/dest" $T1 $T2 $T3 > "$S/stdout" 2>&1
PATH="$S/bin:$PATH" OUT="$S/out" CI_SIM_DEVICES="$S/devices" CI_UI_EXPORT=0 bash "$here/ci-ui-tests.sh" --collect "$S/dest" $T1 $T2 $T3 >> "$S/stdout" 2>&1; rc=$?
check "step killed mid-test: --collect copies the cut-off test's picture (exit 0)" "[ $rc -eq 0 ] && [ -f '$S/dest/10-add-source-types.png' ] && [ -f '$S/dest/02-home-empty.png' ]"
check "step killed mid-test: index.md says cut off, and not started for the next test" "grep -qF \"| $T2 | cut off (the step's time limit) |\" '$S/dest/index.md' && grep -qF '| $T3 | not started (the step ended first) |' '$S/dest/index.md' && grep -qF '| $T1 | passed |' '$S/dest/index.md'"

# The one simulator retry moved to another simulator (ci-sim.sh wrote SIM_UDID=UDID-2 to $GITHUB_ENV): the next test uses it.
setup; printf '%s ok\n%s ok\n' $T1 $T2 > "$S/behaviour"; printf 'SIM_UDID=UDID-1\nSIM_UDID=UDID-2\n' > "$S/env"
PATH="$S/bin:$PATH" OUT="$S/out" SIM_UDID=UDID-1 GITHUB_ENV="$S/env" CI_UI_XCODEBUILD=fake-xcodebuild CI_SIM_DEVICES="$S/devices" \
  CI_UI_EXPORT=0 bash "$here/ci-ui-tests.sh" "$S/dest" $T1 $T2 > "$S/stdout" 2>&1
check "simulator changed by the retry: the later tests use the new id" "grep -q 'Simulator changed by the retry: UDID-1 -> UDID-2' '$S/stdout' && sed -n 1p '$S/xb-args' | grep -q 'id=UDID-1' && sed -n 2p '$S/xb-args' | grep -q 'id=UDID-2'"

# #33 F (1): a test that fails with "main thread busy": the watcher samples the app while the test still runs, the note
# hang-sample-<test>.txt is kept, the job's result is the test's own (failed), and the next test runs and is not sampled.
setup; printf '%s ok
%s busy
%s ok
' $T1 $T2 $T3 > "$S/behaviour"
cat > "$S/bin/fake-sample" <<'EOF'
#!/usr/bin/env bash
out=""; prev=""; for a in "$@"; do [ "$prev" = -file ] && out="$a"; prev="$a"; done
echo "Call graph: fake main thread stack ($1 $2)" > "$out"
EOF
chmod +x "$S/bin/fake-sample"
CI_SAMPLE=fake-sample CI_HANG_PROCESS=no-such-process-vp run $T1 $T2 $T3; rc=$?
check "hang capture: hang-sample note with the sample's report, for the busy test only" "[ -f '$S/dest/notes/hang-sample-$T2.txt' ] && grep -q 'Call graph: fake main thread stack (no-such-process-vp 5)' '$S/dest/notes/hang-sample-$T2.txt' && ! grep -q 'SAMPLE FAILED' '$S/dest/notes/hang-sample-$T2.txt' && ! [ -e '$S/dest/notes/hang-sample-$T1.txt' ] && ! [ -e '$S/dest/notes/hang-sample-$T3.txt' ]"
check "hang capture: the result is the test's own (exit 1, failed 65), the next test still passed" "[ $rc -eq 1 ] && grep -qF '| $T2 | failed (exit 65) |' '$S/dest/index.md' && grep -qF '| $T3 | passed |' '$S/dest/index.md'"
# #36 group 5a: a sample that cannot open the process ("pid_for_task ... failed", "Sampling process 0") is marked SAMPLE
# FAILED, the pid line names both lookups, and an app-log note is written (here: no simulator id, so it says so).
setup; printf '%s busy
' $T2 > "$S/behaviour"
cat > "$S/bin/fail-sample" <<'EOF'
#!/usr/bin/env bash
echo "sample[1]: pid_for_task(c03) failed with error 5"; echo "Sampling process 0 for 5 seconds"
EOF
chmod +x "$S/bin/fail-sample"
CI_SAMPLE=fail-sample CI_HANG_PROCESS=no-such-process-vp run $T2; rc=$?
check "hang capture: a sample without access is marked SAMPLE FAILED, both pid lookups named, app-log note written" "[ $rc -eq 1 ] && grep -q 'SAMPLE FAILED' '$S/dest/notes/hang-sample-$T2.txt' && grep -q 'simulator launchd pid' '$S/dest/notes/hang-sample-$T2.txt' && grep -q 'host pgrep -x pid none found' '$S/dest/notes/hang-sample-$T2.txt' && [ -f '$S/dest/notes/hang-applog-$T2.txt' ]"
# No sample tool at all: the note says so and nothing else changes.
setup; printf '%s busy
' $T2 > "$S/behaviour"; CI_SAMPLE=no-such-sample-tool run $T2; rc=$?
check "hang capture without the sample tool: a note saying so, exit as the test (1)" "[ $rc -eq 1 ] && grep -q 'no no-such-sample-tool command' '$S/dest/notes/hang-sample-$T2.txt'"

# #34 4 (R242): CI_FRESH_SIM_BEFORE gives the named test a clean simulator first (here a fake that logs the call), only
# that test, before its xcodebuild call; the note says how long it took; a failing fresh step does not change the result.
setup; printf '%s ok\n%s ok\n%s ok\n' $T1 $T2 $T3 > "$S/behaviour"
cat > "$S/bin/fake-fresh" <<EOF
#!/usr/bin/env bash
echo "fresh call \$(grep -c 'running test' '$S/stdout' 2>/dev/null)" >> '$S/fresh-calls'
echo "FRESH SIMULATOR READY after 0 s"
EOF
chmod +x "$S/bin/fake-fresh"
CI_FRESH_SIM_BEFORE="$T2" CI_SIM_FRESH=fake-fresh run $T1 $T2 $T3; rc=$?
check "clean simulator: called once, for the named test only, all tests still pass (exit 0)" "[ $rc -eq 0 ] && [ \$(wc -l < '$S/fresh-calls') -eq 1 ] && [ -f '$S/dest/notes/fresh-simulator-$T2.txt' ] && ! [ -e '$S/dest/notes/fresh-simulator-$T1.txt' ] && ! [ -e '$S/dest/notes/fresh-simulator-$T3.txt' ]"
check "clean simulator: before the named test's xcodebuild call (after the first test's, before the second's)" "grep -qx 'fresh call 1' '$S/fresh-calls'"
check "clean simulator: the note has the fresh step's output and its seconds" "grep -q 'FRESH SIMULATOR READY' '$S/dest/notes/fresh-simulator-$T2.txt' && grep -qE 'clean simulator before $T2: [0-9]+ s' '$S/dest/notes/fresh-simulator-$T2.txt'"
setup; printf '%s ok\n' $T2 > "$S/behaviour"; CI_FRESH_SIM_BEFORE="$T2" CI_SIM_FRESH=false run $T2; rc=$?
check "clean simulator: a failing fresh step does not change the result (the test still runs and passes)" "[ $rc -eq 0 ] && grep -qF '| $T2 | passed |' '$S/dest/index.md' && [ -f '$S/dest/notes/fresh-simulator-$T2.txt' ]"

# The host folder could not be written: the pictures are found in the simulator's data folder.
setup; printf '%s simdata\n' $T5 > "$S/behaviour"; run $T5; rc=$?
check "simulator data folder: pictures found there and copied" "[ $rc -eq 0 ] && [ -f '$S/dest/70-files-sources.png' ] && grep -q 'simulator data folder' '$S/out/ui-tests-sources.txt'"

# Nothing at all: the index says no picture and exits non-zero (the artifact check then fails loudly too).
setup; printf '%s nothing\n' $T1 > "$S/behaviour"; run $T1; rc=$?
check "no picture: exit 1, index says so, Missing counts every planned shot" "[ $rc -eq 1 ] && grep -qF -- '- no picture' '$S/dest/index.md' && grep -qF 'Planned: 5. Taken: 0. Missing: 5.' '$S/dest/index.md'"

# The plan matches the tests: every literal shot("NN-...") name in UITests/ScreenshotTests.swift is planned, except the
# "-missing" pictures of what was on screen instead (test12, taken with a NOT-REACHED note; "not in the plan" in index.md).
lit="$(grep -oE 'shot\("[0-9]{2,3}-[a-z0-9-]+"\)' "$here/../UITests/ScreenshotTests.swift" | sed -E 's/shot\("(.*)"\)/\1/' | grep -v -- '-missing$' | sort -u)"
miss="$(while IFS= read -r n; do [ -n "$n" ] && ! cut -f2 "$here/screenshot-plan.tsv" | grep -qx "$n" && echo "$n"; done <<< "$lit")"
S="$(mktemp -d)"; echo "not planned: $miss" > "$S/stdout"
check "plan: every literal shot name in ScreenshotTests.swift is in screenshot-plan.tsv" "[ -z \"$miss\" ] && [ -n \"$lit\" ]"
check "plan: 215 planned pictures (80 part 1, 72 part 2, 33 accessibility; #25 adds 10-add-source-learn-more, #26 the two key-set pictures, #30 two network-search and two long-caption pictures, #32 the toolbars and menus moved to part 2 with 16 more, #34 4 moved test12 and test13, 14 pictures, to part 2; #34 5a adds the two Continue Watching caption pictures; #36 group 3 adds 11-form-webdav-keyboard-name; R331 adds 11-form-webdav-entry-name; R326 adds 12-form-smb-network-search and 12-form-smb-network-found; R329 adds 10-add-source-about-webdav; R333 adds 36-settings-online-lookup-key-entry and 66-move-sheet-entry-show; R334 adds 36-settings-online-lookup-region; R335 adds 53-movies-focused and 54-shows-focused; R340 adds 24-player-episodes-tab, 24-player-stats-tab and 27-player-after-play-now; R341 adds 79-person-page; R342 adds 75-search-discover-cards, 75-discover-card-menu and 75-discover-title-page; R343 adds 76-search-recent; R344 renames the toolbar's -sort-menu and -filter-menu pictures to -sort-filter-menu and -sort-submenu; R348 adds 44-settings-reselected; R392 adds 22-episode-page and 22-episode-page-scrolled-1; R443 adds 12 library grid scroll pictures, six each for Movies and Shows; R449 adds the ten edit-screen pictures; R452 adds 57-movie-detail-bright; R454 adds 24-player-video-tab; R455 adds the three artwork gallery pictures 80-artwork-gallery-poster, -background and -logo; R456 renames 32-settings-home-screen to 32-settings-general and adds 36-settings-metadata-and-artwork, 37-settings-sync-and-backup and 45-settings-language)" "[ \$(grep -vc '^#' '$here/screenshot-plan.tsv') -eq 215 ]"

echo "ci-ui-tests self-test: passed $passed, failed $failed"
[ "$failed" -eq 0 ]
