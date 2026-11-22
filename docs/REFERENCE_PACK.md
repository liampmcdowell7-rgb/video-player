# Reference pack: the Apple pages each screen follows (21 Nov 2026)

The standing reference for every session (R312: design follows Apple's TV app; native system components only). Every
link below was opened on 21 Nov 2026 through Apple's documentation (HIG, SwiftUI, AVKit, TVUIKit, MediaPlayer, the
sample and the WWDC video pages). Links that could not be opened are marked **UNVERIFIED**. Quotes are short and
verbatim. Nothing here has been compiled or checked on tvOS (R318); a page saying something is not proof the app does it.

Prefixes used below:
- HIG = https://developer.apple.com/design/human-interface-guidelines/
- SwiftUI = https://developer.apple.com/documentation/swiftui/
- Sample = https://developer.apple.com/documentation/swiftui/creating-a-tvos-media-catalog-app-in-swiftui (tvOS 18.0+,
  tied to WWDC24 session 10207). Its named parts are given in square brackets, e.g. [Display content shelves].

## 1. Link index

### HIG pages (all opened)

| Page | Link | What to take |
|---|---|---|
| Designing for tvOS | https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos | Content first, edge to edge, seen from 8+ ft; "Embrace the tvOS focus system". |
| Focus and selection | https://developer.apple.com/design/human-interface-guidelines/focus-and-selection | Every element reachable; system focus effects; up to five focus states; no pointer. |
| Layout | https://developer.apple.com/design/human-interface-guidelines/layout | Safe area 60 pt top and bottom, 80 pt sides; grid tables for 2 to 9 columns (e.g. 6 columns: 260 pt wide, 40 pt gap, 100 pt row gap). |
| Typography | https://developer.apple.com/design/human-interface-guidelines/typography | tvOS text styles (Title 1 76 pt to Caption 2 23 pt); body 29 pt, 23 pt minimum. |
| Color | https://developer.apple.com/design/human-interface-guidelines/color | Palette defers to content; "Avoid using only color to indicate focus." |
| Materials | https://developer.apple.com/design/human-interface-guidelines/materials | Liquid Glass for navigation and focused controls; standard materials (ultraThin to thick) in the content layer. |
| Images | https://developer.apple.com/design/human-interface-guidelines/images | Layered images give the focus parallax; "Layered images are at the heart of the Apple TV user experience." |
| Tab bars | https://developer.apple.com/design/human-interface-guidelines/tab-bars | Its tvOS section still describes the top tab bar (68 pt, 46 pt from the top); the app uses the sidebar instead (see WWDC24 10207). |
| Sidebars | https://developer.apple.com/design/human-interface-guidelines/sidebars | No tvOS extras; "Extend visually rich content beneath the sidebar." |
| Toolbars | https://developer.apple.com/design/human-interface-guidelines/toolbars | "No additional considerations for tvOS."; system symbols without borders. |
| Menus | https://developer.apple.com/design/human-interface-guidelines/menus | Short verb labels, frequent items first, one submenu level at most. |
| Lists and tables | https://developer.apple.com/design/human-interface-guidelines/lists-and-tables | A focused row highlights and grows; don't mask images yourself. |
| Collections | https://developer.apple.com/design/human-interface-guidelines/collections | Standard rows and grids; padding so the focus effect is easy to see. |
| Buttons | https://developer.apple.com/design/human-interface-guidelines/buttons | One or two prominent buttons per view; a custom button needs a press state. |
| Pickers | https://developer.apple.com/design/human-interface-guidelines/pickers | "Pickers are available in tvOS with SwiftUI." |
| Text fields | https://developer.apple.com/design/human-interface-guidelines/text-fields | "Minimize text entry in your tvOS and watchOS apps." |
| Searching | https://developer.apple.com/design/human-interface-guidelines/searching | One search location (a tab, as in the TV app), with suggestions. |
| Search fields | https://developer.apple.com/design/human-interface-guidelines/search-fields | tvOS search is a keyboard screen with results below; popular and recent suggestions. |
| Playing video | https://developer.apple.com/design/human-interface-guidelines/playing-video | System player and its tabs; "Avoid asking people if they want to resume playback."; after playback show the detail screen; a spinner on black only after 2 s. |
| Remotes | https://developer.apple.com/design/human-interface-guidelines/remotes | Standard gestures; Back opens the parent screen; Play/Pause must work during playback. |
| SF Symbols | https://developer.apple.com/design/human-interface-guidelines/sf-symbols | System symbols; fill variant for selection; animate sparingly. |
| Alerts | https://developer.apple.com/design/human-interface-guidelines/alerts | "Avoid using an alert merely to provide information."; Menu/Back cancels. |
| Action sheets | https://developer.apple.com/design/human-interface-guidelines/action-sheets | `confirmationDialog` in SwiftUI; use sparingly; destructive choice on top. |
| Progress indicators | https://developer.apple.com/design/human-interface-guidelines/progress-indicators | Prefer determinate progress; keep indicators moving. |
| Loading | https://developer.apple.com/design/human-interface-guidelines/loading | "Show something as soon as possible." (placeholders). |
| Managing accounts | https://developer.apple.com/design/human-interface-guidelines/managing-accounts | "Prefer letting people use another device to sign up or authenticate." |
| Settings | https://developer.apple.com/design/human-interface-guidelines/settings | "Minimize the number of settings you offer."; sensible defaults. |
| Onboarding | https://developer.apple.com/design/human-interface-guidelines/onboarding | Fast and optional. |
| Accessibility | https://developer.apple.com/design/human-interface-guidelines/accessibility | tvOS controls 66×66 pt default, 56 pt minimum; captions; Dim Flashing Lights. |
| Going full screen | https://developer.apple.com/design/human-interface-guidelines/going-full-screen | Not applicable: tvOS apps are always full screen. |

