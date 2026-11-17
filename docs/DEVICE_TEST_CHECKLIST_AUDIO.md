# Device test checklist: audio decoding (DTS, DTS-HD, Dolby TrueHD, Opus, Vorbis to FLAC)

Nothing below has run on a device. The Linux tests (docs/AUDIO_PIPELINE.md) prove the decode and the FLAC repackaging are
bit-exact; they cannot prove what the Apple TV player accepts or what leaves the HDMI port. Use an Apple TV 4K (3rd
generation, and 2nd generation where noted), tvOS 27, a receiver that shows the incoming format and sample rate, and the
test files made by `bash scripts/test-audio.sh media` (copied to a source the app can read). Write the result next to each line.

| ID | Steps | Expected | Result |
|---|---|---|---|
| AU-1 | Build the app with the vendored frameworks (Release, device). Inspect the .app: Frameworks/ holds the five Aether*.framework bundles, signed | Builds; the frameworks are embedded (dynamic) and signed; App Store validation accepts them | |
| AU-2 | Play `dtshd_ma_71_24_48k.mkv` over HDMI to a 7.1 receiver | 7.1 multichannel PCM at 48 kHz on the receiver; channel check: each speaker gets its own channel (use a channel-ident file, AU-14); status line "7.1 PCM (decoded)"; Playback Stats lists "DTS-HD Master Audio 7.1, decoded losslessly to FLAC (24-bit, 48 kHz)" | |
| AU-3 | Play `dtshd_ma_71_24_96k.mkv` (96 kHz) over HDMI | Plays without dropouts. Record the rate the receiver shows (48 or 96 kHz): this answers the open question in QUALITY_CEILINGS.md (Audio). Status note says the system does not report the output rate | |
| AU-4 | Play `dtshd_ma_51_16_192k.mkv` (192 kHz) and `truehd_enc_2ch_24_192k.mkv` over HDMI; repeat on a 2nd generation Apple TV | Plays; record the receiver rate. If 192 kHz FLAC does not play at all on either model, report it: the `maxSampleRate` setting (AudioDecode) is the fallback | |
| AU-5 | Play `dts_core_51_48k.mkv` and `dts_es_61.mkv` | 5.1 / 6.1 PCM; status names DTS; no "lossless" in Playback Stats | |
| AU-6 | Play `truehd_atmos_fate.mkv` on an Atmos receiver | 7.1 PCM, NOT Atmos on the receiver; note "the Atmos objects are not played, only the 7.1 bed" | |
| AU-7 | Play `truehd_51_fate.mkv` with Settings > Playback > "Play the Dolby Digital Core of Dolby TrueHD" off, then on (a TrueHD file with an embedded Dolby Digital core from a Blu-ray remux: no LGPL tool makes one, the Linux test interleaves `raw_truehd_51.thd` and `raw_ac3_51.ac3`) | Off: 5.1 PCM decoded, lossless. On: receiver shows Dolby Digital 5.1; status "Dolby Digital 5.1 (TrueHD core, passthrough)" | |
| AU-8 | Play `opus_8ch.mkv`, `vorbis_6ch.mkv` | 7.1 / 5.1 PCM; status names Opus / Vorbis | |
| AU-9 | Play each of AU-2, AU-6, AU-8 over AirPlay to a HomePod pair and over Bluetooth headphones | Plays (stereo or what the route takes); the status says decoded and downmixed; record what AirPlay receives | |
| AU-10 | Play over a TV on ARC (not eARC) | Plays as PCM stereo (or what ARC passes); no Atmos claim | |
| AU-11 | Make a copy of `truehd_51_fate.mkv` with bytes overwritten in the middle (for example `dd` 4 KB of zeros at 50%) | No crash, no long silence: short silences where frames were damaged; Playback Stats shows "N damaged frame(s) were replaced by silence" | |
| AU-12 | Play `fallback_three_tracks.mkv` with the decoder library removed (debug build with `audioTranscoder` nil) | Alert "Playing a Different Audio Track": "The DTS track (track 2) could not be decoded, so the Dolby Digital Stereo track plays instead." (same language, English, ranks above more channels; PROVISIONAL rule). Sound plays | |
| AU-13 | Seek repeatedly (10 times, forwards and back) in AU-2 and AU-6 | Audio resumes within the usual seek time each time, in sync with the picture (lip sync within one frame by eye) | |
| AU-14 | Play a 7.1 channel-ident file in DTS-HD MA and in TrueHD (each channel speaks its name) | Every name comes from the right speaker. A wrong side/back pair means the FLAC 7.1 order is read differently by the device: report it | |
| AU-15 | CPU: play AU-2 and AU-6 for 10 minutes with Instruments (Time Profiler) attached | Record the app's CPU share for the audio decode thread. Estimate in AUDIO_PIPELINE.md: under 10% of one core (UNMEASURED on device) | |
| AU-16 | Play a 2-hour DTS-HD MA film to the end | No drift between audio and picture at the end; no growth in memory | |
