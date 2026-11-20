#!/usr/bin/env bash
# Self-test for the Codemagic TestFlight route (OPEN_QUESTIONS R266): codemagic.yaml's shape, scripts/cm-build-number.sh,
# scripts/cm-profile-check.py (against the hand-written sample plists in scripts/codemagic-fixtures/, decoded and as
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
pub = wf.get("publishing", {})
c("publishing: only app_store_connect", list(pub.keys()) == ["app_store_connect"])
c("publishing: auth integration, submit_to_testflight false, nothing else",
  pub.get("app_store_connect") == {"auth": "integration", "submit_to_testflight": False})
steps = [s.get("script", "") for s in wf.get("scripts", [])]
c("the five steps run scripts/cm-testflight.sh prepare, signing, check-profiles, archive, export in order",
  steps == ["bash scripts/cm-testflight.sh " + s for s in ("prepare", "signing", "check-profiles", "archive", "export")])
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

# --- build number ---
n="$(bash scripts/cm-build-number.sh)"
printf '%s' "$n" | grep -Eq '^[0-9]{12}$' && ok "build number has 12 digits ($n)" || bad "build number '$n'"
now="$(date -u +%Y%m%d%H%M)"; [ $((now - n)) -ge 0 ] && [ $((now - n)) -le 1 ] && ok "build number is the UTC time yyyyMMddHHmm" || bad "build number $n is not now ($now)"
bash scripts/cm-build-number.sh --check "$n" && ok "--check accepts the build number" || bad "--check refuses $n"
r=0; for v in 202613011200 202611321200 202611202460 2026112012 abc ""; do bash scripts/cm-build-number.sh --check "$v" && r=1; done
[ "$r" -eq 0 ] && ok "--check refuses month 13, day 32, minute 60, a short value, letters and empty" || bad "--check accepted a wrong value"

# --- profile check, decoded plists (hand-written samples) ---
out="$(python3 "$PC" plists "$F/app-ok.plist" "$F/topshelf-ok.plist")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^PROFILE CHECK: com.liamp.videoplayer has iCloud.com.liamp.videoplayer and group.com.liamp.videoplayer; com.liamp.videoplayer.topshelf has group.com.liamp.videoplayer$' \
  && ok "profile check: both sample profiles complete, exit 0 and one result line" || bad "profile check ok case: $rc $out"
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

echo "codemagic tests: passed $pass, failed $fail, skipped $skip"
[ "$fail" -eq 0 ]
