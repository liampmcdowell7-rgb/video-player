# Remux spikes (item F, parts 1 and 2)

Status: research only, the app is not changed. Everything below was run in WSL (Ubuntu, x86-64, i5-8500T, 6 cores) on 2026-11-16.
Scripts: `scripts/spikes/remux/` (copy-pasteable, see "How to re-run"). Tools and generated media live outside the repo in `~/vp-remux-spike`.
Nothing could be played: **no AVPlayer, no Apple TV, no tvOS was available**, so every "will AVPlayer accept it" statement is either from Apple's published
documents (cited) or marked UNVERIFIED.

---------------------------------------------------------------------------------------------------

## Spike 1: remux MKV to fragmented MP4 / HLS fMP4 with an LGPL FFmpeg

### 1.1 Tools used (all downloaded from official release pages, user space, nothing installed system-wide)

| Tool | Version | Size (bytes) | sha256 | Role |
|---|---|---|---|---|
| FFmpeg LGPL (BtbN FFmpeg-Builds) master snapshot | N-128959-g4dbee3b241-20261116, libavformat 63.20.101 | 140,872,148 | ada6f750f336a08d8bc8d6988efc6e930799da4a499a398b3611597fdda9c561 | remuxer under test |
| FFmpeg LGPL 9.0 | n9.0.2-57-gd838f9f9ae-20261116 | 135,669,000 | 3c75df2d1f129dd8a843d2835fee296916a3d78ae253665649f368dbcfe33fb2 | version comparison |
| FFmpeg LGPL 8.1 | n8.1.3-35-gf1acb0a266-20261116 | 134,741,700 | a7909bf3b348b359bb31050e449f32e438330d39455d5a3afd25ed362e3ca1ad | version comparison |
| FFmpeg **GPL** master | same snapshot | 157,195,428 | c68c5d5cec21b81dc76cab9fa08eb43a8955a334e9337b4a142fdd1e187a6e32 | ONLY to encode test video (libx265/libx264). Never in the app path |
| dovi_tool | 2.3.4 (MIT) | 1,815,749 | 1844258e13c26607b32224bf1fa82b595d3b35949f5467405fda560daad32b3f | makes Dolby Vision RPU data, injects it |
| mkvmerge (MKVToolNix, GPL-2) | 97.0 from the Ubuntu archive (mkvtoolnix_97.0-1build1_amd64.deb, 6,472,996 bytes) + library debs unpacked with `dpkg -x` | | | writes MKVs the way rippers do |

The GPL ffmpeg and mkvmerge only produce test inputs. Output files of the remux tests were all made by the LGPL builds.

**LGPL proof** (`00-setup.sh`, command `ffmpeg -L` and `ffmpeg -buildconf`): the LGPL builds report "GNU Lesser General Public License version 3 or later" (`--enable-version3`),
and the build configuration contains no `--enable-gpl`, no `--enable-nonfree`, and no libx264/libx265. The GPL build reports `--enable-gpl` and libx265. A build the app ships must be our own
XCFramework build with the same property (configure without `--enable-gpl`, `--enable-nonfree`; no x264/x265); that build is a separate task (see 1.9).

### 1.2 Test inputs (`10-generate.sh`, `mkvinfo.py` verified them)

Synthetic 1080p24, 10 s, test pattern (no real titles).

| File | Content |
|---|---|
| hdr10.mkv | HEVC Main10, BT.2020 / PQ (16) / bt2020nc, x265 SEI mdcv `G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)` and max-cll 1000,400, **plus** an MKV Colour element (matrix 9, range 1, transfer 16, primaries 9, MaxCLL 1000, MaxFALL 400, MasteringMetadata chromaticity + luminance 1000 / 0.0001) |
| hdr10_sei_only.mkv | the same bitstream, **no** MKV Colour element (only the in-band SEI and VUI) |
| hlg.mkv | HEVC Main10, transfer 18 (HLG), Colour element with matrix/range/primaries/transfer, no mastering data |
| sdr_h264.mkv | H.264 8-bit BT.709 |
| dv81.mkv | HDR10 stream with a Dolby Vision profile 8.1 RPU injected (dovi_tool `generate` + `inject-rpu`); mkvmerge wrote a BlockAdditionMapping of type `dvvC` (0x64767643), extra data `0100101d...` |
| dv5.mkv | same with profile "5" RPU; mkvmerge wrote BlockAdditionMapping type `dvcC` (0x64766343), extra data `01000a1d...` |
| audio_subs.mkv (inside every file above) | AC-3 5.1 640k, E-AC-3 5.1 768k, AAC stereo 160k, DTS 5.1 1509k (FFmpeg `dca` encoder, experimental), 2 SRT tracks (eng, fre), 3 chapters (Intro / Episode / Credits) |
| novui.mkv | HEVC with no VUI colour and no Colour element |
| big_dv81.mkv | dv81.mkv looped 185 times, 1,737,505,737 bytes, 1865.9 s (throughput test) |

