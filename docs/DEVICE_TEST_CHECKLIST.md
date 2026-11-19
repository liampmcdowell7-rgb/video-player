# Apple TV device-test checklist: remux engine

Everything below is **untested**: only an Apple TV (with a real TV, and for some items a receiver) can check it. Each item says
what to do and what "pass" looks like. Platform items P1 to P37 are in `DEVICE_TEST_CHECKLIST_PLATFORM.md`, visual items in
`DEVICE_TEST_CHECKLIST_VISUAL.md`, sorting into Movies and Shows (SO1 "flat mixed folder sorts into Movies and Shows" to
SO14) in `DEVICE_TEST_CHECKLIST_SORTING.md`.

## A. The stream starts and plays
- E1. Play an H.264 MKV with AAC audio. Pass: picture and sound start within about 5 seconds, no stutter for 2 minutes.
- E2. Play an HEVC SDR MKV (8 and 10 bit). Pass: same.
- E3. Play an HEVC HDR10 MKV. Pass: the TV switches to HDR (its HDR indicator shows), colours look right, not washed out.
- E4. Play a Dolby Vision profile 8 MKV. Pass: the TV shows Dolby Vision (if it supports it).
- E5. Play a Dolby Vision profile 7 MKV (needs the converter, which is not built yet). Pass today: a clear message, not a black screen.
- E6. Play a file with a long name and non-Latin characters. Pass: plays.

## B. Audio
- B1. AC-3 5.1 and E-AC-3 5.1 pass-through to a receiver. Pass: the receiver shows Dolby Digital / Digital Plus.
- B2. E-AC-3 with Atmos. Pass today: plays as E-AC-3 (Atmos is not detected, see `eac3JOCComplexity`); note what the receiver shows.
- B3. AAC stereo. FLAC. Pass: plays.
- B4. A file with several audio tracks. Pass: the player's audio menu lists them with names and languages; switching works within a second or two.
- B5. DTS and TrueHD (needs the transcoder, not built). Pass today: the track is listed as unsupported with a reason.

## C. Seeking and control
- C1. Jump forward and back 10 s repeatedly, 20 times. Pass: no hang; resumes within 2 seconds.
- C2. Scrub to the middle and the very end. Pass: plays from there; the end shows the end, not an error.
- C3. Pause for 10 minutes, then play. Pass: resumes.
- C4. Start from a resume position (Continue Watching). Pass: starts at the saved place.
- C5. Play a file with no Cues. Pass: starts a little slower, seeks work.
- C6. Close the player in the middle of a seek. Pass: no crash, no leftover server (memory returns to normal).

## D. Sources
- D1. Repeat E1 and C1 from SMB, from WebDAV, from SFTP and from a media server. Pass: same behaviour; note the start time for each.
- D2. Pull the network cable (or turn Wi-Fi off) for 10 seconds while playing. Pass: it recovers or shows a clear message; no crash.
- D3. A slow link (use a throttled hotspot): Pass: it buffers instead of failing; note the lowest speed that works for a 20 Mbps file.

## E. Memory and the budget (the 192 MiB assumption)
- M1. Play a 60 Mbps and a 120 Mbps file for 10 minutes while watching memory (Xcode Instruments, or the app's own debug counter). Pass: the engine stays under 192 MiB and the app is not terminated.
- M2. Play a 4K HDR file of at least 40 GB. Pass: plays; read-ahead does not grow without limit.
- M3. Note `largestWindowBytes`, `peakCachedWindows` and `isOverBudget` from the session after each run and send them back so the budget can be set from measurements.

## F. Edge cases
- F1. A file with laced audio blocks (some muxers use them). Pass: plays; audio in sync.
- F2. An MKV with chapters. Pass: plays (chapter menu is a separate feature).
- F3. A file whose video is not HEVC or H.264 (VP9, AV1, MPEG-2). Pass: a clear message that it needs the fallback player.
- F4. Background the app for 1 minute and return. Pass: playback resumes or restarts cleanly.
- F5. Memory warning (open many apps first). Pass: the app survives; the engine drops its read-ahead.

## G. First compile check (not a device item)
- G1. `RemuxEngine` compiles for tvOS. The POSIX socket code in `Loopback.swift` is the part most likely to need changes.
