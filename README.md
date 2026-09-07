# TOS — Terminal Operating System

**A multi-user operating system for the OpenComputers Minecraft mod.** Logins,
per-user permissions, a capability sandbox, signed packages and an encrypted
mesh network — on a machine with 256 KB of RAM.

**Requires OpenComputers 1.7.5 or newer, on Minecraft 1.12.2**, with a CPU set
to the **Lua 5.3 or 5.4 architecture** (sneak-click the CPU to switch) and a
Tier 2 disk. Full requirements below.

Current release: **v1.5.0 "Aletheia"** — see [`CHANGELOG.md`](CHANGELOG.md) for
what changed.

<!-- SCREENSHOTS -- see docs/screenshots/SHOTS.md for the shot list and how to
     capture them. Delete this comment wrapper once the files exist on `dev`;
     the URLs are absolute so the same README renders on every branch.

<p align="center">
  <img src="https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/dev/docs/screenshots/desktop.png"  alt="The Desktop: a tile home screen" width="49%">
  <img src="https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/dev/docs/screenshots/rbmk.png"     alt="The RBMK reactor supervisor" width="49%">
</p>
<p align="center">
  <img src="https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/dev/docs/screenshots/boot.gif"     alt="Boot to login to Desktop to a theme switch" width="80%">
</p>
-->

## Install it

On a bare OpenOS machine with an Internet Card, one line:

```
wget -f https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/main/bootstrap.lua /bootstrap.lua && /bootstrap.lua
```

**The leading slash is not optional** — `wget` saves to the filesystem root,
and the root is not on OpenOS's `PATH`. No Internet Card? Install from a floppy
or from source instead; see [Installation](#installation) for all three routes.

Log in as `root` / `root`; the first boot makes you change it and offers a
walkthrough.

## Why not just use OpenOS?

OpenOS gives you a shell. TOS gives you accounts and logins, per-user file
permissions, a capability-based sandbox that user programs cannot escape,
package signing, and an authenticated encrypted mesh between machines — on
hardware OpenOS itself targets.

It is **keyboard-first and built to run infrastructure**: a base that has to
keep working. It degrades to Tier 1 monochrome rather than requiring a big rig,
runs a full independent session on every GPU+screen pair, survives power loss
without corrupting its own filesystem, and ships a cluster scheduler and an
RBMK reactor supervisor for bases that need one. If you want a graphical
desktop on a maxed-out machine, MineOS is the better answer and this is not
trying to be it.

## What's in it

- **Accounts and permissions** — real logins, four tiers (guest/user/admin/root),
  per-user home directories and ACLs, `sudo`, session timeouts, lockout backoff.
- **A capability sandbox** — programs receive only what they declare and are
  granted; no ambient `_G`, no raw `component`, no back door into the kernel.
- **Signed packages** — `pkg` installs from a floppy, a directory, or over the
  network, verifying an Ed25519 signature and a per-file hash on arrival.
- **A zero-trust mesh** — peers are unknown until paired; TRUSTED traffic is
  encrypted and MAC-authenticated with replay protection.
- **A tile Desktop and a file browser**, nine named colour themes, and a full
  reference manual — [`MANUAL.md`](MANUAL.md), *The Book of TOS*.
- **OpenOS compatibility**, so much of what already exists still runs.

Read [`CHANGELOG.md`](CHANGELOG.md) for what each release changed, and
[`ROADMAP.md`](ROADMAP.md) for what is still open — it is generated, carries
its own count, and includes the items deliberately *not* done and why. If you
are looking for somewhere to start, start there.

Contributions welcome: [`CONTRIBUTING.md`](CONTRIBUTING.md) has the branch
layout (work on `dev`, never `main`), the setup, and the house rules for
writing code that has to fit in 192 KB.

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

1. Download and run it, in one line. No other TOS files are needed first:
   ```
   wget -f https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/main/bootstrap.lua /bootstrap.lua && /bootstrap.lua
   ```
   **The leading slash on `/bootstrap.lua` is not optional.** `wget` saves
   it at the filesystem root, and the root is not on OpenOS's `PATH` — so
   typing plain `bootstrap.lua` afterwards gets "command not found" no
   matter which directory you are in. Running it by absolute path works
   from anywhere and needs no `cd`.

   If your shell does not chain with `&&`, it is two commands and the
   second is still the absolute path:
   ```
   wget -f https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/main/bootstrap.lua /bootstrap.lua
   /bootstrap.lua
   ```
   (No `wget`? Any way of getting one file onto an OpenOS machine works —
   `pastebin`, typing it in with `edit`, another disk. `bootstrap.lua`
   itself needs nothing but the Internet Card from here on.)
2. It downloads the release (bios.lua, install.lua, and every file
   `/tos/system_manifest.lua` declares) from GitHub into a scratch
   directory, then hands off to that install.lua exactly as if it were a
   mounted floppy — the same FORCE-WIPE confirmation, BIOS fingerprint
   check, and post-copy size verification run unchanged.
3. Reboot — first-boot tutorial guides you through the system

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
Ctrl+S       Save         Ctrl+Q        Close tab     Ctrl+F  Find
Ctrl+H       Replace      Ctrl+Z        Undo          Ctrl+G  Go to line
Ctrl+Insert  Copy         Shift+Delete  Cut (^X)      Shift+Insert  Paste (^V)
```

Copy is `Ctrl+Insert`, not `Ctrl+C`: the kernel takes `Ctrl+C` as the
foreground interrupt and blanks the signal, so `^C` never reaches the editor
(see MANUAL §4.3).

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

## GPU Tier Support

TOS detects your GPU tier and applies an appropriate base palette:

- **Tier 1 (monochrome)**: Black background, white text, inverse for bars and selections. Themes are intentionally disabled — RGB collapses to 1-bit and the result would be unreadable.
- **Tier 2 (16-color)**: Exact Minecraft dye palette values. Theme RGB values snap to the nearest dye on apply; you'll see the snapped result live.
- **Tier 3 (256-color)**: Full RGB freedom. Themes apply exactly as configured.

All UI code references the theme system (`display.c("name")`) rather than hardcoded hex values, so every screen looks correct on any GPU.

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
   TBFS drive — it reads the TBFS boot region directly), loads `/init.lua`.
   **It will boot a disk that has nothing to do with TOS**, OpenOS included:
   a valid `/init.lua` is the whole requirement. The TOS-specific POST check
   (`K4`, kernel missing) applies only when the `/init.lua` it just read is
   TOS's own, since that is the one that cannot run without a kernel.
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
- **There is no scheduler preemption on OpenComputers.** The wall-clock
  budget in `kernel/process.lua` and the remote-exec step budget in
  `kernel/net/remote.lua` are both built on `debug.sethook`, and OC's
  sandbox deliberately withholds it (the machine uses its own hook for the
  "too long without yielding" deadline, and guest code that could call
  `sethook` could disarm it). So on every real machine — and in the
  emulator — neither budget is armed: a runaway process, or hostile Lua
  arriving through `rsh`, runs until OC's watchdog reboots the *whole
  computer*, and the `/var/crash/preempt.txt` breadcrumb that would name the
  culprit is never written. `proc.preemptionAvailable()` and
  `remote.stepBudgetAvailable()` report this honestly, and the first remote
  command to run without a budget logs a warning. The hook code stays so the
  off-box suite exercises it, and it would arm on a host that exports
  `sethook`. Treat a runaway as an attributable denial-of-service, not a
  containment break — and treat `rsh` as what it is: unbounded code
  execution for TRUSTED peers, off by default.
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
