# TOS audit notes — for a fixing session

Audit of the published `dev` branch at commit `1183c69` ("Cluster: a storage pool, on the answers the operator approved"), done 2026-11-15 in two passes. No source file was changed; this file is the only output.

**Second pass.** The first pass was off-box only. The second ran the findings on a real OpenComputers machine: Ocelot Desktop 1.14.2's jar driven by the project's own `build/headless-selftest.py` and `build/headless-session.py`. It confirmed seven findings on the real system, corrected two of my first-pass claims (B2 and B3, marked below), and added B7, C2, C3, C4, D6 and D7. Setup is in the appendix.

**Third pass.** Lua 5.2 and 5.4. A five-line patch to a private copy of the headless runner (appendix) lets it pick the CPU's architecture, which Ocelot Brain supports. That put B4 and B6 on a real Lua 5.2 machine, added F1 and F2, and checked the README's Lua 5.4 claim on a booted machine. It also ran `build/floorcheck.py`, which boots each memory size the README names, and found D8 and E9, and paired two machines to show A1's effect on the remote shell end to end (and C5 on the way).

**Fourth pass.** `backup` and `srm`, driven on a booted machine. The backup round trip is sound; the headline is G1, an admin writing arbitrary content into `/tos/kernel` through `srm restore`, past the guard the manual says stops exactly that.

**Why this file is in `docs/`.** The first pass put it at the repo root. That broke `test_release_excludes.lua` ("every top-level entry ships or is excluded by BOTH build scripts") and the release build copied it onto the install disk. `docs/` is excluded from the release, and the suite is green with it here.

**Paths.** Everything below is relative to the published repo root, which is `TOS-Dev/` in the local monorepo. `TOS-Extras/` is nested inside the published repo and a sibling of `TOS-Dev/` locally. Line numbers are from `1183c69` and will have drifted in a newer local copy, so each finding also names the function or quotes the text to search for.

**How to read the evidence labels.**

- **Confirmed in Ocelot**: seen on a booted machine (Ocelot Brain, the same `machine.lua` and component code as the mod) through a scripted headless session. The session scripts are in the appendix.
- **Reproduced**: I ran the real module off-box and saw the wrong behaviour. The script is in the appendix.
- **Confirmed against OpenComputers source**: I read the code path here and checked the platform behaviour it depends on in `MightyPirates/OpenComputers` (branch `master-MC1.12`, 1.8.10, and tag `v1.7.5` where noted). Not run in the game.
- **Confirmed by reading**: the code path is unambiguous, but I did not execute it.

## Baseline

| Check | Result |
|---|---|
| `python run_tests.py`, Lua 5.3.6 | PASS=484 FAIL=0 SKIP=6 |
| Same suite with `lua` pointed at Lua 5.4 | PASS=484 FAIL=0 SKIP=6 |
| `python tos.py check` | OK |
| `python tos.py build` | Builds; `test_manifest_digests` and `test_release_budget` pass once `../TOS-Release` exists |
| `luac -p` on every `.lua`, 5.3 and 5.4 | Clean |
| `luacheck` on `tos/`, `etc/`, boot files | No undefined globals beyond the sandbox-injected ones |
| `python tos.py selftest` on Ocelot 1.14.2 | 117 of 117 boot checks pass |
| README one-liner against published `main`, in Ocelot | Signature valid, 171 files, install, BIOS flash, reboot, First Boot Setup: all work |
| README "first ten minutes" on a booted machine | `useradd`, `usermod`, `logout`, login, `why`, `theme set` all behave |
| Boot battery on a **Lua 5.4** CPU in Ocelot | 117 of 117; the REPL reports `Lua 5.4`, and `about`, `useradd`, `df`, `cron` and `verify` work |
| TOS BIOS on a **Lua 5.2** CPU in Ocelot | Stops as designed: "SRM C1 - POST FAILED", the hint, one long and one short beep |
| `build/floorcheck.py` (every README memory size, T1 CPU) | Every claim about what works at each size holds; the free-memory figures are off (E9) |

The suite is green, so everything below is behaviour the tests do not cover.

## Summary

| ID | Severity | What | Evidence |
|---|---|---|---|
| A1 | High | `service stop` is undone by the supervisor within 30 s | Confirmed in Ocelot |
| A2 | High | Once started, `rshd` cannot be switched off again across reboots | Confirmed in Ocelot |
| A3 | Medium | `pkg disable` does not stop the package's service or keep it off | Confirmed in Ocelot |
| B1 | Medium | Ctrl+C at any installer y/n prompt means **yes** | Confirmed in Ocelot |
| B2 | Low–Medium | `bootstrap.lua` counts a failed staging write as a download (revised) | Confirmed in Ocelot |
| B3 | Low | `bootstrap.lua`'s space estimate is about to be too low (corrected) | Measured |
| B4 | Low–Medium | On a Lua 5.2 CPU the bootstrap dies with a traceback and the installer installs anyway | Confirmed in Ocelot |
| B5 | Low | `bootstrap.lua` never removes itself: OpenOS has no `arg` | Confirmed in Ocelot |
| B6 | Low | The Lua 5.2 screen gives an instruction that does not work, and is cut off on Tier 1 | Confirmed in Ocelot |
| B7 | Low | The bootstrap warns it will run out of space, then carries on | Confirmed in Ocelot |
| C1 | Low | `cron add` with a fractional interval errors after saving the job | Confirmed in Ocelot |
| C2 | Low | `log 2.5` crashes with a raw Lua error | Confirmed in Ocelot |
| C3 | Medium | `passwd <user>` ignores the user and changes your own password | Confirmed in Ocelot |
| C4 | Low | `lua <code>` opens the REPL without running the code | Confirmed in Ocelot |
| C5 | Low | `rsh` code loses its quotes, and the manual calls it step-budgeted | Confirmed in Ocelot |
| D1–D8 | Low | Test and build tooling gaps on the published layout | Reproduced |
| E1–E9 | Nit | Docs, comments and repo hygiene | Mixed |
| F1 | Low–Medium | The OpenOS cluster worker cannot load on a Lua 5.2 CPU | Confirmed in Ocelot |
| F2 | Low | The rc-pilot robot EEPROM cannot load on a Lua 5.2 CPU | Reproduced with `luac5.2 -p` |
| G1 | Medium | An admin overwrites kernel files via `srm restore`, past the protected-core guard | Confirmed in Ocelot |
| G2 | Low | `backup` OOMs on trees far smaller than its design and docs imply | Confirmed in Ocelot |

Suggested order: G1 first (it defeats a stated security control), then A1 and A2 together, then A3 (same new API), then C3 and B1, then B2 with B3 and B7, then the rest.

---

## A. Services

### A1. `service stop` does not stick — High — Confirmed in Ocelot

**Where.** `tos/kernel/rc.lua`: `rc.stop` (line 601), `rc.supervise` (line 668), `rc.tryRestart` (line 637). The timer is `event.interval(30, …, "kernel:rc_supervise")` in `tos/kernel/init.lua:945`.

**What happens.** `rc.stop` sets `svc.running = false` and nothing else. `rc.supervise` restarts every service where `svc.restart and not svc.running and not svc.disabledAtBoot`. Nothing distinguishes "the operator stopped it" from "it crashed", so the next 30-second tick starts it again. Every shipped service declares `restart = true`: `10-discoveryd`, `20-chatrelay`, `20-fileshare`, `20-netfsd`, `20-rshd`, and `cluster-storaged` in TOS-Extras.

**What the user sees.** `service stop 20-rshd` prints `Stopped: 20-rshd`, the log says "exec requests now refused", and up to 30 seconds later the remote shell is armed again with only a log line (`Restarting service: 20-rshd (attempt 1)`). The same applies to file sharing and netfs. It only stays down after `maxRestart` restarts are used up, and that budget resets after `RESTART_DECAY` (600 s).

**On the real machine** (two networked machines): `service stop 20-fileshare` showed `stopped`, and about 25 seconds later the kernel log had `[39.5][INF][rc] Restarting service: 20-fileshare (attempt 1)`.

**End to end, with the remote shell** (two machines, mutually TRUSTED with `net trust 1 full`, machine 1 running `rsh 1 print(7000+777)` and waiting for each result):

| Machine 2 (target) | Machine 1 (`rsh`) |
|---|---|
| boot: `Service registered (disabled): 20-rshd` | `Error: Timeout waiting for response` (correct: off by default) |
| `service start 20-rshd` | `7777` |
| 78.2 s: `service stop 20-rshd` → "Stopped: 20-rshd"; log: "Remote shell daemon stopped (exec requests now refused)"; `service list`: `stopped` | at 81 s: `Error: Timeout waiting for response` (correct) |
| 99.5 s: log "Restarting service: 20-rshd (attempt 1)", "Remote shell daemon active"; `service list`: `running` | |
| 115.2 s: log "Executing remote command from ebbed854...", "Command finished (exit=0)" | `7777` |

Twenty-one seconds after the operator stopped it, with no further action on that machine, a peer was running code on it again.

