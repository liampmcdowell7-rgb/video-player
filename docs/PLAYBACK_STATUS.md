# Playback stats and honest status

Code: `Packages/VideoPlayerCore/Sources/PlaybackStatus` (pure Swift, tested in WSL). Covers FEATURE_BACKLOG Tier A items 11 (Playback Stats overlay), 12 (honest audio and video status), 13 (smooth transitions) and the "ARCHITECTURE: PLAYBACK" rules in the user's first message.

**What is tested and what is not.** The wording rules, the overlay formatting and the transition decisions are unit tested (see the end of this file). Reading the real values from tvOS (display modes, audio route) and drawing the overlay happen in the app target, which has never been compiled or run on a device. Everything marked UNVERIFIED needs a real Apple TV.

## Definitions (used in every line of text)

- **passthrough**: the app hands the stream to Apple's player unchanged. tvOS does not tell the app whether it then sends a bitstream to the TV or receiver, so the text only says "passthrough" when the output reports it takes Dolby bitstreams, or when that is unknown (a note then says so).
- **decoded**: turned into PCM audio, by the app, by Apple TV or by the fallback player.
- **base layer**: the layer of a Dolby Vision file that players without Dolby Vision can show (see below).
- **Atmos-capable**: the system reports Atmos rendering on the output. If it does not report it, the status says so; it never guesses "yes".

## Inputs and outputs

