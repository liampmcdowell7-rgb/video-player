# Audio pipeline: DTS, DTS-HD, Dolby TrueHD, MLP, Opus and Vorbis decoded and repackaged as FLAC

Written 2026-11-17 by the AUDIO work stream. Device results: none yet (docs/DEVICE_TEST_CHECKLIST_AUDIO.md).

## 1. What it does

The system player cannot play DTS, Dolby TrueHD, MLP, Opus-in-Matroska or Vorbis. The converting player (RemuxEngine,
docs/ENGINE_DESIGN.md) now hands those tracks to `DecodedAudioTranscoder` (target `AudioDecode`), which decodes them with
FFmpeg's libavcodec and writes FLAC frames into the fragmented MP4 audio rendition, `CODECS="fLaC"` (the F2 spike result,
docs/spikes/REMUX.md). Dolby Digital, Dolby Digital Plus (with Atmos), AAC and FLAC tracks are unchanged: passed through.

| Source | End to end now | Lossless? |
|---|---|---|
| DTS (core, DTS-ES 6.1, DTS 96/24, DTS Express) | decoded with the integer (bit-exact) decoder, 24-bit FLAC at the source rate, source channel layout (6.1 keeps the back centre) | the core is lossy; the FLAC holds exactly what the decoder outputs |
| DTS-HD Master Audio (with or without core; 48/96/192 kHz; 16/24-bit) | decoded with the lossless extension, FLAC at the source bit depth and rate, source layout up to 7.1 | yes, bit-exact (tests below) |
| DTS-HD High Resolution | decoded (lossy extension), 24-bit FLAC | no (lossy source) |
| DTS:X | the decoder outputs the 7.1 bed (the vendored build's `x_heights` option is off: the encoder's height fold-down is in the bed); objects not rendered; said in the status | the bed is lossless |
| DTS-HD MA with a missing extension in some frames | those frames play from the core, counted ("frames without lossless extension") and shown in Playback Stats | lossless where the extension is present |
| Dolby TrueHD | full decode to the track's own layout up to 7.1 (default), FLAC at source depth and rate | yes, bit-exact |
| Dolby TrueHD with Atmos | the 7.1 presentation (bed) is decoded losslessly; the objects are not played; status: "the Atmos objects are not played, only the 7.1 bed" | the bed is bit-exact |
| Dolby TrueHD with an embedded Dolby Digital core | default: full decode as above. Setting "Play the Dolby Digital Core of Dolby TrueHD" (off by default): the AC-3 frames are passed through as a Dolby Digital rendition | core: lossy 5.1 |
| MLP | full decode | yes, bit-exact |
| Opus | decoded (floating point), 24-bit FLAC, 48 kHz, codec delay removed from placement | lossy source |
| Vorbis | decoded (floating point), 24-bit FLAC | lossy source |

Nothing is ever downmixed by the app: a channel without a FLAC slot is reported (`droppedChannels`), never folded in.

## 2. The codec library (item 5a)

**Choice: vendored xcframeworks** (not a binaryTarget URL). FFmpegBuild 3.15.0 has no release assets, so there is no
pinned URL and checksum to point a binaryTarget at; cloning the 404 MB repository in CI is ruled out. Vendored in
`Packages/VideoPlayerCore/Frameworks/MediaCodecs/`:

- `AetherLibavcodec`, `AetherLibavutil`, `AetherLibswresample`, `AetherLibdav1d`, `AetherLibzvbi` `.xcframework`, only the
  `tvos-arm64` and `tvos-arm64_x86_64-simulator` slices (29 MB in total, 9.3 MB device slices). Dynamic frameworks.
