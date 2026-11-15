# TOS audit notes — for a fixing session

Audit of the published `dev` branch at commit `1183c69` ("Cluster: a storage pool, on the answers the operator approved"), done 2026-11-15. Nothing in the repository was changed; this file is the only output.

**Paths.** Everything below is relative to the published repo root, which is `TOS-Dev/` in the local monorepo. `TOS-Extras/` is nested inside the published repo and a sibling of `TOS-Dev/` locally. Line numbers are from `1183c69` and will have drifted in a newer local copy, so each finding also names the function or quotes the text to search for.

**How to read the evidence labels.**

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

The suite is green, so everything below is behaviour the tests do not cover.

## Summary

| ID | Severity | What | Evidence |
|---|---|---|---|
| A1 | High | `service stop` is undone by the supervisor within 30 s | Reproduced |
| A2 | High | Once started, `rshd` cannot be switched off again across reboots | Reproduced |
| A3 | Medium | `pkg disable` does not stop the package's service or keep it off | Confirmed by reading |
| B1 | Medium | Ctrl+C at any installer y/n prompt means **yes** | Confirmed against OC source |
| B2 | Medium | `bootstrap.lua` counts a failed staging write as a download | Confirmed against OC source |
| B3 | Low | `bootstrap.lua`'s space estimate is about 47 KB too low | Measured on a build of this tree |
| B4 | Low | `bootstrap.lua` does not parse on a Lua 5.2 CPU | Reproduced with `luac5.2 -p` |
| B5 | Low | `bootstrap.lua` never removes itself: OpenOS has no `arg` | Confirmed against OC source |
| B6 | Low | The Lua 5.2 screen tells the user to do something that does not work | Confirmed against OC source |
| C1 | Low | `cron add` with a fractional interval errors after saving the job | Reproduced |
| D1–D5 | Low | Test tooling gaps on the published layout | Reproduced |
| E1–E6 | Nit | Docs, comments and repo hygiene | Mixed |

Suggested order: A1 and A2 together, then A3 (same new API), then B1, B2 with B3, then the rest.

---

## A. Services

### A1. `service stop` does not stick — High — Reproduced

**Where.** `tos/kernel/rc.lua`: `rc.stop` (line 601), `rc.supervise` (line 668), `rc.tryRestart` (line 637). The timer is `event.interval(30, …, "kernel:rc_supervise")` in `tos/kernel/init.lua:945`.

**What happens.** `rc.stop` sets `svc.running = false` and nothing else. `rc.supervise` restarts every service where `svc.restart and not svc.running and not svc.disabledAtBoot`. Nothing distinguishes "the operator stopped it" from "it crashed", so the next 30-second tick starts it again. Every shipped service declares `restart = true`: `10-discoveryd`, `20-chatrelay`, `20-fileshare`, `20-netfsd`, `20-rshd`, and `cluster-storaged` in TOS-Extras.

**What the user sees.** `service stop 20-rshd` prints `Stopped: 20-rshd`, the log says "exec requests now refused", and up to 30 seconds later the remote shell is armed again with only a log line (`Restarting service: 20-rshd (attempt 1)`). The same applies to file sharing and netfs. It only stays down after `maxRestart` restarts are used up, and that budget resets after `RESTART_DECAY` (600 s).

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

### A2. `rshd` cannot be turned off again persistently — High — Reproduced

**Where.** `tos/kernel/rc.lua:590-593` (inside `rc.start`), `etc/rc.d/20-rshd.disabled`, `tos/shell/panels/commands/admin.lua:3909-3956` (`C.service`).

**What happens.** `service start 20-rshd` deletes `/etc/rc.d/20-rshd.disabled` so the service auto-starts on later boots. That is intended and documented in the marker. But:

1. The marker's own text is the only place that explains how to turn it off again ("recreate this marker (touch /etc/rc.d/20-rshd.disabled)"), and `service start` has just deleted that file.
2. `service` has only `list | start <name> | stop <name>`. There is no `disable`.
3. `MANUAL.md` mentions `rshd` once (line 1933) and never mentions `.disabled`. README's "The remote shell is off by default" does not say that starting it is permanent.

