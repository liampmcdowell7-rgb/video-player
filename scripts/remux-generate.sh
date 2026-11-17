#!/usr/bin/env bash
# Generates the test media for the RemuxEngine tests (Linux / WSL). Synthetic test patterns and tones only.
#
#   engine_hdr10.mkv   720p HEVC Main10 HDR10 (Colour element + in-band SEI), B-frames and open GOPs, 2 s keyframe
#                      interval, 20 s; audio: AC-3 5.1, E-AC-3 5.1, AAC stereo, FLAC 7.1; one PGS subtitle track
#   engine_h264.mkv    720p H.264 SDR with B-frames, 10 s, AAC + AC-3
#   engine_nocues.mkv  the HDR10 file muxed without Cues (mkvmerge --no-cues)
#   engine_sub.sup     the hand-built PGS stream (see below)
#
# FFmpeg cannot ENCODE PGS: its libavcodec has a `hdmv_pgs_subtitle` decoder only, no encoder. So the PGS stream is
# built by scripts/remux-make-sup.py (a small Python writer of the Presentation Graphic Stream segments: PCS, WDS, PDS,
# ODS, END) and muxed with mkvmerge, which accepts .sup files. Only the pass-through of the track is tested.
#
# Needs the spike tools from scripts/spikes/remux/00-setup.sh (GPL ffmpeg is used to ENCODE test video only; it is
# never shipped). Output directory: $VP_REMUX_MEDIA or ~/vp-remux-spike/media.
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/spikes/remux/env.sh"
out="${VP_REMUX_MEDIA:-$M}"
mkdir -p "$out"
cd "$out"

echo "== video: HEVC Main10 HDR10 with B-frames and open GOPs (x265)"
MD='G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)'
V="testsrc2=size=1280x720:rate=24:duration=20,format=yuv420p10le"
$GPLF -v error -y -f lavfi -i "$V" -c:v libx265 -preset veryfast -crf 26 -pix_fmt yuv420p10le \
  -x265-params "repeat-headers=1:keyint=48:min-keyint=48:scenecut=0:bframes=4:open-gop=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=$MD:max-cll=1000,400:range=limited:log-level=error" \
  -f hevc engine_hdr10.h265

echo "== audio: AC-3 5.1, E-AC-3 5.1, AAC stereo, FLAC 7.1"
$GPLF -v error -y \
  -f lavfi -i "sine=frequency=440:duration=20,aformat=sample_rates=48000,pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0" \
  -f lavfi -i "sine=frequency=330:duration=20,aformat=sample_rates=48000,pan=stereo|FL=c0|FR=c0" \
  -f lavfi -i "sine=frequency=220:duration=20,aformat=sample_rates=48000,pan=7.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0|SL=c0|SR=c0" \
  -map 0:a -c:a:0 ac3 -b:a:0 640k -metadata:s:a:0 language=eng -metadata:s:a:0 title="English 5.1 AC-3" \
  -map 0:a -c:a:1 eac3 -b:a:1 768k -metadata:s:a:1 language=fra -metadata:s:a:1 title="Francais 5.1 E-AC-3" \
  -map 1:a -c:a:2 aac -b:a:2 160k -metadata:s:a:2 language=eng -metadata:s:a:2 title="Stereo AAC" \
  -map 2:a -c:a:3 flac -metadata:s:a:3 language=eng -metadata:s:a:3 title="7.1 FLAC" \
  engine_audio.mkv

echo "== PGS subtitle stream (hand-built)"
python3 -I "$here/remux-make-sup.py" engine_sub.sup

echo "== MKV with mkvmerge (Colour element as rippers write it)"
FPS=24
P3="--colour-matrix 0:9 --colour-range 0:1 --colour-primaries 0:9 --colour-transfer-characteristics 0:16"
HDR="--max-content-light 0:1000 --max-frame-light 0:400 --chromaticity-coordinates 0:0.680,0.320,0.265,0.690,0.150,0.060 --white-colour-coordinates 0:0.3127,0.3290 --max-luminance 0:1000 --min-luminance 0:0.0001"
mkvmerge -q -o engine_hdr10.mkv --default-duration 0:${FPS}fps $P3 $HDR engine_hdr10.h265 \
  engine_audio.mkv --language 0:eng --track-name 0:"English PGS" engine_sub.sup
mkvmerge -q --no-cues -o engine_nocues.mkv --default-duration 0:${FPS}fps $P3 $HDR engine_hdr10.h265 engine_audio.mkv

echo "== H.264 SDR with B-frames"
$GPLF -v error -y -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=10,format=yuv420p" -c:v libx264 -preset veryfast -crf 24 -bf 3 -g 48 -keyint_min 48 -sc_threshold 0 \
  -x264-params "colorprim=bt709:transfer=bt709:colormatrix=bt709" -f h264 engine_h264.h264
$GPLF -v error -y -f lavfi -i "sine=frequency=500:duration=10,aformat=sample_rates=48000,pan=stereo|FL=c0|FR=c0" -c:a aac -b:a 128k engine_h264_audio.mkv
mkvmerge -q -o engine_h264.mkv --default-duration 0:${FPS}fps --colour-matrix 0:1 --colour-primaries 0:1 --colour-transfer-characteristics 0:1 engine_h264.h264 engine_h264_audio.mkv

ls -la engine_hdr10.mkv engine_nocues.mkv engine_h264.mkv engine_sub.sup
echo "ok: media in $out"
