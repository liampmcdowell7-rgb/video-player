# Pre-push scan (prompt #20, 2026-11-19)

## 0. What was scanned

`git log origin/main..HEAD` was **empty** when the scan started: the reflog shows `origin/main` was updated "by push"
to 2940de7 on 2026-11-19 at 06:39 (local time), not from this chat. So this is a **post-push** scan of the last pushed range,
`5ea8e96..2940de7` (the previous push to this one): 44 commits, 199 files, +7,427 / −583 lines. The two commits made by
this scan (section 8) are not pushed yet; they touch only `ArtworkTests.swift`, `docs/COVERAGE.md` and this file.

## 1. Commits and files by area

All 44 commits: author and committer "Video Player Dev" <dev@localhost.invalid>; each message ends with the
Co-Authored-By line. Range 8bb0f0c (CI boot and retry) … 2940de7 (#19 E).

| Area | Files | Added | Removed |
|---|---|---|---|
| app (App/) | 60 | 1,303 | 328 |
| packages (Sources) | 39 | 2,136 | 91 |
| tests (package Tests, UITests) | 24 | 1,806 | 63 |
| scripts | 22 | 919 | 15 |
| fixtures (scripts/*-fixtures: lint, ambiguous-types, test-counts) | 37 | 294 | 0 |
| docs (docs/, OPEN_QUESTIONS.md) | 16 | 781 | 30 |
| workflow (.github/workflows/compile-check.yml) | 1 | 188 | 56 |

Unexpected files: **none**. Every file maps to a commit message of #15–#19 (new App/Shared parts, sorting, title logos,
Media Info, lint fixtures, CI scripts). One deletion: `App/Features/Shows/EpisodeRowView.swift` (replaced by the episode
shelf, 1ad42af). The 37 fixture files are small Swift snippets that the lint, ambiguous-types and test-counts
self-tests read.

## 2. Secrets (every changed file and every commit message)

| Pattern | Result |
|---|---|
| Private keys, certificates (`BEGIN … PRIVATE KEY`, `BEGIN CERTIFICATE`, .p8/.p12/.mobileprovision) | 0 |
| Service tokens (AKIA…, ghp_/gho_/github_pat_, xox…, AIza…, sk-…, JWT `eyJ…`) | 0 |
| Signed URLs (X-Amz-Signature, X-Goog-Signature, sig=, token=/api_key= with a long value) | 0 |
| Assigned secrets (`key/secret/password/token = "16+ chars"`) | 0 |
| Long hex or base64 strings (32+) | 9, all harmless: the XcodeGen download SHA-256 (6× in the workflow), the TMDB logo file's SHA-256 in design-lint.sh, a fake Jellyfin item id in JellyfinClientTests (2×) |
| `scripts/pre-push-check.sh` secret scan (whole tree) | "No secret patterns found" |

## 3. Personal and local identifiers

| Check | Result |
|---|---|
| The user's name or personal e-mail in files or commit messages | Only the decided identifiers `com.liamp.videoplayer` and its iCloud / App Group / Top Shelf forms (user decision R147, also in COVERAGE.md) and the GitHub account in the public repository address (GITHUB_ACTIONS_RUNBOOK.md). Nothing else |
| E-mail addresses | Only dev@localhost.invalid and the Co-Authored-By noreply address |
| Windows / WSL paths | 0 real paths. 3 hits are explanations: R47 (how a stray `CUsers<name>` folder came about, no name), R146 (wording), and a comment in test-all.sh saying "use /mnt/c/... paths" |
| Machine names (DESKTOP-…, LAPTOP-…) | 0. ".local" hits are code (`secrets.local`, Bonjour `.local` names) and test hosts `nas.local`, `server.local` |
| IP addresses | Only private example addresses in tests (192.168.1.20/30, 10.0.0.5/6) |
| Device ids | 0. The 40-character hex strings are public upstream commit ids in the licence notice (NAMES.md) |

## 4. Content that must not be there

| Check | Result |
|---|---|
| Real brand artwork or copied assets | 0 binary files in the range; the title logos and posters in the fixtures are generated at run time (GradientPNG, LogoPNG) |
| TMDB logo | Only `Image("TMDBAttributionLogo")` in `App/Features/Settings/AboutView.swift` (Settings > About > Data Sources, R148); the lint pins the file's SHA-256 |
| Brand names | Only technology and service names used as text (TMDB, Jellyfin, Emby, Dolby Vision …), as the names rule allows |
| **Real media titles** | **Problem 2 (below).** This range added 7 test lines using a real film title ("Heat (1995)") in `ArtworkTests.swift`; fixed (section 8). Older unit tests in 12 other files still use real titles |
| Sample data in a Release build | See below |

**Release-string check.** The real check (`ci-inspect-device-app.sh`, list `VP_RELEASE_FORBIDDEN_RE` in
`ci-inspect-lib.sh`) runs on the signed-off tvOS Release app in CI and **was not run** (no build allowed). Its self-test
passed (`test-ci-inspect.sh`, 22 in test-all). A local stand-in was run: the same forbidden list over AppLogic's
Linux object files.

| Build | Objects | Forbidden-text hits | D7 episode title "A quiet beginning" | UITestFixtures.o |
|---|---|---|---|---|
| Release (`swift build -c release`) | 44 | 2, both only the **source file path** in debug info (`…/UITestFixtures.swift`, `…/UITestLaunch.swift`), no sample text | 0 | 8,968 bytes |
| Debug (control) | 44 | 631 | 2 | 482,584 bytes |

So the sample library compiles out of Release AppLogic; the file-path strings come from Linux debug info and are what
the CI check on the real app will judge (it has passed there before on the same names).

## 5. Large or binary files

- Binary files changed in the range: **0**. Largest changed text files: OPEN_QUESTIONS.md 133 KB, DESIGN_SYSTEM.md 48 KB,
  QueryTests.swift 45 KB, compile-check.yml 45 KB, ScreenshotTests.swift 42 KB.
- pre-push-check: "No file is over 50 MiB."
- `Packages/VideoPlayerCore/Package.resolved`: **untracked** (`git ls-files` count 0), as required.

## 6. Workflow safety (`.github/workflows/compile-check.yml`)

- Trigger: `on: workflow_dispatch: {}` only (no push, pull_request, schedule).
- Runner: `runs-on: xcode-27` in all 6 jobs; no -large/-xlarge label.
- Secrets: no `secrets.` reference; pre-push-check agrees ("no secrets").
- Time caps: every job `timeout-minutes: 30`; long steps have their own caps (2–20 minutes).
- Paid features: none (standard runner, artifacts only).

## 7. `scripts/pre-push-check.sh`

Run 2026-11-19 after the fix in section 8 (before committing it): **exit 0**. Secret-looking file names: none. Secret
patterns: none (Vendor/ counted, 15 files with public upstream sample keys, not scanned, as designed). Workflows: manual
only, no secrets, standard runners. Duplicate test class names: none. Large files: none.

## 8. Fixes made by this scan

- `ArtworkTests.swift`: "Heat (1995)" and "Alien (1979)" renamed "Sample Movie One (1995)" and "Sample Movie Two (1979)"
  in the whole file (7 of the lines were added in 890e1dd, the rest of the file used the same names). AppLogic tests:
  381 passed, 0 failed.
- `docs/COVERAGE.md`: the #19 E note wrongly said the FixMatchTests name clash still moved 5 tests between targets; it
  was fixed in bebc090 and the counts are correct.

## Problems

1. Nothing was left to scan before pushing: the range was pushed at 06:39 before this scan ran. Results above are for
   what is already on GitHub. No secret or personal identifier was found in it.
2. Real film titles remain in older unit-test data (test targets only, never in the app): LibraryScreenTests,
   LibrarySupport (AppLogicTests); FoundationTests, PurgeBackupRestoreTests, QueryTests, SyncTests (LibraryIndexTests);
   FixMatchTests, Fixtures, LibraryOnlyTests, MatchEngineTests, OMDbClientTests, TMDBClientTests (MetadataOnlineTests).
   Some of them are recorded TMDB/OMDb responses that match on the title. Not changed: not this range's work, and
   renaming would need new recorded fixtures. Decision needed.
3. The Release-string check on the real tvOS Release app was not run (needs the CI build); the local stand-in is clean.