Verified with `mkvinfo.py` (own EBML parser, `python3 -I`): Colour element values, CodecPrivate (hvcC, 2530 bytes), DV BlockAdditionMapping types and extra data, chapters.
**Not possible here:** a real E-AC-3 JOC (Atmos) stream and a real DTS-HD MA / TrueHD file (no encoder in FFmpeg; no sample on the machine). Those items are listed under "unverified".

### 1.3 Results: what ffmpeg copies into the MP4 (identical on master, 9.0.2 and 8.1.3)

`25-versions.sh` ran the whole matrix on all three LGPL versions. The box summaries are identical; the only difference is the length of the encoder string in `udta/meta`
(`Lavf63.20.101` vs `Lavf63.1.102` vs `Lavf62.12.103`). Add `-fflags +bitexact` to drop it.

| Item | Result |
|---|---|
| Sample entry for HEVC | default is **`hev1`**. `-tag:v hvc1` gives `hvc1`. Apple's HLS spec rule 1.10 says SHOULD use hvc1/dvh1 and "use not recommended" for hev1/dvhe. **We must pass `-tag:v hvc1`** (or set the tag when using the API). |
| Sample entry for Dolby Vision | ffmpeg keeps `hvc1` even when a DV config exists. `-tag:v dvh1` works and gives `dvh1` + dvcC/dvvC (tested for profile 5 and 8.1). `-tag:v dvhe` is rejected ("Could not find tag"). |
| hvcC | present, parsed from the MKV CodecPrivate and **rewritten**, not copied byte-for-byte (`cmp_hvcc.py`). With hev1 the `array_completeness` bit is cleared on all four NAL arrays (offsets 23, 52, 105, 116: a0->20, a1->21, a2->22, a7->27); with hvc1 only the SEI array byte differs (offset 116, a7->27). Profile, tier, compat flags, level (120 = 4.0) and all parameter sets are equal. |
| colr | `nclx` written from the stream's colour fields (primaries 9, transfer 16, matrix 9, full_range 0). Present whether the values come from the MKV Colour element or from the bitstream VUI (hdr10_sei_only.mkv still got colr). HLG gives transfer 18. SDR H.264 gives 1/1/1. |
| mdcv + clli | written **only when the MKV Colour element carries them** (hdr10.mkv: `mdcv G=(13250,34500) B=(7500,3000) R=(34000,16000) WP=(15635,16450) max 1000 min 0.0001`, `clli MaxCLL=1000 MaxFALL=400`, values correct). **hdr10_sei_only.mkv gets neither**, although the SEI is in the stream. ffmpeg's mov muxer does not read the in-band SEI. dv81.mkv has no mdcv/clli because we gave mkvmerge no mastering values: same rule. |
| dvcC / dvvC | **not written by default.** Warning: `Not writing 'dvcC'/'dvvC' box. Requires -strict unofficial.` With `-strict unofficial`: profile 5 gives `dvcC v1.0 profile=5 level=3 rpu=1 el=0 bl=1 bl_compat_id=0`, profile 8.1 gives `dvvC v1.0 profile=8 level=3 rpu=1 el=0 bl=1 bl_compat_id=1`. FFmpeg picks the box name from the profile (<=7 dvcC, >7 dvvC), as Dolby specifies. The bytes equal the MKV BlockAdditionMapping extra data. |
| `-movflags +write_colr` | no change for MP4 (colr is already written). Irrelevant for us. |
| `-bsf:v hevc_metadata=colour_primaries=9:transfer_characteristics=16:matrix_coefficients=9` | rewrites the VUI inside the SPS (hvcC grew 2437 -> 2440 bytes) but **no colr box was written** (tested on novui.mkv). Not a way to get colr or mdcv. |
| No colour data anywhere (novui.mkv) | no colr. Output options `-color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc` with `-c copy` **do** add the colr box. There is **no command line option for mdcv/clli**. |
| Audio AC-3 / E-AC-3 | **with `empty_moov` alone the header write fails**: `Cannot write moov atom before AC3 packets. Set the delay_moov flag to fix this` (same message for EAC3). Add `+delay_moov`. Then `ac-3` + `dac3` and `ec-3` + `dec3` are written; AAC gives `mp4a`+`esds`. Both ffmpeg HLS and plain mp4 muxing need it. |
| E-AC-3 JOC flag | the muxer **has code** to write the extension byte (`flag_ec3_extension_type_a`=1 and `complexity_index_type_a`): `libavformat/movenc.c` lines 659-687 write it when the parser (`libavcodec/ac3_parser.c`, line 276) saw a JOC EMDF payload. Our synthetic E-AC-3 correctly has **no** extension bytes. **Not verified on a real Atmos stream** (none available). Apple requires `CHANNELS="n/JOC"` in the playlist and says n must equal `complexity_index_type_a` from the EC3SpecificBox, so the app has to read that value from the dec3 anyway. |
| DTS | accepted by the MP4 muxer, written as `mp4a` with an MPEG-4 `esds` (object type 0xA9). Nothing Apple lists can play it. Not useful (see spike 2: decode instead). |
| TrueHD | refused: `truehd in MP4 support is experimental, add '-strict -2'`. With `-strict -2` it writes `mlpa` + `dmlp`. AVPlayer support: none documented. Not needed: the plan is TrueHD to AC-3 core or PCM. |
| Subtitles | SRT to `-c:s mov_text` gives `tx3g` tracks and works. WebVTT (`wvtt`) in MP4 is **not supported** by the muxer ("Could not find tag for codec webvtt"). HLS subtitles are separate `.vtt` files anyway; the app already has its own subtitle renderer, so subtitles should not go through the remux. |
| Chapters | ffmpeg writes a Nero `chpl` box in `udta` **and a QuickTime text track** (`ffprobe` shows it as `bin_data`, tag `text`). The extra data track is unwanted in HLS. Use `-map_chapters -1`; read chapters from the MKV ourselves (`mkvinfo.py` shows what the EBML Chapters element looks like). |
| HLS fMP4 (`-f hls -hls_segment_type fmp4`) | works: `init.mp4` (hvc1, colr, dvvC, dac3, dec3), `seg_NNN.m4s`, `EXT-X-VERSION:7`, `EXT-X-MAP`, `EXT-X-INDEPENDENT-SEGMENTS`. The generated master playlist carries only `BANDWIDTH,AVERAGE-BANDWIDTH,RESOLUTION`: **no `CODECS`, no `VIDEO-RANGE`, no `SUPPLEMENTAL-CODECS`**, all of which Apple makes mandatory (rule 9.1 CODECS, 9.16 VIDEO-RANGE). The app has to write the playlists itself. |

