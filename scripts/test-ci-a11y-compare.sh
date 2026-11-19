#!/usr/bin/env bash
# Self-test of scripts/ci-a11y-compare.py on small generated PNGs (no simulator, no network). Runs in WSL/Linux, where
# there is no `sips`, so the script's own PNG reader is used. Prints "a11y-compare tests: passed N, failed M".
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0

# make.py OUT KIND: a 32x108 RGBA picture (band = rows 5..10 at this height). KIND: base, tabbar (differs only inside
# the band), body (differs below the band), small (another size). Rows use PNG filters 0 to 4 in turn.
cat >"$work/make.py" <<'EOF'
import struct, sys, zlib
out, kind = sys.argv[1], sys.argv[2]
w, h = (32, 108) if kind != "small" else (16, 54)
def pixel(x, y):
    v = (x * 7 + y * 3) & 255
    if kind == "tabbar" and 5 <= y <= 10: v ^= 0x55
    if kind == "body" and y == 60: v ^= 0x55
    return bytes([v, 255 - v, (v * 3) & 255, 255])
def filt(t, line, prev):
    out = bytearray()
    for i, b in enumerate(line):
        a = line[i - 4] if i >= 4 else 0
        up = prev[i]
        c = prev[i - 4] if i >= 4 else 0
        if t == 0: p = 0
        elif t == 1: p = a
        elif t == 2: p = up
        elif t == 3: p = (a + up) >> 1
        else:
            q = a + up - c; pa, pb, pc = abs(q - a), abs(q - up), abs(q - c)
            p = a if pa <= pb and pa <= pc else up if pb <= pc else c
        out.append((b - p) & 255)
    return bytes(out)
raw, prev = b"", bytes(w * 4)
for y in range(h):
    line = b"".join(pixel(x, y) for x in range(w))
    t = y % 5
    raw += bytes([t]) + filt(t, line, prev)
    prev = line
def chunk(k, d): return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
open(out, "wb").write(png)
EOF

# case NAME EXPECTED_EXIT EXPECTED_TEXT FILE:KIND...
case_() {
  local name="$1" want="$2" text="$3"; shift 3
  local dir="$work/$name"; mkdir -p "$dir"
  for spec in "$@"; do python3 "$work/make.py" "$dir/${spec%%:*}" "${spec##*:}"; done
  local got out
  out="$(python3 "$here/ci-a11y-compare.py" "$dir" 2>&1)"; got=$?
  if [ "$got" = "$want" ] && printf '%s' "$out" | grep -qF -- "$text"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "FAIL $name (exit $got, wanted $want and \"$text\"):"; printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

case_ differs 0 "A11Y COMPARE OK (2 compared)" 102-default-home.png:base 80-larger-text-home.png:body 85-bold-text-home.png:body
case_ same-only-tabbar 1 "SAME OUTSIDE TAB BAR: 85-bold-text-home.png" 102-default-home.png:base 85-bold-text-home.png:tabbar 80-larger-text-home.png:body
case_ identical 1 "A11Y COMPARE PROBLEM: 96-bold-text-search.png is the same" 112-default-search.png:base 96-bold-text-search.png:base
case_ other-size 0 "DIFFERS: 90-larger-text-show-page.png" 108-default-show-page.png:base 90-larger-text-show-page.png:small
case_ no-default 1 "NOT COMPARED: 85-bold-text-home.png" 85-bold-text-home.png:body
case_ nothing 1 "nothing was compared" 102-default-home.png:base
case_ three-digit 0 "DIFFERS: 101-bold-text-search.png and 112-default-search.png" 112-default-search.png:base 101-bold-text-search.png:body
case_ mixed 1 "A11Y COMPARE PROBLEM: 86-bold-text-movies.png" 102-default-home.png:base 103-default-movies.png:base 85-bold-text-home.png:body 86-bold-text-movies.png:tabbar
out="$(python3 "$here/ci-a11y-compare.py" "$work/none" 2>&1)"; got=$?
if [ "$got" = 1 ] && printf '%s' "$out" | grep -qF "no folder"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL missing folder: $out"; fi

echo "a11y-compare tests: passed $pass, failed $fail"
[ "$fail" -eq 0 ]
