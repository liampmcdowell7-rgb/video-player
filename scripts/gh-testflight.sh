#!/usr/bin/env bash
# GitHub Actions only (.github/workflows/testflight.yml; OPEN_QUESTIONS R463, PROVISIONAL). The three steps of the TestFlight
# workflow that Codemagic did for us and GitHub does not. Everything else is scripts/cm-testflight.sh, unchanged.
#   gh-testflight.sh install-cert  puts the owner's ONE existing Apple Distribution certificate into a temporary keychain:
#                                  App Store Connect lists its certificates (the CLI call cm-testflight.sh already makes),
#                                  the one whose public key matches the private key in $DIST_KEY_FILE is kept (exactly one
#                                  must match), and a throw-away .p12 made from the two is imported. It makes NO key and NO
#                                  certificate and revokes or deletes nothing (the pre-push check refuses the commands that
#                                  would, scripts/test-ci-testflight-log.sh proves it).
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
step="${1:?step: install-cert | upload | cleanup}"
W="${RUNNER_TEMP:?RUNNER_TEMP is not set}/vp-gh"
KC="$W/build.keychain-db"
ARCHIVE=build/ios/xcarchive/VideoPlayer.xcarchive
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
    cnt="$(security find-identity -v -p codesigning "$KC" 2>/dev/null | grep -cE '^[[:space:]]+[0-9]+\)')"
    [ "${cnt:-0}" -ge 1 ] || { echo "SIGNING ERROR: the temporary keychain holds no code signing identity after the import"; exit 1; }
    echo "SIGNING: the Apple Distribution certificate for the supplied private key is in a temporary keychain ($cnt identity)"
    exit 0 ;;

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
    [ -f "$KC" ] && security delete-keychain "$KC" >/dev/null 2>&1
    rm -rf "$W" "$RUNNER_TEMP/asc" "$HOME/export_options.plist" "${TMPDIR:-/tmp}/vp-testflight"
    if [ -e "$W" ] || [ -e "$RUNNER_TEMP/asc" ]; then echo "::error::The key or keychain folder is still there."; exit 1; fi
    echo "Keychain, keys, export options and logs deleted."
    exit 0 ;;

  *)
    echo "unknown step: $step"; exit 2 ;;
esac