| Input (from the file) | Input (from the device) | Output |
|---|---|---|
| Audio: Dolby Digital, Digital Plus (± Atmos), TrueHD (± Atmos, ± Dolby Digital core), DTS, DTS-HD MA, DTS:X, AAC, FLAC, PCM, Opus; channel count | Audio route: kind (HDMI, Bluetooth, AirPlay, built-in, unknown), most channels, takes Dolby bitstream (yes / no / unknown), Atmos (yes / no / unknown) | Audio line, plus one plain sentence when something differs from the file |
| Video: SDR, HDR10, HDR10+, HLG, Dolby Vision 5, 7 (FEL, MEL), 8.1, 8.2, 8.4 | Display: which HDR modes it supports (or unknown), which mode it is in now (or unknown), Match Dynamic Range (yes / no / unknown), Apple TV model sends HDR10+ (yes / no / unknown, from the model identifier); Profile 7 conversion: available / not on this device / failed for this file | Video line, plus one plain sentence when something differs from the file |
| Engine: primary (Apple's player) or fallback (MPVKit) | | When fallback: "Dolby Vision and Atmos are unavailable in fallback mode." on every screen |

Dolby Vision base layers (from the Dolby Vision profile definitions; not re-read from Dolby documents in this run): Profile 5 none (not viewable without Dolby Vision), Profile 7 HDR10, Profile 8.1 HDR10, Profile 8.2 SDR, Profile 8.4 HLG.

## Rules in words

Audio, primary player:
1. Dolby Digital and Digital Plus are passed through. If the output cannot take Dolby bitstreams Apple TV decodes them (the text says so). If that is unknown the line still says passthrough, with a note that Apple TV decodes it if the output does not take it.
2. Digital Plus with Atmos shows "Dolby Atmos (passthrough)" only when the output reports Atmos. Otherwise it shows the codec and a note: the output does not support Atmos (only the channel bed plays), or Apple TV does not report whether Atmos is active.
3. TrueHD cannot be passed by Apple's player. With an AC-3 core the core is used and shown as Dolby Digital (the line says "TrueHD core" so the user sees where it came from; it is never labelled as TrueHD audio). Without a core it is decoded to PCM, up to 7.1, never more channels than the output accepts; downmixes are named in the line. TrueHD Atmos: the Atmos objects are not played (said in the note).
4. DTS, DTS-HD MA and DTS:X are decoded to PCM, 7.1 at most, downmixed when the output accepts fewer channels. DTS:X objects are not rendered (note).
5. AAC is passed through. FLAC and Opus are decoded to PCM by the app (PROVISIONAL, see Interpretations). PCM stays PCM.
6. If the output does not report its channel count the note says so and the file's channel count (max 7.1) is used.

Audio, fallback player: everything is decoded to PCM; the line never says passthrough; Dolby / DTS objects are not played (note).

Video, primary player:
1. The mode shown is the mode the display is expected to be in, unless the display reports the mode it is really in (then that mode is shown, and a note if it differs from the expected one).
2. A mode the display does not support is never shown. Unsupported HDR is tone-mapped to SDR (the text says so).
3. Dolby Vision on a display without Dolby Vision plays the base layer (named). Profile 5 has no base layer, so the line stays "Display mode: unknown" and the note warns that colors can look wrong.
4. Profile 7 is converted to 8.1 when the conversion is available and the display has Dolby Vision (docs/DOLBY_VISION.md). The note says what the conversion keeps: for FEL, the extra picture detail of the full enhancement layer is not shown; for MEL nothing is lost. FEL or MEL is read from the RPU, not from the configuration record. Otherwise the HDR10 base layer plays and the note gives the reason (not available on this device, failed for this file, or the display has no Dolby Vision).
5. HDR10+ (corrected 2026-11-17; the earlier "Apple TV does not report HDR10+ output" was unverified and wrong for newer models): support.apple.com/102339 says "HDR10+ is a supported format only on Apple TV 4K (3rd generation) and later". The display mode is HDR10 either way. On a 3rd generation or later model the line reads "HDR10+ or HDR10" (the metadata is sent; nothing reports whether the display uses it). On HD, 4K 1st and 2nd generation the line is HDR10 and the note says this model does not support HDR10+. When the model is not known, HDR10 with a note that the app could not tell. The HDR10+ metadata stays in the video samples unchanged.
6. Display abilities unknown: "Display mode: unknown" and one sentence why. SDR files stay "SDR".
7. Match Dynamic Range off: the display is not switched, so the line is the active mode if known, else "Display mode: unknown", with a note.

Video, fallback player: the fallback player never claims Dolby Vision or a confirmed display mode. HDR lines read "Display mode: unknown" unless the display reports its active mode; Dolby Vision files say which base layer plays.

## Wording decisions (edit the text in `AudioRules.swift`, `VideoRules.swift`, `Models.swift`, then regenerate the table)

Line grammar: passthrough `<Codec> <layout> (passthrough)`; core `Dolby Digital 5.1 (TrueHD core, passthrough)`; decoded `<layout> PCM (decoded[, downmixed from <layout>])`; decoded by Apple TV `<layout> PCM (decoded by Apple TV[, downmixed from …])`; Atmos `Dolby Atmos (passthrough)`; PCM source `<layout> PCM`. Layout names: Mono, Stereo, 3.0, 4.0, 5.0, 5.1, 6.1, 7.1, "N channels". Video line names: SDR, HDR10, HLG, Dolby Vision, "HDR10 (Dolby Vision base layer)", "HDR10 (base layer)" (Profile 7 not converted), "Dolby Vision (converted from Profile 7)", "HDR10+ or HDR10" (HDR10+ file on a model that sends HDR10+), "SDR (tone-mapped from HDR10)", "Display mode: unknown". Every other sentence is in the generated table below; the fallback notice is "Dolby Vision and Atmos are unavailable in fallback mode."

Notes are one sentence each. When two reasons apply they are joined into the same sentence with ", and" (see the rows for TrueHD with Atmos and for an unknown output).

## Playback Stats overlay

Order (most important first, all visible at once, no collapsed sections): Resolution, Frame rate, Video codec, Profile and level, HDR format, Bitrate (live), Bitrate (average), Audio codec, Audio channels, Audio output, Network throughput, Buffer health, Dropped frames, Decode path, then extras: Container, Pixel format, Color primaries, Transfer function, Player. The two status lines (audio, video) and the fallback notice are shown above the table (`StatsOverlay.statusLines`).

- Missing value: "—" (em dash), shown dimmed. Rows are never removed.
- File path: not in the overlay (long, private on a shared screen). File Details shows it. (Interpretation, PROVISIONAL.)
- Formatting does not use the device language: frame rates 23.976 / 24 / 29.97 / 59.94 / 119.88 with "." as separator; bitrate "45.2 Mbps", "640 kbps" (decimal, not 1024); resolution "3840 × 2160"; buffer "12.4 s"; dropped "12 of 15000 frames (0.08%)".
- Warning tone (PROVISIONAL numbers, none given by the user): throughput below the live bitrate; buffer under 5 s; dropped frames 0.5% or more.
- Decode path values: "Remux (Apple player)", "Direct (Apple player)", "Fallback player".

## Smooth transitions (item 13)

`Transitions.displayModeChange(from:to:availableHDR:…)` returns keep or change(reason). It compares the display mode each episode ends up in (not the file label), so HDR10 to HDR10+ keeps the mode, and Dolby Vision 8.1 on an HDR10-only display followed by HDR10 keeps it. Frame rates closer than 0.005 are equal; an unknown frame rate counts as equal. Different formats on a display with unknown abilities give change(displayUnknown). `NextEpisodePreparer` starts preparing the next episode once, when the credits start; when the credits are unknown, 30 s before the end (PROVISIONAL). Seeking back does not start it again. Whether tvOS really avoids a black screen when the mode is kept is UNVERIFIED (device test needed).

## Apple documentation checked (read on 2026-11-16)

- `AVPlayer.availableHDRModes` — https://developer.apple.com/documentation/avfoundation/avplayer/availablehdrmodes — **deprecated**, "use eligibleForHDRPlayback instead". It does not tell whether HDR video is playing or whether the video plays on an HDR display.
  #23 D: the app now reads `AVPlayer.eligibleForHDRPlayback` (https://developer.apple.com/documentation/avfoundation/avplayer/eligibleforhdrplayback) instead: `false` is an SDR display; `true` leaves the display's modes "not reported" (DisplayState.availableHDR nil).
- `AVPlayer.eligibleForHDRPlayback` — https://developer.apple.com/documentation/avfoundation/avplayer/eligibleforhdrplayback — a single Bool, not key-value observable. It cannot tell Dolby Vision from HDR10. So the app can only fill `DisplayState.availableHDR` with specific modes if the deprecated property (or another source) is used; otherwise it must pass nil ("unknown") and the status says so. This is the most important open item: decide which source the app uses (device test).
- `AVDisplayManager` — https://developer.apple.com/documentation/avkit/avdisplaymanager — `preferredDisplayCriteria`, `isDisplayCriteriaMatchingEnabled` (the user's Match Content setting), `isDisplayModeSwitchInProgress`. It documents the switch request, not which mode the TV ended up in.
- `AVAudioSession.maximumOutputNumberOfChannels` — https://developer.apple.com/documentation/avfaudio/avaudiosession/maximumoutputnumberofchannels — max channels of the current route (tvOS 9+). Not documented as proof that a bitstream is accepted; that is why `passesDolbyBitstream` is separate and 2 channels over HDMI is "unknown", not "no".
- `AVAudioSession.renderingMode` — https://developer.apple.com/documentation/avfaudio/avaudiosession/renderingmode-swift.property — tvOS 17.2+, but `notApplicable` unless the port is car audio or (iOS 18+) AirPlay, and only while AVPlayer or AVSampleBufferAudioRenderer plays. **For HDMI it is documented as not applicable, so Apple TV probably cannot report Atmos on an HDMI output** (UNVERIFIED on a device). Consequence: on HDMI the status will usually read "Apple TV does not report whether Dolby Atmos is active on this output", and "Dolby Atmos (passthrough)" appears only if some source confirms it. The rules honour that on purpose.

## UNVERIFIED (needs an Apple TV)

1. Which API gives per-mode display support (see above) and whether Dolby Vision support can be read at all.
2. Whether Atmos can be confirmed on HDMI; what `maximumOutputNumberOfChannels` reports behind ARC / eARC / a receiver.
3. Whether tvOS passes Dolby Digital Plus (and JOC) to the sink as a bitstream when AVPlayer plays the remuxed stream, and what it does when the sink refuses it ("Apple TV decodes it" is an assumption).
4. HDR10+ on Apple TV 4K (3rd generation) and later with the remuxed stream: whether AVPlayer passes the in-stream HDR10+ metadata to an HDR10+ TV (Apple's page says the format is supported; the remux path is not proven). See docs/DEVICE_TEST_CHECKLIST_DOLBYVISION.md.
5. What the fallback player (MPVKit) really sends to the display; the fallback rows are assumptions.
6. Tone-mapping to SDR on a display without HDR (assumed to be done by Apple TV / AVPlayer).
7. The Dolby Vision base layer list (from the Dolby profile definitions, not re-read from Dolby documents this run).
8. Black-screen behavior between episodes when the display mode is kept.

## Interpretations (PROVISIONAL, the spec was silent)

- FLAC and Opus are decoded to PCM by the app so Apple's player never has to open them. (The spike on repackaging decoded audio decides the real container.)
- "Passthrough" is shown for AAC although Apple's player decodes it; it means "unchanged to Apple's player", as for Dolby.
- TrueHD with a core is shown as Dolby Digital with "TrueHD core" in brackets, to be honest about where it came from while not labelling the audio as TrueHD.
- Atmos on an output whose Atmos support is unknown shows the codec (Dolby Digital Plus 7.1) with a note, never "Atmos".
- An active display mode reported by the system overrides the expected one.
- The overlay thresholds and the 30 s lead time above.

## Tests

`ExpectedRowsTests` (hand-written expected text for every required case in the brief, independent of the generator), `PropertyTests` (honesty rules checked over every generated row: no Atmos unless confirmed, no passthrough in fallback or for TrueHD without core / DTS, no DV or HDR mode the display lacks, channels never above the route, downmix always named, one sentence per note), `GoldenTests` (generated table equals the golden copy row for row), `StatsOverlayTests`, `TransitionTests`. `scripts/playback-status-doc.sh` checks that the table below equals the golden copy; add it to `scripts/test-all.sh`.

To change wording: edit the rules, then run `VP_UPDATE_GOLDEN=1 VP_REPO_ROOT=<repo root> swift test --filter GoldenTests` in `Packages/VideoPlayerCore`. It rewrites the golden file and this table and fails once on purpose; run the tests again.

## The complete table (generated)

Row ids are stable only while the lists in `StatusTable.swift` do not change.

<!-- RULES-TABLE-BEGIN (generated, do not edit by hand) -->

### Audio rules

| ID | File audio | Audio output | Player | Audio line | Why (shown when present) |
|---|---|---|---|---|---|
| A001 | Dolby Digital 5.1 | HDMI 7.1, Atmos active | Primary player | Dolby Digital 5.1 (passthrough) | — |
| A002 | Dolby Digital 5.1 | HDMI 7.1, Atmos not reported | Primary player | Dolby Digital 5.1 (passthrough) | — |
| A003 | Dolby Digital 5.1 | HDMI 7.1, no Atmos | Primary player | Dolby Digital 5.1 (passthrough) | — |
| A004 | Dolby Digital 5.1 | HDMI 5.1 | Primary player | Dolby Digital 5.1 (passthrough) | — |
| A005 | Dolby Digital 5.1 | HDMI stereo (TV or ARC) | Primary player | Dolby Digital 5.1 (passthrough) | Apple TV does not report whether this output takes Dolby Digital, and decodes it if it does not. |
| A006 | Dolby Digital 5.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded by Apple TV, downmixed from 5.1) | This audio output cannot take Dolby Digital, so Apple TV decodes it to PCM. |
| A007 | Dolby Digital 5.1 | Unknown output | Primary player | Dolby Digital 5.1 (passthrough) | Apple TV does not report whether this output takes Dolby Digital, and decodes it if it does not. |
| A008 | Dolby Digital Plus 5.1 | HDMI 7.1, Atmos active | Primary player | Dolby Digital Plus 5.1 (passthrough) | — |
| A009 | Dolby Digital Plus 5.1 | HDMI 7.1, Atmos not reported | Primary player | Dolby Digital Plus 5.1 (passthrough) | — |
| A010 | Dolby Digital Plus 5.1 | HDMI 7.1, no Atmos | Primary player | Dolby Digital Plus 5.1 (passthrough) | — |
| A011 | Dolby Digital Plus 5.1 | HDMI 5.1 | Primary player | Dolby Digital Plus 5.1 (passthrough) | — |
| A012 | Dolby Digital Plus 5.1 | HDMI stereo (TV or ARC) | Primary player | Dolby Digital Plus 5.1 (passthrough) | Apple TV does not report whether this output takes Dolby Digital Plus, and decodes it if it does not. |
| A013 | Dolby Digital Plus 5.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded by Apple TV, downmixed from 5.1) | This audio output cannot take Dolby Digital Plus, so Apple TV decodes it to PCM. |
| A014 | Dolby Digital Plus 5.1 | Unknown output | Primary player | Dolby Digital Plus 5.1 (passthrough) | Apple TV does not report whether this output takes Dolby Digital Plus, and decodes it if it does not. |
| A015 | Dolby Digital Plus with Atmos 7.1 | HDMI 7.1, Atmos active | Primary player | Dolby Atmos (passthrough) | — |
| A016 | Dolby Digital Plus with Atmos 7.1 | HDMI 7.1, Atmos not reported | Primary player | Dolby Digital Plus 7.1 (passthrough) | Apple TV does not report whether Dolby Atmos is active on this output. |
| A017 | Dolby Digital Plus with Atmos 7.1 | HDMI 7.1, no Atmos | Primary player | Dolby Digital Plus 7.1 (passthrough) | This audio output does not support Dolby Atmos, so only the channel bed plays. |
| A018 | Dolby Digital Plus with Atmos 7.1 | HDMI 5.1 | Primary player | Dolby Digital Plus 7.1 (passthrough) | This audio output does not support Dolby Atmos, so only the channel bed plays. |
| A019 | Dolby Digital Plus with Atmos 7.1 | HDMI stereo (TV or ARC) | Primary player | Dolby Digital Plus 7.1 (passthrough) | Apple TV does not report whether Dolby Atmos is active on this output. |
| A020 | Dolby Digital Plus with Atmos 7.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded by Apple TV, downmixed from 7.1) | This audio output cannot take Dolby Digital Plus, so Apple TV decodes it to PCM, and the Atmos objects are not played. |
| A021 | Dolby Digital Plus with Atmos 7.1 | Unknown output | Primary player | Dolby Digital Plus 7.1 (passthrough) | Apple TV does not report whether Dolby Atmos is active on this output. |
| A022 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos active | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A023 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos not reported | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A024 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, no Atmos | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A025 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 5.1 | Primary player | 5.1 PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A026 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A027 | Dolby TrueHD 7.1 (with Dolby Digital core) | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A028 | Dolby TrueHD 7.1 (with Dolby Digital core) | Unknown output | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the number of channels this output supports is unknown. |
| A029 | Dolby TrueHD 7.1 | HDMI 7.1, Atmos active | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A030 | Dolby TrueHD 7.1 | HDMI 7.1, Atmos not reported | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A031 | Dolby TrueHD 7.1 | HDMI 7.1, no Atmos | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A032 | Dolby TrueHD 7.1 | HDMI 5.1 | Primary player | 5.1 PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A033 | Dolby TrueHD 7.1 | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A034 | Dolby TrueHD 7.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM. |
| A035 | Dolby TrueHD 7.1 | Unknown output | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the number of channels this output supports is unknown. |
| A036 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos active | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A037 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos not reported | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A038 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, no Atmos | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A039 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 5.1 | Primary player | 5.1 PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A040 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A041 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A042 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | Unknown output | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, the Atmos objects are not played, only the 7.1 bed and the number of channels this output supports is unknown. |
| A043 | Dolby TrueHD with Atmos 7.1 | HDMI 7.1, Atmos active | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A044 | Dolby TrueHD with Atmos 7.1 | HDMI 7.1, Atmos not reported | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A045 | Dolby TrueHD with Atmos 7.1 | HDMI 7.1, no Atmos | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A046 | Dolby TrueHD with Atmos 7.1 | HDMI 5.1 | Primary player | 5.1 PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A047 | Dolby TrueHD with Atmos 7.1 | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A048 | Dolby TrueHD with Atmos 7.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed. |
| A049 | Dolby TrueHD with Atmos 7.1 | Unknown output | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, the Atmos objects are not played, only the 7.1 bed and the number of channels this output supports is unknown. |
| A050 | DTS 5.1 | HDMI 7.1, Atmos active | Primary player | 5.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A051 | DTS 5.1 | HDMI 7.1, Atmos not reported | Primary player | 5.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A052 | DTS 5.1 | HDMI 7.1, no Atmos | Primary player | 5.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A053 | DTS 5.1 | HDMI 5.1 | Primary player | 5.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A054 | DTS 5.1 | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded, downmixed from 5.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A055 | DTS 5.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded, downmixed from 5.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A056 | DTS 5.1 | Unknown output | Primary player | 5.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the number of channels this output supports is unknown. |
| A057 | DTS-HD Master Audio 7.1 | HDMI 7.1, Atmos active | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A058 | DTS-HD Master Audio 7.1 | HDMI 7.1, Atmos not reported | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A059 | DTS-HD Master Audio 7.1 | HDMI 7.1, no Atmos | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A060 | DTS-HD Master Audio 7.1 | HDMI 5.1 | Primary player | 5.1 PCM (decoded, downmixed from 7.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A061 | DTS-HD Master Audio 7.1 | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A062 | DTS-HD Master Audio 7.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A063 | DTS-HD Master Audio 7.1 | Unknown output | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the number of channels this output supports is unknown. |
| A064 | DTS:X 7.1 | HDMI 7.1, Atmos active | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the DTS:X objects are not rendered, only the 7.1 bed plays. |
| A065 | DTS:X 7.1 | HDMI 7.1, Atmos not reported | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the DTS:X objects are not rendered, only the 7.1 bed plays. |
| A066 | DTS:X 7.1 | HDMI 7.1, no Atmos | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the DTS:X objects are not rendered, only the 7.1 bed plays. |
| A067 | DTS:X 7.1 | HDMI 5.1 | Primary player | 5.1 PCM (decoded, downmixed from 7.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the DTS:X objects are not rendered, only the 7.1 bed plays. |
| A068 | DTS:X 7.1 | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the DTS:X objects are not rendered, only the 7.1 bed plays. |
| A069 | DTS:X 7.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the DTS:X objects are not rendered, only the 7.1 bed plays. |
| A070 | DTS:X 7.1 | Unknown output | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, the DTS:X objects are not rendered, only the 7.1 bed plays and the number of channels this output supports is unknown. |
| A071 | AAC Stereo | HDMI 7.1, Atmos active | Primary player | AAC Stereo (passthrough) | — |
| A072 | AAC Stereo | HDMI 7.1, Atmos not reported | Primary player | AAC Stereo (passthrough) | — |
| A073 | AAC Stereo | HDMI 7.1, no Atmos | Primary player | AAC Stereo (passthrough) | — |
| A074 | AAC Stereo | HDMI 5.1 | Primary player | AAC Stereo (passthrough) | — |
| A075 | AAC Stereo | HDMI stereo (TV or ARC) | Primary player | AAC Stereo (passthrough) | — |
| A076 | AAC Stereo | Bluetooth or AirPlay stereo | Primary player | AAC Stereo (passthrough) | — |
| A077 | AAC Stereo | Unknown output | Primary player | AAC Stereo (passthrough) | — |
| A078 | FLAC Stereo | HDMI 7.1, Atmos active | Primary player | Stereo PCM (decoded) | — |
| A079 | FLAC Stereo | HDMI 7.1, Atmos not reported | Primary player | Stereo PCM (decoded) | — |
| A080 | FLAC Stereo | HDMI 7.1, no Atmos | Primary player | Stereo PCM (decoded) | — |
| A081 | FLAC Stereo | HDMI 5.1 | Primary player | Stereo PCM (decoded) | — |
| A082 | FLAC Stereo | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded) | — |
| A083 | FLAC Stereo | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded) | — |
| A084 | FLAC Stereo | Unknown output | Primary player | Stereo PCM (decoded) | — |
| A085 | PCM Stereo | HDMI 7.1, Atmos active | Primary player | Stereo PCM | — |
| A086 | PCM Stereo | HDMI 7.1, Atmos not reported | Primary player | Stereo PCM | — |
| A087 | PCM Stereo | HDMI 7.1, no Atmos | Primary player | Stereo PCM | — |
| A088 | PCM Stereo | HDMI 5.1 | Primary player | Stereo PCM | — |
| A089 | PCM Stereo | HDMI stereo (TV or ARC) | Primary player | Stereo PCM | — |
| A090 | PCM Stereo | Bluetooth or AirPlay stereo | Primary player | Stereo PCM | — |
| A091 | PCM Stereo | Unknown output | Primary player | Stereo PCM | — |
| A092 | Opus Stereo | HDMI 7.1, Atmos active | Primary player | Stereo PCM (decoded) | — |
| A093 | Opus Stereo | HDMI 7.1, Atmos not reported | Primary player | Stereo PCM (decoded) | — |
| A094 | Opus Stereo | HDMI 7.1, no Atmos | Primary player | Stereo PCM (decoded) | — |
| A095 | Opus Stereo | HDMI 5.1 | Primary player | Stereo PCM (decoded) | — |
| A096 | Opus Stereo | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded) | — |
| A097 | Opus Stereo | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded) | — |
| A098 | Opus Stereo | Unknown output | Primary player | Stereo PCM (decoded) | — |
| A099 | Dolby Digital 5.1 | HDMI 7.1, Atmos active | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A100 | Dolby Digital 5.1 | HDMI 7.1, Atmos not reported | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A101 | Dolby Digital 5.1 | HDMI 7.1, no Atmos | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A102 | Dolby Digital 5.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A103 | Dolby Digital 5.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 5.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A104 | Dolby Digital 5.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 5.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A105 | Dolby Digital 5.1 | Unknown output | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the number of channels this output supports is unknown. |
| A106 | Dolby Digital Plus 5.1 | HDMI 7.1, Atmos active | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A107 | Dolby Digital Plus 5.1 | HDMI 7.1, Atmos not reported | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A108 | Dolby Digital Plus 5.1 | HDMI 7.1, no Atmos | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A109 | Dolby Digital Plus 5.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A110 | Dolby Digital Plus 5.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 5.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A111 | Dolby Digital Plus 5.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 5.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A112 | Dolby Digital Plus 5.1 | Unknown output | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the number of channels this output supports is unknown. |
| A113 | Dolby Digital Plus with Atmos 7.1 | HDMI 7.1, Atmos active | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A114 | Dolby Digital Plus with Atmos 7.1 | HDMI 7.1, Atmos not reported | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A115 | Dolby Digital Plus with Atmos 7.1 | HDMI 7.1, no Atmos | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A116 | Dolby Digital Plus with Atmos 7.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A117 | Dolby Digital Plus with Atmos 7.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A118 | Dolby Digital Plus with Atmos 7.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A119 | Dolby Digital Plus with Atmos 7.1 | Unknown output | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, the Atmos objects are not played and the number of channels this output supports is unknown. |
| A120 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos active | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A121 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos not reported | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A122 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, no Atmos | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A123 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 5.1 | Fallback player | 5.1 PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A124 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A125 | Dolby TrueHD 7.1 (with Dolby Digital core) | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A126 | Dolby TrueHD 7.1 (with Dolby Digital core) | Unknown output | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the number of channels this output supports is unknown. |
| A127 | Dolby TrueHD 7.1 | HDMI 7.1, Atmos active | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A128 | Dolby TrueHD 7.1 | HDMI 7.1, Atmos not reported | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A129 | Dolby TrueHD 7.1 | HDMI 7.1, no Atmos | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A130 | Dolby TrueHD 7.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A131 | Dolby TrueHD 7.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A132 | Dolby TrueHD 7.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A133 | Dolby TrueHD 7.1 | Unknown output | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the number of channels this output supports is unknown. |
| A134 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos active | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A135 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos not reported | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A136 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, no Atmos | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A137 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 5.1 | Fallback player | 5.1 PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A138 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A139 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A140 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | Unknown output | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, the Atmos objects are not played and the number of channels this output supports is unknown. |
| A141 | Dolby TrueHD with Atmos 7.1 | HDMI 7.1, Atmos active | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A142 | Dolby TrueHD with Atmos 7.1 | HDMI 7.1, Atmos not reported | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A143 | Dolby TrueHD with Atmos 7.1 | HDMI 7.1, no Atmos | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A144 | Dolby TrueHD with Atmos 7.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A145 | Dolby TrueHD with Atmos 7.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A146 | Dolby TrueHD with Atmos 7.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A147 | Dolby TrueHD with Atmos 7.1 | Unknown output | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, the Atmos objects are not played and the number of channels this output supports is unknown. |
| A148 | DTS 5.1 | HDMI 7.1, Atmos active | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A149 | DTS 5.1 | HDMI 7.1, Atmos not reported | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A150 | DTS 5.1 | HDMI 7.1, no Atmos | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A151 | DTS 5.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A152 | DTS 5.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 5.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A153 | DTS 5.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 5.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A154 | DTS 5.1 | Unknown output | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the number of channels this output supports is unknown. |
| A155 | DTS-HD Master Audio 7.1 | HDMI 7.1, Atmos active | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A156 | DTS-HD Master Audio 7.1 | HDMI 7.1, Atmos not reported | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A157 | DTS-HD Master Audio 7.1 | HDMI 7.1, no Atmos | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A158 | DTS-HD Master Audio 7.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A159 | DTS-HD Master Audio 7.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A160 | DTS-HD Master Audio 7.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A161 | DTS-HD Master Audio 7.1 | Unknown output | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the number of channels this output supports is unknown. |
| A162 | DTS:X 7.1 | HDMI 7.1, Atmos active | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the DTS:X objects are not rendered. |
| A163 | DTS:X 7.1 | HDMI 7.1, Atmos not reported | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the DTS:X objects are not rendered. |
| A164 | DTS:X 7.1 | HDMI 7.1, no Atmos | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the DTS:X objects are not rendered. |
| A165 | DTS:X 7.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the DTS:X objects are not rendered. |
| A166 | DTS:X 7.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the DTS:X objects are not rendered. |
| A167 | DTS:X 7.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the DTS:X objects are not rendered. |
| A168 | DTS:X 7.1 | Unknown output | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, the DTS:X objects are not rendered and the number of channels this output supports is unknown. |
| A169 | AAC Stereo | HDMI 7.1, Atmos active | Fallback player | Stereo PCM (decoded) | — |
| A170 | AAC Stereo | HDMI 7.1, Atmos not reported | Fallback player | Stereo PCM (decoded) | — |
| A171 | AAC Stereo | HDMI 7.1, no Atmos | Fallback player | Stereo PCM (decoded) | — |
| A172 | AAC Stereo | HDMI 5.1 | Fallback player | Stereo PCM (decoded) | — |
| A173 | AAC Stereo | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded) | — |
| A174 | AAC Stereo | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded) | — |
| A175 | AAC Stereo | Unknown output | Fallback player | Stereo PCM (decoded) | The fallback player decodes all audio to PCM, and the number of channels this output supports is unknown. |
| A176 | FLAC Stereo | HDMI 7.1, Atmos active | Fallback player | Stereo PCM (decoded) | — |
| A177 | FLAC Stereo | HDMI 7.1, Atmos not reported | Fallback player | Stereo PCM (decoded) | — |
| A178 | FLAC Stereo | HDMI 7.1, no Atmos | Fallback player | Stereo PCM (decoded) | — |
| A179 | FLAC Stereo | HDMI 5.1 | Fallback player | Stereo PCM (decoded) | — |
| A180 | FLAC Stereo | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded) | — |
| A181 | FLAC Stereo | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded) | — |
| A182 | FLAC Stereo | Unknown output | Fallback player | Stereo PCM (decoded) | The fallback player decodes all audio to PCM, and the number of channels this output supports is unknown. |
| A183 | PCM Stereo | HDMI 7.1, Atmos active | Fallback player | Stereo PCM | — |
| A184 | PCM Stereo | HDMI 7.1, Atmos not reported | Fallback player | Stereo PCM | — |
| A185 | PCM Stereo | HDMI 7.1, no Atmos | Fallback player | Stereo PCM | — |
| A186 | PCM Stereo | HDMI 5.1 | Fallback player | Stereo PCM | — |
| A187 | PCM Stereo | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM | — |
| A188 | PCM Stereo | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM | — |
| A189 | PCM Stereo | Unknown output | Fallback player | Stereo PCM | — |
| A190 | Opus Stereo | HDMI 7.1, Atmos active | Fallback player | Stereo PCM (decoded) | — |
| A191 | Opus Stereo | HDMI 7.1, Atmos not reported | Fallback player | Stereo PCM (decoded) | — |
| A192 | Opus Stereo | HDMI 7.1, no Atmos | Fallback player | Stereo PCM (decoded) | — |
| A193 | Opus Stereo | HDMI 5.1 | Fallback player | Stereo PCM (decoded) | — |
| A194 | Opus Stereo | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded) | — |
| A195 | Opus Stereo | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded) | — |
| A196 | Opus Stereo | Unknown output | Fallback player | Stereo PCM (decoded) | The fallback player decodes all audio to PCM, and the number of channels this output supports is unknown. |
| A197 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos active | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used. |
| A198 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos not reported | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used. |
| A199 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, no Atmos | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used. |
| A200 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 5.1 | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used. |
| A201 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI stereo (TV or ARC) | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and Apple TV does not report whether this output takes Dolby Digital. |
| A202 | Dolby TrueHD 7.1 (with Dolby Digital core) | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (Dolby Digital core, decoded by Apple TV, downmixed from 5.1) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and this output cannot take Dolby Digital so Apple TV decodes it to PCM. |
| A203 | Dolby TrueHD 7.1 (with Dolby Digital core) | Unknown output | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and Apple TV does not report whether this output takes Dolby Digital. |
| A204 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos active | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and the Atmos objects are not played. |
| A205 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos not reported | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and the Atmos objects are not played. |
| A206 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, no Atmos | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and the Atmos objects are not played. |
| A207 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 5.1 | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and the Atmos objects are not played. |
| A208 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI stereo (TV or ARC) | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, the Atmos objects are not played and Apple TV does not report whether this output takes Dolby Digital. |
| A209 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (Dolby Digital core, decoded by Apple TV, downmixed from 5.1) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and this output cannot take Dolby Digital so Apple TV decodes it to PCM, and the Atmos objects are not played. |
| A210 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | Unknown output | Primary player | Dolby Digital 5.1 (TrueHD core, passthrough) | Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, the Atmos objects are not played and Apple TV does not report whether this output takes Dolby Digital. |
| A211 | DTS-HD High Resolution 5.1 | HDMI 7.1, Atmos active | Primary player | 5.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A212 | DTS-HD High Resolution 5.1 | HDMI 7.1, Atmos not reported | Primary player | 5.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A213 | DTS-HD High Resolution 5.1 | HDMI 7.1, no Atmos | Primary player | 5.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A214 | DTS-HD High Resolution 5.1 | HDMI 5.1 | Primary player | 5.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A215 | DTS-HD High Resolution 5.1 | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded, downmixed from 5.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A216 | DTS-HD High Resolution 5.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded, downmixed from 5.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM. |
| A217 | DTS-HD High Resolution 5.1 | Unknown output | Primary player | 5.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the number of channels this output supports is unknown. |
| A218 | DTS-HD Master Audio 7.1 | HDMI 7.1, Atmos active | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the system does not report whether this output receives the full 96 kHz. |
| A219 | DTS-HD Master Audio 7.1 | HDMI 7.1, Atmos not reported | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the system does not report whether this output receives the full 96 kHz. |
| A220 | DTS-HD Master Audio 7.1 | HDMI 7.1, no Atmos | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the system does not report whether this output receives the full 96 kHz. |
| A221 | DTS-HD Master Audio 7.1 | HDMI 5.1 | Primary player | 5.1 PCM (decoded, downmixed from 7.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the system does not report whether this output receives the full 96 kHz. |
| A222 | DTS-HD Master Audio 7.1 | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the system does not report whether this output receives the full 96 kHz. |
| A223 | DTS-HD Master Audio 7.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded, downmixed from 7.1) | Apple's player cannot pass DTS audio, so it is decoded to PCM, and the system does not report whether this output receives the full 96 kHz. |
| A224 | DTS-HD Master Audio 7.1 | Unknown output | Primary player | 7.1 PCM (decoded) | Apple's player cannot pass DTS audio, so it is decoded to PCM, the number of channels this output supports is unknown and the system does not report whether this output receives the full 96 kHz. |
| A225 | Vorbis 5.1 | HDMI 7.1, Atmos active | Primary player | 5.1 PCM (decoded) | — |
| A226 | Vorbis 5.1 | HDMI 7.1, Atmos not reported | Primary player | 5.1 PCM (decoded) | — |
| A227 | Vorbis 5.1 | HDMI 7.1, no Atmos | Primary player | 5.1 PCM (decoded) | — |
| A228 | Vorbis 5.1 | HDMI 5.1 | Primary player | 5.1 PCM (decoded) | — |
| A229 | Vorbis 5.1 | HDMI stereo (TV or ARC) | Primary player | Stereo PCM (decoded, downmixed from 5.1) | — |
| A230 | Vorbis 5.1 | Bluetooth or AirPlay stereo | Primary player | Stereo PCM (decoded, downmixed from 5.1) | — |
| A231 | Vorbis 5.1 | Unknown output | Primary player | 5.1 PCM (decoded) | The number of channels this output supports is unknown. |
| A232 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos active | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A233 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos not reported | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A234 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 7.1, no Atmos | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A235 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI 5.1 | Fallback player | 5.1 PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A236 | Dolby TrueHD 7.1 (with Dolby Digital core) | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A237 | Dolby TrueHD 7.1 (with Dolby Digital core) | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable. |
| A238 | Dolby TrueHD 7.1 (with Dolby Digital core) | Unknown output | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the number of channels this output supports is unknown. |
| A239 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos active | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A240 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, Atmos not reported | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A241 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 7.1, no Atmos | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A242 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI 5.1 | Fallback player | 5.1 PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A243 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A244 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played. |
| A245 | Dolby TrueHD with Atmos 7.1 (with Dolby Digital core) | Unknown output | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, the Atmos objects are not played and the number of channels this output supports is unknown. |
| A246 | DTS-HD High Resolution 5.1 | HDMI 7.1, Atmos active | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A247 | DTS-HD High Resolution 5.1 | HDMI 7.1, Atmos not reported | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A248 | DTS-HD High Resolution 5.1 | HDMI 7.1, no Atmos | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A249 | DTS-HD High Resolution 5.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A250 | DTS-HD High Resolution 5.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 5.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A251 | DTS-HD High Resolution 5.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 5.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A252 | DTS-HD High Resolution 5.1 | Unknown output | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the number of channels this output supports is unknown. |
| A253 | DTS-HD Master Audio 7.1 | HDMI 7.1, Atmos active | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A254 | DTS-HD Master Audio 7.1 | HDMI 7.1, Atmos not reported | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A255 | DTS-HD Master Audio 7.1 | HDMI 7.1, no Atmos | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A256 | DTS-HD Master Audio 7.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A257 | DTS-HD Master Audio 7.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A258 | DTS-HD Master Audio 7.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 7.1) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable. |
| A259 | DTS-HD Master Audio 7.1 | Unknown output | Fallback player | 7.1 PCM (decoded) | The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the number of channels this output supports is unknown. |
| A260 | Vorbis 5.1 | HDMI 7.1, Atmos active | Fallback player | 5.1 PCM (decoded) | — |
| A261 | Vorbis 5.1 | HDMI 7.1, Atmos not reported | Fallback player | 5.1 PCM (decoded) | — |
| A262 | Vorbis 5.1 | HDMI 7.1, no Atmos | Fallback player | 5.1 PCM (decoded) | — |
| A263 | Vorbis 5.1 | HDMI 5.1 | Fallback player | 5.1 PCM (decoded) | — |
| A264 | Vorbis 5.1 | HDMI stereo (TV or ARC) | Fallback player | Stereo PCM (decoded, downmixed from 5.1) | — |
| A265 | Vorbis 5.1 | Bluetooth or AirPlay stereo | Fallback player | Stereo PCM (decoded, downmixed from 5.1) | — |
| A266 | Vorbis 5.1 | Unknown output | Fallback player | 5.1 PCM (decoded) | The fallback player decodes all audio to PCM, and the number of channels this output supports is unknown. |

