# TestFlight from GitHub Actions (no Mac needed)

Goal: press one button on GitHub, and a signed build of Video Player appears in TestFlight on your Apple TV 4K.

How to read this list: do the steps **in order**, top to bottom. **YOU** = you do it, on the website or device named in the
step. **CODE** = already done in this repository; nothing for you to do, it only tells you what the code does. In the page
addresses, `<you>/<repository>` is your GitHub account and repository name as in the address bar of your repository page.

Button and menu names marked *(unverified)* were not checked on the live site for this page (nobody here could open
Apple's or GitHub's sites); the others are quoted from the Apple and GitHub pages listed at the end, read on 20 Nov 2026.
If a name differs on screen, look for the nearest match and tell me. Open choices: OPEN_QUESTIONS.md R244 to R252 (all
PROVISIONAL). docs/CODEMAGIC_SETUP.md is the older Codemagic route; steps 3 to 11 here are the same Apple steps, so skip any
you already did there.

**Never** put the `.p8` key file, its text, or the Key ID, Issuer ID or Team ID into the repository, an issue, a commit, a
screenshot or a chat. They go only into GitHub's encrypted secrets (step 16).

1. **YOU (GitHub website)** — check the repository is public. Page: `https://github.com/<you>/<repository>/settings` (tab
   **Settings**, section **General**). At the bottom, under **Danger Zone**, **Change repository visibility** says what it is
   now *(unverified)*. Keep it **public**: GitHub's billing page says "Standard GitHub-hosted runners in public
   repositories" are free, and this workflow uses one (`xcode-27`). If it were private, macOS minutes cost USD 0.062 each
   against USD 12 of included use per month on GitHub Free, so one run (an estimated 15 to 20 minutes) would cost about
   USD 0.90 to 1.25 (R250). Do not change anything on this page.
2. **YOU (Apple website)** — note your **Team ID**. Page: https://developer.apple.com/account, section **Membership
   details**, line **Team ID** (10 letters and digits) *(unverified)*. Write it on paper or in your password manager, not in
   a file in the project.
3. **YOU (Apple website)** — accept the agreements. Sign in at https://developer.apple.com/account and at
   https://appstoreconnect.apple.com. If a banner asks you to review or accept an agreement, open it and accept
   *(unverified)*. Uploads fail while one is waiting.
4. **YOU (Apple website)** — register the app's ID. Page: https://developer.apple.com/account/resources/identifiers/list
   (**Certificates, IDs & Profiles** > **Identifiers**) *(unverified)*. Click **+**, choose **App IDs**, **Continue**, choose
   **App**, **Continue**. **Description**: `Video Player`. **Bundle ID**: **Explicit**, `com.liamp.videoplayer`. Click
   **Continue**, then **Register** *(unverified)*.
5. **YOU (Apple website)** — register the Top Shelf extension's ID the same way (same page, **+**, **App IDs**, **App**).
   **Description**: `Video Player Top Shelf`. **Bundle ID**: **Explicit**, `com.liamp.videoplayer.topshelf`. **Continue**,
   **Register** *(unverified)*.
6. **YOU (Apple website)** — register the iCloud container. Same page, **+**, choose **iCloud Containers**, **Continue**.
   **Description**: `Video Player data`. **Identifier**: `iCloud.com.liamp.videoplayer`. **Continue**, **Register**
   *(unverified)*.
7. **YOU (Apple website)** — register the App Group. Same page, **+**, choose **App Groups**, **Continue**. **Description**:
   `Video Player shared`. **Identifier**: `group.com.liamp.videoplayer`. **Continue**, **Register** *(unverified)*.
8. **YOU (Apple website)** — switch on the app's capabilities. Same page, filter (top right) **App IDs**, click
   `com.liamp.videoplayer`. Tick **iCloud**, choose CloudKit, click its **Configure** (or **Edit**) button and tick
   `iCloud.com.liamp.videoplayer`. Tick **App Groups**, **Configure**, tick `group.com.liamp.videoplayer`. Click **Save**
   (and **Confirm** if asked) *(unverified)*. The app already asks for exactly these in `project.yml`; this makes Apple's
   side match (R252).
9. **YOU (Apple website)** — the same for the extension: click `com.liamp.videoplayer.topshelf`, tick **App Groups**,
   **Configure**, tick `group.com.liamp.videoplayer`, **Save** *(unverified)*.
