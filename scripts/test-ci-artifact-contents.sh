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

# A good accessibility set (text/ only, two- and three-digit numbers).
A="$TMP/accessibility-screenshots"; pic "$A/text/80-larger-text-home.png"; pic "$A/text/85-bold-text-home.png"; pic "$A/text/102-default-home.png"
echo "# index" >"$A/text/index.md"
OUT="$(bash "$CHECK" "$A" accessibility 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && has "ARTIFACT OK (accessibility): 3 pictures"; check "an accessibility set (80+ in text/, NN or NNN) passes" $?

# A good accessibility-settings set, and one where no setting could be applied (no pictures).
S="$TMP/accessibility-settings-screenshots"; pic "$S/contrast/113-increase-contrast-home.png"; pic "$S/motion/117-reduce-motion-movie-detail.png"
echo "contrast: applied" >"$S/settings-applied.txt"
OUT="$(bash "$CHECK" "$S" accessibility-settings 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && has "ARTIFACT OK (accessibility-settings): 2 pictures"; check "an accessibility-settings set (113+ in setting folders) passes" $?
N="$TMP/settings-none"; mkdir -p "$N"; echo "contrast: NOT APPLIED" >"$N/settings-applied.txt"
OUT="$(bash "$CHECK" "$N" accessibility-settings 2>&1)"; RC=$?
[ "$RC" -eq 0 ]; check "no setting applied (no pictures, settings-applied.txt says so) passes" $?
rm "$N/settings-applied.txt"
OUT="$(bash "$CHECK" "$N" accessibility-settings 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "no settings-applied.txt"; check "accessibility-settings without settings-applied.txt fails" $?

# Each accessibility artifact checked as the other one.
OUT="$(bash "$CHECK" "$S" accessibility 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "belongs to the other accessibility artifact" && has "no picture in text/"; check "the settings set checked as accessibility fails" $?
OUT="$(bash "$CHECK" "$A" accessibility-settings 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "text/80-larger-text-home.png is in text/"; check "the text set checked as accessibility-settings fails" $?

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
pic "$A/other/91-x.png"; pic "$A/text/home.png"; pic "$A/text/7-x.png"
OUT="$(bash "$CHECK" "$A" accessibility 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "unknown folder 'other'" && has "text/home.png has no NN- number" && has "text/7-x.png has no NN- number"; check "unknown folder and unnumbered or one-digit picture fail" $?

echo "artifact-contents tests: passed $P, failed $X"
[ "$X" -eq 0 ]
