# Coverage: every backlog item and spec, and what the first TestFlight build would have

Written 2026-11-17 by reading the code and docs as they are during build batch 3 (nothing compiled; no device run exists).
The AUDIO and DOLBY VISION rows were finalised by the lead on 2026-11-17 after those agents finished: built and tested in WSL, never compiled for tvOS, device-unverified.

Status words:
- **built and tested**: the logic is written and its tests ran in WSL (Linux); since the first compile (R155) the package also compiles for tvOS. App/ has not fully compiled yet (see below).
- **built, device-only**: written (App/ screens and Apple wrappers, syntax-checked only) on top of tested logic; it can only be proven on an Apple TV.
- **partly**: some of the item exists; the "missing" column says what does not.
- **not started**: no code.
- **cut**: on the "Considered and cut" list (kept visible, reversible).

Because no device run exists, **every** row that reaches the screen is at most "built, device-only".

### First compile, 2026-11-17 (R155)

GitHub Actions, xcode-27 runner, Xcode 27.2, tvOS Simulator (x86_64 and arm64), run 44199971478 on commit 5703a92. **Build failed with 3 errors**, all in App/Support/AppServices.swift; fixed in the next commit, which has not been compiled yet.

| Part | Result of the first compile |
|---|---|
| XcodeGen project, package resolution, vendored packages, the 7 prebuilt xcframeworks | worked (one SwiftPM identity warning for swift-nio-ssh, fixed since) |
| Every package target (VideoPlayerCore and all Source*, LibraryIndex, UserData, AppLogic, PlaybackLogic, RemuxEngine, AudioDecode, DolbyVisionRPU, …), including the Apple-only `#if canImport` code | **compiled** for both architectures |
| Top Shelf extension | **compiled and linked** for both architectures; never run |
| App declarations (types, signatures, conformances of all 92 App files) | type-checked (the x86_64 module was emitted) |
| App function bodies | 24 files checked, 3 errors (fixed); **the other 68 are unconfirmed**: 23 in a batch that started with no result in the log, 45 never started |
| App link, embedding the dynamic frameworks (5 audio codec frameworks, AMSMB2), copying the extension into the app, signing | **never reached** |
| Running anything (Simulator or Apple TV) | never done |

So "built" for an App/ row still means "syntax-checked and declarations type-checked", not "compiled", until the next compile passes.

### What each CI job proves when it is green (third compile check onwards, R161)

| Job | A green tick proves | It does NOT prove |
|---|---|---|
| 1. Simulator compile (unchanged) | Every App/ and Top Shelf file compiles for the tvOS Simulator (arm64), the app links and embeds the extension and frameworks for the simulator | x86_64 simulator (R159), a real device, anything at run time |
| 2. Device build (new) | The same for a real Apple TV in Release: the device slices of the 5 audio codec frameworks, libnfs, AMSMB2 and the Dolby Vision RPU library link; the extension embeds no frameworks; Release contains no UI-test sample data (R160) | Signing, provisioning, entitlements, that it launches |
| 3. Simulator package tests (new) | The package unit tests build for tvOS and pass on the Simulator (server, iCloud and tool tests skip) | Device hardware paths (decoders, HDR, network to real servers) |
| 4. Screenshots (new) | The app launches on the Simulator, every listed screen is reachable with the remote, and how each looks with sample data | Focus feel, HDR and colour on a TV, real servers, playback (no real video in the sample data) |

None of jobs 2 to 4 has run yet: until a run is green they prove nothing.

## 1. What the first TestFlight build would NOT have that you asked for (gaps first)

