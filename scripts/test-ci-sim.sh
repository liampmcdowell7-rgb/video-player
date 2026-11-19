#!/usr/bin/env bash
# Self-test for scripts/ci-sim.sh on Linux or macOS, with a fake `xcrun` and a fake xcodebuild (nothing real is booted).
# Usage: bash scripts/test-ci-sim.sh   -> "ci-sim self-test: passed N, failed M", exit 1 when anything failed.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
passed=0; failed=0
check() { if eval "$2"; then echo "ok    $1"; passed=$((passed + 1)); else echo "FAIL  $1"; failed=$((failed + 1)); fi; }

# One scenario = a fresh folder with fake tools. Knobs (files in $S): boot-fails (count), xb-script (lines: what each
# fake xcodebuild call prints and its exit code, "message|code"), devices.json (the simulators per runtime; default one
# Apple TV 4K on tvOS 27.0), runtime-broken (UDIDs whose runtime always fails to load), sdk (the Simulator SDK version;
# default 27.2).
DEV_270='"com.apple.CoreSimulator.SimRuntime.tvOS-27-0":[{"name":"Apple TV 4K (3rd generation) (at 1080p)","udid":"UDID-1","isAvailable":true}]'
DEV_272='"com.apple.CoreSimulator.SimRuntime.tvOS-27-2":[{"name":"Apple TV 4K (4th generation) (at 1080p)","udid":"UDID-2","isAvailable":true}]'
setup() {
  S="$(mktemp -d)"; mkdir -p "$S/bin" "$S/out"
  cat > "$S/bin/xcrun" <<'EOF'
#!/usr/bin/env bash
S="$(dirname "$(dirname "$0")")"
echo "xcrun $*" >> "$S/calls"
if [ "$1" = --sdk ]; then cat "$S/sdk" 2>/dev/null || echo 27.2; exit 0; fi
[ "$1" = simctl ] || exit 0; shift
case "$1 ${2:-} ${3:-}" in
  "list runtimes"*) echo "tvOS 27.0 (27.0 - 24J360) - com.apple.CoreSimulator.SimRuntime.tvOS-27-0" ;;
  "runtime list"*) echo "-- tvOS --"; echo "tvOS 27.0 (24J360) - Ready" ;;
  "list devices available")
    if [ "${4:-}" = "-j" ]; then
      cat "$S/devices.json" 2>/dev/null || echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.tvOS-27-0":[{"name":"Apple TV 4K (3rd generation) (at 1080p)","udid":"UDID-1","isAvailable":true}]}}'
    else echo "Apple TV 4K (3rd generation) (at 1080p) (UDID-1) (Shutdown)"; fi ;;
  "list devices"*) b="$(cat "$S/booted" 2>/dev/null)"; [ -n "$b" ] && echo "Apple TV 4K ($b) (Booted)" || echo "Apple TV 4K (none) (Shutdown)" ;;
  "boot"*)
    if grep -qx "$2" "$S/runtime-broken" 2>/dev/null; then
      echo "Unable to boot device: Failed to load requested runtime bundle (tvOS.simruntime)" >&2; exit 1
    fi
    n="$(cat "$S/boot-fails" 2>/dev/null || echo 0)"
    if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$S/boot-fails"; echo "Unable to boot: Failed to load requested runtime bundle" >&2; exit 1; fi
    echo "$2" > "$S/booted" ;;
  "bootstatus"*) [ "$(cat "$S/booted" 2>/dev/null)" = "$2" ] && echo "Device already booted" || exit 1 ;;
  "shutdown"*) rm -f "$S/booted" ;;
  "erase"*) echo erased >> "$S/erased" ;;
esac
EOF
  cat > "$S/bin/fake-xcodebuild" <<'EOF'
