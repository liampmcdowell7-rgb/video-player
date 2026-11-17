#!/usr/bin/env bash
# Citadel SFTP backend tests (WSL / Linux): unit tests plus live tests against real rclone SFTP servers.
#
#   bash scripts/test-sftp.sh          run everything
#   bash scripts/test-sftp.sh stop     stop the extra servers this script started
#
# What it does:
#   1. bash scripts/setup-citadel.sh   (vendors Citadel 0.12.1 and the patched swift-nio-ssh fork, pinned commits)
#   2. starts the rclone servers from scripts/test-servers.sh (password SFTP on 127.0.0.1:12022)
#   3. makes throwaway host keys and user keys with ssh-keygen under ~/video-player-test-servers/sftp-keys (outside the repo)
#   4. starts one more rclone SFTP server on 12023 (host key A, authorized keys); the test starts and stops a third on 12024
#      itself, to swap the host key between two connections
#   5. runs `swift test` for SourceSFTPCitadelTests (and SourceSFTPTests) in a private trimmed copy of the package,
#      ~/vp-build-sftp-citadel, so only Citadel's tree and this code are compiled (set VP_FULL=1 to use the real manifest)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${VP_TEST_HOME:-$HOME/video-player-test-servers}"
KEYS="$BASE/sftp-keys"; RUN="$BASE/run"; LOGS="$BASE/logs"
KEY_PORT=12023; CHANGE_PORT=12024
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"

stop_extra() {
  if [ -f "$RUN/sftp-keys.pid" ]; then kill "$(cat "$RUN/sftp-keys.pid")" 2>/dev/null || true; rm -f "$RUN/sftp-keys.pid"; fi
}
[ "${1:-}" = stop ] && { stop_extra; echo "stopped"; exit 0; }
trap stop_extra EXIT

wait_port() { for _ in $(seq 1 40); do (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3>&- 2>/dev/null || true; return 0; }; sleep 0.25; done; return 1; }

bash "$HERE/scripts/setup-citadel.sh" || exit 1
bash "$HERE/scripts/test-servers.sh" start >/dev/null 2>&1 || true      # one failed server must not stop us; we check the one we need
eval "$(bash "$HERE/scripts/test-servers.sh" env)"
wait_port "$VP_SFTP_PORT" || { echo "the rclone SFTP server on port $VP_SFTP_PORT is not up (see $LOGS/sftp.log)"; exit 1; }
RCLONE="$BASE/bin/rclone"; DATA="$BASE/data"
[ -x "$RCLONE" ] && [ -d "$DATA" ] || { echo "rclone or the test media is missing; run scripts/test-servers.sh start"; exit 1; }

mkdir -p "$KEYS"
mk() { [ -f "$KEYS/$1" ] || ssh-keygen -q -t "$2" ${3:+-b $3} -N "${4:-}" -C vp-test -f "$KEYS/$1"; }
PASSPHRASE="test-passphrase-local"
mk host_a ed25519; mk host_b ed25519
mk user_ed25519 ed25519; mk user_ed25519_pp ed25519 "" "$PASSPHRASE"; mk user_rsa rsa 2048; mk user_unknown ed25519
cat "$KEYS/user_ed25519.pub" "$KEYS/user_ed25519_pp.pub" "$KEYS/user_rsa.pub" > "$KEYS/authorized_keys"
FINGERPRINT="$(ssh-keygen -l -E sha256 -f "$KEYS/host_a.pub" | awk '{print $2}')"

stop_extra
nohup setsid "$RCLONE" serve sftp "$DATA" --addr "127.0.0.1:$KEY_PORT" --read-only --user "$VP_TEST_USER" --pass "$VP_TEST_PASS" \
  --key "$KEYS/host_a" --authorized-keys "$KEYS/authorized_keys" >"$LOGS/sftp-keys.log" 2>&1 &
echo $! > "$RUN/sftp-keys.pid"
wait_port "$KEY_PORT" || { echo "the key-auth SFTP server did not start (see $LOGS/sftp-keys.log)"; exit 1; }

export VP_RCLONE="$RCLONE" VP_SFTP_DATA="$DATA" VP_SFTP_KEY_PORT="$KEY_PORT" VP_SFTP_CHANGE_PORT="$CHANGE_PORT"
export VP_SFTP_HOSTKEY_FINGERPRINT="$FINGERPRINT" VP_SFTP_HOSTKEY_A="$KEYS/host_a" VP_SFTP_HOSTKEY_B="$KEYS/host_b"
export VP_SFTP_KEY_ED25519="$KEYS/user_ed25519" VP_SFTP_KEY_ED25519_PASSPHRASED="$KEYS/user_ed25519_pp"
export VP_SFTP_KEY_PASSPHRASE="$PASSPHRASE" VP_SFTP_KEY_RSA="$KEYS/user_rsa" VP_SFTP_KEY_UNKNOWN="$KEYS/user_unknown"

WORK="${VP_BUILD_DIR:-$HOME/vp-build-sftp-citadel}"
mkdir -p "$WORK"
# VP_KEEP_RESOLVED=1 keeps a Package.resolved and .build already in the private folder (used to reuse fetched checkouts).
RSYNC_EXTRA=(); [ "${VP_KEEP_RESOLVED:-0}" = 1 ] && RSYNC_EXTRA=(--exclude Package.resolved)
rsync -a --delete --exclude .build "${RSYNC_EXTRA[@]}" "$HERE/Packages/VideoPlayerCore/" "$WORK/"
if [ "${VP_FULL:-0}" != 1 ]; then
  cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
// Trimmed manifest written by scripts/test-sftp.sh: only what the Citadel backend needs.
import PackageDescription
let package = Package(
    name: "VideoPlayerCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SourceSFTPCitadel", targets: ["SourceSFTPCitadel"])],
    dependencies: [
        .package(path: "Vendor/Citadel"), .package(path: "Vendor/swift-nio-ssh"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(name: "VideoPlayerCore"),
        .target(name: "SourceSFTP", dependencies: ["VideoPlayerCore"]),
        .testTarget(name: "SourceSFTPTests", dependencies: ["SourceSFTP", "VideoPlayerCore"]),
        .target(name: "SourceSFTPCitadel", dependencies: [
            "VideoPlayerCore", "SourceSFTP",
            .product(name: "Citadel", package: "Citadel"), .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "NIOCore", package: "swift-nio"), .product(name: "NIOFoundationCompat", package: "swift-nio"),
            .product(name: "Crypto", package: "swift-crypto"),
        ]),
        .testTarget(name: "SourceSFTPCitadelTests", dependencies: [
            .target(name: "SourceSFTPCitadel"), "SourceSFTP", "VideoPlayerCore", .product(name: "Citadel", package: "Citadel"),
        ]),
    ]
)
SWIFT
fi
cd "$WORK"
# --build-system native: with Swift 6.4.2's default build system the test runner for SourceSFTPCitadelTests lists 0 tests
# (verified: `swift test list` showed none; the native system finds all 19 unit tests). Recorded in OPEN_QUESTIONS.md.
swift test --build-system native --scratch-path .build-native -j "${VP_JOBS:-2}" --filter 'SourceSFTPCitadelTests|SourceSFTPTests' 2>&1
