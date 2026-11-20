#!/usr/bin/env bash
# Codemagic only (codemagic.yaml, R246 and R266): the build number (CFBundleVersion) is the UTC time yyyyMMddHHmm, the
# same scheme as the GitHub TestFlight workflow, so every upload has a new, rising number.
#   cm-build-number.sh            prints it (12 digits)
#   cm-build-number.sh --check N  exit 0 when N has that form (12 digits, a real month, day, hour and minute)
set -u
if [ "${1:-}" = "--check" ]; then
  n="${2:-}"
  printf '%s' "$n" | grep -Eq '^20[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])([01][0-9]|2[0-3])[0-5][0-9]$'
  exit $?
fi
date -u +%Y%m%d%H%M
