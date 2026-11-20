# Accessibility screenshots: set and self-audit (#16 item 1.10, #17 A and E)

## 1. Self-audit of screenshots 80 to 89: BLOCKED

The nine checks below need the pictures from a CI run. They are in the GitHub artifact `accessibility-screenshots`, which
cannot be downloaded or viewed from this working environment (no outside contact). So NO check has been run, and no row
says PASS. The table is ready to be filled in from the next CI run (or by anyone who opens the pictures).

Checks (from #16 item 1.10; positions in px on a 1920x1080 frame):

1. No text is cut or ends in "…"; short texts scale to fit (rule S1).
2. Tab bar: every label complete (Home, Movies, Shows, Files, Search, Settings), none clipped, the bar fits.
3. Nothing overlaps (text over text, text over buttons, stray glyphs).
4. Rows and buttons are not clipped by the screen edge or a fixed-height card; the main action is reachable.
5. Buttons of the same kind keep one height; side-by-side elements keep equal size.
6. Focus is visible and the focused item is not cut.
7. No text is smaller than the Apple minimum (R165; tvOS minimum 23 pt, HIG Typography).
8. Bold Text: widths still fit (no new cutting from wider glyphs).
9. No empty band under the tab bar and no dim duplicate title (rules L6 and D1 of #15).

| No. | Setting | Screen | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 80 | Larger Text | Home | not audited | not audited | not audited | not audited | not audited | not audited | not audited | n/a | not audited |
| 81 | Larger Text | Movies grid | not audited | not audited | not audited | not audited | not audited | not audited | not audited | n/a | not audited |
| 82 | Larger Text | Settings root | not audited | not audited | not audited | not audited | not audited | not audited | not audited | n/a | not audited |
| 83 | Larger Text | Files (Sample Library) | not audited | not audited | not audited | not audited | not audited | not audited | not audited | n/a | not audited |
| 84 | Larger Text | Movie page (Sample Movie 1) | not audited | not audited | not audited | not audited | not audited | not audited | not audited | n/a | not audited |
| 85 | Bold Text | Home | not audited | not audited | not audited | not audited | not audited | not audited | not audited | not audited | not audited |
| 86 | Bold Text | Movies grid | not audited | not audited | not audited | not audited | not audited | not audited | not audited | not audited | not audited |
| 87 | Bold Text | Settings root | not audited | not audited | not audited | not audited | not audited | not audited | not audited | not audited | not audited |
| 88 | Bold Text | Files (Sample Library) | not audited | not audited | not audited | not audited | not audited | not audited | not audited | not audited | not audited |
| 89 | Bold Text | Movie page (Sample Movie 1) | not audited | not audited | not audited | not audited | not audited | not audited | not audited | not audited | not audited |

Known from the review in #17 (not from my own look at the pictures): 85–89 showed the app's text NOT bold (only the tab
bar differed), so every Bold Text row was a FAIL of the setting itself. Fixed in code (see section 3); verify in the next
screenshots.

## 2. The set now (#16 item 1.10, #17 E)

Every screen #16 item 1.10 asks for, with its numbers. Added in this change: everything from 90 up.

| Screen | Larger Text | Bold Text | Default (to compare) | Test key |
|---|---|---|---|---|
| Home | 80 | 85 | 102 | home |
| Movies grid | 81 | 86 | 103 | movies |
| Settings root | 82 | 87 | 104 | settings |
| Files (Sample Library folder) | 83 | 88 | 105 | files-root |
| Movie page without a title logo (Sample Movie 1) | 84 | 89 | 106 | movie-detail |
| Movie page with a title logo (Sample Movie 2) | 90 | 96 | 107 | movie-detail-logo |
| Show page (Sample Show 1) | 91 | 97 | 108 | show-page |
| A Settings sub-page: Backup (also #17 D) | 92 | 98 | 109 | settings-backup |
| Add a Source (full screen since #30, R228) | 93 | 99 | 110 | add-source |
| A form (WebDAV, Connect at the bottom) | 94 | 100 | 111 | source-form |
| Search | 95 | 101 | 112 | search |

Simulator settings (job 6, folders `contrast`, `transparency`, `motion`): the first five screens, 113–117.

Still open:
- The title logo. No sample title has one yet; #15 Part 9 adds title logos, and Sample Movie 2 and Sample Show 1 must be
  the sample titles that get one. Until then 90/96/107 and 91/97/108 show the text title.
- The form shot shows the form as it opens. Whether "Connect" is visible without scrolling at Larger Text is part of
  check 4 above (not audited).

Every Larger Text and Bold Text picture is compared with its default one by `scripts/ci-a11y-compare.py` (job 5). The
step fails when a picture is the same as its default one outside the tab bar (rows 51–109 of 1080). Self-test:
`scripts/test-ci-a11y-compare.sh`, 9 checks, in `scripts/test-all.sh`.

## 3. Bold Text: why it did not reach the app, and the change (#17 A)

Cause: the override set only the `legibilityWeight` environment value. Apple's page says that value "reflects the value
of the Bold Text display setting". It tells code what the setting is. It does not say that writing it changes how
`Text` is drawn, and the screenshots show it did not
(https://developer.apple.com/documentation/swiftui/environmentvalues/legibilityweight).

Change: the override (App/Support/UITestAccessibility.swift) now also applies `bold(_:)`, "Applies a bold font weight to
the text in this view", tvOS 16+ (https://developer.apple.com/documentation/swiftui/view/bold(_:)). The HIG names
`bold()` as the way to get a text style's emphasized weight, which on tvOS is Bold for every style except Subtitle 1
(https://developer.apple.com/design/human-interface-guidelines/typography). This is an IMITATION of the setting. Which
weights the real setting gives is not on Apple's pages, so the real setting stays unproven: device checklist V-16.

The tab-bar difference in that run lies outside the override and is not explained.

Larger Text on tvOS: the setting exists. Apple's guide says to go to "Accessibility > Display" and use "Text Size", a
slider, and that "Apps that support Dynamic Type automatically adjust to the Text Size setting"
(https://support.apple.com/guide/tv/display-bold-text-or-change-the-text-size-atvb0222141c/tvos). The CI pictures imitate
it with `dynamicTypeSize` = accessibility3; the real setting is checked on a device (V-15).

## 4. "Complete Issue Description.txt" (#17 E)

index.md listed `Complete Issue Description.txt (030DD148-….txt)` under attachments without a numbered name, but the file
was not in the artifact. The cause is `scripts/ci-screenshots-index.py`: it copied only numbered attachments.

Xcode attaches a file with that name to a test issue (a failure) when the issue's full text is recorded. That
explanation is unverified, from memory. No Apple page was found that names it.

The issue it recorded cannot be read here: the file was never uploaded, and the CI logs cannot be fetched. The failure
messages of that run are in `test-report.md` in the `-logs` artifact.

Change: text attachments without a numbered name are now copied to `other-attachments/` in the same folder, with a link
in index.md. Pictures without a number are still listed but not copied, so the artifact check
(`ci-artifact-contents.sh`) stays valid. Tested on a fake manifest in WSL: the file was copied and linked, three-digit
numbers sorted in numeric order (80, 90, 96, 102), and the artifact check passed.
