#!/usr/bin/env bash
# Self-test for scripts/ci-sim.sh on Linux or macOS, with a fake `xcrun` and a fake xcodebuild (nothing real is booted).
# Usage: bash scripts/test-ci-sim.sh   -> "ci-sim self-test: passed N, failed M", exit 1 when anything failed.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
passed=0; failed=0
check() { if eval "$2"; then echo "ok    $1"; passed=$((passed + 1)); else echo "FAIL  $1"; failed=$((failed + 1)); fi; }

# One scenario = a fresh folder with fake tools. Knobs (files in $S): boot-fails (count), xb-script (lines: what each
# fake xcodebuild call prints and its exit code, "message|code").
setup() {
  S="$(mktemp -d)"; mkdir -p "$S/bin" "$S/out"
  cat > "$S/bin/xcrun" <<'EOF'
#!/usr/bin/env bash
S="$(dirname "$(dirname "$0")")"
echo "xcrun $*" >> "$S/calls"
[ "$1" = simctl ] || exit 0; shift
case "$1 ${2:-} ${3:-}" in
  "list runtimes"*) echo "tvOS 27.0 (27.0 - 24J360) - com.apple.CoreSimulator.SimRuntime.tvOS-27-0" ;;
  "runtime list"*) echo "-- tvOS --"; echo "tvOS 27.0 (24J360) - Ready" ;;
  "list devices available")
    if [ "${4:-}" = "-j" ]; then
      echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.tvOS-27-0":[{"name":"Apple TV 4K (3rd generation) (at 1080p)","udid":"UDID-1","isAvailable":true}]}}'
    else echo "Apple TV 4K (3rd generation) (at 1080p) (UDID-1) (Shutdown)"; fi ;;
  "list devices"*) [ -e "$S/booted" ] && echo "Apple TV 4K (UDID-1) (Booted)" || echo "Apple TV 4K (UDID-1) (Shutdown)" ;;
  "boot"*)
    n="$(cat "$S/boot-fails" 2>/dev/null || echo 0)"
    if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$S/boot-fails"; echo "Unable to boot: Failed to load requested runtime bundle" >&2; exit 1; fi
    touch "$S/booted" ;;
  "bootstatus"*) [ -e "$S/booted" ] && echo "Device already booted" || exit 1 ;;
  "shutdown"*) rm -f "$S/booted" ;;
  "erase"*) echo erased >> "$S/erased" ;;
esac
EOF
  cat > "$S/bin/fake-xcodebuild" <<'EOF'
#!/usr/bin/env bash
S="$(dirname "$(dirname "$0")")"
n=$(( $(cat "$S/xb-count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/xb-count"
line="$(sed -n "${n}p" "$S/xb-script")"; [ -n "$line" ] || line="TEST SUCCEEDED|0"
prev=""; for a in "$@"; do [ "$prev" = -resultBundlePath ] && { [ -e "$a" ] && { echo "bundle exists"; exit 9; }; mkdir -p "$a"; }; prev="$a"; done
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

echo "ci-sim self-test: passed $passed, failed $failed"
[ "$failed" -eq 0 ]
