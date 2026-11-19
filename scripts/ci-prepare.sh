#!/usr/bin/env bash
# CI only (compile-check.yml, jobs device-build, simulator-tests, screenshots). The same preparation the "compile" job does in
# its own steps: select Xcode, check the committed vendored packages and binary frameworks, install the pinned XcodeGen
# (SHA-256 checked), generate the project, resolve the packages. Needs XCODE_APP, XCODEGEN_VERSION, XCODEGEN_SHA256, OUT.
# Writes xcode-version.txt, binary-targets.txt, xcodegen.log, schemes.txt and resolve.log into $OUT. No secrets.
set -euo pipefail
: "${XCODE_APP:?}" "${XCODEGEN_VERSION:?}" "${XCODEGEN_SHA256:?}" "${OUT:?}"
mkdir -p "$OUT"

echo "== Select Xcode"
sudo xcode-select -s "$XCODE_APP/Contents/Developer"
xcodebuild -version | tee "$OUT/xcode-version.txt"
xcodebuild -showsdks | tee -a "$OUT/xcode-version.txt"
xcodebuild -showsdks | grep -q 'appletvsimulator27' || { echo "::error::No tvOS 27 Simulator SDK on this runner"; exit 1; }

echo "== Check the committed vendored packages and binary frameworks"
P=Packages/VideoPlayerCore
missing=0
for f in "$P/Vendor/AMSMB2/Package.swift" "$P/Vendor/Citadel/Package.swift" "$P/Vendor/swift-nio-ssh/Package.swift"; do
  if [ -f "$f" ]; then echo "ok      $f"; else echo "::error::missing $f"; missing=1; fi
done
# #23 E: the raw paths (one is the unexpanded "\(name)" pattern) stay in a temporary file; binary-target-paths.txt holds
# the expanded paths only.
patterns="$(mktemp)"
grep -oE 'path: *"[^"]+\.xcframework"' "$P/Package.swift" | sed -E 's/path: *"([^"]+)"/\1/' | sort -u > "$patterns" || true
: > "$OUT/binary-targets.txt"
while read -r rel; do
  case "$rel" in
    *'\('*)
      dir="$(dirname "$rel")"
      n=0
      for x in "$P/$dir"/*.xcframework; do [ -d "$x" ] && echo "${x#$P/}" >> "$OUT/binary-targets.txt" && n=$((n + 1)); done
      [ "$n" -gt 0 ] || { echo "::error::no .xcframework in $P/$dir (Package.swift expects some: $rel)"; missing=1; } ;;
    *) echo "$rel" >> "$OUT/binary-targets.txt" ;;
  esac
done < "$patterns"
rm -f "$patterns"
cp "$OUT/binary-targets.txt" "$OUT/binary-target-paths.txt"
while read -r rel; do
  [ -n "$rel" ] || continue
  d="$P/$rel"
  if [ ! -f "$d/Info.plist" ]; then echo "::error::binary target $d is missing (not committed?)"; missing=1; continue; fi
  if grep -rIl -m1 '^version https://git-lfs.github.com/spec' "$d" >/dev/null 2>&1; then
    echo "::error::$d contains Git LFS pointer files instead of the real binaries"; missing=1; continue
  fi
  echo "ok      $d ($(du -sh "$d" | cut -f1))"
done < "$OUT/binary-targets.txt"
[ "$missing" -eq 0 ] || exit 1

echo "== Install XcodeGen $XCODEGEN_VERSION (pinned release, SHA-256 checked)"
TMP="${RUNNER_TEMP:-/tmp}"
mkdir -p "$TMP/xcodegen"
curl -fsSL -o "$TMP/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
echo "${XCODEGEN_SHA256}  $TMP/xcodegen.zip" | shasum -a 256 -c -
unzip -qo "$TMP/xcodegen.zip" -d "$TMP/xcodegen"
BIN="$(find "$TMP/xcodegen" -type f -name xcodegen -perm -u+x | head -n1)"
[ -n "$BIN" ] || { echo "::error::xcodegen binary not found in the release zip"; exit 1; }
"$BIN" --version

echo "== Generate the Xcode project"
"$BIN" generate --spec project.yml 2>&1 | tee "$OUT/xcodegen.log"
xcodebuild -list -project VideoPlayer.xcodeproj | tee "$OUT/schemes.txt"

echo "== Resolve Swift packages"
xcodebuild -resolvePackageDependencies -project VideoPlayer.xcodeproj -scheme VideoPlayer \
  -clonedSourcePackagesDirPath build/SourcePackages 2>&1 | tee "$OUT/resolve.log"
