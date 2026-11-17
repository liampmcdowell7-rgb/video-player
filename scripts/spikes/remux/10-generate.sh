#!/usr/bin/env bash
# Remux spike, step 1: generate test inputs in ~/vp-remux-spike/media.
# Video is a synthetic test pattern (generic, no real titles). The GPL ffmpeg encodes (libx265/libx264);
# mkvmerge muxes the MKVs the way rippers do (Colour element, Dolby Vision BlockAdditionMapping).
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$M"
FPS=24; SECS=10; FRAMES=$((FPS*SECS))
V="testsrc2=size=1920x1080:rate=$FPS:duration=$SECS,format=yuv420p10le"

echo "== video elementary streams (x265 10-bit; HDR10 / HLG; x264 8-bit)"
MD='G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)'
$GPLF -v error -y -f lavfi -i "$V" -c:v libx265 -preset ultrafast -crf 24 -g 24 -pix_fmt yuv420p10le \
  -x265-params "repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=$MD:max-cll=1000,400:range=limited:log-level=error" \
  -f hevc hdr10.h265
$GPLF -v error -y -f lavfi -i "$V" -c:v libx265 -preset ultrafast -crf 24 -g 24 -pix_fmt yuv420p10le \
  -x265-params "repeat-headers=1:colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc:range=limited:log-level=error" \
  -f hevc hlg.h265
$GPLF -v error -y -f lavfi -i "testsrc2=size=1920x1080:rate=$FPS:duration=$SECS,format=yuv420p" -c:v libx264 -preset ultrafast -crf 22 -g 24 \
  -x264-params "colorprim=bt709:transfer=bt709:colormatrix=bt709" -f h264 sdr.h264

echo "== audio (5.1 test tone): AC-3, E-AC-3, AAC, DTS (FFmpeg 'dca' encoder is EXPERIMENTAL), 2 SRT subtitle tracks, chapters"
cat > en.srt <<'EOT'
1
00:00:01,000 --> 00:00:03,000
First English line

2
00:00:04,000 --> 00:00:06,000
Second English line
EOT
cat > fr.srt <<'EOT'
1
00:00:01,000 --> 00:00:03,000
Premiere ligne

2
00:00:04,000 --> 00:00:06,000
Deuxieme ligne
EOT
cat > chapters.ffmeta <<'EOT'
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=2000
title=Intro
[CHAPTER]
TIMEBASE=1/1000
START=2000
END=8000
title=Episode
[CHAPTER]
TIMEBASE=1/1000
START=8000
END=10000
title=Credits
EOT
$GPLF -v error -y \
  -f lavfi -i "sine=frequency=440:duration=$SECS,aformat=sample_rates=48000,pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0" \
  -f lavfi -i "sine=frequency=330:duration=$SECS,aformat=sample_rates=48000,pan=stereo|FL=c0|FR=c0" \
  -i en.srt -i fr.srt -i chapters.ffmeta \
  -map 0:a -c:a:0 ac3 -b:a:0 640k \
  -map 0:a -c:a:1 eac3 -b:a:1 768k \
  -map 1:a -c:a:2 aac -b:a:2 160k \
  -map 0:a -strict -2 -c:a:3 dca -b:a:3 1509k \
  -map 2 -map 3 -c:s subrip -metadata:s:s:0 language=eng -metadata:s:s:1 language=fra \
  -metadata:s:a:0 language=eng -metadata:s:a:1 language=eng -metadata:s:a:2 language=eng -metadata:s:a:3 language=eng \
  -map_chapters 4 audio_subs.mkv

echo "== MKVs with mkvmerge (HDR10 with Colour element; HLG; SDR H.264) and one in-band-SEI-only HDR10 MKV (no Colour element)"
P3="--colour-matrix 0:9 --colour-range 0:1 --colour-primaries 0:9"
mkvmerge -q -o hdr10.mkv --default-duration 0:${FPS}fps $P3 --colour-transfer-characteristics 0:16 \
  --max-content-light 0:1000 --max-frame-light 0:400 \
  --chromaticity-coordinates 0:0.680,0.320,0.265,0.690,0.150,0.060 --white-colour-coordinates 0:0.3127,0.3290 \
  --max-luminance 0:1000 --min-luminance 0:0.0001 hdr10.h265 audio_subs.mkv
mkvmerge -q -o hlg.mkv --default-duration 0:${FPS}fps $P3 --colour-transfer-characteristics 0:18 hlg.h265 audio_subs.mkv
mkvmerge -q -o sdr_h264.mkv --default-duration 0:${FPS}fps --colour-matrix 0:1 --colour-primaries 0:1 --colour-transfer-characteristics 0:1 sdr.h264 audio_subs.mkv
mkvmerge -q -o hdr10_sei_only.mkv --default-duration 0:${FPS}fps hdr10.h265 audio_subs.mkv   # no Colour element: only the SEI inside the bitstream

echo "== Dolby Vision: RPU from dovi_tool generate, injected into the HDR10 bitstream"
cat > dv81.json <<EOT
{ "cm_version": "V29", "length": $FRAMES, "profile": "8.1",
  "level6": { "max_display_mastering_luminance": 1000, "min_display_mastering_luminance": 1, "max_content_light_level": 1000, "max_frame_average_light_level": 400 },
  "default_metadata_blocks": [ { "Level1": { "min_pq": 0, "max_pq": 3079, "avg_pq": 1229 } } ] }
EOT
sed 's/"profile": "8.1"/"profile": "5"/' dv81.json > dv5.json
$DOVI generate -j dv81.json -o rpu81.bin >/dev/null
$DOVI inject-rpu -i hdr10.h265 --rpu-in rpu81.bin -o dv81.h265 >/dev/null
mkvmerge -q -o dv81.mkv --default-duration 0:${FPS}fps $P3 --colour-transfer-characteristics 0:16 dv81.h265 audio_subs.mkv
if $DOVI generate -j dv5.json -o rpu5.bin >/dev/null 2>dv5.err; then
  $DOVI inject-rpu -i hdr10.h265 --rpu-in rpu5.bin -o dv5.h265 >/dev/null
  # Profile 5 has no HDR10 base layer: the colour tags of the base layer are unspecified, so do not tag them.
  mkvmerge -q -o dv5.mkv --default-duration 0:${FPS}fps dv5.h265 audio_subs.mkv
else
  echo "profile 5 RPU could not be generated: $(cat dv5.err)"
fi
ls -l *.mkv | awk '{print $5, $9}'