Recommended copy command (video + audio, our own subtitles and chapters):

```
ffmpeg -i in.mkv -map 0:v:0 -map 0:a:N -map_chapters -1 -c copy -tag:v hvc1 -strict unofficial \
       -fflags +bitexact -movflags +frag_keyframe+empty_moov+default_base_moof+delay_moov out.mp4
# Dolby Vision profile 5: -tag:v dvh1.   Profile 8.x: keep hvc1 (+ SUPPLEMENTAL-CODECS in the playlist).
```

### 1.4 What ffmpeg does NOT do, i.e. what we write ourselves

All of this is possible without the CLI: the app will use libavformat through its C API (inside our XCFramework), so it can attach data to `AVStream.codecpar->coded_side_data` and set
`AVFormatContext.strict_std_compliance = FF_COMPLIANCE_UNOFFICIAL` (the same switch as `-strict unofficial`). That is read from the FFmpeg source and the messages above; **it was not compiled here**.

1. **mdcv/clli when the MKV has no Colour element** (common for rips that only carry SEI): parse the SEI from the first access unit (payload type 137 mastering display colour volume and 144 content light level, prefix SEI NAL type 39), then attach as `AV_PKT_DATA_MASTERING_DISPLAY_METADATA` / `AV_PKT_DATA_CONTENT_LIGHT_LEVEL` side data. Without that, ffmpeg writes no mdcv/clli (proved by hdr10_sei_only.mkv).
2. **Colour from the MKV Colour element** is already mapped by ffmpeg's matroska demuxer into colr/mdcv/clli. We only need our own fallback if both Colour and VUI are missing (then force primaries/transfer/matrix from a policy, e.g. assume BT.2020/PQ for a Main10 HDR stream only if SEI says so).
3. **dvcC/dvvC**: ffmpeg's Matroska demuxer converts BlockAdditionMapping (types `dvcC`/`dvvC`) to `AV_PKT_DATA_DOVI_CONF` (the mov muxer wrote it from our MKVs, bytes identical). For a MKV without a BlockAdditionMapping (some rips only carry the RPU in the stream) the app has to derive the config from the first RPU (profile, level, rpu_present/el_present/bl_present flags, bl_signal_compatibility_id) itself. **Not built here**; dovi_tool shows the fields exist (`dovi_tool info`). Profile 7 is the other fork's spike.
4. **Sample entry choice**: hvc1 for HDR10/HLG/DV 8.x, dvh1 for DV 5 (and 8.x if we ever want the DV-only path), never hev1/dvhe. Done through the tag.
5. **Master and media playlists**: `CODECS`, `SUPPLEMENTAL-CODECS`, `VIDEO-RANGE`, `CHANNELS`, `FRAME-RATE`, `RESOLUTION`, `BANDWIDTH`, and audio/subtitle rendition groups. Apple's examples (appendix of the HLS authoring spec): HDR10 `CODECS="hvc1.2.4.L150.B0"` `VIDEO-RANGE=PQ`; DV 8.1 `CODECS="hvc1.2.4.L150"` + `SUPPLEMENTAL-CODECS="dvh1.08.06/db1p"`; DV 8.4 (HLG base) `hvc1.2.4.L153.b0` + `dvh1.08.07/db4h` `VIDEO-RANGE=HLG`; DV 5 `CODECS="dvh1.05.06"`. The hvc1 string can be built from the hvcC (profile idc, compat flags, tier, level, constraint bytes).
6. **E-AC-3**: `CHANNELS` with `/JOC` from the dec3 `complexity_index_type_a`.
7. **Subtitles** (WebVTT segments) and **chapters** from the MKV.
8. **Segment boundaries**: `frag_keyframe` cuts at every keyframe (1 s GOPs here). Real films have 2-10 s GOPs; HLS needs a target duration and `EXT-X-INDEPENDENT-SEGMENTS`; use `-hls_time` or our own cutter.

