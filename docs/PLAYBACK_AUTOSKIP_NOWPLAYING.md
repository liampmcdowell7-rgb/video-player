# Auto skip, binge playback, on-device detection and Now Playing

Status: **built 21 Nov 2026** (owner's request of 21 Nov 2026: "They're no longer plan-only"), not yet run on a device.
Section 0 says what was built and how detection works; R314 to R317 in OPEN_QUESTIONS.md record the decisions. Sections
1 to 12 are the plan of 20 Nov 2026, kept as written for the history; where section 0 differs, section 0 holds.

## 0. What was built (21 Nov 2026)

**Settings (R314).** Settings > Playback: "Skip Intros Automatically" (on by default) and "Skip Credits Automatically"
(off by default), system Toggles under "Show Skip Buttons". Off: the Skip Intro / Skip Credits button as before. On:
the segment is skipped without a press, and for 5 seconds after the skip a system contextual action "Watch Intro" (or
"Watch Recap", "Watch Credits") goes back to the start of the segment, which then plays through. That way back is the
reference player's behaviour, decided by the owner's standing rule R312.

**Which segments may skip by themselves (R314, R288).** The file's own data (chapters, sidecar files, the user's marks)
and the media server's markers; on-device detection once two other episodes agree (confidence 0.9); online timings
(IntroDB) only when the on-device comparison found the same stretch within 1.5 s at both ends. Every other segment
shows the button instead, or nothing when Show Skip Buttons is off.

**Binge (R314, R340).** The system Up Next card appears at the credits start, or at the end of the file when no credits
segment is known, and counts down 10 s when "Play Next Episode Automatically" is on (the master switch; off, the card
waits for a press). The next episode then skips its intro from its first second when Skip Intros Automatically is on.
With Skip Credits Automatically on, the credits jump to the end and the card appears at once.

**Order of sources (R315, R289).** The user's marks, sidecar files and chapters; then the media server's markers (Plex,
one read-only request per playback); then what this Apple TV learned; online timings are asked only when none of the
file's or the server's own data gave anything. Credited in the app as plain text: Plex, IntroDB.

**Detection on the Apple TV (R316).** Method:

1. While an episode plays, at background priority, the app reads the audio of that episode and of the next one: the
   intro window (first 10 minutes or first quarter, whichever is shorter) and the credits window (last 10 minutes or
   40 %), as mono samples at 11 kHz through the system's audio reader.
2. Each window becomes a fingerprint: the audio is reduced to about 5.5 kHz, cut into frames of 0.37 s every 0.19 s, and
   each frame gives one 32-bit word recording, for 33 bands between 300 and 2000 Hz, whether the energy difference
   between neighbouring bands rose or fell since the frame before. The same sound gives nearly the same words wherever it
   sits and however loud it is; unrelated sound differs in about half the bits. Quiet frames never match.
3. Two episodes of one season are compared at every offset. The longest stretch whose words differ in at most 10 of 32
   bits (holes of up to 3 s allowed, at least half the frames matching, edges trimmed to where most frames match) is the
   part they share. An intro is 15 to 120 s long, credits 15 to 300 s; a longer match means the two files are the same
   recording and is ignored.
4. Each new episode is compared with up to four others of its season; each comparison is a vote for both. An episode's
   segment is the median of the largest group of votes that agree within 1 s. Confidence: 0.75 after one vote (the
   button only), 0.9 after two (skips by itself), 0.02 more per further vote, at most 0.98. So it gets better as more
   episodes are played.
5. One JSON file per season in the app's caches folder, named by a hash (no title appears in a file name). The newest 8
   episodes keep their fingerprints for later comparisons; older ones keep only their votes. Nothing is sent anywhere.

