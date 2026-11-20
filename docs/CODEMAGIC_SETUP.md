# Setup steps (do once, Windows PowerShell)

> **Superseded for the TestFlight upload (R266, 20 Nov 2026):** follow docs/TESTFLIGHT.md, "Codemagic route". `codemagic.yaml`
> now has one workflow, "tvOS TestFlight (manual)", and the App Store Connect integration is named `asc-testflight` (not
> `codemagic-asc` as in step 13 below). The Apple steps here still apply.

Nothing here starts a build. Builds start only when you press "Start new build" in Codemagic.
Identifiers (developer setup only, never shown in the app): com.liamp.videoplayer

## What Codemagic does for you (do NOT do by hand)
- Creates the distribution certificate and the tvOS App Store provisioning profile (unverified until the first TestFlight run).
- Sets the build number and uploads the build to TestFlight.

## Steps
1. Create the repository and push it by following docs/GITHUB_ACTIONS_RUNBOOK.md, Parts A to C. The repository name, its exact
   address, the pre-push check and the success checks are written there, and only there. The project is already one commit
   (OPEN_QUESTIONS R146): do not run `git init`, commit or push in any other way.
2. (Now part of step 1.)
3. (Now part of step 1.)
4. Sign up for Codemagic: https://codemagic.io > **Sign up** > **Sign up with GitHub** > your personal account (free plan).
5. Click **Add application**, pick GitHub, select `video-player`, choose the codemagic.yaml option if asked.
6. Optional, free, no Apple account needed: **Start new build**, branch `main`, workflow **tvOS compile check**. About 4 to 7 minutes (cap 8). It generates the project, resolves the Swift packages and runs one `xcodebuild build` for the tvOS Simulator with code signing off; it does NOT run `swift test` (all tests run in WSL with `scripts/test-all.sh`; removed 2026-11-17, R81). Run it once, because only 18 free minutes remain this month. Only when you decide to.
7. Register the identifier: https://developer.apple.com/account > **Certificates, Identifiers & Profiles** > **Identifiers** > **+** > **App IDs** > Continue > **App** > Continue. Description `Video Player`. Bundle ID **Explicit**: `com.liamp.videoplayer`. **Continue**, then **Register**.
8. Accept any updated agreement banner at developer.apple.com/account or appstoreconnect.apple.com. Uploads fail until you do.
9. Create the app record: https://appstoreconnect.apple.com > **Apps** > **+** > **New App**.
   - Platforms: tick **tvOS** only.
   - Name: the record name must be unique across the whole App Store, so enter an unused placeholder such as `Video Player Test 1116`. It is used only in App Store Connect and TestFlight. On the Apple TV the app is still called "Video Player".
   - Primary Language: your language. Bundle ID: `com.liamp.videoplayer`. SKU: `videoplayer-001`. User Access: Full Access. **Create**.
10. Create the API key: App Store Connect > **Users and Access** > **Integrations** > **App Store Connect API** > **Team Keys** > **+** (click **Request Access** first if asked).
11. Name `Codemagic`, Access **App Manager**, **Generate**.
12. Click **Download API Key** (the `.p8`, one chance only). Note the Key ID and the Issuer ID at the top of the page. Keep the `.p8` outside the project folder.
13. Add it to Codemagic (stored encrypted): team **Settings** > **Integrations** > **App Store Connect** > **Connect**. Name it exactly `codemagic-asc`. Enter Issuer ID and Key ID, upload the `.p8`, **Save**.
14. Make the signing key. In PowerShell, in a folder outside the project, run, then copy it to the clipboard:
    ```
    ssh-keygen -t rsa -b 2048 -m PEM -f signing_key -q -N '""'
    Get-Content signing_key -Raw | Set-Clipboard
    ```
15. In Codemagic, open the app > **Environment variables**. Group `signing`, name `CERTIFICATE_PRIVATE_KEY`, paste the clipboard as the value, tick **Secure**, **Add**.
16. Delete the key files and clear the clipboard:
    ```
    Remove-Item signing_key, signing_key.pub
    Set-Clipboard -Value " "
    ```
17. Add yourself as a tester: App Store Connect > your app > **TestFlight** > **Internal Testing** > **+**. Name `Me`, enable automatic distribution, add your Apple ID.
18. Tell me when steps 1 to 17 are done. I confirm the estimate (about 9 to 13 minutes, capped at 15), then you press **Start new build** with workflow **tvOS TestFlight upload (manual)**. After Apple finishes processing (10 to 30 minutes), open TestFlight on your Apple TV with the same Apple ID.

Unverified: the tvOS signing commands have never been run. If "Set up signing" fails, send me the error text.

## Added for the storage model: iCloud (CloudKit), Keychain Sharing and the App Group (R56 to R58)
Why: tvOS keeps almost nothing on the device (docs/STORAGE_MODEL.md), so watch history, saved views and the source list are kept in your iCloud. The app target already declares the capabilities in `project.yml`; these steps make Apple's side match. Do them after step 7 (the App ID exists) and before the first signed build (step 18). **Nothing here has been done for you, and nothing in this repository registers anything.** The names of the buttons are from memory of the Apple Developer website and have NOT been checked against the live site; if a button is called something else, tell me what you see.

19. Register the iCloud container: https://developer.apple.com/account > **Certificates, Identifiers & Profiles** > **Identifiers**. In the filter at the top right choose **iCloud Containers**, then **+**. Description `Video Player data`. Identifier: `iCloud.com.liamp.videoplayer`. **Continue**, **Register**.
20. Register the App Group: same page, filter **App Groups**, **+**. Description `Video Player shared`. Identifier: `group.com.liamp.videoplayer`. **Continue**, **Register**.
21. Switch the capabilities on for the app: **Identifiers**, filter **App IDs**, click `com.liamp.videoplayer`. In **Capabilities** tick **iCloud** (and, if you are asked which kind, **Include CloudKit support**) and click **Configure** next to it, tick the container `iCloud.com.liamp.videoplayer`, **Continue**, **Save**. Tick **App Groups**, **Configure**, tick `group.com.liamp.videoplayer`, **Continue**, **Save**. Click **Save** at the top right and confirm if Apple asks. Keychain Sharing is, as far as I know, only an entitlement in the app (already in `project.yml`) with nothing to switch on here; if you see **Keychain Sharing** in the list, tick it.
22. Later, before the first build you hand to other people: the CloudKit database has a Development and a Production side. The app's record types are created automatically on the Development side the first time a development-signed build runs; a TestFlight build uses the Production side, which needs the same record type deployed first: https://icloud.developer.apple.com/dashboard > the container > **Deploy Schema Changes** (to Production). UNVERIFIED: whether a TestFlight build really uses Production, and whether the record type is created automatically, must be checked on the first device test (no device-test checklist file exists yet). What Apple's CKRecord page does say: new record types and fields can only be added automatically during development; in production CloudKit returns an error for an unknown record type or field (https://developer.apple.com/documentation/cloudkit/ckrecord), so deploying the schema is required before a Production build can save anything.
23. Sign in to iCloud on the Apple TV you test on (**Settings > Users and Accounts > iCloud**). Without it the app still works but cannot keep your history safe, and says so in Settings.
24. The Top Shelf extension target does not exist yet. When it is added, its identifier `com.liamp.videoplayer.topshelf` needs the same App Group (step 21) and its own App ID.
