# GitHub Actions compile check: runbook

Rewritten 2026-11-17 (OPEN_QUESTIONS R152). **You decide when, and whether, to do any of this.** None of it has been done yet:
no repository has been created, nothing has been pushed, no GitHub setting has been changed and the workflow has never run.
You do every step yourself on Windows, in a web browser and in a terminal window. Do the parts in order. If anything you see
differs from what a step describes, stop at that step. Nothing in this runbook asks you to contact anyone.

- Repository name: `video-player`
- Repository page: https://github.com/liampmcdowell7-rgb/video-player
- Remote URL (what git pushes to): `https://github.com/liampmcdowell7-rgb/video-player.git`
- Workflow name on the Actions tab: **Compile check (tvOS Simulator, no signing)**
- Branch: `main`

## What was checked (facts this runbook relies on)

- **Cost.** Standard GitHub-hosted runners are free in public repositories. Larger runners are billed even in public
  repositories, and they need a payment method on file. Source: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- **Runner.** `xcode-27` is **generally available**. GitHub changelog, 15 October 2026, "Xcode 27 runner image generally
  available": https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/ . The labels are `xcode-27`
  (standard) and `xcode-27-xlarge` (larger, paid). `xcode-27` (3 CPU M1, 7 GB RAM, 14 GB disk, arm64) is in the standard-runner
  table: https://docs.github.com/en/actions/reference/github-hosted-runners-reference
- **Paid labels.** These are larger runners and are refused by the pre-push check:
  - `macos-latest-large`, `macos-15-large`, `macos-26-large`
  - `macos-latest-xlarge`, `macos-15-xlarge`, `macos-26-xlarge`, `xcode-27-xlarge`

  Sources: https://docs.github.com/en/actions/reference/runners/larger-runners and https://github.com/actions/runner-images
- **Xcode.** The `xcode-27` image has Xcode 27.0, 27.1 (the default) and 27.2, with the tvOS 27.2 SDK and tvOS 27.2
  Simulator SDK. The workflow selects Xcode 27.2. Source:
  https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md . The `macos-26` / `macos-latest`
  images have only Xcode 26.x and cannot build this project, because it targets tvOS 27.0.
- **XcodeGen.** It is not on the image. The workflow downloads XcodeGen 2.46.0 from its GitHub release and checks the
  SHA-256 published on the release page; a mismatch stops the run.
- **Budget form.** The fields and buttons in Part A come from https://docs.github.com/en/billing/how-tos/set-up-budgets .
  That page says that if "Stop usage when budget limit is reached" is left unticked, you only get an e-mail and usage
  does not stop.
- **Payment information.** The click path in Part A comes from
  https://docs.github.com/en/billing/how-tos/set-up-payment/manage-payment-info .
- **Your account.** On 2026-11-17, https://github.com/liampmcdowell7-rgb existed and showed 0 public repositories.
  https://github.com/liampmcdowell7-rgb/video-player answered "404 Not Found".
- **Local repository.**
  - It has no remote. Its branch is `main` and it holds exactly **one** commit, signed
    "Video Player Dev <dev@localhost.invalid>".
  - The earlier history was replaced by that single commit (R146). A backup bundle of the old history is kept outside the
    project folder; it is never pushed.

## What becomes public

Everything in the project folder that is committed: the app code (`App/`, `TopShelf/`), the package
(`Packages/VideoPlayerCore/`, including the prebuilt libraries and the third-party code under `Vendor/`, each with its
licence), `docs/`, `scripts/`, `.github/`, `README.md`, `OPEN_QUESTIONS.md`, `project.yml`, `codemagic.yaml` and `.gitignore`.

Personal details: a scan of every file and of the single commit found no e-mail address of yours, no Windows user name, no
`C:\Users\...` or home-folder path, no time zone in the commit, no password, no key and no token. Some third-party source
files keep their authors' own e-mail addresses in their copyright lines; that is upstream text. Two things you decided to
keep do appear:

- Your GitHub user name `liampmcdowell7-rgb`: in this runbook, and in the address of the source repository that the
  open-source licence offer needs (Settings > About in the app, `AboutNotices.swift`, and docs/NAMES.md section 4a).
