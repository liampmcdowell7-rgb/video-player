#!/usr/bin/env bash
# Syntax check of every Swift file in App/, TopShelf/ and UITests/ with `swiftc -parse`.
#
# WHAT THIS CATCHES: syntax errors only (unbalanced braces, bad punctuation, misplaced keywords).
# WHAT THIS CANNOT CATCH: anything that needs the SDK: unknown names, wrong argument labels, missing imports, wrong types,
# availability, actor isolation, view-builder limits. SwiftUI, AVKit, UIKit, TVServices and the rest do not exist on Linux,
# and `-parse` does not look at them. A pass here means "the text is well-formed Swift", never "it compiles".
# Usage: bash scripts/parse-app.sh [FILE.swift ...]   (needs swiftc: WSL/Linux with the toolchain, or the Mac host)
# With files, only those are parsed (the Claude Code after-edit hook, #28 item 4); without, every file below.
# Output: one line per failing file, then `parse: passed N, failed M` (N and M count files).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
if ! command -v swiftc >/dev/null 2>&1; then echo "parse: swiftc not found"; echo "parse: passed 0, failed 0 (NOT RUN: no swiftc)"; exit 2; fi
pass=0; fail=0
while IFS= read -r f; do
  if out="$(swiftc -parse -swift-version 5 "$f" 2>&1)"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $f"; echo "$out" | head -8; fi
done < <(if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; else find "$HERE/App" "$HERE/TopShelf" "$HERE/UITests" -type f -name '*.swift' 2>/dev/null | LC_ALL=C sort; fi)
echo "parse: passed $pass, failed $fail (syntax only; see the header of this script)"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
