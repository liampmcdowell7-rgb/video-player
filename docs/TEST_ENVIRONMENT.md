# Test environment: why WSL and the media-server tests failed, and what to change

Measured on 2026-11-17 on the user's PC (Windows 11, 16 GB RAM, WSL2 Ubuntu). Everything below was read from the machine; nothing was guessed. Nobody restarted WSL on purpose; `wsl --shutdown` is the user's decision (see step 3).

## 1. Two separate problems

### 1a. "library scan found nothing" (Jellyfin and Emby live tests)
**Cause (reproduced):** right after the server starts, Jellyfin answers `/System/Info/Public` with HTTP 200 while it is still migrating its database, and answers every other request with **HTTP 503** (an HTML "starting" page). The old `scripts/test-mediaservers.sh` retried each setup call only 8 times, one second apart, and ignored every status code. On a loaded machine the wizard calls, the sign-in and the "add library" call all failed silently, so no library existed and the scan "found nothing". The test media was not the problem: all 7 files were present (checked by size). A user named after the OS user (the WSL login name) appears in the Jellyfin log because the first `GET /Startup/User` makes Jellyfin create a default user; the script's `POST` renames it to `tester`. That is harmless.

**Fix (in `scripts/test-mediaservers.sh`, `scripts/lib-testmedia.sh`, `scripts/test-servers.sh`):**
- Every setup call goes through `http`, which waits up to 120 s for a 2xx, stops at a real 4xx, and fails with the call name, the status and the start of the body.
- An empty sign-in token is now an error with the reply shown.
- `start` creates the test media itself every time (`make_media` from the shared `lib-testmedia.sh`; idempotent, 47,192,076 bytes in 7 files). Nothing else has to have run first. `test-servers.sh` uses the same file.
- Failure of the library scan prints the number of files in the media folder and the last item count.

**Verified:** `bash -n` on the four scripts; `make_media` run twice into an empty folder (7 files, 47,192,076 bytes); Jellyfin started from a wiped data folder with the media folder deleted first: server up and library populated in **19 s**, 7 media files recreated. **Not verified:** the `swift test` part of the Jellyfin and Emby stages and the whole Emby start, because the WSL virtual machine crashed right after the Jellyfin start (next section) and the rules say to stop, not loop.

### 1b. The WSL virtual machine crashes under load
**Evidence from Windows (event log, System):**
- 07:30:08, 07:33:04 and 07:34:11: event 2004 "Windows successfully diagnosed a low virtual memory condition", naming `vmmem` (4.3 GB), `vmmemWSL` (3.0 to 3.9 GB) and one `claude.exe` (0.8 GB) as the biggest consumers.
- 07:34:14 to 07:34:19: the WSL virtual network switch port is deleted and created again, which is what a restarted WSL VM looks like. Inside WSL, `uptime` then read "up 0 minutes" and a log written seconds before was empty (unflushed data lost), consistent with a hard stop and not a clean exit.
- Memory counters at the time: **committed 47.7 GB of a 48.8 GB commit limit (98 %)**, 1.4 GB available RAM, 18.5 GB private memory across all processes.

**Memory or disk? Memory (virtual memory commit), not disk.** The "1.1 GB free" earlier was `Win32_OperatingSystem.FreePhysicalMemory`, i.e. RAM.

| Item | Value | Verdict |
|---|---|---|
| Windows RAM | 16,180 MB total, 1.4 to 2.2 GB free (Memory Compression holds 2.8 GB) | tight |
| Windows commit charge | 47.7 GB used of 48.8 GB limit (RAM 16 GB + page file 30.4 GB) | **at the limit: this is what kills the VM** |
| Page file | `C:\pagefile.sys`, 30.4 GB allocated, 2.9 GB in use | it sits on C:, which has only 20 GB free |
| `vmmemWSL` (this WSL) | 2.0 to 2.7 GB working set, 2.7 GB private, up to 3.9 GB virtual | normal |
| `vmmem` (a second VM, not WSL) | 4.1 GB private memory | not identified: needs an administrator tool (`hcsdiag list` says "Insufficient privileges") |
| Claude desktop processes | 2.3 GB across 7 processes | part of the pressure |
| C: drive | 20.1 GB free of 237 GB | not the cause, but low |
| D: drive | 1,905 GB free | plenty |
| WSL disk `ext4.vhdx` | 47.1 GB on C: (inside Linux: 46 GB used of 1,007 GB) | not the cause |
| `.wslconfig` | contains only `[wsl2]`: no memory limit, so WSL may take half the RAM (7.8 GB) | |
| Inside WSL | 7,842 MB RAM, 2,048 MB swap, 911 GB free disk | fine |

