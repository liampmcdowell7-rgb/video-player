#!/usr/bin/env python3
"""Writes a tiny Presentation Graphic Stream (.sup, PGS) with two captions, for the RemuxEngine tests.

PGS segments: 'PG' + PTS(4, 90 kHz) + DTS(4) + type(1) + size(2) + payload.
Types: 0x16 PCS, 0x17 WDS, 0x14 PDS, 0x15 ODS, 0x80 END.
Each caption is a solid 300x60 box (run-length coded) shown for two seconds; a second display set clears it.
Usage: remux-make-sup.py out.sup
"""
import struct
import sys


def seg(pts_s, kind, payload):
    pts = int(pts_s * 90000)
    return b"PG" + struct.pack(">IIBH", pts, 0, kind, len(payload)) + payload


def display_set(t, number, x, y, w, h, color, show=True):
    out = b""
    objects = 1 if show else 0
    pcs = struct.pack(">HHBHBBBB", 1280, 720, 0x10, number, 0x80, 0, 0, objects)
    if show:
        pcs += struct.pack(">HBBHH", 1, 0, 0, x, y)
    out += seg(t, 0x16, pcs)
    out += seg(t, 0x17, struct.pack(">BBHHHH", 1, 0, x, y, w, h))
    if show:
        out += seg(t, 0x14, struct.pack(">BB", 0, 0) + struct.pack(">BBBBB", color, 100, 128, 128, 255))
        # Run-length coded object: every line is one run of `color`, then end-of-line.
        line = bytes([0x00, 0xC0 | (w >> 8), w & 0xFF, color]) + bytes([0x00, 0x00])
        rle = line * h
        out += seg(t, 0x15, struct.pack(">HBB", 1, 0, 0xC0) + struct.pack(">I", len(rle) + 4)[1:] + struct.pack(">HH", w, h) + rle)
    out += seg(t, 0x80, b"")
    return out


data = b""
data += display_set(1.0, 1, 100, 600, 300, 60, 1)
data += display_set(3.0, 2, 100, 600, 300, 60, 0, show=False)
data += display_set(5.0, 3, 100, 600, 300, 60, 2)
data += display_set(7.0, 4, 100, 600, 300, 60, 0, show=False)
with open(sys.argv[1], "wb") as f:
    f.write(data)
print("wrote", sys.argv[1], len(data), "bytes")
