# SF Symbols used by the app (#22 D)

Every SF Symbol name in `App/` (the Top Shelf extension uses none), grouped by screen, with the file that names it.
Collected from the code on 2026-11-19 (`systemImage:`, `Image(systemName:)`, `UIImage(systemName:)` and the `symbol`
values passed to `ArtworkView`, `RowLabel` and `SlotLabel`).

**Why this list exists.** A symbol name is a plain string. A name that does not exist builds without any error or warning
and draws a **blank icon** at run time (the label text still shows). So the compile check cannot catch a wrong name; only
the screenshots can. No name here was checked against Apple's SF Symbols catalogue in this project (there is no Mac);
each is checked by looking at the screenshot listed.

Status values:
- **in screenshots (NN)**: the screen in screenshot NN (UITests/ScreenshotTests.swift) shows this icon; look there to see
  that it is drawn and not blank. This file does not confirm that by itself.
- **name from memory, verify in screenshot 08**: added in #21 F and not yet seen in any screenshot (also in the "verify"
  list of the screenshot index.md).
- **not in a screenshot**: no screenshot shows it yet (a menu the UI tests do not open, or the player); check on a device.

## Tab bar (App/Shell/RootView.swift)

| Symbol | Where | Status |
|---|---|---|
| `house` | Home tab | in screenshots (01, every NN-...-TABBAR check) |
| `film` | Movies tab | in screenshots |
| `tv` | Shows tab | in screenshots |
| `folder` | Files tab | in screenshots |
| `magnifyingglass` | Search tab | in screenshots |
| `gearshape` | Settings tab | in screenshots |

## Cards: posters, Continue Watching, episode cards (App/Shared/PosterCard.swift, ArtworkView.swift, Shows/SeriesCard.swift, Shows/SeasonsList.swift, Discover/DiscoverView.swift)

The placeholder symbol drawn when a card has no picture.

| Symbol | Where | Status |
|---|---|---|
| `film` | movie card, Discover movie card | in screenshots (Sample Show 2 and items without art) |
| `tv` | show card, episode card, Discover show card | in screenshots |

## Card long-press menu (App/Shared/CardContextMenu.swift)

