"""Compare the hvcC in an MP4 with the Matroska CodecPrivate of the source. Run: python3 -I cmp_hvcc.py source.mkv out.mp4
Reports equal / differing bytes (hvcC and the MKV CodecPrivate are the same structure, HEVCDecoderConfigurationRecord).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # -I ignores the script dir, so add it explicitly
import boxes  # noqa: E402
import mkvinfo  # noqa: E402


def mkv_private(path):
    with open(path, "rb") as f:
        data = f.read(4 * 1024 * 1024)
    for t in mkvinfo.summarize(mkvinfo.parse(data, 0, len(data)))["tracks"]:
        if t["type"] == "video":
            return bytes.fromhex(t["codec_private"])


def mp4_hvcc(path):
    with open(path, "rb") as f:
        data = f.read()
    for sp, sh, ss in boxes.find_all(data, 0, len(data), [b"moov"]):
        for tp, th, ts in boxes.find_all(data, sp + sh, sp + ss, [b"trak"]):
            for stp, sth, sts in boxes.find_all(data, tp + th, tp + ts, [b"mdia", b"minf", b"stbl", b"stsd"]):
                for typ, p, h, s, _ in boxes.boxes(data, stp + sth + 8, stp + sts):
                    if typ in boxes.VIDEO:
                        for t, p2, h2, s2, _ in boxes.boxes(data, p + h + 78, p + s):
                            if t == b"hvcC":
                                return data[p2 + h2:p2 + s2]


if __name__ == "__main__":
    a, b = mkv_private(sys.argv[1]), mp4_hvcc(sys.argv[2])
    if a == b:
        print(f"IDENTICAL ({len(a)} bytes)")
    else:
        diffs = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
        print(f"DIFFERENT: mkv {len(a)} bytes, mp4 {len(b)} bytes, differing offsets {diffs[:12]}")
        for i in diffs[:6]:
            print(f"  offset {i}: mkv {a[i]:02x} mp4 {b[i]:02x}")