### SwiftUI and framework pages (all opened, all list tvOS)

| Component | Link | tvOS | What to take |
|---|---|---|---|
| TabView | https://developer.apple.com/documentation/swiftui/tabview | 13.0+ | Holds `Tab`s; `init(selection:)` for code-driven selection. |
| Tab | https://developer.apple.com/documentation/swiftui/tab | 18.0+ | The tvOS 18 tab type. |
| TabSection | https://developer.apple.com/documentation/swiftui/tabsection | 18.0+ | Second level in the sidebar. |
| sidebarAdaptable | https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable | 18.0+ | "macOS and tvOS always show a sidebar." `TabViewCustomization` is not on tvOS. |
| NavigationStack | https://developer.apple.com/documentation/swiftui/navigationstack | 16.0+ | Path binding for code-driven pushes. |
| NavigationLink | https://developer.apple.com/documentation/swiftui/navigationlink | 13.0+ | `NavigationLink(value:)` with `navigationDestination`. |
| navigationDestination | https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:) | 16.0+ | Never inside a lazy container. |
| List | https://developer.apple.com/documentation/swiftui/list | 13.0+ | System rows and sections. |
| Form | https://developer.apple.com/documentation/swiftui/form | 13.0+ | Platform styling for settings. |
| Section | https://developer.apple.com/documentation/swiftui/section | 13.0+ | Headers and footers in List, Form, Picker. |
| LabeledContent | https://developer.apple.com/documentation/swiftui/labeledcontent | 16.0+ | Label and value rows; can be a link's label. |
| Picker | https://developer.apple.com/documentation/swiftui/picker | 13.0+ | Tagged options. |
| Segmented style | https://developer.apple.com/documentation/swiftui/pickerstyle/segmented | 13.0+ | 2 to 5 options. |
| Navigation-link picker | https://developer.apple.com/documentation/swiftui/pickerstyle/navigationlink | 16.0+ | Pushes a list; for long option lists (Region). |
| Toggle | https://developer.apple.com/documentation/swiftui/toggle | 13.0+ | Subtitle via a second `Text`. |
| TextField | https://developer.apple.com/documentation/swiftui/textfield | 13.0+ | Prompt and `onSubmit`. |
| SecureField | https://developer.apple.com/documentation/swiftui/securefield | 13.0+ | Hidden entry for keys and passwords. |
| Menu | https://developer.apple.com/documentation/swiftui/menu | 17.0+ | Submenus, `primaryAction`. |
| Card button style | https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/card | 14.0+ | Dense lockups; edge-to-edge content, Liquid Glass on focus. |
| Borderless button style | https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/borderless | 17.0+ | The main lockup: the first image lifts on focus. |
| Bordered prominent | https://developer.apple.com/documentation/swiftui/borderedprominentbuttonstyle | 15.0+ | The one prominent action (Play). |
| LazyHStack | https://developer.apple.com/documentation/swiftui/lazyhstack | 14.0+ | Shelves. |
| LazyVGrid | https://developer.apple.com/documentation/swiftui/lazyvgrid | 14.0+ | Grids and search results. |
| ScrollView | https://developer.apple.com/documentation/swiftui/scrollview | 13.0+ | `defaultScrollAnchor`, `ScrollViewReader`. |
| scrollClipDisabled | https://developer.apple.com/documentation/swiftui/view/scrollclipdisabled(_:) | 17.0+ | Focus lift and shadow are not cut. |
| containerRelativeFrame | https://developer.apple.com/documentation/swiftui/view/containerrelativeframe(_:count:span:spacing:alignment:) | 17.0+ | N items across the width. |
| focusSection | https://developer.apple.com/documentation/swiftui/view/focussection() | 15.0+ | Empty space passes focus moves to its contents. |
| defaultFocus | https://developer.apple.com/documentation/swiftui/view/defaultfocus(_:_:priority:) | 16.0+ | First focus of a screen. |
| focusable | https://developer.apple.com/documentation/swiftui/view/focusable(_:) | 15.0+ | Focus on a non-control (long text blocks). |
| hoverEffect | https://developer.apple.com/documentation/swiftui/view/hovereffect(_:isenabled:) | 17.0+ | Puts the focus effect on the chosen view. |
| toolbar | https://developer.apple.com/documentation/swiftui/view/toolbar(content:) | 14.0+ | `ToolbarItem`, `ToolbarItemGroup`. |
| searchable | https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:) | 16.0+ | The whole system search screen. |
| contextMenu | https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:) | 14.0+ | Long-press menu. The page is flagged deprecated: check the replacement before new use. |
| confirmationDialog | https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:) | 16.0+ | On tvOS only `Text`-labelled actions show. |
| alert | https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:message:) | 16.0+ | Text labels, plain-text message. |
| fullScreenCover | https://developer.apple.com/documentation/swiftui/view/fullscreencover(ispresented:ondismiss:content:) | 14.0+ | Full-screen modal (long description, player). |
| sheet | https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:) | 13.0+ | Modal sheet. |
| ProgressView | https://developer.apple.com/documentation/swiftui/progressview | 14.0+ | Determinate or indeterminate. |
| ContentUnavailableView | https://developer.apple.com/documentation/swiftui/contentunavailableview | 17.0+ | Empty, error and no-results states; `.search` built in. |
| ViewThatFits | https://developer.apple.com/documentation/swiftui/viewthatfits | 16.0+ | First child that fits. |
| Material, regular | https://developer.apple.com/documentation/swiftui/material, https://developer.apple.com/documentation/swiftui/material/regular | 15.0+ | `.regularMaterial`; a custom foreground style turns off vibrancy. |
| AsyncImage | https://developer.apple.com/documentation/swiftui/asyncimage | 15.0+ | Phase-based loading. |
| AVPlayerViewController | https://developer.apple.com/documentation/avkit/avplayerviewcontroller | 9.0+ | The system player; do not subclass. |
| customInfoViewControllers | https://developer.apple.com/documentation/avkit/avplayerviewcontroller/custominfoviewcontrollers | 15.0+ | Info-panel tabs, titled by each controller's `title`; the tallest sets the height. |
| contextualActions | https://developer.apple.com/documentation/avkit/avplayerviewcontroller/contextualactions | 15.0+ | Timed actions such as Skip Intro, shown while the transport bar is hidden. |
| Customizing the tvOS playback experience | https://developer.apple.com/documentation/avkit/customizing-the-tvos-playback-experience | article | `externalMetadata`, transport-bar items, info tabs, contextual actions. |
| VideoPlayer | https://developer.apple.com/documentation/avkit/videoplayer | 14.0+ | SwiftUI player (the app uses `AVPlayerViewController`). |
| TVMonogramView | https://developer.apple.com/documentation/tvuikit/tvmonogramview | 12.0+ | Deprecated; the page names `TVMonogramContentView`. |
| MPNowPlayingInfoCenter | https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter | 5.0+ | `nowPlayingInfo` for the iPhone remote and Control Center. |

