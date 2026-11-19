# Playback logic (skip segments and Next Episode)

Next Episode was rebuilt in batch 2 from the user's own text (below). It **replaces** the earlier version, which was built without that text (OPEN_QUESTIONS R33, R36 are superseded by R49). Everything that is still a choice of mine is marked "Interpretation (PROVISIONAL)".

## API for the app layer

All in `Sources/PlaybackLogic`, pure Swift, Foundation only, `Sendable`. The Apple TV code sends events in and applies the actions that come out.

| Type | What it is |
|---|---|
| `NextEpisodeMode` | `.whenCreditsBegin` (default), `.whenEpisodeEnds`, `.ask`, `.off`; `title` is the row text ("When Credits Begin", "When Episode Ends", "Ask", "Off"); `CaseIterable` in row order; `Codable` |
| `NextEpisodeSettings` | What Settings > Playback > Next Episode stores: `mode` and `countdownSeconds` (clamped to 0...30; `countdownChoices` = 0, 5, 10, 15, 20, 30 for the row; default 10). `Codable`; missing keys decode to the defaults |
| `NextEpisodePolicy` | `init(settings:)` or `init(mode:autoAdvanceDelay:trailingLimit:endEpsilon:prefetchLead:)`. `autoplay` is now a read-only flag (true for the two countdown modes) |
| `NextEpisodeMachine` | One playback of one file. `init(duration:credits:next:policy:clock:currentFormat:nextFormat:dismissedBefore:)`, `handle(_:) -> [NextEpisodeAction]`. Read-only: `proposalTime` (nil when Off), `watchedTime`, `prefetchRequest`, `displayModeDecision`, `skipCreditsOfferTarget`, `isProposalVisible`, `wasDismissed`, `isFinished`, `automaticAcceptanceDeadline` |
| `NextEpisodeEvent` | `.playhead(time, kind)`, `.paused`, `.resumed`, `.ended`, `.tick`, `.menu`, `.accept`, `.dismiss`, `.skipCreditsToEnd`, `.stopped` (the user left the player) |
| `NextEpisodeAction` | `.markWatched`, `.presentProposal(EpisodeRef)`, `.withdrawProposal`, `.proposalDismissed`, `.advance(EpisodeRef)`, `.playbackEnded`, and new: `.offerSkipCredits(target:)`, `.withdrawSkipCreditsOffer`, `.prefetch(EpisodeRef)`, `.cancelPrefetch(EpisodeRef)` |
| `PrefetchRequest` | `episode` and `startAt` (playhead seconds) |
| `DisplayFormat`, `DynamicRangeFormat`, `ResolutionClass`, `DisplayModePlanner`, `DisplayModeDecision` | Pure format comparison: `DisplayModePlanner.decide(current:next:)` gives `.keep(reason)` or `.switchMode(to:differences:)`; the machine exposes it as `displayModeDecision` for the moment it advances |
| `PlaybackSession` | Skip controller plus the machine: `playhead(_:kind:)`, `skipPressed(_:)`, `event(_:)`; new optional init parameters `currentFormat`, `nextFormat`, `dismissedBefore`. Returns `SessionUpdate` (skip output, episode actions, seek) |
| `NextEpisodeProvider`, `LibraryNextEpisodeProvider`, `EpisodeOrder`, `EpisodeRef`, `NextEpisodeDecision` | Which episode comes next (unchanged) |

## Next Episode spec (user's message, batch 2)

Copied word for word from the user's message ("NEXT EPISODE SPEC"):

> Settings > Playback > Next Episode, with these choices: "When Credits Begin" (default), "When Episode Ends", "Ask", "Off". Plus a countdown row.
> - If the credits segment is known, show the Up Next proposal at the credits start, and jump straight to the next episode when the countdown ends.
> - If the credits segment is unknown, wait for the end of the file.
> - If more than 60 seconds of content remains after the credits segment ends, offer "Skip Credits" to the segment end instead of advancing.
> - Pressing Menu dismisses the proposal, and the app never re-advances that episode afterwards.
> - Next episode selection: the next episode in the same season; then the first episode of the next season; then stop. Season 0 specials are never auto-advanced.
> - The episode is marked watched when advancing at the credits start.
> - Prefetch the next episode. Keep the display mode when the next episode's format matches, so there is no needless display switch.
> Add a test for every sentence above, on the fake clock.

One numbered rule per sentence, with its tests (`Tests/PlaybackLogicTests/NextEpisodeSpecTests.swift`, all on `ManualClock`):

