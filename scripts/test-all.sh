#!/usr/bin/env bash
# Runs every test there is, with every real test server, one stage at a time, and prints one line per stage:
#   passed / skipped / failed. A stage that reports skipped tests is NOT counted as a pass for those tests.
# Needs WSL (or Linux) with Swift, and the servers set up by the other scripts (first run downloads them).
# Leaves nothing running except the rclone servers; stops them with `bash scripts/test-servers.sh stop` if you want.
# Usage: bash scripts/test-all.sh
# Under the shared WSL lock, run it as: flock -o -w 7200 ~/vp-wsl.lock env VP_LOCK_HELD=1 bash scripts/test-all.sh
# (-o keeps the lock out of the servers it starts; VP_LOCK_HELD=1 stops the audio and dovi stages taking it again).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${VP_LOG_DIR:-$HOME/vp-test-all-logs}"; mkdir -p "$LOG"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
SUMMARY=""

# 0. Stray-folder guard. A folder whose name starts with "C:" (or "CUsers") appears when a Windows backslash path
# (typically PowerShell expanding $HOME inside a double-quoted string) goes through bash or wsl.exe unquoted.
# Always use /mnt/c/... paths, or write a script file and run it, never "$HOME" inside a PowerShell "..." string.
STRAY="$(find "$HERE" -path '*/.build' -prune -o -type d \( -name 'C:*' -o -name 'CUsers*' \) -print 2>/dev/null | head -5)"
if [ -n "$STRAY" ]; then
  SUMMARY="$SUMMARY
stray-folder guard: passed 0, skipped 0, failed 1 (remove these folders and fix the command that made them: $STRAY)"
else
  SUMMARY="$SUMMARY
stray-folder guard: passed 1, skipped 0, failed 0"
fi

summarize() { # name logfile stage
  # Counts individual test-case lines (repairing a result line another process wrote into; scripts/test-counts.sh), so it
  # does not depend on which summary line comes last.
  local totals
  totals="$(bash "$HERE/scripts/test-counts.sh" --totals "$2" 2>/dev/null)" || totals="passed 0, skipped 0, failed 0"
  SUMMARY="$SUMMARY
$1: $totals"
  [ "$totals" = "passed 0, skipped 0, failed 0" ] && SUMMARY="$SUMMARY (NO TEST RESULT, see $2)"
  # Per-target counts and the minimum-test-count floors (scripts/test-floors.txt). A stage below its floor, or with no
  # result lines, is reported as FAILED loudly; floors are recorded by a person with: bash scripts/test-counts.sh --record STAGE LOG
  if [ -n "${3:-}" ]; then
    local counts
    counts="$(bash "$HERE/scripts/test-counts.sh" "$3" "$2" 2>&1)"; local rc=$?
    SUMMARY="$SUMMARY
$counts"
    [ "$rc" -ne 0 ] && SUMMARY="$SUMMARY
$1: COUNT CHECK FAILED (see above)"
  fi
}

# 0b. Design lint: the linter's own fixtures first, then App/ itself (pure bash, no Swift).
if bash "$HERE/scripts/test-design-lint.sh" >"$LOG/design-lint-tests.log" 2>&1; then DLT=ok; else DLT=bad; fi
SUMMARY="$SUMMARY
design-lint tests ($DLT): $(tail -1 "$LOG/design-lint-tests.log")"
if bash "$HERE/scripts/design-lint.sh" >"$LOG/design-lint-app.log" 2>&1; then SUMMARY="$SUMMARY
design-lint on App/: passed 1, skipped 0, failed 0"; else SUMMARY="$SUMMARY
design-lint on App/: passed 0, skipped 0, failed 1 (see $LOG/design-lint-app.log)"; fi

# 0b2. The test counter's own fixtures (a warning written into a result line must not hide a test; R153).
if bash "$HERE/scripts/test-counts-tests.sh" >"$LOG/test-counts-tests.log" 2>&1; then TCT=ok; else TCT=bad; fi
SUMMARY="$SUMMARY
test-counts tests ($TCT): $(tail -1 "$LOG/test-counts-tests.log")"

# 0b2b. test-core.sh's exit code on a tiny fixture package (#28 item 1): a failing test must give a non-zero exit and the
# skipped test must stay reported on its own. Exit 3 means Swift is missing here (reported as skipped, not passed).
bash "$HERE/scripts/test-core-tests.sh" >"$LOG/test-core-tests.log" 2>&1; TCR=$?
case "$TCR" in 0) TCC=ok ;; 3) TCC=skipped ;; *) TCC=bad ;; esac
SUMMARY="$SUMMARY
test-core exit-code tests ($TCC): $(tail -1 "$LOG/test-core-tests.log")"

