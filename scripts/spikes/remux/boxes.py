"""MP4 / fMP4 box inspector for the remux spike. Run: python3 -I boxes.py file.mp4 [file2.mp4 ...]
Prints, per track: sample entry type (hvc1/hev1/dvh1/dvhe/ec-3/...) and the interesting child boxes decoded:
hvcC (hex digest + profile/level), colr nclx, mdcv, clli, dvcC/dvvC (profile, level, flags, compat id), dec3 (E-AC-3,
incl. the JOC flag_ec3_extension_type_a), dac3, esds, dfLa, alac, pcmC, chnl; counts moof/sidx; lists the box tree top level.
Written for this spike only; not a general parser.
"""
import hashlib
import struct
import sys

CONTAINERS = {b"moov", b"trak", b"mdia", b"minf", b"stbl", b"edts", b"dinf", b"mvex", b"moof", b"traf", b"udta"}
VIDEO = {b"hvc1", b"hev1", b"dvh1", b"dvhe", b"avc1", b"avc3", b"dva1", b"dvav", b"av01", b"dav1"}
AUDIO = {b"mp4a", b"ac-3", b"ec-3", b"alac", b"fLaC", b"ipcm", b"fpcm", b"Opus", b"mhm1", b"lpcm", b"sowt", b"twos", b"in24", b"fl32"}


def boxes(data, start, end):
    pos = start
    while pos + 8 <= end:
        size, typ = struct.unpack(">I4s", data[pos:pos + 8])
        hdr = 8
        if size == 1:
            size = struct.unpack(">Q", data[pos + 8:pos + 16])[0]
            hdr = 16
        elif size == 0:
            size = end - pos
        if size < hdr or pos + size > end:
            yield typ, pos, hdr, min(end, pos + max(size, hdr)) - pos, True
            return
        yield typ, pos, hdr, size, False
        pos += size


def find_all(data, start, end, path):
    """yield (pos, hdr, size) of boxes at the given path (list of 4cc) below start..end"""
    for typ, pos, hdr, size, _ in boxes(data, start, end):
        if typ == path[0]:
            if len(path) == 1:
                yield pos, hdr, size
            else:
                yield from find_all(data, pos + hdr, pos + size, path[1:])


def hex_of(b, n=48):
    h = b.hex()
    return h if len(b) <= n else h[:n * 2] + f"...(+{len(b) - n}B)"


def dovi(body):
    # DOVIDecoderConfigurationRecord: major, minor, profile(7) level(6) rpu(1) el(1) bl(1), bl_compat_id(4)
    major, minor = body[0], body[1]
    v = (body[2] << 8) | body[3]
    profile = v >> 9
    level = (v >> 3) & 0x3F
    rpu, el, bl = (v >> 2) & 1, (v >> 1) & 1, v & 1
    compat = body[4] >> 4
    return f"v{major}.{minor} profile={profile} level={level} rpu={rpu} el={el} bl={bl} bl_compat_id={compat} raw={body[:24].hex()}"


def hvcc(body):
    prof_space_tier_idc = body[1]
    compat = body[2:6].hex()
    level = body[12]
    narrays = body[22]
    return (f"len={len(body)} sha1={hashlib.sha1(body).hexdigest()[:12]} profile_idc={prof_space_tier_idc & 0x1F} "
            f"tier={(prof_space_tier_idc >> 5) & 1} compat={compat} level_idc={level} (={level / 30:.1f}) arrays={narrays}")


def colr(body):
    kind = body[:4]
    if kind == b"nclx":
        prim, trc, mat = struct.unpack(">HHH", body[4:10])
        return f"nclx primaries={prim} transfer={trc} matrix={mat} full_range={body[10] >> 7}"
    return f"{kind.decode('latin1')} len={len(body)}"


def mdcv(body):
    v = struct.unpack(">8H2I", body[:24])
    # order in file: G, B, R (x,y each; units 0.00002) then white point, then max, min luminance (units 0.0001 cd/m2)
    g, b, r, wp = v[0:2], v[2:4], v[4:6], v[6:8]
    return f"G={g} B={b} R={r} WP={wp} max_lum={v[8] / 10000} min_lum={v[9] / 10000} cd/m2"


def clli(body):
    mx, fall = struct.unpack(">HH", body[:4])
    return f"MaxCLL={mx} MaxFALL={fall}"


def dec3(body):
    # data_rate(13) num_ind_sub(3); then per substream: fscod(2) bsid(5) reserved(1) asvc(1) bsmod(3) acmod(3) lfeon(1)
    # reserved(3) num_dep_sub(4) [chan_loc(9) if dep] ; optional extension: reserved(7) flag_ec3_extension_type_a(1) complexity_index_type_a(8)
    data_rate = (body[0] << 5) | (body[1] >> 3)
    nind = (body[1] & 7) + 1
    pos = 2
    out = [f"data_rate={data_rate}kbps substreams={nind}"]
    bits = int.from_bytes(body, "big")
    total = len(body) * 8
    cur = 16
    def take(n):
        nonlocal cur
        v = (bits >> (total - cur - n)) & ((1 << n) - 1)
        cur += n
        return v
    for i in range(nind):
        fscod, bsid, _r, asvc, bsmod, acmod, lfe, _r2, ndep = take(2), take(5), take(1), take(1), take(3), take(3), take(1), take(3), take(4)
        chan_loc = take(9) if ndep else take(1)
        out.append(f"[sub{i} fscod={fscod} bsid={bsid} bsmod={bsmod} acmod={acmod} lfeon={lfe} num_dep_sub={ndep}]")
    if total - cur >= 16:
        take(7)
        a = take(1)
        c = take(8)
        out.append(f"EXT flag_ec3_extension_type_a={a} complexity_index_type_a={c}")
    else:
        out.append("no extension bytes (flag_ec3_extension_type_a absent => not signalled as JOC)")
    return " ".join(out)


