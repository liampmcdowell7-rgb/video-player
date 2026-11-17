#!/usr/bin/env bash
# Audio pipeline tests on Linux (WSL): the AudioDecode target (DTS, DTS-HD, TrueHD, Opus, Vorbis decoded and repackaged
# as FLAC for fragmented MP4) against a locally built LGPL copy of the same codec library the app ships.
#
#   bash scripts/test-audio.sh            build the library if missing, make the test media if missing, run the tests
#   bash scripts/test-audio.sh build      only build the library
#   bash scripts/test-audio.sh media      only make the test media
#   bash scripts/test-audio.sh test       only run the tests (library and media must exist)
#
# What it uses (tests only; nothing here ships):
#  - FFmpeg n8.1.3 source (the version inside the vendored frameworks, Frameworks/MediaCodecs/upstream-build-record/BUILD-INFO.txt),
#    https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n8.1.3.tar.gz, checked against FFMPEG_SHA256 below, plus the
#    upstream build's DTS patch (dca-xll-x-heights.patch). Configured with the same component list as the shipped build
#    (read from BUILD-INFO.txt, tvos-arm64 line) minus the platform flags (cross compile, Apple SDK, VideoToolbox,
#    AudioToolbox, Metal, NEON) and minus the three external video/teletext libraries (dav1d, zimg, zvbi), which the audio
#    path does not use. No --enable-gpl, no --enable-version3, no --enable-nonfree: LGPL-2.1-or-later. Shared libraries.
#  - The spike's LGPL FFmpeg 8.1 command-line tools (~/vp-remux-spike/tools/lgpl8.1, scripts/spikes/remux/00-setup.sh) to
#    MAKE test media and as the independent reference decoder / ffprobe.
#  - Public test samples from the FFmpeg FATE suite (https://fate-suite.ffmpeg.org/), checked against the sha256 below:
#    real DTS-HD Master Audio and TrueHD streams, which no LGPL encoder can make.
# Environment: VP_TEST_HOME (default ~/video-player-test-servers), VP_AUDIO_MEDIA (default $VP_TEST_HOME/audio-media).
# Every compile and test runs inside the shared WSL lock (flock $HOME/vp-wsl.lock), -j2 at most.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
BASE="${VP_TEST_HOME:-$HOME/video-player-test-servers}"
SRC="$BASE/ffmpeg-n8.1.3-src"; PFX="$BASE/ffmpeg-lgpl"
MEDIA="${VP_AUDIO_MEDIA:-$BASE/audio-media}"
LOCK="$HOME/vp-wsl.lock"
LOCKRUN="flock -w 7200 $LOCK"
# VP_LOCK_HELD=1: the caller already holds the lock (for example a locked run of scripts/test-all.sh).
[ "${VP_LOCK_HELD:-0}" = 1 ] && LOCKRUN=""
FFMPEG_TAG=n8.1.3
FFMPEG_URL="https://github.com/FFmpeg/FFmpeg/archive/refs/tags/$FFMPEG_TAG.tar.gz"
# Recorded on the first download (2026-11-17, 16,906,107 bytes).
FFMPEG_SHA256="${VP_FFMPEG_SHA256:-09f990289327d3ebfedf4fc15cae3f884a65dab7a5aac7bbb5b01ff83900efd9}"
RECORD="$HERE/Packages/VideoPlayerCore/Frameworks/MediaCodecs/upstream-build-record"
TOOLS="${VP_REMUX_TOOLS:-$HOME/vp-remux-spike}/tools/lgpl8.1/bin"
FF="$TOOLS/ffmpeg"; FP="$TOOLS/ffprobe"
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 1; }; }

build_ffmpeg() {
  if [ -f "$PFX/lib/libavcodec.so" ] && [ -f "$PFX/lib/pkgconfig/libavcodec.pc" ] && [ -f "$PFX/lib/pkgconfig/libswresample.pc" ]; then return 0; fi
  need curl; need make; need gcc; need python3; need sha256sum
  mkdir -p "$BASE"
  local tgz="$BASE/ffmpeg-$FFMPEG_TAG.tar.gz"
  [ -f "$tgz" ] || curl -fsSL -o "$tgz" "$FFMPEG_URL"
  local got; got="$(sha256sum "$tgz" | cut -c1-64)"
  echo "FFmpeg $FFMPEG_TAG tarball: $(stat -c %s "$tgz") bytes, sha256 $got"
  if [ -n "$FFMPEG_SHA256" ] && [ "$got" != "$FFMPEG_SHA256" ]; then echo "sha256 mismatch (expected $FFMPEG_SHA256)" >&2; exit 1; fi
  rm -rf "$SRC"; mkdir -p "$SRC"; tar -xzf "$tgz" -C "$SRC" --strip-components=1
  ( cd "$SRC" && patch -p1 --forward < "$RECORD/patches/dca-xll-x-heights.patch" )
  # The component list of the shipped tvOS build, without the platform flags.
  local flags
  flags="$(python3 -I - "$RECORD/BUILD-INFO.txt" <<'PY'
import shlex, sys
text = open(sys.argv[1]).read().splitlines()
line = next(l for l in text if l.startswith('tvos-arm64:'))
tokens = shlex.split(line.split(':', 1)[1])
drop_prefix = ('--prefix', '--target-os', '--arch', '--cc', '--extra-cflags', '--extra-ldflags', '--metalcc', '--metallib',
               '--sysroot', '--as', '--nm', '--ar', '--ranlib', '--strip')
drop_exact = {'--enable-cross-compile', '--enable-metal', '--enable-neon', '--enable-videotoolbox', '--enable-audiotoolbox',
              '--enable-libdav1d', '--enable-libzimg', '--enable-libzvbi', '--enable-decoder=libdav1d',
              '--enable-decoder=libzvbi_teletext', '--disable-stripping'}
out = []
for t in tokens:
    if not t.startswith('--'): continue
    if t.startswith(drop_prefix) or t in drop_exact: continue
    out.append(t)
for bad in ('--enable-gpl', '--enable-version3', '--enable-nonfree'):
    assert bad not in out, bad
print(' '.join(out))
PY
)"
  local asm=""
  command -v nasm >/dev/null 2>&1 || asm="--disable-x86asm"
  echo "configure: $flags $asm"
  ( cd "$SRC" && $LOCKRUN ./configure --prefix="$PFX" $flags $asm >"$BASE/ffmpeg-configure.log" 2>&1 ) || { tail -30 "$BASE/ffmpeg-configure.log"; exit 1; }
  ( cd "$SRC" && $LOCKRUN make -j2 >"$BASE/ffmpeg-make.log" 2>&1 && make install >"$BASE/ffmpeg-install.log" 2>&1 ) || { tail -30 "$BASE/ffmpeg-make.log"; exit 1; }
  grep -q "License: LGPL version 2.1 or later" "$BASE/ffmpeg-configure.log" || { echo "configure did not report LGPL 2.1 or later" >&2; exit 1; }
  echo "built: $PFX ($(grep '^License' "$BASE/ffmpeg-configure.log"))"
}

