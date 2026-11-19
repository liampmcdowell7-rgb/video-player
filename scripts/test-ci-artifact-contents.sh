#!/usr/bin/env bash
# Tests for scripts/ci-artifact-contents.sh (#15 item 1.2) on fake artifact folders made here.
# Prints one line per check and "artifact-contents tests: passed N, failed M" last; exit 1 on any failure.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$HERE/scripts/ci-artifact-contents.sh"
P=0; X=0
check() { if [ "$2" -eq 0 ]; then P=$((P + 1)); echo "ok    $1"; else X=$((X + 1)); echo "FAIL  $1"; echo "$OUT" | sed 's/^/      /'; fi; }
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pic() { mkdir -p "$(dirname "$1")"; printf 'PNG' >"$1"; }

# A good main set.
M="$TMP/screenshots"; pic "$M/01-first-launch.png"; pic "$M/57-movie-detail.png"; pic "$M/64-needs-review-larger-text.png"; echo "# index" >"$M/index.md"
OUT="$(bash "$CHECK" "$M" main 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && has "ARTIFACT OK (main): 3 pictures"; check "a main set (01-79 at the top, index.md) passes" $?
grep -qF "57-movie-detail.png" "$M/CONTENTS.txt" && grep -qF "Pictures: 3." "$M/CONTENTS.txt"; check "CONTENTS.txt lists every file and the count" $?

# A good accessibility set.
A="$TMP/accessibility-screenshots"; pic "$A/text/80-larger-text-home.png"; pic "$A/text/85-bold-text-home.png"; pic "$A/contrast/90-increase-contrast-home.png"
echo "# index" >"$A/text/index.md"; echo "contrast: applied" >"$A/settings-applied.txt"
OUT="$(bash "$CHECK" "$A" accessibility 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && has "ARTIFACT OK (accessibility): 3 pictures"; check "an accessibility set (80+ in setting folders) passes" $?

# The failure from the review: the accessibility pictures uploaded under the main name.
OUT="$(bash "$CHECK" "$A" main 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "is numbered 80; the main set is 01 to 79" && has "no index.md at the top"; check "the accessibility set checked as main fails and says why" $?

# A main folder with one accessibility picture mixed in.
pic "$M/82-larger-text-movies.png"
OUT="$(bash "$CHECK" "$M" main 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "82-larger-text-movies.png is numbered 82"; check "one 80+ picture in the main set fails" $?
rm "$M/82-larger-text-movies.png"

# The main set checked as accessibility.
OUT="$(bash "$CHECK" "$M" accessibility 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "01-first-launch.png is at the top" && has "no picture in text/"; check "the main set checked as accessibility fails" $?

# Main pictures exported but not copied (only index.md left).
E="$TMP/empty"; mkdir -p "$E"; echo "# index" >"$E/index.md"
OUT="$(bash "$CHECK" "$E" main 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "no picture at the top"; check "an index with no pictures fails" $?

# No folder at all.
OUT="$(bash "$CHECK" "$TMP/missing" main 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "no folder"; check "a missing folder fails" $?

# A picture with no number, and an unknown setting folder.
pic "$A/other/91-x.png"; pic "$A/text/home.png"
OUT="$(bash "$CHECK" "$A" accessibility 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "unknown folder 'other'" && has "text/home.png has no NN- number"; check "unknown folder and unnumbered picture fail" $?

echo "artifact-contents tests: passed $P, failed $X"
[ "$X" -eq 0 ]