| Rule | Sentence | Tests |
|---|---|---|
| NES-1 | Settings > Playback > Next Episode, four choices, "When Credits Begin" the default, plus a countdown row | `testNES1a` four choices in order with the texts; `1b` default; `1c` countdown row default 10, choices, clamp; `1d` settings survive encoding, missing keys fall back; `1e` the row sets the countdown on the fake clock |
| NES-2 | Credits known: Up Next at the credits start; jump straight to the next episode when the countdown ends | `2a` appears at the credits start; `2b` jumps when the countdown ends, no further press; `2c` countdown 0 jumps at once; `2d` accepting during the countdown advances at once |
| NES-3 | Credits unknown: wait for the end of the file | `3a` nothing before the end; `3b` Up Next at the end, then the countdown, then advance |
| NES-4 | More than 60 s of content after the credits: offer "Skip Credits" to the segment end instead of advancing | `4a` no Up Next and no advance at the credits start; `4b` the offer appears while inside the credits and goes away at the segment end; `4c` exactly 60 s is not "more than 60"; `4d` after skipping, the episode continues and Up Next waits for the end; `4e` seeking out and back withdraws and re-offers; `4f` no offer without a next episode or in the modes that do not advance at the credits start; session tests `SESS-8`, `SESS-9` (shows even when the Skip Credits setting is Off), `SESS-10` (Automatic jumps to the segment end, no advance) |
| NES-5 | Menu dismisses the proposal, and the app never re-advances that episode afterwards | `5a` Menu dismisses; `5b` never advanced by any later path (waiting, ending, Skip Credits, accept, seeking); `5c` same when the credits are unknown; `5d` a replay the app marks `dismissedBefore` never proposes, advances or prefetches; existing `NE-9` to `NE-13`, `SESS-6` |
| NES-6 | Next episode: same season, then the first episode of the next season, then stop; Season 0 never auto-advanced | `6a` same season; `6b` next season's first; `6c` then stop; `6d` Season 0 never advances nor is entered; `6e` on the fake clock the last episode of a season advances to the next season's first; `6f` on the fake clock the last episode of the last season and a special never advance (existing `NE-30` to `NE-41` cover gaps, versions, multi-episode files) |
| NES-7 | Marked watched when advancing at the credits start | `7a` marked at the credits start, before Up Next and before the advance, exactly once; `7b` once even with seeks; `7c` at the end when the credits are unknown |
| NES-8 | Prefetch the next episode | `8a` the request names the episode and when to start; `8b` starts once at that position; `8c` also after a seek or a resume past it; `8d` Menu cancels it and it never restarts; `8e` leaving the player cancels a running prefetch; `8f` advancing does not cancel; `8g` none when Off or when there is no next episode; `8h` never before 0, lead configurable |
| NES-9 | Keep the display mode when the next episode's format matches | `9a` same format keeps (also a 1920x800 crop of 1920x1080); `9b` each difference switches and says why; `9c` unknown next (or current) format keeps; `9d` 23.976 and 24 are different; `9e` HDR10+ is output as HDR10, Dolby Vision and HLG are their own modes; `9f` resolution classes; `9g` the machine exposes the decision; session test `SESS-11` |
| NES-M | What the other three choices do (my interpretation) | `M1` When Episode Ends; `M2`, `M3` Ask; `M4` Off; `M5` Skip Credits to the end in Ask and Off never advances; `M6` the old autoplay flag is read-only |

### Modes (what each choice does; the user's text only defines the default, the rest is Interpretation (PROVISIONAL))

| Mode | Up Next appears | Countdown | Advances by itself | Marked watched | Prefetch |
|---|---|---|---|---|---|
| When Credits Begin (default) | at the credits start; at the end of the file when the credits are unknown or more than 60 s of content follow them | yes (the countdown row), only when playback reaches Up Next by itself | yes, when the countdown ends | at the credits start (the end when the credits are unknown) | yes |
| When Episode Ends | at the end of the file, even when the credits are known | yes | yes | same as above | yes |
| Ask | same time as When Credits Begin | no: it waits for the user | never | same as above | yes |
| Off | never | none | never | same as above (Off changes only Up Next and advancing) | none |

## Differences from the earlier version

The earlier version (85 tests, rows NE-1 to NE-41, built without your text, R33) differed from the spec in these places:

