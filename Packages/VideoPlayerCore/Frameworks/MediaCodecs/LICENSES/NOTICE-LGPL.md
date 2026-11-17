# Codec library notice (LGPL-2.1-or-later)

The app links the following libraries dynamically, as separate frameworks inside the app bundle:

| Framework | Library | Version | Licence |
|---|---|---|---|
| AetherLibavcodec | FFmpeg libavcodec | n8.1.3 (libavcodec 62.28.103) | LGPL-2.1-or-later (LGPL-2.1.txt) |
| AetherLibavutil | FFmpeg libavutil | n8.1.3 | LGPL-2.1-or-later |
| AetherLibswresample | FFmpeg libswresample | n8.1.3 | LGPL-2.1-or-later |
| AetherLibdav1d | dav1d (linked by libavcodec) | see upstream-build-record/BUILD-INFO.txt | BSD-2-Clause (dav1d.BSD-2-Clause.txt) |
| AetherLibzvbi | libzvbi (linked by libavcodec) | see upstream-build-record/BUILD-INFO.txt | LGPL-2.1-or-later, parts MIT (libzvbi-ure.MIT.txt) |

The frameworks are the prebuilt output of FFmpegBuild 3.15.0 (https://github.com/FFmpegBuild/FFmpegBuild, licence in
FFmpegBuild-LICENSE-LGPL-2.1.txt). FFmpeg was configured without `--enable-gpl`, `--enable-version3` and `--enable-nonfree`;
the full configure lines are in ../upstream-build-record/BUILD-INFO.txt.

## Source code (LGPL-2.1 section 6)

- FFmpeg n8.1.3: https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n8.1.3.tar.gz
  (16,906,107 bytes, sha256 09f990289327d3ebfedf4fc15cae3f884a65dab7a5aac7bbb5b01ff83900efd9).
- Changes applied to it: the patches in ../upstream-build-record/patches/ (their sha256 are in BUILD-INFO.txt).
- The build script that produced the frameworks: ../upstream-build-record/build.sh.

PROVISIONAL (the owner decides before release): how the source is provided under section 6, either shipped alongside
the app download (6a/6d) or a written offer valid for three years (6c). Nothing is promised by this file yet.

## Replacing the library (LGPL-2.1 section 6)

The libraries are dynamic frameworks loaded at run time through their install names, and the app calls only their public
API (through the small C layer in Sources/CMediaCodecs). A modified build of the same version with the same framework names
and compatible API can be put in their place in the app bundle and the bundle re-signed.

## Where the app shows this

The licence text and this notice must also be reachable from inside the app (Settings > About, licences). That screen is
outside the audio work; see docs/AUDIO_PIPELINE.md, "Not done".
