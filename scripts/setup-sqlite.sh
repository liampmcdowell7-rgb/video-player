#!/usr/bin/env bash
# Linux only (WSL). Makes `import CSQLite` linkable without root: downloads the libsqlite3-dev package
# (official Ubuntu archive, user space, `apt-get download` + `dpkg -x`) and puts a libsqlite3.so link in
# $HOME/video-player-test-servers/sqlite/lib, which Package.swift adds with -L on Linux.
# The runtime library (libsqlite3.so.0) is already installed on Ubuntu. On Apple platforms the SDK has SQLite3
# and none of this is used. The header in Sources/CSQLiteSystem/sqlite3.h is SQLite's own (public domain).
# Safe to run any number of times.
set -eu
BASE="${VP_TEST_HOME:-$HOME/video-player-test-servers}/sqlite"
LIB="$BASE/lib"
[ -e "$LIB/libsqlite3.so" ] && exit 0
RT="$(ls /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /usr/lib/aarch64-linux-gnu/libsqlite3.so.0 2>/dev/null | head -1)"
[ -n "$RT" ] || { echo "setup-sqlite: runtime libsqlite3.so.0 not found (install libsqlite3-0)" >&2; exit 1; }
mkdir -p "$LIB"
ln -sf "$RT" "$LIB/libsqlite3.so"
echo "setup-sqlite: linked $LIB/libsqlite3.so -> $RT"
