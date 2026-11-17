#!/usr/bin/env bash
# Runs a real Jellyfin or Emby server in user space (no sudo, no outside account) for integration tests.
#
#   bash scripts/test-mediaservers.sh setup jellyfin|emby   download and unpack (first time only)
#   bash scripts/test-mediaservers.sh start jellyfin|emby   start, finish the first-run wizard, add the test library
#   bash scripts/test-mediaservers.sh stop                  stop both
#   bash scripts/test-mediaservers.sh env jellyfin|emby     print VP_* variables (token included)
#
# Both listen on 127.0.0.1:8096, so run one at a time. `start` creates the test media itself every time
# (scripts/lib-testmedia.sh, the same files scripts/test-servers.sh serves), so nothing else has to run first.
#
# Why every setup call goes through `http` below: right after (re)start a server answers /System/Info/Public with 200
# while it is still migrating its database, and answers everything else with HTTP 503 (an HTML "starting" page).
# The old script retried only 8 times and ignored every status, so on a loaded machine the wizard calls, the sign-in
# and the library add all failed silently and the scan "found nothing". Now each call waits up to 120 s for a 2xx,
# stops at a real 4xx, and fails with the status and body.
# What was downloaded (official sources only):
#   Jellyfin 12.4 generic tarball      https://repo.jellyfin.org/files/server/linux/latest-stable/amd64/  (113,075,397 bytes)
#   jellyfin-ffmpeg 7.1.4-3 portable   https://repo.jellyfin.org/files/ffmpeg/linux/latest-7.x/amd64/    (58,599,712 bytes)
#   libicu78 .deb (ICU, unpacked only) Ubuntu archive via `apt-get download` (no root needed)             (11.5 MB)
#   Emby Server 4.10.2.0 .deb          https://github.com/MediaBrowser/Emby.Releases/releases/        (247,007,280 bytes, unpacked only)
set -eu
BASE="${VP_TEST_HOME:-$HOME/video-player-test-servers}"
DATA="$BASE/data"
USER_NAME="tester"; USER_PASS="testpass-local"
PORT=8096
JF="$BASE/jellyfin"; EM="$BASE/emby"; ICU="$BASE/icu"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 1; }; }
wait_up() { # path
  for _ in $(seq 1 90); do
    [ "$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT$1")" = 200 ] && return 0; sleep 1
  done; return 1
}
json() { python3 -c "import sys,json;print(json.load(sys.stdin)$1)"; }
. "$(dirname "${BASH_SOURCE[0]}")/lib-testmedia.sh"

# http DESCRIPTION CURL-ARGS... : prints the body on 2xx. Waits (up to 120 s) while the server answers 5xx or nothing
# (still starting); stops at once on a 4xx. On failure prints the reason, status and the start of the body, returns 1.
http() {
  local what="$1"; shift
  local out code="000" i; out="$(mktemp)"
  for i in $(seq 1 120); do
    code="$(curl -s -m 20 -o "$out" -w '%{http_code}' "$@" 2>/dev/null || true)"; code="${code:-000}"
    case "$code" in
      2??) cat "$out"; rm -f "$out"; return 0 ;;
      5??|000) sleep 1 ;;
      *) break ;;
    esac
  done
  echo "FAILED: $what: HTTP $code after $i attempt(s); body starts: $(head -c 200 "$out" | tr '\n\r' '  ')" >&2
  rm -f "$out"; return 1
}

wait_items() { # base-url auth-header : wait until the library scan has found videos
  # A server runs a startup library scan right after the wizard; a "refresh" asked for while that scan runs is ignored,
  # so the first scan can finish before the new library was added and the items never appear (MOST LIKELY cause of the
  # 2026-11-17 failure, R81; the failed run's server log was overwritten, so this is not proven). So ask for a refresh again every 15 s until items show up; the whole wait stays 120 s.
  local n="0" i
  for i in $(seq 1 120); do
    [ $((i % 15)) -eq 1 ] && curl -s -m 10 -X POST -H "$2" "$1/Library/Refresh" >/dev/null 2>&1
    n="$(curl -s -m 5 -H "$2" "$1/Items?Recursive=true&IncludeItemTypes=Video,Movie,Episode&Limit=1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("TotalRecordCount",0))' 2>/dev/null || echo 0)"
    [ "${n:-0}" -gt 0 ] && return 0; sleep 1
  done
  echo "FAILED: library scan found nothing after 120 s (media folder $DATA holds $(find "$DATA" -type f 2>/dev/null | wc -l) files; last item count ${n:-0})" >&2
  for f in "$JF/run.log" "$EM/run.log"; do [ -f "$f" ] && { echo "--- last lines of $f:" >&2; tail -15 "$f" >&2; }; done
  return 1
}

