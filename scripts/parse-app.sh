#!/usr/bin/env bash
# Syntax check of every Swift file in App/, TopShelf/ and UITests/ with `swiftc -parse`, and (R461) a check that a file which
# names a TYPE of a package module imports that module.
#
# WHAT THIS CATCHES: syntax errors only (unbalanced braces, bad punctuation, misplaced keywords); and the import check below.
# WHAT THIS CANNOT CATCH: anything that needs the SDK: unknown names, wrong argument labels, wrong types,
# availability, actor isolation, view-builder limits. SwiftUI, AVKit, UIKit, TVServices and the rest do not exist on Linux,
# and `-parse` does not look at them. A pass here means "the text is well-formed Swift", never "it compiles".
# THE IMPORT CHECK (R461): the build on 90b028b failed with "cannot find 'AppInfo' in scope": SettingsView.swift named a type of
# module VideoPlayerCore and did not import it, and neither `-parse` nor the Linux tests can see that. For every file, each
# capitalised name that is a top-level public struct, class, enum, protocol, actor or typealias of a module under
# Packages/VideoPlayerCore/Sources must have that module imported in the file (the project has no `@_exported import`, so no
# module reaches a file through another). A name the app declares itself (App/, TopShelf/, UITests/) is skipped, and so is a
# name after a dot. LIMITS: only types, not functions or constants (a lowercase name cannot be told from a local variable
# without the compiler); names inside strings and comments are not read; a type that two modules declare passes when either
# is imported. ScreenChecks is compiled into the UI-test target by path (project.yml), so it is not a module to import.
# Usage: bash scripts/parse-app.sh [FILE.swift ...]   (needs swiftc: WSL/Linux with the toolchain, or the Mac host)
#        bash scripts/parse-app.sh --imports [FILE.swift ...]   (the import check only; no swiftc needed)
# With files, only those are checked (the Claude Code after-edit hook, #28 item 4); without, every file below.
# PARSE_APP_ROOT names another tree with App/, TopShelf/, UITests/ and Packages/ (the script test uses a small one).
# Output: one line per failing file, then `parse: passed N, failed M` (N and M count files; an import failure counts as one).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${PARSE_APP_ROOT:-$HERE}"
IMPORTS_ONLY=0
if [ "${1:-}" = "--imports" ]; then IMPORTS_ONLY=1; shift; fi

list_files() { if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; else find "$ROOT/App" "$ROOT/TopShelf" "$ROOT/UITests" -type f -name '*.swift' 2>/dev/null | LC_ALL=C sort; fi; }

# The awk program of the import check: reads the table (name TAB module) and the app's own type names, then one Swift file.
IMPORT_AWK='
BEGIN {
  while ((getline l < table) > 0) { split(l, p, "\t"); mods[p[1]] = mods[p[1]] " " p[2] " " }
  while ((getline l < localf) > 0) local[l] = 1
}
{
  line = $0
  if (inml) { if (index(line, "\"\"\"") > 0) inml = 0; next }
  if (index(line, "\"\"\"") > 0) { n = gsub(/"""/, "", line); if (n % 2 == 1) inml = 1; next }
  if (inblock) { i = index(line, "*/"); if (i == 0) next; line = substr(line, i + 2); inblock = 0 }
  while ((i = index(line, "/*")) > 0) {
    j = index(substr(line, i + 2), "*/")
    if (j == 0) { line = substr(line, 1, i - 1); inblock = 1; break }
    line = substr(line, 1, i - 1) " " substr(line, i + 2 + j + 1)
  }
  gsub(/"([^"\\]|\\.)*"/, "\"\"", line)
  sub(/\/\/.*$/, "", line)
  if (match(line, /^[ \t]*(@testable +)?import +/)) {
    rest = substr(line, RLENGTH + 1); sub(/^(struct|class|enum|protocol|func|typealias) +/, "", rest); sub(/[^A-Za-z0-9_].*$/, "", rest)
    imp[rest] = 1; next
  }
  s = line
  while (match(s, /[A-Za-z_][A-Za-z0-9_]*/)) {
    tok = substr(s, RSTART, RLENGTH); before = (RSTART > 1) ? substr(s, RSTART - 1, 1) : ""; s = substr(s, RSTART + RLENGTH)
    if (before != "." && (tok in mods) && !(tok in local)) seen[tok] = 1
  }
}
END {
  for (t in seen) {
    n = split(mods[t], ms, " "); ok = 0; list = ""
    for (k = 1; k <= n; k++) { if (ms[k] in imp) ok = 1; list = list (list == "" ? "" : "/") ms[k] }
    if (!ok) print "IMPORT FAIL " file ": " t " (module " list ") is used without `import " ms[1] "`"
  }
}'

# Prints one line per missing import; returns the number of files with a miss (a failure of the check itself counts as one).
check_imports() {
  local sources="$ROOT/Packages/VideoPlayerCore/Sources" tmp d m f bad=0 out
  [ -d "$sources" ] || { echo "IMPORT FAIL: $sources does not exist (the check cannot run)"; return 1; }
  tmp="$(mktemp -d)"
  for d in "$sources"/*/; do
    m="$(basename "$d")"; [ "$m" = "ScreenChecks" ] && continue
    grep -rhoE '^(@[A-Za-z]+(\([^)]*\))? +)*(public|open) +((final|indirect) +)*(struct|class|enum|protocol|actor|typealias) +[A-Za-z_][A-Za-z0-9_]*' --include='*.swift' "$d" 2>/dev/null \
      | awk -v m="$m" '{ print $NF "\t" m }'
  done >"$tmp/table"
  if [ ! -s "$tmp/table" ]; then echo "IMPORT FAIL: no package type was found under $sources (the check cannot run)"; rm -rf "$tmp"; return 1; fi
  grep -rhoE '(struct|class|enum|protocol|actor|typealias) +[A-Za-z_][A-Za-z0-9_]*' --include='*.swift' "$ROOT/App" "$ROOT/TopShelf" "$ROOT/UITests" 2>/dev/null \
    | awk '{ print $2 }' | sort -u >"$tmp/local"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if ! out="$(awk -v table="$tmp/table" -v localf="$tmp/local" -v file="$f" "$IMPORT_AWK" "$f" 2>&1)"; then
      bad=$((bad + 1)); echo "IMPORT FAIL $f: the check itself failed: $out"; continue
    fi
    if [ -n "$out" ]; then bad=$((bad + 1)); printf '%s\n' "$out" | LC_ALL=C sort; fi
  done < <(list_files "$@")
  rm -rf "$tmp"
  return "$bad"
}

check_imports "$@"; import_fail=$?
if [ "$IMPORTS_ONLY" -eq 1 ]; then
  echo "imports: $import_fail file(s) with a missing import (types of package modules only; see the header of this script)"
  [ "$import_fail" -eq 0 ]; exit
fi
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
if ! command -v swiftc >/dev/null 2>&1; then echo "parse: swiftc not found"; echo "parse: passed 0, failed 0 (NOT RUN: no swiftc)"; exit 2; fi
pass=0; fail=0
while IFS= read -r f; do
  if out="$(swiftc -parse -swift-version 5 "$f" 2>&1)"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $f"; echo "$out" | head -8; fi
done < <(list_files "$@")
fail=$((fail + import_fail))
echo "parse: passed $pass, failed $fail (syntax and the import check of package types only; see the header of this script)"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