def audio_entry_info(data, pos, hdr, size, typ):
    body = pos + hdr
    ver = struct.unpack(">H", data[body + 8:body + 10])[0]
    ch, bits = struct.unpack(">HH", data[body + 16:body + 20])
    rate = struct.unpack(">I", data[body + 24:body + 28])[0] >> 16
    kids = {2: 28 + 8 * 0, 0: 28, 1: 28 + 16}.get(ver, 28)
    if ver == 2:
        kids = 28 + 36 - 8 + 8  # version 2 sound description is 36 bytes after the 8-byte header region
    return f"channels={ch} bits={bits} rate={rate} qt_ver={ver}", body + kids


def describe_entry(data, pos, hdr, size, typ, handler):
    lines = []
    end = pos + size
    if typ in VIDEO:
        info = f"{struct.unpack('>HH', data[pos + hdr + 24:pos + hdr + 28])} "
        kids_start = pos + hdr + 78
    elif handler == b"soun" or typ in AUDIO:
        info, kids_start = audio_entry_info(data, pos, hdr, size, typ)
    else:
        info, kids_start = "", pos + hdr + 8
    lines.append(f"    sample entry '{typ.decode('latin1')}' {info}")
    for t, p, h, s, bad in boxes(data, kids_start, end):
        body = data[p + h:p + s]
        if t == b"hvcC":
            d = hvcc(body)
        elif t == b"colr":
            d = colr(body)
        elif t == b"mdcv":
            d = mdcv(body)
        elif t == b"clli":
            d = clli(body)
        elif t in (b"dvcC", b"dvvC", b"dvwC"):
            d = dovi(body)
        elif t == b"dec3":
            d = dec3(body)
        elif t in (b"avcC", b"dac3", b"esds", b"dfLa", b"dOps", b"pcmC", b"chnl", b"btrt", b"pasp", b"alac", b"wave"):
            d = f"len={len(body)} hex={hex_of(body, 24)}"
        else:
            d = f"len={len(body)}"
        lines.append(f"      {t.decode('latin1')}: {d}")
    return lines


def inspect(path):
    with open(path, "rb") as f:
        data = f.read()
    print(f"=== {path} ({len(data)} bytes)")
    top = [t.decode("latin1") for t, *_ in boxes(data, 0, len(data))]
    counts = {}
    for t in top:
        counts[t] = counts.get(t, 0) + 1
    print("  top-level boxes:", ", ".join(f"{k}x{v}" for k, v in counts.items()))
    ftyp = next(((p, h, s) for t, p, h, s, _ in boxes(data, 0, len(data)) if t == b"ftyp"), None)
    if ftyp:
        b = data[ftyp[0] + ftyp[1]:ftyp[0] + ftyp[2]]
        print(f"  ftyp major={b[:4].decode('latin1')} compat={[b[i:i + 4].decode('latin1') for i in range(8, len(b), 4)]}")
    for moov in find_all(data, 0, len(data), [b"moov"]):
        mp, mh, ms = moov
        for tp, th, ts in find_all(data, mp + mh, mp + ms, [b"trak"]):
            tr_end = tp + ts
            hdlr = next(find_all(data, tp + th, tr_end, [b"mdia", b"hdlr"]), None)
            handler = data[hdlr[0] + hdlr[1] + 8:hdlr[0] + hdlr[1] + 12] if hdlr else b"????"
            name = ""
            if hdlr:
                raw = data[hdlr[0] + hdlr[1] + 24:hdlr[0] + hdlr[2]]
                name = raw.split(b"\0")[0].decode("latin1", "replace")
            print(f"  track handler={handler.decode('latin1')} name={name!r}")
            for sp, sh, ss in find_all(data, tp + th, tr_end, [b"mdia", b"minf", b"stbl", b"stsd"]):
                for typ, p, h, s, _ in boxes(data, sp + sh + 8, sp + ss):
                    for line in describe_entry(data, p, h, s, typ, handler):
                        print(line)
        udta = [t for t, *_ in boxes(data, mp + mh, mp + ms) if t in (b"udta", b"meta")]
        if udta:
            print("  moov-level metadata boxes:", [u.decode() for u in udta])
        for up, uh, us in find_all(data, mp + mh, mp + ms, [b"udta"]):
            for t, p, h, s, _ in boxes(data, up + uh, up + us):
                print(f"  udta child: {t.decode('latin1')} len={s}" + (" (chapter list)" if t == b"chpl" else ""))
    print(f"  moof fragments: {counts.get('moof', 0)}, sidx: {counts.get('sidx', 0)}, mdat: {counts.get('mdat', 0)}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        inspect(p)
