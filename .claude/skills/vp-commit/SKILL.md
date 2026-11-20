---
name: vp-commit
description: Make small local commits of the current changes under this repo's commit rules (author Video Player Dev, UTC dates, never amend, never Package.resolved). Never pushes. Owner-invoked only.
disable-model-invocation: true
argument-hint: "[what the commits are about, optional]"
allowed-tools: Bash, Read, Grep, Glob
---

# /vp-commit

Commit the current work locally. **Never push** (the owner pushes), never amend, never rewrite history, never start
a workflow or build. `$ARGUMENTS`, if given, says what the commits are about.

## Before committing

1. `git status --short` and `git diff --stat`. Read every changed file's diff.
2. Run `bash scripts/pre-push-check.sh` (in WSL on Windows). Stop and report if it flags anything.
3. Scan the diff yourself for keys, tokens, personal details, account names, e-mail addresses and machine paths
   (for example a Windows user folder or a home directory). The repo is public. Stop and report any hit.
4. Never stage `Packages/VideoPlayerCore/Package.resolved`, `.claude/settings.local.json`, `CLAUDE.local.md`, build
   output or logs.

## Splitting

Group the changes into small commits, one topic each (a code change with its tests; docs on their own unless they
belong to that change). Stage files **by name** (`git add -- path …`). Never `git add -A`, `git add .`,
`git add --all` or a parent folder of Package.resolved; the hook blocks those.

## Each commit

- Author and committer "Video Player Dev" <dev@localhost.invalid>, UTC dates:

  ```bash
  export GIT_AUTHOR_NAME="Video Player Dev" GIT_AUTHOR_EMAIL="dev@localhost.invalid"
  export GIT_COMMITTER_NAME="Video Player Dev" GIT_COMMITTER_EMAIL="dev@localhost.invalid"
  D="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; export GIT_AUTHOR_DATE="$D" GIT_COMMITTER_DATE="$D"
  git commit -q -F <message file>
  ```

- Write the message to a file outside the repo and commit with `-F` (a message given with `-m` that mentions the
  forbidden commands is blocked by the hook). A short subject line, a blank line, a body that says what changed and
  why in plain words, with R-numbers and prompt items where they apply. The last line is exactly:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- A normal commit only: no `--amend`, no `--no-verify`, no fixup or squash.

## After

`git log --format='%h %an %ad %s' --date=iso-strict-local origin/main..HEAD` and `git status --short`. Report the
commits made, the files left uncommitted and why, and that nothing was pushed.
