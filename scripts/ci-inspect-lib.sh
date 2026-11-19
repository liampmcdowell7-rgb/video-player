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
# #21 D added the fake synopsis and cast of the sample movies (UITestFixtureDetails.swift, also #if DEBUG).
# #21 E added the generated player clip (App/Support/UITestClip.swift, #if DEBUG) and the sample subtitle lines.
VP_RELEASE_FORBIDDEN_RE='Sample Movie|Sample Show|Sample Library|Sample Clip|Sample Unsorted|Sample Server|uitest-sample-library|uitest-sample-server|sample\.invalid|-UITestEmpty|-UITestFixtures|-UITestTab|-UITestOpen|-UITestTextSize|-UITestBoldText|UITestFixtures|UITestLaunch|UITestMode|UI-test mode|Sample data: not tested|Sample synopsis|Sample Actor|Sample Role|UITestFixtureDetails|UITestClip|uitest-sample-clip|Sample subtitle line'

# Process-spawning C functions (#23 C). An `nm -um` line of an imported one ends in the name, e.g.
# "                 (undefined) external _posix_spawnp (from libSystem)".
VP_SPAWN_RE='_(posix_spawnp?|fork|vfork|execv[pe]?|execl[pe]?|system)'

# The report files the device inspection writes, and the checks each one holds. When the build failed, or the app
# binary is missing, every one of them says NOT CHECKED (#23 C) and none says "ok" or "(none)".
VP_INSPECT_REPORTS='embedded-frameworks.txt macho-report.txt static-libraries.txt release-strings.txt process-spawning.txt app-nm.txt'
VP_INSPECT_CHECKS='embedded frameworks|slices (architectures)|platform tags|linked libraries|libnfs and libdovi linked in|Release has no sample data|process-spawning symbols'

# vp_inspect_not_checked OUTDIR REASON [FIRST_ERROR]: writes "NOT CHECKED: REASON" for every check into every report file
# and prints the same lines. Used when the build failed or produced no app binary.
vp_inspect_not_checked() {
  local out="$1" reason="$2" first="${3:-}" r c
  mkdir -p "$out"
  for r in $VP_INSPECT_REPORTS; do
    {
      echo "NOT CHECKED: $reason"
      [ -n "$first" ] && echo "first error: $first"
      local IFS='|'
      for c in $VP_INSPECT_CHECKS; do echo "NOT CHECKED: $c ($reason)"; done
    } > "$out/$r"
  done
  cat "$out/embedded-frameworks.txt"
}

# vp_app_binaries APP: the Mach-O executables to search, one path per line: the app binary, each extension's executable,
# each embedded framework's binary and any loose dylib. Names only, no `file` call, so it runs in the self-test.
vp_app_binaries() {
  local app="$1" x n
  echo "$app/$(basename "$app" .app)"
  for x in "$app"/PlugIns/*.appex; do
    [ -d "$x" ] || continue
    n="$(basename "$x" .appex)"; [ -f "$x/$n" ] && echo "$x/$n"
  done
  for x in "$app"/Frameworks/*.framework; do
    [ -d "$x" ] || continue
    n="$(basename "$x" .framework)"; [ -f "$x/$n" ] && echo "$x/$n"
  done
  find "$app" -type f -name '*.dylib' 2>/dev/null | sort
}

# vp_spawn_imports NM_UNDEFINED_FILE: prints the process-spawning names a binary imports (one per line, sorted, unique);
# nothing when it imports none. Reads `nm -um` output saved to a file.
vp_spawn_imports() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -oE "external ${VP_SPAWN_RE}( |\$)" "$file" | sed -E 's/^external //; s/ $//' | sort -u
}

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