setup_jellyfin() {
  need curl; need tar; mkdir -p "$JF"; cd "$JF"
  [ -x jellyfin/jellyfin ] || {
    curl -sL -o jellyfin.tar.gz https://repo.jellyfin.org/files/server/linux/latest-stable/amd64/jellyfin_12.4-amd64.tar.gz
    tar -xzf jellyfin.tar.gz; }
  [ -x ffmpeg/ffmpeg ] || {
    mkdir -p ffmpeg
    curl -sL -o ff.tar.xz https://repo.jellyfin.org/files/ffmpeg/linux/latest-7.x/amd64/jellyfin-ffmpeg_7.1.4-3_portable_linux64-gpl.tar.xz
    tar -xJf ff.tar.xz -C ffmpeg; }
  if ! ls /usr/lib/x86_64-linux-gnu/libicu*.so* >/dev/null 2>&1 && [ ! -d "$ICU" ]; then
    mkdir -p "$BASE/debs"; (cd "$BASE/debs" && apt-get download "$(apt-cache search --names-only '^libicu[0-9]+$' | awk '{print $1}' | head -1)")
    dpkg -x "$BASE"/debs/libicu*.deb "$ICU"
  fi
  echo "jellyfin ready in $JF"
}

setup_emby() {
  need curl; mkdir -p "$EM"; cd "$EM"
  [ -d x/opt/emby-server ] || {
    curl -sL -o emby.deb https://github.com/MediaBrowser/Emby.Releases/releases/download/4.10.2.0/emby-server-deb_4.10.2.0_amd64.deb
    mkdir -p x; dpkg -x emby.deb x; }
  echo "emby ready in $EM"
}

stop_all() {
  pkill -9 -f "jellyfin/jellyfin" 2>/dev/null || true
  pkill -9 -f "system/EmbyServer" 2>/dev/null || true
  sleep 1; echo "stopped"
}

start_jellyfin() {
  stop_all >/dev/null; cd "$JF"; rm -rf data config cache log; mkdir -p data config cache log
  [ -d "$ICU" ] && export LD_LIBRARY_PATH="$ICU/usr/lib/x86_64-linux-gnu"
  setsid nohup ./jellyfin/jellyfin --datadir "$PWD/data" --configdir "$PWD/config" --cachedir "$PWD/cache" \
    --logdir "$PWD/log" --ffmpeg "$PWD/ffmpeg/ffmpeg" --nowebclient </dev/null >run.log 2>&1 &
  disown
  wait_up /System/Info/Public || { echo "Jellyfin did not start; see $JF/run.log"; exit 1; }
  local U="http://127.0.0.1:$PORT" J='Content-Type: application/json'
  local H='Authorization: MediaBrowser Client="VPTest", Device="wsl", DeviceId="vp-test-1", Version="1"'
  # The first GET /Startup/User makes Jellyfin create a default user named after the OS user; the POST renames it.
  http "jellyfin wizard configuration" -H "$H" -H "$J" -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' $U/Startup/Configuration >/dev/null || exit 1
  http "jellyfin wizard first user (get)" -H "$H" $U/Startup/User >/dev/null || exit 1
  http "jellyfin wizard first user (set)" -H "$H" -H "$J" -d "{\"Name\":\"$USER_NAME\",\"Password\":\"$USER_PASS\"}" $U/Startup/User >/dev/null || exit 1
  http "jellyfin wizard remote access" -H "$H" -H "$J" -d '{"EnableRemoteAccess":false,"EnableAutomaticPortMapping":false}' $U/Startup/RemoteAccess >/dev/null || exit 1
  http "jellyfin wizard complete" -H "$H" -X POST $U/Startup/Complete >/dev/null || exit 1
  local reply token; reply="$(http "jellyfin sign-in" -H "$H" -H "$J" -d "{\"Username\":\"$USER_NAME\",\"Pw\":\"$USER_PASS\"}" $U/Users/AuthenticateByName)" || exit 1
  token="$(printf '%s' "$reply" | json '["AccessToken"]' 2>/dev/null || true)"
  [ -n "$token" ] || { echo "FAILED: jellyfin sign-in returned no access token: $(printf '%s' "$reply" | head -c 200)" >&2; exit 1; }
  echo "$token" > "$JF/token.txt"
  make_media
  http "jellyfin add library" -H "${H%\"}\", Token=\"$token\"" -H "$J" -d "{\"LibraryOptions\":{\"PathInfos\":[{\"Path\":\"$DATA\"}]}}" \
    "$U/Library/VirtualFolders?name=VPTest&refreshLibrary=true" >/dev/null || exit 1
  wait_items "$U" "${H%\"}\", Token=\"$token\"" || exit 1
  echo "jellyfin up on $U"
}

