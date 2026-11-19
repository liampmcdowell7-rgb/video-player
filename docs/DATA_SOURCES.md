# Data sources, keys and licences (#26)

The app ships with **no key**. Each user brings their own free TMDB key, entered **once** in Settings > Online Lookup. That
one key covers the whole app: every source type (WebDAV, SMB, NFS, SFTP, FTP/FTPS, UPnP/DLNA, OneDrive, Web Links,
Jellyfin, Emby, Plex), every library, Discover, pictures and details. Adding a source never asks for a key. Two key-free
sources (Wikidata, IntroDB) can be turned on with one switch, Free Data Sources, which is **off** until the user turns it
on (PROVISIONAL, OPEN_QUESTIONS R209), so nothing is sent anywhere until lookup is set up.

The app is **non-commercial for now**. Section 4 lists what would change if it were sold (open item R215, not decided).

Terms were read on 2026-11-19 from the services' own pages; they are summarised here in our words, without quotes. No
service was contacted in any other way, and no test talks to a real service (every client test uses a fake transport).

## 1. Audit: every key, token or service credential

"Removable" means the app works fully without it. "Licence for commercial use" is about the data, as each service's terms
say it (section 3).

| Service / credential | Where it is asked for | Where it is stored | Where it is read | Required / optional / removable | Licence status for commercial use | What the app does without it |
|---|---|---|---|---|---|---|
| TMDB key (API key or read access token), the user's own | Settings > Online Lookup only (one row, native secure field) | `OnlineKeyStore`: Keychain items of service `com.liamp.videoplayer.keys`, one per keyed service, plus the encrypted iCloud copy (`MirroredSecrets` → `CloudKitSecretCloud`, private database, encrypted values) | `OnlineServices.rebuild` (TMDB client for pictures, details, Fix Match, Discover, where to watch, Needs Review sorting); with Free Data Sources on, TMDB's external ids give the IMDb id for IntroDB | Optional | Personal, non-commercial only; commercial use needs a written agreement with TMDB | Plays everything; pictures and details come from files next to the videos; Discover says "Discover Needs a Key"; Fix Match, Synopsis and online pictures each say in one line that the key is needed and where |
| OMDb key, the user's own | Settings > Online Lookup only | same store, its own item | Nowhere: saved but no code path calls OMDb | Optional, **removable** (R211) | Not reviewed in #26 (no request is ever made) | Nothing changes: nothing uses it |
| Source passwords and sign-in tokens (WebDAV, SMB, NFS, SFTP, FTP, Jellyfin, Emby, Plex, Web Link, OneDrive) | The source's own form (Add a Source) or its sign-in | Keychain service `com.liamp.videoplayer.sources` (not synchronizable; tvOS ignores the flag anyway) plus the encrypted iCloud copy | The source client only | Required for that source when it needs a sign-in | Not a data source: the user's own server | That source asks again (`CredentialGap`) |
| OneDrive app registration (client id) | Nowhere (would be built into the app) | — | `SourceConfiguration` (nil today) | Not set: OneDrive sign-in is blocked until an app is registered | A public app id, not a secret | OneDrive shows "blocked: needs an app registration" with the alternatives |
| Wikidata | No key exists | — | `WikidataClient` (MetadataOnline) | Optional (Free Data Sources) | CC0 for the structured data: commercial use allowed | Cast from TMDB only (with a key) or none |
| IntroDB | No key needed for reads | — | `IntroDBClient` (MetadataOnline) | Optional (Free Data Sources) | Commercial apps with reasonable use allowed (terms) | Skip Intro uses chapters, sidecars and user marks only |
| Subtitle services, intro/credits data other than IntroDB, Top Shelf | None ask for a key | — | Top Shelf reads only the app's own shared folder | — | — | — |
| TVmaze | Not built (R212) | — | — | — | Data CC BY-SA; commercial use not stated | — |
| Fanart.tv | Not built (R213) | — | — | — | Open decision | — |
| TheTVDB | Not allowed (user decision) | — | — | — | — | — |
| Tests | Placeholder text only, never a real key; the UI tests use one synthetic key (`UITestLaunch.fakeTMDBKey`) in the in-memory store and never send it | — | — | — | — | — |

