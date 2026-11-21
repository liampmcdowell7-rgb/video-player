# Design system: native tvOS 27 with Liquid Glass

## Guiding principle (owner's decision, 20 Nov 2026; OPEN_QUESTIONS R332, Decided)

Applies to every screen and every stage from now on.

1. **Design reference: Apple's TV app on tvOS 27.** Match its layout, navigation, components, typography, spacing, focus
   behaviour and Liquid Glass materials as closely as the system components allow: shelves and lockups (posters, episode
   cards, Up Next / Continue Watching), the show and movie pages, season and episode lists, search with the inline
   keyboard, and the player with its info, audio and subtitle panels. Where the TV app has no equivalent screen (adding a
   source, settings), follow **tvOS Settings**. Native system components only; never imitate a system look with custom
   drawing.
2. **Functionality reference: a leading third-party tvOS video player for personal libraries** (a media-server source and
   network shares, direct play at full quality, rich metadata, a media-server sign-in by a code entered on another
   device). Match that feature set, and exceed it where the owner asked (automatic intro and credits skip, binge playback,
   iPhone Now Playing control; docs/PLAYBACK_AUTOSKIP_NOWPLAYING.md).
3. **Brandless repository:** no third-party app is named anywhere in the repository (code, docs, commit messages, R
   rows); features are described generically. Apple's TV app and tvOS Settings may be named as the design reference, and
   the HIG is cited. (Data providers and technologies stay plain-text names under docs/NAMES.md.)

How it is applied: every design note names, per screen, the TV app screen or tvOS Settings screen it follows, and what
is different and why (first: docs/SOURCE_SETUP_DESIGN.md). Gaps of the screens not yet changed are listed in
docs/HIG_AUDIT.md, section "Against Apple's TV app". Only Apple's pages are cited; a tvOS 27 detail not read on an Apple
page is UNVERIFIED. If the owner sends photos of the TV app, they become the primary reference over any written
description.

**Standard (user decision, 2026-11-17):** the app must be indistinguishable from the system apps: native components first, Liquid Glass from the SDK, system values only, system focus engine only, tvOS navigation conventions, `AVPlayerViewController` for playback, neutral icon art.

**Status of everything below:** written from Apple's pages and checked by `scripts/design-lint.sh` (static text checks). **Nothing has been compiled, run in a Simulator or seen on an Apple TV.** Visual fidelity to the system apps cannot be proven until a build is compiled and looked at on a real Apple TV (docs/DEVICE_TEST_CHECKLIST_VISUAL.md). Every decision here is **PROVISIONAL** with its alternative visible, and is mirrored in OPEN_QUESTIONS.md by the parent.

Source tags used in this file: **[V]** = page read in full for this document (fetched 2026-11-17); **[PA]** = read by the platform audit (docs/PLATFORM_AUDIT.md rows 14a, 14b); **[L]** = linked only, page NOT read in this pass (any rule taken from it is unverified); **[A]** = API name from general knowledge, not re-checked against a page.

---

## 1. Decisions (PROVISIONAL)

| ID | Decision | Alternative (still open) |
|---|---|---|
| D-DS1 | **Deployment target tvOS 27.0** (`project.yml`). No availability checks for anything in tvOS 27.0 or earlier. APIs newer than the target (for example 27.3 beta schemas) stay behind `#available`. | tvOS 18.0 with availability checks around the 26 and 27 APIs (`glass` button style is tvOS 26.0+ [V], scene requirement and `@State` macro are SDK-side). Costs: every 26+ API gated, two looks to test. Also unverified: **which Apple TV models run tvOS 27**; Xcode 27.2's simulators list only Apple TV 4K 3rd and 4th generation (Codemagic page [V]). The user's own Apple TV model must be able to run tvOS 27 or nothing in this file can be tested. |
| D-DS2 | **Xcode 27.2** (`xcode: "27.2"` in `codemagic.yaml`, both workflows; build 27B52, tvOS 27.2 runtime, Apple TV 4K 3rd and 4th generation simulators [V: docs.codemagic.io/specs-macos/xcode-27-2/]). | `edge` = Xcode 27.3 (27C5020n, tvOS 27.3, marked "edge" by Codemagic, not labelled release [V: .../xcode-27-3/]); `latest` (previous value, resolves to whatever Codemagic calls latest on the day). Codemagic's YAML docs say the value is "latest, edge or version (e.g. 11.2)" [V: docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/]; a quoted `"27.2"` follows the version form but **no Codemagic page shows a 27.x example string, so whether `"27.2"` resolves is unverified until a build starts.** |
| D-DS3 | Toolchain Swift 6.4 (ships with Xcode 27.x, per the earlier platform audit; not re-verified here). **Language mode stays 5** (`SWIFT_VERSION: "5.0"`; was the invalid-looking `"5.10"`). | Language mode 6 (strict concurrency errors). Untested, nothing is compiled; one failed compile costs Codemagic minutes (18 free minutes left). The package keeps its own tools version 5.9. |
| D-DS4 | `project.yml` states the scene manifest explicitly: `UIApplicationSceneManifest` with `UIApplicationSupportsMultipleScenes: false`. | Leave it out and rely on SwiftUI's own scene. See section 3, row "scene life cycle". |
| D-DS5 | Artwork: **`AsyncImage` plus `View.asyncImageURLSession(_:)`** with a `URLSession` whose `URLCache` lives in the Caches directory with a size cap (purgeable, matches docs/STORAGE_MODEL.md). No own memory/disk artwork cache for URL-addressable artwork. Own loader only for artwork that has no URL (embedded in a file, sidecar on SMB/NFS/SFTP): a custom view, each case recorded here with its reason. The Top Shelf extension cannot use `AsyncImage`; it keeps the App Group files from the storage model. | Keep an own purgeable artwork cache for everything (more code, same purge behaviour, one place for size limits). Unverified: whether authenticated image requests (WebDAV, media servers with token headers) work through `AsyncImage`'s new `URLRequest` initializers; the release note only names `cachePolicy` [V]. |
| D-DS6 | **Superseded by OPEN_QUESTIONS R167 option (c), PROVISIONAL: there is no Discover tab; Discover is in the Search tab, and Show Discover only decides whether Search shows it.** Earlier text: Discover tab removal. HIG says "Don't disable or hide tab bar buttons, even when their content is unavailable" [V: tab-bars]. Interpretation: that rule is about a tab whose content is temporarily unavailable; a tab the **user removes in Settings > Discover > Show Discover** is a user setting, not an unstable bar. | Always show Discover; when off, the tab shows an empty state explaining how to turn it on. |
| D-DS7 | **Names (user rule, 2026-11-17; replaces the earlier brandless rule; full text in docs/NAMES.md).** The app's own name, icons, colours and wording stay neutral; no logo or icon of any company or product anywhere (text names only; SF Symbols stay allowed), with one exception: TMDB's logo, required by TMDB's terms, only in Settings > About > Data Sources (user decision R148, section 10); no wording that suggests the app is made, certified or endorsed by, or affiliated with, any company; no mention of other media-player applications. Every format, server, service and Apple technology the app plays, connects to or relies on is shown by its **real name** (Dolby Vision, Dolby Atmos, DTS-HD Master Audio, HEVC, WebDAV, SMB, Plex, OneDrive, TMDB, IMDb, AirPlay, Siri Remote, iCloud, Top Shelf, HDMI and the rest of the docs/NAMES.md allowlist), with honest claims only ("Dolby Vision (converted from Profile 7)", never "Dolby Certified"). Settings > About carries the Trademarks and Attributions section. The lint enforces it with `unknown-name`, `claim-wording` and `brand-logo` (section 10). | None: the user decided. Lint details (heuristics, limits) are PROVISIONAL; alternative: a hand-kept per-file list instead of the shape tests. |
| D-DS8 | Icon and Top Shelf art stay as the **tvOS layered image stack in the asset catalog** (3 layers, neutral grays). Icon Composer is not used: the Xcode page says tvOS and visionOS targets still use an `AppIcon` asset catalog [V: creating-your-app-icon-using-icon-composer]. | Rename "App Icon - Large" to the Xcode 27 naming ("App Icon - App Store") once the first compile shows whether the catalog is accepted. |
| D-DS9 | No custom glass anywhere in the first build. Standard components (`TabView`, `NavigationStack`, system button styles, menus, alerts) get Liquid Glass from the SDK. The Playback Stats overlay is **content over video, so a translucent standard material, never glass** (see row "Playback Stats overlay"). | A documented `glassEffect` for the overlay (needs `design-lint:allow` with a reason and a device check that it is legible over bright video). |
| D-DS10 | Background Assets is not adopted now: the app has no On Demand Resources and no downloadable asset packs. | Revisit if art packs or subtitle fonts ever ship as packs. |
| D-DS11 | Settings is a `Form` (grouped), the system Settings look, with `Section` headers in title-style capitalization. | `List` with `.listStyle(.grouped)` [A]. |
| D-DS12 | Text entry (source setup, names): standard `TextField` / `SecureField` inside a `Form`, default style; `.bordered` text field style only for a field outside a `Form`, and only after the first compile confirms it exists for tvOS (the release note says `.squareBorder` and `.roundedBorder` are soft deprecated in favour of `.bordered` [V], it does not list tvOS availability). | Explicit `.bordered` everywhere. |

