# Quality ceilings (Apple TV 4K 2nd generation and later, tvOS 27)

Quality principle (decided by the user, 2026-11-17): wherever quality trades against convenience, speed, size or simplicity, choose the highest quality the Apple TV 4K (2nd generation and later) and tvOS 27 can reproduce, as proven by Apple's documentation, and never trade quality for ease of implementation without approval. Every ceiling below is written with the Apple page that proves it and with what the app shows when content exceeds it.

Each section is owned by one work stream and appended under its own heading. A row without a page link is marked UNVERIFIED and is not a claim.

| Area | Ceiling | Apple page | What the app shows | Status |
|---|---|---|---|---|

## Artwork (COVERAGE agent, 2026-11-17)

| Area | Ceiling | Apple page | What the app shows | Status |
|---|---|---|---|---|
| Poster pixels | A five-column grid poster is 320 pt wide unfocused; tvOS artwork is provided at @1x and @2x, so on a 4K screen (@2x, my reading: the page lists the scale factors but does not name which output uses which) it is drawn 640 px wide, more when focused. Online posters are now requested at `w780` (was `w500`, which was upscaled). `original` is the alternative (PROVISIONAL, see docs/COVERAGE.md) | https://developer.apple.com/design/human-interface-guidelines/layout (tvOS grids: five-column 320 pt), https://developer.apple.com/design/human-interface-guidelines/images (tvOS: @1x and @2x) | The poster as received; no text (a picture has no status line) | Changed; device check: A-series checklist |
| Full-screen pictures | A full-screen picture is 1920 pt = 3840 px at @2x; no fixed online size is that large, so backdrops, episode stills and logos use `original` | same pages | as received | Changed (no screen uses backdrops yet) |
| Pictures next to the video | Read up to 40 MB (was 8 MB) so a full-resolution 3840x2160 PNG (33.2 MB uncompressed RGBA worst case) is not skipped in favour of a smaller online picture | none needed (a file-size limit, not a device ceiling) | as read | Changed |

## Video and display (DOLBY VISION agent, 2026-11-17)

Details and citations: docs/DOLBY_VISION.md. Pages read 2026-11-17.

| Area | Ceiling | Apple page | What the app shows | Status |
|---|---|---|---|---|
| Resolution and frame rate | 2160p up to 60 fps on Apple TV 4K 2nd gen and later (2nd gen: "up to 2160p, 60 fps"; HDMI 2.1 footnote "up to 4K 60-fps HDR video output"); HLS authoring spec 1.19: no frame rates above 60 | https://support.apple.com/en-us/111922, https://support.apple.com/en-us/111839, https://www.apple.com/apple-tv-4k/specs/, https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html | Resolution and frame rate as in the file; a file above 60 fps is not given a frame-rate claim the device cannot output | Verified (pages) |
| Video bit depth | 10-bit: HEVC Main 10 ("HDR10 (Main 10 profile)"); HLS spec 1.6: HEVC up to Main 10, level 5.1 High tier. No 12-bit decode or output is listed on any Apple TV page | same pages | "HEVC"; Dolby Vision profile 7 FEL note says the extra picture detail (12-bit reconstruction) is not shown | Verified (pages); 12-bit: none listed |
| Dolby Vision profiles | 4K 1st, 2nd, 3rd gen pages: "Dolby Vision (Profile 5)"; current model: "Profile 8.1 and 5". The HLS spec documents 8.1 (`dvh1.08.xx/db1p`) and 8.4 (`db4h`). Profile 7 is not playable as such: converted to 8.1 (BL + converted RPU), the best the device can show | 111929, 111922, 111839, apple-tv-4k/specs, HLS spec | "Dolby Vision (converted from Profile 7)" + FEL / MEL note; "Dolby Vision" for 5 and 8.x | Verified (pages); 8.1 on 2nd / 3rd gen through this path: device check DV-3 |
| Dolby Vision FEL | The full enhancement layer residual cannot be shown: Dolby Vision output only comes from the system player decoding a compressed 5 / 8.1 stream; composing the EL in the app would give pixels that can only leave as HDR10 (losing dynamic metadata) or need a lossy re-encode | same, plus docs/DOLBY_VISION.md section 4 | The FEL note on the video line | Device limit (reasoned from the pages; no page states it directly) |
| HDR10+ | Apple TV 4K 3rd generation and later only: "HDR10+ is a supported format only on Apple TV 4K (3rd generation) and later" | https://support.apple.com/en-us/102339, 111839 | 3rd gen and later: "HDR10+ or HDR10" with a note (no API says whether the TV uses it); 1st / 2nd gen: "HDR10" with "This Apple TV model does not support HDR10+" | Verified (pages); remux path: device check DV-10 |
| HLG | 4K 2nd gen and later (1st gen page lists no HLG) | 111922, 111929 | "HLG" | Verified (pages) |
| HDR10 static metadata | Mastering display and content light level are copied unchanged (SEI in the samples, Matroska colour elements into the init segment) | none needed (no device limit) | Values in Playback Stats | Unchanged by this work |
| HDMI output | 2nd gen and later: HDMI 2.1, "Support for up to 4K 60-fps HDR video output"; 1st gen HDMI 2.0a; HD: HDMI 1.4 (SDR only) | 111922, 111839, 111929, 111928 | — | Verified (pages) |
| Codecs | 4K 3rd gen: HEVC, H.264; current model adds AV1 and VP9 (the remux engine handles HEVC and H.264 only) | 111839, apple-tv-4k/specs | — | Verified (pages) |

