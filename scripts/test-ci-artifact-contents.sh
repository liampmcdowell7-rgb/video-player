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

# #23 E: scripts/ci-not-taken.sh, run when the Compile job failed and the UI-test jobs were skipped.
NT="$TMP/not-taken"
OUT="$(GITHUB_STEP_SUMMARY="$TMP/nt-summary.md" bash "$HERE/scripts/ci-not-taken.sh" "$NT" failure "App/Features/Settings/StorageSettingsView.swift:16: generic parameter 'Content' could not be inferred" 2>&1)"; RC=$?
ok=0; [ "$RC" -eq 0 ] || ok=1
for a in screenshots screenshots-library accessibility-screenshots; do
  head -n 1 "$NT/$a/NOT-TAKEN.txt" | grep -qx 'NOT TAKEN: the app did not compile' || ok=1
  grep -qF "first error: App/Features/Settings/StorageSettingsView.swift:16: generic parameter" "$NT/$a/NOT-TAKEN.txt" || ok=1
  grep -qF 'NOT TAKEN: the app did not compile' "$NT/$a/index.md" || ok=1
  grep -qi 'no picture' "$NT/$a/index.md" && ! grep -qF 'NOT TAKEN' "$NT/$a/index.md" && ok=1
done
check "compile failed: every screenshot artifact says NOT TAKEN and the first error line" $ok
[ ! -e "$NT/accessibility-settings-screenshots" ]; check "compile failed: no artifact for the removed accessibility-settings job" $?
ok=0
for r in embedded-frameworks.txt release-strings.txt process-spawning.txt; do
  grep -q '^NOT CHECKED: the app did not compile' "$NT/device-build-results/$r" || ok=1
  grep -qE '^ok |\(none\)' "$NT/device-build-results/$r" && ok=1
done
check "compile failed: device-build-results says NOT CHECKED, no ok or (none)" $ok
OUT="$(bash "$HERE/scripts/ci-not-taken.sh" "$TMP/nt2" cancelled "" 2>&1)"
head -n 1 "$TMP/nt2/screenshots/NOT-TAKEN.txt" | grep -qF 'NOT TAKEN: the Compile job did not finish (result: cancelled)' \
  && grep -qF 'first error: (no error line was passed on' "$TMP/nt2/screenshots/NOT-TAKEN.txt"
check "compile cancelled, no error line: says so instead of inventing one" $?

# #24 D: a main set made by scripts/ci-ui-tests.sh after a deadline stop with an INCOMPLETE result bundle: only the loose
# PNG files of the tests before the stop, notes/ beside them, index.md saying TEST STOPPED. It must pass the check, and its
# index must list every picture and the counts.
D="$TMP/deadline"; mkdir -p "$D/notes"; pic "$D/02-home-empty.png"; pic "$D/10-add-source-types.png"; pic "$D/11-form-webdav-NOT-REACHED.png"
printf 'The row could not be focused.' > "$D/notes/11-form-webdav-NOT-REACHED.txt"
printf 'test\tresult\tseconds\tpictures\ntest01_FirstLaunchAndEmptyScreens\tpassed\t68\t1\ntest02_AddASource\tstopped by the time budget\t900\t2\ntest03_Settings\tnot started (time budget)\t0\t0\n' > "$TMP/ui-tests.tsv"
python3 "$HERE/scripts/ci-ui-index.py" "$D" "$HERE/scripts/screenshot-plan.tsv" "$TMP/ui-tests.tsv" test01_FirstLaunchAndEmptyScreens test02_AddASource test03_Settings > /dev/null
OUT="$(bash "$CHECK" "$D" main 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && has "ARTIFACT OK (main): 3 pictures" && grep -qF 'TEST STOPPED BY THE TIME BUDGET: pictures up to 10-add-source-types' "$D/index.md" \
  && grep -qF 'Planned: 36. Taken: 2. Missing: 33. Failed (not reached): 1.' "$D/index.md" && grep -qE '^- \[02-home-empty\]\(02-home-empty.png\) [0-9]+ KB' "$D/index.md"
check "deadline stop, incomplete bundle: the loose pictures pass the check; index says TEST STOPPED and counts" $?

# #26: the whole synthetic test key in any artifact file fails the check; the masked form passes.
K="$TMP/keyed"; pic "$K/36-settings-online-lookup-key-set.png"; echo "# index" >"$K/index.md"
mkdir -p "$K/notes"; printf 'StaticText, label: "Key", value: ••••c0de
' >"$K/notes/36-settings-online-lookup-key-set-HIERARCHY.txt"
OUT="$(bash "$CHECK" "$K" main 2>&1)"; RC=$?
[ "$RC" -eq 0 ]; check "a masked key in a note passes" $?
printf 'TextField value: uitestFAKEkeyNOTrealDoNotUse0000c0de
' >"$K/notes/leak.txt"
OUT="$(bash "$CHECK" "$K" main 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "notes/leak.txt contains the whole synthetic test key"; check "the whole synthetic key in any artifact file fails" $?
grep -qF '"uitestFAKEkeyNOTrealDoNotUse0000c0de"' "$HERE/Packages/VideoPlayerCore/Sources/AppLogic/UITestLaunch.swift"
check "the check looks for the same key text the app uses (UITestLaunch.fakeTMDBKey)" $?

echo "artifact-contents tests: passed $P, failed $X"
[ "$X" -eq 0 ]
