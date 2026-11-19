# Design references

The reference for every UI and behaviour decision in this app. **Before changing or adding a screen, read the matching
page(s) below first.** Every page was opened on 2026-11-18 (Apple's text read through developer.apple.com); the notes are
summaries in our own words, not quotes. Where a page says nothing about something, that is written down too, so nobody
fills the gap with a guess. Each rule applied to a screen is cited in docs/HIG_AUDIT.md ("Design check").

Behaviour reference: Apple's own tvOS apps (the TV app, Music, Photos, Settings), for behaviour only: where titles, focus,
menus and Back go. No logos, no names, no look-alike artwork. Anything said here about what those apps do, and not taken
from a page in the table below, is **unverified, from memory** (#16 item 1.8) until it is checked on an Apple TV
(docs/DEVICE_TEST_CHECKLIST_VISUAL.md V-05 to V-14).

## Links (checked 2026-11-18)

| Topic | Page | Status |
|---|---|---|
| Designing for tvOS | https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos | OK |
| Liquid Glass overview | https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass | OK |
| Adopting Liquid Glass | https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass | OK |
| Liquid Glass on custom views | https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views | OK |
| Materials | https://developer.apple.com/design/human-interface-guidelines/materials | OK |
| Focus and selection | https://developer.apple.com/design/human-interface-guidelines/focus-and-selection | OK |
| Remotes | https://developer.apple.com/design/human-interface-guidelines/remotes | OK |
| SwiftUI focus APIs | https://developer.apple.com/documentation/swiftui/focus | OK |
| Tab bars | https://developer.apple.com/design/human-interface-guidelines/tab-bars | OK |
| Searching | https://developer.apple.com/design/human-interface-guidelines/searching | OK |
| Collections | https://developer.apple.com/design/human-interface-guidelines/collections | OK |
| Lists and tables | https://developer.apple.com/design/human-interface-guidelines/lists-and-tables | OK |
| Buttons | https://developer.apple.com/design/human-interface-guidelines/buttons | OK |
| Menus | https://developer.apple.com/design/human-interface-guidelines/menus | OK |
| Sheets | https://developer.apple.com/design/human-interface-guidelines/sheets | OK |
| Alerts | https://developer.apple.com/design/human-interface-guidelines/alerts | OK |
| Progress indicators | https://developer.apple.com/design/human-interface-guidelines/progress-indicators | OK |
| Loading | https://developer.apple.com/design/human-interface-guidelines/loading | OK |
| Empty states | **CORRECTED.** No HIG page on empty states was found (the HIG index page could not be loaded by either tool; search found none). Apple's component for it: https://developer.apple.com/documentation/swiftui/contentunavailableview | replaced |
| Typography | https://developer.apple.com/design/human-interface-guidelines/typography | OK |
| Color | https://developer.apple.com/design/human-interface-guidelines/color | OK |
| Layout | https://developer.apple.com/design/human-interface-guidelines/layout | OK |
| SF Symbols | https://developer.apple.com/design/human-interface-guidelines/sf-symbols | OK |
| App icons | https://developer.apple.com/design/human-interface-guidelines/app-icons | OK |
| Top Shelf | https://developer.apple.com/design/human-interface-guidelines/top-shelf | OK |
| Playing video | https://developer.apple.com/design/human-interface-guidelines/playing-video | OK |
| AVKit | https://developer.apple.com/documentation/avkit | OK |
| Now Playing on tvOS | **CORRECTED.** The given path (`/documentation/avkit/displaying-media-metadata-in-the-now-playing-interface`) no longer resolves. Current pages: https://developer.apple.com/documentation/avkit/customizing-the-tvos-playback-experience and https://developer.apple.com/documentation/avfoundation/avplayeritem/externalmetadata | replaced |
| Accessibility | https://developer.apple.com/design/human-interface-guidelines/accessibility | OK |
| VoiceOver | https://developer.apple.com/design/human-interface-guidelines/voiceover | OK |
| HIG index | https://developer.apple.com/design/human-interface-guidelines/ | could not be loaded (2026-11-18); left as the entry point |
| SwiftUI `navigationDestination(for:destination:)` (used for fix R168) | https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:) | OK |
| SwiftUI `toolbarVisibility(_:for:)` (used for R166) | https://developer.apple.com/documentation/swiftui/view/toolbarvisibility(_:for:) | OK |
| SwiftUI `onGeometryChange(for:of:action:)` (used for rule 13) | https://developer.apple.com/documentation/swiftui/view/ongeometrychange(for:of:action:) | OK |

## What the pages say (our summaries; tvOS-specific statements marked "tvOS")

**Designing for tvOS.** People sit 8 feet or more away, often for hours. Use the focus system; edge-to-edge artwork and
subtle motion; legible across a room. No numeric specifications on this page.

**Liquid Glass (overview, adopting, custom views).** Standard SwiftUI controls and bars pick it up by themselves.
tvOS: standard buttons and controls become glass when focused; custom controls should get the same through `focusable`
and focus state. tvOS: needs Apple TV 4K (2nd generation) or later; older models keep the previous look. Remove custom
backgrounds behind tab bars and toolbars. Test with Reduce Transparency and Reduce Motion. `glassEffect()` is for custom
views, applied after appearance modifiers; group several in a `GlassEffectContainer`; too many hurt performance. The search
tab uses `Tab(role: .search)`.

**Materials.** tvOS: Liquid Glass appears in navigation, Top Shelf and Control Center; image views and buttons adopt it on
focus. Glass is not used in the content layer (sliders and toggles while in use are the exception). Clear glass only over
rich media, with a dimming layer over bright content; the system player brings its own dimming.

**Focus and selection.** tvOS: every element is reachable by directional focus, and selecting is a separate press. Focused
items usually get parallax and scale up, so leave room around them. Five states: unfocused, focused, highlighted, selected,
unavailable. Never move focus without the person's input, except when the focused item disappears (then the nearest
neighbour).

