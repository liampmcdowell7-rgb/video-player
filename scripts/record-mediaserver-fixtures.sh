#!/usr/bin/env bash
# Records real responses from the running Jellyfin or Emby test server into the test fixtures folder.
# Tokens are replaced with REDACTED. Usage: bash scripts/record-mediaserver-fixtures.sh jellyfin|emby
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K="$1"
eval "$(bash "$HERE/scripts/test-mediaservers.sh" env "$K")"
if [ "$K" = jellyfin ]; then
  U="$VP_JELLYFIN_URL"; AUTHH="Authorization: MediaBrowser Client=\"VPTest\", Device=\"wsl\", DeviceId=\"vp-test-1\", Version=\"1\", Token=\"$VP_JELLYFIN_TOKEN\""
  TOK="$VP_JELLYFIN_TOKEN"; LOGINH='Authorization: MediaBrowser Client="VPTest", Device="wsl", DeviceId="vp-fixture-login", Version="1"'; Cap=Jellyfin
else
  U="$VP_EMBY_URL"; AUTHH="X-Emby-Token: $VP_EMBY_TOKEN"; TOK="$VP_EMBY_TOKEN"
  LOGINH='X-Emby-Authorization: Emby Client="VPTest", Device="wsl", DeviceId="vp-fixture-login", Version="1"'; Cap=Emby
fi
OUT="$HERE/Packages/VideoPlayerCore/Tests/Source${Cap}Tests/Fixtures"; mkdir -p "$OUT"
red() { sed "s/$TOK/REDACTED-TOKEN/g"; }
curl -s "$U/System/Info/Public" | red > "$OUT/system-info-public.json"
curl -s -H "$LOGINH" -H 'Content-Type: application/json' -d "{\"Username\":\"$VP_TEST_USER\",\"Pw\":\"$VP_TEST_PASS\"}" "$U/Users/AuthenticateByName" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);d["AccessToken"]="REDACTED-TOKEN";print(json.dumps(d,indent=1))' > "$OUT/authenticate.json"
curl -s -H "$AUTHH" "$U/Library/VirtualFolders" | red > "$OUT/virtual-folders.json"
# The library scan fills the list gradually: wait until the video count stays the same for 5 checks.
prev=-1; same=0
for _ in $(seq 1 120); do
  n="$(curl -s -H "$AUTHH" "$U/Items?Recursive=true&IncludeItemTypes=Movie,Episode,Video,MusicVideo&Limit=0" | python3 -c 'import sys,json;print(json.load(sys.stdin)["TotalRecordCount"])' 2>/dev/null || echo -1)"
  if [ "$n" = "$prev" ]; then same=$((same+1)); else same=0; fi
  prev="$n"; [ "$same" -ge 5 ] && break; sleep 1
done
echo "video count settled at $n"
curl -s -H "$AUTHH" "$U/Items?Recursive=true&IncludeItemTypes=Movie,Episode,Video,MusicVideo&Fields=Path,MediaSources,DateCreated,Etag&Limit=500" | red > "$OUT/items.json"
curl -s -H "$AUTHH" "$U/Items?Recursive=true&IncludeItemTypes=Movie,Episode,Video,MusicVideo&Limit=0" | red > "$OUT/items-count.json"
curl -s -o /dev/null -w '%{http_code}' -H "$AUTHH" "$U/Users/Me" > /dev/null || true
ls -la "$OUT"
# Keep personal paths and the computer's name out of the repository.
# The Windows computer name and the user name are looked up at run time (no personal names written in this script).
WINHOST="$( (cmd.exe /c hostname 2>/dev/null || true) | tr -d '\r\n')"
for f in "$OUT"/*.json; do
  sed -i -e 's#/home/[^/"]*/video-player-test-servers#/srv/vp-test#g' -e "s#$(hostname)#TEST-SERVER#g" "$f"
  if [ -n "$WINHOST" ]; then sed -i -e "s#$WINHOST#TEST-SERVER#g" "$f"; fi
done
grep -l "REDACTED-TOKEN" "$OUT"/*.json >/dev/null || true
! grep -rEl "$TOK|/home/|$(id -un)" "$OUT" || { echo "fixture still holds a secret or personal path" >&2; exit 1; }
