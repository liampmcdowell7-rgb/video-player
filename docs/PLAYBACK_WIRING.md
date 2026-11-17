# Playback wiring: converted playback in the app

Status: package code and tests written and run on Linux; **nothing in App/ has been compiled, and nothing has run on a device**. Everything marked PROVISIONAL is a decision the specs do not make; each names its alternative. Device checks are in docs/DEVICE_TEST_CHECKLIST_PLAYBACK.md (P1 to P51). Design background is docs/ENGINE_DESIGN.md; the status text rules are docs/PLAYBACK_STATUS.md; the subtitle rules are docs/SUBTITLES.md.

## What is wired

An MKV file now plays through the system player from a loopback address.

```
library item -> AppServices.resolvePlayback
  route by file name (PlaybackRoute):  mp4 m4v mov m3u8 -> direct URL (unchanged)
                                       mkv mk3d webm    -> converted playback
                                       anything else    -> refused with the reason (PlaybackFailures.unsupportedContainer)
converted: SourceFactory.byteReader(for:) -> RemuxPlayback.open
             -> RemuxHost(MatroskaRemuxSession over the ByteRangeReader) + loopback HTTP server on 127.0.0.1
             -> master.m3u8 URL -> ResolvedPlayback.url (+ .remux, + .segments)
PlayerScreen -> PlayerHost -> PlayerCoordinator -> AVPlayerViewController (the system player draws the controls)
```

The engine side (package `RemuxEngine`): Matroska index, fMP4 segments built on demand, video passthrough (HEVC, H.264), audio passthrough (AC-3, E-AC-3 including Atmos signalling, AAC, FLAC), WebVTT subtitle renditions for text tracks, PGS as raw `.sup` data for the app's own menu, seek map, bounded read-ahead.

### Files

| File | Role |
|---|---|
| `App/Features/Player/RemuxPlayback.swift` | Opens the session and server; owns them; `stop()` closes both. Gives the picture subtitle data to the overlay. |
| `App/Features/Player/PictureSubtitleOverlay.swift` | Draws PGS bitmaps in the player's content overlay view from the player's clock. |
| `App/Features/Player/PlayerCoordinator.swift` | Player setup: display criteria, Picture in Picture, menus (picture subtitles, mark, stats), D1 exclusivity, skip and Up Next, failure reporting. |
| `App/Features/Player/PlaybackProbe.swift` | For converted playback the facts come from the engine (`RemuxPlaybackModel.snapshot`), not from the stream read back. |
| `App/Features/Player/PlayerScreen.swift`, `PlayerHost.swift` | Error state and failure callback. |
| `App/Support/PlaybackResolution.swift` | `PlaybackRoute`, `PlaybackFailureMapper`, `ResolvedPlayback.segments` and `.remux`. |
| `Sources/AppLogic/PlaybackErrors.swift` | Error kinds and text: one sentence for what happened, one for what to do. |
| `Sources/AppLogic/RemuxPlaybackModel.swift` | File facts to status inputs (HDR format, audio content, profile 7 state) and the notices about left-out tracks. |
| `Sources/AppLogic/PictureSubtitleMenu.swift` | The menu model and the D1 rule. |
| `Sources/RemuxEngine/SubtitleRendition.swift`, `Inflate.swift`, `EAC3Atmos.swift`, `Playlist.swift`, `Session.swift` | WebVTT conversion, zlib for compressed tracks, Atmos detection, playlist lines, session resources. |

## Honest status per feature