**Remotes.** tvOS: Back opens the parent screen (not necessarily the previous one); at the top level of an app the parent is
the Home Screen. Pressing and holding Back goes Home. Play/Pause plays, pauses and resumes. Focus moves the way the swipe
goes. Prefer standard gestures.

**SwiftUI focus.** `focusable`, `@FocusState`, `focused(_:equals:)`, `focusSection()` (guides directional moves),
`focusScope` + `prefersDefaultFocus` / `defaultFocus`, `resetFocus`, `focusEffectDisabled`.

**Tab bars.** tvOS: 68 pt high, top edge 46 pt from the top; neither can be changed. Translucent; the selected tab is
opaque and gets a shadow when the bar has focus. tvOS: when there are more tabs than fit, the system fades the rightmost
item from the right edge; with enough tabs to scroll, a fade from the left as well (no "More" tab on tvOS). The bar scrolls
away on single-view tabs and stays pinned on split views. tvOS: pressing Menu returns focus to the tab bar. General: do
not hide or disable tabs; explain an empty section instead; single-word labels.

**Searching.** Search gets a prominent place (a dedicated tab on Apple TV); show scope, suggestions, clearable history. No
extra tvOS notes.

**Collections.** Standard row and grid layouts; padding so focus effects do not overlap. No extra tvOS notes.

**Lists and tables.** tvOS: a focused row highlights, grows slightly and may get rounded corners; check images in rows
still look right; no custom masks. Keep row text short to limit truncation.

**Buttons.** One or two prominent buttons per view at most; preference shown by style, not size; a destructive action is
never the primary one. (tvOS sizes: see Accessibility.)

**Menus.** Title-style capitals, verbs, important items first, one level of submenu with about five items; icons for all
items of a group or none.

**Sheets.** tvOS: always modal. One at a time; Done is paired with Cancel (or Back in a multi-step flow).

**Alerts.** tvOS: Menu cancels an alert. At most three buttons; never at launch; "OK" only for purely informational
alerts; the cancel button is labelled "Cancel".

