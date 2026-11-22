# Visual audit against the Apple TV app, picture against picture (21 Nov 2026)

This audit replaces docs/AUDIT_INVENTED_UI.md and docs/AUDIT_AGAINST_REFERENCE_PACK.md for every visual question
(spacing, sizes, layout, look). Those two stay valid only for "is there a system component for this" questions.

Why it was redone: the owner rejected the screenshot run on fd9731f ("all of the icons are terribly spaced out and
nothing looks like the Apple TV app at all"; the episode screen "did not follow the Apple TV app as a strict design
guideline at all"). The earlier audits compared code with Apple's text. This one compares our screenshots with Apple's
own pictures of the TV app on tvOS 26, measured.

Scope and honesty:

- Audit only. No app code was changed. Nothing was compiled or run (R318). No Apple picture is copied into the repo;
  only addresses and descriptions.
- Our pictures: the screenshot run on **fd9731f** (R390), 1920 × 1080 px, so 1 px = 1 pt. A few screens were only in
  the **earlier run** of 21 Nov (before R384 to R390, with the old top tab bar); those are marked "earlier run".
- Code causes are read at **fd9731f**. Another session has uncommitted R391 edits in the working copy (badge spacing,
  row labels, the toolbar, the season list, episode cards and more, plus a new `VisualSpacing.swift`). That work is
  **not audited here**; some findings below may already be addressed there, UNVERIFIED.
- Apple's pictures were measured by scaling them to 1920 pt wide: the support guide's images (1146 px) × 1.675,
  apple.com images (1208 px) × 1.589, HIG images (1280 px) × 1.5. Measurements from Apple pictures are ± about 5 pt.
- Nothing about the TV app is described from memory. Where no Apple picture shows a screen, the screen is marked
  **NO REFERENCE** and is on the list in section 5.

Severity: **breaks the look** (a person would see at once that it is not the TV app), **noticeable**, **small**.

## 1. Reference list: every address opened

Short names used in the findings are in the first column.

| Ref | Address | What it gave | Failed / missing |
|---|---|---|---|
| A0 | https://support.apple.com/guide/tv/welcome/tvos | The guide's start page and its page list. The default edition is now tvOS 27; the tvOS 26 edition is reached with `/26/tvos/26` at the end of each page address. | No screen picture of its own. Plain `curl` was refused (HTTP 429); the pages were read in a browser instead. |
| A1 | https://support.apple.com/guide/tv/tv-app-at-a-glance-atvb6339cf5a/26/tvos/26 | **Home** picture (tvOS 26, image 6e9290b3, a comedy series featured): title at x 79; metadata "TV Show · Comedy" with the rating badge about 10 pt after the text; one line of synopsis; a Play capsule about 228 × 67 pt, then icon-only circles (about 64 pt) about 22 pt apart; Play's bottom at about 802; the "Continue Watching" header at about 910 to 923 (about 105 pt below the buttons), smaller than ours and grey; 16:9 cards about 318 pt wide, gap about 40, five across plus a peek; the collapsed sidebar pill "‹ ⌂ Home" at top left (x 35 to 223, y about 79); page dots above the shelf; artwork full bleed. The tvOS 27 edition (image 7b654044) has the same layout. | |
| A2 | https://support.apple.com/guide/tv/navigate-the-apple-tv-app-atvb59b423ba/26/tvos/26 | **Sidebar** picture (image 11925e5a; tvOS 27 image 6acc7afb): a rounded material panel x 37 to 372 (335 wide); the profile and the time at the top; then Search, Home, Apple TV, two sports rows, Store, Library (Search first); icon at x about 69 to 90, label at x 119 (about 29 pt from the icon); row pitch about 78; the focused row a white capsule; the page dimmed behind. Text: opened with Back or a swipe, closed by a swipe right or a choice. | |
| A3 | https://support.apple.com/guide/tv/view-movies-and-tv-shows-in-your-library-atvba6a2c11c/26/tvos/26 (page id atvba6a2c11c) | **Library** picture (image 14b68dda): flat dark grey background; the "‹ Library" pill; a category list at the left (icon right edge to label about 25 pt, row pitch about 75, a "Genres" header); a poster grid of 6 columns, posters about 201 × 297 pt, gap about 39, row gap about 69; **no captions under the posters**. | |
| A4 | https://support.apple.com/guide/tv/control-video-playback-atvb7944597f/26/tvos/26 | **Player controls** (image cf29160a): "S1, E1 • episode name" small above the show's name, large and bold; a full-width scrub bar; times under it; capsule tabs Info / InSight / Continue Watching under the bar; round icon buttons (Subtitles, Audio, Picture in Picture) at the top right. **Show page** behind Picture in Picture (image 0f124851, a sci-fi series): title logo at x 79; "TV Show · Sci-Fi · Adventure" plus rating; a 4-line synopsis at most about 658 pt wide; an info line "2023 · 59 min" with badges (4K, Dolby Vision, Dolby Atmos, CC, SDH, AD) about 12 to 15 pt apart; a "Play First Episode" capsule about 350 × 64, then a + circle and a details circle about 27 pt apart; the episode shelf peeking at about 1039, cards about 409 wide, gap about 39. Multiview pictures 4fceac3a and 63c6c988 (not used). | |
| A5 | Support guide page "Find things to watch" (tvOS 26) | Only small icons. | **No picture of the TV app's Search screen.** |
| B1 | https://www.apple.com/apple-tv-app/ | Image `tv_screen_mission_imposible__bvxq3ixq1i82_large.jpg` (under https://www.apple.com/v/apple-tv-app/af/images/overview/): a **movie page**: title logo at x 81; "Movie · Action · Adventure" plus rating at y about 721; a 2-line synopsis at most about 650 pt wide; an info line with badges 10 to 14 pt apart; Buy and Rent text capsules (about 67 high, about 22 apart) then + and details circles; a "Starring … Director …" block at the right (x about 1430); a shelf peeking at about 1041; full-bleed key art darkened at the left. Image `hero__lgyucsgf7t2m_large.jpg`: the sidebar open. Image `tv_screen_the_studio_2`: key art only. | |
| B2 | https://www.apple.com/os/tvos/ | — | **Page Not Found.** https://www.apple.com/tvos/ redirects to the home page. |
| C1 | https://developer.apple.com/videos/play/wwdc2024/10207/ | Transcript: the landing page's full-bleed image with a gradient; shelves on the safe area with a peek; in a lockup "the image lifts, the text moves down"; search as a 4-column grid with 40 pt spacing; the sidebar shrinks to "the same compact indicator from the TV app". Frames: 3:01 top tab bar and 6 portrait posters (gap about 40) with titles under them; 13:35 search field, keyboard row, suggestion chips (search terms only), 4 columns of 16:9 cards with a one-line centred title; 14:31 the system sidebar; 14:40 the collapsed "‹ Up Next" pill. | **Every frame shows Apple's sample app, not the TV app.** |
| C2 | https://developer.apple.com/documentation/SwiftUI/Creating-a-tvOS-media-catalog-app-in-SwiftUI | Two pictures: lockups (including a circular "Shaped" person lockup) and card lockups. Code: the hero at 0.8 of the height, the description in a `fullScreenCover`. | No picture of a product page or of the description page. |
| D1 | https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos | One stylised illustration. | No app picture. |
| D2 | https://developer.apple.com/design/human-interface-guidelines/layout | The safe area illustration (60 pt top and bottom, 80 pt sides) and grid illustrations for 2 to 9 columns. | |
| D3 | https://developer.apple.com/design/human-interface-guidelines/lockups | `lockups-monogram@2x.png`: a row of circular person lockups; the focused one grows as a circle with a circular shadow; name and subtitle centred under it. `lockups-poster@2x.png`: a product page with a shelf. | |
| D4 | https://developer.apple.com/design/human-interface-guidelines/alerts | `alert-tvos@2x.jpg`: a small rounded material alert about 576 pt wide: title, a one-line description, two buttons side by side. | |
| D5 | https://developer.apple.com/design/human-interface-guidelines/materials | `materials-tvos-media-player@2x.png` (the Destination Video player's Info tab): capsule tabs Info / InSight / Continue Watching; a material panel with a thumbnail, the title, a 3-line description, "Science Fiction 33 min"; buttons "From Beginning" and "Go to Show" at the right. | |
| — | Every other page in docs/REFERENCE_PACK.md | Read for text earlier in this session (docs/AUDIT_AGAINST_REFERENCE_PACK.md). | **Not re-opened for pictures** in this audit. |

## 2. The owner's eleven points, measured

| # | Owner's point | Result |
|---|---|---|
| 1 | Badges 65 to 72 pt apart | **Confirmed.** 70 to 72 pt between badges (07, 77, 106); 59 to 60 pt between the facts text and the first badge. Apple: 10 to 15 pt (B1, A4). |
| 2 | List-row icon 60 to 80 pt from its label; Add a Source has an icon on one row only | **Confirmed, measured 66 pt** (Settings 1048 → 1114, Files the same, Add a Source 428 → 494). Apple: about 25 pt (A3), about 29 pt (A2). Only "Search Your Network" has an icon: confirmed. |
| 3 | Three toolbar buttons of different sizes, far apart; the count covered | **Confirmed.** 108 × 66, 99 × 76, 100 × 66, gaps 60 (larger text: 132 × 74, 119 × 102, 123 × 66). The focused first card (top 243) reaches the "7 movies" line (y about 227); in 68 the lifted card covers it. |
| 4 | Movie page: full-width synopsis, loose time-left line, cast circles in squares with a square focus that clips, the Information table | **Confirmed.** Synopsis 1692 to 1754 pt wide; "29 min left" / "1 h 13 min left" on its own line; faint square outlines around 120 pt circles; the square focus seen on the show page's cast (77-show); Information: badge row then Grid rows with dividers, NO REFERENCE. |
| 5 | Show page: stretched season picker, logo off the content edge, gaps in episode captions | **Confirmed.** Picker x 80 to 1840 (1760 pt); logo starts at x 150 (content edge 80: 70 pt off); about 70 pt empty band between the episode title line and "43 min". |
| 6 | Episode page (no picture) | From code and the run's accessibility tree: see E1 and E2. The large title is the **show's name**; the episode's own title is not on the page. |
| 7 | Full synopsis: plain black, edge to edge | **Confirmed.** Black; title at x 96; text x 96 to 1824, about 10 lines. |
| 8 | Home: first shelf header 20 pt under the buttons; featured title cut under larger text | **Confirmed, 20 to 23 pt** (buttons' bottom about 843, header top about 866). Apple about 105 pt. Title truncated with "…" in 80. |
| 9 | Search: focused card covers its title; titles at three sizes; "Recent Searches" drawn like a term | **Confirmed** for the cover (Discover card, 75) and "Recent Searches" (76). Sizes: **two sizes inside one Discover row, a third in the results grid**: confirmed. |
| 10 | Playback failure alert with 14 lines | **Confirmed from code only** (12 to 18 lines for a usual failure). No picture of this version: the only alert picture is from the earlier run, before R386, with 3 lines. |
| 11 | Player: mixed separators; the Info panel for an episode | **Confirmed.** "2026 • Sample Show 1 · S1, E1" mixes "•" and "·". The Info panel shows "Sample Show 1 · S1, E1" as its heading, no episode title, no description, about 150 pt of empty band. |

## 3. Findings by screen

Each finding: our picture and the place (points on 1920 × 1080); what ours does; what Apple's does, with the
address; the view and file that draw it and the likely cause (at fd9731f); severity.

### 3.1 Sidebar and Home

**H1. Sidebar order and contents.** small
- Ours (02-home-empty): panel x 37 to 391 (354 wide), rows Home, Search, Settings, a "Library" header, Movies, Shows,
  Files; icon x 72 to 101, label x 120 (about 19 pt), pitch 76.
- Apple ([A2](https://support.apple.com/guide/tv/navigate-the-apple-tv-app-atvb59b423ba/26/tvos/26)): panel 335 wide,
  profile and time at the top, **Search first**, no Settings row, icon to label about 29 pt, pitch about 78.
- Cause: the tab order of the app's `TabView` (the system sidebar draws the rest). Sizes are close; the order differs.

**H2. The sidebar is open in many pictures, over the page.** noticeable
- Ours: 03, 30, 70, 75-search-discover-cards, 77-movie-long-synopsis, 07-shows-toolbar-larger-text, 95: the sidebar
  open with the focus on Home (or the page's own row) while another page is shown; in 30 and 70 it hides the left
  column's text ("…folders, with their folders exactly as they"); in 95 it covers the search field.
- Apple (A2): the sidebar opens with Back or a swipe and closes when a choice is made; the page is dimmed behind it.
- Cause: either the screenshot steps (where the focus was when the picture was taken) or the R388 focus behaviour.
  UNVERIFIED which.

**H3. Featured buttons: text capsules far apart.** breaks the look
- Ours (50-home-rows): Resume x 76 to 288 (72 high), "··· More" text capsule x 344 to 515, gap 56.
- Apple ([A1](https://support.apple.com/guide/tv/tv-app-at-a-glance-atvb6339cf5a/26/tvos/26)): Play capsule about
  228 × 67, then **icon-only circles** about 64 pt, about 22 pt apart.
- Cause: App/Features/Home/HomeFeaturedView.swift, `ActionRow` with `ActionLabel("More", systemImage: "ellipsis")` in
  `.bordered`; the row's spacing. Shared fault SF2.

**H4. First shelf header 20 to 23 pt under the buttons, large and white.** breaks the look
- Ours (50-home-rows): buttons end at about 843; "Continue Watching" starts at about 866; the header is large and white.
- Apple (A1): about 105 pt between Play's bottom (about 802) and the header (about 910); the header smaller and grey.
- Cause: HomeFeaturedView.swift: the `VStack` ends with the `ActionRow` and nothing below it; the shelf header style in
  HomeRows. Shared fault SF7.

**H5. No synopsis line on the featured title; formats as text.** noticeable
- Ours (50-home-rows): title, then "1 h 34 min left · 4K · Dolby Vision · Dolby Atmos" as one text line, then buttons.
- Apple (A1): "TV Show · Comedy" plus the rating badge, then one line of synopsis, then buttons.
- Cause: HomeFeaturedView.swift has no synopsis; `FittingLine(featured.metadata)`.

**H6. Continue Watching cards three across.** breaks the look
- Ours (50-home-rows): cards 560 pt wide, 3 across.
- Apple (A1): 16:9 cards about 318 wide, gap about 40, five across plus a peek.
- Cause: the shelf's column count in HomeRows (the constant was not read: UNVERIFIED which).

**H7. Featured title cut under Larger Text.** breaks the look
- Ours (80-larger-text-home): the title ends with "…".
- Apple (A1): the title (logo) is never cut.
- Cause: App/Shared/TitleHeader.swift:26 to 30, `.lineLimit(1)` with a `minimumScaleFactor` floored at title1's
  minimum: when the floor is reached the line is truncated (also rule S1).

### 3.2 Movies and Shows grids and toolbars

**G1. Three toolbar buttons of three sizes, 60 pt apart.** breaks the look
- Ours (07-movies-toolbar, notes 07-movies-toolbar-GROUPS.txt): Sort and Filter {1413, 138, 108 × 66}, Saved Views
  {1581, 133, 99 × 76}, More {1740, 137, 100 × 66}, gaps 60. Larger text: 132 × 74, 119 × 102, 123 × 66.
- Apple ([A3](https://support.apple.com/guide/tv/view-movies-and-tv-shows-in-your-library-atvba6a2c11c/26/tvos/26)):
  no toolbar; a category list at the left. Our own rule D2 asks one height.
- Cause: App/Shared/GridToolbar.swift: the system `ToolbarItemGroup(placement: .primaryAction)` with three different
  controls (`Menu` with an icon-only `ToolbarSymbol`, the Saved Views menu, the More menu); each gets its own system size.

**G2. The count line is covered by the lifted card.** breaks the look
- Ours (07-movies-toolbar, 68-card-long-press-move): "7 movies" at y about 227, the first card row at 243; 53 pt from
  the toolbar to the first row (note 07-movies-toolbar-GAP.txt, minimum 60); the lifted card covers half the line in 68.
- Apple (A3): no count line.
- Cause: GridToolbar.swift `GridCountLine`, plain secondary text right above the grid with no room for the focus growth.

**G3. Five columns with captions.** breaks the look
- Ours (07-movies-toolbar): 5 columns, posters 320 × 480, gap 40, captions of title, year and badges.
- Apple (A3): 6 columns, posters about 201 × 297, gap about 39, row gap about 69, **no captions**.
- Cause: the poster grid's column count and PosterCard's captions. Shared fault SF4.

**G4. Caption badges 72 pt apart.** breaks the look
- Ours (07-movies-toolbar): "4K" x 96 to 144, "Dolby Vision" x 216 to 370 (gap 72); HDR10 gap about 71.
- Apple ([B1](https://www.apple.com/apple-tv-app/), A4): 10 to 15 pt.
- Cause: App/Shared/ProductPageParts.swift `BadgeGroups`: `HStack {` with no spacing (the system default, wide on
  tvOS) plus `groupGap`; used by PosterCard.swift:102. Shared fault SF1.

**G5. No category list.** small
- Ours: Movies and Shows are separate sidebar rows, each a full-width grid.
- Apple (A3): one Library page with a category list at the left and the grid at the right.
- Cause: the app's structure (R359 sidebar). A decision for the owner, not a spacing fault.

### 3.3 Movie page

**M1. Metadata line spread.** breaks the look
- Ours (106-default-movie-detail): "2021 · 2 h 1 min" ends at x 292; PG-13 at 352 (gap 60); 4K at 499 (59); Dolby
  Vision at 620 (72); Dolby Atmos at 846 (72). The same in 77, 84 and 89.
- Apple ([B1](https://www.apple.com/apple-tv-app/)): "Movie · Action · Adventure" with the rating about 10 pt after it;
  the badge line 10 to 14 pt apart.
- Cause: ProductPageParts.swift `ProductMetadataLine.line`: `HStack {` with no spacing (about line 27), plus
  `BadgeGroups`. Shared fault SF1.

**M2. Synopsis across the full width.** breaks the look
- Ours (106, 77-movie-long-synopsis): x 80 to 1772/1834 (1692 to 1754 pt), 3 lines.
- Apple (B1): at most about 650 pt wide; A4: about 658 pt.
- Cause: App/Features/Detail/ItemDetailContentView.swift `SynopsisLink`: a `.plain` button with
  `Text.font(.callout).lineLimit(3)` and no width limit. Shared fault SF3.

**M3. A loose "time left" line.** noticeable
- Ours (77, 106): "29 min left" / "1 h 13 min left" on its own line between the synopsis and the buttons.
- Apple (B1, A4): no such line on a product page.
- Cause: ItemDetailContentView.swift, `StatusText(timeLeft)` in the hero `VStack`.

**M4. Action buttons: text capsules about 60 pt apart.** breaks the look
- Ours (106): Resume x 76 to 288, Start Over 344 to 580, More 640 to 811.
- Apple (B1): text capsules about 67 high, about 22 apart, then + and details as **icon circles**; A4 the same with
  "Play First Episode".
- Cause: ItemDetailContentView.swift `actions`: `ActionRow` with Play/Resume `.borderedProminent`, Start Over
  `.bordered`, the Versions and Extras menus and `moreMenu` (`ActionLabel("More", systemImage: "ellipsis")`). Shared
  fault SF2.

**M5. Cast: circles inside squares, a square focus that clips the circle, wide pitch.** breaks the look
- Ours (77-movie-long-synopsis, 106, 84): 120 pt circles at x 139, 419, 702, 985 (pitch about 283) with faint square
  outlines; on focus (77-show-long-synopsis-cast, Actor 3) a rounded-square highlight x 682 to 842 clips the circle.
- Apple ([D3](https://developer.apple.com/design/human-interface-guidelines/lockups), lockups-monogram): the focused
  person grows **as a circle** with a circular shadow; name and role centred under it. C2's "Shaped" person lockup is
  circular too.
- Cause: ItemDetailContentView.swift `CastShelf`: `CastPhoto.frame(width: photoSize, height: photoSize)
  .hoverEffect(.highlight)` on a square frame inside a `.borderless` `NavigationLink`; the label's `.padding()` and the
  name's width set the pitch (`LazyHStack(spacing: 40)`). Shared fault SF5.

**M6. Information: badge row on top of the table.** noticeable
- Ours (78-movie-no-synopsis, 77-movie-long-synopsis-cast): an "Information" header, a badge row (4K / HDR10+ / Dolby
  Atmos / 5.1 / HEVC / MKV, about 70 pt apart) at y 891 to 921, then the "Resolution" row at 942, then Grid rows with
  dividers across x 80 to 1840.
- Apple: **NO REFERENCE** for the TV app's information section.
- Cause: ItemDetailContentView.swift `MediaInfoSection` with `BadgeRow` (line 316). The spacing part is SF1.

**M7. No cast and crew block on the first screen.** noticeable
- Ours (106): cast starts below the hero at about y 928.
- Apple (B1): a "Starring … Director …" text block at the right of the first screen (x about 1430).
- Cause: the hero has no such block (ItemDetailContentView.swift).

**M8. A key-missing status line in place of the synopsis.** small
- Ours (78-movie-no-synopsis): "Synopsis needs your TMDB key…".
- Apple: nothing comparable (B1 always has a synopsis).
- Cause: `StatusText(OnlineLookupText.detailsNeedKey)`. Kept by our honesty rule; only its place is in question.

### 3.4 Show page

**S1. Title logo 70 pt in from the content edge.** breaks the look
- Ours (108-default-show-page, 91-larger-text-show-page): the "SAMPLE" logo's letters start at x 150; everything else
  starts at x 80.
- Apple (A4 Silo page, B1): the logo at x 79 to 81, on the same edge as the text below.
- Cause: App/Shared/TitleHeader.swift draws the logo image fitted (`.resizable().aspectRatio(contentMode: .fit)`,
  `TitleLogoRules.fittedSize`); the likely cause is the transparent margin inside the logo file, drawn as part of the
  image. UNVERIFIED (the sample logo file was not inspected).

**S2. "2 Seasons" and the rating 60 pt apart.** noticeable
- Ours (108): "2 Seasons" then TV-14 about 60 pt later.
- Apple (A4): "TV Show · Sci-Fi · Adventure" with the rating right after it.
- Cause: App/Features/Shows/SeasonsList.swift:46 `ProductMetadataLine` (M1). Shared fault SF1.

**S3. Season picker stretched across the page.** breaks the look
- Ours (108, 91): a segmented picker x 80 to 1840 (1760 pt) with "Season 1" and "Season 2" each half the page; the
  episode cards start below it at about 1003.
- Apple (A4, image 0f124851): the first screen shows "Play First Episode" and the episode shelf peeking at about 1039;
  **no season picker visible; NO REFERENCE** for how the TV app picks a season.
- Cause: SeasonsList.swift:105 to 115, `Picker("Season").pickerStyle(.segmented)` for 2 to 7 seasons; a segmented
  picker fills the width it is given.

**S4. Empty band in episode captions.** noticeable
- Ours (77-show-long-synopsis-cast): the title line, then about 70 pt of nothing, then "43 min" and [1080p] about 60 pt
  apart.
- Apple (A4): episode cards about 409 wide with a gap of about 39 (ours 410 and 40: a match); the caption text is too
  small in Apple's picture to measure.
- Cause: App/Features/Shows/EpisodeCards.swift:87 to 100: `CardCaption` takes the row's tallest caption height (height
  equalising), and the runtime and badges sit in an `HStack` with no spacing. Shared faults SF1, SF4.

### 3.5 Episode page (no picture; from code at fd9731f and the run's accessibility tree)

**E1. The page's large title is the show's name; the episode's title is missing.** breaks the look
- Ours (notes 22-episode-page-EPISODE.txt and 24-player-info-panel-HIERARCHY.txt, which holds the episode page's tree):
  first screen, top to bottom inside the hero (at least 0.8 of the height, content at the bottom left, the backdrop the
  episode still): a button with the show's name {80, 455, 256 × 66}; "S1, E1" {80, 535}; a large text title
  {80, 582, 438 × 82} whose label is **"Sample Show 1"**; the metadata line {80, 666} ("43 min, TV-14, 1080p, HDR10,
  Dolby Digital Plus", spread as M1); content advice; a 3-line full-width synopsis; the time-left line; Play, Start Over
  and More (Play at about y 718); the "Season 1" row at y 842. The note says "EPISODE PAGE PROBLEM: no title". After one
  scroll: the season's other episodes (the same cards as S4), Cast (M5), Information (M6). It is the movie page with
  the show's name on top.
- Apple: **NO REFERENCE** for the TV app's episode page. The closest Apple picture is the player
  ([A4](https://support.apple.com/guide/tv/control-video-playback-atvb7944597f/26/tvos/26), cf29160a): the show's name
  large, "S1, E1 • episode name" small above it, so the episode's name is always shown.
- Cause: ItemDetailContentView.swift: for an episode the hero adds `NavigationLink(series, value: Route.series(…))` and
  `FittingText(code, style: .headline)` above `TitleHeader`, and the title passed to `TitleHeader` is the show's name
  per the tree (where it comes from was not traced: UNVERIFIED).

**E2. A bordered button above the title.** noticeable
- Ours: the show's name as a 256 × 66 button above everything.
- Apple: no picture shows a button above a title on any TV app page (A1, A4, B1).
- Cause: the `NavigationLink(series…)` in the hero (E1).

### 3.6 Full synopsis

**F1. Plain black page, text edge to edge.** breaks the look
- Ours (77-movie-long-synopsis-page, 77-show-long-synopsis-page): black; the title at x 96, y 70 to 120; the text
  x 96 to 1824, about 10 lines.
- Apple: **NO REFERENCE** for the TV app's description page. The sample (C2) opens its description in a
  `fullScreenCover` (no picture). Every Apple product-page picture keeps the synopsis at most about 650 pt wide (B1, A4).
- Cause: `LongTextPage` shown in `taskCover` from `SynopsisLink` (ItemDetailContentView.swift); no width limit, no
  material or artwork. Shared faults SF3, SF8.

### 3.7 Cast shelf and person page

The cast shelf is M5.

**P1. Person page: a poster grid with captions, the focused card touching the subtitle.** noticeable
- Ours (79-person-page): "Sample Actor 1" and "6 titles" at x 80; a 5-column poster grid with captions and badges
  72 pt apart; the focused card's top (y 167) touches "6 titles" (y 150 to 165). No photo of the person.
- Apple: **NO REFERENCE** for the person page (D3 shows circular person lockups only).
- Cause: the person page's grid uses the same PosterCard as G3; the count line sits right above it as in G2.

### 3.8 Search and Discover

**Q1. "Recent Searches" drawn as a term.** noticeable
- Ours (76-search-recent): "Recent Searches" is a chip like "Sample Movie 2".
- Apple ([C1](https://developer.apple.com/videos/play/wwdc2024/10207/) at 13:35, the sample app): the chips are
  search terms only. **NO REFERENCE** for the TV app's own search screen (A5 has no picture).
- Cause: App/Features/Search/SearchView.swift:40 to 53: a `Section(RecentSearches.heading)` inside
  `.searchSuggestions`, which tvOS draws as one more chip.

**Q2. Results as 5 portrait posters with 3-line captions.** breaks the look
- Ours (76-search-results): 5 columns of 320 × 480 posters, captions of 3 lines, badges about 72 apart.
- Apple (C1 13:35 and the transcript, sample app): 4 columns of 16:9 cards, 40 pt apart, a one-line centred title.
- Cause: SearchView.swift results use `PosterGrid(cards:)`. Shared faults SF1, SF4.

**Q3. Discover: the lifted card covers its own title.** breaks the look
- Ours (75-discover-card-menu): the focused card grows down to y 877 over its title at about 860.
- Apple (C1 transcript: "the image lifts, the text moves down"; [D3](https://developer.apple.com/design/human-interface-guidelines/lockups)).
- Cause: App/Features/Discover/DiscoverView.swift `DiscoverCard`: `NavigationLink { … } label: { ArtworkView }
  .buttonStyle(.card)` with the title, detail and where-to-watch text **outside** the button, so they do not move.
  Shared fault SF6.

**Q4. Card titles at three sizes.** noticeable
- Ours (75-search-discover-cards): "Sample Suggested Show" drawn smaller than "Sample Suggestion 2" in the same row; the
  results grid uses a third size.
- Apple (C1): one title size in a row.
- Cause: `FittingText` shrinks each title on its own to fit its card; DiscoverCard and PosterCard use different styles.

**Q5. Discover captions of four lines.** noticeable
- Ours (75): title, detail, and a where-to-watch line of up to 3 lines (`.caption2`, `lineLimit(3)`).
- Apple (C1): a one-line title.
- Cause: DiscoverView.swift `DiscoverCard` captions. Shared fault SF4.

### 3.9 Files

**FI1. Icon 66 pt from its label.** breaks the look
- Ours (71-files-root, 105): the drive icon, then the label 66 pt later.
- Apple (A3): about 25 pt in the library's list; A2: about 29 pt in the sidebar. **NO REFERENCE** for a files screen.
- Cause: App/Shared/LayoutParts.swift:16 `SlotLabel`: `HStack {` with the default spacing and a fixed `slot` frame for
  the icon; used by RowLabel (Settings, Files, Add a Source). Shared fault SF1.

**FI2. The source's name twice.** small
- Ours (71-files-root): the row title "Sample Library" with the subtitle "Sample Library".
- Apple: NO REFERENCE.
- Cause: the Files root row's subtitle falls back to the name (code not traced: UNVERIFIED).

### 3.10 Settings and its panes

**ST1. Icon 66 pt from its label.** breaks the look
- Ours (30-settings): icon x 1015 to 1048, label x 1114.
- Apple: **NO REFERENCE** for the TV app's settings; the spacing reference is A3 (about 25 pt) and A2 (about 29 pt).
- Cause: `SlotLabel` (FI1). Shared fault SF1.
- Settings' sub-pages were only in the earlier run (31 to 43, before R384); not compared again.

### 3.11 Add a Source

**AS1. An icon on one row only.** noticeable
- Ours (110-default-add-source): only "Search Your Network" has an icon (wifi x 395 to 428, label at 494: 66 pt);
  the other rows have none.
- Apple: **NO REFERENCE**.
- Cause: App/Features/Sources/SourceKindListView.swift:23: only `RowLabel("Search Your Network", systemImage: "wifi")`
  has a symbol; the spacing is SF1.

**AS2. Flat black page with upper-case headers.** small
- Ours (110): a flat black background; "FIND ON YOUR NETWORK" and "TYPE AN ADDRESS".
- Apple (A3): the library page is flat dark grey; no picture of a form.
- Cause: the form's background and the system `Section` header style (whether the upper case is the system's or the
  text's was not checked: UNVERIFIED). Shared fault SF8.

### 3.12 Context menus

**CM1. The system menu over the grid.** small
- Ours (68-card-long-press-move): the system context menu (material, white focused row, an icon on every row) beside
  the lifted card; "Remove from Continue Watching" wraps to two lines; the lifted card covers the count (G2).
- Apple: **NO REFERENCE** for the TV app's context menu.
- Cause: system `contextMenu`. Only the wrap is ours to shorten.

### 3.13 How This Was Sorted

**HS1. A full black page with a narrow centred column and two huge buttons.** noticeable
- Ours (67-sorted-how): black; the title at x 393; two capsule rows x 373 to 1547; a sentence; "Move to Shows"
  x 390 to 933 and "Done" x 990 to 1526 (about 545 pt wide each, about 100 high).
- Apple: **NO REFERENCE**. The nearest Apple pattern is the alert (D4, about 576 pt wide, small buttons side by side).
- Cause: the sorted-how sheet's view (file not read: UNVERIFIED which). Shared fault SF8.

### 3.14 Player controls and the Info, Episodes and Stats panels

**PL1. Mixed separators and the episode's hierarchy.** noticeable
- Ours (23-player-controls): "2026 • Sample Show 1 · S1, E1" small, then "A quiet beginning" (the episode's name) large.
- Apple ([A4](https://support.apple.com/guide/tv/control-video-playback-atvb7944597f/26/tvos/26), cf29160a):
  "S1, E1 • episode name" small, the show's name large; one separator.
- Cause: App/Features/Player/PlayerCoordinator.swift:752 to 753 `metadata(for:)`: `commonIdentifierTitle` is the
  episode's name and `iTunesMetadataTrackSubTitle` is "Show · S1, E1"; the system joins the year with "•".
- The tabs (Info, Episodes, Playback Stats) and the round icon buttons at the right match A4. Shared fault SF10.

**PL2. Info panel for an episode: no title, no description, an empty band.** breaks the look
- Ours (24-player-info-panel): heading "Sample Show 1 · S1, E1"; no episode name; no description; about 150 pt of
  nothing between the heading (y 407) and "2026 • 40 sec [TV-14]" (y 557); a portrait poster 136 × 204.
- Apple ([D5](https://developer.apple.com/design/human-interface-guidelines/materials)): a thumbnail, the title, a
  3-line description, "Science Fiction 33 min", buttons at the right.
- Cause: PlayerCoordinator.swift `metadata(for:)` gives the system only a title, a subtitle and the rating, no
  description; why the system shows the subtitle as the heading was not checked (UNVERIFIED).

**PL3. Episodes and Playback Stats tabs not pictured.** small (test)
- Ours (24-player-episodes-tab, 24-player-stats-tab): both show the controls with Subtitles or Audio focused (note
  24-player-info-panel-TABS.txt: the tabs were not found in the tree).
- Apple: **NO REFERENCE** for an Episodes or Stats tab.
- Cause: the screenshot step; the panels themselves (PlayerInfoPanels.swift) were not seen.

### 3.15 Playback failure alert

**AL1. The alert's message grows to about 14 lines.** breaks the look
- Ours (code at fd9731f): App/Features/Player/PlayerScreen.swift:44 to 57 joins the item line, the failure text and
  `problem.screenLines()` with blank lines; Packages/VideoPlayerCore/Sources/AppLogic/PlaybackStartLog.swift:146 to 157
  adds "Error", "Message", one "Underlying" per inner error, "Last event", "Step" and every checkpoint line (R386,
  R390): 12 to 18 lines for a usual failure. No picture of this version. The earlier run's 62-playback-error (before
  R386) shows the alert at x 668 to 1250 (about 582 pt) with 3 lines, close to Apple's.
- Apple ([D4](https://developer.apple.com/design/human-interface-guidelines/alerts)): about 576 pt wide, a title, a
  one-line description, two buttons. **NO REFERENCE** for the TV app's own failure alert.
- Cause: the diagnostics put in the alert's message.

### 3.16 Empty states

**EM1. Empty states under an open sidebar.** small
- Ours (03, 04, 05, 06, 112): the system unavailable view (symbol, title, one line, an "Add a Source" button), dimmed
  while the sidebar has the focus.
- Apple: **NO REFERENCE** for the TV app's empty states.
- Cause: `ContentUnavailableView` (system); the open sidebar is H2.

### 3.17 Larger Text and Bold Text sets

**A11Y1. Two screens were never tested at Larger or Bold Text.** noticeable (test)
- Ours (a11y-compare.txt): 83 and 88 (Files root) and 90 and 96 (movie page with logo) are identical to the default
  pictures outside the tab bar; the override did not reach the app.
- Cause: the screenshot steps for those screens. The rest of the set: the faults above at a larger size (H7 in 80, G1
  in 07 larger, S1 and S3 in 91, M1 and M2 in 84, H2 in 95).

**A11Y2. Larger Text barely changes the movie page.** small
- Ours (84 against 106): the same layout; title and buttons at almost the same size.
- Apple: NO REFERENCE for Larger Text in the TV app.
- Cause: not traced (UNVERIFIED whether the override applied to every style).

### 3.18 Behaviour, materials, colour and identity

These are covered by findings above; collected here:
- Focus and covering: G2, P1, Q3, M5 (the lifted element covers or clips something).
- Cut-off: H7 (title), Q4 (shrunk titles), and the 3-line synopsis ending in "a…" (91; it opens the full text).
- Materials: Apple's pages put text straight over full-bleed key art darkened at one side (A1, A4, B1), and the sidebar
  and menus on material (A2). Ours: tinted artwork on the product pages (sample artwork), but **flat black** on the full
  synopsis, How This Was Sorted and Add a Source (SF8).
- Identity: Apple's secondary actions are **icon circles** (+, details); ours are text capsules ("More"). Apple's
  shelf headers are smaller and grey; ours are large and white. Apple's library has no captions.

## 4. Shared faults: fix once

| # | Fault | Where it shows | Code at fd9731f |
|---|---|---|---|
| SF1 | No spacing given to an `HStack`, so tvOS's wide default spreads the parts | G4, M1, M6, S2, S4, FI1, ST1, AS1, P1, Q2 | ProductPageParts.swift `ProductMetadataLine.line`, `BadgeGroups`; LayoutParts.swift:16 `SlotLabel`; EpisodeCards.swift caption `HStack` |
| SF2 | Action rows of text capsules with wide gaps, instead of one Play capsule plus icon circles about 22 pt apart | H3, M4 | `ActionRow`, `ActionLabel("More")` in HomeFeaturedView.swift and ItemDetailContentView.swift |
| SF3 | Text across the full width | M2, F1 | `SynopsisLink`, `LongTextPage` |
| SF4 | Captions under posters, and captions forced to one height | G3, S4, Q2, Q5, P1 | PosterCard captions, `CardCaption`, DiscoverCard captions |
| SF5 | A focus shape that does not match the content | M5 | `CastShelf` `.hoverEffect(.highlight)` on a square frame |
| SF6 | Text outside the lifted button, or right above a lifted card | Q3, G2, P1 | DiscoverCard, `GridCountLine`, the person page's count |
| SF7 | Section headers too large and too close to what is above | H4 | HomeFeaturedView.swift and HomeRows' header style |
| SF8 | Flat black pages | F1, AS2, HS1 | `LongTextPage`, the Add a Source form, the sorted-how sheet |
| SF9 | The sidebar left open in the pictures (test or behaviour: UNVERIFIED) | H2, EM1 | screenshot steps or R388 focus |
| SF10 | Episode naming: the show's name where the episode's name belongs | E1, PL1, PL2 | ItemDetailContentView.swift hero; PlayerCoordinator.swift `metadata(for:)` |

## 5. NO REFERENCE: screens with no Apple picture (for the owner)

No Apple page opened in this audit shows these screens of the TV app. Each needs the owner to choose a reference, or
to accept the nearest Apple pattern named in the finding.

1. The episode page (E1, E2).
2. The full description page (F1).
3. The Information section of a product page (M6).
4. The season picker (S3).
5. The person page (P1).
6. Settings and each of its pages (ST1).
7. Add a Source and its forms (AS1, AS2).
8. Files (FI1, FI2).
9. How This Was Sorted (HS1).
10. Needs Review and the Move sheet (not reached in the run).
11. The player's Episodes and Playback Stats tabs (PL3).
12. The TV app's own Search screen (only Apple's sample app is pictured: Q1, Q2).
13. The TV app's context menus (CM1).
14. Empty states (EM1).
15. The TV app's playback failure alert (only the HIG alert illustration: AL1).
16. Larger Text in the TV app (A11Y2).

## 6. Not seen in this run

Not reached by the screenshot run on fd9731f (pictures marked NOT-REACHED or missing): the toolbar menus (07 Sort and
Filter, Saved Views), 08 card menu Go to, 10 Add a Source kinds, 22 Skip Intro, 25 and 26 audio and subtitle menus,
40 About, 64 Needs Review, 69 sort by file name, 72 a Files folder, 92 to 94 and 98 to 100 (Larger and Bold Text
settings backup, Add a Source, source form), 109 and 111. 63 (the Needs Review button) was seen; the page it opens was
not.

## 7. Counts

| Severity | Count | Findings |
|---|---|---|
| Breaks the look | 22 | H3, H4, H6, H7, G1, G2, G3, G4, M1, M2, M4, M5, S1, S3, E1, F1, Q2, Q3, FI1, ST1, PL2, AL1 |
| Noticeable | 16 | H2, H5, M3, M6, M7, S2, S4, E2, P1, Q1, Q4, Q5, AS1, HS1, PL1, A11Y1 (a test fault) |
| Small | 9 | H1, G5, M8, FI2, AS2, CM1, PL3, EM1, A11Y2 |

47 findings in all.