1. **No choices.** It had one behavior and a yes/no flag "Play Next Episode Automatically" (B9). Now there are four modes and a countdown row. The old flag `autoplay` can no longer be set; it is read-only (on for the two countdown modes). Mapping used in the tests: flag on = When Credits Begin, flag off = Ask.
2. **Short post-credits scene.** With 60 s or less of content after the credits, the earlier version showed Up Next at the credits start but held the countdown back until the end of the file (NE-19). The spec says only content of **more than** 60 s changes anything, so now the countdown runs from the credits start and the next episode starts about 10 s later, which can cut a short scene. Test `NE-19` was rewritten.
3. **More than 60 s after the credits.** The earlier version only waited for the end of the file. Now it also **offers "Skip Credits"** to the segment end (new action `offerSkipCredits`, shown as the skip button by `PlaybackSession`, also when the Skip Credits setting is Off). The proposal time is unchanged.
4. **Countdown.** It was a parameter (10 s). Now it is a setting row with choices 0, 5, 10, 15, 20, 30 s; 0 means the next episode starts as soon as Up Next appears (before, a delay of 0 waited for the next tick).
5. **Off did not exist.** There was no way to turn Up Next off; the closest was autoplay off, which still showed Up Next. Now Off shows nothing and never advances, but still marks the episode watched.
6. **Prefetch** (new): actions `prefetch` and `cancelPrefetch`, and `prefetchRequest`. Menu now returns `[.proposalDismissed, .cancelPrefetch(...)]` when a prefetch had started (test `SESS-6` changed).
7. **Display mode** (new): `DisplayModePlanner` and `displayModeDecision`.
8. **Leaving the player** (new): event `.stopped` cancels a running prefetch and finishes the machine.
9. **API changes.** `proposalTime` is optional (nil when Off); `NextEpisodePolicy` gained `mode` and `prefetchLead` and lost the `autoplay:` init parameter; `NextEpisodeMachine` and `PlaybackSession` took optional `currentFormat`, `nextFormat`, `dismissedBefore`. The `Rig` test helper now keeps core actions in `log` and everything in `fullLog`; tests `NE-8`, `NE-24`, `NE-27` use `mode: .ask` instead of `autoplay: false`.
10. **Unchanged, because the spec agrees:** proposal at the credits start; credits unknown waits for the end of the file; the 60 s rule and its threshold ("more than"); Menu dismisses and nothing advances afterwards; same season, then next season, then stop, Season 0 never auto-advanced; watched at the credits start.
11. **Rows that were Interpretations and are now your spec:** NE-1, NE-2 (the proposal part), NE-3, NE-9, NE-14, NE-30 to NE-35. The rest stay PROVISIONAL.

No old test was deleted. Changed: `NE-19` (rewritten), `NE-8`, `NE-24`, `NE-27` (policy construction), `SESS-6` (expects `cancelPrefetch`), the `Rig` helper.

## Interpretations in this version (all PROVISIONAL, for OPEN_QUESTIONS)

| # | Interpretation |
|---|---|
| I1 | The countdown row offers 0, 5, 10, 15, 20, 30 s, default 10 (your text says only "a countdown row") |
| I2 | When Episode Ends: Up Next and countdown only at the end of the file, even when the credits are known |
| I3 | Ask: Up Next at the credits start (or the end), never a countdown, waits for the user; at the end `playbackEnded` is reported once and the proposal stays |
| I4 | Off: no Up Next, no advance, no prefetch; the episode is still marked watched |
| I5 | "Marked watched when advancing at the credits start" is read as: watched at the credits start when the credits are known, at the end when they are not, once, in every mode |
| I6 | The countdown starts only when playback reaches Up Next by itself (not after a seek, not when resuming inside the credits); pausing cancels it; the end of the file starts it again; a Skip Credits to the end of the file advances at once in the countdown modes |
| I7 | Exactly 60 s after the credits is not "more than 60" |
| I8 | The Skip Credits offer is made in When Credits Begin and Ask only, only when a next episode exists, and also when the user's Skip Credits setting is Off |
| I9 | Dismissal lasts for one playback; the app can pass `dismissedBefore` to keep it across replays. Seeking back before Up Next withdraws it without dismissing it (kept from before) |
| I10 | Prefetch starts 120 s before Up Next would appear (`prefetchLead`), also after a seek or resume past that point; Menu or leaving cancels it; advancing does not; none when Off or when there is no next episode |
| I11 | Display mode compares resolution class (under 720 lines SD, under 1440 HD, otherwise UHD, measured on the larger of the height and the 16:9 height of the width), frame rate (different above 0.01 fps, so 23.976 and 24 differ), and dynamic range family (HDR10+ output as HDR10, every Dolby Vision profile one mode); an unknown format keeps the mode |

## Spec rows

Every rule is one row. **Source**: `Part B` = the Part B message (SEGMENT MODEL, DETECTION TIERS, PLAYBACK UI, TESTS), `B1`–`B10` = OPEN_QUESTIONS decisions, `Batch C` = item C of the "DECISIONS AND NEXT BATCH" message (including its one-line Next Episode list), `Next Episode spec` = the batch-2 text above (it supersedes the earlier "no CONFIRMATIONS text" situation, R33), `Interpretation` = my reading where the record is silent. The Next Episode rows below are the earlier table, kept with their tests; where the batch-2 spec changed a row it says so, and the new rules are the NES table above. **Status**: `SPEC` = stated by the user; `PROVISIONAL INTERPRETATION` = my choice, stays on the open list until you confirm it. All tests are in `Packages/VideoPlayerCore/Tests/PlaybackLogicTests/`; names start with the row id.