**Progress indicators, Loading.** Prefer determinate progress that keeps moving; do not switch between a spinner and a
bar; show placeholders as soon as possible.

**Empty states (ContentUnavailableView).** tvOS 17+. For content that cannot be shown: a network error, an empty list, no
search results; `ContentUnavailableView.search` for search.

**Typography.** tvOS: default text 29 pt, minimum 23 pt. tvOS styles: Title 1 76, Title 2 57, Title 3 48, Headline 38,
Subtitle 1 38, Callout 31, Body 29, Caption 1 25, Caption 2 23 (pt). Avoid light weights. With larger text sizes, keep
truncation to a minimum and let labels use more lines (see OPEN_QUESTIONS R165 for the conflict with rule 13).

**Color.** tvOS: a limited palette; focus is never shown by colour alone (scale and motion are the cues). Provide light,
dark and increased-contrast variants of custom colours (this app has none).

**Layout.** tvOS: keep primary content 60 pt from the top and bottom and 80 pt from the sides. tvOS grids: 40 pt between
columns, at least 100 pt between rows; unfocused widths per column count: 2 → 860, 3 → 560, 4 → 410, 5 → 320, 6 → 260,
7 → 217, 8 → 184, 9 → 160 pt. Extra vertical space for titled rows; full-screen backgrounds run under the tab bar.

**SF Symbols.** Four rendering modes; prefer system colours; animate sparingly; label custom symbols for accessibility.

**App icons.** tvOS: 800×480 px, 2 to 5 layers for parallax, unmasked rectangular layers, a safe zone because focus crops
the edges.

**Top Shelf.** Prefer the dynamic layouts; static fallback 2320×720 pt; poster (2:3) items 404×608 pt actual; 16:9 items
908×512 pt actual; no advertising; feature new or resume content.

**Playing video.** Use the system player; tvOS: transport controls and info tabs live in the system player, custom actions
one or two steps; small, translucent SDR overlays shown no sooner than 0.5 s; resume automatically; if loading takes more
than 2 s a black screen with a centred spinner; on exit, the detail view with Resume.

**AVKit (tvOS playback).** `AVPlayerViewController`; title and subtitle from `externalMetadata`
(`commonIdentifierTitle`, `iTunesMetadataTrackSubTitle`); info tab artwork, description, genre, rating;
`transportBarCustomMenuItems`, `customInfoViewControllers`, `infoViewActions` (up to two), `contextualActions` (Skip).

**Accessibility.** tvOS: text default 29 pt, minimum 23 pt; controls default 66×66 pt, minimum 56×56 pt. Support text
enlarged by at least 200 %. Contrast 4.5:1 up to 17 pt, 3:1 from 18 pt or bold. About 12 pt around bezelled controls,
24 pt around unbezelled ones. Captions, subtitles and audio descriptions; Reduce Motion (cut zoom, scale and depth
animation; prefer fades); Increase Contrast (higher-contrast colour variants). Reduce Transparency is named on the Liquid
Glass and Materials pages, Bold Text on the Typography page; the Accessibility page itself does not mention them.

**VoiceOver.** Label every meaningful element; hide decorative images; use titles and headings; group related elements;
announce layout changes.

### Things no page states (do not assume them)

- Whether tvOS tab screens show a large navigation title, and how it is aligned (Toolbars has large titles for iOS only).
  Our choice: R166.
- Shrinking text to fit (scaling) is not described anywhere; Typography prefers more lines at large sizes. Our rule: R165.
- "Back from a root tab goes to the tab bar, then exits" is the combination of two pages (Tab bars: Menu returns focus to
  the tab bar; Remotes: at the top level the parent is the Home Screen). No single page states the two-step sequence.

## Checklist: rules every screen is checked against

Numbers are used in docs/HIG_AUDIT.md ("Design check"). Status words there: **pass** (seen in a CI screenshot or on a
device and correct), **fail** (seen and wrong, or known wrong from the code), **unproven** (not yet seen on a device or in
a CI screenshot), **n/a**.

