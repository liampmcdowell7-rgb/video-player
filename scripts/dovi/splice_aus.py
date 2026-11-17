#!/usr/bin/env python3
"""FIXTURE helper for scripts/test-dovi.sh: builds the "profile switches mid-stream" HEVC elementary stream.

Usage: splice_aus.py FIRST.hevc SECOND.hevc SPLIT OUT.hevc
Takes access units 0..SPLIT-1 (decode order) from FIRST and SPLIT.. from SECOND. Access units are split at the
base-layer access unit delimiter (NAL type 35, nuh_layer_id 0); both inputs must be made from the same base-layer
encode with AUDs on (x265 aud=1), so the base layer stays one valid bitstream and SPLIT must be a keyframe.
"""
import sys


def nals(data):
    """(start_code_offset, nal_start, nal_end) for every Annex-B NAL unit."""
    out, i, n = [], 0, len(data)
    starts = []
    while i < n - 3:
        if data[i] == 0 and data[i + 1] == 0 and data[i + 2] == 1:
            sc = i - 1 if i > 0 and data[i - 1] == 0 else i
            starts.append((sc, i + 3))
            i += 3
        else:
            i += 1
    for k, (sc, s) in enumerate(starts):
        e = starts[k + 1][0] if k + 1 < len(starts) else n
        out.append((sc, s, e))
    return out


def access_units(data):
    aus, cur = [], None
    for sc, s, e in nals(data):
        t = (data[s] >> 1) & 0x3F
        layer = ((data[s] & 1) << 5) | (data[s + 1] >> 3)
        if t == 35 and layer == 0:
            if cur is not None:
                aus.append(cur)
            cur = [sc, e]
        elif cur is None:
            cur = [sc, e]
        else:
            cur[1] = e
    if cur is not None:
        aus.append(cur)
    return [data[a:b] for a, b in aus]


def main():
    first, second, split, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    a = access_units(open(first, 'rb').read())
    b = access_units(open(second, 'rb').read())
    if len(a) != len(b):
        sys.exit(f"access unit counts differ: {len(a)} vs {len(b)}")
    with open(out, 'wb') as f:
        for au in a[:split] + b[split:]:
            f.write(au)
    print(f"{out}: {split} access units from {first}, {len(b) - split} from {second}")


if __name__ == '__main__':
    main()
