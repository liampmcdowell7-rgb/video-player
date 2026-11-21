# Sources

All source types are built, none are deferred. Where something is impossible on the platform, this file documents the limit and the closest alternative. Nothing here is claimed to work on an Apple TV until it has been run on one.

Evidence labels: **Read** = read in the project's own documentation or manifest in this session. **Tested** = a test ran and passed (Linux/WSL unless stated). **Measured** = a number I measured. **Unverified** = from memory or inference.

## The contract

`VideoPlayerCore` defines `MediaSource` (`Packages/VideoPlayerCore/Sources/VideoPlayerCore/Source/`): `authenticate()`, `list`, `info`, `read(range:)`, `playbackAccess(for:)`, `capabilities`, change detection (`FileVersion`: server token, then ETag, then date and size), `SourceDiscovery`, one `SourceError`. `SourceKind.verification`, `.limit`, `.gatesPublicRelease` and `.notVerifiedLabel` (SourceStatus.swift) are the single place the Settings screen and the release gate read from.

Layout rule: one Swift package target per source (`SourceWebDAV`, later `SourceSMB`, ...), each depending on `VideoPlayerCore` only, never on another source, each with its own test target. Native-library bindings sit in their own target and must be prebuilt binaries unless you approve a C compile.

Rules for every source: files play in place (range reads or a URL), nothing is downloaded except small sidecar files; credentials are handed in when the source is created (Keychain), never stored by a source; **Library-only**: no ads, promoted rows or outside content inside a source. Media servers add: **Your Library Only**, **direct play only**, **our metadata authoritative**.

## Release gate (B10, decided)
No public release until every source type that is technically possible has passed its integration tests. Platform-limited and account-blocked sources are documented with their alternative and excluded from the gate (`SourceKind.gatesPublicRelease`). Internal TestFlight builds may include partial progress.

## Status

| Source | Target | State | Verified how |
|---|---|---|---|
| WebDAV | `SourceWebDAV` | Built behind the contract | 32 unit + 10 live tests against rclone (Linux). Not on tvOS yet |
| SMB2/3 | `SourceSMB` | Written over AMSMB2 4.0.3 (patched, PROVISIONAL) | 20 unit (fake) + 11 live against impacket (SMB 2.0.2 only). **Not yet verified against a real server** (no Samba/Windows) |
| NFS | `SourceNFS` | Written over NFSKit's `Libnfs.xcframework` (libnfs 5.0.2, NFSv3, PROVISIONAL) | 34 unit + 13 live against `rclone serve nfs` with libnfs built from source. **Not yet verified against a real server** (no NAS), no Apple build |
| SFTP | `SourceSFTP` | Client written behind `SFTPBackend`; **no SSH library chosen (your decision, D-SFTP)** | 18 unit tests, in-memory backend only |
| FTP/FTPS | `SourceFTP` | Written (own client; Network.framework + URLSession on Apple, POSIX sockets on Linux) | 46 unit + 14 live against rclone FTP. **FTPS untested** (no TLS server); Apple transport not compiled |
| UPnP/DLNA | `SourceUPnP` | Written; SSDP discovery device-only | 31 unit + 10 live against `rclone serve dlna` (one server implementation). SSDP sockets untested |
| OneDrive | `SourceOneDrive` | Client written (Graph + device code); **blocked: needs an app registration**; nothing registered | 36 tests on hand-written fixtures, Microsoft never contacted |
| Links | `SourceLinks` | Written (direct, Dropbox, Google Drive, OneDrive, iCloud Drive classification) | 35 unit + 9 live against rclone HTTP (direct links only); provider conversions are recorded-format only |
| Google Drive | (Links) | Platform-limited | n/a |
| Dropbox | (Links, WebDAV bridge) | Platform-limited | n/a |
| Jellyfin | `SourceJellyfin` | Written; real server 12.4.0 in WSL | 26 unit (recorded responses) + 11 live |
| Emby | `SourceEmby` | Written; real server 4.10.2.0 in WSL | 26 unit (recorded responses) + 11 live |
| Plex | `SourcePlex` | plex.tv code sign-in, server list, browse and index (R300 to R304); hand-written fixtures only, no test server | none |

---