---

## 2. What was read, and what was not

Read in full for this pass [V]: tvOS 27 Release Notes; "Applying Liquid Glass to custom views"; "Adopting Liquid Glass"; "Transitioning to the UIKit scene-based life cycle"; "Creating your app icon using Icon Composer"; "Configuring your app icon using an asset catalog"; HIG pages App icons, Layout, Typography, Top Shelf, Tab bars, Focus and selection, Playing video, Remotes, Buttons, Collections; API pages `AVPlayerViewController`, "Customizing the tvOS playback experience", `ContentUnavailableView`, `PrimitiveButtonStyle.card`, `.borderless`, `.glass`; Codemagic pages Xcode 27.2, Xcode 27.3, YAML getting started.

Read earlier by the platform audit [PA]: HIG Materials ("Liquid Glass in navigation and Top Shelf; standard components adopt automatically; Don't use Liquid Glass in the content layer"), HIG Color, tvOS 27 notes, Codemagic Xcode 27.0, 27.1, 27.2.

**Not read in this pass [L] (rules from these pages are unverified, links kept for the first person to open them):** HIG Materials and Color (re-read), Lists and tables, Menus, Context menus, Search fields, Alerts, Progress indicators, Loading, SF Symbols, Toggles, Settings, Onboarding, Accessibility, Motion, Dark Mode; SwiftUI pages for `TabView`, `NavigationStack`, `Form`, `Menu`, `Picker`, `searchable`, `confirmationDialog`, `contextMenu`. Their API names below are tagged [A].

Pages that do not exist or were not found: none looked for and missing. One inconsistency in Apple's own text, recorded not resolved: the asset-catalog page says "iOS, iPadOS, tvOS, and watchOS apps can auto-generate all icon variations from a single 1024×1024 pixel image" and, two sentences later, "For macOS and tvOS, you need to supply an asset for each size" [V].

---

## 3. Release-note items adopted (tvOS 27 SDK) [V]

| Release-note item | What we do |
|---|---|
| Buttons on tvOS no longer use the asset-catalog accent colour as label tint (SDK 27). | The catalog has no AccentColor set; buttons use the system default. Rule: no `.tint(...)` with a literal colour (lint `color-literal`). Prominence comes from `.borderedProminent` / `.glassProminent` styles, not colour. |
| New `@State` macro (Xcode 27). | Not an issue in today's views (`@State private var query = ""`). Review rules for new code: do not give `@State` an initial value **and** assign it in `init`; do not compose `@State` with other wrappers or macros; with all-private stored members the synthesized init is gone, assign members explicitly; write generic types in full. Not lint-checkable (needs a parser); manual review item in the device/visual checklist hand-over. |
| `.bordered` text field style; `.squareBorder` and `.roundedBorder` soft deprecated. | D-DS12. |
| `AsyncImage` caches with HTTP caching, `URLRequest` initializers, `asyncImageURLSession(_:)`. | D-DS5. |
| Scene-based life cycle required or the app fails to launch (UIKit page [V]). | The app is a SwiftUI `App` with a `WindowGroup`: no `UIApplicationDelegate` window code exists, so there is nothing to migrate. The UIKit page tests "migrate if `UIApplicationSceneManifest` is missing or has no configurations, or the delegate lacks `application(_:configurationForConnecting:options:)`" [V]; `project.yml` had neither a manifest nor a delegate, so D-DS4 adds the manifest. **Unverified:** that a SwiftUI app without a `UISceneConfigurations` entry passes Apple's check; the page's own examples are UIKit apps. This is the first thing to look at in the first launch (checklist item V-01). `App/VideoPlayerApp.swift` was normalised (BOM and CRLF removed, comment added). |
| Background Assets replaces On Demand Resources (ODR deprecated). | D-DS10. |
| `LabeledContent` inside a `Menu` becomes the menu item's subtitle (27 SDK). | Use it in track menus for "language + what the file contains" rows instead of a custom row view. |
| New data-item / error-object `alert` and `confirmationDialog` modifiers, usable back to tvOS 15. | Use them for error and confirmation presentation; no availability check needed at the target. |
| `controlSize`, `buttonSizing`, `ButtonBorderShape` etc. reset to defaults inside sheets and popovers (27 SDK). | Do not rely on inheriting them into sheets; set them inside the sheet if needed (none today). |
| Section headers are title-style capitalization (Adopting Liquid Glass, Organization and layout [V]). | Write headers in title case ("Discover", "About"); never pass ALL CAPS. |
| "Remove availability gating pointless under the target." | Lint rule `pointless-availability` reads the target from `project.yml`. App/ had none. |
| Network Security: stricter TLS (TLS 1.2 minimum, ATS-conformant) for **select system processes** (MDM, software update, etc.) [V]. | Not about third-party app traffic; no change. The local-networking ATS exception in `project.yml` is unchanged. |
| Liquid Glass needs Apple TV 4K (2nd generation) or newer; older devices keep the current look ("Adopting Liquid Glass" [V]). | Nothing to do; recorded so the visual check names the device model. |

