# Video Player (tvOS): rules for every Claude Code session

This repository is PUBLIC. The owner does not write code and has no Mac. These are the rules a session must not
forget; the detail lives in the linked docs. `.claude/settings.json` blocks the worst mistakes with a hook and deny
rules (docs/CLAUDE_CODE_SETUP.md), but the rules apply whether or not a hook catches them.

## Never

- **No push** in any form (`git push`, `git -C … push`, an alias that pushes, `--force`). The owner pushes.
- **No workflow runs and no builds by Claude**: no `gh workflow run`, no `gh run …`, no Codemagic call of any kind.
  Builds happen only when the owner starts them.
- **No outside contact**: no requests to services, servers or people. Reading Apple's and Claude Code's own
  documentation pages is allowed when a prompt asks for research.
- No `wsl --shutdown`. No new repositories and no repository settings changes.
- Never commit `Packages/VideoPlayerCore/Package.resolved`. Never commit keys, tokens, personal details, account names
  or machine paths (`.claude/settings.local.json` and `CLAUDE.local.md` are gitignored for personal settings).
- No new third-party MCP server or `.mcp.json` until the owner decides (OPEN_QUESTIONS.md R225).

## GitHub Actions

Free GitHub Actions on standard runners only (`xcode-27`, `ubuntu-latest` and the other standard labels that
`scripts/pre-push-check.sh` allows). Never a `-large` / `-xlarge` or self-hosted runner. Workflows are started by hand
only (`workflow_dispatch`), use no secrets and no GitHub token. Runbook: docs/GITHUB_ACTIONS_RUNBOOK.md.

## Commits

- Small local commits, normal commits only: **never amend**, never rewrite history.
- Author and committer "Video Player Dev" <dev@localhost.invalid>, dates in UTC.
- Each message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Stage files by name; never `git add -A` / `git add .` (they would pick up Package.resolved).
- `/vp-commit` applies these rules. Scan every change before reporting (`scripts/pre-push-check.sh`).

## Decisions and the open list

- Every decision has an R-number in OPEN_QUESTIONS.md. Keep the numbers current; the next free one follows the last row.
- Anything the owner has not decided is entered as **PROVISIONAL** and keeps its alternatives in the last column.
  Never drop an alternative when a provisional item changes.
- Owner decisions are marked Decided and are not reopened without the owner.

## Design (the app)

Full text: docs/DESIGN_SYSTEM.md (lint rules, components, exceptions), OPEN_QUESTIONS.md R165, R172, R177, R178, R190.

- Native system components, SF Symbols, system fonts and system colours only. No custom chrome, pills or palettes.
- Real technology names as **text only** (docs/NAMES.md allowlists). No logos; the one exception is the TMDB logo in
  Settings > About (R148). Synthetic names only in fixtures, tests and screenshots.
- **S1**: short texts are never truncated ("…") and never wrapped: one line, scale to fit, then drop the
  lowest-priority part.
- Elements side by side have equal size; buttons of one kind have one height.
- **L1** rows in a bounded column. **L2** one system List/Form row style, no custom pills. **L3** status text is never
  drawn as a row or button. **L4** one system section-header style, no manual upper case. **L5** footers of one or two
  lines plus Learn More. **L6** no empty band under the tab bar, no dim duplicate title. **L7** nothing cut mid-line,
  no fixed-height card that clips. **L8** short texts follow S1. **L9** each honesty line once per screen.
  **L10** an icon and its label never touch.
- **D1** no dim duplicate title on pushed pages. **D2** one button height. **D3** time left as text, no full-width
  progress bar. **D4** card progress inside the artwork. **D5** columns align across rows. **D6** short text never
  cut (S1). **D7** sample data never claims a real-server test.

## Honest claims

- Never say a check passed unless it ran in this session. Report skipped tests separately from passed ones.
- Nothing is compiled for tvOS here: `scripts/parse-app.sh` is a syntax check only, never "it compiles".
- Unproven items stay listed as unproven (docs/COVERAGE.md, the device checklists). Apple claims come from Apple's
  pages; anything not read there is marked "unverified".

## Running the checks

Swift and the tests run in WSL or Linux (from Windows: `wsl.exe bash scripts/<name>.sh`). `/vp-check` runs the set.

| Check | Command |
|---|---|
| Secrets, personal details, workflows, large files | `bash scripts/pre-push-check.sh` |
| Design lint (pure bash) and its self-test | `bash scripts/design-lint.sh`, `bash scripts/test-design-lint.sh` |
| App syntax check (needs Swift) | `bash scripts/parse-app.sh` |
| Package unit tests (exit code is real since #28) | `bash scripts/test-core.sh` |
| Script self-tests | `bash scripts/test-core-tests.sh`, `bash scripts/test-counts-tests.sh`, `bash scripts/test-claude-hooks.sh`, `bash scripts/test-ci-*.sh` |
| Everything, with test servers | `bash scripts/test-all.sh` |

More: docs/SPECS.md (index of every doc), docs/TEST_ENVIRONMENT.md (WSL), docs/CLAUDE_CODE_SETUP.md (hooks, skills,
agent, what they cannot prove).