### 1.5 Throughput (`30-throughput.sh`, 1737 MB input / 1866 s, about 7.4 Mbit/s synthetic bitstream, WSL2 ext4 disk, 6 cores)

| Run | wall | MB/s of input | CPU user / sys | peak RSS |
|---|---|---|---|---|
| fMP4 to file (3 runs) | 57.0 / 44.0 / 46.2 s | 30 / 39 / 38 | 7.2 / 5.7 / 6.9 s user, 44 / 26 / 26 s **sys** | 37-38 MB |
| fMP4 to a pipe (`-f mp4 -`, output discarded) | 8.9 s | **195** | 3.3 s user, 5.7 s sys | 37 MB |
| HLS fMP4 to disk, 6 s segments (311 files) | 61.5 s | 28 | 8.2 s user, 53 s sys | 53 MB |
| `cp` of the same file (disk baseline) | 17.9 s | 97 | 16 s sys | 2 MB |

Conclusion: the copy itself costs about 3-8 s of user CPU for 1.7 GB; the file-writing runs are dominated by system time (WSL2 virtual disk, many fragment writes), so they say little about an Apple TV's flash. The pipe number (195 MB/s, one core) is the nearest to "remux as fast as the source can be read". A 60 GB UHD remux would be disk/network bound, not CPU bound. Memory stays under 55 MB. **Apple TV A15/A17 numbers are unmeasured.**

### 1.6 What LGPL libavformat cannot do (list only, nothing built)

