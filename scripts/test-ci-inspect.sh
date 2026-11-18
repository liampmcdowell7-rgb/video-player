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
for s in '-UITestFixtures' '-UITestEmpty' '-UITestTab' '-UITestOpen' 'Sample Movie 1 (2021)' 'uitest-sample-library' 'sample.invalid' 'Sample Library'; do
  printf 'Video Player\n%s\n' "$s" > "$T/strings-bad.txt"
  vp_forbidden_strings "$T/strings-bad.txt" >/dev/null; check "Release string '$s' is caught" 1 $?
done

echo "ci-inspect self-test: passed $pass, skipped 0, failed $fail"
[ "$fail" -eq 0 ]
