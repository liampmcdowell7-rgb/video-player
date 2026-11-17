#!/usr/bin/env bash
# Starts the local test servers, runs the integration tests against them, stops the servers.
# Costs nothing on Codemagic: runs in WSL / Linux only. Skips what cannot run here (see docs/SOURCES.md).
# Usage: bash scripts/test-integration.sh
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
WORK="$HOME/video-player-core-build"
mkdir -p "$WORK"
rsync -a --delete --exclude .build "$HERE/Packages/VideoPlayerCore/" "$WORK/" 2>/dev/null || { rm -rf "$WORK"; mkdir -p "$WORK"; cp -r "$HERE/Packages/VideoPlayerCore/." "$WORK/"; }

bash "$HERE/scripts/test-servers.sh" start
trap 'bash "$HERE/scripts/test-servers.sh" stop' EXIT
eval "$(bash "$HERE/scripts/test-servers.sh" env)"

cd "$WORK"
swift test --filter Integration
