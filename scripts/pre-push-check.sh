#!/usr/bin/env bash
# Lists every changed file and flags likely secrets. Review the list against the plan before pushing.
# Run from the project folder after `git init`. Exit 1 when anything is flagged.
set -u
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
#  - use no secrets at all (no `secrets.` expression, no GITHUB_TOKEN use, no `secrets: inherit`);
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
    if grep -nEi '\$\{\{[^}]*(secrets|github\.token)|secrets: *inherit|GITHUB_TOKEN' "$w"; then
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
  echo "Workflows: manual trigger only, no secrets, standard runners only."
fi

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