| # | You asked for | Status | What exists / what is missing | Where |
|---|---|---|---|---|
| G1 | Fallback engine (MPVKit), engine selection | not started | Nothing. Status texts for "Fallback player" exist in the PlaybackStatus table only. Everything the backlog routes "to the fallback engine" (styled ASS, odd containers, no-remux cases) has no player | docs/BUILD_ORDER.md step 8 |
| G2 | Online skip timestamps (backlog 33, Tier 2 of Skip) | not started | Segments come from your marks, MKV/WebM chapters and sidecar files only. No database chosen (B5) | docs/SEGMENTS.md, R94 |
| G3 | On-device intro/credits detection (backlog 34, Tier 3, Chromaprint B6) | not started | Setting text and B6 decision only | docs/SEGMENTS.md, OPEN_QUESTIONS B6 |
| G4 | Collections and franchises, Favorites pinned to Home, user-made collections, pinned folders in Files (backlog 16) | partly | Favorites can be set (long-press) and filtered. Missing: a Collections section or row, user-made collections, a Favorites Home row, pinned folders in Files. Discover's "Collection Gaps" is the only collection screen | App/Shared/CardContextMenu.swift, AppLogic/LibraryScreens.swift (`HomeRowID` has 3 rows) |
| G5 | Versions (backlog 14) | built, device-only | Contrary to the list in the request, this IS in the build: files of one title are grouped, the detail screen has a Versions picker, the choice is remembered (`setPreferredVersion`). Default order: highest resolution, then largest file | App/Features/Detail/VersionsMenu.swift, LibraryIndex `versions(of:)` |
| G6 | Extras and editions (backlog 15) | partly | "Extras" lists the files next to the video (subtitles, pictures, info files). Missing: trailers, behind-the-scenes, Director's Cut and other editions, multi-part files | App/Features/Detail/ExtrasMenu.swift, R74 |
| G7 | Deinterlacing 50i/60i (backlog 24) | not started | No research or code | |
| G8 | Subtitle search and download (backlog 25) | not started | | |
| G9 | "Are you still watching?" (backlog 26) | not started | | |
| G10 | Library Statistics screen (backlog 23) | not started | The index has the data (resolution, HDR, audio, codec columns) but no screen or queries | |
| G11 | Connection Test (backlog 22) | partly | Add a Source runs a real test connection (connect and list). Missing: sample read, measured throughput, highest sustainable bitrate, Ethernet or Wi-Fi, advice | docs/SOURCES_WIRING.md |
| G12 | Backup: export and import (backlog 21) | partly | `UDExport.export/import` (plain JSON, no secrets) is written and tested. Missing: any screen or file route to use it | Packages/VideoPlayerCore/Sources/UserData/ExportImport.swift |
| G13 | DTS, DTS-HD MA, TrueHD (full decode, not the AC-3 core), Opus, Vorbis up to 7.1 (R99) | **built, WSL-tested (38 audio tests, lossless bit-exact); never compiled for tvOS; device-unverified (AU-1 to AU-16)** | Decoded to FLAC in fMP4 at source rate, depth and layout up to 7.1; TrueHD full decode by default (core is a setting); DTS:X and TrueHD Atmos play the 7.1 bed only, status says so; R121-R130 | docs/PLAYBACK_WIRING.md, R92 |
| G14 | Dolby Vision profile 7 as full Dolby Vision (R99, backlog 31) | **built, WSL-tested (byte-identical to dovi_tool on FEL, MEL, switching and 8.1 files); never compiled for tvOS; device-unverified (DV-1 to DV-15)** | Converted per frame to Profile 8.1; MEL lossless, FEL loses its residual (Apple TV outputs Dolby Vision only from its own decoder); dual-track files not yet (R132); R131-R137 | docs/PLAYBACK_WIRING.md, docs/spikes/DOLBY_VISION_P7.md |
| G15 | Playback conveniences (backlog 17): speed menu, hold for 2x, chapter list and skipping, zoom and fill, sleep timer, audio night mode | not started | Only what the system player gives on its own. Chapters are read but used only for Skip segments | |
| G16 | Siri and App Intents (backlog 18) | not started | Top Shelf, deep links and Now Playing exist; AirPlay is whatever the system player offers (no code) | docs/TOP_SHELF.md |
| G17 | Home rows: Upcoming Episodes, Favorites, More Like This (binding rule) | not started | Home has Continue Watching, Next Up, Recently Added | AppLogic/LibraryScreens.swift |
| G18 | Discover extras: scores from all sources, Stream/Rent/Buy filtered by My Services, quality bar (minimum rating and votes, Settings > Discover), Not Interested, no duplicates | partly | Missing Episodes, Collection Gaps, Similar, Watchlist and where-to-watch per region are built. Missing: scores (the ratings key is stored but never used), My Services filter, minimum rating/votes and its setting, Not Interested | docs/ARTWORK_DISCOVER.md section 5 |
| G19 | Long-press actions on every poster (backlog 4) | partly | Present: Mark Watched/Unwatched, Add/Remove Favorites. Missing from the long-press menu: Play, Play from Beginning, Remove from Continue Watching, Fix Match, Refresh Metadata, File Details (Fix Match and File Details exist as screens elsewhere) | App/Shared/CardContextMenu.swift |
| G20 | Track selection set once in Settings > Playback (backlog 10) | partly | Rules are built and tested (languages, forced, SDH, highest channel count, Atmos, per series). Settings has only "Remember ... for Each Show"; there is no preferred-language picker | Subtitles/TrackSelection.swift, App/Features/Settings/PlaybackSettingsView.swift |
| G21 | Scheduled library refresh (backlog 1) | partly | Scan on launch (setting) and on demand; no refresh on a schedule | App/Shell/RootView.swift |
| G22 | Styled ASS (backlog 9 "at least on the fallback engine", backlog 32) | not started | Flattened to text with bold/italic (your D5); needs the fallback engine or an own renderer | R84 |
| G23 | VobSub (.sub/.idx) bitmaps (backlog 9) | not started | Only the `.idx` header is read (R39) | docs/SUBTITLES.md |
| G24 | Disc structures BDMV, VIDEO_TS, ISO (backlog 28) | not started | | |
| G25 | Downsampled images (backlog 20) | not started | `AsyncImage` decodes the whole picture; matters more now that posters are `w780` (section 4) | |
| G26 | Restore the full player from Picture in Picture | not started | PiP itself is on (D3) | R92 |
| G27 | HDR10+ | partly built | Apple TV 4K (3rd generation) and later support HDR10+ (earlier reading was wrong); HDR10+ in the video stream is kept and stated; the Matroska HDR10+ field is not copied yet (R136) | docs/SPECS.md platform decision 7 |
| G28 | On-device AI subtitles (backlog 30) | not started | research item | |
| G29 | OneDrive and Plex sources | blocked (account) | OneDrive needs an app registration, Plex a vendor account (your R30) | docs/SOURCES.md |
| G30 | Provider logo next to the attribution | not done, your decision | The data provider's terms say its logo "must" be used; no logo is added (docs/ARTWORK_DISCOVER.md section 5a) | |

