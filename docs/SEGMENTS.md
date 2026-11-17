# Skip segments and Up Next data

Status: package code and tests written; **nothing has been compiled on a Mac or run on a device**. Everything marked PROVISIONAL is a decision the specs do not make; each names its alternative.

## What exists

Three sources produce skip segments (recap, intro, credits). They are merged, checked, and handed to the playback logic, which shows the skip button and the Up Next card.

| Source | Where it comes from | Confidence | Rank |
|---|---|---|---|
| User mark | the "Mark Skip Points" menu in the player, stored in the user-data ledger | 1.0 | 4 (highest) |
| Embedded chapters | MKV / WebM Chapters element, read with ranged reads through `MatroskaReader` | 0.9 (set by `ChapterSegmentExtractor`) | 3 |
| Sidecar file | `<video name>.edl` or `<video name>.segments.json` in the video's folder | 0.8 (PROVISIONAL) | 2 |
| Online timestamp lookup | **not built**, FEATURE_BACKLOG item 33 | | 1 |
| On-device detection | **not built**, FEATURE_BACKLOG item 34 | | 0 |

`SegmentSourceInputs` already has empty slots for the two later sources, so adding them changes the collector, not the merge.

## Precedence and overlap

1. Each source's candidates go through `SegmentResolver` (the SEG limits: intro 10 s to 3 min, recap starts within the first 60 s, credits start in the last 40 percent, and so on). A rejected candidate is dropped and a line says why.
2. Within one type the highest-ranked source wins (user mark over chapters over sidecar), as SEG-5 says.
3. PROVISIONAL: across types, a candidate that overlaps a higher-ranked one by more than 1.0 s is dropped. Alternative: trim the lower one. Dropping was chosen because a trimmed range is a range nobody marked.
4. The post-credits chapter start is kept as it is; the merged list is not re-validated (re-validating would stretch credits to the end of the file).

## Chapters

Only MKV and WebM are read. MP4 / MOV chapter tracks are **not done**. Hidden editions are skipped; the flagged default edition is marked; nested chapters are flattened. Titles are classified by `ChapterTitleRecognizer`.

## Sidecar formats (PROVISIONAL: the specs name none)

- `<stem>.edl`: one line `start end action`. Action words `recap`, `intro`, `credits`. Numeric EDL actions (0 to 3) are ignored with a warning. `#` starts a comment. Times: `12.5`, `1:15`, `0:01:15.250`.
- `<stem>.segments.json`: `{"version":1,"referenceDuration":2500,"segments":[{"type":"intro","start":0,"end":90,"referenceDuration":2500}]}`. Bad entries are skipped one by one with a warning. A version above 1 is read with a warning.
- Limits: 256 KiB per file, 500 entries. Alternative formats can be added in `SidecarFormat`.

## Marks

- The menu entry "Mark Skip Points" lists Mark Recap / Intro / Credits. The first press of a kind remembers the playhead as the start; the same kind pressed again saves the end. The menu title changes to "Mark X End" while a start is pending.
- Limits apply when saving; a refused mark says why and keeps the start. Credits need an end mark (PROVISIONAL; alternative: a one-press "credits to the end").
- A different kind pressed while a start is pending replaces the start (PROVISIONAL).
- Delete removes a saved mark. Undo covers the changes of this playback only (PROVISIONAL).
- A mark belongs to the item (PROVISIONAL; alternative: apply to the rest of the season, not built).
- Storage: one ledger record per item and kind, `<itemKey>|<kind>`, with start, end and the file length it was made on, written as one atomic group so a sync never mixes two devices' halves. A delete is a tombstone that a later mark revives.
- In STORAGE_MODEL terms: marks travel with the cloud copy and with Export; they are **not** in the essentials copy (sources and settings only).
- A mark made on a file whose length differs by more than `SegmentLimits.durationTolerance` from the one playing is not used (a different cut), and a line says so.

## Collection

`SegmentCollector` runs the chapter read and the sidecar read under one 6 second deadline; if it passes, the player starts with user marks only and a note says so. It never throws. The file length is `file.technical?.duration ?? item.runtime ?? item.watch.duration`, else the length in the MKV Info. Without a length nothing can be checked and no segment is used.

`SegmentProvider` (AppLogic) picks the preferred version of the item, reads its marks and runs the collector. `App/Support/SegmentService.swift` wraps it.

## Skip buttons and Up Next

- `PlayerSessionFactory` builds the `PlaybackSession` and `PlayerOverlayController` from the segments and `NextEpisodeFeed.resolve` (the next item in the library, by `EpisodeOrder`).
- PROVISIONAL: Settings > Show Skip Buttons on means each kind is Ask; off means each kind is Off. The three per-kind modes exist in `SkipSettings` and have no Settings rows.
- PROVISIONAL: Play Next Episode Automatically on means When Credits Begin; off means Ask.
- Display-mode matching is not fed (the library has no frame rate); an unknown format keeps the display mode.
- `EpisodeRef.fileID` is the library item id as text.

## Not done

Online timestamp lookups (FEATURE_BACKLOG item 33). On-device detection (item 34). MP4 chapters. Per-kind Settings rows. Marks for a whole season. A one-press credits mark. Anything on a real device.

## Files

Package: `UserData/SegmentMarks.swift`, `PlaybackLogic/SegmentMerge.swift`, `PlaybackLogic/SidecarSegments.swift`, `LibraryIndex/SQLiteLibraryStore+ItemKey.swift`, `AppLogic/SegmentSourcing.swift`, `SegmentProvider.swift`, `SegmentMarkFlow.swift`, `NextEpisodeFeed.swift`. App: `Support/SegmentService.swift`, `Support/SegmentMarks.swift`, `Features/Player/SegmentsWiring.swift`, `PlayerMarkMenu.swift`.