## 2. Steps for the user (nothing here was done for you)

### Step 1: give Windows more virtual memory (the real fix)
The commit limit is RAM plus page file. The page file is on C:, which has only 20 GB free, so it cannot grow. Add a second page file on D: (1.9 TB free):
1. Press the Windows key, type **View advanced system settings**, open it.
2. On the **Advanced** tab, under **Performance**, click **Settings...**, then the **Advanced** tab, then under **Virtual memory** click **Change...**.
3. Untick **Automatically manage paging file size for all drives**.
4. Select drive **D:**. Choose **Custom size**. Initial size **16384** MB, maximum size **65536** MB. Click **Set**.
5. Select drive **C:** and leave it **System managed size** (click **Set**).
6. Click **OK** on every dialog. If Windows asks to restart, restart when no session is running work. (Adding a page file normally takes effect at once; a restart is only needed to shrink one.)
Result: the commit limit rises by up to 64 GB, so a memory spike no longer kills the VM.

### Step 2: cap WSL so it cannot grow without limit
Create or edit the file `%UserProfile%\.wslconfig` (plain text; `%UserProfile%` is your Windows home folder, `C:\Users\<your user name>`) so it reads exactly:

```
[wsl2]
memory=6GB
processors=4
swap=8GB
swapfile=D:\\wsl-swap.vhdx

[experimental]
autoMemoryReclaim=gradual
```

- `memory=6GB`: the VM never takes more than 6 GB of Windows RAM (today it may take 7.8 GB). Swift builds fit in 6 GB; if a build is killed for memory, use 8GB.
- `processors=4`: leaves 2 of 6 cores to Windows.
- `swap=8GB` and `swapfile=D:\\wsl-swap.vhdx`: the VM's own swap lives on D: (the double backslash is required in this file) instead of C:.
- `autoMemoryReclaim=gradual`: WSL hands unused page-cache memory back to Windows instead of keeping it.
The file is only read when the VM starts, so it takes effect after step 3.

### Step 3: restart WSL once, yourself, when no Claude session needs it
Another Claude session shares the same WSL instance, so no assistant may do this. In a Windows PowerShell window, when every session is idle:
```
wsl --list --running
wsl --shutdown
```
Then start WSL again by opening any WSL command. Check afterwards with `wsl -d Ubuntu -- free -m` that total memory shows about 6000 MB.

### Optional
- Keep at least 15 GB free on C: (the 47 GB `ext4.vhdx` grows as you use it). To move it to D: you can run `wsl --manage Ubuntu --move D:\wsl\Ubuntu` (needs WSL 2.1 or newer: check with `wsl --version`; do this only with WSL idle).
- In Task Manager, Details tab, sort by **Commit size**, and close what you do not need before long test runs. The 4.1 GB `vmmem` process is another virtual machine (not WSL): if you do not know what runs it, check Docker Desktop, Windows Sandbox or another app's VM.

## 3. How to re-run the live stages once steps 1 to 3 are done
```
bash scripts/test-mediaservers.sh start jellyfin     # about 20 s, creates its own media, fails loudly with the reason
bash scripts/test-all.sh                             # every stage, one line each
```
Or one live stage at a time with the helper used for this investigation: start the server, run `swift test --filter SourceJellyfinTests` (or Emby) in a private copy with `eval "$(bash scripts/test-mediaservers.sh env jellyfin)"`, then `bash scripts/test-mediaservers.sh stop`.

## Update 2026-11-17 (parent): what the Windows memory counters showed while WSL kept dying
- Windows event 2004 (low virtual memory) was logged at 08:07, 08:13, 08:18, 08:23 and 09:38. Each time WSL's virtual machine was killed during a long compile (the last one at step 893 of 962 of the Citadel build).
- Commit limit 46.6 GB, about 2.4 GB free at 09:40. The page file is "C:\pagefile.sys", system managed, only on C:.
- Two virtual-machine processes hold memory: `vmmemWSL` (2 to 4.4 GB, the WSL Ubuntu VM) and a second `vmmem` that stays at 4.3 GB and is not WSL. I could not identify it without admin rights; if you run Docker Desktop, Windows Sandbox, or another virtual machine, closing it frees 4.3 GB.
- `~/.wslconfig` is currently only `[wsl2]` (no cap). Steps 1 to 3 in this file still apply.
- Consequence: every stage that needs a long compile (Citadel live tests, the remux engine tests, Jellyfin and Emby, the full unit run) is unreliable until the page file is enlarged. Stages that completed before the crashes are reported with their real results; stages that did not are reported as not run.