## 2. Full table: docs/FEATURE_BACKLOG.md

| Item | Status | Missing / note | Evidence |
|---|---|---|---|
| Binding rule: your library only | built and tested | Home/Movies/Shows/Files/Search read only the library | MetadataOnline `LibraryOnlyTests`, docs/METADATA.md section 2 |
| Discover tab (sections, Show Discover setting) | partly | see G18 | docs/ARTWORK_DISCOVER.md |
| 1 Instant, scalable library | built and tested (logic); UI built, device-only | scheduled refresh (G21); cold-launch time unmeasured on a device | docs/LIBRARY_INDEX.md, App/Features/Movies/AlphabetJumpMenu.swift |
| 2 Combined sort and filter, saved views | built, device-only | | App/Features/Movies/{FilterMenu,SortMenu,SavedViewsMenu}.swift |
| 3 Direct file browsing | built, device-only | | App/Features/Files/ |
| 4 Continue Watching, Next Up, watched marks, resume, long-press actions, retention setting | partly | long-press actions (G19) | App/Features/Home/, HomeScreenSettingsView.swift |
| 5 Setup: Bonjour, connection test, sync of sources, credentials, favorites, filters, watch state | built, device-only | CloudKit and Keychain never run (R65, R71) | docs/SOURCES_WIRING.md, docs/STORAGE_MODEL.md |
| 6 Self-signed certificates, pinning, Basic-over-HTTP warning | built, device-only | | R93, App/Support/TrustCenter.swift |
| 7 WebDAV compatibility tests | partly | rclone WebDAV tested live; Nextcloud, Synology, Apache, nginx not tested | R78 |
| 8 Audio and video sync, per-file delay | partly | logic (`SyncModel`) and delay rows built; fallback engine missing (G1); Wireless Audio Sync assumption unverified (R39) | docs/SUBTITLES.md |
| 9 Subtitles | partly | text subtitles and PGS built; VobSub (G23), styled ASS (G22) missing | docs/SUBTITLES.md, docs/PLAYBACK_WIRING.md |
| 10 Track selection rules | partly | see G20 | |
| 11 Playback Stats overlay | built, device-only; audio and Dolby Vision lines added this batch | | docs/PLAYBACK_STATUS.md |
| 12 Honest audio and video status | built | golden table regenerated (474 rows) | docs/PLAYBACK_STATUS.md |
| 13 Smooth transitions, next episode prepared during credits | partly | display-mode decision logic and prefetch timing built and tested; whether the display mode stays between episodes is device-only | docs/PLAYBACK_LOGIC.md |
| 14 Versions | built, device-only | G5 | |
| 15 Extras and editions | partly | G6 | |
| 16 Collections, Favorites on Home, user collections, pinned folders | partly | G4 | |
| 17 Playback conveniences | not started | G15 | |
| 18 Siri/App Intents, Top Shelf, AirPlay, Now Playing | partly | Top Shelf and Now Playing built, device-only; App Intents not started (G16) | docs/TOP_SHELF.md |
| 19 Accessibility | built, device-only (system components only) | audio description tracks are not specially handled; none of the system settings exercised | docs/DESIGN_SYSTEM.md section 11 |
| 20 Performance budgets | partly | library timings measured in WSL; launch, scrolling, memory and downsampled images (G25) are device-only or missing | docs/LIBRARY_INDEX.md |
| 21 Backup export/import | partly | G12 | |
| 22 Connection Test | partly | G11 | |
| 23 Library Statistics | not started | G10 | |
| 24 Deinterlacing | not started | G7 | |
| 25 Subtitle search and download | not started | G8 | |
| 26 "Are you still watching?" | not started | G9 | |
| 27 All source types | partly | all clients written and tested; OneDrive and Plex blocked (G29); SMB/NFS verified only against stand-ins (R23) | docs/SOURCES.md, docs/SOURCES_WIRING.md |
| 28 Disc structures | not started | G24 | |
| 29 Prefetch to cache (was offline downloads) | partly | next-episode prefetch timing in PlaybackLogic; no title prefetch | R57 |
| 30 On-device AI subtitles | not started | G28 | |
| 31 Dolby Vision profile 7 | built, WSL-tested, device-unverified | G14 | |
| 32 ASS original styling | not started (deferred by your D5) | G22 | R84 |
| 33 Online skip timestamps | not started | G2 | |
| 34 On-device skip detection | not started | G3 | |
| Cut list: separate user profiles, parental controls, Trakt sync, Ambient Mode, AI upscaling, Surprise Me, local ratings and notes, Rewatch list, Wake-on-LAN, SharePlay, scrub thumbnails, dual subtitles, social features | cut | each reversible | docs/FEATURE_BACKLOG.md |
| Out of scope: music, photos, podcasts, live TV, DVR, hosted server, accounts, ads | out of scope | | |

