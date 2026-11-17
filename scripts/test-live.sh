#!/usr/bin/env bash
# Runs tests that need the local rclone test servers (WebDAV, HTTP, SFTP, FTP, DLNA).
# Starts them if they are not running and NEVER stops them, so several runs can share them.
# Each name gets its own build folder, so parallel runs do not collide.
# Usage: bash scripts/test-live.sh <name> [swift test arguments, e.g. --filter SourceFTPTests]
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${1:?usage: test-live.sh <name> [swift test args]}"; shift
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
WORK="$HOME/vp-build-$NAME"
mkdir -p "$WORK"
rsync -a --delete --exclude .build "$HERE/Packages/VideoPlayerCore/" "$WORK/" 2>/dev/null || { find "$WORK" -mindepth 1 -maxdepth 1 ! -name .build -exec rm -rf {} +; cp -r "$HERE/Packages/VideoPlayerCore/." "$WORK/"; }
bash "$HERE/scripts/test-servers.sh" start >/dev/null
eval "$(bash "$HERE/scripts/test-servers.sh" env)"
cd "$WORK"
swift test "$@"
