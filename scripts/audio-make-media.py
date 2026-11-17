#!/usr/bin/env python3
# Makes the audio test media for scripts/test-audio.sh (test fixtures only, never shipped).
#   python3 -I scripts/audio-make-media.py <ffmpeg> <ffprobe> <media dir>
# Every file is a short Matroska file: a small H.264 picture (the engine needs a video track) and one audio track.
# Sources:
#  - generated here with the LGPL tools' own encoders: DTS core (dca), TrueHD (truehd), Opus (libopus), Vorbis (libvorbis);
#    the test signal gives every channel its own tone plus low-level noise, so a swapped channel or a lost low bit shows;
#  - copied from the FATE samples in <media dir>/fate (DTS-HD Master Audio and real TrueHD/Atmos: no LGPL encoder makes
#    DTS-HD Master Audio, see docs/AUDIO_PIPELINE.md).
# Writes <media dir>/MANIFEST.txt (one line per file: name, how it was made, or FAILED with the reason) and READY.
import os
import subprocess
import sys

FF, FP, MEDIA = sys.argv[1], sys.argv[2], sys.argv[3]
FATE = os.path.join(MEDIA, "fate")
WORK = os.path.join(MEDIA, "work")
os.makedirs(WORK, exist_ok=True)
DUR = 6
manifest = []

LAYOUTS = {2: "stereo", 6: "5.1", 7: "6.1", 8: "7.1"}
TONES = [220, 277, 330, 415, 494, 554, 659, 740]


def run(args):
    r = subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y"] + args, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout).strip()[-600:])


def signal(channels, rate, seconds=DUR):
    exprs = "|".join(f"0.4*sin(2*PI*{TONES[c]}*t)+0.002*(random({c})-0.5)" for c in range(channels))
    return ["-f", "lavfi", "-i", f"aevalsrc=exprs='{exprs}':s={rate}:c={LAYOUTS[channels]}:d={seconds}"]


def video(seconds=DUR):
    return ["-f", "lavfi", "-i", f"testsrc2=s=160x96:r=24:d={seconds}"]


VIDEO_OUT = ["-map", "0:v", "-map", "1:a", "-c:v", "libopenh264", "-g", "24", "-b:v", "200k"]


def make(name, how, fn):
    out = os.path.join(MEDIA, name)
    try:
        if not os.path.exists(out):
            fn(out)
        manifest.append(f"{name}\t{how}")
    except Exception as e:  # recorded, the tests report the file as missing
        manifest.append(f"{name}\tFAILED: {how}: {e}")
        if os.path.exists(out):
            os.remove(out)


def pcm_then(out_codec_args, channels, rate, bits, out):
    wav = os.path.join(WORK, os.path.basename(out) + ".wav")
    run(signal(channels, rate) + ["-c:a", "pcm_s24le" if bits == 24 else "pcm_s16le", wav])
    run(video() + ["-i", wav] + VIDEO_OUT + out_codec_args + [out])