## Audio (AUDIO agent, 2026-11-17)

Details, test results and citations: docs/AUDIO_PIPELINE.md. Pages read 2026-11-17.

| Area | Ceiling | Apple page | What the app shows | Status |
|---|---|---|---|---|
| Lossless container | FLAC (and Apple Lossless) are supported multichannel HLS codecs, fMP4 only (HLS spec 2.5, 2.25; CODECS `fLaC`). DTS-HD MA, TrueHD and MLP are decoded and stored as FLAC at the source bit depth, rate and layout: bit-exact in every test | https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html | "<n> PCM (decoded)"; Playback Stats: "... decoded losslessly to FLAC (24-bit, 48 kHz)" | Verified (page + Linux tests); device playback: AU-2 |
| Channels | Up to 7.1 (8 channels) kept as in the source; the app never downmixes; a channel with no FLAC slot is reported | HLS spec 2.5 (no channel order rule on the page) | Downmixes by the system are said in the status ("downmixed from 7.1") | Speaker mapping of FLAC 7.1 UNVERIFIED: AU-14 |
| Sample rate above 48 kHz | Kept (96 and 192 kHz FLAC). Hi-Res Lossless output is documented only for Apple TV 4K 3rd generation and later, with no rate given; what HDMI / eARC / AirPlay receive above 48 kHz is not documented for this path | https://support.apple.com/en-us/118295, https://support.apple.com/en-us/111839 | Note: "the system does not report whether this output receives the full 96 kHz" | UNVERIFIED (device AU-3, AU-4); possible system resampling is said, not hidden |
| Bit depth | 24-bit (16-bit sources stay 16-bit). Sources above 24 bits would be shortened to 24 and counted (none seen) | none (no page gives a limit) | Playback Stats count | Linux-tested |
| Dolby TrueHD with Atmos | Cannot pass through: the 7.1 bed plays (decoded losslessly), objects are lost | https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html (only Dolby Digital Plus JOC carries Atmos, 2.29) | "the Atmos objects are not played, only the 7.1 bed" | Verified (page); bed bit-exact (Linux) |
| DTS:X | The 7.1 bed plays; objects are not rendered | none (no Apple page mentions DTS) | "the DTS:X objects are not rendered, only the 7.1 bed plays" | Linux-tested for DTS-HD MA; no DTS:X sample tested |
| TrueHD Dolby Digital core | Default is the full lossless decode; the 5.1 lossy core only with the compatibility setting (off) | HLS spec 2.5 (AC-3 supported) | "Dolby Digital 5.1 (TrueHD core, passthrough)" only when the setting is on | Changed default (quality) |
| Atmos over ARC | Dolby Atmos is not available over ARC | https://support.apple.com/en-us/102310 | Unchanged rules (Dolby Digital Plus Atmos path) | Verified (page) |
| Lossy sources (DTS core, Opus, Vorbis) | Decoded output stored without further loss (24-bit FLAC, no dither) | none needed | "decoded to FLAC (the source is lossy; nothing further is lost)" | Linux-tested |