### Behaviour
1. Back/Menu goes back exactly one level; from a root tab it goes to the tab bar, then exits. No custom back buttons.
   Play/Pause, Select, long press, swipes and arrow edges behave as in Apple's apps (Remotes; Tab bars). What Apple's
   apps do with long press and arrow edges: unverified, from memory (no page states it); checked by V-06.
2. Focus: a sensible initial focus; never lost or trapped; after Back it returns to the item left; it moves in the
   direction pressed; `focusSection` where lateral moves would otherwise be unpredictable; nothing focusable is invisible.
   (Focus and selection; SwiftUI focus)
3. System focus effect and lift only; no custom focus rings, shadows or scale effects. (Focus and selection; Adopting
   Liquid Glass)
4. Controls behave as Apple documents them; no control used for something Apple uses a different control for. (Buttons;
   Menus; Lists and tables)
5. Loading, empty, offline and error states on every screen that loads something, in plain words with a next action; never
   blank, never silent. (Loading; Progress indicators; ContentUnavailableView)
6. Anything that cannot be undone asks for confirmation with the system alert or confirmation dialog; destructive buttons
   use the destructive role. (Alerts; Buttons)
7. Text entry uses the system keyboard and dictation; no custom keyboards. (Searching)
8. Playback: resumes where it stopped; skip intro/credits and next episode as specified; subtitle and audio pickers are the
   system player's; errors during playback say what happened. (Playing video; AVKit)

### Appearance
9. Liquid Glass only from the SDK (system components; `glassEffect` on custom views); never faked with blurs or gradients;
   glass on top of content, not behind it; no glass on glass. (Liquid Glass pages; Materials)
10. System fonts and text styles only; no fixed point sizes; readable from 10 feet. (Typography)
11. System and semantic colours only; contrast passes in light and dark; nothing relies on colour alone. (Color;
    Accessibility)
12. Spacing and margins from system layout (safe area, standard row and grid spacing); equal items exactly equal in size
    and aligned on the same top edge or baseline. (Layout; Collections)
13. Short texts are never cut with "…" and never wrapped; they scale to fit at a readable size (rule S1, R165).
    (Typography: see the conflict in R165)
14. SF Symbols for all icons, variant and weight matching their text; no custom-drawn icons. (SF Symbols)
15. System transitions only; Reduce Motion respected. (Accessibility)

### Accessibility
16. Every focusable element has a spoken label, a value where it has one, a hint only where the action is not obvious;
    headers have the header trait; VoiceOver reaches and operates every screen. (VoiceOver; Accessibility)
17. Works with Larger Text, Bold Text, Reduce Transparency, Increase Contrast and Reduce Motion, with what was tested
    written down. Larger Text and Bold Text: CI screenshots 80 to 101, drawn by the app as an imitation of the two
    settings, with the same eleven screens at the default size (102 to 112) to compare against (#16 item 1.10, #17 A,
    docs/A11Y_SHOTS.md); the real settings (Settings > Accessibility > Display > Text Size and Bold Text) are V-15 and
    V-16. Increase Contrast, Reduce Transparency and Reduce Motion: device-only proof (#15 item 1.4; V-17 to V-19); CI
    job 6 tries them in the simulator and writes down whether each was applied.
    (Accessibility; Typography; Materials)

### Identity and wording
18. Neutral identity (no logo or branding of our own); real technology and service names only as text; the one TMDB logo
    only in Settings > About > Data Sources.
19. Plain, short, consistent copy: one name per concept everywhere.
20. The honesty lines about what was and was not tested against a real server stay as written unless the owner changes
    them.

## How this file is used

- Every screen's entry in docs/HIG_AUDIT.md has a "Design check" listing the rules above that apply and pass / fail /
  unproven, with the page cited for each rule applied.
- When a rule conflicts with something built or with an owner requirement, the conflict goes into OPEN_QUESTIONS.md with
  both options, and the Apple behaviour is built as the provisional choice.