### Video and HDR rules

| ID | File video | Display | Player | Video line | Why (shown when present) |
|---|---|---|---|---|---|
| V001 | SDR | Dolby Vision, HDR10 and HLG display | Primary player | SDR | — |
| V002 | SDR | HDR10 and HLG display | Primary player | SDR | — |
| V003 | SDR | HLG-only display | Primary player | SDR | — |
| V004 | SDR | SDR display | Primary player | SDR | — |
| V005 | SDR | Display abilities unknown | Primary player | SDR | — |
| V006 | SDR | HDR10 display, Match Dynamic Range off | Primary player | SDR | — |
| V007 | SDR | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 | The display is in HDR10 mode, not SDR. |
| V008 | SDR | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | The display is in HDR10 mode, not SDR. |
| V009 | HDR10 | Dolby Vision, HDR10 and HLG display | Primary player | HDR10 | — |
| V010 | HDR10 | HDR10 and HLG display | Primary player | HDR10 | — |
| V011 | HDR10 | HLG-only display | Primary player | SDR (tone-mapped from HDR10) | This display does not support HDR10, so the picture is tone-mapped to SDR. |
| V012 | HDR10 | SDR display | Primary player | SDR (tone-mapped from HDR10) | This display does not support HDR10, so the picture is tone-mapped to SDR. |
| V013 | HDR10 | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V014 | HDR10 | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V015 | HDR10 | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 | — |
| V016 | HDR10 | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V017 | HDR10+ | Dolby Vision, HDR10 and HLG display | Primary player | HDR10 | The app could not tell whether this Apple TV model sends HDR10+ metadata, so this is shown as HDR10. |
| V018 | HDR10+ | HDR10 and HLG display | Primary player | HDR10 | The app could not tell whether this Apple TV model sends HDR10+ metadata, so this is shown as HDR10. |
| V019 | HDR10+ | HLG-only display | Primary player | SDR (tone-mapped from HDR10) | This display does not support HDR10, so the picture is tone-mapped to SDR. |
| V020 | HDR10+ | SDR display | Primary player | SDR (tone-mapped from HDR10) | This display does not support HDR10, so the picture is tone-mapped to SDR. |
| V021 | HDR10+ | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V022 | HDR10+ | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V023 | HDR10+ | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 | The app could not tell whether this Apple TV model sends HDR10+ metadata, so this is shown as HDR10. |
| V024 | HDR10+ | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V025 | HLG | Dolby Vision, HDR10 and HLG display | Primary player | HLG | — |
| V026 | HLG | HDR10 and HLG display | Primary player | HLG | — |
| V027 | HLG | HLG-only display | Primary player | HLG | — |
| V028 | HLG | SDR display | Primary player | SDR (tone-mapped from HLG) | This display does not support HLG, so the picture is tone-mapped to SDR. |
| V029 | HLG | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V030 | HLG | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V031 | HLG | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 | The display is in HDR10 mode, not HLG. |
| V032 | HLG | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V033 | Dolby Vision Profile 5 | Dolby Vision, HDR10 and HLG display | Primary player | Dolby Vision | — |
| V034 | Dolby Vision Profile 5 | HDR10 and HLG display | Primary player | Display mode: unknown | Dolby Vision Profile 5 has no HDR10 layer, so colors can look wrong on a display without Dolby Vision. |
| V035 | Dolby Vision Profile 5 | HLG-only display | Primary player | Display mode: unknown | Dolby Vision Profile 5 has no HDR10 layer, so colors can look wrong on a display without Dolby Vision. |
| V036 | Dolby Vision Profile 5 | SDR display | Primary player | Display mode: unknown | Dolby Vision Profile 5 has no HDR10 layer, so colors can look wrong on a display without Dolby Vision. |
| V037 | Dolby Vision Profile 5 | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V038 | Dolby Vision Profile 5 | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V039 | Dolby Vision Profile 5 | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 | The display is in HDR10 mode, not Dolby Vision. |
| V040 | Dolby Vision Profile 5 | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V041 | Dolby Vision Profile 7 (FEL), conversion available | Dolby Vision, HDR10 and HLG display | Primary player | Dolby Vision (converted from Profile 7) | Profile 7 is converted to Profile 8.1, so the extra picture detail in its full enhancement layer (FEL) is not shown and the 10-bit base layer plays with the Dolby Vision metadata. |
| V042 | Dolby Vision Profile 7 (FEL), conversion available | HDR10 and HLG display | Primary player | HDR10 (base layer) | This display does not support Dolby Vision, so the HDR10 base layer plays. |
| V043 | Dolby Vision Profile 7 (FEL), conversion available | HLG-only display | Primary player | SDR (tone-mapped from HDR10) | This display does not support Dolby Vision, so the HDR10 base layer is tone-mapped to SDR. |
| V044 | Dolby Vision Profile 7 (FEL), conversion available | SDR display | Primary player | SDR (tone-mapped from HDR10) | This display does not support Dolby Vision, so the HDR10 base layer is tone-mapped to SDR. |
| V045 | Dolby Vision Profile 7 (FEL), conversion available | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V046 | Dolby Vision Profile 7 (FEL), conversion available | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V047 | Dolby Vision Profile 7 (FEL), conversion available | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 | The display is in HDR10 mode, not Dolby Vision. |
| V048 | Dolby Vision Profile 7 (FEL), conversion available | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V049 | Dolby Vision Profile 7 (FEL), conversion not available on this device | Dolby Vision, HDR10 and HLG display | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer plays. |
| V050 | Dolby Vision Profile 7 (FEL), conversion not available on this device | HDR10 and HLG display | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer plays. |
| V051 | Dolby Vision Profile 7 (FEL), conversion not available on this device | HLG-only display | Primary player | SDR (tone-mapped from HDR10) | Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer is tone-mapped to SDR. |
| V052 | Dolby Vision Profile 7 (FEL), conversion not available on this device | SDR display | Primary player | SDR (tone-mapped from HDR10) | Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer is tone-mapped to SDR. |
| V053 | Dolby Vision Profile 7 (FEL), conversion not available on this device | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports, and Dolby Vision Profile 7 conversion is not available on this device. |
| V054 | Dolby Vision Profile 7 (FEL), conversion not available on this device | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V055 | Dolby Vision Profile 7 (FEL), conversion not available on this device | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer plays. |
| V056 | Dolby Vision Profile 7 (FEL), conversion not available on this device | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V057 | Dolby Vision Profile 7 (FEL), conversion failed for this file | Dolby Vision, HDR10 and HLG display | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer plays. |
| V058 | Dolby Vision Profile 7 (FEL), conversion failed for this file | HDR10 and HLG display | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer plays. |
| V059 | Dolby Vision Profile 7 (FEL), conversion failed for this file | HLG-only display | Primary player | SDR (tone-mapped from HDR10) | Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer is tone-mapped to SDR. |
| V060 | Dolby Vision Profile 7 (FEL), conversion failed for this file | SDR display | Primary player | SDR (tone-mapped from HDR10) | Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer is tone-mapped to SDR. |
| V061 | Dolby Vision Profile 7 (FEL), conversion failed for this file | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports, and Dolby Vision Profile 7 conversion failed for this file. |
| V062 | Dolby Vision Profile 7 (FEL), conversion failed for this file | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V063 | Dolby Vision Profile 7 (FEL), conversion failed for this file | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer plays. |
| V064 | Dolby Vision Profile 7 (FEL), conversion failed for this file | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V065 | Dolby Vision Profile 7 (MEL), conversion available | Dolby Vision, HDR10 and HLG display | Primary player | Dolby Vision (converted from Profile 7) | Profile 7 is converted to Profile 8.1, and its minimal enhancement layer (MEL) holds no picture detail, so nothing is lost. |
| V066 | Dolby Vision Profile 7 (MEL), conversion available | HDR10 and HLG display | Primary player | HDR10 (base layer) | This display does not support Dolby Vision, so the HDR10 base layer plays. |
| V067 | Dolby Vision Profile 7 (MEL), conversion available | HLG-only display | Primary player | SDR (tone-mapped from HDR10) | This display does not support Dolby Vision, so the HDR10 base layer is tone-mapped to SDR. |
| V068 | Dolby Vision Profile 7 (MEL), conversion available | SDR display | Primary player | SDR (tone-mapped from HDR10) | This display does not support Dolby Vision, so the HDR10 base layer is tone-mapped to SDR. |
| V069 | Dolby Vision Profile 7 (MEL), conversion available | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V070 | Dolby Vision Profile 7 (MEL), conversion available | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V071 | Dolby Vision Profile 7 (MEL), conversion available | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 | The display is in HDR10 mode, not Dolby Vision. |
| V072 | Dolby Vision Profile 7 (MEL), conversion available | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V073 | Dolby Vision Profile 7 (MEL), conversion not available on this device | Dolby Vision, HDR10 and HLG display | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer plays. |
| V074 | Dolby Vision Profile 7 (MEL), conversion not available on this device | HDR10 and HLG display | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer plays. |
| V075 | Dolby Vision Profile 7 (MEL), conversion not available on this device | HLG-only display | Primary player | SDR (tone-mapped from HDR10) | Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer is tone-mapped to SDR. |
| V076 | Dolby Vision Profile 7 (MEL), conversion not available on this device | SDR display | Primary player | SDR (tone-mapped from HDR10) | Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer is tone-mapped to SDR. |
| V077 | Dolby Vision Profile 7 (MEL), conversion not available on this device | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports, and Dolby Vision Profile 7 conversion is not available on this device. |
| V078 | Dolby Vision Profile 7 (MEL), conversion not available on this device | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V079 | Dolby Vision Profile 7 (MEL), conversion not available on this device | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer plays. |
| V080 | Dolby Vision Profile 7 (MEL), conversion not available on this device | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V081 | Dolby Vision Profile 7 (MEL), conversion failed for this file | Dolby Vision, HDR10 and HLG display | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer plays. |
| V082 | Dolby Vision Profile 7 (MEL), conversion failed for this file | HDR10 and HLG display | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer plays. |
| V083 | Dolby Vision Profile 7 (MEL), conversion failed for this file | HLG-only display | Primary player | SDR (tone-mapped from HDR10) | Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer is tone-mapped to SDR. |
| V084 | Dolby Vision Profile 7 (MEL), conversion failed for this file | SDR display | Primary player | SDR (tone-mapped from HDR10) | Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer is tone-mapped to SDR. |
| V085 | Dolby Vision Profile 7 (MEL), conversion failed for this file | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports, and Dolby Vision Profile 7 conversion failed for this file. |
| V086 | Dolby Vision Profile 7 (MEL), conversion failed for this file | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V087 | Dolby Vision Profile 7 (MEL), conversion failed for this file | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 (base layer) | Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer plays. |
| V088 | Dolby Vision Profile 7 (MEL), conversion failed for this file | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V089 | Dolby Vision Profile 8.1 (HDR10 compatible) | Dolby Vision, HDR10 and HLG display | Primary player | Dolby Vision | — |
| V090 | Dolby Vision Profile 8.1 (HDR10 compatible) | HDR10 and HLG display | Primary player | HDR10 (Dolby Vision base layer) | This display does not support Dolby Vision, so the HDR10 base layer plays. |
| V091 | Dolby Vision Profile 8.1 (HDR10 compatible) | HLG-only display | Primary player | SDR (tone-mapped from HDR10) | This display does not support Dolby Vision, so the HDR10 base layer is tone-mapped to SDR. |
| V092 | Dolby Vision Profile 8.1 (HDR10 compatible) | SDR display | Primary player | SDR (tone-mapped from HDR10) | This display does not support Dolby Vision, so the HDR10 base layer is tone-mapped to SDR. |
| V093 | Dolby Vision Profile 8.1 (HDR10 compatible) | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V094 | Dolby Vision Profile 8.1 (HDR10 compatible) | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V095 | Dolby Vision Profile 8.1 (HDR10 compatible) | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 | The display is in HDR10 mode, not Dolby Vision. |
| V096 | Dolby Vision Profile 8.1 (HDR10 compatible) | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V097 | Dolby Vision Profile 8.2 (SDR compatible) | Dolby Vision, HDR10 and HLG display | Primary player | Dolby Vision | — |
| V098 | Dolby Vision Profile 8.2 (SDR compatible) | HDR10 and HLG display | Primary player | SDR (Dolby Vision base layer) | This display does not support Dolby Vision, so the SDR base layer plays. |
| V099 | Dolby Vision Profile 8.2 (SDR compatible) | HLG-only display | Primary player | SDR (Dolby Vision base layer) | This display does not support Dolby Vision, so the SDR base layer plays. |
| V100 | Dolby Vision Profile 8.2 (SDR compatible) | SDR display | Primary player | SDR (Dolby Vision base layer) | This display does not support Dolby Vision, so the SDR base layer plays. |
| V101 | Dolby Vision Profile 8.2 (SDR compatible) | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V102 | Dolby Vision Profile 8.2 (SDR compatible) | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V103 | Dolby Vision Profile 8.2 (SDR compatible) | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 | The display is in HDR10 mode, not Dolby Vision. |
| V104 | Dolby Vision Profile 8.2 (SDR compatible) | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V105 | Dolby Vision Profile 8.4 (HLG compatible) | Dolby Vision, HDR10 and HLG display | Primary player | Dolby Vision | — |
| V106 | Dolby Vision Profile 8.4 (HLG compatible) | HDR10 and HLG display | Primary player | HLG (Dolby Vision base layer) | This display does not support Dolby Vision, so the HLG base layer plays. |
| V107 | Dolby Vision Profile 8.4 (HLG compatible) | HLG-only display | Primary player | HLG (Dolby Vision base layer) | This display does not support Dolby Vision, so the HLG base layer plays. |
| V108 | Dolby Vision Profile 8.4 (HLG compatible) | SDR display | Primary player | SDR (tone-mapped from HLG) | This display does not support Dolby Vision, so the HLG base layer is tone-mapped to SDR. |
| V109 | Dolby Vision Profile 8.4 (HLG compatible) | Display abilities unknown | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V110 | Dolby Vision Profile 8.4 (HLG compatible) | HDR10 display, Match Dynamic Range off | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V111 | Dolby Vision Profile 8.4 (HLG compatible) | Dolby Vision display, currently in HDR10 mode | Primary player | HDR10 | The display is in HDR10 mode, not Dolby Vision. |
| V112 | Dolby Vision Profile 8.4 (HLG compatible) | Display abilities unknown, currently in HDR10 mode | Primary player | HDR10 | — |
| V113 | SDR | Dolby Vision, HDR10 and HLG display | Fallback player | SDR | — |
| V114 | SDR | HDR10 and HLG display | Fallback player | SDR | — |
| V115 | SDR | HLG-only display | Fallback player | SDR | — |
| V116 | SDR | SDR display | Fallback player | SDR | — |
| V117 | SDR | Display abilities unknown | Fallback player | SDR | — |
| V118 | SDR | HDR10 display, Match Dynamic Range off | Fallback player | SDR | — |
| V119 | SDR | Dolby Vision display, currently in HDR10 mode | Fallback player | HDR10 | The display is in HDR10 mode, not SDR. |
| V120 | SDR | Display abilities unknown, currently in HDR10 mode | Fallback player | HDR10 | The display is in HDR10 mode, not SDR. |
| V121 | HDR10 | Dolby Vision, HDR10 and HLG display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V122 | HDR10 | HDR10 and HLG display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V123 | HDR10 | HLG-only display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V124 | HDR10 | SDR display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V125 | HDR10 | Display abilities unknown | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V126 | HDR10 | HDR10 display, Match Dynamic Range off | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V127 | HDR10 | Dolby Vision display, currently in HDR10 mode | Fallback player | HDR10 | — |
| V128 | HDR10 | Display abilities unknown, currently in HDR10 mode | Fallback player | HDR10 | — |
| V129 | HDR10+ | Dolby Vision, HDR10 and HLG display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V130 | HDR10+ | HDR10 and HLG display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V131 | HDR10+ | HLG-only display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V132 | HDR10+ | SDR display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V133 | HDR10+ | Display abilities unknown | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V134 | HDR10+ | HDR10 display, Match Dynamic Range off | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V135 | HDR10+ | Dolby Vision display, currently in HDR10 mode | Fallback player | HDR10 | — |
| V136 | HDR10+ | Display abilities unknown, currently in HDR10 mode | Fallback player | HDR10 | — |
| V137 | HLG | Dolby Vision, HDR10 and HLG display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V138 | HLG | HDR10 and HLG display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V139 | HLG | HLG-only display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V140 | HLG | SDR display | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V141 | HLG | Display abilities unknown | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V142 | HLG | HDR10 display, Match Dynamic Range off | Fallback player | Display mode: unknown | The fallback player does not confirm which display mode is active. |
| V143 | HLG | Dolby Vision display, currently in HDR10 mode | Fallback player | HDR10 | — |
| V144 | HLG | Display abilities unknown, currently in HDR10 mode | Fallback player | HDR10 | — |
| V145 | Dolby Vision Profile 5 | Dolby Vision, HDR10 and HLG display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, and Profile 5 has no HDR10 layer so colors can look wrong. |
| V146 | Dolby Vision Profile 5 | HDR10 and HLG display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, and Profile 5 has no HDR10 layer so colors can look wrong. |
| V147 | Dolby Vision Profile 5 | HLG-only display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, and Profile 5 has no HDR10 layer so colors can look wrong. |
| V148 | Dolby Vision Profile 5 | SDR display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, and Profile 5 has no HDR10 layer so colors can look wrong. |
| V149 | Dolby Vision Profile 5 | Display abilities unknown | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, and Profile 5 has no HDR10 layer so colors can look wrong. |
| V150 | Dolby Vision Profile 5 | HDR10 display, Match Dynamic Range off | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, and Profile 5 has no HDR10 layer so colors can look wrong. |
| V151 | Dolby Vision Profile 5 | Dolby Vision display, currently in HDR10 mode | Fallback player | HDR10 | Dolby Vision is unavailable in fallback mode, and Profile 5 has no HDR10 layer so colors can look wrong. |
| V152 | Dolby Vision Profile 5 | Display abilities unknown, currently in HDR10 mode | Fallback player | HDR10 | Dolby Vision is unavailable in fallback mode, and Profile 5 has no HDR10 layer so colors can look wrong. |
| V153 | Dolby Vision Profile 7 (FEL) | Dolby Vision, HDR10 and HLG display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V154 | Dolby Vision Profile 7 (FEL) | HDR10 and HLG display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V155 | Dolby Vision Profile 7 (FEL) | HLG-only display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V156 | Dolby Vision Profile 7 (FEL) | SDR display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V157 | Dolby Vision Profile 7 (FEL) | Display abilities unknown | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V158 | Dolby Vision Profile 7 (FEL) | HDR10 display, Match Dynamic Range off | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V159 | Dolby Vision Profile 7 (FEL) | Dolby Vision display, currently in HDR10 mode | Fallback player | HDR10 | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays. |
| V160 | Dolby Vision Profile 7 (FEL) | Display abilities unknown, currently in HDR10 mode | Fallback player | HDR10 | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays. |
| V161 | Dolby Vision Profile 7 (MEL) | Dolby Vision, HDR10 and HLG display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V162 | Dolby Vision Profile 7 (MEL) | HDR10 and HLG display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V163 | Dolby Vision Profile 7 (MEL) | HLG-only display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V164 | Dolby Vision Profile 7 (MEL) | SDR display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V165 | Dolby Vision Profile 7 (MEL) | Display abilities unknown | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V166 | Dolby Vision Profile 7 (MEL) | HDR10 display, Match Dynamic Range off | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V167 | Dolby Vision Profile 7 (MEL) | Dolby Vision display, currently in HDR10 mode | Fallback player | HDR10 | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays. |
| V168 | Dolby Vision Profile 7 (MEL) | Display abilities unknown, currently in HDR10 mode | Fallback player | HDR10 | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays. |
| V169 | Dolby Vision Profile 8.1 (HDR10 compatible) | Dolby Vision, HDR10 and HLG display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V170 | Dolby Vision Profile 8.1 (HDR10 compatible) | HDR10 and HLG display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V171 | Dolby Vision Profile 8.1 (HDR10 compatible) | HLG-only display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V172 | Dolby Vision Profile 8.1 (HDR10 compatible) | SDR display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V173 | Dolby Vision Profile 8.1 (HDR10 compatible) | Display abilities unknown | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V174 | Dolby Vision Profile 8.1 (HDR10 compatible) | HDR10 display, Match Dynamic Range off | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active. |
| V175 | Dolby Vision Profile 8.1 (HDR10 compatible) | Dolby Vision display, currently in HDR10 mode | Fallback player | HDR10 | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays. |
| V176 | Dolby Vision Profile 8.1 (HDR10 compatible) | Display abilities unknown, currently in HDR10 mode | Fallback player | HDR10 | Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays. |
| V177 | Dolby Vision Profile 8.2 (SDR compatible) | Dolby Vision, HDR10 and HLG display | Fallback player | SDR | Dolby Vision is unavailable in fallback mode, so the SDR base layer plays. |
| V178 | Dolby Vision Profile 8.2 (SDR compatible) | HDR10 and HLG display | Fallback player | SDR | Dolby Vision is unavailable in fallback mode, so the SDR base layer plays. |
| V179 | Dolby Vision Profile 8.2 (SDR compatible) | HLG-only display | Fallback player | SDR | Dolby Vision is unavailable in fallback mode, so the SDR base layer plays. |
| V180 | Dolby Vision Profile 8.2 (SDR compatible) | SDR display | Fallback player | SDR | Dolby Vision is unavailable in fallback mode, so the SDR base layer plays. |
| V181 | Dolby Vision Profile 8.2 (SDR compatible) | Display abilities unknown | Fallback player | SDR | Dolby Vision is unavailable in fallback mode, so the SDR base layer plays. |
| V182 | Dolby Vision Profile 8.2 (SDR compatible) | HDR10 display, Match Dynamic Range off | Fallback player | SDR | Dolby Vision is unavailable in fallback mode, so the SDR base layer plays. |
| V183 | Dolby Vision Profile 8.2 (SDR compatible) | Dolby Vision display, currently in HDR10 mode | Fallback player | HDR10 | The display is in HDR10 mode, not SDR. |
| V184 | Dolby Vision Profile 8.2 (SDR compatible) | Display abilities unknown, currently in HDR10 mode | Fallback player | HDR10 | The display is in HDR10 mode, not SDR. |
| V185 | Dolby Vision Profile 8.4 (HLG compatible) | Dolby Vision, HDR10 and HLG display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HLG base layer plays, and the fallback player does not confirm which display mode is active. |
| V186 | Dolby Vision Profile 8.4 (HLG compatible) | HDR10 and HLG display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HLG base layer plays, and the fallback player does not confirm which display mode is active. |
| V187 | Dolby Vision Profile 8.4 (HLG compatible) | HLG-only display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HLG base layer plays, and the fallback player does not confirm which display mode is active. |
| V188 | Dolby Vision Profile 8.4 (HLG compatible) | SDR display | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HLG base layer plays, and the fallback player does not confirm which display mode is active. |
| V189 | Dolby Vision Profile 8.4 (HLG compatible) | Display abilities unknown | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HLG base layer plays, and the fallback player does not confirm which display mode is active. |
| V190 | Dolby Vision Profile 8.4 (HLG compatible) | HDR10 display, Match Dynamic Range off | Fallback player | Display mode: unknown | Dolby Vision is unavailable in fallback mode, so the HLG base layer plays, and the fallback player does not confirm which display mode is active. |
| V191 | Dolby Vision Profile 8.4 (HLG compatible) | Dolby Vision display, currently in HDR10 mode | Fallback player | HDR10 | Dolby Vision is unavailable in fallback mode, so the HLG base layer plays. |
| V192 | Dolby Vision Profile 8.4 (HLG compatible) | Display abilities unknown, currently in HDR10 mode | Fallback player | HDR10 | Dolby Vision is unavailable in fallback mode, so the HLG base layer plays. |
| V193 | HDR10+ | Dolby Vision, HDR10 and HLG display, Apple TV that sends HDR10+ | Primary player | HDR10+ or HDR10 | This Apple TV sends the HDR10+ metadata when the display supports it; it does not report whether the display uses it. |
| V194 | HDR10+ | HDR10 and HLG display, Apple TV that sends HDR10+ | Primary player | HDR10+ or HDR10 | This Apple TV sends the HDR10+ metadata when the display supports it; it does not report whether the display uses it. |
| V195 | HDR10+ | HLG-only display, Apple TV that sends HDR10+ | Primary player | SDR (tone-mapped from HDR10) | This display does not support HDR10, so the picture is tone-mapped to SDR. |
| V196 | HDR10+ | SDR display, Apple TV that sends HDR10+ | Primary player | SDR (tone-mapped from HDR10) | This display does not support HDR10, so the picture is tone-mapped to SDR. |
| V197 | HDR10+ | Display abilities unknown, Apple TV that sends HDR10+ | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V198 | HDR10+ | HDR10 display, Match Dynamic Range off, Apple TV that sends HDR10+ | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V199 | HDR10+ | Dolby Vision display, currently in HDR10 mode, Apple TV that sends HDR10+ | Primary player | HDR10+ or HDR10 | This Apple TV sends the HDR10+ metadata when the display supports it; it does not report whether the display uses it. |
| V200 | HDR10+ | Display abilities unknown, currently in HDR10 mode, Apple TV that sends HDR10+ | Primary player | HDR10 | — |
| V201 | HDR10+ | Dolby Vision, HDR10 and HLG display, Apple TV without HDR10+ | Primary player | HDR10 | This Apple TV model does not support HDR10+, so this plays as HDR10. |
| V202 | HDR10+ | HDR10 and HLG display, Apple TV without HDR10+ | Primary player | HDR10 | This Apple TV model does not support HDR10+, so this plays as HDR10. |
| V203 | HDR10+ | HLG-only display, Apple TV without HDR10+ | Primary player | SDR (tone-mapped from HDR10) | This display does not support HDR10, so the picture is tone-mapped to SDR. |
| V204 | HDR10+ | SDR display, Apple TV without HDR10+ | Primary player | SDR (tone-mapped from HDR10) | This display does not support HDR10, so the picture is tone-mapped to SDR. |
| V205 | HDR10+ | Display abilities unknown, Apple TV without HDR10+ | Primary player | Display mode: unknown | Apple TV did not report which HDR modes this display supports. |
| V206 | HDR10+ | HDR10 display, Match Dynamic Range off, Apple TV without HDR10+ | Primary player | Display mode: unknown | Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file. |
| V207 | HDR10+ | Dolby Vision display, currently in HDR10 mode, Apple TV without HDR10+ | Primary player | HDR10 | This Apple TV model does not support HDR10+, so this plays as HDR10. |
| V208 | HDR10+ | Display abilities unknown, currently in HDR10 mode, Apple TV without HDR10+ | Primary player | HDR10 | — |

When the fallback player is used, every screen also shows: Dolby Vision and Atmos are unavailable in fallback mode.

<!-- RULES-TABLE-END -->
