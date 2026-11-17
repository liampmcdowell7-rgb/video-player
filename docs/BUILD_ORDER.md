# Build order

Status words: **Logic done** = written and tested in WSL (Linux); nothing of it has been compiled for tvOS or run on an Apple TV. The first compile check proves the wiring only.

| Step | Work | Status |
|------|------|--------|
| 1 | Scaffold, Swift package, codemagic.yaml (manual only) | Written, not yet compiled on Codemagic |
| 2 | WebDAV client (PROPFIND, Basic and Digest), behind the shared source contract | Built and tested on Linux (see docs/SOURCES.md). App UI for servers pending |
| 3 | File model, sort, search | Core written and tested locally. File browser UI and Continue Watching pending |
| 4 | Primary playback engine (remux, HDR, audio) | **Spikes only** (docs/spikes/REMUX.md, docs/spikes/DOLBY_VISION_P7.md); engine not started |
| 5 | Metadata: filename parser, sidecar reading (NFO, images, embedded MKV tags and chapters), TMDB, OMDb, matcher, cache, Fix Match | **Logic done**: `MetadataLocal`, `MetadataOnline` (docs/METADATA_LOCAL.md, docs/METADATA.md). TMDB and OMDb were never contacted (hand-written fixtures). Library screens pending |
| 6 | Discover (Missing Episodes, Collection Gaps, Similar to Your Library, Watchlist, Where to Watch) | After step 5 has working TMDB matching |
| 7 | Player UI on AVPlayerViewController, track pickers, File Details, Now Playing | Not started. Track-selection rules and sync model: **logic done** in `Subtitles` (docs/SUBTITLES.md) |
| 7b | Skip Intro, Recap, Credits and Next Episode (Part B) | **Logic done** as a state machine: `PlaybackLogic` (docs/PLAYBACK_LOGIC.md). Tier 2 and Tier 3 not built. AVContentProposal and contextualActions wiring pending |
| 7c | Playback Stats overlay model and honest audio/HDR status | **Logic done**: `PlaybackStatus` (docs/PLAYBACK_STATUS.md) |
| 8 | Fallback engine (MPVKit) and engine selection | Not started |
| A | Tier A basics 1 to 21 (docs/FEATURE_BACKLOG.md) | Item 1 to 4, 14, 16, 20 data layer: **logic done** in `LibraryIndex` (docs/LIBRARY_INDEX.md); item 8 to 10 logic in `Subtitles`; items 11, 12, 13 logic in `PlaybackStatus`. UI for all of them not started |
| B | Tier B items 22 to 26 | Later |
| C | Tier C items 28 to 31, research first (item 27 moved into step S) | Item 31 has a measurement spike (docs/spikes/DOLBY_VISION_P7.md) |
| S | All source types as one program (docs/SOURCES.md) | Clients written and tested in WSL; SMB and NFS PROVISIONAL; SFTP source written and tested against an in-memory backend, the Citadel backend is PROVISIONAL and its live tests ran (60 passed, step 11); OneDrive and Plex account-blocked |
| 9 | Storage model (user data in CloudKit and essentials, caches purgeable) | **Logic done** in `UserData` and `LibraryIndex` (docs/STORAGE_MODEL.md); the CloudKit and Keychain wrappers and the entitlements are **never compiled**; first compile check must compile them |
| 10 | Remux engine (`RemuxEngine`) | **Logic done**: 117 tests, 0 skipped, 0 failed in WSL (docs/ENGINE_DESIGN.md), including 3 on real encoder-made MKV files read back by an independent ffprobe; AudioTranscoding and Dolby Vision converter are protocols with no implementation yet. **Never compiled for tvOS, never played by AVPlayer** (docs/DEVICE_TEST_CHECKLIST.md) |
| 11 | Citadel SFTP backend (`SourceSFTPCitadel`) | **Live tests run** (`bash scripts/test-sftp.sh`, `swift test --build-system native`, real OpenSSH server): 60 passed, 0 skipped, 0 failed (23 Citadel live, 19 Citadel unit, 18 SFTPSourceTests). The live run found one bug (a missing file was reported as a transport error, now `notFound`), fixed. Not compiled for tvOS; fallback Libssh2Prebuild |
| 12 | App-side view models (`AppLogic`) | **Logic done**, 62 tests; Apple wrappers never compiled; no screen uses them yet |
| 13 | App screens (`App/`, SwiftUI, 77 files incl. Top Shelf) | **Written, NEVER COMPILED.** Home, Movies, Shows, Files, Search, Discover (says "not available"), Settings, Add a Source, Fix Match, Item detail, Player (system player + own Now Playing, Skip and Playback Stats hooks). Checks that ran: `swiftc -parse` on every file (syntax only), design lint, two full read-throughs (OPEN_QUESTIONS.md R75), API check against Apple pages (docs/API_USAGE.md). Gaps are listed in R74: only WebDAV connects, no artwork, MKV does not play (remux engine not wired), no Skip or Up Next data. First compile check decides everything else |
| 14 | Top Shelf extension and deep links | `TopShelfSnapshot` (tested), `TopShelfBuilder` and `DeepLink` (AppLogic, tested), extension target in project.yml (`tv-app-extension`). **Never compiled**; shows nothing until artwork exists (R74). Apple TV app (Video Partner) integration: not done, not the right fit (R77) |
| 15 | Test health | Per-target counts and minimum floors: `scripts/test-counts.sh` (result lines and XCTest summary, R153; its own checks in `scripts/test-counts-tests.sh`), `scripts/test-floors.txt`; `scripts/test-all.sh` prints them and fails loudly below a floor (OPEN_QUESTIONS.md R78) |
