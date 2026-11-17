#!/usr/bin/env bash
# Runs the SourceNFS tests against a real NFSv3 server, with the real libnfs, on Linux (WSL). No sudo.
#
#   bash scripts/test-nfs.sh            build libnfs if needed, start the server if needed, run the tests
#   bash scripts/test-nfs.sh build      only build libnfs
#   bash scripts/test-nfs.sh stop       stop the NFS server this script started
#
# What it uses (all tests only, nothing of this ships in the app):
#  - libnfs 5.0.2 source at the exact commit NFSKit's tvOS binary is built from
#    (https://github.com/sahlberg/libnfs, commit 465a12d45703d4c8b1ba534323f911cf28b71501), compiled with gcc
#    into $HOME/video-player-test-servers/libnfs. The machine needs git and gcc; cmake is NOT needed.
#  - `rclone serve nfs` (the same rclone as scripts/test-servers.sh) serving the shared test data, read-only,
#    NFSv3 on 127.0.0.1:12049 (rclone's NFS server has no MOUNT EXPORT call, so libnfs runs with
#    auto-traverse-mounts off; SourceNFS always does that).
# Environment: VP_MANIFEST=/path/Package.swift tests a manifest other than the repo's (used before the
# Package.swift change is merged).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
BASE="${VP_TEST_HOME:-$HOME/video-player-test-servers}"
LIBNFS_COMMIT=465a12d45703d4c8b1ba534323f911cf28b71501
SRC="$BASE/libnfs-src"; PFX="$BASE/libnfs"
PORT=12049
RCLONE="$BASE/bin/rclone"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 1; }; }

build_libnfs() {
  [ -f "$PFX/lib/libnfs.so" ] && [ -f "$PFX/lib/pkgconfig/libnfs.pc" ] && [ -f "$PFX/include/nfsc/libnfs.h" ] && return 0
  need git; need gcc; need ar
  mkdir -p "$SRC"; cd "$SRC"
  if [ ! -d .git ]; then git init -q; git remote add origin https://github.com/sahlberg/libnfs.git; fi
  git fetch -q --depth 1 origin "$LIBNFS_COMMIT"; git checkout -q FETCH_HEAD
  local OBJ="$BASE/libnfs-obj"; rm -rf "$OBJ"; mkdir -p "$OBJ" "$PFX/lib/pkgconfig" "$PFX/include"
  cat > "$OBJ/config.h" <<'CFG'
#define HAVE_ARPA_INET_H 1
#define HAVE_CLOCK_GETTIME 1
#define HAVE_NETDB_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_NETINET_TCP_H 1
#define HAVE_NET_IF_H 1
#define HAVE_POLL_H 1
#define HAVE_SOCKADDR_STORAGE 1
#define HAVE_SO_BINDTODEVICE 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRUCT_STAT_ST_MTIM_TV_NSEC 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_SYS_STATVFS_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_SYSMACROS_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_VFS_H 1
#define HAVE_UNISTD_H 1
#define HAVE_UTIME_H 1
#define MAJOR_IN_SYSMACROS 1
#define _FILE_OFFSET_BITS 64
CFG
  for f in lib/*.c mount/*.c nfs/*.c nfs4/*.c nlm/*.c nsm/*.c portmap/*.c rquota/*.c; do
    gcc -O2 -fPIC -w -DHAVE_CONFIG_H -D_U_='__attribute__((unused))' -include sys/uio.h \
      -I"$OBJ" -Iinclude -Iinclude/nfsc -I. -Imount -Infs -Infs4 -Inlm -Insm -Iportmap -Irquota \
      -c "$f" -o "$OBJ/$(echo "$f" | tr / _).o"
  done
  ar rcs "$PFX/lib/libnfs.a" "$OBJ"/*.o
  gcc -shared -o "$PFX/lib/libnfs.so.11" -Wl,-soname,libnfs.so.11 "$OBJ"/*.o
  ln -sf libnfs.so.11 "$PFX/lib/libnfs.so"
  cp -r include/nfsc "$PFX/include/"
  cat > "$PFX/lib/pkgconfig/libnfs.pc" <<PC
prefix=$PFX
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: libnfs
Description: libnfs built from source for tests
Version: 5.0.2
Libs: -L\${libdir} -lnfs
Cflags: -I\${includedir}
PC
  echo "libnfs built in $PFX"
}

server_up() { (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; }

start_server() {
  server_up && return 0
  [ -x "$RCLONE" ] || { echo "rclone not found at $RCLONE; run: bash scripts/test-servers.sh start" >&2; exit 1; }
  [ -d "$BASE/data" ] || bash "$HERE/scripts/test-servers.sh" start >/dev/null
  mkdir -p "$BASE/logs"
  setsid nohup "$RCLONE" serve nfs "$BASE/data" --addr 127.0.0.1:$PORT --read-only >"$BASE/logs/nfs.log" 2>&1 </dev/null &
  disown
  for _ in $(seq 1 20); do server_up && return 0; sleep 0.5; done
  echo "NFS server did not start; see $BASE/logs/nfs.log" >&2; exit 1
}

case "${1:-run}" in
  build) build_libnfs; exit 0 ;;
  stop) pkill -f "rclone serve nfs" 2>/dev/null || true; echo stopped; exit 0 ;;
esac

build_libnfs
start_server
WORK="${VP_BUILD_DIR:-$HOME/vp-build-nfs}"
mkdir -p "$WORK"
rsync -a --delete --exclude .build "$HERE/Packages/VideoPlayerCore/" "$WORK/" 2>/dev/null || { find "$WORK" -mindepth 1 -maxdepth 1 ! -name .build -exec rm -rf {} +; cp -r "$HERE/Packages/VideoPlayerCore/." "$WORK/"; }
[ -n "${VP_MANIFEST:-}" ] && cp "$VP_MANIFEST" "$WORK/Package.swift"
grep -q SourceNFS "$WORK/Package.swift" || { echo "Package.swift does not contain SourceNFS yet (see the NFS manifest snippet in docs/SOURCES.md or set VP_MANIFEST)." >&2; exit 1; }
cd "$WORK"
export VP_LIBNFS=1 PKG_CONFIG_PATH="$PFX/lib/pkgconfig" LD_LIBRARY_PATH="$PFX/lib" VP_NFS_HOST=127.0.0.1 VP_NFS_PORT=$PORT VP_NFS_EXPORT=/
swift test --filter SourceNFSTests "${@:2}"