10. **YOU (Apple website)** — create the app record. Page: https://appstoreconnect.apple.com, **Apps**, then the **+**
    button, **New App** *(unverified)*. **Platforms**: **tvOS** only. **Name**: a placeholder nobody else uses, such as
    `Video Player Test 1120` (the record's name must be unique on the whole App Store; on the Apple TV the app is still
    called "Video Player"). **Primary Language**: yours. **Bundle ID**: `com.liamp.videoplayer`. **SKU**:
    `videoplayer-001`. **User Access**: **Full Access**. Click **Create**. Apple: "Before you upload your app to the App
    Store for the first time, create an app record".
11. **YOU (Apple website)** — turn on API access (once). App Store Connect > **Users and Access** > **Integrations** >
    **App Store Connect API** (Apple help page; address https://appstoreconnect.apple.com/access/integrations/api
    *(unverified)*). If you see **Request Access**, click it, accept the terms and wait until the page shows the keys
    table. Apple: only the Account Holder can request access; on an individual account that is you.
12. **YOU (Apple website)** — create a **Team** key. Same page, tab **Team Keys**, click **Generate API Key** (or **+**)
    *(unverified)*. **Name**: `GitHub TestFlight`. **Access**: **Admin** (R245: Apple's Xcode 13 notes say cloud signing
    is for the Admin role). Click **Generate** *(unverified)*. Not an **Individual** key: Apple's page says individual keys
    "aren't able to use Provisioning endpoints", which signing needs. The name and access cannot be changed later; to
    change them you revoke the key and make a new one (a revoked key cannot be reinstated).
13. **YOU (Apple website)** — download the key, **once**. In the key's row, click **Download** *(unverified)*. You get a
    file named `AuthKey_` followed by the Key ID and `.p8`. Apple: the private key "can only be downloaded once" and Apple
    keeps no copy. Save it in your **Downloads** folder for now, never inside the project folder.
14. **YOU (Apple website)** — copy two IDs from the same page: the **Key ID** (in the key's row) and the **Issuer ID**
    (above the table, with a **Copy** button) *(unverified)*.
15. **YOU (your computer)** — open the `.p8` file with **Notepad** (right-click > **Open with** > **Notepad**). Press
    **Ctrl+A**, then **Ctrl+C**. You will paste it in the next step. (Pasting the whole text is right: its first and last
    lines, the ones made of dashes and capital words, may be included or left out; the workflow rebuilds them, R251.)
16. **YOU (GitHub website)** — add the four repository secrets. Page:
    `https://github.com/<you>/<repository>/settings/secrets/actions` (**Settings** > **Secrets and variables** >
    **Actions**). For each row: click **New repository secret**, type the **Name** exactly as here, paste the value into
    **Secret**, click **Add secret**:
    - `ASC_KEY_P8`: paste (Ctrl+V) the text you copied in step 15.
    - `ASC_KEY_ID`: the Key ID from step 14.
    - `ASC_ISSUER_ID`: the Issuer ID from step 14.
    - `APPLE_TEAM_ID`: the Team ID from step 2.

    GitHub keeps them encrypted, shows them to nobody (not even you; you can only replace them) and hides them as `***`
    in run logs. Only people with write access to the repository (you) can start the workflow that reads them.
17. **YOU (your computer)** — move the `.p8` file out of Downloads into your password manager or another safe place you
    control, or delete it (if you lose it, revoke the key and make a new one: steps 12 to 16 again). Never put it in the
    project folder: the pre-push check refuses any `.p8` file anyway.
18. **CODE** — `.github/workflows/testflight.yml`, named **TestFlight upload (tvOS, manual)** on the Actions tab. It
    starts only when you press its button. It reads only the four secrets of step 16 (the pre-push check refuses any other
    secret or the GitHub token, R248). On the free standard `xcode-27` runner it: checks the four secrets are set (names
    only); prepares the project exactly as the compile check does; writes the key to the runner's temporary folder (mode
    600); archives the app for tvOS devices with **automatic signing** using the API key (Xcode makes or fetches the
    certificate and profiles itself: none is made by hand or stored, R245); sets the build number to the UTC time
    `yyyyMMddHHmm` (R246); exports and uploads to App Store Connect (R247); and deletes the key, also after a failure. The
    log shows only result and error lines, with names from signing certificates removed, and nothing is uploaded as an
    artifact (R249).
