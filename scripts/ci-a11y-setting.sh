#!/usr/bin/env bash
# CI only (compile-check.yml, job "screenshots"). Turns one accessibility setting on or off in the booted simulator with
# `xcrun simctl ui`, for the rule 17 screenshots (docs/DESIGN_REFERENCES.md).
#
# Usage: ci-a11y-setting.sh UDID WORD on|off
#   WORD is a word that names the setting: contrast, transparency or motion.
#
# No option name is assumed: `xcrun simctl ui` documents its options only in its own help (no Apple web page lists them),
# so the script reads `xcrun simctl help ui` on the runner and uses the option whose name contains WORD
# (for example "increase_contrast"). Whatever happens is printed:
#   APPLIED <option> <value>        the command succeeded
#   NOT APPLIED <reason>            no such option in this Xcode's simctl, or the command failed
# Exit status: 0 applied, 3 not applied (the job then skips that setting's screenshots and says so).
set -uo pipefail
udid="${1:?UDID}"; word="${2:?word}"; state="${3:?on|off}"
help="$(xcrun simctl help ui 2>&1)"
# Option names are lower-case words joined by "_" (prose in the help may use the same word on its own, so a name with an
# underscore is preferred; plain-word matches are the fallback). BSD grep on the runner: no \b, plain classes only.
tokens="$(printf '%s\n' "$help" | grep -oE '[a-z_]*'"$word"'[a-z_]*' | sort -u)"
option="$(printf '%s\n' "$tokens" | grep '_' | head -n 1)"
[ -n "$option" ] || option="$(printf '%s\n' "$tokens" | head -n 1)"
if [ -z "$option" ]; then
  echo "NOT APPLIED $word: \`xcrun simctl help ui\` lists no option containing \"$word\" in this Xcode."
  exit 3
fi
# The value words come from the same help text: the first of enabled/disabled, on/off, yes/no that it mentions.
if [ "$state" = on ]; then candidates="enabled on yes true"; else candidates="disabled off no false"; fi
value=""
for v in $candidates; do
  if printf '%s\n' "$help" | grep -qw "$v"; then value="$v"; break; fi
done
if [ -z "$value" ]; then
  echo "NOT APPLIED $option: the help names no value for \"$state\"."
  exit 3
fi
if out="$(xcrun simctl ui "$udid" "$option" "$value" 2>&1)"; then
  echo "APPLIED $option $value"
  # Read the value back where simctl can (same command without a value prints the current one, if supported).
  xcrun simctl ui "$udid" "$option" 2>&1 | sed 's/^/  now: /' || true
  exit 0
fi
echo "NOT APPLIED $option $value: simctl said: $out"
exit 3
