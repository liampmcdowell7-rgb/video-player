# Storage model (tvOS), R56 to R58

Status: implemented and tested in Swift on Linux (`VideoPlayerCore`: `UserData`, `LibraryIndex`). The two Apple wrappers (`CloudKitUserDataCloud`, `KeychainCredentialStore`) and the `project.yml` entitlements have **never been compiled or run**; see "Not verified" at the end.

Labels used below: **Verified** = read on the Apple page linked next to it, this project. **PROVISIONAL** = the spec was silent, I chose; the alternative is named. **Unverified** = not found on an Apple page.

## 1. What Apple says (verified from the pages)

Source A: App Programming Guide for tvOS, "Apple TV and tvOS" page, section "Local Storage for Your App Is Limited":
https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/ (archived guide; may predate tvOS 27, see "Not verified").

- Local persistent storage is limited to 500 KB, through `UserDefaults`.
- Everything else on the device "must be purgeable by the operating system when space is low".
- User data belongs in iCloud: "Your app can store and retrieve user data in iCloud." Every tvOS app is expected to do this well.
- Caches: downloaded data stays "while the app is running", but "when space is low and your app is not running, this data may be deleted". Do not use the whole cache space.
- Bundle maximum: 4 GB.

Source B: iCloud storage overview, https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/iCloudStorage.html (not re-fetched this session; quoted from the earlier fetch): there is "no guarantee" that information stored on the device is there the next time the app opens. Two options are offered for tvOS: key-value storage (under 1 MB) and CloudKit (more).

Not on either page: how Documents and tmp behave on tvOS, and what an app should do when the user is signed out of iCloud. This model treats **everything outside UserDefaults as purgeable** and says so to the user when signed out.

