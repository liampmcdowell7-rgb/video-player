# HIG audit

Standard: native tvOS 27 with Liquid Glass, indistinguishable from the system apps (docs/DESIGN_SYSTEM.md). Method: every screen is compared with the component map in that file.

**Status of every row in every table below: not yet seen on a screen.** Reviewed from source, from Apple's pages and from `scripts/design-lint.sh` (App/ was clean on 2026-11-17 after one comment fix). Nothing is compiled, run in a Simulator or run on an Apple TV; no row may be changed to "seen" until the visual checklist (docs/DEVICE_TEST_CHECKLIST_VISUAL.md) item for it has been done on a device.

## Screens that exist (placeholders)

| Screen / control | Apple component | Deviation from stock | Reason | Status |
|---|---|---|---|---|
| App shell | `TabView` with `Tab` | None | Standard top tab bar; the SDK applies the material. Height 68 pt and top offset 46 pt are fixed by the system (HIG Tab bars) | not yet seen on a screen |
| Tabs | Home, Movies, Shows, Files, Discover, Search, Settings | None (names provisional, OPEN_QUESTIONS 7 and 8) | Single-word names with SF Symbols | not yet seen on a screen |
| Discover tab visibility | `if` inside `TabView` driven by `@AppStorage` | **Possible deviation**: HIG says not to hide tabs | Interpretation D-DS6 (user setting, not unavailable content); alternative: always show | not yet seen on a screen |
| Search tab | `Tab(role: .search)` | None | System search tab, placed at the trailing end by the system | not yet seen on a screen |
| Per-tab navigation | `NavigationStack` | None | Menu goes back one level; at the top level it goes Home (HIG Remotes) | not yet seen on a screen |
| Home, Movies, Shows, Files, Discover (empty) | `ContentUnavailableView` (tvOS 17.0+) | None | Standard empty state | not yet seen on a screen |
| Search | `ContentUnavailableView` + `.searchable` | None | Standard search field | not yet seen on a screen |
| Settings | `Form`, `Section`, `Toggle`, `LabeledContent` | None | Grouped like the system settings; section headers in title case | not yet seen on a screen |
| Launch screen | Empty `UILaunchScreen` | None | System background | not yet seen on a screen |
| App icon | Layered image stack, 3 layers, neutral grays | None known | HIG: 2 to 5 layers, rectangular unmasked layers; Icon Composer is not used for tvOS. Catalog naming vs Xcode 27 unverified (DESIGN_SYSTEM section 9) | not yet seen on a screen |
| Top Shelf (static fallback) | Static image 2320x720 (plus 1920x720 slot) | None | Flat gray fallback; extension later | not yet seen on a screen |
| Colour, typography | System colours and text styles only | None | Lint rules `color-literal`, `fixed-font` clean | not yet seen on a screen |
| Focus | Native focus engine | None | No custom focusable views; lint `custom-focus` clean | not yet seen on a screen |
| Back stack | Stock `NavigationStack` | None | One level so far | not yet seen on a screen |
| Scene life cycle | SwiftUI `App` + `WindowGroup`, explicit minimal scene manifest | None | tvOS 27 requires scenes; whether the check passes is unverified (DESIGN_SYSTEM D-DS4) | not yet seen on a screen |
| Localisation | `Localizable.xcstrings`, `InfoPlist.xcstrings` | None | No concatenated sentences; no brand words (lint) | not yet seen on a screen |

## Needs approval

Recorded as provisional decisions in DESIGN_SYSTEM section 1 (D-DS1 to D-DS12):
1. Seven tabs including a hideable Discover tab (D-DS6).
2. Minimum tvOS 27.0 (was 18). Alternative tvOS 18 with availability checks.
3. Two extra icon slots (1280x768 large icon, 1920x720 Top Shelf) that Apple's current HIG page does not list.

## Known risks (later steps)

- The fallback player has no system UI; it must copy the system transport bar, scrubbing, menus, control fade timing and the skip-button look and timing exactly. Highest HIG risk.
- Image-subtitle (PGS) overlay following the system caption style may not be fully possible.
- Playback Stats overlay is the one deliberately custom element (DESIGN_SYSTEM section 6): standard material, small, translucent.

## Library screens and player overlay

Status of every row: **not yet seen on a screen.** The view model behind it is tested in WSL (`Packages/VideoPlayerCore/Tests/AppLogicTests`); the SwiftUI view and the AVKit wrapper are not written or not compiled. Sources: HIG "Playing video" and "Remotes", the screens' own wording in `Sources/AppLogic`, and docs/DESIGN_SYSTEM.md.

