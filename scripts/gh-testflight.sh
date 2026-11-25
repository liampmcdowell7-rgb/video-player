#!/usr/bin/env bash
# GitHub Actions only (.github/workflows/testflight.yml; OPEN_QUESTIONS R463, PROVISIONAL). The three steps of the TestFlight
# workflow that Codemagic did for us and GitHub does not. Everything else is scripts/cm-testflight.sh, unchanged.
#   gh-testflight.sh install-cert  puts the owner's ONE existing Apple Distribution certificate into a temporary keychain:
#                                  App Store Connect lists its certificates (the CLI call cm-testflight.sh already makes),
#                                  the one whose public key matches the private key in $DIST_KEY_FILE is kept (exactly one
#                                  must match), and a throw-away .p12 made from the two is imported. It makes NO key and NO
#                                  certificate and revokes or deletes nothing (the pre-push check refuses the commands that
#                                  would, scripts/test-ci-testflight-log.sh proves it).
#                                  R469: it also makes that keychain the DEFAULT keychain (use-profiles reads only that one;
#                                  cleanup restores the old default).
#   gh-testflight.sh check-archive READ-ONLY (R469): after the archive, before the export. Per target (app, Top Shelf): is the
#                                  archived product signed (a _CodeSignature folder), and does `xcodebuild -showBuildSettings`
#                                  resolve a non-empty CODE_SIGN_ENTITLEMENTS for Release (yes or no, plus the base name only
#                                  when it is one of the two committed or generated names). Fails when either is no.
#   gh-testflight.sh check-entitlements  READ-ONLY (R466, moved to the exported .ipa in R468): after the export, before the
#                                  upload. Unzips build/ios/ipa/*.ipa into $RUNNER_TEMP, prints yes or no (never a value)
#                                  for the iCloud container, the iCloud services, the App Group and aps-environment in the
#                                  app and the Top Shelf extension, signed and in the embedded profile
#                                  (scripts/gh-entitlement-check.py), and deletes the copy. Fails when no .ipa is there, and
#                                  when the app's signed entitlements were read and lack the iCloud container or the CloudKit
#                                  service. When nothing can be read it prints n/a, one WARNING and safe facts, exit 0.
#   gh-testflight.sh upload        uploads the archive with `xcodebuild -exportArchive` (the export options that
#                                  `xcode-project use-profiles` wrote, plus destination upload) and the API key flags.
#                                  The profiles and the certificate are the same as in the export, so nothing new is signed.
#   gh-testflight.sh cleanup       deletes the temporary keychain, the key files and the export options (runs with always()).
# Needs: RUNNER_TEMP; install-cert: DIST_KEY_FILE and the Codemagic CLI's APP_STORE_CONNECT_KEY_IDENTIFIER, _ISSUER_ID,
# _PRIVATE_KEY; upload: ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID. The repository is public: every command writes to a file under
# $RUNNER_TEMP and the log shows only redacted result and error lines (cm-testflight.sh redact, ci-testflight-log.sh);
# the identity line of `security find-identity` is never printed (it holds the holder's name).
# UNVERIFIED (no Mac here, never run): every command named here on a GitHub runner.
set -uo pipefail
cd "$(dirname "$0")/.."
step="${1:?step: install-cert | check-archive | check-entitlements | upload | cleanup}"
W="${RUNNER_TEMP:?RUNNER_TEMP is not set}/vp-gh"
KC="$W/build.keychain-db"
ARCHIVE="${VP_ARCHIVE:-build/ios/xcarchive/VideoPlayer.xcarchive}"   # VP_ARCHIVE only for the self-test
IPA_DIR="${VP_IPA_DIR:-build/ios/ipa}"   # VP_IPA_DIR only for scripts/test-ci-testflight-log.sh
EXPORT_OPTIONS="$HOME/export_options.plist"
umask 077
mkdir -p "$W/logs" && chmod 700 "$W"

show() { # LOG TITLE EXIT
  bash scripts/cm-testflight.sh redact < "$1" > "$1.safe" 2>/dev/null || : > "$1.safe"
  bash scripts/ci-testflight-log.sh "$1.safe" "$2" "$3"
}
pubhash() { shasum -a 256 | cut -d' ' -f1; }

