#!/usr/bin/env bash
# Codemagic only (codemagic.yaml, workflow tvos-testflight; OPEN_QUESTIONS R266, PROVISIONAL). One build step per call:
#   cm-testflight.sh prepare         check the vendored files, install the pinned XcodeGen (SHA-256), generate, resolve:
#                                    scripts/ci-prepare.sh, exactly as the GitHub compile check does
#   cm-testflight.sh signing         Codemagic installs the owner's stored distribution certificate by type and bundle
#                                    identifier (codemagic.yaml ios_signing); this step checks that exactly one App Store
#                                    Connect certificate matches the keychain's identity (SHA-1), otherwise it stops; then
#                                    for EACH bundle ID takes an existing active TVOS_APP_STORE profile that carries it, or
#                                    makes one profile with it (scripts/cm-signing.py). It never makes a key or a
#                                    certificate and never revokes or deletes anything (the self-test checks this).
#   cm-testflight.sh check-profiles  scripts/cm-profile-check.py dir (iCloud container and App Group of the chosen two)
#   cm-testflight.sh archive         `xcode-project use-profiles` (the chosen profiles only), a check that both targets now
#                                    sign manually with a profile, the build number, `xcodebuild archive` (Release, tvOS), then
#                                    check-build on the archive
#   cm-testflight.sh export          `xcodebuild -exportArchive` with the generated export options (method app-store)
#   cm-testflight.sh redact          stdin to stdout with the extra redaction below (used by the self-test)
#   cm-testflight.sh check-build ARCHIVE N  the archive's app and Top Shelf Info.plist carry CFBundleVersion N (the archive
#                                    step runs it after xcodebuild archive, before export; R279)
# Codemagic's CLI tools (app-store-connect, xcode-project) are on its build machines; the App Store Connect
# integration `asc-testflight` gives them the API key (codemagic.yaml). The repository is public: every command writes to
# a file in a private temporary folder; the log shows only result lines and, on failure, the error lines, redacted twice
# (here: serial numbers, display names, long hex and base64 runs; then scripts/ci-testflight-log.sh: signing identities
# with the holder's name, e-mail addresses). UNVERIFIED (no Mac, never run): every Codemagic CLI behaviour named here.
set -uo pipefail
cd "$(dirname "$0")/.."
step="${1:?step: prepare | signing | check-profiles | archive | export | redact | check-build}"
APP_ID=com.liamp.videoplayer
TOPSHELF_ID=com.liamp.videoplayer.topshelf
ARCHIVE=build/ios/xcarchive/VideoPlayer.xcarchive
IPA_DIR=build/ios/ipa
EXPORT_OPTIONS="$HOME/export_options.plist"

redact() {
  sed -E \
    -e 's/([Ss]erial[ _-]?[Nn]umber"?[[:space:]]*[:=|]?[[:space:]]*"?)[0-9A-Fa-f:]+/\1[redacted]/g' \
    -e 's/([Dd]isplay[ _-]?[Nn]ame"?[[:space:]]*[:=|][[:space:]]*).*/\1[redacted]/' \
    -e 's/((certificate|profile)[Cc]ontent"?[[:space:]]*[:=][[:space:]]*).*/\1[redacted]/' \
    -e 's/[A-Za-z0-9+\/=]{64,}/[base64 redacted]/g' \
    -e 's/[0-9A-Fa-f]{32,}/[hex redacted]/g'
}

if [ "$step" = redact ]; then redact; exit 0; fi

# check_build_number ARCHIVE N: both bundles in the archive must carry CFBundleVersion N (OPEN_QUESTIONS R279; TestFlight
# showed 0.1.0 (1) for the first upload). Reads with PlistBuddy on the Mac; python3 plistlib where PlistBuddy is missing
# (the Linux self-test). One error line per wrong bundle; returns 1 if any is wrong.
plist_build() {
  if [ -x /usr/libexec/PlistBuddy ]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1" 2>/dev/null
  else
    python3 -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); v=d.get("CFBundleVersion"); sys.exit(1) if v is None else print(v)' "$1" 2>/dev/null
  fi
}
check_build_number() {
  local archive="$1" want="$2" bad=0 label plist got
  # The bundle names are looked up, not assumed (expected VideoPlayer.app and TopShelf.appex; UNVERIFIED until an archive).
  local app ext
  app="$(ls -d "$archive"/Products/Applications/*.app 2>/dev/null | head -n 1)"
  ext="$(ls -d "$app"/PlugIns/*.appex 2>/dev/null | head -n 1)"
  for label in app topshelf; do
    if [ "$label" = app ]; then plist="${app:-$archive/Products/Applications/(no .app)}/Info.plist"
    else plist="${ext:-${app:-$archive}/PlugIns/(no .appex)}/Info.plist"; fi
    if [ ! -f "$plist" ]; then
      echo "BUILD NUMBER ERROR: $label Info.plist not found in the archive ($plist)"; bad=1; continue
    fi
    got="$(plist_build "$plist")" || got=""
    if [ "$got" != "$want" ]; then
      echo "BUILD NUMBER ERROR: $label CFBundleVersion is '${got:-missing}', expected $want (project.yml info properties, R279)"; bad=1
    fi
  done
  [ "$bad" -eq 0 ] && echo "Build number check: app and Top Shelf carry CFBundleVersion $want"
  return "$bad"
}

