#!/usr/bin/env bash
# Remux spike, step 0: download the tools into ~/vp-remux-spike/tools (user space, no sudo).
# Everything here is a TEST TOOL. Nothing in this folder ships in the app.
#   lgpl*   FFmpeg LGPL builds (BtbN/FFmpeg-Builds, official-build helper project linked from ffmpeg.org):
#           the build we would actually remux with. Three versions are kept to see version differences.
#   gpl     FFmpeg GPL build: used ONLY to ENCODE test video with libx265 (the LGPL build has no x265).
#   dovi    dovi_tool 2.3.4 (MIT, quietvoid/dovi_tool): makes Dolby Vision RPU data for test streams.
#   mkv     mkvmerge 97.0 (GPL-2, MKVToolNix from the Ubuntu archive, unpacked with dpkg -x, no install):
#           writes MKV files the way rippers do (Colour element, Dolby Vision BlockAdditionMapping).
# Usage: bash scripts/spikes/remux/00-setup.sh   (about 600 MB of downloads, once)
set -eu
T="${VP_REMUX_HOME:-$HOME/vp-remux-spike}"
mkdir -p "$T/tools" "$T/debs"; cd "$T/tools"
B=https://github.com/BtbN/FFmpeg-Builds/releases/download/latest
get() { # url file
  [ -s "$2" ] || curl -sL -o "$2" "$1"
  echo "$2  $(stat -c %s "$2") bytes  sha256 $(sha256sum "$2" | cut -d' ' -f1)"
}
unpack() { # archive dir
  [ -x "$2/bin/ffmpeg" ] || { mkdir -p "$2"; tar -xf "$1" -C "$2" --strip-components=1; }
}
get $B/ffmpeg-master-latest-linux64-lgpl.tar.xz lgpl.tar.xz;               unpack lgpl.tar.xz lgpl        # master snapshot (becomes 9.1)
get $B/ffmpeg-n9.0-latest-linux64-lgpl-9.0.tar.xz lgpl9.0.tar.xz;          unpack lgpl9.0.tar.xz lgpl9.0
get $B/ffmpeg-n8.1-latest-linux64-lgpl-8.1.tar.xz lgpl8.1.tar.xz;          unpack lgpl8.1.tar.xz lgpl8.1
get $B/ffmpeg-master-latest-linux64-gpl.tar.xz gpl.tar.xz;                 unpack gpl.tar.xz gpl          # test-input encoder only
get https://github.com/quietvoid/dovi_tool/releases/download/2.3.4/dovi_tool-2.3.4-x86_64-unknown-linux-musl.tar.gz dovi.tar.gz
[ -x dovi/dovi_tool ] || { mkdir -p dovi; tar -xzf dovi.tar.gz -C dovi; }
# mkvmerge: the package plus the shared libraries it needs, unpacked (not installed). ICU comes from
# ~/video-player-test-servers/icu (see scripts/test-mediaservers.sh setup jellyfin) or is fetched here.
cd "$T/debs"
for p in mkvtoolnix libmatroska7 libebml5 libboost-filesystem1.90.0 libflac14 libpugixml1v5 libfmt10 libqt6core6t64 \
         libdvdread8t64 libvorbis0a libogg0 libdouble-conversion3 libpcre2-16-0 libb2-1 libmd4c0; do
  ls ${p}_*.deb >/dev/null 2>&1 || apt-get download "$p" >/dev/null 2>&1 || echo "could not download $p"
done
mkdir -p x; for d in *.deb; do dpkg -x "$d" x; done
if [ ! -d "$HOME/video-player-test-servers/icu/usr/lib/x86_64-linux-gnu" ]; then
  apt-get download "$(apt-cache search --names-only '^libicu[0-9]+$' | awk '{print $1}' | head -1)" >/dev/null 2>&1
  mkdir -p "$T/icu"; dpkg -x libicu*.deb "$T/icu"
fi
echo "== versions"
"$T/tools/lgpl/bin/ffmpeg" -version | head -1
"$T/tools/lgpl9.0/bin/ffmpeg" -version | head -1
"$T/tools/lgpl8.1/bin/ffmpeg" -version | head -1
"$T/tools/gpl/bin/ffmpeg" -version | head -1
"$T/tools/dovi/dovi_tool" --version
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
mkvmerge --version | head -1
echo "== LGPL proof (build configuration of the LGPL build: no --enable-gpl, no --enable-nonfree, no x264/x265)"
"$T/tools/lgpl/bin/ffmpeg" -hide_banner -L 2>&1 | sed -n 1,3p
"$T/tools/lgpl/bin/ffmpeg" -hide_banner -buildconf 2>&1 | grep -E "enable-(gpl|nonfree|version3|libx26)|disable-(libx26)" | tr -s ' ' | head