- The short name `liamp` inside the identifiers `com.liamp.videoplayer`, `com.liamp.videoplayer.topshelf`,
  `group.com.liamp.videoplayer` and `iCloud.com.liamp.videoplayer` (your decision, R147).

## Part A: make sure GitHub can never charge you (browser)

1. Open https://github.com in your browser and sign in.
2. Go to the billing overview page. Paste this address into the address bar and press Enter:

   ```text
   https://github.com/settings/billing
   ```

3. Click **Budgets and alerts**, then click **New budget**.
4. Fill in the form:
   - **Budget Type**: choose **Product-level budget**, and choose **Actions** in the product drop-down.
   - **Budget scope**: choose your whole account, not one repository.
   - **Budget**: type `0`.
   - Tick **Stop usage when budget limit is reached**.
   - Optional: tick **Receive budget threshold alerts**.

   Then click **Create budget**.

   *Success looks like this:* the **Budgets and alerts** page lists an Actions budget of $0 with stop usage switched on.

   *If it fails:* if the stop-usage box is missing or cannot be ticked, do not go on with the rest of the runbook. Without a
   payment method GitHub blocks paid usage anyway (Part A step 6), but the budget is the second safeguard you asked for.
5. Check that no payment method is on file:
   1. Click your profile picture in the upper-right corner of any GitHub page.
   2. Click **Settings**.
   3. In the **Access** section of the left sidebar, click **Billing & Licensing**.
   4. Click **Payment information**.

   *Success looks like this:* no credit card and no PayPal account is listed.

   *If a payment method is listed:* you can remove it on that page, or leave it there and rely on the $0 budget with stop
   usage. Never add one for this project.
6. Why this is enough: this project only uses the free standard runner, in a public repository. GitHub blocks paid usage when
   no valid payment method is on file, and larger runners cannot run at all without one.

## Part B: create the empty public repository (browser)

1. Check whether the repository already exists. While signed in, open:

   ```text
   https://github.com/liampmcdowell7-rgb/video-player
   ```

   - **"404 Not Found"**: it does not exist. Go to Part B step 2.
   - **It exists, is empty and is private**:
     1. Click **Settings** on the repository.
     2. Scroll down to **Danger Zone** and click **Change visibility**.
     3. Choose **Public** and confirm.

     Then skip to Part C.
   - **It exists and already has files**: stop. Pushing would be refused. Do not delete anything.
2. Open the new-repository page:

   ```text
   https://github.com/new
   ```

3. Fill in the page:
   - **Owner**: `liampmcdowell7-rgb`
   - **Repository name**: type `video-player`
   - Choose **Public**. Standard runners are free only in public repositories.
   - Leave **Add a README** unticked. Leave **.gitignore** and **license** set to none: anything added here makes the first
     push fail.

   Click **Create repository**.

   *Success looks like this:* a page titled `liampmcdowell7-rgb/video-player` that says the repository is empty and shows
   "Quick setup" instructions. Ignore those instructions; Part C replaces them.

## Part C: check the project and push it (terminal)

1. Open a terminal in the project folder:
   1. In File Explorer, open the folder that contains `project.yml`.
   2. Right-click an empty area of the folder and choose **Open in Terminal**.

   A PowerShell window opens. Type every command below into it, then press Enter.
2. Check that git is installed:

   ```powershell
   git --version
   ```

   *Success looks like this:* a line such as `git version 2.x`.
   *If it says "not recognized":* Git for Windows is missing. Stop here.
3. Check that everything is committed:

   ```powershell
   git status
   ```

   *Success looks like this:* `On branch main` and `nothing to commit, working tree clean`.
   *If files are listed:* stop. The project has uncommitted changes, so it is not the checked version.
4. Check that there is exactly one commit:

   ```powershell
   git log --oneline
   ```

   *Success looks like this:* exactly one line, ending in `Video Player: tvOS app, package, tests, docs and compile-check
   workflow`.
   *If there is more than one line:* stop. The history has not been replaced.
5. Check the commit's author:

   ```powershell
   git log -1 --format="%an <%ae>"
   ```

   *Success looks like this:* `Video Player Dev <dev@localhost.invalid>`.
   *If it shows anything else:* stop.
