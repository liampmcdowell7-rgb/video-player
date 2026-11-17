#!/usr/bin/env bash
# Tests for scripts/design-lint.sh. Pure bash (no Swift). For every rule it runs the fixtures in
# scripts/design-lint-fixtures/<rule>/ : every fail*.* must be reported under that rule, every pass*.* must be clean,
# every allow*.* (design-lint:allow with a reason, same line or line above) must be clean. Plus edge cases below.
# Prints `Test Case 'design-lint NAME' passed|failed` lines (the format scripts/test-all.sh counts) and a summary.
# Usage: bash scripts/test-design-lint.sh        Exit 0 only if every test passed.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$HERE/scripts/design-lint.sh"
FX="$HERE/scripts/design-lint-fixtures"
export DESIGN_LINT_TARGET=27.0
# The names rules read a small fixture allowlist, so the fixtures do not depend on the real docs/NAMES.md.
export DESIGN_LINT_NAMES="$FX/names-fixture.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/design-lint-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "Test Case 'design-lint $1' passed"; PASS=$((PASS + 1)); }
bad() { echo "Test Case 'design-lint $1' failed: $2"; FAIL=$((FAIL + 1)); }
run() { OUT="$(bash "$LINT" "$@" 2>&1)"; RC=$?; }

# 1. Every rule named in the lint header has a fixture directory (so a new rule cannot ship untested).
RULES="$(sed -n 's/^#   \([a-z][a-z-]*\)  .*/\1/p' "$LINT" | sort -u)"
[ -n "$RULES" ] && ok "rule list parsed ($(echo "$RULES" | wc -l | tr -d ' ') rules)" || bad "rule list parsed" "no rules found in header"
for r in $RULES; do
  if [ -d "$FX/$r" ]; then ok "fixture dir exists: $r"; else bad "fixture dir exists: $r" "missing $FX/$r"; fi
done

# 2. Fixtures.
for d in "$FX"/*/; do
  r="$(basename "$d")"
  nfail=0; npass=0; nallow=0
  for f in "$d"fail*; do
    [ -e "$f" ] || continue; nfail=$((nfail + 1))
    run "$f"
    if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "\[$r\]"; then ok "$r: $(basename "$f") is reported"; else bad "$r: $(basename "$f") is reported" "rc=$RC out=$OUT"; fi
  done
  for f in "$d"pass*; do
    [ -e "$f" ] || continue; npass=$((npass + 1))
    run "$f"
    if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q '^design-lint: clean'; then ok "$r: $(basename "$f") is clean"; else bad "$r: $(basename "$f") is clean" "rc=$RC out=$OUT"; fi
  done
  for f in "$d"allow*; do
    [ -e "$f" ] || continue; nallow=$((nallow + 1))
    run "$f"
    if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q ', 1 allowed by design-lint:allow'; then ok "$r: $(basename "$f") is allowed with a reason"; else bad "$r: $(basename "$f") is allowed with a reason" "rc=$RC out=$OUT"; fi
  done
  [ "$nfail" -ge 1 ] && ok "$r: has a failing fixture" || bad "$r: has a failing fixture" "none"
  [ "$npass" -ge 1 ] && ok "$r: has a passing fixture" || bad "$r: has a passing fixture" "none"
  # brand-logo takes no allow marker (its fail-allow-*.swift fixtures prove a marker does not let a logo in).
  [ "$r" = allow-without-reason ] || [ "$r" = brand-logo ] || { [ "$nallow" -ge 2 ] && ok "$r: has same-line and line-above allow fixtures" || bad "$r: has same-line and line-above allow fixtures" "found $nallow"; }
done

# 3. Edge cases.
run "$TMP/does-not-exist.swift"
[ "$RC" -eq 2 ] && ok "missing path exits 2" || bad "missing path exits 2" "rc=$RC"

printf '\xEF\xBB\xBFimport SwiftUI\r\nstruct V: View { var body: some View { Text("x").padding(40) } }\r\n' >"$TMP/crlf-bom-bad.swift"
run "$TMP/crlf-bom-bad.swift"
{ [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q ':2: \[hard-padding\]'; } && ok "CRLF + BOM file: violation found on the right line" || bad "CRLF + BOM file: violation found on the right line" "rc=$RC out=$OUT"
printf '\xEF\xBB\xBFimport SwiftUI\r\nstruct V: View { var body: some View { Text("x").padding() } }\r\n' >"$TMP/crlf-bom-ok.swift"
run "$TMP/crlf-bom-ok.swift"
[ "$RC" -eq 0 ] && ok "CRLF + BOM file: clean file is clean" || bad "CRLF + BOM file: clean file is clean" "rc=$RC out=$OUT"

cat >"$TMP/mixed.swift" <<'SW'
import SwiftUI
struct A: View { var body: some View { Text("a").padding(40) } } // design-lint:allow fixture: this one is allowed
struct B: View { var body: some View { Text("b").padding(50) } }
SW
run "$TMP/mixed.swift"
{ [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q ':3: \[hard-padding\]' && ! printf '%s\n' "$OUT" | grep -q ':2: \['; } && ok "an allow suppresses only its own line" || bad "an allow suppresses only its own line" "rc=$RC out=$OUT"

cat >"$TMP/text-only.swift" <<'SW'
import SwiftUI
// Do not write .padding(40) or Color(red: 0, green: 0, blue: 0) or .onTapGesture in comments.
struct V: View { var body: some View { Text("Color(red: 0) .padding(40)") } }
SW
run "$TMP/text-only.swift"
[ "$RC" -eq 0 ] && ok "code patterns inside comments and strings are not code" || bad "code patterns inside comments and strings are not code" "rc=$RC out=$OUT"

cat >"$TMP/block-comment.swift" <<'SW'
/*
 Netflix and Foozle are named here on purpose in a block comment.
*/
let a = 1
SW
run "$TMP/block-comment.swift"
[ "$RC" -eq 0 ] && ok "names: comment text is not checked" || bad "names: comment text is not checked" "rc=$RC out=$OUT"

