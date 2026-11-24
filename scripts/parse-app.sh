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
#        bash scripts/parse-app.sh --debug [FILE.swift ...]     (the Debug-only type check only, R462; no swiftc needed)
# With files, only those are checked (the Claude Code after-edit hook, #28 item 4); without, every file below.
# PARSE_APP_ROOT names another tree with App/, TopShelf/, UITests/ and Packages/ (the script test uses a small one).
# Output: one line per failing file, then `parse: passed N, failed M` (N and M count files; an import failure counts as one, a use of a Debug-only type as one each).
# THE DEBUG CHECK (R462, above check_debug): a type declared only inside `#if DEBUG` must not be named outside such a block.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${PARSE_APP_ROOT:-$HERE}"
IMPORTS_ONLY=0; DEBUG_ONLY=0
if [ "${1:-}" = "--imports" ]; then IMPORTS_ONLY=1; shift; elif [ "${1:-}" = "--debug" ]; then DEBUG_ONLY=1; shift; fi

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

# THE DEBUG CHECK (R462): the Release archive of 90b028b failed with "cannot find 'UITestMode' in scope": BackdropView.swift used
# a type that is declared inside `#if DEBUG`. Pass 1 reads App/, TopShelf/ and Packages/VideoPlayerCore/Sources and collects
# every type (struct, class, enum, protocol, actor, typealias) declared DIRECTLY inside a `#if DEBUG` block (not in its
# `#else` branch) and not declared anywhere outside one. Pass 2 reports every line outside a DEBUG-only region that names such a
# type. Comments, strings and a name after a dot are not read. CANNOT CATCH: functions, properties and constants that only
# exist in Debug (a lowercase name cannot be told from a local one without the compiler), members added to a normal type
# inside `#if DEBUG`, a `#if` with a more complex condition (treated as not Debug-only), a Debug-only type used through
# a typealias or an inferred type, anything in Vendor/ or in tests, and every other Release-only difference (optimisation,
# `-O` exclusivity or inlining errors, `assert` side effects). Only a Release archive proves a Release build.
DEBUG_AWK='
function strip(line,   i, j, out) {
  out = ""
  if (inml) { if (index(line, "\"\"\"") > 0) inml = 0; return "" }
  if (index(line, "\"\"\"") > 0) { n = gsub(/"""/, "", line); if (n % 2 == 1) inml = 1; return "" }
  if (inblock) { i = index(line, "*/"); if (i == 0) return ""; line = substr(line, i + 2); inblock = 0 }
  while ((i = index(line, "/*")) > 0) {
    j = index(substr(line, i + 2), "*/")
    if (j == 0) { line = substr(line, 1, i - 1); inblock = 1; break }
    line = substr(line, 1, i - 1) " " substr(line, i + 2 + j + 1)
  }
  gsub(/"([^"\\]|\\.)*"/, "\"\"", line)
  sub(/\/\/.*$/, "", line)
  return line
}
function isdbg(   k) { for (k = 1; k <= sp; k++) if (st[k] == 1) return 1; return 0 }
BEGIN {
  DECL = "^[ \t]*((@[A-Za-z]+(\\([^)]*\\))?|public|open|internal|private|fileprivate|final|indirect|static|nonisolated)[ \t]+)*(struct|class|enum|protocol|actor|typealias)[ \t]+[A-Za-z_][A-Za-z0-9_]*"
  if (pass == 2) while ((getline l < names) > 0) { split(l, p, "\t"); dname[p[1]] = p[2] }
}
FNR == 1 { sp = 0; bd = 0; inml = 0; inblock = 0 }
{
  line = strip($0); t = line; gsub(/^[ \t]+|[ \t]+$/, "", t)
  if (t ~ /^#if[ \t]/ || t ~ /^#if$/) {
    sp++; bd0[sp] = bd
    if (t ~ /^#if[ \t]+DEBUG$/) st[sp] = 1; else st[sp] = 0
    isneg[sp] = (t ~ /^#if[ \t]+!DEBUG$/) ? 1 : 0
    next
  }
  if (t ~ /^#else/ && sp > 0) { if (st[sp] == 1) st[sp] = 0; else if (isneg[sp]) st[sp] = 1; next }
  if (t ~ /^#elseif/ && sp > 0) { st[sp] = 0; next }
  if (t ~ /^#endif/ && sp > 0) { sp--; next }
  d = isdbg()
  if (match(line, DECL)) {
    s = substr(line, RSTART, RLENGTH); n = split(s, w, /[ \t]+/); nm = w[n]
    top = 0; if (sp > 0 && st[sp] == 1 && bd == bd0[sp]) top = 1
    if (pass == 1) { if (top) print "D\t" nm; else if (!d) print "N\t" nm }
  }
  if (pass == 2 && !d) {
    s = line
    while (match(s, /[A-Za-z_][A-Za-z0-9_]*/)) {
      tok = substr(s, RSTART, RLENGTH); before = (RSTART > 1) ? substr(s, RSTART - 1, 1) : ""; s = substr(s, RSTART + RLENGTH)
      if (before != "." && (tok in dname)) print "DEBUG FAIL " FILENAME ":" FNR ": " tok " is declared only inside #if DEBUG (" dname[tok] ") and is used outside it"
    }
  }
  o = gsub(/\{/, "{", line); c = gsub(/\}/, "}", line); bd += o - c
}'

# Prints one line per use of a Debug-only type outside Debug; returns the number of such lines (a failure of the check itself counts as one).
check_debug() {
  local tmp f n=0 fl=0 out
  [ -d "$ROOT/Packages/VideoPlayerCore/Sources" ] || { echo "DEBUG FAIL: $ROOT/Packages/VideoPlayerCore/Sources does not exist (the check cannot run)"; return 1; }
  tmp="$(mktemp -d)"
  find "$ROOT/App" "$ROOT/TopShelf" "$ROOT/Packages/VideoPlayerCore/Sources" -type f -name '*.swift' 2>/dev/null | LC_ALL=C sort >"$tmp/all"
  # shellcheck disable=SC2046
  if ! awk -v pass=1 "$DEBUG_AWK" $(cat "$tmp/all") >"$tmp/p1" 2>"$tmp/err"; then
    echo "DEBUG FAIL: the check itself failed: $(head -n 2 "$tmp/err")"; rm -rf "$tmp"; return 1
  fi
  # A name is Debug-only when it has a D line and no N line (a type of that name outside Debug would make a use ambiguous).
  awk -F'\t' '$1=="N"{nd[$2]=1} $1=="D"{d[$2]=1} END{for(k in d) if(!(k in nd)) print k "\tdeclared inside #if DEBUG"}' "$tmp/p1" | LC_ALL=C sort >"$tmp/names"
  if [ ! -s "$tmp/names" ]; then echo "DEBUG FAIL: no type declared inside #if DEBUG was found (the check cannot run, or the tree has none)"; rm -rf "$tmp"; return 1; fi
  list_files "$@" >"$tmp/files"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in */Tests/*|*/UITests/*|*/Vendor/*|*/.build/*) continue ;; esac
    if ! out="$(awk -v pass=2 -v names="$tmp/names" "$DEBUG_AWK" "$f" 2>&1)"; then
      fl=$((fl + 1)); echo "DEBUG FAIL $f: the check itself failed: $out"; continue
    fi
    if [ -n "$out" ]; then n=$((n + $(printf '%s\n' "$out" | wc -l))); printf '%s\n' "$out"; fi
  done <"$tmp/files"
  rm -rf "$tmp"
  return $((n + fl))
}

if [ "$DEBUG_ONLY" -eq 0 ]; then check_imports "$@"; import_fail=$?; else import_fail=0; fi
if [ "$IMPORTS_ONLY" -eq 1 ]; then
  echo "imports: $import_fail file(s) with a missing import (types of package modules only; see the header of this script)"
  [ "$import_fail" -eq 0 ]; exit
fi
if [ "$DEBUG_ONLY" -eq 1 ]; then
  check_debug "$@"; debug_fail=$?
  echo "debug: $debug_fail use(s) of a Debug-only type outside #if DEBUG (types only; see the header of this script)"
  [ "$debug_fail" -eq 0 ]; exit
fi
check_debug "$@"; debug_fail=$?
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
if ! command -v swiftc >/dev/null 2>&1; then echo "parse: swiftc not found"; echo "parse: passed 0, failed 0 (NOT RUN: no swiftc)"; exit 2; fi
pass=0; fail=0
while IFS= read -r f; do
  if out="$(swiftc -parse -swift-version 5 "$f" 2>&1)"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $f"; echo "$out" | head -8; fi
done < <(list_files "$@")
fail=$((fail + import_fail + debug_fail))
echo "parse: passed $pass, failed $fail (syntax, the import check and the Debug-only type check, types only; see the header of this script)"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
