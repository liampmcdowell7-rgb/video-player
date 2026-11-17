# Prebuilt LGPL FFmpeg for tvOS: candidates (batch 2, item D1)

Status: research only. Nothing in the app or the Swift package was changed. Date of research: 2026-11-17 (the project's current date).
Goal: link FFmpeg into the tvOS app **without compiling any C on Codemagic** (18 free macOS minutes remain this month, see OPEN_QUESTIONS R45).

How to read the evidence labels:
- **VERIFIED (file)**: I downloaded the binary or source from the official GitHub release page / tag and read it in WSL (`strings`, `file`, `llvm-objdump`, the build record inside the package).
- **VERIFIED (page)**: read on the project's own GitHub page or GitHub API response (primary source, but not checked against the binary).
- **UNVERIFIED**: from a search-result snippet, inference, or not checkable without a Mac / Apple TV. Every such claim is marked.

Nothing was linked, compiled for tvOS, or run on a device. No Mac was available.

## 1. Downloads made (all into `~/vp-ffmpeg-research` in WSL, from the official GitHub release/tag pages)

| Item | Version / tag | Size (bytes) | sha256 |
|---|---|---|---|
| MPVKit `Libavformat.xcframework.zip` | release 1.1.0-n9.0.2 (prerelease, 2026-10-07) | 14,016,159 | 0a840424d7a2d971687d6e96d995e21420cce1b27dae74687ff4f5f31dc36e73 |
| MPVKit `Libavcodec.xcframework.zip` | same | 58,338,939 | d516e904490c711c2875dd238d7d8d9f4f46e335829cb8ee7e0e1623e952e372 |
| MPVKit `Libavutil.xcframework.zip` | same | 8,103,205 | 0ca518d2a3eab22763310d8bcdc977494ddb3daf3dc3b73a2ed84c5eefc13f75 |
| MPVKit `Libswresample.xcframework.zip` | same | 819,045 | 49edabb3c2e7fb97e6458f2e6a2fea66ab567b55258141e598fecfcd29cd9eeb |
| MPVKit `Libavfilter.xcframework.zip` | same | 6,150,849 | e764dc3b3d36abb26d6d0ae2f0c6a1de0b80a453f3ca4bf2bb6596c0f6464b19 |
| MPVKit `Libswscale.xcframework.zip` | same | 7,368,238 | 5aebc8107219d518d8e89f0af97365ff9758f91b3096a7d5c1a16e092745de39 |
| FFmpegBuild source tarball (contains the xcframeworks) | tag 3.15.0 (commit d445e6daa180db73f12d47606a00c914f682e278, 2026-11-12) | 68,922,502 | 78461aea6737d2284314f6ee8d615c157b3458d2a2b52ab5138345086b25f6a3 |
| mpvkit/libdovi-build `Libdovi.xcframework.zip` | release 3.3.2 (2025-12-22) | 11,443,744 | e693e239808350868e79c5448ef9f02e2716bc822dd8632a41a368a1eae5ca7d |

The MPVKit checksums equal the ones in MPVKit's own `Package.swift` (VERIFIED (file) against VERIFIED (page)).
The six MPVKit zips are the LGPL builds. The `-GPL` zips were not downloaded.

## 2. Comparison table

| | **FFmpegBuild** (superuser404notfound) | **MPVKit** FFmpeg xcframeworks (LGPL product) | thalesfp/ffmpegkit-apple | arthenica/ffmpeg-kit | kingslay/FFmpegKit | need4swede/ffmpeg-build | vvisionnn/swift-ffmpeg | tylerjonesio/SwiftFFmpeg |
|---|---|---|---|---|---|---|---|---|
| Licence of the FFmpeg build | **LGPL-2.1-or-later**; no `--enable-gpl`, no `--enable-version3`, no nonfree. VERIFIED (file: BUILD-INFO.txt configure line has none of them; LICENSES/README.md) | **LGPL-3.0** (`--enable-version3`, `CONFIG_GPL 0`, `CONFIG_NONFREE 0`). VERIFIED (file: config.h, configure string). The separate `-GPL` zips and the `MPVKit-GPL` product are GPL: do not use | LGPL (wrapper LGPL-3.0, FFmpeg "LGPL 2.1 or later", no GPL components). VERIFIED (page only) | LGPL-3.0 by default; `-gpl` packages are GPL-3.0. VERIFIED (page) | **free build is GPL**; LGPL only as a paid build from the author. VERIFIED (page) | LGPL-3.0 (fork of mpvkit/ffmpeg-build; GPL with a flag). VERIFIED (page) | not determined | wrapper only; needs a separate FFmpeg xcframework. VERIFIED (page, via search snippet: UNVERIFIED detail) |
| GPL / nonfree libraries inside | none (dav1d BSD-2, zimg WTFPL, libzvbi LGPL with 3 GPL-2 source files removed by `build.sh`). VERIFIED (file) | FFmpeg deps include gnutls (LGPL-2.1+), nettle/gmp (LGPL/GPL-dual: UNVERIFIED which licence option), libass (ISC), libplacebo (LGPL-2.1), dav1d, libuavs3d (UNVERIFIED licence). No libx264/libx265 (`CONFIG_LIBX264 0`, `CONFIG_LIBX265 0`). VERIFIED (file) for the flags, UNVERIFIED for dependency licences | OpenSSL, zlib, bzip2, libiconv (page) | n/a | GPL libs | n/a | n/a | n/a |
| tvOS slices | `tvos-arm64` (device) and `tvos-arm64_x86_64-simulator`. VERIFIED (file). Also ios, visionOS, macOS | `tvos-arm64_arm64e` (device) and `tvos-arm64_x86_64-simulator` (the simulator slice holds x86_64 + arm64). VERIFIED (file) | tvOS arm64 + arm64 simulator (no x86_64). VERIFIED (page) | tvOS present historically | tvOS (page) | tvOS stated, slices not listed | **no tvOS** (README says it does not claim tvOS). Rejected | depends on another package |
| Libraries included | libavformat, libavcodec, libavutil, libswresample, libswscale, trimmed libavfilter; separate dav1d, zimg, libzvbi; **no libavdevice**. VERIFIED (file) | libavformat, libavcodec, libavutil, libswresample, libswscale, libavfilter, libavdevice (stub, 112 KB) as separate zips; the umbrella `_FFmpeg` target also pulls libass, freetype, fribidi, harfbuzz, libplacebo, MoltenVK, shaderc, lcms2, dav1d, uavs3d, libdovi, gnutls, nettle, hogweed, gmp, OpenSSL (Package.swift). VERIFIED (page) | FFmpegKitNext 8.1.1 wrapper (includes FFmpeg API and the `ffmpeg`-style execute API); component list not shown | n/a | FFmpeg + libmpv | not shown | n/a | n/a |
| Matroska demux | yes (`--enable-demuxer=matroska`, plus 4 local patches for byte-seek and attachment skipping). VERIFIED (file) | yes (`matroska` demuxer). VERIFIED (file) | not shown (UNVERIFIED) | | | | | |
| MP4 / fragmented MP4 mux | muxers enabled: `mp4`, `mov`, `hls`. Strings in libavformat contain `delay_moov`, `empty_moov`, `frag_keyframe`, `default_base_moof`, `cmaf`. VERIFIED (file). No `dash`, no `matroska` muxer | muxers enabled: `mp4`, `mov`, `dash`, `flac`, `hevc`, `m4v`, `matroska`, `mpegts`, `webm*`; **no `hls` muxer** (we write our own playlists anyway). Same fragment option strings. VERIFIED (file) | not shown | | | | | |
| `hvc1` / `dvh1` tags, `-strict unofficial` dvcC/dvvC | libavformat strings contain `dvcC`, `dvvC`, `dvh1`, `hvc1` and "Requires -strict ..." (the same movenc as the spike). VERIFIED (file: strings only; muxing not run on tvOS) | same strings. VERIFIED (file: strings only) | not shown | | | | | |
| Decoders needed | **DTS (`dca`, incl. XLL = DTS-HD MA with a patch adding DTS:X heights), TrueHD, MLP, AC-3, E-AC-3, FLAC, ALAC, AAC, PCM variants, PGS (`pgssub` with a patch), SRT/ASS/WebVTT, H.264, HEVC, AV1 (dav1d), VP9**. VERIFIED (file: configure line) | **`dca`, `truehd`, `ac3*`, `eac3*`, `flac`, `alac*`, `aac*`, `pcm*`, `pgssub`, srt/ass/webvtt, h264, hevc, vp9, av1 + libdav1d**. VERIFIED (file) | not shown | | | | | |
| Encoder needed for the DTS repackaging (FLAC) | **`flac`**, plus `eac3`, `aac`, `alac`. VERIFIED (file) | **`flac`**, `alac`, `aac`, `pcm*`, plus VideoToolbox encoders. VERIFIED (file) | not shown | | | | | |
| Bitstream filters | configure has **`--disable-bsfs`**: `movenc` refers to `aac_adtstoasc` and `hevc_mp4toannexb`-style filters by name (strings are present), so remuxing sources that need them (AAC in ADTS from MPEG-TS) may fail at runtime. UNVERIFIED consequence; MKV and MP4 inputs do not need them | `--enable-bsfs` (all present: `aac_adtstoasc`, `dca_core`, `eac3_core`, `truehd_core`, `extract_extradata`, `hevc_mp4toannexb`). VERIFIED (file) | | | | | | |
| Network / protocols | `--disable-network`, protocols `file`, `pipe`, `data` only: fine, we supply bytes through a custom AVIO callback. VERIFIED (file) | network + TLS (gnutls) compiled in, we would not use it, but the libraries are then required to link (UNVERIFIED which of them a minimal link needs) | OpenSSL | | | | | |
| Size, tvOS device slice | libavcodec 6.1 MB, libavformat 1.1 MB, libavutil 0.76 MB, libswresample 0.14 MB, libswscale 1.1 MB, libavfilter 0.5 MB, dav1d 0.83 MB, zimg 0.3 MB, libzvbi 0.5 MB = **about 10.5 MB** (README says "~10 MB per architecture"). VERIFIED (file). Whole repo is **404 MB** on GitHub because the xcframeworks for all platforms are committed. VERIFIED (page: API `size`) | static archives inside a fat file: libavcodec 21.3 MB, libavformat 5.2 MB, libavutil 2.3 MB, libswresample 0.28 MB for the device slice (these are linker input; the final executable is smaller after dead-stripping, UNVERIFIED how much). Release zips: avcodec 58 MB, avformat 14 MB, avutil 8 MB, swresample 0.8 MB, swscale 7.4 MB, avfilter 6 MB, `FFmpeg-all.zip` 91 MB. VERIFIED (file/page). MPVKit repo itself is 873 KB | not stated | | | | | |
| Linking | **dynamic frameworks** (`MH_DYLIB`, install name `@rpath/AetherLibavformat.framework/...`), static variant only via `./build.sh static`. VERIFIED (file: `file`, LC_ID_DYLIB) | **static** (each `.framework` binary is an `ar` archive inside a fat Mach-O). No dynamic variant is published. VERIFIED (file) | "Dynamic frameworks" (page) | XCFrameworks (page) | | | | |
| How consumed | SwiftPM package URL + `exact:` version; binary targets are **local `path`** xcframeworks committed in the repo (no url/checksum). Product `AetherFFmpegBuild`. VERIFIED (file: Package.swift) | each library is a `binaryTarget` with `url` + `checksum` (release assets); we can reference the zips directly without depending on the MPVKit package (VERIFIED (page): that is how MPVKit's own Package.swift does it) | SwiftPM, `exact: "8.1.1"`, binary targets with checksums (page) | CocoaPods/Maven/SPM historically | SwiftPM branch main | SwiftPM / `make build` | | |
| FFmpeg version | **n8.1.3** + 12 local patches (listed in README; BUILD-INFO.txt) | **n9.0.2** (unpatched as far as I read; UNVERIFIED) | 8.1 via FFmpegKitNext v8.1.1 | 6.0 (2023) | 5.1 badge (UNVERIFIED) | not stated | | |
| Min OS | built `-target arm64-apple-tvos16.0`; Mach-O `LC_BUILD_VERSION` **minos 16.0**, sdk 27.2; BUT the framework `Info.plist` says `MinimumOSVersion 26.0` for the tvOS slice. VERIFIED (file); effect on App Store validation UNVERIFIED (see section 6). Package.swift: tvOS 16 | Package.swift: **tvOS 15**; the framework `Info.plist` says `MinimumOSVersion 100.0` (placeholder, UNVERIFIED effect) | tvOS 18.0 (page) | n/a | n/a | n/a | n/a | n/a |
| Last release / activity | 3.15.0 on **2026-11-12**; releases every few days since 2026-11-01; repo created 2026-04-12; pushed 2026-11-16; 10 stars. Releases carry no assets (xcframeworks live in git). VERIFIED (page: GitHub API) | 1.1.0-n9.0.2 prerelease **2026-10-07**, 1.0.0 2026-07-25; repo pushed 2026-11-09; 214 stars; the README says "won't be maintained too frequently" and recommends a different, separately maintained engine for production. VERIFIED (page) | 2 commits, no release dates visible; 0 stars | **archived, retired**; last native release 6.0 (Aug 2023); pushed 2026-07-02. VERIFIED (page: GitHub API `archived: true`) | no releases shown | forks, no releases | n/a | n/a |
| Verdict | **Primary candidate** | **Fallback candidate** | not enough information, 2 commits: skip | rejected (archived) | rejected (GPL) | rejected (no releases, no component list) | rejected (no tvOS) | not a binary source |

TheFireKahuna/FFmpegBuild is a fork of superuser404notfound/FFmpegBuild with the same README (VERIFIED (page)): use the original.
A playback engine built on FFmpegBuild by the same author also exists (prior art, not a candidate: we are writing our own engine). It is not named here under the names rule (OPEN_QUESTIONS R107: no mention of other media-player applications).

## 3. What the two serious candidates actually contain (read from the binaries)

Both are FFmpeg libraries built with `--disable-programs --disable-doc --disable-devices`. Everything below was read from the configure line embedded in the package.

| Need from the engine design | FFmpegBuild 3.15.0 (n8.1.3) | MPVKit 1.1.0-n9.0.2 |
|---|---|---|
| Open MKV from our own byte-range reads (custom AVIO) | matroska demuxer, `file`/`pipe`/`data` protocols; custom `avio_alloc_context` is core API | matroska demuxer, all protocols |
| Write fragmented MP4 with `hvc1`, hvcC, colr, mdcv/clli | `mp4`, `mov` muxers, movenc strings present | `mp4`, `mov` muxers, movenc strings present |
| Dolby Vision `dvcC`/`dvvC`, `dvh1` | strings present for `dvcC`, `dvvC`, `dvh1`; needs the runtime option the spike used (`strict unofficial`); not exercised | same |
| Decode DTS / DTS-HD MA | `dca` (+ local XLL height patch) | `dca` |
| Decode TrueHD (core and MLP lossless) | `truehd`, `mlp` | `truehd` |
| Re-encode to FLAC / ALAC for AVPlayer | `flac`, `alac`, plus `eac3`, `aac` encoders | `flac`, `alac`, `aac` |
| E-AC-3 / AC-3 / AAC passthrough | decoders and muxer support | same |
| PGS subtitles | `pgssub` decoder (+ patch for damaged display sets), `sup` demuxer | `pgssub` decoder |
| HLS playlist writing | has an `hls` muxer (we do not need it: our engine writes playlists) | no `hls` muxer |
| Bitstream filters | **disabled** | enabled |
| Hardware | VideoToolbox, AudioToolbox | VideoToolbox, AudioToolbox, Vulkan/MoltenVK, libplacebo (not needed for remux) |
| Software video decoders (not needed for the remux path) | AV1 (dav1d), VP9, VP8, MPEG-2/4, VC-1, WMV, FLV, VP6 | AV1, VP9, MPEG-2/4, VC-1, WMV, FLV, VP6, RealVideo, ProRes, ... |

Local patches in FFmpegBuild that matter to us (README, VERIFIED (file)): `movenc_fragment_end` (stops a process abort when a fragment is flushed with a packet still in the interleaver), `eac3_dec3` (builds the `dec3` box for Atmos E-AC-3 with a dependent substream), `dav1_tag` (AV1 Dolby Vision profile 10 sample entry), matroska byte-seek and attachment-skip patches, `dca_x_heights` (opt-in), `pgssub` clearing subtitles. None of them has been run by me.

## 4. Recommendation (confidence in brackets)

1. **Use FFmpegBuild (superuser404notfound) pinned to an exact tag, currently `3.15.0` = commit `d445e6daa180db73f12d47606a00c914f682e278`, for the remux engine.** [medium-high that it is the right binary to build on; medium that it links and runs on tvOS, because nothing was linked]
   Reasons, all VERIFIED (file) unless marked:
   - It is the only candidate that is **dynamic** and **LGPL-2.1-or-later without `--enable-version3`**. LGPL-2.1 section 6 is satisfied by dynamic linking alone, and the closed/open status of our app does not matter; LGPL-3.0 adds installation-information terms that Apple signing makes hard to meet (UNVERIFIED legal reading, not advice).
   - Its feature set is nearly exactly the remux engine's: matroska in, mp4/mov/hls out, flac/alac/eac3/aac out, dca/truehd/mlp/ac3/eac3 in, pgssub, no network stack, about 10.5 MB for the device slice.
   - It is actively maintained (release 3.15.0 on 2026-11-12).
2. **Keep MPVKit as the fallback**, and as the planned fallback *playback* engine (BUILD_ORDER step 8). Its FFmpeg zips can be referenced directly as `binaryTarget(url:checksum:)` from our own Package.swift, so no clone of a large repository is needed. [medium]
3. **Do not put both in one executable unless one of them is isolated** in its own dynamic framework: FFmpegBuild's README says a *static* FFmpeg in the same executable wins symbol resolution for everything linked beside it (MPVKit is static). [from the README, UNVERIFIED by a link]
4. libdovi: use the prebuilt `Libdovi.xcframework` 3.3.2 (section 7). [medium-high]

### Risks to settle before committing to FFmpegBuild
| Risk | Why | How to settle |
|---|---|---|
| Young, single maintainer | repo created 2026-04-12, 10 stars, 1 main author (VERIFIED (page)) | pin the tag, keep our own copy of the three tvOS slices (about 25 MB zipped, UNVERIFIED size) as a GitHub release asset of our own repo so a deleted upstream cannot break builds; keep MPVKit as fallback |
| 404 MB repository clone | the xcframeworks of all platforms are committed in git history (GitHub API `size` 403,758 KB). SwiftPM resolving this package clones the whole repository: this could cost several of the 18 remaining minutes (UNVERIFIED, not measured) | vendor only the tvOS slices (device + simulator) of the 6 libraries into our own `binaryTarget(url:checksum:)` zip; do not depend on the upstream package at build time |
| `--disable-bsfs` | `movenc` adds bitstream filters by name for some inputs (`aac_adtstoasc` for ADTS AAC). Names are present in the binaries, but whether the filters are compiled in could not be checked without running it on a Mac | when the engine is first run on a Mac or device, remux an MPEG-TS file with ADTS AAC; MKV/MP4 sources are unaffected (UNVERIFIED) |
| Framework `Info.plist` `MinimumOSVersion 26.0` on the tvOS slice while the Mach-O says minos 16.0 | App Store validation checks embedded frameworks; our app targets tvOS 18 (R32). If the plist value is enforced, the upload is rejected (UNVERIFIED either way) | the vendored copy can rewrite the plist value to 16.0 (the build record shows the library itself was built for tvOS 16); test at the first TestFlight upload |
| Dolby Vision boxes | strings exist, but `dvcC`/`dvvC` need the runtime option `strict unofficial`; whether it can be set through the libavformat API the engine uses (not the CLI) was not exercised | first Mac run: mux the DV test files from `scripts/spikes/remux` with the API option and check the boxes |
| E-AC-3 JOC (Atmos) | the spike could not test real Atmos; FFmpegBuild has a `dec3` patch for it | device checklist item |

## 5. LGPL obligations (what we must do, per option)

Not legal advice; this is the project's reading of the licence texts shipped with the packages (VERIFIED (file) for what the packages say, UNVERIFIED for how a court or Apple would read it).

**If FFmpegBuild (LGPL-2.1-or-later, dynamic frameworks):**
1. Keep the frameworks as separate dynamic frameworks embedded in `App.app/Frameworks/`; do not merge them into the app binary (no "mergeable library" settings). (README, "Shipping in an App Store app")
2. Reproduce the licence texts from its `LICENSES/` folder in the app (Settings > About > Acknowledgements screen) and in the repository: LGPL-2.1 text, dav1d BSD-2-Clause, zimg WTFPL, libzvbi LGPL-2.1 and MIT (`ure.c`).
3. State that the app uses FFmpeg and name the exact source: link to the tagged release `3.15.0` of the package and (because it patches FFmpeg) the patch files. FFmpeg's own source for n8.1.3 is the upstream tag `n8.1.3`.
4. If we ship our own repackaged copy of the slices, publish the same build record (BUILD-INFO.txt) next to it and say what we changed (plist edit).
5. Our app stays free to be any licence (the project is open source anyway).

**If MPVKit (LGPL-3.0, static):**
1. LGPL section 6(a)-style obligation: users must be able to relink. For a static build we would have to publish our complete app source and build instructions (the project is open source, so this is feasible) and give the FFmpeg and dependency sources.
2. LGPL-3.0 "Installation Information": a user must be able to install a modified library on the device. Apple's signing and App Store distribution may make that impossible (UNVERIFIED).
3. Licence texts for FFmpeg, gnutls, nettle/gmp, libass, libplacebo, dav1d, etc. all have to be reproduced.
4. Never use the `-GPL` zips or `MPVKit-GPL`: GPL-3.0 would apply to the whole app.

**Both:** no GPL codec (x264, x265, fdk-aac) may be added; the only AAC encoder is FFmpeg's native one. Patent licences (HEVC, Dolby, DTS) are the app owner's responsibility and are separate from copyright licences (UNVERIFIED, not researched here).

## 6. What this means for Codemagic minutes

- **No C is compiled** with either candidate: the libraries are prebuilt. Linking prebuilt xcframeworks into a Swift app is part of the normal `xcodebuild` step. I cannot estimate the added link time (UNVERIFIED); static MPVKit libraries (avcodec 21 MB) add more link input than FFmpegBuild's dynamic 6 MB.
- **Dependency download is the real cost.**
  - MPVKit: each zip is a plain HTTPS download; the core five (avcodec, avformat, avutil, swresample, plus swscale) total about 88 MB of release assets (VERIFIED (page)) plus dav1d, uavs3d, gnutls, nettle, hogweed, gmp (and OpenSSL if the umbrella target is used): sizes of those were not read.
  - FFmpegBuild: resolving the upstream package would clone a 404 MB repository (VERIFIED (page)). Mitigation above (vendor only the tvOS slices into our own release asset, or cache `$HOME/Library/Caches/org.swift.swiftpm`; the existing `codemagic.yaml` already caches it, and I did not change that file).
- **Nothing here needs a Codemagic build to be decided.** The first compile check would be the first time any of this is linked; it should not be spent on engine experiments (R45). Until a Mac minute is available, the engine's FFmpeg-facing code stays behind a protocol and is not compiled in the package.
- I did not plan or write any build step.

## 7. libdovi for tvOS

| Question | Answer |
|---|---|
| Is a prebuilt libdovi for tvOS available? | **Yes.** `https://github.com/mpvkit/libdovi-build/releases/download/3.3.2/Libdovi.xcframework.zip`, 11,443,744 bytes, sha256 `e693e239808350868e79c5448ef9f02e2716bc822dd8632a41a368a1eae5ca7d` (released 2025-12-22, not a prerelease; previous releases 3.3.1-xcode and 3.3.1-xcode26). MIT licence (repo LICENSE, VERIFIED (page)). It is also what MPVKit's Package.swift links. VERIFIED (file) |
| Slices | `tvos-arm64_arm64e` (device: arm64 + arm64e) and `tvos-arm64_x86_64-simulator` (x86_64 + arm64), plus ios, macOS, Mac Catalyst, visionOS. VERIFIED (file: `file`) |
| Form | static archive wrapped in a framework; tvOS device binary 6.0 MB, simulator 5.9 MB. VERIFIED (file) |
| Exposes the API the DV spike benchmarked | header `rpu_parser.h` declares `dovi_parse_unspec62_nalu`, `dovi_write_unspec62_nalu`, `dovi_convert_rpu_with_mode`; the binary contains the symbols `dovi_convert_rpu_with_mode`, `dovi_parse_unspec62_nalu`, `dovi_write_unspec62_nalu`, `dovi_rpu_get_header`, `dovi_rpu_free`. VERIFIED (file) |
| Version vs the spike | prebuilt is libdovi **3.3.2**; the cost spike (docs/spikes/DOLBY_VISION_P7.md) measured crate **3.4.0**. Same function names; whether conversion mode 2 behaves identically in 3.3.2 is UNVERIFIED |
| How it was built | by CI on macOS: `cargo cinstall -Zbuild-std=std,panic_abort --release --prefix=... --target=<triple>` with `cargo-c`, from `quietvoid/dovi_tool` at `libdovi-3.3.2`, one run per triple (`aarch64-apple-tvos`, `arm64e-apple-tvos`, `aarch64-apple-tvos-sim`, `x86_64-apple-tvos`) (VERIFIED (page): `Sources/BuildScripts/XCFrameworkBuild/main.swift`). `-Zbuild-std` is nightly-only Cargo, and Rust treats these tvOS targets as tier 3 (no prebuilt std): that is why `build-std` is needed (the tier-3 and nightly statements are UNVERIFIED, from general knowledge, not read from rust-lang.org here) |
| If we had to build it ourselves on Codemagic | install a nightly Rust toolchain with `rust-src`, install `cargo-c`, then build 3 or 4 targets from source. I did not measure this; my **guess is 5 to 15 minutes** on an M2 mini, which is **at or above the 18 minutes left** (UNVERIFIED guess, not a measurement). Do not do it |
| Can a prebuilt XCFramework be built once and committed? | yes in principle: the tvOS slices of the prebuilt are 6.0 MB + 5.9 MB (about 12 MB raw, zip size for tvOS-only UNVERIFIED), so committing a tvOS-only copy (or attaching it to a GitHub release of our repo) is small. Building our own would need a Mac (a Codemagic run, or any Mac the user has): not available now. Reusing the prebuilt avoids it |
| Recommendation | reference the prebuilt by URL + checksum (or vendor the tvOS slices into our own release asset), pin 3.3.2. Whether a third-party GitHub release asset can be replaced after publication was not checked (UNVERIFIED), so keep our own copy |

## 8. What could not be determined without a Mac or an Apple TV

1. Whether either candidate links into a tvOS app target and passes `xcodebuild` (framework `Info.plist` values, dependency closure, `-ObjC`/linker flags, module maps `Libavformat.framework/Modules/module.modulemap`).
2. Final app size after dead-stripping for the static MPVKit option; size of the app with the dynamic FFmpegBuild frameworks embedded.
3. App Store validation of the embedded dynamic frameworks (the `MinimumOSVersion 26.0` plist value).
4. Whether `dvcC`/`dvvC` can be produced through the library API and whether AVPlayer accepts the resulting files (same open points as docs/spikes/REMUX.md).
5. Real-time behaviour on an Apple TV: CPU of demux/remux, read-ahead memory, 100+ Mbps files.
6. Whether the disabled bitstream filters in FFmpegBuild break any real-world input (ADTS AAC from transport streams).
7. Real E-AC-3 Atmos handling and DTS-HD MA decode speed (not testable here).
8. Legal reading of LGPL-3.0 static linking in an App Store app, and patent licences.
9. The Mac-side time to resolve each package (the 404 MB clone).

## 9. Links

- MPVKit: https://github.com/mpvkit/MPVKit (Package.swift: https://raw.githubusercontent.com/mpvkit/MPVKit/main/Package.swift; releases API: https://api.github.com/repos/mpvkit/MPVKit/releases)
- FFmpegBuild: https://github.com/superuser404notfound/FFmpegBuild (tag 3.15.0; Swift Package Index entry: https://swiftpackageindex.com/superuser404notfound/FFmpegBuild)
- FFmpegBuild fork (same content): https://github.com/TheFireKahuna/FFmpegBuild
- FFmpegKitNext prebuilt: https://github.com/thalesfp/ffmpegkit-apple
- FFmpegKit (archived): https://github.com/arthenica/ffmpeg-kit
- kingslay/FFmpegKit: https://github.com/kingslay/FFmpegKit
- mpvkit/ffmpeg-build fork: https://github.com/need4swede/ffmpeg-build
- vvisionnn/swift-ffmpeg (no tvOS): https://github.com/vvisionnn/swift-ffmpeg
- tylerjonesio/SwiftFFmpeg: https://github.com/tylerjonesio/SwiftFFmpeg
- libdovi build repo (MPVKit): https://github.com/mpvkit/libdovi-build ; release 3.3.2: https://github.com/mpvkit/libdovi-build/releases/tag/3.3.2
- libdovi source: https://github.com/quietvoid/dovi_tool
- Earlier spikes in this repo: docs/spikes/REMUX.md, docs/spikes/DOLBY_VISION_P7.md

## 10. Files

- This document only. The downloaded files live outside the repository in `~/vp-ffmpeg-research/` (WSL) and can be deleted.