### Segment model and safety limits

| Row | Rule | Source | Status | Test |
|---|---|---|---|---|
| SEG-1 | A segment belongs to a file identified by path, size and duration; a segment made for another file is rejected | Part B segment model | SPEC | `testSEG1_segmentOfAnotherFileIsRejected` |
| SEG-1b | "Same duration" for file identity means within 0.5 s | Interpretation | PROVISIONAL INTERPRETATION | `testSEG1_segmentOfAnotherFileIsRejected` |
| SEG-2 | Database segments are used only when the file duration matches within the greater of 2 s or 0.5 % | B1 | SPEC | `testSEG2_databaseSegmentNeedsMatchingDurationWithinGreaterOfTwoSecondsOrHalfPercent` |
| SEG-3 | Online-database credits with no reference duration are rejected (cannot prove a match). #26: an online intro or recap with no reference duration (IntroDB gives none) is accepted; `SegmentLimits.acceptsUnreferencedOnlineIntroAndRecap = false` restores the strict rule (OPEN_QUESTIONS R208) | Interpretation | PROVISIONAL INTERPRETATION | `testSEG3_onlineCreditsWithoutReferenceDurationAreRejected`, `testSEG3_onlineIntroWithoutReferenceIsAcceptedUnlessStrict` |
| SEG-4 | Confidence threshold 0.7 (0.7 itself passes) | B2 | SPEC | `testSEG4_confidenceThresholdIsSeventyPercentInclusive` |
| SEG-5 | Priority: user-marked > embedded chapters > local sidecar > online database > on-device detection | B3 | SPEC | `testSEG5_priorityUserThenChaptersThenSidecarThenOnlineThenOnDevice` |
| SEG-6 | A candidate that fails validation never blocks a lower-priority valid one | Interpretation | PROVISIONAL INTERPRETATION | `testSEG6_invalidHigherPriorityCandidateDoesNotBlockLowerOne` |
| SEG-7 | Intro length 10 to 180 s | B4 | SPEC | `testSEG7_introLengthTenToOneHundredEightySeconds` |
| SEG-8a | Recap starts within the first 60 s | B4 | SPEC | `testSEG8_recapStartsInFirstSixtySecondsAndIsAtMostOneEightySeconds` |
| SEG-8b | Recap is at most 180 s long (the spec gives no recap length limit) | Interpretation | PROVISIONAL INTERPRETATION | `testSEG8_recapStartsInFirstSixtySecondsAndIsAtMostOneEightySeconds` |
| SEG-9 | Credits start in the last 40 % (at or after 60 % of the runtime) | B4 | SPEC | `testSEG9_creditsMustStartInLastFortyPercent` |
| SEG-10a | Credits run to the end of the file or to a post-credits chapter; Skip Credits jumps to the post-credits chapter when there is one | B4 | SPEC | `testSEG10_creditsRunToEndOrToPostCreditsChapter` |
| SEG-10b | "Runs to the end" means the credits end within 60 s of the file end and are then extended to the end; more than 60 s left keeps the supplied end | Interpretation | PROVISIONAL INTERPRETATION | `testSEG10_creditsRunToEndOrToPostCreditsChapter` |
| SEG-11 | Out-of-range times are clamped (start below 0 becomes 0, end past the file becomes the file end); empty or inverted segments are rejected; every other limit violation is a rejection, not a clamp | Interpretation | PROVISIONAL INTERPRETATION | `testSEG11_outOfRangeTimesAreClampedAndInvertedSegmentsRejected` |
| SEG-12 | Same source and type: higher confidence wins, then the earlier start; losers are recorded as "outranked" | Interpretation | PROVISIONAL INTERPRETATION | `testSEG12_sameSourceTieBreaksOnConfidenceThenEarlierStart` |
| SEG-13 | Safety limits apply to user-marked segments too ("never skip real content") | Interpretation | PROVISIONAL INTERPRETATION | `testSEG13_userMarkedSegmentsStillObeySafetyLimits` |
| SEG-14 | One segment per type is used | Interpretation | PROVISIONAL INTERPRETATION | `testSEG14_onePerTypeSortedByStart` |

Overlap and partial disagreement rule: the resolver never merges. Per type it keeps the single best candidate (priority, then confidence, then earlier start) and records every other candidate with the reason (`outranked(by:)` or the limit it broke). Segments of different types may overlap; the skip button shows the best-source segment containing the playhead.

