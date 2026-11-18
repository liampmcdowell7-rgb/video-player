#!/usr/bin/env bash
# CI only (compile-check.yml, job "device-build"). Inspects the unsigned tvOS DEVICE build (Release, arm64) and writes
# reports into $OUT. A report: it prints "PROBLEM:" lines and exits 1 if any were found, so the step turns red, but the
# upload step still runs (if: always()).
#   embedded-frameworks.txt   the app's Frameworks folder and the extension's contents (the extension must embed nothing)
#   macho-report.txt          for every Mach-O file: architectures (lipo), platform tag (vtool / LC_BUILD_VERSION), linked libraries
#   static-libraries.txt      the two static libraries linked into the app binary (libnfs, libdovi): platform tag of the
#                             device slice, and the process-spawning symbols they reference (posix_spawn, posix_spawnp, fork, exec*)
#   release-strings.txt       proof that the debug-only UI-test code is compiled out of Release: no launch-argument text
#                             (-UITestEmpty, -UITestFixtures, -UITestTab, -UITestOpen) and no sample-library text
#   app-nm.txt                `nm -m` of the app binary, saved once; the symbol checks read this file (ci-inspect-lib.sh)
set -uo pipefail
: "${OUT:?}"
. "$(dirname "${BASH_SOURCE[0]}")/ci-inspect-lib.sh"
mkdir -p "$OUT"
PROD="build/DerivedData/Build/Products/Release-appletvos"
APP="$PROD/VideoPlayer.app"
P=Packages/VideoPlayerCore
problems=0
problem() { echo "PROBLEM: $*"; problems=$((problems + 1)); }

if [ ! -d "$APP" ]; then
  echo "No $APP (the device build did not produce an app). Products folder:" | tee "$OUT/embedded-frameworks.txt"
  ls -la "$PROD" 2>&1 | tee -a "$OUT/embedded-frameworks.txt"
  exit 1
fi

