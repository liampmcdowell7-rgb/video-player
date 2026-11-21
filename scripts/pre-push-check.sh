#!/usr/bin/env bash
# Lists every changed file and flags likely secrets. Review the list against the plan before pushing.
# Run from the project folder after `git init`. Exit 1 when anything is flagged.
set -u
# #22 E: the first line of the output, before any check can stop the script.
echo "Run this before git push, every time."
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$TOP" ]; then echo "!! Not a git repository yet. Run: git init   then run this check again."; exit 1; fi
if [ -n "$(git rev-parse --show-prefix)" ]; then
  echo "!! The project folder is inside a bigger git repository ($TOP). Run: git init   inside the project folder."; exit 1
fi
echo "== Changed / untracked files =="
git status --porcelain
echo
echo "== Secret-looking file names =="
if git ls-files -co --exclude-standard | grep -E '\.(p8|p12|pem|cer|mobileprovision)$|(^|/)signing_key(\.pub)?$|(^|/)\.env'; then
  echo "!! Secret-looking file name above. Do NOT push."
  exit 1
fi
echo "== Secret-pattern scan (tracked + untracked, excluding .git) =="
# Fixed 2026-11-17 (R81): the old version tested xargs' exit status, which is 123 whenever any batch had no match, so
# printed matches were reported as "No secret patterns found". Now any output from a scan counts as a finding.
# Skips: "password = literal" inside Tests/ folders (example passwords are expected there). Everything under Vendor/ is
# third-party code (Citadel, swift-nio-ssh, AMSMB2) whose upstream tests and examples contain public sample keys and
# passwords; it is not pattern-scanned, only counted below so the exemption stays visible. File NAMES are checked everywhere.
LIST="$(git ls-files -co --exclude-standard)"
SCAN="$(printf '%s\n' "$LIST" | grep -v -E '(^|/)Vendor/' || true)"
VENDOR="$(printf '%s\n' "$LIST" | grep -E '(^|/)Vendor/' || true)"
VN=0
if [ -n "$VENDOR" ]; then
  VN="$(printf '%s\n' "$VENDOR" | tr '\n' '\0' | xargs -0 grep -lEI 'PRIVATE KEY-----|password *[:=] *"' 2>/dev/null | wc -l)"
fi
echo "Vendor/ is third-party code and is not pattern-scanned; $VN vendored files contain sample keys or passwords (public upstream test text)."
HITS="$(printf '%s\n' "$SCAN" | tr '\n' '\0' | xargs -0 grep -nEI \
  '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|api[_-]?key *[:=] *["'"'"'][A-Za-z0-9]{16,}|AKIA[0-9A-Z]{16})' 2>/dev/null || true)"
HITS2="$(printf '%s\n' "$SCAN" | grep -v -E '(^|/)Tests/' | tr '\n' '\0' | xargs -0 grep -nEI \
  'password *[:=] *["'"'"'][^"'"'"']+' 2>/dev/null || true)"
if [ -n "$HITS$HITS2" ]; then
  printf '%s\n%s\n' "$HITS" "$HITS2" | sed '/^$/d'
  echo "!! Possible secret found above. Do NOT push."
  exit 1
fi
echo "No secret patterns found."

# --- GitHub Actions workflows (.github/workflows), added 2026-11-17 ---
# They are part of the pattern scan above (they are not under Vendor/). On top of that every workflow must:
#  - use no secrets at all (no `secrets.` expression, no GITHUB_TOKEN use, no `secrets: inherit`), except testflight.yml,
#    which may read only its four named secrets (R248, below); the GitHub token stays refused there too;
#  - be started by hand only (`workflow_dispatch`; no push, pull_request, schedule or other trigger);
#  - run only on a STANDARD GitHub-hosted runner (larger runners, labels ending in -large / -xlarge, are billed even for
#    public repositories); a self-hosted runner is refused too.
echo
echo "== GitHub Actions workflows =="
WF="$(printf '%s\n' "$LIST" | grep -E '^\.github/workflows/[^/]+\.ya?ml$' || true)"
if [ -z "$WF" ]; then
  echo "No workflow files."