- FFmpeg n8.1.3, configured without `--enable-gpl`, `--enable-version3`, `--enable-nonfree`: LGPL-2.1-or-later.
- `LICENSES/` (LGPL-2.1 text, FFmpegBuild licence, dav1d BSD-2-Clause, libzvbi MIT parts, zimg WTFPL, `NOTICE-LGPL.md`
  with the source location, sha256 and how to replace the libraries), `upstream-build-record/` (BUILD-INFO.txt with the
  exact configure lines, build.sh, patches).
- MPVKit was the fallback and was not needed.

`Package.swift` (AUDIO-DECODE block): Apple platforms declare the five frameworks as path binaryTargets and a small C
target `CMediaCodecs` over them (a neutral wrapper name). Linux declares the targets only when `VP_MEDIACODECS` names an
install prefix of a locally built LGPL FFmpeg (systemLibrary `CMediaCodecsSystem` + pkg-config), like NFS with `VP_LIBNFS`.

Test build of the same library (scripts/test-audio.sh build): FFmpeg n8.1.3 source
https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n8.1.3.tar.gz, 16,906,107 bytes, sha256
09f990289327d3ebfedf4fc15cae3f884a65dab7a5aac7bbb5b01ff83900efd9, the upstream DTS patch, the shipped build's component
list minus platform flags; configure printed "License: LGPL version 2.1 or later". x86 assembly is off (no nasm in WSL),
which makes the CPU numbers below pessimistic for this host.

## 3. How a segment is made

- **Probe** (`outputConfig`): the first frames are decoded to learn the real format (Matroska says `A_DTS` for every DTS
  kind), channels, mask, rate and depth. Output depth: 24 for float decoders or sources above 16 bits, else 16. Output
  rate: the source rate (optional `maxSampleRate` cap, off by default).
- **Block grid**: FLAC blocks of B = 4096 samples (up to 48 kHz), 8192 (up to 96 kHz), 16384 (above), anchored at the
  track's first frame. Block j belongs to the segment whose time range holds its first sample, so any request order gives
  the same blocks. Frame numbers are rewritten to j (CRC-8 and CRC-16 recomputed) so the stream is valid FLAC whatever
  segment it starts from. PROVISIONAL block sizes; alternative: 4096 everywhere (more frames at high rates).
- **Warm / cold**: sequential segments continue the same decoder. A seek starts cold, warmed by up to 0.5 s of the
  previous window when the session still holds it. Without warm-up a DTS-HD segment's first ~38 ms differ slightly from a
  sequential decode (measured below; my reading, PROVISIONAL: the core's synthesis filter has no history; alternative:
  the lossless extension needs its own sync point).
- **Placement**: decoded audio is laid back to back and re-aligned to the frame timestamps only when they disagree by more
  than 40 ms or after an error (PROVISIONAL tolerance; Matroska stores milliseconds). Gaps become counted silence; overlaps
  are dropped. Frames already fed (the previous segment's look-ahead) are not fed again; frames with the same millisecond
  timestamp (TrueHD access units are 0.83 ms apart) are told apart by their bytes.
- **TrueHD / MLP**: blocks are split into access units (AC-3 syncframes of an embedded core are separated out).
- **Layout change**: the first layout is kept; channels missing from a later layout are silent; counted and shown.
- **Rate change**: resampled (libswresample) to the first rate; counted and shown.
- **Damaged frames**: the decoder's error is caught, the frame's time becomes silence, the count and the first five
  messages go to the diagnostics shown in Playback Stats. Playback never stops and never goes silent without a message.

## 4. Channel layouts (item 5b)

FLAC fixes the channel order by channel count (FLAC format: 6 = L R C LFE Ls Rs, 8 = L R C LFE Lb Rb Ls Rs, 7 = L R C LFE
Cs Ls Rs). `ChannelLayoutMap` maps the decoder's mask to the smallest FLAC layout that holds every channel (side and back
are treated as aliases), so 5.1(side) and 5.1(back) both become FLAC 5.1 and 7.1 stays 7.1.

