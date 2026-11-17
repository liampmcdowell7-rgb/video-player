# Subtitles, track selection and sync (target `Subtitles`)

Pure Swift, Foundation only, depends on `VideoPlayerCore` only. Source: `Packages/VideoPlayerCore/Sources/Subtitles/`.
Tests: `Packages/VideoPlayerCore/Tests/SubtitlesTests/`. Everything here runs on Linux; nothing here needs an Apple TV
except the items listed under "What only an Apple TV can verify".

Anything marked **Interpretation (PROVISIONAL)** is a choice I made where the brief was silent or loose. Change it if
you disagree; each has one place in the code.

## 1. Text decoding

Entry point: `SubtitleTextDecoder.decode(_ data:, languageHint:)`. It returns the text, the encoding it settled on, and
how sure it was. Subtitle files rarely say what encoding they use, so this is detection, not certainty.

Order of attempts:

1. A byte-order mark: UTF-8, UTF-16 LE/BE, UTF-32 LE/BE.
2. No BOM, but the zero-byte pattern of UTF-16 or UTF-32 text (every second or fourth byte zero).
3. Pure ASCII, then strictly valid UTF-8.
4. The code pages that the file name's language suggests (`movie.ru.srt` tries Windows-1251 first, and so on).
5. A Cyrillic-shape check (Windows-1251), then a CJK guess, then Windows-1252 as the last resort.

### Supported

| Family | Encodings | How |
|---|---|---|
| Unicode | UTF-8 (with or without BOM), UTF-16 LE/BE (BOM or none), UTF-32 LE/BE (BOM or none) | own code |
| Western and Central European | Windows-1252, ISO-8859-1, ISO-8859-2, ISO-8859-15, Windows-1250, CP437, CP850 | generated tables (`EncodingTables.swift`) |
| Cyrillic, Greek, Turkish, Hebrew, Arabic, Baltic, Vietnamese, Thai | Windows-1251, 1253, 1254, 1255, 1256, 1257, 1258, 874 | generated tables |
| Japanese | Shift-JIS | Foundation (`String.Encoding.shiftJIS`) |
| Korean | EUC-KR | Foundation |
| Simplified Chinese | GBK (decoded as GB18030, which is a superset) | Foundation |
| Traditional Chinese | Big5 | Foundation |

The single-byte tables come from `scripts/gen-subtitle-encodings.py` (Python's codecs, run once; the output is checked in,
so the build does not need Python).

### Not supported, or only partly

- **EUC-JP**: Foundation on Linux does not decode it, so it is not offered. A file in EUC-JP falls to a wrong guess.
- **ISO-2022-JP, HZ, UTF-7, EBCDIC and anything else not listed above**: not detected.
- **CJK relies on Foundation.** On Apple platforms Foundation covers Shift-JIS, EUC-KR, GBK and Big5. On Linux the four
  work in the version tested (Swift 6.4.2) through the raw CFStringEncoding values, but a Foundation without those tables
  would make the CJK guess fail and fall back to Windows-1252. The tests that depend on this are in `TextDecodingTests`.
- **Big5 versus GBK cannot be told apart** from bytes alone when the text is short or uses only characters both can
  decode. A `zh` file name hint with no script tries GB18030 first; `zh-Hant`, `zh-TW`, `zh-HK` tries Big5 first.
- **Short Cyrillic text** (a few words) can be mistaken for Windows-1252, because the byte ranges overlap. Longer text is
  fine. A `ru`/`uk`/`bg`/`sr` hint fixes it.
- **Latin text is never guessed as CJK**: a CJK guess needs most lines that contain high bytes to be mostly high bytes,
  and a score of at least 0.8. This is deliberate; a wrong CJK decode is worse than accented text shown as Windows-1252.
- Detection is a guess for every non-Unicode case. The result carries a plain-language `note` when the choice was a guess
  and an `invalidBytes` count, so the UI can offer "try another encoding" (`decode(_:as:)` takes an explicit encoding).

### Language hint from the file name

`SubtitleTextDecoder.languageHint(fromFileName:)` reads `Movie.en.srt`, `Movie.eng.forced.srt`, `Movie.zh-Hant.srt`,
`Movie.pt-BR.sdh.srt` and similar.

- **Interpretation (PROVISIONAL)**: `hi` means hearing impaired when a language is also present; with no other language
  it means Hindi.
- **Interpretation (PROVISIONAL)**: a file whose whole name is one token counts as a language only if that token is
  lowercase or longer than three characters, so `It.srt` (the film) is not Italian but `it.srt` is.
- **Interpretation (PROVISIONAL)**: the first word of a name is the title, never a language.

