# iCloud backup of generated data

Decision: OPEN_QUESTIONS.md R163 (PROVISIONAL; the alternatives are listed there).

## Goal

The library index, the details and ratings found online, the Fix Match choices and the pictures read from sources all live in
Caches, which tvOS may clear at any time (docs/STORAGE_MODEL.md). Rebuilding them means scanning every source again and
asking the online services again. This feature keeps a copy of that generated data in the user's own iCloud storage, so after
a cleanup, a reinstall or on a new Apple TV the library is back in seconds without a rescan.

The videos themselves are NEVER uploaded. Passwords, sign-in tokens and API keys are NEVER uploaded (they stay in the
Keychain, as decided before); the engine refuses any file that contains one (see "Secrets" below).

## What is backed up (three switches on Settings > Backup)

| Switch | Default | Contents | Where it lives on the Apple TV |
|---|---|---|---|
| Library data | on | `library.sqlite` (the whole index: items, matches, collections, saved views, segment marks, sidecar rows), the online-metadata answers, `matches.json` (Fix Match) | Caches/library.sqlite, Caches/online-metadata/, Application Support/matches.json |
| Artwork | on | pictures read from sources (`Caches/artwork`); option "Only artwork for items in your library" | Caches/artwork/ |
| Settings and watch state | on (shown, not a new upload) | watch state, saved views, sources (without passwords), settings, segment marks, learned skips: already synced record by record by the user-data sync (zone `UserData`) | ledger + UserDefaults |

Not backed up: the online posters' URL cache (`Caches/remote-artwork`, refetched from the web address), the Top Shelf folder
(written again after every scan), temporary files.

## Apple limits (read from Apple's pages, 2026-11-17)

- Record size 1 MB excluding assets; asset 50 MB; 200 operations per request: CloudKit Web Services Reference, "Data Size
  Limits" (archived, last updated 2016):
  https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html
- `CKError.Code.limitExceeded`: a request over 400 items or 2 MB (assets excluded) fails; split it and try again:
  https://developer.apple.com/documentation/cloudkit/ckerror/code/limitexceeded
- `CKSyncEngine` sends at most 250 records per request (tvOS 17+):
  https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5
- `CKAsset`: use assets for values over a few kilobytes; no size limit is stated on the page; available on tvOS:
  https://developer.apple.com/documentation/cloudkit/ckasset
- Quota: "Data in the private database counts toward the user's iCloud storage quota." No other per-app quota was found:
  https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase
- `quotaExceeded`: tell the user to free up iCloud storage:
  https://developer.apple.com/documentation/cloudkit/ckerror/code/quotaexceeded
- `notAuthenticated`, `networkUnavailable` (try again later), `requestRateLimited` and `zoneBusy` (wait `CKErrorRetryAfterKey`):
  https://developer.apple.com/documentation/cloudkit/ckerror/code/notauthenticated,
  https://developer.apple.com/documentation/cloudkit/ckerror/code/networkunavailable,
  https://developer.apple.com/documentation/cloudkit/ckerror/code/requestratelimited,
  https://developer.apple.com/documentation/cloudkit/ckerror/code/zonebusy
- Encryption: `CKAsset` contents are encrypted by default; `encryptedValues` (tvOS 15+) cannot be queried:
  https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues
- Apple TV storage: about 500 KB of persistent local storage (NSUserDefaults); everything else may be purged; apps are
  expected to keep data in iCloud (App Programming Guide for tvOS, archived):
  https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/index.html

The engine keeps far inside these: chunks of at most 1 MiB, one chunk per request for uploads, at most 200 IDs per fetch or
delete request.

## Design

### Records (custom zone `LibraryBackup`, private database)

| Record type | Record name | Fields |
|---|---|---|
| `BKManifest` | `manifest.library`, `manifest.artwork` | `generation` (Int), `payload` (CKAsset: the manifest JSON) |
| `BKChunk` | `chunk.<sha256>` | `codec` (String: `lzfse` on Apple, `none` otherwise), `data` (CKAsset: the compressed chunk) |

No field is queried, so nothing is indexed. The manifest is an asset so a library of any size never meets the 1 MB record limit.

### Chunking and incremental upload

Every file is cut into 1 MiB pieces. Each piece is named by the SHA-256 of its uncompressed bytes (pure Swift,
`BackupSHA256`, checked against the FIPS vectors). Before uploading, the engine asks which of the new names the cloud
already has; only unknown pieces are uploaded. The library database is copied with SQLite's online backup API
(`sqlite3_backup_*`), which keeps pages in place, so a small change in the library changes a few pieces, not the whole file.
The same picture used twice is stored once (content addressing).