### The sample's named parts (opened)

| Part | Pattern |
|---|---|
| [StackView] | Landing page: shelves under a hero header. |
| [Create content lockups] | `.borderless` lockup, `Image` and `Text` siblings, `hoverEffect(.highlight)`, circle shape for people. |
| [Show information-dense lockups] | `.card` style with padded stacks. |
| [Display content shelves] | `ScrollView(.horizontal)` + `LazyHStack(spacing: 40)` + `.scrollClipDisabled()` + `containerRelativeFrame(count: 6)`. |
| [Show content above and below the fold] | Header at 0.8 of the height with `focusSection()`; `.regularMaterial` masked by a `LinearGradient`. |
| [Snap at the fold point] | A custom `ScrollTargetBehavior`. |
| [Provide product highlight pages] | Blurred artwork, equal-width bordered buttons in a `VStack(spacing: 12)`, description as a `.plain` button opening a `fullScreenCover`. |
| [Search for content] | `LazyVGrid` of 4 flexible columns, `.searchable` + `.searchSuggestions`. |
| [SidebarContentView] | A sectioned sidebar with the tvOS 18 tab APIs. Named on the page; **its code is not shown** (UNVERIFIED how it is built). |
| [ButtonsView] | Every tvOS button style. Named; no code on the page. |

