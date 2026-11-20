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

# The workflow's shape (the pre-push check enforces the secret and trigger rules; these lock the rest).
grep -qE '^  workflow_dispatch:' "$W" && ! grep -qE '^  (push|pull_request|schedule|workflow_run|release):' "$W" && ok "testflight.yml: manual trigger only" || bad "trigger"
# R245: automatic signing with no identity set by hand (Xcode refuses Automatic together with a CODE_SIGN_IDENTITY), no
# Run-button input, and the export does the distribution signing. Comment lines are left out of these checks.
code="$(grep -vE '^[[:space:]]*#' "$W")"
printf '%s\n' "$code" | grep -qE '^    inputs:' && bad "testflight.yml: a Run-button input is back" || ok "testflight.yml: no Run-button input (R245)"
printf '%s\n' "$code" | grep -q 'CODE_SIGN_IDENTITY' && bad "testflight.yml: CODE_SIGN_IDENTITY is set (Xcode refuses it with Automatic)" || ok "testflight.yml: no CODE_SIGN_IDENTITY override (R245)"
[ "$(printf '%s\n' "$code" | grep -cE '^[[:space:]]+CODE_SIGN_STYLE=Automatic \\$')" -eq 1 ] && ok "testflight.yml: the archive uses CODE_SIGN_STYLE=Automatic" || bad "CODE_SIGN_STYLE=Automatic missing on the archive"
printf '%s\n' "$code" | grep -q '<key>method</key><string>app-store-connect</string>' && printf '%s\n' "$code" | grep -q '<key>signingStyle</key><string>automatic</string>' \
  && ok "testflight.yml: the export signs for App Store Connect, automatically" || bad "export options"
grep -qiE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' "$W" && bad "a key header is written out in the workflow" || ok "testflight.yml: no key header text (built at run time, R251)"
grep -q 'kind="PRIVATE"' "$W" && grep -q 'fold -w 64' "$W" && ok "testflight.yml: the key file is rebuilt from the secret's body (R251)" || bad "key rebuild"
[ "$(grep -cE '^[[:space:]]*runs-on: xcode-27$' "$W")" -eq 1 ] && ok "testflight.yml: one job on the standard xcode-27 runner" || bad "runner"
names="$(grep -oE 'secrets\.[A-Za-z0-9_]+' "$W" | sort -u | tr '\n' ' ')"
[ "$names" = "secrets.APPLE_TEAM_ID secrets.ASC_ISSUER_ID secrets.ASC_KEY_ID secrets.ASC_KEY_P8 " ] && ok "testflight.yml: exactly the four named secrets" || bad "secrets used: $names"
grep -qE 'GITHUB_TOKEN|github\.token|secrets: *inherit' "$W" && bad "a GitHub token is used" || ok "testflight.yml: no GitHub token"
grep -q 'persist-credentials: false' "$W" && ok "testflight.yml: the checkout keeps no credentials" || bad "persist-credentials"
grep -q 'upload-artifact' "$W" && bad "an artifact is uploaded (logs can name the holder, R249)" || ok "testflight.yml: no artifact upload"
grep -A2 'Delete the key' "$W" | grep -q 'if: always()' && ok "testflight.yml: the key is deleted in an always() step" || bad "key deletion not always()"
grep -qE 'echo.*\$(ASC_KEY_P8|\{ASC_KEY_P8\})' "$W" && bad "the key text is echoed" || ok "testflight.yml: the key text is never echoed"
for f in -authenticationKeyPath -authenticationKeyID -authenticationKeyIssuerID -allowProvisioningUpdates; do
  # Only command lines count (a flag at the start of an indented line), not comments that name the flag.
  [ "$(printf '%s\n' "$code" | grep -cE -- "^[[:space:]]+$f( |$)")" -eq 2 ] && ok "testflight.yml: $f on archive and export" || bad "$f missing"
done
grep -q 'CURRENT_PROJECT_VERSION="\$BUILD_NUMBER"' "$W" && grep -q "date -u +%Y%m%d%H%M" "$W" && ok "testflight.yml: build number is the UTC time (R246)" || bad "build number"

# R248: the pre-push exception is narrow. The real scripts/pre-push-check.sh runs in a throwaway repository holding only
# itself and one workflow variant; only its workflow messages are read.
scan() { # $1 = workflow file name, stdin = its text
  local r="$t/repo-$RANDOM"; mkdir -p "$r/scripts" "$r/.github/workflows"
  cp scripts/pre-push-check.sh "$r/scripts/"; cat > "$r/.github/workflows/$1"
  git -C "$r" init -q 2>/dev/null; (cd "$r" && bash scripts/pre-push-check.sh 2>&1)
}
out="$(scan testflight.yml < "$W")"
printf '%s' "$out" | grep -q 'secrets: only ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, APPLE_TEAM_ID' && ! printf '%s' "$out" | grep -q '^!! .github/workflows' \
  && ok "pre-push: testflight.yml as committed passes the workflow checks" || bad "pre-push on the real testflight.yml: $(printf '%s' "$out" | grep '!!')"
out="$( { cat "$W"; printf '      - run: echo hi\n        env:\n          X: ${{ secrets.OTHER_SECRET }}\n'; } | scan testflight.yml)"
printf '%s' "$out" | grep -q 'uses a secret other than' && ok "pre-push: a fifth secret in testflight.yml is refused" || bad "fifth secret not refused"
out="$( { cat "$W"; printf '        env:\n          X: ${{ secrets.ASC_KEY_ID || secrets.OTHER }}\n'; } | scan testflight.yml)"
printf '%s' "$out" | grep -q 'uses a secret other than' && ok "pre-push: an allowed name mixed with another in one expression is refused" || bad "mixed expression not refused"
out="$( { cat "$W"; printf '        env:\n          T: ${{ github.token }}\n'; } | scan testflight.yml)"
printf '%s' "$out" | grep -q 'refers to the GitHub token' && ok "pre-push: the GitHub token in testflight.yml is refused" || bad "token not refused"
out="$(scan other.yml < "$W")"
printf '%s' "$out" | grep -q 'other.yml refers to secrets or the GitHub token' && ok "pre-push: the same secrets in any other workflow are refused" || bad "other workflow not refused"

echo "testflight-log tests: passed $pass, failed $fail"
[ "$fail" -eq 0 ]