else
  WBAD=0
  while IFS= read -r w; do
    [ -f "$w" ] || continue
    echo "-- $w"
    if [ "$w" = ".github/workflows/testflight.yml" ]; then
      # OPEN_QUESTIONS R248 (PROVISIONAL): the ONE exception. This file may read exactly these four repository secrets, each
      # only as the whole expression `${{ secrets.NAME }}`; never the GitHub token, `secrets: inherit` or any other secret.
      if grep -nEi 'github\.token|secrets: *inherit|GITHUB_TOKEN|secrets\[' "$w"; then
        echo "!! $w refers to the GitHub token or to secrets in a form other than \${{ secrets.NAME }} (lines above)."; WBAD=1
      fi
      OTHER="$(grep -nEi '\$\{\{[^}]*secrets' "$w" | grep -vE '\$\{\{ secrets\.(ASC_KEY_ID|ASC_ISSUER_ID|ASC_KEY_P8|APPLE_TEAM_ID) \}\}' || true)"
      OTHER2="$(grep -oE '\$\{\{[^}]*secrets[^}]*\}\}' "$w" | grep -vxE '\$\{\{ secrets\.(ASC_KEY_ID|ASC_ISSUER_ID|ASC_KEY_P8|APPLE_TEAM_ID) \}\}' || true)"
      if [ -n "$OTHER$OTHER2" ]; then
        printf '%s\n%s\n' "$OTHER" "$OTHER2" | sed '/^$/d'
        echo "!! $w uses a secret other than ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, APPLE_TEAM_ID (above)."; WBAD=1
      else
        echo "   secrets: only ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, APPLE_TEAM_ID (the TestFlight exception, R248)"
      fi
    elif grep -nEi '\$\{\{[^}]*(secrets|github\.token)|secrets: *inherit|GITHUB_TOKEN' "$w"; then
      echo "!! $w refers to secrets or the GitHub token (lines above)."; WBAD=1
    fi
    # Triggers: the `on:` block may only contain workflow_dispatch.
    TRIG="$(awk '/^on:/{f=1; sub(/^on:[[:space:]]*/,""); if ($0!="") print; next} f && /^[^[:space:]#]/{f=0} f && /^  [A-Za-z_]+:/{gsub(/[: {}]/,""); print}' "$w" | tr -d '[]' | tr ',' '\n' | sed 's/[[:space:]]//g' | sed '/^$/d' | sort -u)"
    if [ "$TRIG" != "workflow_dispatch" ]; then
      echo "!! $w has triggers other than workflow_dispatch: $(echo $TRIG)"; WBAD=1
    fi
    while IFS= read -r label; do
      [ -n "$label" ] || continue
      case "$label" in
        *-large|*-xlarge|*self-hosted*|*\$\{\{*)
          echo "!! $w runs-on '$label' is not a standard GitHub-hosted runner (larger runners are always billed)."; WBAD=1 ;;
        ubuntu-latest|ubuntu-2[0-9].04|ubuntu-2[0-9].04-arm|ubuntu-24.04-arm|windows-latest|windows-20[0-9][0-9]|macos-latest|macos-1[0-9]|macos-2[0-9]|macos-1[0-9]-intel|macos-2[0-9]-intel|xcode-2[0-9])
          echo "   runs-on $label (standard runner)" ;;
        *)
          echo "!! $w runs-on '$label' is not on the standard-runner allow list in this script; check it against the GitHub runner reference."; WBAD=1 ;;
      esac
    done < <(grep -E '^[[:space:]]*runs-on:' "$w" | sed -E 's/^[[:space:]]*runs-on:[[:space:]]*//; s/[][" '"'"']//g' | tr ',' '\n')
  done <<< "$WF"
  if [ "$WBAD" -ne 0 ]; then echo "!! Workflow problem found above. Do NOT push."; exit 1; fi
  echo "Workflows: manual trigger only, no secrets (testflight.yml: its four named secrets only, R248), standard runners only."
fi

