#!/usr/bin/env bash
# Tests for scripts/ci-ambiguous-types.sh (#15 item 1.1) on a fake SDK and a fake package (scripts/ci-ambiguous-fixtures).
# Prints one line per check and "ambiguous-types tests: passed N, failed M" last; exit 1 on any failure.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="$HERE/scripts/ci-ambiguous-fixtures"
P=0; X=0
check() { if [ "$2" -eq 0 ]; then P=$((P + 1)); echo "ok    $1"; else X=$((X + 1)); echo "FAIL  $1"; echo "$OUT" | sed 's/^/      /'; fi; }
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }

OUT="$(bash "$HERE/scripts/ci-ambiguous-types.sh" "$F/SDK" "$F/Package" 2>&1)"; RC=$?
[ "$RC" -eq 1 ]; check "a bare use of a name Apple also declares fails the check (exit 1)" $?
has "AMBIGUOUS: BadTests uses 'LibraryItem' bare"; check "Swift interface type (LibraryItem) used bare is named with its target" $?
has "AMBIGUOUS: BadTests uses 'SharedProto' bare"; check "an attribute line before the declaration (@available) is still read" $?
! has "GoodTests"; check "a target with 'typealias LibraryItem = Mod.LibraryItem' and only qualified uses passes" $?
! has "CommentTests"; check "a name only in a comment, and a name Apple declares only nested, are not reported" $?
! has "'SharedClass'"; check "an Objective-C class used only qualified (Mod.SharedClass) is not reported" $?
has "3 also declared in the SDK"; check "the summary line counts the collisions" $?

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp -R "$F/Package" "$TMP/Package"; rm -rf "$TMP/Package/Tests/BadTests"
OUT="$(bash "$HERE/scripts/ci-ambiguous-types.sh" "$F/SDK" "$TMP/Package" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && has "no ambiguous use in a test target"; check "without the bad target: exit 0" $?

mkdir -p "$TMP/Package/Tests/ObjCTests"; printf '@testable import Mod\nlet c = SharedClass()\n' >"$TMP/Package/Tests/ObjCTests/C.swift"
OUT="$(bash "$HERE/scripts/ci-ambiguous-types.sh" "$F/SDK" "$TMP/Package" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "AMBIGUOUS: ObjCTests uses 'SharedClass' bare"; check "an Objective-C @interface name used bare is reported" $?

# The real package against the fake SDK: both test targets that use LibraryItem have the typealias (TestSupport.swift,
# LibrarySupport.swift), so nothing is reported.
OUT="$(bash "$HERE/scripts/ci-ambiguous-types.sh" "$F/SDK" "$HERE/Packages/VideoPlayerCore" 2>&1)"; RC=$?
[ "$RC" -eq 0 ]; check "the real test targets: LibraryItem is covered by their typealias" $?

echo "ambiguous-types tests: passed $P, failed $X"
[ "$X" -eq 0 ]
