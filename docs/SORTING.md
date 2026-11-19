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
