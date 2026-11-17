#!/usr/bin/env bash
# Runs the VideoPlayerCore unit tests on Linux (for example inside WSL). Copies the package
# to a local folder first because builds on a Windows-mounted drive are slow.
# Usage: bash scripts/test-core.sh
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
[ "$(uname -s)" = Linux ] && bash "$HERE/scripts/setup-sqlite.sh"   # LibraryIndex links the system SQLite on Linux
WORK="${VP_BUILD_DIR:-$HOME/video-player-core-build}"
mkdir -p "$WORK"
rsync -a --delete --exclude .build "$HERE/Packages/VideoPlayerCore/" "$WORK/" 2>/dev/null || { rm -rf "$WORK"; mkdir -p "$WORK"; cp -r "$HERE/Packages/VideoPlayerCore/." "$WORK/"; }
cd "$WORK"
# AttributionNoticeTests reads App/Support/Attribution.swift, which is not inside the copied package.
VP_PROJECT_ROOT="$HERE" swift test
