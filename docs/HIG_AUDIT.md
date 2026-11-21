# HIG audit

Standard: native tvOS 27 with Liquid Glass, indistinguishable from the system apps (docs/DESIGN_SYSTEM.md). Method: every screen is compared with the component map in that file.

**Status of every row in every table below: not yet seen on a screen.** Reviewed from source, from Apple's pages and from `scripts/design-lint.sh` (App/ was clean on 2026-11-17 after one comment fix). Nothing is compiled, run in a Simulator or run on an Apple TV; no row may be changed to "seen" until the visual checklist (docs/DEVICE_TEST_CHECKLIST_VISUAL.md) item for it has been done on a device.

## Screens that exist (placeholders)

| Screen / control | Apple component | Deviation from stock | Reason | Status |
|---|---|---|---|---|
| App shell | `TabView` with `Tab` | None | Standard top tab bar; the SDK applies the material. Height 68 pt and top offset 46 pt are fixed by the system (HIG Tab bars) | not yet seen on a screen |
| Tabs | Home, Movies, Shows, Files, Search, Settings (six; OPEN_QUESTIONS R167 option (c), PROVISIONAL) | None (names provisional, OPEN_QUESTIONS 7 and 8) | Single-word names with SF Symbols. The Discover tab is removed; Discover is in Search | fixed in code, verify in next screenshots |
| Discover tab visibility | Removed: there is no Discover tab to hide | None (the D-DS6 deviation is gone) | Show Discover now only decides whether Search shows Discover under an empty field; no tab appears or disappears | fixed in code, verify in next screenshots |
| Search tab | `Tab(role: .search)` + `.searchable`; Discover below the field while it is empty, library results once something is typed | None | Apple: "In apps that use Tab bars, like Photos and Apple TV, search is a dedicated tab"; "display a personʼs recent searches before they start typing" (Searching, https://developer.apple.com/design/human-interface-guidelines/searching). Discover is content under the empty field, not `searchSuggestions` (those are completions of what is typed). Where the system places a search-role tab on tvOS is not stated on Apple's pages; the screenshot job's tab-bar check reports the order | fixed in code, verify in next screenshots |
| Per-tab navigation | `NavigationStack` | None | Menu goes back one level; at the top level it goes Home (HIG Remotes) | not yet seen on a screen |
| Home, Movies, Shows, Files, Discover in Search (empty) | `ContentUnavailableView` (tvOS 17.0+) | None | Standard empty state; Discover's "Discover Needs a Key" wording unchanged | not yet seen on a screen |
| Search | `ContentUnavailableView` + `.searchable` | None | Standard search field | not yet seen on a screen |
| Settings | `Form`, `Section`, `Toggle`, `LabeledContent` | None | Grouped like the system settings (unverified, from memory; V-08); section headers in title case (the Menus page asks title-style capitals for menu items; for section headers: unverified, from memory) | not yet seen on a screen |
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
1. Six tabs, Discover inside Search (R167 option (c), PROVISIONAL; replaces "seven tabs including a hideable Discover tab", D-DS6).
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
| Audio / subtitle delay row | Row in the same menu | New control, not in Apple's player (unverified, from memory) | 50 ms steps, plus or minus 5 s. PROVISIONAL | not yet seen on a screen |
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
4. ~~Hide-able Discover tab vs HIG "don't hide tab bar buttons" (D-DS6).~~ Gone with R167 (c): no Discover tab.

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
  scrolls off on Settings. This is the system's documented overflow (Tab bars, tvOS). Changed (R167 option (c),
  PROVISIONAL): six tabs, Discover folded into Search. Fixed in code, verify in next screenshots: screenshot 02 and the
  "02-home-empty-TABBAR" note (each tab's frame, "TAB BAR OK" or "TAB BAR PROBLEM") show whether all six fit.
- 19 Wording: unproven. The hideable-tab question (D-DS6) is gone: there is no Discover tab.

### Search tab with Discover (R167 option (c), PROVISIONAL)
- Layout: the system search field and keyboard of `.searchable` at the top; below, Discover while the field is empty, library
  results once something is typed (AppLogic `SearchTabContent`, never mixed). No custom search screen. Fixed in code,
  verify in next screenshots (06, 75, 76).
- 1 Back/Menu: Discover has no detail pages (choosing a poster adds it to the watchlist or removes it), so there is no
  Discover page to come back from; Menu at the Search root is the system's (focus to the tab bar). Unproven on a device.
- Library-only rule: Home, Movies, Shows and Files unchanged; Discover's titles appear only here, with "Where to watch" and
  the watchlist marks as before.

### Top-level titles (Home, Movies, Shows, Files, Search, Settings)
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
- #15 4.3 cyan outline on the focused card (51, 52): no custom focus code exists (no border, stroke, tint, focus or hover
  effect in App/); cards use the system `.card` button style, so the outline is the system focus look. Unverified which
  system element draws it (unverified, from memory: the tvOS 26+ focus highlight).