So an operator who tries the remote shell once has it listening on every boot from then on, and `service stop` (see A1) does not even hold for the current boot.

Note that `rc.disable(name)` already exists (line 697) and **deletes the script**. Do not reuse that name for this.

**Recommended fix.**

- Add `rc.setBootEnabled(name, on)`: writes or removes `<full name>.disabled` and updates `svc.disabledAtBoot`.
- Add `service disable <name>` (stop if running, then `setBootEnabled(false)`) and `service enable <name>` (`setBootEnabled(true)`, does not start it). Update the usage line and `help`.
- After `service stop` on a service that will start again at boot, print one line: "Off until the next boot. `service disable <name>` keeps it off."
- Rewrite the tail of `20-rshd.disabled` to say `service disable 20-rshd`, and add the same to README "Known limitations" and the MANUAL's remote-shell section.

### A3. `pkg disable` leaves the package's service running — Medium — Confirmed by reading

**Where.** `tos/kernel/pkg.lua:792-798` (`pkg.setEnabled`), `tos/shell/panels/commands/admin.lua:1383-1391`, against `usr/man/pkg.man:76-77` and `MANUAL.md:1048-1050`.

**What happens.** `pkg.setEnabled` writes one byte to the package's `state` file. Its own comment says "Service start/stop is the caller's responsibility … rc.d hooks (commit 2) will read it and act", but the caller (`pkg disable`) only prints `Disabled: <name>`, and `rc.lua` never reads the package state. It reads only the `.disabled` marker, which `service start` removed.

**What the docs promise.** `man pkg`: "Switch it off without removing it (its commands and its service stop; its files stay)". MANUAL: "a disabled package's commands and service stay dormant".

**Result.** After `pkg disable mail` the mail service keeps receiving, and it starts again at the next boot, while `pkg list` shows the package as disabled. This affects every service package: mail, intercom, the cluster packages, rbmk-controld.

**Recommended fix.** In the `pkg disable` path, for each `/etc/rc.d/*.lua` the package owns: `rc.stop` it and call the new `rc.setBootEnabled(name, false)` from A2. `tos/kernel/pkgops.lua:895-934` already collects a package's rc.d stems and their markers for upgrades and can be reused. Decide what `pkg enable` does for the service (leave it off and say "`service start <svc>` to run it" is the conservative choice, matching `defaultState = "disabled"`), then make the man page and MANUAL say exactly that. Extend `test_pkg_service_enable.lua`.

---

## B. Installing (`bootstrap.lua`, `install.lua`, `init.lua`)

### B1. Ctrl+C at a y/n prompt answers yes — Medium — Confirmed against OC source

**Where.** `ask()` and `confirm()` in `bootstrap.lua:70-100` and `install.lua:87-118`.

**What happens.** OpenOS's `term.read()` returns `false` when the user presses Ctrl+C and `nil` on Ctrl+D (`lib/core/cursor.lua`: `elseif name == "interrupted" then self:echo("^C\n") return false, name`). `ask` then runs `if not answer or answer == "" then return default end`, and `confirm` passes `"y"` as the default. So the universal "get me out of here" key accepts the prompt.

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

### B2. A failed staging write is counted as a download — Medium — Confirmed against OC source

**Where.** `bootstrap.lua:793-796`:

```lua
local f = io.open(stagingDir .. path, "w")
if f then
  f:write(body); f:close()
  copied = copied + 1
```

**What happens.** On OpenComputers a write is all-or-nothing: `Capacity.scala`'s `CountingOutputHandle.write` throws "not enough space" when the whole chunk does not fit, and opening a new file only needs the 512-byte `fileCost`. OpenOS turns that into `nil, "not enough space"`, and `buffer:close()` discards the result of its own flush. So when a file does not fit, `io.open` succeeds, `f:write` fails silently, a 0-byte file is left behind and `copied` goes up. The existing out-of-space handling only triggers when `io.open` itself fails, which needs less than 512 bytes free. Smaller files after the one that failed still fit, so the loop finishes with `failed == 0` and "Downloaded N files".