# 0b2c. The Claude Code hook that blocks forbidden commands, on a dry list of blocked and allowed commands (#28 item 3).
if bash "$HERE/scripts/test-claude-hooks.sh" >"$LOG/claude-hooks-tests.log" 2>&1; then CHT=ok; else CHT=bad; fi
SUMMARY="$SUMMARY
claude hook tests ($CHT): $(tail -1 "$LOG/claude-hooks-tests.log")"
# 0b3. The device-build inspection checks on fake nm/strings output (scripts/ci-inspect-lib.sh; fourth CI run false alarm).
if bash "$HERE/scripts/test-ci-inspect.sh" >"$LOG/ci-inspect-tests.log" 2>&1; then CIT=ok; else CIT=bad; fi
SUMMARY="$SUMMARY
ci-inspect self-test ($CIT): $(tail -1 "$LOG/ci-inspect-tests.log")"

# 0b4. The check for type names a tvOS SDK framework also declares, on a fake SDK (#15 item 1.1; the real SDK only in CI).
if bash "$HERE/scripts/test-ci-ambiguous-types.sh" >"$LOG/ambiguous-types-tests.log" 2>&1; then CAT=ok; else CAT=bad; fi
SUMMARY="$SUMMARY
ambiguous-types self-test ($CAT): $(tail -1 "$LOG/ambiguous-types-tests.log")"

# 0b5. The screenshot artifact contents check (main set 01-79, accessibility set 80 and above) on fake folders (#15 item 1.2).
if bash "$HERE/scripts/test-ci-artifact-contents.sh" >"$LOG/artifact-contents-tests.log" 2>&1; then CAC=ok; else CAC=bad; fi
SUMMARY="$SUMMARY
artifact-contents self-test ($CAC): $(tail -1 "$LOG/artifact-contents-tests.log")"

# 0b6. The simulator boot, retry and time-budget logic of scripts/ci-sim.sh with a fake xcrun (#15 item 1.7, #16 item 1.8).
if bash "$HERE/scripts/test-ci-sim.sh" >"$LOG/ci-sim-tests.log" 2>&1; then CST=ok; else CST=bad; fi
SUMMARY="$SUMMARY
ci-sim self-test ($CST): $(tail -1 "$LOG/ci-sim-tests.log")"

# 0b6b. The one-test-per-call screenshot runner and its index.md (scripts/ci-ui-tests.sh, ci-ui-index.py, #24 A and D) with
# a fake xcodebuild: a failed test in the middle, a deadline stop with an incomplete bundle, pictures from the simulator.
if bash "$HERE/scripts/test-ci-ui-tests.sh" >"$LOG/ci-ui-tests-tests.log" 2>&1; then CUT=ok; else CUT=bad; fi
SUMMARY="$SUMMARY
ci-ui-tests self-test ($CUT): $(tail -1 "$LOG/ci-ui-tests-tests.log")"

# 0b7. The Larger Text / Bold Text against default comparison (scripts/ci-a11y-compare.py, #17 A) on generated PNGs.
if bash "$HERE/scripts/test-ci-a11y-compare.sh" >"$LOG/a11y-compare-tests.log" 2>&1; then ACT=ok; else ACT=bad; fi
SUMMARY="$SUMMARY
a11y-compare self-test ($ACT): $(tail -1 "$LOG/a11y-compare-tests.log")"

# 0b8. The Codemagic TestFlight route (R266): codemagic.yaml's shape, the build number, the profile entitlement check
# against hand-written sample plists, the log redaction and the pre-push codemagic.yaml section.
if bash "$HERE/scripts/test-ci-codemagic.sh" >"$LOG/codemagic-tests.log" 2>&1; then CMT=ok; else CMT=bad; fi
SUMMARY="$SUMMARY
codemagic self-test ($CMT): $(tail -1 "$LOG/codemagic-tests.log")"

# 0c. Syntax check of the app and extension sources (swiftc -parse). SYNTAX ONLY: it cannot see missing imports, wrong
# labels or unknown names, because the Apple frameworks do not exist here. A pass is never "it compiles".
if bash "$HERE/scripts/parse-app.sh" >"$LOG/parse-app.log" 2>&1; then PA=ok; else PA=bad; fi
SUMMARY="$SUMMARY
swiftc -parse on App/ and TopShelf/ ($PA, syntax only): $(tail -1 "$LOG/parse-app.log")"

# 1. Unit tests (no server): live tests report as skipped here, on purpose.
# VP_SKIP_UNIT=1 leaves this stage out (it is reported as NOT RUN, never as passed); VP_RUN_100K=1 runs the 100,000-item (otherwise skipped, reported as one skipped test)
# LibraryIndex scale test (it takes minutes in a debug build; it is reported as one skipped test).
if [ "${VP_SKIP_UNIT:-0}" = 1 ]; then SUMMARY="$SUMMARY
unit: NOT RUN (VP_SKIP_UNIT=1)"
else
  bash "$HERE/scripts/test-core.sh" >"$LOG/unit.log" 2>&1; summarize "unit (no servers; live tests skip)" "$LOG/unit.log" unit