- #15 4.1 (R185): Continue Watching as 16:9 cards; Recently Added stays portrait. Fixed in code, verify in next screenshots.
- #15 4.5: one `GridToolbar` row on Movies and Shows, with "2 shows". Fixed in code, verify in next screenshots.

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
- #15 6.2 (R182): backdrop drawn dimmed, no hand-made scrim (DESIGN_SYSTEM detail-page row: system scroll edge effect,
  HIG Layout); Play has default focus through `defaultFocus(_:_:priority:)` (checked on Apple's page: tvOS 16.0+); the
  cast shelf uses `scrollClipDisabled(_:)` (checked: tvOS 17.0+) so focused entries are not cut. Cast entries and the
  Media Info block take focus with `.focusable()` and no action; whether tvOS draws a focus look for them is unproven.
  Fixed in code, verify in next screenshots.
- #15 5.2 and 5.3 (R189): episode shelves of 16:9 cards (system .card style) per season; Play has default focus; no
  separate season page exists; the episode page is the detail page. Fixed in code, verify in next screenshots.
- #15 8.1 (R183): a title that cannot be played is a system alert over the unchanged page, with "Try Again" when it
  can help and "Done" (was a view inside the player cover). Fixed in code, verify in next screenshots (49, 62).

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
- #30 (OPEN_QUESTIONS R228, PROVISIONAL): no longer a sheet. Run of 20 Nov (10, 11, 17, 94): a third-width card, rows cut,
  the title at the card edge, Home text and the tab bar visible. Changed: a full-screen cover (Modality: full-screen style
  for a multistep task; tvOS dismiss button in the content), one bounded column with the title as the first section's header,
  label and field on one row (Text fields: consistent widths), stacked at accessibility sizes (Layout). Unproven until the
  next screenshots (10 to 21, 93, 94, 99, 100, 110, 111).

### Search
- 7 System keyboard: unproven. The UI test could not type with `typeText` in run 44401030622 (a test problem, not an
  app one); the test now presses the keyboard keys.
- 5 Three non-result states: unproven (ContentUnavailableView.search).
- #15 10.3, screenshot 76 ("No Results for ...", spelling hint): the code draws it with the system `ContentUnavailableView`
  (App/Support/EmptyStateView.swift, via SearchView.swift:41) with the app's own title and message. That is a system view, not
  `ContentUnavailableView.search`. Confirmed in code; the look is from the screenshot only.

### Discover
- 5 No key / offline states: unproven. #15 10.1: the no-key state now uses the `key` symbol instead of the inbox (`tray`)
  (empty-state reason `.needsKey`). Fixed in code, verify in next screenshots.
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

## Against Apple's TV app (guiding principle R332; audit of 20 Nov 2026; no fixes made)

Scope: every screen that the source setup redesign (docs/SOURCE_SETUP_DESIGN.md, R320 to R331) does not change. Method:
the source code of each screen against Apple's pages read on 20 Nov 2026 (apple.com/apple-tv-app; HIG Designing for
tvOS, Materials, Collections, Tab bars, Playing video, Searching, Lockups). The SwiftUI page
`/documentation/swiftui/lockups` and `/documentation/tvui` did not load ("Apple documentation page not found"); the HIG
Lockups page names only TVUIKit views (`TVLockupView`, `TVPosterView`, `TVCardView`, `TVMonogramContentView`,
`TVCaptionButtonView`) and no SwiftUI equivalent. Nothing here was seen on a screen. Where the TV app's own pattern is
not stated on any of those pages, the cell says **UNVERIFIED (from memory)**; a photo of the TV app from the owner
replaces it. Apple's pages do not give shelf spacing, type sizes, the season and episode layout, Continue Watching or Up
Next, the player's info, audio and subtitle panels, or the search keyboard.

