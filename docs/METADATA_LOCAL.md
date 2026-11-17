# MetadataLocal

Local metadata that needs no provider and no network: `.nfo` files, image files next to a video, and the
metadata inside a Matroska/WebM file. Target `MetadataLocal` in `Packages/VideoPlayerCore`. It depends only on
`VideoPlayerCore` (for `SourceEntry`, `ByteRange`, `MediaSource`). Foundation only; XML uses `XMLParser`
(`FoundationXML` on Linux). Nothing here touches the network or the file system: callers pass bytes, folder
listings, or a byte-range closure.

Other targets decide what to do with the result. In particular chapter *recognition* (Intro, Credits, ...) is not
here: the reader only exposes chapters with their titles in every language.

## 1. NFO parsing (`NFOParser`)

`NFOParser.parse(_ data: Data) -> NFOFile` and `parse(text:)`. Never throws. `NFOFile.documents` holds one
`NFOMetadata` per `<movie>`, `<tvshow>` or `<episodedetails>` element in file order (so a multi-episode file gives
several). `NFOFile.link` holds a bare URL; `NFOFile.warnings` says what had to be repaired.

Fields read: title, originaltitle, sorttitle, showtitle, year, premiered/releasedate/aired, plot, outline, tagline,
runtime, genre, studio, country, tag, mpaa/certification, ratings, uniqueid, legacy tmdbid/imdbid/tvdbid/id,
set (collection), actor, director, credits/writer, thumb/fanart/art, trailer, season, episode,
displayseason/displayepisode, playcount, resume.

### Tolerance

| Input | Behaviour |
|---|---|
| UTF-8 BOM, UTF-16 LE/BE with BOM, UTF-16 without BOM | decoded |
| Not valid UTF-8 | read as Windows-1252, then Latin-1 |
| `<?xml ...?>` and `<!DOCTYPE>` | removed before parsing (so a wrong `encoding=` cannot fail the parse) |
| HTML entities XML does not know (`&nbsp;`, `&eacute;` ...) | turned into numeric references |
| Bare `&` or unknown `&name;` | kept as text |
| Control characters XML forbids | dropped |
| Several top-level elements | allowed (the input is wrapped in a synthetic root) |
| Malformed XML | the elements read before the damage are kept; warning added |
| HTML-escaped or CDATA plot (`&lt;br /&gt;`, `<p>`) | converted to plain text with line breaks |
| Empty elements, whitespace-only values | nil / empty, never junk |
| A file that is only a URL (themoviedb, imdb, thetvdb) | `link` with service, id, movie/tv |
| A URL after the XML | `link` set as well |
| Empty file, binary junk, HTML | no documents, a warning |

### Interpretations (PROVISIONAL)

The NFO conventions are not fully specified for these cases; the smallest reasonable reading was taken.

1. Episode date prefers `<aired>`, movie/show date prefers `<premiered>`; each falls back to the other (and `<releasedate>`).
2. `year` is `<year>` when it is 1000-9999, else the year of the date.
3. `runtimeMinutes` is `<runtime>` (leading integer, so "120 min" works); when missing or 0 it falls back to
   `fileinfo/streamdetails/video/durationinseconds`, rounded to minutes.
4. Ratings: the `<ratings>` block first; if it is empty the legacy `<rating>` + `<votes>` pair becomes one default
   rating with `name == nil`. `<criticrating>` is added with `max = 100` and `<userrating>` (when > 0) with `max = 10`.
5. `<set>` with no children is the collection name; with children it uses `<name>` and `<tmdbcolid>`/`<tmdbid>`.
6. Bare `<id>`: starting with `tt` means IMDb; all digits in a `<tvshow>` means TVDB. In a movie or episode a digit-only `<id>` is ignored.
7. `imdbID` is only set when the value starts with `tt`.
8. A `<thumb>` without `aspect` is `thumb`, except `type="season"` which is a season `poster` with its `season` number (0 specials, -1 all seasons).
9. `genre`, `studio`, `country`, `tag` and `director` lists are de-duplicated ignoring case.

## 2. Sidecar images (`SidecarImageFinder`)

Works on a folder listing (`[SourceEntry]`) and a video file name; no I/O. Matching is case-insensitive.
Extensions: `jpg`, `jpeg`, `png`, `webp`, `tbn`. When files differ only by extension the first in that order wins.
Directories are never images.