In the fMP4, the `dfLa` box carries STREAMINFO (channel count); no `chnl` box is written. The HLS playlist gives
`CHANNELS="6"` / `"8"` and `CODECS="fLaC"`. **UNVERIFIED**: Apple's HLS authoring specification lists FLAC as a supported
multichannel codec (rule 2.5) in fMP4 only (rule 2.25) and `fLaC` as the CODECS value, but no Apple page says how the
player maps FLAC channels to speakers or whether it reads a `chnl` box. Device check AU-14.

## 5. What reaches the speakers (Apple pages, read 2026-11-17)

- HLS authoring specification for Apple devices, https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html:
  2.5 (FLAC and Apple Lossless are supported multichannel codecs), 2.25 (FLAC MUST be in fMP4), 2.10 / 2.11 (layout may
  change only with a discontinuity; "SHOULD NOT change" for AirPlay 2 TVs: this is why the app keeps the first layout),
  2.26 (non-Dolby multichannel SHOULD also be offered as multichannel AAC: not done, see section 8). The page has no rule on
  sample rates or bit depths.
- Lossless and Hi-Res Lossless: https://support.apple.com/en-us/118295: "Hi-Res Lossless is available only on Apple TV 4K
  (3rd generation or later)", through an AV receiver over HDMI. The page gives no sample rate or bit depth and says nothing
  about plain lossless on older models. It describes the Music app; whether the same output path applies to a FLAC
  rendition in a video player is my reading (PROVISIONAL).
- Apple TV 4K (3rd generation) specs, https://support.apple.com/en-us/111839: audio formats include "Apple Lossless, FLAC",
  "AC-3 (Dolby Digital 5.1), E-AC-3 (Dolby Digital Plus 7.1 surround sound), and Dolby Atmos"; ARC / eARC appear only in a
  footnote; the page lists no LPCM channel count and no sample rate above 48 kHz.
- Atmos over ARC: https://support.apple.com/en-us/102310 (Dolby Atmos needs eARC or HDMI to a receiver; not over ARC).
- **UNVERIFIED (device):** the HDMI / eARC output rate for a 96 or 192 kHz FLAC rendition, and what AirPlay receives. The
  status text says "the system does not report whether this output receives the full 96 kHz" for sources above 48 kHz
  instead of claiming it. QUALITY_CEILINGS.md, Audio, has the rows.

## 6. Tests (item 5e)

Command (WSL, inside the shared lock, -j2): `bash scripts/test-audio.sh all` (build library, make media, run
`AudioDecodeTests`); also run by `scripts/test-all.sh` as the `audio` stage. Last run 2026-11-17: **38 passed, 0 skipped,
0 failed** (EndToEndTests 25, FramingTests 8, TranscoderTests 5).

Media (fixtures, never shipped; `scripts/audio-make-media.py`): generated with the LGPL tools' encoders (dca, truehd, mlp,
libopus, libvorbis, ac3) from a test signal with a distinct tone per channel plus low noise, and FATE samples for what no
LGPL encoder makes (DTS-HD MA, real TrueHD and Atmos). Short samples are repeated by joining whole frames. The LGPL TrueHD
encoder cannot make 7.1 (asked for 7.1 it wrote "truehd,s32,48000,6,5.1(side)"), so 7.1 TrueHD is tested with the FATE
Atmos sample. No LGPL DTS-HD MA encoder exists.

