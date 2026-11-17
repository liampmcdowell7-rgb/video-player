#!/usr/bin/env bash
# Spike 2: which lossless/PCM codec can carry decoded DTS / DTS-HD (up to 7.1) in fMP4 / HLS fMP4?
# Generates a 7.1 24-bit/48 kHz test signal (a different tone per channel), muxes it as FLAC, ALAC, PCM s16/s24/s32 (ipcm)
# and float (fpcm) into fMP4 and HLS fMP4 with the LGPL ffmpeg, prints the sample entry boxes, decodes back and compares md5.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
O="$T/out/audio"; rm -rf "$O"; mkdir -p "$O"; cd "$O"
FF="$LGPL/ffmpeg -hide_banner -v warning -y"
FM="+frag_keyframe+empty_moov+default_base_moof+delay_moov"
SRC="sine=f=220:d=6:r=48000[a];sine=f=330:d=6:r=48000[b];sine=f=440:d=6:r=48000[c];sine=f=110:d=6:r=48000[d];sine=f=550:d=6:r=48000[e];sine=f=660:d=6:r=48000[f];sine=f=770:d=6:r=48000[g];sine=f=880:d=6:r=48000[h];[a][b][c][d][e][f][g][h]amerge=inputs=8,aformat=sample_fmts=s32:channel_layouts=7.1"
echo "== 7.1 source (WAV, 24-bit content in s32 container)"
$FF -f lavfi -i "$SRC" -c:a pcm_s24le src71.wav; $LGPL/ffprobe -v error -show_entries stream=codec_name,channels,channel_layout,sample_rate,bits_per_sample -of compact src71.wav
ref=$($LGPL/ffmpeg -v error -i src71.wav -f s32le -map_metadata -1 - | md5sum | cut -c1-12); echo "reference decoded md5 (s32le): $ref"
mk() { # name, codec args...
  local n=$1; shift
  echo "--- $n: $*"
  $FF -i src71.wav "$@" -movflags $FM "$n.mp4" 2>&1 | sed 's/0x[0-9a-f]*//g' | sort | uniq -c | head -4
  [ -s "$n.mp4" ] || { echo "    NOT WRITTEN"; return; }
  echo "    size $(stat -c %s $n.mp4) bytes"
  $PY "$SPIKE_DIR/boxes.py" "$n.mp4" | grep -a "sample entry\|pcmC\|chnl\|dfLa\|alac\|esds" | sed 's/^/    /'
  $LGPL/ffprobe -v error -show_entries stream=codec_name,codec_tag_string,channels,channel_layout,sample_fmt,bits_per_raw_sample -of compact "$n.mp4" | sed 's/^/    ffprobe: /'
  local m=$($LGPL/ffmpeg -v error -i "$n.mp4" -f s32le -map_metadata -1 - 2>/dev/null | md5sum | cut -c1-12)
  [ "$m" = "$ref" ] && echo "    decode-back md5 $m == reference (bit-exact)" || echo "    decode-back md5 $m != reference $ref (flac/alac may use 24-bit shift: see note)"
}
mk flac71     -c:a flac -sample_fmt s32 -strict -2
mk alac71     -c:a alac -sample_fmt s32p
mk pcm24_71   -c:a pcm_s24le
mk pcm16_71   -c:a pcm_s16le
mk pcm32_71   -c:a pcm_s32le
mk pcmf32_71  -c:a pcm_f32le
mk pcm24be_71 -c:a pcm_s24be
echo "== 5.1 and stereo sanity for FLAC/ALAC (channel order)"
$FF -f lavfi -i "sine=f=440:d=2,aformat=channel_layouts=5.1" -c:a flac -movflags $FM flac51.mp4 2>&1 | head -2; $PY "$SPIKE_DIR/boxes.py" flac51.mp4 | grep -a "sample entry\|dfLa\|chnl"
echo "== HLS fMP4 with each codec"
for c in flac alac pcm_s24le; do
  mkdir -p hls_$c; $FF -i src71.wav -c:a $c $( [ $c = alac ] && echo -sample_fmt s32p ) $( [ $c = flac ] && echo "-sample_fmt s32 -strict -2" ) -f hls -hls_segment_type fmp4 -hls_time 2 -hls_playlist_type vod \
    -hls_fmp4_init_filename init.mp4 -hls_segment_filename "hls_$c/s_%02d.m4s" hls_$c/a.m3u8 2>&1 | sed 's/0x[0-9a-f]*//g' | sort | uniq -c | head -3
  echo "  [$c] files: $(ls hls_$c | tr '\n' ' ')"; [ -s hls_$c/init.mp4 ] && $PY "$SPIKE_DIR/boxes.py" hls_$c/init.mp4 | grep -a "sample entry" | sed 's/^/    /'
done
echo "== bytes per second of 7.1 24-bit/48 kHz (6 s test tone, so only an order-of-magnitude, tone compresses far better than film audio)"
for n in flac71 alac71 pcm24_71 pcm16_71; do echo "$n $(( $(stat -c %s $n.mp4) / 6 )) B/s"; done
