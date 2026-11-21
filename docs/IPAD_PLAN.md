# Long-term: iPad app (plan only, nothing built)

Status: **LONG-TERM PLAN, no iPad code.** Owner decision of 20 Nov 2026, in the owner's words: "turn this into an iPad
app as well, one that can use local storage and external storage." Everything below that is not the owner's own words is
PROVISIONAL and listed in OPEN_QUESTIONS.md (R274 to R278). Linked from docs/FEATURE_BACKLOG.md (item 37) and
docs/SPECS.md.

## Goal

The same player on iPad, with sources for Plex, WebDAV, and files on the iPad itself or on external storage (USB-C
drives, SD cards), opened through the system Files experience (the system document picker; no file browser of our own
for picking).

## Owner use case

While away from home, the owner plugs a portable SSD with the media library into the iPad and plays the library
directly. Today the owner does this with another app; this app should replace that. (At home the library reaches the
Apple TV through Plex Media Server on the owner's PC: docs/PLEX_SOURCE.md, owner context.)

## Constraints that carry over from the tvOS app

- Brandless: technology names as plain text only, no logos (docs/NAMES.md; the one TMDB exception, R148).
- Native system components only: system List, Form, document picker, the system player; SF Symbols, system fonts and
  colours (docs/DESIGN_SYSTEM.md).
- Highest-quality playback: the original stream first, the app's own remux for Matroska, no needless re-encode
  (docs/PLEX_SOURCE.md section 5 has the same rule for Plex).
- Rich metadata (docs/METADATA.md, R270 and R276 for whose metadata wins).
- Apple HIG and Liquid Glass: the iPadOS HIG page "Designing for iPadOS" (read, see below) plus the system look of the
  current SDK.
- Per-stage tests: every stage has offline tests before it is called done, like the tvOS stages.
- Honest claims: anything not read on Apple's pages is marked UNVERIFIED; nothing is called working before a device run.

## Stage order (owner's rule)

iPad work starts only after **all three** of these:
1. the tvOS TestFlight build is installed on the Apple TV and verified by the owner;
2. the text-field bug is fixed (OPEN_QUESTIONS.md R273: the fix is **built** (PROVISIONAL) but **unverified**: not yet
   seen in a screenshot or on a device; the next step is the screenshot check 11-form-webdav-FIELDS-AT-REST);
3. the Plex source is working (docs/PLEX_SOURCE.md stages 1 to 6).

**No iPad code before then.** Not even a target in project.yml.

## What was read (20 Nov 2026)

| Page | What it says that this plan uses |
|---|---|
| UIDocumentPickerViewController, https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller | iPadOS 8.0+. "The open and move operations provide security-scoped URLs for all external documents." Use `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`; "Always use file coordinators" (`NSFileCoordinator`) to read external documents and a file presenter (`NSFilePresenter`) when showing their contents. "Don't save URLs that the open and move operations provide"; save a bookmark created with the `withSecurityScope` option instead. Points to "Providing access to directories" for folders (**not read**). |
| startAccessingSecurityScopedResource(), https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource() | Each start must be balanced by a stop; after the last stop "you immediately lose access". Failing to stop "leaks kernel resources" and the app can lose the ability to add locations "until relaunched". |
| Designing for iPadOS (HIG), https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados | Large display; viewing distance "typically within about 3 feet"; touch, keyboard, pointer, Apple Pencil, voice; people run several apps at once; adapt to orientation, multitasking modes, Dark Mode and Dynamic Type; minimise modal and full-screen transitions. Lists the "Meet Liquid Glass" video (the video itself was **not watched**). |
| Configuring a multiplatform app, https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target | "iOS, iPadOS, macOS, tvOS, and visionOS apps can share a single target." An app target "specifies project settings information like your app's bundle identifier"; settings are shared by default and can be varied per platform; platform code goes behind `#if os(...)` / `#if canImport(...)`; a whole file can be limited to some platforms. A SwiftUI app on both platforms is named as a good fit for one target. **It does not say anything about** App Store records, universal purchase, App ID capabilities, provisioning profiles, the iCloud container or App Groups. |

## Facts from this repository that matter for iPad

- The package `Packages/VideoPlayerCore` declares `platforms: [.tvOS("27.0"), .macOS(.v14)]`: no iOS or iPadOS.
- The vendored binary frameworks (the codec libraries in `Frameworks/MediaCodecs`, `Libnfs`, `DolbyVisionRPULib`) have
  tvOS device and simulator slices only (for example `tvos-arm64`, `tvos-arm64_x86_64-simulator`). An iPad build needs
  iOS slices of each, built and recorded the same way.
- project.yml has one tvOS app target (`VideoPlayer`), the tvOS Top Shelf extension and a tvOS UI-test target;
  `TARGETED_DEVICE_FAMILY: "3"` (Apple TV).
- `SourceKind` has no local-files kind (webdav, smb, nfs, sftp, ftp, upnp, googleDrive, oneDrive, dropbox, directLink,
  jellyfin, emby, plex).
- The storage model (R57, docs/STORAGE_MODEL.md) is built around tvOS keeping no durable local files. iPadOS differs;
  what iPadOS guarantees for an app's own storage was not read for this plan (UNVERIFIED).

## Open questions (all PROVISIONAL, in OPEN_QUESTIONS.md)

- **R274** One App Store record with tvOS and iPadOS together (universal purchase) or a separate iPad app: trade-offs
  only, no decision.
- **R275** Local and external storage: access, keeping access, unplugged drives, a new source type, scanning without a
  server.
- **R276** Metadata without a Plex server: the app must match titles itself; conflicts with R270 for the on-device case.
- **R277** Codemagic cost: an iPad target adds build time and minutes at the overage rate. Noted, nothing changed.
- **R278** Project structure: shared code in a Swift package or in the app target. Options only.

The detail of each lives in its row; this file is the overview.
