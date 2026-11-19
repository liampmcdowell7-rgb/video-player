# Names: real names for what the app plays and connects to, a neutral identity for the app itself

**The rule (user decision, 2026-11-17; replaces the earlier "brandless" rule everywhere, including R91):**

1. **Neutral and unbranded:** the app's own name and identity, icons, colours and wording. No logo or icon of any company or product anywhere (text names only; no brand logos, no brand-coloured badges). No wording that suggests the app is made by, certified by, endorsed by or affiliated with any company. No mention of other media-player applications as references, comparisons or inspiration, in code, comments, UI or docs.
2. **Always the real name** (nominative, descriptive use) wherever the user needs to understand what something is: video and HDR formats, audio formats, subtitle formats, source types and servers, data providers and services, Apple technologies, connectors. The allowlist below is the complete list of third-party names the UI may show.
3. **Required notices stay:** Settings > About > Trademarks and Attributions (section 3 below, verbatim).
4. **Honest claims only:** naming a format is not a claim of certification. Status text says what the app actually does ("Dolby Vision (converted from Profile 7)", "Dolby Atmos (Dolby Digital Plus, passed through)", "TrueHD Atmos plays as 7.1"), never "Dolby Certified", "DTS Ready" or "Works with Plex". The lint rule `claim-wording` checks this.

How the lint uses this file (`scripts/design-lint.sh`, rule `unknown-name`; exact rule text in the lint header and docs/DESIGN_SYSTEM.md section 10): every proper noun that names a third-party technology, service or company in a UI string must be in the `names-allowlist` block below. Ordinary words and the app's own terms that look like names to the lint's shape tests go in the `names-generic` block. Both blocks are read by the lint; keep one entry per line, `#` lines are headings. Adding a name here is a decision: add it only for something the app really plays, connects to, shows data from or runs on, and add its trademark owner to section 3 if the owner publishes a notice.

---

## 1. Allowlist (machine-readable)

```names-allowlist
# Video and HDR formats, codecs and containers
Dolby Vision
Dolby Vision Profile
HDR10+
HDR10
HLG
HEVC
H.265
H.264
AVC
AV1
VP9
VP8
MPEG-1
MPEG-2
MPEG-4 Part 2
MPEG-4
VC-1
EBML
Windows
Xvid
DivX
ProRes
Matroska
MKV
MP4
M4V
MOV
WebM
AVI
WMV
MPEG-TS
M2TS
HLS
fMP4
RPU
# Audio formats
Dolby Atmos
Dolby Digital Plus
Dolby Digital
Dolby TrueHD
Dolby
TrueHD Atmos
TrueHD
Atmos
AC-3
E-AC-3
DTS-HD Master Audio
DTS-HD High Resolution Audio
DTS-HD High Resolution
DTS-HD MA
DTS-HD HRA
DTS-HD
DTS:X
DTS-ES
DTS Express
DTS
MLP
MP2
AAC
HE-AAC
ALAC
FLAC
Opus
Vorbis
PCM
LPCM
MP3
# Subtitle and sidecar formats
SubRip
SRT
WebVTT
Advanced SubStation
SubStation
ASS/SSA
ASS
SSA
PGS
SUP
VobSub
TTML
CEA-608
CEA-708
NFO
EDL
# Source types and servers
WebDAV
SMB
NFS
SFTP
SSH
FTPS
FTP
UPnP/DLNA
UPnP
DLNA
Jellyfin
Emby
Plex
OneDrive
iCloud Drive
Dropbox
Google Drive
Google Docs
Google
Linux
rclone
# Data providers and services
TMDB
OMDb
IMDb
Rotten Tomatoes
Metacritic
JustWatch
TVDB
# Apple technologies
Apple TV 4K
Apple TV
Apple
tvOS
AirPlay
Siri Remote
Apple Account
Siri
iCloud
CloudKit
HomePod
Top Shelf
Picture in Picture
SharePlay
Bonjour
VoiceOver
Match Dynamic Range
Match Frame Rate
Control Center
Keychain
# Connectors and networks
HDMI
eARC
ARC
Wi-Fi
Ethernet
Bluetooth
# Open-source libraries named in the licence notices (Settings > About)
FFmpeg
dav1d
libzvbi
libdovi
libnfs
libsmb2
AMSMB2
Citadel
SwiftNIO
SwiftNIO SSH
Swift Crypto
libavcodec
libavutil
libswresample
VideoLAN
FFmpegBuild
zvbi
GNU Lesser General Public License
GNU
Apache License
Swift
# Trademark owners named in the notices (Settings > About)
Dolby Laboratories Licensing Corporation
Xperi Inc.
Xperi
Apple Inc.
HDMI Licensing Administrator, Inc.
HDMI High-Definition Multimedia Interface
HDMI Trade Dress
HDMI Logos
Microsoft
```

