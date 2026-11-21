# Plex as a source type: research, plan and build status

**Build status (owner's request of 20 Nov 2026 to build Plex; R300 onwards).** Stage 1 (client, models, fake server; R300),
stage 2 (the sign-in code page; R302), stage 3 (server list and connection order; R303) stage 4 (browse and index;
Plex is available in Add a Source; R304) stage 5 (playback: direct play and the app's own remux, no server
conversion; R305) stage 6 (watch state copied once, never written back; R306) and stage 7 (Plex's synopsis and poster first, TMDB
filling gaps; R307) are built and tested offline with hand-written fixtures; later stages are listed
in section 8. Nothing was compiled for tvOS and no Plex server or plex.tv was contacted. Section 10 names, per screen,
the Apple screen it follows (R301).

Original status of the plan below: **PLAN ONLY, nothing built.** No app code, no test server, no Plex account was used. Every decision below is
PROVISIONAL and listed in OPEN_QUESTIONS.md (R267 to R272) for the owner to confirm or change. Owner answers of 20 Nov
2026: sign-in (R267) follows the owner's wording, and R12 (B7) "no plex.tv sign-in", R19 "local-only mode if it works,
otherwise blocked" and the Plex part of R30 "account-blocked" are marked SUPERSEDED (kept as history). Metadata (R270) was
not answered and follows a stated assumption. S12 (plex.tv sign-in allowed for Plex only) already fits. S21 and the
media-server rule in docs/SOURCES.md ("Your Library Only, direct play only, our metadata authoritative") still stand
except where this plan says otherwise (R270 for metadata; R271 for the server-transcode fallback).

## Owner context (as stated by the owner, 20 Nov 2026)

- The owner has used Plex for their entire life and prefers it. **Plex is the primary source type for this app.**
- The owner's media library is on a portable SSD. At home, Plex Media Server on the owner's PC streams that library to the
  Apple TV over the home network. This is the path this plan serves.
- Away from home, the owner plugs the SSD into an iPad and plays it directly over USB-C with another app. That is a
  separate path and **not part of this app** (a possible later iPad version is a separate long-term plan).
- WebDAV stays working and untouched.

The owner's goal: add a Plex server in the same Add a Source flow as WebDAV, browse movies and shows, and play items in
the existing player with the same quality, metadata, artwork and Continue Watching behaviour as WebDAV items. WebDAV
behaviour must not change. The app stays brandless: "Plex" appears only as the plain-text name of the source type (it is
already on the `names-allowlist` in docs/NAMES.md); no Plex logo, colour or look anywhere.

## What was read (20 Nov 2026) and what was not

| Source | Result |
|---|---|
| Plex developer home, https://developer.plex.tv/ | Read in full (authentication: PIN and JWT flows, resources, headers) |
| Plex Media Server API, https://developer.plex.tv/pms/ | 20 Nov 2026: read in part (the page text returned to the fetch stops partway through the Library section; a second reader was refused by the site's robots.txt and was not retried). **21 Nov 2026:** the page was opened in a browser and the OpenAPI file it offers for download ("Download OpenAPI specification", `info.version` "1.2.3") was read: the Timeline operations (`/:/timeline`, `/:/scrobble`, `/:/unscrobble`), the Transcoder group (`/{transcodeType}/:/transcode/universal/decision`, `start.*`, `fallback`), `/status/sessions/terminate` and the Profile Augmentations text are now **(read)**; quotes in sections 5, 6 and 9 come from that file. Nothing else from it is claimed. |
| Plex Support, direct play and direct stream, https://support.plex.tv/articles/200250387-streaming-media-direct-play-and-direct-stream/ | **Not read**: HTTP 403 (the same as the earlier attempt recorded in docs/SOURCES.md, Plex B7) |
| Apple, AVPlayer, https://developer.apple.com/documentation/avfoundation/avplayer | Read: AVPlayer plays "local and remote file-based media, such as QuickTime movies and MP3 audio files, as well as audiovisual media served using HTTP Live Streaming"; tvOS 9.0+ |
| Apple, AVFileType, https://developer.apple.com/documentation/avfoundation/avfiletype | Read: the listed video file types are `mov`, `mp4`, `m4v` (and 3GPP); Matroska is not listed |
| Apple, HLS Authoring Specification for Apple Devices, https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices | 20 Nov 2026: read in part (the tvOS-specific section only as a summary). **21 Nov 2026:** read verbatim except the body of the HDR example playlist and the end of the revision history |

Rule for this document: an endpoint, parameter or behaviour quoted from a page read verbatim is marked **(read)**.
Everything else is marked **UNVERIFIED** and must be checked against the PMS reference (or recorded fixtures from a real
server the owner provides) before the stage that uses it is built.

## 1. Sign-in on an Apple TV

**Owner's answer (R267, PROVISIONAL): sign in the way a leading third-party tvOS player for personal libraries does it
today** (the owner named that app; the name is left out under the brandless rule, R332 and R301; that app signs in with
the owner's Plex account through plex.tv). Recorded as: **plex.tv account sign-in with a PIN or link code, then a server
chosen from the account's server list** (section 2). PROVISIONAL because it follows the owner's wording; the exact flow of
the app the owner named has not been verified (nothing of it was read). A manual server-address-plus-token path is **not**
the primary flow (it stays only as alternative (a) below).

The flow: the TV shows a short code and a link; the owner enters the code on a phone or computer where the owner is
already signed in to Plex; the TV polls until the token arrives.

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
documents for devices; it finds the owner's servers by itself (section 2). It contacts plex.tv, which R12 (B7) had
decided against; R12 is now marked SUPERSEDED by the owner's statement (20 Nov 2026), and S12 already allowed a plex.tv
sign-in for Plex only.

Alternatives (kept in R267, none is the primary flow):
- (a) Server address plus a token pasted by the owner (from the Plex account on a computer). No plex.tv call from the
  app, but typing a ~20-character token with the remote, and the owner has to find the token without help.
- (b) R12's local no-auth mode (server setting "allowed without auth", typed address, no token). Plex grants listed
  networks "full administrative access" and forum reports call it inconsistent (docs/SOURCES.md, from summaries).
- (c) The JWT PIN flow from the start.
- (d) Keep Plex blocked (R19, R30 as first written; now against the owner's statement, kept only so it is not lost).

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
| `Guid` `tmdb://…` | `LibraryItem.tmdbID` | Exact match for the TMDB lookup that fills gaps (better than filename matching) |
| `title`, `year` | title, year | Shown first (R270 assumption); TMDB only when Plex has none |
| `duration` (ms) | runtime | Yes (seconds) |
| `Media`/`Part` codecs, container, size, width, height | technical facts | Yes, decides the playback route before opening the file |
| `summary`, `thumb`, `art`, `contentRating`, `rating` | details and artwork | **R270, PROVISIONAL (the owner did not answer; assumption)**: Plex's matched metadata and artwork first, TMDB only to fill gaps (`DetailsLayers.swift` already names "a Jellyfin, Emby or Plex server" as layer 1). For Plex this differs from "our metadata authoritative" and "Titles from the server are never used", which stay as they are for Jellyfin and Emby. Alternative kept visible: TMDB first, Plex as fallback (the earlier choice) |
| `viewOffset`, `viewCount`, `lastViewedAt` | resume, watched | **UNVERIFIED** names (not in the text read); section 6 |
| `Stream` (audio and subtitle tracks, language, codec) | track menus | **UNVERIFIED** (not in the text read); the system player draws the menus as today |
| `addedAt`, `updatedAt`, `Rating` image ids, `tvdb://`, collections, extras, chapters, markers (intro) | not used yet | Listed for later; markers could feed the existing segment (skip-intro) data |

Endpoints for browsing (UNVERIFIED unless marked): `/library/sections` and `/library/sections/{id}/all` (named in the
reference's table of contents only), `/library/metadata/{id}/children` and `/allLeaves` (read: children "Passing no paging
headers here should only return the first 20 Metadata objects", so the client must page), `/library/metadata/{id}`
(read, sample). JSON only when asked: "The default is XML, so JSON will only be returned if it's explicitly requested
(`Accept: application/json`)" (read). Images through `/library/metadata/{id}/images` (read, name only) or the photo
transcoder (UNVERIFIED), sized for the TV, with the token in a header where possible.

**Built in stage 7 (R307):** for Plex files only, the movie page's synopsis is the server's `summary` (TMDB then fills
only what is missing, such as the cast), and the card's picture is the server's `thumb` (a movie's poster, an episode's
still), read once with the token in a header and kept in the artwork cache, after any picture next to the file and before
the online poster. Show pages and show posters still come from the online layers (the show's own record is not read).
Titles, years and the item model still come from the app's own matcher on the file names. WebDAV, Jellyfin and Emby keep
their order exactly (tests compare them with and without the Plex layer).

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
   VC-1, or a server that refuses ranges). The universal transcoder, read 21 Nov 2026 in the OpenAPI file: `GET
   /{transcodeType}/:/transcode/universal/decision` "Make a decision on media playback based on client profile, and
   requested settings such as bandwidth and resolution" and `GET /{transcodeType}/:/transcode/universal/start.*` "Starts
   the transcoder and returns the corresponding streaming resource document" (answer types include
   `application/vnd.apple.mpegurl`), with `protocol` one of `http`, `hls`, `dash`, and `directPlay`, `directStream`,
   `directStreamAudio` as 0 or 1 (read). Not built: see "Later: server conversion" below. The player shows a plain
   "Converted by the server" line in the info panel so the owner knows quality is reduced. Whether Plex's "Direct Stream"
   (remux without re-encode) can be requested this way is UNVERIFIED (the Plex Support page was not readable).

Subtitles and audio: in routes 1 and 2 the tracks come from the file itself, as today (system menus; picture subtitles
through the existing remux menu). External subtitle files that Plex lists as separate streams (`.srt` next to the film)
need the `Stream` data (UNVERIFIED) and are a later stage. In route 3 the transcoder decides; burned-in subtitles are
avoided by asking for WebVTT where the API allows it (UNVERIFIED).

**Built in stage 5 (R305):** routes 1 and 2 only. Route 3 is NOT built: a file whose video format is on the refused list
(MPEG-2, VC-1, older Windows formats, Theora, RealVideo) shows "The Apple TV cannot play this file ..." before the player
starts, and no request ever goes to a transcode or decision path (a test checks it). One client per server address is
shared by the app and its listing is reused for five minutes, so starting playback does not read the whole library again.

### Later: server conversion (R305 a, decided by the owner 21 Nov 2026 for later; nothing built)

What was read on 21 Nov 2026 (OpenAPI file of https://developer.plex.tv/pms/, and Apple's HLS Authoring Specification):

- Decision: `GET /{transcodeType}/:/transcode/universal/decision`, `transcodeType` one of `video`, `music`, `audio`,
  `subtitles`. Query parameters include `path` ("Internal PMS path of the media to transcode"), `protocol`, `directPlay`,
  `directStream`, `directStreamAudio`, `mediaIndex`, `partIndex`, `videoBitrate`, `peakBitrate`, `videoResolution`,
  `videoQuality`, `audioChannelCount`, `offset`, `subtitles`, `transcodeSessionId`. Headers: `X-Plex-Client-Identifier`
  (required), `X-Plex-Client-Profile-Extra`, `X-Plex-Client-Profile-Name` ("Generally should only be used to specify the
  Generic profile"), `X-Plex-Session-Identifier`. The answer carries `generalDecisionCode`, `directPlayDecisionCode`,
  `transcodeDecisionCode` with their `Text`, and `availableBandwidth` (read); what each code value means is not stated.
- Start: `GET /{transcodeType}/:/transcode/universal/start.*` with the same parameters; answers
  `application/vnd.apple.mpegurl` or `video/x-matroska` (read).
- Fallback: `POST /{transcodeType}/:/transcode/universal/fallback` with `transcodeSessionId`, "Manually trigger a
  transcoder fallback ex: HEVC to h.264 or hw to sw" (read).
- Codec limits: `X-Plex-Client-Profile-Extra`, url-encoded directives joined by "+": `add-transcode-target(type=…&context=
  streaming|static&protocol=hls|http|…&container=…&videoCodec=…&audioCodec=…)`, `add-limitation(scope=…&scopeName=…&type=
  match|notMatch|upperBound|lowerBound&name=…&value=…)`, `add-direct-play-profile`, `add-transcode-target-codec`,
  `append-transcode-target-codec`, `add-settings` (read).
- Apple (read verbatim): video "MUST be encoded using H.264/AVC, HEVC/H.265, Dolby Vision, or AV1"; tvOS H.264 "MUST be
  less than or equal to High Profile, Level 5.1"; "The container format for HEVC video MUST be fMP4"; H.264 in fMP4 or
  MPEG transport streams; "Your EXT-X-STREAM-INF tag MUST always provide the CODECS attribute"; "Video segments MUST start
  with an IDR frame". Audio lists AAC, AC-3, E-AC-3 (and others); DTS is not mentioned anywhere on the page.

Stage plan (each offline first, then the owner's device check):
1. Decision request and a tvOS profile string (H.264, HEVC only in fMP4; AAC, AC-3, E-AC-3; `protocol=hls`), the
   decision answer read from hand-written fixtures.
2. A "server conversion" playback route instead of today's refusal for MPEG-2 and VC-1: start request, session
   identifier, the playlist through the app's own loopback server, ending the session when playback stops.
3. The fallback call when the player fails, and a plain "Converted by the Plex server" line in the info panel.
4. Device only: AVPlayer plays the playlist, seeking, picture quality, server load, sessions ended.

Open problems:
- **No documented stop call.** No `/transcode/universal/stop` path is in the OpenAPI file (the text does not contain it).
  The only documented end is `POST /status/sessions/terminate` with `sessionId`, "Terminate a playback session kicking off
  the user": the wrong tool for a client ending its own session. Whether an unused session ends by itself, and when:
  UNVERIFIED. No ping or keep-alive operation is documented either.
- **Re-encoding cost on the owner's PC.** MPEG-2 and VC-1 cannot be repackaged for the Apple TV; the server must re-encode
  the whole video while it plays. Whether the owner's server uses hardware for it is not on these pages (UNVERIFIED).
- **The token in HLS.** AVPlayer fetches the playlist and every segment itself, so the app cannot add the token header to
  those requests through a documented API. Plex allows every `X-Plex-` header "as query string arguments" (read), but that
  puts the token in addresses and logs (R300; R305 alternative d). The plan keeps the header: the playlist and segments go
  through the app's own loopback server (the one the remux already uses), which adds the header (UNVERIFIED with Plex).
- **Highest quality.** The OpenAPI file describes `videoQuality` (0 to 99) as "Target photo quality" and gives
  `videoResolution` a pattern that allows only one digit on each side; how to ask for the original quality is UNVERIFIED.
- Whether Plex's playlists carry the `CODECS` attribute Apple requires, and which segment container they use: UNVERIFIED.

## 6. Watched state and resume position

Recommended (R272): **read once, then local only** for the first stages. When an item is first indexed, Plex's resume
position and watched flag (UNVERIFIED field names `viewOffset`, `viewCount`) seed the app's `WatchState` if the app has
none for that item; after that the app's own records (synced through iCloud like every source) are the truth, and the app
writes nothing back to the server. Reason given on 20 Nov 2026: writing to the server needs the timeline and scrobble
endpoints, whose parameters were not in the text read then, and wrong writes would change the Plex history on other
devices. The parameters were read on 21 Nov 2026 (below) and the owner chose two-way (R306 b).

Read 21 Nov 2026 (OpenAPI file of https://developer.plex.tv/pms/):
- `POST /:/timeline`, "Report media timeline": "This endpoint is hit during media playback for an item. It must be hit
  whenever the play state changes, or in the absence of a play state change, in a regular fashion (generally this means
  every 10 seconds on a LAN/WAN, and every 20 seconds over cellular)." Query: `key` ("The details key for the item"),
  `ratingKey`, `state` (`stopped`, `buffering`, `playing`, `paused`), `time` ("The current time offset of playback in
  ms"), `duration` (ms), `continuing` (0 or 1, with `stopped`), `playQueueItemID`, `offline` (0 or 1, "used to indicate
  that a timeline is being synced from being offline, as opposed to being live"), `updated` ("Used when a sync client
  comes online and is syncing media timelines, holds the time at which the playback state was last updated"), and
  playback statistics. Header `X-Plex-Client-Identifier` required ("Unique per client"); `X-Plex-Session-Identifier`
  optional ("Unique per client playback session"). Answers 200 or 400.
- `PUT /:/scrobble`, "Mark an item as played": "this does not create any view history of this item but rather just sets
  the state as played. The client must provide either the `key` or `uri` query parameter … applications should use PUT".
  Query: `identifier` (required, "Typically `com.plexapp.plugins.library`"), `key` ("This is the `ratingKey` found in
  metadata items"), `uri`. `PUT /:/unscrobble`, "Mark an item as unplayed", the same parameters. Answers 200, 400, 404.
- Media-Providers: the timeline feature "may additionally specify the `scrobbleKey` and `unscrobbleKey` attributes", and
  clients should "read them from the feature keys directly".
- Not documented: any rule for conflicts (the app and Plex both changed), whether `time` in a timeline becomes the item's
  `viewOffset`, and whether a `stopped` timeline near the end creates a history entry: UNVERIFIED.

Alternatives (R272): (a) fully read-only, never seed; (b) two-way: report progress with the timeline call while playing
and mark watched at 95 % (`LibraryWatchRules.watchedFraction`) with scrobble, as a later stage after recorded fixtures
prove the parameters.

**Built in stage 6 (R306):** the recommended "read once, then local only". After the first complete scan of a Plex
source, a played item (`viewCount` above 0 and no resume point) is marked watched and an item stopped at 30 seconds or more
resumes there, only where the app has recorded nothing; the source then carries the option `seeded=done` and is never
seeded again. No timeline, scrobble or any other write is sent (a test fails on any request but GET or HEAD to the server).

**Decided by the owner, 21 Nov 2026 (R306 b): two-way watch state, top priority, built offline in three stages.**
(1) a write client for the three calls above, token in a header only, paths from the server's feature keys with the
documented paths as the fallback; (2) wiring to the player and to the app's own Mark as Watched and Unwatched, behind a
per-source switch "Sync Watched Status with Plex", off by default; (3) newer change wins (Plex's `lastViewedAt` against
the app's own change time) and a queue for writes made while the server cannot be reached, replayed with `offline=1` and
`updated`. With the switch off the stage 6 behaviour above stays exactly as it is. Stage 4 is the owner's device check.

**Built, two-way stage 1 (R308):** `PlexWatchWriter` (SourcePlex) behind the protocol `ServerWatchWriting`
(VideoPlayerCore): the three calls exactly as quoted above, paths from `/media/providers` (documented fallback), the token
in a header only; `ServerTimelineRhythm` decides when a report is due (every state change, otherwise every 10 seconds).

## 7. Test plan per stage (no real server, no network)

The pattern already used for Jellyfin and Emby (`Tests/SourceJellyfinTests/`: a fake server, JSON fixtures, client
tests): a `FakePlexServer` in the test target answers on 127.0.0.1 with JSON fixtures. No real Plex server can run here
(scripts/test-servers.sh notes this; setting one up needs a plex.tv account). The fixtures are hand-written from the
fields read on the PMS page and marked "HAND-WRITTEN, not recorded"; if the owner later records responses from the
Plex server, `scripts/record-mediaserver-fixtures.sh` already redacts tokens for Jellyfin and Emby and would get a Plex mode.

| Stage | Tests (all offline) |
|---|---|
| 1 Skeleton | client headers (client identifier, product, JSON `Accept`), decoding of the models read on the PMS page, the fake server answers; Plex still blocked in the app |
| 2 Sign-in | PIN create, poll until `authToken`, expired PIN, `authToken` null until claimed, headers sent (client id, product), token never in logs or errors (fake plex.tv endpoints) |
| 3 Servers | resources JSON with local, remote and relay connections; order chosen; relay skipped unless allowed; all down = offline state |
| 4 Browse and index | sections, paged children (21+ items to prove paging), shows to seasons to episodes, tree paths built from `Part.file`, XML response refused (we always ask for JSON); model: mapping table above, `tmdb://` to `tmdbID`, ms to seconds, same file on WebDAV and Plex gives one item key, WebDAV tests unchanged |
| 5 Play | route choice per container and codec (mp4 HEVC direct, mkv DTS remux, MPEG-2 transcode fallback), ranged reads through the fake server (206, 416), token header present, token absent from every logged URL |
| 6 Watch seed | seeding only when the app has no record; never overwrites; no write requests sent (the fake server fails the test on any POST/PUT to timeline or scrobble) |
| UI | Add a Source shows Plex as available; existing UI fixture `10-add-source-types-HIERARCHY.txt` and the tests that assert Plex is blocked (`SourceWiringTests` lines 63, 86, 96, 119; `SourceStatusTests` lines 26 to 28) change in the same stage that unblocks it; design lint: "Plex" only as allowlisted plain text, no "Works with", no logo |

Device checks (owner, on the Apple TV): sign in with the code, one local and one remote server, direct play of an MP4,
an MKV with DTS, a 4K Dolby Vision file, resume after stopping, offline server. Added to
docs/DEVICE_TEST_CHECKLIST_SOURCES.md when the stage is built.

## 8. Stages, each small enough to review

0. **Owner decisions** R267 to R272. Answered 20 Nov 2026: R267 (PROVISIONAL, owner's wording) and the SUPERSEDED marks
   on R12, R19 and the Plex part of R30. Still open: R268, R269, R270 (assumption only), R271, R272.
1. `SourcePlex` target and client skeleton: headers, client identifier, JSON decoding of the models read on the PMS page;
   fake server; no UI. Plex stays blocked in the app.
2. PIN sign-in in `LiveSourceConnector` (the existing device-code `SignInSession` used by OneDrive is the model) and
   the Plex form in Add a Source; token to the Keychain; still no browsing.
3. Server list and connection choice (local first, relay off).
4. Browse and index: sections, items, seasons, episodes into the existing scanner; Plex unblocked in Add a Source.
5. Direct play and remux routes.
6. Watch-state seed (read once).
7. Later, each after its own decision: the Plex-first metadata layer with TMDB filling gaps (R270; or the TMDB-first
   alternative), external subtitle streams, the HLS transcode fallback, two-way watch state, the JWT sign-in.
   Owner, 21 Nov 2026: two-way watch state decided, top priority (R306 b; section 6); the HLS transcode fallback decided
   for later (R305 a; section 5, "Later: server conversion").

Every stage keeps WebDAV untouched: no change to `SourceWebDAV`, and the WebDAV tests must pass unchanged in each commit.

## 9. Unverified items and where to verify each

Every item below stays UNVERIFIED until a later stage reads the named page (or records a fixture from the owner's
server) before building on it. "Checked 20 Nov 2026" says what that page gave this time; nothing here is a claim beyond it.

| Item | Page that should answer it | Checked 20 Nov 2026 |
|---|---|---|
| Library endpoints and field names (`/library/sections`, `/library/sections/{id}/all`, `viewOffset`, `viewCount`, `lastViewedAt`, `Stream`/`streamType`) | https://developer.plex.tv/pms/#tag/Library (and its "Get a stream" operation); https://developer.plex.tv/pms/#section/API-Info/Media-Queries | Section loads ("Library endpoints which are outside of the Media Provider API"); `/library/sections` appears only as a sample URL; the other names were not in the text returned; "Get a stream" body not returned |
| Transcoder endpoint and parameters (`/video/:/transcode/universal/start.m3u8`, decision, Direct Stream) | https://developer.plex.tv/pms/ Transcoder group ("Make a decision on media playback", "Start A Transcoding Session"); https://developer.plex.tv/pms/#section/API-Info/Profile-Augmentations; Plex Support "Streaming Media: Direct Play and Direct Stream", https://support.plex.tv/articles/200250387-streaming-media-direct-play-and-direct-stream/ | 20 Nov: operation names only; Profile-Augmentations read (`X-Plex-Client-Profile-Extra`); the support article returned HTTP 403 earlier and was not fetched again. **21 Nov 2026, OpenAPI file: decision, start, fallback and Profile Augmentations read** (section 5, "Later: server conversion"). Still UNVERIFIED: a stop call (none documented), decision code meanings, highest-quality parameters, the playlist's `CODECS` and segment container |
| Timeline and scrobble (`/:/timeline`, `/:/scrobble`, `/:/unscrobble`) | https://developer.plex.tv/pms/ Media Provider > Timeline ("Report media timeline", "Mark an item as played", "Mark an item as unplayed"); https://developer.plex.tv/pms/#section/API-Info/Media-Providers | 20 Nov: names only. **21 Nov 2026, OpenAPI file: read** (paths, methods, parameters and the 10-second rhythm, quoted in section 6). Still UNVERIFIED: conflict handling (not documented), whether `time` becomes `viewOffset`, whether a stopped timeline creates history, the exact form of the server's feature keys |
| Server-list identification (telling servers apart from other resources, e.g. `provides`) | https://developer.plex.tv/pms/#section/API-Info/Authenticating-with-Plex ("Talking to PMS"); https://developer.plex.tv/pms/#tag/General/operation/securityGetResources | `provides=server` not found; connections carry `local` and `relay`; the `clientIdentifier` sample is from the server's own `/security/resources`, not the plex.tv list |
| HTTPS certificate validation on tvOS (`*.plex.direct`) | Plex Support "How to Use Secure Server Connections", https://support.plex.tv/articles/206225077-how-to-use-secure-server-connections/; https://developer.plex.tv/pms/#tag/General/operation/getSlash (`"certificate": true`); Apple's side only on a device | Plex: certificates via Let's Encrypt, server setting defaults to "Preferred". That tvOS accepts them: needs a device run |
| Remote access and connection choice | Plex Support "Remote Access", https://support.plex.tv/articles/200289506-remote-access/; "Troubleshooting Remote Access", https://support.plex.tv/articles/200931138-troubleshooting-remote-access/; "Accessing a Server through Relay", https://support.plex.tv/articles/216766168-accessing-a-server-through-relay/ | First two read: setup and port forwarding only, no client connection-choice rule; relay article not fetched |
| Token as header or URL parameter | https://developer.plex.tv/pms/#section/API-Info/Headers | Read: "all `X-Plex-` headers can also be sent as query string arguments". Which form AVPlayer needs for ranged reads: device run |
| PIN lifetime | https://developer.plex.tv/pms/#section/API-Info/Authenticating-with-Plex (Legacy, step 4 "Generate a PIN") | Read: short PIN has "a much shorter lifetime", no number; the 7-day figure is for JWTs |
| Local no-auth networks (alternative (b) only) | Plex Support "Authentication for Local Network Access", https://support.plex.tv/articles/200890058-authentication-for-local-network-access/ | HTTP 403, not read |
| tvOS codec limits | Apple, HLS Authoring Specification for Apple Devices, https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices (tvOS section) | **21 Nov 2026: read verbatim**, tvOS amendments included (H.264 at most High Profile Level 5.1; SDR trick play streams; no audio-only variants) |
| Token storage (Keychain) | Apple, Keychain services, https://developer.apple.com/documentation/security/keychain-services | The link as given (`.../security/keychain_services`) did not load through the documentation reader (page not found); the hyphenated address loaded: "Securely store small chunks of data on behalf of the user." Nothing more was needed from it for this plan |

## 10. Screens and their design reference (owner's principle, R332; applied in R301)

Adding a source has no equivalent in Apple's TV app, so the Plex setup screens follow **tvOS Settings**; the Plex
library uses the app's existing Home, Movies, Shows and detail screens, whose gaps against the TV app are listed in
docs/HIG_AUDIT.md, section "Against Apple's TV app" (T1 to T19 for those screens; T20 is the Plex sign-in code page below). Pages read 20 Nov 2026: HIG Designing for tvOS, Managing
accounts, Materials, Collections, Tab bars, Playing video, Searching; apple.com/apple-tv-app. The SwiftUI page
`/documentation/swiftui/lockups` did not load ("Apple documentation page not found"). Nothing here was seen on a screen.

| Screen | Follows | What is different, and why |
|---|---|---|
| Plex sign-in code page (`PlexSetupView`, stage 2, R302) | tvOS Settings (adding a source) | A full-screen page with the code as its largest text, not a Settings form: HIG Managing accounts, tvOS, "Prefer letting people use another device to sign up or authenticate" and "Minimize data entry" (a tvOS guideline of that page, read again 21 Nov 2026); Designing for tvOS: people sit "often 8 feet or more" away. Says how it signs in and why ("Always identify the authentication method you offer"; "Display this message in your sign-in view"). "plex.tv/link" is plain text, no logo or Plex look. Whether tvOS Settings has a page of this exact shape is UNVERIFIED (no Apple page read shows one). The QR code is an alternative only (R302). |
| Plex server list (`PlexSetupView`, stage 3, R303) | tvOS Settings list (the same `TaskPage` Form as Add a Source and the forms) | One system row per server, the name and "Local" or "Remote" as secondary text (rule L2), a footer on what adding does. A server that cannot be reached is a system error page with Try Again, not a row state. Same as the other setup lists; nothing differs. |
| Plex library, detail and player | The TV app screens the app already has (Home shelves, movie and show pages, the system player) | No Plex-specific screen: Plex items appear in the same screens as every other source, so the TV app gaps T1 to T19 apply to them unchanged (T20 is the code page only) and are fixed (or not) for all sources at once. |
| "Cannot play this file" (stage 5, R305) | The app's existing playback error (system alert) | One calm sentence; the server transcode is not built (R271 kept open). |
