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
     echo plist > "$bundle/Info.plist"; echo "** TEST SUCCEEDED **"; exit 0 ;;
  fail) printf 'PNG' > "$folder/$first.png"; printf 'PNG' > "$folder/$second-NOT-REACHED.png"
     printf 'The row could not be focused.' > "$folder/$second-NOT-REACHED.txt"
     echo plist > "$bundle/Info.plist"; echo "** TEST FAILED **"; exit 65 ;;
  hang) printf 'PNG' > "$folder/$first.png"; exec sleep 30 ;;   # killed by the budget; the bundle has no Info.plist
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
check "index.md: counts against the plan (18 planned for test01+test02, 4 taken)" "grep -qF 'Planned: 18. Taken: 4. Missing: 14. Failed (not reached): 0. Warnings (unchanged): 2.' '$S/dest/index.md'"
check "index.md: an unchanged picture is a WARNING line, and the picture is kept" "grep -qF -- '- WARNING: 03-movies-empty: Identical to 02-home-empty' '$S/dest/index.md' && [ -f '$S/dest/03-movies-empty.png' ] && [ -f '$S/dest/notes/03-movies-empty-UNCHANGED.txt' ]"
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
check "plan: 140 planned pictures (81 part 1, 26 part 2, 33 accessibility; #25 adds 10-add-source-learn-more)" "[ \$(grep -vc '^#' '$here/screenshot-plan.tsv') -eq 140 ]"

echo "ci-ui-tests self-test: passed $passed, failed $failed"
[ "$failed" -eq 0 ]
