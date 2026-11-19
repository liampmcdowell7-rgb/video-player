#!/usr/bin/env bash
# CI only (compile-check.yml, job "accessibility-settings-screenshots").
# Usage: ci-a11y-run.sh WORD TEST   (WORD: contrast, transparency or motion; TEST: the ScreenshotTests method)
# Turns the setting on in the simulator ($SIM_UDID), runs that one UI test into $OUT/A11y-WORD.xcresult, turns it off.
# When the setting cannot be applied, nothing runs and a11y-settings.txt says NOT APPLIED (no screenshot is ever saved
# under the name of a setting that was not on).
set -uo pipefail
word="${1:?word}"; test="${2:?test}"
here="$(dirname "$0")"
bash "$here/ci-stage.sh" "Accessibility: $word"
[ -f "$OUT/simctl-ui-help.txt" ] || xcrun simctl help ui > "$OUT/simctl-ui-help.txt" 2>&1 || true
if ! bash "$here/ci-a11y-setting.sh" "$SIM_UDID" "$word" on 2>&1 | tee -a "$OUT/a11y-settings.txt"; then
  echo "Skipped: $word could not be turned on."
  exit 0
fi
status=0
# A simulator retry (ci-sim.sh) erases the simulator, which turns the setting off again: the hook turns it back on.
export SIM_RETRY_HOOK="bash '$here/ci-a11y-setting.sh' '$SIM_UDID' '$word' on 2>&1 | tee -a '$OUT/a11y-settings.txt'"
bash "$here/ci-sim.sh" test "$OUT/test.log" -- xcodebuild test-without-building \
  -project VideoPlayer.xcodeproj -scheme VideoPlayerUITests -configuration Debug \
  -destination "platform=tvOS Simulator,id=$SIM_UDID" \
  -clonedSourcePackagesDirPath build/SourcePackages -derivedDataPath build/DerivedData \
  -resultBundlePath "$OUT/A11y-$word.xcresult" -parallel-testing-enabled NO \
  -only-testing:"VideoPlayerUITests/ScreenshotTests/$test" || status=1
bash "$here/ci-a11y-setting.sh" "$SIM_UDID" "$word" off 2>&1 | tee -a "$OUT/a11y-settings.txt" || true
exit $status
