# Dolby Vision profile 7, HDR10+ and static HDR metadata

Owner: Dolby Vision work stream (2026-11-17). Covers user items 6 (profile 7 to 8.1) and 7 (HDR10+, HLG, static HDR10 metadata).
Code: `Packages/VideoPlayerCore/Sources/DolbyVisionRPU` (converter), `Sources/RemuxEngine/DynamicHDR.swift` (record, level,
NAL helpers, planner, HDR10+ detection), `Sources/RemuxEngine/Session.swift` (wiring), `Sources/AppLogic/DynamicHDRPlayback.swift`
(engine options, HDR10+ by model), `Sources/PlaybackStatus/VideoRules.swift` (status text). Tests: `scripts/test-dovi.sh`.
Device checks: `docs/DEVICE_TEST_CHECKLIST_DOLBYVISION.md`.

## 1. Result in one paragraph

A Dolby Vision profile 7 Matroska file (FEL or MEL) plays as Dolby Vision profile 8.1 on Apple TV 4K: while remuxing, each
access unit loses its enhancement-layer NAL units and its RPU is rewritten as a profile 8.1 RPU by the RPU library
(version 3.3.2, prebuilt static library, MIT); the configuration record becomes a profile 8.1 `dvvC`, the HLS variant gets
`CODECS="hvc1..."` plus `SUPPLEMENTAL-CODECS="dvh1.08.LL/db1p"`. Nothing is re-encoded, nothing is read twice, and every
access unit is converted on its own, so seeking works in any order. The status line reads
"Dolby Vision (converted from Profile 7)" with a note that says, for FEL, that the extra picture detail of the full
enhancement layer is not shown and, for MEL, that nothing is lost. When the RPU library rejects the file, the HDR10 base
layer plays and the status says "conversion failed for this file" (never a silent fallback). HDR10+ is supported by
Apple TV 4K (3rd generation) and later (the earlier "unsupported" statement was wrong); the metadata is kept in the samples
and the status text depends on the model.

## 2. How profile 7 is stored