| Screen / control | Apple component the view should use | Deviation from stock | Reason / check | Status |
|---|---|---|---|---|
| Home rows (Continue Watching, Next Up, Recently Added) | `ScrollView` of horizontal `LazyHStack` shelves with card buttons (`.buttonStyle(.card)`, Liquid Glass on focus) | None | Row set is closed in `HomeViewModel`; an empty row is left out. Library-only rule by construction | not yet seen on a screen |
| Home, nothing indexed / no sources | `ContentUnavailableView` | None | Wording and one action ("Add a Source") from `EmptyState` | not yet seen on a screen |
| Continue Watching card | Poster card with a progress bar and "1 h 10 min left" | None | Remaining time is plain text, not only a bar. Resume starts automatically (HIG Playing video: avoid asking to resume) | not yet seen on a screen |
| Movies grid | `LazyVGrid`, card buttons, system focus; grid numbers from HIG Layout (5 or 6 columns, 40 pt, 100 pt) | None | Letter jump list only for title sorts. Count line "212 movies" | not yet seen on a screen |
| Filter and sort | `Menu` with `Toggle`s and a `Picker`; active filters as chips under the title | Chips may look hand-made | One list per group; each chip removes itself. Revisit on screen | not yet seen on a screen |
| Saved views | `Menu` entries; name asked with the system text-entry sheet | None | Blank name falls back to "Saved View" | not yet seen on a screen |
| Shows grid, Seasons | Same grid; season `Section`s; Season 0 "Specials", last | None | Play button reads Play / Resume / Play Again | not yet seen on a screen |
| Mark watched / unwatched, favourite | `contextMenu` on a card (long press) | None | Actions on one card or one season | not yet seen on a screen |
| Files browser | `List` with `Label` rows, `NavigationStack` | None | Menu goes to the parent folder (HIG Remotes); at the root the app leaves the screen | not yet seen on a screen |
| Search | `.searchable` on the Search tab, card grid results | None | Library only. Three non-result states | not yet seen on a screen |
| Loading | Plain `ProgressView`, no skeletons | None | HIG: avoid loading screens; the spinner shows only after a delay (view, not model) | not yet seen on a screen |
| Error state | `ContentUnavailableView` with "Try Again" | None | One calm sentence, no codes | not yet seen on a screen |
| Audio and Subtitles pickers | `transportBarCustomMenuItems` / `customInfoViewControllers`; `LabeledContent` in a `Menu` gives a subtitle (27 SDK) | None (decided at wiring time) | Actions take one or two steps | not yet seen on a screen |
| Audio / subtitle delay row | Row in the same menu | New control, not in Apple's player | 50 ms steps, plus or minus 5 s. PROVISIONAL | not yet seen on a screen |
| Skip Intro / Recap / Credits | `AVPlayerViewController.contextualActions` | None | Apple's own API and example (Skip button) | not yet seen on a screen |
| Up Next | `AVContentProposal` + player delegate | Own countdown text | AVKit counts from the end of playback; ours from the credits start | not yet seen on a screen |
| Playback Stats overlay | `contentOverlayView` / `customOverlayViewController`, standard material, system text styles | **Custom** (no Apple equivalent) | Small, translucent, off by default; legibility over bright video and image retention unverified | not yet seen on a screen |
| Honest audio / HDR status | `LabeledContent` rows in the overlay and the Info tab | None | Wording from `PlaybackStatus`; format names open (D-DS7) | not yet seen on a screen |
| Now Playing / Control Center | `AVPlayerViewController` publishes it from `AVPlayerItem.externalMetadata` (title, episode line, poster) | None | The app writes neither `MPNowPlayingInfoCenter` nor `MPRemoteCommandCenter`, so there is exactly one entry, the system player's (`updatesNowPlayingInfoCenter` does not exist on tvOS; R157, docs/API_USAGE.md) | not yet seen on a screen (device check P10) |
| Exiting playback | Detail screen of the title just watched | Not written | HIG: show a contextually relevant screen | not yet seen on a screen |

### Findings (open)
1. AVKit presents a proposal at `contentTimeForTransition` and counts from the end of playback; our design presents at the credits start with its own countdown. Unverified whether the workaround presents at once.
2. Loading spinner delay and picker focus order are view concerns, not covered by WSL tests.
3. No view in `App/Features` uses these view models yet.
4. Hide-able Discover tab vs HIG "don't hide tab bar buttons" (D-DS6).

## Design check per screen

Rules 1–20 and the Apple page behind each are in docs/DESIGN_REFERENCES.md. **pass** = seen correct in a CI screenshot or
on a device; **fail** = seen wrong, or known wrong from the code; **unproven** = not yet seen. The first screenshots ever
taken (CI run 44401030622, simulator, fixture library, 16 screens) showed the faults listed as "fail (run 44401030622)";
each has a code change that is **not yet seen in a screenshot**, so it stays unproven until the next run. Nothing has been
seen on an Apple TV. Rule 17 (Larger Text, Bold Text, Reduce Transparency, Increase Contrast, Reduce Motion) has not been
tested on any screen: **unproven everywhere**, and nothing was run with those settings.