It is a pure demux/mux library, so on tvOS there is nothing missing at the format level. What is missing is the **build**:
- A tvOS arm64 (device) + arm64/x86_64 simulator **XCFramework** with `--disable-programs`, `--disable-gpl`, `--disable-nonfree`, the needed demuxers (matroska, mov, mpegts, avi), parsers, BSFs (hevc_mp4toannexb is not needed), protocols as a custom `AVIOContext` reading from our sources (no network protocols compiled in), and the mov/hls muxers.
- Decoders for the audio that must be decoded: `dca` (DTS core + DTS-HD extension substreams: LGPL FFmpeg decodes the **core** and the XLL lossless extension; XLL is supported in recent FFmpeg versions, to be checked against a real DTS-HD MA sample), `truehd`/`mlp`, `ac3`, `eac3`, `flac` encoder, `aac`. All are in the LGPL build used here.
- Hardware decode of video is **not** needed (AVPlayer decodes), and VideoToolbox in FFmpeg is only needed if we ever decode ourselves (we do not plan to).
- Not available in LGPL: libx264/libx265 encoders (not needed), DTS-HD *encoder*, any nonfree AAC (FFmpeg native AAC is LGPL).
- Needs Apple tooling to produce: a Codemagic/Mac build (`xcodebuild -create-xcframework`), signing, App Store license text for LGPL (dynamic framework or relinkable). Forbidden in this batch: build it.

### 1.7 Confidence

| Claim | Confidence | Why |
|---|---|---|
| LGPL ffmpeg writes correct hvcC/colr/mdcv/clli when the MKV Colour element has them | High | Parsed the output boxes with an independent parser, values equal inputs |
| ffmpeg does not write mdcv/clli from in-band SEI | High | Proven on hdr10_sei_only.mkv, 3 versions |
| dvcC/dvvC with `-strict unofficial`, content equal to the MKV mapping | High for the box; **Medium** that AVPlayer accepts our files, no device | boxes verified, playback not |
| hvc1 + `-tag:v hvc1` is the right tag | High (Apple spec rule 1.10) | document |
| DV profile 5 needs `dvh1` | Medium: Apple's example `CODECS="dvh1.05.01"`; sample entry rule is from the HLS spec text, not tested | |
| JOC flag written by ffmpeg for real Atmos | Medium-low | code read, not executed on Atmos |
| Behaviour same in 8.1 / 9.0 / master | High | diffed outputs |

### 1.8 Cannot be verified without an Apple TV (or at least a Mac with AVFoundation)

1. That AVPlayer plays these files (hvc1 + HDR10 boxes, DV 5 as dvh1, DV 8.1 as hvc1 + dvvC with SUPPLEMENTAL-CODECS) and that the TV switches into HDR10 / Dolby Vision mode.
2. Whether AVPlayer wants the `mdcv`/`clli` boxes or the in-band SEI (both are present in our HDR10 files).
3. Whether the extra `hvcC` differences (array_completeness) matter (almost certainly not).
4. That E-AC-3 JOC is passed through as Atmos over HDMI.
5. AVPlayer with HLS fMP4 delivered by our own local server (for example whether it accepts `delay_moov` init segments and 1 s fragments).
6. Real HLS segmentation limits for 4K 80 Mbps remuxes.
7. Real DTS-HD MA / TrueHD decode behaviour (no sample).

### 1.9 Recommendation

Remux with LGPL FFmpeg (libavformat API, our XCFramework) to fMP4/HLS fMP4, **copy video and AC-3/E-AC-3/AAC**, use `hvc1` (or `dvh1` for profile 5), `strict unofficial` for DV boxes, `delay_moov`, no chapters, our own subtitles. Write the SEI-to-mdcv/clli and the playlists ourselves. Decode DTS / TrueHD ourselves (spike 2). Build the XCFramework later, as a separate approved task (OPEN_QUESTIONS item 19, build step 4).

---------------------------------------------------------------------------------------------------

## Spike 2: codec for decoded DTS / DTS-HD audio (up to 7.1) that AVPlayer accepts

### 2.1 Question

DTS / DTS-HD cannot be passed through (no Apple support). The plan decodes them to multichannel PCM up to 7.1. The decoded audio still has to reach AVPlayer inside fMP4 / HLS. Which codec: ALAC, FLAC or raw PCM (`ipcm`)?

### 2.2 Apple documents read

