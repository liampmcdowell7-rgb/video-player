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
| OMDb key | **Removed in #27** (R211): no row, no client, no stored item. A key saved by an earlier version is deleted once from this device, the old items and the iCloud copy (`OnlineKeyStore.removeRetiredKeys`) | — | Nothing read it: the only uses were the Settings row and the status line; the OMDb client was never created by the app | — | — | Nothing changes |
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
key is stored without it (behaviour on tvOS unverified). Keys an earlier version kept with the source passwords are moved
once (`OnlineKeyStore.migrateLegacy`). What brings the key to another Apple TV is the encrypted iCloud copy below.

### 2a. The encrypted iCloud copy, in plain words (#27 item 1, OPEN_QUESTIONS R220)

Apple pages read 2026-11-19: CKRecord.encryptedValues and "Encrypting User Data" (developer.apple.com), "iCloud data
security overview" (support.apple.com/102651) and "How to turn on Advanced Data Protection for iCloud"
(support.apple.com/108756).

**(a) Where it is stored.** Not in a file and not in iCloud Drive. It is one CloudKit record in the app's own iCloud
container `iCloud.com.liamp.videoplayer`, in the user's **private** database (only that Apple Account can reach it), in a
record zone called **Secrets** (`UserDataModule.secretsZoneName`). The record type is `SourceSecret`, the record name is
`secret-online-key.tmdb`, and the key itself is in one field, `secret`, written through `encryptedValues`
(`CloudKitSecretCloud`). Source passwords sit in the same zone, one record each (named after the source's random id). The
library sync uses a different zone, **UserData**, and never holds a key: `AppWideKeyStoreTests.testTheEncryptedKeyCopyIsSeparateFromTheLibrarySync`
runs a full library sync and checks that no key (and no key record) reaches it, and that the key is only in the secrets
store. The library backup refuses any file that contains a key (section 2).

**(b) What encrypts it.** CloudKit itself. Apple's page says CloudKit encrypts an `encryptedValues` field on the device
before saving it to iCloud and decrypts it only after fetching it. The app adds no encryption of its own and never sees
the encryption key.

**(c) Where the encryption key lives, and whether a second Apple TV can decrypt it.**
- Apple's "Encrypting User Data" page says CloudKit encrypts with key material in the user's **iCloud Keychain**. That is
  the system's own keychain for the Apple Account, not the app's Keychain items (which, on tvOS, never leave the device).
- With standard iCloud data protection, Apple's overview says third-party CloudKit data is encrypted in transit and on the
  server, and the keys from the user's trusted devices are kept in Apple's data centres. So **Apple holds the means to
  decrypt it**. The key is not stored next to the data in the record, but the same company holds both.
- With Advanced Data Protection turned on, the overview says CloudKit encrypted fields are end-to-end encrypted. Only the
  user's trusted devices hold the keys, and Apple cannot read the value.
- **Second Apple TV.** Apple's Advanced Data Protection page lists "Apple TV with tvOS 16.2 or later" among the devices
  that must meet its requirements. That fits Apple TVs holding the account's keys, but no Apple page read says in so many
  words that an Apple TV can decrypt a CloudKit encrypted field. **Unverified; device checks K1–K4.** If it cannot, the
  download fails or comes back empty, the app keeps working without online lookup, and Settings > Online Lookup shows
  "Not set" on that Apple TV, so the user types the key once there. Nothing is lost on the first Apple TV.
- If the user resets their iCloud Keychain, CloudKit reports that the encrypted data is gone for good. The app deletes and
  recreates the Secrets zone and uploads the key again from a device that still has it (Apple's documented handling).

**(d) What someone with only the iCloud data could read.** Not the key: the field is encrypted, and the key material is
not in the record. What is visible without it:
- the container name;
- the zone name "Secrets";
- the record type;
- the record names, which show that a TMDB key exists and, for passwords, a random source id;
- when each record was changed, and roughly how large it is.

Someone who can sign in to the Apple Account on a trusted device can read the key, the same as the user. Under standard
protection, so can Apple, or anyone Apple must hand data to. With Advanced Data Protection, only trusted devices can.

**Assessment.** The copy is separate from the library data, it is encrypted, and the app never holds its encryption key.
It is not end-to-end encrypted unless the user has Advanced Data Protection on. Whether a second Apple TV can read it is
unverified. Kept as PROVISIONAL (R220). The closest alternatives:
- no iCloud copy for keys (`mirrored: false`, already supported), so the key is typed once on each Apple TV;
- an iCloud copy only when the user turns it on;
- record names that do not reveal which service a record is for.

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
IntroDB gives no release duration, so the strict duration rule B1 had to be relaxed for intro and recap (R208); #27 adds
the safeguards in section 5.

## 4. Licence table: if the app were sold

| Source | Data licence | Today (non-commercial, open source, user's own key) | If the app were sold |
|---|---|---|---|
| TMDB | TMDB API terms (personal, non-commercial key) | Allowed for each user's own key (R214 open) | Needs a commercial agreement with TMDB, or remove TMDB |
| JustWatch (where to watch, through TMDB) | Through TMDB's terms, credit required | Shown with credit | Covered only by a TMDB commercial agreement |
| Wikidata | CC0 | Allowed | Allowed, unchanged |
| IntroDB | Their terms: commercial with reasonable use | Allowed | Allowed with reasonable use; bulk only via the ODbL export (share-alike on the database) |
| OMDb | — | Removed (#27) | — |
| TVmaze | CC BY-SA 4.0, commercial use unclear | Not built | Ask TVmaze first |
| Fanart.tv | Open decision | Not built | Open |

## 5. Source order and coverage (item 6, PROVISIONAL R210)

Synopsis and cast: the source's own details first (Jellyfin, Emby, Plex servers, NFO files, embedded tags), then Wikidata
(Free Data Sources on), then TMDB (key set). A later layer fills only gaps: synopsis, cast list, a cast member's role or
photo by name. Alternative: TMDB first.

Content (age) rating (R371, R372, R374): its own order, first found wins: the source's own rating, then
TMDB's certification for the Region setting (key set), then Wikidata's official rating (Free Data Sources on), the Region
setting's system first. Wikidata properties read on Wikidata's property pages (21 Nov 2026): P1657 MPA film rating, P2629
BBFC rating, P1981 FSK film rating, P3156 Australian Classification, P3216 ClassInd rating, and P7367 content descriptor
(a qualifier on those rating statements); they are asked in the same request as the title's other facts. No Wikidata
property for the US TV Parental Guidelines was found. Content descriptors are shown only with Wikidata's own rating.
The source's own rating (R374) is, in order: the media server's field, Plex `contentRating`, Jellyfin `OfficialRating`
(API page https://api.jellyfin.org, BaseItemDto) and Emby `OfficialRating` (https://dev.emby.media, ItemsService getItems,
BaseItemDto), from the item list the client already holds; when the list lacks it (it is not a `Fields` value on either
API, and Emby's docs say lists are "minimal" while a single item is "the entire object"), from ONE single-item request
(Jellyfin `GET /Items/{itemId}`, Emby `GET /Users/{UserId}/Items/{Id}` with the user id from the sign-in), kept in the
library; then the title's own NFO file (`<mpaa>`, else
`<certification>`, in the `<movie>` or `<episodedetails>` document), the `.nfo` next to the video with the same name,
read once when the page is first opened and kept in the library (`items.content_rating`, schema 7; "" records a file
without a rating). UNVERIFIED (the pages do not say): which properties a list response carries without `Fields`; Emby with
a pasted token has no user id, so no single-item request is made. Limits: a folder-wide `movie.nfo` or `tvshow.nfo` is not read, and a changed NFO file is not read again.
Rejected: Common Sense Media (its API needs a partnership agreement, its reviews are copyrighted, and it would be a new
outside contact).

Honest coverage today: layer 1 is filled **for Plex files only** (the server's synopsis, read from the listing the source
already holds; R307); only its content rating also comes from Jellyfin, Emby and NFO files (R374). For every other
source its synopsis stays empty (the NFO reader, Jellyfin and Emby do not keep a synopsis or
cast), so their order is unchanged; and the IMDb id from an NFO or a server is not stored either
(IntroDB then needs TMDB or Wikidata to find it). How much of a real library each layer covers can only be measured on a
device with real sources: checklist item K8 records it. `LayeredDetails.used` says which layers gave something.

Skip Intro (item 5a): chapters, sidecars and user marks first; IntroDB only when none of them gives a segment, under the
same 6-second deadline. IntroDB intro and recap are accepted without a reference duration (R208); IntroDB credits are not.
A failure gives a note in File Details and no segment, so no Skip button.

Safeguards for IntroDB timings (#27 item 2, docs/PLAYBACK_LOGIC.md SEG-15 and SESS-8 to SESS-12):
- An intro or recap whose end is after the end of this file is dropped, not trimmed (it was made for another cut).
- The Skip button, a press and an automatic skip act only while the playhead is inside the returned window.
- A skip never seeks past the end of the file.

A different cut that is long enough cannot be told apart, so these rules limit the harm to "a wrong button inside that
window".

## 6. Code map

- Key store: `AppLogic/OnlineLookup.swift` (`OnlineKeyStore`, texts), `UserData/Apple/KeychainCredentialStore.swift`,
  `App/Support/AppDependencies.swift` (`keyCredentials`), `App/Support/AppServices.swift` (wiring, backup forbidden list).
- Screen: `App/Features/Settings/OnlineLookupSettingsView.swift`; credits: `App/Features/Settings/AboutView.swift`,
  `App/Support/Attribution.swift`.
- Clients: `MetadataOnline/IntroDBClient.swift`, `MetadataOnline/WikidataClient.swift`.
- Use: `AppLogic/OnlineSegments.swift` (IMDb id chain, IntroDB → segments), `AppLogic/SegmentSourcing.swift` (online slot),
  `AppLogic/DetailsLayers.swift` (layer order), `AppLogic/OnlineComposition.swift` (the closures the app passes, typed, #29 R226), `App/Support/OnlineServices.swift`, `App/Support/SegmentService.swift`.
- Tests: `MetadataOnlineTests/KeyFreeSourceTests.swift`, `AppLogicTests/AppWideKeyTests.swift`,
  `PlaybackLogicTests/SegmentTests.swift` (SEG-3), `PlaybackLogicTests/OnlineSkipSafeguardTests.swift` (SEG-15, SESS-8 to SESS-12), UI test `test03_Settings` and `test02_AddASource` (no key field).
