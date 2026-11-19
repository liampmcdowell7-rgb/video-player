#!/usr/bin/env python3
"""CI only (compile-check.yml, job "accessibility-screenshots"); #17 A.

Compares every Larger Text and Bold Text screenshot with the default screenshot of the same screen, OUTSIDE the tab bar,
and fails when they are the same there: then the override did not reach the app's own text (the reviewed CI run had Bold
Text screenshots that differed from the normal ones only in the tab bar).

  python3 scripts/ci-a11y-compare.py DIR

DIR holds NN-larger-text-KEY.png, NN-bold-text-KEY.png and NN-default-KEY.png (ScreenshotTests test06 and test11; NN has
two or three digits). The tab bar band is rows 51 to 109 of a 1080-row screenshot (the band named in #17 A), scaled to
the picture's real height.

Prints one line per comparison ("DIFFERS", "SAME OUTSIDE TAB BAR", or "NOT COMPARED" with the reason) and ends with
"A11Y COMPARE OK (N compared)" or "A11Y COMPARE PROBLEM: ..." (exit 1). Nothing compared at all is a problem too.

Pictures are read with macOS `sips` (converted to BMP) when it exists, else with the small PNG reader below (used by the
self-test on Linux: scripts/test-ci-a11y-compare.sh). No third-party modules.
"""
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

NAME = re.compile(r"^(\d{2,3})-(larger-text|bold-text|default)-([a-z0-9-]+)\.png$")
BAND_TOP, BAND_BOTTOM, BAND_HEIGHT = 51, 109, 1080


def read_png(path):
    """(width, height, rows) with rows a list of bytes, one per pixel row. 8-bit, non-interlaced PNGs only."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, width = 8, [], None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or interlace != 0:
                raise ValueError("only 8-bit non-interlaced PNGs are read here")
            channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(colour)
            if channels is None:
                raise ValueError("palette PNGs are not read here")
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        pos += 12 + length
    if width is None:
        raise ValueError("no IHDR")
    raw = zlib.decompress(b"".join(idat))
    bpp, stride = channels, width * channels
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 255
        elif kind == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = previous[i]
                c = previous[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        elif kind != 0:
            raise ValueError("unknown PNG filter %d" % kind)
        rows.append(bytes(line))
        previous = line
    return width, height, rows


def read_bmp(path):
    """(width, height, rows) of an uncompressed BMP (as `sips -s format bmp` writes), rows top first."""
    with open(path, "rb") as fh:
        data = fh.read()
    offset = struct.unpack("<I", data[10:14])[0]
    width, height = struct.unpack("<ii", data[18:26])
    bits = struct.unpack("<H", data[28:30])[0]
    stride = ((bits * width + 31) // 32) * 4
    used = width * bits // 8
    rows = [data[offset + y * stride:offset + y * stride + used] for y in range(abs(height))]
    if height > 0:
        rows.reverse()
    return width, abs(height), rows


def read_picture(path, tmp):
    if shutil.which("sips"):
        out = os.path.join(tmp, os.path.basename(path) + ".bmp")
        subprocess.run(["sips", "-s", "format", "bmp", path, "--out", out], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return read_bmp(out)
    return read_png(path)


def band(height):
    """The rows of the tab bar band for a picture `height` rows high (half-open range)."""
    scale = height / BAND_HEIGHT
    return int(BAND_TOP * scale), int(-(-(BAND_BOTTOM + 1) * scale // 1))


def same_outside_band(a, b):
    (wa, ha, ra), (wb, hb, rb) = a, b
    if (wa, ha) != (wb, hb):
        return False
    top, bottom = band(ha)
    return all(ra[y] == rb[y] for y in range(ha) if not top <= y < bottom)


def main():
    if len(sys.argv) != 2:
        print("usage: ci-a11y-compare.py DIR", file=sys.stderr)
        return 2
    folder = sys.argv[1]
    if not os.path.isdir(folder):
        print("A11Y COMPARE PROBLEM: no folder %s" % folder)
        return 1
    found = {}
    for name in sorted(os.listdir(folder)):
        m = NAME.match(name)
        if m:
            found.setdefault((m.group(2), m.group(3)), name)
    problems, compared = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        cache = {}

        def picture(name):
            if name not in cache:
                cache[name] = read_picture(os.path.join(folder, name), tmp)
            return cache[name]

        for (variant, key), name in sorted(found.items(), key=lambda kv: kv[1]):
            if variant == "default":
                continue
            base = found.get(("default", key))
            if base is None:
                print("NOT COMPARED: %s (no default screenshot of %s)" % (name, key))
                continue
            try:
                same = same_outside_band(picture(name), picture(base))
            except (ValueError, OSError, subprocess.CalledProcessError) as error:
                print("NOT COMPARED: %s (could not read: %s)" % (name, error))
                continue
            compared += 1
            if same:
                print("SAME OUTSIDE TAB BAR: %s and %s" % (name, base))
                problems.append("%s is the same as %s outside the tab bar (the %s override did not reach the app)" % (name, base, variant))
            else:
                print("DIFFERS: %s and %s" % (name, base))
    if compared == 0:
        problems.append("nothing was compared (no Larger Text or Bold Text screenshot with a default screenshot of the same screen)")
    if problems:
        for p in problems:
            print("A11Y COMPARE PROBLEM: " + p)
        return 1
    print("A11Y COMPARE OK (%d compared)" % compared)
    return 0


if __name__ == "__main__":
    sys.exit(main())