CloudKit facts used (verified, fetched through Apple's documentation pages):
- A record's data must stay under 1 MB (assets excluded): https://developer.apple.com/documentation/cloudkit/ckrecord
- New record types and fields can only be created automatically in development. In production an unknown type or field is an error: same page. So the schema must be deployed to Production before the first Production build (CODEMAGIC_SETUP step 22).
- `CKRecord.encryptedValues`: tvOS 15 and later, private database, encrypted fields cannot be indexed or queried: https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues
- `CKRecord.encodeSystemFields(with:)` is the documented way to store the record's identity and change tag locally: https://developer.apple.com/documentation/cloudkit/ckrecord/encodesystemfields(with:)
- Error codes `limitExceeded`, `quotaExceeded` (private database: the user's iCloud is full, prompt them to manage storage), `requestRateLimited` (wait `CKErrorRetryAfterKey` seconds), `serverRecordChanged`, `changeTokenExpired`, `notAuthenticated`, `networkUnavailable`, `zoneNotFound`: https://developer.apple.com/documentation/cloudkit/ckerror/code ; quota page https://developer.apple.com/documentation/cloudkit/ckerror/code/quotaexceeded ; rate limit page https://developer.apple.com/documentation/cloudkit/ckerror/code/requestratelimited
- `CKContainer.accountStatus()` returns `available`, `noAccount`, `restricted`, `couldNotDetermine`, `temporarilyUnavailable`: https://developer.apple.com/documentation/cloudkit/ckcontainer/accountstatus(completionhandler:) and https://developer.apple.com/documentation/cloudkit/ckaccountstatus
- The `limitExceeded` limits used (at most 400 items and 2 MB per request, split the batch and retry) come from the earlier fetch of the `limitExceeded` page; this session's re-fetch of that page failed (connection reset), so treat the two numbers as verified earlier, not re-checked today.
- Entitlements available on tvOS: `com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services`, `keychain-access-groups` (Apple's entitlement pages, fetched earlier).

## 2. Every stored item: user data or rebuildable cache

USER DATA means the user would be upset to lose it and the app cannot recompute it. It goes to the cloud copy (section 3) and, where small, the essentials copy in UserDefaults (section 5). REBUILDABLE CACHE means the app can recreate it from the sources or the network; losing it costs time, never information.

| Item | Where it lives now | Class | Survives a purge by |
|---|---|---|---|
| Library index tables: `items` (except the watch columns), `files`, `folders`, `series`, `item_genres`, `scans`, `scan_queue` | `library.sqlite` in Caches | REBUILDABLE CACHE | rescan of the sources |
| Watch state: position, duration, watched, play count, last played (`items` watch columns) | SQLite, written through to the ledger | **USER DATA** | cloud records `watch` |
| Favorite, "hide from Continue Watching" (`items.favorite`, `items.hidden`) | SQLite, written through | **USER DATA** | cloud records `watch` (own fields) |
| Saved views and sorts (`views`) | SQLite, written through, schema v2 adds `views.uid` | **USER DATA** | cloud records `view` |
| Fix Match overrides (user picked the right title) | not built yet | **USER DATA** | cloud records `fixmatch` (schema ready, no writer yet) |
| User-marked segments (intro, credits) | not built yet | **USER DATA** | record `segment` (schema ready, no writer yet) |
| Learned skip data | not built yet | **USER DATA** | record `learnedskip` (schema ready, no writer yet) |
| Source definitions: kind, name, host, port, path, user name, auth kind (no secret) | `sources` table, written through | **USER DATA** | cloud records `source` + essentials copy |
| Source passwords and tokens | Keychain (this device only) | **USER DATA but cannot be synced** | asked for again (section 6) |
| App settings | UserDefaults | **USER DATA** | essentials copy + record `settings` |
| Online metadata (ratings, overviews, cast) | SQLite columns | REBUILDABLE CACHE | refetch from the metadata provider |
| Artwork (posters, backdrops) | files in Caches | REBUILDABLE CACHE | refetch |
| Subtitle files fetched from the network | Caches | REBUILDABLE CACHE (R57: reclassified, was "offline download") | refetch; sidecar subtitles on the source are never copied |
| Prefetched video ranges | Caches | REBUILDABLE CACHE, best effort, never promised | none needed |
| Top Shelf snapshot (`topshelf.json` and images) | App Group container, purgeable | REBUILDABLE CACHE | rewritten whenever the app runs |
| The local copy of user data (`userdata-ledger.json`) | Caches | REBUILDABLE CACHE (it is a copy of the cloud) | pulled from the cloud |

If a new stored thing is added later it must be added to this table in the same change.

## 3. The cloud copy

One custom zone `UserData` in the user's **private** CloudKit database, container `iCloud.com.liamp.videoplayer`. One CloudKit record per user-data record, record type `UDRecord`. The whole record (every field with its stamp) is stored as one JSON `payload` in `encryptedValues` (verified API, tvOS 15 and later), plus a plain `schema` integer. The merge rules live in Swift, not in CloudKit, so adding a field never needs a CloudKit schema change; only the single record type has to be deployed once. Encrypted fields cannot be queried, which does not matter: the app fetches changes by change token and never by predicate.

Record types (strings are stored in the cloud and never renamed): `watch`, `view`, `fixmatch`, `segment`, `learnedskip`, `source`, `settings`. Record ids: the library item `key` for `watch` (derived from the file name, stable across rebuilds, unlike database row ids), a random uid for `view`, the source id for `source`, one record `settings`. The CloudKit record name is `type.id` when short and plain ASCII, otherwise `type.h<128-bit hash>` (the 255-character name limit is recalled, not verified, so names stay under 180 bytes).

### Conflict rules (field level; `UDSchema.merge`)
Every field carries a stamp (time, then device id). Merge is a **join**: it drops nothing, so it is commutative, associative and idempotent, tested on random records (`MergeTests.testMergeIsCommutativeAssociativeAndIdempotentOnRandomRecords`, 400 rounds for each of 3 record types).
- Plain field: the later stamp wins, ties broken by the value text.
- Atomic group: fields that must not mix move together and the group with the later stamp wins as a whole. Watch: position, duration, watched, last played. View: scope kind, scope source, scope path, query. Others in `UDSchema.schemas`.
- Counter group: `[playEpoch, playCount]`, the larger tuple wins. "Mark unwatched" starts a new epoch (the time of the unwatch) with count 0, so it beats older counts from other devices; two devices that played in the same epoch keep the larger count.
- Independent fields: `favorite` and `hidden` each have their own stamp, so one device favoriting and another saving progress both win.
- Deletion (saved views, sources): a record gets a `deleted` stamp. Fields not newer than it stay stored but are not read; a later edit brings the record back. Not pruned at merge time because pruning in the middle of a chain of merges broke associativity (found by the random test on its first run).
- Reading: `playCount = max(playCount, watched ? 1 : 0)`.
- Unknown record types and fields (written by a newer app) merge field by field and are kept.
- Known edge, accepted: for a counter group (`playEpoch`, `playCount`) or a `maxFields` field, the winner is chosen by value, not by stamp. If such a record also carries a deletion stamp, the winning value can be one that is older than the deletion and therefore reads as gone, even though a newer, smaller value exists on another device. Every device computes the same join, so devices never disagree; the edge only matters for records that are deleted, and the app never deletes `watch` records (an unwatch is a new epoch).

### Sync protocol (`UserDataSyncEngine`, an actor)
1. Check account status. `noAccount`, `restricted`: report `signedOut`, keep every edit in the local copy, send nothing.
2. Pull: fetch changes since the stored change token, page by page, merge each record into the local copy. An expired token triggers one full refetch.
3. Push: records changed locally, in batches of at most 400 records and 2,000,000 bytes (`UDLimits.cloudKit`). On `limitExceeded` the batch is halved and both halves retried, down to one record. A record over 1,000,000 bytes is reported in `report.oversize` and never sent.
4. `requestRateLimited`: sleep for the server's retry time (default backoff times attempt if none), then retry; the sleep is injectable so tests do not wait.
5. `serverRecordChanged`: merge the server copy into the local one and push again.
6. `quotaExceeded`: report `iCloudFull`, keep the edits queued.
7. Network failure: report `offline`; the edits stay queued and go out on the next sync.
First sync on a new install: the local copy is empty, so pull brings everything and nothing is pushed. First sync on a device that already has data and an empty cloud: everything is pushed in batches. First sync with data on both sides: both are merged by the rules above.

Tests: `SyncEngineTests` (conflicts, batching, limit halving, rate limit, quota, offline, signed out, expired token, oversize record) against `InMemoryCloud`, a fake that enforces the same limits and produces change tags and conflicts. `InMemoryCloud` is not Apple code; it can only prove the protocol, not CloudKit.

## 4. Startup, signed out, never wrong watch state

`LibraryBootstrap` decides from the database health (`ok`, `missing`, `empty`, `corrupt`) and whether the local copy of user data was found:
1. Database fine and local copy fine: show the library now, sync in the background.
2. Database missing, empty or corrupt: **close the watch gate** (every item reads as unwatched, Continue Watching and Next Up are empty, so no wrong state is ever shown); show "Rebuilding"; restore the essentials from UserDefaults; pull from the cloud; hand watch state, views and deleted views to the store; open the gate; rescan the sources. Items the scan creates later take their watch state from the restored data (`pendingWatch`), then the pending list is cleared.
3. Database fine, local copy lost: rebuild the local copy from the database (`userDataPatches`, stamped with last-played time, or second 1 for items with none, so anything the cloud holds wins over this guess), then sync.
End states (`LibraryBootstrapNote`): none; `historyNotRestored` (signed out and the local copy was gone); `restoredOffline`; `iCloudFull`; `passwordsNeeded(sourceIDs)`.

Signed out of iCloud: Settings shows a status line (`UDStatusText`, English placeholder text until localisation) saying history is only on this Apple TV and the system may delete it, with **Export** and **Import**. Export writes one JSON file (`UDExport`, format `video-player-userdata` version 1, sorted keys) holding watch history, saved views, sources without passwords, settings. Import merges with the same rules and reports how many records changed. PROVISIONAL: plain JSON, since it holds no secret; alternative: passphrase-encrypted.

Tests: `BootstrapTests` (every path above, with the order of calls checked), `LibraryUserDataTests.testWhileTheGateIsClosedNothingShowsWatchStateAndOpeningItBringsItBack`, and the purge simulator below.

## 5. The essentials copy in UserDefaults

UserDefaults is the only local storage the system keeps (500 KB, source A). The `source` and `settings` records are also saved there as JSON so that, even signed out and purged, the app starts with its source list and settings. Budget **200,000 bytes** (`UDEssentialsStore`); over it, saving fails with `overBudget` and the app reports it rather than writing; the Apple ceiling is 500,000. Tests: `EssentialsTests.testTheEssentialsStayUnder200KBForAVeryLargeSetup` fails if the saved copy of a very large setup goes above 200 KB; `testAnOversizedSetupIsRefusedAndTheLastGoodCopyIsKept` covers the refusal. PROVISIONAL: 200 KB leaves room for the system's own keys and the app's other defaults.

## 6. Credentials: the contradiction

The plan said "credentials in the iCloud Keychain". **That does not work on tvOS.** Apple's documentation for `kSecAttrSynchronizable` (https://developer.apple.com/documentation/security/ksecattrsynchronizable) says tvOS does not synchronize keychain items through iCloud, and that items stored on tvOS "never leave the device where you create them".

What the code does instead:
- The source definition (host, user name, auth kind) syncs through CloudKit. The password or token does not: `KeychainCredentialStore` keeps it in the Keychain of this Apple TV only, without `kSecAttrSynchronizable` (it would have no effect there).
- After a purge or on a second Apple TV, `CredentialGap.sourcesNeedingPassword` lists the sources whose definition is known but whose secret is missing, and the end state `passwordsNeeded` asks the user to enter them again. A missing secret is never an error.
- Unverified: whether Keychain items on tvOS survive when the system frees space. The code does not rely on it.

**Decision needed from the owner.** Option A (built): the password is typed again after a purge or on a new device. Option B: store the secret in CloudKit `encryptedValues` so it comes back by itself; it needs the owner to accept that secrets leave the device, and Apple's pages must be read for what protects that field before it is built. Not built. Recommendation: A for the first release.

## 7. Top Shelf extension never crashes on missing files

The app writes `topshelf.json` and image files into the App Group container (`group.com.liamp.videoplayer`) through `TopShelfSnapshotStore`; the extension (not built yet) reads them through `TopShelfSnapshotStore.read`, which **never throws**. It returns an empty result (and the extension shows nothing) for: no file, empty file, a file over 512,000 bytes, damaged JSON, a wrong version, a folder where the file should be, and image names that point outside the folder. An item whose image is missing or empty is dropped; at most 24 items are kept. Tests: `TopShelfSnapshotTests` (`testEveryKindOfMissingOrBadFileShowsNothingAndNeverCrashes` and the six others). The container is purgeable like Caches; the app rewrites the snapshot each time it runs.

## 8. The purge simulator

`PurgeSimulatorTests` (in `LibraryIndexTests`): runs the app twice over one temporary folder, deletes the database and the local copy between the runs (what the system does when space is low and the app is not running), keeps the in-memory cloud and the UserDefaults stand-in, and compares.
- `testAfterAFullPurgeEveryWatchStateAndSavedViewComesBackExactly`: 400 items, 600 scripted user actions (progress, watched, unwatched, favorite, hide, saved views created, changed, deleted). After the purge every item's watch state and every saved view is identical, item by item.
- Signed-out purge: history is lost, the library rebuilds, the note says so.
- Export, then purge, then import: history recovered.
- Local copy lost but database intact: the copy is rebuilt from the database and merged.
- Two devices: edits from both sides merge by the rules in section 3.
It uses a deterministic clock, so the stamps are repeatable.

## 9. Rebuild cost (measured)

Machine: Intel Core i5-8500T 2.1 GHz, 6 cores, 7.8 GB RAM, Ubuntu 26.04.1 in WSL2, SQLite 3.46.1, **debug build**. Worst case: every item has a user-data record. The cloud is the in-memory fake, so these are CPU times; real network time per CloudKit request is **not** included. Test: `RebuildTimingTests` (1,000 items always; 10,000 with `VP_RUN_REBUILD_10K=1`). Lines are also written to `/tmp/library-index-perf.txt`.

| Step | 1,000 items | 10,000 items |
|---|---|---|
| Scan from empty (nothing to restore) | 2.39 s | 24.74 s |
| Pull all user-data records from the cloud (200 per fetch request) | 0.01 s (5 requests) | 1.06 s (50 requests) |
| Hand the watch states to the database | 0.02 s | 0.19 s |
| Rescan that also applies the restored watch state | 2.48 s | 24.71 s |
| **Total rebuild** | **2.51 s** | **25.96 s** |
| User-data part alone (pull + hand over + extra scan time) | 0.12 s | 1.25 s |
| Writing one user action through to the local copy | 0.05 ms | 0.05 ms |
| Upload of the full set (400 records per request) | 0.17 s (3 requests, 512 KB) | 1.72 s (25 requests, 5.1 MB) |

100,000 items, **extrapolated, not measured**: `docs/LIBRARY_INDEX.md` records a first scan of 219.7 s in a **release** build (the project brief quotes 221 s); the user-data part scales linearly in the measurements above, so about 12 s (from the debug figure for 10,000, times 10), for roughly 232 s in total. The user-data part grows with the number of records (about 500 pull requests of 200 records and 250 upload requests of 400 at that size), so on a real network the request count, not the CPU time, will dominate; that is unmeasured.

## 10. Interpretations where the spec was silent (PROVISIONAL)

1. Watch state is matched to items by `items.key` (file-name derived), not by database id, because ids change on a rebuild. Alternative: a content hash (more robust to renames, costs reading the file).
2. One CloudKit record per user-data record, whole record in one encrypted payload. Alternative: one CloudKit field per value (queryable, but needs a schema change per new field).
3. Essentials budget of 200,000 bytes.
4. Export file is plain JSON. Alternative: passphrase-encrypted.
5. An unwatch starts a new play-count epoch; a plain edit never does.
6. Items with no last-played time get stamp second 1 when the local copy is rebuilt from the database, so cloud data always wins over the guess.
7. The App Group entitlement is added to the app target now, for the Top Shelf extension later; it is not in the original brief.
8. "Backup" (backlog 21) includes watch history; offline downloads (backlog 29) became "prefetch to cache, best effort, never promised"; subtitle downloads (backlog 25) are cache.
9. Credentials: option A in section 6.

## 11. Not verified / never compiled

- `Sources/UserData/Apple/CloudKitUserDataCloud.swift` and `Apple/KeychainCredentialStore.swift`: never compiled (no Mac, Linux has no CloudKit or Security). Every call was checked against an Apple page, but a compile error or a behaviour difference on a real account is possible. Their first compile is the first Codemagic compile check. The `resultsLimit: 200` and the `modifyRecords` argument labels are the likeliest places for a mismatch.
- `project.yml` entitlements block: not run through XcodeGen (no XcodeGen here).
- The button names in CODEMAGIC_SETUP steps 19 to 24 are from memory.
- Whether the archived tvOS guide (source A) still describes tvOS 27 (500 KB limit, purge rules); a tvOS 27 page was not found.
- Whether Keychain items survive a system cleanup on tvOS; how Documents and tmp behave.
- Whether a TestFlight build uses the Production CloudKit schema and whether a development build creates the `UDRecord` type automatically.
- CloudKit behaviour under real rate limiting, real conflicts and a real full iCloud.
- Timings are debug-build, in-memory cloud; 100,000 is extrapolated.
