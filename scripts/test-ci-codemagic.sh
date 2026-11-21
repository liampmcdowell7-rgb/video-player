#!/usr/bin/env bash
# Self-test for the Codemagic TestFlight route (OPEN_QUESTIONS R266): codemagic.yaml's shape, scripts/cm-build-number.sh,
# scripts/cm-signing.py (synthetic CLI output and throwaway certificates; the negative checks that nothing can make,
# revoke or delete a key or a certificate), scripts/cm-profile-check.py (against the hand-written sample plists in scripts/codemagic-fixtures/, decoded and as
# signed profiles made here with a throwaway key), the redaction in scripts/cm-testflight.sh, and the codemagic.yaml
# section of scripts/pre-push-check.sh. Runs on Linux with bash, python3 (PyYAML for the YAML parse) and openssl;
# contacts nothing. Every name and ID below is synthetic.
set -uo pipefail
cd "$(dirname "$0")/.."
pass=0; fail=0; skip=0
ok()  { echo "ok    $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
Y=codemagic.yaml
F=scripts/codemagic-fixtures
PC=scripts/cm-profile-check.py

# --- codemagic.yaml parses and has the agreed shape ---
if python3 -c 'import yaml' 2>/dev/null; then
  out="$(python3 - "$Y" <<'EOF'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
w = d["workflows"]
checks = []
def c(name, cond): checks.append(("ok" if cond else "FAIL") + "|" + name)
c("codemagic.yaml parses as YAML and has exactly one workflow", isinstance(w, dict) and len(w) == 1)
wf = list(w.values())[0]
c("the workflow is named 'tvOS TestFlight (manual)'", wf.get("name") == "tvOS TestFlight (manual)")
c("no triggering section (manual only)", "triggering" not in wf and "triggering" not in d)
c("max_build_duration is 30 or less", isinstance(wf.get("max_build_duration"), int) and wf["max_build_duration"] <= 30)
c("instance_type is mac_mini_m2", wf.get("instance_type") == "mac_mini_m2")
c("xcode is exactly 27.2 (a string)", wf.get("environment", {}).get("xcode") == "27.2")
c("the only integration is app_store_connect: asc-testflight", wf.get("integrations") == {"app_store_connect": "asc-testflight"})
env = wf.get("environment", {})
c("no environment groups (no secrets)", "groups" not in env)
c("ios_signing is exactly distribution_type app_store and bundle_identifier com.liamp.videoplayer",
  env.get("ios_signing") == {"distribution_type": "app_store", "bundle_identifier": "com.liamp.videoplayer"})
pub = wf.get("publishing", {})
c("publishing: only app_store_connect", list(pub.keys()) == ["app_store_connect"])
c("publishing: auth integration, submit_to_testflight false, nothing else",
  pub.get("app_store_connect") == {"auth": "integration", "submit_to_testflight": False})
steps = [s.get("script", "") for s in wf.get("scripts", [])]
c("the five steps run scripts/cm-testflight.sh signing, check-profiles, prepare, archive, export in order",
  steps == ["bash scripts/cm-testflight.sh " + s for s in ("signing", "check-profiles", "prepare", "archive", "export")])
c("the artifact is the .ipa only", wf.get("artifacts") == ["build/ios/ipa/*.ipa"])
for line in checks: print(line)
print("XCG|%s|%s" % (env.get("vars", {}).get("XCODEGEN_VERSION"), env.get("vars", {}).get("XCODEGEN_SHA256")))
EOF
)"
  while IFS='|' read -r st name rest; do
    case "$st" in ok) ok "$name" ;; FAIL) bad "$name" ;; XCG) cmv="$name"; cms="$rest" ;; esac
  done <<< "$out"
  gv="$(sed -nE 's/^[[:space:]]+XCODEGEN_VERSION: "([^"]+)"$/\1/p' .github/workflows/compile-check.yml | sort -u)"
  gs="$(sed -nE 's/^[[:space:]]+XCODEGEN_SHA256: "([^"]+)"$/\1/p' .github/workflows/compile-check.yml | sort -u)"
  [ "${cmv:-}" = "$gv" ] && [ "${cms:-}" = "$gs" ] && ok "XcodeGen version and SHA-256 equal compile-check.yml's ($gv)" || bad "XcodeGen pin differs: $cmv/$cms vs $gv/$gs"
else
  echo "SKIP  codemagic.yaml YAML parse (PyYAML not installed)"; skip=$((skip + 1))
fi
grep -qE '^[[:space:]]*(api_key|key_id|issuer_id|groups):' "$Y" && bad "codemagic.yaml names a key or a group" || ok "codemagic.yaml names no API key and no environment group"
grep -q 'ITSAppUsesNonExemptEncryption: false' project.yml && ok "project.yml keeps ITSAppUsesNonExemptEncryption false (R261)" || bad "R261 value changed"

# --- NEGATIVE: nothing in the workflow or its scripts can make, revoke or delete a key or a certificate (R266) ---
KEYGEN='genrsa|genpkey|ecparam|ssh-keygen|openssl[[:space:]]+req|-newkey|certificates[[:space:]]+(create|delete|revoke)|fetch-signing-files|--certificate-key|CERTIFICATE_PRIVATE_KEY|--create|--delete-stale-profiles|profiles[[:space:]]+delete|keychain[[:space:]]+add-certificates|security[[:space:]]+(delete|import|create-keychain)'
hits=""; for f in "$Y" scripts/cm-*; do h="$(grep -vE '^[[:space:]]*#' "$f" | grep -nE "$KEYGEN")" && hits="$hits $f:$h"; done
[ -z "$hits" ] && ok "no key generation, certificate create/revoke/delete, fetch-signing-files, --create or key option in codemagic.yaml or scripts/cm-*" || bad "key or certificate command found:$hits"
grep -q 'app-store-connect profiles create' scripts/cm-testflight.sh && ! grep -qE 'app-store-connect certificates[[:space:]]+[^l]' scripts/cm-testflight.sh \
  && ok "the only App Store Connect write is 'profiles create'; certificates are only listed" || bad "unexpected certificates command in cm-testflight.sh"

# --- entitlements in project.yml (XcodeGen writes App/VideoPlayer.entitlements and TopShelf/TopShelf.entitlements from it) ---
if python3 -c 'import yaml' 2>/dev/null; then
  out="$(python3 - <<'EOF'
import yaml
t = yaml.safe_load(open("project.yml"))["targets"]
app = t["VideoPlayer"]["entitlements"]["properties"]
top = t["TopShelf"]["entitlements"]["properties"]
print("APP=%s TOP=%s" % (app.get("aps-environment"), "aps-environment" in top))
EOF
)"
  [ "$out" = "APP=production TOP=False" ] && ok "project.yml: the app's entitlements have aps-environment production; the Top Shelf's have none" || bad "aps-environment in project.yml: $out"
else
  echo "SKIP  project.yml entitlements parse (PyYAML not installed)"; skip=$((skip + 1))
fi
grep -q 'aps-environment' TopShelf/TopShelf.entitlements && bad "TopShelf/TopShelf.entitlements has aps-environment" || ok "TopShelf/TopShelf.entitlements has no aps-environment"

# --- build number ---
n="$(bash scripts/cm-build-number.sh)"
printf '%s' "$n" | grep -Eq '^[0-9]{12}$' && ok "build number has 12 digits ($n)" || bad "build number '$n'"
now="$(date -u +%Y%m%d%H%M)"; [ $((now - n)) -ge 0 ] && [ $((now - n)) -le 1 ] && ok "build number is the UTC time yyyyMMddHHmm" || bad "build number $n is not now ($now)"
bash scripts/cm-build-number.sh --check "$n" && ok "--check accepts the build number" || bad "--check refuses $n"
r=0; for v in 202613011200 202611321200 202611202460 2026112012 abc ""; do bash scripts/cm-build-number.sh --check "$v" && r=1; done
[ "$r" -eq 0 ] && ok "--check refuses month 13, day 32, minute 60, a short value, letters and empty" || bad "--check accepted a wrong value"

# --- profile check, decoded plists (hand-written samples) ---
out="$(python3 "$PC" plists "$F/app-ok.plist" "$F/topshelf-ok.plist")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^PROFILE CHECK: com.liamp.videoplayer has iCloud.com.liamp.videoplayer, group.com.liamp.videoplayer and aps-environment production; com.liamp.videoplayer.topshelf has group.com.liamp.videoplayer$' \
  && ok "profile check: both sample profiles complete (the Top Shelf's has no aps-environment and needs none), exit 0" || bad "profile check ok case: $rc $out"
out="$(python3 "$PC" plists "$F/app-no-aps.plist" "$F/topshelf-ok.plist")"; rc=$?
[ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c 'MISSING CAPABILITY')" -eq 1 ] \
  && printf '%s' "$out" | grep -q 'MISSING CAPABILITY: Push Notifications (aps-environment production) is missing on the App ID com.liamp.videoplayer;' \
  && printf '%s' "$out" | grep -q 'error 90575' \
  && ok "profile check: an app profile without aps-environment (build 3's case, error 90575) stops the build, exit 1" || bad "no-aps case: $rc $out"
out="$(python3 "$PC" plists "$F/app-no-capabilities.plist" "$F/topshelf-ok.plist")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'MISSING CAPABILITY: iCloud container iCloud.com.liamp.videoplayer is missing on the App ID com.liamp.videoplayer ' \
  && printf '%s' "$out" | grep -q 'MISSING CAPABILITY: App Group group.com.liamp.videoplayer is missing on the App ID com.liamp.videoplayer ' \
  && ! printf '%s' "$out" | grep -q 'App ID com.liamp.videoplayer.topshelf' \
  && ok "profile check: the app's missing iCloud container and App Group are named on com.liamp.videoplayer, exit 1" || bad "app missing case: $rc $out"
out="$(python3 "$PC" plists "$F/app-ok.plist" "$F/topshelf-no-group.plist")"; rc=$?
[ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c 'MISSING CAPABILITY')" -eq 1 ] \
  && printf '%s' "$out" | grep -q 'App Group group.com.liamp.videoplayer is missing on the App ID com.liamp.videoplayer.topshelf ' \
  && ok "profile check: the Top Shelf's missing App Group is named on com.liamp.videoplayer.topshelf, exit 1" || bad "topshelf missing case: $rc $out"
printf '%s' "$out" | grep -qE 'ZZ00000000|UUID|00000000-' && bad "profile check printed the team or a UUID" || ok "profile check prints no team ID and no UUID"

# --- profile check, installed signed profiles (made here with a throwaway key and certificate) ---
if openssl req -x509 -newkey rsa:2048 -nodes -subj "/CN=Throwaway test signer" -days 1 \
     -keyout "$t/k.pem" -out "$t/c.pem" > /dev/null 2>&1; then
  sign() { openssl cms -sign -binary -nodetach -outform DER -in "$F/$1" -signer "$t/c.pem" -inkey "$t/k.pem" -out "$2" 2>/dev/null; }
  home="$t/home"; d1="$home/Library/MobileDevice/Provisioning Profiles"; d2="$home/Library/Developer/Xcode/UserData/Provisioning Profiles"
  mkdir -p "$d1" "$d2"
  sign app-development.plist "$d1/dev.mobileprovision"; sign topshelf-ok.plist "$d2/top.mobileprovision"
  out="$(HOME="$home" PATH="/usr/bin:/bin" python3 "$PC" installed)"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no App Store profile for com.liamp.videoplayer is installed' \
    && ok "installed profiles: a Development profile is not taken for the app (exit 1, says which is absent)" || bad "dev profile case: $rc $out"
  sign app-ok.plist "$d1/app.mobileprovision"
  out="$(HOME="$home" PATH="/usr/bin:/bin" python3 "$PC" installed)"; rc=$?
  [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'App Store profiles found for com.liamp.videoplayer and com.liamp.videoplayer.topshelf' \
    && ok "installed profiles: signed App Store profiles in both folders are decoded, matched by App ID and pass" || bad "installed ok case: $rc $out"
  rm -f "$d1/app.mobileprovision"; sign app-no-capabilities.plist "$d1/app.mobileprovision"
  out="$(HOME="$home" PATH="/usr/bin:/bin" python3 "$PC" installed)"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'MISSING CAPABILITY: iCloud container' \
    && ok "installed profiles: an installed profile without the capabilities stops the build" || bad "installed missing case: $rc $out"
  out="$(HOME="$home" PATH="/usr/bin:/bin" python3 "$PC" dir "$d1")"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no App Store profile for com.liamp.videoplayer.topshelf' \
    && ok "dir mode: only the given folder is read (the Top Shelf profile in the other folder is not taken)" || bad "dir mode: $rc $out"

  # --- cm-signing.py: the stored certificate is found by SHA-1, profiles are chosen by certificate, never made here ---
  SG=scripts/cm-signing.py
  openssl req -x509 -newkey rsa:2048 -nodes -subj "/CN=Throwaway other signer" -days 1 -keyout "$t/k2.pem" -out "$t/c2.pem" > /dev/null 2>&1
  python3 - "$t" <<'EOF'
import base64, datetime, hashlib, json, plistlib, ssl, sys
t = sys.argv[1]
der = {n: ssl.PEM_cert_to_DER_cert(open("%s/%s.pem" % (t, n)).read()) for n in ("c", "c2")}
sha = {n: hashlib.sha1(d).hexdigest().upper() for n, d in der.items()}
later = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=300)).strftime("%Y-%m-%dT%H:%M:%S.000+00:00")
gone = "2020-01-01T00:00:00.000+00:00"
json.dump({"data": [{"id": "CERTOTHER1", "attributes": {"certificateContent": base64.b64encode(der["c2"]).decode(), "expirationDate": later}},
                    {"id": "CERTSTORED1", "attributes": {"certificateContent": base64.b64encode(der["c"]).decode(), "expirationDate": later}}]},
          open(t + "/certs.json", "w"))
open(t + "/identities.txt", "w").write('  1) %s "Apple Distribution: Sample Person (ZZ00000000)"\n     1 valid identities found\n' % sha["c"])
open(t + "/identities-none.txt", "w").write("     0 valid identities found\n")
json.dump([{"id": "BUNDLEAPP1", "attributes": {"identifier": "com.liamp.videoplayer"}},
           {"id": "BUNDLETOP1", "attributes": {"identifier": "com.liamp.videoplayer.topshelf"}}], open(t + "/bundles.json", "w"))
json.dump({"data": [{"id": "PROF1"}, {"id": "PROF2"}]}, open(t + "/profiles.json", "w"))
base = plistlib.load(open("scripts/codemagic-fixtures/app-ok.plist", "rb"))
def prof(name, cert, expires, uuid, platform=("tvOS",)):
    p = dict(base); p["DeveloperCertificates"] = [der[cert]]; p["Platform"] = list(platform); p["UUID"] = uuid
    p["ExpirationDate"] = expires; plistlib.dump(p, open("%s/%s.plist" % (t, name), "wb"))
soon = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
prof("p-other", "c2", soon + datetime.timedelta(days=300), "00000000-0000-4000-8000-0000000000a1")
prof("p-expiring", "c", soon + datetime.timedelta(hours=5), "00000000-0000-4000-8000-0000000000a2")
prof("p-ios", "c", soon + datetime.timedelta(days=300), "00000000-0000-4000-8000-0000000000a3", ("iOS",))
prof("p-good", "c", soon + datetime.timedelta(days=200), "00000000-0000-4000-8000-0000000000a4")
EOF
  out="$(python3 "$SG" cert-id "$t/certs.json" "$t/identities.txt" "$t/cid" "$t/csha")"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(cat "$t/cid")" = CERTSTORED1 ] && ! printf '%s' "$out" | grep -qE 'CERT|Sample|ZZ0' \
    && ok "cert-id: picks the App Store Connect certificate whose SHA-1 is the keychain identity; prints no ID or name" || bad "cert-id: $rc $out"
  out="$(python3 "$SG" cert-id "$t/certs.json" "$t/identities-none.txt" "$t/x" "$t/y")"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'distribution_type app_store' && ok "cert-id: no identity in the keychain stops the build and names the ios_signing form" || bad "cert-id none: $rc $out"
  python3 - "$t" <<'EOF'
import json, sys; t = sys.argv[1]; d = json.load(open(t + "/certs.json")); d["data"] = d["data"][:1]; json.dump(d, open(t + "/certs-other.json", "w"))
EOF
  out="$(python3 "$SG" cert-id "$t/certs-other.json" "$t/identities.txt" "$t/x" "$t/y")"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'never makes a certificate' && ok "cert-id: no matching certificate stops the build (it never makes one)" || bad "cert-id other: $rc $out"
  python3 "$SG" bundle-rid "$t/bundles.json" com.liamp.videoplayer.topshelf "$t/rid" > /dev/null && [ "$(cat "$t/rid")" = BUNDLETOP1 ] \
    && ok "bundle-rid: the exact identifier's resource ID (not the app's for the extension)" || bad "bundle-rid"
  python3 "$SG" bundle-rid "$t/bundles.json" com.liamp.other "$t/rid" > /dev/null; [ $? -eq 1 ] && ok "bundle-rid: an unregistered identifier stops the build" || bad "bundle-rid unknown"
  python3 "$SG" profile-ids "$t/profiles.json" "$t/pids" > /dev/null && [ "$(tr '\n' ' ' < "$t/pids")" = "PROF1 PROF2 " ] && ok "profile-ids: one ID per line" || bad "profile-ids"
  mkdir -p "$t/ex" "$t/chosen"
  for n in p-other p-expiring p-ios; do openssl cms -sign -binary -nodetach -outform DER -in "$t/$n.plist" -signer "$t/c.pem" -inkey "$t/k.pem" -out "$t/ex/$n" 2>/dev/null; done
  python3 "$SG" pick "$t/ex" com.liamp.videoplayer "$t/csha" "$t/chosen" > /dev/null; rc=$?
  [ "$rc" -eq 3 ] && [ -z "$(ls "$t/chosen")" ] && ok "pick: other certificate, expiring within a day, iOS platform: none taken (exit 3, a profile is then made)" || bad "pick none: $rc"
  openssl cms -sign -binary -nodetach -outform DER -in "$t/p-good.plist" -signer "$t/c.pem" -inkey "$t/k.pem" -out "$t/ex/p-good" 2>/dev/null
  out="$(python3 "$SG" pick "$t/ex" com.liamp.videoplayer "$t/csha" "$t/chosen")"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(ls "$t/chosen")" = "00000000-0000-4000-8000-0000000000a4.mobileprovision" ] && ! printf '%s' "$out" | grep -q 00000000 \
    && ok "pick: the existing valid tvOS App Store profile with the stored certificate is reused (no UUID printed)" || bad "pick good: $rc $out $(ls "$t/chosen")"
  python3 "$SG" pick "$t/ex" com.liamp.videoplayer.topshelf "$t/csha" "$t/chosen2" > /dev/null; [ $? -eq 3 ] && ok "pick: a profile for another bundle ID is not taken" || bad "pick other bundle"
else
  echo "SKIP  signed-profile checks (openssl could not make a throwaway certificate)"; skip=$((skip + 1))
fi

# --- redaction of command output ---
cat > "$t/cli.log" <<'EOF'
Found certificate: Apple Distribution: Sample Person (ZZ00000000)
- Serial number: 1A2B3C4D5E6F70819203
  serialNumber: "7F00AA11BB22CC33DD44"
  Display name: Sample Person
  certificateContent: MIIFzzCCBLegAwIBAgIQaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  fingerprint 0123456789ABCDEF0123456789ABCDEF01234567
Contact sample.person@example.invalid
Error: could not create the certificate
EOF
red="$(bash scripts/cm-testflight.sh redact < "$t/cli.log")"
printf '%s' "$red" | grep -qE '1A2B3C4D5E6F70819203|7F00AA11BB22CC33DD44' && bad "a serial number survives" || ok "redact: serial numbers removed"
printf '%s' "$red" | grep -q 'MIIFzz' && bad "certificate content survives" || ok "redact: base64 certificate content removed"
printf '%s' "$red" | grep -q '0123456789ABCDEF0123456789ABCDEF' && bad "a long hex value survives" || ok "redact: long hex values removed"
printf '%s' "$red" | grep -q 'Display name: Sample Person' && bad "a display name survives" || ok "redact: display names removed"
printf '%s\n' "$red" > "$t/safe.log"
out="$(bash scripts/ci-testflight-log.sh "$t/safe.log" "Signing files" 1 2>&1)"
printf '%s' "$out" | grep -qE 'Sample Person|example\.invalid|1A2B3C|MIIFzz' && bad "the failure view leaks: $out" || ok "failure view after both redactions: no name, e-mail, serial or certificate"
printf '%s' "$out" | grep -q 'Error: could not create the certificate' && ok "failure view keeps the error line" || bad "error line lost: $out"

# --- pre-push: the codemagic.yaml section (the real script in a throwaway repository with one codemagic.yaml variant) ---
scan() { # stdin = codemagic.yaml text
  local r="$t/repo-$RANDOM"; mkdir -p "$r/scripts"; cp scripts/pre-push-check.sh "$r/scripts/"; cat > "$r/codemagic.yaml"
  git -C "$r" init -q 2>/dev/null; (cd "$r" && bash scripts/pre-push-check.sh 2>&1)
}
out="$(scan < "$Y")"; printf '%s' "$out" | grep -q '^codemagic.yaml: manual only' && ! printf '%s' "$out" | grep -q '^!! codemagic' \
  && ok "pre-push: codemagic.yaml as committed passes" || bad "pre-push on the real codemagic.yaml: $(printf '%s' "$out" | grep '!!')"
refused() { # $1 = description, $2 = expected message part, stdin = variant
  local o; o="$(scan)"; printf '%s' "$o" | grep -q "!! codemagic.yaml: .*$2" && ok "pre-push refuses $1" || bad "pre-push did not refuse $1: $(printf '%s' "$o" | grep '!!')"
}
{ cat "$Y"; printf '    triggering:\n      events:\n        - push\n'; } | sed 's/^    triggering:/    triggering:/' | refused "a triggering section" "triggering"
sed 's/app_store_connect: asc-testflight/app_store_connect: other-key/' "$Y" | refused "another integration name" "integrations must be"
sed 's/^      vars:/      groups:\n        - signing\n      vars:/' "$Y" | refused "an environment group" "environment groups"
sed 's/^        XCODEGEN_VERSION:/        CERTIFICATE_PRIVATE_KEY: x\n        XCODEGEN_VERSION:/' "$Y" | refused "a secret-looking variable" "looks like a secret"
{ cat "$Y"; printf '      email:\n        recipients:\n          - someone@example.invalid\n'; } | refused "e-mail publishing" "publishes to"
sed 's/max_build_duration: 30/max_build_duration: 60/' "$Y" | refused "a 60-minute limit" "max_build_duration"
sed 's/xcode: "27.2"/xcode: latest/' "$Y" | refused "xcode: latest" "exact version"
sed 's/instance_type: mac_mini_m2/instance_type: mac_mini_m4/' "$Y" | refused "mac_mini_m4 (billed)" "mac_mini_m2"
{ cat "$Y"; printf '  second:\n    name: x\n'; } | refused "a second workflow" "workflows"
sed 's/        auth: integration/        api_key: $X/' "$Y" | refused "an API key instead of the integration" "names an API key"
sed 's/^        distribution_type: app_store$/        certificates:\n          - "Stored certificate"/; /^        bundle_identifier:/d' "$Y" | refused "certificates only (the form Codemagic's validator rejects)" "ios_signing must be exactly"
sed 's/^        distribution_type: app_store$/        provisioning_profiles:\n          - some_profile/; /^        bundle_identifier:/d' "$Y" | refused "a provisioning profile reference" "ios_signing must be exactly"
sed 's/distribution_type: app_store/distribution_type: ad_hoc/' "$Y" | refused "another distribution_type (ad_hoc)" "ios_signing must be exactly"
sed 's/bundle_identifier: com.liamp.videoplayer/bundle_identifier: com.liamp.other/' "$Y" | refused "another bundle identifier" "ios_signing must be exactly"
sed 's/^        bundle_identifier: com.liamp.videoplayer$/        bundle_identifier: com.liamp.videoplayer\n        certificates:\n          - "Stored certificate"/' "$Y" | refused "both forms mixed (type + certificates)" "ios_signing must be exactly"
sed '/^      ios_signing:/,/^        bundle_identifier:/d' "$Y" | refused "a missing ios_signing section" "exactly one ios_signing"
scan_script() { # $1 = description, stdin = a scripts/cm-extra.sh body
  local r="$t/repo-$RANDOM" o; mkdir -p "$r/scripts"; cp scripts/pre-push-check.sh "$r/scripts/"; cp "$Y" "$r/codemagic.yaml"
  cat > "$r/scripts/cm-extra.sh"; git -C "$r" init -q 2>/dev/null; o="$(cd "$r" && bash scripts/pre-push-check.sh 2>&1)"
  printf '%s' "$o" | grep -q '!! codemagic.yaml: scripts/cm-extra.sh could make' && ok "pre-push refuses a cm script that $1" || bad "pre-push missed a cm script that $1"
}
echo 'openssl genrsa -out k.pem 2048' | scan_script "generates a key (openssl genrsa)"
echo 'app-store-connect certificates create --certificate-key @file:k.pem' | scan_script "creates a certificate"
echo 'app-store-connect certificates revoke X' | scan_script "revokes a certificate"
echo 'app-store-connect fetch-signing-files "$id" --type TVOS_APP_STORE --create' | scan_script "runs fetch-signing-files --create"
echo 'app-store-connect profiles delete X' | scan_script "deletes a profile"
printf '# openssl genrsa is never run here\necho ok\n' > "$t/c.sh"
r="$t/repo-c"; mkdir -p "$r/scripts"; cp scripts/pre-push-check.sh "$r/scripts/"; cp "$Y" "$r/codemagic.yaml"; cp "$t/c.sh" "$r/scripts/cm-extra.sh"; git -C "$r" init -q
(cd "$r" && bash scripts/pre-push-check.sh 2>&1) | grep -q 'could make' && bad "pre-push refused a comment line" || ok "pre-push ignores the commands in comment lines"

echo "codemagic tests: passed $pass, failed $fail, skipped $skip"
[ "$fail" -eq 0 ]
