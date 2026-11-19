# Artwork audit (#9, read-only)

Request #9 asked whether each movie and show screen uses the artwork types the way the Apple TV app does, with a read-only report before any UI change. This file is that report. **Nothing here changes code.** The fixes are made under #15 Parts 4 to 6 and 9, on the new layouts (Addendum #19 D, order of work). The last section says which #15 part covers each gap.

Sources used:
- The code, read on 2026-11-18. File and line numbers are given in the tables.
- Apple HIG, Images (https://developer.apple.com/design/human-interface-guidelines/images), read 2026-11-18. In its tvOS section, Apple says layered images are "at the heart of the Apple TV user experience". It also says that if you "use standard views and system-provided focus APIs", layered images "automatically get the parallax treatment".
- The Apple TV app's own behaviour could not be checked here (no Apple TV). Every Apple TV app claim below is marked **unverified, from memory**, and is listed at the end for checking on a device.

## 1. Artwork inventory

**Shared plumbing**

| What | Where | Notes |
|---|---|---|
| Resolver | `ArtworkEngine.resolve` (AppLogic/ArtworkEngine.swift:79-94) | Order: a sidecar picture, then the TMDB poster (only with the user's key), then none. |
| Index model | `LibraryItem` and `ItemMetadata` (LibraryIndex/LibraryModels.swift:108-148) | No artwork fields. Only `tmdbID` is stored. Artwork is resolved on demand and never written to the index. |
| Sidecar cache | `ArtworkDiskCache` (AppLogic/ArtworkCache.swift) | In Caches/artwork, so the system can purge it. One file per key; least recently used files go above 150 MB; 40 MB cap per file. |
| Online cache | `URLCache` in Caches/remote-artwork (App/Support/ArtworkResolving.swift:36-47) | 20 MB memory, 100 MB disk. Purgeable. Never in the iCloud backup (docs/BACKUP.md). |
| "Nothing found" | ArtworkEngine.swift:69 | A miss is remembered for 15 minutes. |
| Fallback | `ArtworkView.placeholder` (App/Shared/ArtworkView.swift:44-52) | A `.quaternary` rectangle with an SF Symbol (`film` or `tv`). No invented art. |
| TMDB sizes | MetadataOnline/TMDBMapping.swift:244 | Poster w780; backdrop, logo and still `original`; profile h632. |

**Per type**

| Type | Comes from | Mapped in | Shown today |
|---|---|---|---|
| Poster 2:3 | Sidecar (`-poster`, `-folder`, `-cover`, then `poster`, `folder`, `cover`, `movie`, `show`, `default`; MetadataLocal/SidecarImages.swift). TMDB `poster_path`. | `ArtworkEngine.resolveItem/resolveSeries`, `TMDBArtworkProvider.poster` | **Yes. It is the only type drawn.** |
| Backdrop 16:9 | Sidecar `fanart`, `backdrop`, `background`, `art`. TMDB `backdrop_path`. | `SidecarImages.backdrop`, `MetadataFields.backdrop` | No. The engine never reads it. |
| Episode still 16:9 | Sidecar `<name>-thumb`, `<name>.thumb`, `<name>.jpg`. TMDB `still_path`. | Sidecar thumb in ArtworkEngine.swift:109-110. The TMDB still only reaches `MetadataMerger`, which the app never calls. | Only the sidecar thumb, inside a 2:3 frame. Online, an episode falls back to the **show poster**. |
| Season poster | Sidecar `seasonNN-poster`. TMDB season `poster_path`. | `images(forSeason:)` has no caller. | No. |
| Cast photo | TMDB `profile_path` only. | `Person.profilePath` | No. |
| Title lettering | Sidecar `clearlogo` / `logo`, NFO `clearlogo`, TMDB `images.logos`. | `bestLogo` → `MergedMetadata.logo` (unused). | No. |
| Server artwork (Jellyfin, Emby) | None. Those source modules have no image code. There is no Plex module. | n/a | n/a |
| Embedded in file | Matroska attachments are parsed by name, type and size only; the bytes are never read. | MetadataLocal/MatroskaParser.swift | No (listed as text in file details). |

**Debug fixture art.** UITestFixtures.swift:150-160 writes generated gradient PNGs: `poster.png` 240×360 (2:3) and `fanart.png` 480×270 (16:9) per movie and show folder. Episodes get none, so an episode card shows the show poster. `fanart.png` is never shown.

**Why a 16:9 picture sits in a 2:3 frame.** `ArtworkView` is one 2:3 frame for every card. The picture fills it and is clipped (ArtworkView.swift:17-20, 33). This was done on purpose (screenshot review item 3c): an unclipped wide picture made its card wider than the cards beside it. The side effect is that a 16:9 still or fan-art shows only a vertical strip from its middle. It is never stretched, but it is the wrong shape for that surface.

## 2. Surface by surface

"Apple TV app" columns are **unverified, from memory**.

| Surface | Today (file) | Apple TV app (unverified, from memory) | Gap |
|---|---|---|---|
| Home Continue Watching | 2:3 poster (`PosterCard` via `CardRow`). Episode shows the show poster. | Landscape 16:9 card (still or backdrop) with progress inside it. | Wrong shape. Progress sits below the card. |
| Home Next Up, Recently Added | 2:3 poster. | 2:3 posters or 16:9 cards depending on the row. | Small: shape choice per row. |
| Movies grid | 2:3 poster, 5 columns. | 2:3 posters. | None for artwork. |
| Shows grid | 2:3 series poster (`SeriesCard`). | 2:3 posters. | None for artwork. |
| Movie detail top | **No image.** `artworkKey` exists but is never drawn. | Full-width backdrop with a gradient into the content, title (often lettering), metadata, Play focused. | Backdrop, synopsis and lettering are missing. |
| Movie detail below | Nothing: no shelves, the lower half is empty. | Shelves: extras, cast with photos, related titles. | Cast and info are missing. |
| Show page | Text list, no image (`SeasonsList`). | Backdrop at the top, a season picker, and a row of 16:9 episode stills. | Backdrop and stills are missing. |
| Season sections | Text header "Season N", no image. | A season picker over the episode row. | Layout only. |
| Episode rows | Text: code, runtime, progress bar, check. No still (`EpisodeRowView`). | 16:9 still with progress inside it, number, title, runtime, synopsis, watched state. | Still, title and synopsis are missing. |
| Search results | 2:3 poster grid. | 2:3 posters. | None. |
| Discover cards | 2:3 `remote:` poster. | 2:3 posters. | None. |
| Top Shelf | `.poster` image shape. Items without a picture are dropped. | Wide 16:9 key art for many apps. | A shape choice (open list, #15 9.4). |
| Player info, Now Playing | `commonIdentifierArtwork` from `item-N` (PlayerCoordinator.swift:400-416). | Poster or still in the info panel. | None known. |
| Up Next card | `previewImage: nil` | A still of the next episode. | Missing preview image. |
| Needs Review, Files rows | SF Symbols only. | n/a (no matching surface). | None. Files keeps symbols (#15 Part 7). |

## 3. Detail page behaviour (for comparison)

Today the movie or episode page is a ScrollView with these parts, top to bottom:
1. Series link (episodes only).
2. Title.
3. Facts line.
4. Badges.
5. A progress bar on its own line.
6. Buttons: Play/Resume, Start Over, Versions, Extras, More.

There is no default focus set, so the first focusable control gets focus: Play on a movie, but the series link on an episode.

Apple TV app (unverified, from memory):
- A backdrop with a gradient.
- Play or Resume first and focused.
- A metadata line, then the synopsis.
- Secondary actions.
- Shelves (episodes, extras, cast, related).
- Scrolling moves the backdrop up behind the shelves.

## 4. Fallbacks

- Nothing is ever stretched. ArtworkView fills and clips, so the shape is right and the content is cropped.
- When there is no artwork, every surface shows the symbol placeholder, never a tiny or distorted image.
- **Gap.** A 16:9 picture in a 2:3 frame shows a middle strip, so surfaces that want 16:9 need their own frame. Covered by #15 Parts 4 and 5.
- No HIG page read here supports a blurred fill behind a mis-shaped image. The rule stays fill-and-clip with the right frame shape, and the placeholder when the right type is missing.

## 5. Title lettering

#9 item 5 asked for an open question: is title lettering content artwork (allowed) or a logo (not allowed)?
- **Answered by the user in #15 Part 9:** title logos are allowed, on the movie and show pages, with a "Show Title Logos" setting. They are never on grid cards.
- The rule "no logos except the TMDB logo in About" still holds for brand and company logos.
- No new OPEN_QUESTIONS entry is needed. The Part 9 choices get their own R entries when Part 9 is built.

## 6. Which #15 part covers each #9 fix

| #9 gap | Covered by | Status |
|---|---|---|
| Continue Watching shape and progress inside the card | #15 4.1 and D4 | D4 in the shared-components commit; 4.1 pending |
| Movie detail backdrop, synopsis, cast, Media Info, Play focused | #15 6.2 | built (R182); synopsis and cast need a TMDB key; verify in next screenshots |
| Show page backdrop, 16:9 episode stills, episode titles | #15 5.2, 5.3 | backdrop built (R182); stills and titles pending |
| Episode row progress inside the still | #15 D4, 5.2 | pending |
| Title lettering | #15 Part 9 | built (3e7d8fe, 85fa8a9; R179) |
| Season posters, Top Shelf shape, Up Next preview image | not in #15 | open list (not built: no new features) |
| Selection of "which type goes where, with which fallback" in AppLogic | #15 Parts 4 to 6 and 9 (built with each layout) | pending |
| Screenshot steps for movie, show, season and episode pages | already in the main set (55 to 61) and the accessibility set | done (2bb3f53) |

## Device checks for you (unverified, from memory)

On your Apple TV, in the Apple TV app:
1. Does Continue Watching use wide (16:9) cards, with the progress bar inside the picture?
2. Does a movie page open on a full-width backdrop, with Play focused?
3. On a show page, are the episodes a sideways row of wide stills with a season picker above?
4. Does the title appear as lettering artwork rather than plain text when the show has it?
5. Do cast members appear as a shelf with photos?
