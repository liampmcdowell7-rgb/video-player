#!/usr/bin/env bash
# Dolby Vision profile 7 -> 8.1 tests (WSL / Linux). See docs/DOLBY_VISION.md.
#
#   bash scripts/test-dovi.sh            setup (only what is missing) + tests
#   bash scripts/test-dovi.sh setup      build / fetch tools and generate the test streams only
#   bash scripts/test-dovi.sh test       run the tests only (setup must have run)
#
# Setup, each step skipped when its output already exists:
#  1. libdovi 3.3.2 (the version of the vendored tvOS library) from the official repository tag `libdovi-3.3.2`,
#     built as a static C library (`cargo rustc --features capi --crate-type staticlib`, panic=abort, -j2), with the
#     header from the vendored xcframework (same version) and a pkg-config file `vp-dovi.pc`.
#  2. The reference CLI dovi_tool 2.3.4 (release binary, sha256 checked).
#  3. FIXTURE streams (synthetic, never real content): a base layer and an enhancement layer encoded with x265 by the
#     GPL ffmpeg of the remux spike (test input only, never shipped), synthetic profile 7 FEL / MEL and 8.1 RPUs from
#     scripts/dovi/fixturegen, then dovi_tool inject-rpu + mux into single-track dual-layer profile 7 streams, a
#     "profile switches mid-stream" stream, MKVs by mkvmerge, and the reference conversions by `dovi_tool -m 2 convert --discard`.
# Every compile and test runs inside the shared WSL lock (flock $HOME/vp-wsl.lock). Never starts a server.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
export PATH="$HOME/.cargo/bin:$PATH"
LOCK="flock -w 7200 $HOME/vp-wsl.lock"
# VP_LOCK_HELD=1: the caller already holds the lock (for example a locked run of scripts/test-all.sh); taking it again
# here would wait on ourselves until the timeout.
[ "${VP_LOCK_HELD:-0}" = 1 ] && LOCK=""
DH="${VP_DOVI_HOME:-$HOME/vp-dovi}"
LIBV=3.3.2
SRC="$DH/libdovi-$LIBV-src"
PREFIX="$DH/libdovi-$LIBV"
MEDIA="${VP_DOVI_MEDIA:-$DH/media}"
DOVI_TOOL="$DH/dovi_tool"
DOVI_TOOL_URL="https://github.com/quietvoid/dovi_tool/releases/download/2.3.4/dovi_tool-2.3.4-x86_64-unknown-linux-musl.tar.gz"
DOVI_TOOL_SHA=1844258e13c26607b32224bf1fa82b595d3b35949f5467405fda560daad32b3f
SPIKE="${VP_REMUX_HOME:-$HOME/vp-remux-spike}"
GPLF="$SPIKE/tools/gpl/bin/ffmpeg"          # ONLY to encode the synthetic test video
export LD_LIBRARY_PATH="$SPIKE/debs/x/usr/lib/x86_64-linux-gnu:$HOME/video-player-test-servers/icu/usr/lib/x86_64-linux-gnu:$SPIKE/icu/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export PATH="$SPIKE/debs/x/usr/bin:$PATH"   # mkvmerge
HEADER="$HERE/Packages/VideoPlayerCore/Frameworks/DolbyVisionRPULib.xcframework/tvos-arm64_arm64e/Headers/rpu_parser.h"
N=96          # frames per fixture (4 s at 24 fps)
fail() { echo "FAIL: $*"; exit 1; }

build_lib() {
  [ -f "$PREFIX/lib/libdolby_vision.a" ] && [ -f "$PREFIX/lib/pkgconfig/vp-dovi.pc" ] && { echo "libdovi $LIBV: present ($PREFIX)"; return 0; }
  command -v cargo >/dev/null || fail "cargo missing (expected in ~/.cargo/bin)"
  if [ ! -d "$SRC/.git" ]; then
    git clone -q --depth 1 --branch "libdovi-$LIBV" https://github.com/quietvoid/dovi_tool.git "$SRC" || fail "clone of libdovi-$LIBV failed"
  fi
  grep -q "^version = \"$LIBV\"" "$SRC/dolby_vision/Cargo.toml" || fail "source at $SRC is not dolby_vision $LIBV"
  ( cd "$SRC/dolby_vision" && CARGO_PROFILE_RELEASE_PANIC=abort $LOCK cargo rustc -q --release -j 2 --features capi --crate-type staticlib ) || fail "libdovi build failed"
  mkdir -p "$PREFIX/lib/pkgconfig" "$PREFIX/include"
  cp "$SRC/dolby_vision/target/release/libdolby_vision.a" "$PREFIX/lib/"
  cp "$HEADER" "$PREFIX/include/rpu_parser.h"
  grep -q "RPU_PARSER_PATCH 2" "$PREFIX/include/rpu_parser.h" || fail "vendored header is not version $LIBV"
  cat > "$PREFIX/lib/pkgconfig/vp-dovi.pc" <<EOF
prefix=$PREFIX
Name: vp-dovi
Description: libdovi $LIBV C API (tests only)
Version: $LIBV
Cflags: -I\${prefix}/include
Libs: -L\${prefix}/lib -ldolby_vision -lpthread -ldl -lm
EOF
  ( cd "$SRC" && git rev-parse HEAD ) > "$PREFIX/source.commit"
  sha256sum "$PREFIX/lib/libdolby_vision.a" | tee "$PREFIX/libdolby_vision.a.sha256"
}