### Chapter titles

| Row | Rule | Source | Status | Test |
|---|---|---|---|---|
| CH-1 | Recognises recap, intro and credits titles in EN, FR, DE, ES, IT, PT, NL, SV, JA (kana and kanji), KO, RU, ZH, PL, TR | Batch C | SPEC | `testCH1_titlesInManyLanguages` |
| CH-2 | Case- and diacritic-insensitive | Batch C | SPEC | `testCH2_caseAndDiacriticsDoNotMatter` |
| CH-3 | Numbering is ignored ("Opening 2" is an intro); "Chapter 01" is not a segment | Batch C | SPEC | `testCH3_numberingIsIgnoredButPlainChaptersAreNot` |
| CH-4 | Whole-title match: "Introduction to the Cast", "Opening the Vault", "The Ending of Everything" are not segments | Interpretation | PROVISIONAL INTERPRETATION | `testCH4_ordinaryTitlesContainingTheWordsAreNotMatched` |
| CH-5 | "Previously on X" style titles are a recap (prefix form for recaps only) | Interpretation | PROVISIONAL INTERPRETATION | `testCH5_prefixForm` |
| CH-6 | Post-credits chapters (Post-credits, Stinger, After credits, Extras scene, and the same in the other languages) are recognised before credits | Batch C | SPEC | `testCH6_postCreditsChaptersAreRecognisedBeforeCredits` |
| CH-7 | A chapter with several titles matches when any title matches | Interpretation | PROVISIONAL INTERPRETATION | `testCH7_anyTitleLanguageOfAMarkCanMatch` |
| CH-8 | Hidden and disabled chapters are ignored | Batch C | SPEC | `testCH8_hiddenAndDisabledChaptersAreIgnored` |
| CH-8b | Chapter-derived segments get confidence 0.9 (above the 0.7 threshold, below a user mark) | Interpretation | PROVISIONAL INTERPRETATION | `testCH8_hiddenAndDisabledChaptersAreIgnored` |
| CH-9 | Only one edition is used: the one flagged default, else the first | Batch C | SPEC | `testCH9_onlyOneEditionIsUsed_theDefaultOneWhenFlagged` |
| CH-10 | A post-credits chapter ends the credits segment | Part B / B4 | SPEC | `testCH10_postCreditsChapterBecomesTheCreditsEnd` |
| CH-11 | Chapter segments obey the same safety limits | Interpretation | PROVISIONAL INTERPRETATION | `testCH11_chapterSegmentsObeyLimits` |

### Skip button

| Row | Rule | Source | Status | Test |
|---|---|---|---|---|
| SKIP-1 | Each type is Ask, Automatic or Off; default Ask | B9 | SPEC | `testSKIP1_defaultSettingIsAskForEveryType` |
| SKIP-2 | Button wording "Skip Recap", "Skip Intro", "Skip Credits" | B7 | SPEC | `testSKIP2_buttonWording` |
| SKIP-3 | The button shows only while the playhead is inside the segment (end exclusive) | Part B playback UI | SPEC | `testSKIP3_buttonShowsOnlyWhileInsideTheSegment` |
| SKIP-4 | Off shows nothing and never jumps | B9 | SPEC | `testSKIP4_offShowsNothingAndNeverJumps` |
| SKIP-5 | Automatic jumps with no button and no toast | B10 | SPEC | `testSKIP5_automaticJumpsWithoutAnyButton` |
| SKIP-6 | Automatic jumps once per type | Interpretation | PROVISIONAL INTERPRETATION | `testSKIP6_automaticJumpsOnlyOncePerType` |
| SKIP-7 | Stepping back (Siri Remote skip-back) into an automatically skipped segment does not jump again | B10 | SPEC | `testSKIP7_steppingBackIntoAnAutomaticallySkippedSegmentDoesNotJumpAgain` |
| SKIP-8 | Starting playback (resume) inside an Automatic segment skips it | Interpretation | PROVISIONAL INTERPRETATION | `testSKIP8_startingPlaybackInsideASegmentSkipsAutomatically` |
| SKIP-9 | A seek into an Automatic segment never jumps | Interpretation | PROVISIONAL INTERPRETATION | `testSKIP9_seekIntoAnAutomaticSegmentNeverJumps` |
| SKIP-10 | Each type has its own setting | B9 | SPEC | `testSKIP10_eachTypeHasItsOwnSetting` |
| SKIP-11 | The Skip Credits target is the post-credits chapter when present, else the end | B4 | SPEC | `testSKIP11_creditsTargetIsThePostCreditsChapterWhenThereIsOne` |
| SKIP-12 | Changing a setting takes effect on the next update | Interpretation | PROVISIONAL INTERPRETATION | `testSKIP12_settingsCanChangeWhileSegmentsStay` |

