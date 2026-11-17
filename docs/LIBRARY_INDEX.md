# Library index and incremental sync

The `LibraryIndex` target of `Packages/VideoPlayerCore`. It is the local database behind the library grid, Continue Watching, Next Up, search and folder browsing, and the sync engine that keeps it in step with any `MediaSource` (docs/FEATURE_BACKLOG.md, Tier A).

Foundation-only Swift, async/await, no Apple-only frameworks. On Apple platforms it talks to the system SQLite (`import SQLite3`); on Linux it links `libsqlite3` through the `CSQLite` system-library target (see "Building on Linux").

Everything here is tested in WSL (Linux). Nothing in this target has been compiled on a Mac or tvOS yet; the first Codemagic build has to prove the Apple side (see "Unverified").

## Storage: SQLite behind a protocol (R34, PROVISIONAL)

The app talks to `LibraryStore` (queries, watch state, saved views) and `LibraryScanStore` (what the sync engine needs). `SQLiteLibraryStore` implements both. A SwiftData store could implement the same protocols later without touching the callers. R34 stays PROVISIONAL: SQLite was chosen because keyset paging, partial indexes, row-value comparisons and a 100,000-item library with sub-millisecond grid pages are straightforward and testable on Linux, where SwiftData does not exist. Alternative kept open: a SwiftData-backed `LibraryStore` for the app target; it would need the same protocol tests run against it and could not be tested in WSL.

## Thread-safety model

`SQLiteLibraryStore` is an `actor` that owns exactly one SQLite connection (opened `NOMUTEX`, WAL journal, `synchronous = NORMAL`, `busy_timeout` 5000 ms, a small prepared-statement cache). Every call is serialized on the actor, so there is no locking in the SQLite wrapper and no shared mutable state outside it. Transactions use `BEGIN IMMEDIATE` and nest through a depth counter. The sync engine (`LibrarySyncer`) is a plain `Sendable` struct that awaits the store; one folder is held in memory at a time. Tested by `testManyTasksCanUseOneStoreAtTheSameTime`. A second process opening the same file is allowed by WAL, but only one writer at a time (the busy timeout covers short waits).

## Schema (`PRAGMA user_version` = 1)

| Table | Holds |
|---|---|
| `sources` | one row per source (id, kind, name, added) |
| `series` | one row per series key (normalized title), title, TMDB id |
| `items` | one row per movie or episode: title, sort key, letter, search text, year, series, season, episode, TMDB id, added date, plus the aggregates over live versions (version count, effective and preferred file, best resolution, HDR and Dolby Vision masks, max channels, Atmos, container mask, runtime) and the watch state (position, duration, watched, play count, last played, favorite, hidden) |
| `item_genres` | genres per item |
| `files` | every file seen (path, parent, name, kind, size, modified, ETag, server token, technical info: duration, container, width/height, resolution class, HDR, DV profile, codecs, channels, Atmos, bitrate, version label, first seen, removed-at tombstone). Video files are the versions of an item; subtitle, image and NFO files are stored as sidecars |
| `folders` | every folder seen: the version observed in the parent's listing, the version it had when it was last scanned, empty-listing strikes, last error, tombstone |
| `scans`, `scan_queue` | scan records and the persisted folder queue (the scan cursor) |
| `views` | saved views (name, scope, JSON-encoded query, pinned) |

A newer database than this code understands is refused with `LibraryIndexError.newerSchema` before any pragma runs and is left untouched. Older databases are upgraded one version at a time.

Indexes: a partial index per sort (`title`, `year`, `rating`, `added`, `played`, `runtime`, `letter`) restricted to `version_count > 0`, `idx_items_series`, `idx_items_continue` (`watched = 0 AND position > 0`), `idx_items_watched`, `idx_files_parent`, `idx_files_item`, `idx_files_removed`, `idx_folders_parent`, `idx_queue_next`. `queryPlan`/`gridPlan` expose `EXPLAIN QUERY PLAN` and the tests assert that the grid, count and alphabet queries use the intended indexes.