fetch_dovi_tool() {
  if [ -x "$DOVI_TOOL" ] && "$DOVI_TOOL" --version 2>/dev/null | grep -q "2.3.4"; then echo "dovi_tool: $("$DOVI_TOOL" --version)"; return 0; fi
  mkdir -p "$DH/dl"
  curl -fsSL -o "$DH/dl/dovi_tool.tgz" "$DOVI_TOOL_URL" || fail "download of dovi_tool failed"
  echo "$DOVI_TOOL_SHA  $DH/dl/dovi_tool.tgz" | sha256sum -c - || fail "dovi_tool checksum mismatch"
  tar -xzf "$DH/dl/dovi_tool.tgz" -C "$DH" dovi_tool && chmod +x "$DOVI_TOOL"
}

make_media() {
  if [ -f "$MEDIA/done.$N" ]; then echo "fixtures: present ($MEDIA)"; return 0; fi
  [ -x "$GPLF" ] || fail "$GPLF missing: run scripts/spikes/remux/00-setup.sh (it provides the test encoder and mkvmerge)"
  command -v mkvmerge >/dev/null || fail "mkvmerge missing: run scripts/spikes/remux/00-setup.sh"
  mkdir -p "$MEDIA" && cd "$MEDIA" || fail "cannot use $MEDIA"
  # RPU generator (FIXTURE), built against the same libdovi source.
  local G="$DH/fixturegen"; mkdir -p "$G/src"
  cp "$HERE/scripts/dovi/fixturegen/main.rs" "$G/src/main.rs"
  cat > "$G/Cargo.toml" <<EOF
[package]
name = "fixturegen"
version = "0.1.0"
edition = "2021"
publish = false
[dependencies]
dolby_vision = { path = "$SRC/dolby_vision", features = ["serde"] }
serde_json = "1"
anyhow = "1"
EOF
  ( cd "$G" && $LOCK cargo build -q --release -j 2 ) || fail "fixture generator build failed"
  "$G/target/release/fixturegen" "$N" "$MEDIA" || fail "RPU generation failed"
  # Base layer (HDR10, 1280x720) and enhancement layer (a quarter of the area, 640x360), same GOP structure, AUDs on.
  local X="repeat-headers=1:keyint=24:min-keyint=24:scenecut=0:bframes=3:open-gop=0:aud=1:log-level=error"
  local MD='G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)'
  $LOCK "$GPLF" -v error -y -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=4,format=yuv420p10le" -frames:v $N -c:v libx265 -preset veryfast -crf 28 \
    -x265-params "$X:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=$MD:max-cll=1000,400" -f hevc bl.hevc || fail "BL encode"
  $LOCK "$GPLF" -v error -y -f lavfi -i "mandelbrot=size=640x360:rate=24,format=yuv420p10le" -frames:v $N -c:v libx265 -preset veryfast -crf 30 \
    -x265-params "$X" -f hevc el.hevc || fail "EL encode"
  for kind in fel mel; do
    "$DOVI_TOOL" inject-rpu -i el.hevc --rpu-in rpu_p7_$kind.bin -o el_$kind.hevc >/dev/null || fail "inject $kind"
    "$DOVI_TOOL" mux --bl bl.hevc --el el_$kind.hevc -o p7_$kind.hevc >/dev/null || fail "mux $kind"
  done
  "$DOVI_TOOL" inject-rpu -i bl.hevc --rpu-in rpu_p81.bin -o p81.hevc >/dev/null || fail "inject 8.1"
  python3 -I "$HERE/scripts/dovi/splice_aus.py" p7_fel.hevc p81.hevc $((N / 2)) p7_switch.hevc || fail "splice"
  local P3="--colour-matrix 0:9 --colour-range 0:1 --colour-primaries 0:9 --colour-transfer-characteristics 0:16"
  for s in p7_fel p7_mel p7_switch p81; do
    mkvmerge -q -o $s.mkv --default-duration 0:24fps $P3 $s.hevc || fail "mkvmerge $s"
    "$DOVI_TOOL" -m 2 convert --discard $s.hevc -o ref81_$s.hevc >/dev/null || fail "reference conversion $s"
  done
  sha256sum *.bin *.hevc *.mkv > SHA256SUMS
  touch "done.$N"
}

run_tests() {
  local W="$HOME/vp-build-dovi"; mkdir -p "$W"
  rsync -a --delete --exclude .build "$HERE/Packages/VideoPlayerCore/" "$W/"
  cd "$W" || fail "no build dir"
  VP_LIBDOVI=1 PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" VP_DOVI_MEDIA="$MEDIA" VP_DOVI_TOOL="$DOVI_TOOL" \
    $LOCK swift test --filter 'DolbyVisionRPUTests|DynamicHDRPlaybackTests' 2>&1
}

case "${1:-all}" in
  setup) build_lib && fetch_dovi_tool && make_media ;;
  test) run_tests ;;
  all) build_lib && fetch_dovi_tool && make_media && run_tests ;;
  *) echo "usage: $0 [setup|test|all]"; exit 2 ;;
esac