### WWDC sessions (https://developer.apple.com/videos/play/...)

| Session | Link | What to take |
|---|---|---|
| Migrate your TVML app to SwiftUI (2024) | https://developer.apple.com/videos/play/wwdc2024/10207 | The sample's session: lockups, shelves, edge-to-edge hero, search tab, the TV app's sidebar via `.sidebarAdaptable`. |
| Build SwiftUI apps for tvOS (2020) | https://developer.apple.com/videos/play/wwdc2020/10042 | Card style, context menus, focus state, default focus, shelves. |
| Deliver a great playback experience on tvOS (2021) | https://developer.apple.com/videos/play/wwdc2021/10191 | Player title view, transport-bar menus, info tabs, contextual actions, metadata; "avoid adding extra gestures to the player." |
| Mastering the Living Room With tvOS (2019) | https://developer.apple.com/videos/play/wwdc2019/211 | Content-first, edge-to-edge design; profiles. |
| Discover search suggestions for Apple TV (2020) | https://developer.apple.com/videos/play/wwdc2020/10634 | Search suggestions; do not cover the keyboard. |
| Master Picture in Picture on tvOS (2020) | https://developer.apple.com/videos/play/wwdc2020/10176 | PiP with `AVPlayerViewController`; no custom swipe-up gesture. |
| Support multiple users in your tvOS app (2020) | https://developer.apple.com/videos/play/wwdc2020/10645 | Per-person data with "Runs as Current User". |
| Simplify sign in for your tvOS apps (2021) | https://developer.apple.com/videos/play/wwdc2021/10279 | One Sign In button; finish on iPhone or iPad. |
| Get to know the new design system (2025) | https://developer.apple.com/videos/play/wwdc2025/356 | Opened; general Liquid Glass direction, not tvOS-specific. |
| Build a SwiftUI app with the new design (2025) | https://developer.apple.com/videos/play/wwdc2025/323 | Opened; general, not tvOS-specific. |
| Design intuitive search experiences (2026) | https://developer.apple.com/videos/play/wwdc2026/292 | Opened; mentions the TV app's search tab only as an iOS example. |
| Direct and reflect focus in SwiftUI (2021) | https://developer.apple.com/videos/play/wwdc2021/10023 | Opened 21 Nov 2026 (for docs/AUDIT_AGAINST_REFERENCE_PACK.md). `@FocusState` with `focused(_:equals:)` reads and moves focus on tvOS; "directional focus navigation is based on adjacency relationships", so a swipe reaches only a neighbouring focusable element; `focusSection()` makes a container one large target. |
| Deep Linking on tvOS (2017) | https://developer.apple.com/videos/play/wwdc2017/246 | **UNVERIFIED** (found in search, not opened). |
| Discover Continuity Camera for tvOS (2023) | https://developer.apple.com/videos/play/wwdc2023/10256 | **UNVERIFIED**, and not needed by this app. |