fi

# 2. rclone servers: WebDAV, HTTP links, FTP, DLNA (SFTP is served but has no live client yet).
bash "$HERE/scripts/test-live.sh" rclone --filter "SourceWebDAVTests|SourceFTPTests|SourceUPnPTests|SourceLinksTests" >"$LOG/rclone.log" 2>&1
summarize "live rclone: webdav, ftp, upnp, links" "$LOG/rclone.log" rclone

# 2b. SFTP through Citadel against a real OpenSSH server (scripts/test-sftp.sh sets up the server and the vendored copies).
bash "$HERE/scripts/test-sftp.sh" >"$LOG/sftp-citadel.log" 2>&1; summarize "live sftp (Citadel + OpenSSH, with SFTPSourceTests)" "$LOG/sftp-citadel.log" sftp

# 3. Jellyfin, then Emby (they share port 8096).
for k in jellyfin emby; do
  cap="$(echo "$k" | sed 's/./\U&/')"
  bash "$HERE/scripts/test-mediaservers.sh" start "$k" >"$LOG/$k-start.log" 2>&1 || { SUMMARY="$SUMMARY
live $k: server did not start (see $LOG/$k-start.log)"; continue; }
  (
    eval "$(bash "$HERE/scripts/test-mediaservers.sh" env "$k")"
    W="$HOME/vp-build-$k"; mkdir -p "$W"
    rsync -a --delete --exclude .build "$HERE/Packages/VideoPlayerCore/" "$W/"
    cd "$W"
    # A scratch build left half-written by an interrupted earlier run fails with "signature mismatch" (seen 2026-11-17, R81):
    # throw the build folder away and build once more, so the stage does not depend on what ran before.
    swift test --filter "Source${cap}Tests" 2>&1 | tee run1.log; if grep -q "error: Build failed" run1.log; then rm -rf .build; swift test --filter "Source${cap}Tests"; fi
  ) >"$LOG/$k.log" 2>&1
  summarize "live $k" "$LOG/$k.log" "$k"
  bash "$HERE/scripts/test-mediaservers.sh" stop >/dev/null 2>&1
done

# 4. SMB (impacket server + AMSMB2 4.0.3 patched) and NFS (rclone NFS server + libnfs 5.0.2 built from source).
bash "$HERE/scripts/test-smb.sh" >"$LOG/smb.log" 2>&1; summarize "smb (unit + live)" "$LOG/smb.log" smb
bash "$HERE/scripts/test-smb.sh" stop >/dev/null 2>&1
bash "$HERE/scripts/test-nfs.sh" >"$LOG/nfs.log" 2>&1; summarize "nfs (unit + live)" "$LOG/nfs.log" nfs
bash "$HERE/scripts/test-nfs.sh" stop >/dev/null 2>&1

# 4b. dovi: Dolby Vision profile 7 -> 8.1 with the RPU library built from source, compared with the reference tool on
# FIXTURE streams (scripts/test-dovi.sh builds / fetches what is missing; no server).
bash "$HERE/scripts/test-dovi.sh" >"$LOG/dovi.log" 2>&1; summarize "dovi (Dolby Vision profile 7 conversion)" "$LOG/dovi.log" dovi

# 4c. audio: DTS, DTS-HD, Dolby TrueHD, MLP, Opus and Vorbis decoded to FLAC with the LGPL codec library built from source,
# bit-exact checks against reference decodes on FIXTURE files (scripts/test-audio.sh builds / generates what is missing).
bash "$HERE/scripts/test-audio.sh" all >"$LOG/audio.log" 2>&1; summarize "audio (decode to FLAC, bit-exact checks)" "$LOG/audio.log" audio

# 5. Doc check: the rules table in docs/PLAYBACK_STATUS.md equals the golden table the unit tests compare against.
if bash "$HERE/scripts/playback-status-doc.sh" check >"$LOG/status-doc.log" 2>&1; then
  SUMMARY="$SUMMARY
playback-status doc table: passed 1, skipped 0, failed 0 ($(head -1 "$LOG/status-doc.log"))"
else
  SUMMARY="$SUMMARY
playback-status doc table: passed 0, skipped 0, failed 1 (see $LOG/status-doc.log)"
fi

# The unit stage (1) covers every target: VideoPlayerCore, all Source*, LibraryIndex (system SQLite via
# scripts/setup-sqlite.sh, run by test-core.sh), MetadataLocal, MetadataOnline, PlaybackLogic, Subtitles, PlaybackStatus.
echo "$SUMMARY"
echo "Logs: $LOG"