6. Run the pre-push check. **Run this before git push, every time.**

   ```powershell
   & "C:\Program Files\Git\bin\bash.exe" scripts/pre-push-check.sh
   ```

   *Success looks like this:*
   - `No secret patterns found.`
   - `Workflows: manual trigger only, no secrets (testflight.yml: its four named secrets only, R248), standard runners only.`
   - `No file is over 50 MiB.`
   - No line starts with `!!`.
   - A line saying that some `Vendor/` files contain sample keys is expected: that is public third-party test text.

   *If any line starts with `!!`:* stop and do not push. The check refuses:
   - any secret;
   - any trigger other than the manual button;
   - any `runs-on` label ending in `-large` or `-xlarge` (including `xcode-27-xlarge`);
   - any file over 100 MiB.
7. Connect the local repository to GitHub:

   ```powershell
   git remote add origin https://github.com/liampmcdowell7-rgb/video-player.git
   ```

   Then check the connection:

   ```powershell
   git remote -v
   ```

   *Success looks like this:* two lines, both showing `https://github.com/liampmcdowell7-rgb/video-player.git`.

   *If it says "remote origin already exists":* run the next command, then run `git remote -v` again.

   ```powershell
   git remote set-url origin https://github.com/liampmcdowell7-rgb/video-player.git
   ```
8. Push:

   ```powershell
   git push -u origin main
   ```

   If a browser window asks you to sign in to GitHub, sign in and allow it. The push uploads the prebuilt libraries too, so it
   can take several minutes.

   *Success looks like this:* the output ends with a line like `branch 'main' set up to track 'origin/main'`.

   *If it fails:*
   - **"rejected"**: the repository on GitHub is not empty. Go back to Part B step 1.
   - **"exceeds GitHub's file size limit"**: a file is too big. Do not retry.
   - **An authentication error**: run the push command again and complete the browser sign-in.
9. Check in the browser:

   ```text
   https://github.com/liampmcdowell7-rgb/video-player
   ```

   *Success looks like this:* the folders `App`, `Packages`, `docs` and so on are shown, and the commit count says
   **1 commit**.

## Part D: run the compile check (browser)

1. On the repository page, click the **Actions** tab.
2. In the left list, click **Compile check (tvOS Simulator, no signing)**.
3. On the right, click **Run workflow**, keep **Branch: main**, then click the green **Run workflow** button.

   This button is the only way the workflow runs. Nothing runs on a push. A run stops by itself after at most 30 minutes.
4. Refresh the page after a minute. A new run appears with a yellow dot while it is running.
5. Wait for the result:
   - A **green tick** means the app and the Top Shelf extension compiled for the tvOS Simulator.
   - A **red cross** is expected for the first run: nothing in `App/` has ever been compiled.

   Both results are useful. Since the third compile check the run has several jobs (now five); Part F lists them and their downloads.

   *If the run stays "Queued" for a long time:* the free standard runners are busy. Wait; do not switch to another label.

   *If the step "Select Xcode 27.2" fails:* GitHub has changed the image. The fix is one line (`XCODE_APP`) in
   `.github/workflows/compile-check.yml`.

## Part E: save the results

Save the error list in either of these two ways.

**Browser:**

1. Open the run and scroll to **Artifacts** at the bottom.
2. Click **compile-check-results** to download a zip file.
3. Unzip it into your Downloads folder. Do not unzip it into the project folder.

The zip holds three files:

- `errors.txt`: the short list (file, line, message).
- `errors-other.txt`: errors that have no file position.
- `build.log`: the full log.

The run's **Summary** page shows the same short list, so you can also copy it from there.

**Terminal (the `gh` tool is installed and signed in):**

1. List the newest run:

   ```powershell
   gh run list --repo liampmcdowell7-rgb/video-player --workflow compile-check.yml --limit 1
   ```

   This prints one line. The long number in it is the run ID.
2. Download the results. Put the run ID in place of `RUN-ID`:

   ```powershell
   gh run download RUN-ID --repo liampmcdowell7-rgb/video-player --name compile-check-results --dir "$env:USERPROFILE\Downloads\compile-check"
   ```

   *Success looks like this:* the folder `Downloads\compile-check` contains `errors.txt`, `errors-other.txt` and `build.log`.

   *If it says "no artifact":* the run failed before the upload step. Open the run in the browser and read its last red step.

