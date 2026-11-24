#!/usr/bin/env bash
# Dry test of the Claude Code hook .claude/hooks/block-forbidden.sh (#28 item 3). Nothing is executed: each case is
# turned into the JSON Claude Code sends to a PreToolUse hook and fed to the hook on stdin; the hook's exit code says
# blocked (2) or allowed (0). Also checks that .claude/hooks/after-edit.sh ignores files outside App/ and UITests/.
# A git repository in a temporary folder holds two configured aliases (pp = push, pq = !git push) for the alias cases.
# Prints one line per case (expected, result, tool, text) and "claude hook tests: passed N, failed M" last.
# Pure bash; runs in Git Bash, WSL, Linux and macOS. Exit 1 on any failure.
#
# What this cannot prove: that Claude Code really calls the hook, with this JSON, in a live session (docs/CLAUDE_CODE_SETUP.md).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HERE/.claude/hooks/block-forbidden.sh"
AFTER="$HERE/.claude/hooks/after-edit.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/repo" 2>/dev/null
git -C "$TMP/repo" config alias.pp push
git -C "$TMP/repo" config alias.pq '!git push'
git -C "$TMP/repo" config alias.st status
export CLAUDE_PROJECT_DIR="$TMP/repo"

esc() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; printf '%s' "$s"; }
P=0; X=0
run_case() { # expect tool json-of-tool_input label
  local expect="$1" tool="$2" input="$3" label="$4" rc got
  printf '{"session_id":"t","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' \
    "$(esc "$TMP/repo")" "$tool" "$input" | bash "$HOOK" >/dev/null 2>"$TMP/err"; rc=$?
  case $rc in 0) got=allow ;; 2) got=block ;; *) got="error($rc)" ;; esac
  if [ "$got" = "$expect" ]; then P=$((P + 1)); printf 'ok    %-5s %-10s %s\n' "$expect" "$tool" "$label"
  else X=$((X + 1)); printf 'FAIL  expected %s, got %s  %-10s %s\n' "$expect" "$got" "$tool" "$label"; sed 's/^/      /' "$TMP/err"; fi
}
cmd()  { run_case "$1" "$2" "{\"command\":\"$(esc "$3")\",\"description\":\"x\"}" "$3"; }
edit() { run_case "$1" Edit "{\"file_path\":\"$(esc "$2")\",\"old_string\":\"$(esc "$4")\",\"new_string\":\"$(esc "$3")\",\"replace_all\":false}" "$2 <- $3"; }
write(){ run_case "$1" Write "{\"file_path\":\"$(esc "$2")\",\"content\":\"$(esc "$3")\"}" "$2 <- $3"; }

echo "== Blocked =="
cmd block Bash 'git push'
cmd block Bash 'git push --force origin main'
cmd block Bash 'git push -f'
cmd block Bash 'git -C . push'
cmd block Bash 'git -C "some folder" push origin main'
cmd block Bash 'git -c push.default=current push'
cmd block Bash 'git --no-pager push'
cmd block Bash '/usr/bin/git push'
cmd block Bash 'GIT_TRACE=1 git push'
cmd block Bash 'cd video-player && git push'
cmd block Bash 'git status; git push'
cmd block Bash 'bash -c "git push"'
cmd block Bash "git -c alias.p='!git push' p"
cmd block Bash 'git pp'
cmd block Bash 'git pq origin main'
cmd block Bash 'git config alias.up push'
cmd block Bash $'git \\\n  push'
cmd block PowerShell '& "C:\Program Files\Git\cmd\git.exe" push'
cmd block PowerShell 'GIT PUSH'
cmd block PowerShell 'git push; if ($?) { echo done }'
cmd block Bash 'gh workflow run compile-check.yml'
cmd block Bash 'gh run list'
cmd block Bash 'gh run rerun 123 --failed'
cmd block Bash 'gh api repos/o/r/actions/workflows/compile-check.yml/dispatches -f ref=main'
cmd block Bash 'curl -X POST https://api.github.com/repos/o/r/actions/workflows/1/dispatches'
cmd block Bash 'curl https://api.codemagic.io/builds'
cmd block Bash 'pip install codemagic-cli-tools'
cmd block Bash 'codemagic start --workflow ios'
cmd block Bash 'wsl --shutdown'
cmd block PowerShell 'wsl.exe --shutdown'
cmd block PowerShell 'wsl -d Ubuntu --shutdown'
cmd block Bash 'git add Packages/VideoPlayerCore/Package.resolved'
cmd block Bash 'git add -A'
cmd block Bash 'git add .'
cmd block Bash 'git add --all'
cmd block Bash 'git add Packages'
cmd block Bash 'git add Packages/VideoPlayerCore/'
cmd block Bash 'git commit -m x Packages/VideoPlayerCore/Package.resolved'
cmd block Bash "sed -i 's/xcode-27/xcode-27-large/' .github/workflows/compile-check.yml"
edit block .github/workflows/compile-check.yml '    runs-on: macos-15-xlarge' '    runs-on: xcode-27'
write block .github/workflows/new.yml $'on: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-latest-large'
edit block 'C:\repo\.github\workflows\compile-check.yml' 'runs-on: macos-14-large' 'runs-on: xcode-27'
cmd block Bash 'grep -n "git push" docs/SPECS.md'   # known false positive (R223): use git[ ]push
cmd block Bash 'git commit -m "docs: never git push"'   # known false positive (R223): commit with -F file

