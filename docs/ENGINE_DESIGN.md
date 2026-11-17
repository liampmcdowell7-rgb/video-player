# Remux engine design (`RemuxEngine`)

Status: **PROVISIONAL.** The pure-Swift part is written and tested in WSL (Linux): 117 tests, 0 skipped, 0 failed
(`swift test --build-system native`, private copy with a trimmed manifest). **Nothing here has been compiled for tvOS and
nothing has been played by AVPlayer.** The research behind it is in `docs/spikes/REMUX.md`, `docs/spikes/DOLBY_VISION_P7.md`
and `docs/spikes/FFMPEG_TVOS_CANDIDATES.md`.

## What it does

Plays a Matroska (MKV) file on the Apple TV's own player without re-encoding the picture. The engine reads the file through
a `ByteRangeReader` (any source type), cuts it into short segments at keyframes, re-wraps each segment as fragmented MP4,
and serves the result as a local HLS stream from a small HTTP server on `127.0.0.1`. AVPlayer plays that stream, so HDR,
Dolby Vision signalling, the system audio output and the system player UI all stay native.

```
source (SMB, WebDAV, SFTP ...) -> ByteRangeReader -> Matroska index (header, Cues or cluster scan)
  -> segment plan -> demuxer (one window of the file per segment) -> fMP4 writer -> loopback HTTP server -> AVPlayer
```

## Parts (all in `Sources/RemuxEngine`, depends on `VideoPlayerCore` only)

| Part | File | What it does |
|------|------|--------------|
| Matroska reader | `Matroska.swift` | Tracks (video, audio, subtitle, colour, Dolby Vision mapping), Cues, cluster layout, blocks. **Laced blocks** (Xiph, EBML, fixed) are supported; frame times inside a laced block come from the block duration or the track default duration, and a laced block with neither is reported as unsupported, never guessed. |
| Segmenter | `Plan.swift` | Cuts at video keyframes only, target 2 to 6 s (shorter when the bitrate is high, see budget). Each segment knows its time range and the byte range of its window. |
| Cluster scan | `Matroska.swift` | Files without Cues: one small read per cluster header to find keyframe positions. Assumes a cluster that holds a video keyframe starts with it (true for mkvmerge and ffmpeg output); a file that breaks this gets fewer cut points and a warning. |
| Box writer | `FMP4.swift` | Init segment (`ftyp`, `moov` with empty sample tables, `mvex`) per track, and one `moof` + `mdat` per segment. Default-base-is-moof, version 1 `tfdt`, version 1 `trun` with composition offsets. |
| Box checker | `BoxParser.swift`, `FMP4Checker` | Parses what the writer produced and checks it (sample sizes add up to the `mdat`, data offset, box order). Also used by the tests on real files. |
| Codec records | `HEVC.swift`, `AudioCodecs.swift` | `hvcC` rewritten from the stream, `hvc1` tag, `colr`; mastering display and light level written from the SEI in the stream; Dolby Vision record (`dvcC` / `dvvC`) from the MKV mapping. Audio pass-through: AC-3, E-AC-3, AAC, FLAC. |
| Playlists | `Playlist.swift` | One master playlist, one video playlist, one playlist per audio track, all VOD with `EXT-X-MAP`. Subtitles are not in the playlists; the app draws them itself. |
| Seek map | `Plan.swift` (`SeekMap`) | A time in the file maps to a segment index, and a segment to its byte range; byte-offset estimates are interpolated between the Cue anchors and resynchronised to the next cluster. |
| Read-ahead | `ReadAhead.swift` | A pure planner with a fake clock in the tests. Fetches the next segments while the player plays, and stops when the budget is full (back-pressure). |
| Loopback server | `Loopback.swift` | HTTP/1.1 on a POSIX socket bound to `127.0.0.1`, ephemeral port, secret path prefix, GET and HEAD, byte ranges (206 / 416), keep-alive, cancels the work when the client disconnects. Everything the app uses sits behind the `LoopbackServer` protocol, so tests can use a fake. |
| Session | `Session.swift` | Ties it together: `prepare()`, `resource(path:)`, window cache, planner, cancel. |

## Memory budget (ASSUMPTION, to be checked on a device)

The engine may use **192 MiB** of the app's memory (`EngineBudget`). A window (the bytes of one segment plus the one cluster
after it, all tracks) costs about 1.5 times the segment bytes. The cache must hold at least two windows (the one being served
and one read ahead), so the target segment length is `192 MiB / (2 * 1.5 * bytes per second)`, clamped to 2..6 s. A stream
too fast for even 2 s segments runs with one window and no read-ahead, and reports a warning (`isOverBudget`).
The budget numbers are unmeasured assumptions; the Apple TV checklist (DEVICE_TEST_CHECKLIST.md, section E) measures them.

## Seeking

AVPlayer asks for segments by number. A seek to time t becomes: segment index (`segmentIndex(forSeconds:)`), then its window.
The window starts at the cluster that holds the segment's starting keyframe (from Cues or the scan) and ends in the cluster
that holds the next cut keyframe. Cancelling a seek cancels the pending windows (`planner.cancel`).

## What is behind a protocol (not in this target)

- `AudioTranscoding`: DTS, DTS-HD, TrueHD, MLP, Opus, Vorbis to FLAC. Implemented by `DecodedAudioTranscoder` in the
  `AudioDecode` target over the vendored FFmpegBuild 3.15.0 frameworks (LGPL, dynamic); the app supplies it in
  `RemuxPlayback.open`. The protocol gained `outputConfig(for:firstFrames:)`, `transcode(_ input:...)` (segment number,
  frames, warm-up and look-ahead frames, segment bounds), `sourceInfo(for:)` and `diagnostics(for:)`, with defaults so a
  simple transcoder still works. Design and results: `docs/AUDIO_PIPELINE.md`.
- When the file's default audio track still cannot be offered, `RemuxMediaInfo.audioFallback` names it and the track that
  replaces it (same language, then lossless, then more channels; PROVISIONAL), and that track becomes the default.
- `DolbyVisionConverting`: profile 7 to 8.1, measured at about 11 microseconds per frame with libdovi (spike).
- Without them: DTS and TrueHD tracks are listed in `skippedAudio` with a reason; Dolby Vision profile 7 files are reported.

## Tested (WSL, Linux, Swift 6.4.2)

117 tests in `Tests/RemuxEngineTests`: synthetic Matroska files whose frame layout the test controls (exact frame, time and
byte checks, Cues at the end, no Cues, many tracks, read amplification and window counts, read-ahead with a fake clock and
throttled reader, budget limits at 120 Mbps, seek maps, HTTP ranges and cancellation over a real loopback socket), 8 lacing
tests, and 3 tests on files made by a real encoder and muxer (x265 HDR10 with B-frames and open GOPs, x264, no Cues) that
are remuxed completely and read back by an independent LGPL `ffprobe` (codec, size, exactly the right frame count, no errors).

## Not verified

AVPlayer playing the stream (any codec), HDR and Dolby Vision switching, audio pass-through to a receiver, seeking while playing,
the 127.0.0.1 socket under tvOS rules (App Transport Security, local network permission is not needed for loopback but is untested),
memory on the device, long files (the 1.7 GB sample was used for the spikes, not for these tests), files with BlockGroups for
every frame, Matroska "ContentCompression" (header stripping is handled, zlib compression is not), DTS and TrueHD (need the
transcoder), subtitles (drawn by the app, not by this engine).