## 2. Parsers and the cue model

All three parsers are tolerant: they never throw, never crash and never hang; they skip what they cannot read and add a
plain-language note to `ParsedSubtitle.warnings` (the notes never contain subtitle text). Cues come back sorted by start
time, stably.

Shared model (`SubtitleModel.swift`): `SubtitleCue` (start, end, styled `runs`, optional position, alignment, layer,
format-specific settings), `SubtitleRun` (text with italic/bold/underline/strike and optional colour, font, size).

### SRT
- Accepts `,` or `.` before the fraction, `-->` with or without spaces, 1 to 9 fraction digits (the digit count sets the scale),
  missing hours, CRLF/LF/CR, a BOM, a missing blank line between cues.
- **Interpretation (PROVISIONAL)**: a cue with zero or negative duration is dropped (with a warning). A negative start is
  clamped to 0.
- **Interpretation (PROVISIONAL)**: a digits-only line directly before a timing line is the cue number, not text.
- Inline markup: `<i> <b> <u> <s>`, `<font color/face/size>`, `{\an1..9}`, `{\i1}`-style ASS tags, HTML entities.
  Unclosed or stray tags are repaired, not shown.

### WebVTT
- Header, `NOTE`, `STYLE` and `REGION` blocks, cue identifiers, cue settings (`line`, `position`, `size`, `align`,
  `vertical`, `region`), `<v>`, `<c.class>`, `<i> <b> <u>`, timestamps with or without hours. `<ruby>`, `<rt>`, `<lang>` tags are recognised and
  removed (no ruby rendering).
- **Interpretation (PROVISIONAL)**: a one-word line before the next timing line is that cue's identifier, but only after
  at least one text line has been seen, so a cue whose text is one word is not eaten.
- CSS in `STYLE` blocks is kept verbatim in `vttStyleBlocks`; it is **not** applied.

### ASS / SSA
- `[Script Info]`, `[V4+ Styles]`/`[V4 Styles]`, `[Events]` with any `Format:` order, `Dialogue:` lines with commas in the text,
  style defaults, `\N \n \h`, alignment (SSA numbering for `.ssa`), margins, layers.
- Override tags applied: `\b \i \u \s \fn \fs \c \1c \alpha \1a \an \a \r \pos \fad \p`.
- **Interpretation (PROVISIONAL)**: `\move` uses its start point (no animation); `\p` drawing text is dropped (no vector
  drawing), and a cue with only drawings is dropped.
- Read and ignored: `\2c \3c \4c \2a \3a \4a \fscx \fscy \fsp \fr* \fax \fay \bord \xbord \ybord \shad \xshad \yshad \be
  \blur \fe \q \org \clip \iclip \fade \t \k* \pbo`. Their text is kept; only the effect is lost.
- `[Fonts]` and `[Graphics]` sections are skipped, never decoded. Missing `PlayRes` follows libass (384x288 or derived at 4:3).
- Style booleans are resolved into runs; colour, font and size are set on a run only when overridden.

### SubtitleTrack
`SubtitleTrack(cues:format:)` builds an interval index (an implicit balanced tree over the start-sorted cues, each node
holding the largest end time below it). `activeCues(at:)` is O(log n + k) for k active cues; it is tested with 50,000 and
100,000 cues, and with 20,000 cues that all overlap. Also: `nextChange(after:)`, `shifted(by:)` (a start is never negative: a cue
that would start before 0 starts at 0, and a cue that ends at or before 0 is dropped), `mergingIdenticalNeighbours(maxGap:)`
(same text and style, touching or overlapping within 1 ms, merged into one; it compares only the newest 8 cues with the
same text so thousands of repeated "♪" cues stay fast).

## 3. PGS (`.sup`) bitmap subtitles

`PGSParser.parse(_ data:)` reads the segment stream: palette (PDS), object (ODS, including objects split over several
segments), presentation composition (PCS), window (WDS) and end-of-set. It builds `PGSBitmapCue`s with start and end times,
decoded index bitmaps, palettes in RGBA, the forced flag and the frame size. Epochs (acquisition points, normal
updates), clear-screen sets, palette-only updates and cropped objects are handled. Damaged or truncated data produces the
cues it can and a warning.

- **Interpretation (PROVISIONAL)**: a cue that is never cleared lasts 5 seconds (`PGSParser.unterminatedDuration`).
- Palette entries are Y, Cr, Cb, A; converted with BT.709 when the frame is 720 lines or taller, else BT.601, limited range.
- **The segment layout is written from my memory of the format and common decoders' conventions, and checked only against
  my own test-side encoder (`PGSTestEncoder`). I have not parsed a real Blu-ray `.sup`.** Passing tests show that parser
  and encoder agree, not that either matches real discs. First real file: if cues are missing or garbled, start with
  the palette entry order and the object-flag bits.
