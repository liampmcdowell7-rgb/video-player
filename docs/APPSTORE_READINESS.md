# App Store and TestFlight readiness

Status: **PROVISIONAL**. Research and writing only. Nothing is registered, uploaded, submitted, or sent to Apple. Pages read 2026-11-17; anything not read is **UNVERIFIED**. Answers below are drafts for the user to confirm, not legal advice.

## 1. Privacy manifest (`PrivacyInfo.xcprivacy`)

What Apple says ([Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)):
- The manifest is a property list named exactly `PrivacyInfo.xcprivacy`, added to the target's resources. It records the data collected and the **required reason APIs** used. Both are needed for tvOS.
- Each executable or dynamic library that uses a required reason API needs a manifest in its own bundle; an SDK "can't rely on the privacy manifest files for apps that link the third-party SDK".
- Apps that use required reason APIs without declaring a reason "aren't accepted by App Store Connect" (since May 1, 2024, per the page).
- The reason codes per API category are on the dictionary-key pages (`NSPrivacyAccessedAPITypes`), which were **not read**. **The reason codes are therefore UNVERIFIED and are not written here.** The parent (or the user on the Mac-less build) must read https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes before the file is written.
- The page "SDKs that require a privacy manifest and signature" ([Upcoming third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/)) lists, among others, **BoringSSL / openssl_grpc**, **OpenSSL**, **Alamofire**, **SDWebImage**, **SwiftyJSON**, **Starscream**, **sqflite**, **FMDB**. It does not mention XCFrameworks or Swift packages as such, and gives no enforcement date; signatures are required "where the listed SDKs are used as binary dependencies".

### Manifests the project needs (draft contents)

| Target / binary | Needs its own manifest? | Draft content | Status |
|---|---|---|---|
| App target `VideoPlayer` | **Yes** | `NSPrivacyTracking` = false; `NSPrivacyTrackingDomains` = empty; `NSPrivacyCollectedDataTypes` = per section 3 (empty if the user accepts the recommendation); `NSPrivacyAccessedAPITypes`: **declare every category the code calls**. Our code reads file modification dates for incremental sync (file timestamp category), reads available disk space for cache budgeting (disk space category) if we implement it, uses `UserDefaults` for the essentials copy (user defaults category), and may read `ProcessInfo.systemUptime` for timing (system boot time category). Reason codes: UNVERIFIED | Not written |
| Top Shelf extension `com.liamp.videoplayer.topshelf` | **Yes** if it calls any such API (it reads the App Group snapshot with file APIs and `UserDefaults(suiteName:)`) | Same structure, its own categories | Not written |
| Swift package `VideoPlayerCore` and its targets | Swift package resources are not an SDK we distribute; the **app's** manifest covers code we compile into it | Included in the app manifest | Decision recorded |
| AMSMB2 4.0.3 (patched, `Vendor/AMSMB2`), it wraps libsmb2 | libsmb2 (C) calls `stat`-family functions: **UNVERIFIED**, check by symbol scan | If it links as a dynamic library or framework, it needs its own manifest; if static, the app manifest must declare what it calls | UNVERIFIED |
| Libnfs.xcframework (`Frameworks/Libnfs.xcframework`) | Same question for libnfs | Same | UNVERIFIED |
| Citadel, swift-nio-ssh, swift-nio, **swift-crypto** | swift-crypto vendors BoringSSL (the target is named `CCryptoBoringSSL`). The signature list names "BoringSSL / openssl_grpc"; whether this vendored copy counts as a repackaging of it is **UNVERIFIED** | Treat as listed: ask Apple's validator (upload to App Store Connect produces the email described on the page) | UNVERIFIED |
| FFmpeg (LGPL prebuilt, docs/spikes/FFMPEG_TVOS_CANDIDATES.md) / MPVKit (fallback engine) | FFmpeg uses file APIs (`stat`, `fstat`) and `getenv`; **UNVERIFIED** which required reason categories | Needs its own manifest if it is an XCFramework with dynamic libraries | UNVERIFIED |
| SQLite | System library in the SDK, nothing to declare for the binary; our calls to `stat` are app-side | | Done |

