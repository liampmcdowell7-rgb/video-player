#!/usr/bin/env bash
# Self-test of the device-build inspection checks (scripts/ci-inspect-lib.sh) on fake `nm -m` and `strings` output.
# Runs in WSL/Linux; part of scripts/test-all.sh. Prints one line per case and a final "passed N, failed M" line.
set -uo pipefail   # the same options as the CI script, so a pipe problem like the fourth run's would show here
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$HERE/scripts/ci-inspect-lib.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { # name expected-status actual-status
  if [ "$2" -eq "$3" ]; then echo "ok    $1"; pass=$((pass + 1)); else echo "FAIL  $1 (expected $2, got $3)"; fail=$((fail + 1)); fi
}

# Fake `nm -m` output of the fourth run's app binary: defined libnfs and libdovi symbols, plus imports.
cat > "$T/nm-present.txt" <<'EOF'
                 (undefined) external _posix_spawn (from libSystem)
0000000100a1b2c0 (__TEXT,__text) external _nfs_close
0000000100a1b3c0 (__TEXT,__text) external _nfs_closedir
0000000100c00010 (__TEXT,__text) external _dovi_convert_rpu_with_mode
0000000100c00100 (__TEXT,__text) external _dovi_rpu_free
EOF
# A long output with the match on the first line: the case that broke `nm | grep -q` under pipefail.
{ cat "$T/nm-present.txt"; for i in $(seq 1 200000); do echo "0000000100000000 (__TEXT,__text) external _filler_$i"; done; } > "$T/nm-long.txt"
# Only imports of the names, no definitions: the library is not linked in.
cat > "$T/nm-absent.txt" <<'EOF'
                 (undefined) external _nfs_close (from libnfs)
                 (undefined) external _dovi_rpu_free (from libdovi)
0000000100a1b2c0 (__TEXT,__text) external _main
EOF
: > "$T/nm-empty.txt"

vp_symbols_defined "$T/nm-present.txt" _nfs_;  check "libnfs symbols present are found" 0 $?
vp_symbols_defined "$T/nm-present.txt" _dovi_; check "libdovi symbols present are found" 0 $?
vp_symbols_defined "$T/nm-long.txt" _nfs_;     check "found in a 200,000-line output (no SIGPIPE false alarm)" 0 $?
vp_symbols_defined "$T/nm-absent.txt" _nfs_;   check "imports only: libnfs reported absent" 1 $?
vp_symbols_defined "$T/nm-absent.txt" _dovi_;  check "imports only: libdovi reported absent" 1 $?
vp_symbols_defined "$T/nm-empty.txt" _nfs_;    check "empty nm output: reported absent" 1 $?
vp_symbols_defined "$T/missing.txt" _nfs_;     check "missing nm output file: reported absent" 1 $?

printf 'Video Player\nContinue Watching\n' > "$T/strings-clean.txt"
vp_forbidden_strings "$T/strings-clean.txt" >/dev/null; check "clean Release strings pass" 0 $?
for s in '-UITestFixtures' '-UITestEmpty' '-UITestTab' '-UITestOpen' '-UITestTextSize' '-UITestBoldText' 'Sample Movie 1 (2021)' 'uitest-sample-library' 'sample.invalid' 'Sample Library' 'Sample Clip.mkv' 'Sample Unsorted Recital.mkv' 'Sample Server' 'uitest-sample-server'; do
  printf 'Video Player\n%s\n' "$s" > "$T/strings-bad.txt"
  vp_forbidden_strings "$T/strings-bad.txt" >/dev/null; check "Release string '$s' is caught" 1 $?
done