# --- codemagic.yaml (OPEN_QUESTIONS R266) ---
# The owner's decision of 20 Nov 2026: Codemagic for the TestFlight upload only. The file passed the scans above already;
# this section grants no exception, it only holds the file to that one purpose. It must: start by hand only (no
# `triggering:` key), have exactly one workflow, use exactly one integration (`app_store_connect: asc-testflight`), read no
# secret (no environment `groups:`, no `api_key:`, no variable whose name looks like a key, token, password or
# certificate), publish only to App Store Connect with the integration (no e-mail, Slack or other publisher), run on the
# free `mac_mini_m2`, stop within 30 minutes, and pin an exact Xcode version (not `latest` or `edge`). Signing: its
# `ios_signing` names only the owner's one stored certificate ("Balance Ahead distribution"), and neither it nor
# scripts/cm-* contains a command that makes, revokes or deletes a key or a certificate.
if printf '%s\n' "$LIST" | grep -qx 'codemagic.yaml'; then
  echo
  echo "== Codemagic (codemagic.yaml, R266) =="
  CBAD=0
  CM="$(grep -vE '^[[:space:]]*#' codemagic.yaml | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' | grep -v '^$')"
  # cm_block KEY: the lines nested under the first `KEY:` line, with their indentation removed relative to it.
  cm_block() {
    printf '%s\n' "$CM" | awk -v k="$1" '
      found && match($0, /^ */) && RLENGTH <= ind { exit }
      found { print substr($0, ind + 3) }
      !found && $0 ~ "^ *" k ":$" { found = 1; match($0, /^ */); ind = RLENGTH }'
  }
  cm_bad() { echo "!! codemagic.yaml: $1"; CBAD=1; }
  printf '%s\n' "$CM" | grep -qE '^[[:space:]]*triggering:' && cm_bad "has a triggering: section (builds must start by hand only)"
  n="$(cm_block workflows | grep -cE '^[A-Za-z0-9_-]+:$')"
  [ "$n" -eq 1 ] || cm_bad "has $n workflows (exactly one, the TestFlight upload)"
  [ "$(cm_block integrations)" = "app_store_connect: asc-testflight" ] || cm_bad "integrations must be exactly 'app_store_connect: asc-testflight'"
  printf '%s\n' "$CM" | grep -qE '^[[:space:]]*groups:' && cm_bad "uses environment groups (secrets); none are allowed"
  printf '%s\n' "$CM" | grep -qE '^[[:space:]]*(api_key|key_id|issuer_id):' && cm_bad "names an API key directly; only the integration is allowed"
  cm_block vars | grep -iE '^[A-Za-z0-9_]*(KEY|SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CERTIFICATE|P12|P8)[A-Za-z0-9_]*:' \
    && cm_bad "a variable above looks like a secret"
  pubs="$(cm_block publishing | grep -E '^[A-Za-z0-9_]+:' | tr '\n' ' ')"
  [ "$pubs" = "app_store_connect: " ] || cm_bad "publishes to '$pubs' (only app_store_connect is allowed)"
  cm_block app_store_connect | grep -qx 'auth: integration' || cm_bad "app_store_connect publishing must use auth: integration"
  printf '%s\n' "$CM" | grep -E '^[[:space:]]*instance_type:' | grep -qvE 'instance_type: mac_mini_m2$' && cm_bad "instance_type must be mac_mini_m2"
  d="$(printf '%s\n' "$CM" | sed -nE 's/^[[:space:]]*max_build_duration:[[:space:]]*([0-9]+)$/\1/p' | head -n 1)"
  { [ -n "$d" ] && [ "$d" -le 30 ]; } || cm_bad "max_build_duration must be set and at most 30 (is '${d:-unset}')"
  printf '%s\n' "$CM" | grep -qE '^[[:space:]]*xcode:[[:space:]]*"?[0-9]+\.[0-9]+(\.[0-9]+)?"?$' || cm_bad "xcode must be an exact version (not latest or edge)"
  # Signing (R266): ios_signing must name exactly the owner's one stored certificate, by reference, and nothing else
  # (no profile references, no distribution_type / bundle_identifier, no second certificate, no file-path variable).
  [ "$(printf '%s\n' "$CM" | grep -cE '^[[:space:]]*ios_signing:$')" -eq 1 ] || cm_bad "needs exactly one ios_signing: section"
  [ "$(cm_block ios_signing)" = "$(printf 'certificates:\n  - "Balance Ahead distribution"')" ] \
    || cm_bad "ios_signing must be exactly 'certificates: - \"Balance Ahead distribution\"' (the one stored certificate)"
  # Neither the workflow nor its scripts may make, revoke or delete a key or a certificate (comment lines ignored).
  CMS="$(printf '%s\n' "$LIST" | grep -E '^scripts/cm-[^/]+$' || true)"
  KEYGEN='genrsa|genpkey|ecparam|ssh-keygen|openssl[[:space:]]+req|-newkey|certificates[[:space:]]+(create|delete|revoke)|fetch-signing-files|--certificate-key|CERTIFICATE_PRIVATE_KEY|--create|--delete-stale-profiles|profiles[[:space:]]+delete|keychain[[:space:]]+add-certificates|security[[:space:]]+(delete|import|create-keychain)'
  for f in codemagic.yaml $CMS; do
    hits="$(grep -vE '^[[:space:]]*#' "$f" | grep -nE "$KEYGEN" | cut -c1-120)"
    [ -z "$hits" ] || cm_bad "$f could make, revoke or delete a key or certificate: $hits"
  done
  if [ "$CBAD" -ne 0 ]; then echo "!! codemagic.yaml problem found above. Do NOT push."; exit 1; fi
  echo "codemagic.yaml: manual only, one workflow, integration asc-testflight only, no secrets, App Store Connect publishing only, mac_mini_m2, at most 30 minutes, exact Xcode, the one stored certificate only, no key or certificate made."
