#!/usr/bin/env bash
# PreToolUse hook (#28 item 3): blocks the commands this project forbids, deterministically, before they run.
# Wired in .claude/settings.json for Bash, PowerShell, Edit, Write and MultiEdit. Reads the hook JSON on stdin.
# Exit 0 = allowed. Exit 2 = blocked; the reason goes to stderr and Claude Code shows it to Claude.
# Pure bash (no jq, no python): runs in Git Bash on Windows, WSL, Linux and macOS.
#
# Blocked:
#   - git push in every form: git -C dir push, git -c x=y push, git.exe / a full path to git, push --force, a word
#     "push" after git anywhere in a command segment (also inside bash -c "..." or quotes), an inline alias
#     (-c alias.x=...push), a configured alias whose text pushes (resolved with `git config --get alias.<name>`),
#     and setting an alias that pushes (git config alias.x push)
#   - gh workflow run, gh run (any subcommand), gh api / curl calls to GitHub's dispatches or rerun endpoints
#   - any Codemagic call: codemagic.io, codemagic-cli-tools, a command word starting with "codemagic"
#   - wsl --shutdown (also wsl.exe, -shutdown, /shutdown)
#   - git add / stage / commit / update-index naming Package.resolved, and adds that would sweep it in:
#     git add -A / --all / . / * / :/ or a parent folder of Packages/VideoPlayerCore/Package.resolved
#   - Edit / Write / MultiEdit of .github/workflows/* whose new text contains -large or -xlarge, and shell commands
#     that mention .github/workflows together with -large / -xlarge
#
# Known limits (OPEN_QUESTIONS.md R223): text matching, not a shell parser. It errs on the side of blocking: a command
# that only mentions the words (echo "git push", grep "git push") is blocked too; write such patterns as git[ ]push.
# JSON \uXXXX escapes are not decoded (Claude Code sends ASCII as is). A command built at run time from pieces
# (variables, base64, eval of a downloaded script) can evade any text check; the permission deny rules are the second
# layer, and the rules in CLAUDE.md apply regardless. Self-test: scripts/test-claude-hooks.sh.
set -u
set -f            # no globbing when splitting words
shopt -s nocasematch

INPUT="$(cat)"

block() {
  printf 'Blocked by .claude/hooks/block-forbidden.sh: %s\nProject rule (CLAUDE.md): no push, no workflow runs or builds, no outside contact, never commit Package.resolved, standard runners only.\n' "$1" >&2
  exit 2
}

# Value of the first JSON string field named $1 in $2, with the common escapes decoded. Empty when absent.
json_field() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  if [[ $2 =~ $re ]]; then unescape "${BASH_REMATCH[1]}"; fi
}
unescape() {
  local s="$1"
  s="${s//\\\\/$'\001'}"
  s="${s//\\\"/\"}"
  s="${s//\\n/$'\n'}"
  s="${s//\\r/$'\r'}"
  s="${s//\\t/$'\t'}"
  s="${s//\\\//\/}"
  s="${s//$'\001'/\\}"
  printf '%s' "$s"
}

TOOL="$(json_field tool_name "$INPUT")"
PROJECT="${CLAUDE_PROJECT_DIR:-$(json_field cwd "$INPUT")}"

# ---------------------------------------------------------------- file edits: workflow runners
check_edit() {
  local path new="" rest re m
  path="$(json_field file_path "$INPUT")"
  path="${path//\\//}"
  [[ $path =~ (^|/)\.github/workflows/ ]] || return 0
  rest="$INPUT"
  re="\"(content|new_string)\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  while [[ $rest =~ $re ]]; do
    m="${BASH_REMATCH[0]}"
    new+="$(unescape "${BASH_REMATCH[2]}")"$'\n'
    rest="${rest#*"$m"}"
  done
  if [[ $new =~ -x?large([^A-Za-z0-9_]|$) ]]; then
    block "a -large / -xlarge runner in a workflow file ($path). Larger runners are billed; use a standard runner."
  fi
}

# ---------------------------------------------------------------- shell commands
is_git()  { local b="${1##*/}"; b="${b##*\\}"; [[ $b == git || $b == git.exe ]]; }
is_gh()   { local b="${1##*/}"; b="${b##*\\}"; [[ $b == gh || $b == gh.exe ]]; }
is_wsl()  { local b="${1##*/}"; b="${b##*\\}"; [[ $b == wsl || $b == wsl.exe ]]; }

RESOLVED="packages/videoplayercore/package.resolved"
# True when adding path $1 would include Package.resolved.
sweeps_resolved() {
  local p="$1"   # nocasematch is on, so the patterns below ignore case
  p="${p//\\//}"; p="${p#./}"; p="${p%/}"
  case "$p" in
    ""|.|"*"|":/"|":"|":/*") return 0 ;;
    packages|packages/videoplayercore|"$RESOLVED"|*/package.resolved|package.resolved) return 0 ;;
    packages/\**|packages/videoplayercore/\**) return 0 ;;
  esac
  return 1
}

# Text of alias $1 (configured in any git scope), empty when none.
alias_text() {
  git -C "${PROJECT:-.}" config --get "alias.$1" 2>/dev/null || true
}