### App shell and tab bar
- 1 Back/Menu: unproven (Remotes; Tab bars: Menu returns focus to the bar).
- 2 Focus: unproven.
- 3, 9 System focus and glass: unproven; no custom bar background (Adopting Liquid Glass).
- 12 Layout: **fail (run 44401030622)**: seven tabs do not fit; the system fades Settings on the right and the first tab
  scrolls off on Settings. This is the system's documented overflow (Tab bars, tvOS); not fixed, owner decision R167.
- 19 Wording: unproven. Hideable Discover tab vs "don't hide tabs" (Tab bars): D-DS6, open.

### Top-level titles (Home, Search, Movies, Shows, Files, Discover, Settings)
- 10, 12 Typography/consistency: **fail (run 44401030622)**: large centred dim titles on five tabs, none on Home and
  Search. Changed: no visible title on any tab root, title kept as an accessibility header (R166, PROVISIONAL). No Apple
  page states the tvOS rule. Unproven.
- 16 VoiceOver header: unproven (VoiceOver: use headings).

### Home
- 2 Initial focus on the first shelf: unproven.
- 5 Empty / no sources: unproven (ContentUnavailableView).
- 12 Equal cards: **fail (run 44401030622)**: Recently Added mixed tall posters and wide 16:9 cards (unclipped
  artwork). Changed: every card artwork is a clipped 2:3 frame. Unproven.
- 13 Short texts: **fail (run 44401030622)**: subtitles cut with "…". Changed: R165 one-line fitting. Unproven.
- 19 Wording: episode cards titled with the episode code. Changed: show name as title, "S2 E1 · Title" or "S2 E1"
  underneath (unit-tested in WSL; unproven on screen).
- 18 Real names as text ("Dolby Vision", "Dolby Atmos"): pass in code (unit test); unproven on screen.

### Movies and Shows grids
- 12 Equal and aligned: **fail (run 44401030622)**: posters at different heights. Changed: grid cells top-aligned
  (`GridItem(alignment: .top)`), every card reserves the same text lines, artwork clipped 2:3 (Layout; Collections).
  Unproven. Shows grid uses the same layout and card frame.
- 13 Short texts: changed (R165). Unproven.
- 5 No artwork: the grey film / tv symbol on a quaternary fill is the designed placeholder (one function in
  ArtworkView). Unproven.
- 14 SF Symbols: pass in code (`film`, `tv`); unproven on screen.

### Show page and movie detail page
- 1, 2 Push and Back: **fail (run 44401030622)**: not reached. Cause found in code: route destinations attached
  outside the NavigationStack (R168). Fixed in code; unproven.
- 13 Title, facts and badges on one line: changed (R165). Unproven.
- 8 Playback (resume, skip, next episode, system pickers, errors): unproven (Playing video; AVKit). No player
  screenshot exists by design (R161).

### Files (sources and folders)
- 12 Icon against label: **fail (run 44401030622)**: the drive symbol touched the text. The row was already a system
  `Label`; the cause is not proven. Changed: every Files and source row uses one `RowLabel` (system `Label`, primary
  tint). Unproven.
- 1, 2 Folder push and Back to the parent: not reached in run 44401030622 (R168). Unproven.
- 5 Empty / offline / error: unproven.

### Add a Source sheet
- 11 Contrast: **fail (run 44401030622)**: the focused "Search Your Network" symbol disappeared into the focused row.
  Changed: symbol drawn in the primary style so it follows the focused text colour (Lists and tables). Unproven.
- 10 Section headers and sheet title: system `Section` and `navigationTitle`, no custom style; no change (Sheets).
  Unproven.
- 20 Honesty lines: unchanged, as written.

### Search
- 7 System keyboard: unproven. The UI test could not type with `typeText` in run 44401030622 (a test problem, not an
  app one); the test now presses the keyboard keys.
- 5 Three non-result states: unproven (ContentUnavailableView.search).

### Discover
- 5 No key / offline states: unproven.
- 13 Title, year and reason: changed (R165). The "where to watch" sentence keeps wrapping (a sentence, not a short
  text). Unproven.
- 18 TMDB logo only in Settings > About > Data Sources: pass in code (design-lint); unproven on screen.

### Settings
- 2 Focus: not reached past the first row in run 44401030622. Cause: the UI-test focus helper, not the app (the rows are
  buttons; the log found the "Playback" button). Helper fixed; unproven.
- 4 Controls: system `Form`, `Toggle`, `NavigationLink` (Lists and tables). Unproven.
- 6 Destructive actions confirmed with the system alert: unproven (Alerts).

### Top Shelf
- 18, 12: unproven (Top Shelf). Not reachable from UI tests (R161).