| # | Screen | Fault | The TV app's pattern (source) |
|---|---|---|---|
| T1 | Home, Movies, Shows, Discover: portrait cards (`PosterCard`, `SeriesCard`, `DiscoverCard`) | Title and subtitle are always shown, under the artwork and outside the focusable button | Posters: "an optional title and subtitle, which are hidden until the poster comes into focus" (HIG Lockups) |
| T2 | Home Continue Watching, show page episodes (`PosterCard` wide, `EpisodeCard`) | `.buttonStyle(.borderless)` with `.hoverEffect(.highlight)` attached to the artwork by hand, and a custom PreferenceKey (`equalCaptionRow`) to equalise caption heights: a lockup put together by hand | A lockup is content, header and footer that "expand and contract together as the lockup gets focus" (HIG Lockups). SwiftUI equivalent: not named on any page read (UNVERIFIED which SwiftUI style gives it) |
| T3 | All shelves and grids (`CardRow`, `PosterGridLayout`, Discover) | Spacing hard-coded: 40 pt between cards, 100 pt between grid rows, cards sized by `containerRelativeFrame(count: 6 / 3 / 4)` | "leave enough room between lockups to avoid overlapping" and "Use consistent lockup sizes within a row" (HIG Lockups); the TV app's actual spacing and cards per row: UNVERIFIED (no page gives values) |
| T4 | Movies, Shows grid toolbar (`GridToolbar`, `ToolbarIconGroup`) | `GlassEffectContainer` around a custom equal-width `Layout` inside the scrolling content | "Don't use Liquid Glass in the content layer" (HIG Materials). The TV app's Library tab is a split view with the tab bar pinned (HIG Tab bars); its sidebar of categories in place of sort and filter menus: UNVERIFIED (from memory) |
| T5 | Movies, Shows (`FilterChipsRow`) | A row of default buttons with an `xmark` symbol, one per active filter: a chip row the TV app has no equivalent of (UNVERIFIED) | No such control on any page read; TV app: UNVERIFIED (from memory, it has no filter chips) |
| T6 | Movie page, show page (`BackdropView`) | The backdrop is drawn at 40 % opacity (15 % with Reduce Transparency) behind the text, with no dimming layer | "Deliver beautiful, edge-to-edge artwork" (Designing for tvOS); for bright content behind controls "consider adding a dark dimming layer of 35% opacity" (HIG Materials). TV app: artwork at full strength, text over a dimmed lower part: UNVERIFIED (from memory) |
| T7 | Movie page, show page (Play focus) | `.defaultFocus($playFocused, true)` and also `playFocused = true` in a `.task`, a second, programmatic focus move | Focus is moved only by people (HIG Focus and selection, quoted in docs/SOURCE_SETUP_DESIGN.md); `.defaultFocus` alone is the pattern |
| T8 | Movie page, show page (`CastShelf`) | Circles clipped by hand (`clipShape(Circle())`), `.focusable()` with no action, no initials when there is no photo | Monograms "identify people, usually the cast and crew… If an image isn't available, the person's initials appear" (HIG Lockups); selecting a person in the TV app opens their page: UNVERIFIED (from memory) |
| T9 | Movie page (`MediaInfoSection`) | A `Grid` with `Divider`s, the whole block one focusable item | "Consider using a table instead of a collection for text" (HIG Collections); the TV app's "information" section layout: UNVERIFIED (from memory) |
| T10 | Show page (`SeasonsList`) | Every season is its own shelf, stacked down the page; no season picker | TV app: one episode shelf with the seasons as a choice above it: UNVERIFIED (from memory; no page read describes it) |
| T11 | Search (`SearchView`) | No suggestions and no recent searches; results reuse the five-column poster grid | "display a personʼs recent searches before they start typing or offer predictive search suggestions" (`searchSuggestions(_:)`), and "provide a way for people to clear" search history (HIG Searching). Search as a dedicated tab already matches ("In apps that use Tab bars, like Photos and Apple TV, search is a dedicated tab") |
| T12 | Discover in Search (`DiscoverCard`) | Select on the artwork toggles the watchlist; the card's primary action is an action, not opening the title | No page read states it; in the TV app Select on a poster opens the title's page and adding to a list is a secondary action: UNVERIFIED (from memory) |
| T13 | Files and Settings (`PaneColumns`) | Title and summary on the left half, the list on the right half, each half the same width | tvOS Settings: a picture or title on the left, the list on the right: UNVERIFIED (from memory; no page read gives the proportions) |
| T14 | Files, Settings and grids (`FittingText` with `fadesAtRest`, `MarqueeText`) | Overflowing text is masked with a gradient at rest and scrolled by a UIKit `UILabel` marquee on focus: custom drawing | No page read describes how system rows show long text on tvOS (UNVERIFIED). Note: this exists because of the owner's rule S1 (CLAUDE.md); any change needs the owner |
| T15 | Player (`StatsOverlayView`) | A SwiftUI panel with `.regularMaterial` and orange warning values, pinned over the video | tvOS: "Defer to content when displaying logos or noninteractive overlays above video" (HIG Playing video) |
| T16 | Player (`transportBarCustomMenuItems`) | Mark Skip Points (a menu of seven items) and Playback Stats live in the transport bar | "Use a transport control to support a playback-related action …; use custom content tabs to display supplementary information" and "make sure your actions don't take more than a step or two" (HIG Playing video) |
| T17 | Player (no `customInfoViewControllers`) | No content tabs: for an episode there is no Episodes tab under the transport controls | "Below the transport controls, the video player displays content tabs, like Info, Episodes, or Chapters" (HIG Playing video) |
| T18 | Player (`PictureSubtitleOverlay`) | Picture subtitles are drawn by the app in `contentOverlayView` | Custom drawing, but with a reason: the system player does not draw picture-based subtitles (from the code's comments; UNVERIFIED on an Apple page). Kept as a known exception |
| T19 | Player (`ProposalPresenter`) | `automaticAcceptanceInterval = .nan`; the app runs the Up Next countdown itself | System content proposal with its own countdown is the stock pattern (AVKit); why the app runs its own: see docs/PLAYBACK_AUTOSKIP_NOWPLAYING.md. TV app's Up Next look: UNVERIFIED |
| T20 | Plex sign-in code page (`PlexSetupView`; R302, reported by the Plex work under R301) | A full-screen page with the sign-in code as its largest text, not a Settings form of rows; no Apple page read shows a tvOS Settings page of this shape | HIG Managing accounts, tvOS: "**Prefer letting people use another device to sign up or authenticate.**" and "**Minimize data entry.** If you need to gather more than a small amount of information, ask people to visit a website from another device" (re-read 21 Nov 2026; a code entered on another device matches both). The page's shape against the TV app or tvOS Settings: UNVERIFIED |

Plex screens (R301): the server list (R303) uses the same TaskPage Form and row style as Add a Source, and the "cannot
play this file" message (R305) the existing playback alert: no gap found. Plex adds no library, detail or player screens of
its own, so T1 to T19 apply to them unchanged.

Matches (no gap found in code): the system `TabView` tab bar with Search as a tab (HIG Tab bars, Searching); one
`NavigationStack` per tab; the stock `AVPlayerViewController` with `externalMetadata` (HIG Playing video: "Use the system
video player"); audio and text subtitle choice left to the system player's menus; skip intro as the system
`contextualActions`; system `.contextMenu` on cards; system alerts and confirmation dialogs; `ContentUnavailableView`
for empty states. Liquid Glass appears only where the system applies it (tab bar, focused buttons and images: HIG
Materials, tvOS), except T4.

### Status of T1 to T20 (fixes of 21 Nov 2026, presentation only)

Apple sources read 21 Nov 2026: HIG Designing for tvOS, Lockups, Collections, Materials, Playing video, Searching, Tab bars;
SwiftUI `PrimitiveButtonStyle.borderless`, `HoverEffect.highlight` and the sample "Creating a tvOS media catalog app in
SwiftUI" (the SwiftUI page `/documentation/swiftui/lockups` still does not load: "Apple documentation page not found").

| # | Status |
|---|---|
| T1 | Built (R335): portrait cards are one `.borderless` lockup with the title inside the button. Titles stay visible at rest (Apple's SwiftUI sample shows them; rule S1); hiding them until focus is R335 alternative (a). |
| T2 | Matches Apple's sample (`.borderless`, `hoverEffect(.highlight)` on a custom artwork view): no change. The caption-height key stays (R264). |
| T3 | Matches Apple's sample (40 pt, `containerRelativeFrame(count: 6, spacing: 40)`): no change. 100 pt between grid rows: UNVERIFIED. |
| T6 | Built (R336): the backdrop at full strength under the system `regularMaterial` (Apple's sample, product page). The 35 % dimming-layer citation above is withdrawn: on the Materials page it is for components with clear Liquid Glass. |
| T7 | Not changed: the second focus request fixes a measured run (#25 B10, the tab bar kept the focus on a page pushed at launch). Removing it would need a run that proves `defaultFocus` alone is enough (R338). |
| T8 | Built (R336): initials in place of a missing photo (HIG Lockups, Monograms). Selecting a person still does nothing (no person page; R338). Decided by the owner, 21 Nov 2026: selecting a cast member opens a page of their titles from the library (R341). Built (R341): each cast entry opens the person's page, their titles in the library from stored details only (no online lookup); look on tvOS 27 UNVERIFIED. |
| T9 | Not changed: Media Info is already text in two columns, not a collection; the `LabeledContent` form was replaced for a measured reason (#25 B6). |
| T10 | Not built: a season picker changes the show page's structure; the TV app's pattern is not on any Apple page read (R338). Decided by the owner, 21 Nov 2026: seasons as a row of tabs above the episode list (R339). Built (R339): the system segmented picker above one episode list, a menu picker above seven seasons. |
| T11 | Built in part (R337): system `searchSuggestions` from the titles already found. Recent searches (storage) and landscape result lockups (a backdrop lookup per result, more online requests) are for the owner (R338). Decided by the owner, 21 Nov 2026: recent searches on this Apple TV only, with Clear Recent Searches (R343); wide result cards not built, kept as an alternative. |
| T12 | Not built: Select on a Discover card toggling the watchlist is behaviour, not presentation (R338). Decided by the owner, 21 Nov 2026: Select opens the title; adding to Up Next moves to the context menu (R342). |
| T4 | Not changed: owner decision R258 (Decided) is not reopened (R338). |
| T5 | Not changed: the TV app's pattern for active filters is not on any page read (R338). Decided by the owner, 21 Nov 2026: replace the chips with a system Menu in the toolbar, sort and filters together (R344). |
| T13 | Not changed: no Apple page read gives the proportions (R338). Decided by the owner, 21 Nov 2026: no change now; revisit after the owner sees it on the Apple TV. |
| T14 | Not changed: the owner's rule S1 (R338). Decided by the owner, 21 Nov 2026: no change now; revisit after the owner sees it on the Apple TV. |
| T15 | Not changed: the player is being changed by the Plex work now; moving the overlay is for the owner (R338). Decided by the owner, 21 Nov 2026: the stats move into the info panel, every stat shown, most important first (R340). Built (R340): the stats are a Playback Stats tab of the info panel; the overlay is gone. |
| T16 | Not changed: moving Skip Points and Stats into content tabs is a change to the player's actions (R338). Decided by the owner, 21 Nov 2026: Playback Stats leaves the transport bar for an info panel tab (R340); the Mark menu stays. Built (R340): Playback Stats left the transport bar; the Mark menu stays there. |
| T17 | Not changed: an Episodes tab needs new data and behaviour in the player (R338). Decided by the owner, 21 Nov 2026: an Episodes tab in the info panel (R340). Built (R340): an Episodes tab with the season's episodes; choosing one plays it. |
| T18 | Kept as a known exception: the system player does not draw picture subtitles. Decided by the owner, 21 Nov 2026: unchanged. |
| T19 | Not changed: playback behaviour (R338). Decided by the owner, 21 Nov 2026: the system Up Next (`AVContentProposal`), and the dropped advance step fixed (R340). Built (R340): the system Up Next (`automaticAcceptanceInterval`, the card an `AVContentProposalViewController` subclass) and the advance that was dropped. |
| T20 | Not changed: the Plex work's own decision (R302, R338). Decided by the owner, 21 Nov 2026: no change now; revisit after the owner sees it on the Apple TV. |