19. **CODE** — `project.yml` already declares that the app uses no non-exempt encryption
    (`ITSAppUsesNonExemptEncryption: false`), so TestFlight should not hold the build for an export-compliance question.
20. **YOU (your computer)** — push the commits that contain this page and the workflow (only you push). GitHub lists a
    manual workflow on the Actions tab only once its file is on the repository's default branch *(unverified)*.
21. **YOU (GitHub website)** — run it. Page: `https://github.com/<you>/<repository>/actions/workflows/testflight.yml`
    (tab **Actions**, left column **TestFlight upload (tvOS, manual)**). Click **Run workflow** (right side); in the box
    keep the branch **main** (there is nothing else to choose); click the green **Run workflow** *(unverified)*. Expected
    time: about 15 to 20 minutes (an estimate: it has never run). It stops itself at 45 minutes.
22. **YOU (GitHub website)** — if the run turns red: click it, click the red step, and copy the lines that start with
    `error:` or `::error::` (with the lines above them that the step printed) into a message to me. Secrets show as `***`;
    do not send anything else. If the error is about signing (no devices registered, no profile, no certificate), do not
    run it again: send me the error first. The archive is signed automatically by Xcode and the export step signs it for
    distribution; whether the archive needs a registered Apple TV is not known until a run (R245 lists what can be done:
    register the Apple TV, archive unsigned and sign at export, or manual signing).
23. **YOU (Apple website)** — wait for Apple to process the build. App Store Connect > **Apps** > your app > tab
    **TestFlight** *(unverified)*. The build appears with its number (the UTC time of the run) as "Processing", then
    becomes ready to test (often 10 to 30 minutes; Apple e-mails you). If it asks about encryption, answer for an app that
    uses only the system's encryption *(unverified)*.
24. **YOU (Apple website)** — add yourself as a tester (once). Same **TestFlight** tab, left column **Internal Testing**,
    **+** (create a group) *(unverified)*. Group name `Me`; turn on automatic distribution; add yourself (your Apple
    Account must be a user of the team: the account holder is). Apple's Xcode page: TestFlight distributes to internal
    and external testers.
25. **YOU (Apple website)** — iCloud data: so the app can keep your history in iCloud from a TestFlight build, the
    CloudKit schema must be in the **Production** environment (docs/CODEMAGIC_SETUP.md step 22) *(unverified; without it
    the app should still play, but iCloud sync may report an error)*.
26. **YOU (Apple TV 4K)** — install. On the Apple TV open the **App Store**, search **TestFlight**, **Get**. Open
    **TestFlight**, sign in with the same Apple Account, choose **Video Player**, **Install** *(unverified)*. Also sign in
    to iCloud on the Apple TV (**Settings** > **Users and Accounts**) *(unverified)*.
27. **YOU (Apple website), only if asked** — if a run ever fails because the team has too many certificates: Certificates,
    IDs & Profiles > **Certificates**, revoke the older "Apple Distribution" ones made by the key, then run step 21 again
    *(unverified that runs leave certificates behind, R245)*.
28. **YOU** — for every later build: step 21 only (and 23 to 26 if you want it on the Apple TV). The build number is new
    each time; nothing else changes.

**Sources read for this page (20 Nov 2026):**
- Apple, "Distributing your app for beta testing and releases":
  https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases (archive, upload to
  App Store Connect for TestFlight, automatic signing with cloud-managed certificates, the app record first, internal and
  external testers).
- Apple, App Store Connect Help, "App Store Connect API":
  https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api (Users and Access > Integrations >
  App Store Connect API; the Account Holder requests access; team keys need the Account Holder or Admin role; a key is
  downloadable once; name and access cannot be edited; a revoked key cannot be reinstated).
- Apple, "Creating API Keys for App Store Connect API":
  https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api (team and
  individual keys; individual keys cannot use Provisioning endpoints; Apple keeps no copy of the private key; never store
  a key in a code repository).
- Apple, Xcode 13 release notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-13-release-notes
  (`xcodebuild` takes an API key through `authenticationKeyPath`, `authenticationKeyID` and `authenticationKeyIssuerID`
  for automatic signing on build machines; cloud signing and the Admin role).
- Apple, App Store Connect Help, "Upload builds": https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
  (tvOS uploads; each build needs its own build string).
- GitHub, "About billing for GitHub Actions":
  https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions
  ("Standard GitHub-hosted runners in public repositories" are free; otherwise USD 0.062 per macOS minute against USD 12
  included per month on GitHub Free).