**Why the suite misses it.** `test_rc_disabled.lua` covers "the supervisor must not resurrect a disabled service" and "a crash of an operator-enabled service is restarted", but never stop followed by supervise.

**Recommended fix.**

```lua
-- rc.stop, on success
svc.running = false
svc.operatorStopped = true     -- supervise() must not undo an operator's stop

-- rc.supervise
if svc.restart and not svc.running and not svc.disabledAtBoot
   and not svc.operatorStopped then
  rc.tryRestart(name)
end
```

`rc.start` normally replaces the record with a fresh one from `loadService`, which clears the flag by itself. Clear it explicitly on a successful start as well, for the branch where the old record is kept. The `check` hook path sets `running = false` without the flag, so real crashes still restart.

**Test to add** (in `test_rc_disabled.lua`): start a `restart = true` service, `rc.stop` it, call `rc.supervise()`, assert it is still stopped and `start` ran once. Then `rc.start` it, simulate a crash (`check` returning false), `rc.supervise()`, assert it restarted.

### A2. `rshd` cannot be turned off again persistently — High — Confirmed in Ocelot

**Where.** `tos/kernel/rc.lua:590-593` (inside `rc.start`), `etc/rc.d/20-rshd.disabled`, `tos/shell/panels/commands/admin.lua:3909-3956` (`C.service`).

**What happens.** `service start 20-rshd` deletes `/etc/rc.d/20-rshd.disabled` so the service auto-starts on later boots. That is intended and documented in the marker. But:

1. The marker's own text is the only place that explains how to turn it off again ("recreate this marker (touch /etc/rc.d/20-rshd.disabled)"), and `service start` has just deleted that file.
2. `service` has only `list | start <name> | stop <name>`. There is no `disable`.
3. `MANUAL.md` mentions `rshd` once (line 1933) and never mentions `.disabled`. README's "The remote shell is off by default" does not say that starting it is permanent.

4. The step the marker describes does not work as written. On the real machine, after `service start 20-rshd`, root's `touch /etc/rc.d/20-rshd.disabled` was refused: "Refused: writing to /etc is a protected system path … `protect off` stands the guard down for THIS SESSION ONLY … [E-402 ERR_PATH_PROTECTED]". The marker's text never mentions `protect off`.

So an operator who tries the remote shell once has it listening on every boot from then on, and `service stop` (see A1) does not even hold for the current boot.

**On the real machine:** after `service start 20-rshd` and `service stop 20-rshd`, `service list` showed `stopped`, then `running` 40 seconds later. After a power cycle `/etc/rc.d` held five scripts and no `20-rshd.disabled`.

Note that `rc.disable(name)` already exists (line 697) and **deletes the script**. Do not reuse that name for this.

**Recommended fix.**

- Add `rc.setBootEnabled(name, on)`: writes or removes `<full name>.disabled` and updates `svc.disabledAtBoot`.
- Add `service disable <name>` (stop if running, then `setBootEnabled(false)`) and `service enable <name>` (`setBootEnabled(true)`, does not start it). Update the usage line and `help`.
- After `service stop` on a service that will start again at boot, print one line: "Off until the next boot. `service disable <name>` keeps it off."
- Rewrite the tail of `20-rshd.disabled` to say `service disable 20-rshd`, and add the same to README "Known limitations" and the MANUAL's remote-shell section.

### A3. `pkg disable` leaves the package's service running — Medium — Confirmed in Ocelot

**Where.** `tos/kernel/pkg.lua:792-798` (`pkg.setEnabled`), `tos/shell/panels/commands/admin.lua:1383-1391`, against `usr/man/pkg.man:76-77` and `MANUAL.md:1048-1050`.

**What happens.** `pkg.setEnabled` writes one byte to the package's `state` file. Its own comment says "Service start/stop is the caller's responsibility … rc.d hooks (commit 2) will read it and act", but the caller (`pkg disable`) only prints `Disabled: <name>`, and `rc.lua` never reads the package state. It reads only the `.disabled` marker, which `service start` removed.

**What the docs promise.** `man pkg`: "Switch it off without removing it (its commands and its service stop; its files stay)". MANUAL: "a disabled package's commands and service stay dormant".

**Result.** After `pkg disable mail` the mail service keeps receiving, and it starts again at the next boot. This affects every service package: mail, intercom, the cluster packages, rbmk-controld.

**On the real machine:** `pkg install mail` from an add-on floppy, `service start mail`, `pkg disable mail`. `service list` showed `mail  running` straight away, 35 seconds later, and again after a power cycle. `pkg list` after the reboot showed `mail 1.0.1 service` with nothing to say it was disabled, which is worth fixing in the same change.

**Recommended fix.** In the `pkg disable` path, for each `/etc/rc.d/*.lua` the package owns: `rc.stop` it and call the new `rc.setBootEnabled(name, false)` from A2. `tos/kernel/pkgops.lua:895-934` already collects a package's rc.d stems and their markers for upgrades and can be reused. Decide what `pkg enable` does for the service (leave it off and say "`service start <svc>` to run it" is the conservative choice, matching `defaultState = "disabled"`), then make the man page and MANUAL say exactly that. Extend `test_pkg_service_enable.lua`.

---

## B. Installing (`bootstrap.lua`, `install.lua`, `init.lua`)

### B1. Ctrl+C at a y/n prompt answers yes — Medium — Confirmed in Ocelot

**Where.** `ask()` and `confirm()` in `bootstrap.lua:70-100` and `install.lua:87-118`.

**What happens.** OpenOS's `term.read()` returns `false` when the user presses Ctrl+C and `nil` on Ctrl+D (`lib/core/cursor.lua`: `elseif name == "interrupted" then self:echo("^C\n") return false, name`). `ask` then runs `if not answer or answer == "" then return default end`, and `confirm` passes `"y"` as the default. So the universal "get me out of here" key accepts the prompt.

**On real OpenOS** (1.8.9, with a TOS install disk): at `Continue? [y/n] (default: y):` I sent Ctrl+C. The screen showed `^C` and the installer went straight on: "Kept the previous /init.lua as /init.lua.pre-tos", "Creating directories", "Copying system files".

**Prompts affected.**

| Prompt | File:line | Effect of Ctrl+C |
|---|---|---|
| "Download TOS from the internet and run the installer?" | `bootstrap.lua:405` | Starts the download |
| "Continue?" | `install.lua:1464`, `1552` | Replaces `/init.lua` and copies TOS |
| "Remove OpenOS leftovers for a clean install?" | `install.lua:1536` | Queues deletion of `/bin`, `/boot`, `/lib` |
| "Apply these settings?" | `install.lua:1587` | Writes the config |
| "Boot from the TOS drive from now on?" | `install.lua:1654` | Rewrites the EEPROM boot address |
| "Reboot now?" | `install.lua:1743` | Reboots |
| "Trust the Optional Utilities publisher?" | `install.lua:1254` | Trusts the key |
| Old-system choice (default "2") | `install.lua:1521` | Moves the old system into `/openos` |

The two typed confirmations (`FORCE-WIPE`, `flash`) use `io.read() or ""` and are safe. The comment at `install.lua:1556-1560` talks about a user pressing Ctrl+C during the questionnaire, so an abort is clearly the intended meaning.

**Recommended fix.** In both files make `ask` return `nil, "interrupted"` when `term.read` fails, returns `false`, or returns `nil`, and return the default only for an empty line. `confirm` then returns false. For the non-confirm asks (device type, hostname, drive number) a nil must cancel the install, not loop: `chooseTarget` and `chooseConfigTarget` currently answer "Type a number from the list." forever on a nil. The simplest shape is one cancel path: a sentinel raised from `ask` and caught around the main flow, printing "Cancelled." and returning. `bootstrap.lua` calls the installer with `pcall(chunk, …)` and must treat that sentinel as a cancellation, not as "install.lua exited with an error".

**Worth deciding at the same time.** `confirm` always defaults to yes, so pressing Enter through the installer removes OpenOS (line 1536) and turns on verbose boot with debug messages (line 1287). Giving `confirm` a default parameter and defaulting the destructive and optional ones to no is a small change.

**Test.** `ask` is not `TEST-EXTRACT`ed today. Mark it, or split the "what does this raw read result mean" decision into a small pure function and test `false`, `nil`, `""` and `"y\n"`.

### B2. A failed staging write is counted as a download — Low–Medium — Confirmed in Ocelot

*Revised in the second pass. The first pass said this leaves an empty file in the installed system. With today's file order it does not; it produces a misleading failure. The mechanism is as first described.*

**Where.** `bootstrap.lua:793-796`:

```lua
local f = io.open(stagingDir .. path, "w")
if f then
  f:write(body); f:close()
  copied = copied + 1
```

**What happens.** On OpenComputers a write is all-or-nothing: `Capacity.scala`'s `CountingOutputHandle.write` throws "not enough space" when the whole chunk does not fit, and opening a new file only needs the 512-byte `fileCost`. OpenOS passes the whole body to the component in one call and turns the failure into `nil, "not enough space"`; `buffer:close()` discards the result of its own flush. So when a file does not fit, `io.open` succeeds, `f:write` fails silently, a 0-byte file is left behind and `copied` goes up. The existing out-of-space handling only triggers when `io.open` itself fails.