### Next Episode

Time is driven by a fake clock (`ManualClock`) and scripted playhead timelines (`Rig` in `NextEpisodeTests.swift`: one playhead event and one tick per simulated second).

| Row | Rule | Source | Status | Test |
|---|---|---|---|---|
| NE-1 | The proposal appears at the credits start | B8, Batch C | SPEC | `testNE1_proposalAppearsAtCreditsStart` |
| NE-2 | Credits unknown: the proposal appears at the end of the file, and the episode is marked watched there | Batch C | SPEC (the watched-at-end part is an interpretation) | `testNE2_creditsUnknown_proposalAndWatchedAtTheEnd` |
| NE-3a | More than 60 s remaining after the credits segment: the proposal waits for the end of the file | Batch C | SPEC | `testNE3_moreThanSixtySecondsAfterCredits_proposalWaitsForTheEnd` |
| NE-3b | Exactly 60 s remaining is not "more than 60" (proposal at credits start); "end of the file" means within 0.5 s of the duration | Interpretation | PROVISIONAL INTERPRETATION | `testNE3_moreThanSixtySecondsAfterCredits_proposalWaitsForTheEnd` |
| NE-4 | Accepting the proposal advances to the next episode; later events are ignored | B8 | SPEC | `testNE4_acceptAdvancesAndNothingElseHappensAfterwards` |
| NE-5 | Accept with no proposal on screen does nothing | Interpretation | PROVISIONAL INTERPRETATION | `testNE5_acceptWithoutVisibleProposalDoesNothing` |
| NE-6a | "Play Next Episode Automatically" (default on) advances without a press after a countdown | B9 | SPEC | `testNE6_autoplayCountsDownTenSecondsOnTheFakeClockThenAdvances` |
| NE-6b | The default countdown is 10 s; the countdown row (NES-1) sets it | Interpretation (I1) | PROVISIONAL INTERPRETATION | `testNE6_autoplayCountsDownTenSecondsOnTheFakeClockThenAdvances` |
| NE-7 | The delay is a parameter | Batch C | SPEC | `testNE7_delayIsAParameter` |
| NE-8 | In Ask mode (formerly "autoplay off") nothing advances by itself; the proposal waits | B9, NES-M2 | SPEC | `testNE8_autoplayOffNeverAdvancesByItself` (policy is now `mode: .ask`) |
| NE-9 | Menu dismisses the proposal without re-advancing | Batch C | SPEC | `testNE9_menuDismissesWithoutReAdvancing` |
| NE-10 | After a dismissal the proposal never returns and nothing auto-advances for the rest of that playback session, even after seeking back and forward | Interpretation | PROVISIONAL INTERPRETATION | `testNE10_seekingBackAndForwardAfterDismissalStaysDismissed` |
| NE-11 | An explicit dismiss event behaves like Menu | Interpretation | PROVISIONAL INTERPRETATION | `testNE11_dismissEventBehavesLikeMenu` |
| NE-12 | Menu with no proposal on screen is not handled here (the player exits as usual) | Interpretation | PROVISIONAL INTERPRETATION | `testNE12_menuWithoutAProposalIsNotHandled` |
| NE-13 | Seeking back before the proposal time withdraws the proposal (not a dismissal); it can show again | Interpretation | PROVISIONAL INTERPRETATION | `testNE13_seekingBeforeTheProposalTimeWithdrawsItAndItCanReturn` |
| NE-14a | The episode is marked watched at the credits start | Batch C | SPEC | `testNE14_markedWatchedOnceAtCreditsStartEvenAfterSeeksAndDismissal` |
| NE-14b | Marked watched once per session; dismissing never un-marks it | Interpretation | PROVISIONAL INTERPRETATION | `testNE14_markedWatchedOnceAtCreditsStartEvenAfterSeeksAndDismissal` |
| NE-15 | No credits: marked watched at the end, also when there is no next episode | Interpretation | PROVISIONAL INTERPRETATION | `testNE15_noCreditsMeansWatchedAtTheEndEvenWhenThereIsNoNextEpisode` |
| NE-16 | Resuming inside the credits marks watched and shows the proposal, but starts no countdown until the end of the file | Interpretation | PROVISIONAL INTERPRETATION | `testNE16_resumingInsideTheCreditsMarksWatchedAndShowsProposalButDoesNotCountDown` |
| NE-17 | Seeking into the credits shows the proposal without a countdown | Interpretation | PROVISIONAL INTERPRETATION | `testNE17_seekingIntoTheCreditsShowsTheProposalWithoutACountdown` |
| NE-18 | Pausing cancels the countdown; reaching the end re-arms it | Interpretation | PROVISIONAL INTERPRETATION | `testNE18_pausingCancelsTheCountdownAndTheEndRearmsIt` |
| NE-19 | **Changed by the batch-2 spec (was: no countdown while a post-credits scene plays).** 60 s or less of content after the credits does not hold Up Next back: it appears at the credits start and the countdown runs | Next Episode spec (NES-4) | SPEC | `testNE19_shortSceneAfterCredits_proposalAndCountdownStillAtCreditsStart` |
| NE-20 | End of file with no proposal yet presents it and counts down | Interpretation | PROVISIONAL INTERPRETATION | `testNE20_endOfFileWithoutAProposalYetPresentsItAndCountsDown` |
| NE-21 | No next episode (last episode of the last season, Season 0, not an episode): no proposal, no advance, the end is reported once | Batch C | SPEC | `testNE21_noNextEpisodeNeverProposesAndReportsTheEndOnce` |
| NE-22 | Skip Credits flows into Next Episode (proposal, then advance with autoplay) | Batch C | SPEC | `testNE22_skipCreditsToTheEndFlowsIntoNextEpisode`, `testNE23_skipCreditsFromBeforeTheProposalPresentsThenAdvances` |
| NE-23 | Skip Credits with autoplay off leaves the proposal waiting | Interpretation | PROVISIONAL INTERPRETATION | `testNE24_skipCreditsWithAutoplayOffLeavesTheProposalWaiting` |
| NE-24 | Skip Credits after a dismissal does not bring the proposal back | Interpretation | PROVISIONAL INTERPRETATION | `testNE25_skipCreditsAfterDismissalDoesNotBringTheProposalBack` |
| NE-25 | After advancing, every event is ignored; duplicate end events repeat nothing | Interpretation | PROVISIONAL INTERPRETATION | `testNE26_eventsAfterAdvanceAreIgnored`, `testNE27_duplicateEndedEventsDoNotRepeatActions` |
| NE-26 | The machine takes an async provider; it never sees the library | Batch C | SPEC | `testNE28_coordinatorAsksTheProviderOnce`, `testNE41_libraryProviderLoadsTheSeriesAndResolves` |
| NE-27 | A file that is not an episode has no next episode | Interpretation | PROVISIONAL INTERPRETATION | `testNE29_nonEpisodeFileHasNoNextEpisode` |
| NE-30 | Next episode in the same season | Batch C | SPEC | `testNE30_nextEpisodeInTheSameSeason`, `testNE31_inputOrderDoesNotMatter` |
| NE-32 | Season rollover: last episode of season N goes to the first of N+1 | Batch C | SPEC | `testNE32_seasonRolloverGoesToTheFirstEpisodeOfTheNextSeason` |
| NE-33 | The last episode of the last season has no next | Batch C | SPEC | `testNE33_lastEpisodeOfTheLastSeasonHasNoNext` |
| NE-34 | Season 0 never auto-advances | Batch C | SPEC | `testNE34_season0NeverAutoAdvances` |
| NE-35 | Rollover never enters Season 0 | Batch C | SPEC | `testNE35_rolloverNeverEntersSeason0` |
| NE-36 | Gaps: the next episode is the next available one in order | Interpretation | PROVISIONAL INTERPRETATION | `testNE36_gapsAreSkipped_nextIsTheNextAvailable` |
| NE-37 | A missing season (or missing first episode) is skipped | Interpretation | PROVISIONAL INTERPRETATION | `testNE37_missingSeasonIsSkippedAndAMissingFirstEpisodeToo` |
| NE-38 | A multi-episode file counts up to its last episode number | Interpretation | PROVISIONAL INTERPRETATION | `testNE38_multiEpisodeFileCountsUpToItsLastEpisode` |
| NE-39 | Several versions of the same episode count once; the first listed wins | Interpretation | PROVISIONAL INTERPRETATION | `testNE39_severalVersionsOfTheSameEpisodeCountOnce` |
| NE-40 | Other series are ignored | Interpretation | PROVISIONAL INTERPRETATION | `testNE40_otherSeriesAreIgnored` |