FATE samples (https://fate-suite.ffmpeg.org/<path>), sha256 and size:

| File | Path | sha256 | Bytes |
|---|---|---|---|
| master_audio_7.1_24bit.dts | dts/ | 227f1008f9529b2bdf937ce856d2562d0128162ac930e2579ef4b8fd7474ee18 | 6,598,176 |
| xll_71_24_96_768.dtshd | dts/dcadec-suite/ | d2911b34183f7379359cf914ee93228796894e0b0f0055e6ee5baefa4fd6a923 | 54,184 |
| xll_51_16_192_768_0.dtshd | dts/dcadec-suite/ | 34441a4f2df89e086f67a7b0f72aa871e1cbb3b04b301470a7727038bb91b618 | 44,608 |
| xll_51_24_48_none.dtshd | dts/dcadec-suite/ | c445bb746c6afc920761b55b00932053d64a96d3d08cd9cad4c759a892fae4cd | 34,460 |
| core_51_24_48_768_0.dtshd | dts/dcadec-suite/ | 95653e7d94307a9d467c28ae10883440dcc39f06ac79d7401b27eb422cd99009 | 7,368 |
| dts_es.dts | dts/ | 2e2530d220d51b914d1e7acb63badb5b2dae1578f3274116206fa1aa5e597638 | 503,000 |
| truehd_5.1.raw | lossless-audio/ | f00a67adeec561c8bb9e98da06e38f5d3f204778ff931c592f81db54ce428127 | 655,360 |
| atmos.thd | truehd/ | 020c9b9e67f80de105663af191740f8b60f550107c9f765b632f4cd5efb1c6ab | 58,738 |

How each case is checked: the Matroska file goes through the whole engine; the fMP4 output is probed with ffprobe (codec
flac, channels, rate, bits) and decoded back with the reference ffmpeg (`-flags +bitexact`, s32 PCM); the source is decoded
the same way; the two are compared sample by sample (bit-exact means: the reference decode of the source equals the
decode of our FLAC). For the generated TrueHD and MLP files the output is also compared with the encoder's input WAV.

Bit-exact results (6 s each, all channels):

| File | Format found | Out | Frames compared | Mismatching samples |
|---|---|---|---|---|
| dtshd_ma_71_24_48k | DTS-HD MA 7.1 | 8ch 48 kHz 24-bit | 288,256 | 0 |
| dtshd_ma_71_24_96k | DTS-HD MA 7.1 | 8ch 96 kHz 24-bit | 576,512 | 0 |
| dtshd_ma_51_16_192k | DTS-HD MA 5.1 | 6ch 192 kHz 16-bit | 1,153,024 | 0 |
| dtshd_ma_51_24_48k_nocore | DTS-HD MA 5.1, no core | 6ch 48 kHz 24-bit | 288,768 | 0 |
| dtshd_ma_71_missing_ext (3 s without extension) | DTS-HD MA 7.1 | 8ch 48 kHz 24-bit | 288,256 | 0 (and the core-only frames are counted) |
| dtshd_core_51_24_48k (DTS-HD file, core only) | DTS | 6ch 48 kHz 24-bit | 288,256 | 0 |
| dts_core_51_48k | DTS | 6ch 48 kHz 24-bit | 288,256 | 0 |
| dts_core_20_44k | DTS | 2ch 44.1 kHz 24-bit | 264,704 | 0 |
| dts_es_61 | DTS-ES 6.1 | 7ch 48 kHz 24-bit | 288,256 | 0 |
| truehd_51_fate | TrueHD 5.1 | 6ch 48 kHz 24-bit | 288,000 | 0 |
| truehd_atmos_fate | TrueHD with Atmos, 7.1 bed | 8ch 48 kHz 24-bit | 288,000 | 0 |
| truehd_enc_6ch_24_48k | TrueHD 5.1 | 6ch 48 kHz 24-bit | 288,000 | 0 (also 0 against the encoder's input) |
| truehd_enc_6ch_24_96k | TrueHD 5.1 | 6ch 96 kHz 24-bit | 576,000 | 0 (also 0 against the input) |
| truehd_enc_2ch_24_192k | TrueHD stereo | 2ch 192 kHz 24-bit | 1,152,000 | 0 (also 0 against the input) |
| mlp_enc_6ch_24_48k | MLP 5.1 | 6ch 48 kHz 24-bit | 288,000 | 0 (also 0 against the input) |
| TrueHD with Dolby Digital frames inside (transcoder test) | TrueHD 5.1, core present | 6ch 48 kHz 24-bit | 288,000 | 0 (default full decode) |
| opus_2ch / 6ch / 8ch | Opus | 48 kHz 24-bit | 288,000 | largest difference 384 / 2^31 (float decoders; tolerance 2^-15) |
| vorbis_2ch / 6ch / 8ch | Vorbis | 48 kHz 24-bit | 288,000 | largest difference 512 / 2^31; output starts 144 samples (3 ms) later, see below |

Other checks: layout change 5.1 to stereo (6 channels kept, the 4 missing channels silent, 1 change counted, no silence
added); rate change 48 to 44.1 kHz (resampled, 6.0 s out, longest zero run 1 sample); segments asked out of order (every
segment byte-identical to the sequential run except the cold one, which differs in 14,547 samples, largest 6e-4 of full
scale, 0 silent samples); damaged TrueHD (6 frames concealed, 3,880 samples of counted silence, full length out, messages
recorded); the compatibility core setting passes the AC-3 frames; `maxSampleRate` 44100 resamples; the fallback chooses
the same-language track.

Vorbis start (PROVISIONAL): the first Vorbis packet decodes to nothing; the output begins at the timestamp of the first
decoded packet, so 144 samples of counted silence come first; a plain decode starts at its first sample. The test accepts
a shift only when it is fully explained by counted silence and under 20 ms. Alternative: start Vorbis output at the
anchor (would move the audio 3 ms earlier than the file's timestamps say). Opus end: 648 extra samples at the end of the
track (the Matroska end padding is not trimmed; inaudible, after the last real sample).

## 7. CPU (item 5d)

Measured in WSL on this machine (x86-64, one thread, FFmpeg without x86 assembly), decode + FLAC encode (level 5), seconds
of CPU per second of audio:

| Source | Load |
|---|---|
| DTS-HD MA 7.1 24-bit 48 kHz | 0.087 |
| DTS-HD MA 7.1 24-bit 96 kHz | 0.32 |
| DTS-HD MA 5.1 16-bit 192 kHz | 0.33 |
| TrueHD Atmos 7.1 bed 48 kHz | 0.11 |
| Opus 7.1 | 0.13 |
| FLAC level 0 / 2 / 5 / 8 on the 7.1 96 kHz case (whole path) | 0.35 / 0.30 / 0.33 / 0.36 (noise between runs is about +-0.05) |

The encode level makes little difference; the decode dominates. **Apple TV 4K estimate, UNMEASURED on device:** the
vendored build has the ARM NEON paths this test build lacks; assuming an A12 / A15 performance core is roughly as fast per
thread as this host's core (an assumption, not measured), 7.1 48 kHz lossless would cost about 5 to 15% of one core and
7.1 96 kHz or 192 kHz about 15 to 40%. Both are under one core, and the engine produces audio ahead of playback, so real
time holds with margin if the assumption is within a factor of two. Device check AU-15.

## 8. Not done / open

- The licence screen in the app (Settings > About) does not yet show the LGPL notice; the text is in
  `Frameworks/MediaCodecs/LICENSES/NOTICE-LGPL.md`. How the source is offered (LGPL 6a/6c) is the owner's decision.
- HLS rule 2.26 (SHOULD also offer multichannel AAC next to non-Dolby multichannel): not done; it would add a lossy
  encode. Quality principle: lossless only; owner decision.
- Nothing has been compiled for tvOS: the CMediaCodecs C target against the xcframework headers, the binaryTarget names,
  embedding and signing of the dynamic frameworks, and the App code (RemuxPlayback, PlayerCoordinator, settings toggle).
- Device questions: 96 / 192 kHz output, FLAC 7.1 speaker mapping, AirPlay behaviour, CPU (checklist AU-1 to AU-16).
- Next-best track rule (same language, then lossless, then more channels) is PROVISIONAL; alternative: the file's order.