**On real OpenOS** (2 MB boot drive, padded to leave 1370 KB free, about 15 KB short): the bootstrap printed "Downloading 172 files", reported no failure and handed off to the installer. The staged `tos/system_manifest.lua` was 0 bytes (checked on the kept disk). The installer then printed:

```
  + Kept the previous /init.lua as /init.lua.pre-tos
  X Cannot load install manifest: manifest did not return a table
  X Install file copy/verify did NOT fully succeed.
  ! You can retry installation; the partial files won't conflict.
```

with 6 KB free on the drive. Disk space is never mentioned, a retry cannot work, and the bootstrap's own OUT OF SPACE exit, which explains the remedy well, is never reached.

**How wide the window is.** I simulated the download loop against a release built from this tree for every amount of free space:

| Free space | Outcome |
|---|---|
| 1412 KB or more | Clean |
| 1408–1412 KB | Only `/bios.lua` is empty; the installer says "Empty bios.lua" and carries on (harmless) |
| 1379–1408 KB | The manifest (and below 1385, `ru.lang`) is empty; hand-off, then the manifest error above |
| Under 1379 KB | The proper OUT OF SPACE exit |

It is not a silent bad install today only because the last sizeable file in download order is the manifest itself, which the installer cannot do without. If a future manifest ends with a different large file, that file would be installed empty and `verifyCopy` (0 bytes against 0 bytes) would call it verified. `install.lua`'s `copyFileChunked` (line 410) was already fixed for this class ("AUDIT 5"); the bootstrap is the twin that was missed.

**Recommended fix.**

```lua
local staged = stagingDir .. path
local f = io.open(staged, "w")
local wrote = false
if f then
  local okW, res = pcall(f.write, f, body)
  local okF, resF = okW and res, okW and res
  if okW and res and f.flush then okF, resF = pcall(f.flush, f) end
  pcall(f.close, f)
  wrote = okW and res and okF and resF and (fs.size(staged) or -1) == #body
end
```

On failure, remove the partial file and treat `freeSpace(stagingDir) < #body + 512` as the out-of-space case (the current `freeNow < 4096` test is too narrow for a 100 KB file). As a second line of defence, have `install.lua` refuse a 0-byte source for any manifest entry.

**Test.** `test_install_bootstrap.lua` with a fake file handle whose `write` returns `nil, "not enough space"`.

### B3. The bootstrap's space estimate is about to be too low — Low — Measured

*Corrected in the second pass. The first pass said 1447 KB; that double-counted `/install.lua`, which is already a manifest entry.*

**Where.** `bootstrap.lua:710`: `local NEED_BYTES = 1400 * 1024`.

**Measured.**

- A release built from this tree stages 174 files in 13 directories: 1,349,765 bytes, or **1,446,021 bytes (1412 KB)** with OpenComputers' 512 bytes per file and directory. That is 12 KB over the threshold.
- The published `main` release today (171 files) used about 1385 KB of staging in Ocelot, so the threshold still holds for it, by about 15 KB.

So the warning is correct today and stops being correct at the next release from this tree. In the gap, a drive gets no warning and lands in B2's window.

The surrounding text is stale: comments at lines 646, 680 and 1025 say "~1.2 MB across 152 files".

**Recommended fix.** Raise it to 1536 KB, update `printHelp` (line 333) and `MANUAL.md:228` from "about 1.4 MB" to "about 1.5 MB", and correct the comments. `MAX_FILE_BYTES` already has a test that measures the real release (`test_install_bootstrap.lua`); give `NEED_BYTES` the same, summing sizes plus 512 per entry, so it cannot drift again.

### B4. A Lua 5.2 CPU: the bootstrap dies with a traceback, the installer installs anyway — Low–Medium — Confirmed in Ocelot

**Where.** `bootstrap.lua:505-540` (`sha256hex` uses `>>`, `~`, `&`, `|`); `install.lua`'s `printHardwareReport` (line 287).

**Reproduce off-box.** `luac5.2 -p bootstrap.lua` gives `bootstrap.lua:517: unexpected symbol near '>'`. `init.lua`, `bios.lua` and `install.lua` all parse under 5.2, in source and in the release build.

**On a real Lua 5.2 machine** (OpenOS 1.8.9, whose `lua` prompt confirmed "Lua 5.2"):

1. `bootstrap.lua` ends in a raw error and a nine-line traceback:

   ```
   /lib/process.lua:52: /mnt/d15/bootstrap.lua:127: unexpected symbol near '>':
   stack traceback:
           machine:823: in function 'errorCapture'
           ...
   ```

2. `install.lua` runs. Its hardware report lists RAM, GPU, disk, network and crypto and says nothing about the CPU. The install completes with "TOS is installed! Reboot to start." and, on the default answer, moves OpenOS's 178 files into `/openos`.
3. After the reboot the machine stops: at the BIOS's C1 if the TOS BIOS was flashed, or at `init.lua`'s screen (B6) if it was not.

So the one place the problem could be named before anything is changed, the installer, is the one place that is silent. `bios.lua` and `init.lua` both go out of their way to say it ("stop HERE with the fix instead of booting into a raw syntax-error panic"). OpenComputers defaults to 5.3 (`defaultLua53: true`, checked in 1.7.5 and 1.8.10), so this hits switched CPUs and servers with an older config.

**Recommended fix.**

- `install.lua`: probe with `load("return 1<<1")` in `printHardwareReport` and refuse to copy on 5.2, with the fix from B6. This is the cheap half and the one that protects the user's existing system.
- `bootstrap.lua`: keep it 5.2-parseable the way `init.lua` is. Probe right after the helpers and stop with the same message; compile the 5.3-only code from a long string with `load`. `sha256hex` and `verifyRelease` carry `--[[TEST-EXTRACT]]` markers, so `test_install_bootstrap.lua` has to follow whatever shape is chosen.
- `test_bios.lua` pins the probe in the two boot files; extend it to these two, and add a scan for 5.3 operators outside the loaded string, since CI has no Lua 5.2. The runner patch in the appendix makes all of this testable on a machine.

### B5. The bootstrap never removes itself — Low — Confirmed in Ocelot

**Where.** `bootstrap.lua:1004`: `local self = selfPathToReclaim((arg and arg[0]) or nil)`.

**What happens.** OpenOS does not define a global `arg`. `lib/process.lua`'s `process.load` passes arguments as `...` and records the script with `os.setenv("_", program)`. So `arg` is nil, `selfPathToReclaim(nil)` returns nil, and `/bootstrap.lua` stays on the disk after every network install. The "Removed /bootstrap.lua" line can never print. `install.lua:200` already uses `os.getenv("_")` for the same purpose, and the bootstrap's own comment at line 949 mentions the convention.

**On real OpenOS:** after a complete network install of the published release (declining the reboot so the disk could be listed), `ls /` still showed `bootstrap.lua`. The installer's own "Removed the download at /home/tos-netinstall" worked.

**Why the suite misses it.** The tests call `selfPathToReclaim` with strings directly. Stock Lua defines `arg`, OpenOS does not. `test_install_bootstrap.lua:287` even asserts the source contains `arg and arg[0]`.

**Recommended fix.** `selfPathToReclaim((os.getenv and os.getenv("_")) or (arg and arg[0]) or nil)`. `os.getenv("_")` is the resolved absolute path, so the root-only guard still protects the OPPM copy in `/usr/bin`. Update the assertion at line 287.

### B6. The Lua 5.2 screen gives an instruction that does not work — Low — Confirmed in Ocelot

**Where.** `init.lua:49-53`.

**What it says.** "Fix: sneak-click (crouch + right-click) the CPU in its computer-case slot to cycle architectures, then reboot."

**What is true.** OpenComputers changes the architecture in `CPULike.onItemRightClick` when `player.isSneaking`: the CPU has to be **held in the hand** and used while sneaking. Shift-clicking it in the case's slot just moves it to the inventory. The README, MANUAL and BIOS say "sneak-click the CPU", which is vague but not wrong.

Two of those lines are also 54 and 55 characters, drawn from column 2, so a Tier 1 screen (50 columns) cuts them off. On a real Lua 5.2 machine with a Tier 1 GPU and screen it reads:

```
 TOS requires the Lua 5.3 or 5.4 CPU architecture.
 This CPU is running an older one (Lua 5.2).
 Fix: sneak-click (crouch + right-click) the CPU i
 computer-case slot to cycle architectures, then r
 Press any key to power off.
```

