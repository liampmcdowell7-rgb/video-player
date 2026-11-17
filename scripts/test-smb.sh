#!/usr/bin/env bash
# SMB source tests (WSL / Linux). Builds SourceSMB WITH the AMSMB2 dependency in a scratch package,
# which the main Package.swift does not contain yet.
#
#   bash scripts/test-smb.sh            unit tests (fake SMB library) + live tests if a server is reachable
#   bash scripts/test-smb.sh server     only start the test SMB server (impacket), print its settings
#   bash scripts/test-smb.sh stop       stop the test SMB server
#
# AMSMB2 4.0.3 does not compile with Swift 6.4 unpatched, so a patched copy is used:
#   scripts/patches/AMSMB2-4.0.3-swift6.4.patch   (one function in AMSMB2/Stream.swift)
# The copy lives in ~/vp-smb-scratch/Vendor/AMSMB2 and is created on first run.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$REPO/Packages/VideoPlayerCore"
WORK="${VP_SMB_DIR:-$HOME/vp-smb-scratch}"
BASE="${VP_TEST_HOME:-$HOME/video-player-test-servers}"
DATA="$BASE/data"
VENV="$BASE/smb-venv"
PORT="${VP_SMB_PORT:-12445}"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"

vendor() {
  [ -d "$WORK/Vendor/AMSMB2/AMSMB2" ] && return 0
  mkdir -p "$WORK/Vendor"
  git clone --quiet --branch 4.0.3 --depth 1 --recurse-submodules --shallow-submodules https://github.com/amosavian/AMSMB2.git "$WORK/Vendor/AMSMB2"
  (cd "$WORK/Vendor/AMSMB2" && git apply "$REPO/scripts/patches/AMSMB2-4.0.3-swift6.4.patch")
}

stop_server() { pkill -f "smbserver.py|impacket-smbserver|vp_smbserver" 2>/dev/null || true; sleep 1; echo "smb server stopped"; }

start_server() {
  [ -d "$DATA" ] || { echo "Run: bash scripts/test-servers.sh start   (creates $DATA)" >&2; exit 1; }
  [ -x "$VENV/bin/python" ] || { echo "No impacket venv at $VENV; see docs/SOURCES.md (SMB section)" >&2; exit 1; }
  stop_server >/dev/null
  setsid nohup "$VENV/bin/python" "$WORK/vp_smbserver.py" "$DATA" "$PORT" </dev/null >"$BASE/smb.log" 2>&1 &
  disown
  for _ in $(seq 1 20); do
    (exec 3<>/dev/tcp/127.0.0.1/"$PORT") 2>/dev/null && { echo "smb server up on 127.0.0.1:$PORT"; return 0; }
    sleep 1
  done
  echo "smb server did not start; see $BASE/smb.log" >&2; return 1
}

sync_package() {
  mkdir -p "$WORK/Sources" "$WORK/Tests"
  rm -rf "$WORK/Sources/VideoPlayerCore" "$WORK/Sources/SourceSMB" "$WORK/Tests/SourceSMBTests"
  cp -r "$PKG/Sources/VideoPlayerCore" "$WORK/Sources/VideoPlayerCore"
  cp -r "$PKG/Sources/SourceSMB" "$WORK/Sources/SourceSMB"
  cp -r "$PKG/Tests/SourceSMBTests" "$WORK/Tests/SourceSMBTests"
  cp "$REPO/scripts/vp_smbserver.py" "$WORK/vp_smbserver.py"
  cat > "$WORK/Package.swift" <<'EOF'
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "SMBScratch",
    platforms: [.tvOS("18.0"), .macOS(.v14)],
    products: [.library(name: "SourceSMB", targets: ["SourceSMB"])],
    dependencies: [.package(path: "Vendor/AMSMB2")],
    targets: [
        .target(name: "VideoPlayerCore"),
        .target(name: "SourceSMB", dependencies: ["VideoPlayerCore", .product(name: "AMSMB2", package: "AMSMB2")]),
        .testTarget(name: "SourceSMBTests", dependencies: ["SourceSMB", "VideoPlayerCore"]),
    ]
)
EOF
}

case "${1:-test}" in
  stop) stop_server; exit 0 ;;
  server) sync_package; start_server; echo "export VP_SMB_HOST=127.0.0.1 VP_SMB_PORT=$PORT VP_SMB_SHARE=Media VP_SMB_USER=tester VP_SMB_PASS=testpass-local"; exit 0 ;;
esac

vendor
sync_package
cd "$WORK"
if [ -x "$VENV/bin/python" ] && [ -d "$DATA" ] && [ -f "$WORK/vp_smbserver.py" ]; then
  start_server && export VP_SMB_HOST=127.0.0.1 VP_SMB_PORT="$PORT" VP_SMB_SHARE=Media VP_SMB_USER=tester VP_SMB_PASS=testpass-local \
    VP_TEST_DATA="$DATA"
fi
[ "${1:-}" = test ] && shift
swift test "$@"
