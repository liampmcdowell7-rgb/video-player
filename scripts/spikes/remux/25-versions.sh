#!/usr/bin/env bash
# Remux spike, step 2b: run the same matrix with the three LGPL versions and diff the box summaries against master.
set -u
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$D/env.sh"
for v in 9.0 8.1; do bash "$D/20-remux.sh" $v >"$T/run-$v.txt" 2>&1; done
bash "$D/20-remux.sh" master >"$T/run-master.txt" 2>&1
norm() { grep -a -v "^################\|bytes$\|^=== \|^--- " "$1" | sed 's#/home/[^ ]*/out/[^/]*/##g;s/0x[0-9a-f]*//g'; }
for v in 9.0 8.1; do
  echo "== diff master vs $v (box summaries and warnings; file sizes and paths removed)"
  diff <(norm "$T/run-master.txt") <(norm "$T/run-$v.txt") && echo "IDENTICAL"
done
echo "== encoder tags written (ffmpeg writes its version into udta/meta unless -fflags +bitexact)"
for v in master 9.0 8.1; do strings -a "$T/out/$v/C_hdr10_video.mp4" | grep -a -m1 "Lavf" | sed "s/^/$v: /"; done