# --- #23 C: the inspection must never pass on a failed build or without the app binary ---
# Runs the real scripts/ci-inspect-device-app.sh on a fake products folder; both cases stop before any Mac tool is used.
# not_checked_case NAME OUTDIR STATUS: exit status 1, every report file present and saying NOT CHECKED for every check,
# and no "ok" or "(none)" line anywhere.
not_checked_case() {
  local name="$1" out="$2" status="$3" r bad=0
  [ "$status" -eq 1 ] || { echo "      exit status $status, expected 1"; bad=1; }
  for r in $VP_INSPECT_REPORTS; do
    [ -f "$out/$r" ] || { echo "      $r missing"; bad=1; continue; }
    [ "$(grep -c '^NOT CHECKED: ' "$out/$r")" -ge 8 ] || { echo "      $r lacks NOT CHECKED lines"; bad=1; }
    if grep -nE '^ok |\(none\)' "$out/$r"; then echo "      $r has an ok/(none) line"; bad=1; fi
  done
  check "$name" 0 "$bad"
}
mkdir -p "$T/w1/build/ci"
echo "/src/App/Features/Settings/StorageSettingsView.swift:16:13: error: generic parameter 'Content' could not be inferred" > "$T/w1/build/ci/build.log"
( cd "$HERE" && OUT="$T/w1/build/ci" BUILD_OUTCOME=failure VP_PRODUCTS="$T/w1/none" bash scripts/ci-inspect-device-app.sh > "$T/w1/out.txt" 2>&1 ); st=$?
not_checked_case "build failed: every check says NOT CHECKED, exit 1" "$T/w1/build/ci" "$st"
grep -q 'first error: .*StorageSettingsView.swift:16:13' "$T/w1/build/ci/embedded-frameworks.txt"; check "build failed: the first error line is in the report" 0 $?
# The failed build left an app folder with frameworks behind (as in the first CI run): still NOT CHECKED.
mkdir -p "$T/w1b/build/ci" "$T/w1b/p/VideoPlayer.app/Frameworks/AetherLibavcodec.framework"
: > "$T/w1b/p/VideoPlayer.app/Frameworks/AetherLibavcodec.framework/AetherLibavcodec"
( cd "$HERE" && OUT="$T/w1b/build/ci" BUILD_OUTCOME=failure VP_PRODUCTS="$T/w1b/p" bash scripts/ci-inspect-device-app.sh > "$T/w1b/out.txt" 2>&1 ); st=$?
not_checked_case "build failed with leftovers in the app folder: NOT CHECKED, exit 1" "$T/w1b/build/ci" "$st"
( cd "$HERE" && OUT="$T/w1c/build/ci" VP_PRODUCTS="$T/w1b/p" bash scripts/ci-inspect-device-app.sh > "$T/w1c.txt" 2>&1 ); st=$?
not_checked_case "build outcome not given: NOT CHECKED, exit 1" "$T/w1c/build/ci" "$st"
# The build step reported success but VideoPlayer.app/VideoPlayer is missing.
mkdir -p "$T/w2/build/ci" "$T/w2/p/VideoPlayer.app/PlugIns/TopShelf.appex"
: > "$T/w2/p/VideoPlayer.app/PlugIns/TopShelf.appex/TopShelf"
( cd "$HERE" && OUT="$T/w2/build/ci" BUILD_OUTCOME=success VP_PRODUCTS="$T/w2/p" bash scripts/ci-inspect-device-app.sh > "$T/w2/out.txt" 2>&1 ); st=$?
not_checked_case "main binary missing after a reported success: NOT CHECKED, exit 1" "$T/w2/build/ci" "$st"
grep -q 'app binary .*VideoPlayer is missing' "$T/w2/build/ci/release-strings.txt"; check "main binary missing: the reason is named" 0 $?

# vp_app_binaries: the app binary, the extension and every framework binary are searched.
A="$T/w3/VideoPlayer.app"
mkdir -p "$A/PlugIns/TopShelf.appex" "$A/Frameworks/AetherLibavutil.framework" "$A/Frameworks/AMSMB2.framework"
: > "$A/VideoPlayer"; : > "$A/PlugIns/TopShelf.appex/TopShelf"; : > "$A/Frameworks/AetherLibavutil.framework/AetherLibavutil"; : > "$A/Frameworks/AMSMB2.framework/AMSMB2"
vp_app_binaries "$A" > "$T/w3/list.txt"
[ "$(wc -l < "$T/w3/list.txt")" -eq 4 ] && grep -q '/VideoPlayer.app/VideoPlayer$' "$T/w3/list.txt" && grep -q 'TopShelf.appex/TopShelf$' "$T/w3/list.txt" && grep -q 'AMSMB2.framework/AMSMB2$' "$T/w3/list.txt"
check "binaries searched: app, Top Shelf extension, every framework" 0 $?

# vp_spawn_imports on fake `nm -um` output.
cat > "$T/nmu-spawn.txt" <<'EOF'
                 (undefined) external _posix_spawnp (from libSystem)
                 (undefined) external _posix_spawn_file_actions_init (from libSystem)
                 (undefined) external _malloc (from libSystem)
EOF
[ "$(vp_spawn_imports "$T/nmu-spawn.txt")" = "_posix_spawnp" ]; check "spawn imports: _posix_spawnp found, file_actions helper not counted" 0 $?
printf '                 (undefined) external _fork (from libSystem)\n                 (undefined) external _system (from libSystem)\n' > "$T/nmu-fork.txt"
[ "$(vp_spawn_imports "$T/nmu-fork.txt" | tr '\n' ' ')" = "_fork _system " ]; check "spawn imports: _fork and _system found" 0 $?
[ -z "$(vp_spawn_imports "$T/nm-absent.txt")" ]; check "spawn imports: none in an output without them" 0 $?

echo "ci-inspect self-test: passed $pass, skipped 0, failed $fail"
[ "$fail" -eq 0 ]
