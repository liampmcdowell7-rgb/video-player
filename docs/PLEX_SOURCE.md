# Plex as a source type: research and plan (not built)

Status: **PLAN ONLY, nothing built.** No app code, no test server, no Plex account was used. Every decision below is
PROVISIONAL and listed in OPEN_QUESTIONS.md (R267 to R272) for the owner to confirm or change. This plan changes earlier
decided rows only if the owner says so: R12 (B7) "no plex.tv sign-in", R19 "local-only mode if it works, otherwise
blocked", R30 "account-blocked", S12, S21 and the media-server rule in docs/SOURCES.md ("Your Library Only, direct play
only, our metadata authoritative"). Where this plan differs from them it says so.

The owner's goal: add a Plex server in the same Add a Source flow as WebDAV, browse movies and shows, and play items in
the existing player with the same quality, metadata, artwork and Continue Watching behaviour as WebDAV items. WebDAV
behaviour must not change. The app stays brandless: "Plex" appears only as the plain-text name of the source type (it is
already on the `names-allowlist` in docs/NAMES.md); no Plex logo, colour or look anywhere.

## What was read (20 Nov 2026) and what was not

| Source | Result |
|---|---|
| Plex developer home, https://developer.plex.tv/ | Read in full (authentication: PIN and JWT flows, resources, headers) |
| Plex Media Server API, https://developer.plex.tv/pms/ | Read in part. The page text returned to the fetch stops partway through the Library section; the bodies of the library-section, on-deck/hubs, transcoder and timeline/scrobble operations were **not** returned (only their names in the table of contents). A second reader was refused by the site's robots.txt and was not retried. |
| Plex Support, direct play and direct stream, https://support.plex.tv/articles/200250387-streaming-media-direct-play-and-direct-stream/ | **Not read**: HTTP 403 (the same as the earlier attempt recorded in docs/SOURCES.md, Plex B7) |
| Apple, AVPlayer, https://developer.apple.com/documentation/avfoundation/avplayer | Read: AVPlayer plays "local and remote file-based media, such as QuickTime movies and MP3 audio files, as well as audiovisual media served using HTTP Live Streaming"; tvOS 9.0+ |
| Apple, AVFileType, https://developer.apple.com/documentation/avfoundation/avfiletype | Read: the listed video file types are `mov`, `mp4`, `m4v` (and 3GPP); Matroska is not listed |
| Apple, HLS Authoring Specification for Apple Devices, https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices | Read in part (the tvOS-specific section only as a summary, not verbatim) |

Rule for this document: an endpoint, parameter or behaviour quoted from a page read verbatim is marked **(read)**.
Everything else is marked **UNVERIFIED** and must be checked against the PMS reference (or recorded fixtures from a real
server the owner provides) before the stage that uses it is built.

## 1. Sign-in on an Apple TV

**Recommended (R267): the plex.tv PIN flow ("link" code).** The TV shows a short code and a link; the owner enters the
code on a phone or computer where the owner is already signed in to Plex; the TV polls until the token arrives.

Steps, from the developer home page (read):
1. `POST https://plex.tv/api/v2/pins?strong=true` with `Accept: application/json`, `X-Plex-Product` and
   `X-Plex-Client-Identifier`. The response has `id` and `code`. Without `strong`, "a shorter pin is created but will have
   a much shorter lifetime" (read). For a TV the short 4-character code is the usable one: "For 4-digit pins, you need to
   use the link page: `https://plex.tv/link/?pin=<code>`" (read). So the TV asks **without** `strong=true` and shows the
   code and the text "plex.tv/link". The exact lifetime of a short PIN is **not stated** (UNVERIFIED; the screen offers
   "Get a New Code" when it expires).
2. Poll `GET https://plex.tv/api/v2/pins/<id>` with `Accept` and `X-Plex-Client-Identifier`, "once per second" (read).
   When the owner has entered the code, `authToken` is set; "If authentication failed, the `authToken` field will remain
   `null`" (read).
3. The token is stored at once (section 3) and never shown, logged or printed.

