#!/usr/bin/env bash
# CI only (compile-check.yml, job "not-taken", #23 E). The screenshot jobs and the device build need the Compile job
# (`needs: compile`); when it did not succeed they are skipped and upload nothing. This job runs instead (ubuntu-latest,
# a few seconds) and writes, under the SAME artifact names, folders that say why there are no pictures:
#   screenshots/, screenshots-library/, accessibility-screenshots/, accessibility-settings-screenshots/
#       NOT-TAKEN.txt and index.md: "NOT TAKEN: the app did not compile" and the first error line
#   device-build-results/   every inspection report saying "NOT CHECKED: ..." (scripts/ci-inspect-lib.sh)
# Usage: ci-not-taken.sh ROOT COMPILE_RESULT [FIRST_ERROR]
#   COMPILE_RESULT is needs.compile.result: failure, cancelled or skipped (success never reaches this script).
set -uo pipefail
root="${1:?output folder}"; result="${2:?compile job result}"; first="${3:-}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/ci-inspect-lib.sh"
if [ "$result" = "failure" ]; then
  line="NOT TAKEN: the app did not compile"
else
  line="NOT TAKEN: the Compile job did not finish (result: $result)"
fi
[ -n "$first" ] || first="(no error line was passed on; see the compile-check-results artifact, errors.txt)"
for a in screenshots screenshots-library accessibility-screenshots accessibility-settings-screenshots; do
  mkdir -p "$root/$a"
  {
    echo "$line"
    echo "first error: $first"
    echo "The UI-test jobs wait for the Compile job (needs: compile) and did not run. No picture exists for this run."
  } > "$root/$a/NOT-TAKEN.txt"
  { echo "# $a"; echo; sed 's/$/  /' "$root/$a/NOT-TAKEN.txt"; } > "$root/$a/index.md"
done
reason="the app did not compile (Compile job: $result); the device build did not run"
vp_inspect_not_checked "$root/device-build-results" "$reason" "$first" > /dev/null
{
  echo "## $line"
  echo
  echo "first error: \`$first\`"
  echo
  echo "Screenshots (parts 1 and 2), accessibility screenshots and the device build were not run (needs: compile)."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "$line"
echo "first error: $first"