### Session (skip controller plus Next Episode together)

| Row | Rule | Source | Status | Test |
|---|---|---|---|---|
| SESS-1 | Skip Credits seeks to the end and flows into Next Episode | Batch C | SPEC | `testSESS1_skipCreditsFlowsIntoNextEpisode` |
| SESS-2 | Skip Credits to a post-credits chapter is only a seek | Part B / B4 | SPEC | `testSESS2_skipCreditsToAPostCreditsChapterIsJustASeek` |
| SESS-3 | Automatic Skip Credits seeks with no button and flows on | B10 | SPEC | `testSESS3_automaticCreditsSkipSeeksAndFlowsOnWithNoButton` |
| SESS-4 | Skip Intro only seeks | Interpretation | PROVISIONAL INTERPRETATION | `testSESS4_skipIntroSeeksAndLeavesNextEpisodeAlone` |
| SESS-5 | Skip for a type with no segment does nothing | Interpretation | PROVISIONAL INTERPRETATION | `testSESS5_skipForATypeWithoutASegmentDoesNothing` |
| SESS-6 | Skip Credits after a dismissal does not advance | Interpretation | PROVISIONAL INTERPRETATION | `testSESS6_skipCreditsAfterMenuDismissalDoesNotAdvance` |
| SESS-7 | Credits timing for the machine comes from the resolved credits segment | Interpretation | PROVISIONAL INTERPRETATION | `testSESS7_creditsTimingComesFromTheResolvedSegment` |

