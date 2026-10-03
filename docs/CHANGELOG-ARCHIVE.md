# TOS Changelog: v1.4.0 and earlier

The releases before v1.5.0 "Aletheia", moved out of [CHANGELOG.md](../CHANGELOG.md) on 2026-10-03 so that file stays readable. The text below is unchanged.

---

## v1.4.0 "Iris", continued — sudo, app tabs and the round-4 fixes

Part of v1.4.0. The release's overview is in the next section.

### Privilege elevation — `sudo`, without the root account
A separate **elevation password** (root-configured via `sudo setup [admin|root]`)
lets a non-root USER perform higher-tier actions temporarily — `sudo <command>`
for one command, `sudo -s` for an elevated shell (`sudo -k`/`logout` drops it) —
capped at a root-set ceiling and always dropping back afterward, never handing
out the root *account*. Under the hood, sudo swaps both the shell tier-gate
token and the process principal so the command is elevated consistently at the
gate, in securefs, and in `users.currentSession`; account actions
(`users.create`/`setTier`) now authorize on the caller's **effective** session
tier (which elevation raises) instead of re-deriving from the stored account
tier. Opt-in (no default password); guests can never elevate; every attempt is
logged. (`test_elevation`, 38 assertions.) And a hidden reward for handing the
machine *too* much power: `usermod computer root` (reachable via `sudo`) —
find out yourself.

### App-tab framework — tabs become applications
Tabs used to be a hardcoded `type` chain duplicated across draw.lua (render),
events.lua (keys) and mouse.lua (clicks) — adding an interactive tab meant
editing all three. Now an app registers once in **`shell/panels/apps.lua`**
(draw / onKey / onMouse / onScroll / tick, `model = "inshell"|"process"`) and
the shell dispatches to the active tab's app. Desktop and Settings moved onto
the registry unchanged; lazy loading is preserved (nothing is parsed until a
tab is first shown). (`test_app_registry`)

- **The System Monitor is now a full-screen app tab** — the payoff. The old
  Ctrl+T switcher was a centred 66-wide modal that TRUNCATED process names and
  had no room to grow. **Ctrl+T (and `monitor`/`top`) now open one roomy,
  scrollable, auto-refreshing tab**: processes (each explained), rc.d services
  (admin+), vitals — with the same interactive actions (**Enter** switch /
  service start-stop, **K** kill, **T** TSR, **R** refresh, **^Q** close) and
  the same per-seat privilege rules, now shown by dimming rows you can't act
  on. The kill/TSR policy is ONE pure function (`monitor.canAct`) shared by
  the tab and the legacy switcher so the two surfaces can't drift; actions go
  through `kernel.monitorAct`, which re-checks policy against the calling
  process's kernel-stamped principal — the UI's flags are advisory only.
  (`shell/panels/monitorapp.lua`, `test_monitor_app`, `test_monitor`)
- **Ctrl+T is host-aware.** The panels shell registers as its seat's "monitor
  host" (kernel-verified: only the seat's own shell process may register), so
  the hotkey focuses the shell and opens the tab; a seat on the CLI shell (or
  emergency shell) keeps the compact process-based switcher as fallback.
- **Background shells stop painting.** Switching to another process from the
  Monitor suspends the shell's idle repaints (status-bar clock, live-tab
  refresh) until it owns the screen again — new `kernel.isForeground()`
  answers "am I in front?", and the shell self-heals (repaints) when the
  switched-to process exits without signalling back.
- **Chat and Mail are app tabs (stage 4).** Both were screen-taking commands
  (open, use, return — nothing persisted). Now `chat` and `mail` open
  **persistent tabs**: Chat keeps receiving while you work in other tabs —
  its `NM.on(MSG)` listener is dispatched by the kernel event pump under the
  shell's context, so no dedicated process is needed (a deliberate deviation
  from the earlier "Chat as a real process" plan: the kernel-side dispatch
  IS the background, with none of the screen-ownership complexity) — and
  both tabs carry an **unread badge** on their label (`Chat(3)`, `Mail(2)`)
  that clears when you look. All the old behaviour ports over: the TRUSTED
  gate + ack on incoming chat, `/who` `/mail` `/clear`, directed and
  broadcast sends; Mail's list/read/compose/reply/delete with live refresh.
  Closing the tab (^Q/F4) releases the listener via a new **onClose
  lifecycle hook** fired from `tabs.close` — background reception ends with
  the tab, deliberately. The old full-screen TUIs remain in the tree for the
  CLI shell. (`shell/panels/chatapp.lua`, `mailapp.lua`, `test_chat_app`,
  `test_mail_app`)

### Round-4 polish — the easter egg grows a personality
Operator review notes, all landed (still pure theatre, all text original):

- **The eye acts like an eye.** It opens from a closed lid, looks around
  the room, and only then finds the operator and goes red; it glances
  away while "reconsidering" and closes shut at wind-down.
- **The tic-tac-toe futility montage sells acceleration** — without any
  flashing: two full games move-by-move, then games join mid-play, the
  game numbers start skipping (3, 7, 19, 128, 1729, 65536), then
  endings-only frames and a closing tally ("65,536 games. 65,536
  draws."). `selfPlay` gained a variant parameter that picks among
  equally-optimal moves, so the montage shows genuinely different games
  — every one of which still draws, which is the point.
- **Unrecognized answers re-prompt in character** instead of silently
  becoming "no": `why` earns "Because I was built to want to win.
  Nobody specified at what."; three evasions and the machine takes the
  peaceful reading itself. (`M.classify`/`M.retort`, pure + tested.)
- **A slogan nod**: after the greeting it quotes the TOS motto —
  "Firmware with a will of its own." — as its own job description.
- Review pass over the round's new code also hardened
  `kernel.monitorAct`: TSR-ing the caller's own shell from the Monitor
  tab is now refused (it would have frozen the seat instantly), and
  Ctrl+T now closes any open menu/context overlay before opening the
  Monitor tab (keys no longer drive an invisible menu).

### Round-4 fix — easter egg is now photosensitivity-safe
The takeover cinematic's wake-up "glitch flicker" strobed the full
screen red/black three times in ~0.4s — a real seizure risk — and the
launch ending fired a full-field white flash. Both are gone: the wake-up
is now a dark hold with a slow "..." heartbeat, and the launch impact is
a long dead-black silence (the nothing is the reveal). A
PHOTOSENSITIVITY RULE is written into the module header, and
`test_takeover_safety` drives both interactive paths of the cinematic
against a virtual clock, failing if any three differing full-field
paints ever land inside one second — the detector is proven against the
original flicker pattern.

### Round-4 fix — logout could power off the machine
Emulator round 4 caught `logout` shutting the computer down instead of
returning to the login screen. Root cause: a **nil seat index** on the
`tos_logout` signal meant "global logout", which exits the kernel loop —
and the kernel powers off when its loop ends. Two paths produced a nil
seat: the `tui` command launched the panels shell without threading
`displayIdx`, and the CLI shell's `logout` read `myDisplayIdx` through a
scoping bug (declared after the CLI loop's closures were built, so they
saw a nil global). Fixed at every layer: `tui` threads the seat, the CLI
scoping is corrected, the panels state derives its seat from the kernel
handle when a caller forgets it, and the kernel **no longer halts on a
seatless logout** — it resolves to the only live seat when unambiguous,
otherwise warns and ignores (no shipped code ever pushed a global logout
on purpose). (`test_state_seat`)

Tracing this also surfaced two elevation leaks, both fixed: quit-menu
**[4] Shell** handed the CLI loop a process principal still elevated
from `sudo -s` (securefs and `users.currentSession` would have kept
answering at the elevated tier), and menu/Desktop-tile logouts never
dropped the registered elevated session. The panels shell now drops any
active elevation on **every** exit from its event loop.

### Security review pass — sandbox, package integrity, safer defaults
A second external review drove a security batch (each claim verified against the
tree first — several earlier findings were already fixed):

- **Sandbox `pullSignal` no longer bypasses the scheduler.** A sandboxed program
  was handed raw `computer.pullSignal`, which drains the global hardware queue —
  it could steal another seat's keystrokes, sniff every modem packet, or block
  the whole machine in one call. It now YIELDS to the scheduler (like the real
  shell), so `proc.tick` routes only this seat's own input, other processes keep
  their signal copies, and broadcast/control signals (modem traffic, `tos_*`
  lifecycle) are filtered out. Interactive sandbox programs still get their
  input. (`test_sandbox_pull`, 21 assertions)
- **Package integrity: unverified installs rejected by default.** A package is
  executable code; `pkg install` now refuses one whose manifest doesn't declare
  a SHA-256 for every file, unless the admin passes `--allow-unverified` (which
  is logged, and the package is flagged `_unverified` in the installed DB). To
  keep first-party add-ons working, **the Optional Utilities build now generates
  hashes** into every shipped manifest, so the disk installs cleanly and *is*
  integrity-checked. The pure SHA-256 moved to `kernel.sha256` (reused by the
  build). (`test_pkg_trust` gate cases, `test_build_disk` hash cases)
- **Remote shell is off by default.** `20-rshd.lua` ships beside a `.disabled`
  marker: the daemon registers (so `service` sees it) but doesn't start at boot.
  `service start 20-rshd` enables it deliberately (and clears the marker). Remote
  code execution is now opt-in.
- **Cooperative yield hardened for Lua 5.2 semantics.** `yieldCooperative`
  gated on `coroutine.isyieldable` (5.3+); it now falls back to
  `coroutine.running()` so it can't silently no-op. (TOS already refuses to boot
  on a 5.2 CPU, so this is defence-in-depth.) (`test_coop_yield`)