Headers: "`X-Plex-Client-Identifier` is typically required, as is `X-Plex-Token` for authentication" (read). The app
sends a stable random client identifier per install (generated once, kept with the source definition; not secret),
`X-Plex-Product` = the app's display name, and `X-Plex-Version`, `X-Plex-Platform` = `tvOS`, `X-Plex-Device` = `Apple TV`
(these four are "common headers"; whether they are required is not stated). The product name "should be different from
any existing Plex products" (read): "Video Player" is.

Newer JWT variant (read, recorded for later, not recommended for the first build): the PIN is created at
`https://clients.plex.tv/api/v2/pins` with an Ed25519 public key (`jwk`), polled with a signed `deviceJWT`, and returns a
JWT "valid for 7 days", refreshed through `/api/v2/auth/nonce` and `/api/v2/auth/token`. Plex calls it "Recommended". It
needs a device key pair in the Keychain and a refresh path. Choice in R267: start with the classic PIN token, keep the JWT
flow as the planned follow-up stage (it fits the existing `AuthMethod.pinLink`).

Why the PIN flow: no typing of a long token with the Siri Remote; the owner never handles the token; it is the flow Plex
documents for devices; it finds the owner's servers by itself (section 2). Against it: it contacts plex.tv, which R12
(B7) decided against. **The owner must decide whether R267 replaces R12.**

Alternatives (in R267):
- (a) Server address plus a token pasted by the owner (from the Plex account on a computer). No plex.tv call from the
  app, but typing a ~20-character token with the remote, and the owner has to find the token without help.
- (b) R12's local no-auth mode (server setting "allowed without auth", typed address, no token). Plex grants listed
  networks "full administrative access" and forum reports call it inconsistent (docs/SOURCES.md, from summaries).
- (c) Keep Plex blocked (R19, R30 as they are).

## 2. Finding and choosing a server

From the developer home page (read): `GET https://clients.plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1`
with `Accept: application/json`, `X-Plex-Product`, `X-Plex-Client-Identifier`, `X-Plex-Token`. Each resource carries "the
`accessToken` used in communication with this PMS" and its connections. A connection has `protocol`, `address`, `port`,
`uri`, `local` and `relay`; the HTTPS `uri` looks like `https://10-0-2-123.<identifier>.plex.direct:32400` (read). Rules
(read): "Connections labeled as `local` should be preferred over those that are not"; "relay should only be used as a last
resort". Filtering to servers (a `provides` field containing `server`) is **UNVERIFIED** (not stated on the pages read).

Plan (R268):
- Add a Source > Plex > sign in > list of the owner's servers (system `List`, one row per server: its name as plain text,
  "Local" or "Remote" as secondary text). One server is added as one source; adding a second server repeats the flow.
- Connection order, tried in turn with a short timeout: local HTTPS (`plex.direct`) > local HTTP > remote HTTPS > relay.
  The first that answers is used and remembered; the list is re-read when all remembered connections fail.
- HTTPS to `*.plex.direct` uses normal certificate validation (Plex issues these certificates; that this always validates
  on tvOS is UNVERIFIED). Plain HTTP only for `local` connections, which `NSAllowsLocalNetworking` already covers for IP
  and `.local` hosts (docs/SOURCES.md, B9). No new ATS exception.
- Relay is **off by default** (R268): it is slower and Plex says last resort; if it is the only route, the source shows
  "Reachable only through relay" and plays only after the owner turns relay on in the source's settings.
- Server offline: intended to behave like an offline WebDAV source today (how the app shows an unreachable source was
  not re-read for this plan; confirm in stage 3). The library keeps its indexed items, Continue Watching keeps its rows,
  playback shows the existing "source not
  reachable" error, and nothing is deleted. A rescan runs when the server answers again.

## 3. Where the token lives

- The token goes to the Keychain through the existing `KeychainCredentialStore` (service `com.liamp.videoplayer.sources`,
  account = source id, not synchronizable), exactly like WebDAV, Jellyfin and Emby secrets. The source definition
  (`UDSourceDefinition`) holds no secret: kind `plex`, the server name, the chosen connection URI, the server's machine
  identifier and the client identifier go into `host`, `port`, `path` and `options`.