## 3. Full table: docs/SPECS.md

Spec documents:

| Spec | Status | Note |
|---|---|---|
| README.md, OPEN_QUESTIONS.md, docs/BUILD_ORDER.md | current | BUILD_ORDER step 13 still says Discover shows "not available"; batch 2 built it (lead to update) |
| docs/FEATURE_BACKLOG.md | section 2 above | |
| docs/SOURCES.md | built and tested (clients); wiring built, device-only | |
| docs/HIG_AUDIT.md | written; device-only checks | |
| docs/CODEMAGIC_SETUP.md | written; Codemagic not used this month (R105) |
| docs/BACKUP.md (iCloud backup of generated data, R163) | engine, merge rule and purge-then-restore built and tested (WSL, in-memory fake); CloudKit adapter, Settings > Backup and the automatic restore built, device-only (never compiled, never run) | checklist docs/DEVICE_TEST_CHECKLIST_BACKUP.md B1 to B22 | |
| docs/LIBRARY_INDEX.md | built and tested | |
| docs/METADATA_LOCAL.md | built and tested | MP4 chapters not done (SEGMENTS) |
| docs/METADATA.md | built and tested (clients, matcher, Fix Match); OMDb client built but unused by the app | ratings never fetched (G18) |
| docs/PLAYBACK_LOGIC.md | built and tested | |
| docs/SUBTITLES.md | built and tested (parsers, PGS placement, selection, sync) | VobSub bitmaps missing |
| docs/PLAYBACK_STATUS.md | regenerated this batch (474 rows) | |
| docs/spikes/REMUX.md, DOLBY_VISION_P7.md, FFMPEG_TVOS_CANDIDATES.md | spikes done; implemented this batch (docs/AUDIO_PIPELINE.md, docs/DOLBY_VISION.md) | |
| scripts/test-*.sh | in use | test-core.sh now exports VP_PROJECT_ROOT (this batch) |
| docs/STORAGE_MODEL.md | built and tested (logic); CloudKit/Keychain wrappers device-only | |
| docs/APP_LOGIC.md | built and tested | |
| docs/SFTP_CITADEL.md | built and tested (live) | |
| docs/TEST_ENVIRONMENT.md | current | |
| Spec change: offline downloads -> prefetch | partly (row 29) | |

