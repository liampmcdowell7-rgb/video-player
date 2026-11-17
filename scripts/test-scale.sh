#!/usr/bin/env bash
# Runs the library-index scale tests including the 100,000-item one, in a release build (about 5 minutes).
# Usage: bash scripts/test-scale.sh
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
[ "$(uname -s)" = Linux ] && bash "$HERE/scripts/setup-sqlite.sh"
WORK="${VP_BUILD_DIR:-$HOME/video-player-scale-build}"
mkdir -p "$WORK"
rsync -a --delete --exclude .build "$HERE/Packages/VideoPlayerCore/" "$WORK/"
cd "$WORK"
VP_RUN_100K=1 swift test -c release -Xswiftc -enable-testing --filter 'ScaleTests/testScale(1000|10000|100000)$'
