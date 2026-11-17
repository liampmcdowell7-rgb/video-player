#!/usr/bin/env bash
# Creates the vendored, pinned and patched copies of Citadel and its swift-nio-ssh fork under
# Packages/VideoPlayerCore/Vendor/ (the same idea as the AMSMB2 copy). Package.swift only wires the Citadel
# backend target (SourceSFTPCitadel) when both copies exist, so the base manifest never needs them.
#
#   bash scripts/setup-citadel.sh          create the copies if they are missing, verify them
#   bash scripts/setup-citadel.sh check    verify only (exit 1 if a copy is missing or wrong)
#   bash scripts/setup-citadel.sh clean    remove both copies
#
# Pins (exact commits, from the official GitHub repositories; a tag can move, a commit cannot):
#   Citadel 0.12.1            https://github.com/orlandos-nl/Citadel.git        ae8562f895de06ccb86fdb1cbb65fd99c8976e12
#   swift-nio-ssh 0.3.4 fork  https://github.com/Wellz26/swift-nio-ssh.git     b93961a2988607a756cbc21a811f406f27aa9ab6
# Patch (fork only): scripts/patches/swift-nio-ssh-0.3.4-cdispatch.patch (a guarded `import CDispatch`, needed on
# Linux with Swift 6.4 only; it does nothing on Apple platforms).
# Change (Citadel only, OPEN_QUESTIONS R155): Vendor/Citadel/Package.swift depends on the vendored fork by path
# (`.package(path: "../swift-nio-ssh")`) instead of by URL, so SwiftPM sees one source of the swift-nio-ssh identity
# (Xcode 27.2 warned "Conflicting identity for swift-nio-ssh" and says that will become an error in a future version).
# The .git folders are removed from the copies so the project folder holds no nested repositories.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$HERE/Packages/VideoPlayerCore/Vendor"
CITADEL_URL="https://github.com/orlandos-nl/Citadel.git";    CITADEL_COMMIT="ae8562f895de06ccb86fdb1cbb65fd99c8976e12"
NIOSSH_URL="https://github.com/Wellz26/swift-nio-ssh.git";   NIOSSH_COMMIT="b93961a2988607a756cbc21a811f406f27aa9ab6"
PATCH="$HERE/scripts/patches/swift-nio-ssh-0.3.4-cdispatch.patch"
FILE_IN_FORK="Sources/NIOSSH/Keys And Signatures/NIOSSHCertifiedPublicKey.swift"

verify() {
  local ok=1
  [ -f "$VENDOR/Citadel/Package.swift" ] && grep -q "^$CITADEL_COMMIT" "$VENDOR/Citadel/VENDORED_FROM.txt" 2>/dev/null || { echo "Vendor/Citadel missing or not at $CITADEL_COMMIT"; ok=0; }
  [ -f "$VENDOR/swift-nio-ssh/Package.swift" ] && grep -q "^$NIOSSH_COMMIT" "$VENDOR/swift-nio-ssh/VENDORED_FROM.txt" 2>/dev/null || { echo "Vendor/swift-nio-ssh missing or not at $NIOSSH_COMMIT"; ok=0; }
  grep -q "canImport(CDispatch)" "$VENDOR/swift-nio-ssh/$FILE_IN_FORK" 2>/dev/null || { echo "Vendor/swift-nio-ssh is not patched"; ok=0; }
  { grep -q '^        \.package(path: "\.\./swift-nio-ssh"),' "$VENDOR/Citadel/Package.swift" 2>/dev/null \
    && ! grep -q 'url: "https://github.com/Wellz26/swift-nio-ssh' "$VENDOR/Citadel/Package.swift"; } \
    || { echo "Vendor/Citadel/Package.swift does not use the vendored swift-nio-ssh by path"; ok=0; }
  [ "$ok" = 1 ]
}

fetch() { # name url commit
  local name="$1" url="$2" commit="$3" tmp
  tmp="$(mktemp -d)"
  git clone --quiet "$url" "$tmp/src"
  git -C "$tmp/src" -c advice.detachedHead=false checkout --quiet "$commit"
  [ "$(git -C "$tmp/src" rev-parse HEAD)" = "$commit" ] || { echo "checkout of $name is not at $commit" >&2; rm -rf "$tmp"; exit 1; }
  rm -rf "$tmp/src/.git"
  echo "$commit  $url  (vendored by scripts/setup-citadel.sh)" > "$tmp/src/VENDORED_FROM.txt"
  rm -rf "$VENDOR/$name"; mkdir -p "$VENDOR"
  mv "$tmp/src" "$VENDOR/$name"
  rm -rf "$tmp"
}

case "${1:-setup}" in
  clean) rm -rf "$VENDOR/Citadel" "$VENDOR/swift-nio-ssh"; echo "removed"; exit 0 ;;
  check) verify && echo "OK: Citadel and swift-nio-ssh are vendored, pinned and patched" && exit 0 || exit 1 ;;
esac

if verify >/dev/null 2>&1; then echo "OK: already vendored, pinned and patched"; exit 0; fi
[ -f "$VENDOR/Citadel/VENDORED_FROM.txt" ] && grep -q "^$CITADEL_COMMIT" "$VENDOR/Citadel/VENDORED_FROM.txt" || fetch Citadel "$CITADEL_URL" "$CITADEL_COMMIT"
fetch swift-nio-ssh "$NIOSSH_URL" "$NIOSSH_COMMIT"
(cd "$VENDOR/swift-nio-ssh" && patch -p1 --quiet < "$PATCH")
# Citadel uses the vendored fork by path (R155). The comment lines say what changed; an already-changed file is left alone.
if grep -q 'url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4" ..< "0.4.0"' "$VENDOR/Citadel/Package.swift"; then
  sed -i 's#^        \.package(url: "https://github.com/Wellz26/swift-nio-ssh\.git", "0\.3\.4" \.\.< "0\.4\.0"),$#        // Video Player change (scripts/setup-citadel.sh): the vendored, patched fork next to this folder, by path, so the\n        // build has one source of the swift-nio-ssh identity (was: the Wellz26 fork by URL, 0.3.4 ..< 0.4.0).\n        .package(path: "../swift-nio-ssh"),#' "$VENDOR/Citadel/Package.swift"
fi
verify && echo "OK: vendored Citadel $CITADEL_COMMIT and swift-nio-ssh $NIOSSH_COMMIT (patched)"
