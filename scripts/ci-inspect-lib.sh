#!/usr/bin/env bash
# Checks used by scripts/ci-inspect-device-app.sh, kept apart so scripts/test-ci-inspect.sh can run them on fake tool output
# in WSL (no Mac tools needed). Source this file; it defines functions only.
#
# Fourth CI run: the old check `nm -m BIN | grep -qE 'external _nfs_' || problem ...` reported "no libnfs symbols" although
# the same output listed _nfs_close. Under `set -o pipefail`, `grep -q` stops reading at the first match, nm is killed by
# SIGPIPE while still writing, the pipeline status is nm's 141, and `||` fired. Every check below reads a FILE (tool output
# saved first), never a pipe, so an early exit of grep cannot turn a match into a failure.

# Texts that exist only in the debug-only UI-test code and sample library (UITestLaunch.swift, UITestFixtures.swift,
# App/Support/UITestMode.swift, App/Support/AppDependencies.swift uiTest(), all inside #if DEBUG). None may appear in a
# Release binary. #15 3.6 added "UI-test mode" (the iCloud-off reason) and the sample sources' "not tested" status.
VP_RELEASE_FORBIDDEN_RE='Sample Movie|Sample Show|Sample Library|Sample Clip|Sample Unsorted|Sample Server|uitest-sample-library|uitest-sample-server|sample\.invalid|-UITestEmpty|-UITestFixtures|-UITestTab|-UITestOpen|-UITestTextSize|-UITestBoldText|UITestFixtures|UITestLaunch|UITestMode|UI-test mode|Sample data: not tested'

# vp_symbols_defined NM_OUTPUT_FILE PREFIX: 0 when `nm -m` output lists at least one DEFINED external symbol starting
# with PREFIX (for example _nfs_ or _dovi_), 1 otherwise. "(undefined)" lines (imports) do not count.
vp_symbols_defined() {
  local file="$1" prefix="$2"
  [ -s "$file" ] || return 1
  # One grep on the file, no pipe. A defined symbol's line starts with its address ("0000000100012345 (__TEXT,__text)
  # external _nfs_close"); an imported one starts with spaces and "(undefined)".
  grep -Eq "^[0-9a-fA-F]+ \([^)]*\) .*external ${prefix}" "$file"
}

# vp_forbidden_strings STRINGS_OUTPUT_FILE: prints the forbidden lines found (nothing when clean); 0 when clean, 1 otherwise.
vp_forbidden_strings() {
  local file="$1"
  if grep -nE -- "$VP_RELEASE_FORBIDDEN_RE" "$file"; then return 1; fi
  return 0
}
