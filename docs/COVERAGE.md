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

### What the App syntax check can and cannot find (#23 B)

`scripts/parse-app.sh` (the "App syntax parse" line in every report) **only parses** each App/ and Top Shelf file. It
cannot find type errors: a wrong initializer or argument label, a missing import, an API that does not exist on tvOS, a
package symbol that is not `public`, a missing `await`, an Optional used as a value, an ambiguous type name. None of
those stop a file from parsing. The first CI compile of the App target (#23) failed on exactly such an error
(`Section("iCloud") { } footer: { }` in StorageSettingsView.swift), in a file the syntax check had passed. Only the
CI "Compile" job proves that App/ compiles; a passing syntax check proves nothing beyond "the file parses".
design-lint has one rule for that error class (`section-title-closure`); it is a pattern check, not a compiler.

### What each CI job proves when it is green (third compile check onwards, R161)

| Job | A green tick proves | It does NOT prove |
|---|---|---|
| 1. Simulator compile (unchanged) | Every App/ and Top Shelf file compiles for the tvOS Simulator (arm64), the app links and embeds the extension and frameworks for the simulator | x86_64 simulator (R159), a real device, anything at run time |
| 2. Device build (new) | The same for a real Apple TV in Release: the device slices of the 5 audio codec frameworks, libnfs, AMSMB2 and the Dolby Vision RPU library link; the extension embeds no frameworks; Release contains no UI-test sample data (R160) | Signing, provisioning, entitlements, that it launches |
| 3. Simulator package tests (new) | The package unit tests build for tvOS and pass on the Simulator (server, iCloud and tool tests skip) | Device hardware paths (decoders, HDR, network to real servers) |
| 4. Screenshots (new) | The app launches on the Simulator, every listed screen is reachable with the remote, and how each looks with sample data | Focus feel, HDR and colour on a TV, real servers, playback (no real video in the sample data) |

Jobs 2 to 4 first ran in run 44401030622 (commit 92f7724): launch OK, device-build inspection clean, 5 package-test
failures (fixed in ccf88b1), screenshots of 16 screens. A job proves nothing until a run of it is green.

### UI-test jobs: the split and the expected times (#24 B, 2026-11-19)

The run on fa00af8 delivered **no picture at all**: each UI job ran all its tests in one xcodebuild call, the time budget
stopped it, and the incomplete result bundle could not be exported. Since #24 every test is its own call
(scripts/ci-ui-tests.sh) and writes its pictures as PNG files too, so the pictures before a stop or a failure are kept.
The budget is **25 minutes from the start of the first UI test** (`CI_TEST_BUDGET_SECONDS` 1500); each job's hard cap is
60 minutes. Times marked "measured" are from fa00af8; the others are estimates.

| Job | Tests, in run order | Planned pictures | UI tests | Job, start to end (estimate) |
|---|---|---|---|---|
| Screenshots, part 1 | 01 (68 s), 02 (36 s), 03 (148 s), 05 (39 s), 12, 13, 14 (never reached on fa00af8: about 90 s each), 10 (312 s) | 5 + 12 + 16 + 7 + 6 + 8 + 6 + 20 = **80** | about 14:30 (10:03 measured + 4:30 estimated) | about 28 min |
| Screenshots, part 2 (`screenshots-library`) | 04 alone (436 s) | **26** | 7:16 measured | about 21 min |
| Accessibility screenshots | 06 (628 s), then 11 (about 315 s: half as many screens) | 22 + 11 = **33** | about 15:45 | about 28 min |

Before the tests every UI job spends about 12 minutes (fa00af8, measured: prepare 1:18, pick and boot 1:29, build
7:37-7:48, launch smoke 1:11-1:21; the accessibility job has no smoke). The collect, check and upload steps after the
tests take about 1-2 minutes. Each job stays well inside its budget (part 1 and accessibility use about 60% of the 25
minutes). Total planned: **139 pictures**. The plan is scripts/screenshot-plan.tsv; every index.md counts taken, missing
and failed pictures against it.

Two deviations from the #24 request, with the reason:
- test06 (Larger Text and Bold Text) and test11 (the default screens) share one job. scripts/ci-a11y-compare.py compares
  each Larger/Bold picture with its default one, so both sets must be in one folder; together they need about 16 of
  the 25 minutes. Each is still its own xcodebuild call, so a stop in test11 cannot lose test06's pictures.
- No shared build (one build-for-testing artifact for the three UI jobs). It would save about 2 × 7:45 of runner time
  per run, but the size of the build products has never been measured, and every UI job would wait for the upload
  first. ci-build-uitests.sh now prints the size (`build-products-size.txt` in each `-logs` download); decide from that
  number. Public repositories have no artifact-storage charge for standard use (unverified, from memory), but large
  artifacts slow every job down.

### What the ad-hoc signed simulator build cannot prove (stays unproven until a signed build runs on an Apple TV)

The screenshots job (job 4) signs the simulator app ad hoc: identity "-", no team, no provisioning profile, no certificate
(R164). **What run 44401030622 showed:** the ad-hoc build succeeded, but `codesign --display --entitlements` printed an
EMPTY dictionary, so the app carried none of the entitlements in project.yml. The app stayed up only because of the
launch-safety code (iCloud reported as not available, App Group checked before use). On top of that, every UI-test launch
(`-UITestEmpty`, `-UITestFixtures`) replaces iCloud with in-memory stand-ins, so the screenshots never touch CloudKit at
all. Apple does not say on any page whether the simulator applies entitlements from an ad-hoc signature (R164).

So everything below is **unproven** in every CI job and stays unproven until a build signed with the real team and a
provisioning profile runs on a real Apple TV (a development build first, then TestFlight):

| Area | What the app relies on | Why the simulator build cannot show it |
|---|---|---|
| **Entitlements and signing** | The four entitlements in project.yml (`icloud-container-identifiers` iCloud.com.liamp.videoplayer, `icloud-services` CloudKit, `keychain-access-groups`, `application-groups` group.com.liamp.videoplayer) and the Top Shelf extension's App Group | Nothing was embedded (run 44401030622). Whether the identifiers exist in the Apple Developer account, the profile matches them, the distribution certificate signs, and App Store processing accepts the build: none of it is exercised without a team and a profile (docs/CODEMAGIC_SETUP.md) |
| **CloudKit: the container** | `CKContainer(identifier:)` made lazily on first use (launch safety, R164) | Only the FAILURE path ran (no entitlement: "iCloud is not available"). The success path, a container that really opens, has never run |
| **CloudKit: account and data** | Account status, the private database, the `LibraryBackup` zone, `BKManifest` / `BKChunk` records and assets (docs/BACKUP.md), the user-data sync records, the iCloud copy of secrets the app mirrors | Needs a signed app, a signed-in iCloud account and the container's schema. Unknown: first-run zone creation, record size and quota limits, upload/download speed, the schema deployed to production, conflicts between two Apple TVs |
| **CloudKit: change notices** | `CKAccountChangedNotification` (name used as text, PROVISIONAL), any push that wakes the sync | Not delivered without the entitlement and a real account |
| **Backup restore at start-up** | Restore of an empty library before the start-up sync; the launch time-box (R169) | The time-box is unit-tested with a fake clock; the real timing with a slow or offline iCloud on a device is not |
| **App Group** | `containerURL(forSecurityApplicationGroupIdentifier:)` returns the shared folder; the app writes the Top Shelf snapshot and pictures there; the extension reads them | Without the entitlement the call returns nil (Apple's page for that method), so the app skips the Top Shelf write. Never seen: the folder existing, the extension reading it, the system purging it |
| **Top Shelf extension** | Loaded by the Home Screen when the app is in the top row | Not part of the app; UI tests cannot open the Home Screen (R161). Needs a device |
| **Keychain** | Source passwords and API keys stored per device (`KeychainCredentialStore`, not synchronised on tvOS per Apple's `kSecAttrSynchronizable` page), the shared access group for the extension | The simulator keychain is not the device keychain; with no `keychain-access-groups` embedded the items go to the app's default group. Unproven: the shared group, persistence across reinstall and updates, behaviour after a restore to a new Apple TV |
| **Local network** | Bonjour browsing (`NSBonjourServices`), the local-network permission prompt, SMB/NFS/WebDAV/SFTP to real servers | UI-test mode makes no network calls; the prompt is not answered in CI. Device checklists: docs/DEVICE_TEST_CHECKLIST_SOURCES.md |
| **Launch with everything present** | The normal launch path with iCloud, App Group and Keychain all available | CI only ever launched the app with all three missing or replaced |

What the simulator build DOES prove (when green): the app compiles, links and launches without crashing when none of
these is available, and every screen it can reach looks as the screenshots show.

### Unproven items and how each will be proven (#15 item 1.4, #16 item 1.8, 2026-11-18)

Each row stays **unproven** until the proof in the last column has been done and its result written here.

| Item | Why it is unproven now | How it will be proven |
|---|---|---|
| Entitlements under the ad-hoc signed simulator build (R164): CloudKit, App Group, Keychain | The CI build embeds no entitlements (table above) and UI-test launches replace iCloud | A team-signed build on a real Apple TV: docs/DEVICE_TEST_CHECKLIST_PLATFORM.md U1 (iCloud), U2 (App Group via Top Shelf), U3 (Keychain) |
| iCloud restore at launch (R169): the 8-second wait (`TimeBox.launchWait`) and the local copy shown first | Tested only with a simulated iCloud and a fake clock (AppLogic unit tests) | DEVICE_TEST_CHECKLIST_PLATFORM.md U4 (normal, slow and offline iCloud on a device) |
| Larger Text (the real setting) | The CI screenshots 80–84 and 90–95 IMITATE it: the app sets its own `dynamicTypeSize` to accessibility3 from a launch argument (App/Support/UITestAccessibility.swift). That proves the layouts at that size, not what the real setting does. tvOS has the real setting: Apple's guide names "Accessibility > Display" with "Text Size", a slider, and says "Apps that support Dynamic Type automatically adjust to the Text Size setting" (https://support.apple.com/guide/tv/display-bold-text-or-change-the-text-size-atvb0222141c/tvos) | DEVICE_TEST_CHECKLIST_VISUAL.md V-15 (Settings > Accessibility > Display > Text Size at its largest) |
| Bold Text (the real setting) | The CI screenshots 85–89 and 96–101 IMITATE it with SwiftUI `bold(_:)` (#17 A: setting `legibilityWeight` alone changed nothing in the app's text). Apple's pages do not say which weights the real setting gives; `scripts/ci-a11y-compare.py` only proves the imitation changes the app's text (each picture must differ from its default one, 102–112, outside the tab bar) | DEVICE_TEST_CHECKLIST_VISUAL.md V-16 (Settings > Accessibility > Display > Bold Text) |
| Increase Contrast | Device-only: the tvOS simulator cannot set it (`simctl` offers no option for it on tvOS). Since #24 no CI job tries (the accessibility-settings job is removed, OPEN_QUESTIONS R197) | DEVICE_TEST_CHECKLIST_VISUAL.md V-18 |
| Reduce Transparency | Device-only, same reason | DEVICE_TEST_CHECKLIST_VISUAL.md V-17 |
| Reduce Motion | Device-only, same reason; also cannot be judged from still pictures | DEVICE_TEST_CHECKLIST_VISUAL.md V-19 |
| The simulator retry in scripts/ci-sim.sh (8bb0f0c) | Passes its self-test with a fake `xcrun` (scripts/test-ci-sim.sh, 20 checks, in test-all.sh), but no runner has really failed to load the runtime since it was added | A CI run where it happens: the log shows `SIMULATOR RETRY: <reason>` (also a `::warning::` annotation) and the job summary shows `Simulator ready after N s (retries: 1/1)`. Not a device item |
| Pictures after a test run is stopped or fails (#24 A) | The run on fa00af8 lost every picture when the time budget stopped the one xcodebuild call per job. Now each test is its own call, writes PNG files, and its pictures are copied right after it; at the budget the running test gets SIGINT and 60 s to finish its bundle. Passes its self-tests with a fake xcodebuild (scripts/test-ci-ui-tests.sh 24 checks, scripts/test-ci-sim.sh 35, scripts/test-ci-artifact-contents.sh 19). Unproven on a runner: that xcodebuild hands TEST_RUNNER_SCREENSHOT_DIR to the runner as SCREENSHOT_DIR, that the runner can write that host folder from the simulator (else the simulator data folder is searched), and whether xcodebuild finishes the bundle on SIGINT | The next CI run: each UI job's log shows `SCREENSHOT FILES: <folder>` and `pictures from: host folder N, simulator data folder N, result bundle N`; every screenshot artifact has pictures and an index.md with the counts (or `TEST STOPPED BY THE TIME BUDGET: pictures up to <name>`). Not a device item |
| Statements about what Apple's own apps do | Several were written from memory | Marked "unverified, from memory" in docs/DESIGN_REFERENCES.md and docs/HIG_AUDIT.md, or given the Apple page that confirms them; checked against the system apps by V-08 to V-14 |

### Linux test counts: which command gave which number (addendum #18 A, 2026-11-18)

Two different numbers were reported because they came from two different commands:

| Number | Command | What it covers |
|---|---|---|
| 1,810 passed, 121 skipped, 0 failed | `scripts/test-all.sh` (unit stage: `swift test` over the whole VideoPlayerCore package, counted per target by `scripts/test-counts.sh`) | Every test target. Earlier run; its log was overwritten, so only the totals remain |
| 879 passed, 24 skipped | `vp-filter.sh` (a helper outside the repo that runs `swift test --filter` on a copy of the package) over 8 targets | Only the targets the per-file sorting change touched. Not a full run |
| **1,848 passed, 121 skipped, 0 failed** | `scripts/test-all.sh`, rerun for #18 A | Every test target, per target below |

| Target | Passed | Skipped | Failed |
|---|---|---|---|
| AppLogic | 336 | 0 | 0 |
| DolbyVisionRPU | 7 | 8 | 0 |
| LibraryBackup | 20 | 0 | 0 |
| LibraryIndex | 100 | 2 | 0 |
| MetadataLocal | 123 | 1 | 0 |
| MetadataOnline | 227 | 0 | 0 |
| PlaybackLogic | 163 | 0 | 0 |
| PlaybackStatus | 32 | 0 | 0 |
| RemuxEngine | 179 | 0 | 0 |
| SourceEmby | 27 | 11 | 0 |
| SourceFTP | 47 | 14 | 0 |
| SourceJellyfin | 27 | 11 | 0 |
| SourceLinks | 36 | 8 | 0 |
| SourceNFS | 34 | 13 | 0 |
| SourceOneDrive | 36 | 0 | 0 |
| SourceRangeProxy | 7 | 0 | 0 |
| SourceSFTPCitadel | 19 | 23 | 0 |
| SourceSFTP | 22 | 0 | 0 |
| SourceSMB | 20 | 11 | 0 |
| SourceUPnP | 32 | 9 | 0 |
| SourceWebDAV | 32 | 10 | 0 |
| Subtitles | 180 | 0 | 0 |
| UserData | 106 | 0 | 0 |
| VideoPlayerCore | 36 | 0 | 0 |
| **Total** | **1,848** | **121** | **0** |

Same run, other stages: live servers rclone 188, sftp 64, jellyfin 38, emby 38, smb 31, nfs 47, dovi 17, audio 38;
design-lint self-tests 147, App syntax parse 102 files, ci-inspect self-test 18, test-counts self-test 13.

- 1,848 − 1,810 = 38 new tests, the same 121 skipped: no test disappeared.
- The skips are the server, iCloud and tool tests that need something the Linux machine lacks (as before).
- `FixMatchTests` exists in both AppLogic and MetadataOnline. `test-counts.sh` maps by class name, so the 5 tests of
  one of them are counted under the other target; the two per-target numbers are off by those 5, the total is right.
  This is why AppLogic shows 336 here and 334 in the earlier report.
- Added after that run (later #18 commits, including 755de7f and ed59e32): LibraryIndex, AppLogic and LibraryBackup together went
  from 456 passed / 2 skipped to 473 passed / 2 skipped (`vp-filter.sh 'LibraryIndexTests|AppLogicTests|LibraryBackupTests'`).
  The full run was not repeated, so about 1,865 passed is expected but **not run**.

### Final Linux run for #19 E (2026-11-19, after c9ddcda)

`scripts/test-all.sh`, exit 0. Linux only: nothing here builds or runs the tvOS app (that needs the CI simulator).

| Target | Passed | Skipped | Failed |
|---|---|---|---|
| AppLogic | 381 | 0 | 0 |
| DolbyVisionRPU | 7 | 8 | 0 |
| LibraryBackup | 22 | 0 | 0 |
| LibraryIndex | 112 | 2 | 0 |
| MetadataLocal | 123 | 1 | 0 |
| MetadataOnline | 222 | 0 | 0 |
| PlaybackLogic | 163 | 0 | 0 |
| PlaybackStatus | 32 | 0 | 0 |
| RemuxEngine | 179 | 0 | 0 |
| SourceEmby | 27 | 11 | 0 |
| SourceFTP | 47 | 14 | 0 |
| SourceJellyfin | 27 | 11 | 0 |
| SourceLinks | 36 | 8 | 0 |
| SourceNFS | 34 | 13 | 0 |
| SourceOneDrive | 36 | 0 | 0 |
| SourceRangeProxy | 7 | 0 | 0 |
| SourceSFTPCitadel | 19 | 23 | 0 |
| SourceSFTP | 22 | 0 | 0 |
| SourceSMB | 20 | 11 | 0 |
| SourceUPnP | 32 | 9 | 0 |
| SourceWebDAV | 32 | 10 | 0 |
| Subtitles | 180 | 0 | 0 |
| UserData | 106 | 0 | 0 |
| VideoPlayerCore | 36 | 0 | 0 |
| **Total** | **1,902** | **121** | **0** |

Same run, other stages (all 0 failed, 0 skipped): live servers rclone 188, sftp 64, jellyfin 38, emby 38, smb 31,
nfs 47, dovi 17, audio 38; design-lint self-tests 200, design-lint on App/ clean, App syntax parse 109 files,
test-counts self-test 17, ci-inspect self-test 22, ambiguous-types 10, artifact-contents 14, ci-sim 20, a11y-compare 9,
stray-folder guard 1, playback-status doc table 1 (474 rows).

- 1,902 − 1,848 = 54 new tests, the same 121 skipped (the server, iCloud and tool tests that need what Linux lacks).
- The `FixMatchTests` name clash (above) is gone: bebc090 renamed AppLogic's class `FixMatchViewModelTests`, so its 5
  tests are now counted under AppLogic (381, matching `swift test --filter AppLogicTests`) and MetadataOnline shows
  its own 222 instead of 227. `scripts/test-counts.sh --duplicates` finds no shared class name.

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
| Discover, inside the Search tab while the field is empty (sections, Show Discover setting; R167 option (c), PROVISIONAL) | partly | see G18; the move is fixed in code, verify in next screenshots (06, 75) | docs/ARTWORK_DISCOVER.md, AppLogic/AppTabs.swift |
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
| docs/SORTING.md (per-file sorting into Movies, Shows and Needs Review, R171) | sorting rules, sort records (schema 3), overrides in the ledger, Jellyfin/Emby item types, Move form, online check and Needs Review list built and tested (WSL: 15 LibraryIndex, 7 AppLogic, 2 source tests); Needs Review screen, Move sheet, long-press items, How This Was Sorted, source setting and scan wiring built, device-only (never compiled, never run); online check never run against TMDB; sync of a Move between two Apple TVs unproven | checklist docs/DEVICE_TEST_CHECKLIST_SORTING.md SO1 ("flat mixed folder sorts into Movies and Shows") to SO14 |
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