Platform decisions 1 to 18 (all PROVISIONAL in SPECS.md):

| # | Decision | Status |
|---|---|---|
| 1 | System player, externalMetadata, Now Playing for the fallback only | built, device-only (fallback missing, G1) |
| 2 | Subtitle menu D1, D5 | built, device-only |
| 3 | Remotes: system behaviour only | built (no code), device-only |
| 4 | Picture in Picture | partly (on; restore not done, G26) |
| 5 | Lifecycle: save position, resume without prompt, scene life cycle | built, device-only (exact save intervals not re-checked by this agent) |
| 6 | Audio routes and honest text | built this batch (fallback alert, honest bed-only and sample-rate text); device-unverified |
| 7 | Display: system applies criteria, HDR10+ stated where the hardware supports it, read-ahead budget | built, device-only; read-ahead budget unchanged this batch (listed in the quality re-check) |
| 8 | Text entry | built, device-only |
| 9 | Accessibility | built, device-only |
| 10 | App Store readiness (manifests, export compliance D7 open, privacy label D10) | partly: D7 is yours to decide; privacy draft reconciled this batch |
| 11 | No reliance on background work | built (by design) |
| 12 | One library per device | built (by design) |
| 13, 17 | Apple TV app integration | not possible (Video Partner Program), substitutes built |
| 14 | Liquid Glass / tvOS 27 system components | built, device-only |
| 15 | Passwords: local plus encrypted cloud copy (option B) | built, device-only |
| 16 | App screens native; honest "not available" texts | built, device-only; several R74 gaps closed in batch 2 |
| 18 | Test health floors | built and in use |

## 4. Defaults re-checked against the quality principle (R98)

