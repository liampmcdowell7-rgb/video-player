# TestFlight (no Mac needed): Codemagic route, GitHub Actions fallback

Goal: press one button, and a signed build of Video Player appears in TestFlight on your Apple TV 4K.

## Which route (OPEN_QUESTIONS R266, PROVISIONAL)

**Use the Codemagic route below.** Your decision of 20 Nov 2026: Codemagic does the TestFlight upload, and only that.
Compile checks, package tests and UI tests stay on GitHub Actions.

**The GitHub Actions workflow (steps 1 to 28 further down) stays in the repository, unchanged, as the fallback.** Its two
runs of 20 Nov passed the secrets check, the key step and Prepare, then stopped at Archive with "Your team has no devices
from which to generate a provisioning profile" and "No profiles for com.liamp.videoplayer (and .topshelf) were found:
Xcode couldn't find any tvOS App Development provisioning profiles". Why: its archive uses automatic signing, which asks
Apple for a *Development* profile, and a Development profile needs a registered device. Without a Mac you cannot read the
Apple TV's real device ID (the placeholder that was registered was classified as "iPod"). The Codemagic route makes an
*App Store* profile instead, which has no device list. The GitHub workflow can work again after one of R266's
alternatives (for example the real Apple TV ID, once a Mac is borrowed).

## Codemagic route

Names from Codemagic's pages read on 20 Nov 2026 (listed under Sources at the end); anything else is marked
*(unverified)*. Your Apple steps are the same as in the GitHub route, so they point there.

- **C1. YOU (Apple website)** — do steps 3 to 14 of the GitHub route below: agreements, the two App IDs, the iCloud
  container, the App Group, the capabilities on both App IDs (steps 8 and 9 matter most: the build checks them), the app
  record, API access, a **Team** key with **Admin** access (name it, for example, `Codemagic TestFlight`), its download
  and its Key ID and Issuer ID. Skip steps 1, 2 and 15 to 22 (they are for GitHub only). Keep the `.p8` file out of the
  project folder.
- **C2. YOU (your computer)** — push the commits that contain `codemagic.yaml` (only you push). Codemagic reads the file
  from the repository.
- **C3. YOU (Codemagic website)** — add the repository. Sign in at https://codemagic.io *(unverified: sign in with
  GitHub)*. On the Applications page click **Add application**, pick your team if asked, connect GitHub, select the
  repository from the list, choose the project type *(unverified: which entry; pick the one for a native iOS app or
  codemagic.yaml)*, then **Finish: Add application**. If asked, pick the branch `main` and click **Check for
  configuration file**.
- **C4. YOU (Codemagic website)** — add the App Store Connect key as the integration **`asc-testflight`** (exactly this
  name: `codemagic.yaml` refers to it and to nothing else). In your team settings (you must be a team admin) open
  **Team integrations**, click **Connect** next to **Developer Portal**, then fill in: **App Store Connect API key name**
  `asc-testflight`, **Issuer ID** and **Key ID** (from step 14), and in **API key** upload the `.p8` file. Click
  **Save**. (To change it later: **Manage keys** next to Developer Portal.) The key stays in Codemagic, encrypted; it is
  never in the repository.
  **Certificate (nothing to add):** the build signs with your ONE existing Apple Distribution certificate, stored in
  Codemagic as **Balance Ahead distribution** (team settings > **codemagic.yaml settings** > **Code signing
  identities** > **iOS certificates**; team admin needed to see it). `codemagic.yaml` names it by that reference name, so
  keep the name exactly as it is. The build never makes, revokes or deletes a certificate or a key, and it does not touch
  your other apps.