**Movie** (`images(forMovie:in:folderHoldsOneVideo:)`), strongest first, per role:

| Role | Names tried (`<name>` = video base name) |
|---|---|
| poster | `<name>-poster`, `<name>.poster`, `<name>-folder`, `<name>.folder`, `<name>-cover`, `<name>.cover`, **`<name>`**, then (only if the folder holds one video) `poster`, `folder`, `cover`, `movie`, `show`, `default` |
| backdrop | `<name>-fanart`, `<name>-backdrop`, `<name>-background` (also `.` forms), then folder-wide `fanart`, `backdrop`, `background`, `art` |
| logo | `<name>-clearlogo`, `<name>-logo`, then `clearlogo`, `logo` |
| banner | `<name>-banner`, then `banner` |
| landscape | `<name>-landscape`, then `landscape` |
| thumb | `<name>-thumb`, `<name>.thumb`, then `thumb` |

A folder with several videos does not hand its generic `poster.jpg` to any of them (`folderHoldsOneVideo: false`).

**Episode** (`images(forEpisode:in:)`): same-name files only. thumb = `<name>-thumb` > `<name>.thumb` > `<name>`;
poster `<name>-poster`; backdrop `<name>-fanart`/`-backdrop`; landscape; logo. The season's or show's own
`poster.jpg` is never an episode image.

**Show folder** (`images(forShowFolder:)`): `poster`, `folder`, `cover`, `movie`, `show`, `default`; `fanart`, `backdrop`, `background`, `art`; `clearlogo`, `logo`; `banner`; `landscape`; `thumb`.

**Season** (`images(forSeason:showFolder:seasonFolder:)`): in the show folder `season01-poster` (also `season1`,
`season-01`, `season 01`, `season 1`; for 0 `season-specials`, `season00`, `season0`, `specials`), then for the poster the plain
`season01`; then anything still missing is taken from the season's own folder (`poster`, `folder`, ... or
`season01-poster`). `seasonNumber(ofFolder:)` reads "Season 02", "S2", "Staffel 3", "Specials" (0).

Interpretation (PROVISIONAL): a plain same-name image (`Film.jpg`) is a poster for a movie and a thumb for an episode.

## 3. Embedded Matroska/WebM metadata (`MatroskaReader`)

```swift
let metadata = try await MatroskaReader().read { range in try await source.read(path, range: range) }
// or: try await MatroskaReader().read(from: source, path: path)
```

The only I/O is the closure `(ByteRange) async throws -> Data`.

### Strategy and limits

1. One read of the first `headBytes` (default 512 KiB). Parse the EBML header (DocType `matroska` or `webm`), find the Segment, walk its children.
2. The walk stops at the first Cluster. Clusters are never read.
3. Elements that start in the window but end beyond it (for example a big Attachments) and elements the SeekHead
   points to beyond the window (typically Chapters and Tags written after the clusters) are fetched with one more read each.
   The read length is bounded by the next element the file has told us about, so it stops short of the Clusters.
   Limits: `maxFetches` (12) extra reads, `maxElementBytes` (4 MiB) per element, 64 KiB first chunk.
   Memory is therefore bounded by `headBytes + maxElementBytes` plus the parsed result.
4. The SeekHead can point at a second SeekHead; it is followed (within `maxFetches`).
5. Without a SeekHead, elements after the first Cluster are **not** searched (no hopping from cluster to cluster, which would cost one round trip per cluster); a warning says so.
6. Unknown-size Segment and unknown-size Clusters are fine (the Segment size is never needed). An unknown-size
   element that is not a Cluster is not read.
7. Void and CRC-32 elements are skipped. Unknown elements are skipped if the next element looks right; otherwise the walk resynchronises on the next known top-level ID and warns.
8. Truncated data gives a partial result plus warnings. Errors (`MatroskaError`) are only thrown when no usable
   result exists: empty file, not EBML, wrong DocType, Segment missing or cut off, or the first read failed. `CancellationError` is passed through.

### What is read