Folder queries by parent use `INDEXED BY idx_folders_parent`. Without the hint SQLite chose the table's primary key and scanned every folder of the source, which made a no-change rescan 40 times slower at 100,000 items (found by the scale test; see "Timings").

## Items, versions and episodes

* A **version** is one video file. Files group into one item by a key: `m|title|year[|pN]` for movies (`pN` is a multi-part marker), `e|series|season|episode` for episodes, `e|series|d|date` for dated episodes, `f|name` when nothing could be parsed. The grouping uses the existing `FilenameParser`.
* The **effective file** is the user's remembered choice (`setPreferredVersion`) while that file is still live, otherwise the best by resolution, then size. Item aggregates are recomputed for every touched item inside the same transaction as the file changes.
* **Episodes** carry series, season, episode (and `episodeEnd` for double episodes) and a TMDB id when known. Season 0 is Specials and is kept, but is never offered as "next".
* Titles are stored with a sort key: article dropped, digit runs zero-padded to 8, prefixed `0` for the `#` bucket and `1` for letters. The alphabet index and the sort order use the same key, so a letter jump always lands on the right row. Episodes sort under their series title.

## Sync engine

`LibrarySyncer(store:source:sourceID:annotator:clock:)`, with `sync(roots:options:resume:progress:)` and `refresh(folder:recursive:progress:)`.

* **Unchanged detection** is `FileVersion.isSame(as:)`: server token first, then ETag, then date and size. An unchanged file costs no write. A file whose version cannot be compared at all is treated as changed.
* **Queue.** The list of folders still to do lives in `scan_queue`, FIFO, so memory stays flat: one folder's listing at a time. (Measured: about 25 MB growth for 100,000 items, mostly the in-memory test source.)
* **Resumable.** Each folder is applied in ONE transaction together with its "done" mark in the queue. A scan that dies at any point resumes with the next folder (`sync(resume: true)` matches an unfinished scan with the same roots and options). `testKilledScanResumesAndEndsWithTheSameIndexAsAnUninterruptedScan` kills a scan after every possible folder and checks that the resumed index equals an uninterrupted scan's index row for row, with exactly the expected listing calls.
* **Cancellation.** Cancelling the task finishes the scan as `.cancelled` after the current folder and keeps the queue so the next scan resumes. Progress is reported after every folder (`ScanProgress`: folders done/pending/failed, files seen, added/changed/removed/unchanged, current folder).
* **Failures.** A folder that cannot be listed keeps every row it had; the error is stored on the folder and the scan goes on. `SourceError.unauthorized` and the unsupported/insecure authentication errors stop the scan as `.interrupted` (every remaining folder would fail the same way).
* **Removals are tombstones** (`removed_at`), kept until `purgeRemoved(olderThan:)`; a file that reappears is revived and keeps its item and watch state.
* **Per-folder refresh** re-reads one folder, optionally recursively, without disturbing an unfinished full scan.
* **`trustFolderVersions`** (option, default off): enqueue only children whose folder version differs from the version recorded at their last scan. After a stamping scan, a rescan after two edits listed 5 folders instead of 59,060 (0.1 s at 100,000 items). It is only sound for sources whose folder version changes when anything below it changes (some WebDAV and cloud sources do; plain SMB/NFS/FTP folder dates do not reliably). That is why it is off by default.

## Queries

`ItemQuery(filter:sort:)` with `ItemFilter`: kinds, genres, year range, minimum rating, watch state, resolutions, HDR formats, Dolby Vision (and profiles), Atmos, minimum channels, containers, added-after, favorites, series/season, folder scope, source, title text. Facets combine with AND; values inside one facet combine with OR. `ItemSort`: title, year, rating, added, last played, runtime, ascending or descending.

* Keyset paging `page(_:limit:after:)` returns `ItemPage(items, next)`; offset paging `page(_:limit:offset:)` is there for jump-to-position. `count`, `alphabetIndex` (letter, count, row offset) and title search (`ItemFilter.text`, every word must match).
* Rows: `continueWatching`, `nextUp`, `recentlyAdded`, `episodes(ofSeries:)`, `children(sourceID:folder:sort:limit:offset:)` for direct folder browsing (folders first, natural name order), `sidecars(for:)`.
* **Saved views**: `saveView(name:scope:query:pinned:)`, scope is global or a folder, persisted as JSON, pinnable, listed per scope and as a pinned set.
* **Watch state**: `updateProgress`, `markWatched`, `markSeries`, `setFavorite`, `hideFromContinue`.
* Metadata written by the metadata layer: `setMetadata` (single and batch), `setTechnicalInfo`.