### Versioning

- `format` (1 today): the layout of the manifest. A backup with a newer format is never restored and never overwritten; the
  screen says "made by a newer version of Video Player".
- `librarySchema`: the database's `user_version`. A backup with a newer schema is refused the same way; an older one is
  migrated by the normal schema code after import.
- `generation`: +1 on every successful backup. A manifest is saved only after every piece it lists is uploaded, and pieces
  are immutable (the name is the content), so a restore always reads ONE generation: versions never mix.
- Clean-up keeps the current and the previous generation (and everything the other set uses); older pieces are deleted.
  Clean-up failures are ignored (a leftover piece costs space, not correctness).

### Merge rule (restore)

- The library database is restored only when the library is empty or missing (automatic restore), or when the user
  confirms "Restore from iCloud" (it then replaces the index on this Apple TV).
- Every other file: the newer one wins. A local file changed after the backed-up copy is kept.
- Watch state, saved views, sources and settings come back through the user-data sync, which already joins record by record
  with "newest edit wins" (docs/STORAGE_MODEL.md). The restore of the index happens BEFORE that join, so a newer local or
  cloud watch state is applied on top of the restored index.
- Order: the database first, then the other library files, then the pictures, with the Home-row posters first (priority).
- Every piece is checked against its SHA-256; a damaged piece is downloaded once more, then the restore stops with "a part of
  the backup was damaged". The whole file is checked again before it is written.
- Resumable and idempotent: verified pieces stay in a staging folder until the restore finishes, so an interrupted restore
  downloads only what is missing; running a finished restore again changes nothing.

### Degrading honestly

- iCloud full while backing up pictures: that picture and every larger one is left out and listed; the backup finishes with
  what fits and the screen says how many files and how much was left out. The library data is all-or-nothing.
- A picture over 20 MB is left out and listed.
- Signed out: nothing is sent; the screen says to sign in to iCloud in the Settings app.
- No network: the screen says so; the next trigger tries again.
- "Too many requests" (`requestRateLimited`, `zoneBusy`): wait the time iCloud gives (or 2, 4, 6 s), up to 3 times.

### Secrets

Before any upload the engine searches every file and the manifest for each source password or token and each API key
(strings of 4 characters or more). A match stops the backup with "a file held a password or key, so nothing was uploaded".
The list comes from the Keychain at the time of the backup and is never written anywhere.

### When it runs

- 2 minutes after the library last changed (debounced: a scan of 1,000 files causes one backup);
- at launch when the last successful backup is more than a day old;
- "Back Up Now".

Never through background sync (decision D8). It runs in a low-priority task; it never blocks the UI or playback.

### Not Core Data

`NSPersistentCloudKitContainer` is not used: the index is SQLite and is rebuilt from sources; mirroring it record by record
would cost thousands of records and requests for data that can be regenerated, and would not fit the "newest edit wins"
ledger already in place.

## Code

| Piece | File | Tested where |
|---|---|---|
| Models, manifest, settings, errors, status | Packages/VideoPlayerCore/Sources/LibraryBackup/BackupModels.swift | WSL |
| SHA-256 | .../LibraryBackup/SHA256.swift | WSL (FIPS vectors) |
| Cloud protocol, codecs, in-memory fake | .../LibraryBackup/BackupCloud.swift | WSL |
| Engine (backup, restore, usage) | .../LibraryBackup/BackupEngine.swift | WSL |
| Scheduler, screen texts | .../LibraryBackup/BackupScheduling.swift | WSL |
| Files on this Apple TV | .../LibraryBackup/LibraryBackupFiles.swift, BackupContent.swift | WSL (purge simulator) |
| Database snapshot export/import | .../LibraryIndex/SQLiteLibraryStore+Snapshot.swift | WSL |
| CloudKit adapter | .../LibraryBackup/Apple/CloudKitBackupCloud.swift (commit B) | CI compile, then a device |

## Progress notes

- 2026-11-17, commit A (package core): models, chunking, versioning, merge rule, the in-memory fake store and the Linux
  tests. 16 tests in LibraryBackupTests and 2 new purge-simulator tests (purge, then restore with no rescan; a library with
  items is never replaced unless the user asks). Not yet wired into the app.
