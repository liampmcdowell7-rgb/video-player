# SFTP over Citadel (backend for `SourceSFTP`)

Status words: **Written** = the code exists in the repository. **Tested** = I ran it and it passed (the exact command is given). **Not run** = written but not compiled or run yet. Nothing here has been compiled for tvOS or run on an Apple TV.

Decision record: OPEN_QUESTIONS R29 (Citadel, PROVISIONAL) and R51. Libssh2Prebuild stays the recorded fallback (see docs/SOURCES.md, SFTP section); it was not built.

## What was written

| Path | What it is | Status |
|---|---|---|
| `Packages/VideoPlayerCore/Sources/SourceSFTPCitadel/CitadelSFTPBackend.swift` | `CitadelSFTPBackend: SFTPBackend`. Password and private-key (ed25519, RSA, optional passphrase) authentication, list, attributes, ranged read with one open file kept between reads, host-key check through the `SFTPSource` policy before any credential is sent, error mapping, `HostKeyFingerprint` (`SHA256:` plus unpadded base64, same text as `ssh-keygen -l`) | Written, **not run** (see "Test status") |
| `Packages/VideoPlayerCore/Tests/SourceSFTPCitadelTests/CitadelUnitTests.swift` | Tests that need no server: fingerprint against three real `ssh-keygen` outputs (ed25519, RSA, ECDSA), attribute mapping, auth-method building, error mapping, behaviour with no connection, connection to a closed port | Written, **not run** |
| `Packages/VideoPlayerCore/Tests/SourceSFTPCitadelTests/CitadelLiveTests.swift` | Live tests against real rclone SFTP servers: password auth, wrong password and wrong user refused, list, info, ranged reads (offset 1000 / 64 bytes, many offsets and sizes across the 32 KiB request size, crossing the end, past the end, missing file), 8 MiB sequential read with speed printed, recovery after a dropped connection, trust-on-first-use (first connect records, second matches, fingerprint equals `ssh-keygen`'s), pinned fingerprint, changed host key refused (the test starts rclone with key A, then restarts it on the same port with key B), key authentication (ed25519, passphrase-protected ed25519 and a wrong passphrase, RSA, a key the server does not know) | Written, **not run** |
| `scripts/setup-citadel.sh` | Creates `Packages/VideoPlayerCore/Vendor/Citadel` and `Vendor/swift-nio-ssh` at pinned commits, applies the patch, removes `.git`, writes `VENDORED_FROM.txt`, verifies (`check`), removes (`clean`) | **Tested**: ran, printed `OK: vendored Citadel ae8562f8... and swift-nio-ssh b93961a2... (patched)`; `check` printed OK. Vendor sizes: Citadel 696 KB, swift-nio-ssh 1.4 MB |
| `scripts/test-sftp.sh` | One command: vendors, starts the rclone servers, generates throwaway host and user keys with `ssh-keygen` under `~/video-player-test-servers/sftp-keys` (outside the repo), starts an extra key-auth server on 12023, runs the tests in a private trimmed copy of the package (`VP_FULL=1` uses the real manifest), stops what it started | Written, **not run to completion** |
| `scripts/patches/swift-nio-ssh-0.3.4-cdispatch.patch` | Unchanged from the last batch. Three added lines, a guarded `import CDispatch`. Needed on Linux with Swift 6.4 only; does nothing on Apple platforms | Applied by `setup-citadel.sh` (verified by the script) |
| `Package.swift`, `CITADEL-BLOCK` | Declares `SourceSFTPCitadel` and `SourceSFTPCitadelTests` only if both vendored copies exist. Adds the two vendored packages as `.package(path:)` plus `swift-nio` and `swift-crypto` by URL (the backend imports `NIOCore`, `NIOFoundationCompat`, `Crypto`) | Written, **not run** against the full manifest |

## Test status (read this first)

WSL's virtual machine restarted by itself on most attempts. I never ran `wsl --shutdown` or anything that restarts WSL. `%UserProfile%\.wslconfig` was rewritten by someone else (07:42: `memory=4GB`, `swap=0`, `processors=4`; 07:44: `memory=3GB` plus `autoMemoryReclaim=dropcache`); I left it alone.

What actually ran, in order:

- `scripts/setup-citadel.sh`: ran, passed (pins verified, patch applied).
- Run 6 compiled Citadel, NIO, swift-nio-ssh and my backend on Linux (debug) and stopped on one error (`NIOConnectionError` is in NIOPosix). Fixed by matching the type name.
- Run 7 compiled. **18 `SFTPSourceTests` passed, 0 failed, 0 skipped.** The `SourceSFTPCitadelTests` runner then **crashed** (`Illegal instruction` in `CitadelSFTPBackend.connect`, during `testAChangedHostKeyIsRefusedAfterTheFirstConnection`).
- Cause: `withoutActuallyEscaping` traps when the closure is still referenced after the call returns. When a connection fails (the test waits for a freshly started server), NIO still holds the delegate, so it trapped. Fix: `acceptHostKey` is now `@escaping @Sendable` in `SFTPBackend`, `CitadelSFTPBackend` and the two test fakes, and `withoutActuallyEscaping` is gone. **This fix has not been re-run**, because WSL restarted again on runs 8 and 9 (uptime 0 minutes, no output). I stopped there.

Status of the Citadel tests (fingerprint, mapping, live list, ranged read, read past end, wrong password, host-key policy, key auth): **no result yet; none passed, none failed, none counted.** The earlier timings in the next section are from the previous batch and were not re-measured.

To run them when WSL is stable: `VP_JOBS=2 VP_KEEP_RESOLVED=1 bash scripts/test-sftp.sh` (keeps compile jobs low for the 3-4 GB limit).

## Timed builds of Citadel and its dependency tree

**Not re-measured this round** (WSL instability above). The numbers below are the ones measured last batch, kept for reference, and are Linux, not Codemagic:

| Build | Result | Conditions |
|---|---|---|
| Package fetch and resolve | 19.6 s | clean, cold cache |
| Debug build, Citadel and tree | 148.8 s wall (9 min 59 s CPU) | Linux x86-64, i5-8500T, 6 cores, Swift 6.4.2, default jobs, 8 GB WSL |
| Release build | 337.5 s wall (14 min 44 s CPU) | same |

Re-measure with `bash scripts/test-sftp.sh` (it prints Swift's own build times in the log) or the earlier throwaway package in `~/vp-citadel-time`. The new WSL limits (4 cores, 4 GB, no swap) will make all of these slower than the table.

## Dependency table (resolved in the earlier timing package, fresh resolve)

| Package | Resolved version | Commit | Licence | Used for |
|---|---|---|---|---|
| Citadel (orlandos-nl) | 0.12.1 | `ae8562f895de06ccb86fdb1cbb65fd99c8976e12` | MIT | SFTP client, SSH wrapper |
| swift-nio-ssh, fork Wellz26 | 0.3.4 | `b93961a2988607a756cbc21a811f406f27aa9ab6` | Apache-2.0 | SSH protocol |
| swift-nio | 2.105.0 | `2f58d8ef84438d6517fc78bcea2f8527e3c72936` | Apache-2.0 | networking |
| swift-crypto (with BoringSSL sources) | 3.15.1 | `95ba0316a9b733e92bb6b071255ff46263bbe7dc` | Apache-2.0 (BoringSSL parts carry their own notices) | cryptography |
| swift-asn1 | 1.7.4 | `917b472dbe53ba699cbb0495f9a95a084bc6364d` | Apache-2.0 | key parsing |
| swift-atomics | 1.3.1 | `0442cb5a3f98ab802acb777929fdb446bda11a34` | Apache-2.0 | NIO |
| swift-collections | 1.7.6 | `88754449ab766a739610b660e117762115fabc9c` | Apache-2.0 | NIO |
| swift-system | 1.9.0 | `640e5755b5826f4437eaeedd366fd776737db62c` | Apache-2.0 | NIO |
| swift-log | 1.17.0 | `e3da04078777e6a1b72ce19981fbd6539b0847d8` | Apache-2.0 | logging |
| BigInt (attaswift) | 5.7.0 | `e07e00fa1fd435143a2dcf8b7eec9a7710b2fdfe` | MIT | RSA keys |

This differs from the table in docs/SOURCES.md, which listed the versions in Citadel's own lock file (for example swift-nio 2.84.0). A fresh resolve takes the newest allowed versions; the commit pins above are what the timing package actually used. Licences are from the licence files' headers (read last batch); the BoringSSL notice detail is from memory.

## Can the Wellz26 fork be pinned to an exact commit?

Yes. The commit is `b93961a2988607a756cbc21a811f406f27aa9ab6` (tag 0.3.4). Citadel's manifest asks for `"0.3.4" ..< "0.4.0"` from `https://github.com/Wellz26/swift-nio-ssh.git`. A tag can move; a commit cannot. I did not test whether SwiftPM accepts a `revision:` pin on that URL from the root package next to Citadel's version range (**Unverified**). What works, and what this work uses, is a **vendored local copy**: `scripts/setup-citadel.sh` clones both repositories, checks out the exact commits, verifies `git rev-parse HEAD`, applies the patch to the fork, deletes `.git`, and the manifest overrides the fork with `.package(path: "Vendor/swift-nio-ssh")` (the same identity `swift-nio-ssh`, so Citadel's own URL requirement is replaced; SwiftPM prints a "Conflicting identity" warning that is expected and harmless). Citadel is vendored the same way so the whole Citadel code under review is in the project folder.

Pinning the other dependencies: SwiftPM picks them when the project is first resolved. A committed `Package.resolved` for the package fixes them (the versions in the table above). Not created yet because the full-manifest resolve could not be run.

## Added Codemagic minutes (estimate, not measured)

The compile check is a debug build for the tvOS Simulator, with the `max_build_duration` cap now 8 minutes and 18 free macOS minutes left this month. Reasoning:
- Debug Linux time for the tree: 149 s wall, about 600 s of CPU, at 6 jobs on a 2.1 GHz desktop CPU.
- An M2 Mac mini has 8 cores (4 performance) and is roughly 1.5 to 2 times faster per core than that CPU for compiling Swift, so the tree costs about **2 to 3.5 minutes** of wall time in debug (dependency compile only).
- Add: fetching 10 packages (about 20 to 40 s, partly cached by the existing `cache_paths`), BoringSSL C sources in swift-crypto (included in the compile estimate), linking.
- AMSMB2 (about 1 minute, estimated before), the Xcode project generation, the whole package's own compile and its `swift test` all share the same 8 minutes.
- My judgement: **the Citadel tree alone is likely 2.5 to 4 minutes, and with the rest of the package and the app it is plausible to exceed 8 minutes.** I cannot promise otherwise without a measurement. Options, cheapest first: (1) do not wire Citadel into the first compile check; keep it out of the Xcode project until a second check (the Package.swift condition already does this when `Vendor/` is absent, so the first check can simply run without `scripts/setup-citadel.sh`); (2) run the Mac `swift test` with `--filter` to the targets that matter; (3) raise the cap (your decision, it costs minutes). Recommendation: **leave Citadel out of the first compile check** (nothing in the app target imports it yet), and compile it in a later check once the cap and the budget are known.

## Design

- **Host key** (R29 seam): `SFTPSource` keeps the policy (pinned, trust on first use, accept-any for tests). The backend only computes the SHA-256 fingerprint during the SSH key exchange and asks `acceptHostKey` before authentication starts. If the answer is no, the handshake is failed in NIOSSH's validation step, which runs before user authentication, so no password or key signature is sent to an unknown host. The rejected fingerprint is kept and reported as `hostKeyRejected(fingerprint:)`, which `SFTPSource` turns into "The server's host key changed or is not trusted (SHA256:...)". **Not yet proved by a test** that no credential is sent (that needs a server that logs authentication attempts); it follows from reading Citadel's `ClientHandshakeHandler` and NIOSSH, not from an observation.
- **Reads:** one SFTP open per file, kept while the same file is read (the usual playback pattern); a different file closes the old one. A read past the end returns empty data (the protocol's EOF status), a read crossing the end returns the available bytes.
- **Listing:** Citadel's `listDirectory(atPath:)` opens a directory handle and, in the version read, never sends a close for it. On a long session with many listings each leaves a handle open on the server until disconnect. The source reconnects after errors; a periodic reconnect would bound it. **Unverified how many handles servers allow.**
- **Reconnect:** `SFTPSource` retries once after `connectionLost`; the backend reports `connectionLost` when the SFTP channel is not active, which includes a call before `connect` and after `disconnect`.
- **Key types:** ed25519 and RSA with optional passphrase (OpenSSH format). ECDSA user keys are refused with a clear message (Citadel has no OpenSSH-format initialiser for P-256 in the version read). `capabilities.authMethods` of `SFTPSource` lists `publicKey`; that is true for ed25519 and RSA only.
- **Throughput:** 32 KiB requests, one at a time (the `SFTPSource` chunk size), so throughput is bounded by round-trip time; pipelining several requests would need a change in `SFTPSource` (not done). The live test prints MiB/s over loopback; a 100 Mbps file over a real network is a device test.

## Unverified (needs WSL running, or an Apple TV)

- Everything marked "Not run" above, in WSL.
- That Citadel, swift-nio-ssh, swift-crypto and swift-nio compile for tvOS (Citadel declares only macOS 14 and iOS 17; swift-nio supports tvOS). First compile check only.
- Throughput on an Apple TV; behaviour on a flaky network; key authentication against a real OpenSSH server (the tests use rclone's Go SSH server).
- `-strict` concurrency warnings or errors on the Xcode toolchain (the code uses Swift 5 language mode).

## Fallback

`Libssh2Prebuild` (libssh2 1.11.0 with OpenSSL 1.1.1w, end of life since 11 September 2023; slices tvos-arm64 and tvos-arm64_x86_64-simulator verified last batch) stays the recorded fallback behind the same `SFTPBackend` protocol. A second backend means a new target next to this one and no change to `SFTPSource`.