| Symbol | Where | Status |
|---|---|---|
| `film` | Go to Movie (#21 F) | **name from memory, verify in screenshot 08** |
| `tv` | Go to Show (#21 F) | **name from memory, verify in screenshot 08** |
| `minus.circle` | Remove from Continue Watching (#21 F) | **name from memory, verify in screenshot 08** |
| `eye`, `eye.slash` | Mark as Watched / Unwatched | in screenshots (52) |
| `heart`, `heart.slash` | Add to / Remove from Favorites | in screenshots (52) |
| `tv` | Move to Shows | in screenshots (68) |
| `film` | Move to Movies | in screenshots (68) |

`film` and `tv` themselves are proven by the tab bar; what screenshot 08 must show is that the two new menu items have
their icon.

## Movies and Shows toolbar (App/Features/Movies/: SortMenu, FilterMenu, SavedViewsMenu, AlphabetJumpMenu, FilterChipsRow)

The same views on Movies (53) and Shows (07, #21 F reuses them; no new names).

| Symbol | Where | Status |
|---|---|---|
| `arrow.up.arrow.down` | Sort menu; "Show Largest First" / "Show Smallest First" | in screenshots (53, 07) |
| `line.3.horizontal.decrease.circle` | Filter menu | in screenshots (53, 07) |
| `bookmark` | Saved Views menu | in screenshots (53, 07) |
| `plus` | Save Current View | not in a screenshot (menu content; 07-shows-toolbar-saved-views-menu should show it) |
| `trash` | Delete a Saved View | not in a screenshot |
| `textformat.abc` | Jump to Letter | in screenshots (53, 07) |
| `xmark` | a filter chip | not in a screenshot |

## Movie page (App/Features/Detail/: ItemDetailContentView, VersionsMenu, ExtrasMenu)

| Symbol | Where | Status |
|---|---|---|
| `play.fill` | Play / Resume | in screenshots (57) |
| `arrow.counterclockwise` | Start Over | in screenshots (49) |
| `square.stack` | Versions | in screenshots (60, 47) |
| `doc.on.doc` | Extras | in screenshots (48) |
| `ellipsis` | More | in screenshots (57, 44) |
| `eye`, `eye.slash` | Mark as Watched / Unwatched (More) | in screenshots (44) |
| `heart`, `heart.slash` | Add to / Remove from Favorites (More) | in screenshots (44) |
| `magnifyingglass` | Fix Match (More) | in screenshots (44) |
| `arrow.up.arrow.down` | How This Was Sorted (More) | in screenshots (44) |

## Show page (App/Features/Shows/SeasonsList.swift)

| Symbol | Where | Status |
|---|---|---|
| `play.fill` | Play / Resume | in screenshots (55) |
| `ellipsis` | More | in screenshots (55) |
| `eye`, `eye.slash` | Mark Show as Watched / Unwatched; an episode's Mark as Watched / Unwatched | not in a screenshot (menu content) |
| `checkmark.circle` | the watched mark on an episode card | in screenshots (55, 56) |

## Move sheet and How This Was Sorted (App/Shared/SortMoveSheet.swift)

| Symbol | Where | Status |
|---|---|---|
| `film`, `tv` | the sheet's save button; Move to Movies / Move to Shows | in screenshots (66, 67) |
| `arrow.uturn.backward` | Sort Automatically | in screenshots (67) |

## Files (App/Features/Files/: FilesView, FileRowView)

| Symbol | Where | Status |
|---|---|---|
| `externaldrive` | a source row | in screenshots (70) |
| `folder` | a folder row | in screenshots (71, 72) |
| `film` | a video file | in screenshots (73) |
| `captions.bubble` | a subtitle file | in screenshots (73) |
| `photo` | a picture file | in screenshots (73) |
| `doc.text` | an .nfo file | not in a screenshot unless the sample folder has one |
| `doc` | any other file | not in a screenshot |

## Search and Discover (App/Features/Discover/DiscoverView.swift)

| Symbol | Where | Status |
|---|---|---|
| `checkmark` | "On Your Watchlist" | not in a screenshot (needs a key) |

## Settings (App/Features/Settings/, App/Features/Sources/SourceKindListView.swift, App/Shared/LayoutParts.swift)

| Symbol | Where | Status |
|---|---|---|
| `play.rectangle` | Playback row | in screenshots (30) |
| `house` | Home Screen row | in screenshots (30) |
| `externaldrive` | Sources row | in screenshots (30) |
| `books.vertical` | Library row | in screenshots (30) |
| `globe` | Online Lookup row | in screenshots (30) |
| `icloud` | Storage and iCloud row | in screenshots (30) |
| `arrow.clockwise.icloud` | Backup row | in screenshots (30) |
| `accessibility` | Accessibility row | in screenshots (30) |
| `info.circle` | About row; every "Learn More" link | in screenshots (30, 31-38) |
| `plus` | Add a Source | in screenshots (33) |
| `wifi` | Search Your Network | in screenshots (10) |
| `arrow.clockwise` | Scan Now (Library); Try Again (Needs Review) | in screenshots (35) |
| `questionmark.circle` | the Needs Review button | in screenshots (63) |

## Empty, error and loading states (App/Support/EmptyStateView.swift, ErrorStateView.swift)

| Symbol | Where | Status |
|---|---|---|
| `externaldrive.connected.to.line.below` | no sources yet | in screenshots (02-06) |
| `tray` | nothing indexed yet | not in a screenshot |
| `magnifyingglass` | no matches / no query | not in a screenshot (06 shows the "needs a key" state) |
| `folder` | an empty folder | not in a screenshot |
| `key` | Discover needs a key | in screenshots (06, 75) |
| `exclamationmark.triangle` | any error state | not in a screenshot |

## Player menus (App/Features/Player/: PlayerCoordinator, PlayerMarkMenu)

UIKit menus in the system player's info panel (`UIImage(systemName:)`).

| Symbol | Where | Status |
|---|---|---|
| `captions.bubble` | the picture-subtitle menu | not in a screenshot (26 shows the system Subtitles menu) |
| `chart.bar` | Playback Stats | not in a screenshot |
| `flag` | Mark Skip Points and each mark | not in a screenshot |
| `xmark` | Cancel Start Mark | not in a screenshot |
| `trash` | delete a mark | not in a screenshot |
| `arrow.uturn.backward` | Undo Last Mark | not in a screenshot |

When a symbol is added or renamed, add it here with the screenshot that shows it, or "not in a screenshot".