| Feature | State |
|---|---|
| Video passthrough, HEVC and H.264 | Written and tested on synthetic files. Not seen on a device. |
| HDR10, HLG signalling | `VIDEO-RANGE` PQ or HLG and the transfer characteristics in the init segment. Tested as playlist and box content only. |
| Dolby Vision 5 and 8.x | `dvh1` for profile 5, `SUPPLEMENTAL-CODECS` with the brand for 8.x, `dvcC` or `dvvC` kept in the sample entry. Not seen on a device (P3, P4). |
| Dolby Vision 7 | Played as its HDR10 base layer. The conversion interface (`DolbyVisionConverting`) exists with no implementation. Status text says "HDR10 (base layer)" and why. |
| Match Content (display criteria) | Left to the system: `appliesPreferredDisplayCriteriaAutomatically = true`. The app sets no `AVDisplayCriteria`. PROVISIONAL, alternative: set criteria from the frame rate and format description if P6 or P7 fail. |
| AC-3, E-AC-3, AAC passthrough | Written and tested as box and playlist content. Not heard on a device. |
| Atmos (E-AC-3 JOC) | Detected from the additional bit stream information of the first syncframe and signalled with the dec3 JOC extension and `CHANNELS="n/JOC"`. The parser is tested on frames the tests build. NOT run on a real Atmos stream (P11). PROVISIONAL, alternative: a per-file setting or no automatic detection. |
| TrueHD, DTS, DTS-HD, Opus, Vorbis | **Not playable.** The tracks are left out with a reason; if no playable audio is left the video plays without sound and an alert says why (P14, P15). `AudioTranscoding` exists with no implementation. The spec's "TrueHD core" path (use the AC-3 core inside a TrueHD track) is NOT built: the engine does not extract the core. |
| Text subtitles | SRT, ASS (flattened to text, bold and italic kept) and WebVTT become WebVTT renditions in the system menu. System caption style applies (D5). |
| Picture subtitles | PGS only, through one custom menu "Picture Subtitles" (D1). After a jump into the middle of an epoch the first subtitle may be missing. VobSub is not supported and is reported. |
| Seeking | By the engine's seek map: any position maps to a segment that starts at a video keyframe. Tested for the map and the segment contents. |
| Picture in Picture | On (D3). Whether it keeps playing while the app is in the background is unverified (P32 to P35). Restoring the full screen from PiP is not handled (P33). |
| Playback Stats | Audio and picture status come from the same rules as before (`StatusRules`), now with the real file facts and the audio rendition in use. A note line lists left-out tracks. |
| Errors | Every file the engine cannot handle ends in a screen with the reason and a what-to-do line: unsupported video format, no video, laced blocks, encryption, compression, unusual file layout, damaged file, unreadable source, source gone, local connection failure, decoder rejection after hand-over, unsupported container. |
| Mark Intro, Recap, Credits | Menu entry wired to `PlayerMarkController` (the SEGMENTS agent's code). Skip button and Up Next are built from `ResolvedPlayback.segments` and marks made during playback. Never run. |

## Decisions and their alternatives (all PROVISIONAL)

- D1: text subtitles in the system menu only, picture subtitles in one custom menu, choosing one source turns the other off. Alternative: one merged menu (the system player does not allow replacing its subtitle menu).
- D3: Picture in Picture on for converted playback.
- D5: the system caption style is honoured; no `textStyleRules` override.
- D6: deployment target tvOS 27.0.
- No automatic choice of a picture subtitle track. Alternative: pick the default or forced track when no text track matches the preferred language.
- A file with no playable audio plays without sound plus an alert, instead of a refusal. Alternative: refuse the file.
- Dolby Vision profile 7 files play (as HDR10) instead of being refused.
- The loopback server uses plain HTTP on 127.0.0.1 with a random port and secret path prefix. `NSAllowsLocalNetworking` already in project.yml covers it; no ATS key was added.
- `.webm` goes to the engine, which refuses VP8, VP9 and AV1 with the codec named.
- Subtitle windows are read through the same window cache as the video without moving the read-ahead planner. Risk: the player may fetch every subtitle segment at the start (P22; `subtitleWindowLoads` counts it).

## Not done

- No decoder for DTS, TrueHD, Opus or Vorbis (needs a media library that is not linked; nothing downloaded). Order of preference stays FFmpegBuild, then MPVKit as the fallback engine.
- No Dolby Vision profile 7 conversion.
- No fallback engine, so no "fallback player" path and nothing that needs it (stats show the primary path only).
- HDR10+ is not identified; such a file is described as HDR10.
- No automatic quality or bitrate switching: the playlist has one variant.
- Picture in Picture restore, background audio modes, and interruption recovery are not built beyond the system defaults.
- Nothing in App/ compiled. The package builds and tests on Linux only.