No session titled "Designing for tvOS" or "What's new in tvOS" was found.

## 2. Screen by screen

Each line: the page, then what to take for that screen. Full links are in section 1.

### App shell: sidebar (Home, Movies, Shows, Files, Search, Settings)
- SwiftUI tabview, tab, tabsection, tabviewstyle/sidebaradaptable: the sidebar and its Library section; no customization on tvOS.
- HIG sidebars: content extends beneath the sidebar.
- HIG tab-bars: Back returns focus to the navigation; its tvOS text predates the sidebar (UNVERIFIED how much still applies).
- Sample [SidebarContentView]: the sectioned sidebar (code not shown).
- WWDC24 10207: the TV app's sidebar through `.sidebarAdaptable`.
- HIG remotes: Back opens the parent screen.

### Home
- HIG designing-for-tvos: edge-to-edge artwork, content first.
- Sample [StackView], [Show content above and below the fold], [Snap at the fold point]: hero header then shelves; the header at 0.8 of the screen height (the only Apple source for a hero fraction; see Gaps), `focusSection`, material gradient.
- Sample [Display content shelves], [Create content lockups]: shelf and lockup code.
- SwiftUI lazyhstack, view/scrollclipdisabled(_:), view/containerrelativeframe(…), view/focussection(), primitivebuttonstyle/borderless, borderedprominentbuttonstyle.
- HIG layout: safe area and spacing; HIG materials: material over artwork; HIG loading: placeholders early.