echo "== Allowed =="
cmd allow Bash 'git status'
cmd allow Bash 'git log --oneline origin/main..HEAD'
cmd allow Bash 'git -C . status --short'
cmd allow Bash 'git -C "some folder" status'
cmd allow Bash 'git commit -q -F msg.txt'
cmd allow Bash 'git add scripts/test-core.sh docs/SPECS.md'
cmd allow Bash 'git add Packages/VideoPlayerCore/Sources/PlaybackLogic/Segments.swift'
cmd allow Bash 'git add -u'
cmd allow Bash 'git stash push -m wip'
cmd allow Bash 'git log --grep=push'
cmd allow Bash 'git st'
cmd allow Bash 'git config --get alias.st'
cmd allow Bash 'pushd scripts && ls; popd'
cmd allow Bash 'cat codemagic.yaml'
cmd allow Bash 'gh --version'
cmd allow Bash 'gh pr view 5'
cmd allow PowerShell 'wsl.exe bash scripts/test-core.sh'
cmd allow PowerShell 'wsl --list --verbose'
cmd allow Bash 'bash scripts/pre-push-check.sh'
cmd allow Bash 'grep -n "runs-on" .github/workflows/compile-check.yml'
edit allow .github/workflows/compile-check.yml '    runs-on: xcode-27' '    runs-on: macos-15-xlarge'
edit allow App/Features/Home/HomeView.swift 'let style = "x-large"' 'let style = "large"'
write allow docs/GITHUB_ACTIONS_RUNBOOK.md 'Never use a -large or -xlarge runner.'

echo "== after-edit.sh =="
if [ -f "$AFTER" ]; then
  out="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$(esc "$HERE/docs/SPECS.md")" | bash "$AFTER" 2>&1)"; rc=$?
  if [ $rc -eq 0 ] && [ -z "$out" ]; then P=$((P + 1)); echo "ok    a docs/ edit runs no check and prints nothing"
  else X=$((X + 1)); echo "FAIL  a docs/ edit: exit $rc, output: $out"; fi
else
  X=$((X + 1)); echo "FAIL  $AFTER is missing"
fi

# R461: the import check of scripts/parse-app.sh (the after-edit hook runs that script), on a small invented tree. No swiftc needed.
echo "== parse-app.sh --imports (R461) =="
FX="$TMP/fx"
mkdir -p "$FX/Packages/VideoPlayerCore/Sources/ModA" "$FX/Packages/VideoPlayerCore/Sources/ModB" "$FX/App"
printf 'public enum AppThing { public static let version = "1" }\n@MainActor public final class Store {}\n' >"$FX/Packages/VideoPlayerCore/Sources/ModA/A.swift"
printf 'public struct OtherThing {}\n' >"$FX/Packages/VideoPlayerCore/Sources/ModB/B.swift"
printf 'import SwiftUI\nimport ModA\nlet a = AppThing.version\n' >"$FX/App/Good.swift"
printf 'import SwiftUI\nlet a = AppThing.version\n' >"$FX/App/Bad.swift"
printf 'import ModB\nlet a = AppThing.version\n' >"$FX/App/Wrong.swift"
printf 'import SwiftUI\nlet s = Store()\n' >"$FX/App/Attr.swift"
printf 'import ModB\nlet b = Foo.AppThing\n// AppThing in a comment\nlet s = "AppThing in a string"\n/* Store\n   in a block */\n' >"$FX/App/Quiet.swift"
printf 'struct OtherThing {}\nlet c = OtherThing()\n' >"$FX/App/Local.swift"
run_imports() { PARSE_APP_ROOT="$FX" bash "$HERE/scripts/parse-app.sh" --imports "$@" 2>&1; }
says() { printf '%s\n' "$IMP" | grep -qF -- "$1"; }
imports_case() { # label rc-wanted
  if [ "$2" -eq 0 ]; then P=$((P + 1)); echo "ok    $1"; else X=$((X + 1)); echo "FAIL  $1"; printf '%s\n' "$IMP" | sed 's/^/      /'; fi
}
IMP="$(run_imports)"; rc=$?
[ "$rc" -eq 1 ]; imports_case "a file that names a package type without importing its module fails (exit 1)" $?
says "Bad.swift: AppThing (module ModA) is used without \`import ModA\`"; imports_case "the miss is named with the type and the module" $?
says "Wrong.swift: AppThing"; imports_case "importing a different module does not help" $?
says "Attr.swift: Store (module ModA)"; imports_case "a type declared after an attribute (@MainActor public final class) is read" $?
! says "Good.swift"; imports_case "a file with the import passes" $?
! says "Quiet.swift"; imports_case "a name after a dot, in a comment, in a string or in a block comment is not read" $?
! says "Local.swift"; imports_case "a type the app declares itself is not a package type" $?
says "imports: 3 file(s) with a missing import"; imports_case "the summary counts the files" $?
IMP="$(run_imports "$FX/App/Good.swift" "$FX/App/Quiet.swift")"; rc=$?
[ "$rc" -eq 0 ]; imports_case "with file arguments only those files are checked (the hook)" $?
rm -f "$FX/App/Bad.swift" "$FX/App/Wrong.swift" "$FX/App/Attr.swift"
IMP="$(run_imports)"; rc=$?
[ "$rc" -eq 0 ] && says "imports: 0 file(s)"; imports_case "without the three bad files: exit 0" $?
rm -rf "$FX/Packages"
IMP="$(run_imports)"; rc=$?
[ "$rc" -eq 1 ] && says "the check cannot run"; imports_case "a tree without the package sources fails loudly, it does not pass silently" $?

echo "claude hook tests: passed $P, failed $X"
[ "$X" -eq 0 ]