## 2. Generic terms (machine-readable)

Ordinary words, standard technical abbreviations and the app's own screen and feature names. These are not third-party names; they are listed only so the lint's shape tests do not report them.

```names-generic
# Standard abbreviations and technical terms
HTTP
HTTPS
URL
TLS
SSL
IP
ID
TV
OK
PIN
NAS
DNS
LAN
API
JSON
XML
CPU
GPU
UI
HD
UHD
SD
SDR
HDR
4K
8K
FPS
UTC
LFE
FEL
MEL
JOC
GB
MB
KB
TB
ms
SDH
US
GET
HEAD
GMT
SHA-256
SHA256
United States
# Version tags of the LGPL libraries in the written source offer (Settings > About > Open Source)
n8.1.3
v0.2.46
# Licence identifiers (SPDX-style), used in the licence notices
LGPL-2.1-or-later
LGPL-2.0-or-later
LGPL-2.1
LGPL
BSD-2-Clause
Apache-2.0
MIT
U.S.
# Parts of Matroska codec IDs compared in code (A_DTS/LOSSLESS, A_DTS/EXPRESS, "MA"): not shown as words
LOSSLESS
EXPRESS
MA
# The app's own neutral display name (not a brand: see docs/SPECS.md)
Video Player
# The app's own screens, sections and features
Review
# (the Needs Review screen, docs/SORTING.md; named inside the Online Lookup "What Is Sent" text, addendum #18 E)
Full Licence Texts
Intro
Recap
Credits
Home
Movies
Shows
Files
Discover
Search
Settings
Sources
Source
About
Online Lookup
Fix Match
Web Link
Playback Stats
Continue Watching
Next Up
Recently Added
Home Screen
Storage
Library
Playback
Accessibility
Your Data
Data Sources
Trademarks and Attributions
Open Source
Add a Source
Try Again
Play
Resume
Start Over
Play Again
Info
Up Next
Skip Intro
Skip Recap
Skip Credits
Bold Text
Reduce Motion
Reduce Transparency
Increase Contrast
Larger Text
Trust
Continue
Mark
Profile
English
Unknown
# Settings > Backup (iCloud backup of generated data, OPEN_QUESTIONS R163; the screen uses the real names iCloud and CloudKit, listed above)
Backup
Back Up Now
Restore from iCloud
Library Data
Artwork
Settings and Watch State
Last Backup
# The debug-only UI-test sample library (OPEN_QUESTIONS R160): ordinary words in its synthetic titles
Sample
Movie
Show
Season
# PNG chunk type names written by the sample library's picture generator (PNG specification, not brands)
IHDR
IDAT
IEND
```

---

## 3. Settings > About (verbatim as shipped) and the owner pages

Source of the texts: `App/Features/Settings/AboutView.swift`, `App/Support/Attribution.swift`,
`Packages/VideoPlayerCore/Sources/AppLogic/AboutNotices.swift`, `AboutText.dataNote` in `SettingsModel.swift`,
`App/Features/Settings/LicenseTextsView.swift`. One logo on the screen: TMDB's, in Data Sources (section 4 item 1).
Tests: `AppLogicTests/NamesTests` and `AppLogicTests/AttributionNoticeTests`.

**Version** (row) · **Your Data:** "Movie and show details can come from the files’ own information and from online lookups you allow. Nothing is sold or shared."

**Open Source:** "This app is open source and free. It plays videos you own from servers you set up." Then the written source offer, the five library rows and the repository line, word for word in section 4a.

**Data Sources:**
- "Pictures, matches, Discover and where-to-watch information come from TMDB, and only after you enter your own TMDB key in Settings > Online Lookup."
- [TMDB logo, `TMDBAttributionLogo`, VoiceOver label "TMDB"] directly above:
- "This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB."
- "Where-to-watch data is provided by JustWatch."

**Trademarks and Attributions:**
1. "This app is not affiliated with, endorsed by, sponsored by or certified by any company, project or service named in it. Names of formats, servers and services are used only to say what a file contains or what the app connects to; naming a format does not mean that this app or your equipment is certified for it."
2. "Dolby, Dolby Vision, Dolby Atmos, Dolby Digital, Dolby Digital Plus, Dolby TrueHD and the double-D symbol are trademarks or registered trademarks of Dolby Laboratories Licensing Corporation or its affiliates."
3. "DTS, DTS-HD, DTS-HD Master Audio, DTS-HD High Resolution Audio and DTS:X are trademarks or registered trademarks of Xperi Inc. or its subsidiaries in the United States and other countries."
4. "Apple, Apple TV, AirPlay, HomePod, iCloud, iCloud Drive, Siri and Siri Remote are trademarks of Apple Inc., registered in the U.S. and other countries and regions."
5. "The terms HDMI, HDMI High-Definition Multimedia Interface, HDMI Trade Dress and the HDMI Logos are trademarks or registered trademarks of HDMI Licensing Administrator, Inc."
6. "Microsoft, OneDrive and Windows are trademarks of the Microsoft group of companies."
7. "HDR10+, AV1, Plex, Jellyfin, Emby, Dropbox, Google Drive, Google Docs, TMDB, OMDb, IMDb, Rotten Tomatoes, Metacritic, JustWatch, Bluetooth, Opus, Vorbis, FLAC and all other names mentioned are trademarks or names of their respective owners."