**What follows.** `install.lua`'s `verifyCopy` (line 448) compares the size of each installed file with the staged one, 0 against 0, reports "All N files verified", and offers the BIOS flash. `init.lua`'s critical-file check is `exists()` only. The machine is left with an empty file somewhere in the system, found later by `verify` or by a panic.

`install.lua`'s own `copyFileChunked` (line 410) was already fixed for exactly this and its comment explains it ("OpenOS answers a full disk with nil, 'not enough space' rather than raising … AUDIT 5"). The bootstrap is the twin that was missed.

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

On failure, remove the partial file, and treat `freeSpace(stagingDir) < #body + 512` as the out-of-space case (the current `freeNow < 4096` test is too narrow for a 100 KB file). As a second line of defence, have `install.lua` refuse a 0-byte source for any manifest entry, or hash the installed files against the manifest: it already loads `/tos/kernel/sha256.lua` for `biosDigest`.

**Test.** `test_install_bootstrap.lua` with a fake file handle whose `write` returns `nil, "not enough space"`.

### B3. The bootstrap's space estimate is stale — Low — Measured

**Where.** `bootstrap.lua:710`: `local NEED_BYTES = 1400 * 1024`.

**Measured** on a release built from this tree with `python tos.py build`: 175 staged files and 13 directories, 1,384,463 bytes; with OpenComputers' 512 bytes per file and directory, **1,481,231 bytes (1447 KB)**. The threshold is 1,433,600. A staging drive with between 1400 and 1447 KB free gets no warning and then runs short. Combined with B2 that is a silent partial install, not a failed one.

The surrounding text is stale as well: comments at lines 646, 680 and 1025 say "~1.2 MB across 152 files"; `printHelp` (line 333) and `MANUAL.md:228` say "about 1.4 MB".

**Recommended fix.** Raise it to 1536 KB and correct the three texts. `MAX_FILE_BYTES` already has a test that measures the real release (`test_install_bootstrap.lua`); give `NEED_BYTES` the same treatment, summing sizes plus 512 per entry, so it cannot drift again.

### B4. `bootstrap.lua` does not parse on Lua 5.2 — Low — Reproduced

**Where.** `bootstrap.lua:505-540` (`sha256hex` uses `>>`, `~`, `&`, `|`).

**Reproduce.** `luac5.2 -p bootstrap.lua` gives `bootstrap.lua:517: unexpected symbol near '>'`. `init.lua`, `bios.lua` and `install.lua` all parse under 5.2, in source and in the release build.

**What the user sees.** On a CPU set to Lua 5.2 the documented one-liner ends in a raw syntax error with no hint that the CPU is the problem. `bios.lua` and `init.lua` both go out of their way to avoid precisely that ("stop HERE with the fix instead of booting into a raw syntax-error panic"). OpenComputers defaults to 5.3 (`defaultLua53: true`, checked in 1.7.5 and 1.8.10), so this only hits switched CPUs and servers with an older config.

`install.lua` parses on 5.2 but says nothing: it installs, offers the flash, and the machine then halts at the BIOS's C1.

**Recommended fix.** Keep `bootstrap.lua` 5.2-parseable the way `init.lua` is. Probe with `load("return 1<<1")` right after the helpers and stop with the fix; compile the 5.3-only code from a long string with `load`. `sha256hex` and `verifyRelease` carry `--[[TEST-EXTRACT]]` markers, so `test_install_bootstrap.lua` needs to follow whatever shape is chosen. Add the same probe as a warning in `install.lua`'s `printHardwareReport`. `test_bios.lua` pins the probe in the two boot files; extend it to these two, and add a syntax scan for 5.3 operators outside the loaded string since CI has no Lua 5.2.

### B5. The bootstrap never removes itself — Low — Confirmed against OC source

**Where.** `bootstrap.lua:1004`: `local self = selfPathToReclaim((arg and arg[0]) or nil)`.

