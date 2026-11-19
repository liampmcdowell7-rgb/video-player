# Specs index

| Document | What it covers |
|---|---|
| README.md | What the project is |
| OPEN_QUESTIONS.md | Every undecided point with a provisional choice |
| docs/BUILD_ORDER.md | Build steps and status |
| docs/FEATURE_BACKLOG.md | Tier A, B, C, the cut list, out of scope |
| docs/SOURCES.md | Source contract, one section per source type, blocked list |
| docs/HIG_AUDIT.md | Apple HIG audit of each screen |
| docs/CODEMAGIC_SETUP.md | One-time setup steps |
| docs/LIBRARY_INDEX.md | Library database, incremental sync, filters, measured timings |
| docs/METADATA_LOCAL.md | NFO, sidecar images, embedded MKV tags and chapters |
| docs/METADATA.md | TMDB and OMDb clients, matching order, Fix Match, cache, Your Library Only (the wording the user gave, copied here because this index is not the spec) |
| docs/PLAYBACK_LOGIC.md | Skip Intro, Recap, Credits and Next Episode as a state machine, every rule with its test |
| docs/SUBTITLES.md | Subtitle parsers, PGS overlay placement, track selection, audio sync model |
| docs/PLAYBACK_STATUS.md | Playback Stats model and the exact honest-status texts |
| docs/spikes/REMUX.md | FFmpeg remux and audio repackaging feasibility |
| docs/spikes/DOLBY_VISION_P7.md | Dolby Vision profile 7 to 8.1 conversion cost |
| scripts/test-all.sh | Every test, every test server, one line per stage |
| scripts/test-core.sh | Unit tests in WSL (no Codemagic minutes); non-zero exit on a failed test or no results, last line "test-core: passed P, skipped S, failed F" (self-test scripts/test-core-tests.sh) |
| scripts/test-servers.sh | Start and stop local test servers in WSL |
| scripts/test-integration.sh | Start servers, run integration tests, stop servers |
| scripts/test-mediaservers.sh | Run real Jellyfin or Emby in WSL (user space) |
| docs/BACKUP.md | iCloud backup of generated data (not the media): records, chunking, versioning, merge rule, the Backup screen, Apple's limits (R163) |
| docs/DEVICE_TEST_CHECKLIST_BACKUP.md | Device checks for the backup, one per screen state (B1 to B22) |
| docs/STORAGE_MODEL.md | tvOS storage model: what is USER DATA (CloudKit, essentials in UserDefaults) and what is a purgeable cache, startup after a purge, conflict rules, limits. Refines the library spec: the SQLite index is a rebuildable mirror (OPEN_QUESTIONS R56, R64, R65) |
| docs/APP_LOGIC.md | View models for the track pickers, Now Playing, skip and Up Next buttons, library screens (R52, R55) |
| docs/SFTP_CITADEL.md | Citadel SFTP backend, timings, pin, patch (R29, R51) |
| docs/TEST_ENVIRONMENT.md | Why WSL dies (Windows virtual memory) and the steps for the user |
| docs/NAMES.md | Names rule: real names for formats, servers and services, neutral app identity, the machine-readable allowlist the lint reads, the About trademark text and owner pages (item 19 below) |
| docs/spikes/FFMPEG_TVOS_CANDIDATES.md | Prebuilt LGPL FFmpeg for tvOS: comparison and recommendation (R50) |
| **Spec change recorded openly** | "Offline downloads" (docs/FEATURE_BACKLOG.md) is now "prefetch to cache, best effort, never promised" because tvOS cannot keep local files (R57). The Next Episode spec text lives in docs/PLAYBACK_LOGIC.md (R49) |


## Platform decisions (PROVISIONAL)

Source: docs/PLATFORM_AUDIT.md (every Apple claim there carries its link; anything not read is marked UNVERIFIED). Nothing below is compiled or run on an Apple TV. Each line names the alternative. These are decisions D1 to D10 in the audit; none changes an existing row above.

