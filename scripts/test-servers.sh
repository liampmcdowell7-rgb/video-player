#!/usr/bin/env bash
# Starts and stops local test servers for the source integration tests (WSL / Linux, no admin needed).
#
#   bash scripts/test-servers.sh start     download rclone (first time only), make test media, start servers
#   bash scripts/test-servers.sh stop      stop everything this script started
#   bash scripts/test-servers.sh status    show what is running
#   bash scripts/test-servers.sh env       print the VP_* variables the integration tests read
#   bash scripts/test-servers.sh check     probe every running server with curl
#
# Other test servers have their own scripts: Jellyfin/Emby (test-mediaservers.sh), SMB (test-smb.sh),
# NFS (test-nfs.sh). `bash scripts/test-all.sh` runs every stage. The SFTP server below has no live
# client yet (the SSH library is not chosen); FTP, DLNA, WebDAV and HTTP are used by live tests.
#
# Everything lives under ~/video-player-test-servers (outside the project). Nothing is installed
# system-wide. All servers bind to 127.0.0.1 and use throwaway TEST credentials printed below.
#
# What runs here (real servers, user-space rclone):
#   WebDAV open       http://127.0.0.1:18081/
#   WebDAV Basic      http://127.0.0.1:18082/   (tester / testpass-local)
#   HTTP direct link  http://127.0.0.1:18083/
#   SFTP              127.0.0.1:12022           (tester / testpass-local)
#   FTP               127.0.0.1:12121           (tester / testpass-local)
#   UPnP/DLNA         http://127.0.0.1:17879/   (SSDP multicast does not cross into WSL reliably)
#
# What cannot run here without admin rights or large downloads (see docs/SOURCES.md):
#   SMB (Samba), NFS server, Jellyfin, Emby, Plex, cloud providers, Digest-auth WebDAV.
#   Those are covered by contract tests against recorded responses instead, and by device-only checks.
set -eu

BASE="${VP_TEST_HOME:-$HOME/video-player-test-servers}"
BIN="$BASE/bin"
DATA="$BASE/data"
RUN="$BASE/run"
LOGS="$BASE/logs"
USER_NAME="tester"
USER_PASS="testpass-local"

PORT_WEBDAV=18081
PORT_WEBDAV_BASIC=18082
PORT_HTTP=18083
PORT_SFTP=12022
PORT_FTP=12121
PORT_DLNA=17879

mkdir -p "$BIN" "$DATA" "$RUN" "$LOGS"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 1; }; }

install_rclone() {
  [ -x "$BIN/rclone" ] && return 0
  need curl; need unzip
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo "Unsupported CPU: $(uname -m)" >&2; exit 1 ;;
  esac
  echo "Downloading rclone (user-space, one time, about 20 MB)..."
  version="$(curl -fsS https://downloads.rclone.org/version.txt | awk '{print $2}')"   # e.g. v1.68.2
  name="rclone-${version}-linux-${arch}"
  tmp="$(mktemp -d)"
  curl -fsS -o "$tmp/$name.zip" "https://downloads.rclone.org/${version}/${name}.zip"
  curl -fsS -o "$tmp/SHA256SUMS" "https://downloads.rclone.org/${version}/SHA256SUMS"
  expected="$(grep " ${name}.zip\$" "$tmp/SHA256SUMS" | awk '{print $1}')"
  actual="$(sha256sum "$tmp/$name.zip" | awk '{print $1}')"
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "Checksum mismatch for $name.zip. Not installing." >&2; rm -rf "$tmp"; exit 1
  fi
  unzip -q -o "$tmp/$name.zip" -d "$tmp"
  cp "$tmp/$name/rclone" "$BIN/rclone"
  chmod +x "$BIN/rclone"
  rm -rf "$tmp"
  echo "rclone $("$BIN/rclone" version | head -1) installed in $BIN (checksum verified)"
}

# Deterministic test media (make_file, make_media): byte k of every file is (k*7+3) mod 251, so tests can check any
# offset. The code lives in a shared file so scripts/test-mediaservers.sh creates the same media on its own.
. "$(dirname "${BASH_SOURCE[0]}")/lib-testmedia.sh"

pidfile() { echo "$RUN/$1.pid"; }
is_running() { [ -f "$(pidfile "$1")" ] && kill -0 "$(cat "$(pidfile "$1")")" 2>/dev/null; }

start_one() { # name, then the rclone arguments
  name="$1"; shift
  if is_running "$name"; then echo "  $name already running"; return 0; fi
  # Close every inherited descriptor above 2 first: a server that outlives this script must not keep a caller's
  # lock file (for example the shared WSL test lock) open, or the next locked run waits for the server to stop.
  (
    for fd in /proc/$BASHPID/fd/*; do
      fd=${fd##*/}
      [ "$fd" -gt 2 ] 2>/dev/null && eval "exec $fd>&-"
    done
    exec nohup setsid "$BIN/rclone" "$@" >"$LOGS/$name.log" 2>&1
  ) &
  echo $! > "$(pidfile "$name")"
}