## Interpretations where the spec was silent (all PROVISIONAL)

1. **Watched threshold**: a stop at 95% or more of the duration counts as watched (watched = 1, position reset, play count + 1). Unwatching resets the watch state completely. Updating progress un-hides an item.
2. **Series identity** is the normalized series title only (no year), so "The Office (2001)" and "The Office (2005)" collapse into one series until the metadata layer says otherwise.
3. **Year 0 = unknown, rating 0 = unrated.** An unknown-year item never matches a year range; an unrated item never matches a minimum-rating filter.
4. **Version attributes are matched as the union over versions**: an item with a 1080p and a 4K file matches both "1080p" and "4K" filters. The AND/OR rule applies between and within facets as stated above.
5. **Next Up**: from the most recently played watched episode (season above 0, within the retention window) take the next unwatched episode of that series by (season, episode). Season 0 is never "next". A series with an episode in progress is excluded (it is in Continue Watching). A hidden next episode is skipped.
6. **Empty listing rule**: a folder that had content and now lists as empty is held back once and believed the second time in a row, so a server glitch or unmounted share does not wipe a library. A single deleted last file therefore disappears one scan later (visible in the scale numbers below: "16 removals at once, 5 after the empty-folder hold").
7. **Unknown change signals are treated as changed** (see above).
8. **Added date** is `min(scan time, file modified date)`, so Recently Added reflects when the file was made, and a first scan of an old library does not make everything "new".
9. **One transaction per folder.** A single huge flat folder is held in memory as one listing and applied in one transaction. Bounded by the largest folder, not the library.
10. **Sidecars** (subtitle, image, NFO) are stored as files without items, for later artwork/subtitle features.
11. **Watch state survives tombstones**: an item whose files vanished keeps its watch state until `purgeRemoved`; if the file comes back the history is intact. Items with no live version are hidden from every query.
12. **`.kind` browse sort** is by kind, then name.
13. **Technical info** (resolution, HDR, channels, Atmos, container) comes from a `FileAnnotator`. The default `FilenameAnnotator` derives it from the file name and extension only; real probing (reading the container) is a later step that calls `setTechnicalInfo`.

## Timings

Measured by `ScaleTests` on generated libraries (about 1.2 files per item, about 0.6 folders per item, 500-file flat folder, single/multi-version movies, episodes, sidecars; 5% watched, 1% in progress). The source is an in-memory fake, so these numbers are the index and engine cost with zero network. A real network adds one request per folder (about 60,000 for a 100,000-item library).

Machine: Intel Core i5-8500T 2.1 GHz, 6 cores, 7.8 GB RAM, Ubuntu 26.04.1 in WSL2, SQLite 3.46.1, **release build** (`swift test -c release`). Debug-build figures are slower (first scan of 10,000 items about 30 s in debug) because the filename parser is regex-based; the test ceilings are set about 10 times above the release numbers, which a debug build also meets.

| | 1,000 items | 10,000 items | 100,000 items |
|---|---|---|---|
| Folders / files | 621 / 1,212 | 5,933 / 12,109 | 59,060 / 121,084 |
| First scan | 2.4 s | 22.5 s | 219.7 s |
| No-change rescan | 0.15 s | 1.4 s | 15.6 s |
| Rescan, about 1% changed | 0.18 s | 1.6 s | 17.5 s |
| Rescan, trusted folder versions, 2 edits | 0.007 s (5 listings) | 0.015 s (5 listings) | 0.10 s (5 listings) |
| Database size | 1.2 MB | 11.2 MB | 114 MB (about 1.2 KB per item) |
| Peak process memory | 41 MB | 63 MB | 142 MB (growth during first scan 25 MB) |