**How to find out without a Mac (suggestion, not run):** list the undefined symbols of each static library or binary (`nm -u` on the Linux copy of each library, or on the xcframework slice) and compare with the API list on the dictionary-key pages. This audit did not run it (no WSL work was allowed).

**Signatures:** the page says signatures are required for listed SDKs used as binary dependencies. Our binary dependencies are Libnfs.xcframework and the FFmpeg frameworks (MediaCodecs) and the libdovi framework (DolbyVisionRPULib); they are built by us (or downloaded), so they would be signed by our own signing identity at archive time (Codemagic does this with the managed certificate: docs/CODEMAGIC_SETUP.md). If a downloaded framework carries its own signature, keep it. UNVERIFIED whether Apple demands the vendor's signature for a library not on its list.

## 2. Encryption export compliance

Apple ([Complying with Encryption Export Regulations](https://developer.apple.com/documentation/Security/complying-with-encryption-export-regulations)):
- Uploading to TestFlight or the App Store counts as an export if the app "uses, accesses, contains, implements, or incorporates encryption".
- `ITSAppUsesNonExemptEncryption`: NO "if your app, including any third-party libraries it links against, doesn't use encryption, or if it only uses forms of encryption that are exempt". "Typically, the use of encryption that's built into the operating system, for example when your app makes HTTPS connections using URLSession, is exempt from export documentation upload requirements, whereas the use of proprietary encryption is not."
- If non-exempt, upload documents; Apple returns a code for `ITSEncryptionExportComplianceCode`. Exempt apps may still owe a yearly self-classification report to the US government (page: "How to file an Annual Self Classification Report").
- The classification rules page ("Export compliance documentation for encryption") and the App Store Connect question flow were **not read**. SSH, SMB encryption and TLS-through-libraries classification is therefore **UNVERIFIED**.

Where our code uses encryption:
| Use | Implementation | Comment |
|---|---|---|
| HTTPS/TLS to WebDAV, Jellyfin, Emby, Plex-like APIs, TMDB, OMDb | `URLSession` (OS) | OS-provided; the page calls this exempt |
| SFTP | Citadel + swift-nio-ssh + swift-crypto | Encryption implemented in third-party libraries bundled in the app (SSH). On Apple platforms swift-crypto may forward to CryptoKit (UNVERIFIED which is used in our build) |
| SMB 3 encryption | libsmb2 via AMSMB2 | Its own cryptographic code (AES-CCM/GCM, signing): UNVERIFIED how it is classified |
| Digest authentication hashes | our own MD5/SHA code or CryptoKit | Authentication hashing, UNVERIFIED classification |
| HLS loopback | plain HTTP on 127.0.0.1 | no encryption |

**Finding: `project.yml` sets `ITSAppUsesNonExemptEncryption: false`.** With SSH and SMB encryption implemented in bundled libraries, that answer is **possibly wrong**. Decision **D7** for the user: (a) recommendation, set it to true and answer App Store Connect's guided questions once (the questions decide whether documents are needed); (b) keep false only after reading Apple's classification page and being sure every use is exempt. Do not ship `false` unread: a wrong declaration is a compliance problem, not a build problem. `project.yml` is not edited by this audit. **UPDATE 2026-11-17: D7 is NOT decided and `project.yml` is unchanged; read section 7 (worksheet) and decide yourself.**

## 3. Privacy nutrition label (App Privacy)

Apple's definition ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)): "collect" means transmitting data off the device so that you or third-party partners can access it for longer than needed to service the request in real time. Data "processed only on device is not 'collected'". Data sent on a server call and not retained "if an authentication token or IP address is sent ... and not retained" need not be disclosed. The page does not say how to treat data sent only to the user's own server; the deciding factor is retention and access.

Draft answers (**for the user to confirm; this is the recommendation**):

| Data | Leaves the device? | Who can access it | Collected under Apple's definition? |
|---|---|---|---|
| Watch history, saved views, source list | To the user's own iCloud private CloudKit database | Only the user's Apple Account; the developer has no access to a private database (**UNVERIFIED** statement, not read on a CloudKit page) | Recommend **No** (not accessible to us) |
| Server addresses, usernames, passwords | Only to the servers the user entered; passwords in the local Keychain (not synced on tvOS: docs/STORAGE_MODEL.md) | The user's own servers | Recommend **No** |
| File names and titles (library) | Search text sent to **TMDB** and **OMDb** to find posters and metadata | TMDB and OMDb | **Open question.** The requests send a title string, year, and (OMDb) an API key, plus the IP address of the viewer's network. We do not store these off-device; the third party's retention is **UNVERIFIED** (their terms were not read). Under the page's definition the data is "transmitted to third-party partners"; if either keeps logs it is arguably "Search History" or "Other Usage Data", not linked to identity, not used for tracking |
| Diagnostics | None collected. There is no analytics SDK, no crash reporter | — | **No** |
| Anything for advertising or tracking | None | — | **No** |

**D10 (needs the user's decision):** recommend **declaring "Data Not Collected"** only if the user accepts that TMDB/OMDb requests are metadata look-ups with no retention by us and have first read TMDB's and OMDb's privacy statements; otherwise declare "Search History" (not linked to the user, not used for tracking, purpose: App Functionality). Also add a privacy policy page (Privacy Policy URL is a field in App Store Connect, [required properties page](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties)) saying the app contacts TMDB and OMDb and nobody else. TMDB and OMDb **attribution rules** (a notice that the app uses their data, TMDB logo rules) were not read: UNVERIFIED, check before submission, because a missing attribution can be a licence breach.

## 4. Age rating

Apple's questionnaire ([Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)): descriptors answered None / Infrequent / Frequent in groups: In-App Controls (Parental Controls, Age Assurance); Capabilities (Unrestricted Web Access, User-Generated Content, Social Media, Messaging and Chat, Advertising); Mature Themes; Medical or Wellness; Sexuality or Nudity; Violence; Chance-Based Activities (Gambling, Simulated Gambling, Contests, Loot Boxes). Apple derives the rating (4+, 9+, 13+, 16+, 18+, or Unrated). The page read covered the first 100,000 of 116,913 characters; the Korea values and the remainder were not read.

Draft answers:
| Descriptor | Answer | Reason |
|---|---|---|
| Parental Controls | None | cut feature |
| Age Assurance | None | |
| Unrestricted Web Access | None | no web view, no browser; the app plays media from servers the user adds |
| User-Generated Content | None | the app publishes nothing |
| Social Media, Messaging and Chat, Advertising | None | |
| All content descriptors (violence, sexuality, mature themes, gambling) | None | the app contains no content; the user's own files are not the app's content |

Expected rating: **4+**. **D9 (the user decides):** the user's files may contain any content; the questionnaire asks about the app's own content, but a reviewer may judge differently. The alternative is a higher rating (UNVERIFIED how Apple reviews apps that play arbitrary user media). Nothing is submitted.

## 5. Metadata and other items needed

From the required-properties page (fields listed; which are mandatory was **not** readable in the extraction, UNVERIFIED): App Name, Subtitle, Age Rating, Bundle ID (`com.liamp.videoplayer`), SKU, Content Rights, Primary Language, Primary and Secondary Category, Support URL, Marketing URL, Version Number, Copyright, App Review Information, Version Release Settings, What's New (updates only), Privacy Policy URL, Data Types (privacy), Accessibility URL and Accessibility Support (Accessibility Nutrition Labels).

Still to prepare (nothing exists yet):
1. **App name and subtitle.** The app's own identity stays neutral (docs/NAMES.md rule 1): choose the name in App Store Connect only; the on-device name stays "Video Player" (`CFBundleDisplayName`). Name availability is checked by App Store Connect, not by us.
2. **Icon:** tvOS uses layered images (a brand asset with front, middle, back layers); the parent's NATIVE standard work records the gap (not researched here).
3. **Screenshots:** Apple TV sizes are in the "Screenshot specifications" help page, **not read**. General knowledge says 1920x1080 or 3840x2160 landscape (UNVERIFIED). Screenshots must come from a real Apple TV or simulator; none exist.
4. **Description, keywords, promotional text**: write after the feature set is fixed. No claims for features that are not built (HDR10+, Atmos on every route, Match Content on every TV).
5. **Support URL and privacy policy URL**: need a public web page. The project has no hosting; this is an open item for the user (no outside accounts were created here).
6. **Review notes:** the reviewer needs a working media server to see anything. Provide a reachable test WebDAV server and credentials in App Review Information, or a short explanation. Without one the app shows only the empty state (**real rejection risk**).
7. **Apple Developer Program membership, App ID, App Group `group.com.liamp.videoplayer`, iCloud container `iCloud.com.liamp.videoplayer`, keychain group, TestFlight**: all pending; `docs/CODEMAGIC_SETUP.md` steps 19 to 22 describe them. Nothing was registered by this audit.
8. **Accessibility Nutrition Labels** and **App Privacy** are answered in App Store Connect (web). They require the declarations above.
9. **TestFlight:** export compliance is asked before a build can go to external testers ([determine-and-upload page](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation): documentation "should be completed before submitting a build for review on either App Review or TestFlight App Review"; review about two business days if complete).
10. **Open-source licences:** the app bundles Citadel, swift-nio, swift-crypto, AMSMB2/libsmb2 (LGPL), libnfs (LGPL), FFmpeg (LGPL) and later MPVKit. LGPL needs a relinking path for iOS-style static linking: **UNVERIFIED**, a legal question for the user; docs/spikes/FFMPEG_TVOS_CANDIDATES.md covers FFmpeg only.

## 6. Order of work when the user decides to submit (not started)
1. Decide D7, D9, D10.
2. Write the two `PrivacyInfo.xcprivacy` files after reading the reason-code pages.
3. Fix `ITSAppUsesNonExemptEncryption`.
4. Build, sign, TestFlight (a Codemagic build; the user's remaining free minutes limit this).
5. Fill App Store Connect.

## 7. D7 worksheet: encryption export compliance (NOT DECIDED; the user decides)

**I am not a lawyer and this is not legal advice.** I read Apple's pages and listed what they say. Apple's own text states "you're responsible for all liabilities associated with misinterpretation of export regulations or claiming exemption inaccurately". `ITSAppUsesNonExemptEncryption` is **unchanged** in `project.yml` (still `false`, which is the part I am least sure about). The decision is yours.

### What I read (2026-11-17, public pages only)
1. https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations : uploading to TestFlight or the App Store is an export when the app "uses, accesses, contains, implements, or incorporates encryption"; `ITSAppUsesNonExemptEncryption` is `NO` only "if your app, including any third-party libraries it links against, doesn't use encryption, or if it only uses forms of encryption that are exempt"; operating-system encryption such as HTTPS through `URLSession` is "typically" exempt from documentation upload, "whereas the use of proprietary encryption is not"; an app that uses exempt encryption "might alternatively be required to submit a year-end self-classification report to the U.S. government" (https://www.bis.doc.gov/index.php/policy-guidance/encryption/4-reports-and-reviews/a-annual-self-classification); after Apple reviews documents it gives a code for `ITSEncryptionExportComplianceCode`.
2. https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation : App Store Connect asks "a set of questions"; documentation should be complete before submitting a build to App Review or TestFlight App Review; review takes about two business days if complete; the role needed is Account Holder, Admin or App Manager. The page does not list the questions.
3. https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption : the table. Only operating-system encryption: no documentation. "An industry standard algorithm, not provided within the Apple operating system": upload the French encryption declaration (only required if distributing on the App Store in France). Proprietary algorithms not accepted by IEEE, IETF or ITU: a CCATS and the French declaration.
4. https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance : the questionnaire has two outcomes (documentation required or not); the three kinds of use that need a determination are standard algorithms, crypto in Apple's OS and proprietary or non-standard algorithms; it does **not** say whether third-party or open-source libraries count (it says to ask Apple or read the Apple developer documentation); the responsibility sentence quoted above.

**Not read, so not claimed:** the exact wording and order of the App Store Connect questions (they appear only inside App Store Connect), the BIS (US government) rules themselves, any mass-market or open-source treatment, and any other country's rules.

### Which of our components matter
| Component | What it does | Provided by | Which row of Apple's table it most likely falls in (my reading, not a ruling) |
|---|---|---|---|
| System TLS (HTTPS to servers, TMDB, OMDb, CloudKit) through `URLSession` / Network.framework | Encrypts connections | Apple OS | Row 1: OS encryption only. Apple's page gives HTTPS through `URLSession` as the example |
| CloudKit encrypted fields (`CKRecord.encryptedValues`) | Encrypts password copies before upload | Apple OS (CloudKit) | Row 1: the algorithm is Apple's. Our code only sets values |
| Keychain | Stores the passwords | Apple OS | Row 1 |
| CryptoKit `SHA256` (certificate fingerprints, hashing) | A hash, no confidentiality | Apple OS | Row 1; hashing alone is not encryption in the ordinary sense, but that classification is the regulation's, not mine |
| SFTP: Citadel + swift-nio-ssh (+ swift-crypto) | SSH transport encryption and key exchange implemented **inside code we bundle** | Third-party libraries compiled into the app. On Apple platforms swift-crypto may forward to CryptoKit (not checked in our build) | Row 2 candidate: "an industry standard algorithm, not provided within the Apple operating system" (SSH is an IETF standard), if the SSH layer's own cipher code, not CryptoKit, performs the encryption |
| SMB 3 encryption and signing: libsmb2 through AMSMB2 | AES-CCM/GCM, signing, NTLM/Kerberos-style hashing in C code we bundle | Third party | Row 2 candidate, same reason (IETF/Microsoft-published standard algorithms in bundled code) |
| NFS: libnfs | Plain NFS has no encryption in our use (no Kerberos privacy configured) | Third party | Probably no encryption of its own; unverified (Kerberos support exists in the library; we do not enable it) |
| FFmpeg (remux engine, if linked): its TLS/crypto parts | The candidate builds say network and TLS are compiled out (FFmpegBuild) or included (MPVKit uses gnutls/OpenSSL) | Third party | FFmpegBuild: `--disable-network`, probably nothing. MPVKit fallback: bundles TLS libraries, which would be row 2 |
| FTPS | TLS through the system | Apple OS | Row 1 |
| Loopback HLS server | Plain HTTP on 127.0.0.1 | us | No encryption |
| OneDrive device-code sign-in | HTTPS through the system | Apple OS | Row 1 |

### What each answer would mean (the choice is yours)
| Answer you could give | What it declares | What follows (from the pages above) | Risk |
|---|---|---|---|
| **A. `ITSAppUsesNonExemptEncryption = false`** (today) | App only uses OS encryption or exempt forms | No questions on every submission, no documents | If SSH and SMB code we bundle counts as non-exempt, this is a wrong declaration; Apple puts the liability on you |
| **B. `= true`, answer the questionnaire in App Store Connect** | App uses non-exempt encryption | App Store Connect asks its questions on each build; the likely outcome from the table is "industry standard algorithm not in the OS": a French encryption declaration, only if you distribute in France; possibly annual self-classification reporting to the US government (a separate legal step I did not research) | Slower TestFlight start (about two business days for review if documents are needed); more paperwork; safest against a wrong claim |
| **C. Drop the bundled-crypto sources for the first release** (SFTP and SMB, or build them behind a later release) | The remaining encryption is all in the OS | Answer A becomes defensible; but two source types are missing at release, and R9 says every technically possible source type must pass before a public release | Product trade-off, not a legal answer |
| **D. Ask Apple or a lawyer first** | n/a | Apple's contact link is on the determine-and-upload page (topic SC1110) | Time |

My only recommendation is process: do not leave `false` unread (it was written in an early scaffold before SSH and SMB existed in the app). Pick A, B, C or D and tell me; I will then change `project.yml` and the Codemagic notes.
