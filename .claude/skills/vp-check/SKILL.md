---
name: vp-check
description: Run every local check of this repo (pre-push scan, design lint, App syntax parse, script self-tests, full package tests) and report real failures, with skipped tests listed separately. Owner-invoked only.
disable-model-invocation: true
argument-hint: "[--quick: leave out the full package tests]"
allowed-tools: Bash, Read, Grep, Glob
---

# /vp-check

Run the checks below and report what really happened. Never push, never start a workflow or a build, never contact
anything outside this machine. Do not fix anything in this skill: report only.

## Where to run

Swift and the tests need WSL or Linux. On Windows run each script as `wsl.exe bash scripts/<name>.sh` from the repo
folder (the repo is under `/mnt/<drive>/…` in WSL). In WSL, Linux or on a Mac run `bash scripts/<name>.sh`.
Run them one at a time (not in parallel: WSL can run out of memory, docs/TEST_ENVIRONMENT.md). Save each output to a
file in a temporary folder outside the repo and read it from there.

## Checks, in this order

1. `bash scripts/pre-push-check.sh` (secrets, personal details, Claude Code files, workflows, large files). Exit 0 = pass.
2. `bash scripts/test-design-lint.sh` (the lint's own fixtures), then `bash scripts/design-lint.sh` (App/ and TopShelf/).
3. `bash scripts/parse-app.sh` (swiftc -parse on App/, TopShelf/, UITests/: syntax only, never "it compiles").
4. Script self-tests: `bash scripts/test-core-tests.sh` (exit 3 = skipped, no Swift), `bash scripts/test-counts-tests.sh`,
   `bash scripts/test-claude-hooks.sh`, and every `bash scripts/test-ci-*.sh`.
5. Unless `$ARGUMENTS` contains `--quick`: `bash scripts/test-core.sh` (the full package tests, about 10 minutes).
   Its exit code is real (non-zero on any failed test or when no result was found) and its last line is
   `test-core: passed P, skipped S, failed F (swift test exit N)`.

## Reading the output

- A check passed only if its exit code is 0. Do not trust a summary line alone; also search the output for
  `error:`, `FAIL`, `failed [1-9]`, `Fatal error`, `Build failed`, `NO TEST RESULTS`.
- For the package tests, count with `bash scripts/test-counts.sh --totals <log>` and list the failing test names
  (`Test Case '-[…]' failed` lines).
- Skipped tests are not passes. Report their number on its own line, and group them by reason when the reason is in
  the output (live servers, 100k scale test, missing tools).
- A check that did not run (missing Swift, timeout, WSL stopped) is reported as NOT RUN with the reason, never as passed.

## Report

One table: check, command, result (pass / FAIL / NOT RUN), counts (passed / skipped / failed), time. Below it: every
real failure with file:line or test name and the first relevant lines of output; then the skipped tests on their own.
Say what these checks cannot prove (no tvOS compile, no device, hooks only prove themselves in a real session).
