# TestFlight from GitHub (short guide)

Goal: press one button on GitHub, and a build of Video Player appears in TestFlight for your Apple TV 4K.
Built and tested only as text (nothing here has run on a Mac yet): the first run is the real test. Decision record:
OPEN_QUESTIONS R463 (PROVISIONAL). The long Apple-website steps (App IDs, iCloud container, App Group, app record, API key)
and the Codemagic route are in docs/TESTFLIGHT_BACKGROUND.md; you did them already.

## What you need once: four secrets on GitHub

Page: your repository on GitHub > **Settings** > **Secrets and variables** > **Actions** > **New repository secret**.
Type the name exactly, paste the value, click **Add secret**. GitHub shows a secret to nobody afterwards, and hides it as
`***` in logs. Never paste any of these into a file, an issue, a chat or a screenshot.

| Name | What it is | Where you get it |
|---|---|---|
| `ASC_KEY_ID` | The ID of your App Store Connect API key (10 letters and digits) | App Store Connect > **Users and Access** > **Integrations** > **App Store Connect API** > **Team Keys**, column **Key ID** |
| `ASC_ISSUER_ID` | Your account's Issuer ID (looks like a long code with dashes) | Same page, above the table of keys |
| `ASC_KEY_P8` | The text of the key file `AuthKey_<Key ID>.p8` | Open the file with Notepad, **Ctrl+A**, **Ctrl+C**, paste. The key must be a **Team** key with **Admin** access |
| `DIST_CERT_PRIVATE_KEY` | The private key of your existing **Apple Distribution** certificate (text that starts with a line of dashes and the words BEGIN and PRIVATE KEY) | The one you stored for Codemagic. Where to find it is **unverified**: in Codemagic, team settings > **codemagic.yaml settings** > **Code signing identities** > **iOS certificates**, look for a way to download the key or the certificate file (`.p12`). If you cannot get it, tell me: there is a second way (OPEN_QUESTIONS R464) |

Not needed any more: `APPLE_TEAM_ID`. You may delete that secret. Why a fifth-looking name is on the list: the
Distribution certificate's key is what lets the runner sign the app; without it there is no signature. This workflow never
makes, replaces or deletes a certificate or a key.

## Start a run

1. Open your repository on GitHub and click the **Actions** tab.
2. In the list on the left click **TestFlight upload (tvOS, manual)**.
3. Click **Run workflow** (grey button on the right). Leave the branch as **main**. Leave **Keep the .ipa** and **Keep the dSYM files** unticked, unless a crash needs the symbols (see below).
4. Click the green **Run workflow** button. After a few seconds a new line appears; click it to watch.

A run takes an estimated 15 to 25 minutes (not measured) and stops by itself after 30. Nothing starts unless you press the
button. It costs nothing: the repository is public and the runner is one of GitHub's standard free ones (R250).

## Where the results appear

- **TestFlight**: App Store Connect > your app > **TestFlight**. The new build shows **Processing**, then becomes ready
  (Apple's processing time is not on a page I read; expect minutes). Its number is the date and time of the run, for example
  `202611232102`, so each one is new. Add yourself as an internal tester once (Internal Testing group), then install the
  build from the TestFlight app on the Apple TV. Nothing is submitted for review.
- **The .ipa file**: only if you tick **Keep the .ipa**. Then the run page has an **Artifacts** box at the bottom with
  `testflight-ipa`, kept for 1 day. Leave it unticked unless you need the file: it contains your Team ID, and anyone signed
  in to GitHub can download artifacts of a public repository.
- **The dSYM files** (R466): only if you tick **Keep the dSYM files**. Then the run page has `testflight-dsyms`, kept for 1
  day. They are the symbols that turn a crash report into function names: they list this app's function and file names
  (the source is public anyway) and hold no key, profile or Team ID. Anyone signed in to GitHub can download them while
  they are kept, so tick the box only for the build you need to read a crash of. Send the crash report (`.ips`) of THAT same
  build, then tell me.
- **The entitlement check** (R466, on the .ipa since R468): a step AFTER the export and BEFORE the upload unzips the exported
  .ipa into the runner's temporary folder, prints `yes` or `no` for the iCloud container, the iCloud services, the App Group
  and the push environment, in the app and the Top Shelf extension, and deletes the copy. It never prints a value. It is on
  the .ipa because this workflow signs during the export: the archive is unsigned (run #6 of 099ee39 could read nothing from
  it). It reads the signed entitlements with `codesign` (R467: a second form, then the `.xcent` file when there is one). The
  run stops before the upload when there is no .ipa, or when the app's entitlements were read and lack the iCloud container or
  the CloudKit service. If nothing could be read, the step prints `n/a`, one `WARNING` line and a few safe facts, and the run
  goes on to the upload: that is not a pass, it only means the check could not look.
- **Logs**: the run page shows only short result lines and, on a failure, the error lines (names and e-mail addresses
  removed). No log file is saved anywhere.

## If a step is red

Open the red step and copy its last lines into a message to me. The lines are already cleaned.

| Red step | What it says | What it means and what to do |
|---|---|---|
| Check that the four secrets are set | `The repository secret ... is missing` | Add that secret (table above) and run again |
| Check that the four secrets are set | `... must be the text of the .p8 file` or `... PEM text` | You pasted the wrong thing; replace the secret |
| Install the command line tools | `pip` error | A download failed; run again |
| Write the keys ... install the certificate | `is not a readable private key` | `DIST_CERT_PRIVATE_KEY` is not the whole key text; replace it |
| Write the keys ... install the certificate | `0 App Store Connect certificate(s) match the private key` | The key is not the one of your Apple Distribution certificate. Do not make a new certificate; tell me |
| Signing files | `MISSING CAPABILITY: ... on the App ID ...` | On developer.apple.com > **Identifiers**, open that App ID, tick the capability, **Configure**, **Save**; run again |
| Signing files | an App Store Connect error (401, forbidden) | The API key is not a **Team** key with **Admin** access, or the Key ID or Issuer ID is wrong |
| Prepare | `missing ...` or `binary target ... missing` | A committed file is missing from the repository; tell me |
| Archive | `SIGNING ERROR` lines | The profiles or the certificate do not fit; the line names the target |
| Archive | `BUILD NUMBER ERROR` | The build number did not reach a bundle; tell me |
| Check the signed entitlements of the exported .ipa | `ENTITLEMENT ERROR: ... lack the iCloud container` or `... the CloudKit service`, or `no .ipa` | The exported app was signed without iCloud (its entitlements were read), or the export wrote no .ipa. Copy the yes/no lines and tell me; do not upload anything from this run. A `WARNING ... could not be read` is not red: the run went on; copy the `facts` lines and tell me |
| Export | `no .ipa` | The export wrote nothing; tell me |
| Upload | `90575`, `aps-environment` | Push Notifications is missing on the app's App ID or profile; tick it on developer.apple.com and run again |
| Upload | `has already been used` or `redundant binary upload` | A build with that number exists; run again later (a new minute gives a new number) |
| Upload | `no app record` or `Cannot determine the Apple ID` | The app record is missing in App Store Connect (background doc step 10) |

Green run but no build in TestFlight after an hour: look in App Store Connect > your app > **TestFlight** for a message from
Apple (e-mail to the account holder too) and tell me what it says.

## Codemagic

`codemagic.yaml` and `scripts/cm-testflight.sh` stay in the repository. This workflow reuses most of that script, so it is
not a copy. Once a GitHub run has reached TestFlight, tell me whether to remove the Codemagic file (OPEN_QUESTIONS R463).
