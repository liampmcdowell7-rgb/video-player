#!/usr/bin/env bash
# Remux spike, step 3: throughput of the LGPL remux on a ~2 GB generated MKV (looped copy of the HDR10/DV 8.1 test clip).
# Reports wall time, MB/s of input, CPU (user+sys) and peak RSS via /usr/bin/time. Disk is WSL ext4 (vhd), not a network share.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
O="$T/out/big"; mkdir -p "$O"
BIG="$M/big_dv81.mkv"
df -h "$T" | tail -1
if [ ! -s "$BIG" ]; then
  LOOPS=${LOOPS:-185}
  echo "== generating $BIG: dv81.mkv looped $LOOPS times with -c copy (video + 4 audio + subs + chapters, DV 8.1 RPU in every frame)"
  $LGPL/ffmpeg -hide_banner -v error -y -stream_loop $LOOPS -i "$M/dv81.mkv" -map 0:v -map 0:a:0 -map 0:a:1 -map 0:a:2 -c copy "$BIG"
fi
SZ=$(stat -c %s "$BIG"); echo "input: $SZ bytes ($((SZ/1000000)) MB); duration: $($LGPL/ffprobe -v error -show_entries format=duration -of csv=p=0 "$BIG") s"
TM=/usr/bin/time
[ -x $TM ] || { echo "/usr/bin/time missing: using bash time only"; TM=""; }
measure() { # label cmd...
  local lbl=$1; shift
  sync; local t0=$(date +%s.%N)
  if [ -n "$TM" ]; then $TM -f "%U %S %M" -o "$O/time.txt" "$@" >/dev/null 2>"$O/err.txt"; else "$@" >/dev/null 2>"$O/err.txt"; fi
  local rc=$? t1=$(date +%s.%N)
  local wall=$(echo "$t1 - $t0" | bc -l)
  if [ -n "$TM" ]; then read u s rss < "$O/time.txt"; else u=?; s=?; rss=?; fi
  printf "%-34s rc=%s wall=%.2fs  %.0f MB/s  user=%ss sys=%ss  cpu=%s%%  peakRSS=%s MB\n" "$lbl" $rc $wall $(echo "$SZ/1000000/$wall" | bc -l) $u $s \
    $(echo "($u+$s)/$wall*100" | bc -l 2>/dev/null | cut -d. -f1) $(( ${rss:-0} / 1024 ))
}
FM="+frag_keyframe+empty_moov+default_base_moof+delay_moov"
COMMON="-hide_banner -v error -y -i $BIG -map 0:v -map 0:a:0 -map 0:a:1 -map 0:a:2 -map_chapters -1 -c copy -tag:v hvc1 -strict unofficial"
echo "== remux runs (page cache warm after the first read; first row includes disk read)"
for i in 1 2 3; do
  measure "fMP4 to file (run $i)" $LGPL/ffmpeg $COMMON -movflags $FM "$O/big.mp4"
done
measure "fMP4 to pipe (/dev/null)" $LGPL/ffmpeg $COMMON -f mp4 -movflags $FM -
measure "HLS fMP4, 6 s segments to disk" $LGPL/ffmpeg $COMMON -f hls -hls_segment_type fmp4 -hls_time 6 -hls_playlist_type vod -hls_flags independent_segments -hls_fmp4_init_filename init.mp4 -hls_segment_filename "$O/seg_%04d.m4s" "$O/index.m3u8"
echo "== output"; ls -l "$O/big.mp4" | awk '{print $5, $9}'; ls "$O"/seg_*.m4s | wc -l
echo "== sanity: output readable end to end"; $LGPL/ffprobe -v error -show_entries format=duration -of csv=p=0 "$O/big.mp4"
echo "== raw copy baseline (cp, same disk) for comparison"; measure "cp of the input" cp "$BIG" "$O/cp-test.bin"; rm -f "$O/cp-test.bin"
echo "== TrueHD with -strict -2 (experimental in MP4, not usable by AVPlayer; shown only for completeness)"
$LGPL/ffmpeg -hide_banner -v warning -y -i "$T/out/extra/truehd.mkv" -c copy -strict -2 -movflags $FM "$O/truehd.mp4" 2>&1 | head -3
[ -s "$O/truehd.mp4" ] && $PY "$SPIKE_DIR/boxes.py" "$O/truehd.mp4" | grep -a "sample entry\|mlp\|dmlp"
