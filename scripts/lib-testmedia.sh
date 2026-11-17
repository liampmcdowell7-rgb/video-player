#!/usr/bin/env bash
# Shared by scripts/test-servers.sh and scripts/test-mediaservers.sh (source it; needs $DATA and python3).
# Creates the deterministic test media. Idempotent: a file that already has the right size is left alone.
# Byte k of every file is (k*7+3) mod 251, so tests can check any offset. The files are NOT real video;
# the media servers index them by name and extension.

make_file() { # path size_bytes
  mkdir -p "$(dirname "$1")"
  [ -f "$1" ] && [ "$(stat -c %s "$1")" = "$2" ] && return 0
  python3 - "$1" "$2" <<'PY'
import sys
path, size = sys.argv[1], int(sys.argv[2])
period = bytes(((i * 7 + 3) % 251) for i in range(251))   # byte at offset k is period[k % 251]
with open(path, "wb") as f:
    f.write((period * (size // 251 + 1))[:size])
PY
}

make_media() {
  command -v python3 >/dev/null 2>&1 || { echo "Missing tool: python3 (needed to generate the test media)" >&2; return 1; }
  mkdir -p "$DATA"
  make_file "$DATA/Movies/Test Movie (2020).mkv" 3145728
  make_file "$DATA/Movies/Test Movie (2020).en.srt" 2048
  make_file "$DATA/Shows/Test Show (2019)/Season 1/Test Show - S01E01 - Pilot.mkv" 1048576
  make_file "$DATA/Shows/Test Show (2019)/Season 1/Test Show - S01E02.mkv" 1048576
  make_file "$DATA/Odd Names/$(printf 'Caf\303\251 \342\200\223 100%% [test] #1.mp4')" 4096
  make_file "$DATA/big/Large Sample.mkv" 41943040   # 40 MB, for the sustained-read check
  printf 'not a video\n' > "$DATA/notes.txt"
}
