#!/usr/bin/env bash
# Remux spike, step 2: remux the test MKVs to fragmented MP4 with LGPL ffmpeg and print what the OUTPUT boxes contain.
# Usage: bash 20-remux.sh [all|master|9.0|8.1] [input-name ...]     outputs: ~/vp-remux-spike/out/<version>/
# Every variant prints: the exact command, the ffmpeg exit status, the distinct warnings, then (only if the file is
# valid) the box summary from boxes.py. Failed runs delete their partial output so a broken file is never inspected.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
O="$T/out"; mkdir -p "$O"
FM="+frag_keyframe+empty_moov+default_base_moof"

run() { # label ffmpegdir outname input -- ffmpeg-args-after-input
  local lbl=$1 dir=$2 name=$3 in=$4; shift 4
  local o="$O/$lbl"; mkdir -p "$o"; rm -f "$o/$name"
  echo "--- [$lbl] $name <= $in : ffmpeg -i $in $*"
  "$dir/ffmpeg" -hide_banner -v warning -y -i "$M/$in" "$@" "$o/$name" >"$o/$name.log" 2>&1; local rc=$?
  sed 's/0x[0-9a-f]*//g' "$o/$name.log" | sort | uniq -c | head -6
  if [ $rc -ne 0 ]; then echo "    EXIT $rc -> FAILED (partial output deleted)"; rm -f "$o/$name"; return; fi
  echo "    EXIT 0, $(stat -c %s "$o/$name") bytes"
  $PY "$SPIKE_DIR/boxes.py" "$o/$name" | grep -av "top-level\|moof fragments\|ftyp\|pasp"
}

for pair in "master:$LGPL" "9.0:$LGPL90" "8.1:$LGPL81"; do
  lbl=${pair%%:*}; dir=${pair#*:}
  case "${1:-all}" in all|"$lbl") ;; *) continue;; esac
  echo "################ LGPL ffmpeg $lbl: $("$dir/ffmpeg" -hide_banner -version | head -1)"
  # A. the plain command people would try: everything copied, empty_moov
  run $lbl $dir A_hdr10_allcopy.mp4 hdr10.mkv -map 0:v -map 0:a:0 -map 0:a:1 -map 0:a:2 -c copy -movflags $FM
  # B. same plus delay_moov (moov written after the first fragment so AC-3/E-AC-3 dac3/dec3 can be built from real packets)
  run $lbl $dir B_hdr10_delaymoov.mp4 hdr10.mkv -map 0:v -map 0:a:0 -map 0:a:1 -map 0:a:2 -c copy -movflags $FM+delay_moov
  # C. video only, default flags (what does ffmpeg write for the video track by itself)
  for f in hdr10 hdr10_sei_only hlg dv81 dv5 sdr_h264; do
    run $lbl $dir C_${f}_video.mp4 $f.mkv -map 0:v -c copy -movflags $FM
  done
  # D. video only, -tag:v hvc1 (+ -strict unofficial so dvcC/dvvC is written)
  for f in hdr10 dv81 dv5; do
    run $lbl $dir D_${f}_hvc1_unofficial.mp4 $f.mkv -map 0:v -c copy -tag:v hvc1 -strict unofficial -movflags $FM
  done
done
