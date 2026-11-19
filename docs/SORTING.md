# Sorting files into Movies and Shows

## Part 1. How it works before this change (read-only report, 2026-11-18)

This part describes the code at commit 8bb0f0c, before any sorting change. Nothing was changed to write it.

### Where the decision is made

One place: `LibrarySyncer.scanFolder` (`Packages/VideoPlayerCore/Sources/LibraryIndex/LibrarySyncer.swift`, lines 142-166).
For every video file in a folder listing it calls

1. `FilenameParser.parse(fileName:folders:)` (`Sources/VideoPlayerCore/Parsing/FilenameParser.swift:43`), then
2. `ItemGrouping.seed(parsed:fileName:)` (`Sources/LibraryIndex/ItemGrouping.swift:101`), which returns an `ItemSeed`
   whose `kind` is `.movie` or `.episode` (`ItemKind`, `LibraryModels.swift:82`). There is no third state.

The store (`SQLiteLibraryStore+Scan.swift`, `apply`) files the seed under its key: `m|title|year` (movie),
`e|show|season|episode` or `e|show|d|date` (episode, with series key `s|show`), or `f|stem` (a movie named after the
file when nothing usable was parsed).

### Inputs that are used

- The file name.
- The names of the folders above the file (`LibraryPath.ancestorNames`), nearest first. Only two things are taken from
  them: a season number from one of the two nearest folders ("Season 2", "S02", "Specials"), and a title (and year)
  from the nearest folder that is not a season folder and not a generic name such as "Movies" or "Downloads"
  (`FilenameParser.parse`, lines 47-50 and 79-86). The folder title is used only when the file name has no title or a
  generic one.

### Inputs that are NOT used

- Other files in the same folder (siblings). Each file is decided alone.
- The kind of source (WebDAV, SMB, Jellyfin, Emby, ...).
- TMDB. The matcher only sets a TMDB id on an item that already has a kind; it never changes movie into episode or back
  (`AppLogic/TMDBArtworkProvider.swift`, lines 31-43, `MatchEngine.candidates`).
- The item type a Jellyfin or Emby server knows. The client does not ask for it: the request uses
  `Fields=Path,MediaSources,Etag` (`SourceJellyfin/JellyfinClient.swift:210`; Emby mirrors this), `JFItem` decodes
  only Id, Path, Etag and MediaSources (`JellyfinModels.swift`), and `JellyfinTree.swift:6` says "Titles from the
  server are never used". The server library is turned into a plain file tree and sorted by file name like any share.
- Plex: there is no Plex source in the app, so there is nothing to read from it.

### The rule today

`FilenameParser.parseName` (lines 191-231) looks for episode markers in this order and stops at the first one found:

1. `S01E02` (also `S1E2`, `S01E01-E03`, `S01E01E02`), `findSxxEyy`
2. `1x02`, `findNxNN`
3. "Season 1 Episode 2", `Rx.seasonEpisodeWords`
4. a date `2024-03-05` / `2024.03.05` / `2024 03 05`, `Rx.date`
5. an episode number alone: `E05`, `Ep 5`, `Episode 5`, `Rx.episodeOnly`
6. a special: `SP01`, `OVA 2`, `Rx.special`
7. a season alone: `S01`, `Season 1`, `Rx.seasonOnlyWord` / `Rx.seasonOnlyShort`
8. absolute numbering ` - 012`, `Rx.absolute`

Any one of them makes the file an episode (line 232, and again in `parse`, lines 66-67). A file with none of them is a
movie. In `ItemGrouping.seed`, an "episode" that has neither an episode number nor a date (case 7, season only) falls
through to a movie, and an episode or movie whose title is empty becomes an `f|stem` movie.

### Where this fails on a flat, mixed folder

1. **No "not sure" state.** A file with no pattern at all ("Sample Show Pilot.mkv", "holiday clip.mp4") is always a
   movie. It goes straight into Movies, Home rows and Top Shelf.
2. **Weak markers make episodes.** "Sample Movie - 12 (2010)" is read as absolute episode 12 of a show called
   "Sample Movie"; "Sample Movie E3 Trailer" becomes episode 3; "Sample Movie Part 2 SP1" becomes a special. Nothing
   asks whether a year and no strong marker would make it a movie.
3. **Absolute numbering ignores siblings.** " - 012" is accepted for a single file even when no other file in the
   folder has the same show name.
4. **An episode number alone assumes season 1** (`ItemGrouping.seed`, line 109) when there is no season folder.
5. **Folder tie-breaks only use folder names**, never "this folder holds several files of the same show". In a flat
   root there is no folder name to use, so this signal is lost entirely.
