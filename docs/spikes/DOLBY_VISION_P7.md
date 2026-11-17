# Spike: what does Dolby Vision Profile 7 → 8.1 conversion cost?

Status: measured on a PC under WSL2, not on an Apple TV. Date: 2026-11-16. Nothing here changes the app.

## 1. Question

If the app converts Dolby Vision Profile 7 (dual layer, UHD Blu-ray style) to Profile 8.1 with libdovi, how much CPU time does that take per second of video, and is that plausible on an Apple TV?

Not part of this question (see section 9): the picture quality lost by dropping a full enhancement layer (FEL), and whether tvOS accepts the converted stream.

## 2. Method

1. **Source of the code.** libdovi is the Rust crate `dolby_vision` in quietvoid/dovi_tool (MIT), built with its `capi` feature into a static library. The same repository provides the `dovi_tool` CLI.
2. **Test data.** `dovi_tool generate` cannot make Profile 7: `dovi_tool generate --help` lists `--profile` values `5, 8.1, 8.4` only. So `scripts/spikes/dovi/gen_p7` builds synthetic P7 FEL RPUs with libdovi's own structures (profile 7, 10-bit base, `el_spatial_resampling_filter_flag` set, residual enabled, non-trivial NLQ block, polynomial coefficients varied per RPU). Each RPU is serialised with `write_hevc_unspec62_nalu` (0x7C01 NAL header, emulation prevention) and re-parsed to check it reads back as profile 7 FEL. 2400 RPUs are generated (100 s at 24 fps).
3. **Harness.** `scripts/spikes/dovi/bench.c` calls the libdovi C API: `dovi_parse_unspec62_nalu` → `dovi_convert_rpu_with_mode(…, 2)` (mode 2 = to 8.1) → `dovi_write_unspec62_nalu`. Declarations are written by hand because the crate does not ship the header here. Before timing, RPU 0 is converted and re-parsed to check it is profile 8 with no EL type (the run aborts otherwise); during timing every call is checked only for a zero return code and non-null output.
4. **Timing.** `clock_gettime(CLOCK_MONOTONIC)` around each stage of each call (240,000 calls = 100 passes × 2400 RPUs; mean, p50, p99, max), plus `CLOCK_THREAD_CPUTIME_ID` over the whole loop for the CPU figure, plus `getrusage` for peak RSS. The process is pinned to one core with `taskset`.
5. **Surrounding work.** A synthetic 4K P7 stream is built in memory: 240 access units at 24 fps, 4 base-layer slice NALs (type 1 or 19) of random bytes + one enhancement-layer NAL (type 63) + one RPU NAL (type 62, the real synthetic RPUs). Sizes: base ≈ 80 Mbps, EL ≈ 20 Mbps, per-frame size varied 0.5×–1.5×. Measured result: 98.7 Mbps, 12.3 MB/s. Payload bytes are never 0x00, so no accidental start codes. Five variants are timed per access unit (40 passes):
   - A: length-prefixed (MKV / MP4 `hvcC` style), walk the NAL lengths only.
   - B: length-prefixed, drop type 63, copy the rest, RPU untouched.
   - C: as B, but the RPU goes through libdovi.
   - D: Annex-B (start codes), `memchr` scan, drop type 63, copy, RPU untouched.
   - E: as D, with libdovi conversion.

## 3. Exact commands

```bash
bash scripts/spikes/dovi/run.sh 100
```

`run.sh` clones `https://github.com/quietvoid/dovi_tool.git` into `~/vp-dovi/src` (depth 1), builds `libdolby_vision.a` with `CARGO_PROFILE_RELEASE_PANIC=abort cargo build --release --features capi`, builds and runs `gen_p7`, compiles with `gcc -O2 -Wall -o bench bench.c libdolby_vision.a -lpthread -ldl -lm`, and runs `taskset -c 2 ./bench p7_rpus.bin 100`. It writes `host.txt`, `results.txt`, `src.commit` and checksums under `~/vp-dovi`. This run was started from Windows with `wsl -d Ubuntu -- bash /mnt/c/<path to repo>/scripts/spikes/dovi/run.sh 100`. (The dovi_tool clone and library build had been done in an earlier step of the same spike, so the build lines in `run.sh` reused them; the timing results come from this final run.)