**Open-Source Licences:** "This app includes the following open-source software, each under its own licence. The full licence texts are in Full Licence Texts below." Then a **Full Licence Texts** link (ten bundled texts from `App/Licenses`, listed in `LicenseNotices.texts`), then one row each (name; licence · use; copyright):
- FFmpeg (libavcodec, libavutil, libswresample); LGPL-2.1-or-later · Audio decoding; Copyright the FFmpeg developers
- dav1d; BSD-2-Clause · AV1 decoding inside the FFmpeg build; Copyright © 2018-2019, VideoLAN and dav1d authors
- libzvbi; LGPL-2.0-or-later (used under LGPL-2.1); ure.c under MIT · Teletext subtitles inside the FFmpeg build; Copyright the libzvbi authors
- libdovi; MIT · Dolby Vision metadata conversion; Copyright (c) 2025 quietvoid
- libnfs; LGPL-2.1-or-later · NFS sources; Copyright the libnfs authors
- AMSMB2 and libsmb2; LGPL-2.1 · SMB sources; Copyright the AMSMB2 and libsmb2 authors
- Citadel; MIT · SFTP sources; Copyright (c) 2022 Orlandos
- SwiftNIO SSH, SwiftNIO and Swift Crypto; Apache-2.0 · SFTP connections; Copyright Apple Inc. and the SwiftNIO project authors

PROVISIONAL: the licence list was read from Package.swift, the vendored packages' LICENSE files and
Packages/VideoPlayerCore/Frameworks (MediaCodecs/LICENSES, DolbyVisionRPULib-LICENSE.txt) on 2026-11-17; compare it with
the first archive's linked libraries. Alternative: a separate Licences screen (OPEN_QUESTIONS R129).

### Owner pages read (2026-11-17) and what each line follows

| Line | Owner page | What the page says / how the line follows it | Read? |
|---|---|---|---|
| Dolby | dolby.com site footer | Footer notice "... are trademarks or registered trademarks of Dolby Laboratories Licensing Corporation or its affiliates." Line follows it; Dolby Digital, Dolby Digital Plus and Dolby TrueHD added to the same sentence (PROVISIONAL; alternative: move them to line 7) | Footer read. Dolby's brand / trademark guidelines page: NOT READ (not reachable) |
| DTS / Xperi | xperi.com/media-kit | Notice form "... are trademark(s) or registered trademark(s) of Xperi Inc. or its subsidiaries in the United States and other countries." DTS-HD, DTS-HD Master Audio, DTS-HD High Resolution Audio, DTS:X added | Media kit read. dts.com/trademarks: NOT READ (page did not render) |
| Apple | apple.com/legal/intellectual-property/guidelinesfor3rdparties.html and the Apple Trademark List (appletmlist) | Notice form for material distributed outside the U.S. without trademark symbols; marks used as adjectives with the generic noun; no Apple logo; AirPlay badges are for licensees only (none used). Top Shelf is not on the list (named as a tvOS feature) | Read |
| HDMI | hdmi.org/resource/brand (HDMI LA brand page) | Notice copied word for word. Logos are for adopters only (none used) | Read. Adopter guidelines behind a click-through: NOT READ |
| Microsoft | microsoft.com/en-us/legal/intellectualproperty/trademarks (general usage guidelines) | Notice template "... are trademarks of the Microsoft group of companies."; compatibility statements allowed; no logos | Read. The trademark list PDF: NOT READ |
| TMDB | themoviedb.org/api-terms-of-use (section 3), themoviedb.org/about/logos-attribution, developer FAQ | Notice word for word ("application" chosen from the bracket list). **The terms also require the TMDB logo** (section 3); shown as the one logo exception (section 4 item 1) | Read (again 2026-11-17 for the logo) |
| JustWatch | developer.themoviedb.org/reference/movie-watch-providers | Watch-provider data must be attributed to JustWatch | Read |
| Plex | plex.tv trademark / partner pages | Pages returned HTTP 403. A forum post (not an owner page) says Plex icons are not allowed; not relied on | NOT READ |
| Jellyfin | jellyfin.org/docs/general/contributing/branding | Interoperability references by name are fine; logo has its own rules (none used) | Read |
| Emby | emby.media terms | No naming requirement found | Read |
| IMDb | imdb.com conditions of use | Bars using IMDb marks with non-IMDb products and commercial use of its data; ratings are not shown yet | Read |
| Rotten Tomatoes | rottentomatoes.com terms | Bars commercial use and republication; not shown yet | Read |
| Metacritic | metacritic.com terms | Page returned 404 | NOT READ |
| OMDb | omdbapi.com | Data under CC BY-NC 4.0 (non-commercial, attribution); no code calls OMDb yet | Read |
| HDR10+ | hdr10plus.org | Certification and logo are for adopters; no text rule for naming the format | Read (logo guide PDF NOT READ) |
| AV1 | aomedia.org trademark page | Accurate adjective use allowed | Read |
| UPnP / DLNA | openconnectivity.org; DLNA certification page (SpireSpark) | Notice text seen only in a search snippet; DLNA word-mark status UNVERIFIED | Partly |
| Xiph (Opus, Vorbis, FLAC) | xiph.org trademark notes | Only the logos are claimed | Partly (wiki NOT READ) |

