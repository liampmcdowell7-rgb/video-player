#!/usr/bin/env bash
# CI only (compile-check.yml, every job that uses the tvOS Simulator). Makes the simulator robust against runner problems
# such as run 44424319207 ("Failed to load requested runtime bundle ... Malformed bundle does not contain an identifier"),
# which are not caused by our code.
#
#   ci-sim.sh prepare
#       Prints `xcrun simctl list runtimes` and `xcrun simctl runtime list` (log and $OUT/sim-runtimes.txt), picks the
#       simulator by name (ci-pick-simulator.py), boots it (xcrun simctl boot) and waits for it (xcrun simctl bootstatus
#       UDID -b). If boot or the wait fails: the one retry of this job (below). Writes SIM_UDID to $GITHUB_ENV.
#   ci-sim.sh test LOG -- xcodebuild ...
#       Runs one xcodebuild test call, output appended to LOG. If it fails AND its own output contains "Failed to load
#       requested runtime bundle" or "Failed to prepare device", and the job has not retried yet: the one retry, then the
#       same call again (its -resultBundlePath is removed first). Any other failure is returned as it is, never retried.
#       $SIM_RETRY_HOOK, when set, is run after the simulator is back (for a simulator setting the erase turned off).
#
# The retry: shut down all simulators, erase the chosen one, boot it, wait for it. At most once per job (marker file in
# $OUT), printed as "SIMULATOR RETRY: <reason>". $OUT/sim-ready.txt holds "Simulator ready after N s (retries: 0/1)";
# ci-stage.sh --summary puts it and the runtime lists into the job summary.
#
# Time budget (#16 item 1.8): with CI_TEST_DEADLINE_SECONDS set, every `test` call must end that many seconds after the
# job's first stage marker ($OUT/stage-times.txt, written by ci-stage.sh in the first step). A call is not started when
# the deadline has passed ("TIME BUDGET: not started"), and one still running then gets SIGTERM, and SIGKILL 30 s later
# ("TIME BUDGET: stopping"). So the export and upload steps after it always have the rest of the job's 30 minutes, also
# when the build before was slow. Whether xcodebuild still leaves a readable result bundle after SIGTERM is unverified.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${OUT:-build/ci}"
case "$out" in /*) ;; *) out="${GITHUB_WORKSPACE:-.}/$out" ;; esac
mkdir -p "$out"
retry_marker="$out/sim-retry-used"
ready_file="$out/sim-ready.txt"
BOOT_WAIT_SECONDS="${BOOT_WAIT_SECONDS:-180}"
RUNTIME_PATTERN='Failed to load requested runtime bundle|Failed to prepare device'

# Runs a command, stopping it after $1 seconds (bootstatus -b can wait forever on a broken runtime).
with_timeout() {
  local seconds="$1"; shift
  "$@" & local pid=$!
  ( sleep "$seconds"; kill -TERM "$pid" 2>/dev/null ) & local watcher=$!
  wait "$pid"; local rc=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  return $rc
}

# Seconds left before CI_TEST_DEADLINE_SECONDS (after the first stage marker); empty when no budget applies.
seconds_left() {
  [ -n "${CI_TEST_DEADLINE_SECONDS:-}" ] || return 0
  local first; first="$(head -n 1 "$out/stage-times.txt" 2>/dev/null | cut -f1)"
  [ -n "$first" ] || first="$(date +%s)"
  echo $(( first + CI_TEST_DEADLINE_SECONDS - $(date +%s) ))
}

# Runs a command until it ends or $1 seconds pass; then SIGTERM, and SIGKILL 30 s later.
with_budget() {
  local seconds="$1"; shift
  "$@" & local pid=$!
  (
    sleep "$seconds"
    kill -0 "$pid" 2>/dev/null || exit 0
    echo "================ TIME BUDGET: stopping the test run (CI_TEST_DEADLINE_SECONDS=$CI_TEST_DEADLINE_SECONDS) so the export and upload still run ================"
    # Not SIGINT: a command started with & in a non-interactive shell ignores it (found by scripts/test-ci-sim.sh).
    kill -TERM "$pid" 2>/dev/null; sleep 30; kill -KILL "$pid" 2>/dev/null
  ) & local watcher=$!
  wait "$pid"; local rc=$?
  # The watcher's own sleep first (after the watcher dies it is no longer its child), else it keeps the output pipe open.
  pkill -P "$watcher" 2>/dev/null; kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  return $rc
}

# Runs the test command, under the time budget when there is one.
budgeted() {
  local left; left="$(seconds_left)"
  if [ -z "$left" ]; then "$@"; return; fi
  if [ "$left" -le 0 ]; then
    echo "================ TIME BUDGET: not started, the deadline (CI_TEST_DEADLINE_SECONDS=$CI_TEST_DEADLINE_SECONDS) has passed ================"
    return 124
  fi
  echo "(time budget: $left s left for this test run)"
  with_budget "$left" "$@"
}

is_booted() { xcrun simctl list devices 2>/dev/null | grep -F "$1" | grep -q '(Booted)'; }

# Boot and wait. Returns 0 when the simulator reports booted.
boot_and_wait() {
  local udid="$1"
  echo "+ xcrun simctl boot $udid"
  if ! xcrun simctl boot "$udid" 2>&1; then
    is_booted "$udid" && echo "(already booted)" || { echo "BOOT FAILED"; return 1; }
  fi
  echo "+ xcrun simctl bootstatus $udid -b (at most ${BOOT_WAIT_SECONDS} s)"
  with_timeout "$BOOT_WAIT_SECONDS" xcrun simctl bootstatus "$udid" -b 2>&1 || { echo "BOOTSTATUS FAILED"; return 1; }
}

write_ready() {  # seconds retries [reason]
  { echo "Simulator ready after $1 s (retries: $2/1)"; [ -n "${3:-}" ] && echo "Retry reason: $3"; } > "$ready_file"
  cat "$ready_file"
}

# The one retry of the job. Returns 1 when it was already used or the simulator still does not come up.
recover() {
  local udid="$1" reason="$2"
  if [ -e "$retry_marker" ]; then
    echo "SIMULATOR RETRY NOT DONE: this job already retried once ($(cat "$retry_marker")). Reason now: $reason"
    return 1
  fi
  echo "$reason" > "$retry_marker"
  echo "::warning::SIMULATOR RETRY: $reason. Shutting down all simulators, erasing $udid, booting it again."
  echo "================ SIMULATOR RETRY: $reason ================"
  local start; start="$(date +%s)"
  xcrun simctl shutdown all 2>&1 || true
  xcrun simctl erase "$udid" 2>&1 || echo "(erase failed; booting anyway)"
  if boot_and_wait "$udid"; then
    write_ready "$(( $(date +%s) - start ))" 1 "$reason"
    if [ -n "${SIM_RETRY_HOOK:-}" ]; then echo "+ $SIM_RETRY_HOOK"; bash -c "$SIM_RETRY_HOOK" 2>&1 || true; fi
    return 0
  fi
  write_ready "never (still not booted after the retry)" 1 "$reason"
  return 1
}

prepare() {
  {
    echo "== xcrun simctl list runtimes"; xcrun simctl list runtimes 2>&1
    echo; echo "== xcrun simctl runtime list"; xcrun simctl runtime list 2>&1
  } | tee "$out/sim-runtimes.txt"
  xcrun simctl list devices available | tee "$out/simulators.txt"
  local udid
  udid="$(xcrun simctl list devices available -j | python3 "$here/ci-pick-simulator.py" 2> >(tee -a "$out/simulators.txt" >&2))"
  [ -n "$udid" ] || { echo "::error::No tvOS simulator could be picked (see the runtime lists above)."; write_ready "never (no simulator picked)" 0; return 1; }
  [ -n "${GITHUB_ENV:-}" ] && echo "SIM_UDID=$udid" >> "$GITHUB_ENV"
  local start; start="$(date +%s)"
  if boot_and_wait "$udid"; then
    write_ready "$(( $(date +%s) - start ))" 0
  else
    recover "$udid" "boot or bootstatus failed" || { echo "::error::The simulator did not boot, also not after the retry."; return 1; }
  fi
  cat "$ready_file" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

run_test() {
  local log="$1"; shift
  [ "${1:-}" = "--" ] && shift
  local udid="${SIM_UDID:?SIM_UDID is not set (run ci-sim.sh prepare first)}"
  local bundle="" prev=""
  for a in "$@"; do [ "$prev" = "-resultBundlePath" ] && bundle="$a"; prev="$a"; done
  local this_run; this_run="$(mktemp)"
  budgeted "$@" 2>&1 | tee "$this_run" | tee -a "$log"
  local rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ] && grep -qE "$RUNTIME_PATTERN" "$this_run"; then
    local reason; reason="xcodebuild failed with: $(grep -oE "$RUNTIME_PATTERN" "$this_run" | head -n 1)"
    if recover "$udid" "$reason"; then
      [ -n "$bundle" ] && rm -rf "$bundle"
      echo "================ SIMULATOR RETRY: running the same xcodebuild call again ================" | tee -a "$log"
      budgeted "$@" 2>&1 | tee -a "$log"
      rc=${PIPESTATUS[0]}
    fi
  fi
  rm -f "$this_run"
  return "$rc"
}

case "${1:-}" in
  prepare) prepare ;;
  test) shift; run_test "$@" ;;
  *) echo "usage: ci-sim.sh prepare | ci-sim.sh test LOG -- xcodebuild ..." >&2; exit 2 ;;
esac