Versions and checksums of this run:

| Item | Value |
|---|---|
| dovi_tool repo commit | d1abe0e27ff2c7ab3339614d06db9f8a058af6b2 (main; the `libdovi-3.4.0` tag was not found, crate version reads 3.4.0) |
| `dolby_vision` crate | 3.4.0, edition 2024, MIT |
| `libdolby_vision.a` | 25,515,982 bytes, sha256 75226a149e506d00d45924820aadfd22354ccf8b021c240ee8b5ef1e099ebf4e (static library, release profile, panic=abort) |
| `p7_rpus.bin` | 984,000 bytes, sha256 0f27bb09fdeec87c1365cbd07ce2ec9e72abefb80281a84d8fddf9f33e804df8 |
| `dovi_tool` CLI binary | 2.3.4, 4,088,792 bytes, sha256 619d4cd4e14781257a3e7f39973332eedafd9d155fd7a9b844614e29b2b86fc4 (used only to check `generate` options; not used for timing) |
| Toolchain | rustc 1.100.0, cargo 1.100.0, gcc 15.2.0 |
| Host | Intel Core i5-8500T @ 2.10 GHz (6 cores), Linux 6.18.58.1-microsoft-standard-WSL2 x86_64 (WSL2 on Windows 11) |

## 4. Results

### 4.1 libdovi alone (240,000 conversions, 2400 distinct RPUs)

Input RPU mean 406 bytes, output mean 140 bytes (RPU 0: 406 → 139 bytes, profile 7 FEL → profile 8, no EL).

| Stage | mean µs | p50 µs | p99 µs | max µs |
|---|---|---|---|---|
| parse | 8.24 | 5.40 | 22.40 | 12016.86 |
| convert (mode 2) | 0.35 | 0.30 | 0.60 | 3814.22 |
| write (+ emulation prevention) | 2.46 | 1.60 | 4.30 | 12613.97 |
| parse + convert + write | 11.05 | 7.30 | 31.90 | 12619.87 |

Thread CPU time per RPU: 11.37 µs (wall 11.44 µs, so the timer overhead is small). The max column is a scheduler or page-fault outlier on WSL2 (a handful of calls out of 240,000), not a property of the code. p99 is the number to design against.

| Rate | CPU per video-second | Share of one core | Per-frame cost vs frame budget |
|---|---|---|---|
| 24 fps | 0.273 ms | 0.027 % | 11.4 µs of 41.67 ms = 0.027 % |
| 60 fps | 0.682 ms | 0.068 % | 11.4 µs of 16.67 ms = 0.068 % |

p99 per frame (31.9 µs) is 0.077 % of the 41.67 ms budget at 24 fps.

Memory: the harness's own timing arrays account for about 7.7 MB of the 9.4 MB peak RSS growth seen in this run, so libdovi's own working memory was **not separated out and is not measured**. Parse allocates and frees a small heap structure per RPU; nothing is retained between calls (the loop frees every result; no growth beyond the harness arrays is visible, but this is an inference, not a leak test).

### 4.2 Surrounding per-sample work (synthetic 4K, 98.7 Mbps, 24 fps, 240 access units × 40 passes)

| Variant | mean µs / frame | p99 µs | max µs | CPU ms per video-second at 24 fps |
|---|---|---|---|---|
| A length-prefixed, walk NAL lengths only | 0.3 | 0.9 | 26.4 | 0.01 |
| B length-prefixed, drop EL + copy, RPU untouched | 76.5 | 335.9 | 11,497.8 | 1.84 |
| C length-prefixed, drop EL + copy + libdovi | 89.2 | 711.1 | 10,419.0 | 2.14 |
| D Annex-B `memchr` scan, drop EL + copy, RPU untouched | 180.1 | 1800.6 | 13,061.7 | 4.31 |
| E Annex-B `memchr` scan, drop EL + copy + libdovi | 209.7 | 2620.2 | 21,911.0 | 5.00 |