cat >"$TMP/triple.swift" <<'SW'
let s = """
    Stream everything from your Foozle server
    """
SW
run "$TMP/triple.swift"
{ [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q '\[unknown-name\] .Foozle.'; } && ok "names: triple-quoted string text is checked" || bad "names: triple-quoted string text is checked" "rc=$RC out=$OUT"

printf 'let s = "Plays Dolby Vision from your Foozle server"\n' >"$TMP/one-hit.swift"
run "$TMP/one-hit.swift"
{ [ "$RC" -eq 1 ] && [ "$(printf '%s\n' "$OUT" | grep -c '\[unknown-name\]')" -eq 1 ] && ! printf '%s\n' "$OUT" | grep -q "'Dolby"; } && ok "names: an allowlisted name is blanked, the unknown one is reported once" || bad "names: an allowlisted name is blanked, the unknown one is reported once" "rc=$RC out=$OUT"

DESIGN_LINT_NAMES="$TMP/no-such-names.md" run "$TMP/one-hit.swift"
[ "$RC" -eq 2 ] && ok "names: a missing allowlist file exits 2" || bad "names: a missing allowlist file exits 2" "rc=$RC out=$OUT"

printf 'import SwiftUI\nstruct V: View { var body: some View { Text("x").padding(40) } }\n' >"$TMP/names-only.swift"
run --names-only "$TMP/names-only.swift"
[ "$RC" -eq 0 ] && ok "--names-only skips the layout rules" || bad "--names-only skips the layout rules" "rc=$RC out=$OUT"

cat >"$TMP/escape.swift" <<'SW'
let s = "quote \" then .padding(40) is still inside the string"
let t = 1
SW
run "$TMP/escape.swift"
[ "$RC" -eq 0 ] && ok "escaped quote does not end the string early" || bad "escaped quote does not end the string early" "rc=$RC out=$OUT"

run --list-allows "$FX/color-literal"
{ [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c 'design-lint:allow')" -eq 2 ]; } && ok "--list-allows lists both exceptions" || bad "--list-allows lists both exceptions" "rc=$RC out=$OUT"

# availability: the target decides.
printf 'func f() { if #available(tvOS 27.3, *) { } }\n' >"$TMP/avail.swift"
DESIGN_LINT_TARGET=27.3 run "$TMP/avail.swift"
[ "$RC" -eq 1 ] && ok "availability: 27.3 is pointless when the target is 27.3" || bad "availability: 27.3 is pointless when the target is 27.3" "rc=$RC out=$OUT"
DESIGN_LINT_TARGET=27.0 run "$TMP/avail.swift"
[ "$RC" -eq 0 ] && ok "availability: 27.3 is needed when the target is 27.0" || bad "availability: 27.3 is needed when the target is 27.0" "rc=$RC out=$OUT"

# default scope (App/ next to scripts/) in a copy of the tree.
mkdir -p "$TMP/tree/scripts" "$TMP/tree/App"
cp "$LINT" "$TMP/tree/scripts/"
printf 'import SwiftUI\nstruct V: View { var body: some View { Text("x").padding(40) } }\n' >"$TMP/tree/App/V.swift"
OUT="$(bash "$TMP/tree/scripts/design-lint.sh" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && ok "default scope is App/" || bad "default scope is App/" "rc=$RC out=$OUT"
printf 'import SwiftUI\nstruct V: View { var body: some View { Text("x").padding() } }\n' >"$TMP/tree/App/V.swift"
OUT="$(bash "$TMP/tree/scripts/design-lint.sh" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "default scope: clean App/ passes" || bad "default scope: clean App/ passes" "rc=$RC out=$OUT"

echo "design-lint tests: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