| URL | Gist |
|---|---|
| https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices | Rule 2.2 stereo codecs include Apple Lossless and FLAC; **2.5 multichannel codecs: APAC, AAC-LC, HE-AAC, Apple Lossless, FLAC, Dolby Digital, Dolby Digital Plus, DD+ JOC**; 2.25 "container format for xHE-AAC, Apple Lossless, FLAC and APAC audio MUST be fMP4"; 2.3 stereo AAC must always exist; lossless is "a good practice to have a multichannel AAC as well". **No mention of PCM/LPCM, ipcm, sample rates, bit depth, chnl box or a maximum channel count.** |
| https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices-appendixes | CODECS strings `alac` and `fLaC` (capital L and C); the video examples for hvc1 / dvh1 / SUPPLEMENTAL-CODECS used in 1.4; tvOS: Atmos needs tvOS 12; "Multichannel output depends on the capability of the actual output device". PCM and eight channels not mentioned. |
| https://developer.apple.com/videos/play/wwdc2020/10158/ | "FLAC and Apple Lossless support up to eight channels ... 5.1 and 7.1", "AVPlayer supports all the channel configurations ... up to eight channels"; **channel order differs: ALAC centre first then L R, FLAC L R first then centre**, "you must follow these"; "carriage is restricted to the fragmented MP4 container"; only common encryption; multichannel lossless peaks about 8 Mbps at 24-bit/96 kHz six channels. |
| https://developer.apple.com/forums/thread/651588 | accepted answer (June 2020, tvOS 14 beta): "Multi-channel FLAC and ALAC are both supported on tvOS 14, iOS 14 and macOS 11." Apple engineer: "multichannel AAC is only available on macOS" (2020; not rechecked for later releases). |
| https://developer.apple.com/wwdc20/10011 (found by search, not read in full) | AVAssetWriter fMP4/CMAF output; no PCM sample entries mentioned |

I also searched for PCM in fMP4/HLS on Apple's sites (`ipcm`, `pcmC`, `lpcm`): **no Apple statement found**. FFmpeg's `ipcm` writing follows ISO/IEC 23003-5 (FFmpeg-devel patch series 2022-2023), which is an ISO format, not an Apple-documented HLS audio format.

### 2.3 What FFmpeg (LGPL master) can mux, tested (`40-audio.sh`)

7.1 24-bit 48 kHz signal, a different tone per channel, 8 channels. fMP4 with `empty_moov+delay_moov`, then decoded back with ffmpeg and compared (md5 of s32le):

| Codec | Sample entry + config | channels written | decode-back vs source |
|---|---|---|---|
| FLAC (`-c:a flac -sample_fmt s32 -strict -2`) | `fLaC` + `dfLa` | 8 (layout 7.1) | **bit-exact** |
| ALAC (`-c:a alac -sample_fmt s32p`) | `alac` | **7** (6.1(back)): the FFmpeg ALAC encoder supports only mono, stereo, 3.0, 4.0, 5.0, 5.1, 6.1(back), **7.1(wide)**; our standard 7.1 (side) input lost a channel | not equal (channel lost) |
| PCM s24le | `ipcm` + `pcmC` (0118: little endian, 24 bit) + `chnl` | 8 | bit-exact |
| PCM s16le | `ipcm` + `pcmC` | 8 | bit-exact |
| PCM f32le | `fpcm` + `pcmC` | 8 | bit-exact |
| PCM s24be | `ipcm` + `pcmC` (big endian flag) | 8 | bit-exact |
| PCM s32le | `ipcm` but labelled 24 bit | 8 | **not equal**, an FFmpeg pitfall: use s24le for 24-bit content |

All muxed into HLS fMP4 as well (`init.mp4` + segments): FLAC, ALAC and PCM s24 worked with `-hls_segment_type fmp4`.
Size for the 6 s tone (not representative of film audio): PCM s24 7.1 is 1.15 MB/s (9.2 Mbit/s) by definition, FLAC about 0.1 MB/s on a pure tone. Real film audio compresses to roughly 50-60% (typical for lossless, not measured here).
FLAC encode speed: 600 s of 7.1 pink noise in 15.8 s CPU (about 38x real time on one core of an i5-8500T). Encoding on an Apple TV is far below that cost.

Channel layout signalling in the files: PCM carries a `chnl` box with explicit speaker positions (`0,1,2,3,8,9,4,5` for 7.1 per ISO 23091-3). FLAC has **no** `chnl` box, the layout is implied by the FLAC channel order (and the dfLa/STREAMINFO channel count). ALAC from ffmpeg writes no `chan` box.

### 2.4 Recommendation