Reading it:

- Converting the RPU adds about 12.7 µs per frame (C − B), consistent with the 11 µs measured in 4.1.
- Almost all of the cost is memory copy of ≈ 10 MB/s of surviving base-layer bytes (about 10 MB/s, roughly 420 KB per frame), not parsing.
- Walking length-prefixed NALs to find type 62 and 63 is negligible (0.3 µs per frame).
- Annex-B is 2.4× slower than length-prefixed here. Part of that is the synthetic payload: random bytes 1–255 contain 0x01 about once per 255 bytes, so `memchr` stops very often. Real HEVC contains far fewer 0x01 bytes preceded by two zeros, but also far more zero runs; the Annex-B figures are therefore **indicative only**. A production scanner would use a SIMD or word-at-a-time start-code search.
- Holding both layouts of the 10 s stream cost 234 MB RSS in the harness; that is test scaffolding, not an app figure.

### 4.3 What the cost is relative to

Using the i5-8500T figures above as the reference (X on this CPU → % of frame budget):

| Work | This CPU, per frame | % of 41.67 ms (24 fps) | % of 16.67 ms (60 fps) |
|---|---|---|---|
| libdovi parse + convert + write (mean) | 11.4 µs | 0.03 % | 0.07 % |
| same, p99 | 31.9 µs | 0.08 % | 0.19 % |
| length-prefixed drop-EL copy + convert (C, mean) | 89 µs | 0.21 % | 0.54 % |
| C, p99 | 711 µs | 1.7 % | 4.3 % |
| Annex-B drop-EL copy + convert (E, mean) | 210 µs | 0.50 % | 1.3 % |
| E, p99 | 2.6 ms | 6.3 % | 15.7 % |

## 5. How representative is the synthetic RPU?

Honest limits:

- The RPUs were built by this spike, not taken from a disc. They are valid to libdovi (they parse back as profile 7, FEL) but their field values are invented.
- Size: mean 406 bytes. The size of RPUs on real UHD Blu-ray remuxes is **unverified**; no real RPU was read. Real RPUs can be larger with more mapping pieces or extension metadata blocks. Parse cost scales with bytes and fields, so the useful scaling is ≈ 28 ns per input byte (11.37 µs / 406 B). A real RPU 3× larger would be about 34 µs, still 0.08 % of a 24 fps frame.
- The extension-metadata blocks emitted by the generator were not enumerated; real streams carry per-shot and per-frame level blocks that this data may not match.
- Conversion mode 2 drops the P7 mapping and NLQ data, so convert cost is tiny whatever the input; the cost is parse and write, which depend on size.
- Only FEL-shaped RPUs were generated. Minimal enhancement layer (MEL) discs were not tested.

## 6. Plausibility on Apple TV

**Verdict: the libdovi step itself is plausible with high confidence (about 90 %), on arithmetic alone. Whole-pipeline plausibility is medium-high (about 75 %), because it depends on where the app can rewrite samples and on the copy cost.**

Reasoning, stated as arithmetic and not as a claim about the device:

- Apple TV CPU single-thread speed relative to the i5-8500T (at WSL2 Linux) is **UNVERIFIED**: no source was read for it and no Apple TV number is used. Do not read the table in 4.3 as an Apple TV figure.
- As a sensitivity check only, if the Apple TV core were 10× slower than this one on this workload, libdovi would cost about 114 µs per frame (0.27 % of a 24 fps frame), and the length-prefixed pipeline (C) about 0.9 ms (2.1 %), and Annex-B (E) about 2.1 ms (5 %), all on one core, off the render path. The 10× is a stress assumption, not a measurement.
- At 98.7 Mbps the copy is about 12 MB/s, which is small next to memory bandwidth, and the app needs the same copy for any remux to fragmented MP4 anyway (spike F1), so the incremental cost of P7 handling is the drop of NAL 63 plus ≈ 11 µs per frame.
- p99 numbers are dominated by WSL2 scheduling and cache effects; on a device, thermal state and background load matter more than the mean.