- Rendering the bitmaps is the app's job. This target gives it the pixels and where to put them.

### Placement and the vertical-position setting (Tier A item 9)

`PGSPlacement.place(_ cue:, containerWidth:, containerHeight:, options:)` returns a `PlacedRect` per object in the
container's coordinates.

- `aspect`: `.fit` (uniform scale, centred; bars where the aspects differ) or `.stretch`.
- `verticalOffset`: a fraction of the container height, **positive moves up**, clamped to ±0.5. It moves the whole
  block (all objects of the cue together).
- **Interpretation (PROVISIONAL)**: objects in the top half of the frame (dialogue moved up by the disc author for
  signs) are not moved unless `moveTopSubtitles` is set.
- The block is then clamped so it stays inside the container.

### VobSub: not built in this batch
`.idx` + `.sub` pairs are listed by the matcher (shown once, as the `.idx`) so the app can say "this subtitle needs VobSub
support", and `VobSubIndexHeader.parse` reads the `.idx` text header (size, palette, language tracks, timestamp count)
only. There is no `.sub` bitmap decoding. `SubtitleFileParser.parse` throws `unsupportedFormat(.vobSub)` for both.

## 4. Matching external subtitle files

`ExternalSubtitleMatcher.candidates(videoFileName:folderListing:)` takes the video's file name and the names in its folder
and returns the subtitle files that belong to it, each with a language, forced and hearing-impaired flags, format, and
the tier it matched at:

1. `sameName`: `Movie.mkv` with `Movie.srt`, `Movie.en.srt`, `Movie.en.forced.srt` ...
2. `sameEpisode`: a different title but the same season/episode key (`S01E02`, `1x02`).
3. `onlyVideoInFolder`: the folder holds exactly one video, so any subtitle file in it is taken.

Ordering inside a tier: language (unknown last), non-forced before forced, non-hearing-impaired before hearing-impaired,
then format (SRT, ASS, SSA, WebVTT, PGS, VobSub), then name. A lone `.sub` or `.idx` has `isUsable == false`.

## 5. Track selection (Tier A item 10)

`TrackSelector.select(audio:subtitles:originalLanguage:preferences:remembered:)` is a pure function. It returns the audio
track id, the subtitle track id (nil is off), and a plain sentence for each, meant to be shown in the UI.

Audio, in order:
1. The choice already made for this series (matched by language and kind, closest channel count). A remembered audio
   description or commentary choice is honoured.
2. "Original language" mode: the original language.
3. The first preferred language that exists.
4. The file's default track, else the first.

Audio description and commentary are skipped in steps 2 to 4 unless nothing else exists. Inside a language: region match,
then Atmos (if wanted), then most channels (if wanted), then the default flag, then file order.

- **Interpretation (PROVISIONAL)**: an Atmos track (usually 5.1 channels carrying the Atmos extension) is ranked above a
  7.1 DTS-HD track when "prefer Atmos" is on. Turn it off and 7.1 wins on channel count.

Subtitles, in order:
1. The earlier choice for the series, including "off".
2. "Original language plus forced subtitles" mode with original-language audio: only a forced track in a wished language,
   else off.
3. Audio in a preferred language (or unknown language): only a forced track, else off. `alwaysShowSubtitles` skips this
   step.
4. Foreign audio: a full (non-forced) track in the first wished language that has one. The SDH preference
   (`prefer`/`avoid`/`noPreference`) orders the choices inside a language. Forced-only as a last resort.
5. Off, with the reason ("there are no subtitles in your languages").

Subtitle wishes default to the audio wishes when none are set. Commentary subtitle tracks are never chosen automatically.
The test table in `TrackSelectionTests.testSelectionTable` is the specification: anime with Japanese audio and forced
English signs, a foreign film, commentary, audio description, several English tracks with different channel counts, Atmos
against 7.1, SDH against non-SDH, no match, and the remembered series choice.

## 6. Audio and video sync (Tier A item 8)

Sign convention: **positive means the audio is later than the video**. `SyncModel.plan(path:userDelay:systemOutputLatency:settings:)`
returns what the player must do.

| Path | Who deals with the output latency | App adds |
|---|---|---|
| `avPlayer` | the system | the per-file delay only |
| `fallbackEngine` (default assumption) | the app | the per-file delay minus the output latency |
| `fallbackEngine` with `fallbackOutputIsSystemSynchronised = true` | the system | the per-file delay only |