def from_raw(raw, out, loop=True, extra=()):
    # The raw elementary stream copied into Matroska. A short sample is repeated by joining copies of its bytes (not with
    # -stream_loop: that restarts the timestamps from an estimated duration and leaves gaps or overlaps at each repeat, which
    # a decoder that follows the timestamps fills with silence while a plain decode does not).
    src = raw
    if loop:
        # First the plain elementary stream as the demuxer's parser cuts it: whole frames only (a .dtshd file is a chunked
        # container, and a sample may end inside a frame), so every repeat starts on a frame boundary.
        fmt = "truehd" if raw.endswith((".thd", ".raw")) else "dts"
        plain = os.path.join(WORK, os.path.basename(out) + ".plain." + fmt)
        run(["-i", raw, "-map", "0:a", "-c:a", "copy", "-f", fmt, plain])
        src = os.path.join(WORK, os.path.basename(out) + ".joined." + fmt)
        size = os.path.getsize(plain)
        # Enough bytes for DUR seconds at up to 32 Mbit/s (well above any of these samples); -t cuts the rest.
        copies = min(2000, max(2, -(-(DUR * 4 * 1024 * 1024) // max(size, 1))))
        with open(plain, "rb") as f:
            data = f.read()
        with open(src, "wb") as j:
            for _ in range(copies):
                j.write(data)
    args = video() + list(extra) + ["-i", src, "-t", str(DUR)] + VIDEO_OUT + ["-c:a", "copy", out]
    run(args)


def fate(name):
    p = os.path.join(FATE, name)
    if not os.path.exists(p):
        raise RuntimeError(f"FATE sample {name} missing")
    return p


# DTS core (lossy), generated.
make("dts_core_51_48k.mkv", "dca encoder, 5.1, 48 kHz, 1509 kb/s",
     lambda o: pcm_then(["-c:a", "dca", "-strict", "-2", "-b:a", "1509k"], 6, 48000, 24, o))
make("dts_core_20_44k.mkv", "dca encoder, stereo, 44.1 kHz",
     lambda o: pcm_then(["-c:a", "dca", "-strict", "-2", "-b:a", "768k"], 2, 44100, 24, o))

# DTS-HD Master Audio and other DTS kinds, from FATE.
make("dtshd_ma_71_24_48k.mkv", "FATE dts/master_audio_7.1_24bit.dts",
     lambda o: from_raw(fate("master_audio_7.1_24bit.dts"), o))
make("dtshd_ma_71_24_96k.mkv", "FATE dts/dcadec-suite/xll_71_24_96_768.dtshd, looped",
     lambda o: from_raw(fate("xll_71_24_96_768.dtshd"), o))
make("dtshd_ma_51_16_192k.mkv", "FATE dts/dcadec-suite/xll_51_16_192_768_0.dtshd, looped",
     lambda o: from_raw(fate("xll_51_16_192_768_0.dtshd"), o))
make("dtshd_ma_51_24_48k_nocore.mkv", "FATE dts/dcadec-suite/xll_51_24_48_none.dtshd (lossless without a core), looped",
     lambda o: from_raw(fate("xll_51_24_48_none.dtshd"), o))
make("dtshd_core_51_24_48k.mkv", "FATE dts/dcadec-suite/core_51_24_48_768_0.dtshd (core only), looped",
     lambda o: from_raw(fate("core_51_24_48_768_0.dtshd"), o))
make("dts_es_61.mkv", "FATE dts/dts_es.dts (DTS-ES 6.1), looped",
     lambda o: from_raw(fate("dts_es.dts"), o))


def missing_extension(o):
    # 3 s of the full DTS-HD MA stream, then 3 s of the same stream with the lossless extension removed (dca_core).
    src = fate("master_audio_7.1_24bit.dts")
    a = os.path.join(WORK, "ma_full.dts")
    b = os.path.join(WORK, "ma_core.dts")
    run(["-i", src, "-t", "3", "-c:a", "copy", "-f", "dts", a])
    run(["-ss", "3", "-i", src, "-t", "3", "-c:a", "copy", "-bsf:a", "dca_core", "-f", "dts", b])
    joined = os.path.join(WORK, "ma_missing_ext.dts")
    with open(joined, "wb") as j:
        for p in (a, b):
            with open(p, "rb") as f:
                j.write(f.read())
    from_raw(joined, o, loop=False)


make("dtshd_ma_71_missing_ext.mkv", "FATE master_audio_7.1_24bit.dts: 3 s full, then 3 s with the extension stripped (dca_core)",
     missing_extension)


def joined_dts(o, first, second):
    parts = []
    for i, (ch, rate) in enumerate((first, second)):
        wav = os.path.join(WORK, f"{os.path.basename(o)}_{i}.wav")
        dts = wav + ".dts"
        run(signal(ch, rate, DUR // 2) + ["-c:a", "pcm_s24le", wav])
        run(["-i", wav, "-c:a", "dca", "-strict", "-2", "-b:a", "1509k", "-f", "dts", dts])
        parts.append(dts)
    joined = os.path.join(WORK, os.path.basename(o) + ".dts")
    with open(joined, "wb") as j:
        for p in parts:
            with open(p, "rb") as f:
                j.write(f.read())
    from_raw(joined, o, loop=False)


make("dts_layout_change.mkv", "dca encoder: 3 s 5.1 then 3 s stereo, 48 kHz",
     lambda o: joined_dts(o, (6, 48000), (2, 48000)))
make("dts_rate_change.mkv", "dca encoder: 3 s 48 kHz then 3 s 44.1 kHz, 5.1",
     lambda o: joined_dts(o, (6, 48000), (6, 44100)))

# TrueHD: real streams from FATE, and generated with the (experimental) LGPL encoder from a known PCM signal.
make("truehd_51_fate.mkv", "FATE lossless-audio/truehd_5.1.raw, looped", lambda o: from_raw(fate("truehd_5.1.raw"), o))
make("truehd_atmos_fate.mkv", "FATE truehd/atmos.thd (TrueHD with Atmos), looped", lambda o: from_raw(fate("atmos.thd"), o))
# No 7.1 here: asked for 7.1, the LGPL TrueHD encoder (n8.1.3) writes a 5.1 stream (checked with ffprobe on 2026-11-17:
# "truehd,s32,48000,6,5.1(side)"), so the 7.1 TrueHD cases use the FATE Atmos sample (a real 7.1 presentation).
for ch, rate in ((6, 48000), (6, 96000), (2, 192000)):
    name = f"truehd_enc_{ch}ch_24_{rate // 1000}k.mkv"
    make(name, f"truehd encoder (experimental), {LAYOUTS[ch]}, 24-bit, {rate} Hz",
         lambda o, ch=ch, rate=rate: pcm_then(["-c:a", "truehd", "-strict", "-2"], ch, rate, 24, o))
make("mlp_enc_6ch_24_48k.mkv", "mlp encoder (experimental), 5.1, 24-bit, 48 kHz",
     lambda o: pcm_then(["-c:a", "mlp", "-strict", "-2"], 6, 48000, 24, o))

# Opus and Vorbis (lossy, 48 kHz).
for ch in (2, 6, 8):
    make(f"opus_{ch}ch.mkv", f"libopus, {LAYOUTS[ch]}, 48 kHz",
         lambda o, ch=ch: pcm_then(["-c:a", "libopus", "-b:a", f"{64 * ch}k", "-mapping_family", "1"], ch, 48000, 24, o))
    make(f"vorbis_{ch}ch.mkv", f"libvorbis, {LAYOUTS[ch]}, 48 kHz",
         lambda o, ch=ch: pcm_then(["-c:a", "libvorbis", "-q:a", "6"], ch, 48000, 24, o))



def two_tracks(o):
    # Track 2 (default): DTS 5.1; track 3: Dolby Digital 5.1 ("fre"); track 4: Dolby Digital stereo ("eng").
    wav = os.path.join(WORK, "two_tracks.wav")
    run(signal(6, 48000) + ["-c:a", "pcm_s24le", wav])
    run(video() + ["-i", wav, "-i", wav, "-i", wav, "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3:a",
                   "-c:v", "libopenh264", "-g", "24", "-b:v", "200k",
                   "-c:a:0", "dca", "-strict", "-2", "-c:a:1", "ac3", "-c:a:2", "ac3", "-ac:a:2", "2",
                   "-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=fre", "-metadata:s:a:2", "language=eng",
                   "-disposition:a:0", "default", "-disposition:a:1", "0", "-disposition:a:2", "0", o])


make("fallback_three_tracks.mkv", "dca 5.1 (eng, default) + ac3 5.1 (fre) + ac3 stereo (eng)", two_tracks)

# Raw streams for the transcoder-level tests (TrueHD with interleaved Dolby Digital frames, damaged frames).
make("raw_truehd_51.thd", "truehd encoder, 5.1, 24-bit, 48 kHz, raw",
     lambda o: (run(signal(6, 48000) + ["-c:a", "pcm_s24le", os.path.join(WORK, "raw_truehd.wav")]),
                run(["-i", os.path.join(WORK, "raw_truehd.wav"), "-c:a", "truehd", "-strict", "-2", "-f", "truehd", o])))
make("raw_ac3_51.ac3", "ac3 encoder, 5.1, 48 kHz, 640 kb/s, raw",
     lambda o: run(signal(6, 48000) + ["-c:a", "ac3", "-b:a", "640k", "-f", "ac3", o]))

with open(os.path.join(MEDIA, "MANIFEST.txt"), "w") as m:
    m.write("\n".join(manifest) + "\n")
print("\n".join(manifest))
failed = [l for l in manifest if "\tFAILED" in l]
with open(os.path.join(MEDIA, "READY"), "w") as r:
    r.write(f"{len(manifest) - len(failed)} made, {len(failed)} failed\n")