6. **The year is dropped from the show key.** `s|show` ignores the year, so "Sample Show (2019)" and
   "Sample Show (2005)" are merged into one show.
7. **A date without a show name** ("2024-03-05.mkv") falls back to an `f|` movie.
8. **Nothing records why.** There is no field saying which rule decided, so the item info and the logs cannot explain a
   wrong sort.
9. **No way to correct the kind.** Fix Match (`AppLogic/FixMatch.swift`) changes which TMDB entry an item points to; it
   does not move a file from Movies to Shows or back.
10. **Old files are never re-sorted.** An unchanged file is skipped before parsing (`LibrarySyncer.swift:151`) and an
    unchanged folder is not queued again (`SQLiteLibraryStore+Scan.swift`, lines 196-199). Any improvement to the rules
    reaches only new or changed files unless the library is rebuilt.

What already works on a flat folder: strong markers (`S01E02`, `1x02`, "Season 1 Episode 2", dates after a show name)
are found anywhere in the name, case, dots and underscores are ignored, and release tags (resolution, codec, source,
group) are cut from the title before the show key is built, so "Sample.Show.S01E02.2160p.WEB-DL.x265-GRP" and
"Sample Show - S01E03" already share the key `s|sample show`.

## Part 2. How it works now (commits e1f641a, 595d1f2, 94a3487, fbc57ab; OPEN_QUESTIONS R171)

Every video file is decided on its own, wherever it sits. The folder layout is only ever a tie-breaker. Discover items are
never part of this: they are online titles, not files, and never enter the library index.

### The decision (`LibraryIndex/MediaSorter.swift`)

`MediaSorter.decide(fileName:context:)` returns an outcome (movie, episode, needs review), the **signal** that decided and
one plain sentence (the note). The signals are tried in this order:

| Signal (stored raw value) | Shown as | When |
|---|---|---|
| a. `episodePattern` | Episode Pattern in the File Name | `S01E02`, `S1E2`, `S01E02-E03`, `S01E02E03`, `1x02`, "Season 1 Episode 2", `SP01`, a date after the show name, and `Show - 012` **only** when at least one other file of the same show (same normalised name, with a marker) is in the folder |
| b. `moviePattern` | Year in the File Name | a year in the file name ("Name (2019)" or "Name 2019") and no strong episode pattern. Weak markers (`E3`, `Ep 2`, ` - 12`, `Part 2`) are then read as part of the title |
| c. `folderHint` | Folder Hint | tie-breaker only: a weak marker (`E05`, `Ep 5`, ` - 12`) inside a season folder or with other files of the same show beside it; a number at the start of the name inside a season folder; a date whose show name comes from the folder; a year-less name inside a folder named like a movie with a year |
| d. `onlineLookup` | Online Lookup | only for Needs Review files, only with the user's own TMDB key (the app has no separate online switch: no key means nothing is sent). A title search as a movie and, only when the name has episode numbers, as a show. Exactly one side confirmed at confidence 0.8 or more (the matcher's own `acceptThreshold`) moves the file; both or neither leaves it. At most 40 files per launch, each file once per launch |
| `serverType` | Server Library Type | Jellyfin or Emby said "Movie" or "Episode" and the file name agrees, or the file name is not clear and can be filed that way |
| `filenameOverServer` | File Name, Not the Server | the server's type contradicts a clear file name (a or b); the note starts "Sorted by filename, not by the server." |
| `manual` | Moved by Hand | a Move to Movies / Move to Shows choice |
| e. `undecided` | Needs Review | nothing above decided. The file is kept in the index (so it can be moved) but never shown in Movies, Shows, Home, Search, Top Shelf or the counts |

The show key is the normalised title (`LibraryText.normalize`): case, accents, dots, underscores and punctuation are
ignored, and release tags are already cut by the parser, so "Sample.Show.S01E02.2160p" and "sample_show_s01e03_720p"
group into one show. "Sample Show" and "Sample Show Two" stay apart.

### What is stored and shown

Schema 3 (migration 2 to 3) adds to `files`: `sort_signal`, `sort_note`, `sort_rev` (`MediaSorter.revision`, now 1),
`sort_inputs` (the override, server type and source setting that went into the decision) and `review`; and `items.review`.
Every list query, the counts, Continue Watching and Recently Added add `review = 0`.

- **Item info:** detail page > More > How This Was Sorted: the signal, the note and the file name, with Move to Movies /
  Move to Shows and, after a Move, Sort Automatically (`SortInfoSheet` in App/Shared/SortMoveSheet.swift).