`effectiveAudioDelay = userDelay + appCompensation`. Output latency is counted by exactly one party on every path;
`testNoDoubleApplyAcrossAllPaths` checks this over every combination of path, flag, latency (including nil, negative,
NaN, 10 s) and delay (including NaN, infinities, beyond the limits).

- The per-file delay is rounded to milliseconds and **clamped to ±5 s** (Interpretation, PROVISIONAL). The output latency
  is clamped to 0...3 s (Apple documents AirPlay devices at about 2 s).
- Per-file delays are kept in `SyncDelayTable`, keyed by source, path and file size (so a different file saved under the
  same name does not inherit it), saved as JSON. A missing or unreadable file gives an empty table.
- `DriftCheck.evaluate(_ samples:)` takes pairs of audio-clock and video-clock readings and returns the drift in
  milliseconds per hour (least-squares slope), the offset change from the first third of the samples to the last third,
  whether it needs correcting, and the delay change that would cancel it. It needs at least 3 samples spanning 30 s to
  call the figure reliable. The correction threshold is 45 ms (Interpretation, PROVISIONAL: the smaller of the ITU-R BT.1359
  detectability figures, about 45 ms audio early and 125 ms audio late).

### What "honouring the system wireless audio sync setting" means in this model

tvOS has a calibration, Settings > Video and Audio > Calibration > Wireless Audio Sync, in which the Apple TV and an
iPhone measure the delay between sound and picture and then match the wireless speakers' output to it (Apple Support,
"Calibrate video and audio on Apple TV 4K"). In this model, honouring it means:

1. When the audio goes through AVPlayer, the system already applies that calibration. The app does **not** add, subtract
   or read the calibration, and adds only the user's per-file delay on top. (`avPlayer` row above.)
2. When the app plays audio itself, it must not apply the calibration a second time if the system already did. Whether it
   did depends on which audio renderer the fallback engine uses; the model has a switch for it
   (`fallbackOutputIsSystemSynchronised`) and defaults to the cautious reading: the app clocks the audio itself and applies
   `AVAudioSession.outputLatency` as a negative compensation.

Apple documentation read for this:
- `AVAudioSession.outputLatency` (tvOS 9.0+): "The latency for audio output, in seconds", with the note that using an
  AirPlay-enabled device can result in about a 2-second delay.
- Apple Support, "Calibrate video and audio on Apple TV 4K", for the setting above.
- The `AVSampleBufferRenderSynchronizer` page lists no latency behaviour.

### What only an Apple TV can verify (none of this was tested)

- Whether `AVAudioSession.outputLatency` on tvOS includes the Wireless Audio Sync calibration, or only the device's own latency.
  The model's fallback-engine row is correct only if it does; if it does not, the app would under-compensate.
- How tvOS exposes the calibration to an app at all, if it does.
- Which renderer the fallback engine ends up using, which decides `fallbackOutputIsSystemSynchronised`.
- That the AVPlayer path really needs no app compensation with real AirPlay and Bluetooth speakers.
- That the 45 ms threshold and 5 s clamp feel right in use.

The numbers in the model are tested; whether they match what the Apple TV does is not.

## 7. Tests

`swift test --filter SubtitlesTests`, run on Linux. Covered: SRT, WebVTT, ASS parsers, text decoding (every listed
encoding built from generated bytes, with BOMs, odd encodings and wrong hints), the cue index (50,000 cues), PGS (own
encoder: multi-fragment objects, RLE forms, epochs, clear screens, truncation), the matcher, track selection (a table),
sync (no double apply, drift, storage), a fixed-seed fuzz (random bytes, mutated valid files, every truncation point,
punctuation soup) and huge inputs (100,000 cues, multi-megabyte single lines, deeply nested unclosed tags, overlapping
cues). No test is skipped. 180 tests in total.

Two limits exist only because the huge-input tests found a quadratic slowdown (an ASS line with 200,000 unclosed `{`
took minutes): a `{` with no closing `}` anywhere later is scanned for once, and inline-markup nesting (SRT/WebVTT `<i><b>…`
and `{\i1}`) is capped at 32 open tags, extra opens being ignored.

## 8. Shared types for other targets

This target defines types other targets may want: `LanguageTag`/`LanguageTable`, `SubtitleColor`, `SubtitleAlignment`,
`PlacedRect`, `PlaybackPath`, `SyncFileKey`, `AudioTrackInfo`, `SubtitleTrackInfo`. They live here because moving them to
`VideoPlayerCore` was not in scope for this batch.
