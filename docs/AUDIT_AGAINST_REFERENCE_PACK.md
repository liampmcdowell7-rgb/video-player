# Audit against the reference pack (21 Nov 2026)

Read-only. The screens in docs/REFERENCE_PACK.md checked against their Apple pages, mainly the ones
docs/AUDIT_INVENTED_UI.md did not reach: the player and its info panel, Up Next, each Settings page, Add a Source and
its forms, Discover, Needs Review, Move and the person page. Line numbers are at commit 0adccb8. Other sessions were
editing some of these files while this was written, so the working copy may differ. Nothing was compiled or run on tvOS
(R318).

Rule used (R312): Apple's TV app and Apple's own samples first. When an Apple page only suggests something, the finding
is "ask the owner", never a bug. Recommendations: **Replace** (a system component or a sample pattern does it),
**Keep** (the app already follows the page, or Apple has nothing), **Ask** (the owner decides). UNVERIFIED marks what
no page settles.

## 1. Findings

### Player and its info panel

| # | File and line | What the app does | Apple page and what it says | Recommendation |
|---|---|---|---|---|
| 1 | `App/Features/Player/PlayerCoordinator.swift:351` | A notice about the playback (no sound, say) is a `UIAlertController` with only an OK button, early in playback. | HIG Alerts, https://developer.apple.com/design/human-interface-guidelines/alerts: "Avoid using an alert merely to provide information." | **Ask**. The alert stops the video for information only. Alternatives: a line in the Info tab, or a contextual action that opens the text. |
| 2 | `App/Features/Player/PlayerInfoPanels.swift:68-94` | Playback Stats: a 3-column grid of `LabeledContent`, none focusable. | HIG Focus and selection, https://developer.apple.com/design/human-interface-guidelines/focus-and-selection: "make sure that people can bring focus to every element". | **Ask**. Fine while every row fits in the panel height (#3); rows below it could not be reached. UNVERIFIED how many rows fit. |
| 3 | `App/Features/Player/PlayerInfoPanels.swift:14,20` | Every info tab is 420 pt high (`preferredContentSize`). | AVKit customInfoViewControllers, https://developer.apple.com/documentation/avkit/avplayerviewcontroller/custominfoviewcontrollers: the tallest tab sets the height for all. | **Keep** (follows the page); whether 420 pt is enough is UNVERIFIED. |
| 4 | `App/Features/Player/PlayerInfoPanels.swift:84` | A warning value in Playback Stats is told apart by orange text alone. | HIG Color, https://developer.apple.com/design/human-interface-guidelines/color: "Avoid using only color to indicate focus." (said of focus, not of warnings). | **Ask**. No page read says this for warnings, so UNVERIFIED; a word or symbol next to the value would not rely on colour. |
| 5 | `App/Features/Player/PlayerInfoPanels.swift:38` | In the Episodes tab the current episode is a focusable button that does nothing when pressed. | HIG Buttons, https://developer.apple.com/design/human-interface-guidelines/buttons: "Always include a press state for a custom button." | **Keep**. The system press state still shows. Whether a no-op press confuses is UNVERIFIED. |
| 6 | `App/Features/Player/SkipButtonPresenter.swift:12-13` | Skip Intro and Skip Credits are `contextualActions`. | AVKit contextualActions, https://developer.apple.com/documentation/avkit/avplayerviewcontroller/contextualactions: timed actions such as a skip button. | **Keep** (the system pattern). |
| 7 | `App/Features/Player/PlayerMarkMenu.swift:72` | The result of the last mark is shown as a disabled item at the top of the Mark Skip Points menu. | HIG Menus, https://developer.apple.com/design/human-interface-guidelines/menus: "Prefer listing important or frequently used menu items first." | **Ask**. A status line takes the top place in the menu (rule L3: status text is never drawn as a row or button). |
| 8 | `App/Features/Player/PlayerMarkMenu.swift:96`, `PlayerCoordinator.swift:453` | Mark Skip Points is a `UIMenu` in `transportBarCustomMenuItems`. | AVKit article, https://developer.apple.com/documentation/avkit/customizing-the-tvos-playback-experience: custom transport-bar items. | **Keep**. |
| 9 | `App/Features/Player/PlayerCoordinator.swift:92,112-117` | Now Playing comes from `AVPlayerItem.externalMetadata`; the app writes no `MPNowPlayingInfoCenter` values. | AVKit article (`externalMetadata`); MediaPlayer, https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter. | **Keep**. The pack's player entry lists `MPNowPlayingInfoCenter`; for this app the source is `externalMetadata` (the pack is not edited here). |
| 10 | `App/Features/Detail/ItemDetailContentView.swift:94` | Play resumes, and Start Over is its own button: no "resume?" question. | HIG Playing video, https://developer.apple.com/design/human-interface-guidelines/playing-video: "Avoid asking people if they want to resume playback." | **Keep** (follows the page). |