# FATE samples: name|url path|sha256
FATE="https://fate-suite.ffmpeg.org"
SAMPLES="
master_audio_7.1_24bit.dts|dts/master_audio_7.1_24bit.dts|227f1008f9529b2bdf937ce856d2562d0128162ac930e2579ef4b8fd7474ee18
xll_71_24_96_768.dtshd|dts/dcadec-suite/xll_71_24_96_768.dtshd|d2911b34183f7379359cf914ee93228796894e0b0f0055e6ee5baefa4fd6a923
xll_51_16_192_768_0.dtshd|dts/dcadec-suite/xll_51_16_192_768_0.dtshd|34441a4f2df89e086f67a7b0f72aa871e1cbb3b04b301470a7727038bb91b618
xll_51_24_48_none.dtshd|dts/dcadec-suite/xll_51_24_48_none.dtshd|c445bb746c6afc920761b55b00932053d64a96d3d08cd9cad4c759a892fae4cd
core_51_24_48_768_0.dtshd|dts/dcadec-suite/core_51_24_48_768_0.dtshd|95653e7d94307a9d467c28ae10883440dcc39f06ac79d7401b27eb422cd99009
dts_es.dts|dts/dts_es.dts|2e2530d220d51b914d1e7acb63badb5b2dae1578f3274116206fa1aa5e597638
truehd_5.1.raw|lossless-audio/truehd_5.1.raw|f00a67adeec561c8bb9e98da06e38f5d3f204778ff931c592f81db54ce428127
atmos.thd|truehd/atmos.thd|020c9b9e67f80de105663af191740f8b60f550107c9f765b632f4cd5efb1c6ab
"

make_media() {
  [ -x "$FF" ] && [ -x "$FP" ] || { echo "Missing the spike's LGPL tools in $TOOLS (run scripts/spikes/remux/00-setup.sh)" >&2; exit 1; }
  mkdir -p "$MEDIA/fate"
  local manifest="$MEDIA/fate/SHA256SUMS"
  : > "$manifest.new"
  echo "$SAMPLES" | while IFS='|' read -r name path sum; do
    [ -n "$name" ] || continue
    [ -f "$MEDIA/fate/$name" ] || curl -fsSL -o "$MEDIA/fate/$name" "$FATE/$path"
    local got; got="$(sha256sum "$MEDIA/fate/$name" | cut -c1-64)"
    if [ -n "$sum" ] && [ "$got" != "$sum" ]; then echo "sha256 mismatch for $name" >&2; exit 1; fi
    echo "$got  $name  $(stat -c %s "$MEDIA/fate/$name")  $FATE/$path" >> "$manifest.new"
  done
  mv "$manifest.new" "$manifest"
  cat "$manifest"
  python3 -I "$HERE/scripts/audio-make-media.py" "$FF" "$FP" "$MEDIA"
}

run_tests() {
  [ -f "$PFX/lib/pkgconfig/libavcodec.pc" ] || { echo "library not built: bash scripts/test-audio.sh build" >&2; exit 1; }
  local W="${VP_BUILD_DIR:-$HOME/vp-build-audio}"
  mkdir -p "$W"
  rsync -a --delete --exclude .build --exclude Vendor --exclude Frameworks "$HERE/Packages/VideoPlayerCore/" "$W/"
  cd "$W"
  # This stage runs AudioDecodeTests only. On Linux every test target is linked into one test binary, so a compile error in
  # another work stream's tests would stop this stage: in this private copy the other test targets keep one empty file each
  # (the unit stage runs them for real).
  for d in Tests/*/; do
    [ "$(basename "$d")" = "AudioDecodeTests" ] && continue
    rm -rf "$d"; mkdir -p "$d"; echo "// placeholder: this target runs in the unit stage" > "$d/Placeholder.swift"
  done
  export PKG_CONFIG_PATH="$PFX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  export LD_LIBRARY_PATH="$PFX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export VP_MEDIACODECS="$PFX" VP_AUDIO_MEDIA="$MEDIA" VP_AUDIO_TOOLS="$TOOLS"
  $LOCKRUN swift test --filter "AudioDecodeTests" 2>&1
}

case "${1:-all}" in
  build) build_ffmpeg ;;
  media) make_media ;;
  test) run_tests ;;
  all) build_ffmpeg; [ -f "$MEDIA/READY" ] || make_media; run_tests ;;
  *) echo "usage: $0 [build|media|test]" >&2; exit 2 ;;
esac