### Movies and Shows (grids, Sort and Filter, saved views, A to Z)
- HIG collections and HIG layout: grid columns and gaps (layout's 2-to-9-column table).
- SwiftUI lazyvgrid, primitivebuttonstyle/borderless, view/focussection().
- HIG toolbars, SwiftUI view/toolbar(content:): the system toolbar for Sort and Filter.
- HIG menus, SwiftUI menu, picker, toggle: the Sort and Filter menus.
- HIG sf-symbols: fill variant while a filter is on.
- SwiftUI contentunavailableview: an empty library or no matches.

### Files (and file details)
- HIG lists-and-tables, SwiftUI list, section, navigationlink: folders and files as system rows.
- SwiftUI sheet, labeledcontent: file details.
- SwiftUI contentunavailableview: an empty folder.

### Search
- HIG searching and HIG search-fields: one search tab, keyboard screen, suggestions.
- SwiftUI view/searchable(text:placement:prompt:), lazyvgrid, contentunavailableview (`.search`).
- Sample [Search for content]: 4-column grid of borderless lockups with suggestions.
- WWDC20 10634: search suggestions.

### Settings and each Settings page (Sources, Library, Home Screen, Playback, Online Lookup, Accessibility, Backup, Storage, About, Full Licence Texts)
- HIG settings: few settings, sensible defaults.
- SwiftUI form, list, section, labeledcontent, toggle, picker, navigationlink: rows of one system style.
- SwiftUI pickerstyle/navigationlink: long option lists such as Online Lookup > Region.
- SwiftUI securefield, HIG text-fields: entering an online key; little typing.
- SwiftUI view/confirmationdialog(…), HIG action-sheets: Backup and Storage clear or restore choices.
- SwiftUI progressview, HIG progress-indicators: backup and scan progress.
- HIG typography and HIG accessibility: Accessibility page (text sizes, captions).
- HIG lists-and-tables: Full Licence Texts as a plain list of system rows.

### Add a Source and its forms (kind list, discovery, field entry, Plex setup)
- SwiftUI navigationstack, view/navigationdestination(for:destination:), sheet: the setup flow.
- SwiftUI form, section, labeledcontent, textfield, securefield, picker: the form rows.
- HIG text-fields: minimise typing; right keyboard type.
- HIG managing-accounts, WWDC21 10279: sign-in from another device where a source supports it.
- SwiftUI progressview, contentunavailableview, alert: connecting, nothing found, a failure.
- HIG alerts: alerts only when a choice is needed.

### Movie page and show page (product pages, seasons, episodes, cast, Information)
- Sample [Provide product highlight pages]: blurred artwork, equal-width buttons, description opening a `fullScreenCover`.
- Sample [Show content above and below the fold]: hero area and material gradient.
- SwiftUI borderedprominentbuttonstyle, view/fullscreencover(…), view/defaultfocus(…), view/focussection(), view/focusable(_:).
- SwiftUI pickerstyle/segmented: season tabs (2 to 5; more seasons need another style, UNVERIFIED which the TV app uses).
- Sample [Display content shelves] and [Create content lockups]: episode and cast shelves; circle lockups for people.
- TVUIKit tvmonogramview: deprecated; `TVMonogramContentView` for initials (UIKit only).
- SwiftUI menu: Versions and Extras menus. SwiftUI labeledcontent: the Information rows.
- HIG materials, HIG images: material over artwork; layered artwork.

### Person page
- Sample [Create content lockups]: circle lockup for the person; borderless lockups for titles.
- SwiftUI lazyvgrid or lazyhstack, primitivebuttonstyle/card where the lockups are dense.

### Discover (and Discover title page)
- Sample [Display content shelves], [Show information-dense lockups]: shelves; `.card` for dense lockups.
- SwiftUI view/contextmenu(menuitems:): long-press actions (the page is flagged deprecated).
- HIG collections: padding for the focus effect.
- HIG focus-and-selection: every element must be reachable by focus ("make sure that people can bring focus to every
  element"), including the Missing Episodes lines and the where-to-watch text.
- WWDC21 10023 (Direct and reflect focus in SwiftUI): a swipe reaches only a neighbouring focusable element, so a
  shelf or line with nothing focusable next to it in that direction cannot be reached; `focusSection()` helps.

### Player and its info panel
- HIG playing-video: system player, no resume question, detail screen after playback, spinner only after 2 s.
- AVKit avplayerviewcontroller and the article "Customizing the tvOS playback experience".
- AVKit custominfoviewcontrollers: the info panel's tabs (Info, Episodes, Playback Stats).
- AVKit contextualactions: Skip Intro and Skip Credits.
- MediaPlayer mpnowplayinginfocenter: iPhone Now Playing.
- HIG remotes: Play/Pause and Back behaviour.
- WWDC21 10191 and WWDC20 10176: playback experience and Picture in Picture.

### Up Next
- AVKit avplayerviewcontroller: its "next episode" proposal (the system Up Next, R340).
- HIG playing-video: what follows playback.
- WWDC21 10191: content proposals.

### Needs Review and Move
- SwiftUI list, section, navigationlink, view/toolbar(content:): the review list.
- SwiftUI view/confirmationdialog(…), HIG action-sheets: Move choices and destructive actions.
- SwiftUI sheet, picker: the Move sheet.
- SwiftUI progressview: work in progress.

## 3. Gaps

- The sample's [SidebarContentView] and [ButtonsView] have no code on the page.
- The HIG tab-bars page describes the top tab bar, not the tvOS 18 sidebar.
- Two WWDC sessions are still marked UNVERIFIED here (wwdc2017/246, wwdc2023/10256). Both were opened on 21 Nov 2026;
  what they say is in docs/AUDIT_AGAINST_REFERENCE_PACK.md section 3.
- Hero fractions: only Apple's media catalog sample gives one. Its [Show content above and below the fold] code sizes
  the landing page's header to 0.8 of the screen height (`containerRelativeFrame(.vertical)`, `length * 0.8`). That
  covers the landing page (Home) only. No HIG page gives a hero fraction, and neither the sample nor the HIG gives one
  for a product page.
- Grid columns: HIG Layout gives column widths and spacing for 2 to 9 columns, but no Apple page says how many columns
  a given screen should use.
- The title-logo box: no Apple page gives a size. The app's own numbers are listed in docs/AUDIT_INVENTED_UI.md.