Already decided in docs/AUDIT_INVENTED_UI.md: the Episodes tab's 4 columns and the stats grid columns (finding #14).

### Up Next

| # | File and line | What the app does | Apple page and what it says | Recommendation |
|---|---|---|---|---|
| 11 | `App/Features/Player/ProposalPresenter.swift:27` | The next-episode proposal is made with `previewImage: nil`. | AVKit AVPlayerViewController, https://developer.apple.com/documentation/avkit/avplayerviewcontroller ("next episode" proposals); WWDC21 10191, https://developer.apple.com/videos/play/wwdc2021/10191 (content proposals). | **Ask**. The episode's still would give the card a picture, as the TV app shows one (UNVERIFIED on tvOS 27). |
| 12 | `App/Features/Player/UpNextProposalController.swift:20` | The video shrinks to 960 × 540 at the top while the card shows. | The file quotes Apple's "a 960x540 window centered at the top" (AVKit). | **Keep**. |
| 13 | `App/Features/Player/UpNextProposalController.swift:73-97` | The Up Next card is the app's own view (heading, title, countdown, two buttons). | AVKit: `AVContentProposalViewController` is subclassed for its own content; Apple gives no ready-made card. | **Keep** (Apple has none). |

Already decided: Play Now and Cancel side by side (AUDIT_INVENTED_UI #20).

### Settings pages

| # | File and line | What the app does | Apple page and what it says | Recommendation |
|---|---|---|---|---|
| 14 | `App/Support/OnlineServices.swift:52-57` | Fix Match choices are saved in Application Support (`matches.json`), on this device only (PROVISIONAL in the file). | WWDC23 10256, https://developer.apple.com/videos/play/wwdc2023/10256: on tvOS, use only the caches directory, which can be cleared; keep lasting data in iCloud. The session names `.documentDirectory` as failing; it says nothing about Application Support. | **Ask**. Whether tvOS keeps Application Support is UNVERIFIED. The file's own alternative (a synced record) would match the session. |
| 15 | `App/Features/Settings/AccessibilitySettingsView.swift:22-31` | Shows Reduce Motion, Reduce Transparency, Bold Text and Increase Contrast; not Dim Flashing Lights. | HIG Accessibility, https://developer.apple.com/design/human-interface-guidelines/accessibility: "Allow people to opt out of flashing lights in video playback." | **Ask**. Whether the system player honours Dim Flashing Lights by itself is UNVERIFIED. |
| 16 | `App/Features/Settings/OnlineLookupSettingsView.swift:175-191` | Region is a hand-made pushed page holding an inline `Picker` that closes on a choice (R353). | SwiftUI navigation-link picker style, https://developer.apple.com/documentation/swiftui/pickerstyle/navigationlink: the picker pushes its own list of options. | **Ask**. `.pickerStyle(.navigationLink)` is the system way to do the same thing; R353 (a blank page) came from this row, so any change needs the UI test. |
| 17 | `App/Features/Settings/PlaybackSettingsView.swift:21-38` | Playback has 7 toggles in three sections. | HIG Settings, https://developer.apple.com/design/human-interface-guidelines/settings: "Minimize the number of settings you offer." | **Keep**. Every toggle is a feature the owner asked for; the page only suggests. |
| 18 | `App/Features/Settings/BackupSettingsView.swift:11-13` | Restore progress is determinate when the fraction is known. | HIG Progress indicators, https://developer.apple.com/design/human-interface-guidelines/progress-indicators: "When possible, use a determinate progress indicator." | **Keep** (follows). |
| 19 | `App/Features/Settings/BackupSettingsView.swift:58`, `SourceDetailView.swift:109,115`, `OnlineLookupSettingsView.swift:138` | Restore, Remove and Trust are `confirmationDialog`s with text buttons. | HIG Action sheets, https://developer.apple.com/design/human-interface-guidelines/action-sheets: "Use action sheets sparingly."; SwiftUI: on tvOS only Text-labelled actions show. | **Keep**. Each guards a destructive or trust choice. |
| 20 | `App/Features/Settings/SettingsView.swift:12-24` | Each Settings row has an SF Symbol whose name was written from memory (R178). | HIG SF Symbols, https://developer.apple.com/design/human-interface-guidelines/sf-symbols. | **Keep**; the symbol names stay UNVERIFIED until a run. |
| 21 | `App/Shared/SettingsPane.swift:295` | `SettingToggle` is a system `Toggle` whose label is `FittingText`. | SwiftUI Toggle, https://developer.apple.com/documentation/swiftui/toggle. | **Keep** (system toggle; the label follows rule S1). |

Already decided: Full Licence Texts' list style (AUDIT_INVENTED_UI #21); the two-column pane and task-page sizes (#17, #18).

### Add a Source and its forms

| # | File and line | What the app does | Apple page and what it says | Recommendation |
|---|---|---|---|---|
| 22 | `App/Features/Sources/PlexSetupView.swift:54-62` | "Code expired" is a hand-made stack (title, text, button). The same file uses `ContentUnavailableView` for "no servers" (line 71). | SwiftUI ContentUnavailableView, https://developer.apple.com/documentation/swiftui/contentunavailableview: empty, error and no-results states. | **Replace** with `ContentUnavailableView` and its action, as line 71 already does. |
| 23 | `App/Features/Sources/PlexSetupView.swift:94-117` | Plex sign-in: a code typed on another device. | HIG Managing accounts, https://developer.apple.com/design/human-interface-guidelines/managing-accounts: "Prefer letting people use another device to sign up or authenticate."; WWDC21 10279. | **Keep** (follows). The QR code alternative stays open in R302. |
| 24 | `App/Features/Sources/SourceFieldRow.swift:23,50-52` | A choice field's `Picker` shows the prompt text as its selection while the field is empty. | SwiftUI Picker, https://developer.apple.com/documentation/swiftui/picker: tag each option with the selection type. | **Ask**. If the prompt is not one of the tags, the picker has no matching row. UNVERIFIED what tvOS shows. |
| 25 | `App/Features/Sources/SourceFormView.swift:113-129` | Three alerts: a failure (OK), sign-in (Continue / Cancel), certificate trust (Trust / Cancel). | HIG Alerts: "Avoid using an alert merely to provide information." | **Keep** for sign-in and trust (each asks a choice). The OK-only failure alert is **Ask** (same question as #1). |
| 26 | `App/Features/Sources/SourceFormView.swift:136-140` | While connecting, a spinner and "Connecting" take the Connect button's place. | HIG Progress indicators. | **Keep**. |
| 27 | `App/Features/Sources/SourceKindListView.swift:57-60` | A Cancel button at the end of the list; Back also closes the cover. | HIG Remotes, https://developer.apple.com/design/human-interface-guidelines/remotes: Back opens the parent screen. | **Keep** (R255). |
| 28 | `App/Features/Sources/SourceFormView.swift:48-54` | Server address, user name and password are typed on entry pages. | HIG Text fields, https://developer.apple.com/design/human-interface-guidelines/text-fields: "Minimize text entry in your tvOS and watchOS apps." | **Keep**. Search Your Network is offered first and fills what it can; Apple has no other way for these servers. |

### Discover

| # | File and line | What the app does | Apple page and what it says | Recommendation |
|---|---|---|---|---|
| 29 | `App/Features/Discover/DiscoverView.swift:165-180` | Missing Episodes: plain `Text` lines in a vertical `ScrollView`, none focusable. | HIG Focus and selection: "make sure that people can bring focus to every element". | **Ask**. A long list below the last shelf may not be reachable by the remote. UNVERIFIED on tvOS 27. |
| 30 | `App/Features/Discover/DiscoverTitlePage.swift:19-40` | A Discover title page is a quarter-width poster beside text and one bordered button. | Sample, [Provide product highlight pages], https://developer.apple.com/documentation/swiftui/creating-a-tvos-media-catalog-app-in-swiftui: blurred artwork with equal-width buttons. | **Ask**. The movie and show pages follow the sample; this page does not. |
| 31 | `App/Features/Discover/DiscoverView.swift:157-160` | The where-to-watch line has `lineLimit(3)`, so a long line ends in "…". | Owner's rule L7 (nothing cut mid-line); no Apple page read covers it. | **Ask** (goes with R356). |
| 32 | `App/Features/Discover/DiscoverView.swift:145` | Add to or remove from the watchlist by press and hold (`contextMenu`). The title page has the same action as a button. | SwiftUI contextMenu(menuItems:), https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:): flagged deprecated (section 2). | **Keep** for now; see section 2. |

Already decided: Discover's `.card` style and header text style (AUDIT_INVENTED_UI #23).

### Needs Review and Move

| # | File and line | What the app does | Apple page and what it says | Recommendation |
|---|---|---|---|---|
| 33 | `App/Features/Settings/NeedsReviewView.swift:24-37` | "Nothing to review" and the failure are section text (with a Try Again button). | SwiftUI ContentUnavailableView: empty and error states. | **Ask**. The system view fits; inside the Settings pane the section text keeps rule L1. The owner chooses. |
| 34 | `App/Features/Settings/NeedsReviewView.swift:60-72` | Choosing a file opens a dialog (Move to Movies, Move to Shows), then the Move cover. | HIG Action sheets: "Use action sheets sparingly." | **Keep** (a real choice). |
| 35 | `App/Shared/SortMoveSheet.swift:68-70` | A failed save is said in the section footer, not an alert. | HIG Alerts: "Avoid using an alert merely to provide information." | **Keep** (follows). |
| 36 | `App/Shared/SortMoveSheet.swift:42-61` | Move asks for title and year (and season and episode) on typed entry pages, filled in from the file. | HIG Text fields: "Minimize text entry". | **Keep**. The draft is pre-filled; the person only corrects it. |

Already decided: Move and Cancel side by side (AUDIT_INVENTED_UI #20, #24).

### Person page and deep links

| # | File and line | What the app does | Apple page and what it says | Recommendation |
|---|---|---|---|---|
| 37 | `App/Features/Detail/PersonView.swift:18-19` | The person page shows the name only, with no photo or initials. | Sample, [Create content lockups]: the circle shape for people. | **Ask**. Whether the TV app's person page shows the photo is UNVERIFIED (no photos yet). |
| 38 | `App/Features/Detail/PersonView.swift:24-31` | Movies then shows in one grid, with no heading between them. | HIG Collections, https://developer.apple.com/design/human-interface-guidelines/collections. | **Ask**. Two shelves or two headed grids would say which is which; no page decides. |
| 39 | `App/Shell/RootView.swift:126,191-198` | A deep link opens the title's page on Home's stack, so Back goes to Home, then out. There is no "play" link. | WWDC17 246, https://developer.apple.com/videos/play/wwdc2017/246: Back from a deep-linked page goes to the app's main screen, then out; a play link starts playback with no prompts. | **Keep** for the page link (follows). A play link only matters if a Top Shelf is added: **Ask**. |

Finding count: **39**.

## 2. The two deprecated APIs

Searched `App/` at 0adccb8.

**`contextMenu(menuItems:)`.** Apple's page carries a "Deprecated" flag but names no replacement, and its own text still
recommends the modifier. Its declaration takes `@ContentBuilder`, so the flag may only concern the older `@ViewBuilder`
form. That is UNVERIFIED: read the declaration in the tvOS SDK before changing anything. Uses:
- `App/Shared/CardContextMenu.swift:15`, used by every poster card through `PosterCard.swift:54` and `PosterCard.swift:81`.
- `App/Features/Discover/DiscoverView.swift:145`, the Discover card's watchlist action.
- `App/Features/Shows/SeasonsList.swift:202`, the episode lockup's menu.
- (Outside the app: `scripts/design-lint-fixtures/tap-gesture/pass.swift:5`, a lint test fixture.)

**`TVMonogramView`.** No use. Only comments name `TVMonogramContentView` (its replacement), at
`App/Features/Detail/ItemDetailContentView.swift:194-195`. The cast circle is drawn in SwiftUI
(AUDIT_INVENTED_UI #9).

## 3. The three WWDC sessions the pack marked UNVERIFIED

All three opened on 21 Nov 2026. They replace the pack's UNVERIFIED marks (the pack itself is not edited).

| Session | Link | What it says for this app |
|---|---|---|
| Direct and reflect focus in SwiftUI (WWDC21) | https://developer.apple.com/videos/play/wwdc2021/10023 | `@FocusState` with `focused(_:equals:)` reads and moves focus, on tvOS too. A swipe only reaches a neighbour: "directional focus navigation is based on adjacency relationships." `focusSection()` makes a container one large target; put it on both sides of a split (sidebar and content, shelves and page buttons). Supports findings #2 and #29 and R361. No `defaultFocus` and nothing on the player. |
| Deep Linking on tvOS (WWDC17) | https://developer.apple.com/videos/play/wwdc2017/246 | Top Shelf items have a display link (opens the page) and a play link (starts playback at once: no loading screens, no "start playing?" alert). Build the back stack before showing the page: Back goes to the page, then the main screen, then out. Prefers universal links to a custom scheme. Predates SwiftUI; carrying it to `onOpenURL` is my reading, not the session's. See #39. |
| Discover Continuity Camera for tvOS (WWDC23) | https://developer.apple.com/videos/play/wwdc2023/10256 | About cameras and microphones, which this app does not use. One part applies to every tvOS app: `.documentDirectory` fails at runtime on tvOS; use the caches directory, which can be cleared, and iCloud for data that must last. See #14. |

## 4. Top five

1. #1: an OK-only alert interrupts playback for information (HIG Alerts). Ask.
2. #14: Fix Match choices live in Application Support; WWDC23 says only caches and iCloud on tvOS. Ask; UNVERIFIED.
3. #29: Missing Episodes lines are not focusable, so a long list may not scroll into view (HIG Focus, WWDC21 10023).
   Ask.
4. #22: Plex "code expired" is hand-made where the same file already uses `ContentUnavailableView`. Replace.
5. #11: the Up Next proposal has no picture (`previewImage: nil`). Ask.