fi

# --- Claude Code files (#28 item 8) ---
# CLAUDE.md, everything under .claude/ (settings, hooks, skills, agents) and the hook self-test are public. They must hold
# no secrets, no personal details and no machine paths, and the personal files must never be tracked. The names checked
# for are read at run time (git user name and e-mail, the login name), so this script itself names nobody.
echo
echo "== Claude Code files =="
CBAD=0
for f in .claude/settings.local.json CLAUDE.local.md; do
  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then echo "!! $f is tracked; it is personal. Run: git rm --cached $f"; CBAD=1; fi
  if [ -e "$f" ] && ! git check-ignore -q -- "$f"; then echo "!! $f exists and is not gitignored."; CBAD=1; fi
done
CF="$(printf '%s\n' "$LIST" | grep -E '^(CLAUDE\.md|\.claude/|scripts/test-claude-hooks\.sh$)' || true)"
if [ -n "$CF" ]; then
  CHITS="$(printf '%s\n' "$CF" | tr '\n' '\0' | xargs -0 grep -nEI \
    '(BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|sk-[A-Za-z0-9_-]{20,}|xox[abprs]-|AIza[0-9A-Za-z_-]{30}|eyJ[A-Za-z0-9_-]{10,}\.eyJ|(key|token|secret|password) *[:=] *["'"'"'][A-Za-z0-9/+_-]{12,})' 2>/dev/null || true)"
  # Machine paths: a Windows user folder, a macOS or Linux home folder, a WSL view of a Windows user folder.
  CHITS2="$(printf '%s\n' "$CF" | tr '\n' '\0' | xargs -0 grep -nEI \
    '([A-Za-z]:[\\/]+Users[\\/]+[A-Za-z0-9]|/Users/[A-Za-z0-9]|/home/[a-z0-9]|/mnt/[a-z]/Users/|AppData[\\/])' 2>/dev/null || true)"
  # E-mail addresses other than the two the commit rules use.
  CHITS3="$(printf '%s\n' "$CF" | tr '\n' '\0' | xargs -0 grep -noEI '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' 2>/dev/null \
    | grep -viE ':(dev@localhost\.invalid|noreply@anthropic\.com)$' || true)"
  # The person's own names, read from this machine.
  CHITS4=""
  for who in "$(git config user.name 2>/dev/null)" "$(git config user.email 2>/dev/null)" "${USER:-}" "${USERNAME:-}"; do
    [ "${#who}" -ge 3 ] || continue
    case "$who" in "Video Player Dev"|dev@localhost.invalid|root|runner) continue ;; esac
    H="$(printf '%s\n' "$CF" | tr '\n' '\0' | xargs -0 grep -nIiwF -- "$who" 2>/dev/null || true)"
    [ -n "$H" ] && CHITS4="$CHITS4$(printf '%s\n' "$H" | sed 's/:.*//' | sort -u | sed 's/$/: contains a name or e-mail of the person on this machine/')"$'\n'
  done
  if [ -n "$CHITS$CHITS2$CHITS3$CHITS4" ]; then
    printf '%s\n%s\n%s\n%s\n' "$CHITS" "$CHITS2" "$CHITS3" "$CHITS4" | sed '/^$/d'
    echo "!! Secret, machine path or personal detail in the Claude Code files above."; CBAD=1
  fi