## WebDAV
- **Auth**: none, Basic, Digest (RFC vectors Tested). Basic over `http://` refused unless allowed per server.
- **Discovery**: Bonjour `_webdav._tcp`, `_webdavs._tcp` (app side).
- **Ranges/seeking**: HTTP `Range`; Tested at start, middle, end, past the end (416), short tail. Servers ignoring `Range` give `rangesNotSupported`.
- **100 Mbps (12.5 MB/s)**: Measured on loopback, 40 MB in 0.44 s; shows client headroom only. Real network is device-only.
- **Reconnect**: stateless; stale Digest nonce refreshed once (Tested).
- **Credentials**: Keychain. **Library**: ours (`URLSession`).
- **WSL server**: `rclone serve webdav` (open and Basic). No real Digest server; RFC vectors and mock flows instead.
- **Device-only**: Digest against a real NAS, certificate pinning (D8), 100 Mbps `AVPlayer` playback, Digest via byte reader.
- **Risks**: Digest URLs cannot be given to `AVPlayer` (nonce count), so Digest uses the byte-reader path built in step 4.

## SMB2/3 (B1)
- **Prebuilt binary search result: none exists.** AMSMB2 4.0.3 releases carry no assets and the repo has no xcframework (Read, GitHub API). Searching GitHub for `libsmb2 xcframework` returned zero repositories. libsmb2's own README could not be fetched (404), so my earlier claim that it recommends a precompiled framework is **withdrawn**. Pure-Swift alternatives checked: `SMBClient` (MIT, 291 stars) documents SMB 2.0 only, no range reads, no tvOS (Read), so it is not enough; `SwiftSMB` has no licence and 0 stars, so it cannot be used.
- **What AMSMB2 actually compiles (Read, Measured)**: its `Package.swift` declares library `AMSMB2` as `type: .dynamic` (so the LGPL dynamic-link requirement is met by SwiftPM) and a C target `libsmb2` from a git submodule, **55 C files**, depending on swift-atomics and swift-system. tvOS 14+.
- **Measured compile cost** (Linux x86-64, 6 cores, Swift 6.4.2): `libsmb2` C target alone 6.6 s wall / 8.9 s CPU (debug), 8.1 s wall / 16.2 s CPU (release). Package resolve 19 s. On a Codemagic M2 the C part should be well under a minute per architecture. **Estimate: adds about 1 minute (range 0.5 to 2) to a compile check.** That is an estimate from a Linux measurement, not an M2 measurement.
- **A new risk found**: AMSMB2's Swift code **does not compile on Linux with Swift 6.4.2** (Sendable capture errors in `Stream.swift`, lines 176 to 187, Swift 6 language mode). Whether Codemagic's Xcode accepts it is unknown, and the first compile check is how I find out. Fallbacks if it fails: pin AMSMB2 4.0.2 or earlier, or patch a vendored copy.
- **Auth**: username/password (NTLM), guest; Kerberos not by default. **Discovery**: `_smb._tcp` Bonjour (listed in Info.plist), typed address. **Ranges**: native offset reads; 100 Mbps Unverified (device-only). **Reconnect**: re-open session and handles after sleep.
- **Decision (R15, PROVISIONAL until the first compile check)**: AMSMB2 **4.0.3**, exact version. **None of 4.0.3, 4.0.2, 4.0.1, 4.0.0, 3.4.0 compiles unpatched on Swift 6.4.2.** The only errors are in `AMSMB2/Stream.swift`, function `prefetchData()`, which captures `self` inside a `Task { @Sendable }`. The local patch (16 lines added, 7 removed, that one function; passes `self` in a small `@unchecked Sendable` box; the class was already `@unchecked Sendable`, so behaviour is unchanged) is saved at `scripts/patches/AMSMB2-4.0.3-swift6.4.patch`; `git apply --check` succeeds on a fresh 4.0.3 clone with its libsmb2 submodule. Whether Codemagic's Xcode needs it is unknown.
- **How it is wired**: `Package.swift` adds the real backend only when a patched copy exists at `Packages/VideoPlayerCore/Vendor/AMSMB2`; otherwise `SourceSMB` still builds (its backend is `#if canImport(AMSMB2)`) and its 20 unit tests run against a fake. `scripts/test-smb.sh` clones and patches into `~/vp-smb-scratch`. Do not add AMSMB2 to `project.yml` until a compile check is approved. LGPL-2.1 libsmb2 sits inside a dynamic AMSMB2 library: attribution and relink notes needed before release.
- **WSL test server (Tested)**: impacket 0.13.1 `smbserver` in a venv (no sudo; `scripts/vp_smbserver.py`, `scripts/test-smb.sh`). AMSMB2 connects and reads. It speaks only SMB 2.0.2 (inferred), no signing, no encryption, guest refused. A failed login needed a small server fix (impacket sent the wrong reply body and libsmb2 waited ~40 s). impacket's missing-file stat returns "access denied"; the client checks the parent folder before reporting forbidden. 11 live tests (shares, listing, unicode names, ranged reads, seek past end, wrong password, guest refused, reconnect, 40 MB read). **Not tested**: Samba, Windows, SMB3, encryption, Apple TV.