1. **System player features and voice commands.** Primary engine plays through `AVPlayerViewController`; the loopback HLS is seekable VOD and supplies `externalMetadata` (title, subtitle, artwork, description, genre, rating). The app does not publish to `MPNowPlayingInfoCenter` itself for the primary engine; AppLogic's NowPlaying mapping applies to the fallback engine through `MPNowPlayingSession` and `MPRemoteCommandCenter`. Alternative: publish ourselves (rejected: duplicates AVKit). Device test for every voice phrase.
2. **Subtitle menu (D1, D5).** Text subtitles (SRT, ASS, SSA, WebVTT) are converted to WebVTT and served as `EXT-X-MEDIA TYPE=SUBTITLES` renditions so the system menu, "What did they say?" and the system caption style apply. PGS and other picture subtitles are drawn by our overlay and chosen from one custom transport-bar menu; picking one source turns the other off. ASS styling is flattened. Alternative: draw all subtitles ourselves (keeps ASS styling, loses the system features). This reverses the "app draws them itself" note in `Playlist.swift` and the REMUX spike line; the parent decides when.
3. **Remotes and controllers.** Standard Siri Remote behaviour only, system focus engine, no custom gestures; Space on a Bluetooth keyboard checked on device; iPhone remote and Control Center remote device-tested; game controllers: no code (D4). Alternative: map A and shoulders to play/pause and skip.
4. **Picture in Picture (D3).** Adopt for the primary engine (Background Modes > Picture in Picture, `.playback` audio session, a delegate object outside the view hierarchy, fast UI restore). Loopback server and read-ahead keep running while in PiP. No PiP for the fallback engine. Alternative: no PiP.
5. **App lifecycle.** Save position locally every 10 s while playing and on pause, seek end, resign active, PiP stop, background; CloudKit on pause, stop and at most once a minute. Resume without a prompt; "Play from beginning" is a separate Info-tab action. Never set `isIdleTimerDisabled`. Pause on route loss and interruption. Scene-based lifecycle (required by tvOS 27 per its release notes).
6. **Audio routes.** Honest status text is built from the port type and channel count the OS reports; route changes update the text within a second and do not restart playback; no eARC, HomePod-pair or Wireless Audio Sync claims until device-tested.
7. **Display.** Primary engine applies display criteria automatically; the fallback sets `preferredDisplayCriteria`; status says when Match Content is off. **No HDR10+ claim anywhere** (no Apple page read supports it). Read-ahead is a configurable budget with a conservative default and a memory-warning shrink; no per-model constants until measured.
8. **Text entry.** Standard fields only, `.bordered` style on tvOS 27; setup order: Bonjour pick, then host, then credentials; a pasted URL is split into fields.
9. **Accessibility.** System text styles, system colours, labels on every control and poster, Reduce Motion and Increase Contrast respected, Nutrition Label claims limited to what the device checklist proved.
10. **App Store readiness.** docs/APPSTORE_READINESS.md: two privacy manifests (app, Top Shelf) plus any binary dependency that uses required reason APIs; export compliance (`ITSAppUsesNonExemptEncryption` is `false` today and is probably wrong, D7); privacy label (D10); age rating 4+ (D9); a reachable test server for App Review.
11. **Background work (D8).** Not relied on. Library sync while the app is open and on foreground; Top Shelf shows what the app last wrote to the App Group. Alternative: a `BGAppRefreshTask` as a bonus.
12. **System profiles, multi-user (D2).** One library and one watch history per device; no Runs as Current User entitlement in v1; two-user switching tested on a device. Alternative: adopt the entitlement and a user-independent Keychain for per-user data.
13. **Apple TV app integration.** Not possible for this app (Video Partner Program is for premium subscription video services on iOS and tvOS; individual-developer eligibility not addressed on the page; nothing was asked of Apple). Substitutes: Top Shelf, deep links (mechanism UNVERIFIED), App Intents Video schema (tvOS 27.3 beta 2 only, behind `#available`), in-player Up Next.
14. **Liquid Glass and tvOS 27.** System components only for navigation, buttons, player; no Liquid Glass in the content layer; Playback Stats uses a standard material. Newest Codemagic image read: Xcode 27.2 (tvOS 27.2 runtime, Apple TV 4K 3rd and 4th generation simulators); Xcode 27.3 is not on a page read. APIs newer than the deployment target sit behind availability checks.
15. **Passwords on tvOS (D-KC1, PROVISIONAL option B).** Local Keychain copy plus a mirror in CloudKit encrypted fields (`encryptedValues`, tvOS 15+) in the private database. A reset of the user's encrypted data key removes the cloud copy; the app uploads the local ones again. After a device reset the cloud copy restores them. Settings says this in plain words. Alternative A: Keychain only. OPEN_QUESTIONS.md R71.
16. **App screens.** Native components only, system look, no custom colours or fonts (docs/DESIGN_SYSTEM.md). Only WebDAV connects in this version; Discover, online lookups, artwork, MKV playback, Skip and Up Next are shown honestly as "not available yet" (OPEN_QUESTIONS.md R74). PROVISIONAL.
17. **Apple TV app integration (answer).** Confirmed again 2026-11-17 against developer.apple.com/programs/video-partner/: the programme is for apps delivering premium subscription video services. This app plays the user's own files, so it does not apply. Same as item 13.
18. **Test health.** Every test stage reports per-target counts and fails loudly below a recorded floor (`scripts/test-counts.sh`, `scripts/test-floors.txt`). OPEN_QUESTIONS.md R78.
19. **Names (user rule, 2026-11-17; replaces the earlier "brandless" rule, R91 and R102).** The app's own name, icons, colours and wording stay neutral; no logo or icon of any company or product anywhere (text names only), except TMDB's logo, which TMDB's terms require: shown unaltered only in Settings > About > Data Sources next to the TMDB notice (user decision 2026-11-17, OPEN_QUESTIONS R148); no wording that suggests the app is made, certified or endorsed by, or affiliated with, any company; no mention of other media-player applications in code, comments, UI or docs. Every format, server, service and Apple technology the app plays, connects to or relies on keeps its real name (Dolby Vision with its profiles, Dolby Atmos, DTS-HD Master Audio, HEVC, AV1, WebVTT, PGS, WebDAV, SMB, UPnP/DLNA, Jellyfin, Emby, Plex, OneDrive, TMDB, OMDb, IMDb, Rotten Tomatoes, JustWatch, AirPlay, Siri Remote, iCloud, Top Shelf, HDMI and the rest). Claims stay honest ("Dolby Atmos (Dolby Digital Plus, passed through)", never "Dolby Certified" or "Works with Plex"). Settings > About has a Trademarks and Attributions section, an Open Source section with the written LGPL source offer (R149, PROVISIONAL) and a Full Licence Texts screen with every licence text bundled in the app. The allowlist, the About text with the owner pages, every owner requirement and every replaced name are in docs/NAMES.md; the lint rules are `unknown-name`, `claim-wording` and `brand-logo` (docs/DESIGN_SYSTEM.md D-DS7 and section 10).