Per-source or per-library key fields: **none exist** (`SourceFieldKind` is name, address, host, port, share, folder,
username, password, security). A package test checks every source form; the UI test opens every source form and, with a
key set and a second source being added, fails if any field is labelled with "key" or "token".

## 2. Where keys never go

Keys are kept out of: the library backup (the backup refuses any file containing a key: `BackupHost` forbidden list, now
also any key not yet migrated), the iCloud library sync (`UserDataLedger` records hold no key), the export file and the
essentials copy (both are ledger records), logs (`TMDBCredentials` prints "redacted"; error texts are fixed sentences),
screenshots and UI-test dumps (shown masked as dots plus the last four characters; the CI artifact check fails if the
synthetic key's whole text is in any artifact file), crash text (no key is put in an error) and CI artifacts. Tests:
`AppWideKeyStoreTests.testNoKeyInTheBackupExportTheSyncedLibraryOrLogs`, `BackupEngineTests.testNoPasswordTokenOrAPIKeyCanBeUploaded`,
`scripts/test-ci-artifact-contents.sh`.

**iCloud Keychain sync on tvOS (R207).** The user asked for kSecAttrSynchronizable. Apple's page for that key (re-read
2026-11-19) says tvOS does not synchronize keychain items through iCloud and items stored on tvOS never leave the device.
The key store sets the flag anyway (reads and deletes match with "any"), and if the system refuses a synchronizable item the
key is stored without it (behaviour on tvOS unverified). What actually brings the key to another Apple TV on the same
iCloud account, or back after a reinstall, is the encrypted iCloud copy the app already keeps for source passwords. Keys an
earlier version kept with the source passwords are moved once (`OnlineKeyStore.migrateLegacy`). Device check: checklist
items K1–K4.

## 3. Terms, summarised (read 2026-11-19)

**TMDB** (themoviedb.org API terms of use and the getting-started page).
- Commercial use needs a separate written agreement; the free key is for personal, non-commercial use.
- The licence is personal and cannot be transferred or sublicensed. With bring-your-own-key, each user is their own
  licensee and the app ships no key. The terms do not address an open-source app whose users bring their own keys; nothing
  read forbids it, but nothing explicitly allows it either (R214).
- Attribution: the TMDB logo, less prominent than the app's own marks, and a fixed notice placed prominently. The user
  decided the logo and the notice appear only in Settings > About > Data Sources; whether that counts as "prominent" is
  for TMDB to judge (R214).
- Cached data at most six months; no use for AI training; the app must not hide its identity; delete TMDB content when the
  licence ends. No numeric rate limit on the pages read.
- Getting a key: an account, then account settings > API, done in a browser, accepting the terms.

**IntroDB** (introdb.app terms and API pages).
- Commercial apps with reasonable use are allowed. No bulk crawling: bulk use goes through their data export (ODbL).
- Credit is optional for API use (given anyway, text only).
- Anonymous reads need no key. Caching and numeric rate limits are not addressed (the app caches 7 days, "none" 1 day,
  one request per second at most, own cap 300 per day).
- Endpoint: GET api.introdb.app/segments with imdb_id and season/episode, or is_movie=true. Fields: intro, recap,
  outro (each null or start/end in seconds and milliseconds, confidence, submission count). Errors are not documented on the
  pages read; the OpenAPI file was not read.

**theintrodb.org** — the landing page shows no API, terms, licence or commercial information. **Not added** (R216).

**Wikidata** (Wikidata licensing and query-service pages, Wikimedia User-Agent and API etiquette pages).
- Structured data is CC0 (public domain): commercial use allowed, no credit required (given anyway, text only). Other
  namespaces are CC BY-SA; Wikimedia Commons images are not covered and are not used.