Sources: Dolby Vision profiles and levels (Dolby, https://ott.dolby.com/OnDelKits/Dolby_Vision_Online_Delivery_Kit/v1/Documentation/Specs/Visio_Profiles/help_files/topics/c_dovi_profiles.html,
`c_dovi_levels.html`, `c_differ_mel_non.html` in the same folder), Matroska codec mappings
(https://www.matroska.org/technical/codec_specs.html, https://www.matroska.org/technical/block_additional_mappings.html),
dovi_tool / libdovi source (https://github.com/quietvoid/dovi_tool, tag `libdovi-3.3.2`, crate `dolby_vision`).

- Profile 7 is "dvhe.07", 10-bit HEVC, base layer (BL) plus enhancement layer (EL) at 1:1/4 for UHD (1:1 for FHD),
  BL signal compatibility id 6, EL carried in "Unspecified NALu" (Dolby profiles page). The BL alone is a normal HDR10
  (PQ, BT.2020) HEVC Main 10 stream.
- Single-track dual layer (what Blu-ray remuxes in Matroska and MP4 use): one HEVC track. Each access unit holds the BL
  NAL units, then the EL NAL units each wrapped in a NAL unit of type 63 (UNSPEC63, header `7E 01`), then the RPU in a
  NAL unit of type 62 (UNSPEC62, header `7C 01`) as the last NAL unit. Some muxers instead carry EL NAL units with
  `nuh_layer_id > 0`; this app treats both as enhancement layer (`DolbyVisionNAL.isEnhancementLayer`).
- Dual-track (BL and EL in separate tracks, MP4 `vdep` reference): the engine only reads Matroska and only the video
  track it selects, so a second EL track is never read; such a file plays its BL with the RPU it carries (if any).
  NOT covered as profile 7 (no such Matroska fixture exists; see OPEN_QUESTIONS rows in the report).
- RPU contents: header (profile hints, bit depths, `disable_residual_flag`), composer data (per-component mapping
  curves: polynomial or MMR, and for FEL the NLQ parameters that add the EL residual), and display management metadata
  (L1 per-shot min / mid / max, L2 trims, L5 active area, L6 MaxCLL / MaxFALL, CM v4.0 levels L3, L8 to L11, L254).
- Signalling: the Dolby Vision decoder configuration record (24 bytes: version, profile 7 bits, level 6 bits,
  rpu / el / bl present flags, compatibility id 4 bits) is a Matroska BlockAdditionMapping of type `dvcC` for profiles up
  to 7, `dvvC` for 8 to 10, `dvwC` for 11 and up; in ISO BMFF the same names are boxes inside the sample entry.

## 3. What conversion to 8.1 involves

1. Drop every EL NAL unit (type 63 or layer > 0). The BL is untouched byte for byte; parameter sets, SEI (including
   HDR10 mastering display and content light level, and HDR10+), slices and their order stay as they are.
2. Rewrite the RPU: libdovi conversion mode 2 ("to 8.1"). In the 3.3.2 source `ConversionMode::from(u8)` maps 2 (and 3)
   to `To81`, which calls `convert_to_p81_remove_mapping`: `el_spatial_resampling_filter_flag = false`,
   `disable_residual_flag = true`, NLQ data removed, partitions zeroed, the DM data's P8.1 coefficients set; for FEL the
   mapping curves are reset to identity (FEL mapping is meant to be composed with the residual), for MEL the mapping is
   kept. All dynamic metadata (L1, L2, L5, L6, L8 ...) is kept frame by frame. The header comment of
   `dovi_convert_rpu_with_mode` lists an older numbering (4 = "preserve mapping"); the code is what runs, and the tests
   compare against `dovi_tool -m 2 convert --discard`, which uses the same code path.
3. Rewrite the codec configuration: `dvcC` profile 7 becomes `dvvC` profile 8, same level, `rpu=1 el=0 bl=1`,
   compatibility id 1 (`MKVDolbyVisionMapping.profile81()`). The `hvcC` is unchanged (it only ever held the BL parameter
   sets). Sample entry stays `hvc1` (HLS authoring spec 1.10: prefer `hvc1`/`dvh1`; with an HDR10-compatible BL, `hvc1` +
   `dvvC` lets every player fall back to HDR10).
4. HLS signalling (HLS authoring specification for Apple devices, rev. 2025-06-26, section on SUPPLEMENTAL-CODECS):
   `CODECS="hvc1.2.4.L150.."`, `SUPPLEMENTAL-CODECS="dvh1.08.LL/db1p"`, `VIDEO-RANGE=PQ`.
5. A file without any record (old muxers): the record is derived from the first RPU (profile from the RPU, level from
   picture size and frame rate per Dolby's level table, compatibility 6 for profile 7) and the session logs it
   (PROVISIONAL; alternative: play such files untouched).

## 4. MEL, FEL, what is lost, and why nothing higher is feasible

- MEL (Dolby, `c_differ_mel_non.html`): the EL carries no picture information (NLQ offset 0, `vdr_in_max` 1, all other
  NLQ values 0); composing it is the same as mapping the BL. Converted to 8.1 with the mapping kept: nothing is lost.
- FEL: the EL carries a residual (1/4 area for UHD) that, added through the NLQ step, reconstructs a 12-bit signal.
  Converting to 8.1 drops that residual: the BL (10-bit) plays with the per-shot dynamic metadata. What is lost is the
  residual detail; how visible it is depends on the title and is not measured here.
- Keeping more of the EL on Apple TV would mean decoding the EL (a second HEVC decode, 1920x1080 for UHD) and composing
  BL + mapped EL per pixel (libplacebo 7.387.0 added FEL composition on the GPU; AviSynth MapNLQ does it on the CPU and
  outputs 12-bit). The result is uncompressed pixels. On Apple TV, Dolby Vision output is only produced by the system
  player from a compressed Dolby Vision stream (profile 5 or 8.1 per Apple's specs); an app that renders its own pixels
  can output HDR10 at best (10-bit, static metadata), which loses the dynamic metadata that 8.1 keeps, and re-encoding the
  composed picture back to 8.1 is a lossy encode (forbidden by the no-re-encode rule) and is far beyond real time on
  Apple TV's video encoder at 4K. So "8.1 from the BL plus the converted RPU" is the highest quality Apple TV can show
  for profile 7. This is a hard device limit, not a choice for ease.
- Cost of the chosen conversion (WSL x86-64, see section 8; Apple TV not measured): tens of microseconds per frame for
  the RPU, plus one copy of the access unit; under 1% of one core at 24 or 60 fps.

## 5. Which Apple TV models play what (read 2026-11-17)

| Model | Video formats on Apple's page | Page |
|---|---|---|
| Apple TV HD | SDR only (HDMI 1.4) | https://support.apple.com/en-us/111928 |
| Apple TV 4K (1st gen) | "HEVC Dolby Vision (Profile 5)/HDR10 (Main 10 profile) up to 2160p"; no HLG, no HDR10+ | https://support.apple.com/en-us/111929 |
| Apple TV 4K (2nd gen) | "HEVC Dolby Vision (Profile 5)/HDR10 (Main 10 profile)/HLG up to 2160p, 60 fps"; no HDR10+ | https://support.apple.com/en-us/111922 |
| Apple TV 4K (3rd gen) | "Dolby Vision (Profile 5) up to 2160p, 60 fps"; "HDR10+/HDR10/HLG with HEVC (Main 10 Profile) up to 2160p, 60 fps" | https://support.apple.com/en-us/111839 |
| Apple TV 4K (current, 4th gen) | "Dolby Vision (Profile 8.1 and 5), HDR10, HDR10+, HLG"; AV1, VP9, HEVC, H.264 up to 2160p60 | https://www.apple.com/apple-tv-4k/specs/ |
| All 4K models | "HDR10+ is a supported format only on Apple TV 4K (3rd generation) and later." | https://support.apple.com/en-us/102339 |

Profile 8.1 is named only on the newest page; earlier pages name profile 5 only, while the HLS authoring spec documents
8.1 (`dvh1.08.xx/db1p`) for Apple devices. Whether profile 8.1 plays as Dolby Vision on 2nd and 3rd generation through
this remux path is the first device check (DEVICE_TEST_CHECKLIST_DOLBYVISION.md, DV-1).

## 6. How the conversion gets onto tvOS: option (i), a prebuilt library

Chosen: **(i) the prebuilt tvOS build of libdovi 3.3.2 from the public release below**, re-packaged
unchanged as `Packages/VideoPlayerCore/Frameworks/DolbyVisionRPULib.xcframework` (static libraries, no C or Rust compiled
by the app build). Licence: MIT, `Frameworks/DolbyVisionRPULib-LICENSE.txt` (copied from the 3.3.2 source, sha256
f35d4515dd8d81c7996af2b20e9605561d1af0c21bc12ba7cc4fa4c60aed2178).

Provenance:
- Download: https://github.com/mpvkit/libdovi-build/releases/download/3.3.2/Libdovi.xcframework.zip, 11,443,744 bytes,
  sha256 e693e239808350868e79c5448ef9f02e2716bc822dd8632a41a368a1eae5ca7d.
- Checked before use: static `ar` archives; tvOS device slice arm64 + arm64e (LC_VERSION_MIN_TVOS 10.0 in all 108
  members), simulator slice arm64 (minos 14.0) + x86_64; header `rpu_parser.h` version 3.3.2, identical in every slice;
  21 `dovi_*` symbols exported; undefined symbols are libSystem only (no extra linker settings).
- Re-packaged as a library-style xcframework (the original is framework-style with symlinks and a MinimumOSVersion
  100.0 plist that does not apply to static archives). Binaries byte-identical: tvOS device libdovi.a sha256
  0ec9427ca1a71efe893cc1de25f50a6f8a0f9793ec7a6379597bd5138644b156 (6,000,184 bytes), simulator
  8a7fd61d11c7c803bc3da185c5b84380f6961e46d996a9e94cab9efb8b7ca7b2 (5,943,128), macOS
  434ebd779549a96cab93818189ae8293dd99b31b0081334c1f2baa538c829bf9 (6,059,552).

Why not the others:
- (ii) building it in a free GitHub Actions workflow and committing the result gives the same binary class with an extra
  workflow to own; it is only needed if the published build disappears or a newer version is required. Not chosen; no
  workflow added.
- (iii) a Swift port tested byte-for-byte: the RPU format has many versions and DM levels; a port means re-implementing a
  bit-exact parser / writer (with CRC and emulation prevention) and would have to track upstream. More risk, no quality gain.

Linux tests use the same version built from source (`scripts/test-dovi.sh`, systemLibrary `CDolbyVisionRPU` with
pkg-config `vp-dovi`, enabled by `VP_LIBDOVI`). The Apple build uses `.binaryTarget(DolbyVisionRPULib)` + the C module
`CDolbyVisionRPU` (umbrella header only).

Risk (cross-agent): this is a Rust static library. If another target ever links a second Rust static library or
another copy of the same library (for example one bundled with the fallback player's frameworks), duplicate symbols (`rust_eh_personality`, `dovi_*`) are possible at link time. Reuse this
target instead of adding another copy. NOT compiled for tvOS in this run (no Mac); the link is checked by the first CI build.

## 7. Engine behaviour

- On the fly, no extra read: the converter works on the frame bytes the demuxer already read for the segment
  (`Session.videoSamples`); the test `testSeekingInAnyOrderGivesTheSameBytesAndNoExtraReads` checks that the bytes read
  with and without conversion are equal.
- Seeking: no state between access units; segments fetched in reverse order equal segments fetched in order (tested).
- Decided once per file from the record and the first keyframe (`DolbyVisionPlanner`): profile 7 with converter: the first
  keyframe is converted as a probe; if the library rejects it the file plays its HDR10 base layer and the status says
  "conversion failed for this file". Profile 5 and 8.x files are left byte for byte, except that a profile 8 file whose
  access units carry an enhancement layer (a profile 7 section spliced in) has exactly those access units converted.
- Files whose profile switches mid-stream: a profile 7 file whose later access units are profile 8.1 has every access
  unit passed through mode 2 (as the reference tool does); a profile 8 file with profile 7 sections converts only the
  sections with EL NAL units. When the record says profile 8 but the first keyframe's RPU is profile 7 (the remux spike's mkvmerge wrote
  a `dvvC` profile 8 record for the FIXTURE `p7_switch` file, which starts with profile 7 FEL), the stream wins and the
  file is converted as profile 7 (PROVISIONAL; alternative: trust the record and convert only access units with EL NAL
  units, which gives the same bytes but would not say "converted from Profile 7"). Both paths are tested.
- Per-scene RPU handling: every access unit keeps its own RPU, converted individually; the per-shot L1 / L2 / L8
  metadata and scene-cut flags are not merged, repeated or dropped.
- One rejected RPU in the middle of a file: that one frame keeps its base layer without RPU (PROVISIONAL; alternative:
  repeat the previous converted RPU, which would make a sample depend on the one before it). Counted in
  `DolbyVisionProfile7Converter.stats`.
- CPU: see section 8.

## 8. Tests and what they prove

`bash scripts/test-dovi.sh` (also stage `dovi` of `scripts/test-all.sh`): builds libdovi 3.3.2 from the official tag,
fetches dovi_tool 2.3.4 (release binary, sha256 1844258e13c26607b32224bf1fa82b595d3b35949f5467405fda560daad32b3f),
generates FIXTURE streams and runs `DolbyVisionRPUTests` and `DynamicHDRPlaybackTests` with the library linked.

FIXTURE streams (synthetic, never real content, `~/vp-dovi/media`, 96 frames, 24 fps): BL 1280x720 HDR10 (x265, test
encoder of the remux spike, never shipped) and EL 640x360; RPUs written by `scripts/dovi/fixturegen` with the libdovi
crate (FEL: CM v2.9, three shots, an edit, L5 / L6, NLQ; MEL: CM v4.0; 8.1); `dovi_tool inject-rpu` + `mux` give
single-track dual-layer profile 7 FEL and MEL streams (EL NAL units in UNSPEC63); `p7_switch` is FEL for 48 frames then
8.1; Matroska files by mkvmerge; references by `dovi_tool -m 2 convert --discard`.

| Check | Where | Result |
|---|---|---|
| Every access unit equals the reference tool's output, NAL for NAL (FEL, MEL, switching) | NativeConversionTests | passed 2026-11-17 |
| FEL / MEL read from the RPU; converted RPU reads back as profile 8 | NativeConversionTests | passed 2026-11-17 |
| Whole remux: `dvvC` profile 8 level kept, no `dvcC`, SUPPLEMENTAL-CODECS `dvh1.08.LL/db1p`, slices + RPU equal the reference | SessionConversionTests | passed 2026-11-17 |
| Seeking out of order gives identical segments; no extra bytes read | SessionConversionTests | passed 2026-11-17 |
| Profile 8.1 file left byte for byte | SessionConversionTests | passed 2026-11-17 |
| Independent reader: ffprobe (LGPL build) reports DOVI record profile 8, el 0, bl 1, compat 1, and per-frame RPU with `disable_residual_flag` 1 | SessionConversionTests | passed 2026-11-17 |
| NAL rewriting, errors, counters, thread safety (fake codec, no library) | Profile7ConverterTests | runs everywhere |
| Record bytes, levels, EL detection, base-layer-only fallback, HDR10+ SEI detection, planner | RemuxEngineTests/DynamicHDRTests, SessionTests | runs everywhere |
| Status text: FEL / MEL notes, HDR10+ by model | PlaybackStatusTests, AppLogicTests | runs everywhere |

CPU cost (printed by `testConversionCostPerVideoSecond` as `DOVI-COST:`), WSL x86-64, 2026-11-17, two runs: 19.7 to
33.4 µs per access unit (720p FIXTURE, NAL rewrite + RPU) and 12.3 to 14.9 µs per RPU alone, so 0.47 to 0.80 ms of CPU
per video second at 24 fps and 1.2 to 2.0 ms at 60 fps (the copy grows with frame size; the RPU part does not). The earlier
spike measured 11 µs per RPU and 89 µs per 4K access unit including the copy (docs/spikes/DOLBY_VISION_P7.md), about
0.3 ms of CPU per video second at 24 fps on x86-64. Apple TV's CPU is not measured (device check DV-6).

Only on a real Apple TV (not provable in WSL): that tvOS plays the remuxed 8.1 stream in Dolby Vision mode; that the TV
reports Dolby Vision; picture correctness of FEL conversion; behaviour with a rejected RPU frame; HDR10+ reaching an
HDR10+ TV; frame pacing under conversion load. See the device checklist.

## 9. HDR10+, HLG and static HDR10 metadata (item 7)

- Finding: support.apple.com/102339 "HDR10+ is a supported format only on Apple TV 4K (3rd generation) and later";
  111839 lists "HDR10+/HDR10/HLG with HEVC (Main 10 Profile) up to 2160p, 60 fps"; the 4th generation specs list HDR10+.
  1st and 2nd generation pages do not list HDR10+. The earlier statement "Apple TV does not report HDR10+ output, so this
  plays as HDR10" is corrected in VideoRules and docs/PLAYBACK_STATUS.md.
- Kept through the remux: HDR10+ is an ST 2094-40 `user_data_registered_itu_t_t35` prefix SEI (payload type 4,
  header B5 00 3C 00 01 04) inside each access unit; the engine copies those NAL units unchanged (the converter and the
  base-layer fallback keep every SEI). The engine detects it on the first keyframe (`HDR10Plus.present`), sets
  `RemuxMediaInfo.hasHDR10PlusMetadata`, and for a PQ variant without Dolby Vision adds `SUPPLEMENTAL-CODECS="<codecs>/cdm4"`
  (the HLS authoring spec documents the `cdm4` brand for HDR10+; its example is AV1, the HEVC use is PROVISIONAL;
  alternative: no SUPPLEMENTAL-CODECS for HEVC). Matroska's own HDR10+ BlockAdditional (BlockAddIDValue 4) is not
  copied into the samples (PROVISIONAL; such files are rare, the SEI in the stream is the common case).
- Status text: model from `uname` machine (AppleTV14,1 and later: yes; AppleTV5,3 / 6,2 / 11,1: no; others unknown,
  PROVISIONAL for unknown future identifiers). Yes: "HDR10+ or HDR10" and a note that Apple TV sends the metadata when
  the display supports it but does not report whether the display uses it. No: "HDR10" and "This Apple TV model does not
  support HDR10+, so this plays as HDR10." Unknown: "HDR10" and "The app could not tell whether this Apple TV model sends
  HDR10+ metadata, so this is shown as HDR10." No API reports HDR10+ (AVPlayer HDR modes are HLG, HDR10, Dolby Vision).
- HDR10 `mdcv` / `clli`, HLG, and Dolby Vision profiles 5 and 8.x are left as they were (tests:
  `testPlannerKeepsProfile5And8Untouched`, `testProfile81FileIsLeftByteForByte`, existing HDR static metadata tests).