- **C5. YOU (Codemagic website)** — start the build: open the app and click **Start new build**. In **Specify build
  configuration** choose the branch `main` and the workflow **tvOS TestFlight (manual)**, then start it *(unverified:
  the name of the final button)*. Nothing starts by itself: the file has no trigger. It stops itself at 30 minutes. An
  estimate: 15 to 25 minutes (never measured). **Minutes cost money now:** on 20 November 2026 the Codemagic Billing
  page showed 506 of 500 free macOS minutes used, current balance $6.75, next invoice 1 December 2026, so builds bill as
  overage until the reset (OPEN_QUESTIONS R105). You decide when to start a build.
- **C6. CODE** — what the workflow does (`codemagic.yaml`, `scripts/cm-testflight.sh`), on a Mac mini M2 with Xcode 27.2
  (the tvOS 27.2 SDK, the same Xcode as the GitHub runner):
  1. Prepare exactly as the GitHub compile check does (`scripts/ci-prepare.sh`): check the committed vendored packages,
     install the pinned XcodeGen 2.46.0 (SHA-256 checked), generate the project, resolve the packages.
  2. Signing: Codemagic installs the stored certificate **Balance Ahead distribution** (`ios_signing` in
     `codemagic.yaml`). The step finds that same certificate in App Store Connect (by comparing fingerprints, through the
     integration), then for `com.liamp.videoplayer` and `com.liamp.videoplayer.topshelf` reuses an existing active
     **tvOS App Store** profile that carries it; only if there is none does it make a new profile with it
     (`app-store-connect profiles create --type TVOS_APP_STORE`). No devices. It never makes a key or a certificate and
     never revokes or deletes anything (the pre-push check and its self-test refuse such commands).
  3. Checks the two profiles: the app's must carry the iCloud container `iCloud.com.liamp.videoplayer` and the App Group
     `group.com.liamp.videoplayer`; the Top Shelf's the App Group. A missing one stops the build (see C7).
  4. Points each target at its own profile (`xcode-project use-profiles`), checks both now sign manually, sets the build
     number to the UTC time `yyyyMMddHHmm` and archives for tvOS devices (Release).
  5. Exports the `.ipa` (method `app-store`), and Codemagic uploads it to App Store Connect with the integration.
     `submit_to_testflight` is `false`: internal testers need no beta review. No e-mail, Slack or other publishing.

  The log shows only result lines and, on failure, the error lines, with serial numbers, certificate content and the
  certificate holder's name removed. `project.yml` keeps `ITSAppUsesNonExemptEncryption: false` (step 19, R261).
- **C7. YOU (Codemagic website)** — if the build turns red: open the red step and copy its last lines (they are already
  redacted) into a message to me. Two cases you can fix yourself:
  - **"MISSING CAPABILITY: ... on the App ID ..."**: the line names the capability and the App ID. On
    developer.apple.com > **Certificates, IDs & Profiles** > **Identifiers**, click that App ID, tick the capability,
    click **Configure** and tick the named container or group, **Save** (steps 8 and 9 below) *(unverified)*. Then start a
    new build (C5). The build reuses only *active* profiles; whether Apple marks the old profile inactive after the
    change is *(unverified)*: if the same line comes back, tell me rather than deleting anything.
  - **"no code signing identity in this machine's keychain"** or **"0 App Store Connect certificate(s) match"**: the
    stored certificate was not installed or not found. Check that **Balance Ahead distribution** is still listed under
    **iOS certificates** (C4) with exactly that name, then send me the lines. Do not make a new certificate for this.
- **C8. YOU (Apple website and Apple TV)** — steps 23 to 26 below: wait for Processing, add yourself as an **internal
  tester** (Internal Testing group, automatic distribution), install TestFlight on the Apple TV and the build.
- **C9. YOU** — for every later build: C5 only (and C8 if you want it on the Apple TV).

## GitHub Actions route (the fallback; it stops at Archive today, see above)

How to read this list: do the steps **in order**, top to bottom. **YOU** = you do it, on the website or device named in the
step. **CODE** = already done in this repository; nothing for you to do, it only tells you what the code does. In the page
addresses, `<you>/<repository>` is your GitHub account and repository name as in the address bar of your repository page.

