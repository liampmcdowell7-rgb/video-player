#!/bin/bash
# Checks that the rules table in docs/PLAYBACK_STATUS.md is exactly the golden table the unit tests compare
# against (Packages/VideoPlayerCore/Tests/PlaybackStatusTests/RulesGolden.swift).
# The unit test GoldenTests checks golden == rules code; this script checks doc == golden. Together: doc == code.
# Usage: scripts/playback-status-doc.sh [check]     (default: check, exit 1 on mismatch)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/docs/PLAYBACK_STATUS.md"
GOLD="$ROOT/Packages/VideoPlayerCore/Tests/PlaybackStatusTests/RulesGolden.swift"
BEGIN='<!-- RULES-TABLE-BEGIN (generated, do not edit by hand) -->'
END='<!-- RULES-TABLE-END -->'
[ -f "$DOC" ] || { echo "FAIL: $DOC missing"; exit 1; }
[ -f "$GOLD" ] || { echo "FAIL: $GOLD missing"; exit 1; }

# Table inside the doc: lines strictly between the markers, blank lines at both ends removed.
doc_table=$(awk -v b="$BEGIN" -v e="$END" '$0==b{f=1;next} $0==e{f=0} f' "$DOC" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | sed '/./,$!d')
# Table inside the golden file: between the raw string delimiters.
gold_table=$(awk '/static let markdown = #"""/{f=1;next} /^"""#/{f=0} f' "$GOLD")

if [ -z "$doc_table" ] || [ -z "$gold_table" ]; then
  echo "FAIL: could not read a table (doc ${#doc_table} bytes, golden ${#gold_table} bytes)"; exit 1
fi
if [ "$doc_table" = "$gold_table" ]; then
  echo "OK: docs/PLAYBACK_STATUS.md table matches the golden table ($(printf '%s\n' "$gold_table" | grep -c '^| [AV][0-9]') rows)"
  exit 0
fi
echo "FAIL: docs/PLAYBACK_STATUS.md table differs from the golden table. Regenerate with:"
echo "  VP_UPDATE_GOLDEN=1 VP_REPO_ROOT=\"$ROOT\" swift test --filter GoldenTests   (run in Packages/VideoPlayerCore; it fails once on purpose)"
diff <(printf '%s\n' "$doc_table") <(printf '%s\n' "$gold_table") | head -20
exit 1