- Two tokens exist: the plex.tv account token (from the PIN) and each server's `accessToken` (from resources). Plan: keep
  the **server access token** as the source secret (it is all playback needs), and keep the account token in the same
  Keychain item only if the owner wants server-list refresh without signing in again (R269).
- iCloud: secrets today are mirrored by `MirroredSecrets` (Keychain first, then the CloudKit `Secrets` zone, record type
  `SourceSecret`). Recommended (R269): the Plex token follows the same rule as the other source secrets, so a second Apple
  TV in the same iCloud account gets the source without signing in again. Alternative: never mirror Plex tokens (sign in
  on each Apple TV).
- Never logged or printed: the token is never in a URL that is logged, never in an error message, never in a screenshot
  fixture. URLs carrying `X-Plex-Token` as a query parameter (needed by AVPlayer for direct play, section 5) are built
  only in memory at play time. A unit test checks that every log line and every error text from the Plex client is free of
  the token (the same redaction rule as the other sources).

## 4. Mapping Plex items onto the app's model

The app's model (LibraryIndex): `LibraryItem` (title, year, rating, series id and title, season, episode, TMDB id,
runtime, technical facts), `ItemMetadata`, `StoredFile` (source id, path, etag, `serverToken`), `WatchState` (position,
duration, watched, play count, last played). There are no separate show and season types; series are grouped from
episodes. Jellyfin and Emby already map onto this through a `MediaSource` that builds a file tree from each item's
server file path (`JFTree`), with `SourceEntry.serverItemType` = movie or episode.

Plan (R270): the same shape. `SourcePlex` is a `MediaSource` like `SourceJellyfin`:
- Libraries: the movie and show sections become top-level folders; each item's `Part.file` path builds the tree, so the
  existing scanner (`LibrarySyncer`), `FilenameParser` and the sorting rules run unchanged. The Part's server id goes into
  `serverToken` so a changed file is noticed.
- Item key: watch records are keyed by the file-name item key, so the same film on WebDAV and on Plex shares one
  Continue Watching entry and one watched state. This is a feature, but it must be tested (stage 4).

Fields Plex has (read from the sample on the PMS page: `title`, `summary`, `year`, `contentRating`, `rating`, `duration`
"Runtime in milliseconds", `thumb`, `art`, `addedAt`, `updatedAt`, `Guid` with `imdb://`, `tmdb://`, `tvdb://`, `Rating`
entries, `Media` with `videoCodec`, `audioCodec`, `audioChannels`, `container`, `bitrate`, `width`, `height`, and `Part`
with `key`, `file`, `size`, `container`):

| Plex field | App field | Use |
|---|---|---|
| `Guid` `tmdb://…` | `LibraryItem.tmdbID` | Exact match for our metadata lookup (better than filename matching) |
| `title`, `year` | title, year | Only as a hint when there is no TMDB id (our metadata rule) |
| `duration` (ms) | runtime | Yes (seconds) |
| `Media`/`Part` codecs, container, size, width, height | technical facts | Yes, decides the playback route before opening the file |
| `summary`, `thumb`, `art`, `contentRating`, `rating` | details and artwork | **Owner decision (R270)**: today "our metadata authoritative" and "Titles from the server are never used" apply to Jellyfin and Emby. Recommended: keep TMDB as the source of truth and use Plex's summary and artwork only when TMDB has none (a fallback layer; `DetailsLayers.swift` already names "a Jellyfin, Emby or Plex server" as layer 1) |
| `viewOffset`, `viewCount`, `lastViewedAt` | resume, watched | **UNVERIFIED** names (not in the text read); section 6 |
| `Stream` (audio and subtitle tracks, language, codec) | track menus | **UNVERIFIED** (not in the text read); the system player draws the menus as today |
| `addedAt`, `updatedAt`, `Rating` image ids, `tvdb://`, collections, extras, chapters, markers (intro) | not used yet | Listed for later; markers could feed the existing segment (skip-intro) data |