## Detection tiers

- Tier 1 (embedded chapters): built, `ChapterTitleRecognizer` and `ChapterSegmentExtractor`.
- Tier 2 (local sidecar and online database): the resolver accepts candidates from these sources and applies the rules above; reading sidecar files and calling databases belongs to the metadata targets.
- **Tier 3 audio fingerprint matcher: not built in this batch.** `SegmentSource.onDeviceDetection` exists so its output can be ranked later (lowest priority).

## Files

| File | What it does |
|---|---|
| `Sources/PlaybackLogic/Segments.swift` | Segment model, limits, rejection reasons, `SegmentResolver` |
| `Sources/PlaybackLogic/Chapters.swift` | `ChapterMark`, multilingual title recogniser, chapter-to-segment extractor |
| `Sources/PlaybackLogic/SkipController.swift` | Skip settings, button state, automatic jump |
| `Sources/PlaybackLogic/NextEpisode.swift` | Clock, episode ordering, async provider, the four modes and the countdown setting, the Next Episode state machine, prefetch and the Skip Credits offer |
| `Sources/PlaybackLogic/DisplayMode.swift` | Display format types and the "keep or switch the display mode" comparison |
| `Sources/PlaybackLogic/PlaybackSession.swift` | Combines the two for one playback |

## How the pieces fit

1. The app collects candidates (chapters through `ChapterSegmentExtractor`, sidecar, online, user) and calls `SegmentResolver.resolve`.
2. It asks a `NextEpisodeProvider` for the next episode and builds a `PlaybackSession`.
3. The player sends playhead updates (`.started`, `.natural`, `.seek`), pause/resume, end, Menu and accept; it applies the returned `SessionUpdate` (button, seek, proposal actions).

## What only an Apple TV can verify

Everything above is pure logic tested in WSL. These are not verified and need a device:

- AVContentProposal presentation, its accept and reject callbacks, and that Menu really reaches the dismiss path.
- `contextualActions` showing the Skip button, its focus, and activation with the remote.
- Siri Remote skip-back after an automatic skip (that the player reports it as a `.seek`).
- That the player reports `.natural`, `.started` and `.seek` playhead kinds the way this code assumes (for example a scrub is a seek, resuming is `.started`).
- Timing in a real AVPlayer (observer cadence, end-of-file notification arriving after the last playhead update).
- Whether the real prefetch (opening the next item ahead of time) is cheap and does not disturb the playing item, and that `.stopped` is sent when the user leaves.
- Whether tvOS needs a display switch for each difference `DisplayModePlanner` reports (resolution class, frame rate, dynamic range family), in particular the choice to treat HDR10+ as HDR10 and the 0.01 fps frame rate tolerance. The planner only compares; it never switches anything.
- That showing the Skip Credits offer as a contextual action works for content that is not marked as a skippable segment by the user's setting (the offer ignores a Skip Credits setting of Off).

## Checks run

```
swift test -j 3 --filter PlaybackLogicTests      # in ~/vp-build-pn, a private copy with a trimmed manifest (VideoPlayerCore + PlaybackLogic + PlaybackLogicTests), run through a script file under /mnt/c/.../Temp
```

Result (2026-11-17): **140 tests, 0 failures, 0 skipped.** Of them 51 are the new `NextEpisodeSpecTests` (the NES rules above) and 11 are `PlaybackSessionTests` (SESS-1 to SESS-11); the earlier 85 tests are kept (four of them adjusted, see "Differences"). The first attempt after the rewrite had 1 failure (`SESS-6`, which expected Menu to return only `proposalDismissed`; the new `cancelPrefetch` is intended), fixed in the test and re-run. The full-manifest run of the whole package is the parent's.