check_git_words() { # words after "git"
  local -a w=("$@")
  local n=${#w[@]} i=0 inline="" sub
  while [ $i -lt $n ]; do
    case "${w[$i]}" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--config-env|--super-prefix)
        [[ ${w[$i]} == -c ]] && inline+=" ${w[$((i+1))]:-}"
        i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ $i -lt $n ] || return 0
  sub="${w[$i]}"
  local rest=("${w[@]:$((i+1))}")
  [[ $inline =~ alias\.[^=]*=.*push ]] && block "git -c alias...=push (an inline alias that pushes)"
  case "$sub" in
    push) block "git push (pushing is the owner's job)" ;;
    config)
      local all=" ${rest[*]} "
      if [[ $all =~ alias\. ]] && [[ $all =~ push ]]; then block "git config of an alias that pushes"; fi ;;
    add|stage)
      local a
      for a in "${rest[@]}"; do
        case "$a" in
          -A|--all|--no-ignore-removal) block "git add $a (would also add Package.resolved; name the files)" ;;
          --) ;;
          -*) ;;
          *) sweeps_resolved "$a" && block "git add $a (would add Package.resolved; name the files one by one)" ;;
        esac
      done ;;
    commit|update-index)
      local all=" ${rest[*]} "
      [[ $all =~ package\.resolved ]] && block "git $sub naming Package.resolved (never committed)" ;;
  esac
  # An alias: resolve up to three levels.
  local name="$sub" text depth=0
  while [ $depth -lt 3 ]; do
    text="$(alias_text "$name")"
    [ -n "$text" ] || break
    [[ $text =~ (^|[^A-Za-z])push([^A-Za-z]|$) ]] && block "git $sub is an alias for \"$text\", which pushes"
    name="${text%% *}"; name="${name#!}"
    depth=$((depth + 1))
  done
}

check_gh_words() {
  local -a w=("$@")
  local -a pos=()
  local x
  for x in "${w[@]}"; do [[ $x == -* ]] || pos+=("$x"); done
  [ ${#pos[@]} -gt 0 ] || return 0
  case "${pos[0]}" in
    run) block "gh run ${pos[1]:-} (no workflow runs by Claude)" ;;
    workflow) [[ ${pos[1]:-} == run ]] && block "gh workflow run (no workflow runs by Claude)" ;;
    api) [[ " ${w[*]} " =~ (dispatches|/rerun) ]] && block "gh api to a dispatch or rerun endpoint (starts a workflow)" ;;
  esac
}

check_command() {
  local cmd="$1"
  # Join continued lines (bash backslash-newline, PowerShell backtick-newline).
  cmd="${cmd//\\$'\n'/ }"; cmd="${cmd//\`$'\n'/ }"; cmd="${cmd//$'\r'/}"

  # Whole-command checks.
  [[ $cmd =~ codemagic\.io|codemagic-cli ]] && block "a Codemagic call (no builds by Claude, no outside contact)"
  [[ $cmd =~ api\.github\.com[^[:space:]]*(dispatches|/rerun) ]] && block "a GitHub API dispatch or rerun call (starts a workflow)"
  if [[ $cmd =~ \.github[/\\]+workflows ]] && [[ $cmd =~ -x?large([^A-Za-z0-9_]|$) ]]; then
    block "a command that writes a -large / -xlarge runner into a workflow file"
  fi

  # Split into segments at shell separators. Each segment is judged twice: once with every quote removed (so the
  # text inside bash -c "..." is seen as words), and once with each quoted span kept as one word (so a quoted
  # value with spaces, such as git -C "some folder" push, does not shift the words). Either pass can block.
  local seg="$cmd" s
  seg="${seg//&&/$'\n'}"; seg="${seg//||/$'\n'}"
  local c
  for c in ';' '|' '&' '(' ')' '`' '{' '}'; do seg="${seg//"$c"/$'\n'}"; done
  seg="${seg//\$/ }"
  while IFS= read -r s; do
    [[ $s =~ alias\.[^[:space:]=]+[[:space:]]*=.*push ]] && block "an inline git alias that pushes"
    check_words "${s//[\"\']/ }"
    if [[ $s == *[\"\']* ]] && [ ${#s} -lt 20000 ]; then check_words "$(group_quotes "$s")"; fi
  done <<<"$seg"
}

# Spaces inside quotes become \002 and the quotes are dropped, so a quoted span is one word.
group_quotes() {
  local s="$1" out="" q="" ch i
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:$i:1}"
    if [ -z "$q" ] && [[ $ch == \" || $ch == \' ]]; then q="$ch"; continue; fi
    if [ -n "$q" ] && [ "$ch" = "$q" ]; then q=""; continue; fi
    if [ -n "$q" ] && [[ $ch == [[:space:]] ]]; then out+=$'\002'; else out+="$ch"; fi
  done
  printf '%s' "$out"
}

check_words() {
  local -a w=()
  read -r -a w <<<"$1" || true
  local n=${#w[@]} i word base x
  for ((i = 0; i < n; i++)); do
    word="${w[$i]#!}"; word="${word#@}"
    base="${word##*/}"; base="${base##*\\}"
    if is_git "$word"; then check_git_words "${w[@]:$((i+1))}"; fi
    if is_gh "$word"; then check_gh_words "${w[@]:$((i+1))}"; fi
    if is_wsl "$word"; then
      for x in "${w[@]:$((i+1))}"; do
        [[ $x == --shutdown || $x == -shutdown || $x == /shutdown ]] && block "wsl --shutdown (stops every WSL distribution)"
      done
    fi
    if [[ $base == codemagic* && $base != *.* ]]; then block "a Codemagic command ($base)"; fi
  done
}

case "$TOOL" in
  Bash|PowerShell)
    CMD="$(json_field command "$INPUT")"
    [ -n "$CMD" ] || CMD="$(unescape "$INPUT")"   # could not read the field: judge the whole input instead
    check_command "$CMD" ;;
  Edit|Write|MultiEdit)
    check_edit ;;
esac
exit 0