Endpoints for browsing (UNVERIFIED unless marked): `/library/sections` and `/library/sections/{id}/all` (named in the
reference's table of contents only), `/library/metadata/{id}/children` and `/allLeaves` (read: children "Passing no paging
headers here should only return the first 20 Metadata objects", so the client must page), `/library/metadata/{id}`
(read, sample). JSON only when asked: "The default is XML, so JSON will only be returned if it's explicitly requested
(`Accept: application/json`)" (read). Images through `/library/metadata/{id}/images` (read, name only) or the photo
transcoder (UNVERIFIED), sized for the TV, with the token in a header where possible.

## 5. Playback

Principle (owner's rule, and the existing media-server rule): highest quality, the original file first.

What tvOS plays directly, from Apple's pages read:
- AVPlayer: "local and remote file-based media, such as QuickTime movies … as well as audiovisual media served using HTTP
  Live Streaming" (read). AVFileType lists `mov`, `mp4`, `m4v` among video file types; Matroska is not listed (read).
- HLS (read, verbatim): video "MUST be encoded using H.264/AVC, HEVC/H.265, Dolby Vision, or AV1"; Dolby Vision "Profile
  5 (single layer 10-bit HEVC)"; HEVC in fMP4; audio includes Apple Lossless, FLAC, Dolby Digital (AC-3), Dolby Digital
  Plus (E-AC-3) and Dolby Digital Plus JOC; "Subtitles MUST be WebVTT … or IMSC1 in fMP4". DTS and TrueHD are not stated
  (they are not in the list). The tvOS-specific limits (for example H.264 level) were read only as a summary: UNVERIFIED.

Routes, in order (R271):
1. **Direct play** for `mp4`, `m4v`, `mov` Parts with codecs from the lists above: AVPlayer opens the Part URL
   (`/library/parts/{id}/…`, read as the Part `key` form) with the token. Plex allows "all `X-Plex-` headers … as query
   string arguments" (read); the app already passes headers through `AVURLAssetHTTPHeaderFieldsKey`
   (`PlayerCoordinator`), so the header form is tried first and the query form is the fallback (UNVERIFIED which one
   AVPlayer needs for ranged requests on a Plex server).
2. **The app's own remux** for `mkv`/`webm` Parts: the existing RemuxEngine (Matroska to fMP4/HLS on the loopback, DTS
   and TrueHD decoded to FLAC, Dolby Vision 7 to 8.1) reads the Part through ranged requests, exactly as it reads a WebDAV
   file today. The picture stays the original stream (no re-encode), so quality matches WebDAV. Needs ranged reads of the
   Part URL (UNVERIFIED on Plex; Jellyfin's `static=true` stream supports `Range`).
3. **Plex's HLS transcode, stated fallback only** (when 1 and 2 cannot play: an unsupported video codec such as MPEG-2 or
   VC-1, or a server that refuses ranges). The universal transcoder (`/video/:/transcode/universal/start.m3u8` with
   `protocol=hls`, `directPlay`, `directStream`) is **UNVERIFIED**: its body was not in the text read; only the
   `X-Plex-Client-Profile-Extra` parameter "for the universal transcode endpoint" was read. The player shows a plain
   "Converted by the server" line in the info panel so the owner knows quality is reduced. Whether Plex's "Direct Stream"
   (remux without re-encode) can be requested this way is UNVERIFIED (the Plex Support page was not readable).

Subtitles and audio: in routes 1 and 2 the tracks come from the file itself, as today (system menus; picture subtitles
through the existing remux menu). External subtitle files that Plex lists as separate streams (`.srt` next to the film)
need the `Stream` data (UNVERIFIED) and are a later stage. In route 3 the transcoder decides; burned-in subtitles are
avoided by asking for WebVTT where the API allows it (UNVERIFIED).

## 6. Watched state and resume position

Recommended (R272): **read once, then local only** for the first stages. When an item is first indexed, Plex's resume
position and watched flag (UNVERIFIED field names `viewOffset`, `viewCount`) seed the app's `WatchState` if the app has
none for that item; after that the app's own records (synced through iCloud like every source) are the truth, and the app
writes nothing back to the server. Reason: writing to the server needs the timeline and scrobble endpoints, whose
parameters were not in the text read ("Report media timeline", "Mark an item as played", "Mark an item as unplayed" are
names only), and wrong writes would change the Plex history on other devices.

Alternatives (R272): (a) fully read-only, never seed; (b) two-way: report progress with the timeline call while playing
and mark watched at 95 % (`LibraryWatchRules.watchedFraction`) with scrobble, as a later stage after recorded fixtures
prove the parameters.

## 7. Test plan per stage (no real server, no network)

The pattern already used for Jellyfin and Emby (`Tests/SourceJellyfinTests/`: a fake server, JSON fixtures, client
tests): a `FakePlexServer` in the test target answers on 127.0.0.1 with JSON fixtures. No real Plex server can run here
(scripts/test-servers.sh notes this; setting one up needs a plex.tv account). The fixtures are hand-written from the
fields read on the PMS page and marked "HAND-WRITTEN, not recorded"; if the owner later records responses from the
Plex server, `scripts/record-mediaserver-fixtures.sh` already redacts tokens for Jellyfin and Emby and would get a Plex mode.

| Stage | Tests (all offline) |
|---|---|
| 1 Sign-in | PIN create, poll until `authToken`, expired PIN, `authToken` null until claimed, headers sent (client id, product), token never in logs or errors (fake plex.tv endpoints) |
| 2 Servers | resources JSON with local, remote and relay connections; order chosen; relay skipped unless allowed; all down = offline state |
| 3 Browse | sections, paged children (21+ items to prove paging), shows to seasons to episodes, tree paths built from `Part.file`, XML response refused (we always ask for JSON) |
| 4 Model | mapping table above, `tmdb://` to `tmdbID`, ms to seconds, same file on WebDAV and Plex gives one item key, WebDAV tests unchanged |
| 5 Play | route choice per container and codec (mp4 HEVC direct, mkv DTS remux, MPEG-2 transcode fallback), ranged reads through the fake server (206, 416), token header present, token absent from every logged URL |
| 6 Watch seed | seeding only when the app has no record; never overwrites; no write requests sent (the fake server fails the test on any POST/PUT to timeline or scrobble) |
| UI | Add a Source shows Plex as available; existing UI fixture `10-add-source-types-HIERARCHY.txt` and the tests that assert Plex is blocked (`SourceWiringTests` lines 63, 86, 96, 119; `SourceStatusTests` lines 26 to 28) change in the same stage that unblocks it; design lint: "Plex" only as allowlisted plain text, no "Works with", no logo |

Device checks (owner, on the Apple TV): sign in with the code, one local and one remote server, direct play of an MP4,
an MKV with DTS, a 4K Dolby Vision file, resume after stopping, offline server. Added to
docs/DEVICE_TEST_CHECKLIST_SOURCES.md when the stage is built.

## 8. Stages, each small enough to review

0. **Owner decisions** R267 to R272 (and whether they replace R12, R19, R30).
1. `SourcePlex` target and client skeleton: headers, client identifier, JSON decoding of the models read on the PMS page;
   fake server; no UI. Plex stays blocked in the app.
2. PIN sign-in in `LiveSourceConnector` (the existing device-code `SignInSession` used by OneDrive is the model) and
   the Plex form in Add a Source; token to the Keychain; still no browsing.
3. Server list and connection choice (local first, relay off).
4. Browse and index: sections, items, seasons, episodes into the existing scanner; Plex unblocked in Add a Source.
5. Direct play and remux routes.
6. Watch-state seed (read once).
7. Later, each after its own decision: Plex artwork/summary fallback layer, external subtitle streams, the HLS
   transcode fallback, two-way watch state, the JWT sign-in.

Every stage keeps WebDAV untouched: no change to `SourceWebDAV`, and the WebDAV tests must pass unchanged in each commit.