## Part F: the six jobs and their downloads (third compile check onwards, OPEN_QUESTIONS R161)

One press of **Run workflow** starts six jobs (#24 D removed the seventh, the accessibility-settings screenshots; OPEN_QUESTIONS
R197). Each has its own line on the run page, its own tick or cross, and its own download. The Simulator build, the
device build and the package tests have a 30-minute limit each; the three screenshot jobs 60 minutes each (#24 B), the two
Screenshots parts 75 minutes since R367.

**Order (#23 E).** "Build app + Top Shelf (Simulator)" and "Package tests" start at once. The device build and the three
screenshot jobs wait for the Simulator build (`needs: compile`) and start only when it is green, about 5 minutes later
(it took 4:27 in the run of fa00af8, plus queueing). When the app does not compile, they are skipped (grey), and a small
job **"Not taken (the app did not compile)"** (ubuntu-latest, about a minute) uploads `screenshots`,
`screenshots-library`, `accessibility-screenshots` and `device-build-results` with `NOT-TAKEN.txt` / `index.md` saying
"NOT TAKEN: the app did not compile" and the first error line (the device reports say "NOT CHECKED"). The first compile
of the App target (#23) failed, and the other jobs then spent their whole time on the same error.

| Job (name on the run page) | What a green tick proves | Download (Artifacts list) | What is inside |
|---|---|---|---|
| Build app + Top Shelf (Simulator) | The app and Top Shelf compile for the tvOS Simulator (arm64) | `compile-check-results` | `errors.txt`, `errors-other.txt`, `build.log` |
| Build app + Top Shelf (Apple TV device, Release, unsigned) | The same compile for a real Apple TV, and the device slices of the codec frameworks, libnfs and the Dolby Vision RPU library link | `device-build-results` | `errors.txt`, `build.log`, `embedded-frameworks.txt`, `macho-report.txt`, `static-libraries.txt`, `release-strings.txt`, `process-spawning.txt` (#23 C; every report says NOT CHECKED when the build failed) |
| Package tests (tvOS Simulator) | The package unit tests build and pass on tvOS (tests that need a server, iCloud or a tool are skipped, not failed) | `simulator-test-results` | `test-report.md` (passed / skipped / failed per test target, then the failures), `test.log` |
| Screenshots, part 1 (setup, Settings, sorting; tvOS Simulator, UI tests) | The UI tests 01, 02, 03, 05, 14 and 10 ran (each its own call) and took pictures | `screenshots` and `screenshots-logs` | `02-….png`, `03-….png` … in viewing order (67 planned: first launch, Add a Source, Settings, About, Files, Search, the card menu 08, the sorting screens 63–69), `index.md`, `notes/` |
| Screenshots, part 2 (player, synopsis, library and detail pages; tvOS Simulator, UI tests) | The UI tests 12 and 13 ran first (13 after a clean simulator: shut down, erase, boot), then 15, 04 and 16, and took pictures | `screenshots-library` and `screenshots-library-logs` | the same kind of folder: the Movies and Shows toolbars and menus 07, the player clip 22–27, Home (with the Continue Watching caption), Movies, Shows, the movie and show pages 44–62, the synopsis pages 77–78 (64 planned; test15 takes no picture), with its own `index.md` and `notes/` |
| Accessibility screenshots (tvOS Simulator, UI tests) | Eleven screens were drawn with Larger Text and Bold Text (the app's imitation of those settings) and at the default size, and each Larger Text and Bold Text picture differs from its default one outside the tab bar (OPEN_QUESTIONS R170, #17 A) | `accessibility-screenshots` and `accessibility-screenshots-logs` | folder `text` with its `index.md`: 80–84 and 90–95 Larger Text, 85–89 and 96–101 Bold Text, 102–112 the same screens at the default size (33 planned); `a11y-compare.txt` (the comparison) |

**Increase Contrast, Reduce Transparency and Reduce Motion are device checks only (#24 D).** The tvOS simulator cannot
turn them on, so no job takes pictures of them any more (OPEN_QUESTIONS R197, provisional). Check them on the Apple TV
with docs/DEVICE_TEST_CHECKLIST_VISUAL.md: **V-17** Reduce Transparency (bars and menus solid and readable), **V-18**
Increase Contrast (labels and focus still clear), **V-19** Reduce Motion (no large movement from the app's own
animations). Each is in Settings > Accessibility on the Apple TV.

**Partial runs still give you files (#24 A).** The run of fa00af8 gave no picture at all: each screenshot job ran its
tests in one xcodebuild call, the time limit stopped it, and the half-written result bundle could not be read. Now:
- every UI test is its own xcodebuild call, and its pictures are copied into the download right after it. A test that
  fails does not stop the tests after it;
- every picture is also written as a PNG file at once, so even a test that is stopped half-way keeps the pictures it
  took (the logs download has the loose files in `screenshot-files/`);
- the tests have **25 minutes counted from the start of the first UI test** (`CI_TEST_BUDGET_SECONDS`; 40 minutes in the two
  Screenshots jobs since R367, whose job cap is 75 minutes). A test still
  running then is stopped (`TIME BUDGET: stopping`: first the polite stop, Ctrl-C, with 60 seconds to finish; then a
  hard stop), the rest are not started, and `index.md` begins with **TEST STOPPED BY THE TIME BUDGET: pictures up to
  <name>**;
- every upload step runs even when an earlier step failed or ran out of time (`if: always()`), and a step "Collect the
  pictures any cut-off test left" runs before them.

Each `index.md` lists every test (passed, failed, stopped or not started, its time and seconds per picture), then
**Planned / Taken / Missing / Failed / Warnings** against the plan, then every picture with its size, then the screens
not reached (with the reason), the missing ones and the warnings (a picture identical to the one before it is a
WARNING, not a failure; the picture is kept, except where a step is marked as meant to change the screen: then the test
fails, #33 L).

**Notes** (`notes/` in each download, docs/COVERAGE.md "UI-test jobs" has the full list): `-NOT-REACHED` and
`-UNCHANGED` as above; `-COVER` (the page behind a full-screen cover is hidden from VoiceOver, the cover is not); `-NAME`
(the server name on 21); `-GAP` (measured gaps on 55, 57 and the toolbar pictures); `-CONTRAST` (31 and 78);
`fresh-simulator-<test>.txt` (part 2: the clean simulator before test13 and its seconds); `hang-sample-<test>.txt` (a
sample of the app's main thread when a test hung). None of them fails a job by itself.

**Stage times.** Each job's summary (open the job, scroll to the top of its page) has a table "Stage times" saying how
long each step took, so you can see where the time goes. The same table is `stage-times.md` inside that job's download
(for the screenshots jobs: inside the `-logs` download).

**Screenshots job, launch smoke (fourth compile check onwards, OPEN_QUESTIONS R164).** Before any UI test, the job
installs the app and launches it twice: once plain, once with `-UITestEmpty`. For each, the log shows either
`LAUNCH OK (plain)` / `LAUNCH OK (uitest-empty)` (the app was still running 8 seconds later) or `LAUNCH FAILED (...)`
followed by the crash report (first 120 lines), the simulator's log lines and the app's last 100 console lines. A failed
launch turns the job red but the UI tests still run. The job is built with ad-hoc signing (no certificate, no secret);
the log prints the signature and the entitlements the app carries. `screenshots-logs` now also holds `attachments/`
(crash reports, videos and text files from the test results) and `launch-smoke-*/`. A screenshot is only taken while
the app is in front; otherwise the test fails and `index.md` lists the screen as not reached.

**When the simulator itself fails (a runner problem, not our code).** Run 44424319207: the package tests job stopped with
0 tests, and its log said `Failed to load requested runtime bundle (.../tvOS 27.0.simruntime)` and
`Malformed bundle does not contain an identifier`. The same runner image had worked the run before. Since then, the three
jobs that use the simulator (Package tests, both Screenshots jobs, Accessibility screenshots) do this (scripts/ci-sim.sh):

- They print `xcrun simctl list runtimes` and `xcrun simctl runtime list` in the step "Pick the simulator", and
  the same lists sit in the job summary under "Simulator runtimes on this runner" (and in `sim-runtimes.txt` in the
  download). A missing or broken tvOS runtime shows there.
- They pick the **runtime first** (#21 A): the one matching the tvOS Simulator SDK (27.2 with Xcode 27.2), else the
  newest; an older runtime only when no newer one exists. Then the device by name on that runtime. The log lists every
  runtime found and says which was chosen and why (`runtime found: …`, `chosen: …`, `why: …`). The earlier order (name
  first) is why the Package tests job of the last run took the 3rd generation on tvOS 27.0 and failed with 0 tests.
- They boot the simulator and wait for it before any test, in the stage **Boot and retry** of the Stage times table.
- If booting fails, or a test run stops with "Failed to load requested runtime bundle" or "Failed to prepare device", the
  job tries **once** more. When the runtime failed to load, that runtime is marked unavailable for the job and the
  simulator on the next runtime is booted and used (the same test call runs again with its id). When there is no other
  runtime, or the failure was something else, it shuts all simulators down, erases the chosen one and boots it again.
  The log then shows a yellow warning and a line `SIMULATOR RETRY: <reason>`. A test that fails for any other reason is
  never retried. After one retry, later failures in the same job are reported as they are.
- The job summary says `Simulator ready after N s (retries: 0/1)`, the runtime used, any runtime marked unavailable,
  and the retry reason.
- When no test ran because the runtime did not load, the test report starts with **NO TESTS RAN: simulator runtime
  failed to load** and the cause line, not only an empty table.

*If such a job is still red with one of those two messages:* on the run page press **Re-run jobs**, then **Re-run failed
jobs**. That is the first thing to try; it starts only the red jobs again, on a fresh runner. Do not change the app or
the tests for this failure. If it fails the same way twice, send the "Simulator runtimes on this runner" list from the job
summary.

## Run time budget and runner minutes (#24 B)

**Measured in the run of fa00af8** (2026-11-19): Compile 4:27 (the compile step), Package tests 1,922 passed / 155 skipped
/ 0 failed. Each screenshot job before its tests: prepare 1:18, pick and boot 1:29, build 7:37–7:48, launch smoke
1:11–1:21. UI tests: test01 68 s, test02 36 s, test03 148 s, test10 312 s, test04 436 s, test05 39 s, test06 628 s
(tests 11, 12, 13 and 14 were not reached). All three screenshot jobs were stopped by the time budget and gave no picture.

**The split since #34** (docs/COVERAGE.md "UI-test jobs" has the detail; times measured in the run of 20 Nov, OPEN_QUESTIONS
R232):

| Job | Tests | Planned pictures | UI tests | Job time (estimate) |
|---|---|---|---|---|
| Screenshots, part 1 | 01, 02, 03, 05, 14, 10 | 67 | about 18:40 | about 26 min (30 measured with test12 and test13) |
| Screenshots, part 2 | 12, 13 (after a clean simulator), 15, 04, 16 | 64 | about 17:35 to 18:55 | about 30 min (25 measured without them) |
| Accessibility screenshots | 06, 11 | 33 | 18:28 (measured) | 31 min (measured) |

**#25 C1:** the accessibility job measured 24:47 start to end on 1fe5d50, so its UI tests took about 12-13 minutes, half
of the 25-minute budget; #25 adds no picture there and its new waits end as soon as the element is there. test11 stays in
that job (docs/COVERAGE.md has the reasoning). Expected pictures per set: **67 / 64 / 33 = 164** (#34: test12 and test13
moved to part 2, two Continue Watching caption pictures added to test04; earlier 83 / 26 / 33 = 142, and the run on 1fe5d50
delivered 54 / 20 / 33).

**How many minutes a full run uses (estimate; each job's summary now prints its own "Runner minutes for this job"):**

| Job | Runner | Minutes (estimate) |
|---|---|---|
| Build app + Top Shelf (Simulator) | macOS (xcode-27) | about 7 |
| Build app + Top Shelf (Apple TV device) | macOS | about 7 (6:23 in the run of 5ea8e96) |
| Package tests | macOS | about 12 (not in the #24 numbers; an estimate) |
| Screenshots, part 1 | macOS | about 26 (30 measured on 20 Nov, before #34 moved test12 and test13) |
| Screenshots, part 2 | macOS | about 30 (25 measured on 20 Nov, plus test12, test13 and the clean simulator) |
| Accessibility screenshots | macOS | about 31 (measured on 20 Nov) |
| **All jobs** | | **about 113 macOS minutes** |

The run takes about **40 minutes** from the button to the last upload (the Simulator build first, then the five other
jobs side by side). GitHub bills every job in whole minutes, rounded up. On a standard runner in a **public** repository
these minutes are **free** (0 USD; docs.github.com, "GitHub Actions billing", checked 2026-11-17 for this runbook). The
worst case, every job at its limit, is 30 + 30 + 30 + 60 + 60 + 60 = 270 minutes, still free on a public repository.

Every test is named in exactly one job (compile-check.yml) and in scripts/screenshot-plan.tsv, so a new screenshot test
must be added to both.

**Step by step after the run has finished:**

1. Open the run. Scroll to **Artifacts** at the bottom.
2. Click each of the nine names above to download a zip file: `compile-check-results`, `device-build-results`,
   `simulator-test-results`, `screenshots`, `screenshots-logs`, `screenshots-library`, `screenshots-library-logs`,
   `accessibility-screenshots`, `accessibility-screenshots-logs` (the three `-logs` ones only matter if their job is
   red or a picture is missing).
3. Make a new folder `Downloads\run-3` and unzip each zip into its own subfolder there. Do not unzip into the project folder.
4. Open `screenshots\index.md` (any text editor) and look at the pictures in number order, then
   `screenshots-library\index.md` (the numbers continue across both: part 2 holds 07, 22–27, 44–62 and 77–78). At the end
   of each `index.md`, "Fixed in code, verify in these screenshots" (#21 G) lists each change still to be checked by eye,
   what to look for, and the pictures that show it (or NOT REACHED). Look at 08 (the card long-press menu) every time:
   a wrong SF Symbol name builds and passes every test but draws a blank icon, and the three icons of that menu were
   named from memory (#22 D; every symbol and its screenshot are in docs/SYMBOLS.md). Then open
   `accessibility-screenshots`: `text` holds the Larger Text pictures (80–84, 90–95), the Bold Text pictures (85–89,
   96–101) and the same eleven screens at the default size (102–112), so each can be compared with its default one;
   `a11y-compare.txt` says for each whether it differs from the default outside the tab bar (#17 A).
   Each of the three screenshot zips has a `CONTENTS.txt` at the top: every file in it, and which set it should be. The
   job checks this before uploading (`scripts/ci-artifact-contents.sh`, #15 item 1.2): `screenshots` must hold only
   01–79 at the top with `index.md`, and `accessibility-screenshots` only 80 and above in `text/`. A wrong set
   turns the step "List and check what the … artifact holds" red, with one `ARTIFACT PROBLEM:` line per file. Unzip each
   zip into its OWN folder: zips unzipped into one folder overwrite each other's `index.md`.
5. Send back, in this order of importance:
   - `compile-check-results\errors.txt` and `device-build-results\errors.txt` (even if empty);
   - `device-build-results\embedded-frameworks.txt`, `static-libraries.txt` and `release-strings.txt`;
   - `simulator-test-results\test-report.md`;
   - `screenshots\index.md` and the screenshots (the whole folder, or the ones that look wrong);
   - `accessibility-screenshots\a11y-compare.txt` and any accessibility picture that looks wrong;
   - the "Stage times" table of any job that took longer than 25 minutes;
   - for any red job without an `errors.txt`: the name of its last red step and the last 30 lines of that step.

**Terminal alternative:** `gh run download RUN-ID --repo liampmcdowell7-rgb/video-player --dir "$env:USERPROFILE\Downloads\run-3"`
downloads every artifact of the run into one folder each.

*If the screenshots job is red but `screenshots` has pictures:* the pictures are still valid; `index.md` and
`screenshots-logs\test-report.md` say which test step failed.

## Do not

- Do not run the Codemagic build. `codemagic.yaml` stays only for a TestFlight upload later.
- Do not change `runs-on` to any label ending in `-large` or `-xlarge`.
- Do not add a trigger other than the manual button.
- Do not add secrets to the repository.
- Do not add a payment method to GitHub for this project.

## Notes

- Only people with write access to the repository can press **Run workflow**. Others can read the code and the run logs.
- The workflow uses no secrets. Every workflow job automatically receives GitHub's short-lived token. Here that token is
  limited to read-only access to the code (`permissions: contents: read`), and the checkout step uses it to download the code.