- Info: TimecodeScale, Duration (converted to seconds), Title, MuxingApp, WritingApp, DateUTC, SegmentUID.
- Tracks: number, UID, type, codec ID, codec name, raw CodecPrivate, name, Language (default `eng`, as the spec says) and BCP 47,
  enabled/default/forced/hearing-impaired/visual-impaired/text-descriptions/original/commentary flags, DefaultDuration (frame rate), ContentEncodings (flag only).
  Video: pixel and display size, interlacing, Colour (matrix, transfer, primaries, range, bits, MaxCLL, MaxFALL, mastering display), Dolby Vision (`dvcC`/`dvvC` in BlockAdditionMapping: profile, level, rpu/el/bl, compatibility id).
  Audio: sampling frequency, channels, bit depth.
- Chapters: editions (UID, hidden, default, ordered) and nested chapters (UID, string UID, start, end, hidden, enabled, titles in every language with language, BCP 47 and country). Nesting deeper than 12 levels is cut with a warning.
- Tags: global and per-target tags, SimpleTag trees, TargetTypeValue/TargetType, target UIDs. Binary values keep only their size.
- Attachments: name, media type, description, UID, data size. The data is never kept.
- `layout`: file offsets of SeekHead, Info, Tracks, Chapters, Tags, Attachments, Cues and the first Cluster. Cues are located, not parsed.
- `detailRows`: rows for a File Details screen (container, title, duration, one row per track, chapter count, muxer, attachments, problem count).

### Honesty rules

- Matroska has no Dolby Atmos flag. `MatroskaTrack.atmos` is `.nameSuggests` only for E-AC-3 or TrueHD tracks whose
  *name* says Atmos, otherwise `.unknown`. The header alone is never reported as proof.
- `ColourInfo.transfer == .pq` means "PQ transfer", which is HDR10, HDR10+ or a Dolby Vision base layer. It cannot tell which.
- Nothing is measured from the stream; every value is what the file's header says.

### Interpretations (PROVISIONAL)

1. Repeated top-level elements: the first Info wins; Tracks, Chapters, Tags and Attachments are appended.
2. A chapter with no ChapterDisplay language is treated as `eng` (the spec default).
3. A chapter with no start time is kept at 0 and a warning is added.
4. `preferredEdition`: the default non-hidden edition, else the first non-hidden, else the first. Ordered editions are exposed as flagged, not resolved.
5. `Atmos` handling as above.
6. The head window defaults and limits (512 KiB, 4 MiB, 12 reads) are a judgement call, not measured against real files.
7. `languageName` knows about 40 common codes and returns the code itself otherwise.

## 4. Tests

`Tests/MetadataLocalTests`: `NFOTests`, `SidecarImageTests`, `MatroskaReaderTests`, `MatroskaFuzzTests`,
`FFmpegCrossCheckTests`, and `MatroskaWriter.swift` (the test-side EBML encoder; there is no mkvmerge here).
Files built by the writer are hand-written from the Matroska specification, **not recordings of any real muxer**.
NFO samples are hand-written from the publicly documented NFO conventions, not recorded from Jellyfin, Emby or any other tool.

Run on Linux (WSL): `bash scripts/test-core.sh`, or only this target in a private copy:
`swift test --filter MetadataLocalTests`.

`FFmpegCrossCheckTests` builds a real file with ffmpeg and compares it with what ffmpeg was told to write. It looks for
`$VP_FFMPEG`, then `~/video-player-test-servers/ffmpeg/ffmpeg`; with neither it is **skipped** and reported as skipped.

### Not verified

- Files from real mkvmerge, MakeMKV, HandBrake or other tools (only the test writer and, when enabled, ffmpeg).
- A SeekHead that points at a second SeekHead: the code follows it by the same mechanism as any other element, but no test builds that file.
- Real nfo files written by Jellyfin, Emby or other tools, and nfo files in languages or encodings beyond the samples.
- Behaviour of real `MediaSource` implementations for short reads and reads past the end (the tests simulate both: an empty answer and `.rangeNotSatisfiable`).
- Build and run on Apple platforms (only compiled and tested on Linux). `XMLParser` and `String(data:encoding:)` behave the same in the cases tested, but are different implementations.
- Time and memory on very large or damaged real files. A hang cannot be detected by a test; the code's loops all advance or stop, and the fuzz tests finish in seconds.
- Dolby Vision profile and level for real streams (checked against the record layout only).