Throughput is flat across sizes (about 450 items/s first scan, 6,500 items/s no-change rescan), i.e. linear scaling.

Queries at 100,000 items (median of 15 after a warm-up call; first call in brackets where it differs a lot):

| Query | Median |
|---|---|
| Grid first page (60), sorted by title | 0.25 ms |
| Same, 4K + unwatched + rating | 0.9 ms |
| Same, 7-facet combination (genres, years, Dolby Vision, 5.1 ...) | 29 ms |
| Sorted by year / by rating, unwatched | 0.2 ms |
| Page from the middle by offset (row 50,053) | 2.1 ms |
| Alphabet index (all letters) | 9.7 ms |
| Alphabet jump (page at first "M") | 2.4 ms |
| Count for the 3-facet filter | 34 ms |
| Title search, 2 words / common word | 0.9 ms / 0.4 ms |
| Title search, no match | 52 ms |
| Continue Watching / Next Up / Recently Added | 0.05 / 3.7 / 0.04 ms |
| Browse first 100 of a 500-file folder / of the root | 0.6 / 0.06 ms |
| Open one item (item + versions) | 0.1 ms |
| Write: update one playback position | 0.02 ms |

At 10,000 and 1,000 items every query median is below 5 ms (full tables in `/tmp/library-index-perf.txt` written by the test, one `PERF` line per measurement).

Finding recorded while measuring: the first version of the folder queries let SQLite scan every folder row for each folder, so rescan time grew with library size (no-change rescan 1,213 s at 100,000 items). Forcing `idx_folders_parent` made it linear (15.6 s). The tests keep this from coming back: the scale test fails on a 10x regression, and the 1,000-to-100,000 throughput is printed side by side.

Known soft spots (measured, not hidden): the 7-facet filter, the filtered count and a title search with no match scan a large part of the items table at 100,000 items (30 to 50 ms). They are well inside any interactive budget but are the first things to optimize (a covering index for common facets, or a trigram/FTS table for search) if a larger library needs it. The first scan is dominated by `FilenameParser.parse`, which costs about 1.2 ms per file in a release build; it lives in `VideoPlayerCore` and was not changed.

### Tier A item 20 budgets that can only be measured on a device

These cannot be checked in WSL and stay unverified until an Apple TV run: cold launch to a usable grid in about 2 s from the cache (needs real SQLite on tvOS storage and real app start-up); smooth grid scrolling (needs the renderer); image downsampling and image memory; scan speed over a real network (latency per folder, server listing speed); SQLite performance and file size on tvOS hardware (the A-series CPU and flash differ from this PC); peak memory on a 4 GB Apple TV with the real UI. The numbers above bound only the index and engine part.

## Building on Linux

`scripts/setup-sqlite.sh` (idempotent, no root) symlinks the system `libsqlite3.so.0` to `<VP_TEST_HOME or ~/video-player-test-servers>/sqlite/lib/libsqlite3.so`. `scripts/test-core.sh` calls it on Linux. `Package.swift` links it through a Linux-only `-L` flag inside the `SQLITE-BLOCK`. `Sources/CSQLiteSystem` holds the `sqlite3.h` public-domain header and a module map for the `CSQLite` system-library target. On Apple platforms none of this is used (`#if canImport(SQLite3)`).

## Tests

`Tests/LibraryIndexTests`: `FoundationTests` (SQLite wrapper, schema, newer-schema refusal, text and path helpers, grouping, annotator, Unicode normalization, concurrent use), `SyncTests` (first scan, unchanged detection by token/ETag/date+size, edits, removals and tombstones, failed listings keep rows, empty-listing rule, kill-and-resume at every folder boundary, cancellation and resume, per-folder refresh, trusted folder versions, progress), `QueryTests` (300 random filter combinations checked against a plain Swift model, every sort in both directions with keyset and offset paging, alphabet index, search, saved views, Continue Watching, Next Up, watch rules, metadata, query plans), `ScaleTests` (1,000, 10,000 and 100,000 items; set `VP_RUN_100K=1 (opt-in; default is skipped)` to skip the 100,000 run, which then shows as a skipped test).
