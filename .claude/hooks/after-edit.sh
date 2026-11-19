#!/usr/bin/env bash
# PostToolUse hook (#28 item 4): after Claude edits a file under App/ or UITests/, run the design lint (whole default
# scope: a single-file lint gives false results for rules that look at other files, such as brand-logo) and
# `swiftc -parse` on the edited Swift file (scripts/parse-app.sh FILE). Each is bounded by a time limit.
# Prints nothing when both pass. On a failure, or when a check did not finish in time, it prints only the failing
# lines to stderr and exits 2, which Claude Code shows to Claude. Measured run time: docs/CLAUDE_CODE_SETUP.md.
#
# Where it runs: with a local swiftc (WSL, Linux, a Mac) directly; on Windows through `wsl.exe` when WSL is there.
# Without either, the parse is skipped silently (it is not a failure of the edit) and the lint runs in local bash.
# A pass is never "it compiles": parse-app.sh checks syntax only.
set -u
shopt -s nocasematch
LINT_LIMIT="${VP_HOOK_LINT_LIMIT:-90}"
PARSE_LIMIT="${VP_HOOK_PARSE_LIMIT:-60}"
INPUT="$(cat)"

field() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\"" s
  [[ $INPUT =~ $re ]] || return 0
  s="${BASH_REMATCH[1]}"; s="${s//\\\\/\\}"; s="${s//\\\"/\"}"; printf '%s' "$s"
}
norm() { # forward slashes, /c/... and /mnt/c/... as c:/...
  local p="${1//\\//}"
  if [[ $p =~ ^/mnt/([a-z])/(.*)$ ]] || [[ $p =~ ^/([a-z])/(.*)$ ]]; then p="${BASH_REMATCH[1]}:/${BASH_REMATCH[2]}"; fi
  printf '%s' "${p%/}"
}

FILE="$(norm "$(field file_path)")"
PROJ="$(norm "${CLAUDE_PROJECT_DIR:-$(field cwd)}")"
[ -n "$FILE" ] && [ -n "$PROJ" ] || exit 0
[[ $FILE == "$PROJ"/* ]] || exit 0
REL="${FILE:${#PROJ}+1}"
[[ $REL == App/* || $REL == UITests/* ]] || exit 0
PARSE_ARG=""
[[ $REL == *.swift ]] && PARSE_ARG="$REL"

ROOT="${CLAUDE_PROJECT_DIR:-$PROJ}"
script() { # how to run the two checks; prints their combined, marked output
  cat <<EOF
cd "\$1" || exit 1
[ -f "\$HOME/.local/share/swiftly/env.sh" ] && . "\$HOME/.local/share/swiftly/env.sh"
out="\$(timeout $LINT_LIMIT bash scripts/design-lint.sh 2>&1)"; rc=\$?
echo "@@lint \$rc"; printf '%s\n' "\$out"
if [ -n "\$2" ]; then
  if command -v swiftc >/dev/null 2>&1; then
    out="\$(timeout $PARSE_LIMIT bash scripts/parse-app.sh "\$2" 2>&1)"; rc=\$?
    echo "@@parse \$rc"; printf '%s\n' "\$out"
  else
    echo "@@parse skipped"
  fi
fi
EOF
}

# The script goes in on stdin with its two values quoted inside it (wsl.exe joins its arguments into one command line).
if command -v swiftc >/dev/null 2>&1 || ! command -v wsl.exe >/dev/null 2>&1; then
  RESULT="$(printf 'set -- %q %q\n%s\n' "$ROOT" "$PARSE_ARG" "$(script)" | bash -s 2>&1)"
else
  WROOT="$(norm "$ROOT")"
  if [[ $WROOT =~ ^([a-z]):/(.*)$ ]]; then WROOT="/mnt/$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')/${BASH_REMATCH[2]}"; fi
  RESULT="$(printf 'set -- %q %q\n%s\n' "$WROOT" "$PARSE_ARG" "$(script)" | MSYS_NO_PATHCONV=1 wsl.exe bash -s 2>&1 | tr -d '\r')"
  RESULT="${RESULT//"$WROOT/"/}"
fi
RESULT="${RESULT//"$ROOT/"/}"

REPORT=""
section() { printf '%s\n' "$RESULT" | awk -v tag="@@$1" 'index($0, "@@") == 1 { on = (index($0, tag " ") == 1); next } on'; }
status()  { printf '%s\n' "$RESULT" | awk -v tag="@@$1 " 'index($0, tag) == 1 { print substr($0, length(tag) + 1); exit }'; }
LRC="$(status lint)"
case "$LRC" in
  0) ;;
  124) REPORT+="design-lint did not finish within ${LINT_LIMIT} s: no result (not a pass)."$'\n' ;;
  "") REPORT+="design-lint did not run: $(printf '%s' "$RESULT" | head -3)"$'\n' ;;
  *) REPORT+="design-lint failed after editing $REL:"$'\n'"$(section lint | grep -E '\[[a-z-]+\]|violation|error|usage' | head -40)"$'\n' ;;
esac
if [ -n "$PARSE_ARG" ]; then
  PRC="$(status parse)"
  case "$PRC" in
    0|skipped) ;;
    124) REPORT+="swiftc -parse did not finish within ${PARSE_LIMIT} s for $REL: no result (not a pass)."$'\n' ;;
    *) REPORT+="swiftc -parse failed for $REL (syntax):"$'\n'"$(section parse | grep -v '^parse: passed' | head -20)"$'\n' ;;
  esac
fi
[ -z "$REPORT" ] && exit 0
printf '%s' "$REPORT" >&2
exit 2