What could still make it not plausible even if the CPU cost is small: the stream rewrite point. AVPlayer plays a file URL or HLS; it does not hand the app the samples. Converting RPUs means the app must own the demux and remux stage (for example local fragmented MP4 / HLS served by the app). If the app does not already do that for the file, the cost to add it is far larger than this spike's numbers. This was not measured here.

## 7. What a device measurement needs

1. A tvOS (or iOS/macOS for a first approximation) test target that links libdovi (see section 10) and calls the same four functions on a real captured P7 RPU set.
2. Real P7 RPUs: extracted from a stream the owner has the right to use, with `dovi_tool extract-rpu`, and their size distribution recorded.
3. Measure with `ProcessInfo.systemUptime`/`mach_absolute_time` per call and `task_thread_basic_info` or `getrusage` for CPU; at least 100 passes; report mean and p99 as here.
4. Run on an Apple TV 4K with the screen on and playback running, on release builds, with thermal state recorded (`ProcessInfo.thermalState`).
5. Repeat the surrounding copy test with a real MKV/MP4 demux, at the highest bitrate the user has (the 100 Mbps figure here is an assumption of the brief, not a measured file).
6. Compare with the same code on the dev Mac to get a measured ratio; only then can any "relative to this CPU" claim be made.

## 8. Not tested

- No real Dolby Vision file was parsed or converted. No `dovi_tool` CLI conversion of a stream was run (the CLI was used only for its help output).
- No video decode, no AVFoundation, no tvOS code.
- libdovi was built for x86_64 Linux only.
- Multi-thread behaviour (one thread was used; libdovi calls are independent per RPU, so parallelism was not needed).

## 9. Explicitly not answered

- **FEL quality loss.** Converting to 8.1 discards the enhancement layer and the NLQ mapping, so FEL detail is lost. How visible that is on a real disc was not measured and is not claimed.
- **Whether tvOS accepts the output.** Not tested. It is not known whether a P8.1-converted stream with `dvcC`/`dvvC` configuration plays as Dolby Vision on Apple TV, or which other box fields it needs.
- **Per-title behaviour.** Titles with only MEL, with mixed profile changes, or with irregular RPU placement were not tested.

## 10. What building libdovi as a tvOS XCFramework needs (list only, nothing built)

From the repository files read (`dolby_vision/Cargo.toml` has `[package.metadata.capi.*]` for cargo-c and `cbindgen.toml` is present); none of this was tried:

- A Mac with Xcode (command-line tools for `lipo` and `xcodebuild -create-xcframework`). Not possible from WSL.
- A Rust toolchain with Apple tvOS targets. `aarch64-apple-tvos` and `aarch64-apple-tvos-sim` have no prebuilt standard library as far as I know (tier 3), which means a nightly toolchain with `-Zbuild-std`; this is **unverified** and must be checked on a Mac.
- `cargo-c` (`cargo cbuild --features capi`) or cbindgen to generate the C header, since a header is not shipped in the build output.
- `-Cpanic=abort` (set in the crate's capi metadata), and `rust-version` 1.88 or newer.
- One static library per slice (device arm64, simulator arm64, and x86_64 if an Intel simulator is needed), a header and a module map, combined into an `.xcframework`; then a `.binaryTarget` in `Package.swift`.
- A build step that fits the project's own rule on native libraries (docs/SOURCES.md): prebuilt binary, recorded source commit and checksum.
- A licence note: the crate is MIT. Whether using Dolby Vision output requires any Dolby licence or certification for a distributed app was not investigated.

## 11. Files

- `scripts/spikes/dovi/run.sh`: the whole run.
- `scripts/spikes/dovi/bench.c`: the C harness and the surrounding-cost harness.
- `scripts/spikes/dovi/gen_p7/` (`Cargo.toml`, `src/main.rs`): the synthetic P7 RPU generator. Its `Cargo.toml` resolves `dolby_vision` through a relative path, so it only builds after `run.sh` has copied it next to the `src` clone.
