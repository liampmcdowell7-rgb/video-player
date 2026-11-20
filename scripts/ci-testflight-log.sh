#!/usr/bin/env bash
# CI only (testflight.yml). Prints a short, redacted view of one xcodebuild log, because the full log stays on the runner
# and is deleted (R249): on a public repository the Actions log is readable by anyone, and xcodebuild names the signing
# certificate's holder ("Apple Distribution: <name> (<team>)"). GitHub already hides the secret values themselves.
#   ci-testflight-log.sh LOG TITLE EXIT_CODE
# Exit code 0: the result lines (** ... SUCCEEDED **, upload lines) and the number of warnings.
# Otherwise: every error line with the 20 lines before it (at most 400 lines), then the last 30 lines; the first 10 error
# lines also go to the step summary. Everything printed passes through redact(). Uses only POSIX ERE (BSD and GNU sed).
# Never fails by itself: the caller exits with the xcodebuild exit code.
log="${1:?log file}"; title="${2:-xcodebuild}"; rc="${3:-0}"

redact() {
  sed -E \
    -e 's/((Apple|iPhone|iOS|Mac|tvOS) (Distribution|Development|Developer)|Developer ID Application|Apple Distribution Certificate): [^"()]*(\([^)]*\))?/\1: [redacted]/g' \
    -e 's/(Signing Identity|Signing identity|signing identity|Provisioning Profile|Provisioning profile|provisioning profile|Signing Certificate|Signing certificate)( *[:=] *).*/\1\2[redacted]/' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+/[e-mail redacted]/g'
}

if [ ! -f "$log" ]; then
  echo "::error::$title: no log was written ($log)."
  exit 0
fi

errpat='error:|\*\* [A-Z ]+ FAILED \*\*|Error Domain='
warnings="$(grep -c 'warning:' "$log" 2>/dev/null || true)"

if [ "$rc" -eq 0 ]; then
  echo "== $title: succeeded (exit 0). Warnings: ${warnings:-0}."
  grep -E '\*\* [A-Z ]+ SUCCEEDED \*\*|[Uu]pload(ed)? (succeeded|successful|complete)|EXPORT SUCCEEDED|Progress [0-9]+%: Upload' "$log" | tail -n 20 | redact
  exit 0
fi

echo "== $title: FAILED (exit $rc). Warnings: ${warnings:-0}. Error lines with the 20 lines before each (redacted):"
if grep -qE "$errpat" "$log"; then
  grep -B 20 -E "$errpat" "$log" | head -n 400 | redact
else
  echo "(no line with 'error:' in the log)"
fi
echo "== $title: last 30 lines of the log (redacted):"
tail -n 30 "$log" | redact
first="$(grep -E "$errpat" "$log" | head -n 10 | redact)"
echo "::error::$title failed (exit $rc). First error: $(printf '%s\n' "$first" | head -n 1 | cut -c1-300)"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## $title failed (exit $rc)"
    echo
    echo '```'
    printf '%s\n' "${first:-no line with error: in the log}"
    echo '```'
    echo
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit 0