Rule applied: where an earlier default traded quality and you had not decided it, the highest-quality option replaces it; where the code belongs to the AUDIO or DOLBY VISION agents (RemuxEngine, the new audio/DV targets, the PlaybackStatus golden table, App/Features/Player/*), the default is only listed here.

### Changed by this agent

| Default | Was | Now | Why (proof) | Old default kept as |
|---|---|---|---|---|
| Online poster size (`ImageURLBuilder.preferred[.poster]`, MetadataOnline/TMDBMapping.swift) | `w500` | `w780` | The app's grid is five columns, 320 pt wide unfocused (HIG Layout, tvOS grid table); tvOS art is @1x and @2x (HIG Images), so a 4K screen draws 640 px, more when focused: `w500` was upscaled. `w780` is the smallest size at or above 640 px. Alternative: `original` (largest; without a downsampling loader a grid of 2000x3000 posters risks memory, G25). PROVISIONAL | the `size:` argument still accepts any size; no setting added (you did not ask for one) |
| Backdrop, episode still, logo size | `w1280`, `w300`, `w500` | `original` | A full-screen picture is 3840 px wide at @2x; no fixed size reaches it. No screen shows backdrops or stills yet | `size:` argument |
| Cast photo size | `w185` | `h632` | larger than any size a cast row needs at @2x | `size:` argument |
| Largest picture read from a source (`ArtworkEngine.maxSidecarBytes`) | 8 MB | 40 MB | A 3840x2160 PNG next to the video can be over 8 MB; skipping it fell back to a smaller online poster. 40 MB covers 3840x2160x4 bytes (33.2 MB) | constant; PROVISIONAL |

Tests: `TMDBClientTests.testConfigurationAndImageURLs`, `testImageBuilderFallsBackWhenConfigurationIsUnavailable`, `AttributionNoticeTests.testArtworkDefaultsAreTheHighQualityChoices`. Rows in docs/QUALITY_CEILINGS.md under "Artwork".

### Kept, because they are already the highest quality or you decided them

| Default | Value | Why kept |
|---|---|---|
| Version picked first | highest resolution, then largest file (`versions(of:)` ORDER BY res DESC, size DESC) | already the highest quality; does not yet rank Dolby Vision/HDR above SDR at equal resolution (suggestion for the AUDIO/DV agents' status work, not changed here) |
| Track selection | prefer highest channel count, prefer Atmos (`TrackSelection` defaults true) | already highest quality |
| PGS placement | `.fit` (uniform scale, no stretch) | already correct geometry |
| Text subtitles flattened to WebVTT (D5) | ASS styling flattened | **your decision D5** (R84); the styled option is backlog 32 |
| Tone mapping | done by the system, never our own | matches the principle ("no own tone mapping") |
| Artwork caches | 150 MB source pictures, 20 MB / 100 MB online | size of the cache, not of the pictures: a smaller cache means re-downloads, never lower quality |

### Listed only: owned by the AUDIO or DOLBY VISION agents this batch

| Default | Value before this batch | Owner |
|---|---|---|
| TrueHD with an AC-3 core plays the AC-3 core | PlaybackStatus rows A022 to A042 ("TrueHD core, passthrough") | AUDIO |
| DTS, DTS-HD MA, TrueHD, Opus, Vorbis | decoded to lossless FLAC at source depth and rate, up to 8 channels (this batch) | done (WSL) |
| "Always also offer a stereo AAC track" (REMUX spike, HLS rule 2.3) | extra track, the original stays | AUDIO |
| Sample rates above 48 kHz (DTS-HD MA 96 kHz) | kept at source rate; status says the system does not report what the output receives | done; device test AU-2/AU-3 |
| Downmix when the output has fewer channels | done by the system | AUDIO |
| Dolby Vision 7 | converted to Profile 8.1 (full Dolby Vision); FEL residual lost | done (WSL); device test |
| Display criteria (frame rate and dynamic range matching) | left to the system (`appliesPreferredDisplayCriteriaAutomatically = true`), follows the user's Match Content | DV / Player |
| Read-ahead budget, segment length | 192 MiB, 2 to 6 s (ASSUMPTIONS, R69) | RemuxEngine owners |

## 5. Recommended order for the rest

1. Next compile check (manual GitHub Actions, R105) on the commit that fixes the first compile's 3 errors (R155), and fix what it finds, until the app links: everything above is "device-only" until then.
2. Play the hard requirements built this batch (G13 audio, G14 Dolby Vision 7) on a device, and fix what the device shows.
3. G19 long-press actions and G20 language preferences: small, daily-use, logic already tested.
4. G4 collections and Favorites on Home, G17 Upcoming Episodes: library-only rows from data the index already has.
5. G12 backup screen: the logic exists; it is the only safety net for people signed out of the cloud.
6. G25 downsampled images, then consider `original` posters: protects memory with large libraries.
7. G15 playback conveniences (speed, chapters, sleep timer).
8. G11 Connection Test, then G10 Library Statistics (Tier B).
9. G1 fallback engine (unblocks G22 styled ASS and the backlog-9 "fallback engine" items), then G9 still-watching, G8 subtitle download, G7 deinterlacing (research first).
10. G18 Discover quality bar and scores (needs the ratings key wired), G16 App Intents.
11. Research items: G2 and G3 skip timestamps/detection, G24 disc structures, G28 AI subtitles.