Limits: it needs at least two episodes of a season that share the same theme or credits music; it finds no recap and
never counts a cold open as part of the intro; credits without shared music (a different song each week) are not found;
files the system player cannot open itself (Matroska played through the app's own remux, sources read byte by byte) are
not analysed; the system may empty the caches folder, after which the season is learned again. UNVERIFIED until a device
run: whether the system's audio reader reads a file over HTTP (Plex, WebDAV) at all, how long the two windows take and
how much they cost on the network, and the accuracy on real episodes. The tuning values are first guesses (PROVISIONAL).

**iPhone Now Playing (R317).** Apple's pages (read 21 Nov 2026): the system player view controller "manages its own
player and Now Playing session", so the app cannot add its own; `updatesNowPlayingInfoCenter` is not on tvOS. What the
app supplies: the item's metadata, title = the episode's name, second line "Show · S1, E3" (R313), and the poster as
artwork. What the system supplies by itself: duration, elapsed time and rate from the player, and the answers to play,
pause, scrubbing and the 10-second skips from the iPhone. The Apple TV Remote on the iPhone and its volume buttons are
system features (volume only with a receiver or TV that supports it). The app registers no remote commands and sets no
Now Playing values of its own, which would compete with the system's entry. All of it is UNVERIFIED until the device
check in section 11.

**Tests (Linux, synthetic data).** `AudioDetectionTests` (fingerprints and the season memory on generated audio),
`SegmentDetectionTests` (the store on disk, the collector, the provider), `AutoSkipTests`, `BingeTests`,
`PlexMarkerTests` (hand-written answers, fake server only).

## Plan of 20 Nov 2026 (history)

Status then: **plan, no code** (owner's request of 20 Nov 2026). Every decision below is PROVISIONAL (except R288 and R290, decided by the owner on 21 Nov 2026) and has an R number in
OPEN_QUESTIONS.md (R-rows listed in section 12). Nothing here is built. Brandless rule: this document names no other
media-player app; behaviour is described generically. Data providers appear only as plain-text names, as
docs/NAMES.md allows (IntroDB is already on its allowlist; other names in section 8 are research notes, not app text).

**Gate (no stage starts before both):** the R273 field fix is seen working in a screenshot run
(11-form-webdav-FIELDS-AT-REST passes), and the build-number fix (R279) is committed. Status: both met (the simulator
run of 20 Nov 2026 passed 11-form-webdav-FIELDS-AT-REST; R279 committed locally, not yet pushed); no stage starts
without the owner's go-ahead.

Owner's words (20 Nov 2026), in summary: a setting to skip intros and credits automatically, or keep the button;
pressing the button every time is annoying. At the end of an episode go straight to the next one, then skip that
episode's intro. Full Now Playing control from an iPhone: timeline, skip ahead or back, the Apple TV remote, the volume.
If nothing out there shares the necessary data, the app should detect it itself and learn to be smarter; open data can
serve as a baseline.

## 1. What exists today (audit of 20 Nov 2026, from the code)

**Segment data.** Models: `Packages/VideoPlayerCore/Sources/PlaybackLogic/Segments.swift` (`SegmentType` recap, intro,
credits; `SegmentSource` with a priority order on-device detection < online database < sidecar < chapters < user mark;
`SkipSegment`, `SegmentLimits`), merging in `SegmentMerge.swift`, collection in
`Sources/AppLogic/SegmentSourcing.swift` (`SegmentCollector`, 6 s deadline). There is no per-source segment code: every
source goes through the generic `MediaSource.list` and `read(range:)`.

| Where segments come from | State |
|---|---|
| MKV/WebM chapters named Intro, Recap, Credits (`MatroskaReader`) | built; MP4 chapters not built |
| Sidecar files `.edl` and `.segments.json` next to the video (`SidecarSegments.swift`) | built |
| The user's own marks (`UserData/SegmentMarks.swift`, `AppLogic/SegmentMarkFlow.swift`, `App/Features/Player/PlayerMarkMenu.swift`) | built |
| Online community timestamps: IntroDB (`MetadataOnline/IntroDBClient.swift`, `AppLogic/OnlineSegments.swift`, wired in `App/Support/OnlineServices.swift`) | built; asked only when nothing else gives a segment and only while Free Data Sources is on (R208, R209, R221) |
| Jellyfin and Emby media segments | not built (nothing in `SourceJellyfin`, `SourceEmby`) |
| Plex markers | not built (no Plex source code; docs/PLEX_SOURCE.md) |
| On-device detection | not built (backlog item 34) |

Out of date and to fix in the first stage: docs/SEGMENTS.md and FEATURE_BACKLOG item 33 say online lookup is "not
built", and the Settings text `SettingsTexts.skipFull` says online markers are "not available yet".

**Skip buttons.** `App/Features/Player/SkipButtonPresenter.swift` sets the system player's `contextualActions` (one
`UIAction`) only while the playhead is inside a segment: the system's own button, no custom chrome. `SkipSetting` has
`ask`, `automatic` and `off` (`PlaybackLogic/SkipController.swift`), but Settings shows one switch, **Show Skip
Buttons** (on), which maps only to ask or off (`AppLogic/NextEpisodeFeed.swift`). **Automatic exists in logic, not in
Settings.**

**Next Episode (R49).** `PlaybackLogic/NextEpisode.swift`: `NextEpisodeMachine`, modes when credits begin, when the
episode ends, ask, off; countdown 0 to 30 s (default 10); `EpisodeOrder.next` takes the lowest later episode of the same
season, then the first episode of the next season, never advances from season 0. `App/Features/Player/ProposalPresenter.swift`
uses the system `AVContentProposal` with automatic acceptance off (`automaticAcceptanceInterval = .nan`).
**Missing, found in the audit:** `PlayerCoordinator.handle` acts only on seek and mark-watched; the advance effect falls
into `default: break`, so **the next episode never starts**; the overlay's `tick()` is never called, so a countdown never
fires; the overlay's effects reach `handle` twice (a seek may run twice). These are bugs to fix in the binge stage.
**Fixed by R340 (owner decision of 21 Nov 2026):** the advance effect now plays the next item (`PlayerCoordinator.play`,
`PlayerScreen` resolves it and the old playback stops first, so its position is saved and the watch sync is told);
the effects reach `handle` once (through the overlay's sink only); the countdown is the system's own
(`AVContentProposal.automaticAcceptanceInterval`, the logic in Ask mode), so the overlay's `tick()` is no longer needed.

**Settings > Playback** (`App/Features/Settings/PlaybackSettingsView.swift`, `@AppStorage`): Auto-Play Next Episode (on:
when credits begin; off: ask), Show Skip Buttons (on), Playback Stats button (on), Remember Track Choice per Show (on),
TrueHD compatibility core (off). No per-kind skip setting, no Next Episode mode or countdown row. The ledger's
`setSetting` is never called, so these settings are not synced between devices.

**Now Playing.** No use of `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` or `MPNowPlayingSession` in the code
(only comments in `PlayerCoordinator.swift`; an unused key mapping in `AppLogic/NowPlaying.swift`). The player publishes
`externalMetadata` (title, series title as subtitle, artwork) on the `AVPlayerItem` (R157). No remote command is
handled by the app.

**The app's own remux.** `Pkg/RemuxEngine/Loopback.swift` (HTTP server on 127.0.0.1, secret path), used by
`App/Features/Player/RemuxPlayback.swift` when `AppServices` picks the remux route. It still plays in
`AVPlayerViewController`, so it gets the same treatment as direct play. There is no second player (no non-AVPlayer
renderer in code; the fallback engine exists only in docs/SPECS.md D1, D4).

**Building blocks for detection.** Ranged reads over every source: `MatroskaReader`, `SegmentCollector.readSidecars`,
the RemuxEngine readers with a block cache. No use of AVAssetReader, Accelerate/vDSP, Sound Analysis, Vision or Core ML.

UNVERIFIED in the audit: whether Jellyfin and Emby listings ever return sidecar files; whether `SourceRangeProxy` is wired
in the app; the full text of docs/PLAYBACK_LOGIC.md, docs/BACKUP.md, docs/STORAGE_MODEL.md.

## 2. Auto skip setting (R280)

Settings > Playback gets two rows, **Skip Intro** and **Skip Credits**, each a system `Picker` with three choices:
**Off** (no button, no skip), **Show Button** (the system contextual action, as today), **Automatic** (skip without a
press). Recap follows Skip Intro (it sits at the start too). Provisional default: Show Button for both, so nothing skips
unexpectedly; the owner is expected to choose Automatic. The existing Show Skip Buttons switch is replaced (on maps to
Show Button, off to Off), so no setting is lost.

Automatic skip rules (all offline-testable in `SkipController`): skip once per segment per play; never skip when the
user scrubbed into the segment (they chose to be there); never skip past the end of the file; only with a segment whose
confidence is high (section 6); otherwise show the button. After an automatic skip: section 7.3.

Alternatives: (a) one combined switch for all segments; (b) Automatic as the default; (c) settings per source or per
show; (d) keep the single switch and add Automatic as its third state.

## 3. Binge playback (R281)

What the system gives (Apple pages read 20 Nov 2026): `AVContentProposal` (tvOS 10.0+), set as the current item's
`nextContentProposal`, with a transition time, title, preview image and URL; `automaticAcceptanceInterval` shows a
countdown and accepts at its end ("Set this value to nan to disable"); the app subclasses
`AVContentProposalViewController` for the card; the player delegate is told when a proposal is presented, accepted or
rejected (`shouldPresent`, `didAccept`, `didReject`). `MPNowPlayingInfoPropertyCreditsStartTime` tells the system where
the credits start. The HIG "Playing video" page has no guidance on next episode or skip buttons.

**R340 (built, owner decision of 21 Nov 2026):** the system Up Next. The playback logic runs in Ask mode
(`PlayerSessionFactory.systemUpNextSettings`): it presents the card at the credits start (or the end) and waits. With
Auto-Play Next Episode on, the proposal's `automaticAcceptanceInterval` makes the system accept 10 s after the card
appears (`UpNextCard.acceptanceInterval`; negative while the credits run, as Apple's article uses -1.0); off, it is NaN.
The card is `UpNextProposalController` (an `AVContentProposalViewController` subclass, the layout of Apple's article:
the video at 960 x 540 at the top, Play Now and Cancel below; the countdown text read from the playhead). Accept, by a
press or by the system, reaches the logic through the delegate's `didAccept`; the advance plays the next item, which
resumes at its saved position. UNVERIFIED until a run on tvOS 27: whether the system's own acceptance calls `didAccept`,
whether the system also draws a countdown on the card, and the card's look. Not built here: the countdown row, the 0 s
"straight to the next episode", "Are you still watching".

Plan: a separate **Auto-Play Next Episode** switch (exists) plus the existing modes, now with a countdown row. With
Auto-Play on: at the credits start (or the end, when no credits segment exists) the proposal card appears with the
system countdown; at zero, or on accept, the next episode starts; it then applies the Skip Intro setting from its first
second. Countdown 0 means "go straight to the next episode" with no card. The app must add: the missing advance and
tick wiring (section 1), loading the next item, resuming at its saved position, and stopping after the last episode of
the last season (no proposal; credits play to the end). Native only: the system proposal and player, no custom overlay.

Alternatives: (a) no countdown at all by default (straight to the next episode); (b) countdown 10 s (today's default);
(c) "Are you still watching" after N episodes (not planned; listed so it is not lost); (d) Auto-Play off by default.

## 4. Segment sources and the order of use (R282, R289)

Sources that can supply segments: Plex markers (intro and credits, documented by Plex; field names UNVERIFIED, see
docs/PLEX_SOURCE.md section 9); Jellyfin and Emby media segments (server API; field names UNVERIFIED, not read for this
plan); MKV chapters titled Intro, Recap or Credits (built); MP4 chapters (not built); sidecar files (built); community
timestamps (section 8); the user's own marks (built); on-device detection (section 6).

**Order of use per item (PROVISIONAL, R289; replaces the order of the first addition):**
1. segment data the source provides (server markers or segments, chapters, sidecars; the user's explicit marks rank here
   too, as today);
2. what the app learned from the owner for this show (section 7);
3. community timestamps that passed the match check (section 8.3);
4. on-device detection (section 6);
5. nothing: **no skip and no button**. The player says nothing; a missing button is the honest answer.

The player's info panel shows one plain line per item, for example "Intro: from the server", "Intro: from chapters",
"Intro: learned from you", "Intro: community timestamps", "Intro: found by the app", "Intro: not known". UNVERIFIED: the
best native place for it (an info-view tab via `customInfoViewControllers`, tvOS 15.0+, or the Playback Stats page).

Alternatives: (a) community data before the owner's own learning; (b) on-device detection before community data;
(c) today's code order (user mark > chapters > sidecar > online > detection), with learning added under user marks.

## 5. Now Playing and remote commands (R283)

Apple (read 20 Nov 2026): `MPNowPlayingInfoCenter` (tvOS 5.0+) carries title, artwork, duration, elapsed time, rate and
default rate; `MPRemoteCommandCenter` (tvOS 7.1+) has play, pause, stop, toggle, skip forward and back with
`preferredIntervals`, change playback position, change rate, next and previous track; `MPNowPlayingSession` (tvOS 14.0+)
with `automaticallyPublishesNowPlayingInfo` (tvOS 16.0+). The `AVPlayerViewController` page lists
`updatesNowPlayingInfoCenter` for iOS, iPadOS, Mac Catalyst and visionOS, **not tvOS**, and the session page says the
player view controller "manages its own player and Now Playing session". So on tvOS the system player very likely
publishes Now Playing itself from the item and `externalMetadata`; **UNVERIFIED** until a device test, and the reason
this plan starts by testing before writing any publishing code.

Plan: (1) device test first (checklist, section 11) with the app as it is; (2) only for what is missing, publish by hand:
episode line (show, season, episode), duration, elapsed time and rate on every play, pause, seek and item change;
`MPNowPlayingInfoPropertyCreditsStartTime`; handle play, pause, toggle, skip forward and back (10 s, matching the Siri
Remote default), change playback position (scrubbing from an iPhone), next and previous track (next and previous
episode). The remux route is the same `AVPlayerViewController`, so it needs nothing extra; elapsed time is the item's
own time (the loopback is invisible to the system). Never claim a command works until the device test says so.

What the app does NOT control: the iPhone's Apple TV Remote and its volume buttons are system features. Apple's user
guide (support.apple.com, read 20 Nov 2026) lists play/pause, 10-second skips and subtitles in the iPhone remote, and
says the iPhone volume buttons work "only with supported audio/video receivers". The app's part is only to keep a
correct Now Playing state and handle the commands above. Whether the iPhone shows the app's Now Playing card and its
timeline: **UNVERIFIED until a device test**; no developer page about it was found.

Alternatives: (a) publish everything by hand from the start; (b) rely on the system only (no code); (c) adopt
`MPNowPlayingSession` (not possible with the system player view controller, per Apple's page).

## 6. Detection on the device (R284)

Used only when the source gives nothing, nothing was learned and no community timestamp matched (section 4).

**6a. Intro: episode comparison.** Compare the audio of the first minutes (provisional: 10 minutes or the first quarter,
whichever is smaller) of two or more episodes of the same season; the stretch that repeats is the intro. Method: decode
the audio to mono at a low rate, build a compact fingerprint per short frame (spectral peaks with vDSP FFT, tvOS 13.0+),
find the longest aligned run that matches across episodes (correlation); provisional length limits 15 s to 2 min. Sparse
frames only when audio is ambiguous. Needs at least two episodes of the season. The first episode watched has no partner
until a second one is analysed: no automatic skip; the button appears only once a partner confirms it (then also for
that first episode when it is played again). Costs: decoding about 10 minutes of audio per episode. UNVERIFIED: speed on
Apple TV hardware; whether AVAssetReader reads remote or loopback HTTP assets (its page mentions file-based media only),
so decoding may need the app's own demuxer and FFmpeg audio decoder that already exist for the remux.

**6b. Credits.** Signals near the end of the file (provisional: the last 10 minutes, or 15 for a film): a long
low-energy or silent gap, black frames, a sudden lasting change in the picture, and rolling text found by Vision
(`VNRecognizeTextRequest`, tvOS 13.0+, on device). A credits segment is proposed only when at least two signals agree.
Costs: sparse frames (provisional: one per 2 s) plus audio over the last minutes. UNVERIFIED: speed and accuracy; how
frames are decoded for the remux route (video decode outside the player).

**6c. Recap / "previously on".** No method better than guessing is known: **not planned**. Recaps still come from
sources, sidecars, user marks and community data.

**6d. What is read and when.** Only the first and last minutes of an episode, through ranged reads over the existing
`MediaSource.read(range:)`, never the whole file. For a container the app remuxes, the existing demuxer finds the byte
ranges of the wanted minutes from its index (cues), then reads only those. Network cost per episode: about 10 + 10
minutes of the audio track, plus the video packets only when frames are needed; for a 1080p file roughly a few hundred
MB at most for 20 minutes of video, much less for audio alone (an estimate; UNVERIFIED, depends on interleaving: audio
and video are interleaved, so reading audio alone may still read most of the bytes of that range). Time: UNVERIFIED.

When to analyse (docs/SPECS.md D8: background work is not relied on): (a) analyse the next episode while the current one
plays (provisional choice); (b) analyse while the app is open and idle; (c) on demand from the episode's menu. Whether
tvOS allows any of this outside playback, in the background: UNVERIFIED; the plan does not rely on it.

Alternatives for detection as a whole: (a) intro only, no credits detection; (b) no on-device detection (only sources,
community data and marks); (c) a trained model later (section 9).

## 7. Learning from the owner (R285)

On the device only. Signals: where the owner presses Skip; where the owner scrubs back after an automatic skip (it skipped too far) or
forward right after one (too little); where the owner stops or presses next during credits. Adjustment, simple and explainable:
per show and segment kind, a stored start and end time and a confidence value; each signal moves the stored time toward
what the owner did (provisional: halfway, at most 10 s per signal); agreement raises the confidence, disagreement lowers it;
automatic skip only above a threshold (section 10).

**7.1 Storage.** The ledger's existing user-data path in the owner's private CloudKit database (custom zone, private database
only; CloudKit tvOS 9.0+), mirrored like the other user data (R56, R65: the local SQLite index is a rebuildable mirror);
no outside server, no analytics, nothing shared. UNVERIFIED: the exact record type; whether it belongs in the existing
user-data zone or a new one.

**7.2 Visibility.** The info-panel line says "learned from you"; Settings gets "Forget Learned Skip Times" (per show and
all).

**7.3 After a wrong automatic skip.** Options: (a) provisional: a short "Skipped Intro" system contextual action for a
few seconds that goes back to the segment start when pressed (and counts as a disagreement); (b) no message, the user
scrubs back (also counted); (c) a short message without an action.

## 8. Community and open data baseline (R288, R290, R291)

### 8.1 Candidates (public documentation and licence pages only, read 20 Nov 2026; nothing downloaded, no API called)

| Candidate | Key | Covers | Answer | Licence and credit | Key or account | Rate limits | Maintenance and dump |
|---|---|---|---|---|---|---|---|
| IntroDB (already used by the app) | IMDb ID + season/episode | TV, movies | JSON: start/end in s and ms, confidence, submission count, updated time, "no intro / recap / outro" flags | Data ODbL 1.0, commercial use allowed; the open-data page asks for the credit "Contains data from IntroDB (introdb.app), available under the ODbL." and share-alike for the data; docs/DATA_SOURCES.md records credit as optional for API use | anonymous reads; submitting needs a key | on an "Errors and limits" page not read | live submissions, review queue with votes; daily CSV dumps (90 days kept) and a weekly release |
| TheIntroDB | TVDB ID first, or TMDB or IMDb | TV, movies | start/end in ms, arrays per kind | data licence: pages did not say; client code MIT, plugins GPL-3.0 | reads public; submitting needs a key | did not say | did not say; the site needs JavaScript and showed nothing (R216 already: not added) |
| AniSkip | not stated on official pages | anime openings and endings | not stated on official pages | code MIT; data licence and terms did not say | did not say | did not say | a weekly anonymised dump is mentioned in its repository; schema not shown |
| An open-source intro-skip plugin for Jellyfin servers | none (works on the server's own files) | TV, films | result format not described | GPL-3.0 (code only; a method reference; reusing its code in this app would need a licence decision) | — | — | active; documented defaults: intros within the first quarter or 10 minutes, 15 s to 2 min; credits 15 s to 5 min |
| Chromaprint (audio fingerprint library) | none | audio | fingerprint format not described | licence not on the page read | — | — | version 1.6.2 |
| Research paper, arXiv 2504.09738 (CC BY 4.0) | — | 972 episodes | per-second classifier, F1 91.0 % | paper CC BY 4.0; dataset release not stated | — | — | — |

No source gave average intro start times or lengths. A WACV 2021 paper page returned HTTP 403. Pages that did not load
or did not say: theintrodb.org docs and terms (JavaScript only), the AniSkip API docs (empty), the AniSkip common
repository (no specification), the dump repository (no licence or schema), the Chromaprint page (no licence, no format),
the plugin repository (no result format or thresholds).

### 8.2 Three ways to use it (R288)

**Decided by the owner, 21 Nov 2026 (R288):** (a) lookup at playback time behind the existing **Free Data Sources**
switch (off by default), plus (c) priors. Only the show's ID, season and episode are sent; answers are cached on the
Apple TV; typical intro and credit lengths narrow the on-device detection; no automatic skip unless the on-device audio
check (8.3) agrees. No separate switch, no default ON, no shipped snapshot. The options below are kept as history.

**(a) Lookup at playback time** (what the app already does for IntroDB, behind Free Data Sources). Sends ONLY the show's
IMDb ID, season and episode (today also the app's User-Agent with name, version and repository address); nothing about
the owner, the device, the source or the file name. Cached on the device (today 7 days, "none" 1 day); works without
the network when nothing is cached (no button). Settings: either the existing **Free Data Sources** switch (OFF by
default, R209) or a separate **Use Community Timestamps** switch (provisional default OFF until the owner says
otherwise). Alternatives: default ON; no lookup at all.

**(b) A snapshot shipped in the app.** No contact at run time, but a download at development time that only the owner
can approve: the IntroDB daily `segments.csv.gz` (and `segmentless.csv.gz`) from its open-data page, size not stated on
the pages read (UNVERIFIED). On the device: the whole table or only shows in the library (UNVERIFIED size). Problems: it
is out of date from day one and needs a new app release to update; the ODbL share-alike and credit apply to the shipped
database. Not done; listed for the owner.

**(c) Priors only.** No lookup: published typical limits (for example intros within the first quarter or 10 minutes,
15 s to 2 min; credits 15 s to 5 min, from the plugin's documented defaults) only narrow where on-device detection looks.
No outside contact, no licence beyond citing the numbers' source.

### 8.3 Matching a community timestamp to the owner's file

Timestamps belong to one cut of an episode. Checks: (1) when the data carries a duration, the file's duration must be
within a few seconds (IntroDB gives none, R208); (2) the returned end must fall inside the file (built, R221); (3) a short
audio check: the audio at the stated intro start should match the same moment in another episode of the season (the
section 6a fingerprint), or, when nothing else exists, at least not be silence. On a mismatch: never skip
automatically; show the button only if the owner's setting is Show Button, otherwise fall back to detection. A wrong
automatic skip is worse than none.

### 8.4 Licence, attribution and the brandless rule (R290)

**Decided by the owner, 21 Nov 2026 (R290):** a plain-text credit line in Settings > About, no logo: the same exception
the TMDB credit has, limited to that one line (docs/NAMES.md section 4 item 6). No snapshot is shipped (R288), so the
ODbL credit is not mandatory; the existing About line stays. The text below is the question as it was put.

IntroDB is already credited in plain text in Settings > About (`App/Support/Attribution.swift`), and its name is on the
docs/NAMES.md allowlist. The open-data page's ODbL credit ("Contains data from IntroDB (introdb.app), available under the
ODbL.") is a plain-text line; a line in Settings > About would carry it, without a logo. **Conflict flagged for the owner,
not decided:** the owner's brandless rule says no other company in the app's screens except TMDB (R148), while the app
already names IntroDB in About, and a snapshot (8.2 b) would make the ODbL credit mandatory. Any other dataset whose
licence needs a name or logo goes on the same open item.

### 8.5 Privacy (R291)

| Option | What leaves the device | How the owner sees and stops it |
|---|---|---|
| (a) lookup | IMDb ID, season, episode, the app's User-Agent (name, version, repository address); the network address, as with any request | Settings switch (Free Data Sources today); the info-panel line "community timestamps" |
| (b) snapshot | nothing at run time | nothing to switch |
| (c) priors | nothing | nothing to switch |
| on-device detection and learning | nothing (learning syncs only in the owner's private iCloud database) | "Forget Learned Skip Times"; detection can be switched off with the Skip settings |

Privacy label and manifest (docs/APPSTORE_READINESS.md sections 1 and 3): the manifests are not written yet; with no
analytics and no tracking, "Data Not Collected" stays the recommendation (D10, open). Whether a lookup keyed by a public
show ID counts as collected data: UNVERIFIED (Apple's privacy-label pages not read for this plan).

## 9. Trained models (R286)

No trained model exists in the repository, none may be downloaded, and the owner has no Mac for Create ML training.
Core ML (tvOS 11.0+, on device) and Sound Analysis (tvOS 13.0+; the built-in classifier "can identify over 300 sounds")
are a later alternative. A model would need: hand-marked training data (episodes with intro and credits times), a Mac
or a cloud training service, a size budget on the device (UNVERIFIED), and a licence for any model or data used. The
research paper in 8.1 reports F1 91.0 % with a large vision model, far beyond what this plan bundles. Nothing is bundled
or downloaded; the first versions use the explainable methods of sections 6 and 7.

## 10. Accuracy and tests (R287)

Measures, against hand-marked answers: (1) start and end each within N seconds (provisional N = 3); (2) share of items
found; (3) share of wrong automatic skips. Provisional targets: wrong automatic skips under 1 %; intros found in at least
80 % of seasons with two or more episodes. **Real accuracy is UNKNOWN** until the owner supplies real episodes (marked by
hand once). Because a wrong automatic skip is worse than no skip, the first version skips automatically only at high
confidence (provisional: two agreeing episodes and a match within 1 s) and shows the button otherwise.

Offline tests (Linux, like the existing package tests): synthetic fixtures generated by a script in the repository (no
downloads): a repeated jingle at different offsets across fake episodes, plus noise and a cold open; a black-frame and
text credits roll with silence; files shorter than the stated end; a mismatched cut. Each stage below adds its tests.

## 11. Device test checklist (owner, on the Apple TV and an iPhone)

Now Playing: the Now Playing card appears on the iPhone; scrub the timeline; skip 10 s forward and back; pause and
resume; next episode; volume (works only with a supported receiver, per Apple's guide); the iPhone's Apple TV Remote
opens and controls the app. Skipping, for each of Off, Show Button and Automatic: at an intro, at credits, and at the
credits of the last episode of a season (no next episode; credits play). Binge: an episode ends, the next starts and its
intro is skipped as set. Each result goes into docs/DEVICE_TEST_CHECKLIST_PLATFORM.md when the stage is built.

Added 21 Nov 2026 for what was built (section 0): with Skip Intros Automatically on, "Watch Intro" shows for about 5 s
after the skip and goes back; with it off, the button as before; with Skip Credits Automatically on, the card appears at
once and counts down; on a Plex show, the server's markers are used (File Details lists "Server markers: N"); on a show
without markers, after two or three episodes of a season "Found on this Apple TV" appears in File Details and the third
episode's intro is skipped; the iPhone's Now Playing shows the episode's name over "Show · S1, E3" with the poster.

## 12. Stages (each small, each with offline tests; none before the gate at the top)

1. **Segment data and settings:** fix the out-of-date texts; Skip Intro and Skip Credits pickers (R280); Next Episode
   countdown row; the info-panel line (R289); settings synced through the ledger.
2. **Now Playing:** device test first; publish only what is missing; remote commands (R283).
3. **Detection, intro by episode comparison** (R284 6a).
4. **Detection, credits** (R284 6b).
5. **Learning from the owner** (R285).
6. **Binge playback:** advance and countdown wiring, the double-effect bug, the last episode (R281).

Community data (R288) can join stage 1 (it already exists behind Free Data Sources): the owner decided R288 and R290 on
21 Nov 2026. Stage 1 adds the audio check of 8.3 before any automatic skip from community data.

## Sources read (20 Nov 2026)

Apple: AVPlayerViewController, AVContentProposal, MPRemoteCommandCenter, MPNowPlayingInfoCenter, "Becoming a now
playable app" (lists no steps on the page itself), MPNowPlayingSession, HIG Playing video (nothing on skip buttons or
next episode), AVAssetReader (does not say whether HTTP assets work), vDSP, Sound Analysis, Recognizing text in images
(no availability line; `VNRecognizeTextRequest` is tvOS 13.0+), Core ML, CloudKit; Apple TV User Guide on the iPhone
remote (support.apple.com). `contentProposalAcceptanceHandler` was not found on any page read. Community: section 8.1.
Read again 21 Nov 2026 for section 0: AVPlayerViewController (`updatesNowPlayingInfoCenter` availability, skipping
behaviour), MPNowPlayingSession, MPNowPlayingInfoCenter, MPRemoteCommandCenter, AVContentProposal.
