# Claude Code setup for this repo (#28)

What is committed for Claude Code sessions, what each part does, and what it cannot prove. Sources: Claude Code's own
documentation pages on memory, hooks, skills, sub-agents, settings and MCP (code.claude.com/docs/en/…, read 2026-11-19).

| File | What it is |
|---|---|
| `CLAUDE.md` | The rules a session must not forget (under 100 lines), with links to the docs. Context, not enforcement. |
| `.claude/settings.json` | Shared settings: the two hooks below and 33 permission deny rules (second layer). |
| `.claude/hooks/block-forbidden.sh` | PreToolUse hook on Bash, PowerShell, Edit, Write, MultiEdit. Exit 2 blocks the call. |
| `.claude/hooks/after-edit.sh` | PostToolUse hook on Edit, Write, MultiEdit of App/ or UITests/ files. |
| `.claude/skills/vp-check/SKILL.md` | `/vp-check`: every local check, real failures, skipped tests apart. Owner-invoked only. |
| `.claude/skills/vp-commit/SKILL.md` | `/vp-commit`: small local commits under the commit rules; never pushes. Owner-invoked only. |
| `.claude/agents/docs-sync.md` | Read-only sub-agent: docs against the diff (R-numbers, PLAYBACK_LOGIC rows and tests, picture counts, NAMES.md, DATA_SOURCES.md). |
| `scripts/test-claude-hooks.sh` | Dry test of the blocking hook (44 blocked and 23 allowed cases) and one after-edit case. |

Personal files stay out of the repo: `.claude/settings.local.json` and `CLAUDE.local.md` are gitignored, and
`scripts/pre-push-check.sh` fails if either is tracked, and scans CLAUDE.md, `.claude/` and the hook self-test for
secrets, machine paths, e-mail addresses and the names of the person on the machine (read at run time).

No MCP server and no `.mcp.json` are committed: the owner's decision is pending (OPEN_QUESTIONS.md R225).

## The blocking hook

Blocks, with the reason shown to Claude: `git push` in every form (`git -C`, `git -c`, `--force`, a full path to git,
inside `bash -c "…"`, inline and configured aliases, setting an alias that pushes); `gh workflow run`, `gh run …`, GitHub
API dispatch and rerun calls; any Codemagic call; `wsl --shutdown`; `git add` / `commit` naming Package.resolved and
adds that would sweep it in (R222); Edit / Write of `.github/workflows/*` or shell commands that put a `-large` /
`-xlarge` runner there. Pure bash: Git Bash on Windows, WSL, Linux, macOS. Limits: R223.

Why a hook and deny rules: Claude Code's docs say deny rules are not a security boundary and that a rule such as
`Bash(git push *)` does not match `git -C . push`; the hook does. The deny rules still catch the plain forms if the
hook is not run (for example when hooks are turned off).

Dry test result (2026-11-19): 68 passed, 0 failed, in Git Bash on Windows (16 s) and in WSL. Two cases are known
false blocks kept in the test on purpose: `grep -n "git push" …` and `git commit -m "… git push …"`.

## The after-edit hook

Runs the full design lint (`scripts/design-lint.sh`) and `scripts/parse-app.sh <edited file>`; through `wsl.exe` on
Windows when there is no local Swift. Limits 90 s (lint) and 60 s (parse); hook timeout 180 s. Prints nothing on a pass;
on a failure or a timeout it prints only the failing lines and exits 2. Measured 2026-11-19 on this machine: 25.0 s for
an App/ edit, 23.7 s for a UITests/ edit, 23.0 s for a broken probe file (both the lint line and the parse error
reported, exit 2). Choices and alternatives: R224.

## What stays unproven

- That Claude Code calls these hooks in a real session with exactly this JSON, on Windows through Git Bash with a
  Windows `${CLAUDE_PROJECT_DIR}`: only a live session proves it. The dry test feeds hand-built JSON.
- That the deny rules (including the `PowerShell(...)` ones) match as the docs describe: not exercised.
- That `/vp-check`, `/vp-commit` and the docs-sync agent behave as written: they are instructions to Claude, not code.
- Hooks change nothing about the app: there is still no tvOS compile here, and parse-app.sh is a syntax check only.