**FLAC in fMP4, 24-bit (or the source bit depth), up to 8 channels, written with ffmpeg's `flac` encoder, with `CODECS="fLaC"` in HLS.** Reasons:
1. It is on Apple's multichannel list (rule 2.5) with the exact CODECS string, and Apple states up to eight channels (WWDC20 10158) and tvOS 14 support (forum answer). PCM is in none of Apple's documents.
2. FFmpeg writes it bit-exact for the full 7.1 layout in both plain fMP4 and HLS fMP4; ALAC through FFmpeg loses a channel in the standard 7.1 layout (needs the "7.1 wide" layout) and writes no channel layout box.
3. Cost: about half the bitrate of PCM (bandwidth does not matter on a local connection, memory does), and encode is cheap.
4. Channel order: FLAC wants L R C LFE Ls Rs (side/back as FLAC orders them: FL FR FC LFE BL BR SL SR for 7.1); ffmpeg's `flac` encoder maps its layouts to the correct order. **The decoder output order of DTS must therefore go through the same channel-layout mapping**: pass layouts as FFmpeg `AVChannelLayout` (native order), never as raw interleaved guesses.

Fallback if FLAC fails on a device: ALAC with an explicit `7.1(wide)` layout (needs a remap), then PCM s24 `ipcm` (valid ISO, **not documented by Apple**). Always also offer a stereo AAC track (HLS rule 2.3) and, when an AC-3 core exists, keep it as the compatible variant.

Confidence: **Medium-high for FLAC being accepted** (documented by Apple, though the documents are 2020 session and a forum answer, and the HLS spec page), **Medium** for correct 7.1 channel placement, **Low** for PCM (undocumented).

### 2.5 Only an Apple TV can confirm (unverified)

1. AVPlayer actually plays an 8-channel FLAC fMP4 / HLS and reports 8 channels (check `AVAudioSession.currentRoute`, `maximumOutputNumberOfChannels`, `AVAudioSession.sharedInstance().outputNumberOfChannels`).
2. Correct speaker placement (channel order) for 7.1 FLAC, 6.1/5.1 variants and odd layouts (the spec says FLAC and ALAC differ).
3. The maximum channel count the HDMI route carries: what a given receiver/TV advertises (LPCM 7.1 over HDMI depends on the sink; many TVs only accept 2.0 or Dolby bitstream; Apple states that "multichannel output depends on the capability of the actual output device").
4. Whether an Apple TV re-encodes (to DD) or passes LPCM when the receiver is in "Auto" mode.
5. Whether `chnl` is needed for PCM (we do not rely on PCM).
6. Sample rates above 48 kHz and 24-bit 96 kHz (DTS-HD MA often 96 kHz): not tested here for playback; FFmpeg muxing at 96 kHz not run in this spike.
7. Gapless/seek behaviour across FLAC fragments.
8. A DTS-HD MA sample decode (needs a real file; none available here).

---------------------------------------------------------------------------------------------------

## How to re-run

All commands in WSL: `bash scripts/spikes/remux/<script>` (paths relative to the repo root). Order:
`00-setup.sh` (downloads ~600 MB), `10-generate.sh`, `20-remux.sh [all|master|9.0|8.1]`, `21-extra.sh`, `25-versions.sh`, `30-throughput.sh`, `40-audio.sh`. Python helpers (run with `python3 -I`, called by the scripts):
`mkvinfo.py file.mkv` (EBML reader), `boxes.py file.mp4` (MP4 box inspector), `cmp_hvcc.py source.mkv out.mp4`.
`env.sh` is sourced by all; tools directory override: `VP_REMUX_HOME`.

## Unverified summary / known limits of this spike

- No Apple device; no AVPlayer test. Boxes were checked with a parser written for this spike (not validated against Dolby or Apple tools). `boxes.py` is minimal (no version-1 `tkhd`, no fragments inside moof, `chnl` raw only).
- No real DTS-HD MA, TrueHD, E-AC-3 JOC sample. The synthetic `dca` stream is DTS core only.
- 4K, 60 fps, 10-bit HEVC at real bitrates were not generated; the throughput file is a 1080p synthetic loop (about 7.5 Mbit/s).
- Dolby Vision profile 7 is covered by the other spike. Profile 5 and 8.1 RPUs came from dovi_tool `generate`, so they are synthetic (valid structure, no real content).
- Source code claims about libavformat (movenc.c lines 659-687, ac3_parser.c line 276) were read from the FFmpeg master branch on GitHub at test time and are not the same revision as the BtbN snapshot.
- FFmpeg `-strict unofficial` for DV boxes is documented by the muxer's own warning; the `strict_std_compliance` API equivalent was not compiled.