wait_port() { # port
  for _ in $(seq 1 40); do
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3>&- 2>/dev/null || true; return 0; }
    sleep 0.25
  done
  return 1
}

cmd_start() {
  install_rclone
  make_media
  start_one webdav       serve webdav "$DATA" --addr "127.0.0.1:$PORT_WEBDAV" --read-only
  start_one webdav-basic serve webdav "$DATA" --addr "127.0.0.1:$PORT_WEBDAV_BASIC" --read-only --user "$USER_NAME" --pass "$USER_PASS"
  start_one http         serve http   "$DATA" --addr "127.0.0.1:$PORT_HTTP" --read-only
  start_one sftp         serve sftp   "$DATA" --addr "127.0.0.1:$PORT_SFTP" --read-only --user "$USER_NAME" --pass "$USER_PASS"
  start_one ftp          serve ftp    "$DATA" --addr "127.0.0.1:$PORT_FTP" --read-only --user "$USER_NAME" --pass "$USER_PASS"
  start_one dlna         serve dlna   "$DATA" --addr "127.0.0.1:$PORT_DLNA" --name "VP Test Media"
  ok=1
  for pair in "webdav:$PORT_WEBDAV" "webdav-basic:$PORT_WEBDAV_BASIC" "http:$PORT_HTTP" "sftp:$PORT_SFTP" "ftp:$PORT_FTP" "dlna:$PORT_DLNA"; do
    n="${pair%%:*}"; p="${pair##*:}"
    if wait_port "$p"; then echo "  up    $n (port $p)"; else echo "  FAILED $n (port $p) - see $LOGS/$n.log"; ok=0; fi
  done
  [ "$ok" = 1 ] || exit 1
}

cmd_stop() {
  for f in "$RUN"/*.pid; do
    [ -e "$f" ] || continue
    n="$(basename "$f" .pid)"
    if kill -0 "$(cat "$f")" 2>/dev/null; then kill "$(cat "$f")" 2>/dev/null || true; echo "  stopped $n"; fi
    rm -f "$f"
  done
}

cmd_status() {
  any=0
  for n in webdav webdav-basic http sftp ftp dlna; do
    if is_running "$n"; then echo "  running $n (pid $(cat "$(pidfile "$n")"))"; any=1; else echo "  stopped $n"; fi
  done
  [ "$any" = 1 ] || true
}

cmd_env() {
  cat <<EOF
export VP_WEBDAV_URL=http://127.0.0.1:$PORT_WEBDAV/
export VP_WEBDAV_BASIC_URL=http://127.0.0.1:$PORT_WEBDAV_BASIC/
export VP_HTTP_URL=http://127.0.0.1:$PORT_HTTP/
export VP_SFTP_HOST=127.0.0.1
export VP_SFTP_PORT=$PORT_SFTP
export VP_FTP_HOST=127.0.0.1
export VP_FTP_PORT=$PORT_FTP
export VP_DLNA_URL=http://127.0.0.1:$PORT_DLNA/
export VP_TEST_USER=$USER_NAME
export VP_TEST_PASS=$USER_PASS
EOF
}

cmd_check() {
  need curl
  code() { curl -s -o /dev/null -w '%{http_code}' "$@" || true; }
  echo "  webdav open   PROPFIND        -> $(code -X PROPFIND -H 'Depth: 1' "http://127.0.0.1:$PORT_WEBDAV/")  (want 207)"
  echo "  webdav basic  no credentials  -> $(code -X PROPFIND -H 'Depth: 1' "http://127.0.0.1:$PORT_WEBDAV_BASIC/")  (want 401)"
  echo "  webdav basic  with credentials-> $(code -u "$USER_NAME:$USER_PASS" -X PROPFIND -H 'Depth: 1' "http://127.0.0.1:$PORT_WEBDAV_BASIC/")  (want 207)"
  echo "  webdav range  bytes=100-103   -> $(code -H 'Range: bytes=100-103' "http://127.0.0.1:$PORT_WEBDAV/Movies/Test%20Movie%20(2020).mkv")  (want 206)"
  echo "  http   range  bytes=0-9       -> $(code -H 'Range: bytes=0-9' "http://127.0.0.1:$PORT_HTTP/Movies/Test%20Movie%20(2020).mkv")  (want 206)"
  echo "  dlna   description            -> $(code "http://127.0.0.1:$PORT_DLNA/rootDesc.xml")  (want 200)"
  curl -s -o /dev/null -w "  webdav sustained read of 40 MB over loopback: %{speed_download} bytes/s\n" \
    "http://127.0.0.1:$PORT_WEBDAV/big/Large%20Sample.mkv" || true
  echo "  (loopback speed only shows the test machine is not the limit; real network speed needs the device)"
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  env) cmd_env ;;
  check) cmd_check ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