- Etiquette: a descriptive User-Agent with a way to reach the maker (the app sends its name, version and repository
  address), compressed responses, honour 429 and Retry-After. maxlag applies to the Action API, which the app does not use
  (it uses the SPARQL query service). The app caches 30 days, "none found" 7 days, one request per second, own cap 300 per day.

**TVmaze** (tvmaze.com API page). Data under CC BY-SA 4.0 with a link back; commercial use not mentioned (larger use via
their sales team); images not stated as covered. Provisional only, OFF, nothing built (R212).

**Conflicts flagged:** TMDB prominence vs About-only placement (R214); kSecAttrSynchronizable has no effect on tvOS (R207);
IntroDB gives no release duration, so the strict duration rule B1 had to be relaxed for intro and recap (R208).

## 4. Licence table: if the app were sold

| Source | Data licence | Today (non-commercial, open source, user's own key) | If the app were sold |
|---|---|---|---|
| TMDB | TMDB API terms (personal, non-commercial key) | Allowed for each user's own key (R214 open) | Needs a commercial agreement with TMDB, or remove TMDB |
| JustWatch (where to watch, through TMDB) | Through TMDB's terms, credit required | Shown with credit | Covered only by a TMDB commercial agreement |
| Wikidata | CC0 | Allowed | Allowed, unchanged |
| IntroDB | Their terms: commercial with reasonable use | Allowed | Allowed with reasonable use; bulk only via the ODbL export (share-alike on the database) |
| OMDb | Not reviewed (not used) | Not used | Review before any use |
| TVmaze | CC BY-SA 4.0, commercial use unclear | Not built | Ask TVmaze first |
| Fanart.tv | Open decision | Not built | Open |

## 5. Source order and coverage (item 6, PROVISIONAL R210)

Synopsis and cast: the source's own details first (Jellyfin, Emby, Plex servers, NFO files, embedded tags), then Wikidata
(Free Data Sources on), then TMDB (key set). A later layer fills only gaps: synopsis, cast list, a cast member's role or
photo by name. Alternative: TMDB first.

Honest coverage today: the library stores **no synopsis or cast from the source layer** (the NFO reader and the server
sources do not keep them), so layer 1 is always empty for now, and the IMDb id from an NFO or a server is not stored either
(IntroDB then needs TMDB or Wikidata to find it). How much of a real library each layer covers can only be measured on a
device with real sources: checklist item K8 records it. `LayeredDetails.used` says which layers gave something.

Skip Intro (item 5a): chapters, sidecars and user marks first; IntroDB only when none of them gives a segment, under the
same 6-second deadline. IntroDB intro and recap are accepted without a reference duration (R208); IntroDB credits are not.
A failure gives a note in File Details and no segment, so no Skip button.

## 6. Code map

- Key store: `AppLogic/OnlineLookup.swift` (`OnlineKeyStore`, texts), `UserData/Apple/KeychainCredentialStore.swift`,
  `App/Support/AppDependencies.swift` (`keyCredentials`), `App/Support/AppServices.swift` (wiring, backup forbidden list).
- Screen: `App/Features/Settings/OnlineLookupSettingsView.swift`; credits: `App/Features/Settings/AboutView.swift`,
  `App/Support/Attribution.swift`.
- Clients: `MetadataOnline/IntroDBClient.swift`, `MetadataOnline/WikidataClient.swift`.
- Use: `AppLogic/OnlineSegments.swift` (IMDb id chain, IntroDB → segments), `AppLogic/SegmentSourcing.swift` (online slot),
  `AppLogic/DetailsLayers.swift` (layer order), `App/Support/OnlineServices.swift`, `App/Support/SegmentService.swift`.
- Tests: `MetadataOnlineTests/KeyFreeSourceTests.swift`, `AppLogicTests/AppWideKeyTests.swift`,
  `PlaybackLogicTests/SegmentTests.swift` (SEG-3), UI test `test03_Settings` and `test02_AddASource` (no key field).
