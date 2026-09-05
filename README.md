# TOS v1.4.0 "Iris"

Terminal Operating System for OpenComputers (Minecraft).
A Norton Commander-inspired OS with a tile Desktop, zero-trust networking, OpenOS compatibility, multi-seat support, named color themes, and a modular kernel.

> **Operators:** the full reference is [`MANUAL.md`](MANUAL.md) — *The Book of TOS*, in two halves: **The Operator's Guide** (tutorial chapters) and **The Reference** (alphabetical command listing + appendices). Three depths of help: `help` gets you moving (install-aware), `man <topic>` is the in-system page, and the Manual is the long story.

## Released

TOS is public and installable. v1.4.0 "Iris" is the current release — install it with the [network bootstrap](#over-the-network-no-disk-no-floppy), from an install disk, or from source. Bug reports and contributions are welcome; see [`CONTRIBUTING.md`](CONTRIBUTING.md).

[`ROADMAP.md`](ROADMAP.md) is what is actually open — 61 items, including the ones deliberately *not* done and why. If you are looking for somewhere to start, start there.

## Three branches

| Branch | What it is | Edit it? |
|---|---|---|
| **`main`** | The **release build** — what installers download. Comments stripped, dev tests and build tooling removed, blank-line runs collapsed. | **No.** Generated. |
| **`dev`** | The **source tree**. Full `--!` security/invariant comments, `usr/lib/tests/`, `build/`, notes. | **Yes** — all work happens here. |
| **`optional-utilities`** | The **add-on pack**, laid out as a `pkg` repository so a machine with an internet card installs from it directly. | **No.** Generated from `TOS-Extras/` on `dev`. |

**`main` is a build artifact, not a source tree.** Every file on it is generated from `dev` by `build/strip.lua`, so a change committed to `main` is silently destroyed by the next release build. Open pull requests against **`dev`**.

The split exists because comments cost real memory on a machine that has 192 KB of it, and the BIOS is fighting a hard 4 KiB EEPROM budget — roughly a third of `bios.lua` is comments that must not ship, and must not be lost either. `strip.lua` keeps every `--!`-marked comment (security notes, cross-file invariants, license headers) and drops the rest.

Installing from either branch works, since both carry the same tree shape and the same `tos/system_manifest.lua`:

```
bootstrap.lua                                            # main (release)
bootstrap.lua Evan450/TOS-Terminal-Operating-System- dev  # dev (source)
```

## What's New in v1.4.0 "Iris"

A UI release: TOS gets a face that isn't a prompt — without moving the prompt.
See [`CHANGELOG.md`](CHANGELOG.md) for detail.

### The Desktop

- **A tile home screen** (`desktop`, or System → Desktop): built-in apps
  (Files, Monitor, Chat, Mail, Launcher, Settings, Help, Tutorial, Log Out)
  plus a tile for every command an installed package provides — installed
  programs are visible, not memorized. Tiles honor the command registry's
  tier + hardware gates.
- **It's a view of Home, not a second place to be.** Home is one tab; the tile
  grid and the file list are two views of it and **F2 flips between them**. The
  prompt is resident in both, on the row it has always been on, so a tile
  launches through the same executor as typing the command *and* its output
  lands on the same rows. Keyboard-first (arrows, Enter, `Alt+1-9`,
  PgUp/PgDn), clickable with the mouse add-on, and it degrades to a numbered
  list on Tier-1 mono screens.
- **Per-user landing** — the `landing` profile field picks which view login
  opens: root defaults to files, everyone else to tiles. Change it in
  Settings → Home. Boot Settings → Interface → `split` restores the older
  two-tab shape if you want it.

### The Settings app

- `settings` (or Settings → Settings App): **Appearance** (live theme preview
  + save), **Status Bar** (widget checkboxes), **Desktop** (landing), and
  **System** (bootsettings / users / doctor / about buttons, tier-gated) —
  forms instead of memorized commands.

### Browser polish + shared toolkit

- **File-type glyphs** in the browser (`■` dir, `♦` lua, `≡` text, `§` config,
  `▓` archive), and a new shared `ui.lua` widget toolkit (tiles, setting rows,
  grid math — unit-tested off-box) that the Desktop and Settings app build on.

### Translations (framework)

- **Community-translatable UI** — language catalogs are plain data files in
  `/usr/lang` (no code changes to translate; partial catalogs are fine —
  untranslated strings keep their English default). `lang` lists/sets your
  language, `lang dump` writes a translator template. Login + Desktop are the
  first translated surfaces, with a Russian starter catalog included; width
  math is unicode-aware so Cyrillic (and later CJK) render straight.

### Fewer commands, same power

- **Command consolidation** — overlapping commands merged into one obvious
  door each: `ver`→`about`, `device`→`hostname`, `swap`→`optimize swap`,
  `restore`→`trash restore`, `servers`→`net servers`; a dozen aliases now
  collapse onto one `help` row (`ls (dir)`). The `launcher` command retired —
  the Desktop is the menu surface (it tiles your `~/.launcher.cfg` entries
  too), and the keycard menu lives on as `tape-menu`. Pick your language from
  **Settings → Language**.

### Unmanaged drives (raw block devices)

- **TBFS** — TOS now uses *unmanaged* OC drives (raw `drive` components), not just managed disks. The base image detects them (shown as *Raw Drive* in
  `lsdev`/`hw`/POST) and inspects them with `drive`; install the **`blockfs`**
  Extras package and TBFS lays a real hierarchical filesystem onto the bare
  sectors so `drive format` / `drive mount` make one behave like any other
  disk. Includes fsck (`drive check --repair`) and a **defragmenter**
  (`drive defrag`, manual or `--if-over N` for cron-driven upkeep). The driver
  is pure and ships with 52 off-box unit tests.

Also folds in the previously-unreleased maintenance pass (dead-code prune, a
security fix, JBOD as opt-in, the mouse add-on) — see the CHANGELOG.

## What's New in v1.3.2 "Argus"

A focused security-and-usability release. See [`CHANGELOG.md`](CHANGELOG.md) for detail.

### Security fixes

- **Process control is admin-gated again** — `fg` and `kill` were missing their
  in-body tier guard (the panels executor does no dispatch-level tier check), so
  any logged-in user could invoke them. Restored to ADMIN, matching `bg`/`run`.
- **Input-injection fix (#SEC H13)** — `proc.setForeground` now enforces
  ownership of the *target* process, not just the seat. Without it, a low-tier
  user could point their own seat at a higher-privileged process and have their
  keystrokes delivered to it. Fixed in the kernel, so it covers every caller.
- **File serving fails closed** — `kernel.net.transfer`'s FILE_REQ server no
  longer defaults to armed at boot; it tracks the `fileshare` service lifecycle
  like `rshd` does. Stock boots are unchanged.
- **Lua REPL gates on the live tier (#SEC M-7)** — `lua` checked a cached tier
  snapshot; it now uses the seat's current session like every other gate.

### Shell usability (additive — no layout or keybinding changes)

- **Function-key legend** on the shell's idle output row (`F1 Help · F3 View ·
  F5 Copy …`), classic file-manager style; width-responsive, and it yields to
  command output the moment there is any.
- **Help menu** (rightmost): Quick Help, Keyboard Shortcuts, Manual Pages,
  Tutorial, About — discovery for users who don't yet know the bindings.

## What's New in v1.3.1 "Polaris"

An internal-improvement release: a configurable boot process, resilience to
unsafe power-loss, disk swap, a smarter help system, and a cleaner package
story. No security regressions — the v1.3.0 audit posture is preserved and
extended. See [`CHANGELOG.md`](CHANGELOG.md) for the full list.

### Configurable boot ("everything → nothing")

- **Boot spectrum** in `/etc/boot.cfg`: a `profile` (`minimal`/`normal`/`full`/
  `diagnostic`/`safe`) controls *what loads*; a `verbosity` muter
  (`silent`/`splash`/`text`/`verbose`) controls *what it says*; `advanced`
  toggles override individual subsystems — including `services`, `cron`, and
  `packages`, the stages that run third-party code. Fail-safe — a
  missing/corrupt file boots `normal`, i.e. exactly as before.
- **Safe Mode** — `profile safe` (or press **S** at the POST screen for a
  one-time safe boot, config untouched): kernel + shell only, nothing
  third-party runs, but `pkg` admin verbs still work so the broken add-on can
  be removed. Boots loud with a SAFE MODE banner.
- **Self-repair** — `bootsettings repair on`: the next boot runs a one-shot
  repair pass (interrupted atomic writes, orphaned temps, stale `/var/run`,
  oversized logs, corrupt `boot.cfg`) and reports what it can't safely fix.
  The flag clears itself; a crashing repair can never loop.
- **CLI startup** — `bootsettings ui cli` boots every seat straight to the
  command line (lightest startup, and no loss of capability: the CLI runs the
  same commands and loads them as you use them); `tui` opens the panels
  interface on demand.
- **Honest hardware overrides** — `cputier`/`datatier` correct the two tier
  heuristics, `ramgate auto|plenty|tight` declares your RAM situation for the
  optional stages. Reliably-detected hardware (GPU/screen/modem) deliberately
  has no override.
- **System Configuration POST screen** — a TOS-ified AMIBIOS screen showing
  installed hardware **with tiers** (CPU detect/estimate/confirm, RAM, GPU,
  crypto card, disks, peripherals). Shown briefly each boot.
- **Boot Settings** — press **DEL** during the POST screen for the visual
  editor, or run `bootsettings` from the shell. Edits `/etc/boot.cfg`.

### Power-loss protection

- **Unsafe-shutdown detection** — a dirty-bit marker flags a boot that follows
  a power cut / forced off (vs. a clean `shutdown`), surfaced in the log, on
  the login screen, and in `doctor`.
- **Atomic writes** for the critical state DBs (`users.dat`, `trust.dat`,
  config, cron, `critical.bak`) so a power cut mid-save can't corrupt them;
  interrupted writes are repaired at boot.
- A **critical battery** is converted into a clean shutdown to protect data.

### Disk swap ("slow RAM")

- Explicit spill-to-disk for cold data, backed by `/var/swap`: a store API and
  a `swap.table{}` proxy (disk-backed table with an in-RAM LRU cache). Volatile,
  size-capped. Inspect via the `swap` command.

### Help, packaging & UI

- **Install-aware help** — `help` shows only commands whose hardware/module is
  actually present (no `chat` without a modem, no `robot` without the robot).
- **Package commands run directly** — `pkg`-installed packages' commands now
  dispatch through pkg's own sandboxed runner (the first step of retiring the
  legacy module manager). `pkg` also gained the `command` kind and a narrow
  `/etc/rc.d` + cfg exception for service packages.
- **Optional Utilities disk** — a pick-and-choose installer (`TOS-Extras/build/`)
  for the bundled add-ons, MS-DOS Supplemental-Utilities style.
- **PaneUI** (OpenOS) now renders TOS's nine named themes color-for-color.
- The cluster protocol + worker bridge **moved out of the base kernel** into the
  optional cluster package — ~1240 LOC of dormant code no longer ships in every
  install.

## What's New in v1.3.0 "Aegis"

A full security-audit pass — **every** consolidated finding across all four
severity tiers is fixed (9 Critical, 21 High, 21 Medium, 7 Low). No new
user-facing features; this is a correctness/security release. See
[`CHANGELOG.md`](CHANGELOG.md) for the complete per-finding list.

### Security highlights

- **Cluster worker is default-deny** — the Manager↔Worker bridge refuses to bind without a `shared_secret` in `/etc/cluster.cfg`, closing the unauthenticated remote-code-execution path.
- **Package manager hardened** — `pkg.install` verifies file hashes (constant-time) and confines writes to `/usr` and `/var/pkg`; install/uninstall/enable require an admin session; dependency-confusion and accept-all floppy installs are closed.
- **rc.d kernel-tier services** get a gated `require` (no pulling in `kernel.process`/`kernel.users`/`kernel.sandbox`).
- **Vault & keychain fail closed** without a data card (no XOR-"encrypted" secrets); the vault now uses domain-separated encryption/MAC subkeys (V2 format, V1 still readable).
- **`term.gpu()` is seat-bound and capability-gated** — sandboxed programs can no longer draw to or rebind another seat's screen.
- **Shell ACL checks use the bound seat principal** instead of a stale global session — fixing wrong-user reads/writes on multi-seat rigs.
- **Network replay protection** now binds a per-peer monotonic sequence + per-boot epoch into the packet MAC; **session tokens** accumulate cross-boot entropy.
- **`fs.normalize` fails closed** on tainted (NUL/malformed) paths instead of defaulting to the privileged root.
- **Login hardening** — no username/lock-state enumeration, and the root account (exempt from permanent lockout) now has reboot-proof exponential backoff.

> **Operator notes:** Cluster Managers must set a 16+ byte `shared_secret` in `/etc/cluster.cfg`; the keychain now requires a data card; network peers must be upgraded in lockstep (the packet MAC format changed).

## What's New in v1.2.6 "Beacon"

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

## What's New in v1.2.5 "Atlas"

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

## Earlier Highlights (v0.2.1 → v1.2.5)

Security hardening — `securefs` normalization, protected-path deletion, remote-shell sandbox tightening, trust-level clamping, cron sandbox, module sandbox, module install path traversal, remote execution wired into the TRUSTED tier, and dozens of bugfixes across the kernel, shell, compat, and networking modules. The full list lived in the previous README; consult the source comments and `tos/kernel/sandbox.lua` for context on individual hardening decisions.

## System Requirements

| Tier | RAM | Experience |
|------|-----|-----------|
| Minimum | T1 (192KB) | Degraded: minimal auth + emergency shell |
| Recommended | T1.5+ (256KB) | Full: login, CLI, panels, multitasking |
| Optimal | T2+ (512KB+) | All modules + compat layer + themes + generous headroom |

- **GPU**: Tier 1 (monochrome), Tier 2 (16-color), Tier 3 (256-color) — auto-detected
- **CPU**: Tier 1+ on the **Lua 5.3 or 5.4 architecture** (any tier works;
  sneak-click the CPU to switch architectures). The BIOS and `/init.lua` both
  probe for 5.3 *features* — 5.4 parses 5.3 syntax and carries every library
  TOS uses, so it boots normally — and halt with instructions on a 5.2 CPU:
  kernel modules use 5.3 bitwise syntax and the boot chain uses `string.pack`.
- **Disk**: **Tier 2 (2 MB) minimum for a full install.** The 152 files the
  manifest installs are ~1,518 KB, and OpenComputers charges a per-file cost
  (`fileCost`, 512 B by default) on top — so the real on-disk footprint is
  **~1,594 KB**. That does not fit a floppy (512 KB) or a Tier 1 HDD (1 MB),
  and leaves roughly 450 KB free on a Tier 2. Budget your own number as
  `bytes + 512 × files`; `deploy` prints the target disk's free space before
  it starts copying, so you can compare against it.

### Multi-seat: supported, but sequential use is recommended

TOS runs a full independent session on every GPU+Screen pair, so several
operators *can* be logged in on one computer at once. But OpenComputers gives a
computer a **single CPU** — one Lua execution stream and one per-tick call
budget shared by everything on the box. Two operators working *simultaneously*
therefore split that one CPU: each seat runs slower, and a heavy command on one
seat (a big `cp`, `find`, `pkg install`, or `drive defrag`) briefly slows the
others. This is a hardware limit of the mod, not a TOS defect.

TOS mitigates it — long commands cooperatively yield so a busy seat *slows*
rather than *freezes* the others, and the System Monitor (Ctrl+T) runs as a
per-seat process instead of pausing the whole machine — but it cannot remove
the shared-CPU ceiling. **Recommendation: treat multi-seat as taking turns.**
Several people using one box in sequence is smooth; several hammering it at the
same moment is not. For genuinely concurrent workloads, give each operator their
own computer (a higher-tier CPU raises the shared budget but never makes it
per-seat).

## GPU Tier Support

TOS detects your GPU tier and applies an appropriate base palette:

- **Tier 1 (monochrome)**: Black background, white text, inverse for bars and selections. Themes are intentionally disabled — RGB collapses to 1-bit and the result would be unreadable.
- **Tier 2 (16-color)**: Exact Minecraft dye palette values. Theme RGB values snap to the nearest dye on apply; you'll see the snapped result live.
- **Tier 3 (256-color)**: Full RGB freedom. Themes apply exactly as configured.

All UI code references the theme system (`display.c("name")`) rather than hardcoded hex values, so every screen looks correct on any GPU.

## Themes

Nine built-in presets:

| Name | Description |
|------|-------------|
| `default` | TOS classic — teal frames, gold titles on black |
| `midnight` | Tokyo night — indigo panels, neon accents |
| `amber` | Retro CRT — warm amber phosphor |
| `green` | Matrix — green phosphor on black |
| `plasma` | Plasma display — neon red-orange on black (night-vision friendly) |
| `classic` | Norton-style — white on blue, cyan bars |
| `contrast` | High contrast — readability first |
| `nord` | Nord — arctic blues and frost |
| `solarized` | Solarized dark — muted teal + earth accents |

Quick examples:

```
theme list                       List presets and which one is active
theme show                       Show active theme + per-user overrides
theme set midnight               Apply 'midnight' and save preference
theme preview amber              Apply 'amber' for the session, no save
theme color title 0xFF8800       Override the title color (saves automatically)
theme reset                      Drop overrides, keep current preset
theme clear                      Wipe saved theme, revert to default
theme keys                       List overridable color keys
```

Overridable keys: `bg`, `fg`, `border`, `title`, `highlight`, `dim`, `selected_bg`, `selected_fg`, `menubar_bg`, `menubar_fg`, `menubar_hot`, `statusbar_bg`, `statusbar_fg`, `error`, `warning`, `panel_bg`, `input_bg`, `input_fg`, `syn_keyword`, `syn_string`, `syn_comment`, `syn_number`, `syn_func`, `file_lua`, `dir_color`. Color values accept `0xRRGGBB`, `#RRGGBB`, plain `RRGGBB`, or decimal.

## Features

### Multitasking & Multi-Seat

- Cooperative multitasking via coroutine-based process scheduler
- Keyboard/mouse signals route to foreground process only
- Background processes (TSR) keep running during user interaction
- **Multi-seat**: each GPU+Screen pair gets its own independent shell session.
  Best used **sequentially** (operators taking turns), not simultaneously — see
  the performance note under [System Requirements](#system-requirements).
- **Ctrl+T** opens the live **System Monitor** — every process (kernel and user, each
  explained), the rc.d services, and memory/uptime in one auto-refreshing screen;
  switch to / kill / suspend a process, or start/stop a service. Also `monitor` (alias `top`).
- `ps` shows a one-shot process snapshot (`monitor` for the live, interactive view)
- `kill <pid>` and `fg <pid>` for process management

### Security (always active, all boot paths)

- Password required on ALL boot paths — removing RAM sticks does NOT bypass login
- SHA-256 (data card) or DJB2+FNV1a dual-hash passwords
- 4-tier access: ROOT / ADMIN / USER / GUEST
- **Role-based command execution** — `helpers.adminOnly()` / `rootOnly()` guards inside admin/root commands at dispatch time. Earlier releases relied solely on a `CATEGORY` map that only controlled lazy-loading; that map is now advisory and each admin-category command performs an explicit tier check at function entry.
- Account lockout after failed attempts + anti-brute-force delays. The failed-attempt counter and lock state persist in `/etc/users.dat`, and the exponential login backoff (#SEC H-5) is stamped with the wall clock (#SEC H-9) so neither the lockout nor the cooldown resets on reboot
- First-boot password change enforced + first-boot tutorial walkthrough
- Emergency shell also requires authentication
- **`securefs`** mediates every user-level filesystem operation; raw component access is denied to sandboxed code

### Shell

- Theme-aware prompt: `user@host:/path$`
- Formatted `ls` with tier-correct colors for file types
- RAM usage bar, status bar, F-key bar
- Command history (up/down arrows)
- Pipe (`|`), redirect (`>`), and append (`>>`) support
- PATH-based external program resolution
- Per-process environment variables
- F1 Help, F2 Tiles/Files, F5 Copy, Ctrl+T System Monitor, F10 Quit

### Home: tiles and files in one tab (`panels`)

- Norton Commander-inspired single-panel navigation with tab multitasking
- **One tab, two views** — F2 flips tiles ⇄ files; the prompt, the output row,
  the summary rail and the status bar stay put across the flip
- Runs as its own process — Ctrl+T switches back to shell
- Tab bar with memory info, menu bar (File | Tools | System | Settings);
  Tab moves between tabs when the command line is empty
- Enter to navigate, Backspace to go up, F3 View, F5 Copy, F6 Move, F7 Mkdir, F8 Delete
- **Select and copy text** — Shift+arrows (or click and drag with the mouse
  add-on) at the prompt, in the editor, and by the line in any command's
  output. `Ctrl+Insert` copies, `Shift+Insert`/`^V` pastes, `Shift+Delete`/`^X`
  cuts. One per-seat clipboard shared by all three, cleared at logout
- Built-in text editor with undo, find/replace, clipboard, and syntax coloring
- Context menus for files and directories

### Networking (Zero-Trust)

- 4-tier trust: BLOCKED / UNKNOWN / KNOWN / TRUSTED
- Encrypted comms (AES with data card, XOR software fallback)
- Challenge-response anti-spoofing for trusted connections
- Network discovery and peer hostname exchange
- Secure messaging with acknowledgment
- File transfer between trusted peers (`scp`, `share`)
- Remote command execution in a sandbox (`rsh`, `ssh`)
- Real-time chat TUI (`chat`)

### OpenOS Compatibility

- Shim layer for twelve OpenOS standard libraries: `sides`, `colors`, `keyboard`, `text`, `serialization`, `buffer`, `term`, `filesystem`, `event`, `shell`, `io`, `internet`
- `require("term")`, `require("filesystem")`, `require("event")`, etc. all work
- **OPPM-packaged programs install and run**, from a local repo or a disk:
  `pkg` reads all four manifest forms including a real OPPM `programs.cfg` repo
  index, translates its source→destination file mapping and its dependency
  list, and grants a foreign package the compat capabilities it never had to
  declare. See MANUAL §7.5.
- **Packages can be fetched over an internet card** — `pkg repo add <name>
  <url>` then `pkg fetch <name>`. The configured repo list *is* the allowlist:
  there is no default repo and no discovery, so a machine reaches only hosts an
  admin wrote down. A fetch downloads into a staging directory and then runs the
  **ordinary local install** against it, so hash verification, write-root
  confinement, conflict checks and the unverified-package gate are the same code
  for a remote package as for a floppy. See MANUAL §7.6.
- `require("internet")` works (OpenOS's `internet` library), gated by the
  `internet` capability. Still no shim for `thread` or `uuid`.
- Loaded conditionally — skipped on low-RAM systems to save memory
- `compat.filesystem.get()` returns a metadata-only proxy (no raw `open`/`list`/`remove`); use `filesystem.open` and friends for path operations

### Peripheral Integration

- Redstone I/O (vanilla + bundled cable support)
- Robot/drone movement, interaction, and inventory
- Inventory controller and transposer inspection
- Generic component method caller for any OC component

### Services & Scheduling

- `/etc/rc.d/` startup scripts with start/stop lifecycle
- Cron-like job scheduler with persistent storage
- Multi-screen GPU+Screen binding and runtime switching

### Power-Loss Protection

TOS detects when the previous session ended uncleanly — power toggled on the
computer block, battery drained, or the chunk/world unloaded — rather than via
a `shutdown`/`reboot`:

- A dirty-bit marker (`/var/run/pwrstate`) is stamped *running* early in boot
  and flipped to *clean* only by `kernel.shutdown`. A running/corrupt marker at
  the next boot means the last session was cut off.
- On an unsafe boot TOS complains in three places: a kernel-log warning + beep,
  a login-screen banner, and a `power` section in `doctor`/`diag` (which also
  shows the boot count and battery state).
- **Corruption is mitigated, not just reported.** The critical state files
  (`/etc/users.dat`, `/etc/trust.dat`, `/etc/tos.cfg`, cron DB, `critical.bak`)
  are written **atomically** (`fs.writeFileAtomic`: write a temp, then replace),
  so a power cut mid-save can never truncate them into an unparseable file that
  would lock you out. Any write interrupted mid-replace is repaired at boot
  (`fs.recoverAtomic`).
- On a tablet, a **critical battery** is converted into a clean shutdown (flushes
  state, clears the dirty bit) instead of an abrupt corrupting cut. Opt out with
  `critBatShutdown = false` in `/etc/tos.cfg`.

### Disk Swap ("slow RAM")

OpenComputers does not model transparent virtual memory — the Lua heap can't be
paged to disk, so `computer.totalMemory()` is a hard ceiling. What TOS provides
is an **explicit** spill-to-disk layer for cold data, backed by `/var/swap`:

- **Store API** (`_G._TOS.swap`): `store(key, value)` serializes a value out and
  frees the RAM reference; `fetch(key)` pages it back; plus `free`/`has`/`keys`/
  `usage`/`clear`.
- **Table proxy** (`swap.table{ hot = N }`): a table whose entries live on disk
  with a small in-RAM LRU "hot" cache. Reads/writes feel like a normal table
  (honors `#` and `pairs()`); cold entries are serialized out. Free it with
  `swap.freeTable(t)`. Sandboxed programs get *only* this self-namespacing API
  via the `swap` capability — no shared global keyspace.
- **Volatile by design** — `/var/swap` is wiped on every boot (like RAM, and to
  clear any crash debris). Size-capped via `swapMaxKB` in `/etc/tos.cfg`
  (default 4 MB), auto-clamped so swap can't fill the disk; over-budget writes
  fail loudly rather than corrupt.
- Inspect/maintain from the shell: `optimize swap` (status), `optimize swap keys`, `optimize swap clear`.
- Caveat: values round-trip through `kernel.serialize`, so functions/userdata
  inside a stored value are dropped — use it for data, not closures.

## Installation

### From Source

1. Run `install.lua` from OpenOS for guided setup
2. Flash `bios.lua` to EEPROM: `flash bios.lua`
3. Reboot — login as `root` / `root`, set new password on first boot

### From Install Disk

1. On an existing TOS machine: `deploy /mnt/floppy` (root only)
2. Move the floppy to the target OpenOS computer
3. Run `/mnt/<disk>/install.lua` — the installer copies all files, runs setup, and offers to flash the BIOS
4. Reboot — first-boot tutorial guides you through the system

The deploy command sources its file list from `/tos/system_manifest.lua`. As of v1.2.6 this manifest covers every runtime file, and `/usr/lib/tests/test_manifest_completeness.lua` enforces that property — run it before cutting a release to catch new files that were added but not listed.

### Over the Network (no disk, no floppy)

For a bare OpenOS machine with an Internet Card but no TOS install disk at
all — nothing has ever been copied onto it:

1. Get `bootstrap.lua` onto the machine, one line, no other TOS files
   needed first:
   ```
   wget -f https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/main/bootstrap.lua /bootstrap.lua
   ```
   (No `wget`? Any way of getting one file onto an OpenOS machine works —
   `pastebin`, typing it in with `edit`, another disk. `bootstrap.lua`
   itself needs nothing but the Internet Card from here on.)
2. Run it: `bootstrap.lua`
3. It downloads the release (bios.lua, install.lua, and every file
   `/tos/system_manifest.lua` declares) from GitHub into a scratch
   directory, then hands off to that install.lua exactly as if it were a
   mounted floppy — the same FORCE-WIPE confirmation, BIOS fingerprint
   check, and post-copy size verification run unchanged.
4. Reboot — first-boot tutorial guides you through the system

`bootstrap.lua` doesn't assume the repo's default branch or layout: it
probes `main` then `master`, and a bare repo root then a `TOS-Release`
subdirectory, before giving up. Point it at a fork or a specific
branch/layout instead of the built-in defaults:
```
bootstrap.lua <owner>/<repo>
bootstrap.lua <owner>/<repo> <branch>
bootstrap.lua <owner>/<repo> <branch> <subdir>
```
No Internet Card on the target machine? Craft one (Tier 1 is enough) or
fall back to the From Install Disk method above — a physical disk has no
network dependency at all.

### Optional Utilities (add-ons)

Add-ons that run on TOS but aren't TOS itself — a spreadsheet, mail, games, a printer driver, TBFS, the cluster control plane. They ship separately from the OS and install two ways.

**Over the network**, on a machine with an internet card, as an admin:

```
pkg repo add utils https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/optional-utilities
pkg search
pkg fetch calc
```

A fetch downloads into a staging directory and then runs the **ordinary local install** against it, so hash verification, write-root confinement and the unverified-package gate are the same code as installing from a floppy. The configured repo list *is* the allowlist: there is no default repo and no discovery, so a machine reaches only hosts an admin wrote down.

**From a floppy**, the MS-DOS Supplemental-Utilities way: build the disks with `TOS-Extras/build/build-disk.lua`, copy each `diskN/`'s contents onto its own floppy, insert one, and run `pkg install` to pick add-ons from a menu. The set manifest describes the whole set, so a machine with one disk in the drive still lists everything and can name the disk to ask for.

Packages below version 1.0.0 are deliberately excluded from the published pack — an unfinished add-on that installs cleanly is worse than one you cannot reach. `cluster-storage` and `rbmk-control` are held back on that rule today.

### Install-path fallbacks

`install.lua`'s disk auto-detection no longer assumes a floppy is
mounted at `/mnt/<name>` — it checks whatever directory actually
contains the script (so a staged network download, a loop-mounted
directory, or a non-standard mount point all work the same way a floppy
does), and a scripted or chain-loaded install can also name its source
directory explicitly as `install.lua`'s first argument instead of
relying on path detection at all. `bootstrap.lua` uses that argument to
hand off the directory it just downloaded.

## Shell Commands

### Files & Navigation

```
ls [path]    cd <path>    pwd    mkdir <path>    rm <path>
cp <src> <dst>    mv <src> <dst>    cat <file>    edit <file>
touch <file>    df    du [path]    find [path] -name <pattern>    grep <pat> <file>
head <file>    tail <file> [lines]    wc <file>    tree [path] [depth]
flash <file>    programs    history    which <name>
```

### Shorthand

```
alias                        List your command aliases
alias ll ls -l               Define one (saved in your profile)
unalias ll                   Remove one
which <name>                 What a name resolves to: built-in, package, or program
```

### Time & Customization

```
date [fmt]                   Wall-clock time (time = alias)
uptime                       System uptime
theme list|show|set|preview  Color themes (colors = alias)
theme color <key> <0xRGB>    Override a single color
theme reset|clear|keys       Manage overrides / list keys
```

### Session & Power

```
whoami    users    passwd    logout    reboot    shutdown    tutorial
```

### Administration (root only)

```
useradd <user>    userdel <user>    usermod <user> lock|unlock|admin|user
deploy <mount-point>                 Create TOS install disk
```

### Packages & Disks

```
pkg [list|search|info|install|uninstall|enable|disable|commands|from-floppy|make-disk] [args]
disk [list|info|install|export|eject] [args]
```

### Environment & Services

```
env [KEY=VAL]    service [start|stop <name>]    cron [list|add|rm]
optimize swap [status|keys|now|clear|on|off|auto]   Disk-swap status / maintenance
doctor    diag                       System health check (incl. power/swap)
```

### Peripherals

```
redstone [set <side> <0-15> | pulse <side> [dur]]    (rs = alias)
robot <forward|back|up|down|left|right|swing|use|detect|inv>
inventory [side]    (inv = alias)
component <type> [method] [args...]
```

### Network

```
net    ping <addr>    hostname [name]    config    battery
chat    rsh <addr> <cmd>    scp <addr>:<path> <local>    screen [list|next|N]
```

### Editor Keybindings

```
Ctrl+S  Save       Ctrl+Q  Close tab     Ctrl+F  Find
Ctrl+H  Replace    Ctrl+Z  Undo          Ctrl+G  Go to line
Ctrl+C  Copy line  Ctrl+X  Cut line      Ctrl+V  Paste
```

## File Structure

```
bios.lua                          BIOS (4KB EEPROM)
init.lua                          Boot loader + require() system
install.lua                       Interactive installer
bootstrap.lua                     Network bootstrap: fetches a release from GitHub, hands off to install.lua

tos/system_manifest.lua           Single source of truth for `deploy` and `verify`

tos/kernel/
  audio.lua                       Audio feedback (beep codes, volume control)
  backup.lua                      Directory-tree snapshot/restore
  bootcfg.lua                     Boot spectrum config (/etc/boot.cfg): profile + verbosity
  bootsettings.lua                Boot Settings editor (DEL-to-setup UI); edits /etc/boot.cfg
  bootsteps.lua                   Maps raw boot-log lines to splash-bar step narration
  clipboard.lua                   One per-seat clipboard shared by prompt, editor and output
  compress.lua                    Data-card deflate/inflate framing (.tcz containers)
  config.lua                      System configuration store
  crypto.lua                      Crypto (AES/data card + software fallback)
  cron.lua                        Scheduled task executor
  datacard.lua                    Shared data-card detection/capability probe
  diag.lua                        Health-check unit powering `doctor`
  display.lua                     TUI engine (tier-aware themes, drawing)
  ed25519.lua                     Signature verification for package manifests
  env.lua                         Per-process environment variables
  event.lua                       Event system (listeners, timers, intervals)
  fs.lua                          Virtual filesystem (mount, normalize, R/W)
  hal.lua                         Hardware abstraction layer
  i18n.lua                        Language catalogs (community-translatable UI text)
  init.lua                        Kernel orchestrator (boot, login, shutdown)
  internet.lua                    Internet-card transport (HTTP/TCP) + its bounds and kill switch
  jbod.lua                        Disk pooling (JBOD), opt-in
  keychain.lua                    Per-user passphrase stash
  log.lua                         Rotating file logger
  logo.lua                        Shared ASCII wordmark (splash/POST/login)
  monitor.lua                     System Monitor helpers (pure) backing Ctrl+T
  netfs.lua                       Mount a directory exported by another TOS machine
  notify.lua                      Unified notification surface (toasts, beeps, log lines)
  pipe.lua                        Shell pipe/redirect parsing & streams
  pkg.lua                         Package manager — install/enable/uninstall + dependency/hash verification
  pkgremote.lua                   Fetching packages over an internet card (repo → staging dir)
  pkgsign.lua                     Publisher trust store + manifest signature gate
  power.lua                       Battery monitoring (tablets)
  process.lua                     Cooperative process scheduler
  profile.lua                     Per-user profile (theme, env, startup cmds, cwd)
  rc.lua                          /etc/rc.d/ startup service manager
  repair.lua                      One-shot self-repair pass ("Self-repair next boot")
  sandbox.lua                     Capability-based program sandbox
  screen.lua                      Multi-screen GPU+Screen manager + displayProxy
  securefs.lua                    Filesystem ACLs
  selftest.lua                    On-box self-test battery (runs inside a booted TOS)
  serialize.lua                   Shared serialization (encode/decode/compact)
  sha256.lua                      SHA-256, split out so it works without a data card
  sha512.lua                      SHA-512 (RFC 8032 requires it for ed25519)
  srm.lua                         One front door over the four maintenance subsystems
  swap.lua                        Disk-backed "slow RAM" spill-over store
  sysinfo.lua                     Hardware inventory + tiering (System Configuration POST screen)
  theme.lua                       Named color themes + per-user persistence
  trash.lua                       Soft-delete layer backing `rm`/`trash`
  users.lua                       Multi-user auth (hash, lockout, roles)
  ustr.lua                        Unicode-aware string helpers
  vault.lua                       Passphrase-encrypted data blobs

tos/kernel/net/
  init.lua                        Network stack (zero-trust, send/recv/dispatch)
  aliases.lua                     Peer aliases (human-friendly names for modem addresses)
  chatpair.lua                    Out-of-band shared-secret pairing between two TRUSTED peers
  mesh.lua                        Mesh router (store-and-forward, controlled flooding)
  meshctl.lua                     Mesh transport: service-multiplexed, sealed, retried
                                  (chat/mail/… ride it; mail itself is an add-on)
  protocol.lua                    Packet format & message type definitions
  remote.lua                      Remote shell execution (sandboxed)
  transfer.lua                    File transfer (FILE_REQ/FILE_RES)
  trust.lua                       Trust manager (4-tier, challenge-response)

tos/compat/
  init.lua                        OpenOS compatibility layer loader
  sides.lua                       Side name/number constants
  colors.lua                      Minecraft color constants
  keyboard.lua                    Key scan code constants + helpers
  text.lua                        Text utilities (trim, wrap, pad, tokenize)
  serialization.lua               Wraps kernel.serialize for OpenOS API
  buffer.lua                      Buffered stream wrapper
  term.lua                        Terminal API (cursor, read, write)
  filesystem.lua                  Wraps kernel.fs for OpenOS API (metadata-only get)
  event.lua                       Wraps kernel.event for OpenOS API
  internet.lua                    `require("internet")` as OpenOS programs expect it
  shell_api.lua                   Shell path resolution & execution
  io.lua                          Standard Lua io library replacement

tos/peripheral/
  redstone.lua                    Redstone I/O (vanilla + bundled)
  robot.lua                       Robot/drone movement & interaction
  inventory.lua                   Inventory controller / transposer

tos/shell/
  init.lua                        Launcher: picks TUI or CLI, lets them hand off
  cli.lua                         The command line (same registry as the TUI)
  progenv.lua                     Sandbox program-env builder, shared by both shells
  login.lua                       Login screen
  panels.lua                      Forwarding shim -> panels/init.lua
  ext.lua                         Extended commands (net, ping, etc.)
  syntax.lua                      Syntax highlighting definitions
  chat.lua                        Peer-to-peer chat TUI
  clustersetup.lua                Guided cluster stand-up (Manager + workers)
  colophon.lua                    Easter egg (the second one)
  keys.lua                        One keybinding table every first-party surface reads
  kiosk.lua                       Locked-down single-app mode
  launcher.lua                    Full-screen clickable action menu (~/.launcher.cfg)
  pkgpicker.lua                   Pick-and-choose installer (MS-DOS Supplemental style)
  tutorial.lua                    First-boot role-aware tutorial

tos/shell/panels/
  init.lua                        Orchestrator — wires submodules together
  state.lua                       Shared state table for all panels
  helpers.lua                     Path, file, text, permission helpers
  apps.lua                        Tab-type registry (replaced a hardcoded type chain)
  tabs.lua                        Tab create/close/cycle/find
  home.lua                        One tab, two views — F2 flips tiles ⇄ files
  desktop.lua                     The tile grid of what this machine can do
  settingsapp.lua                 The Settings app (appearance, status bar, system)
  chatapp.lua                     Chat as a persistent panels tab
  monitorapp.lua                  Full-screen System Monitor (the grown-up Ctrl+T)
  ui.lua                          Shared widget toolkit (tiles, setting rows, grid math)
  widgets.lua                     Syntax highlighting + status bar widgets
  dialogs.lua                     Inline input prompts + search dialogs
  draw.lua                        All TUI rendering (tabs, menus, file list, editor)
  filebrowser.lua                 Navigate, copy, move, delete, rename, mkdir
  editor.lua                      View/edit tab opening
  selection.lua                   Text selection for prompt, editor and output
  mouse.lua                       Click/scroll handling via the optional mouse driver
  context.lua                     Right-click context menu
  commands.lua                    Command registry front end
  commands/core.lua               Core commands (files, navigation, session)
  commands/admin.lua              Admin/root commands (users, deploy, flash)
  commands/extras.lua             Everything else (net, pkg, disk, peripherals)
  executor.lua                    Command executor + pipe/redirect handler
  menus.lua                       Menu bar action handler
  events.lua                      Main event loop + signal dispatch
  keymap.lua                      OC scancode table
  takeover.lua                    Administrative-handover cinematic

etc/rc.d/                         Boot services (discoveryd, chatrelay, fileshare, netfsd, rshd)
usr/bin/                          User tools (share, ssh) — `servers` folded into `net servers` (v1.4.0)
usr/lang/                         Language catalogs (community-translatable UI text)
usr/man/                          Manual pages served by `man`
usr/lib/tests/                    Regression tests (dev tree only; not in a Release build)
```

## Boot Sequence

1. **BIOS** — minimal EEPROM: finds the boot disk (managed filesystem or raw
   TBFS drive — it reads the TBFS boot region directly), loads `/init.lua`
2. **Stage 0** — locate boot filesystem (TOS BIOS pass-through, TBFS
   unmanaged root, or scan)
3. **Stage 1** — build `require()` system, register `package.loaded`
4. **Stage 2** — GPU + early display for boot messages
5. **Stage 3** — system integrity check (optional, validates all manifest files)
6. **Kernel boot**:
   - Core modules (log, HAL, filesystem, config, events, processes, display)
   - Power monitoring (tablets)
   - Security subsystem (crypto, users, securefs)
   - **Theme manager** (loads after security so per-user themes can persist)
   - Network stack + file transfer + remote shell handlers
   - Startup services (`/etc/rc.d/`) and cron scheduler
   - OpenOS compatibility layer
7. **Login** — full login screen or minimal auth (low RAM fallback)
8. **Theme apply** — kernel reads the user's saved theme on `tos_login_complete` and applies it before spawning the shell
9. **First-boot tutorial** — role-filtered walkthrough (auto-skipped after first run)
10. **Shell** — panels TUI by default, or the CLI (`ui=cli`, or `cli` at any prompt). Same command set either way; the CLI loads command groups as you use them

## Known Limitations

- **OpenOS compatibility is best-effort.** A program that expects raw `component.proxy("filesystem")` access or assumes ambient `_G` authority will hit sandbox/securefs walls. Programs that stick to documented OpenOS APIs typically work.
- **Themes are global to the running display.** Each seat shares a single live `THEME` table; the *last* user to log in (or run `theme set`) determines the colors all seats currently see. Per-seat themes are not yet supported.
- **Remote shell is OFF by default.** `20-rshd.lua` ships beside a `.disabled` marker, so the daemon is registered but not started at boot — remote code execution is opt-in. Enable it deliberately with `service start 20-rshd` (which clears the marker so it persists). Even then it only honors TRUSTED-tier peers; review the trust list (`net trust`) before exposing a machine.
- **Packages install verified by default.** `pkg install` refuses a package whose manifest doesn't declare a SHA-256 for every file — an unverified package is unchecked executable code. The Optional Utilities build generates these hashes, so first-party add-ons install (and are integrity-checked) with no friction; a third-party package without hashes needs an explicit `pkg install --allow-unverified` (logged, and flagged in the installed-package DB).
- **Multi-seat needs stable GPU/screen bindings.** `screen.lua` snapshots bindings at boot and on hot-plug; renaming or swapping screens at runtime can leave a seat without input until the next reboot.
- **Packages, not modules.** As of v1.3.1 the legacy module manager is gone; `pkg` is the single install/enable/uninstall + command-dispatch system. `pkg` does dependency resolution and SHA-256 hash verification (constant-time) at install, and runs package commands in a capability sandbox whose facets are allowlisted — a manifest can never request the `legacy` (raw os/io) cap. Still: a manifest *without* declared hashes installs unverified, so write access to `/usr/modules/<name>/` is code execution at next run. Treat third-party packages with the usual caution.
- **Scheduler preemption can be trapped by hostile code.** The wall-clock
  budget kills a runaway process by raising an error from a debug hook — a
  process spinning inside its *own* `pcall` catches that error and never
  returns control, so the whole machine eventually reboots via OC's
  "too long without yielding" watchdog (this is a Lua limitation: a hook
  cannot yield across the C boundary, so true preemption needs C-side support
  OC doesn't provide). TOS shrinks the blast radius: once the budget blows,
  the hook re-arms to raise on *every* instruction (the trap loop starves
  instead of computing), and a breadcrumb at `/var/crash/preempt.txt` names
  the culprit — `doctor` surfaces it after the reboot. Sandboxed user code
  can still trigger the reboot deliberately; treat it as a (attributable)
  denial-of-service, not a containment break.
- **Boot chain integrity is not yet cryptographically anchored.** `/init.lua`, `/tos/system_manifest.lua`, `/var/pkg/installed/tos-core/package.lua`, and `/etc/critical.bak` are loaded as Lua at boot; the BIOS verifies that `/init.lua` parses but does not check file hashes. Anyone with write access to those paths (ADMIN+ via securefs) gets unconditional code execution before login.
- **XOR fallback encryption is now MAC-protected and replay-protected on the wire.** When a data card is unavailable the net layer still falls back to XOR with a hashed shared key (XOR itself remains malleable cipher-only), but the HMAC over `(algo || nonce || ciphertext)` and per-peer nonce ring buffer apply to both `aes` and `xor` modes — a captured XOR packet cannot be replayed or trivially edited without breaking the MAC. Receivers with a data card refuse inbound `enc = "xor"` packets (no downgrade). The kernel log still emits a one-time warning when the local sender has to use XOR.

## License

TOS is licensed under the **GNU General Public License v3.0** — see
[`LICENSE.txt`](LICENSE.txt) for the full text.

Copyright © 2026 Strata Systems LLC. This program is free software: you may
redistribute it and/or modify it under the terms of the GPLv3. It comes with
ABSOLUTELY NO WARRANTY (see sections 15–16 of the license).

**Third-party reference material.** The repository keeps a copy of the
OpenComputers **OpenOS** source under `Reference/OpenOS/` purely for API
reference while developing TOS's compatibility layer. That code is **not part
of TOS**, is **not shipped** in a TOS release build, and remains under its own
license (OpenOS is MIT-licensed by the OpenComputers project). Do not treat
anything under `Reference/` as GPL TOS code.