## 4. Owner requirements for a logo, licence or specific wording (open for the user; nobody was contacted)

1. **TMDB logo: shown, the one logo exception (user decision 2026-11-17, OPEN_QUESTIONS R148).**
   - **Pages read (2026-11-17):** https://www.themoviedb.org/about/logos-attribution says "Below you will find some logos you can use within your application" and "every application that uses our data or images is required to properly attribute TMDB as the source"; it offers five SVG logos and lists the brand colours; it states no size, placement or alteration rule. https://www.themoviedb.org/api-terms-of-use (last updated 2023-10-20), section 3: "You must use the TMDB logo to identify Your use of TMDB, the TMDB APIs, or TMDB Content"; "Any use of any TMDB logos in Your Application must be less prominent than the logos or marks that primarily describe or identify Your Application and must make it clear that use of any TMDB logos does not imply any endorsement, certification, or other approval by TMDB"; the notice must be placed "prominently". Section 4 reserves TMDB's trademarks; the logos page is the permission to use the files in an application.
   - **File:** "Primary long (blue)", downloaded from https://www.themoviedb.org/assets/v4/logos/v2/blue_long_2-9665a76b1ae401a510ec1e0ca40ddcb3b0cfe45f1d51b77a308fea0845885648.svg (2,297 bytes; sha256 `9665a76b1ae401a510ec1e0ca40ddcb3b0cfe45f1d51b77a308fea0845885648`, which equals the hash TMDB puts in the file name). Stored unaltered as `App/Assets.xcassets/TMDBAttributionLogo.imageset/TMDBAttributionLogo.svg` (vector preserved). Not recoloured, not cropped, not re-encoded. Why this one: a horizontal logo sits naturally above a line of text.
   - **Placement and size:** only in Settings > About > Data Sources, directly above the TMDB notice; caption height (28 pt at the default text size, scaled with Dynamic Type), so smaller than the screen title and the app's own name (the "less prominent" rule); the notice next to it says TMDB does not endorse the app (the "no implied endorsement" rule). TMDB publishes no other size or placement rule.
   - **Lint:** `brand-logo` allows exactly this file at exactly this path on exactly this screen (sha256 checked); no `design-lint:allow` marker works for logos any more; fixtures prove that the TMDB logo on another screen, an altered copy, a copy in another catalog, an extra file in the set and any other logo on the About screen all fail (docs/DESIGN_SYSTEM.md section 10).
   - **Not verified:** whether the SVG's gradient (defined with a `<style>` element) renders correctly in an asset catalog on tvOS: device check N12. If it renders wrong, the fallback is a PDF made from the same file without changing colours, which needs your OK.