- **Logs:** every decision is logged with `os.Logger`, category "Sorting", at debug level:
  `sorted movie by moviePattern: <path, private> (<note>)`.
- **Needs Review:** Settings > Library > Needs Review, with the count; each row shows the file name and why it could not
  be sorted; choosing one offers Move to Movies and Move to Shows.

### Re-sorting

Files indexed before this change have no sort record and are sorted once on the next scan; so is a file whose rule
revision, override, server type or source setting changed, and every file still in Needs Review (a new file of the same
show can resolve it). A rescan with nothing changed writes nothing (tested).

### Move to Movies / Move to Shows

In the long-press menu of a movie card (Move to Shows) and an episode card (Move to Movies), in How This Was Sorted, and in
Needs Review. A system form, filled from the file name: Title (or Show), Year (optional), and for a show Season, Episode,
Last Episode (optional). Checks: a title; year 1888 to 2100; season 0 to 999; episode 1 to 9999; last episode not before
the first. The choice covers every version of the item.

The choice is a user-data ledger record of the new type `sorting` (record id: source id + newline + path; one atomic group
`kind, title, year, season, episode, episodeEnd, signal`), so it syncs through iCloud like watch state and survives a rescan
and a rebuilt index. Sort Automatically writes a tombstone. Scans read the choices through
`LedgerSortOverrides`.

### Media servers

Jellyfin and Emby items already arrive with their `Type`; it is now decoded and carried on each file
(`SourceEntry.serverItemType`: "Movie" or "Episode"; "Video" and anything else mean nothing). The request is unchanged.
Source setting (Jellyfin and Emby only): **Sort by Filename Instead of Server Library Types**, default off, PROVISIONAL
(R171), kept in the source options as `sortByFilename=1`.

### Tests (Linux, WSL)

`LibraryIndexTests/SortingTests` (15): a flat folder of 40 synthetic files (23 episode files, 11 movies, 6 Needs Review),
release-tag noise, "Sample Show" beside "Sample Show Two", "Sample Movie 2049 (2017)" (a movie of 2017, title
"Sample Movie 2049"), absolute numbering alone and with siblings, weak markers with a year, folder hints, server types
(agree, disagree, unclear, preferFilename), the flat folder through a real scan, the sort info and the log hook, rescan
stability, a review file resolved by a new sibling, overrides through the ledger and a second ledger, removal, record
round trip and merge, and the upgrade path. `AppLogicTests/SortingLogicTests` (7): the source setting, the Move form and its
checks, Move from Needs Review through a real scan and back, Move an item to Shows, Sort Automatically, the online check
with a fake lookup. `SourceJellyfinTests` and `SourceEmbyTests`: the item type read from the recorded fixtures.

### Patterns that cannot be sorted safely (they go to Needs Review unless a folder, a sibling, the online check or a Move decides)

1. A title with no year and no marker ("Sample Clip.mkv"): a movie without a year, or a one-off episode.
2. An absolute number with no other file of that show ("Sample Lone Show - 007.mkv"): episode 7, or a title with a number.
3. A weak marker with no year and no sibling ("Sample Extra E05.mkv").
4. A season with no episode ("Sample Pack S03.mkv"): a whole season in one file, or a title.
5. A date with no show name ("2024-01-02.mkv").

Accepted on purpose but can be wrong:

6. A year plus a weak marker is a movie: "Sample Movie Seven Ep 2 (2012)" keeps "Ep 2" in its title; an episode named this
   way needs Move to Shows.
7. A name that looks like a strong marker is an episode even in a movie title (a title containing "S01E01" or "1x02").
8. Shows with one name and different years ("Sample Show (2019)" and "Sample Show (2005)") are one show: the show key
   ignores the year (Part 1, item 6; not changed here).
9. Date episodes are filed by date (season 0 when no season is known), not by episode number.
10. The online check can confirm a wrong title with high confidence; it only ever moves Needs Review files, never a file
    the rules already decided, and How This Was Sorted shows "Online Lookup" with Sort Automatically to take it back.

### Not proven

- None of the App/ code (screens, sheets, menu items, the scan wiring, the logger) has been compiled: syntax only
  (parse-app, design-lint).
- The online check against the real TMDB service (tested with a fake lookup only).
- Server item types against a live Jellyfin or Emby server (recorded fixtures only).
- A Move choice reaching a second Apple TV through iCloud (ledger sync is tested in memory only).
- The first scan after the upgrade on a large library: every file is sorted once (one parse per file, no network), time
  not measured.
- With "trust unchanged folders" on (`ScanOptions.trustFolderVersions`, off in the app), a Move in an unchanged folder
  waits for a full rescan.
