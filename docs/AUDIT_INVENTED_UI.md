# Audit: where the app draws its own UI (21 Nov 2026)

Read-only audit of every screen under `App/` at commit c8f278d. Nothing in the code was changed. Nothing here has been
compiled or run on tvOS (R318). Line numbers are at c8f278d; two other sessions were editing `App/Features/Player`,
`App/Shell` and `App/Support` at the time, so lines in those folders may have moved.

The question for each item: the app draws or lays something out itself; does Apple have a system component, a HIG rule
or a sample that shows the pattern? Design follows Apple's TV app (R312).

## The Apple pages used

| Short name | Page | What it says (quoted briefly) |
|---|---|---|
| HIG tvOS | https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos | "Embrace the tvOS focus system"; "Deliver beautiful, edge-to-edge artwork" |
| HIG Focus | https://developer.apple.com/design/human-interface-guidelines/focus-and-selection | "Rely on system-provided focus effects"; "Consider creating custom focus effects only if it's absolutely necessary"; "make sure that people can bring focus to every element" |
| HIG Materials | https://developer.apple.com/design/human-interface-guidelines/materials | "use Standard materials for elements in the content layer"; tvOS "regular: Overlay views that partially obscure onscreen content"; "consider adding a dark dimming layer of 35% opacity" |
| Sample | https://developer.apple.com/documentation/swiftui/creating-a-tvos-media-catalog-app-in-swiftui | The sample's code: shelves are `LazyHStack(spacing: 40)` with `.scrollClipDisabled()`, `.buttonStyle(.borderless)` and `containerRelativeFrame(.horizontal, count:, spacing: 40)`; the header is `containerRelativeFrame(.vertical)` at `length * 0.8` with `focusSection()`; the backdrop is `.regularMaterial` masked by a `LinearGradient`; the product page's description is a `.plain` button that opens the whole text with `fullScreenCover`; search is a `LazyVGrid` of 4 flexible columns, spacing 40 |
| fullScreenCover | https://developer.apple.com/documentation/swiftui/view/fullscreencover(ispresented:ondismiss:content:) | "Presents a modal view that covers as much of the screen as possible" |
| TVMonogramView | https://developer.apple.com/documentation/tvuikit/tvmonogramview | TVUIKit's view for a person's picture or initials (UIKit, no SwiftUI form) |

Verdicts: **Replace** (a system component or a sample pattern does it), **Keep** (Apple has none, or the app already
uses the sample's pattern), **UNVERIFIED** (Apple's pages do not settle it; the number or the look needs a run or the
owner).

## Findings, most visible first

