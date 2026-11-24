#!/usr/bin/env bash
# Self-test for scripts/ci-testflight-log.sh (the redacted log view of testflight.yml) and for the shape of
# .github/workflows/testflight.yml. Runs anywhere with bash, grep and sed; contacts nothing. The names and IDs below are
# synthetic.
set -uo pipefail
cd "$(dirname "$0")/.."
pass=0; fail=0
ok()  { echo "ok    $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
S=scripts/ci-testflight-log.sh
W=.github/workflows/testflight.yml

cat > "$t/fail.log" <<'EOF'
note: Using codesigning identity override: Apple Distribution
Signing Identity:     "Apple Distribution: Sample Person (ZZ00000000)"
Provisioning Profile: "iOS Team Store Provisioning Profile: com.example.app"
    /usr/bin/codesign --force --sign 0000 --entitlements x.xcent "Apple Distribution: Sample Person (ZZ00000000)"
Contact sample.person@example.invalid for access.
error: No profiles for 'com.example.app' were found
** ARCHIVE FAILED **
EOF
out="$(GITHUB_STEP_SUMMARY="$t/summary.md" bash "$S" "$t/fail.log" Archive 65 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "a failed log: the script itself exits 0 (the workflow exits with xcodebuild's code)" || bad "script exit $rc"
printf '%s' "$out" | grep -q 'Sample Person' && bad "the holder's name is printed" || ok "the certificate holder's name is removed"
printf '%s' "$out" | grep -q 'example.invalid' && bad "an e-mail address is printed" || ok "e-mail addresses are removed"
printf '%s' "$out" | grep -q 'ZZ00000000' && bad "the team ID in the identity is printed" || ok "the team ID inside the identity is removed"
printf '%s' "$out" | grep -q "error: No profiles for 'com.example.app' were found" && ok "the error line is kept as it is" || bad "the error line is missing"
printf '%s' "$out" | grep -q 'ARCHIVE FAILED' && ok "the FAILED line is kept" || bad "FAILED line missing"
printf '%s' "$out" | grep -q '::error::Archive failed (exit 65)' && ok "an annotation names the step and the exit code" || bad "no annotation"
grep -q "No profiles" "$t/summary.md" 2>/dev/null && ok "the first error goes to the step summary" || bad "summary has no error"
grep -q 'Sample Person' "$t/summary.md" 2>/dev/null && bad "summary has the name" || ok "the step summary has no name either"

printf '%s\n' 'warning: something' 'Upload succeeded.' '** EXPORT SUCCEEDED **' > "$t/ok.log"
out="$(bash "$S" "$t/ok.log" Export 0 2>&1)"
printf '%s' "$out" | grep -q 'succeeded (exit 0). Warnings: 1' && ok "a good log: one summary line with the warning count" || bad "good-log summary: $out"
printf '%s' "$out" | grep -q 'EXPORT SUCCEEDED' && ok "a good log: the result line is shown" || bad "result line missing"
out="$(bash "$S" "$t/none.log" Export 1 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'no log was written' && ok "a missing log is reported, not a crash" || bad "missing log: $out"

# The workflow's shape (the pre-push check enforces the secret and trigger rules; these lock the rest). R463: manual signing
# like the Codemagic route; no automatic signing, no Team ID secret. Comment lines are left out of these checks.
grep -qE '^  workflow_dispatch:' "$W" && ! grep -qE '^  (push|pull_request|schedule|workflow_run|release):' "$W" && ok "testflight.yml: manual trigger only" || bad "trigger"
code="$(grep -vE '^[[:space:]]*#' "$W")"
if python3 -c 'import yaml' 2>/dev/null; then
  out="$(python3 - "$W" <<'EOF'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True, d.get("on"))
j = d["jobs"]
jb = list(j.values())[0]
r = []
def c(n, cond): r.append(("ok" if cond else "FAIL") + "|" + n)
c("testflight.yml parses as YAML", isinstance(d, dict))
c("the only trigger is workflow_dispatch", list(on.keys()) == ["workflow_dispatch"])
c("one job, 30 minutes, runner xcode-27", len(j) == 1 and jb.get("timeout-minutes") == 30 and jb.get("runs-on") == "xcode-27")
c("concurrency group testflight, no cancel", d.get("concurrency", {}).get("group") == "testflight")
c("permissions: contents read only", d.get("permissions") == {"contents": "read"})
c("the only input is the keep_ipa box, default off", list(on["workflow_dispatch"]["inputs"].keys()) == ["keep_ipa"] and on["workflow_dispatch"]["inputs"]["keep_ipa"]["default"] is False)
print("\n".join(r))
EOF
)"
  printf '%s\n' "$out" | while IFS='|' read -r s n; do [ "$s" = ok ] && echo "ok    testflight.yml: $n" || echo "FAIL  testflight.yml: $n"; done > "$t/yaml.txt"
  cat "$t/yaml.txt"; pass=$((pass + $(grep -c '^ok' "$t/yaml.txt"))); fail=$((fail + $(grep -c '^FAIL' "$t/yaml.txt")))
else
  echo "SKIP  testflight.yml YAML parse (PyYAML not installed)"
fi
printf '%s\n' "$code" | grep -qE 'CODE_SIGN_STYLE=Automatic|-allowProvisioningUpdates|-authenticationKeyPath .*archive' && bad "testflight.yml: automatic signing is back (R463: it needs a registered device)" || ok "testflight.yml: no automatic signing"
for s in "gh-testflight.sh install-cert" "cm-testflight.sh signing" "cm-testflight.sh check-profiles" "cm-testflight.sh prepare" "cm-testflight.sh archive" "cm-testflight.sh export" "gh-testflight.sh upload" "gh-testflight.sh cleanup"; do
  printf '%s\n' "$code" | grep -qE "^[[:space:]]+(run: )?bash scripts/$s\$" && ok "testflight.yml runs scripts/$s" || bad "testflight.yml misses scripts/$s"
done
printf '%s\n' "$code" | awk '/gh-testflight.sh install-cert/{a=NR} /cm-testflight.sh signing/{b=NR} /cm-testflight.sh archive/{c=NR} /cm-testflight.sh export/{d=NR} /gh-testflight.sh upload/{e=NR} END{exit !(a<b && b<c && c<d && d<e)}' \
  && ok "testflight.yml: certificate, signing, archive, export, upload in that order" || bad "step order"
grep -qiE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' "$W" && bad "a key header is written out in the workflow" || ok "testflight.yml: no key header text (built at run time, R251)"
grep -q 'kind="PRIVATE"' "$W" && grep -q 'fold -w 64' "$W" && ok "testflight.yml: the API key file is rebuilt from the secret's body (R251)" || bad "key rebuild"
[ "$(grep -cE '^[[:space:]]*runs-on: xcode-27$' "$W")" -eq 1 ] && ok "testflight.yml: one job on the standard xcode-27 runner" || bad "runner"
grep -q 'Xcode_27.2.app' "$W" && grep -q 'Xcode_27.2.app' .github/workflows/compile-check.yml && ok "testflight.yml: the same Xcode 27.2 as compile-check.yml" || bad "Xcode selection differs"
names="$(grep -oE 'secrets\.[A-Za-z0-9_]+' "$W" | sort -u | tr '\n' ' ')"
[ "$names" = "secrets.ASC_ISSUER_ID secrets.ASC_KEY_ID secrets.ASC_KEY_P8 secrets.DIST_CERT_PRIVATE_KEY " ] && ok "testflight.yml: exactly the four named secrets" || bad "secrets used: $names"
grep -qE 'APPLE_TEAM_ID|TEAM_ID' "$W" && bad "a Team ID secret is used (R463: not needed)" || ok "testflight.yml: no Team ID secret"
grep -qE 'GITHUB_TOKEN|github\.token|secrets: *inherit' "$W" && bad "a GitHub token is used" || ok "testflight.yml: no GitHub token"
grep -q 'persist-credentials: false' "$W" && ok "testflight.yml: the checkout keeps no credentials" || bad "persist-credentials"
[ "$(grep -c 'upload-artifact' "$W")" -eq 1 ] && grep -q 'path: build/ios/ipa/\*.ipa' "$W" && grep -q 'if: \${{ inputs.keep_ipa }}' "$W" && ok "testflight.yml: the one artifact is the .ipa, only when the box is ticked" || bad "artifact rules"
grep -qE 'path:.*(\.log|logs|asc|\.p8|\.key|keychain)' "$W" && bad "an artifact path could hold a log or a key" || ok "testflight.yml: no log or key in an artifact (R249)"
grep -B1 -A2 'Delete the keys' "$W" | grep -q 'if: always()' && ok "testflight.yml: the keys are deleted in an always() step" || bad "key deletion not always()"
grep -qE 'echo.*\$(ASC_KEY_P8|\{ASC_KEY_P8\}|DIST_CERT_PRIVATE_KEY|\{DIST_CERT_PRIVATE_KEY\})' "$W" && bad "a key text is echoed" || ok "testflight.yml: no key text is echoed"
grep -q 'chmod 600' "$W" && grep -q 'umask 077' "$W" && ok "testflight.yml: key files are written with mode 600" || bad "key file mode"
# One source for the XcodeGen pin: read from compile-check.yml at run time, no copy in this file.
grep -qE '^[[:space:]]*XCODEGEN_(VERSION|SHA256): "[0-9a-f.]+"' "$W" && bad "testflight.yml holds its own XcodeGen pin (it must read compile-check.yml's)" || ok "testflight.yml: no copy of the XcodeGen pin"
v="$(sed -nE 's/^[[:space:]]+XCODEGEN_VERSION: "([^"]+)"$/\1/p' .github/workflows/compile-check.yml | sort -u)"
s="$(sed -nE 's/^[[:space:]]+XCODEGEN_SHA256: "([^"]+)"$/\1/p' .github/workflows/compile-check.yml | sort -u)"
[ "$(printf '%s\n' "$v" | wc -l)" -eq 1 ] && printf '%s' "$s" | grep -Eq '^[0-9a-f]{64}$' && ok "compile-check.yml: one XcodeGen version and one SHA-256 for the workflow to read ($v)" || bad "XcodeGen pin in compile-check.yml"
grep -q 'sed -nE .s/\^\[\[:space:\]\]+XCODEGEN_VERSION' "$W" && grep -q 'compile-check.yml' "$W" && ok "testflight.yml: reads the pin from compile-check.yml" || bad "pin read"
# The helper script: it can import a certificate and a key into a temporary keychain, and nothing else about keys.
G=scripts/gh-testflight.sh
bash -n "$G" && ok "gh-testflight.sh: bash syntax" || bad "gh-testflight.sh syntax"
gcode="$(grep -vE '^[[:space:]]*#' "$G")"
printf '%s\n' "$gcode" | grep -qE 'genrsa|genpkey|ecparam|ssh-keygen|openssl[[:space:]]+req|-newkey|certificates[[:space:]]+(create|delete|revoke)|fetch-signing-files|--certificate-key|--create|profiles[[:space:]]+delete|delete-identity|delete-certificate' \
  && bad "gh-testflight.sh can make, revoke or delete a key or certificate" || ok "gh-testflight.sh: no key or certificate is made, revoked or deleted"
printf '%s\n' "$gcode" | grep -qE 'echo[^|]*\$\{?(DIST_KEY_FILE|pw)\b|find-identity[^|]*$' && bad "gh-testflight.sh prints a key, a password or an identity line" || ok "gh-testflight.sh: prints no key, password or identity line"
grep -q 'cert-files' "$G" && grep -q 'cert-files' scripts/cm-signing.py && ok "gh-testflight.sh and cm-signing.py share the cert-files step" || bad "cert-files"
# install-cert against a throwaway key and certificate (made here with openssl; Linux has no keychain, so only the matching
# is run: cm-signing.py cert-files writes the DER files and the public-key hash of exactly one equals the key's).
if command -v openssl >/dev/null 2>&1; then
  mkdir -p "$t/ic"
  for n in 1 2; do
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$t/ic/k$n.pem" -out "$t/ic/c$n.pem" -days 2 -subj "/CN=Sample $n" >/dev/null 2>&1
  done
  python3 - "$t/ic" <<'EOF'
import base64, json, subprocess, sys
d = sys.argv[1]
items = []
for n in (1, 2):
    der = subprocess.run(["openssl", "x509", "-in", "%s/c%d.pem" % (d, n), "-outform", "DER"], capture_output=True).stdout
    items.append({"id": "CERT%d" % n, "attributes": {"certificateContent": base64.b64encode(der).decode()}})
json.dump({"data": items}, open(d + "/certs.json", "w"))
EOF
  out="$(python3 scripts/cm-signing.py cert-files "$t/ic/certs.json" "$t/ic" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '2 certificate(s)' && ls "$t/ic"/cert-1.der "$t/ic"/cert-2.der >/dev/null 2>&1 && ok "cm-signing.py cert-files writes one DER file per listed certificate" || bad "cert-files: $out"
  kh="$(openssl pkey -in "$t/ic/k2.pem" -pubout -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)"; hits=0
  for der in "$t/ic"/cert-*.der; do
    h="$(openssl x509 -inform DER -in "$der" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)"
    [ "$h" = "$kh" ] && hits=$((hits + 1))
  done
  [ "$hits" -eq 1 ] && ok "exactly one listed certificate matches the key (the public-key comparison install-cert uses)" || bad "key match count $hits"
  printf '{"data":[]}' > "$t/ic/none.json"; mkdir -p "$t/ic/n"
  python3 scripts/cm-signing.py cert-files "$t/ic/none.json" "$t/ic/n" >/dev/null 2>&1 && bad "cert-files accepted an empty list" || ok "cert-files fails on an empty list"
  printf 'not a key\n' > "$t/ic/notakey.txt"
  out="$(DIST_KEY_FILE="$t/ic/notakey.txt" RUNNER_TEMP="$t/rt" bash "$G" install-cert 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'not a readable private key' && ok "install-cert stops on a file that is not a private key" || bad "install-cert with a bad key: $out"
else
  echo "SKIP  install-cert matching (openssl not installed)"
fi

# R248: the pre-push exception is narrow. The real scripts/pre-push-check.sh runs in a throwaway repository holding only
# itself and one workflow variant; only its workflow messages are read.
scan() { # $1 = workflow file name, stdin = its text
  local r="$t/repo-$RANDOM"; mkdir -p "$r/scripts" "$r/.github/workflows"
  cp scripts/pre-push-check.sh "$r/scripts/"; cat > "$r/.github/workflows/$1"
  git -C "$r" init -q 2>/dev/null; (cd "$r" && bash scripts/pre-push-check.sh 2>&1)
}
out="$(scan testflight.yml < "$W")"
printf '%s' "$out" | grep -q 'secrets: only ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, DIST_CERT_PRIVATE_KEY' && ! printf '%s' "$out" | grep -q '^!! .github/workflows' \
  && ok "pre-push: testflight.yml as committed passes the workflow checks" || bad "pre-push on the real testflight.yml: $(printf '%s' "$out" | grep '!!')"
out="$( { cat "$W"; printf '      - run: echo hi\n        env:\n          X: ${{ secrets.OTHER_SECRET }}\n'; } | scan testflight.yml)"
printf '%s' "$out" | grep -q 'uses a secret other than' && ok "pre-push: a fifth secret in testflight.yml is refused" || bad "fifth secret not refused"
out="$( { cat "$W"; printf '        env:\n          X: ${{ secrets.ASC_KEY_ID || secrets.OTHER }}\n'; } | scan testflight.yml)"
printf '%s' "$out" | grep -q 'uses a secret other than' && ok "pre-push: an allowed name mixed with another in one expression is refused" || bad "mixed expression not refused"
out="$( { cat "$W"; printf '        env:\n          T: ${{ github.token }}\n'; } | scan testflight.yml)"
printf '%s' "$out" | grep -q 'refers to the GitHub token' && ok "pre-push: the GitHub token in testflight.yml is refused" || bad "token not refused"
out="$( { cat "$W"; printf '      - run: openssl genrsa -out k.pem 2048\n'; } | scan testflight.yml)"
printf '%s' "$out" | grep -q 'could make, revoke or delete a key' && ok "pre-push (R463): a command that makes a key in testflight.yml is refused" || bad "key generation not refused"
out="$( { cat "$W"; printf '      - run: app-store-connect certificates create --type DISTRIBUTION\n'; } | scan testflight.yml)"
printf '%s' "$out" | grep -q 'could make, revoke or delete a key' && ok "pre-push (R463): a certificate-creating command in testflight.yml is refused" || bad "certificate creation not refused"
out="$( { cat "$W"; printf '      - run: echo "$DIST_CERT_PRIVATE_KEY"\n'; } | scan testflight.yml)"
printf '%s' "$out" | grep -q 'testflight.yml echoes a key' && ok "pre-push (R463): echoing a key in testflight.yml is refused" || bad "echo of a key not refused"
out="$(scan other.yml < "$W")"
printf '%s' "$out" | grep -q 'other.yml refers to secrets or the GitHub token' && ok "pre-push: the same secrets in any other workflow are refused" || bad "other workflow not refused"

echo "testflight-log tests: passed $pass, failed $fail"
[ "$fail" -eq 0 ]