Button and menu names marked *(unverified)* were not checked on the live site for this page (nobody here could open
Apple's or GitHub's sites); the others are quoted from the Apple and GitHub pages listed at the end, read on 20 Nov 2026.
If a name differs on screen, look for the nearest match and tell me. Open choices: OPEN_QUESTIONS.md R244 to R252 and
R266 (all PROVISIONAL). docs/CODEMAGIC_SETUP.md is the older Codemagic setup (its integration name and workflows are
replaced by the Codemagic route above); steps 3 to 11 here are the same Apple steps, so skip any you already did there.

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
19. **YOU (a declaration to Apple), not decided** — `project.yml` sets `ITSAppUsesNonExemptEncryption: false`, which
    tells Apple the app uses no encryption or only exempt encryption, so App Store Connect asks no questions and does not
    mark the build "Missing Compliance". The app carries its own SSH (Citadel, swift-nio-ssh, swift-crypto) for SFTP, which
    Apple's pages put outside the operating system's own encryption; whether `false` is correct is **your** declaration
    to Apple, not something code can settle. What each answer means: OPEN_QUESTIONS R261 (PROVISIONAL, with the
    alternatives). Until you decide, the value stays as it is.
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
- Codemagic, codemagic.yaml reference: https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/ ("If no
  events are defined, you can start builds only manually"; **Start new build** and **Specify build configuration**;
  `max_build_duration` in minutes, "min 1, max 120"; `xcode`: "latest, edge or version (e.g. 11.2)"; `mac_mini_m4` needs
  billing).
- Codemagic, Xcode 27.2 build machine: https://docs.codemagic.io/specs-macos/xcode-27-2.md (Xcode 27.2, 27B52, tvOS 27.2
  SDK, Mac mini M2 and M4); edge is Xcode 27.3 (27C5020n): https://docs.codemagic.io/specs-macos/xcode-27-3.md.
- Codemagic, App Store Connect publishing: https://docs.codemagic.io/yaml-publishing/app-store-connect/ (`integrations:
  app_store_connect: <key name>`, `auth: integration`, `submit_to_testflight`; **Team integrations**, **Developer
  Portal**, **Connect**, **App Store Connect API key name**, **Issuer ID**, **Key ID**, **API key**, **Save**, **Manage
  keys**).
- Codemagic, native iOS quick start: https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app (**Add
  application**, **Finish: Add application**, **Check for configuration file**, `xcode-project use-profiles`).
- Codemagic, signing iOS apps and alternative code signing methods: https://docs.codemagic.io/yaml-code-signing/signing-ios/
  and https://docs.codemagic.io/yaml-code-signing/alternative-code-signing-methods.md (`ios_signing` lists "the
  references of the uploaded files under the `provisioning_profiles` and `certificates` fields"; keychain steps "are not
  required"; **Code signing identities**, **iOS certificates**, **Reference name**, team admin needed; with the
  integration "the certificate private key has to be exported too" for `fetch-signing-files`, which this route therefore
  does not use; the integration "will expose necessary environment variables during the build").
- Codemagic CLI tools: https://github.com/codemagic-ci-cd/cli-tools/tree/master/docs (`certificates list` with `--json`;
  `bundle-ids list --bundle-id-identifier --strict-match-identifier`; `bundle-ids profiles --bundle-ids --type
  TVOS_APP_STORE --state ACTIVE`; `profiles get --save`; `profiles create BUNDLE_ID_RESOURCE_ID --certificate-ids --type
  TVOS_APP_STORE --save` with no key option; common `--profiles-dir`; `xcode-project use-profiles --profile` takes a glob
  and writes `$HOME/export_options.plist`).
- Apple, "Certificates" support page: https://developer.apple.com/support/certificates/ (builds uploaded but not yet
  submitted for App Review "may be marked as Invalid Binary" when signed with a revoked certificate).
