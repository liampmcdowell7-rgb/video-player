#!/usr/bin/env bash
# CI only (compile-check.yml, job "device-build"). Inspects the unsigned tvOS DEVICE build (Release, arm64) and writes
# reports into $OUT. A report: it prints "PROBLEM:" lines and exits 1 if any were found, so the step turns red, but the
# upload step still runs (if: always()).
#   embedded-frameworks.txt   the app's Frameworks folder and the extension's contents (the extension must embed nothing)
#   macho-report.txt          for every Mach-O file: architectures (lipo), platform tag (vtool / LC_BUILD_VERSION), linked libraries
#   static-libraries.txt      the two static libraries linked into the app binary (libnfs, libdovi): platform tag of the
#                             device slice, and the process-spawning symbols they reference (posix_spawn, posix_spawnp, fork, exec*)
#   release-strings.txt       proof that the debug-only sample library is compiled out of Release (no "Sample Movie" string)
set -uo pipefail
: "${OUT:?}"
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
    file -b "$f" | grep -q 'Mach-O' || continue
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
  nm -m "$BIN" 2>/dev/null | grep -E '\(__TEXT,__text\) external _(nfs_|rpc_nfs)' | head -n 5 || true
  nm -m "$BIN" 2>/dev/null | grep -E '\(__TEXT,__text\) external _dovi_' | head -n 5 || true
} | tee "$OUT/static-libraries.txt"
nm -m "$BIN" 2>/dev/null | grep -qE 'external _nfs_' || problem "no libnfs symbols in the app binary (libnfs not linked?)"
nm -m "$BIN" 2>/dev/null | grep -qE 'external _dovi_' || problem "no libdovi symbols in the app binary (Dolby Vision RPU library not linked?)"

# The UI-test sample library is #if DEBUG only (OPEN_QUESTIONS R160): a Release binary must not contain it.
{
  echo "Strings from the debug-only sample library found in the Release app binary and frameworks (expected: none):"
  hits=0
  while read -r f; do
    if strings -a "$f" 2>/dev/null | grep -nE 'Sample Movie|uitest-sample-library|-UITestFixtures|UITestFixtures'; then hits=1; echo "  in ${f#$APP/}"; fi
  done < <(find "$APP" -type f -perm -u+x)
  [ "$hits" -eq 0 ] && echo "(none)"
} | tee "$OUT/release-strings.txt"
grep -q '^(none)$' "$OUT/release-strings.txt" || problem "the Release build contains UI-test sample-library strings"

echo "Problems found: $problems" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
[ "$problems" -eq 0 ]
