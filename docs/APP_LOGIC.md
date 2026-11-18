# App logic (batch 2, item E)

Target `AppLogic` in `Packages/VideoPlayerCore`. It is the glue between the feature targets and the screens: view models, text, and the protocols the Apple wrappers implement. It is the only package target that depends on other feature targets (`LibraryIndex`, `PlaybackLogic`, `Subtitles`, `PlaybackStatus`). Pure Swift and Foundation, so it builds and tests on Linux.

## Status

| Part | Written | Tested in WSL | Compiled for tvOS |
|---|---|---|---|
| Track pickers (`TrackPickers.swift`) | yes | yes, 10 tests | no |
| Now Playing mapping and session (`NowPlaying.swift`) | yes | yes, 10 tests | no |
| Skip button and Up Next controller (`PlayerOverlay.swift`) | yes | yes, 16 tests (fake clock, fake presenters) | no |
| Cards, filters, sorts (`LibraryCards.swift`) | yes | yes, through the library tests | no |
| Library screens (`LibraryScreens.swift`): Home, grid/Movies, Shows, Seasons, Files, Search | yes | yes, 25 tests on a real in-memory `SQLiteLibraryStore` plus a failing wrapper store | no |
| Shared states and text (`Presentation.swift`) | yes | yes | no |
| Tabs and the Search tab (`AppTabs.swift`): the six tabs and what Search shows (R167 (c), PROVISIONAL) | yes | yes, 8 tests (`AppTabsTests`) | no |
| Apple wrappers: only in the app now (`App/Features/Player/ProposalPresenter.swift`, `SkipButtonPresenter.swift`); the unused package copies were deleted after the first compile, 2026-11-17 (R76, R154); the app's `NowPlayingCenterPublisher.swift` was deleted after the second compile, 2026-11-17 (R157) | n/a | **no, cannot be built on Linux** | **no** |

Run: `swift test` in a manifest that has the AppLogic targets: 62 tests, 0 skipped, 0 failed (last run in a private trimmed copy, debug, Swift 6.4.2 on WSL). The test target needs only `AppLogic` and `VideoPlayerCore` in the manifest as written.

## What each part decides (and what the view only draws)

- **Track pickers.** `TrackPickerModel` takes the file's tracks and the user's preferences, selects through `Subtitles.TrackSelector` (first selection and "same as last episode" memory are those tested rules), and exposes `audioPicker` and `subtitlePicker` as rows with title, content line and badges. A pick returns a `TrackChange` carrying the `SeriesTrackChoice` to remember. Delay rows: 50 ms steps, limit from `SyncModel`.
- **Now Playing.** `NowPlayingMapper` builds the field dictionary, `RemoteCommandPlanner` decides which remote commands are on, `NowPlayingSession` sends a new snapshot only on a rate change, a jump of more than 1.5 s, or after 30 s (the system extrapolates in between).
- **Skip and Up Next.** `PlayerOverlayController` wraps `PlaybackSession` and turns its output into `PlayerOverlayState` (skip button, Up Next with countdown text), calls to the two presenter protocols, and a list of effects the player carries out (`seek`, `markWatched`, `advance`, `prefetch`, `cancelPrefetch`, `playbackEnded`). All timing decisions are PlaybackLogic's (docs/PLAYBACK_LOGIC.md, R49). Menu on a visible proposal is `handled`, so the player does not exit.
- **Tabs and Search.** `AppTabID` lists the tabs in bar order: Home, Movies, Shows, Files, Search, Settings (no Discover tab;
  OPEN_QUESTIONS R167, option (c), PROVISIONAL). Its raw values are the `-UITestTab` names. `SearchTabContent.forQuery`
  decides what the Search tab shows under the system search field: an empty field (spaces count as empty) shows Discover when
  Settings > Home Screen > Show Discover is on, otherwise the "Search Your Library" prompt; any typed text shows library
  results only, and clearing the field brings Discover back. Library results and Discover are never in one list. Only the
  Discover state loads Discover (`loadsDiscover`), so typing or turning Discover off sends no discovery request. The view
  keeps Discover's model while the person types, so clearing the field does not load it again.