if [ "$step" = check-build ]; then check_build_number "${2:?archive path}" "${3:?build number}"; exit $?; fi

W="${TMPDIR:-/tmp}/vp-testflight"
mkdir -p "$W/logs" && chmod 700 "$W"
# show LOG TITLE EXIT: the redacted view of one log (result lines, or the error lines on failure).
show() {
  redact < "$1" > "$1.safe" 2>/dev/null || : > "$1.safe"
  bash scripts/ci-testflight-log.sh "$1.safe" "$2" "$3"
}

case "$step" in
  prepare)
    : "${XCODEGEN_VERSION:?set in codemagic.yaml}" "${XCODEGEN_SHA256:?set in codemagic.yaml}"
    dev="$(xcode-select -p)"
    export XCODE_APP="${dev%/Contents/Developer}" OUT=build/codemagic RUNNER_TEMP="$W"
    bash scripts/ci-prepare.sh > "$W/logs/prepare.log" 2>&1; rc=$?
    grep -E '^Xcode [0-9]|^Build version' "$W/logs/prepare.log" | head -n 2
    grep -E '^ok ' "$W/logs/prepare.log" | head -n 20
    show "$W/logs/prepare.log" "Prepare" "$rc"
    exit "$rc" ;;

  signing)
    # Reuses the owner's ONE stored Apple Distribution certificate, which Codemagic installs with its private key by type
    # and bundle identifier (codemagic.yaml ios_signing). This step makes no key and no certificate, and revokes or
    # deletes nothing: it only reads App Store Connect and, when no usable profile exists, makes a profile.
    umask 077
    S="$W/signing"; rm -rf "$S"; mkdir -p "$S/chosen"
    security find-identity -v -p codesigning > "$S/identities.txt" 2>&1
    app-store-connect certificates list --json > "$S/certs.json" 2> "$W/logs/certs.log"; rc=$?
    [ "$rc" -eq 0 ] || { show "$W/logs/certs.log" "List certificates" "$rc"; exit "$rc"; }
    python3 scripts/cm-signing.py cert-id "$S/certs.json" "$S/identities.txt" "$S/cert-id" "$S/cert-sha1" || exit 1
    cid="$(cat "$S/cert-id")"
    for id in "$APP_ID" "$TOPSHELF_ID"; do
      d="$S/$id"; mkdir -p "$d/existing" "$d/new"
      # --strict-match-identifier: without it "com.example.app also matches ... com.example.app.extension" (CLI docs).
      app-store-connect bundle-ids list --bundle-id-identifier "$id" --strict-match-identifier --json \
        > "$d/bundle.json" 2> "$W/logs/bundle-$id.log"; rc=$?
      [ "$rc" -eq 0 ] || { show "$W/logs/bundle-$id.log" "Bundle ID $id" "$rc"; exit "$rc"; }
      python3 scripts/cm-signing.py bundle-rid "$d/bundle.json" "$id" "$d/rid" || exit 1
      rid="$(cat "$d/rid")"
      app-store-connect bundle-ids profiles --bundle-ids "$rid" --type TVOS_APP_STORE --state ACTIVE --json \
        > "$d/profiles.json" 2> "$W/logs/profiles-$id.log"; rc=$?
      [ "$rc" -eq 0 ] || { show "$W/logs/profiles-$id.log" "Profiles for $id" "$rc"; exit "$rc"; }
      python3 scripts/cm-signing.py profile-ids "$d/profiles.json" "$d/profile-ids" || exit 1
      while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        app-store-connect profiles get "$pid" --save --profiles-dir "$d/existing" > "$W/logs/get-$id.log" 2>&1; rc=$?
        [ "$rc" -eq 0 ] || { show "$W/logs/get-$id.log" "Download a profile for $id" "$rc"; exit "$rc"; }
      done < "$d/profile-ids"
      # Prefer an existing profile: active, App Store, tvOS, this bundle ID, with the stored certificate, valid > 1 day.
      python3 scripts/cm-signing.py pick "$d/existing" "$id" "$S/cert-sha1" "$S/chosen"; rc=$?
      if [ "$rc" -eq 3 ]; then
        echo "SIGNING: no usable TVOS_APP_STORE profile for $id with the stored certificate; making one (profile only)"
        app-store-connect profiles create "$rid" --certificate-ids "$cid" --type TVOS_APP_STORE \
          --name "Video Player tvOS App Store $id $(date -u +%Y%m%d%H%M)" --save --profiles-dir "$d/new" \
          > "$W/logs/create-$id.log" 2>&1; rc=$?
        [ "$rc" -eq 0 ] || { show "$W/logs/create-$id.log" "Make a profile for $id" "$rc"; exit "$rc"; }
        python3 scripts/cm-signing.py pick "$d/new" "$id" "$S/cert-sha1" "$S/chosen"; rc=$?
        [ "$rc" -eq 0 ] || { echo "SIGNING ERROR: the new profile for $id does not carry the stored certificate"; exit 1; }
      elif [ "$rc" -ne 0 ]; then
        exit "$rc"
      fi
    done
    # Xcode reads profiles from these folders; the build machine is fresh, so these two are the only ones there.
    for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
      mkdir -p "$dir" && cp "$S/chosen"/*.mobileprovision "$dir/"
    done
    echo "SIGNING: $(ls "$S/chosen" | wc -l | tr -d ' ') profile(s) installed; no key or certificate was made"
    exit 0 ;;

  check-profiles)
    python3 scripts/cm-profile-check.py dir "$W/signing/chosen"
    exit $? ;;

  archive)
    xcode-project use-profiles --project VideoPlayer.xcodeproj --profile "$W/signing/chosen/*.mobileprovision" \
      --custom-export-options '{"method": "app-store", "uploadSymbols": true, "manageAppVersionAndBuildNumber": false}' \
      > "$W/logs/use-profiles.log" 2>&1; rc=$?
    [ "$rc" -eq 0 ] || { show "$W/logs/use-profiles.log" "xcode-project use-profiles" "$rc"; exit "$rc"; }
    # Both targets must now sign manually with a named profile (the CLI docs do not say what use-profiles sets).
    bad=0
    for t in VideoPlayer TopShelf; do
      xcodebuild -showBuildSettings -project VideoPlayer.xcodeproj -target "$t" -configuration Release \
        > "$W/logs/settings-$t.txt" 2>&1
      style="$(sed -nE 's/^[[:space:]]*CODE_SIGN_STYLE = (.*)$/\1/p' "$W/logs/settings-$t.txt" | head -n 1)"
      prof="$(sed -nE 's/^[[:space:]]*PROVISIONING_PROFILE_SPECIFIER = (.+)$/\1/p' "$W/logs/settings-$t.txt" | head -n 1)"
      if [ "$style" = Manual ] && [ -n "$prof" ]; then
        echo "SIGNING: target $t signs manually with its own App Store profile"
      else
        echo "SIGNING ERROR: target $t: CODE_SIGN_STYLE '${style:-unset}', profile ${prof:+set}${prof:-not set} after use-profiles"; bad=1
      fi
    done
    [ "$bad" -eq 0 ] || exit 1
    BUILD_NUMBER="$(bash scripts/cm-build-number.sh)"
    bash scripts/cm-build-number.sh --check "$BUILD_NUMBER" || { echo "SIGNING ERROR: build number '$BUILD_NUMBER' has the wrong form"; exit 1; }
    echo "Build number (CFBundleVersion): $BUILD_NUMBER"
    mkdir -p "$(dirname "$ARCHIVE")"
    xcodebuild archive \
      -project VideoPlayer.xcodeproj \
      -scheme VideoPlayer \
      -configuration Release \
      -destination 'generic/platform=tvOS' \
      -archivePath "$ARCHIVE" \
      -clonedSourcePackagesDirPath build/SourcePackages \
      -derivedDataPath build/DerivedData \
      -skipPackagePluginValidation \
      -skipMacroValidation \
      CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
      > "$W/logs/archive.log" 2>&1; rc=$?
    show "$W/logs/archive.log" "Archive" "$rc"
    [ "$rc" -eq 0 ] || exit "$rc"
    # Before export: both bundles must carry this build number (R279), or the upload would repeat an old one.
    check_build_number "$ARCHIVE" "$BUILD_NUMBER" || exit 1
    exit 0 ;;

  export)
    [ -f "$EXPORT_OPTIONS" ] || { echo "SIGNING ERROR: no export options at ~/export_options.plist (use-profiles writes it)"; exit 1; }
    method="$(/usr/libexec/PlistBuddy -c 'Print :method' "$EXPORT_OPTIONS" 2>/dev/null || true)"
    echo "Export method: ${method:-not set}"
    [ "$method" = app-store ] || { echo "SIGNING ERROR: export method is '${method:-not set}', not app-store"; exit 1; }
    xcodebuild -exportArchive \
      -archivePath "$ARCHIVE" \
      -exportOptionsPlist "$EXPORT_OPTIONS" \
      -exportPath "$IPA_DIR" \
      > "$W/logs/export.log" 2>&1; rc=$?
    show "$W/logs/export.log" "Export" "$rc"
    [ "$rc" -eq 0 ] || exit "$rc"
    n=0; for f in "$IPA_DIR"/*.ipa; do [ -f "$f" ] && { n=$((n + 1)); echo "IPA: $(basename "$f") ($(du -h "$f" | cut -f1))"; }; done
    [ "$n" -ge 1 ] || { echo "SIGNING ERROR: the export wrote no .ipa into $IPA_DIR"; exit 1; }
    exit 0 ;;

  *)
    echo "unknown step: $step"; exit 2 ;;
esac