| # | File and line | What the app does | Apple page and what it says | Verdict |
|---|---|---|---|---|
| 1 | `App/Features/Detail/ItemDetailContentView.swift:130` (`SynopsisLink`), `App/Shared/LongTextPage.swift:5` | The 3-line synopsis is a `.plain` button that **pushes** a page with the whole text. | Sample: the description button opens the text with `fullScreenCover`. | **Replace**: present `LongTextPage` with `fullScreenCover` instead of a push. R365's missing title would then be the cover's own content. |
| 2 | `App/Features/Home/HomeFeaturedView.swift:73` (`HomeFeaturedLayout.heightFraction = 2/3`) | Home's featured area is two thirds of the screen. | Sample: the header is `length * 0.8`. | **UNVERIFIED**: 2/3 lets the first shelf show (R349); 0.8 is the sample's value. Owner's choice; the TV app photos would settle it. |
| 3 | `App/Shared/ProductPageParts.swift:149` (`ProductPageLayout.heroFraction = 0.85`) | Product page hero is 85 % of the page. | Sample: 0.8. | **UNVERIFIED**: a different number from the sample with no Apple source. Candidate to use 0.8. |
| 4 | `App/Shared/BackdropView.swift:49-57`, `heroClearTop` near line 75 | Artwork under `.regularMaterial` masked by a `LinearGradient`; the gradient is clear for the top 0.35. | Sample: the same material and gradient. HIG Materials: regular is for "Overlay views that partially obscure onscreen content". | **Keep** the pattern; the 0.35 stop is **UNVERIFIED** (the sample's stops were not read as numbers). |
| 5 | `App/Shared/PosterGridLayout.swift:10,15` | Movies and Shows grid: 5 flexible columns, spacing 40, row spacing 100. | Sample: search grid of 4 columns, spacing 40 both ways. | **UNVERIFIED**: 5 columns and 100 pt row spacing come from DESIGN_SYSTEM.md section 4, not from a page read today. |
| 6 | `App/Shared/TitleHeader.swift:5,24-32` | Title logo fitted to a 640 × 200 pt box; the text title is `largeTitle` with `minimumScaleFactor`. | HIG tvOS: "edge-to-edge artwork"; no page gives a logo box size. | **Keep** (Apple has no title-logo component); the box size is **UNVERIFIED**. |
| 7 | `App/Shared/CardRow.swift:10` | Shelf title is `FittingText(row.title, style: .title3)` with the header trait. | Sample: the shelf title code was not on the page. | **UNVERIFIED** (text style). The shelf itself (`LazyHStack(spacing: 40)`, line 14) follows the sample: **Keep**. |
| 8 | `App/Shared/PosterCard.swift:118-180` (`CardCaption`, `CaptionHeightKey`, `EqualCaptionRow`) | A PreferenceKey makes every caption in a row as tall as the tallest one. | Sample: captions are plain `Text` siblings of the image; no height equalising. | **UNVERIFIED**: depends on R356 (wrap at the floor, or cut with "…"). If R356 goes to (b), the plain `Text` of the sample is enough. |
| 9 | `App/Features/Detail/ItemDetailContentView.swift:214-232` | Cast photo clipped to a `Circle`; with no photo, a circle with the person's initials. | TVMonogramView in TVUIKit is the system monogram; SwiftUI has none (the file's own note at line 193). | **UNVERIFIED**: replace only by wrapping the UIKit view; whether that look matches the TV app was not checked. |
| 10 | `App/Features/Detail/ItemDetailContentView.swift:155-171` (`CastShelf`) | Cast shelf: `photoSize` 120 pt ScaledMetric, `LazyHStack` with the **default** spacing. | Sample: every shelf uses spacing 40. | **Replace** the default spacing with 40 (sample); the 120 pt size is **UNVERIFIED**. |
| 11 | `App/Shared/ProductPageParts.swift:46,128` (`BadgeGroups.groupGap = 12`, `BadgeOutline`) | Format badges drawn as text in a rounded outline, groups split by a 12 pt gap. | No tvOS badge component on any page read. | **Keep**: Apple has none; owner decided (R370, R373). |
| 12 | `App/Features/Detail/ItemDetailContentView.swift:247-280` (`MediaInfoSection`) | Information is a `Grid` with `Divider`s, made one `.focusable()` block so the remote can scroll it. | HIG Focus: "make sure that people can bring focus to every element". A `Form` with `LabeledContent` is the system alternative (rejected in #25 B6). | **Keep** (#25 B6), with the focus look **UNVERIFIED**. |
| 13 | `App/Shared/LayoutParts.swift:155` (`ReadableSecondary`) | Secondary text is the primary colour at an opacity, not the system `.secondary`. | HIG Focus and Materials do not cover it; the system style is `.secondary`. | **UNVERIFIED**: kept because of R240's contrast results; an invented colour level against "system colours only". |
| 14 | `App/Features/Player/PlayerInfoPanels.swift:34,55,72` | Player info shelves: spacing 40, `count: 4`; stats in a 3-column `LazyVGrid`, spacing 40. | Sample: shelf spacing 40 (matches); the count and the stats grid are not in the sample. | **Keep** the spacing; count 4 and the stats grid are **UNVERIFIED**. (Plex session's folder: not touched.) |
| 15 | `App/Shared/GridToolbar.swift:79` (`GridCountLine`) | A line with the item count above the grid. | No system place for a count on tvOS in the pages read. | **Keep** (Apple has none); PROVISIONAL in R375. |
| 16 | `App/Shared/PosterCard.swift:42,68` | `hoverEffect(.highlight)` on the artwork. | HIG Focus: "Rely on system-provided focus effects"; the sample's lockups use the system button styles. | **Keep** (system effect); whether the system lifts the custom artwork is unverified (the file says so). |
| 17 | `App/Shared/SettingsPane.swift:240` (`PaneColumns`) | Settings' two-column layout (image left, list right). | No SwiftUI two-column settings container on tvOS in the pages read. | **Keep** (R172). |
| 18 | `App/Shared/SettingsPane.swift:55` (`TaskPageLayout`) | Task pages sized at 2/3 and 0.5 of the screen. | No Apple size given. | **Keep** (R228); the fractions are UNVERIFIED against the TV app. |
| 19 | `App/Shared/FittingLine.swift:8,70` (`FittingLine`, `FittingText`) | Measured one-line texts with `ViewThatFits`, dropping the lowest part. | No system "fit or drop" text; `ViewThatFits` is the system container used inside. | **Keep** (owner's rule S1). |
| 20 | `App/Shared/LayoutParts.swift:78` (`ActionRow`), `HomeFeaturedView.swift:29` | Play and More in an `HStack` with `fixedSize` so both have one height. | Sample: product page buttons are a `VStack(spacing: 12)` with `frame(maxWidth: .infinity)`. | **UNVERIFIED**: the sample stacks them vertically; the TV app (R312) shows them side by side. Owner's photos decide. |
| 21 | `App/Features/Settings/LicenseTextsView.swift:19` (`.grouped`), `App/Features/Files/FilesView.swift:29`, `FilesFolderView.swift:32` (`.plain`) | Two different system list styles. | No page read says which style a file browser takes. | **UNVERIFIED** (R363): both are system styles; the question is only whether they should be one. |
| 22 | `App/Shared/ArtworkView.swift:53` | Placeholder: `.fill(.quaternary)` with a `largeTitle` symbol. | System fill and symbol; no Apple placeholder component. | **Keep**. |
| 23 | `App/Features/Discover/DiscoverView.swift:80,103,142` | `.card` button style for dense lockups; section headers `.title3`. | Sample uses `.card` for dense lockups. | **Keep** `.card`; header text style **UNVERIFIED** (same as #7). |
| 24 | `App/Shared/LayoutParts.swift:208` (`TaskButtonRow`) | `listRowBackground(.clear)` on a button row. | No page read covers it. | **Keep** (R255). |
| 25 | `App/Features/Settings/AboutView.swift:8` | TMDB logo at 28 pt ScaledMetric. | The one logo exception. | **Keep** (R148). |

## What this audit did not cover

- The look of any item on tvOS 27: nothing was run.
- The sidebar (R359, R376) and the system toolbar (R375): both are system components and are not "drawn by the app".
- The player's left strip (15-item list, 9(b)): in `App/Features/Player`, left to the Plex session.
- The TV app itself: no photos yet; the TV-app comparisons above use the written description in DESIGN_SYSTEM.md.

## Summary of verdicts

- Replace: #1 (synopsis push → `fullScreenCover`), #10 (cast shelf spacing → 40).
- UNVERIFIED numbers against the sample: #2 (2/3 vs 0.8), #3 (0.85 vs 0.8), #5 (5 columns, row 100 vs 4 columns, 40).
- Keep, Apple has none: #6, #11, #15, #17, #18, #19, #22, #24, #25.
- Waiting on an owner decision: #8 (R356), #20 (button row direction), #21 (R363).