**What happens.** OpenOS does not define a global `arg`. `lib/process.lua`'s `process.load` passes arguments as `...` and records the script with `os.setenv("_", program)`. So `arg` is nil, `selfPathToReclaim(nil)` returns nil, and `/bootstrap.lua` stays on the disk after every network install. The "Removed /bootstrap.lua" line can never print. `install.lua:200` already uses `os.getenv("_")` for the same purpose, and the bootstrap's own comment at line 949 mentions the convention.

**Why the suite misses it.** The tests call `selfPathToReclaim` with strings directly. Stock Lua defines `arg`, OpenOS does not. `test_install_bootstrap.lua:287` even asserts the source contains `arg and arg[0]`.

**Recommended fix.** `selfPathToReclaim((os.getenv and os.getenv("_")) or (arg and arg[0]) or nil)`. `os.getenv("_")` is the resolved absolute path, so the root-only guard still protects the OPPM copy in `/usr/bin`. Update the assertion at line 287.

### B6. The Lua 5.2 screen gives an instruction that does not work — Low — Confirmed against OC source

**Where.** `init.lua:49-53`.

**What it says.** "Fix: sneak-click (crouch + right-click) the CPU in its computer-case slot to cycle architectures, then reboot."

**What is true.** OpenComputers changes the architecture in `CPULike.onItemRightClick` when `player.isSneaking`: the CPU has to be **held in the hand** and used while sneaking. Shift-clicking it in the case's slot just moves it to the inventory. The README, MANUAL and BIOS say "sneak-click the CPU", which is vague but not wrong.

Two of those lines are also 54 and 55 characters, drawn from column 2, so a Tier 1 screen (50 columns) cuts them off.

**Recommended text** (each line under 48 characters):

```
TOS needs the Lua 5.3 or 5.4 CPU architecture.
This CPU is set to Lua 5.2.
Fix: take the CPU out, hold it, and sneak +
right-click until it says Lua 5.3. Put it back.
Press any key to power off.
```

Consider the same wording in README line 81 and `MANUAL.md:204`.

---

## C. Commands

### C1. `cron add` with a fractional interval — Low — Reproduced

**Where.** `tos/kernel/cron.lua:117-119` (`cron.add`'s validation), `216-226` (store and save), `229` (log line); `tos/shell/panels/commands/admin.lua:4002`.

**What happens.** `cron.add` accepts any positive number. It stores and saves the job and then logs with `string.format("… (every %ds, …)", intervalSec)`. For `1.5` that raises "number has no integer representation". The command reports an error, but the job exists and runs. A user who retries with a whole number ends up with two jobs.

The scheduler ticks every 10 seconds (`cron.lua:89`), so an interval under 10 means "every tick" in any case.

**Recommended fix.** Validate before storing: a whole number of seconds, at least 1, and say in the usage text that jobs are checked every 10 seconds. Add a case to `test_cron_add_report.lua`.

I checked the other commands that parse a number (`redstone set`, `pulse`, `date tz`, `watch`, `menu remove`, `log`, `drive read`). `redstone set` validates properly; I found no second instance, but I did not trace every one of them to its last use.

---

## D. Test tooling on the published layout

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

---

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

This was one pass over a repository of about 250,000 lines. No finding in an area below means I did not look closely, not that it is clean.

- **Not read line by line**: `kernel/sandbox.lua`, `securefs.lua`, `pkgops.lua`, `pkgremote.lua`, the whole `kernel/net/` tree, `crypto` and the Ed25519 code, `process.lua`, `screen.lua` and `display.lua`.
- **Shell**: the panels interface, editor and file browser were not reviewed. Only `service`, `cron`, `pkg enable/disable`, `touch` and the numeric-argument commands were read.
- **Add-ons**: only `cluster-worker-setup.lua` was read. The rest were covered by their own tests and lint only.
- **MANUAL.md** was checked for specific claims, not proofread.
- **Nothing was run in the game or in Ocelot.** There is no Ocelot jar in this environment, so `tos.py selftest`, `floorcheck` and the headless sessions were not run. B1, B2, B5 and B6 rest on reading OpenComputers' source, which I am confident in but did not observe.
- `test_component_api.lua` could not run without `Reference/`, so component calls were not checked against the API table.

---

## Appendix: reproduction scripts

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
