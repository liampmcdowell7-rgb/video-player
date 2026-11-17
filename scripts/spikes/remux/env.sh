#!/usr/bin/env bash
# Sourced by the other spike scripts: tool locations. Not run directly.
T="${VP_REMUX_HOME:-$HOME/vp-remux-spike}"
SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LGPL="$T/tools/lgpl/bin"          # FFmpeg LGPL master snapshot: the remuxer under test
LGPL90="$T/tools/lgpl9.0/bin"     # FFmpeg 9.0.x LGPL
LGPL81="$T/tools/lgpl8.1/bin"     # FFmpeg 8.1.x LGPL
GPLF="$T/tools/gpl/bin/ffmpeg"    # GPL build: ONLY used to encode test video (libx265)
DOVI="$T/tools/dovi/dovi_tool"
export LD_LIBRARY_PATH="$T/debs/x/usr/lib/x86_64-linux-gnu:$HOME/video-player-test-servers/icu/usr/lib/x86_64-linux-gnu:$T/icu/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export PATH="$T/debs/x/usr/bin:$PATH"          # mkvmerge, mkvinfo, mkvextract
M="$T/media"; mkdir -p "$M"
PY="python3 -I"