fi
if [ "$CBAD" -ne 0 ]; then echo "!! Claude Code file problem found above. Do NOT push."; exit 1; fi
echo "Claude Code files: $(printf '%s\n' "$CF" | sed '/^$/d' | wc -l | tr -d ' ') scanned; no secrets, machine paths or personal details; settings.local.json and CLAUDE.local.md not tracked."

# --- Test class names used in two test targets (addendum #19 B) ---
# XCTest on Linux reports results by class name only, so scripts/test-counts.sh would credit both classes to one target.
echo
echo "== Test class names =="
if ! bash "$HERE/scripts/test-counts.sh" --duplicates; then
  echo "!! Rename one of the test classes above before pushing."
  exit 1
fi

# --- #23 A/E: the error class that broke the first App compile (Section("title") { } header:/footer: { }) ---
# Self-test of the design-lint rule section-title-closure on its fixtures (fail1 must be reported, pass must be clean),
# then the rule on every App/ and Top Shelf file that contains "Section(" (design-lint on those files only: the full lint
# is slow in Git Bash; scripts/test-all.sh runs all of it). This is a pattern check, not a compiler (docs/COVERAGE.md).
echo
echo "== Section title with a header or footer closure (design-lint section-title-closure) =="
FXD="$HERE/scripts/design-lint-fixtures/section-title-closure"
if ! bash "$HERE/scripts/design-lint.sh" "$FXD/fail1.swift" 2>&1 | grep -q '\[section-title-closure\]'; then
  echo "!! design-lint no longer reports $FXD/fail1.swift: the rule is broken."; exit 1
fi
if bash "$HERE/scripts/design-lint.sh" "$FXD/pass.swift" 2>&1 | grep -q '\[section-title-closure\]'; then
  echo "!! design-lint reports $FXD/pass.swift: the rule reports correct code."; exit 1
fi
echo "Rule self-test: fail1.swift reported, pass.swift clean."
SECF="$(git ls-files -co --exclude-standard -- 'App/*.swift' 'TopShelf/*.swift' | while IFS= read -r f; do [ -f "$f" ] && grep -q 'Section(' "$f" && echo "$f"; done || true)"
if [ -n "$SECF" ]; then
  # shellcheck disable=SC2086
  SECHITS="$(bash "$HERE/scripts/design-lint.sh" $SECF 2>&1 | grep '\[section-title-closure\]' || true)"
  if [ -n "$SECHITS" ]; then
    echo "$SECHITS"
    echo "!! The lines above do not compile. Write Section { } header: { Text(\"Title\") } footer: { }. Do NOT push."; exit 1
  fi
fi
echo "No Section(\"title\") with a header or footer closure in $(printf '%s\n' "$SECF" | sed '/^$/d' | wc -l | tr -d ' ') App/Top Shelf files that use Section."

# --- Files GitHub would refuse (over 100 MiB per file) or warn about (over 50 MiB) ---
echo
echo "== Large files =="
BIG="$(printf '%s\n' "$LIST" | while IFS= read -r f; do [ -f "$f" ] && s=$(wc -c < "$f") && [ "$s" -gt 52428800 ] && echo "$s $f"; done || true)"
if [ -z "$BIG" ]; then
  echo "No file is over 50 MiB."
else
  echo "$BIG" | awk '{printf "%8.1f MiB  %s\n", $1/1048576, $2}'
  if echo "$BIG" | awk '$1 > 104857600 {found=1} END {exit !found}'; then
    echo "!! A file above is over 100 MiB: GitHub refuses the push. Do NOT push (see docs/GITHUB_ACTIONS_RUNBOOK.md)."
    exit 1
  fi
  echo "Files over 50 MiB push with a GitHub warning; files over 100 MiB are refused."
fi