## NFS (B2)
- **Licence of the library itself (Read)**: libnfs's `COPYING` says `lib` and `include` are **LGPL-2.1 or later**; protocol `.x` files are simplified BSD; generated `libnfs-raw-*` files may be treated as BSD; `examples` are **GPL-3**. I confirmed file headers: `lib/init.c` is LGPL-2.1+, `utils/nfs-ls.c` is **GPL-3+**. So the **library is LGPL (usable with dynamic linking); the GPL parts are examples and utilities, which we do not ship**. The repo page labels "GPL-3.0" only because of those files. My earlier "GPL mix blocks it" was too strong and is withdrawn.
- **tvOS buildability**: libnfs's README lists iOS (SDK 4.2) and no tvOS. But **NFSKit** (MIT, wraps libnfs, last push 2023-12) ships a **prebuilt `Libnfs.xcframework` with slices `tvos-arm64` and `tvos-arm64_x86_64-simulator`** (also iOS, Catalyst, macOS), each a static `libnfs.a` (Read: Info.plist). Its manifest also compiles a small C wrapper target `nfs`. Its README does not mention read-at-offset (Read).
- **Problems**: the binary is **static** (LGPL needs relinking ability or dynamic linking; to be solved by wrapping it in our own dynamic framework or by providing object files), the libnfs version inside is unknown, and offset reads are not documented (libnfs itself has `nfs_pread`, Unverified here).
- **Plan**: (1) pull NFSKit's xcframework only (do not depend on NFSKit's Swift layer if it lacks offset reads), (2) write `SourceNFS` over libnfs's C API (`nfs_mount`, `nfs_opendir`, `nfs_pread`), (3) tvOS link and licence handling at the first compile check, (4) NFSv3 AUTH_SYS only (Kerberos off).
- **Decision (R16, PROVISIONAL)**: only the NFSKit xcframework, copied to `Packages/VideoPlayerCore/Frameworks/Libnfs.xcframework` (6.9 MB, NFSKit's Swift layer not used); NFSv3 only.
- **libnfs version: 5.0.2.** `strings` on the static `libnfs.a` finds no version (only `0.0.0.0`), so it comes from NFSKit's `Vendor/libnfs` submodule pointer: commit `465a12d45703d4c8b1ba534323f911cf28b71501` (2023-11-17), whose `configure.ac` and `CMakeLists.txt` say 5.0.2. The slice headers `libnfs.h`, `libnfs-raw.h`, `libnfs-zdr.h` are byte-identical to that commit and the 24 object files match what compiles from it. NFSKit's binary was not rebuilt to prove it. Slices: `tvos-arm64` (487,176 bytes, arm64) and `tvos-arm64_x86_64-simulator` (975,264 bytes, x86_64 + arm64); all slices hold the same 24 members, with `nfs_pread`, `nfs_mount`, `nfs_opendir`, `nfs_stat64`, `nfs_read`, `nfs_set_version`, `mount_getexports`.
- **Wiring**: Apple: `binaryTarget` Libnfs plus a header-only C target `CLibnfs`. Linux: nothing declared unless `VP_LIBNFS` is set (a binaryTarget with no matching slice fails SwiftPM on Linux when depended on), so Linux runs the 34 unit tests and the 13 live tests are reported skipped. `scripts/test-nfs.sh` builds libnfs at the pinned commit with gcc and runs everything.
- **WSL test server (Tested)**: `rclone serve nfs` (NFSv3, read-only, 127.0.0.1:12049). It has no MOUNT EXPORT call, so libnfs runs with `auto-traverse-mounts` off (the backend always does this); the port needs `nfsport`/`mountport`, so `port` is nil by default and real servers use the portmapper. 13 live tests: mount, listing, nested walk, accented names, info, ranged reads on the byte pattern, 9 MB read across chunks, read across EOF, missing file, unknown export refused, reconnect, 12 parallel reads.
- **Static-linking note for the first compile check**: the xcframework is static, so LGPL-2.1+ libnfs code lands inside the app (examples/utils are GPL-3 and not linked). Before a public release the licence text must ship and the relinking obligation needs a decision. First compile check must confirm: `CLibnfs` builds, `<nfsc/libnfs.h>` is found through the binary target's Headers path, and the archive links with no duplicate or missing symbols.
- **Auth**: AUTH_SYS. **Discovery**: `_nfs._tcp` Bonjour (Unverified), typed address plus export path. **Ranges**: native. **Unverified**: any real NAS/`nfsd`, portmapper path, AUTH_SYS uid/gid, symlinks, permission-denied mapping, the Apple build, tvOS timing.
- **Risks**: LGPL static linking, C wrapper compile (small).

## SFTP (B3)
- **Prebuilt package manifest (Read)**: `Libssh2Prebuild`, `Package.swift` tools 5.6, package `CSSH`, **a single `binaryTarget` with a URL and checksum** (`CSSH-1.11.0-OpenSSL-1-1-1w.xcframework.zip`, 22,651,057 bytes, sha256 `f2a14236019b617019f522001c89ad5db2125e8f350cbcde5ed6e96f50842157`, no declared `platforms`). **tvOS: its README lists tvOS arm64 and tvOS Simulator x86_64/arm64 (Read)**. **Zip opened (Read, sha256 matches the manifest)**: slices are `ios-arm64`, `ios-arm64_x86_64-simulator`, `ios-arm64_x86_64-maccatalyst`, `macos-arm64_x86_64`, **`tvos-arm64`** (device, 5,104,592-byte `libssh2.a`), **`tvos-arm64_x86_64-simulator`** (10,219,504 bytes, arm64 + x86_64), `xros-arm64`, `xros-arm64-simulator`. The libs contain libssh2 1.11.0 and the string `OpenSSL 1.1.1w  11 Sep 2023`. Built May 2023. No Linux slice, so it cannot run in WSL.
- **Licences**: the repo is **MIT** (Read); it bundles **libssh2 1.11.0 (BSD-3-Clause)** and **OpenSSL 1.1.1w**. OpenSSL 1.1.1 is end-of-life and under the old OpenSSL/SSLeay licence (advertising clause); that is from memory (**Unverified**). Needs an attribution line in the app's acknowledgements.
- **Concern**: OpenSSL 1.1.1 reached end of life on 11 September 2023 (from memory, Unverified here); 1.1.1w is the last release and nothing will fix a future flaw in it. The binary also dates from May 2023.
- **Citadel (Read in the repo, 0.12.1, MIT)**: pure Swift over a **fork** of swift-nio-ssh (`Wellz26/swift-nio-ssh` 0.3.x). `Package.swift` declares only macOS 14 and iOS 17, **no tvOS**. `SFTPFile.read(from:length:)` exists (ranged reads). Password, ed25519, P256 and RSA key auth. **Spike in WSL (not in the repo)**: it does not compile on Swift 6.4.2 Linux as shipped (missing `import CDispatch` in the fork's `NIOSSHCertifiedPublicKey.swift`); with that one import added it builds, and against the rclone SFTP server it listed folders, read 64 bytes at offset 1000 matching the test pattern, returned 0 bytes past the end, and refused a wrong password.
- **Decision (R29, PROVISIONAL)**: Citadel, with Libssh2Prebuild as the recorded fallback.
- **Timed clean builds (Measured, Linux x86-64, 6 cores, Swift 6.4.2, a throwaway package that depends only on Citadel 0.12.1 and the patched fork; not the app)**: package resolve and fetch 19.6 s; **debug build 148.8 s wall (9 min 59 s CPU)**; **release build 337.5 s wall (14 min 44 s CPU)**. Those are Linux numbers; the Codemagic Mac and Xcode are different. My estimate, **not measured**: with roughly 1.5x faster cores and 4 to 8 usable cores, the Citadel tree adds about **1.5 to 3 minutes (debug) or 2.5 to 5 minutes (release)** to a compile check. The compile check is a debug Simulator build, so use the debug figure. Together with AMSMB2 (about 1 minute, estimated) that is roughly **2.5 to 4 minutes of dependency compilation** on top of the app itself. I have no measured baseline for the app, so I cannot promise the total stays under 8 minutes; I think it likely does, but it is not certain. If the first check shows the total near 8 minutes, the recommended order is: (1) cache `SourcePackages` and DerivedData between runs in `codemagic.yaml`, (2) keep the check on the debug configuration, (3) only then drop Citadel from the check and fall back to Libssh2Prebuild, which compiles nothing (prebuilt binary).
- **Dependency tree (Read from `Package.resolved` and each checkout's licence file; "Apache-2.0" and "MIT" taken from the licence file headers, the BigInt licence name from memory)**:
  | Package | Version resolved | Licence | Used for |
  |---|---|---|---|
  | Citadel (orlandos-nl) | 0.12.1 | MIT | SFTP client and SSH wrapper |
  | swift-nio-ssh, **fork Wellz26** | 0.3.4 (tag), commit `b93961a2988607a756cbc21a811f406f27aa9ab6` | Apache-2.0 | SSH protocol |
  | swift-nio | 2.84.0 | Apache-2.0 | networking |
  | swift-crypto (includes vendored BoringSSL sources) | 3.12.3 | Apache-2.0 (BoringSSL parts carry their own ISC/OpenSSL-style notices; from memory) | cryptography |
  | swift-asn1 | 1.4.0 | Apache-2.0 | key parsing |
  | swift-atomics | 1.3.0 | Apache-2.0 | NIO dependency |
  | swift-collections | 1.2.0 | Apache-2.0 | NIO dependency |
  | swift-system | 1.5.0 | Apache-2.0 | NIO dependency |
  | swift-log | 1.5.4 | Apache-2.0 | logging |
  | BigInt (attaswift) | 5.3.0 | MIT | RSA keys |
  | CCitadelBcrypt (inside Citadel) | n/a | part of Citadel | bcrypt for encrypted keys |
  | ColorizeSwift (mtynior) | 1.6.0 | MIT | only the example server executable, **not linked into the library** |
  A fresh resolve with no `Package.resolved` picked newer minor versions of swift-system (1.9.0), swift-collections (1.7.6) and swift-log (1.17.0) than Citadel's own lock file; our `Package.resolved` must be committed so the compile check is reproducible.
- **Can the Wellz26 fork be pinned to an exact commit? Yes, with one caveat.** Citadel's manifest asks for `"0.3.4" ..< "0.4.0"` from `https://github.com/Wellz26/swift-nio-ssh.git`. Tag 0.3.4 is commit `b93961a2988607a756cbc21a811f406f27aa9ab6` (a merge of PR #9, 2025-07-14). A tag can be moved, so the exact commit is the real pin. SwiftPM would not accept a `revision:` pin on that URL from a root package alongside Citadel's version range in my reading (**Unverified**, not tested); a **vendored local copy at that commit** (`Vendor/swift-nio-ssh`) does work as an override and is what the timed build used. The vendored copy also carries the patch. Supply-chain note: this is a third-party fork of Apple's swift-nio-ssh, so a vendored, reviewed copy is the safer way to use it.
- **Patch**: `scripts/patches/swift-nio-ssh-0.3.4-cdispatch.patch` (3 lines added to `NIOSSHCertifiedPublicKey.swift`: `#if canImport(CDispatch) import CDispatch #endif`). It is needed on Linux with Swift 6.4.2 only; on Apple platforms `CDispatch` does not exist, so the patch does nothing there. `git apply --check` succeeds on a clean checkout of that commit.
- **Backend seam**: `SourceSFTP` talks to `SFTPBackend` (connect, list, attributes, read, disconnect) with host-key policy (pinned or trust-on-first-use) in the client; either library plugs in behind it. No library backend is written until you choose.
- **Auth**: password, public key, keyboard-interactive; host key trust on first use per server. **Ranges**: libssh2 SFTP `seek64`/`read` (Unverified here). 100 Mbps: unknown; SFTP is often slower, device-only. **Reconnect**: re-establish SSH and SFTP handle.
- **WSL test server**: `rclone serve sftp` (running). `SourceSFTP` has 18 unit tests against an in-memory backend; live tests wait for your backend choice.
- **Device-only**: tvOS link, key auth, throughput.

## FTP and FTPS (B4)
- **Client**: written on Network.framework (`NWConnection`), tested in WSL over a small stream seam implemented with POSIX sockets. URLSession FTP is not used (you said it is gone).
- **Auth**: username/password, anonymous. **Ranges**: `REST offset` + `RETR`; servers refusing `REST` are marked no-seek. Prefer `MLSD`, fall back to `LIST` parsing. **Reconnect**: re-login after idle drop.
- **WSL test server**: `rclone serve ftp` (plain FTP, running). 46 unit tests (scripted fake server + parsers) and 14 live tests pass. Explicit FTPS uses `URLSessionStreamTask` for the control channel (`NWConnection` cannot upgrade to TLS after connecting), the data channel and implicit FTPS use `NWConnection`; the client dials the control host and ignores the address in the PASV reply. None of the Apple transport code has been compiled.
- **Exactly what stays untested without a TLS-capable test server**: FTPS explicit (`AUTH TLS`), FTPS implicit, TLS session reuse on the data channel (many servers require it), certificate trust/pinning for FTPS, `PROT P` negotiation, and 100 Mbps throughput. Also untested until the device: Network.framework behaviour (it does not exist on Linux, so only the protocol logic is Linux-tested).

## UPnP/DLNA (B5)
- **Approved**: no multicast entitlement requested (Apple lists it for iOS 14, iPadOS 14, visionOS 1 and not tvOS, Read). Typed address plus Bonjour; SSDP is tried on the device only and reported.
- **Browse (Tested)**: device description (`/rootDesc.xml`, honours URLBase) to find the ContentDirectory control URL, SOAP `Browse` `BrowseDirectChildren` with paging, DIDL-Lite parsing; paths are built from titles (repeated titles get " (2)") with an object-id map. **Ranges**: plain HTTP `Range` on the `res` URL. **WSL server**: `rclone serve dlna` (HTTP only, no multicast through WSL); 31 unit tests (fixtures are real rclone responses) and 10 live tests pass. **Device-only / untested**: `SSDPDiscovery` sockets (message building and response parsing are tested), other DLNA servers (MiniDLNA, Plex, Jellyfin DLNA), servers that refuse HEAD or ignore Range (mock only), `BrowseMetadata` (not used).

## Cloud storage and links (B6)
**Platform limits**, written down so nothing is silently dropped:
- **Google Drive: platform-limited.** The TV sign-in (device flow) only allows the `drive.file` and `drive.appdata` scopes, so a Drive cannot be browsed from a TV. Alternative: **Links** (shared URL pasted by the user).
- **Dropbox: platform-limited.** No device/TV sign-in is documented; flows are code, PKCE and a no-redirect code that the user copies back (Read). Alternatives: **Links** (a shared link that serves file bytes), or reaching Dropbox through a **WebDAV bridge on a PC** (for example rclone serving the Dropbox remote over WebDAV, which then works as a normal WebDAV source).
- **iCloud Drive**: shared links are web pages, not file bytes, so the Links list says so rather than guessing. Alternative: the same WebDAV-bridge route.
- **Built**: **Links** list (`SourceLinks`: `LinkStore` Codable list, `LinkClassifier`, HEAD or one-byte ranged probe, rejects an HTML answer as "web page" before it reaches the player; Dropbox `dl=1`, Google Drive `uc?export=download&id=`, personal OneDrive via the shares API only when the link is open to anyone, iCloud Drive classified and explained with the WebDAV-bridge alternative; links with a user name or password in them are refused) and **OneDrive browsing** (`SourceOneDrive`, Microsoft Graph with the device code flow). The Links provider conversions are tested only against recorded formats; no provider was contacted. The OneDrive client has no client ID, so every call throws `needsAppRegistration` ("blocked: needs an app registration"); its 36 tests use fixtures I wrote from Microsoft's documentation, not recordings; `SourceKind.oneDrive.limit` is `vendorAccountBlocked`, so it is outside the release gate.

### OneDrive app registration (not done; nothing registered, no provider contacted)
What it involves (Read from Microsoft Learn):
1. Sign in to the Microsoft Entra admin center (`entra.microsoft.com`) with an Azure account. The documented prerequisites say an account with an active subscription and at least the Application Developer role, and a tenant (your "Default Directory" works). An Azure account can be created free; whether a free account with no subscription is enough is **not stated** and I will not guess.
2. Entra ID > App registrations > New registration. Enter a name. Under supported account types choose **Personal Microsoft accounts only** (or "Any Entra tenant + personal accounts"). Register.
3. Copy the **Application (client) ID**. For the device flow also turn on "Allow public client flows" (the doc I read does not list this step; this is from memory, **Unverified**).
4. Add the delegated Graph permissions `Files.Read` (or `Files.Read.All`) and `offline_access`.
5. The client ID is then compiled into the app. No client secret is used for the device flow (Read: the request needs only `client_id` and `scope`).

What registration publishes: the **app name**, shown to users on the sign-in and consent screens (Read); the client ID is a public identifier (anyone can see it in the app). Newly registered apps are hidden from users' My Apps page by default (Read). **Publisher verification** is optional, free, and needs a verified Microsoft AI Cloud Partner Program account **and an organisation (work/school) registration**; apps registered with a personal Microsoft account cannot be publisher-verified (Read). Without it, work/school tenants with step-up consent may show an "unverified publisher" warning; personal accounts are the target here.
Cost: Microsoft's pages say registration and verification are not charged (publisher verification: "No charges", Read). Registration itself: no price stated on the page I read; the Azure account sign-up is free but may ask for a card (Unverified).
Sign-in on the TV (Read): code valid 15 minutes, the user opens `verification_uri` on a phone, personal accounts are asked to sign in again, polling at the returned interval, refresh token only with `offline_access`.

## Media servers
### Jellyfin (B8: real server running)
- **Run in user space, no sudo, no account (Tested)**: generic tarball `jellyfin_12.4-amd64.tar.gz` (113,075,397 bytes, repo.jellyfin.org) is a self-contained native executable; it needed (a) `jellyfin-ffmpeg 7.1.4-3` portable (58,599,712 bytes) because the server exits at start without ffmpeg, and (b) ICU libraries, which I unpacked from the Ubuntu `libicu78` deb with `apt-get download` + `dpkg -x` (no root). Globalization-invariant mode does **not** work (it crashes). `scripts/test-mediaservers.sh setup|start jellyfin` does all of it.
- **What worked (Tested, curl)**: first-run wizard through the API, user login (`Authorization: MediaBrowser ...` header), adding a library over the test folder, listing children, `Items?Recursive=true` with `Path`, `Videos/{id}/stream?static=true` with `Range` (206, correct `Content-Range`, bytes identical), 40 MB at about 45 MB/s on loopback, Quick Connect reported enabled.
- **Findings that shape the client**: Jellyfin's names are wrong for our purposes (a movie folder shows as "Home Movies", "Odd Names" is a "Movie"), folders collapse; so the client reads **`Path`** from a recursive listing and builds its own folder tree. A stream request with no token still returned 200 (server-side setting; we always send the token).
- **Auth**: username/password, Quick Connect (Read), token. **Discovery**: typed address (UDP 7359 discovery Unverified). **Reconnect**: re-authenticate on 401.
- **Status**: `SourceJellyfin` written: file tree from each item's `Path`, waits until the item count is stable before listing (a first check saw 3 of 5 items), direct play (`static=true`) only, token in a header. 26 unit tests on responses recorded from the server (token and paths redacted) and 11 live tests (browse, ranged reads on the byte pattern, read past end, direct-play URL, 401 reconnect, wrong token refused, wrong password refused) pass. **Unverified**: non-administrator users (libraries come from a fallback, mock-tested only), multi-location or Windows-hosted libraries, multiple versions of one movie.

### Emby (B8: real server running)
- **Run in user space, no sudo, no outside account (Tested)**: `emby-server-deb_4.10.2.0_amd64.deb` (247,007,280 bytes, GitHub Emby.Releases), **unpacked with `dpkg -x`, not installed**. It bundles its own runtime and ffmpeg and starts with `./system/EmbyServer -programdata ...`. `scripts/test-mediaservers.sh` automates it.
- **What worked (Tested)**: wizard, `AuthenticateByName` (`X-Emby-Authorization`), library over the test folder (4 items found; sizes read 0 because the test files are not real video), `Videos/{id}/stream?static=true` with `Range` (206, bytes identical), no-token request refused (401).
- **Status**: `SourceEmby` written and tested like Jellyfin (26 unit, 11 live). Findings: Emby lists every file with size 0 and omits `Etag` unless asked, so the client treats 0 as unknown, asks for `Etag`, and `info()` reads the real size from a one-byte ranged request; Emby skips files with "sample" in the name under 300 MB. Emby and Jellyfin both bind 8096, so run one at a time.

### Plex (B7)
- **No plex.tv sign-in will be used.** Plex documents a server setting, **"List of IP addresses and networks that are allowed without auth"** (Settings > Network, advanced), also stored as `allowedNetworks`; when set, clients on those addresses need no token. Findings (search results, Read as summaries): it takes comma-separated IPs or CIDR; with a signed-in server the list ignores 127.0.0.1; only private RFC1918 ranges count; a listed network gets **full administrative access**; and forum reports say it is **inconsistent** (redirects to plex.tv sign-in after updates, with proxies, and with some apps). Plex's own support page returned 403 to my fetch, so the details come from the search summary and forum posts, **not the vendor page**.
- **Decision applied**: support **only** a server configured this way (typed address, no token). If it does not work on the user's server, Plex is marked **"blocked: needs a vendor account"**. Everything else stays in the spec.
- **Testing**: no Plex server here. I did not try to download or run one (setting one up normally involves a plex.tv account, which is out of bounds). Contract tests from recorded responses only; the Settings screen shows "Not yet verified against a real server".
- **Superseded (20 Nov 2026)**: the owner's statement recorded in OPEN_QUESTIONS.md R267 replaces the two points above for Plex: Plex is the primary source type and signs in with the owner's Plex account through plex.tv (PIN or link code), then picks a server from the account's list. For Plex, R270 (PROVISIONAL) puts Plex's own metadata first, unlike the rule below. Plan: docs/PLEX_SOURCE.md. The text above is kept as history.

For every media server the rules are: Your Library Only, direct play only, our metadata authoritative.

## Local networking (B9, done in `project.yml`)
`NSAllowsLocalNetworking = true` (no other ATS exception), `NSLocalNetworkUsageDescription` (text in `InfoPlist.xcstrings`), and `NSBonjourServices`: `_webdav._tcp`, `_webdavs._tcp`, `_smb._tcp`, `_nfs._tcp`, `_sftp-ssh._tcp`, `_ftp._tcp`. `NSAllowsLocalNetworking` covers IP-address and `.local` hosts; a typed host name that resolves through DNS (for example `nas.example.lan`) may still be blocked for plain `http://` (Unverified; the compile check does not test this, a device run does). The app now also links the `SourceWebDAV` product, so the next compile check compiles it for tvOS.

## What still needs a decision from you
SMB and NFS are approved but PROVISIONAL until the first compile check (R15, R16).
| # | Item | Why |
|---|---|---|
| D-SFTP | Choose the SSH library: Citadel (my recommendation) or Libssh2Prebuild with OpenSSL 1.1.1w | Comparison in the SFTP section and OPEN_QUESTIONS R17 |
| D-OD | Decide whether to register the OneDrive app (summary above); I will not register or contact Microsoft | Your rule; OneDrive stays "blocked: needs an app registration" |

## Test servers and scripts
`bash scripts/test-all.sh` runs everything below one stage at a time and prints passed / skipped / failed per stage.
| Server | Script | Used by |
|---|---|---|
| rclone WebDAV, HTTP, FTP, DLNA (SFTP also served) | `scripts/test-servers.sh`, `scripts/test-live.sh <name>` | WebDAV, Links, FTP, UPnP |
| Jellyfin 12.4.0 / Emby 4.10.2.0 (one at a time, port 8096) | `scripts/test-mediaservers.sh`, fixtures: `scripts/record-mediaserver-fixtures.sh` | Jellyfin, Emby |
| impacket SMB server (port 12445) | `scripts/test-smb.sh` | SMB |
| `rclone serve nfs` (port 12049) + libnfs built from source | `scripts/test-nfs.sh` | NFS |