#!/usr/bin/env bash
S="$(dirname "$(dirname "$0")")"
n=$(( $(cat "$S/xb-count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/xb-count"
line="$(sed -n "${n}p" "$S/xb-script")"; [ -n "$line" ] || line="TEST SUCCEEDED|0"
echo "$*" >> "$S/xb-args"
prev=""; for a in "$@"; do [ "$prev" = -resultBundlePath ] && { [ -e "$a" ] && { echo "bundle exists"; exit 9; }; mkdir -p "$a"; }; prev="$a"; done
# "SLEEP n|code": a test run that takes n seconds (exec, so a signal reaches the sleeping process itself).
case "$line" in "SLEEP "*) s="${line#SLEEP }"; exec sleep "${s%|*}" ;; esac
echo "${line%|*}"; exit "${line##*|}"
EOF
  chmod +x "$S/bin/xcrun" "$S/bin/fake-xcodebuild"
  : > "$S/xb-script"
}
run() { PATH="$S/bin:$PATH" OUT="$S/out" GITHUB_ENV="$S/env" GITHUB_STEP_SUMMARY="$S/summary" SIM_UDID=UDID-1 \
        BOOT_WAIT_SECONDS=5 bash "$here/ci-sim.sh" "$@" > "$S/stdout" 2>&1; }
# Each call has its own result bundle, as each workflow step does.
xb() { run test "$S/out/test.log" -- fake-xcodebuild -resultBundlePath "$S/out/${1:-R}.xcresult"; }

setup; run prepare; rc=$?
check "prepare: boots and waits, exit 0" "[ $rc -eq 0 ]"
check "prepare: boot then bootstatus -b were called" "grep -q 'simctl boot UDID-1' '$S/calls' && grep -q 'bootstatus UDID-1 -b' '$S/calls'"
check "prepare: SIM_UDID written to GITHUB_ENV" "grep -qx 'SIM_UDID=UDID-1' '$S/env'"
check "prepare: both runtime lists printed and saved" "grep -q 'list runtimes' '$S/calls' && grep -q 'runtime list' '$S/calls' && grep -q 24J360 '$S/out/sim-runtimes.txt'"
check "prepare: 'ready after N s (retries: 0/1)' in the summary" "grep -qE 'Simulator ready after [0-9]+ s \(retries: 0/1\)' '$S/summary'"

setup; echo 1 > "$S/boot-fails"; run prepare; rc=$?
check "boot fails once: retried, exit 0" "[ $rc -eq 0 ]"
check "boot fails once: shutdown all + erase done, retry printed" "grep -q 'shutdown all' '$S/calls' && [ -s '$S/erased' ] && grep -q 'SIMULATOR RETRY: boot or bootstatus failed' '$S/stdout'"
check "boot fails once: summary says retries 1/1" "grep -q '(retries: 1/1)' '$S/summary'"

setup; echo 5 > "$S/boot-fails"; run prepare; rc=$?
check "boot keeps failing: exit non-zero after one retry" "[ $rc -ne 0 ] && [ \$(grep -c 'erase' '$S/calls') -eq 1 ]"

setup; run prepare; printf '%s\n' "Invalid request: Failed to load requested runtime bundle|65" "TEST SUCCEEDED|0" > "$S/xb-script"; xb; rc=$?
check "runtime error in the test run: retried once and passes" "[ $rc -eq 0 ] && [ \$(cat '$S/xb-count') -eq 2 ]"
check "runtime error: old result bundle removed before the retry" "! grep -q 'bundle exists' '$S/out/test.log'"
check "runtime error: retry and reason in log and ready file" "grep -q 'SIMULATOR RETRY' '$S/out/test.log' && grep -q 'Failed to load requested runtime bundle' '$S/out/sim-ready.txt' && grep -q 'retries: 1/1' '$S/out/sim-ready.txt'"

setup; run prepare; printf '%s\n' "error: Failed to prepare device for impending launch|70" > "$S/xb-script"; xb
check "'Failed to prepare device' is also retried" "[ \$(cat '$S/xb-count') -eq 2 ]"

setup; run prepare; printf '%s\n' "Test Case 'x' failed (1.0 seconds)|65" > "$S/xb-script"; xb; rc=$?
check "a failing test is NOT retried" "[ $rc -ne 0 ] && [ \$(cat '$S/xb-count') -eq 1 ] && ! [ -s '$S/erased' ]"

setup; run prepare; printf '%s\n' "Failed to load requested runtime bundle|65" "Failed to load requested runtime bundle|65" "Failed to load requested runtime bundle|65" > "$S/xb-script"
xb first; rc1=$?; xb second; rc2=$?
check "at most one retry per job: second runtime failure not retried" "[ $rc1 -ne 0 ] && [ $rc2 -ne 0 ] && [ \$(cat '$S/xb-count') -eq 3 ] && [ \$(grep -c erased '$S/erased') -eq 1 ] && grep -q 'already retried once' '$S/stdout'"

setup; run prepare; printf '%s\n' "Failed to load requested runtime bundle|65" > "$S/xb-script"
SIM_RETRY_HOOK="echo hook-ran > '$S/hook'" xb
check "SIM_RETRY_HOOK runs after the retry" "[ -s '$S/hook' ]"

setup; run test "$S/out/test.log" -- fake-xcodebuild; rc=$?
check "exit code of a passing run is 0, no retry" "[ $rc -eq 0 ] && ! [ -e '$S/out/sim-retry-used' ]"

# Time budget (#16 item 1.8): the first stage marker was 100 s ago.
budget() { printf '%s\tPrepare\n' $(( $(date +%s) - 100 )) > "$S/out/stage-times.txt"; }
setup; run prepare; budget; printf '%s\n' "SLEEP 20|0" > "$S/xb-script"
t0=$(date +%s); CI_TEST_DEADLINE_SECONDS=102 xb; rc=$?; took=$(( $(date +%s) - t0 ))
check "time budget: a run past the deadline is stopped (SIGTERM) and fails" "[ $rc -ne 0 ] && [ $took -lt 12 ] && grep -q 'TIME BUDGET: stopping' '$S/out/test.log'"
setup; run prepare; budget
CI_TEST_DEADLINE_SECONDS=50 xb; rc=$?
check "time budget: after the deadline nothing is started (exit 124)" "[ $rc -eq 124 ] && ! [ -e '$S/xb-count' ] && grep -q 'TIME BUDGET: not started' '$S/out/test.log'"
setup; run prepare; budget
CI_TEST_DEADLINE_SECONDS=1000 xb; rc=$?
check "time budget: a run inside the budget passes and says how much time it had" "[ $rc -eq 0 ] && grep -qE 'time budget: [0-9]+ s left' '$S/out/test.log'"

# #21 A: runtime choice and retry on the next runtime.
lastenv() { grep '^SIM_UDID=' "$S/env" | tail -n 1; }
setup; echo "{\"devices\":{$DEV_270,$DEV_272}}" > "$S/devices.json"; run prepare; rc=$?
check "27.0 and 27.2 present, SDK 27.2: picks 27.2 (the runtime before the device name)" "[ $rc -eq 0 ] && [ \"\$(lastenv)\" = SIM_UDID=UDID-2 ] && grep -q 'matches the Simulator SDK 27.2' '$S/stdout'"
check "picker prints every runtime found and why it chose" "grep -q 'runtime found: tvOS 27.2' '$S/stdout' && grep -q 'runtime found: tvOS 27.0' '$S/stdout' && grep -q '^why: ' '$S/stdout'"
check "'Boot and retry' is its own stage" "grep -q \$'\tBoot and retry\$' '$S/out/stage-times.txt'"

setup; echo "{\"devices\":{$DEV_270,$DEV_272}}" > "$S/devices.json"; echo 27.0 > "$S/sdk"; echo UDID-1 > "$S/runtime-broken"; run prepare; rc=$?
check "27.0 fails to load, 27.2 works: 27.0 marked unavailable, booted on 27.2" "[ $rc -eq 0 ] && [ \"\$(lastenv)\" = SIM_UDID=UDID-2 ] && grep -q 'tvOS-27-0' '$S/out/sim-excluded-runtimes' && grep -q 'tvOS-27-2' '$S/out/sim-ready.txt'"
check "27.0 fails to load: one retry, no erase, ready file says unavailable" "grep -q 'retries: 1/1' '$S/out/sim-ready.txt' && grep -q 'marked unavailable' '$S/out/sim-ready.txt' && ! [ -s '$S/erased' ]"

setup; echo "{\"devices\":{$DEV_270,$DEV_272}}" > "$S/devices.json"; echo 27.0 > "$S/sdk"; run prepare
printf '%s\n' "Failed to load requested runtime bundle (tvOS 27.0.simruntime)|65" "TEST SUCCEEDED|0" > "$S/xb-script"
SIM_UDID=UDID-1; run test "$S/out/test.log" -- fake-xcodebuild -destination "platform=tvOS Simulator,id=UDID-1" -resultBundlePath "$S/out/R.xcresult"; rc=$?
check "test run: runtime fails to load, retried once on 27.2 with the new id" "[ $rc -eq 0 ] && sed -n 2p '$S/xb-args' | grep -q 'id=UDID-2' && [ \"\$(lastenv)\" = SIM_UDID=UDID-2 ]"

setup; echo "{\"devices\":{$DEV_270}}" > "$S/devices.json"; run prepare; rc=$?
check "only 27.0 exists (SDK 27.2): the older runtime is used and the log says why" "[ $rc -eq 0 ] && [ \"\$(lastenv)\" = SIM_UDID=UDID-1 ] && grep -q 'none is newer; older runtime used' '$S/stdout'"
setup; echo "{\"devices\":{$DEV_270}}" > "$S/devices.json"; echo 1 > "$S/boot-fails"; run prepare; rc=$?
check "only 27.0 exists and it fails once: no other runtime, erased and retried on it" "[ $rc -eq 0 ] && grep -q 'No other tvOS runtime' '$S/stdout' && [ -s '$S/erased' ] && [ \"\$(lastenv)\" = SIM_UDID=UDID-1 ]"
setup; echo "{\"devices\":{$DEV_270}}" > "$S/devices.json"; echo UDID-1 > "$S/runtime-broken"; run prepare; rc=$?
check "only 27.0 exists and it never loads: fails after one retry" "[ $rc -ne 0 ] && grep -q 'did not boot, also not after the retry' '$S/stdout'"
python3 "$here/ci-test-report.py" "$S/out/test.log" "$S/report.md" > /dev/null
check "report: 'NO TESTS RAN: simulator runtime failed to load' with the cause line" "grep -q 'NO TESTS RAN: simulator runtime failed to load' '$S/report.md' && grep -q 'Cause: .*Failed to load requested runtime bundle' '$S/report.md'"
printf '%s\n' "Test Case '-[AppLogicTests.SampleTests testA]' passed (0.010 seconds)." > "$S/ok.log"
python3 "$here/ci-test-report.py" "$S/ok.log" "$S/ok.md" > /dev/null
check "report: a run with results has no NO TESTS RAN line" "! grep -q 'NO TESTS RAN' '$S/ok.md' && grep -q '| AppLogicTests | 1 | 0 | 0 |' '$S/ok.md'"

echo "ci-sim self-test: passed $passed, failed $failed"
[ "$failed" -eq 0 ]