{
  echo "== $APP/Frameworks"
  ls -la "$APP/Frameworks" 2>&1 || echo "(no Frameworks folder)"
  echo
  echo "== PlugIns"
  ls -la "$APP/PlugIns" 2>&1 || echo "(no PlugIns folder)"
  for appex in "$APP"/PlugIns/*.appex; do
    [ -d "$appex" ] || continue
    echo
    echo "== $appex (full listing)"
    find "$appex" -maxdepth 3 | sed "s#^$APP/##"
  done
} | tee "$OUT/embedded-frameworks.txt"

# The five audio codec frameworks must be embedded in the app. (No pipes around the loops: problem() must count in this shell.)
exec 3>&1 1> >(tee -a "$OUT/embedded-frameworks.txt")
for fw in AetherLibavcodec AetherLibavutil AetherLibswresample AetherLibdav1d AetherLibzvbi; do
  if [ -f "$APP/Frameworks/$fw.framework/$fw" ]; then echo "ok      $fw.framework embedded"; else problem "$fw.framework is not embedded in the app"; fi
done
# The Top Shelf extension must not embed frameworks of its own (they belong to the app).
for appex in "$APP"/PlugIns/*.appex; do
  [ -d "$appex" ] || { problem "no Top Shelf extension in PlugIns"; continue; }
  if [ -d "$appex/Frameworks" ] && [ -n "$(ls -A "$appex/Frameworks" 2>/dev/null)" ]; then
    problem "$(basename "$appex") embeds frameworks: $(ls "$appex/Frameworks" | tr '\n' ' ')"
  else
    echo "ok      $(basename "$appex") embeds no frameworks"
  fi
done
exec 1>&3 3>&-

# Every Mach-O file in the bundle: arm64 only, platform TVOS (2 in LC_BUILD_VERSION), not the simulator.
{
  find "$APP" -type f | while read -r f; do
    case "$(file -b "$f")" in *Mach-O*) ;; *) continue ;; esac   # no pipe into grep -q (SIGPIPE under pipefail)
    echo "== ${f#$APP/}"
    lipo -info "$f" 2>&1
    vtool -show-build "$f" 2>&1 | sed -n '1,12p'
    otool -L "$f" 2>&1 | sed -n '2,40p'
    echo
  done
} > "$OUT/macho-report.txt"
grep -nE 'TVOSSIMULATOR|platform 10$' "$OUT/macho-report.txt" && problem "a Mach-O file in the device app is tagged for the tvOS SIMULATOR (lines above)"
grep -nE '(are|architecture): .*x86_64' "$OUT/macho-report.txt" && problem "an x86_64 slice is in the device app (lines above)"
echo "Mach-O files inspected: $(grep -c '^== ' "$OUT/macho-report.txt")"

# Static libraries linked into the app binary.
BIN="$APP/VideoPlayer"
# Saved to a file first: the checks below read the file, never `nm | grep -q` (a SIGPIPE false alarm under pipefail).
nm -m "$BIN" > "$OUT/app-nm.txt" 2>"$OUT/app-nm.stderr" || echo "nm -m failed on $BIN (see app-nm.stderr)"
{
  for lib in "$P/Frameworks/Libnfs.xcframework/tvos-arm64/libnfs.a" "$P/Frameworks/DolbyVisionRPULib.xcframework/tvos-arm64_arm64e/libdovi.a"; do
    echo "== $lib"
    [ -f "$lib" ] || { echo "missing"; continue; }
    lipo -info "$lib" 2>&1
    # Platform tag of the first object file in the archive (LC_BUILD_VERSION platform 3 = TVOS, 10 = TVOSSIMULATOR).
    otool -l "$lib" 2>/dev/null | grep -A4 'LC_BUILD_VERSION' | grep -E 'platform|minos|sdk' | sort | uniq -c | head -n 10
    echo "-- process-spawning symbols the library references (undefined, so they must resolve on tvOS at link time):"
    nm -u "$lib" 2>/dev/null | grep -E '_(posix_spawnp?|fork|vfork|execv[pe]?|execl[pe]?|system)$' | sort | uniq -c || echo "(none)"
    echo
  done
  echo "== the same symbols in the linked app binary (undefined = imported from the system):"
  nm -um "$BIN" 2>/dev/null | grep -E '_(posix_spawnp?|fork|vfork|execv[pe]?|execl[pe]?|system)$' || echo "(none)"
  echo
  echo "== libnfs and libdovi code is in the app binary (sample of defined symbols):"
  grep -m 5 -E '\(__TEXT,__text\) external _(nfs_|rpc_nfs)' "$OUT/app-nm.txt" || echo "(no libnfs symbol)"
  grep -m 5 -E '\(__TEXT,__text\) external _dovi_' "$OUT/app-nm.txt" || echo "(no libdovi symbol)"
} | tee "$OUT/static-libraries.txt"
if vp_symbols_defined "$OUT/app-nm.txt" _nfs_; then echo "ok      libnfs symbols defined in the app binary"; else problem "no libnfs symbols in the app binary (libnfs not linked?)"; fi
if vp_symbols_defined "$OUT/app-nm.txt" _dovi_; then echo "ok      libdovi symbols defined in the app binary"; else problem "no libdovi symbols in the app binary (Dolby Vision RPU library not linked?)"; fi

# The UI-test modes and the sample library are #if DEBUG only (OPEN_QUESTIONS R160): a Release binary must not contain
# their texts (list: VP_RELEASE_FORBIDDEN_RE in ci-inspect-lib.sh). `strings` output is saved per file, then searched.
hits=0
{
  echo "Debug-only UI-test texts found in the Release app binary, extension and frameworks (expected: none):"
  echo "searched for: $VP_RELEASE_FORBIDDEN_RE"
} > "$OUT/release-strings.txt"
while read -r f; do
  strings -a "$f" > "$OUT/strings.tmp" 2>/dev/null || true
  if ! vp_forbidden_strings "$OUT/strings.tmp" >> "$OUT/release-strings.txt"; then hits=1; echo "  in ${f#$APP/}" >> "$OUT/release-strings.txt"; fi
done < <(find "$APP" -type f -perm -u+x)
rm -f "$OUT/strings.tmp"
[ "$hits" -eq 0 ] && echo "(none)" >> "$OUT/release-strings.txt"
cat "$OUT/release-strings.txt"
[ "$hits" -eq 0 ] || problem "the Release build contains debug-only UI-test texts (release-strings.txt)"

echo "Problems found: $problems" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
[ "$problems" -eq 0 ]
