"""Minimal Matroska (EBML) header reader for the remux spike. Run: python3 -I mkvinfo.py file.mkv [--json]

Reads only the Segment header area (Tracks, Chapters), never clusters, so it works on big files.
Reports per video track: CodecPrivate (hvcC / avcC bytes), Colour element (matrix, transfer, primaries, range,
MaxCLL, MaxFALL, mastering metadata) and BlockAdditionMapping (Dolby Vision dvcC/dvvC config), and the chapters.
This is also the shape of the code the app would need to write to turn MKV colour data into MP4 boxes.
"""
import json
import struct
import sys

MASTER = {0x18538067: "Segment", 0x1654AE6B: "Tracks", 0xAE: "TrackEntry", 0xE0: "Video", 0xE1: "Audio",
          0x55B0: "Colour", 0x55D0: "MasteringMetadata", 0x41E4: "BlockAdditionMapping",
          0x1043A770: "Chapters", 0x45B9: "EditionEntry", 0xB6: "ChapterAtom", 0x80: "ChapterDisplay"}
CLUSTER = 0x1F43B675
UINT = {0xD7: "TrackNumber", 0x83: "TrackType", 0x55B1: "MatrixCoefficients", 0x55B2: "BitsPerChannel",
        0x55B9: "Range", 0x55BA: "TransferCharacteristics", 0x55BB: "Primaries", 0x55BC: "MaxCLL",
        0x55BD: "MaxFALL", 0x41E7: "BlockAddIDType", 0x41F0: "BlockAddIDValue",
        0xB0: "PixelWidth", 0xBA: "PixelHeight", 0x91: "ChapterTimeStart", 0x92: "ChapterTimeEnd",
        0x45BD: "EditionFlagHidden", 0x98: "ChapterFlagHidden", 0x4555: "EditionFlagOrdered"}
FLOAT = {0x55D1: "PrimaryRChromaticityX", 0x55D2: "PrimaryRChromaticityY", 0x55D3: "PrimaryGChromaticityX",
         0x55D4: "PrimaryGChromaticityY", 0x55D5: "PrimaryBChromaticityX", 0x55D6: "PrimaryBChromaticityY",
         0x55D7: "WhitePointChromaticityX", 0x55D8: "WhitePointChromaticityY",
         0x55D9: "LuminanceMax", 0x55DA: "LuminanceMin"}
STRING = {0x86: "CodecID", 0x22B59C: "Language", 0x536E: "Name", 0x85: "ChapString", 0x41A4: "BlockAddIDName"}
BINARY = {0x63A2: "CodecPrivate", 0x41ED: "BlockAddIDExtraData"}


def vint(data, pos, keep_marker):
    first = data[pos]
    length = 1
    mask = 0x80
    while length <= 8 and not (first & mask):
        length += 1
        mask >>= 1
    if length > 8:
        raise ValueError("bad vint")
    value = first if keep_marker else first & (mask - 1)
    all_ones = (first & (mask - 1)) == mask - 1
    for i in range(1, length):
        b = data[pos + i]
        value = (value << 8) | b
        all_ones = all_ones and b == 0xFF
    return value, length, (all_ones and not keep_marker)


def parse(data, start, end, depth=0):
    out = []
    pos = start
    while pos < end:
        try:
            eid, n1, _ = vint(data, pos, True)
            size, n2, unknown = vint(data, pos + n1, False)
        except (ValueError, IndexError):
            break
        body = pos + n1 + n2
        stop = end if unknown else min(end, body + size)
        if eid == CLUSTER:
            break  # headers only
        node = {"id": hex(eid)}
        if eid in MASTER:
            node["name"] = MASTER[eid]
            node["children"] = parse(data, body, stop, depth + 1)
        elif eid in UINT:
            node["name"] = UINT[eid]
            node["value"] = int.from_bytes(data[body:stop], "big")
        elif eid in FLOAT:
            node["name"] = FLOAT[eid]
            raw = data[body:stop]
            node["value"] = struct.unpack(">f" if len(raw) == 4 else ">d", raw)[0]
        elif eid in STRING:
            node["name"] = STRING[eid]
            node["value"] = data[body:stop].decode("utf-8", "replace").rstrip("\0")
        elif eid in BINARY:
            node["name"] = BINARY[eid]
            node["hex"] = data[body:stop].hex()
        else:
            node = None
        if node:
            out.append(node)
        pos = stop
    return out


def find(nodes, name):
    return [n for n in nodes if n.get("name") == name]


def flat(node):
    return {c["name"]: c.get("value", c.get("hex")) for c in node.get("children", []) if "name" in c and "children" not in c}


def summarize(tree):
    seg = find(tree, "Segment")[0]["children"]
    result = {"tracks": [], "chapters": []}
    for tracks in find(seg, "Tracks"):
        for te in find(tracks["children"], "TrackEntry"):
            t = flat(te)
            info = {"number": t.get("TrackNumber"), "type": {1: "video", 2: "audio", 17: "subtitle"}.get(t.get("TrackType"), t.get("TrackType")),
                    "codec": t.get("CodecID"), "language": t.get("Language"), "codec_private": t.get("CodecPrivate")}
            for v in find(te["children"], "Video"):
                info.update({k: v2 for k, v2 in flat(v).items() if k.startswith("Pixel")})
                for col in find(v["children"], "Colour"):
                    c = flat(col)
                    for mm in find(col["children"], "MasteringMetadata"):
                        c["MasteringMetadata"] = flat(mm)
                    info["Colour"] = c
            for bam in find(te["children"], "BlockAdditionMapping"):
                info.setdefault("BlockAdditionMapping", []).append(flat(bam))
            result["tracks"].append(info)
    for chs in find(seg, "Chapters"):
        for ed in find(chs["children"], "EditionEntry"):
            for atom in find(ed["children"], "ChapterAtom"):
                a = flat(atom)
                titles = [flat(d).get("ChapString") for d in find(atom["children"], "ChapterDisplay")]
                result["chapters"].append({"start_ns": a.get("ChapterTimeStart"), "titles": titles, "hidden": a.get("ChapterFlagHidden", 0)})
    return result


if __name__ == "__main__":
    path = sys.argv[1]
    with open(path, "rb") as f:
        data = f.read(4 * 1024 * 1024)  # headers sit at the start of files made by mkvmerge and ffmpeg
    info = summarize(parse(data, 0, len(data)))
    if "--json" in sys.argv:
        print(json.dumps(info, indent=1))
    else:
        for t in info["tracks"]:
            print(f"track {t['number']} {t['type']} {t['codec']} lang={t['language']}")
            if t.get("Colour"):
                c = t["Colour"]
                print("  Colour:", {k: v for k, v in c.items() if k != "MasteringMetadata"})
                if "MasteringMetadata" in c:
                    print("  MasteringMetadata:", c["MasteringMetadata"])
            for b in t.get("BlockAdditionMapping", []):
                print("  BlockAdditionMapping:", b)
            if t["type"] == "video" and t.get("codec_private"):
                print("  CodecPrivate:", t["codec_private"][:80], "...", len(t["codec_private"]) // 2, "bytes")
        for ch in info["chapters"]:
            print("chapter", ch)