case "$step" in
  install-cert)
    : "${DIST_KEY_FILE:?}"
    d="$W/cert"; rm -rf "$d"; mkdir -p "$d"
    # /usr/bin/openssl is LibreSSL on the Mac: its .p12 files import into the keychain without extra flags.
    if ! /usr/bin/openssl pkey -in "$DIST_KEY_FILE" -noout 2>/dev/null; then
      echo "SIGNING ERROR: DIST_CERT_PRIVATE_KEY is not a readable private key (docs/TESTFLIGHT.md, the secret DIST_CERT_PRIVATE_KEY)"; exit 1
    fi
    keyhash="$(/usr/bin/openssl pkey -in "$DIST_KEY_FILE" -pubout -outform DER 2>/dev/null | pubhash)"
    app-store-connect certificates list --json > "$d/certs.json" 2> "$W/logs/certs.log"; rc=$?
    [ "$rc" -eq 0 ] || { show "$W/logs/certs.log" "List certificates" "$rc"; exit "$rc"; }
    python3 scripts/cm-signing.py cert-files "$d/certs.json" "$d" || exit 1
    match=""; n=0
    for der in "$d"/cert-*.der; do
      [ -f "$der" ] || continue
      h="$(/usr/bin/openssl x509 -inform DER -in "$der" -pubkey -noout 2>/dev/null | /usr/bin/openssl pkey -pubin -outform DER 2>/dev/null | pubhash)"
      if [ "$h" = "$keyhash" ]; then match="$der"; n=$((n + 1)); fi
    done
    if [ "$n" -ne 1 ]; then
      echo "SIGNING ERROR: $n App Store Connect certificate(s) match the private key in DIST_CERT_PRIVATE_KEY (need exactly 1). The key must belong to your existing Apple Distribution certificate; this workflow never makes a certificate (R463)"
      exit 1
    fi
    /usr/bin/openssl x509 -inform DER -in "$match" -out "$d/cert.pem" || exit 1
    pw="$(/usr/bin/openssl rand -hex 24)"
    /usr/bin/openssl pkcs12 -export -inkey "$DIST_KEY_FILE" -in "$d/cert.pem" -out "$d/id.p12" -passout "pass:$pw" 2> "$W/logs/p12.log" \
      || { show "$W/logs/p12.log" "Make the .p12" 1; exit 1; }
    {
      security create-keychain -p "$pw" "$KC" &&
      security set-keychain-settings -lut 3600 "$KC" &&
      security unlock-keychain -p "$pw" "$KC" &&
      security import "$d/id.p12" -k "$KC" -P "$pw" -T /usr/bin/codesign -T /usr/bin/security &&
      security set-key-partition-list -S apple-tool:,apple: -s -k "$pw" "$KC"
    } > "$W/logs/keychain.log" 2>&1; rc=$?
    rm -f "$d/id.p12" "$d/cert.pem"
    [ "$rc" -eq 0 ] || { show "$W/logs/keychain.log" "Keychain" "$rc"; exit "$rc"; }
    old="$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')"
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KC" $old
    # R469: `xcode-project use-profiles` looks for the certificate ONLY in the DEFAULT keychain (`security default-keychain`;
    # it has no keychain option). Found nowhere, it still writes CODE_SIGN_STYLE Manual and the profile but an EMPTY
    # CODE_SIGN_IDENTITY, Xcode then archives UNSIGNED, and the export signs the app with no entitlements (runs #6 and #7).
    # Codemagic's own keychain is the default one, which is why that route worked. The old default is restored by cleanup.
    security default-keychain -d user > "$W/default-keychain.before" 2>/dev/null || : > "$W/default-keychain.before"
    security default-keychain -d user -s "$KC" > "$W/logs/default-keychain.log" 2>&1 \
      || { show "$W/logs/default-keychain.log" "Default keychain" 1; exit 1; }
    now="$(security default-keychain -d user 2>/dev/null | tr -d '" ')"
    [ "$now" = "$KC" ] || { echo "SIGNING ERROR: the temporary keychain is not the default keychain (use-profiles reads only that one)"; exit 1; }
    echo "SIGNING: the temporary keychain is the default keychain (xcode-project use-profiles reads the certificate there)"
    cnt="$(security find-identity -v -p codesigning "$KC" 2>/dev/null | grep -cE '^[[:space:]]+[0-9]+\)')"
    [ "${cnt:-0}" -ge 1 ] || { echo "SIGNING ERROR: the temporary keychain holds no code signing identity after the import"; exit 1; }
    echo "SIGNING: the Apple Distribution certificate for the supplied private key is in a temporary keychain ($cnt identity)"
    exit 0 ;;

  check-archive)
    # R469, read-only: yes or no only. The base name of the entitlements file is printed only when it is one of the two
    # names the repository uses; any other value prints "other". No path, Team ID, identity or profile is printed.
    app="$(ls -d "$ARCHIVE"/Products/Applications/*.app 2>/dev/null | head -n 1)"
    [ -d "$app" ] || { echo "ARCHIVE CHECK ERROR: no app in the archive"; exit 1; }
    ext="$(ls -d "$app"/PlugIns/*.appex 2>/dev/null | head -n 1)"
    bad=0
    for t in VideoPlayer TopShelf; do
      if [ "$t" = VideoPlayer ]; then b="$app"; label=app; else b="$ext"; label=topshelf; fi
      if [ -n "$b" ] && [ -d "$b/_CodeSignature" ]; then signed=yes; else signed=no; bad=1; fi
      xcodebuild -showBuildSettings -project VideoPlayer.xcodeproj -target "$t" -configuration Release \
        > "$W/logs/archive-settings-$t.txt" 2>&1
      ent="$(sed -nE 's/^[[:space:]]*CODE_SIGN_ENTITLEMENTS = (.+)$/\1/p' "$W/logs/archive-settings-$t.txt" | head -n 1)"
      if [ -n "$ent" ]; then
        e=yes
        case "$(basename "$ent")" in VideoPlayer.entitlements|TopShelf.entitlements) name="$(basename "$ent")" ;; *) name=other ;; esac
      else
        e=no; name=-; bad=1
      fi
      printf '  %-9s signed %-3s   CODE_SIGN_ENTITLEMENTS (Release) %-3s %s\n' "$label" "$signed" "$e" "$name"
    done
    if [ "$bad" -ne 0 ]; then
      echo "ARCHIVE CHECK ERROR: a target in the archive is unsigned or has no entitlements file for Release; the export would make an app without entitlements (R469). Nothing is exported or uploaded."
      exit 1
    fi
    echo "Archive check: app and Top Shelf are signed in the archive and both have an entitlements file for Release"
    exit 0 ;;

  check-entitlements)
    # R468: reads the EXPORTED .ipa, because this workflow signs during the export (the archive is unsigned: run #6 could read
    # nothing from it). The .ipa is unzipped into the runner's temporary folder, never the workspace, and the copy is deleted.
    ipa="$(ls "$IPA_DIR"/*.ipa 2>/dev/null | head -n 1)"
    [ -f "$ipa" ] || { echo "ENTITLEMENT ERROR: no .ipa in $IPA_DIR (the export step writes it)"; exit 1; }
    X="$W/ipa-check"
    rm -rf "$X"; mkdir -p "$X"
    if ! unzip -q -o "$ipa" -d "$X" >/dev/null 2>&1; then
      rm -rf "$X"; echo "ENTITLEMENT ERROR: the .ipa could not be unzipped"; exit 1
    fi
    app="$(ls -d "$X"/Payload/*.app 2>/dev/null | head -n 1)"
    if [ ! -d "$app" ]; then
      rm -rf "$X"; echo "ENTITLEMENT ERROR: no Payload/*.app inside the .ipa"; exit 1
    fi
    ext="$(ls -d "$app"/PlugIns/*.appex 2>/dev/null | head -n 1)"
    # The script prints fixed words only (key names, yes, no); codesign's and security's own output is never shown.
    python3 scripts/gh-entitlement-check.py bundles "$app" "${ext:-}"
    rc=$?
    rm -rf "$X"
    exit "$rc" ;;

  upload)
    : "${ASC_KEY_PATH:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}"
    [ -f "$EXPORT_OPTIONS" ] || { echo "SIGNING ERROR: no export options at ~/export_options.plist (use-profiles writes it)"; exit 1; }
    [ -d "$ARCHIVE" ] || { echo "SIGNING ERROR: no archive at $ARCHIVE"; exit 1; }
    up="$W/upload_options.plist"
    cp "$EXPORT_OPTIONS" "$up"
    /usr/libexec/PlistBuddy -c 'Delete :destination' "$up" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c 'Add :destination string upload' "$up" || exit 1
    method="$(/usr/libexec/PlistBuddy -c 'Print :method' "$up" 2>/dev/null || true)"
    [ "$method" = app-store ] || { echo "SIGNING ERROR: export method is '${method:-not set}', not app-store"; exit 1; }
    plutil -lint "$up" >/dev/null || exit 1
    echo "Upload: method app-store, destination upload; no submission for review"
    xcodebuild -exportArchive \
      -archivePath "$ARCHIVE" \
      -exportOptionsPlist "$up" \
      -exportPath "$W/upload" \
      -authenticationKeyPath "$ASC_KEY_PATH" \
      -authenticationKeyID "$ASC_KEY_ID" \
      -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
      > "$W/logs/upload.log" 2>&1; rc=$?
    show "$W/logs/upload.log" "Upload to App Store Connect" "$rc"
    exit "$rc" ;;

  cleanup)
    # R469: give the runner back its old default keychain before the temporary one is deleted.
    if [ -s "$W/default-keychain.before" ]; then
      prev="$(tr -d '"' < "$W/default-keychain.before" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | head -n 1)"
      [ -n "$prev" ] && security default-keychain -d user -s "$prev" >/dev/null 2>&1
    fi
    [ -f "$KC" ] && security delete-keychain "$KC" >/dev/null 2>&1
    rm -rf "$W" "$RUNNER_TEMP/asc" "$HOME/export_options.plist" "${TMPDIR:-/tmp}/vp-testflight"
    if [ -e "$W" ] || [ -e "$RUNNER_TEMP/asc" ]; then echo "::error::The key or keychain folder is still there."; exit 1; fi
    echo "Keychain, keys, export options and logs deleted."
    exit 0 ;;

  *)
    echo "unknown step: $step"; exit 2 ;;
esac