(The screen itself was seen in Ocelot; that the instruction is wrong comes from OpenComputers' source, since the emulator has no player to sneak.)

**Recommended text** (each line under 48 characters):

```
TOS needs the Lua 5.3 or 5.4 CPU architecture.
This CPU is set to Lua 5.2.
Fix: take the CPU out, hold it, and sneak +
right-click until it says Lua 5.3. Put it back.
Press any key to power off.
```

Consider the same wording in README line 81 and `MANUAL.md:204`.

### B7. The bootstrap warns it will run out of space, then carries on — Low — Confirmed in Ocelot

**Where.** `bootstrap.lua:731-738`.

**What happens.** With less than `NEED_BYTES` free it prints "That is under the ~1400 KB the release needs. The download will likely run out of space partway through. Free some room, or install from a disk instead. Continuing." and starts a two-minute download it has just predicted will fail. In the B2 run that is exactly what happened.

**Recommended fix.** Ask instead of continuing: "Download anyway? [y/N]", defaulting to no. The comment says the figure is "a floor for WARNING only, never a refusal" so that an unusual layout is not blocked; a question keeps that door open without wasting the download.

---

## C. Commands

### C1. `cron add` with a fractional interval — Low — Confirmed in Ocelot

**Where.** `tos/kernel/cron.lua:117-119` (`cron.add`'s validation), `216-226` (store and save), `229` (log line); `tos/shell/panels/commands/admin.lua:4002`.

**What happens.** `cron.add` accepts any positive number. It stores and saves the job and then logs with `string.format("… (every %ds, …)", intervalSec)`. For `1.5` that raises "number has no integer representation". The command reports an error, but the job exists and runs. A user who retries with a whole number ends up with two jobs.

**On the real machine:** `cron add job 1.5 print(1)` printed `Error: /tos/kernel/cron.lua:50: bad argument #3 to 'format' (number has no integer representation)` (the line number is the minified build's), and `cron list` then showed `1  job  1.5s  yes`.

The scheduler ticks every 10 seconds (`cron.lua:89`), so an interval under 10 means "every tick" in any case.

**Recommended fix.** Validate before storing: a whole number of seconds, at least 1, and say in the usage text that jobs are checked every 10 seconds. Add a case to `test_cron_add_report.lua`.

### C2. `log <n>` with a fractional count crashes — Low — Confirmed in Ocelot

**Where.** `tos/shell/panels/commands/admin.lua:2252` and `2283-2291` (`C.log`).

**What happens.** `local first = (n and n > 0 and #lines - n + 1) or 1` is fractional when `n` is, so `lines[i]` is nil for every `i` in the loop and `line:find` raises. On the real machine `log 2.5` printed `Error: /tos/shell/panels/commands/admin.lua:992: attempt to index a nil value (local 'aM')`.

`log ring 2.5` does not crash but answers "(no log entries in ring)" when the ring is not empty. `log denied 1.5` is harmless.

**Recommended fix.** One small helper for "a whole number from the command line" (reject or floor, with a range), used by `log`, `log ring`, `log denied` and `cron add`. `redstone set` (`extras.lua:106-111`) already validates this way and is the pattern to copy.

**Also tried on the real machine and fine:** `watch 1.5 df`, `tree / 1.5`, `date tz 2.5` (half-hour offsets are legitimate), `kill 1.5`, `menu remove 1.5`, `screen 1.5`. I did not trace every numeric argument to its last use.

### C3. `passwd <user>` changes your own password — Medium — Confirmed in Ocelot

**Where.** `tos/shell/panels/commands/core.lua:2844-2868` (`C.passwd`), against `MANUAL.md:2981-2983`.

**What happens.** `C.passwd` never reads `args`. It always prompts "Current password:", "New password:", "Confirm new password:" and calls `U.changePassword(w2, w2, old, new)` for the caller. The manual's command reference says: "**passwd** — `passwd [user]` (other users: admin). Change your password (or another user's, as admin)." `MANUAL.md:460` and the `help` text say "change your own", so the manual disagrees with itself.

**On the real machine**, as root: `useradd alice`, then `passwd alice`. The prompts name no account. I gave root's current password and a new one; it answered "Password changed." Logging in as alice with the new password then failed. `passwd nobody`, for an account that does not exist, also ends in "Password changed."

**Why it matters.** An admin resetting a locked-out user's password by the book changes their own password to the one they meant for the user, and nothing on screen says so. There is also no shell command that resets another account's password, although the kernel supports it: `users.changePassword` (`tos/kernel/users.lua:782`) lets an admin change any account that does not outrank them, without the old password.

**Recommended fix.** Implement the documented form. With `args[1]` naming another account: skip the current-password prompt, prompt "New password for <user>:" and its confirmation, and call `U.changePassword(self, args[1], nil, new)`; the kernel already enforces tier and rank and returns "User not found". Name the account in every prompt in both forms ("New password for root:"). Pass on the keychain note `changePassword` returns, since an admin reset cannot re-key the user's keychain. Then make `MANUAL.md:460`, the reference entry and `help` agree. Add a test beside `test_keychain_rekey.lua`.

### C4. `lua <code>` opens the REPL without running the code — Low — Confirmed in Ocelot

**Where.** `tos/shell/panels/commands/admin.lua:2486` (`C.lua`), against `MANUAL.md:2324-2335` (§13.1 "One-liners with `lua`") and `MANUAL.md:2810-2813`.

**What happens.** The manual documents `lua <expression-or-statement>` with three examples (`lua 2^16`, `lua print(("hello"):upper())`, `lua for i=1,3 do print(i) end`). `C.lua` never reads `args`. On the real machine `lua print(math.pi)` opened the REPL at an empty `>` prompt and printed nothing. `help` and the command registry describe only the REPL.

§13.1 also says two different things about the environment: "The REPL has full `_ENV` access" and, two paragraphs later, "It runs in the sandbox of your session — you get a safe `_G`".

**Recommended fix.** Either implement one-liners (join the arguments, try `return <code>` first and then the statement form, print the results; mind that the shell's tokenizer has already split and unquoted the line, so use the raw command text if the executor can supply it), or remove §13.1's one-liner form and the example in the reference. Settle the environment sentence either way.

### C5. `rsh` code loses its quotes, and the manual calls it step-budgeted — Low — Confirmed in Ocelot

**Where.** `tos/shell/panels/commands/extras.lua:1819-1832` (`C.rsh`, `C.ssh`), `tos/shell/panels/executor.lua:89` (`tokenize`), `MANUAL.md:3060-3064` and `1931`.

**Quotes.** `C.rsh` rebuilds the Lua chunk with `table.concat(args, " ", 2)`, after the shell's tokenizer has already treated `"` and `'` as shell quotes and removed them. `rsh 1 print("RESULT-"..(1+2))` reached the peer as `print(RESULT-..(1+2))` and failed with `Load error: remote:1: unexpected symbol near '..'`. Wrapping the whole chunk in single quotes works (`rsh two 'print("hi")'`), but nothing says so: the manual's only example, `rsh two print(1+2)`, has no string in it, and the usage line is the same. Either pass the unparsed remainder of the line to `rsh` (the executor would need to provide it; C4's `lua <code>` needs the same thing), or document the single quotes in the usage line and the manual.

**"Step-budgeted".** The manual twice describes `rsh` as running "in a step-budgeted sandbox" (`MANUAL.md:1931` and `3061`). On the real machine the target logs, for every command: "debug.sethook is unavailable here (OpenComputers does not expose it): remote commands run with NO step or memory budget." `service start 20-rshd` already warns about this, and README "Known limitations" says TOS cannot stop a runaway program. Make the two manual sentences say the same.

---

## D. Test and build tooling on the published layout

### D1. `run_tests.sh` is red on a fresh clone and skips every add-on test — Reproduced

`bash run_tests.sh` on a clean checkout of `dev`: `PASS=416 FAIL=1`, exit 1.

- **Line 77**: `EXTRAS="$DEV_DIR/../TOS-Extras"` has no fallback to the nested `TOS-Extras/`, so none of the 72 add-on test files run. `run_tests.py` has that fallback (`_NESTED_EXTRAS`).
- There is no rule for a missing `Reference/` tree, so `test_component_api.lua` fails where `run_tests.py` skips it.

CONTRIBUTING calls this script the no-Python fallback and its header calls it "the definition-of-record". Port the two rules from `run_tests.py`. It is also committed without the executable bit (see E4).

### D2. `run_tests.py` mislabels its skips — Reproduced

Lines 372-399. With `Reference/` absent, every skip is printed as `SKIP(needs Reference)=6` and the note says "6 test(s) that check component calls against it were skipped". Only `test_component_api.lua` needs `Reference/`. The other five skip for their own reasons: no built `TOS-Release` (two tests), no built pack, no `TODO.txt` (two tests). Count the Reference skips separately; the per-test `SKIP:` lines already carry the real reasons.

`CONTRIBUTING.md` and `.github/workflows/ci.yml` both say "two tests" need `Reference/`. It is one.

### D3. `test_addon_versions.lua` never checks the picker here — Reproduced

`TOS-Extras/build/test_addon_versions.lua:122` looks for `../TOS-Dev/tos/shell/pkgpicker.lua` and `TOS-Dev/tos/shell/pkgpicker.lua`. In the published layout the file is at `../tos/shell/pkgpicker.lua`, so the test prints "no TOS-Dev beside TOS-Extras; the picker is not checked" and passes. Add the third candidate.

### D4. CI never runs the release checks

`ci.yml` runs only `python3 run_tests.py`, so `test_manifest_digests.lua` and `test_release_budget.lua` always skip there ("no built TOS-Release"). `python3 tos.py build` works on a bare runner with just Lua and Python and took under a minute here; with it both tests run and pass. Adding it as a step before the suite closes that gap, as long as the build writing to `../TOS-Release` is acceptable on the runner.

### D5. Misleading skip message

`usr/lib/tests/test_untrusted_index_budget.lua:71` and `:122` print "SKIP: TOS-Extras is not beside TOS-Dev" when what is missing is the built pack (`TOS-Extras/dist/optional-utilities/programs.cfg`). TOS-Extras is present.

### D6. `tos.py pack` fails at its second step — Reproduced

`python tos.py pack` builds the two add-on disks and then stops with `error: cannot load kernel.serialize from the sibling TOS-Dev tree`. `TOS-Extras/build/make-repo-index.lua:51` only adds `EXTRAS/../TOS-Dev/tos/?.lua` to `package.path`. `build-disk.lua` and `sign-package.lua` beside it already try both layouts (`../TOS-Dev/tos/` and `../tos/`). So on a clone of `dev` the repo index cannot be built, and `test_repo_index.lua`'s skip message ("run: lua build/build-disk.lua && lua build/make-repo-index.lua") names a command that fails. Add the nested path.

### D7. The add-on pack's output is not ignored

`.gitignore` lists `TOS-Release/` but not `TOS-Extras/dist/`. After `tos.py pack` or `build-disk.lua` on the published layout, `git status` shows `TOS-Extras/dist/` as untracked. Add it.

### D8. `floorcheck.py` never checks the panels' free-memory figures — Confirmed in Ocelot

`build/floorcheck.py` compares each case's free memory with the README by reading `mem`'s output for `used, NNNK` (`free_kb`, line 153). Its machines use the T1 profile, whose 50-column screen leaves the panels' output area one line tall: only `=== Memory ===` is visible, the regex finds nothing, and the three panels cases (1.5 MB, 1.5 MB with a network card, 2 MB) print a blank "free" column every run. So the README's "about 330 KB", "about 175 KB" and "about 800 KB" are never compared with anything. The command-line cases read fine.

The panels' status bar shows the same number (`draw.lua:368`, `computer.freeMemory()`), and it is on the snapped screen: `Memory:401K`. Fall back to `Memory:(\d+)K` when `used, NNNK` is not found.


---

## E. Docs, comments, hygiene

**E1. PR template contradicts CONTRIBUTING.** `.github/PULL_REQUEST_TEMPLATE.md` asks for "`--!` marker so the release build keeps them". CONTRIBUTING's comment table says `--!` survives only in the rc.d scripts and as licence notices. One of them is out of date.

**E2. Lua 5.4 is off by default in OpenComputers.** README line 81, `MANUAL.md:204` and the OPPM note say to sneak-click the CPU to choose 5.3 or 5.4. In OC 1.8.10's `application.conf`, `enableLua54` is `false`, so 5.4 is not offered unless the server enables it. One clause would save a confused report.

**E3. Two comments disagree about a platform fact.** `bootstrap.lua:671-683` says OpenComputers' filesystem `remove` does not recurse. `install.lua:1044` says it does. The component's `remove` callback recurses in both 1.7.5 and 1.8.10 (`FileSystem.scala`, `def recurse`). `removeTree` is harmless either way. If the non-recursive behaviour was seen on Ocelot, the comment should say so; otherwise the bootstrap's leftover-staging history is fully explained by the installer rebooting before the cleanup ran.

**E4. Shell scripts are not executable.** `run_tests.sh`, `build/build-release.sh` and `TOS-Extras/build/build-disk.sh` are mode 100644. `git update-index --chmod=+x`, or document `bash run_tests.sh`.

**E5. Byte-order marks.** `.github/PULL_REQUEST_TEMPLATE.md` and `.gitignore` start with a UTF-8 BOM. Git tolerates it in `.gitignore`; both are probably from a Windows editor.

**E6. `cluster-worker-setup.lua` (runs on OpenOS).** `TOS-Extras/cluster/openos/cluster-worker-setup.lua`:

- Lines 345-348, `ctx.ask`: tests `s == nil` only, so Ctrl+C (`io.read()` returns `false`) reaches `s:gsub` and dies with "attempt to index a boolean value". Use `if not s`.
- Lines 360-363, `ctx.writeFile`: `h:write(data)` is unchecked, the same class as B2. On a full disk an empty temp file is renamed over the worker's config, which the "temp + rename" comment says cannot happen.
- Line 335, `if not (...)`: any command-line argument, including `--help`, makes the script do nothing and print nothing.

**E7. Small things seen during the real network install.**

- After the installer prints "Removed the download at /home/tos-netinstall", the bootstrap prints "Removed the staging copy (2218 KB free now)" for the same directory when the user declines the reboot. `removeTree` returns true for a path that is already gone.
- "A TOS BIOS was found on the install disk." appears during a network install, where there is no disk.
- README step 6 reads "`theme list`, then `theme set midnight`". `theme list` (like `help`) opens a viewer tab, and what is typed next goes to the viewer until it is closed with Ctrl+Q. The footer says so, but a first-time user following the README literally will type into the viewer. "`theme list` (Ctrl+Q closes it)" would cover it.

**E8. Small things from a sweep of about 120 commands with missing or wrong arguments on the real machine.** No raw Lua error apart from C1 and C2; refusals were worded and coded throughout.

- `userdel nobody` shows the red "Delete the account 'nobody'?" confirmation before finding out the account does not exist (`admin.lua:3200-3225`). Check first.
- `log filter net 9` is accepted ("Source 'net' now logs at 9+"). Levels run 0 to 4, so this silences the source with no hint.
- `verify` takes over the screen for about half a minute on a 4 MB install; keys typed meanwhile are lost.

**E9. The README's free-memory figures.** Measured on Tier 1 machines in Ocelot, a fresh install, logged in, after one command, as the README describes:

| README | Says | Measured | Runs |
|---|---|---|---|
| 1 MB | "About 65 KB stays free" | 4, 32, 41, 46, 3 KB | 5 |
| 1.5 MB | "about 330 KB free after you log in" | 401, 403, 403 KB | 3 |
| 1.5 MB with a network card | "with about 175 KB free" | 219, 220, 220 KB | 3 |
| 2 MB | "about 800 KB free after you log in" | 915, 913, 915 KB | 3 |

The panel figures are conservative by 45 to 115 KB and steady. The 1 MB figure is the one that matters: it is optimistic, and two of five runs left under 5 KB, which is on the edge of not working. "Very little stays free (often under 50 KB)" would be honest. `floorcheck.py` flags the 1 MB reading as "differs" but cannot see the other three (D8).

---

## F. Add-ons that run outside TOS

### F1. The OpenOS cluster worker cannot load on Lua 5.2 — Low–Medium — Confirmed in Ocelot

**Where.** `TOS-Extras/cluster/openos/cluster-worker.lua:59` (`rrot`) and 20 more lines of bitwise-operator syntax in its SHA-256 and HMAC.

**What happens.** The worker is the part of the cluster meant for "cheap OpenOS worker" machines, and its own code plans for Lua 5.2 ones. The comment at lines 444-452 reads: "OpenComputers offers both architectures and OpenOS runs on either, so a worker and a Manager on different CPUs canonicalize the same frame differently", and the ping handler floors a number for that reason. But the file cannot be parsed on 5.2 at all. On real OpenOS:

| CPU | `cluster-worker.lua` |
|---|---|
| Lua 5.2 | `/lib/process.lua:52: /mnt/e7a/cluster-worker.lua:59: unexpected symbol near '>':` and a traceback |
| Lua 5.3 | starts (here: "cluster-worker: no modem component available") |

`cluster-worker-setup.lua`, the wizard that installs it, does parse on 5.2, so setup succeeds and the worker then fails to start. Neither `TOS-Extras/cluster/README.md` nor the installer's README states a Lua requirement.

**Recommended fix.** Decide which is true. If workers must be 5.3 or later: say so in the README, have `cluster-worker-setup.lua` refuse on 5.2 with the same probe and message as B4, and delete the 5.2 reasoning from the ping comment. If 5.2 workers are wanted: OpenOS on 5.2 has `bit32`, so the SHA-256 can pick `bit32` or the operators at load time, with the operator form compiled from a string.

### F2. The rc-pilot robot EEPROM cannot load on Lua 5.2 — Low — Reproduced with `luac5.2 -p`

`TOS-Extras/robot/eeprom-rc-pilot.lua:42` uses the same operators (`unexpected symbol near '>'`). A robot's CPU can be on 5.2 like any other, and an EEPROM that does not parse gives no screen and no beep code of its own. `TOS-Extras/robot/README.md` does not mention the requirement. State it there, and consider a one-line 5.2-safe prologue that beeps a recognisable pattern before the 5.3 code is loaded from a string. Not run on a machine: the session tool's `--chip` robot was not combined with the architecture patch.

The other scripts that run outside TOS parse on 5.2: `cluster-worker-setup.lua`, `rbmk/openos/rbmk-display.lua`, `cluster-install.lua`, `cluster-make-floppy.lua`.

---

## G. Backup and SRM

### G1. An admin overwrites kernel files via `srm restore`, past the protected core — Medium — Confirmed in Ocelot

**Where.** `tos/kernel/srm.lua`: `srm.restore` (line 634), `writeSafely` (line 377), `srm.deps` (line 103, `fs = TOS.fs`). `_G._TOS.fs` is the raw `kernel.fs` (`tos/kernel/init.lua:1061`), which has no permission model and no protected-path guard — those live only in `securefs`. The command is `tos/shell/panels/commands/admin.lua:1663` (`srm restore`), gated `adminOnly`.

**The claim it breaks.** The protected-core guard is described in `MANUAL.md:832-837` as "defence-in-depth against a *tampered admin session*, not an ACL — it sits above the permission model and refuses regardless of tier," and on screen as "stops even an admin overwriting the kernel or its libraries. Only root can lift it, with `protect off`." The README lists among its security properties a capability sandbox "that user programs cannot escape" and a kernel no one but root can write.

**What happens.** `srm restore <path> --source <dir> --unverified`, as an ADMIN (not root):
- takes any `<path>` the caller names (the parser puts every non-flag word after the verb into `paths`, and restore uses them directly — it is not limited to baselined files);
- with `--unverified` and no baseline, skips the "must match the baseline hash" check;
- reads `<dir><path>` and writes it to `<path>` through `writeSafely` → `kernel.fs.writeFileAtomic`, which never consults securefs.

So the guard is never reached. `srm repair --restore --source <dir> --unverified` is the same, since `repair` calls `restore` with those options.

**On the real machine**, logged in as an admin named bob:
- `touch /tos/kernel/proof.lua` → refused: "writing to /tos is a protected system path ... stops even an admin ... Only root can lift it. [E-402]".
- `cp /tos/kernel/display.lua /home/bob/ec/tos/kernel/clipboard.lua`, then `srm restore /tos/kernel/clipboard.lua --source /home/bob/ec --unverified` → "restored /tos/kernel/clipboard.lua from /home/bob/ec (UNVERIFIED), 1 fixed". `head -1 /tos/kernel/clipboard.lua` afterward showed `display.lua`'s first line: the kernel module held attacker-chosen bytes.
- For contrast, `backup restore` of the same payload into `/tos` was refused for every file — "could not be written: Refused: writing to /tos is a protected system path" — because `backup` writes through `securefs` (`tos/kernel/backup.lua`: `securefs.writeFile`). Same tier, same target, opposite outcome: the guard works when the write goes through securefs, and SRM is the one writer that goes around it.

**Why it matters.** `/tos/kernel/init.lua` and every module it loads run as the kernel, before login. An admin who can put arbitrary bytes there runs code as the kernel on the next boot — the escalation the protected core exists to stop. Admin is already a high-trust tier, and the README's "boot files are not signed" limitation already concedes a lot to admins, which is why this is Medium rather than High; but the control is advertised specifically as holding against a tampered admin, and here it does not.

**Recommended fix.** SRM legitimately must write `/tos` for its core job (putting a drifted critical file back), so the fix is not "route everything through securefs" — that would block the repair SRM exists to do. Options, roughly in order:
- Make the dangerous combination need root: a `restore`/`repair --restore` that would write a path under the protected core (`/tos`, and the protected parts of `/etc`, `/usr`, `/var`) requires either ROOT or an active `protect off` in the session, the same bar a direct write faces. A baseline-verified restore of a critical file by an admin could stay allowed, since its content is pinned to the baseline hash; it is `--unverified` and caller-named paths that need the higher bar.
- At minimum, refuse `--unverified` writes to protected paths unless root, and refuse caller-named `paths` that are not in the baseline.
- Have `srm.restore`/`writeSafely` go through `securefs` with the session when one is present, and fall back to raw `kernel.fs` only on the pre-kernel recovery path (`recovery.lua` already builds its own raw fs over the proxy, so the boot path is unaffected).
- Whatever the choice, reword the protected-core text if admins are meant to have any kernel-write path at all.

A test belongs beside `test_srm_*`: an admin session (a securefs stub that refuses `/tos` writes) must not be able to land a file under `/tos` through `srm.restore`.

### G2. `backup` runs out of memory on trees far smaller than it implies — Low — Confirmed in Ocelot

**Where.** `tos/kernel/backup.lua`: `encodeSnapshot` (line 146) and `backup.restore` (line 314); the caps `MAX_ENTRY_BYTES = 1 MB` and `MAX_TOTAL_ENTRIES = 4096` (lines 44-45).

**What happens.** The module header says the binary format exists so it "doesn't depend on the OPPM/serialize size for big trees" and does not OOM "on T1.5 boxes for trees more than a few MB." In fact `encodeSnapshot` reads every file whole into `data`, accumulates all of them in `bodyParts`, `table.concat`s that into `body`, then builds `parts` and concats again — several copies of the whole tree in RAM at once — and `restore` reads the entire backup file into one string. Measured on booted machines, a folder snapshot (free RAM at the time in parentheses):

| Machine | Largest tree that snapshotted + restored | Next size up |
|---|---|---|
| 1.5 MB (two T3 sticks) | 50 KB (88 KB free) | 100 KB → `Error: not enough memory` |
| 2 MB (two T3.5 sticks) | 200 KB (742 KB free) | 400 KB → `Error: not enough memory` |

So the practical ceiling is a fraction of free RAM and nowhere near "a few MB"; the 1 MB-per-file and 4096-entry caps describe trees that cannot be built on any real machine. It fails safe — nothing is written, and the snapshot is refused — but the error on the 1.5 MB box is a raw `Error: /tos/kernel/backup.lua:34: not enough memory for buffer allocation`, a file and line rather than "this tree is too large for free memory."

**Recommended fix.** Lower expectations or raise the ceiling. The honest-cheap option: document a realistic limit (roughly "a tree up to about a quarter of free memory") and catch the OOM so the command says that instead of a Lua line number. The real fix is to stream — write entries to the destination file as they are read instead of building the whole blob, and verify the restore as it reads rather than slurping the file — which is what the header already claims the format was designed for. Either way, correct the module header and `man backup`.

## Checked and found fine

So the next session does not repeat it:

- `actions/checkout@v7` and `github/codeql-action@v4` exist as tags. Workflow permissions are minimal, and `issue_triage.py` runs from the base branch with `persist-credentials: false`.
- No CRLF line endings; every tracked text file is valid UTF-8.
- README memory and drive figures match OpenComputers' defaults (`ramSizes`, `hddSizes`, `tmpSize`). "15 OpenOS libraries" matches `OPENOS_SHIMS`. "Nine colour themes" matches `kernel.theme`.
- Every command in README's "Your first ten minutes" is registered, and `pkg repo`, `pkg search`, `pkg fetch` exist.
- `init.lua` and `bios.lua` parse under Lua 5.2 as their guards require, in source and in the release build. The built `bios.lua` is 3847 bytes.
- `bios.lua`: boot-device selection, the `SKP:` skip, the fallback approval and the K4 rule all read correctly.
- `init.lua`'s floppy-to-drive copy checks every write and verifies before touching the EEPROM.
- `users.login`: no username or lock-state oracle, and the cooldown path does not inflate the failure count.
- Kernel-tier services get `_TOS` through a read-only proxy, so the `_G._TOS` use in `20-rshd`, `20-fileshare`, `20-chatrelay` and `10-discoveryd` is valid.
- `build/oppm/programs.cfg` is consistent with its README.

## Not covered

This was two passes over a repository of about 250,000 lines. No finding in an area below means I did not look closely, not that it is clean.

- **Not read line by line**: `kernel/sandbox.lua`, `securefs.lua`, `pkgops.lua`, `pkgremote.lua`, the whole `kernel/net/` tree, `crypto` and the Ed25519 code, `process.lua`, `screen.lua` and `display.lua`.
- **Shell**: the panels interface, editor and file browser were not reviewed. Only `service`, `cron`, `pkg enable/disable`, `touch` and the numeric-argument commands were read.
- **Add-ons**: only `cluster-worker-setup.lua` was read. The rest were covered by their own tests and lint only.
- **MANUAL.md** was checked for specific claims, not proofread.
- **Nothing was run in Minecraft itself.** The second pass used Ocelot, which runs OpenComputers' own machine and component code but is not the mod inside the game. `tos.py floorcheck` was run (all claims hold); see E9 for its numbers.
- **Emulator coverage is narrow.** I drove the findings above, the network install, the README's first ten minutes, a sweep of about 120 commands with missing or wrong arguments, mutual trust and `rsh` between two machines, and the memory floors. `backup` and `srm` were exercised this pass (G). The editor, file browser, Desktop tiles, `net pair` codes, chat, netfs and `deploy` were not; SRM's online repair (`--online`) and the boot recovery menu were read but not run.
- `test_component_api.lua` could not run without `Reference/`, so component calls were not checked against the API table.

---

## Appendix: reproduction

### The emulator

What the second pass used, in a cloud container with 4 cores and a JDK 21 already present:

```bash
mkdir -p ~/Ocelot
curl -sSL -o ~/Ocelot/ocelot-desktop-v1.14.2.jar \
  https://gitlab.com/api/v4/projects/9941848/packages/generic/ocelot-desktop/v1.14.2/ocelot-desktop-v1.14.2.jar
echo "6675c509c9bf6f88572d4acbed0666458c04164b0a908188f330ea7d707eba17  $HOME/Ocelot/ocelot-desktop-v1.14.2.jar" | sha256sum -c -
python tos.py selftest          # builds ../TOS-Release, boots it, runs the 117 boot checks
```

`build/headless-selftest.py` finds the jar in any folder named `*Ocelot*` under the home directory, so no option is needed. A boot takes 10 to 20 seconds and the runner asks for a 1 GB heap; there is no window and no Minecraft, so modest hardware is enough.

**Saving it as a cloud environment.** In the session's environment settings (Edit, then Setup script), this script installs everything the three passes used, each time a fresh container starts. It never fails a session start; a jar that does not match the checksum is deleted, so the headless tests skip rather than run against something else. The network needs `gitlab.com`; the package registries are allowed by default.

```bash
#!/bin/bash
# TOS dev tools: Lua for the test suite, pytest for the build tests, and
# Ocelot Desktop's jar so `python tos.py selftest` can boot a real machine.
# Nothing here is allowed to stop a session from starting.
apt-get update -qq || true
apt-get install -y -qq lua5.2 lua5.3 lua5.4 lua-check || true
pip install -q pytest pyyaml || true
# build/headless-selftest.py finds the jar in a folder named *Ocelot* under $HOME.
mkdir -p /root/Ocelot
JAR=/root/Ocelot/ocelot-desktop-v1.14.2.jar
URL=https://gitlab.com/api/v4/projects/9941848/packages/generic/ocelot-desktop/v1.14.2/ocelot-desktop-v1.14.2.jar
SUM=6675c509c9bf6f88572d4acbed0666458c04164b0a908188f330ea7d707eba17
[ -f "$JAR" ] || curl -sSL -m 300 -o "$JAR" "$URL" || true
if ! echo "$SUM  $JAR" | sha256sum -c - >/dev/null 2>&1; then
  echo "setup: Ocelot jar missing or wrong checksum; headless tests will not run"
  rm -f "$JAR"
fi
exit 0
```

Each session below is `python build/headless-session.py SCRIPT [options]`. Run `python tos.py build` first: the sessions boot `../TOS-Release`.

**A1** — options `--machines 2`

```
firstboot
type service stop 20-fileshare\n
sleep 1
type service list\n
sleep 1
snap after-stop
sleep 40
type clear\n
type service list\n
sleep 1
type log ring 6\n
sleep 1
snap after-40s
```

**A2** — options `--machines 2`

```
firstboot
type service start 20-rshd\n
sleep 2
type service stop 20-rshd\n
sleep 1
type clear\n
type service list\n
sleep 1
snap rshd-just-stopped
sleep 40
type clear\n
type service list\n
sleep 1
snap rshd-40s-later
powercycle
login root headless1
type clear\n
type ls /etc/rc.d\n
sleep 1
snap rshd-after-reboot
```

**A3** — first `python tos.py pack` (its first step is enough; see D6), then options `--machines 2 --floppy utils=TOS-Extras/dist/optional-utilities/disk1 --floppy-in utils`. Delete `TOS-Extras/dist/` afterwards (D7).

```
firstboot
type pkg install mail\n
wait 30 Installed: mail
type service start mail\n
sleep 2
type clear\n
type pkg disable mail\n
sleep 2
type service list\n
sleep 2
snap right-after-disable
sleep 35
type clear\n
type service list\n
sleep 2
snap 35s-after-disable
powercycle
login root headless1
type clear\n
type service list\n
sleep 2
snap after-reboot-services
```

**B1** — options `--os openos --install-disk`

```
wait 90 /home\s*#
type /mnt/d15/install.lua\n
wait 60 Language
type \n
wait 60 Continue\?
key ctrl+c
sleep 8
snap after-ctrl-c
```

**B5 and the published install** — options `--os openos --internet --timeout 900`. Needs the machine to reach `raw.githubusercontent.com`.

```
wait 90 /home\s*#
type wget -f https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/main/bootstrap.lua /bootstrap.lua && /bootstrap.lua\n
wait 60 Download TOS from the internet
type \n
wait 400 Language|Continue\?|REFUSED|Refusing|failed to download|Cannot
maybe 2 Language
type \n
wait 60 Continue\?
type \n
wait 240 Leave them where they are
type 1\n
wait 30 What type of device
type \n
wait 30 Hostname
type \n
wait 30 Security level
type \n
wait 30 Who may add
type \n
wait 30 Trust the Optional
type \n
wait 30 Verbose boot
type n\n
wait 30 Apply these settings
type \n
wait 60 confirm BIOS reflash
type no\n
wait 60 Reboot now
type n\n
wait 30 #\s*$
type ls /\n
sleep 2
snap final-ls
```

**B2 and B7** — options `--os openos --internet --boot-tier 2 --timeout 900 --keep`. The filler leaves 1370 KB free; afterwards look for 0-byte files under `boot/home/tos-netinstall` in the kept run directory.

```
wait 90 /home\s*#
type wget -f https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/main/bootstrap.lua /bootstrap.lua\n
wait 40 Saved data
type echo 'local fs=require("filesystem") local p=fs.get("/") local free=p.spaceTotal()-p.spaceUsed() local f=io.open("/filler","w") f:write(string.rep("x",free-1370*1024-512)) f:close() print("free now",p.spaceTotal()-p.spaceUsed())' > /home/f.lua\n
type /home/f.lua\n
wait 30 free now
type /bootstrap.lua\n
wait 60 Download TOS from the internet
type \n
wait 60 Staging in
sleep 2
snap staging-msg
wait 500 Language|Continue\?|REFUSED|Refusing|failed to download|Cannot|did not download|Ran out of space
maybe 2 Language
type \n
wait 60 Continue\?
type \n
wait 300 verified|FAILED|Cannot load|WRONG SIZE|MISSING|Not enough space
sleep 4
snap copy-result
```

**C1 and C2** — no options

```
firstboot
type cron add job 1.5 print(1)\n
sleep 2
snap cron-add
type cron list\n
sleep 2
snap cron-list
type clear\n
type log 2.5\n
sleep 2
snap log
```

**C3 and C4** — no options

```
firstboot
type lua print(math.pi)\n
sleep 3
snap lua-oneliner
type exit\n
sleep 1
type clear\n
type useradd alice\n
sleep 2
type alicepass1\n
sleep 1
type alicepass1\n
sleep 2
type clear\n
type passwd alice\n
sleep 2
snap passwd-alice-prompt
type headless1\n
sleep 1
type resetpass1\n
sleep 1
type resetpass1\n
sleep 2
snap passwd-alice-result
type logout\n
wait 30 Username:
type alice\n
sleep 1
type resetpass1\n
sleep 4
snap alice-with-new-password
```

**A1 end to end, with `rsh`** — options `--machines 2`. `net trust` takes the index `net scan` prints, not the one from `net peers`. Each `rsh` is waited out, because a disabled target ignores the request and the caller only gives up after 30 seconds.

```
firstboot
machine 2
firstboot
sleep 3
type net scan\n
wait 20 peer\(s\) responded
type clear\n
type net trust 1 full\n
wait 10 Trust updated
machine 1
type net scan\n
wait 20 peer\(s\) responded
type clear\n
type net trust 1 full\n
wait 10 Trust updated
sleep 6
type clear\n
mark rsh1
type rsh 1 print(7000+777)\n
wait 45 7777|Timeout waiting|Error
snap 1-default-off
machine 2
type clear\n
type service start 20-rshd\n
wait 10 Started: 20-rshd
machine 1
type clear\n
mark rsh2
type rsh 1 print(7000+777)\n
wait 45 7777|Timeout waiting|Error
snap 2-after-start
machine 2
type clear\n
type service stop 20-rshd\n
wait 10 Stopped: 20-rshd
type clear\n
type service list\n
sleep 1
snap 3-m2-after-stop
machine 1
type clear\n
mark rsh3
type rsh 1 print(7000+777)\n
wait 45 7777|Timeout waiting|Error
snap 4-right-after-stop
machine 2
type clear\n
type service list\n
sleep 1
snap 5-m2-list
machine 1
type clear\n
mark rsh4
type rsh 1 print(7000+777)\n
wait 45 7777|Timeout waiting|Error
snap 6-later
machine 2
type clear\n
type log ring 8\n
sleep 2
snap 7-m2-log
```

### Choosing the CPU's Lua architecture

The repo's `build/HeadlessTOS.java` always builds a Lua 5.3 machine. Ocelot Brain's `CPU` and `APU` have `setArchitecture`, and the jar carries native Lua 5.2, 5.3 and 5.4, so this patch adds a `TOS_HEADLESS_ARCH` environment variable. The third pass applied it to a private copy (the three `build/headless-*` files plus links to `TOS-Release` and `TOS-Extras`), leaving the repo's runner untouched. It is small and self-contained enough to adopt as is.

```diff
--- build/HeadlessTOS.java
+++ build/HeadlessTOS.java
@@ -583,6 +583,21 @@
     }
   }
 
+  /** Audit patch: TOS_HEADLESS_ARCH=5.2|5.3|5.4 picks the CPU's Lua architecture. */
+  static void applyArch(Object cpu) {
+    String want = System.getenv("TOS_HEADLESS_ARCH");
+    if (want == null || want.isEmpty()) return;
+    try {
+      Class<?> arch = Class.forName("totoro.ocelot.brain.entity.machine.luac.NativeLua"
+          + want.replace(".", "") + "Architecture");
+      cpu.getClass().getMethod("setArchitecture", Class.class).invoke(cpu, arch);
+      System.out.println("[headless] CPU architecture: Lua " + want);
+    } catch (Exception e) {
+      throw new RuntimeException("cannot set CPU architecture " + want, e);
+    }
+  }
+
+
   static void build(String profile, Path bootDir, Path diskDir, byte[] bios, boolean internet, String ram,
                     String bootTier, String diskAddress, List<String> floppySpecs, String floppyIn,
                     int seats, List<String> peerBoots) {
@@ -637,9 +652,13 @@
     }
     if (t1) {
       pc.inventory().apply(1).put(new GraphicsCard(Tier.One()));
-      pc.inventory().apply(8).put(new CPU(Tier.One()));
+      CPU cpu1 = new CPU(Tier.One());
+      applyArch(cpu1);
+      pc.inventory().apply(8).put(cpu1);
     } else {
-      pc.inventory().apply(8).put(new APU(Tier.Two()));
+      APU apu1 = new APU(Tier.Two());
+      applyArch(apu1);
+      pc.inventory().apply(8).put(apu1);
     }
     pc.inventory().apply(9).put(eeprom);
     mainEeprom = eeprom;
```

`TOS_HEADLESS_ARCH=5.4 python build/headless-selftest.py` ran the battery on Lua 5.4 (117 of 117). The sessions below were run with `TOS_HEADLESS_ARCH=5.2`.

**B4, B6** — options `--os openos --install-disk`. The installer's answers are the defaults; the last snap is the stock BIOS booting the installed `init.lua`.

```
wait 90 /home\s*#
type lua\n
sleep 2
snap openos-lua-version
type os.exit()\n
sleep 1
type clear\n
type /mnt/d15/bootstrap.lua\n
sleep 4
snap bootstrap-on-52
type clear\n
type /mnt/d15/install.lua\n
wait 60 Language
snap install-hardware-report
type \n
wait 60 Continue\?
type \n
wait 240 Leave them where they are
type \n
wait 30 What type of device
type \n
wait 30 Hostname
type \n
wait 30 Security level
type \n
wait 30 Who may add
type \n
wait 30 Trust the Optional
type \n
wait 30 Verbose boot
type n\n
wait 30 Apply these settings
type \n
wait 60 confirm BIOS reflash
type no\n
wait 60 Reboot now
snap before-reboot
type \n
sleep 15
snap after-reboot-stock-bios
```

**B6 on a Tier 1 screen** — options `--os openos --install-disk --profile t1 --ram 1024,1024`. `bootaddr` makes the stock BIOS boot the TOS disk.

```
wait 120 /home\s*#
bootaddr d15c0000-0000-4000-8000-000000000000
powercycle
sleep 12
snap t1-guard-screen
```

**F1** — options `--os openos --extra-disk TOS-Extras/cluster/openos`; also run without the variable for the Lua 5.3 row.

```
wait 90 /home\s*#
type /mnt/e7a/cluster-worker.lua\n
sleep 4
snap worker
```

### Off-box scripts

Both run from the repo root with `lua <file>`.

### A1 and A2 — `repro_rc_stop.lua`

```lua
-- Operator `service stop` vs the 30 s supervisor. Harness copied from
-- usr/lib/tests/test_rc_disabled.lua.
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local sharedEnv = {}
package.loaded["kernel.sandbox"] = { build = function() return sharedEnv end }
package.loaded["kernel.users"]   = { kernelSession = function() return {} end }
_G._TOS = { bootSession = {} }
local function makeFs(files)
  return {
    exists = function(p)
      if files[p] ~= nil then return true end
      local prefix = p:sub(-1) == "/" and p or (p .. "/")
      for k in pairs(files) do if k:sub(1, #prefix) == prefix then return true end end
      return false
    end,
    makeDirectory = function() return true end,
    list = function(dir)
      local out = {}
      local prefix = dir:sub(-1) == "/" and dir or (dir .. "/")
      for p in pairs(files) do
        local rest = p:sub(#prefix + 1)
        if p:sub(1, #prefix) == prefix and not rest:find("/") then out[#out + 1] = rest end
      end
      table.sort(out); return out
    end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, d) files[p] = d; return true end,
    remove = function(p) files[p] = nil; return true end,
  }
end
local function running(rc, n)
  for _, s in ipairs(rc.list()) do if s.name == n then return s.running end end
end
local SRC = "return { restart = true, start = function() STARTS = STARTS + 1 end, "
  .. "stop = function() STOPS = STOPS + 1 end }"

-- Case A: a restart=true service that booted enabled.
do
  local rc = require("kernel.rc")
  sharedEnv.STARTS, sharedEnv.STOPS = 0, 0
  rc.init({ fs = makeFs({ ["/etc/rc.d/svc.lua"] = SRC }) }); rc.runAll()
  rc.stop("svc")
  print("A after stop:      running=" .. tostring(running(rc, "svc")))
  rc.supervise()
  print("A after supervise: running=" .. tostring(running(rc, "svc"))
    .. " starts=" .. sharedEnv.STARTS .. "   (want false / 1)")
end
-- Case B: rshd ships disabled; the operator starts it, then stops it.
do
  package.loaded["kernel.rc"] = nil
  local rc = require("kernel.rc")
  sharedEnv.STARTS, sharedEnv.STOPS = 0, 0
  local files = { ["/etc/rc.d/20-rshd.lua"] = SRC, ["/etc/rc.d/20-rshd.disabled"] = "notes" }
  rc.init({ fs = makeFs(files) }); rc.runAll()
  rc.start("20-rshd")
  print("B after start:     marker=" .. tostring(files["/etc/rc.d/20-rshd.disabled"]))
  rc.stop("20-rshd"); rc.supervise()
  print("B after supervise: running=" .. tostring(running(rc, "20-rshd")) .. "   (want false)")
  package.loaded["kernel.rc"] = nil
  rc = require("kernel.rc"); sharedEnv.STARTS = 0
  rc.init({ fs = makeFs(files) }); rc.runAll()
  print("B next boot:       running=" .. tostring(running(rc, "20-rshd")))
end
```

Output at `1183c69`:

```
A after stop:      running=false
A after supervise: running=true starts=2   (want false / 1)
B after start:     marker=nil
B after supervise: running=true   (want false)
B next boot:       running=true
```

### C1 — `repro_cron.lua`

```lua
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end,
  freeMemory = function() return 1048576 end, totalMemory = function() return 2097152 end,
  beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
  isAvailable = function() return false end }
local files = {}
local F = { readFile = function(p) return files[p] end,
  writeFile = function(p, d) files[p] = d; return true end,
  writeFileAtomic = function(p, d) files[p] = d; return true end,
  exists = function(p) return files[p] ~= nil end, normalize = function(p) return p end }
local EV = { interval = function() return 1 end, timer = function() return 1 end,
  cancelTimer = function() end, every = function() return 1 end }
_G._TOS = { fs = F, event = EV }
package.loaded["kernel.users"] = {
  currentSession = function() return { user = "root", tier = 3 } end,
  canAccessAs = function() return true end }
local cron = require("kernel.cron")
local quiet = function() end
cron.init({ fs = F, event = EV, log = { info = quiet, warn = quiet, error = quiet, debug = quiet } })
for _, iv in ipairs({ 60, 1.5 }) do
  local ok, res = pcall(cron.add, "job" .. tostring(iv), iv, "print(1)")
  local n = 0; for _ in pairs(cron.list()) do n = n + 1 end
  print(("interval=%s ok=%s result=%s jobs=%d"):format(tostring(iv), tostring(ok), tostring(res), n))
end
```

Output at `1183c69`:

```
interval=60 ok=true result=1 jobs=1
interval=1.5 ok=false result=tos/kernel/cron.lua:229: bad argument #3 to 'format' (number has no integer representation) jobs=2
```

### B4

```
luac5.2 -p bootstrap.lua    # bootstrap.lua:517: unexpected symbol near '>'
luac5.2 -p init.lua bios.lua install.lua    # clean
```

### D1

```
bash run_tests.sh    # PASS=416 FAIL=1, exit 1, no TOS-Extras tests listed
```