- **Library screens.** Each is a value type with `async mutating` methods and a `state` of `idle / loading / loaded / empty / failed`. Empty and error wording is final text in `Presentation.swift` and `LibraryScreens.swift`.

## Interpretations (all PROVISIONAL, none has spec text; listed in OPEN_QUESTIONS under item E)

1. Home keeps 90 days for Continue Watching and Next Up, 20 cards per row, 30 for Recently Added.
2. A Home row with no cards is left out.
3. Sorting: Title starts A to Z, every other key starts largest or newest first; choosing the active key again flips it.
4. Grid pages of 60, the next page loads when one of the last 10 cards appears.
5. Play button on a show: Resume when something is in progress or part of the series is watched, Play Again when everything is watched, else Play. Specials (Season 0) are listed last as "Specials" and are never picked as the resume target.
6. Now Playing: an episode shows its own title, the series as the second line, "Season N" or "Specials" as the album line; a movie shows only its title. 10-second skip commands, Next only when a next episode exists, Previous off.
7. Delay row: 50 ms steps.
8. The Up Next presenter turns Apple's own countdown off (NaN) and shows ours, because AVKit counts from the end of playback (see below).
9. Series list: `LibraryStore` has no "list series" call, so `EpisodeGroupingCatalog` reads all episodes page by page and groups them. Fine for tests and a mid-size library, O(episodes) for a big one. **Gap for the parent:** add a `series()` query to `LibraryIndex` and a `SeriesCatalog` that uses it; the Shows view model already takes the catalog as a parameter.

## Apple wrappers (in the app)

Written from Apple's documentation without a Mac; no decisions in them. They live in `App/Features/Player/`. The package once held a second, unused copy; the first compile built it without an error, and it was deleted afterwards as dead code (R76, R154). The names below are the ones those package copies used; the app's files are `ProposalPresenter` and `SkipButtonPresenter` (`NowPlayingCenterPublisher` was removed, R157). Neither app file has had its body compiled yet: the first compile type-checked only their declarations (R155).

- `NowPlayingCenterPublisher` (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`): **removed** after the second compile (R157). It set `updatesNowPlayingInfoCenter = false`, which does not exist on tvOS (compile error), and on tvOS `AVPlayerViewController` publishes Now Playing itself from `externalMetadata`, so a second writer must not exist. The package's `NowPlayingMapper`, `RemoteCommandPlanner` and `NowPlayingSession` stay, tested but unused by the app, for a later player that is not `AVPlayerViewController` (it would publish through `MPNowPlayingSession`).
- `ContentProposalPresenter` (`AVContentProposal`, `AVPlayerViewControllerDelegate`, an `AVContentProposalViewController` subclass) and `ContextualActionSkipPresenter` (`AVPlayerViewController.contextualActions`).
- Known difference from Apple's model, found by reading "Presenting content proposals in tvOS": AVKit presents a proposal when the item reaches `contentTimeForTransition` and counts `automaticAcceptanceInterval` from the end of playback. Our machine picks the moment (credits start) and runs its own countdown. The wrapper sets the transition time to the current playhead and the interval to NaN. Whether AVKit then shows the proposal at once is **unverified**; it is on the Apple TV checklist.
- The wrapper files are built only in the tvOS app target, so the package's Linux tests never see them.

## Not covered by these tests

- Anything drawn: focus order, layout, the delay before a loading spinner shows, artwork loading, localisation of the strings (they are English literals here; moving them into `Localizable.xcstrings` happens when the views use them).
- The item detail screen and the "exit playback shows the title's detail screen" rule (HIG, Playing video).
- Real library sizes: the tests use 9 items. Paging and counts at 100k items are covered by `LibraryIndex`'s scale tests, not here.
- Concurrency under load: the controller and Now Playing session take one lock each and call presenters after releasing it; no stress test.
