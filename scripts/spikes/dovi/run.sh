#!/usr/bin/env bash
# Dolby Vision P7 -> P8.1 cost spike. Linux/WSL only, user-space (no sudo). Result doc: docs/spikes/DOLBY_VISION_P7.md
# Usage: bash scripts/spikes/dovi/run.sh [passes-over-the-2400-RPUs, default 100]
# Needs: git, a Rust toolchain (cargo), gcc. Network is used once, to clone quietvoid/dovi_tool from GitHub.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="${VP_DOVI_HOME:-$HOME/vp-dovi}"
PASSES="${1:-100}"
mkdir -p "$W"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# 1. libdovi source (crate `dolby_vision`, MIT) and the dovi_tool CLI
if [ ! -d "$W/src/.git" ]; then git clone --depth 1 https://github.com/quietvoid/dovi_tool.git "$W/src"; fi
git -C "$W/src" rev-parse HEAD > "$W/src.commit"
grep -m1 '^version' "$W/src/dolby_vision/Cargo.toml" | tee "$W/libdovi.version"

# 2. static libdovi with the C API. panic=abort matches how a tvOS XCFramework would be built.
( cd "$W/src/dolby_vision" && CARGO_PROFILE_RELEASE_PANIC=abort cargo build --release --features capi )
LIB="$W/src/dolby_vision/target/release/libdolby_vision.a"
ls -l "$LIB"
sha256sum "$LIB" > "$W/libdolby_vision.a.sha256"

# 3. synthetic P7 FEL RPUs (dovi_tool `generate` cannot make profile 7; this builds them from the library's own structs)
rm -rf "$W/gen_p7"; cp -r "$HERE/gen_p7" "$W/gen_p7"
( cd "$W/gen_p7" && cargo run --release -- 2400 "$W/p7_rpus.bin" )

# 4. the C harness, linked against libdovi
gcc -O2 -Wall -o "$W/bench" "$HERE/bench.c" "$LIB" -lpthread -ldl -lm
{ echo "== host"; uname -srm; grep -m1 'model name' /proc/cpuinfo; nproc; gcc --version | head -1; rustc --version; } | tee "$W/host.txt"

# 5. run (pinned to one core when taskset exists, to keep the numbers steady)
if command -v taskset >/dev/null; then PIN="taskset -c 2"; else PIN=""; fi
$PIN "$W/bench" "$W/p7_rpus.bin" "$PASSES" | tee "$W/results.txt"
