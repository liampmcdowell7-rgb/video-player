#!/usr/bin/env bash
# Remux spike, step 2c: colour-signalling variants, full remux (video+audio+subs+chapters), HLS fMP4,
# DTS / TrueHD / FLAC copy into MP4, and E-AC-3 / AC-3 behaviour. LGPL master ffmpeg only (versions behave the same, see 25-versions.sh).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
O="$T/out/extra"; mkdir -p "$O"; cd "$O"
FF="$LGPL/ffmpeg -hide_banner -v warning -y"
FM="+frag_keyframe+empty_moov+default_base_moof+delay_moov"
show() { $PY "$SPIKE_DIR/boxes.py" "$1" | grep -av "top-level\|moof fragments\|ftyp\|pasp\|btrt"; }
try() { # name, args...   (input/args given by caller; last arg is the output file)
  echo "--- ffmpeg $*"; $FF "$@" 2>&1 | sed 's/0x[0-9a-f]*//g' | sort | uniq -c | head -5; local out="${!#}"; [ -s "$out" ] && show "$out" || echo "    (no output)"; }

echo "################ 1. colour signalling when the MKV has NO Colour element and the bitstream has NO VUI colour"
if [ ! -s "$M/novui.mkv" ]; then
  $GPLF -v error -y -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=4,format=yuv420p10le" -c:v libx265 -preset ultrafast -crf 26 -g 24 \
    -pix_fmt yuv420p10le -x265-params "repeat-headers=1:log-level=error" -f hevc "$M/novui.h265"
  mkvmerge -q -o "$M/novui.mkv" --default-duration 0:24fps "$M/novui.h265"
fi
try -i "$M/novui.mkv" -c copy -tag:v hvc1 -movflags $FM novui_plain.mp4
echo "  -> now force the colour tags on the output (copy mode, ffmpeg options -color_primaries/-color_trc/-colorspace)"
try -i "$M/novui.mkv" -c copy -tag:v hvc1 -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -movflags $FM novui_forced.mp4

echo "################ 2. hevc_metadata bsf (rewrites VUI/SEI-less fields in the bitstream) and +write_colr"
try -i "$M/novui.mkv" -c copy -tag:v hvc1 -bsf:v hevc_metadata=colour_primaries=9:transfer_characteristics=16:matrix_coefficients=9 -movflags $FM novui_bsf.mp4
try -i "$M/hdr10.mkv" -map 0:v -c copy -tag:v hvc1 -movflags $FM+write_colr hdr10_write_colr.mp4
try -i "$M/hdr10.mkv" -map 0:v -c copy -tag:v hvc1 -strict unofficial -movflags $FM+write_colr hdr10_unofficial_write_colr.mp4

echo "################ 3. full remux: video + 3 audio + 2 subtitle tracks + chapters, recommended flags"
try -i "$M/dv81.mkv" -map 0:v -map 0:a:0 -map 0:a:1 -map 0:a:2 -map 0:s -c copy -c:s mov_text -tag:v hvc1 -strict unofficial -movflags $FM full_dv81.mp4
echo "  -> same without chapters (-map_chapters -1)"
try -i "$M/dv81.mkv" -map 0:v -map 0:a:0 -map 0:a:1 -map 0:a:2 -map 0:s -map_chapters -1 -c copy -c:s mov_text -tag:v hvc1 -strict unofficial -movflags $FM full_dv81_nochap.mp4
$LGPL/ffprobe -hide_banner -v error -show_entries stream=index,codec_name,codec_type,codec_tag_string:stream_tags=language -of compact full_dv81.mp4
$LGPL/ffprobe -hide_banner -v error -show_chapters -of compact full_dv81.mp4 | head -5
echo "  -> subtitles as WebVTT text in fMP4 (wvtt) instead of mov_text"
try -i "$M/dv81.mkv" -map 0:v:0 -map 0:s -c:v copy -c:s webvtt -tag:v hvc1 -movflags $FM sub_wvtt.mp4

echo "################ 4. DTS / TrueHD / FLAC / PCM copy into MP4 (are they accepted?)"
$FF -f lavfi -i "sine=frequency=440:duration=4,aformat=sample_rates=48000,pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0" -strict -2 -c:a truehd truehd.mkv 2>&1 | head -3
$FF -i "$M/audio_subs.mkv" -map 0:a:3 -c copy dts.mkv 2>&1 | head -3
ls -l truehd.mkv dts.mkv 2>&1 | awk '{print $5, $9}'
for f in truehd dts; do
  echo "--- $f.mkv -> mp4 (-c copy) default"; $FF -i $f.mkv -c copy -movflags $FM $f.mp4 2>&1 | sed 's/0x[0-9a-f]*//g' | sort | uniq -c | head -4; [ -s $f.mp4 ] && show $f.mp4 || echo "    (no output)"
  echo "--- $f.mkv -> mp4 (-c copy) -strict unofficial"; $FF -i $f.mkv -c copy -strict unofficial -movflags $FM ${f}_u.mp4 2>&1 | sed 's/0x[0-9a-f]*//g' | sort | uniq -c | head -4; [ -s ${f}_u.mp4 ] && show ${f}_u.mp4 || echo "    (no output)"
done
echo "--- E-AC-3 copy without delay_moov"; $FF -i "$M/audio_subs.mkv" -map 0:a:1 -c copy -movflags +frag_keyframe+empty_moov+default_base_moof eac3_nodelay.mp4 2>&1 | sed 's/0x[0-9a-f]*//g' | sort | uniq -c | head -3

echo "################ 5. HLS fMP4 (video+audio, 2 s segments, hvc1)"
rm -rf hls; mkdir hls
$FF -i "$M/dv81.mkv" -map 0:v -map 0:a:0 -map 0:a:1 -map_chapters -1 -c copy -tag:v hvc1 -strict unofficial -f hls -hls_segment_type fmp4 \
  -hls_time 2 -hls_playlist_type vod -hls_flags independent_segments -hls_fmp4_init_filename init.mp4 -hls_segment_filename "hls/seg_%03d.m4s" hls/index.m3u8 2>&1 | sed 's/0x[0-9a-f]*//g' | sort | uniq -c | head -5
ls -l hls | awk 'NR>1{print $5, $9}' | head -12
sed -n 1,14p hls/index.m3u8
show hls/init.mp4
echo "--- HLS with explicit variant map (so the master playlist carries CODECS)"
rm -rf hls2; mkdir hls2
$FF -i "$M/dv81.mkv" -map 0:v -map 0:a:0 -map_chapters -1 -c copy -tag:v hvc1 -strict unofficial -f hls -hls_segment_type fmp4 \
  -hls_time 2 -hls_playlist_type vod -hls_flags independent_segments -master_pl_name master.m3u8 -var_stream_map "v:0,a:0" \
  -hls_segment_filename "hls2/seg_%v_%03d.m4s" "hls2/v%v.m3u8" 2>&1 | sed 's/0x[0-9a-f]*//g' | sort | uniq -c | head -5
cat hls2/master.m3u8