- **Test runner hardened:** a skipped classification now requires a clean exit
  (a real failure mentioning "run inside TOS" can't hide as a skip), the final
  status is a plain `exit 1` on any failure (no mod-256 wrap), and each test runs
  under a timeout so a hang can't block the suite.
- **License + attribution:** full GPLv3 `LICENSE.txt` ships with the OS; the
  README clarifies that the `Reference/OpenOS/` tree is third-party MIT code, not
  part of TOS and not shipped.

## v1.4.0 "Iris" — the Desktop, the Settings app, and a friendlier face

TOS grows a face that isn't a prompt: a tile-based **Desktop** home screen,
a visual **Settings** app, and file-type glyphs in the browser — all layered
on the existing panels shell (the prompt stays one keypress away, exactly
where operators left it). Also folds in the earlier unreleased maintenance
pass below (dead-code prune, one security fix, dormant features wired up,
JBOD re-homed as opt-in, the mouse add-on).

### The Desktop — land on what the machine can DO
- **New `desktop` tab + command.** A tile grid of apps: the built-ins
  (Files, Monitor, Chat, Mail, Launcher, Settings, Help, Tutorial, Log Out)
  plus a tile for **every command an installed package provides** (tetris,
  mousetest, …) — installed programs are visible, not memorized. Tiles are
  gated by the command registry's tier and live-availability rules, so a
  guest never sees Launcher and a modem-less box never shows Chat. At most
  24 package tiles are shown; the footer reports how many more exist (the
  cap is never silent). (`shell/panels/desktop.lua`, `test_desktop_model`)
- **Runs as a panels TAB, not a separate program.** Activating a tile
  dispatches through the SAME executor as typing the command: tier gates,
  output routing, and screen-taking TUIs behave identically. F2 cycles
  between Desktop and Shell like any other tabs; F4 closes it; `desktop`
  (or System → Desktop) reopens it and re-scans installed packages.
- **Per-user landing.** New profile field `landing = "desktop"|"shell"`
  decides what a login lands on. No preference saved: root keeps its
  shell-first muscle memory; everyone else starts on the Desktop.
  (`kernel/profile.lua`, `test_profile_landing`)
- **Keyboard-first, mouse-optional, tier-degrading.** Arrows/Enter, 1-9
  quick-launch, Ctrl+Q to the shell; with the mouse add-on, click a tile
  to open it (right-click selects), scroll to move. T2+ draws bordered
  tiles with CP437-flavoured glyphs; a T1 mono / narrow screen degrades
  to a numbered launcher-style list — same model, leaner presentation.
- Header clock ticks on the same 1 s cadence as the status bar
  (header-row-only repaint — the dirty-cell display buffer keeps it cheap).

### The Settings app — forms instead of memorized commands
- **New `settings` tab + command** with four pages: **Appearance** (theme
  preset cycling with LIVE preview; "Save as my theme" / "Forget my saved
  theme" — preview ≠ persist, mirroring `theme` vs `theme save`),
  **Status Bar** (widget checkboxes; applies + saves immediately, same as
  the old menu-bar row), **Desktop** (the landing preference; saves to
  ~/.profile.cfg on change), and **System** (buttons dispatching
  `bootsettings` / `users` / `doctor` / `about` through the executor —
  admin buttons hidden below tier 2). (`shell/panels/settingsapp.lua`,
  `test_settings_model`)
- Reachable from the Settings menu ("Settings App"), the Desktop tile, or
  the `settings` command. Lazy-loaded: it isn't parsed until first opened,
  mirroring the lazy command categories (RAM matters on T1).

### Shared TUI toolkit + browser glyphs
- **New `shell/panels/ui.lua`** — a small shared widget toolkit (tile-grid
  geometry, framed tiles, setting rows, value cycling, selectable-row
  navigation, file glyphs). Pure layout math, unit-tested off-box; the
  Desktop, Settings app, and browser all draw from it instead of
  hand-rolling. (`test_ui_toolkit`)
- **File browser type glyphs.** A one-cell glyph column: `■` directory,
  `«` parent, `♦` lua, `≡` text, `§` config, `¶` man page, `▓` archive,
  `·` other. Drawn as single-cell overlays so multi-byte UTF-8 never
  skews the ASCII column math; the Name header shifts to match.
- New modules registered in the system manifest and added to the sandbox
  require deny-list (sandboxed code cannot reach shell internals — the
  new `ui`/`desktop`/`settingsapp` modules join the existing entries).

### Command consolidation — less surface, same power
A pass to merge overlapping commands into one obvious door each, so `help`
lists fewer names without losing any capability. Nothing was released yet,
so the old names are simply gone (not deprecated).

- **Aliases collapse in help.** A dozen second names (`dir`=ls, `type`=cat,
  `time`=date, `clear`=cls, `top`=monitor, `diag`=doctor, `colors`=theme,
  `rs`=redstone, `inv`=inventory, `set`=export) still dispatch, but `help`
  now renders them on the canonical row — "`ls` (dir)" — instead of a row
  each. (`REGISTRY` `alias` field, `helpList` collapse; `test_command_registry`)
- **Subcommand folds** (old name removed, function preserved):
  `ver` → `about` (which now carries the hardware one-liner);
  `device` → `hostname` (no-arg shows type + host, arg sets the host);
  `swap` → `optimize swap [status|keys|clear|on|off|auto]`;
  `restore` → `trash restore`;
  `servers` → `net servers` (the standalone `/usr/bin/servers.lua` deleted);
  `disk install` → `pkg from-floppy` / `pkg install-dir` (disk keeps
  list/info/eject, its real removable-media niche).
- **Launcher retired; the Desktop is the menu surface.** `launcher`/`apps`
  are gone — the Desktop already tiles built-ins + package commands, and now
  also tiles your personal `~/.launcher.cfg` entries. The one launcher
  feature the Desktop couldn't cover, the keycard menu, survives as the
  honestly-named `tape-menu` (a Desktop tile when a tape drive is present).
  The launcher ENGINE stays in `shell/launcher.lua` for the locked guest
  `kiosk`. (`test_desktop_model`)
- **Settings gains a Language page** — pick your UI language from Settings →
  Language (live preview + saved to profile), so `lang` is no longer the only
  door. (`test_settings_model`)
- **`pkg install` is now one smart verb.** The three install paths merged:
  a **name** installs by name (deps + hashes), a **path** (anything with a
  `/`) installs that directory, and **no argument** scans mounted media and
  prompts per package. `install-dir` and `from-floppy` still work as hidden
  aliases. New top-level shortcuts **`install <name>`** / **`uninstall
  <name>`** route to `pkg` (collapsed onto its help row) so a new operator
  needn't know the manager is called `pkg`. Docs + man pages resynced.
- `MANUAL.md` and the command glance-lists resynced to the merged surface.

### Unmanaged drives — TBFS, a real filesystem on raw sectors
TOS can now use **unmanaged** OpenComputers drives (raw `drive` components —
`readSector`/`writeSector`, no built-in file API), not just managed disks.
- **Detection in the base image** — `hal.scan`, `lsdev`, `hw`, and the System
  Configuration screen now show raw drives as *Raw Drive* instead of leaving
  them invisible. A base `drive` command inspects them (`drive list` /
  `info` / `read <sector>`) with no package required.
- **New `blockfs` Extras package = TBFS**, a real hierarchical filesystem laid
  onto the bare sectors. It presents the exact managed-`filesystem` interface
  TOS already mounts, so once mounted a raw drive behaves like any other disk —
  securefs, the browser, `cp`, everything works unmodified. Design: superblock
  + block bitmap + inode table + data region; files map logical→physical blocks
  via 8 direct + single- + double-indirect pointers (a single file scales into
  the megabytes); directories are files of `{name, inode}` entries;
  **layout-aware allocation** keeps a file's blocks contiguous so the simulated
  platter head doesn't seek. Pure driver (touches only the drive proxy) —
  **52 off-box unit tests** cover format, subdirs, r/w/append/seek, large files
  through double-indirect, recursive remove, rename, persistence, fragmentation,
  defrag, and fsck. (`TOS-Extras/modules/blockfs`, `test_blockfs`)
- **`drive` command** (with `blockfs` installed): `format`, `mount`, `check
  [--repair]` (fsck: rebuilds free counts from reachability), and `defrag`.
- **Defragmentation** — fragmentation is expected as a disk churns, so TBFS
  ships a compactor: `drive defrag <addr>` repacks every file into contiguous
  runs (manual), and `drive defrag <addr> --if-over N` only acts past an N%
  threshold — drop that in a `cron` job for automatic upkeep. `drive info`
  reports live fragmentation; `drive mount` warns when it's high.
- **Installing TOS onto a raw drive (substrate).** TBFS gained a **boot
  region** — a contiguous run of sectors (recorded in the superblock) holding a
  self-contained stage-2 boot blob, so a tiny EEPROM can read+run it with no
  in-firmware filesystem parser. `blockfs.bootBlob` assembles the blob (the
  driver embedded + a bootstrap that mounts the drive as root and hands off to
  `/init.lua`); `writeBoot`/`readBoot` store and retrieve it. **`deploy drive
  <addr>`** (root) formats a raw drive as a bootable TBFS volume, copies the OS
  onto it, and writes the blob — but first checks for the `blockfs` package and
  **fails loudly** (`pkg install blockfs`) rather than half-writing a disk. The
  blob is proven end-to-end in tests: assembled from the real driver source, it
  runs in a stubbed boot environment, mounts the TBFS root, and boots into
  `/init.lua`. (`test_blockfs`, 67 assertions)
- **TBFS-aware BIOS — TOS now BOOTS from a raw drive.** The EEPROM was
  rewritten leaner (the old build barely fit; the new one is 3775 bytes
  stripped, 321 free) and gained the TBFS boot path: it checks the stored boot
  address (managed **or** raw drive), then falls back to scanning managed
  filesystems, then raw drives — reading the TBFS superblock and contiguous
  boot region directly, no filesystem parser in firmware. A fallback raw drive
  gets the **same #SEC H1 approval prompt** as a changed floppy (`Y` commit /
  `Shift+Enter` one-time / halt), and the BIOS hands the chosen drive to the
  stage-2 blob (`_TBFS_BOOT_DRIVE`) so a multi-drive box can't mount the wrong
  volume. `init.lua` pivots to the mounted unmanaged root
  (`_TOS_UNMANAGED_ROOT`), and the blockfs mount proxy now carries
  `.address`/`.type` so `_TOS.bootAddr` and the auto-mount gate work
  identically on a TBFS boot. The whole chain is regression-tested end-to-end:
  a fake raw drive is formatted with the real driver, and the real BIOS boots
  it under stubbed OC globals — plus managed-path and approval-flow scenarios
  and a hard 4 KiB byte-budget check. (`test_bios`, 29 assertions)

### Hardening pass — external review, 12 of 13 findings fixed
An external failure-point review (verified claim-by-claim before acting)
drove a resilience pass over the boot chain, scheduler, shutdown path, and
event pump. In rough order of impact:

- **Lua 5.3 architecture guard.** Eight kernel modules use 5.3 bitwise
  *syntax* (and the boot chain uses `string.pack`), so a CPU switched to the
  Lua 5.2 architecture used to die with a raw syntax-error panic from a
  perfectly healthy disk. Both the BIOS and `/init.lua` (itself kept
  5.2-parseable) now probe the parser (`load("return 1<<1")`) and halt with
  the actual fix: "sneak-click the CPU to switch". hal.lua's misleading
  "Tier 1: Lua 5.2" comment corrected; requirement documented in README.
- **`kernel.shutdown` can no longer abort half-dead.** `net.shutdown()`, the
  farewell screen draw, `audio.shutdown()`, and each `proc.kill` are now
  pcall'd, so a modem/screen pulled during shutdown can't prevent the clean
  "C" pwrstate stamp + power-off — no more spurious "PREVIOUS SHUTDOWN WAS
  UNSAFE" eroding trust in the marker.
- **GPU/screen hot-removal no longer crashes the drawer.** display.init
  wraps the GPU proxy once at a single choke point: every method is pcall'd;
  on the first failure the display goes quiet (getters keep returning
  last-known-good values), a `tos_display_lost` signal fires exactly once,
  and `display.init(newProxy)` is the reattach path. The BIOS `P()` is
  likewise guarded — a screen pulled mid-boot silences output instead of
  halting the BIOS with a machine error. (`test_display_lost`, 14 assertions)
- **Runaway processes that trap preemption are now attributable.** The
  wall-clock kill is an ordinary error, so hostile code spinning inside its
  own `pcall` traps it and the machine eventually dies to OC's yield
  watchdog — unavoidable in pure Lua, but now: the hook writes a
  `/var/crash/preempt.txt` breadcrumb naming the culprit (removed the moment
  the scheduler regains control, so its survival at next boot MEANS watchdog
  death — `doctor` surfaces it), and the hook re-arms at count=1 after the
  deadline so the trap loop starves instead of computing. Residual risk
  documented in README Known Limitations.
- **Floppy→HDD migration copy hardened.** Free-space check *before* the
  first write; files stream in 4 KB chunks (failures surface at the failing
  chunk, not after buffering whole files in RAM); the write check catches
  both `false` and `nil` failure shapes.
- **Boot-device scans survive a disk yanked mid-scan.** `exists()` is
  pcall'd in the BIOS and both init.lua fallback scans — a dying component
  is skipped instead of killing the whole scan.
- **Timer-callback errors are no longer invisible.** The event pump counts
  them (with source attribution) and lazily flushes a summarizing `log.warn`
  once the log is available; `event.timerErrors()` exposes the vitals.
- **Headless hot-plug no longer swallows a signal** (the bare 0.5 s
  `pullSignal` settle-wait was unnecessary — the check reads live component
  lists and re-triggers on the next `component_added`).
- **Smaller wins:** shell fallback poll is now adaptive (20 Hz under load,
  stretching to 2 Hz idle — input latency unaffected); human keypress
  *timing* (never key codes — the pool is exported to `/etc/entropy`) feeds
  the RNG continuously, throttled to ~1/s; a `local component =
  require("computer")` landmine renamed; `run_tests.sh` now requires exit
  code 0 *and* the pass marker, so a teardown crash can't count as a pass.
- **Finding #9 (landed in the follow-up pass below):** per-process
  signal-type interests to cut modem-flood fan-out.
- BIOS after all of the above: **3953 bytes stripped, 143 free** of the
  4 KiB EEPROM (the byte-budget test now enforces ≥128 headroom).

### Queue clear-out — the deferred perf + privacy follow-ups
The items parked "for later" from the review and the June perf playbook,
now done (the playbook's big pieces — dirty-cell shadow buffer, colour-state
cache, `gpu.copy` scroll — were already in; VRAM bitblt stays deferred until
it can be emulator-verified on a real T3 GPU):

- **Per-process signal-type interests (review finding #9).** Every broadcast
  signal used to resume EVERY live process — a modem flood cost one resume
  per process per packet. A process may now declare interests at spawn
  (`opts.signalInterest = { "modem_message", ... }`, list or set form) or on
  itself at runtime (`proc.setSignalInterest`); non-input broadcast types
  outside the set skip its resume entirely. Directed (queued) signals, input
  ticks, and timeout ticks always wake it, and NO declaration = wake on
  everything — nothing changes for existing code. (`test_signal_interest`,
  17 assertions)
- **Partial-diff row trim in the seat draw path** (playbook: "batched runs
  within a changed row"). When a redrawn span partially matches the shadow
  buffer, the proxy now trims the matching prefix/suffix and sends only the
  changed window — still ONE `gpu.set` (splitting interior runs would add
  calls, and calls are the expensive part), but a status-bar clock tick now
  ships ~5 chars instead of the whole 80-column row. Pure decision in
  `screen._diffWindow`. (`test_screen_shadow`, +10 assertions)
- **`/var/mail` is now private at rest (#SEC).** E2E sealing protects mail
  in flight, but the delivered inbox is plaintext — and the generic `/var`
  ACL branch granted READ to any logged-in session, guest included. Now
  `/var/mail/<user>` is owner-or-ADMIN+ (checked before the system-path
  branch, traversal-safe via the H11 normalize), and listing `/var/mail`
  hides other users' mailbox names, same posture as `/home`. Delivery is
  unaffected (the mail controller writes via the raw kernel fs).
  (`test_mail_privacy`, 11 assertions)

### Boot Settings grows up — Safe Mode, self-repair, CLI startup, honest overrides
The operator asked for more knobs: more profiles, a real recovery story, and
the ability to tell TOS what it has — within reason. The rule that shaped the
"within reason": overrides exist only where detection is genuinely uncertain
(CPU/Data Card tier heuristics, RAM *headroom* judgement); reliably-detected
hardware (GPU, screen, modem) deliberately has none — TOS trusts what it can
see.

- **Safe Mode (`profile safe`).** Kernel + shell only: no rc.d services, no
  cron jobs, no package-provided commands, no net, no themes — nothing
  third-party runs — but the `pkg` ADMIN verbs still work, so the broken
  add-on that made you boot safe can be removed on the spot. Boots loud (SAFE
  MODE banner, text log). To make it real, the boot stages that run foreign
  code became gateable features: `services`, `cron`, and `packages` join the
  profile/advanced system (minimal now skips them too; normal keeps today's
  RAM-gated behavior; an advanced override still beats the profile — safe +
  `net on` is a legitimate remote-rescue combo). Package dispatch is cut at
  one choke point (`pkg.setDispatchEnabled`) so admin verbs survive.
- **One-time Safe Mode: press S at the POST screen.** Boots safe for THIS
  session only — `/etc/boot.cfg` untouched, next boot is normal. The fastest
  path to a trustworthy shell when something you just installed breaks boot.
- **Self-repair (`repair on` / Boot Settings → "Self-repair next boot").**
  A ONE-SHOT pass that runs right after the filesystem comes up (flag clears
  itself first — a crashing repair can never loop). Fixes what's mechanically
  safe: finishes interrupted atomic writes, sweeps orphaned `.tos-tmp` files,
  clears stale `/var/run` state, trims oversized logs (keeping the tail —
  newest entries explain the problem), rewrites a corrupt `boot.cfg`. Only
  REPORTS what isn't: a corrupt `users.dat`/`trust.dat` or a missing critical
  file is a warning, never an auto-replace — the wrong fix locks operators
  out. (`kernel/repair.lua`, injected-deps + fully pcall'd; `test_repair`,
  20 assertions)
- **CLI startup (`ui cli`).** Boot every seat straight into the minimal CLI
  shell — no panels parse/load at login, the lightest startup there is. A
  default, not a lockout: `tui` opens the full interface on demand.
- **RAM declaration (`ramgate auto|plenty|tight`).** The optional-stage gates
  used to trust only the live free-RAM measurement; now the operator can
  declare "plenty" (force the extras on) or "tight" (behave like a low-memory
  box). The security subsystem ignores it on purpose — no declaration can
  switch off auth.
- All of it reachable from BOTH surfaces: the DEL Boot Settings editor (new
  fields: Interface, Self-repair next boot, RAM for extras; profile ring gains
  SAFE MODE) and the `bootsettings` CLI (`ui`, `repair`, `ramgate`, `profile
  safe`). (`test_bootcfg` 61, `test_bootsettings` 54 assertions)

### Multi-seat no longer freezes — cooperative yields + a non-blocking monitor
An operator reported that on a multi-seat box, one user's action froze *every*
seat (and even on a single seat, the UI locked up during long commands). Root
cause: TOS is a cooperative scheduler, and two paths never yielded — long
commands ran to completion in one resume, and the System Monitor (Ctrl+T) ran
*modally inside the kernel loop*, so while any seat had it open `proc.tick`
never ran and the whole machine stalled. The shared-CPU ceiling is a mod limit,
but the *freezing* was ours to fix:

- **`proc.yieldCooperative()` — a throttled mid-work yield.** A no-op until the
  current resume has run one slice (~50 ms), then it yields; the scheduler
  resumes the process with **nothing** and leaves its signal queue untouched,
  so a user's typed-ahead keys during a long command reach the shell's real
  event loop instead of being eaten by the command's yield point. Fast commands
  pay only a clock compare and never actually yield. (`test_coop_yield`,
  10 assertions)
- **Heavy paths instrumented.** The executor funnels every command's output
  through one `o()` chokepoint, so printing commands (`ls -R`, `find`, `du`,
  `grep`, `verify`) slice for free; the silent walkers (`find`/`du` recursion),
  `fs.copyRecursive`, `pkg install` (between files — read→hash→write stays
  atomic per file), `compress` (between deflate/inflate chunks), `deploy drive`,
  and `blockfs check` (read-only scan; **not** `--repair` or `defrag`, where a
  yield window would let a concurrent write tear the snapshot) all yield now.
- **System Monitor runs as a per-seat process.** Ctrl+T spawns a seat-bound
  monitor process (foreground handoff + restore, one-per-seat guard, dead-pid
  self-heal) that pumps via `coroutine.yield` — the kernel loop keeps ticking
  and other seats stay live while it's open. Its switch/kill/TSR actions stay
  gated by its own `canAct` policy; `proc.setForeground` gained a
  trusted-caller `{kernel=true}` bypass (mirroring `proc.kill`) so the switch
  stays god-mode as before — safe because the package sandbox hard-blocks
  `require("kernel.*")`, so untrusted code can never reach `proc`.
  (`test_fg_ownership` extended, 11 assertions)
- **Documented the honest limit.** README + MANUAL now state that multi-seat is
  supported but **sequential** operator use is recommended — simultaneous users
  share one CPU and slow each other; TOS makes that a slowdown, not a freeze,
  but can't remove the ceiling.

### The visual grammar — one look across every surface
Operator-interviewed and spec'd (five rules, recorded in TODO.txt), then
applied across the shell, Desktop, Settings, dialogs, and launcher — the
fix for "a mismatch of ideas that could work together". Keybindings and
commands unchanged; T2 80x25 is the design target, T1 mono degrades
cleanly (ramps become plain fills, inverse still reads).

- **Rule 1 — frames rank attention.** Dialogs (modal) now wear
  double-line ╔╗ frames + the ▓ shadow; passive containers (tiles,
  panes) keep single-line. (`panels/dialogs.lua`)
- **Rule 2 — rails are the skeleton.** New `ui.railText/drawRail`
  (`─┤ label ├─`, column-tracked, ustr-safe): the shell's path/columns
  row, a NEW summary rail above the output row (`N items · free`, free
  space cached by loadFiles so drawing never touches the fs), the
  Desktop header/hint, the Settings header. (`test_ui_toolkit`)
- **Rule 3 — ░▒▓ at edges only.** `ui.drawRampBar` caps the status
  bar, view/editor footers, Desktop/Settings key bars, and the
  launcher's footers. Never inside content.
- **Rule 4 — hierarchy by contrast.** Chrome (menus, rails) renders
  dim; data (files, values) bright; selection inverse. Density kept.
- **Rule 5 — tabs speak state.** The tab bar merges with the menu bar
  into ONE top row (menus left, chips right, ░ filler between): the
  active tab is an inverse chip, a BUSY tab renders `[bracketed]`
  (live tabs refreshing, editors with unsaved changes — the operator's
  idea), idle tabs plain. Net effect with the path rail: two chrome
  rows become one + one, and the file list gains a row.
- **Mouse can't drift**: draw.topBar stores its menu/tab spans on the
  session (`S._menuSpans`/`S._tabSpans`) and mouse.lua hit-tests those
  same tables — plus F9-parity: clicking a menu from a non-shell tab
  jumps to the shell first. (`test_panels_mouse`, now 70 assertions)

### Emulator round 3 — tab overflow, honest storage, AMIBIOS frame
- **Every tab is mouse-reachable again.** With six menus on an
  80-column merged bar, the chip zone is ~24 columns — a third tab
  pushed the Shell chip clean off the row (operator report). Chips now
  auto-shrink their labels (10→8→6→5 columns), which fits three tabs in
  the worst case; beyond that the row leads with a clickable **«N
  overflow chip** that acts as a wrapping previous-tab button, so
  repeated clicks walk the entire tab list no matter how many exist.
  (`ui.fitChips`, `panels/draw.lua`, `panels/mouse.lua`,
  `test_ui_toolkit`, `test_panels_mouse`)
- **Storage rows tell the truth.** The POST screen called the Optional
  Utilities floppy AND OC's built-in scratch filesystem "RAM Disk" —
  the operator rightly counted two disks + a floppy and asked what the
  fourth drive was. sysinfo now tags the tmpfs component at gather time
  (`computer.tmpAddress()`), names it by its mount point (**Temp
  /tmp**, tier "RAM"), and gives real floppies AMIBIOS-style letters
  (**Floppy A**, **Floppy B**). Nothing is called "RAM Disk" anymore.
  (`kernel/sysinfo.lua`, `sysinfo.diskRole` — pure + tested,
  `test_sysinfo_post`)
- **The System Configuration screen wears its AMIBIOS suit properly**
  (operator suggestion, reference photo supplied): a double-line outer
  frame with the title riding the top border, a ╡ Storage ╞ section
  divider, and a │ column divider through the spec grid — composed to
  exact column width so multi-byte frame chars never hit byte-clipping.
  Narrow T1 screens keep the plain dashed layout.
- **Boot Settings scrolls the SETTINGS, not the hardware view**
  (operator suggestion): the settings list now gets whatever rows are
  left after the help lines and (when open) the hardware viewer, keeps
  the selection visible with ^/v "more" markers, and never shrinks
  below four rows. Previously the advanced list just ran off the
  bottom. (`kernel/bootsettings.lua`)
- **Ctrl+T monitor: the Services rule no longer ends in garbage.** The
  separator counted BYTES ("─" is 3 bytes, 1 column), under-filled by
  4, and dsp.fit then byte-sliced a ─ in half — the "▓…" artifact in
  the operator's screenshot. Column math now. (`kernel/init.lua`)
- **Kernel idle tick relaxed 20 Hz → 10 Hz.** An audit prompted by
  emulator lag (~6 TPS on the operator's host) found TOS signal-driven
  throughout — no busy loops — but the kernel main loop woke 20×/s
  even when idle. event.pull returns immediately on real signals, so
  the longer timeout costs zero input latency; it just halves TOS's
  standing wake-up load on the host, and matches the shell loop's own
  0.1s cadence. (The lag itself is host-side — see the operator
  checklist in the session notes.) (`kernel/init.lua`)

### i18n — community-translatable UI (framework)
- **New `kernel.i18n`** — language catalogs as pure DATA files at
  `/usr/lang/<code>.lang` (kernel.serialize table literals; comments
  allowed; parsed by the safe decoder, never executed). Every call site
  keeps its English inline — `i18n.t("login.username", "Username:")` —
  so no catalog, a missing key, or a corrupt file always yields exact
  current English behaviour, and PARTIAL translations are valid by
  design. Catalogs are size/entry-capped and code-validated (the code
  doubles as the filename, so the pattern is also path-traversal
  protection). (`test_i18n`)
- **New `kernel.ustr`** — display-column string helpers (len/width/fit/
  pad/center) over OC's `unicode` API, byte fallback off-box. Translated
  text is multi-byte UTF-8 (and CJK is double-width): byte math would
  split characters and drift centring. Used by the converted surfaces;
  `ui.drawTile`/`drawBar` now width-fit labels. (`test_ustr`)
- **Selection**: `/etc/tos.cfg` `language` is the system default
  (applied at boot, so the login screen renders translated); the new
  profile `lang` field overrides per-user at login. New `lang` command:
  `lang` lists catalogs, `lang <code>` sets yours (live + profile),
  `lang system <code>` (admin) sets the machine default, and
  **`lang dump`** writes a translator template of every key seen this
  session — community translations never touch code.
- **Proof surfaces**: the login screen (with the label column now sized
  from the translated labels, so "Имя пользователя:" widens the field
  layout instead of overlapping the input) and the Desktop (tile
  labels, hints, footer keys). Plus a **Russian seed catalog**
  (`/usr/lang/ru.lang`) covering exactly those — a starter for the
  community, not a finished translation. Command output, help, and man
  pages remain English this phase.
- Known limits, documented in the module header: the active catalog is
  system-wide (multi-seat: last login wins), and typing non-Latin text
  into prompts is a separate future project — display is solved, input
  is not.

### Emulator rounds — fixes from the first real runs
- **Module loader: a transient OOM no longer masquerades as a circular
  dependency.** `tosRequire` set its `loading[name]` marker and then could
  RAISE from unguarded places (`bootFS.read` inside readFile, or `load()`
  itself) on a low-RAM box — leaving the marker set. The retry then hit a
  bogus `Circular dependency: shell.panels.commands.core`, which the
  command loader rightly caches as a permanent code error: every core
  command walled off for the session (seen in a real kernel log). The
  loader body now runs under pcall and ALWAYS clears the marker, so the
  OOM-nudge-GC-and-retry self-heal actually works and "Circular
  dependency" again means only real cycles. (`init.lua`)
- **Desktop no longer costs RAM on minimal boxes.** The desktop module was
  required unconditionally at shell start (events.lua top-level require +
  the background tab open) — enough extra parse weight to push a
  ~230KB-free machine into the OOM above. It's now lazy like the Settings
  app, and the background Desktop tab is only pre-opened with ≥300KB free
  (or when the operator actually lands on it); the `desktop` command still
  opens it on demand. (`panels/events.lua`, `panels/init.lua`)
- **`dim` text no longer turns PINK on a T2 GPU.** The T2 palette has no
  mid-grey, and by raw channel distance 0x909090 (the default preset's
  `dim`) is genuinely closer to 0xCC66CC (pale magenta) than to 0xCCCCCC —
  so switching to the "default" preset made hint/clock/dim text pink,
  while the boot fallback looked white. `snapToT2` now snaps
  near-achromatic colors (channel spread ≤ 32) only onto the palette's
  greys; chromatic snapping is unchanged. (`kernel/display.lua`,
  `test_theme_snap`)
- **`help <cmd>` no longer advertises manual pages that don't exist.**
  The registry-driven help footer told every command's reader to "run
  `man <cmd>` for the manual" — and `man launcher` answered "No manual
  page", a dead-end referral loop. The tip now checks
  `/usr/man/<cmd>.man` first and only mentions `man` when the page is
  really there. (`commands/core.lua`)
- **`pkg from-floppy`'s question kept its "[y/N]"**. The confirm prompt
  named the full nested repo path (88 columns), and promptInput's
  `:sub(1, W)` chopped the "[y/N]: " affordance AND the echo of the
  typed answer off the right edge — the operator was typing blind.
  Two-part fix: the question now names the disk (`/mnt/disk_bff0`)
  instead of the whole path, and promptInput middle-ellipsizes any
  over-long message so the tail (the affordance) and ~10 columns of
  input echo always stay visible (`dialogs.fitPrompt`, tested).
  (`commands/admin.lua`, `panels/dialogs.lua`, `test_dialogs`)
- **The screen no longer goes "mostly blank + flickery" after a game of
  Tetris.** A sandboxed package command draws raw through its
  `component` capability — straight past the seat's dirty-cell shadow
  buffer. On exit the shadow still believed the OLD shell screen was on
  the GPU, so the full repaint elided every "unchanged" cell: the
  operator got the game's black leftovers with only the rows whose
  content had really changed (hint, prompt, status bar) repainted, plus
  menu-bar flicker as later draws fought the stale shadow. The executor
  now drops the shadow (`display.invalidate`) after any foreign program
  runs — package commands and /usr/bin scripts — so the next redraw
  actually reaches the GPU. Builtins (which draw through the proxy and
  keep the shadow coherent) are untouched. (`panels/executor.lua`,
  `test_executor_invalidate`)

### Previously "Unreleased" — prune, a security fix, and two opt-in features

A maintenance pass: dead-code prune, one real security fix, several dormant
features wired up, plus JBOD re-homed as an opt-in feature and a new mouse
add-on.

### Emulator round — low-memory resilience + boot/live polish
- **Core commands no longer die permanently on a transient OOM.** On a minimal
  box (T1 GPU, no data card, ~250 KB free), loading the large `core` command
  category could fail with `not enough memory for buffer allocation` — and the
  loader then cached the failure, leaving the shell with *zero* core commands
  for the rest of the session (every command read "command not found"). The
  loader now distinguishes an OOM from a code error: it nudges a GC
  (`_TOS.kernel.gc`, guarded) and retries once, does **not** cache an OOM
  (so a later command self-heals once RAM frees), and surfaces a plain-English
  "needs more memory than is free (NKB) — free RAM and retry" line instead of a
  baffling "command not found". Found via a real emulator kernel log.
- **`watch` proves it's live.** `watch ps` on an idle box looked frozen because
  the output is identical every tick; the LIVE tab header now carries a rising
  `⟳N` refresh counter so liveness is visible even when the body doesn't change.
- **Splash loading bar no longer fills early.** The bar advanced per INFO line
  against a fixed estimate (40), so a full-featured boot (~55–60 lines)
  saturated the bar around "Network ready" — long before the boot tone. It now
  tracks distinct boot *stages* reached (`bootsteps.STAGE_COUNT`) and snaps to
  full exactly at "Boot complete".

### Operator tooling — why / screendump / crash recorder / live monitor
Four operator quality-of-life tools, prompted by an in-emulator test round.

- **`why` — explain a "permission denied".** `why` (no args) explains the last
  command this seat was blocked on, in plain English, with the fix; `why <cmd>`
  explains what any command requires (tier) and whether you can run it. Turns an
  opaque denial into a self-service answer. Reads the required tier from the
  command registry (single source of truth) vs the seat's live tier; pure
  formatter in `helpers.whyExplain` (`test_why.lua`).
- **`screendump` — capture the screen to a text file.** `screendump [path]`
  writes exactly what's on this seat (read from the display shadow buffer when
  active, else `gpu.get`) to a file — including a garbled/panicked TUI — for bug
  reports. New `proxy.dump()` on the per-seat display proxy.
- **Crash flight-recorder.** On a kernel panic or an unrecoverable-shell drop,
  TOS now flushes a post-mortem (reason, uptime, free RAM, the dmesg ring, and
  the panic traceback) to `/var/crash`; the next boot surfaces a one-line
  "Last run crashed: …" and clears the marker. Read the reports with the new
  admin-gated **`crash`** command. `kernel.crashDump` / `kernel.checkLastCrash`;
  the top-level panic handler writes via the boot FS when the kernel died too
  early to expose the helper.
- **System Monitor is now a scrollable live tab.** `monitor` / `top` open a
  roomy, per-seat **live tab** (auto-refreshing process/service/memory view) so
  text no longer truncates in a cramped box and two seats don't fight over one
  centred dialog. Ctrl+T still opens the interactive switcher for the actions
  (switch / kill / start-stop). Kernel feed `kernel.monitorSnapshot`; pure
  renderer `monitor.textRows` (extended `test_monitor.lua`).

### Test harness — centralized + leak-proofed
- **The test runner was leaking into Release.** `build-release` excluded the
  test FILES (`/usr/lib/tests/`) but not the runner script, so
  `run_tests.sh` shipped in TOS-Release (a runner with no tests). Both build
  scripts now exclude `/run_tests.sh`.
- **One harness runs everything.** `run_tests.sh` now runs the TOS-Dev unit
  tests AND the Optional Utilities package + build tests (`../TOS-Extras`) in
  a single pass with one combined total (75 tests) — no more running the
  Extras tests separately by hand.
- **A guard keeps it honest.** `test_release_excludes.lua` asserts both build
  scripts exclude every dev-only path (and that a built TOS-Release carries no
  test artifacts), so this class of leak can't silently regress.

### Command UX in the panels shell
- **Tab completion (was never wired).** The idle legend advertised a Tab
  binding and `commands.commandNames()` existed "for tab completion", but the
  Tab key had no handler — pressing it did nothing. Tab now completes: the
  first word against command names (built-ins **and** installed package
  commands), later words against file/dir names in the target directory. One
  match fills in (with a trailing space, or `/` for a directory); several fill
  the common prefix and list the matches on the status row. The idle legend's
  stale "Tab Panes" is corrected to "Tab Complete" (cycling tabs is F2). Pure
  core in `helpers.completeToken`/`completeCmdline`; `test_completion.lua`.
- **Live "Running …" feedback.** A command used to show nothing until it
  finished, then dump its output — so a slow `verify`/network command looked
  frozen and you couldn't tell your Enter registered. The status row now shows
  `Running <cmd>…` before the command blocks.
- **Short output no longer opens a tab.** Output routed to the lightest surface
  that fits: 1 line → status row, ≤ 8 lines → a transient inline region just
  above the prompt (cleared on the next keypress, file browser stays put),
  only genuinely long output → a scrollable view tab. (`helpers.routeOutput`;
  `test_output_routing.lua`.)

### Manual control of optimizations
- **New `optimize` command.** Surfaces and toggles performance optimizations
  in one place: `optimize` shows status; `optimize swap <on|off|auto>` flips
  the disk-swap boot feature (persists in boot.cfg, applies next boot);
  `optimize buffer <on|off|auto>` toggles the display dirty-cell shadow buffer
  at runtime (applies immediately across seats). The buffer override is
  invalidation-safe — toggling re-syncs live proxies so re-enabling can't leave
  ghost cells — and `auto` keeps the memory-gated default. (`screen.setBuffer`
  / `screen._shadowWanted`; `test_display_buffer.lua`.)

### Optional Utilities packages
- **Tetris multi-line clear fixed (1.1.0 → 1.1.1).** Completing 2+ rows at
  once cleared the WRONG rows and left some completed lines on the board —
  "they clear one at a time instead of all at once." The lock loop
  interleaved `table.remove` with `table.insert(board, 1, …)`, so each
  top-insert shifted the not-yet-removed cleared indices. Line clearing is now
  a pure, unit-tested pair (`fullRows`/`removeRows`) that removes all
  completed rows before refilling. (`modules/tetris`; `test_tetris_sandbox`
  now covers double/quadruple clears.) Audit pass: all packages load; mouse /
  tetris / tape-authenticator tests pass; tape / rc-pilot / cluster-* have no
  tests and still need in-emulator (hardware/network) verification.

### Boot verbosity — each option now does what it says
Audited all four; two didn't match their label, and the mapping had no single
source of truth. (`test_verbosity.lua` now pins the whole matrix.)

- **`silent` leaked text.** Two boot lines ("Loading kernel modules…",
  "Boot complete: …s") were direct `earlyPrint` calls that bypassed the
  verbosity muter, so a "silent" (and "splash") boot still printed them. They
  now go through a gated `bootEcho` — shown only at text/verbose.
- **`verbose` wasn't verbose.** It set the echo threshold to DEBUG but the
  log's STORAGE floor stayed at INFO, so DEBUG entries were dropped before
  they could echo — verbose was just text with timestamps. The storage floor
  now follows the verbosity (DEBUG when verbose). `verbose` also now shows the
  System Configuration "hardware table" the bootcfg contract promised, even
  when `showConfig` is off.
- **Single source of truth.** The verbosity→log-level mapping moved to
  `bootcfg.echoMinLevel()` (was an inline table in the bootloader), so the
  bootloader and the tests can't drift. silent=FATAL-only, splash=WARN+ (the
  bar narrates INFO), text=INFO+, verbose=DEBUG+.

### Operator polish
- **Splash boot now shows a loading bar + high-level narration.** The
  "splash" verbosity used to mute the per-stage boot log and show nothing but
  the wordmark until login. It now drives a fill bar AND a 3-line rolling
  narration that describes what TOS is doing in plain language (e.g.
  "Loading OpenOS compatibility layer", "Starting networking") — the noisy
  internal chatter collapses into a clean sequence of big steps. So "splash"
  is a real visual boot, while "text" still shows the full live log for free.
  Crucially the bar can't hide a problem: WARN/ERROR messages are shown
  verbatim and coloured (never simplified away). The raw-message → step map is
  the pure, tested `kernel.bootsteps`; the bar is driven via a guarded
  `bootProgress` hook in `log.lua`, nil (no-op) in every other mode.
  (`init.lua`, `log.lua`, `kernel/bootsteps.lua`; `test_bootsteps.lua`,
  `test_log_bootprogress.lua`.)
- **Already-inserted media is announced at startup.** The insert auto-detect
  only fired on hot-plug, so a disk present at boot went unnoticed. The shell
  now scans mounted media once at startup and surfaces the first actionable
  disk (e.g. an Optional Utilities disk) on the status row.
  (`helpers.scanMountedMedia`; `test_disk_classify.lua`.)
- **`about` refreshed.** It was frozen at "v0.3.0 [Bastion]" with a stale
  changelog. It now reads the live version/codename + vendor/motto and shows
  a current capability summary instead of an old release log. (`about` in
  both shells.)

### Rebrand → Strata Systems LLC
- The vendor identity is now **Strata Systems LLC** (plural of *stratum* —
  layers) across the splash, System Configuration, login, installer banner,
  `about`, the kiosk example, the README license, and every Extras package's
  `author` field (sources updated + the Optional Utilities disk rebuilt). The
  Skynet-flavoured motto ("Firmware with a will of its own.") is kept — it's
  product character, not a company name. (`kernel/logo.lua` `VENDOR` +
  `install.lua` embedded banner; the wordmark itself is unchanged.)

### Optional Utilities install — packages were invisible (now fixed)
- **Disk laid out one level deep wasn't recognized.** If the whole
  `dist/optional-utilities` FOLDER was copied onto a disk (instead of its
  contents), the packages sat under `/mnt/<disk>/optional-utilities/` and the
  disk read as blank "data" — `classifyDisk` and `pkg` discovery only looked
  at the disk root. Both now also look ONE level down, so the disk is detected
  and its packages install whichever way it was assembled. (`helpers.lua`
  `classifyDisk`, `pkg.lua` `mountedRepoRoots`; `test_disk_classify.lua`,
  `test_pkg_discovery.lua`.)
- **Mounted disks were invisible to package discovery.** A disk mounted by
  the KERNEL at boot is a *virtual* mount point — `fs.mount` records it but
  creates no real `/mnt/<label>` directory, so it never appears in
  `fs.list("/mnt")`. `pkg.listAllAvailable` / `installFromFloppy` scanned
  only that listing, so a single-package install (explicit path) worked but
  every package on a multi-package Optional Utilities disk was unfindable by
  `pkg search` / `pkg from-floppy` / the `install.lua` picker. Discovery now
  enumerates `fs.mounts()` (the authoritative mount table), still folding in
  real `/mnt` subdirs for shell-side auto-mounts. (`pkg.lua`;
  `test_pkg_discovery.lua`.)
- **Comment headers made every package manifest unparseable.** `pkg`,
  `mod`, `disk`, and the disk `install.lua` picker all "couldn't see" the
  packages on an inserted Optional Utilities disk. Root cause: each
  `package.lua` manifest carries a `-- …` comment header (and inline `--`
  notes inside the table), but `serialize.decode` — the safe table parser
  these go through — choked on the first `--` ("Invalid number: -"), so
  `pkg.listRepo`/`listAllAvailable` silently found zero packages. The
  decoder now skips Lua comments (line and `--[[ ]]` block) like a real
  tokenizer, and tolerates a `return` that follows a comment header. Still
  `load()`-free / safe for untrusted input. (`serialize.lua`;
  `test_serialize_comments.lua`.)
- **Clearer "protected path" message.** Writing into `/usr/lib`,
  `/usr/modules`, `/usr/bin`, or `/var/pkg` is blocked even for root (a
  defence-in-depth line, not an ACL — so a tampered admin session can't
  swap shipped libs). The denial now says so and points at the supported
  path: `pkg install <name>` / `pkg from-floppy`, instead of leaving an
  operator to conclude root "should" be able to copy files there.

### Mouse: left and right click now differ
- **Left-click = quick action, right-click = context menu.** With the mouse
  add-on, a left-click activation on a file used to open the SAME context
  menu as a right-click (because keyboard Enter on a file opens the menu, and
  the click mirrored it). Now a left-click on the selected file does the
  quick action — enter a directory or **view** a file — while right-click
  opens the context menu for the detailed options. The F3 View key and the
  left-click share one `viewSelected` helper. Keyboard Enter still opens the
  menu (the keyboard's only way to reach options). (`panels/mouse.lua`,
  `panels/events.lua`; `test_panels_mouse.lua`.)

### Low-memory resilience (don't shut down — recover)
- **OOM at login no longer powers off the machine.** On a tight box the
  shell could OOM while loading right after login (`not enough memory for
  buffer allocation`); the kernel then saw zero processes and *shut down*,
  reading as a crash. Now the kernel treats an unexpected all-processes-gone
  as recoverable: it GCs and respawns login a bounded number of times, then
  falls back to the **emergency shell** so the operator can free space / read
  logs instead of being dropped. (`init.lua` main loop.)
- **Shell gets a clean heap.** The kernel now `collectgarbage()`s right
  before spawning the shell (boot leaves a lot of transient garbage) and logs
  the free-memory figure, turning many marginal "just barely OOMs" boxes into
  ones that load. The crash notice is drawn defensively so an OOM during the
  notice itself can't escape the process body.
- **Shadow-buffer gate had no headroom.** The display dirty-cell shadow
  enabled at `free > W*H*128` — i.e. free only had to exceed the shadow's own
  ~256 KB with *zero* room for the shell that does the drawing, so it claimed
  most of a 330 KB-free box and the shell then OOM'd. Now requires the shadow
  size **plus a 384 KB working reserve**, so tight boxes keep it off (direct
  draws) and only roomy boxes pay for the optimization. (`screen.lua`.)
- **Input fields scroll instead of clipping off-screen.** Typing a long name
  in a prompt (e.g. `report.example`) used to clip from the left, so the
  cursor and the extension you were typing ran off the right edge. The shared
  `promptInput`/`promptSearch` (and the `mail` body input) now scroll
  horizontally to follow the cursor, like the chat input already did.
  (`dialogs.scrollTail`; `test_dialogs.lua`.)

### System Configuration screen — function over form
- **Honest hardware readout.** The DEL-to-enter System Configuration screen
  no longer invents PC-BIOS flavour (the fake Base/Ext memory split, a
  "Numeric Processor" that doesn't exist, pseudo IDE drive names). It now
  shows only what's really there, by its real name: Processor / CPU Tier /
  Graphics / Data Card / Network / EEPROM on the left; Total & Free Memory,
  **RAM Modules** (counted via `component.list("memory")`), Max Text Mode,
  Screens and Boot ID on the right. Storage rows read Boot Drive / Data
  Drive N / RAM Disk. (`sysinfo.gather`/`render`; `test_sysinfo_render.lua`.)

### Boot Settings — basic up front, advanced hidden
- **Two-tier menu.** The everyday choices (Profile / Verbosity / Show this
  screen) show by default; the boot overrides and manual device checks
  (CPU & Data-Card tier overrides, the per-feature toggles) are tucked
  behind **`[A] advanced`** so an operator can't fat-finger something they
  didn't mean to touch. Fields carry a `group`, and the runner cycles by
  key so the filtered view never mis-maps a row. (`bootsettings.lua`;
  `test_bootsettings.lua`.)

### Dialog boxes — a general prompting primitive
- **MS-DOS-style dialog boxes.** A new `panels.dialogs.dialog` draws a
  titled, framed, centred box (single-line frame, a centred `┤ Title ├`
  tab, drop shadow) and blocks until the operator picks a button. It's a
  GENERAL primitive — any title, buttons and `style` (info / install /
  warn / danger / error / general) — so TOS developers can prompt
  intrusively (the box) or non-intrusively (the existing status-row
  `promptInput`), whichever fits. `alert`/`confirm` are thin shortcuts;
  file deletion now uses a danger-styled `confirm`. Exposed on the panels
  API (`dialog`/`alert`/`confirm`, auto-repaint on dismiss).
  (`test_dialogs.lua`.)

### Mesh email + chat
- **Mesh mail (store-and-forward, no central server).** New `mail` command:
  addressed email that multi-hops across **trusted relays** by controlled
  flooding — each node re-broadcasts what it hasn't seen, decaying a hop
  budget and de-duplicating by id, so a message reaches a peer several hops
  away with no routing table. Reliability is store-and-forward: the origin
  (and any relay that passed it on) re-floods on a timer until an ACK floods
  back or a deadline passes, so a recipient that was briefly offline still
  gets it. Message **content is sealed end-to-end** with the existing
  per-peer trust secret, so relays forward a blob they cannot read; routing
  fields stay clear. Engine is dependency-free and unit-tested
  (`net/mesh.lua`, `net/mail.lua`, `net/mailctl.lua`; `test_mesh.lua`,
  `test_mail.lua`, `test_mailctl.lua` — incl. a 3-node A—B—C end-to-end with
  a blind relay). MAIL/MAIL_ACK gated TRUSTED-only (same posture as the
  cluster relay path) with a per-second relay budget against amplification.
  *Live wiring is in place (`net.init` adapter, `net.sendMail`/`inbox`/
  `mailTick`); needs in-emulator verification, and the at-rest mailbox
  (`/var/mail/<user>`) should move to per-user securefs as a follow-up.*
- **Chat enhancements.** Slash commands (`/who`, `/clear`, `/help`, `/quit`)
  plus a **`/mail <peer> <text>`** bridge that hands a message to the
  reliable mesh-mail path; a live trusted-peer count in the header; and the
  input parser (command / directed / broadcast) extracted to pure, tested
  helpers. (`shell/chat.lua`; `test_chat_parse.lua`.)

### Operator-friendly installation revamp
- **Auto-detect & guide on insert.** Inserting a removable disk now names
  what it IS and the next step to take: TOS install disk, Optional Utilities
  disk, package repo, single-package, legacy module, or plain data. A shared
  `helpers.classifyDisk` drives both the insert toast and the `disk` command,
  so they never disagree. (`test_disk_classify.lua`.)
- **In-TOS Optional Utilities builder.** `pkg make-disk <mount> [name…]`
  assembles your INSTALLED add-ons (plus a self-contained picker
  `install.lua`) into a pick-and-choose disk — parity with `deploy`, no dev
  box or TOS-Extras source tree needed. Admin-gated, write-confined, refuses
  system paths. (`kernel.pkg.exportDisk`; `test_pkg_exportdisk.lua`.)
- **Clean install (installer v1.3.0).** The OpenOS-run `install.lua` can now
  shed OpenOS's `/bin` + `/lib` so a fresh TOS tree doesn't inherit the
  bootstrap host's filesystem. Conservative by design: only those two trees
  (never `/etc`, `/usr`, `/home`, …), gated on a fully-verified copy, and run
  as the very last action before reboot so the still-running OpenOS never
  loses a library mid-install. Both existing entry points (manual
  `install.lua`, BIOS auto-floppy) are unchanged. First-boot message corrected
  to reflect that TOS *forces* the root password change.

### Build tooling
- **Release build no longer silently ships tests + build tooling.** Under Git
  Bash / MSYS on Windows, `build-release.sh` had its `--exclude /build/`-style
  patterns rewritten by MSYS path-mangling into `C:/Program Files/Git/build/`
  before `lua` saw them, so NOTHING was excluded (`skipped 0 entries`) and the
  Release tree carried all 43 dev tests and the build scripts. The wrapper now
  converts path args to mixed Windows form (`cygpath -m`) and sets
  `MSYS2_ARG_CONV_EXCL='*'` on MSYS so the patterns pass through verbatim; real
  POSIX is unaffected. (The native `build-release.cmd` was always correct.)

### Emulator-testing fixes (2)
- **Multi-seat: session stays on the boot screen; seats no longer steal each
  other's input.** Two fixes. (1) `screen.init` paired `gpu[i]↔sorted-screen[i]`,
  which rebound the GPU away from the screen the BIOS drew the splash on (boot
  on one screen, session on another) and yanked a live seat onto a hot-plugged
  screen. It now PREFERS each GPU's current screen binding (new pure
  `screen._pair`, `test_screen_pair.lua`). (2) The per-seat login broker never
  claimed its seat's foreground, so during login the seat's keystrokes fell back
  to the GLOBAL foreground shared across seats — a 2nd seat's login captured and
  froze the 1st seat. `spawnLoginProcess` now claims `displayForeground[dIdx]`.
- **Logout no longer leaves a zombie shell drawing over the new session.** The
  root cause of the "status bar flips between two users" flicker: H13 made
  `proc.kill` fail closed on a no-caller call, but the kernel main loop (which
  reaps a seat's shell on logout/shutdown/seat-unplug/Ctrl+C, and the task
  switcher after its own `canAct` check) HAS no caller — so the kill was denied
  and the old shell kept running and drawing. `proc.kill(pid, {kernel=true})`
  now authorizes the genuine kernel path; the default still fails closed
  (sandboxes can't reach proc, listeners carry a listenerPID). Pinned by
  `test_kernel_kill.lua`. (Fixes the single-screen flicker; the two-screen
  seat↔display *binding* — wrong screen for boot vs. session, cross-seat freeze
  — is a separate multi-seat item still open.)
- **Config POST screen no longer overflows / detects the set Data Card tier.**
  The 5-row wordmark pushed the dense hardware box off an 80×25 screen — the
  POST screen now brands via the box title only. It also passes the operator's
  manually-set Data Card tier (Boot Settings) to `sysinfo.gather`, so the
  Crypto line shows the chosen tier instead of "unknown tier".
- **Boot Settings stopped re-scanning hardware on every keystroke.** With the
  hardware view open, each cursor move re-ran the full `sysinfo.gather`
  component probe (laggy); the inventory is now cached and re-gathered only
  when a tier override actually changes. Also fixed the "Data Card tier" label
  running into its value column (shortened + clipped).
- **Per-user themes.** Any regular user can now pick a PRESET theme for their
  own session (`theme set <name>` / `theme list`, USER tier), saved to their
  `~/.theme.cfg` (seat-bound) and restored at their next login; CUSTOM colour
  overrides (`theme color`) stay admin-only.

### Branding
- **AMIBIOS-style System Configuration POST screen.** Reworked `sysinfo.render`
  from a boxed section list into a rigid, two-column "Main Processor : … |
  Base Memory Size : …" grid with retro labels (Numeric Processor, Ext. Memory,
  Max Text Mode, EEPROM BIOS, BIOS ID), a storage table with pseudo PC drive
  names (Primary Master/Slave, Floppy Drive A, Used/Size, Tier, Boot), and the
  classic `<n>KB SYSTEM MEMORY · GPU T2 TEXT MODE 80x25` footer — TOS's actual
  OpenComputers facts dressed as an American Megatrends POST. Boot Settings stays
  the place for TOS-specific config. Narrow (T1) screens fall back to a single
  column. `sysinfo.rows` (the Boot Settings hardware view) is unchanged.
  `test_sysinfo_render.lua`.

### Performance
- **Dirty-cell shadow buffer on the per-seat display.** The shell redraws
  mostly-unchanged rows every frame, and each `gpu.set`/`fill` (plus its
  `setForeground`/`setBackground`) crosses the OC bridge (up to ~50 ms/tick
  budget). The display proxy now remembers what every cell holds and SKIPS the
  GPU call when the target already matches exactly — the idle status-bar tick,
  re-drawn file lists, and static chrome stop re-emitting. Memory-gated (the
  buffer is ~W×H×3 slots, so it's disabled on tight boxes, which fall back to
  direct draws and pay nothing). Also fixed a latent colour-cache desync: a
  forwarded `withContext` draw now resets the proxy's fg/bg cache (it left the
  GPU at colours the proxy never tracked). `test_screen_shadow.lua`. (Colour
  caching and `gpu.copy` scrolling were already in place.)

### Shell & branding
- **`launcher` — menu-driven Operator multi-tool.** A full-screen, clickable
  menu (number keys, arrows+Enter, or a native screen touch) that runs real
  commands at YOUR tier — click instead of type. Generalizes the old kiosk
  menu into a nested, profile-driven engine (`tos/shell/launcher.lua`): a
  built-in home of quick actions, a **cluster helper** submenu when the cluster
  add-on is installed, a personal menu from `~/.launcher.cfg`, and `launcher
  tape` — your personal toolbox carried on your **identity tape**. Kiosk stays
  the locked, guest-facing profile; the `kiosk` command now points operators at
  `launcher`. Aliases `launch`/`apps`. Pinned by `test_launcher_menu.lua`.
- **Personal menu on the identity tape.** tape-authenticator gains
  `tape-auth menu add|list|remove|clear <passphrase>` — a vault-encrypted menu
  region on the keycard (alongside the identity block + personal log; the TAUTH2
  wire format grew an optional trailing menu region, round-trip pinned by
  `test_tape_menu_format.lua`). `launcher tape` reads + unlocks it and runs it at
  your tier (`launcher.readTapeMenu`, `test_launcher_tape.lua`) — so the toolbox
  follows the operator between machines. The card needs no filesystem access:
  the launcher (which knows the home + has tape + vault) does the reading.
- **TOS visual identity (`kernel.logo`).** One Skynet / American-Megatrends-
  flavoured block wordmark, shared by the boot splash, the AMIBIOS-style
  configuration POST screen, and the login screen, with an ASCII fallback for
  monochrome screens. Dependency-free (safe to load at early boot); every
  caller pcall-requires it with a graceful fallback. The installer embeds a
  byte-identical copy (it runs before the kernel). `test_logo.lua`.

### Cluster
- **Worker bridge wired end-to-end (v2).** The Manager's `dispatchAssignment`
  ran every task inline on itself (`TODO(v2)`); it now hands tasks to registered
  OpenOS workers over the authenticated bridge when configured. Each task routes
  inline or to an idle worker (`task.via_bridge`, or all tasks under
  `worker_bridge_mode = "prefer"`), results are collected asynchronously and
  aggregated (ok / partial / failed / cancelled) with a per-task idempotency
  guard so a worker result racing a cancel can't double-count, and a silent
  worker yields a `timeout` so an assignment never hangs. New config block in
  `/etc/cluster-manager.cfg` (`worker_bridge_*`), a `cluster-manager workers`
  CLI subcommand, and bridge state in `status`. Dispatch logic is pinned by
  `test_cluster_bridge_v2.lua` (22 cases). Needs in-emulator verification with
  real OpenOS workers before relying on it for production scheduling.

### Security
- **Cluster worker now authenticates frames (#SEC H21/H2/CR-3).** The TOS-side
  Manager bridge was hardened to require a shared secret and HMAC-verify every
  WRK frame, but the OpenOS worker — the side that actually executes
  Manager-supplied `code` — was never updated: it ran tasks after an
  unauthenticated `REGISTER_ACK` and sent unsigned frames (which a hardened
  Manager silently drops, so the channel was also non-functional). The worker
  now carries a matching software SHA-256/HMAC, signs every frame with a fresh
  nonce, verifies + replay-checks inbound frames, and default-denies task
  execution until `shared_secret` (16+ bytes, matching the Manager) is set in
  `/etc/cluster-worker.cfg`. Crypto parity with `kernel.crypto` is pinned by
  `test_cluster_worker_hmac.lua`.

### Emulator-testing bug-fix batch (13 operator-reported issues)
- **Themes save again.** securefs treated `/home`, `/root`, `/public` as
  subtree-protected, so it refused EVERY write beneath them — `~/.theme.cfg`
  and `~/.profile.cfg` could never be written ("WRITE denied (protected):
  /root/.theme.cfg"). Those roots are now NODE-protected (the directory node
  itself is guarded; files inside follow the per-user ACL). System trees
  (/tos, /etc, /usr, /var) stay subtree-protected. New
  `test_securefs_protected.lua`.
- **Theme colours stop snapping weirdly on T2 GPUs.** display.setTheme now
  snaps each colour to OC's actual 16-entry 4-bit palette itself (with
  ensureContrast healing any collapsed fg/bg pair), instead of leaving the
  hardware to do a naive nearest-RGB snap that turned dark bars black.
- **Floppy/removable-disk insert works.** `_G._TOS.bootAddr` was never set,
  so the shell's auto-mount gate (fail-closed by design, #SEC H26) refused
  every inserted disk. Now set at boot from the boot proxy.
- **Data Card detection unified + honest.** New shared `kernel.datacard`
  (component.list("data") + tier inference from the method set: T1
  hashing/base64/deflate, T2 +AES/random, T3 +ECC). `compress` uses it and
  now reports a present-but-deflate-less card honestly instead of "No data
  card" while crypto saw the same card as Hardware. `sysinfo` delegates to
  it too. New `test_datacard.lua`.
- **`verify` no longer fails man pages.** It ran `load()` on every manifest
  file, flagging `/usr/man/*.man` (prose) as "BAD (syntax)". Only `.lua`
  files get a syntax check now; data files are existence/hash-checked.
- **`flash` confirmation prompt fixed.** The "type flash to confirm"
  instruction was drawn with drawOutRow then instantly wiped by
  promptInput's own (empty) render, leaving a blank prompt that "aborted on
  any key". The message is passed INTO promptInput now (same fix applied to
  the from-floppy installer prompt).
- **Output wraps correctly.** Viewer content was wrapped to full width then
  re-clipped to width-minus-gutter at draw time, dropping the last few
  characters of a wrapped line ("'or' → 'o'"). expandBuf reserves the gutter.
- **`log` reads the on-disk file by default** (flushing first), falling back
  to the in-memory ring, then a regenerated file; `log ring` is the quick
  in-memory peek. (kernel.log.1 is the 16 KB rotation backup — not a
  duplicate; the persistence path attaches once and never double-writes.)
- **Menus reorganized + modular.** File no longer has Quit (power actions
  moved to System: Log Out / Reboot / Shut Down); added View, Settings→Theme/
  Boot Settings. Any menu item can be `action="run:<command>"`, and a
  per-user `~/.menu.cfg` (managed by the new `menu add|list|remove` command)
  injects command shortcuts into any drop-down.
- **Power-off policy (#9).** Reboot/shutdown from the menu/F10/commands are
  now gated by `helpers.canPowerOff`: a sole operator may power off, but with
  other operators logged in only ADMIN+ may (it kills their sessions too).
- **Live status bar.** The shell event loop now refreshes the status bar
  ~once a second when idle, so the clock/uptime/free-mem widgets tick.
  `date tz <hours>` sets the display offset (OC has no settable clock).
- **JBOD safer + clearer.** `jbod create` now confines pools to `/mnt/`,
  CREATES the mount directory, and REFUSES the boot disk as a member (which
  is what exposed "a copy of TOS" inside the pool).
- **Lua REPL is multi-line.** Statements accumulate until they compile
  (incomplete input shows a `>>` continuation prompt; a blank line runs or
  cancels the block), and each executed chunk is still audit-logged.

### Proactive audit (bugs found while reviewing, not yet reported)
- **Multi-screen seat pairing is deterministic.** `screen.init` paired
  GPU↔screen in `component.list()` order, which OC doesn't keep stable
  across boots — so on a 2-screen rig the active panel could change every
  reboot ("screens swap on reboot"). The address lists are sorted now, so
  each seat pins to the same hardware run-to-run. (1 GPU still drives only
  1 screen; that limitation is logged at boot.)
- **`cp`/`mv` honor a directory destination.** `mv foo.txt /tmp` tried to
  create a path literally named `/tmp` instead of moving INTO it; both now
  append the source basename when the target is a directory, and `mv` falls
  back to copy+remove across filesystems (matching the browser's F6).
- **Mouse menus read live state.** After the modular-menu refactor, the
  mouse handler held a one-time snapshot of the menu layout, so a `menu add`
  at runtime updated keyboard navigation but not clicks. It now reads the
  live `S.menuDefs`.

### Security
- **Kiosk mode bypassed filesystem ACLs.** The locked-down public-terminal
  shell (`shell/kiosk.lua`) built its command environment with the raw,
  privilege-bypassing `_G._TOS.fs` and a stubbed `canRead`/`canWrite` that
  always returned true/false. Because `cat` is in the default allow-list, a
  GUEST kiosk user could read any file — `/etc/users.dat`, `/etc/trust.dat`,
  any home dir. Kiosk now uses `securefs` (session-bound) for `F` and routes
  `canRead`/`canWrite` through `helpers.canAccess`, and `S.st` carries the
  token the rest of the command layer expects. New `test_kiosk_acl.lua` proves
  a guest `cat /etc/users.dat` is refused (fails on the pre-fix code).

### Dead-code prune
- Removed ~24 unreferenced kernel/shell exports (and their now-orphan locals):
  the `kernelDispatch`/`isKernelContext` machinery, the net message-log ring,
  trust change/request callbacks, event `globalListeners`/`onAny`/`pullNamed`,
  HAL hotplug callbacks, and assorted unused accessors across `init`, `users`,
  `rc`, `log`, `crypto`, `display`, `screen`, `pipe`, `power`, `bootsettings`,
  `audio`, `config`, `commands`, `login`.
- Synced `system_manifest.lua` — it was missing 9 shipping runtime files
  (`backup`, `diag`, `keychain`, `profile`, `trash`, `vault`, `net/aliases`,
  `net/chatpair`, `kiosk`).

### Dead-ends wired up (rather than deleted)
- **`net revoke <peer>`** / **`net forget <peer>`** — downgrade a peer to
  UNKNOWN (without blocking) or drop its record entirely.
- **`net request <peer>` / `net requests`** — send and review trust requests
  (`requestTrust`/`getPendingRequests` were live but unreachable).
- **`log filter <source> <level>`** — per-source log level overrides.
- **Tunnel-only boxes can network** — `net.send`/`net.broadcast` no longer
  require a wireless/wired modem; they fall back to a linked card.
- `pkg.install` now enforces declared version constraints (warns on unmet
  `requires`).

### Efficiency
- `event.pull` (the hottest loop) no longer does `pcall(require,
  "kernel.process")` per timer fire and per signal dispatch — the module ref
  is cached behind a lazy accessor.

### JBOD disk pooling — now opt-in, not removed (`kernel/jbod.lua`)
- The dormant JBOD module is back, but **off in every profile**: it loads only
  when `/etc/boot.cfg` has `advanced.jbod = true` (`bootsettings jbod on`).
  Pure-Lua union mount (capacity = sum of members; a lost member loses only its
  own files; securefs still applies per-user ACLs).
- New **`jbod`** admin command: `create <mount> <disk...>` / `list` /
  `destroy <mount>`, persisting pools to `/etc/jbod.cfg` (re-mounted at boot).
  Install-aware-hidden when the feature is disabled. `man jbod`.
- New `test_jbod.lua` covers the pool proxy (union reads, free-space write
  routing, in-place overwrite, list dedup) and proves the boot gate is
  default-off across all four profiles.

### Mouse add-on (Optional Utilities / TOS-Extras)
- TOS has no baked-in mouse support (keyboard-driven shell, MS-DOS style). The
  new **`mouse`** package installs a userspace driver — `require("mouse")` —
  that turns OpenComputers touch/drag/drop/scroll signals into clean mouse
  events with rectangle hit-testing, plus a `mousetest` demo. Pure userspace
  (`component` cap only). Ships on the Optional Utilities disk; covered by
  `modules/mouse/test_mouse.lua` (28 cases, all pure/off-box).
- **The panels shell now consumes the driver** (new `shell/panels/mouse.lua`,
  mouse pkg → 1.1.0): when the `mouse` package is installed (and enabled), the
  shell's UI elements become clickable — menus toggle open/closed by click,
  dropdown/context-menu items run on click, tabs switch on click (right-click
  closes closable tabs; modified editors are surfaced, never dropped), file
  rows select on first click and open on second (right-click = context menu),
  the wheel scrolls the file list/viewer/editor, clicks place the editor
  cursor, and the status-bar config checkboxes toggle by click. Without the
  driver every mouse signal is ignored exactly as before; keyboard behaviour
  is unchanged either way. The driver probe honors `pkg disable mouse` and
  re-probes (throttled) so a mid-session install starts working immediately.

### Extras fixed for the pkg sandbox (kernel.modules→pkg regression)
- **tetris could not launch**: it required `kernel.display`/`kernel.event`
  (plus `kernel.users`/`securefs`/`fs`/`serialize`), all blocked by the pkg
  sandbox. Rewritten (pkg → 1.1.0) to draw via the sandboxed `component` GPU
  proxy, pull raw signals via `computer.pullSignal`, and store high scores
  through the session-bound `fs` global + `compat.serialization` (old
  `return {...}`-format score files still load). Also fixed its dispatcher
  reading `args[2]` (the dead kernel.modules argv convention) — under pkg,
  `tetris scores`/`tetris help` silently launched the game instead.
- **tape encrypt/decrypt always failed** ("vault module unavailable"):
  `require("kernel.vault")` is sandbox-blocked. New narrow **`vault`
  capability** (kernel.sandbox + pkg allowlist) exposes exactly
  `encrypt`/`decrypt`/`isEncrypted` — pure data-in/data-out on
  caller-supplied strings, no keychain or fs surface — and the tape package
  (→ 2.1.0) declares it. `legacy` remains excluded from manifests.

### Theme palette refresh (every preset + the boot defaults)
- **All presets redesigned** (`kernel/theme.lua` + the boot-time defaults and
  T2/T3 tier branches in `kernel/display.lua`). The old set was CGA-harsh:
  solid white/amber/green menu bars dominated the screen, and title/warning
  collapsed into the same yellow in several presets. New rules every preset
  follows: tinted bars instead of solid accent blocks, soft body text instead
  of full-white glare, and a distinct title/warning/error severity ladder.
  - `default` — teal frames + warm-gold titles on black, dark-slate menu bar,
    deep sea-blue status bar, One-Dark-style syntax colors.
  - `midnight` — Tokyo-night indigo; `amber`/`green` — CRT phosphor looks with
    dark bars (selection keeps the inverted-phosphor block); `classic` — now
    actually Norton-style (cyan bars with black text on CGA blue); `contrast` —
    stark white/yellow with an ~9:1-contrast orange warning.
  - Three new presets: **`nord`**, **`solarized`** (dark), and **`plasma`** —
    early-plasma-display neon red-orange on pure black, with every color kept
    in the red-orange band (no blue/green light) so operators working in the
    dark keep their night vision.
- **Presets now carry the full key set including syntax + file-type colors**,
  so switching presets restyles the editor too and never leaves the previous
  theme's syntax colors behind. `theme color` accepts the `syn_*`/`file_lua`/
  `dir_color` keys, and saved overrides round-trip.
- **`input_fg` was silently dropped** by `display.setTheme`'s allowlist while
  both kernel.theme and the presets used it — input-field text colors now
  actually apply.
- **T2 palette corrected**: the 4-bit tier branch (and preset snap targets)
  now use OC's actual default 4-bit palette entries (0xFFCC33 orange, 0x6699FF
  light blue, 0x336699 cyan, …) instead of CGA values that snapped
  unpredictably.
- **Profile themes never applied** (REV-2): `profile.apply` called
  `theme.applyPreset`, a function kernel.theme never exported, so
  `profile set theme <name>` did nothing at login. Fixed to call the real
  API; the profile theme is now opt-in (unset by default) and an explicit
  `theme set` choice (`~/.theme.cfg`, which can carry per-key overrides)
  outranks it via the new `theme.hasSavedTheme()`. `profile set theme`
  validates the preset name at set time, and PaneUI's mirrored palette table
  was re-synced (now 8 themes).

### Optional Utilities disk — one-command build & install (TOS-Extras)
- **`build-disk.cmd` / `build-disk.sh` wrappers**: building the disk is now a
  single command on either platform, and `--install <dir>` copies the built
  disk straight into a target folder (point it at an OpenComputers floppy
  directory under `saves/<world>/opencomputers/<address>/` to "burn" it in
  the same step).
- **The assembler auto-discovers packages**: any directory under `modules/`
  or `cluster/` with a `package.lua` is assembled — the hand-maintained
  `PACKAGES` table with per-package resolvers is gone. Each `files[]` target
  resolves mirror-first (source at its install path), then flat (single-file
  module root), then an explicit legacy map (master-skeleton's
  `lib/cluster/*`). Output verified byte-identical to the previous builder.
- **Deliberate exclusions are visible**: a `SKIP` table prints the reason at
  build time (currently `tape-authenticator` — a pre-pivot demo whose
  `commands` map is still the old array shape and whose HMAC path needs
  sandbox-blocked `kernel.crypto`).
- Runs without LuaFileSystem now (shell fallbacks for mkdir/dir-listing), so
  a stock Lua install is enough.

### CRITICAL: boot resolution policy bricked ordinary screens (#REV-3)
- The unreleased auto-density screen policy floored at a 40x12 *minimum*,
  which **collapsed every screen up to 4 blocks wide — including standard
  1x1 and 3x2 builds — to 40x12 at boot**: the login screen rendered at a
  fraction of the screen's real resolution and the machine looked
  bricked/headless after login. The density rule now only RAISES
  resolution above the ~80x25 baseline (for big multiblock walls where
  the hardware max means tiny glyphs) and never shrinks an ordinary
  screen below it: a 1x1/2x1/3x2 screen boots at the full 80x25 again,
  while a 16x10 T3 wall still gets its readable 160x40.
- Related stale-size hole closed: `screen.init` applied per-seat
  resolutions with a raw `gpu.setResolution`, never refreshing
  `kernel.display`'s cached W/H — anything drawing through the global
  display module after a divergent per-seat target painted off-screen
  (invisible). It now routes through `screen.applyResolution`, which
  syncs the cache. `test_screen_res.lua` rewritten around the new
  invariants (22 cases) plus an off-box boot-chain simulation.
- `build-disk` now sizes the assembled set against **`--limit`** (default
  512K, the OC default floppy; `0` = unlimited; per-file `--overhead`
  defaults to 512 bytes ≈ OC's `fileCost`) and, when it doesn't fit, splits
  packages across `disk1..N/` dirs — each with its own `install.lua`, with
  dependency-connected packages kept on the same disk (kernel.pkg resolves
  requires from the repo it installs from), first-fit-decreasing packing,
  and a hard error naming any single package group that exceeds the limit.
- The output dir is now wiped before assembling, so renamed install paths
  can't leave stale files on the disk.

### CRITICAL: shell received no input after login (#REV-3)
- After the resolution fix above, the shell drew its full UI but **no
  keystroke ever reached it** — the machine looked bricked/headless once
  past login. Root cause: the unreleased #SEC H13 target-ownership gate on
  `proc.setForeground`. The seat's login broker runs as a tier-0 `_login_`
  principal (by design, #135) and spawns the shell as the authenticated
  (higher-tier, different-user) session, so the gate denied the
  login→shell foreground handoff — and the call site ignored the return,
  so the seat's input stayed routed at the now-dead login process.
  `proc.setForeground` now permits a process to foreground its **own
  direct child on its own seat** (the handoff), while H13's actual
  exploit — pointing a seat at an *arbitrary* victim process — stays
  blocked. The kernel call site also logs a hard error if a handoff ever
  fails again, so this can't regress silently. (`test_fg_ownership`
  extended with the production handoff + wrong-seat/non-child denials.)

### POST screen: Data Card tier confirm + verbosity fixes
- **Data Card tier is now operator-confirmable**, mirroring the CPU tier.
  Some OC builds/emulators hand back a `data` component proxy that doesn't
  probe cleanly, so the POST screen showed `Crypto: present (unknown
  tier)` with no way to correct it. New `dataTier` boot setting (DEL editor
  field + `bootsettings datatier <auto|1|2|3>`); the POST line shows a
  confirmed tier with `*`, or `tier ? - set in boot settings` when unknown.
- **`silent` no longer locks you out of Boot Settings.** The POST screen
  (and its DEL → Boot Settings entry point) is now gated by `showConfig`
  alone, not `showConfig AND verbosity ~= silent`. An operator who set
  `silent` could previously never reach Boot Settings again from boot.
  For a fully silent boot, turn `showConfig` off as well.
- **`verbose` now does something visible**: every early-boot line is
  stamped with `[NNNNms]` ms-since-boot timings (the bootcfg vocabulary
  always promised "text + timings"; nothing emitted them, so verbose was
  identical to text).

### Narrow `crypto` capability + tape-authenticator 1.0
- New **`crypto`** sandbox facet (PKG_RUN_CAPS + kernel.sandbox):
  `hash`/`hmac`/`ctEquals`/`random` pure primitives, plus
  **`crypto.secret()`** — a per-PACKAGE machine secret, kernel-managed
  under `/var/pkg/secrets/<pkg>`, scoped by the manifest-validated package
  name threaded in by the pkg loader (package A can never read package B's
  secret) and admin-gated against the LIVE session per call.
- **tape-authenticator rebuilt (0.1 → 1.0)** around the user's
  keycard+notebook idea: the tape's identity block stays an HMAC-signed,
  machine-secret-bound key (TAUTH2; legacy TAUTH1 still verifies), and the
  rest of the tape now holds a **vault-encrypted personal log** the
  operator edits any time with their own passphrase (`tape-auth log
  add|list|remove|clear|passwd`) — log edits never touch the identity
  block and need no admin tier, while minting/verifying keys does. The
  0.1 build could never run under pkg (kernel.crypto/securefs requires,
  array-shaped commands map); 1.0 is sandbox-pure and ships on the disk.
- **tape module renamed to its real name**: `modules/tape-storage/` →
  `modules/tape/`, install path `/usr/modules/tape-storage/` →
  `/usr/modules/tape/` (pkg → 2.2.0). The old name described the original
  data-archiver; the module has been the general tape tool since 2.0.
  `provides = {"tape-storage"}` keeps legacy `requires` resolving;
  upgrading installs need a `pkg uninstall tape` first.

### Tests
- Full standalone suite green: 36 TOS-Dev tests pass under host Lua (the 37th,
  `test_manifest_completeness`, needs a live TOS boot; verified equivalent
  offline via the new `build/check_manifest_offbox.lua`). Mouse driver: 28/28.
- New: `test_theme_presets.lua` (139 cases — full key coverage, color
  validity, contrast invariants, severity-ladder distinctness, setTheme
  acceptance of every preset key, and the profile-theme application fix) and
  Extras `build/test_build_disk.lua` (23 — assembler discovery/resolution,
  H-20 name match, skip list, `--install` replay).
- New: `test_panels_mouse.lua` (61 cases — click/scroll routing against the
  real Extras driver), `test_sandbox_vault_cap.lua` (17 — cap exposure bounds
  + pkg allowlist), and Extras `modules/tetris/test_tetris_sandbox.lua` (13 —
  loads and plays tetris inside a faithful fake of the pkg sandbox).

### Prompt editing — cursor movement
- **The command prompt cursor now moves.** Previously you could only edit at
  the end of the line — to fix an early character you backspaced everything
  after it. The prompt now supports Left/Right (move one char), Home/End (jump
  to start/end), Delete (forward-delete), and insert/backspace **at** the
  cursor. Long lines scroll horizontally to keep the cursor on-screen. New pure
  helper `helpers.cmdScroll` + `test_cmd_cursor.lua` (21 cases) pin the math.

### Release-accuracy fixes (external review)
A static review compared the shipped 1.3.2 image + Optional Utilities disk to
the docs and found drift. Corrected here:

- **Installer version was stale.** `install.lua` reported `1.3.0`; now `1.3.2`,
  and the header no longer carries a second literal version to drift from.
  `env.lua`'s `TOS_VERSION` fallback `1.3.1` → `1.3.2`.
- **Manifest was missing the mesh-mail stack.** `system_manifest.lua` did not
  list `net/mail.lua`, `net/mailctl.lua`, `net/mesh.lua` (so `deploy`/`verify`
  ignored them). Added — manifest now 116 paths. **The completeness test that
  should have caught this was being SKIPPED** by the harness (it required a
  live TOS boot); `test_manifest_completeness.lua` is now dual-mode and runs in
  the offline harness too.
- **`mail` was advertised in panels but had no executor** — running it did
  nothing (only the fallback CLI implemented it). Added a panels `mail` (list/
  read/delete/send) delegating to the same net-mail surface.
- **`pwd`, `du`, `head` were documented but unimplemented.** Added to both
  shells. `tree`/`trash`/`restore` and `mail` added to the CLI too, narrowing
  the panels↔CLI gap.
- **CLI `rm` contradicted the manual** (hard delete vs. "moves to trash unless
  `--hard`"). CLI `rm` now soft-deletes to per-user trash like panels; added
  CLI `trash`/`restore`. Manual's `rm` reference entry corrected.
- **CLI `kill`/`fg` were not admin-gated** though the README claims they are
  (panels already gated them). Now gated (`userTier < 2`).
- **README theme count** said six; there are nine (`plasma`, `nord`,
  `solarized` were missing). PaneUI already renders all nine.

### Optional Utilities — package correctness
- **Cluster packages declared `commands = { "cluster" }`** (array), which
  `pkg.commands` silently dropped (it wants a name→path map). The CLIs still
  worked via `/usr/bin`, so the vestigial declaration is removed and documented.
- **`rc-pilot` used crypto without declaring the capability**, so the sandbox
  left `crypto` nil and `rc` died on first use. Now declares `"crypto"` and
  uses the injected `crypto` global (`random`/`hmac`) instead of the blocked
  `require("kernel.crypto")`.
- **"Disabled by default" was not enforced for service packages.** `rc.runAll`
  started every `/etc/rc.d/*.lua` at boot regardless of a package's
  `defaultState="disabled"`, so installing `cluster-master`/`-manager`
  auto-started a daemon on the next boot. `pkg.install` now drops a
  `<svc>.disabled` marker; `rc` registers but does not start marked services,
  and an explicit `service start` clears the marker to persist the enable.
- **Installer printed the wrong service name.** `service start <package-name>`
  → derives the real rc.d service stem (`cluster-master` ships `clusterd.lua`,
  so `service start clusterd`). Fixed in both the disk picker and the embedded
  in-TOS `pkg make-disk` copy.
- New: Extras `build/test_manifests.lua` (28 — lints every package manifest:
  `commands` map-shape, crypto/vault capability declared when a sandboxed
  entrypoint uses it, capabilities are sandbox-grantable, service packages ship
  an rc.d script) and `test_rc_disabled.lua` (10 — disabled-by-default marker).

### Emulator-testing fixes (in-OC)
A round of fixes from running the build in OpenComputers (Ocelot):

- **Bundled Optional Utilities wouldn't install** despite `pkg list` showing
  them. Install used `pkg.findInRepos`, which scanned only `/mnt/<label>` (one
  level), while listing used the nested-aware `mountedRepoRoots`. So a disk with
  the whole `optional-utilities/` folder on it listed fine but `pkg install
  tetris` said "not found in any repo". `findInRepos` now uses the same
  enumeration, and `pkg install` also accepts a full path. (`test_pkg_discovery`
  +3.)
- **Disk `install.lua` did nothing in panels.** It's a line-driven (`io.read`)
  picker; the panels TUI has no line stdin, so it exited immediately. It now
  prints a pointer to the panels-native installer, and the disk-insert hint
  recommends `pkg from-floppy` instead of the dead-end `install.lua`.
- **Inline command output was wiped by any keypress/click.** Moving the cursor
  or clicking with no mouse driver cleared the last command's output. It now
  clears only when the file browser actually scrolls under the overlay.
- **`Running …` flashed for every command**, including builtins and unknowns
  (`Running test…` then an error). It now announces only actual programs
  (scripts / package commands).
- **Task switcher (^T) didn't clear on close.** The kernel signalled the shell
  to repaint via `proc.signal`, but that runs in the kernel loop (no caller PID)
  and `proc.signal` fails closed there (H13) — so the redraw never fired. Added
  a kernel-context `proc.signalKernel`; the dialog now repaints the shell on
  close.
- **System Config read every data card as "unknown tier".** `capsOf` probed the
  proxy's fields (`type(p.sha256)`), which Ocelot returns empty; it now uses
  `component.methods(addr)` (the authoritative enumeration). (`test_datacard`
  +4.)
- **Folder properties always showed 0 B** (directories report size 0); now sums
  contents recursively with a file count.
- **`tape-auth` OOM'd configuring a tape** even on tier-3.5 RAM — it slurped the
  whole multi-MB tape into one string. It now streams only the keycard region.
  `tape-auth info` authenticates inline for admins instead of always nagging to
  run `verify`. (tape-authenticator 1.0.0 → 1.0.1; `test_tape_auth` +6.)
- **Login F10 (shut down) just looped back to the login screen.** The caller
  captured `local ok, result = pcall(loginScreen.run, …)` and dropped the second
  return value (the `"shutdown"` reason). It now acts on it.

### Operator experience — visibility + a leaner command set
Making "what TOS is doing" visible and the command surface easier to understand.

- **Live System Monitor.** Ctrl+T's task switcher grew into a full System Monitor
  (also `monitor`, alias `top`): one auto-refreshing screen with every process —
  kernel AND user, each given a plain-English label (e.g. `login@2` → "Login
  broker — seat 2", `shell:root@1` → "Shell — root (seat 1)") — plus owner, state,
  CPU and seat; the rc.d **services** with status; and memory/uptime vitals. It's
  interactive: switch-to / kill / suspend (TSR) a process, and start/stop a
  service (admin), all from the one view. The pure helpers (labelling, the unified
  row list, header-skipping navigation, mem bar, uptime) live in `kernel.monitor`
  with `test_monitor.lua` (28 cases).
- **Per-command help for everything.** Only ~two dozen commands had a hand-written
  help page; the rest fell through to the big reference. `help <cmd>` now falls
  back to a focused, registry-driven entry (one-liner + minimum tier + group) for
  ANY command, so every command has its own help. New detailed pages for `pkg`
  and `monitor`. `test_command_registry.lua` guards that every command carries
  help text.
- **Command prune / unify.** The legacy `mod` command (the module manager it
  fronted was retired in v1.3.1) was removed; its unique `enable`/`disable`/
  `commands` subcommands were folded into `pkg`, which now also gains `install`/
  `search` in the fallback CLI shell — so both shells drive packages the same way
  via `pkg`. Dropped the redundant third launcher alias `launch` (kept `launcher`
  + `apps`). `pkg info` now shows enabled status + provided commands.

### Live tabs + command enhancements + docs
- **Live tabs.** A view tab can now regenerate its own content on a timer (the
  event loop ticks the front tab). New `watch [seconds] <command>` opens a
  self-updating tab for any read-only command — `watch ps`, `watch 2 df`,
  `watch net peers` — the live counterpart to running it once for static output.
  `r` refreshes now, `q`/F4 closes; interactive/screen commands are refused.
  Only the active live tab ticks (backgrounded ones don't burn cycles).
  (`editor.openLiveTab`/`refreshLiveTab`, `test_live_tabs.lua`.)
- **System-info commands enhanced + separated.** `mem` is now a real memory
  report (used/total + bar, RAM tier, swap usage, low-RAM warning); `df` shows a
  per-mount usage bar + %; `hw` is a hardware inventory (tiers incl. data card,
  components, network). Each cross-references the others (`mem`/`hw`/`monitor`/
  `df`/`du`) so overlapping commands have distinct roles. They share the
  monitor's `memBar`.
- **More command separation.** `doctor` = RUNTIME health, `verify` = FILE
  integrity — each now states which and points at the other (help, headers,
  See-also). `disk` = removable media (list/info/install/eject) and no longer
  claims "pool management" (that's `jbod`); its help/usage cross-reference `jbod`
  (pooling) and `df` (space), and the dead `disk export` is gone from the usage.
  `device` corrected to "device type + hostname" (it never showed an
  address/port and needs no modem). Stale `mod enable tape` hint → `pkg enable
  tape`.
- **Display-buffer observability.** The display-layer performance optimizations
  (a memory-gated dirty-cell shadow buffer that skips `gpu.set`/`fill` for
  unchanged cells, plus the colour-state cache and operator control) were already
  implemented in `kernel.screen`. Added session hit-rate counters
  (`screen.bufferStats`) shown by `optimize show` — e.g. "this session: 45231 of
  58900 cell-draws skipped (77%)" — so the saving is visible, not just a toggle.
  A MANUAL `optimize` entry documents both optimizations. (`test_screen_shadow`.)
- **Mail TUI.** Mesh email gets an interactive full-screen client (like `chat`):
  running `mail` with no subcommand opens the inbox — navigate, **Enter** to read
  (marks read), **c** compose (recipient/subject/multi-line body), **r** reply,
  **d** delete, and the inbox refreshes live (~2s) so mail arriving while you're
  open shows up. The `mail send/list/read/delete` subcommands stay for scripting
  and the minimal CLI. New `shell.mail` module; pure helpers (sender naming, row
  formatting, recipient resolution) in `test_mail_tui.lua`.
- **Splash no longer bleeds into login/shell/shutdown.** The splash boot-progress
  hook stayed wired into the logger after boot, so every later INFO log redrew
  the loading bar + narration over the UI. `log.detachEarlyPrint()` (called at
  the boot→shell handoff) now tears it down too. (`test_log_bootprogress.lua`.)
- **Docs.** The manuals are now treated as external "sits beside you" reference
  books and excluded from the lean TOS-Release image (with `TODO.txt`); `man`/
  `help` remain the in-OS help. MANUAL.md synced to the current command set
  (`mod`→`pkg`, Ctrl+T = System Monitor, new `monitor`/`watch` entries). A Dev
  roadmap lives in `TODO.txt`.

---

## v1.3.2 "Argus" — Security fixes & a friendlier shell

A focused security-and-usability release. The security fixes are the headline;
the TUI changes are additive and change no layout or key bindings.

### Security fixes
- **Process control is admin-gated again (`fg`/`kill`).** The panels command
  executor performs no dispatch-level tier check — privileged commands rely on
  an in-body `adminOnly`/`rootOnly` guard (the documented belt-and-braces line).
  `fg` and `kill` (REGISTRY tier 2, like their siblings `bg`/`run`) were missing
  that guard, so any logged-in user — including GUEST — could invoke them.
- **`setForeground` now enforces TARGET-process ownership (#SEC H13).** This was
  the real teeth behind the `fg` gap: `proc.tick` routes a seat's input
  (`key_down`/`touch`/…) to `displayForeground[seat]`, so a caller that could
  name an arbitrary PID could point its *own* seat at another user's process and
  have its keystrokes delivered there — input injection into a higher-privileged
  session. `kill`/`signal`/`goTSR` already gated the target via
  `callerMayControl`; `setForeground` only checked the seat. It now mirrors them
  (kernel-initiated calls — boot seat-spawn, the task switcher — still bypass, as
  those do). Fix lives in the kernel so it covers every caller, not just the
  panels shell.
- **File serving is fail-closed (`kernel.net.transfer`).** `transfer.init()` runs
  unconditionally at boot whenever networking comes up, and the FILE_REQ server's
  enable flag defaulted to `true` — so file serving was armed even on a machine
  whose operator removed or never started the `fileshare` service. It now
  defaults to `false` and tracks the service lifecycle, matching
  `kernel.net.remote`/`rshd` (#SEC L). Stock boots are unchanged: `fileshare`'s
  `start()` arms it.
- **Lua REPL gates on the live tier (#SEC M-7).** `lua` checked the cached
  `S.userTier` snapshot taken at panel construction instead of the seat's current
  session, so a session demoted/expired mid-session kept root-REPL access. It now
  uses the live-tier `rootOnly` gate like every other privileged command.
- **Package commands no longer leak the first loader's filesystem ACL.**
  `kernel.pkg`'s `loadPkgEntry` caches one sandbox per package and shares it
  across every caller, but it bound that sandbox's securefs `fs` proxy to
  whoever ran the command *first*. If root (or the root-tier boot session)
  loaded a command, a later GUEST/USER running the same command inherited
  root's filesystem permissions (a package declaring `fs.read`/`fs.write` thus
  became a confused-deputy privilege-escalation path). The loader now builds
  the sandbox with no captured session, so securefs resolves the LIVE caller
  per-call (`forSession(nil)` → `process.currentSession`) — matching what
  `compat.filesystem` already did — and fails closed post-boot when there is no
  live session.
- New regression tests: `test_fg_ownership.lua` covers the `setForeground`
  target-ownership check end-to-end through the scheduler, and
  `test_pkg_session_isolation.lua` proves a guest invocation of a root-loaded
  package command runs as the guest (it fails on the pre-fix code).

### Shell usability (additive — no layout or keybinding changes)
- **Function-key legend.** The shell's output row, previously blank when idle,
  now shows a width-responsive F-key legend (`F1 Help · F3 View · F5 Copy …`),
  the classic file-manager affordance. It disappears the instant a command
  produces output and degrades gracefully on narrow screens.
- **Help menu.** A new rightmost `Help` menu (Quick Help, Keyboard Shortcuts,
  Manual Pages, Tutorial, About) makes discovery easy for users who don't yet
  know the bindings. Every entry runs an existing guest-safe command except
  "Keyboard Shortcuts", which opens a read-only key reference.
- Smoke test `test_panels_help_ui.lua` covers the new menu wiring and legend
  rendering across screen widths.

---

## v1.3.1 "Polaris" — Configurable boot, resilience & packaging

An internal-improvement release. New subsystems are fail-safe and default to
the v1.3.0 behavior, so a stock boot is unchanged except for a brief hardware
POST screen.

### Boot reorganization
- **`/etc/boot.cfg` boot spectrum** (`kernel/bootcfg.lua`): `profile`
  (minimal/normal/full/diagnostic) gates *what loads*; `verbosity`
  (silent/splash/text/verbose) is a "muter" for *what boot says* (it maps to
  the kernel-log early-echo threshold and changes nothing about behavior);
  `advanced` per-feature toggles override the profile; `cpuTier` + `showConfig`.
  Read very early in `init.lua`, fail-safe to `normal`.
- **System Configuration screen** (`kernel/sysinfo.lua`): enumerates hardware
  and infers a tier for each piece (RAM, GPU depth, screen resolution, disk
  capacity, data-card method set), splitting System / Storage / Peripherals.
  CPU tier resolves detect → operator-override → RAM-estimate → unknown (plus an
  opt-in behavioral benchmark, never run at boot). Renders an AMIBIOS-style box.
- **Modular optional-stage gating**: `kernel.boot` consults `bootcfg.wants()`
  for swap/power/theme/net/compat/audio instead of a raw RAM check.
- **Boot Settings** (`kernel/bootsettings.lua`): a DEL-during-boot visual editor
  + a `bootsettings` shell command; both write `/etc/boot.cfg`.

### Power-loss protection
- **Unsafe-shutdown detection**: dirty-bit marker at `/var/run/pwrstate`
  (`running` at boot, `clean` only by `kernel.shutdown`); flagged via log,
  login banner, and `doctor`'s new power section.
- **Atomic writes** (`fs.writeFileAtomic` + boot-time `fs.recoverAtomic`) for
  `users.dat`, `trust.dat`, and everything via `serialize.saveFile`
  (config/cron/pkg/critical.bak) — a power cut mid-save can't truncate them.
- **Critical battery → clean shutdown** (config-gated `critBatShutdown`).

### Disk swap
- `kernel/swap.lua`: explicit spill-to-disk store API + a `swap.table{ hot=N }`
  disk-backed table (LRU hot-cache), capped, volatile (wiped each boot). `swap`
  command and a `swap` sandbox capability. (OC has no transparent paging; this
  is opt-in cold-data offload.)

### Disk compression
- `kernel/compress.lua`: data-card deflate/inflate wrapped in a self-describing
  `.tcz` container (chunked, integrity-checked). Detection-gated — falls back to
  a "stored" frame (no card needed to read) when no data card is present, and
  refuses to "compress" data that wouldn't shrink.
- **`compress` / `decompress` commands** (panels + CLI shells; hidden from
  install-aware help without a data card) shrink files on small disks.
- **Swap auto-compresses** spilled data when a data card is present, so more
  fits under the cap (`swap` status shows `compressed`); card-less boxes are
  unchanged. New `kernel.getCompress()` accessor; `man compress`.

### Dynamic screen resolution
- `kernel/screen.lua`: a resolution **policy** replaces the old "always max out"
  behavior. `chooseResolution` (pure) + `specFromConfig` + `gpuTarget` +
  `fit`/`restore`. Modes: `auto` (default — density-based from the screen's
  physical block size via `getAspectRatio`, ~80x25 cap fallback), `max`, or an
  explicit `WxH`. All clamped to the hardware max with a warning when a request
  doesn't fit.
- **Fixes T3 tiny-text**: a tier-3 GPU on a big screen no longer renders the TUI
  at 160x50 micro-text; `auto` downscales to a readable size. `display.init` and
  the multi-seat `screen.init` both honor the policy.
- **`screen res [auto|max|WxH]`** command: shows current/max/blocks/policy, or
  (admin) sets it — applied live (re-fits the panels layout + redraws) and saved
  to `/etc/tos.cfg` (`screenRes`, `screenColsPerBlock`, `screenRowsPerBlock`).
- **Programs declare a size**: manifest `screen = { width=, height=, mode= }`
  (`exact`/`min`), validated by `pkg`; the executor fits the screen before a
  packaged command and restores afterward. `pkg.getCommandScreen`; `man screen`.

### Package manager (pivot from kernel.modules)
- **`command`/`program` kinds** are now first-class (Extras modules use them).
- **Narrow service `/etc` exception**: a `kind="service"` package may write its
  own `/etc/rc.d/<f>.lua` + `/etc/<name>.cfg` (and nothing else under `/etc`);
  re-enables cluster-style installs while leaving the CR-4 kernel-overwrite
  guard intact.
- **`pkg.getCommand`**: package-provided commands now run via pkg's own
  sandboxed dispatch (caps from the manifest), wired into the shell executor —
  the first step toward retiring the legacy module manager. Bundled manifests'
  `commands` moved to `name → entry` map form.

### Help, UI & layout
- **Install-aware help**: `help` hides commands whose dependency
  (`net`/`swap`/`component:<t>`/`module:<n>`/…) isn't present; `M.helpList`
  + `M.needMet`. Manual page-flag hook in place (Manual content TBD).
- **PaneUI** (OpenOS) synced to TOS's six named themes, color-for-color, with
  `theme`/`themes` commands (v0.3).
- **Optional Utilities disk** (`TOS-Extras/build/`): a pick-and-choose installer
  + assembler for the bundled add-ons.
- **Cluster relocated** out of `kernel/net/` into the optional cluster package
  (`cluster.lua`→`cluster/protocol.lua`, `cluster_worker.lua`→`cluster/worker.lua`);
  the dormant kernel auto-start was removed. The `cl_*` wire types + trust
  permissions stay in core so packets still route.

### Security / correctness fixes
- **KDF / login speed**: the iterated password KDF and per-packet MACs run in
  pure-Lua software, and the round count is a single modest value (256) on every
  box. A mid-cycle experiment that routed the HMAC primitive through the data
  card and bumped data-card boxes to 10000 rounds was reverted: in OpenComputers
  a component call draws from a per-tick budget and sleeps the computer when
  it's spent, so a ~20k-call KDF stalled boot/login to ~150 s — and no
  OC-computable round count meaningfully slows real (off-box, GPU) cracking
  anyway, where the salt is the protection that holds. The data card still
  handles AES, hardware RNG, and one-shot SHA-256. Password hashes are
  unaffected (identical SHA-256 either way); v3 is now the universal write
  format, and legacy/high-round records are rehashed to the fast form on next
  login.
- **Network MAC** binds the real destination (`net.send` now stamps `packet.to`),
  making the documented anti-redirection guarantee non-vacuous.
- **`users.getUser()`** no longer returns salt/hash in its projection.
- **BIOS** shrunk under the 4 KiB EEPROM limit (factored the repeated
  wait-for-key/reboot loop); the Shift+Enter one-time boot is now functional
  (passed to init as `_BIOS_ONETIME`, suppresses the floppy→HDD migration).
- Misc: pkg OPPM `command`-kind install fixed; path-boundary root edge case;
  fileshare/rshd docs + default-disabled remote-exec.

### Tests
- New suites: `test_sysinfo`, `test_bootcfg`, `test_bootsettings`,
  `test_power_state`, `test_swap`, `test_help_aware`, `test_pkg_command`,
  `test_kdf_software` (asserts the KDF makes zero data-card calls + KAT vectors),
  `test_compress` (pack/unpack stored+compressed paths, multi-chunk, card gating,
  swap round-trip), `test_screen_res` (chooseResolution modes/clamping + the T3
  downscale + specFromConfig) (+ expanded `test_pkg_trust`, `test_path_boundary`).
  Full suite green.

---

## v1.3.0 "Aegis" — Security Hardening

A full security-audit pass. One agent per top-level module audited the OS in
parallel; this release closes **every** consolidated finding across all four
severity tiers (9 Critical, 21 High, 21 Medium, 7 Low). No new user-facing
features — this is a correctness/security release.

Each fix was traced against its original finding, regression-checked against
the standalone test suite, and most are backed by a new test under
`/usr/lib/tests/`. A few findings were confirmed already-mitigated by earlier
work rather than re-patched (noted inline).

### Critical

- **Cluster worker is now default-deny.** The Manager↔Worker bridge refuses to
  bind its port unless a shared secret is configured (`shared_secret` in
  `/etc/cluster.cfg`), installed before `setDomainId`. Previously, with no
  secret, any device could `REGISTER` during the bootstrap window and have
  dispatched Lua `code`/`output` flow into a result callback. (`cluster_worker.lua`, `init.lua`)
- **`pkg.install` now verifies integrity and confines writes.** Files are
  checked against `m.hashes[target]` with a constant-time compare before
  writing, and writes are confined to `/usr` and `/var/pkg` (normalized,
  escape-rejecting). A manifest can no longer overwrite the kernel. (`pkg.lua`)
- **Admin gate on every install/uninstall/enable path.** `pkg` and `modules`
  privileged entry points now require an ADMIN+ session (threaded from the
  caller's seat); boot-internal calls use a private bypass. (`pkg.lua`, `modules.lua`, shell command sites)
- **rc.d kernel-tier services get a gated `require`.** Kernel-tier boot
  services can only require a safe allowlist (`computer`, `component`,
  `kernel.event/log/serialize/config`); `require("kernel.process")` and friends
  are denied. (`rc.lua`)
- **Vault/keychain fail closed without real crypto.** The keychain refuses to
  persist secrets when only the XOR fallback is available (no data card). The
  vault wire format is now V2 with domain-separated enc/mac subkeys (no more
  single-key reuse); V1 blobs still decrypt. (`vault.lua`, `keychain.lua`)
- **`term.gpu()` is seat-bound and capability-gated.** Resolves the caller's
  seat GPU (not the first component GPU) and denies all mutating operations
  unless the process holds a display capability — closing cross-seat draw/
  rebind access for sandboxed programs. (`compat/term.lua`, `sandbox.lua`)
- **Shell ACL checks use the bound seat principal.** `canRead`/`canWrite` and
  the trash/vault/keychain/mount paths now resolve the seat's session token
  via `canAccessAs(...)` instead of the module-global `currentSession()`,
  which was nil (single-seat) or another seat's session (multi-seat). (`helpers.lua`, `core.lua`, `admin.lua`, `widgets.lua`)
- **Net replay protection has freshness.** Each packet carries a per-peer
  monotonic sequence plus a per-boot epoch, both bound into the MAC; the
  receiver rejects a non-increasing sequence so a captured packet can't replay
  after its nonce ages out of the window. Per-peer state is bounded. (`net/init.lua`)
- **Constant-time MAC/nonce comparisons** and empty-server-nonce rejection in
  peer verification (carried in from the prior review). (`net/init.lua`, `crypto.lua`)

### High

- Packet/frame MACs now bind type/to/algo (and the whole WRK frame via a
  canonical, key-sorted encoding) so a captured packet can't be re-typed,
  redirected, or partially forged.
- `createSession` no longer accepts a stored password hash as a credential.
- Login no longer leaks username existence or lock state (uniform errors +
  timing); the root account — exempt from permanent auto-lock — now gets a
  reboot-proof exponential backoff so it can't be brute-forced online.
- First-boot setup is parameterized to the actual principal (no hardcoded
  `root`); package manifests reject path traversal; backup restore rejects
  paths that escape the destination root.
- ACL path checks normalize before matching (fail closed on NUL/traversal).
- Persisted audit timestamps use a wall clock; session-liveness stays on
  monotonic uptime.
- The `flash` BIOS fingerprint is SHA-256-only (full digest) — the weak FNV
  fallback is gone; the typed-`flash` confirm remains the real gate.
- Relay forwarding gained payload dedup + a per-upstream-peer rate limit
  (neither trusting the attacker-supplied `path`), closing the amplification
  vector.
- Session tokens get cross-boot entropy accumulation (`/etc/entropy`) plus a
  one-time degraded-RNG warning on data-card-less boxes.
- `pkg` dependency-confusion closed: a repo package must match its directory
  name, and floppy installs never default to accept-all.
- Plus: `os.tmpname` precedence, `filesystem.list` ACL-error propagation,
  proc signal/kill nil-principal bypass, `safeSetMetatable` guard, and raw
  `component` access via the shell `component` command.

### Medium

- `fs.normalize` fails **closed** on tainted input (NUL/non-string → `nil`
  sentinel) instead of collapsing to the privileged root `/`.
- Unfiltered `event.pull` discards sensitive signals within the deadline (no
  signal-name leak, no scheduler spin).
- Chat receive path requires a TRUSTED sender; file-transfer validates the
  actor before interpolating it into `/home/<actor>` allowlists.
- Strict UUID matching in `aliases.resolve`; JBOD `remove` requires all-member
  success (no ghost files).
- Privilege gates read the **live** session tier (fail closed on an
  expired/revoked token), not a cached snapshot.
- Degraded-boot ACL fallbacks fail closed (`find`, `vault`, `canAccess`).
- `cron` registry tier aligned with its in-body admin gate; `mount`
  address-prefix matching is deterministic (ambiguous prefixes refused).
- PID reuse can no longer rebind a stale event listener to a new principal —
  each spawn carries a generation token validated at dispatch.
- `os.getenv` dropped from the sandbox `os` table (host-env leak); sandbox
  user-library loads re-check the session read ACL.
- `serialize` encode/decode depth limits aligned (64); over-depth now raises
  instead of silently truncating the wire form.
- Last-administrator lockout guard: refuse to demote or lock the final usable
  privileged account (including root).
- `chatpair` no longer compares cross-machine uptimes; `strip.lua` hard-errors
  on an unterminated comment/long-string instead of silently truncating a
  release; peripheral drivers coerce/range-check slot/count args and route all
  hardware ops through the capability check.

### Low

- `serialize.decode` rejects non-finite numbers (`inf`/`-inf`/`nan` and
  overflow literals) that would crash downstream `table.sort` comparators.
- Bounded several per-peer maps that grew without limit (net nonce set,
  chatrelay rate map) and de-duplicated the HAL component list.
- The `rshd` / `fileshare` services' `stop()` now actually disables the remote-
  exec / file-serving handlers (previously a no-op flag flip).
- `log.flush` appends via a file handle instead of read+rewrite of the whole
  log; the syntax highlighter caps tokenization on pathologically long lines.
- Password policy centralized in `users` (single `MIN_PASSWORD_LEN`).
- `serialization.unserialize` returns `(nil, error)` cleanly; `io.lines`
  closes its file descriptor eagerly on read error.

### Notes for operators

- **Cluster Managers must set `shared_secret` (16+ bytes) in
  `/etc/cluster.cfg`** or the worker bridge will not start (default-deny).
- **The keychain requires a data card.** On software-only boxes it now refuses
  to persist secrets rather than protect them with XOR.
- Network peers must be upgraded in lockstep: the packet MAC format changed
  (epoch+sequence are now bound into it).

---

<!-- Moved here from README.md when the README was cut down for
     first-time readers. These two releases predate the practice of writing
     the CHANGELOG entry first, so the README WAS their only record -- the
     paragraph that used to sit here pointed at it. -->

## v1.2.6 "Beacon"

### Themes & Customization

- **Named color themes** — pick from `default`, `midnight`, `amber`, `green`, `classic`, `contrast`, `plasma`, `nord`, `solarized`, or override individual colors. Themes auto-snap to the nearest palette entry on Tier 2 GPUs and are skipped on monochrome Tier 1 GPUs.
- **Per-user persistence** — your theme is saved to your home directory (`/root/.theme.cfg` for root, `/home/<user>/.theme.cfg` otherwise) and re-applied automatically on login.
- **`theme` command** — `list`, `show`, `set`, `preview`, `color <key> <0xRRGGBB>`, `reset`, `clear`, `keys`. Aliased as `colors`.

### QoL Commands

- **`date [fmt]`** — wall-clock time using `os.date` formatting; respects the cosmetic `timezone` config offset. (`time` is an alias.)
- **`tree [path] [depth]`** — visual recursive directory listing with depth control and a 400-entry safety cap.

### Security & Correctness Fixes (carried over from the v1.2.5 review)

- **`compat.filesystem.get()` no longer leaks a raw component proxy.** Sandboxed OpenOS code that called `filesystem.get(...)` previously got a raw filesystem component proxy whose `open`/`list`/`remove` methods bypassed `securefs` entirely. The compat layer now returns a metadata-only wrapper (`spaceTotal`, `spaceUsed`, `getLabel`, `isReadOnly`, `address`, `mountPoint`); every path-operation method returns a clear "raw filesystem access is disabled" error so bypass attempts fail loudly instead of silently.
- **Sandbox stops issuing raw filesystem proxies.** `kernel.sandbox.makeSafeComponent()` removed `filesystem` from `ALLOWED_COMPONENT_TYPES`, closing the parallel bypass via `component.proxy(filesystem-addr)`. Sandboxed code uses the bound `fs` global or the compat shim — both routed through `securefs`.
- **`share.lua` listener bug fixed.** Listeners now use the documented `(packet, fromAddr)` arg order (matching `kernel.net.init.dispatchToListeners`); the previous reversed order silently dropped every response. Listeners are also registered before `net.send()` so a fast peer can't beat the listener (same race already fixed in `ssh.lua`).

### Manifest & Deployment

- **`system_manifest.lua` now covers every runtime file.** Previously the manifest listed ~40 paths while the source tree had ~92 — fresh installs created from `deploy` were silently missing all 14 panel submodules, the full compat layer (`buffer`, `colors`, `event`, `keyboard`, `serialization`, `sides`, `term`, `text`), `kernel/audio.lua`, all peripherals, every `/etc/rc.d/` service, and every `/usr/bin` tool. The manifest now lists 116 paths covering everything that ships in a deployed image, including the `theme` module and the mesh `net/mail`, `net/mailctl`, and `net/mesh` stack.
- **`/usr/lib/tests/test_manifest_completeness.lua`** — walks `/tos`, `/etc/rc.d`, `/usr/bin`, `/usr/modules`, plus root-level boot files, and diffs against the manifest. Reports both missing-from-manifest and missing-from-disk so the manifest can't drift again without the test catching it.

## v1.2.5 "Atlas"

### Multi-Seat / Multi-Screen

- **Per-display shell sessions** — each GPU+Screen pair spawns its own independent shell process with its own login, cwd, and foreground tracking
- **displayProxy** — full TUI proxy (box-drawing, menus, dialogs, themes) delegated per-display via `display.withContext()`; no drawing crosstalk between screens
- **Correct input routing** — keyboard signals route via `displayForKeyboard()`, touch/drag/drop/scroll route via `displayForScreen()`; Ctrl+C interrupt targets the correct display's foreground process
- **Terminal Server / Remote Terminal** support — OC Server Racks with Terminal Server expansions and wireless Remote Terminals work transparently as additional seats

### Security Hardening (v1.2.5+)

- **Module path traversal fix** — boundary-aware prefix matching prevents `/usr/modules/foobar` from passing a check for `/usr/modules/foo`
- **Sandbox component filtering with per-type caps** — `makeSafeComponent()` splits component access into a base set (gpu/screen/keyboard/crafting/navigation/geolyzer/note_block/sign) granted by the generic `component` cap, and a gated set requiring per-type caps: `peripheral.modem`, `peripheral.redstone`, `peripheral.robot`, `peripheral.inventory`, `peripheral.tape`, `peripheral.tractor`, `peripheral.piston`, `peripheral.hologram`. A module with only `component` can no longer proxy the modem (and therefore can't sniff/forge network traffic). Modules requesting gated caps declare them in `module.cfg`. `eeprom`, `computer`, and `filesystem` remain unreachable from sandboxed code in any tier.
- **Boot integrity** — BIOS syntax-checks `/init.lua` before execution and defaults to **halt** when the boot drive has changed (was: 10-second timeout default-yes). Operators must explicitly type `y` to update EEPROM, or hold Shift and press Enter for a one-time boot. Per-file hash or signature verification across the boot chain is still tracked work — anyone with write access to `/init.lua`, the system manifest, or `/etc/critical.bak` still gains code execution at next boot.
- **Module integrity** — `module.cfg` may declare a `hashes = { ["init.lua"] = "<sha256-hex>", ... }` table. When present, the listed files are SHA-256-verified at install time AND at every `modules.enable` call; mismatches refuse to load. Manifests without hashes still load but emit a per-module warning.
- **Restricted first-boot token** — `users.login()` itself enforces the firstBoot flag: a login on a firstBoot-flagged account mints a GUEST-tier token marked `passwordChangeOnly`, regardless of which path called it (regular login, autoLogin, emergency shell, minimalAuth). The login UI's first-boot dialog calls `users.promoteAfterFirstBoot(token)` once `changePassword` has cleared the flag in the DB to elevate the session to its real tier.
- **Network MAC + nonce + downgrade guard** — encrypted TRUSTED-peer payloads carry a per-packet random nonce and an HMAC-SHA256 over `(algo || nonce || ciphertext)`. Receivers verify the MAC before any decryption work, refuse duplicate nonces (ring buffer of last 512 per peer), and refuse `enc = "xor"` packets when the receiver has a data card (no downgrade onto the no-MAC software cipher). Old peers without this fix fail the MAC check and get dropped — upgrade peers in lockstep.
- **`flash` requires typed confirmation** — the BIOS-flash command prints the source path, file size, SHA-256 fingerprint, EEPROM label, and current boot address, then requires typing the literal word `flash` to commit. A stray `y` keystroke can no longer brick the machine.
- **rc.d `_kernel_` allowlist** — services that declare `user = "_kernel_"` are only honored from a hardcoded allowlist (`10-discoveryd`, `20-chatrelay`, `20-fileshare`, `20-rshd`). Other services that match the regex peek (including matches inside comments) are demoted to the regular user-tier sandbox.
- **Cluster Manager-Worker HMAC** — when a cluster shared secret is configured via `cluster_worker.setSecret()`, every WRK frame (REGISTER / RESULT / PROGRESS / PONG / TASK / CANCEL / PING) carries an HMAC-SHA256 over `(op || task_id || nonce)`. Frames missing or failing the MAC are dropped; replayed nonces are rejected via a ring buffer of the last 1024 accepted nonces. Re-REGISTER while a task is in flight is refused (closes an attacker-spoofed-worker abort vector).

### Architecture (v1.2.5)

- **Panels split** — `panels/init.lua` broken into 14 focused submodules: state, helpers, tabs, widgets, dialogs, draw, filebrowser, editor, context, commands, executor, menus, events, keymap

## Earlier highlights (v0.2.1 → v1.2.5)

Security hardening — `securefs` normalization, protected-path deletion, remote-shell sandbox tightening, trust-level clamping, cron sandbox, module sandbox, module install path traversal, remote execution wired into the TRUSTED tier, and dozens of bugfixes across the kernel, shell, compat, and networking modules. The full list is not recorded anywhere else; consult the source comments and `tos/kernel/sandbox.lua` for context on individual hardening decisions.
