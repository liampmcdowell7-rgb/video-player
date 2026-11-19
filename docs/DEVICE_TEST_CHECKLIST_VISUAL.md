# Visual fidelity checklist (Apple TV)

Purpose: prove, by looking, that the app is indistinguishable from the system apps. **Until every item is done on a real Apple TV, visual fidelity is unproven.** Written for a non-coder. Needs a build installed through TestFlight (docs/CODEMAGIC_SETUP.md) on an Apple TV that runs tvOS 27, and the Apple TV's own Settings app beside it for comparison of standard controls. Record the Apple TV model and tvOS version first.

Write a result next to each item: **Pass**, **Fail** (what you saw), or **Not tested**.

## First launch
- V-01 The app opens and stays open (no immediate quit). If it quits at launch, that is the scene life cycle problem (DESIGN_SYSTEM D-DS4); report it with the time.
- V-02 After the first build, the build log has no asset-catalog warnings about the icon or Top Shelf image (ask the parent; Codemagic log search "App Icon").
- V-03 The Home Screen icon: layered, moves and sways when focused, no text, nothing cropped. Compare with the Settings icon.
- V-04 Static Top Shelf image shows when the app sits in the top row and is focused; it does not look clickable.
- V-TS1 (was CI screenshot 79; a UI test of this app cannot open the system Home Screen, #15 item 1.3) Put the app in the top row, watch something for a minute, go back to the Home Screen and focus the app: the Top Shelf shows the Continue Watching row (docs/TOP_SHELF.md), titles not cut off, and selecting one opens that title in the app. Take a photo.

## Tab bar and navigation
- V-05 The tab bar looks like the standard system tab bar (as in Settings): translucent, only the selected tab solid, selected tab has a shadow when focused. Six tabs (Home, Movies, Shows, Files, Search, Settings; no Discover tab, R167 (c)) all fit with no fade at either edge; record where Search sits.
- V-06 Move focus into content and press Menu: focus returns to the tab bar. Press Menu on the tab bar: you go to the Home Screen. In Settings, push a page and press Menu: you go back one level.
- V-07 Focus is always visible; nothing is focusable that should not be; nothing needs a pointer.

## Components next to the system apps
- V-08 Settings looks like the system Settings: grouped rows, same row height, section headers in title case, toggle looks the same.
- V-09 Empty-state screens look like system empty states (symbol, title, sentence, button).
- V-10 Search: the keyboard and results behave like the standard system search screen.
- V-11 (when built) Poster cards lift, sway and glow like standard system card buttons (`.card` style); the focused card is not clipped at the row edges; spacing of 40 pt between cards is even.
- V-12 (when built) Context menu on long press looks like the system's, same glass.
- V-13 (when built) Alerts and confirmations look like system alerts; destructive button is red, never the highlighted default.
- V-14 (when built) Source setup: the text-entry keyboard is the system one; fields look like system fields.

## Accessibility (set each in Apple TV Settings > Accessibility, test, set back)
- V-15 Larger Text at the largest size: no text cut off or overlapping on any screen; layout reflows.
- V-16 Bold Text on.
- V-17 Reduce Transparency on: bars and menus become solid and stay readable.
- V-18 Increase Contrast on: labels and focus still clear.
- V-19 Reduce Motion on: no large movement from the app's own animations.
- V-20 Light and dark appearance (Settings > General > Appearance): both look right, no black-on-black or white-on-white.
- V-21 VoiceOver on: every tab and button is read with a sensible name; the icon-only buttons have labels.

## Playback (when built)
- V-22 Player looks exactly like the standard system player (`AVPlayerViewController`): transport bar, scrubber, subtitle and audio menus, Info tab. No extra chrome.
- V-23 Skip Intro / Skip Credits button appears bottom right only while the controls are hidden, same look as system.
- V-24 Up Next appears at the credits start with our countdown; Menu dismisses it and it does not return for that episode.
- V-25 Playback Stats overlay: small, translucent, readable over a bright scene and a dark scene; does not stay on screen for long periods (image retention).
- V-26 Audio and HDR status text matches what the Apple TV shows in its own info (compare with the TV's display info).

## Hand-over notes for reviewers (not checks)
- `@State` macro rules (DESIGN_SYSTEM section 3) cannot be linted: when new views are written, check that no `@State` has both an initial value and an `init` assignment.
- Any `design-lint:allow` added to App/ must be listed in docs/DESIGN_SYSTEM.md section 10.