2. **OMDb / IMDb / Rotten Tomatoes / Metacritic ratings.** OMDb data is CC BY-NC 4.0 (non-commercial, attribution); IMDb and Rotten Tomatoes terms bar commercial use and republication. Nothing calls OMDb today and no ratings by these names are shown. **Before ratings ship:** the app must stay non-commercial and add an OMDb attribution line, or the feature stays off.
3. **LGPL libraries (FFmpeg, libnfs, libsmb2/AMSMB2, libzvbi).** The notices are in About; the full licence texts are bundled (`App/Licenses`, ten files, copied into the app by an explicit `buildPhase: resources` entry in project.yml, because XcodeGen's ProjectSpec does not say which phase a .txt file gets by default; device check N14); the written source offer is in About > Open Source (section 4a, OPEN_QUESTIONS R149, PROVISIONAL). libnfs and libsmb2 are linked statically; because this app's whole source is public, anyone can relink the app with a changed library (LGPL-2.1 section 6), which the offer says.
4. **Pages not read** (cannot confirm they have no further requirement): Dolby brand guidelines, dts.com trademarks, Plex trademark/partner pages, HDMI adopter guidelines, Microsoft trademark list PDF, UPnP notice PDF, HDR10+ logo guide, Metacritic terms. A person should read them before release.
5. **Apple:** "Apple TV" and the other marks are used as adjectives with generic nouns where possible; no Apple logo, no AirPlay or "Made for" badge.

## 4a. Written source offer for the LGPL libraries (Settings > About > Open Source, verbatim; OPEN_QUESTIONS R149, PROVISIONAL)

Source: `LicenseNotices.sourceOffer`, `sourceLinks` and `repositoryLine` in
`Packages/VideoPlayerCore/Sources/AppLogic/AboutNotices.swift`. Nobody was contacted. The repository address is the one the
runbook creates; it answers "404" until the first push. Versions: FFmpeg and libzvbi from
`Frameworks/MediaCodecs/upstream-build-record/BUILD-INFO.txt`; libnfs from docs/SOURCES.md (NFSKit's submodule pointer);
libsmb2 from AMSMB2 tag 4.0.3's submodule pointer (GitHub API, read 2026-11-17); AMSMB2 from `Vendor/AMSMB2/VENDORED_FROM.txt`.
Every tag and commit below was confirmed to exist with the GitHub API on 2026-11-17.

> Written offer for source code: some libraries in this app are licensed under the GNU Lesser General Public License, version 2.1 or later (LGPL). For at least three years from the day you received this app, anyone who has it may get the complete corresponding source code of each of these libraries, together with the build scripts and patches used to build them, at no charge other than the cost of physically delivering a copy. Everything is published in this app’s public source repository, listed below with each library’s exact version and upstream source. This app’s own source is in the same repository, so you can change these libraries and rebuild the app with your changes.
>
> - FFmpeg 8.1.3 (libavcodec, libavutil, libswresample), with the FFmpegBuild 3.15.0 patches — https://github.com/FFmpeg/FFmpeg/tree/1041abdc962f4cc4f394aa8de9dc5236c0c3b9e7 (tag n8.1.3) and https://github.com/superuser404notfound/FFmpegBuild/tree/3.15.0
> - libzvbi 0.2.46, with the FFmpegBuild 3.15.0 build changes — https://github.com/zapping-vbi/zvbi/tree/34bb6f660c5c1bacd4a66cc7b22311e4ca3c1ab5 (tag v0.2.46)
> - libnfs 5.0.2 — https://github.com/sahlberg/libnfs/tree/465a12d45703d4c8b1ba534323f911cf28b71501
> - libsmb2 (the version included in AMSMB2 4.0.3) — https://github.com/sahlberg/libsmb2/tree/aff9fa6ba9f41cfd3c15d184554601ec3f6d8d03
> - AMSMB2 4.0.3, with this app’s Swift 6.4 patch — https://github.com/amosavian/AMSMB2/tree/4942c3b336dc6cc5ae93a60a65961a66535e482a (tag 4.0.3)
>
> Source code, build scripts and patches: https://github.com/liampmcdowell7-rgb/video-player

Where the build scripts and patches are in the repository: `Packages/VideoPlayerCore/Frameworks/MediaCodecs/upstream-build-record/`
(FFmpeg, libzvbi), `scripts/patches/AMSMB2-4.0.3-swift6.4.patch` and `Packages/VideoPlayerCore/Vendor/AMSMB2/` (AMSMB2 and
libsmb2, vendored source). libnfs is NFSKit's prebuilt static library; its source is the upstream commit above (the
library was not rebuilt here, docs/SOURCES.md). Alternative (R149): ship the source next to the binary (LGPL-2.1 section 6a).

This puts the GitHub handle in the app's About screen and in AboutNotices.swift, as you asked for the repository link.

## 5. Every generic replacement found and fixed (rule A; baseline b713641 and the later brandless edits)

| File | Old (generic) | New (real name) |
|---|---|---|
| Packages/VideoPlayerCore/Sources/AppLogic/SourceSetup.swift | title "Media Server (DLNA)", "A media server on your network, found automatically or by its address." | "UPnP/DLNA", "A UPnP/DLNA media server on your network, found automatically or by its address." |
| same | "A folder reached over a secure shell connection." | "A folder reached over SSH (SFTP)." |
| same | "A direct link to one video file." | "A direct link to one video file, including Dropbox, Google Drive and OneDrive file links. An iCloud Drive sharing page cannot be played." |
| same | "blocked: needs an app registration. No app has been registered with the provider yet, ... Share a link and add it as a Web Link, ..." | "blocked: needs an app registration. No app has been registered with Microsoft yet, ... Share a OneDrive link and add it as a Web Link, or use a WebDAV bridge." |
| same | "Needs an account sign-in that this app does not offer yet. Use the server’s shared folder through SMB or WebDAV instead." | "blocked: Plex needs a Plex account sign-in, which this app does not offer yet. Use the Plex server’s media folder through SMB or WebDAV instead." |
| same | "There is no sign-in for TVs. Add a shared link as a Web Link, or use a WebDAV bridge." | "blocked: Dropbox has no sign-in for TVs. Add a Dropbox shared link as a Web Link, or use a WebDAV bridge." |
| same | "A TV sign-in cannot browse a whole Drive. Add a shared link as a Web Link." | "blocked: a TV sign-in cannot browse a whole Google Drive. Add a Google Drive shared link as a Web Link." |
| App/Features/Sources/DiscoveryView.swift | "Looking for servers on your network. ... Media servers (DLNA) are not found automatically on this device: choose Media Server and type the address ..." | "Looking for WebDAV, SMB, NFS, SFTP and FTP servers on your network with Bonjour. ... UPnP/DLNA servers are not found automatically on Apple TV: choose UPnP/DLNA and type the address of its device description." |
| App/Features/Settings/SourcesSettingsView.swift | the host alone | "<source type> · <host>" (the real type name on every row) |
| App/Features/Settings/SettingsView.swift, StorageSettingsView.swift | "Storage and Cloud", Section "Cloud Sync" | "Storage and iCloud", Section "iCloud" |
| App/Features/Settings/HomeScreenSettingsView.swift | "... appear in the row on the device’s Home Screen ..." | "... appear in the Top Shelf row on the Apple TV Home Screen ..." |
| App/Features/Sources/SourceKindListView.swift, App/Support/LiveSourceConnector.swift, SourceBuilder.swift, SourceConfiguration.swift (comments) | "cloud-storage kind", "the provider" | OneDrive, Microsoft |
| App/Support/AppServices.swift, CloudSyncHost.swift (comments) | "cloud sync" | "iCloud (CloudKit) sync", "Settings > Storage and iCloud" |
| App/Support/Attribution.swift | "come from an online service"; header "the data provider"; two `design-lint:allow` lines | "come from TMDB, and only after you enter your own TMDB key ..."; "the notices TMDB requires"; allows removed |
| Packages/VideoPlayerCore/Sources/AppLogic/CloudSync.swift (CloudSyncText) | "Cloud sync has not started yet.", "Not signed in to cloud sync, ...", "The cloud could not be reached. ...", "Your cloud storage is full, ..." | "iCloud sync has not started yet.", "Not signed in to iCloud, so nothing is synced. ...", "iCloud could not be reached. ...", "Your iCloud storage is full, ..." |
| Packages/VideoPlayerCore/Sources/AppLogic/SettingsModel.swift (accountLine) | "Signed in. ... sync to your account.", "Not signed in. Everything is kept on this device only.", "Cloud sync is restricted on this device. ...", "Cloud sync status is not known right now." | "Signed in to iCloud. ... sync through your iCloud account.", "Not signed in to iCloud. Everything is kept on this Apple TV only.", "iCloud is restricted on this Apple TV. ...", "iCloud status is not known right now." |
| Packages/VideoPlayerCore/Sources/AppLogic/OnlineLookup.swift | "When you are signed in to cloud sync, an encrypted copy is kept in your own cloud storage, ..."; comments "cloud copy"; header "the app target is brandless" | "When you are signed in to iCloud, an encrypted copy is kept in your iCloud account, ..."; "iCloud copy"; header states the names rule (whatIsSent was already rewritten by the COVERAGE stream and names TMDB, IMDb and OMDb) |
| Packages/VideoPlayerCore/Sources/UserData/SecretSync.swift (CredentialStorageText and comments) | "... a copy is kept in your account’s encrypted cloud storage ...", "You are not signed in to cloud sync. ...", "Your cloud encryption key was reset, so the cloud copy ...", "The cloud copy could not be updated ...", "They come back from cloud sync if you are signed in with the same account; ..." | "... an encrypted copy is kept in your iCloud account ...", "You are not signed in to iCloud. ...", "Your iCloud encryption key was reset, so the iCloud copy ...", "The iCloud copy could not be updated ...", "They come back from iCloud if you are signed in with the same Apple Account; ..." |
| Packages/VideoPlayerCore/Sources/AppLogic/LibraryCards.swift | badge "Atmos", filter `.atmos` title "Atmos", chip "Atmos" | "Dolby Atmos" in all three |
| Packages/VideoPlayerCore/Sources/AppLogic/ItemDetail.swift | version row `c.uppercased()` and a bare "HDR" | `FormatNames`: "HEVC · Dolby Vision Profile 8 / HDR10 · Dolby TrueHD with Dolby Atmos 7.1" |
| Packages/VideoPlayerCore/Sources/AppLogic/ArtworkEngine.swift, DiscoverModels.swift, MetadataOnline/Models.swift (comments) | "the online catalogue", "the provider notices" | TMDB, JustWatch |
| docs/ARTWORK_DISCOVER.md section 5a | "Attribution required by the data provider" | "Attribution required by TMDB" |
| docs/APPSTORE_READINESS.md item 1 | "The app is brandless" | "The app's own identity stays neutral (docs/NAMES.md rule 1)" |
| docs/DEVICE_TEST_CHECKLIST_ARTWORK.md A7, A29, A32 | "the same cloud account", "Sign out of the cloud account" | "the same iCloud account (Apple Account)", "Sign out of iCloud", "while signed in to iCloud" |
| docs/DEVICE_TEST_CHECKLIST_PLAYBACK.md P48 | "no product names" | "formats, servers and services by their real names (docs/NAMES.md), no certification claims, no other player apps" |
| docs/DESIGN_SYSTEM.md D-DS7, section 9 item 6, section 10, section 11 item 13 | brandless rule, `apple-trademark` and `third-party-name` rules | the names rule and the three new lint rules |
| Tests: SourceWiringTests, CloudSyncTests, SettingsModelTests, SecretSyncTests, LibraryScreenTests | pinned the generic texts or banned the names | pin the real names (e.g. `testEverySourceTypeHasItsRealNameAndBlockedOnesNameTheService`, `testTheStorageTextsNameICloudAndClaimNothing`, `testSettingsTextNamesICloudAndStatesTheReset`) |

### Mentions of other media-player applications removed (described without their names)

| File | What was there | Now |
|---|---|---|
| Packages/VideoPlayerCore/Sources/MetadataLocal/NFO.swift (comments, 5 places) | a third-party player app named as the source of the NFO layout | "the common NFO layout", "publicly documented NFO conventions", "NFO files write", "the NFO `<set>` element" |
| Packages/VideoPlayerCore/Tests/MetadataLocalTests/NFOTests.swift (comment) | a third-party player app | NFO conventions |
| docs/METADATA_LOCAL.md (3 lines) | a third-party player app | the NFO format |
| docs/SEGMENTS.md line 32 | a third-party player app's EDL actions | "Numeric EDL actions (0 to 3)" |
| docs/DEVICE_TEST_CHECKLIST_VISUAL.md (5 lines), DEVICE_TEST_CHECKLIST_PLATFORM.md line 51 | comparison with a third-party player app / a system video app | comparison with the system standard, the Settings app or `AVPlayerViewController` |
| docs/spikes/FFMPEG_TVOS_CANDIDATES.md line 110 | a sentence about a third-party player app | removed |
| docs/APPSTORE_READINESS.md line 29 | a third-party player's framework name | "the FFmpeg frameworks (MediaCodecs) and the libdovi framework (DolbyVisionRPULib)" |
| scripts/design-lint.sh, scripts/design-lint-fixtures, Tests/AppLogicTests/SettingsModelTests.swift | ban lists naming third-party player apps | removed; the lint is an allowlist, its KNOWN list holds no player apps |
| docs/spikes/FFMPEG_TVOS_CANDIDATES.md lines 49, 53 and the link list (lead, 2026-11-17) | a playback engine by the FFmpegBuild author, named three times with its link | described without its name; link removed |
| Packages/VideoPlayerCore/Package.swift, Frameworks/MediaCodecs (NOT changed) | the vendored framework names carry that engine's prefix (`AetherLibavcodec` and four more), as FFmpegBuild 3.15.0 ships them | kept: renaming changes each binary's install name and needs a Mac or a CI run; OPEN_QUESTIONS R145 (your decision) |

Kept, PROVISIONAL: "MPVKit" in docs (spikes, BUILD_ORDER, PLAYBACK_WIRING, PLAYBACK_STATUS, APPSTORE_READINESS) and one
comment in PlaybackStatus/Models.swift: it is a Swift library considered as the fallback engine (a technology the app may
rely on), not a reference to a player app. Alternative: call it "the fallback engine library" everywhere. "video/quicktime"
(a MIME type) and "QuickTime text track" (a file format) are format identifiers. The Apple TV app (system Up Next / Now
Playing integration) is an Apple platform feature, not a comparison.

## 6. Pending in files owned by other work streams (to do at the end, after the owner reports done)

Done after the owners finished (coordinator, 2026-11-17):
- Packages/VideoPlayerCore/Tests/AppLogicTests/PlaybackErrorsTests.swift: `testNoTextNamesAProduct` (a ban list that named third-party player apps and banned "apple", "plex" and others) became `testErrorTextsMakeNoCertificationClaims` (no certification or endorsement wording, no trademark signs; the unsupported codec is named "VP9").
- AUDIO and DOLBY VISION status texts (PlaybackStatus AudioRules, VideoRules, StatusTable; TrackPickers; RemuxPlaybackModel): checked; they already use the real names ("Dolby Vision (converted from Profile 7)", "Dolby Vision Profile 5 has no HDR10 layer ...") and pass the names lint. No status text was changed, so RulesGolden.swift and docs/PLAYBACK_STATUS.md were not regenerated.

Still pending (not this work stream's file):

| File | Owner | Pending edit |
|---|---|---|
| OPEN_QUESTIONS.md rows 18, B11, R50, R88, R91, R101, R102 | lead (done 2026-11-17) | Rows 18 and B11 now say "fallback playback engine (MPVKit library)" / "fallback engine"; R50, R88, R101 keep MPVKit as a library name (R143, PROVISIONAL); R91 and R102 marked superseded by R107/R138; docs/spikes/FFMPEG_TVOS_CANDIDATES.md says "libmpv" (the library) |
| project.yml | lead (done 2026-11-17) | Full licence texts bundled: App/Licenses, explicit `buildPhase: resources` (section 4 item 3, R149) |

## 7. Lint summary

`scripts/design-lint.sh`: rules `apple-trademark` and `third-party-name` removed; `unknown-name`, `claim-wording` and
`brand-logo` added (exact text in the lint header and docs/DESIGN_SYSTEM.md section 10). Scope now includes TopShelf/,
asset-catalog image sets and the package modules AppLogic, PlaybackStatus, SourceLinks and UserData (names rules only).
Fixtures: `scripts/design-lint-fixtures/{unknown-name,claim-wording,brand-logo}` and `names-fixture.md`.

## 8. Every occurrence of "Aether" (user decision 2026-11-17, OPEN_QUESTIONS R145 / R150, PROVISIONAL)

"Aether" is the prefix FFmpegBuild 3.15.0 gives its frameworks; it is also the name of a playback engine by the same
author. Rule: it may appear only as a technical identifier of a shipped file or in licence material, never in wording a
user sees. Checked 2026-11-17 with `grep -rIn -i aether` over the whole tree (excluding .git), `find -iname '*aether*'`
and a binary search of Frameworks/. **No occurrence is in App/, TopShelf/, any UI string, any status text or any
.xcstrings file.** Alternative kept open: rebuild with a neutral prefix on GitHub Actions after the first compile.

| Where | Count | What it is | Category |
|---|---|---|---|
| `Packages/VideoPlayerCore/Frameworks/MediaCodecs/Aether{Libavcodec,Libavutil,Libswresample,Libdav1d,Libzvbi}.xcframework` (folder and file names, both slices) | 5 frameworks | names of the shipped frameworks, the dynamic library inside each, its install name `@rpath/AetherLib….framework/…` | technical identifier of a shipped file |
| the same frameworks: `Info.plist` (xcframework and per slice), `Modules/module.modulemap`, `Headers/*.h` (`#include <AetherLib…/…>` lines) | 188 lines in 75 text files, plus the 10 binaries | bundle identifiers, module names and include paths inside the shipped files | technical identifier of a shipped file (third-party, unaltered) |
| `Packages/VideoPlayerCore/Package.swift` line 170 | 1 | the five binary-target names, which must equal the framework names | technical identifier |
| `Packages/VideoPlayerCore/Sources/CMediaCodecs/mediacodecs.c` lines 10 to 16 | 7 | `#include <AetherLibavcodec/avcodec.h>` and the like | technical identifier |
| `Packages/VideoPlayerCore/Frameworks/MediaCodecs/LICENSES/NOTICE-LGPL.md`, `LICENSES/README.md` | 9 | which framework file holds which library under which licence | licence notice |
| `Packages/VideoPlayerCore/Frameworks/MediaCodecs/upstream-build-record/BUILD-INFO.txt` | 63 (framework names only) | the upstream build record | licence material (LGPL corresponding source) |
| `…/upstream-build-record/build.sh` | 53 lines, 44 of them containing `AetherEngine` (the upstream author's playback engine) | the build script, byte for byte as published (sha256 in BUILD-INFO.txt) | licence material: it is the build script the LGPL offer must provide, so it is not edited |
| `…/upstream-build-record/patches/av1-delayed-rap.patch`, `matroska-byte-seek-done.patch`, `matroska-skip-attachments.patch` | 1 each | one mention in each patch's description text | licence material (the patches the offer must provide), not edited |
| `…/upstream-build-record/README.md` | 0 | our own short README (listed because it replaced one that named the engine) | none (the upstream project README, which named the engine, was removed 2026-11-17) |
| `docs/AUDIO_PIPELINE.md` line 34, `docs/DEVICE_TEST_CHECKLIST_AUDIO.md` AU-1 | 2 | the framework file names to look for in the built app | technical identifier |
| `docs/spikes/FFMPEG_TVOS_CANDIDATES.md` lines 45 and 46 | 2 | install name `@rpath/AetherLibavformat.framework` and the upstream product name `AetherFFmpegBuild` | technical identifier |
| `OPEN_QUESTIONS.md` R145, R150 and this section | 3 | the decision itself | records of the decision |
