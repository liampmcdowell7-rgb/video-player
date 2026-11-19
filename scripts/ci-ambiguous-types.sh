#!/usr/bin/env bash
# Finds type names that are ambiguous in a test target on Apple platforms (#15 item 1.1).
#
#   bash scripts/ci-ambiguous-types.sh SDK_DIR [PACKAGE_DIR]
#
# Why: `LibraryItem` is a public type of the LibraryIndex module and also of Apple's DeveloperToolsSupport
# (https://developer.apple.com/documentation/developertoolssupport/libraryitem). On Linux the second one does not exist, so
# the tests build; in the tvOS package-test build the bare name was ambiguous (fourth CI run, TestSupport.swift:286). The
# fix is a `typealias Name = Module.Name` in the test target: a declaration in the target's own module wins over imports.
#
# How: our public type names come from PACKAGE_DIR/Sources; Apple's come from the SDK itself (Swift interfaces
# `*.swiftinterface` and Objective-C `@interface` headers under SDK_DIR), so no list is kept by hand. A name in both that a
# test target (PACKAGE_DIR/Tests/<Target>) uses as a bare word, with no `typealias Name =` in that target, is reported.
# In CI SDK_DIR is the tvOS simulator SDK (`xcrun --sdk appletvsimulator --show-sdk-path`); this runs in seconds and
# before the long package-test build, so the failure is named directly. Self-test on fake trees: scripts/test-ci-ambiguous-types.sh.
#
# Prints one line per problem and a summary; exit 1 when any test target has an ambiguous bare name.
set -u
SDK="${1:?usage: ci-ambiguous-types.sh SDK_DIR [PACKAGE_DIR]}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="${2:-$HERE/Packages/VideoPlayerCore}"
[ -d "$SDK" ] || { echo "ambiguous-types: no SDK folder $SDK" >&2; exit 2; }
[ -d "$PKG/Sources" ] && [ -d "$PKG/Tests" ] || { echo "ambiguous-types: no Sources/Tests in $PKG" >&2; exit 2; }

DECL='(struct|enum|class|protocol|actor|typealias)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*'
OURS="$(mktemp)"; APPLE="$(mktemp)"; trap 'rm -f "$OURS" "$APPLE"' EXIT

# Our public and open types (any nesting; a nested name only matters if a test uses it bare, which the next steps check).
grep -rhoE --include='*.swift' "^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*(public|open)[[:space:]]+((final|indirect)[[:space:]]+)*$DECL" "$PKG/Sources" 2>/dev/null \
  | awk '{print $NF}' | sort -u >"$OURS"

# Apple's top-level public types: in a .swiftinterface a top-level declaration starts at column 0; Objective-C classes and
# protocols are `@interface Name` / `@protocol Name` in the headers. Each line: "Name<TAB>file".
{
  grep -rHoE --include='*.swiftinterface' "^(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*(public|open)[[:space:]]+((final|indirect)[[:space:]]+)*$DECL" "$SDK" 2>/dev/null \
    | sed -E 's/^([^:]*):.*[[:space:]]([A-Za-z_][A-Za-z0-9_]*)$/\2\t\1/'
  grep -rHoE --include='*.h' '^@(interface|protocol)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$SDK" 2>/dev/null \
    | sed -E 's/^([^:]*):@(interface|protocol)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)$/\3\t\1/'
} | sort -u -t "$(printf '\t')" -k1,1 >"$APPLE"

bad=0; checked=0
while IFS= read -r name; do
  where="$(awk -F '\t' -v n="$name" '$1 == n { print $2; exit }' "$APPLE")"
  [ -n "$where" ] || continue
  checked=$((checked + 1))
  for dir in "$PKG"/Tests/*/; do
    target="$(basename "$dir")"
    # A bare use: the whole word, not after a dot (Module.Name or Type.Name), outside line comments.
    uses="$(grep -rnwE --include='*.swift' "$name" "$dir" 2>/dev/null | grep -vE "^[^:]*:[0-9]+:[[:space:]]*//" | grep -E "(^|[^.A-Za-z0-9_])$name([^A-Za-z0-9_]|$)" | grep -vE "typealias[[:space:]]+$name[[:space:]]*=" | head -n 1)"
    [ -n "$uses" ] || continue
    if grep -rqE --include='*.swift' "^[[:space:]]*(public[[:space:]]+|internal[[:space:]]+)?typealias[[:space:]]+$name[[:space:]]*=" "$dir"; then continue; fi
    echo "AMBIGUOUS: $target uses '$name' bare (${uses#"$PKG"/}); Apple also declares it (${where#"$SDK"/})."
    echo "           Add 'typealias $name = <OurModule>.$name' to a file of $target."
    bad=1
  done
done <"$OURS"

echo "ambiguous-types: $(wc -l <"$OURS" | tr -d ' ') public package types, $checked also declared in the SDK, $( [ "$bad" -eq 0 ] && echo "no ambiguous use in a test target" || echo "AMBIGUOUS USES FOUND")"
exit "$bad"
