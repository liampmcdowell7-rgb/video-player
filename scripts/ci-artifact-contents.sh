#!/usr/bin/env bash
# Lists what a screenshot artifact folder holds and checks it is the right set (#15 item 1.2).
#
#   bash scripts/ci-artifact-contents.sh DIR main|accessibility
#
# Why: a review of the CI run for 8bb0f0c found the accessibility pictures where the main set was expected. The workflow
# keeps them apart (job "screenshots" uploads screenshots/, job "accessibility-screenshots" uploads accessibility-screenshots/),
# so this check runs in each job just before its upload and fails loudly if the folder holds the other set.
#
#   main           index.md at the top; pictures at the top only, each named NN-... with NN from 01 to 79.
#   accessibility  pictures only in the setting folders (text, contrast, transparency, motion), each NN-... with NN 80 or
#                  more; at least one picture in text/ (Larger Text and Bold Text, 80 to 89).
#
# Writes DIR/CONTENTS.txt (every file with its size, then the counts) so the artifact says what it is, prints the same,
# and prints "ARTIFACT OK (<set>)" or one "ARTIFACT PROBLEM: ..." line per problem (exit 1).
# Self-test on fake folders: scripts/test-ci-artifact-contents.sh.
set -u
dir="${1:?usage: ci-artifact-contents.sh DIR main|accessibility}"; set_name="${2:?usage: ci-artifact-contents.sh DIR main|accessibility}"
case "$set_name" in main|accessibility) ;; *) echo "ci-artifact-contents: set must be main or accessibility" >&2; exit 2;; esac
problems=()
if [ ! -d "$dir" ]; then
  echo "ARTIFACT PROBLEM: no folder $dir (nothing would be uploaded)"
  exit 1
fi

listing="$(cd "$dir" && find . -type f ! -name CONTENTS.txt | sed 's|^\./||' | LC_ALL=C sort)"
pictures=0; top=0; text=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.png|*.jpg|*.jpeg|*.heic) ;; *) continue;; esac
  pictures=$((pictures + 1))
  base="${f##*/}"; folder=""; [ "$f" != "$base" ] && folder="${f%/*}"
  num="$(printf '%s' "$base" | sed -nE 's/^([0-9]{2})-.*/\1/p')"
  if [ -z "$num" ]; then problems+=("$f has no NN- number"); continue; fi
  n=$((10#$num))
  if [ "$set_name" = main ]; then
    [ -z "$folder" ] || problems+=("$f is in a subfolder; the main set has its pictures at the top")
    [ "$n" -ge 1 ] && [ "$n" -le 79 ] || problems+=("$f is numbered $num; the main set is 01 to 79 (80 and above are the accessibility set)")
    [ -z "$folder" ] && top=$((top + 1))
  else
    case "$folder" in
      text|contrast|transparency|motion) ;;
      "") problems+=("$f is at the top; accessibility pictures go in text/, contrast/, transparency/ or motion/");;
      *) problems+=("$f is in an unknown folder '$folder'");;
    esac
    [ "$n" -ge 80 ] || problems+=("$f is numbered $num; the accessibility set is 80 and above (01 to 79 are the main set)")
    [ "$folder" = text ] && text=$((text + 1))
  fi
done <<EOF
$listing
EOF

if [ "$set_name" = main ]; then
  [ -f "$dir/index.md" ] || problems+=("no index.md at the top")
  [ "$top" -gt 0 ] || problems+=("no picture at the top (the main screenshots were not copied here)")
else
  [ "$text" -gt 0 ] || problems+=("no picture in text/ (Larger Text and Bold Text, 80 to 89)")
fi

{
  echo "Artifact folder: $(basename "$dir") (expected: the $set_name set)"
  echo
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "$(wc -c <"$dir/$f" | tr -d ' ')	$f"
  done <<EOF
$listing
EOF
  echo
  echo "Files: $(printf '%s\n' "$listing" | grep -c .). Pictures: $pictures."
} >"$dir/CONTENTS.txt"
cat "$dir/CONTENTS.txt"

if [ "${#problems[@]}" -eq 0 ]; then
  echo "ARTIFACT OK ($set_name): $pictures pictures"
  exit 0
fi
for p in "${problems[@]}"; do echo "ARTIFACT PROBLEM: $p"; done
exit 1
