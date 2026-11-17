# Build record of the vendored codec frameworks

The five frameworks in `../` were built by FFmpegBuild 3.15.0
(https://github.com/superuser404notfound/FFmpegBuild/tree/3.15.0). This folder keeps, unchanged, what that build used, so
the corresponding source of the LGPL libraries can be rebuilt (written offer: Settings > About > Open Source; docs/NAMES.md
section 4a):

- `build.sh`: the build script, as published in that tag.
- `patches/`: the patches applied to FFmpeg, as published in that tag.
- `BUILD-INFO.txt`: the build record written by `build.sh` (sources with tags and commits, configure lines, toolchain).

`build.sh` and `patches/` are third-party files kept byte for byte (their sha256 are in BUILD-INFO.txt); their comments
mention the upstream author's own projects. They are not edited, because they are the source the licence requires us to
offer. The upstream project README is not copied here; read it at the link above.