---

## 4. Verified values

| Value | Number | Source |
|---|---|---|
| Safe area, tvOS | 60 pt top and bottom, 80 pt left and right | HIG Layout [V] |
| Grid, unfocused content width / horizontal spacing / minimum vertical spacing | 2 columns 860 / 40 / 100; 3: 560; 4: 410; 5: 320; 6: 260; 7: 217; 8: 184; 9: 160 (all spacing 40 and 100 pt) | HIG Layout [V] |
| Card widths in this app (#15 4.2) | exactly two poster widths: 260 pt on shelves (six to the width, `CardRow`) and 320 pt in grids (five columns, `PosterGridLayout`); Continue Watching 16:9 cards are three to the width (about 560 pt, the 3-column grid width; R185); episode cards on the show page four to the width (about 410 pt, the 4-column grid width; R189). No other card width: widths come from `containerRelativeFrame` and grid columns, never a number (lint `hard-padding`) | HIG Layout [V] grid widths |
| Poster proportion (Top Shelf row images) | 2:3: actual 404x608, focused/safe 380x570, unfocused 333x570 pt; square 608; 16:9 908x512 | HIG Top Shelf [V] |
| Tab bar | height 68 pt, top edge 46 pt from the top of the screen, "you can't change either"; translucent, only the selected tab opaque | HIG Tab bars, tvOS [V] |
| Text styles (tvOS, weight / size / leading pt) | Title 1 Medium 76/96; Title 2 Medium 57/66; Title 3 Medium 48/56; Headline Medium 38/46; Subtitle 1 Regular 38/46; Callout Medium 31/38; Body Medium 29/36; Caption 1 Medium 25/32; Caption 2 Medium 23/30 | HIG Typography [V] |
| Text size default / minimum, tvOS | 29 pt / 23 pt | HIG Typography [V] |
| Hit region | at least 44x44 pt (general rule; tvOS has no extra note) | HIG Buttons [V] |
| Focus states (up to five) | unfocused, focused, highlighted, selected, unavailable | HIG Focus and selection, tvOS [V] |
| App icon (tvOS) | layout 800x480 px, 2 to 5 layers, rectangular, parallax; sRGB / Gray Gamma 2.2 / Display P3 | HIG App icons [V] |
| Top Shelf static fallback | 2320x720 pt (2320x720 @1x, 4640x1440 @2x); system flips and blurs it into 1920 px at 16:9; must not imply interactivity | HIG Top Shelf [V] |
| Back (Menu) | Opens the parent of the current screen; at the top level the parent is the Home Screen; press and hold goes Home from anywhere; Play/Pause plays/pauses | HIG Remotes [V] |
| Loading screens | avoid; if loading takes more than two seconds, black screen with a centred spinner | HIG Playing video [V] |
| Interactive overlay over video | minimum delay 0.5 s to pause before showing | HIG Playing video, tvOS [V] |
| Overlays over video | small, unobtrusive; prefer translucent SDR graphics to bright opaque content (image retention) | HIG Playing video, tvOS [V] |

Poster grid arithmetic (derived, not from a page): a 2:3 poster in the five-column grid is 320 pt wide, so 480 pt tall; in the six-column grid 260 x 390 pt. In code this is `aspectRatio(2.0 / 3.0, contentMode: .fit)` inside a grid with the spacing above; the grid numbers are literals, so each use carries `design-lint:allow HIG Layout grid: 40 pt spacing, 100 pt minimum vertical`.

---

## 5. Liquid Glass rules

Sources: Applying Liquid Glass to custom views [V]; Adopting Liquid Glass [V]; HIG Materials [PA].

1. **Standard components get the material for free.** Rebuilding with the SDK is the adoption ("standard components like bars, sheets, popovers, and controls automatically adopt this material"). On tvOS "standard buttons and controls take on a Liquid Glass appearance when focus moves to them" [V]. `.card` applies a Liquid Glass effect on focus; `.borderless` raises the button with a Liquid Glass effect on the button's first image; `.glass` (tvOS 26.0+) applies Liquid Glass regardless of focus [V: button style pages].
2. **No custom backgrounds in controls and navigation**: they "might overlay or interfere with Liquid Glass or other effects ... such as the scroll edge effect" [V]. Lint `custom-glass` bans `.background(...opacity)`, `.blur`, `Material`.
3. **Glass is for controls and navigation, never the content layer** (HIG Materials [PA]): posters, artwork, text rows, detail pages are content.
4. **No glass on glass.** Never put `glassEffect` on something inside a standard glass container (tab bar, menu, alert). Nothing in App/ uses `glassEffect` today; the lint makes any use need a recorded reason.
5. **If custom glass is ever approved:** one `GlassEffectContainer` per cluster, `glassEffect(_:in:)` applied after the other appearance modifiers, `interactive(_:)` only on things the user can act on, `matchedGeometry` / `materialize` transitions, "limit the use of Liquid Glass effects on screen at the same time" [V].
6. **Focus** (tvOS): "adopt standard focus APIs ... consider applying these effects to custom controls ... by adopting the standard focus APIs" (`focusable(_:)`, `isFocused`) [V]. This file's reading: prefer a standard control (`Button` with a system style) over any custom focusable, so the question does not arise. The one documented exception is a `.hoverEffect(.highlight)` on a **non-first** image inside a `.borderless` button [V: borderless page]; that use needs `design-lint:allow` citing the page.
7. **Accessibility settings (Reduce Transparency, Reduce Motion, Increase Contrast, Bold Text, Larger Text)**: translucency and morphing "can adapt to people's needs"; standard components adapt automatically; custom elements, colours and animations must be tested with these settings [V]. Our rules: no custom glass (nothing to adapt), system colours and text styles only (they adapt), any animation reads `accessibilityReduceMotion` (lint `motion`), layouts must reflow at the largest text size (device checklist V-06).
8. **Light and dark**: semantic colours only (`.primary`, `.secondary`, `Color.accentColor`, system colours); no `Color.white`/`.black` literals (lint `color-literal`). Custom colours are not allowed at all; if one is ever approved it needs light, dark and increased-contrast variants in the asset catalog [V: Adopting, "Review your use of color in controls"].
9. **Tab bar colour**: avoid a similar colour on tab labels and content backgrounds; prefer the monochrome default (HIG Tab bars, "Liquid Glass color" link [V]).
10. **Performance**: not measured. Unverified on Apple TV 4K 2nd generation (the oldest model Apple lists for the effect).

---

## 6. Native component map

One row per UI element. "Custom?" says whether anything is built by hand and why. All "verified values" are only the ones read on the page named; "none" means no value was checked. Everything is *not yet seen on a screen*.

| Element | System component | HIG page and link | Verified values | Custom? / reason |
|---|---|---|---|---|
| Tab bar (Home, Movies, Shows, Files, Search, Settings; R167 (c), PROVISIONAL) | `TabView { Tab(...) }` with `Tab(role: .search)` for Search | Tab bars [V] https://developer.apple.com/design/human-interface-guidelines/tab-bars | height 68 pt, top 46 pt (fixed); Menu from content returns focus to the tab bar; do not hide tabs (see D-DS6); single-word labels; SF Symbols; search tab at the trailing end ("Use semantic search tabs" [V Adopting]) | No. Seven tabs is a count Apple's guidance neither forbids nor endorses; unverified how the bar looks with seven. |
| Per-tab navigation, back stack | `NavigationStack` per tab | Remotes [V] https://developer.apple.com/design/human-interface-guidelines/remotes | Back opens the parent screen; at the top level goes Home; press and hold goes Home | No custom Menu handling anywhere except playback (below). |
| Rows / shelves (Continue Watching, Next Up, Recently Added) | `ScrollView(.horizontal)` + `LazyHStack` of `Button`s, `.buttonStyle(.borderless)` lockups (R335; was `.card`), `scrollClipDisabled()`, 40 pt spacing and `containerRelativeFrame(count: 6, spacing: 40)` as Apple's sample "Creating a tvOS media catalog app in SwiftUI" [V 21 Nov 2026]; row title as a `Text` with a text style / or `Section` header | Collections [V] https://developer.apple.com/design/human-interface-guidelines/collections ; Layout [V] | "Use the standard row or grid layout"; grid numbers in section 4; extra vertical space for titled rows; keep partially hidden content symmetrical | No. `.card` = Liquid Glass on focus, no padding [V]. Whether the focused card needs `scrollClipDisabled()` [A] to avoid clipping is for the first screen check. |
| Poster card | R335 (PROVISIONAL): `Button` + `.buttonStyle(.borderless)` with the artwork AND its title and second lines in the label (one lockup; Apple's sample: "Provide a separate `Image` and `Text` view in the button's label closure"), `hoverEffect(.highlight)` on the custom artwork view; was `.card` with the title below the button. The Discover card stays `.card` (information-dense lockup, the sample's advice) | Collections [V]; Top Shelf poster sizes [V] | 2:3; unfocused 333x570 pt in the Top Shelf row spec; in-app width from the grid table | No. Progress bar on Continue Watching: `ProgressView(value:)` [A] (system), remaining time as text as well, not only a bar. |
| Poster grid (Movies, Shows, search results) | `LazyVGrid` with fixed-count `GridItem`s | Layout [V] | 5 or 6 columns, 40 pt spacing, 100 pt minimum vertical spacing | No. Grid spacing numbers need `design-lint:allow` citing Layout. |
| Detail page (title, seasons, Play) | `ScrollView`/`Form`-free page: artwork, `Text` with text styles, `Button`s with `.borderedProminent` for Play (one prominent button) and `.bordered` for the rest; seasons as `Section`s | Buttons [V] https://developer.apple.com/design/human-interface-guidelines/buttons | one or two prominent buttons per view; style, not size, distinguishes the preferred action; verbs for labels | No. Hero artwork behind controls: scroll edge effect (system) rather than a scrim [V Layout]; `backgroundExtensionEffect()` only with an allow and reason. R336 (PROVISIONAL): the backdrop at full strength under the system `regularMaterial`, as the product page of Apple's sample "Creating a tvOS media catalog app in SwiftUI" [V 21 Nov 2026] (was: the picture alone at 40 %, R182); cast circles without a photo show the person's initials (HIG Lockups, Monograms [V]). |
| Buttons | `Button` with system styles (`.bordered`, `.borderedProminent`, `.glass`, `.glassProminent`, `.card`, `.borderless`, `.plain`) and roles (`.destructive`, `.cancel`) | Buttons [V] | roles: normal, primary, cancel, destructive; destructive is never primary | No custom `ButtonStyle` (lint `custom-focus`). |
| Context menu (mark watched, favourite, Fix Match) | `.contextMenu { Button ... }` on a card (long press on the remote) | Context menus [L] https://developer.apple.com/design/human-interface-guidelines/context-menus | "Match top menu actions to swipe actions" [V Adopting] | No. |
| Filter / sort menus, saved views | `Menu` with `Toggle`s and a `Picker` | Menus [L] https://developer.apple.com/design/human-interface-guidelines/menus ; Pop-up / pull-down buttons [L] | none verified | No. Active-filter chips: `Button`s with a symbol and text in a `HStack` using a system style; revisit if they look hand-made on screen. |
| Settings | `Form` (grouped) with `Section`, `Toggle`, `Picker`, `LabeledContent`, `NavigationLink` | Settings [L] https://developer.apple.com/design/human-interface-guidelines/settings ; Lists and tables [L] | title-style section headers [V Adopting] | No. |
| Source setup flow (add server) | `NavigationStack` pushing `Form` pages: server type `Picker`, `TextField`, `SecureField`, a "Connect" `Button`, `ProgressView` while testing, `.alert` on failure | Text fields [L] https://developer.apple.com/design/human-interface-guidelines/text-fields | D-DS12 | No. tvOS text entry is the system keyboard sheet. Discovery results (Bonjour) as a `List` of `NavigationLink`s. |
| Files browser | `List` with `Label` rows (SF Symbol + name), `NavigationLink`s, `NavigationStack` | Lists and tables [L] https://developer.apple.com/design/human-interface-guidelines/lists-and-tables | Menu goes to the parent folder (Remotes [V]) | No. |
| Search | `.searchable(text:)` on the Search tab's `NavigationStack`; results grid; `ContentUnavailableView.search(text:)` for no results | Search fields [L] https://developer.apple.com/design/human-interface-guidelines/search-fields | "Use semantic search tabs" [V Adopting] | No. |
| Alerts, confirmations | `.alert` / `.confirmationDialog` with the data-item or error forms (tvOS 15+ [V release note]) | Alerts [L] https://developer.apple.com/design/human-interface-guidelines/alerts | Buttons roles: primary is never destructive [V Buttons] | No. |
| Empty state | `ContentUnavailableView` (tvOS 17.0+ [V]) | n/a (API page [V] https://developer.apple.com/documentation/swiftui/contentunavailableview) | title, SF Symbol, one sentence, at most one action | No. |
| Loading | `ProgressView()` [A], shown only after a short delay, no skeletons | Playing video, "Loading content" [V] | more than 2 s: black screen with centred spinner (playback start only) | No. |
| Error state | `ContentUnavailableView` with a "Try Again" `Button` | same | one calm sentence, no codes | No. |
| App icon | Layered image stack in the asset catalog | App icons [V] https://developer.apple.com/design/human-interface-guidelines/app-icons | 800x480 layout, 2 to 5 layers, safe zone, unmasked rectangular layers, text only above other layers | Neutral placeholder art; see section 9. |
| Launch screen | Empty `UILaunchScreen` | n/a | system background | No. Playback launched from the Apple TV app skips it anyway (Playing video [V]). |
| Top Shelf | Top Shelf extension (not built); static fallback image now | Top Shelf [V] https://developer.apple.com/design/human-interface-guidelines/top-shelf | static 2320x720; dynamic: carousel actions / details, sectioned content row (poster 2:3 sizes), inset banner 1940x692; no ads or prices; feature new and personal content | Extension not written. Layered images preferred for dynamic images. Library-only content. |
| Player | `AVPlayerViewController` (cannot be subclassed [V]) hosted by `UIViewControllerRepresentable` | Playing video [V] https://developer.apple.com/design/human-interface-guidelines/playing-video | system player, no custom chrome | Wrapper only. |
| Skip Intro / Recap / Credits buttons | `AVPlayerViewController.contextualActions` with a `UIAction`, set only inside the range (periodic time observer) | Customizing the tvOS playback experience [V] https://developer.apple.com/documentation/avkit/customizing-the-tvos-playback-experience | shown bottom-trailing while the controls are hidden | No. The API page's own example is a Skip button. |
| Up Next | `AVContentProposal` on `AVPlayerItem.nextContentProposal`, presented through the player delegate; countdown text in the proposal | AVPlayerViewController page [V] ("Content Proposals") | AVKit's automatic acceptance counts from the end of playback (HIG_AUDIT finding 1) | Own countdown text because the credits-start behaviour differs; the proposal UI itself is the system's. |
| Audio / subtitle track menus | Transport bar: system menus for audio and subtitles come with the player; extra rows via `transportBarCustomMenuItems` (`UIAction` / `UIMenu`) | same page [V] | "The system automatically displays controls to configure common playback settings, like selecting subtitles" [V] | Delay row is the only addition (HIG_AUDIT, PROVISIONAL). Embedded text tracks come from HLS renditions or `AVMediaSelectionGroup`; platform audit D1 is open. |
| Info tab (title, description, artwork, rating) | `AVPlayerItem.externalMetadata` -> system Info tab; `infoViewActions` for "Play from Beginning" etc. | same page [V] | title and subtitle in the title view; other fields in Info | No. |
| Chapters | `AVNavigationMarkersGroup` on the item (`navigationMarkerGroups`) | AVPlayerViewController page [V] | system chapter UI | No. |
| Playback Stats overlay | `contentOverlayView` (between video and controls) or `customOverlayViewController` hosting a SwiftUI view | AVPlayerViewController page [V]; Playing video, tvOS overlays [V] | small, unobtrusive; translucent SDR, not bright opaque; image-retention risk | **Custom, reason: Apple has no stats overlay.** Uses a standard material (`.regularMaterial` is flagged by the lint, so it needs `design-lint:allow` citing HIG Playing video) and `.secondary`/`.primary` text styles. Toggled by a transport-bar action, off by default. |
| Honest audio / HDR status | Text in the Playback Stats overlay and in the Info tab (`LabeledContent` rows); wording from `PlaybackStatus` | same | numbers and labels come from the tested model | No custom control. Format names: open question (D-DS7). |
| Now Playing | the system player publishes it from `externalMetadata`; the app does not write Now Playing itself (HIG_AUDIT, R157) | Playing video [V] | none | No. |
| Exiting playback | Detail page of the title just watched | Playing video [V] ("Show a contextually relevant screen") | none | Needs the detail page (not written). |
| Settings: Discover toggle | `Toggle` in a `Form` | Toggles [L] https://developer.apple.com/design/human-interface-guidelines/toggles | none | No. |

---

## 7. Navigation and remote (summary of [V] Remotes / Tab bars)

- Menu: returns to the parent screen; from a top-level tab content focus returns to the tab bar; Menu at the top level goes to the Home Screen. Long press Menu/Back = Home. No custom Menu handling outside playback.
- Play/Pause: system player only. No other screen reacts to it.
- Long-press (touch surface click-hold) = context menu; no `onLongPressGesture` (lint `tap-gesture`).
- "Avoid responding to taps during live video playback" [V]: nothing in the app reacts to taps during playback.
- Search is the system `.searchable` on a `Tab(role: .search)`.
- Settings is the grouped list described above.

---

## 8. Playback

`AVPlayerViewController` hosted by a representable, with only the documented customization properties (section 6 rows). No custom chrome, no overlay except the stats overlay, no gesture recognisers on the player. `appliesPreferredDisplayCriteriaAutomatically` (frame-rate / dynamic-range matching [V: property listed]) stays at its default; Next Episode "keep display mode when formats match" is handled by the playback logic, not by custom UI. `transportBarIncludesTitleView` default.

The fallback engine (a later step) has no system UI and must copy the system player; docs/HIG_AUDIT.md "Known risks" stays the highest HIG risk.

---

## 9. App icon and Top Shelf art: requirements and the gap

Requirements ([V] App icons; Configuring your app icon using an asset catalog; Creating your app icon using Icon Composer):

| Requirement | Source |
|---|---|
| tvOS app icon = layered **image stack** (2 to 5 layers), rectangular 800x480 px layout, system masks the rounded corners, parallax on focus; layers supplied unmasked | App icons [V] |
| tvOS and visionOS "still use an `AppIcon` asset catalog"; an Icon Composer file would **replace** an asset-catalog icon, so none is added | Icon Composer page [V] |
| Liquid Glass icon attributes (specular, refraction, translucency, default / dark / clear / tinted variants) apply to iOS, iPadOS, macOS, watchOS icons; **tvOS icons do not use Icon Composer**, they use the image stack and system parallax | App icons [V] |
| tvOS safe zone: keep content away from the edges; foreground layers are cropped more than background layers; text, if any, above other layers | App icons, tvOS [V] |
| Avoid soft/feathered edges on foreground layers; vary opacity for depth; no baked-in highlights, shadows, blurs | App icons [V] |
| App Store icon: drag layers into the "App Icon - App Store" stack inside "App Icon & Top Shelf Image" | asset catalog page [V] |
| Top Shelf static image: 2320x720 pt (@1x 2320x720, @2x 4640x1440), no implied interactivity; layered images preferred for dynamic Top Shelf | Top Shelf [V] |
| Colour spaces: sRGB, Gray Gamma 2.2, Display P3 | App icons [V] |
| No Apple hardware replicas; avoid text unless essential | App icons [V] |

Current catalog (`App/Assets.xcassets/App Icon & Top Shelf Image.brandassets`): stacks "App Icon - Large" (1280x768, role primary-app-icon) and "App Icon - Small" (400x240 @1x, 800x480 @2x), each with Back / Middle / Front layers; "Top Shelf Image" (1920x720) and "Top Shelf Image Wide" (2320x720 @1x, @2x 4640x1440). Art is neutral gray, a translucent disc, a white play triangle, no text (`scripts/generate-icons.ps1`).

**Gap:**
1. **Naming/structure unverified.** The Xcode page talks about an "App Icon - App Store" stack; ours is named "App Icon - Large" with size 1280x768. Not knowable without Xcode 27 compiling the catalog. First compile: look for asset-catalog warnings (checklist V-02).
2. The 1920x720 Top Shelf slot is not on Apple's current HIG page (only 2320x720 is); kept for the catalog format (existing note in HIG_AUDIT).
3. The two layouts in Apple's text conflict (single 1024x1024 auto-generation vs per-size assets for tvOS, section 2). We supply per-size assets and do not use auto-generation.
4. Nothing was previewed with Parallax Previewer / Exporter (macOS tools from Apple Design Resources); the safe-zone fit is by arithmetic only (content kept within 50% of the height).
5. Dynamic Top Shelf (layered images, carousel / sectioned row) is not built.
6. The icon art is a placeholder; a real one is the user's call and must stay neutral: no logo or mark of Apple or any other company (D-DS7).

---

## 10. Lint (`scripts/design-lint.sh`)

Pure bash/grep/POSIX awk (runs with mawk), no Swift. Default scope: every `.swift` and `.xcstrings` file and every asset-catalog image set under `App/` and `TopShelf/` with all rules, plus the package modules whose strings reach the screen (`Packages/VideoPlayerCore/Sources/AppLogic`, `PlaybackStatus`, `SourceLinks`, `UserData`) with the three names rules only. `--names-only` applies the names rules to the paths after it; `DESIGN_LINT_NAMES=<file>` reads another allowlist (the tests use `scripts/design-lint-fixtures/names-fixture.md`). Run: `bash scripts/design-lint.sh`. Tests: `bash scripts/test-design-lint.sh` (fixtures in `scripts/design-lint-fixtures/<rule>/`; 200 checks passed in WSL on 2026-11-18).

| Rule | Catches | Why / standard rule |
|---|---|---|
| `color-literal` | `Color(red:)`, `Color(white:)`, `UIColor(red:)`, `#colorLiteral`, `0xRRGGBB`, `"#RRGGBB"`, `Color.white`, `.black` | rule 3: semantic colours, no hex; light/dark |
| `fixed-font` | `.system(size:)`, `.custom(`, `UIFont` sizes, `.dynamicTypeSize(` limits, `.minimumScaleFactor(` | rule 3 and 4: text styles, Larger Text, Bold Text |
| `custom-focus` | `focusEffectDisabled`, `.hoverEffect(`, `isFocused`, `.focusable(`, `: ButtonStyle` and kin | rule 4: system focus engine only |
| `custom-glass` | `.blur(`, `UIVisualEffectView`, any `Material`, `.glassEffect`, `GlassEffectContainer`, `.backgroundExtensionEffect`, opacity backgrounds, black/white scrims | rule 2: glass from the SDK only |
| `image-control` | an `Image` that is not `Image(systemName:)` inside `Button`, `Menu`, `Toggle`, `Picker`, `NavigationLink` | rule 3: SF Symbols for controls |
| `tap-gesture` | `onTapGesture`, `TapGesture`, `onLongPressGesture`, `.gesture(`, `DragGesture` | rule 1 and 4: `Button` / `contextMenu` so the focus engine sees controls |
| `hard-padding` | numeric `.padding`, `.frame(width:...)` with numbers, `spacing: <n>`, `.offset`, `.ignoresSafeArea`, `.safeAreaPadding`, `EdgeInsets`, `.listRowInsets`, `.contentMargins` | rule 3: system spacing and safe areas |
| `unknown-name` | a proper noun in a **UI string** (string literals, triple-quoted text, `.xcstrings` keys and values; never comments or identifiers) that is not in the `names-allowlist` or `names-generic` block of docs/NAMES.md. Exact heuristic below | D-DS7: real names, but only names the app really uses, each acknowledged |
| `claim-wording` | in UI strings: the signs TM, R, SM (as characters or "(TM)", "(R)"); "Works with", "Made for", "Designed for", "Certified by/for", "Approved by", "Endorsed by", "Licensed by", "Official" before a capitalised word; a capitalised word followed by Certified / Ready / Approved / Compatible / Official (not after Not / Is / Are / Be / Been / Yet). Strings that say "not endorsed / affiliated / certified / approved / sponsored" are exempt | D-DS7: honest claims only |
| `brand-logo` | the Apple logo character U+F8FF anywhere; `Image(systemName:)` with `applelogo`, `apple.logo` or `logo.*`; `Image("...")` / `UIImage(named:)` or an asset-catalog image set (not the `.brandassets` app icon) whose name contains logo, badge, brand or an allowlisted / known third-party name | D-DS7: text names only, no logos; SF Symbols stay allowed. **No `design-lint:allow` works for this rule.** The one exception (user decision R148) is built into the lint: the image set `App/Assets.xcassets/TMDBAttributionLogo.imageset` holding only `Contents.json` and `TMDBAttributionLogo.svg` with sha256 `9665a76b…5648` (the file TMDB publishes, unaltered), loaded only as `Image("TMDBAttributionLogo")` in `App/Features/Settings/AboutView.swift` (Settings > About > Data Sources). Fixtures `brand-logo/fail4` to `fail8` prove the logo on another screen, an altered file, another catalog, an extra file and any other logo on the About screen all fail |
| `pointless-availability` | `#available` / `@available` for tvOS versions at or below the project target | release-note item |
| `motion` | `withAnimation`, `.animation(`, `.transition(`, ... in a file that never mentions `accessibilityReduceMotion` | rule 4: Reduce Motion |
| `allow-without-reason` | `design-lint:allow` with no text after it | exceptions must carry a reason |
| `upper-case` | `textCase(.uppercase)` | #15 L4: one system section-header style, no manual upper case (#16 item 1.11) |
| `row-background` | in a file under `Settings/` or `Sources/`, or any file with a `Form`: `.listRowBackground(`, `.background(` with a shape, fill or colour, `.clipShape(RoundedRectangle/Capsule)`, `.cornerRadius(` | #15 L2, L3: system List / Form rows only, no pills |
| `fixed-card` | in a file with a `ScrollView`, `List` or `Form`: `.frame(` with `height:` / `maxHeight:` (not `.infinity`), `.presentationDetents(` | #15 L7: no fixed-height card that clips scrolling content |
| `short-line` | `.lineLimit(1)` with no `.minimumScaleFactor` within three lines | rule S1: short texts scale to fit (App/Shared/FittingLine.swift), never "…" |
| `pushed-title` | a `.navigationTitle(` in a file that neither hides the navigation bar nor uses `.pushedScreen(` / `.tabRootScreen(` | #15 D1: no dim centred duplicate title on pushed pages |
| `fixture-claim` | "Tested against a real server" or `.realServer` in a file whose name contains "Fixture" (every scope, also the package modules) | #15 D7: sample data never claims a real-server test |
| `section-title-closure` | `Section("Title") { ... }` (or `Section(title)`) followed by a `header:` or `footer:` closure, matched across lines on the code stream | #23 A: no such SwiftUI initializer, so the App target does not compile (the first CI compile failure); write `Section { } header: { Text("Title") } footer: { }` |
| `form-sheet` | any `.sheet(` presentation | #30, OPEN_QUESTIONS R228: every task screen is full screen; present it with `.taskCover(isPresented:)` or `.taskCover(item:)` (Add a Source: `.addSourceCover`) |

**Rules that cannot be checked in the code** (#16 item 1.11), and how each is verified instead: L1 (rows in a bounded column) and L5 (footers of one or two lines) depend on rendered size: CI screenshots, docs/A11Y_SHOTS.md, device checklist V-08. L9 (each honesty line once per screen) depends on what the three screens show together: screenshots 10 to 19 and 34. L10 (icon and label not touching) and D2 (one button height) are pixel measurements: screenshots, and the shared `Label` / button-row components. D4 and D5 (progress inside the artwork, aligned columns): screenshots 50 to 56. The changed-screen check in UITests/ScreenshotTests.swift catches a "scrolled" capture that did not scroll.

**Exceptions.** `design-lint:allow <reason>` in a comment on the same line or alone on the line above. The reason is required. Every exception in App/ is listed here with its reason (`bash scripts/design-lint.sh --list-allows` prints them):

| File:line | Rule | Reason |
|---|---|---|
| App/Shared/PosterGridLayout.swift (2 lines) | HIG Layout | five-column grid: 40 pt horizontal spacing and 100 pt minimum vertical spacing (section 4) |
| App/Shared/CardRow.swift (2 lines) | HIG Layout | 40 pt spacing between posters in a shelf, and six columns so shelf posters line up with grid posters (section 4) |
| App/Features/Player/PlayerScreen.swift:23 | safe area | the system player draws its own safe areas; the video fills the whole screen |
| App/Features/Player/StatsOverlayView.swift:26 | material | content over video: a translucent standard material, never glass (D-DS9) |
| App/Shared/BackdropView.swift | material | R336 (PROVISIONAL): the system `regularMaterial` over the full-strength detail-page backdrop, Apple's tvOS media catalog sample's product page; a standard material in the content layer (HIG Materials), never glass |
| App/Features/Discover/DiscoverView.swift (2 lines) | HIG Layout | the same 40 pt spacing and six columns as a Home shelf, for the Discover shelves (section 4) |
| App/Features/Settings/LicenseTextsView.swift:34 | focus | a long licence text has no controls, so the scroll view itself takes focus for the Siri Remote to scroll it (`focusable()`, the standard focus API, section 5 item 6) |
| App/Features/Detail/ItemDetailContentView.swift:22, App/Shared/FittingLine.swift:23 and :76 | rule S1 | the system text style shrinks to fit, never below Apple's 23 pt minimum (R165) |
| App/Shared/FittingLine.swift:33 | short-line | hidden measurement of a candidate's natural width, never drawn or spoken; S1 is applied to the visible line |
| App/Features/Settings/AboutView.swift:39 | fixed-card | the TMDB logo's own image height inside the scrolling list, not a card |
| App/Shared/LayoutParts.swift (`TaskButtonRow`) | row-background | #36 S-C (OPEN_QUESTIONS R255, PROVISIONAL): the row around bezeled action buttons draws no background of its own (`Color.clear`), so the system button bezels are the only shape. (The former pushed-title exceptions of the sheet roots are gone: every task cover uses `TaskPage`, which hides the navigation bar, #36 S-B, R254.) |
| App/Shared/GridToolbar.swift (`ToolbarIconGroup`) | custom-glass | #36 6 (OPEN_QUESTIONS R258, PROVISIONAL, owner decision against D-DS9): one `GlassEffectContainer` around the library toolbar's symbol controls so they read as one group; no `glassEffect` of our own, the controls keep their system style. |
| App/Shared/PosterCard.swift (Continue Watching card), App/Features/Shows/SeasonsList.swift (`EpisodeCard`) | custom-focus | #36 7 (OPEN_QUESTIONS R259, PROVISIONAL): `hoverEffect(.highlight)` on the artwork of the two borderless lockups. Apple's tvOS media catalog sample: the borderless style "locates the first `Image`" and attaches this highlight; for a custom view "you can manually attach it". ArtworkView is a custom view whose first Image is clipped, so the system lift was not seen (picture 50). The system effect, not our own. |
| App/Features/Shows/SeasonsList.swift (`EpisodeCard`) | HIG Layout | four columns of the grid width for 16:9 episode cards (R189), now on the artwork inside the label (#36 7, R259; the sample's "make the image the source of the frame calculations") as well as on the card. |

App/Support/Attribution.swift no longer needs exceptions: TMDB and JustWatch are allowlisted, and the TMDB notice is exempt from `claim-wording` because it says "not endorsed". No package module carries an exception.

**Logo allow table** (the only logo in the app; `brand-logo` takes no marker, the exception is fixed in the lint):

| Asset | File | Screen | Source | Rules followed |
|---|---|---|---|---|
| `TMDBAttributionLogo` | `App/Assets.xcassets/TMDBAttributionLogo.imageset/TMDBAttributionLogo.svg`, sha256 `9665a76b1ae401a510ec1e0ca40ddcb3b0cfe45f1d51b77a308fea0845885648`, byte for byte as downloaded | Settings > About > Data Sources, next to the TMDB notice (`App/Features/Settings/AboutView.swift`) | https://www.themoviedb.org/about/logos-attribution, "Primary long (blue)" | TMDB API terms section 3: less prominent than the marks that identify the app, no implied endorsement (the required notice sits next to it); not recoloured or altered; caption height, scaled with Dynamic Type. No size or placement rule is published beyond that (docs/NAMES.md section 4) |

As of 2026-11-18 (after #16 item 1.11): `design-lint: clean, 18 allowed by design-lint:allow, 183 file(s) checked` (`--list-allows` prints the exact lines).

**The `unknown-name` heuristic, exactly** (same text as the lint header). Per string: interpolations `\(...)` (one nesting level), escapes, URLs, absolute paths, file and host names (a dot followed by a lowercase letter), format specifiers, locale identifiers (`en_US`, `en_US_POSIX`) and date-format fields (a word made only of runs of one pattern letter: `EEE`, `MMM`, `yyyy`, `HH:mm:ss`) are blanked. Then every allowlist and generic entry is blanked (longest first, case-sensitive, whole words). A string that is one word in identifier shape (starts lowercase, camel case, or contains `_` `.` `/`) is skipped unless it is a KNOWN name. What remains is reported when it is (a) a KNOWN third-party name (a fixed list in the lint; it holds no media-player applications), (b) camel shape, (c) letters mixed with digits, (d) all capitals of two or more characters, (e) inside a sentence (at least three lowercase-initial words, at least 40% of the words) a capitalised word that is not first and does not follow `. ! ? : > ( "` or a dash, or (f) a capitalised word followed by a format-like token (a layout such as 7.1, a number, or "Profile").

**What the lint cannot do** (it is text matching, not a Swift parser): it sees one line at a time, so a modifier split over lines can be missed or a number computed elsewhere is invisible; `Image` inside a control is tracked by brace depth and can be wrong on unusual formatting; `@State` macro rules, Dynamic Type reflow, contrast, focus order and "does it look native" are not checkable; strings built at run time and text that arrives as data (provider names from TMDB, server and file names) are not seen. Names rules: a third-party name spelled as one ordinary capitalised word at the start of a sentence or in a Title Case string is caught only when it is in the KNOWN list; an ordinary word that trips (b) to (f) must be added to `names-generic`; a code-only string in a package module that trips them takes a `design-lint:allow`; it cannot judge whether a claim is true, only whether it uses certification wording; asset images are judged by their names, not their pixels. Passing the lint is necessary, not sufficient.

---

## 11. Unverified list (visual fidelity)

1. **Everything looks like the system only if a person sees it on an Apple TV.** Not compiled, not simulated, not seen.
2. Whether `"27.2"` is accepted as the Codemagic `xcode:` value (D-DS2); whether Xcode 27.2 compiles the catalog and project as written; Codemagic compile minutes on a Mac mini (instance type left as `mac_mini_m2`; the 27.2 page also lists a Mac mini M4 [V]; M4 is a different machine and the minute estimate in `codemagic.yaml` is unmeasured either way).
3. Which Apple TV models run tvOS 27 (D-DS1); the user's own model.
4. Whether a SwiftUI app with the explicit minimal scene manifest passes the scene requirement at launch (D-DS4).
5. SF Symbol names: `house`, `film`, `tv`, `folder`, `sparkles`, `magnifyingglass`, `gearshape`, `externaldrive.connected.to.line.below`. All are long-standing names; **not verified to exist in the SF Symbols release that ships with tvOS 27** (no machine-readable list was available; check in the first Simulator run: a missing name renders an empty image and logs a warning).
6. The seven-tab bar, `Tab(role: .search)` placement and the tab-bar look with a hideable tab.
7. `.card` focus lift clipping in rows; `scrollClipDisabled()` need.
8. Whether the Playback Stats overlay is legible over bright and over dark video with a standard material; image-retention note.
9. `contextualActions` timing against the transport bar; `AVContentProposal` behaviour with our own countdown.
10. `AsyncImage` + custom `URLSession` with authenticated or non-HTTP artwork (D-DS5).
11. `.bordered` text field style on tvOS (D-DS12).
12. Larger Text, Bold Text, Reduce Motion, Reduce Transparency, Increase Contrast, light and dark appearance: none exercised.
13. Names (D-DS7): (a) and (c) of the old brand questions are answered by the user's names rule (real names everywhere, docs/NAMES.md). (b) The TMDB notice is shown word for word (Settings > About, Online Lookup, Discover); the TMDB logo, which TMDB's terms require, is the one logo exception (user decision R148), shown only in Settings > About > Data Sources. Whether the SVG renders with its original gradient on the device is not seen (device check N12). Whether the About section reads well with VoiceOver and Larger Text is not seen.

## Shared layout parts (#15, OPEN_QUESTIONS R177)

Screens use these parts instead of drawing their own. All of them are in App/Shared.

| Part | File | Rule | Use |
|---|---|---|---|
| `SlotLabel` | LayoutParts.swift | L10, D2 | A symbol and title with the system spacing, the symbol in a fixed slot scaled with the text. Every button label on the detail pages and every list row (through `RowLabel`). |
| `SymbolColumn` | LayoutParts.swift | D5 | A value-column symbol (the watched check) that keeps its slot when hidden, so columns line up. |
| `TaskButton` + `TaskButtonRow` | LayoutParts.swift | D2, equal size | #36 S-C (R255, PROVISIONAL): action buttons (Connect, Cancel, Save, Done, Check Connection, Sync Now and the rest) as bezeled system buttons, label centred, at least 66 pt high (HIG Accessibility, tvOS default control size), the most likely action `.borderedProminent`, the others `.bordered`; side by side they share the row equally. Rows that open a page stay rows. |
| `TextEntryRow` + `TextEntryPage` | TextEntryPage.swift | L2, S1 | R320, R321 and R333 (PROVISIONAL): every text value the user types (source forms through `SourceFieldRow`, Settings > Online Lookup's Enter Key / Replace Key, the Move cover) is ONE system `NavigationLink` row with `LabeledContent`: the name leading, the value trailing in the secondary level, nothing when empty, eight dots for a secret (never the key). Select opens the entry page: the name as the heading, one sentence, one system text or secure field with the right keyboard (`TextEntryRules`, `SourceFieldEntry`). No field is drawn inside a row platter. Replaces `FieldRow` (R256, R265, R273), removed with R333. UNVERIFIED until the next compile run (36, 66, 11 to 19). |
| `ToolbarIconGroup` + `EqualWidthHStack` | GridToolbar.swift | equal size | #36 6 (R258, PROVISIONAL): the library toolbar's symbol controls as one group, one shared glass container, every control the width of the widest and the height of the tallest, 40 pt apart (`GridToolbarLayout`). |
| `CardCaption` | PosterCard.swift | S1, L7, equal size | #36 group 4 (R264, PROVISIONAL; replaces the one-line marquee of R259): the title of a lockup card (Continue Watching, episode): one Caption line shrunk to no lower than 23 pt, else the floor size (Caption 2) wrapped onto as many lines as it needs, never cut; every card of a row reserves the row's tallest caption height (`equalCaptionRow`), and the artwork keeps its height. |
| `StatusText` | LayoutParts.swift | L3 | Status and explanations: secondary callout text, never a row, pill or button. |
| `LearnMoreLink` + `LongTextPage` | LayoutParts.swift, LongTextPage.swift | L5 | A one- or two-line footer, with the complete text one press away ("Learn More", "What Is Sent"). |
| Progress inside the artwork | PosterCard.swift | D4 | A `ProgressView` overlaid on the artwork's bottom edge, so it moves with the focused card. |
| Time left as text | ItemDetailContentView.swift (`ItemDetailContent.timeLeft`) | D3 | No full-width progress bar on a detail page. |

There are two poster widths only: the shelf poster (six columns, CardRow.swift) and the grid poster (five columns, PosterGridLayout.swift). Part 4.2 records the measured widths.