start_emby() {
  stop_all >/dev/null; local A="$EM/x/opt/emby-server"; cd "$A"
  rm -rf "$EM/data"; mkdir -p "$EM/data"
  export EMBY_DATA="$EM/data" FONTCONFIG_PATH="$A/etc/fonts" SSL_CERT_FILE="$A/etc/ssl/certs/ca-certificates.crt" PATH="$A/bin:$PATH"
  setsid nohup ./system/EmbyServer -programdata "$EM/data" -ffdetect "$A/bin/ffdetect" -ffmpeg "$A/bin/ffmpeg" \
    -ffprobe "$A/bin/ffprobe" -restartexitcode 3 </dev/null >"$EM/run.log" 2>&1 &
  disown
  wait_up /System/Info/Public || { echo "Emby did not start; see $EM/run.log"; exit 1; }
  local U="http://127.0.0.1:$PORT/emby" J='Content-Type: application/json'
  local H='X-Emby-Authorization: Emby Client="VPTest", Device="wsl", DeviceId="vp-test-1", Version="1"'
  http "emby wizard configuration" -H "$H" -H "$J" -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' $U/Startup/Configuration >/dev/null || exit 1
  http "emby wizard first user (get)" -H "$H" $U/Startup/User >/dev/null || exit 1
  http "emby wizard first user (set)" -H "$H" -H "$J" -d "{\"Name\":\"$USER_NAME\",\"Password\":\"$USER_PASS\"}" $U/Startup/User >/dev/null || exit 1
  http "emby wizard remote access" -H "$H" -H "$J" -d '{"EnableRemoteAccess":false,"EnableAutomaticPortMapping":false}' $U/Startup/RemoteAccess >/dev/null || exit 1
  http "emby wizard complete" -H "$H" -X POST $U/Startup/Complete >/dev/null || exit 1
  local reply token; reply="$(http "emby sign-in" -H "$H" -H "$J" -d "{\"Username\":\"$USER_NAME\",\"Pw\":\"$USER_PASS\"}" $U/Users/AuthenticateByName)" || exit 1
  token="$(printf '%s' "$reply" | json '["AccessToken"]' 2>/dev/null || true)"
  [ -n "$token" ] || { echo "FAILED: emby sign-in returned no access token: $(printf '%s' "$reply" | head -c 200)" >&2; exit 1; }
  echo "$token" > "$EM/token.txt"
  make_media
  http "emby add library" -X POST -G -H "X-Emby-Token: $token" -H "$J" -d '{"LibraryOptions":{}}' \
    --data-urlencode "name=VPTest" --data-urlencode "paths=$DATA" --data-urlencode "refreshLibrary=true" "$U/Library/VirtualFolders" >/dev/null || exit 1
  wait_items "$U" "X-Emby-Token: $token" || exit 1
  echo "emby up on $U"
}

cmd_env() {
  case "$1" in
    jellyfin) echo "export VP_JELLYFIN_URL=http://127.0.0.1:$PORT VP_JELLYFIN_TOKEN=$(cat "$JF/token.txt")" ;;
    emby) echo "export VP_EMBY_URL=http://127.0.0.1:$PORT/emby VP_EMBY_TOKEN=$(cat "$EM/token.txt")" ;;
  esac
  echo "export VP_TEST_USER=$USER_NAME VP_TEST_PASS=$USER_PASS"
}

case "${1:-}:${2:-}" in
  setup:jellyfin) setup_jellyfin ;;
  setup:emby) setup_emby ;;
  start:jellyfin) start_jellyfin ;;
  start:emby) start_emby ;;
  stop:*) stop_all ;;
  env:jellyfin|env:emby) cmd_env "$2" ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
