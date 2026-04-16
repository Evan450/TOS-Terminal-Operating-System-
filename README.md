# TOS v1.2.5 "Atlas"

Terminal Operating System for OpenComputers (Minecraft).
A Norton Commander-inspired OS with zero-trust networking, OpenOS compatibility, multi-seat support, and a modular kernel.

## What's New in v1.2.5 "Atlas"

### Multi-Seat / Multi-Screen
- **Per-display shell sessions** — each GPU+Screen pair spawns its own independent shell process with its own login, cwd, and foreground tracking
- **displayProxy** — full TUI proxy (box-drawing, menus, dialogs, themes) delegated per-display via `display.withContext()`; no drawing crosstalk between screens
- **Correct input routing** — keyboard signals route via `displayForKeyboard()`, touch/drag/drop/scroll route via `displayForScreen()`; Ctrl+C interrupt targets the correct display's foreground process
- **Terminal Server / Remote Terminal** support — OC Server Racks with Terminal Server expansions and wireless Remote Terminals work transparently as additional seats

### Security Hardening (v1.2.5)
- **Module path traversal fix** — boundary-aware prefix matching prevents `/usr/modules/foobar` from passing a check for `/usr/modules/foo`
- **Sandbox component filtering** — `makeSafeComponent()` whitelists allowed component types (filesystem, gpu, screen, modem, etc.) and blocks access to eeprom, computer, and other dangerous components from user programs
- **Boot integrity expanded** — BIOS verification covers 10 critical system files and 22 non-critical files, including all kernel modules, networking stack, shell, and compat layer

### Architecture (v1.2.5)
- **Panels split** — `panels/init.lua` (3,664 lines) broken into 14 focused submodules: state, helpers, tabs, widgets, dialogs, draw, filebrowser, editor, context, commands, executor, menus, events, keymap
- **77 source files, ~20,700 lines** across kernel, shell, compat, and peripheral layers

## What's New in v0.2.1

### Security Hardening
- **Path traversal fixes** in `users.lua` — access control now uses boundary-aware prefix matching (`/tmp` no longer matches `/tmpfiles`, `/public` no longer matches `/publicdata`, etc.)
- **securefs normalization bypass closed** — permission checks and file operations now both use the normalized path, preventing `/../` traversal attacks; init guards added for early calls
- **securefs protected path deletion** — `securefs.remove` now blocks deletion of protected paths and all their children, not just exact matches
- **Remote shell sandbox hardened** — shared `table`/`string`/`math` libraries are now shallow-copied so remote commands cannot poison host-process globals; `fs` access restricted to `/public/` only; output size capped during capture to prevent memory exhaustion
- **Trust level clamping** — deserialized trust database levels are now validated against the set of known levels, preventing privilege escalation via tampered trust files
- **Cron sandbox tightened** — removed `require`, `load`, `io`, and raw `os` from the cron job sandbox; jobs get controlled fs access and safe `os` subset instead
- **Module sandbox tightened** — removed `dofile` and `io` from the module sandbox; shared libraries are shallow-copied to prevent host poisoning
- **Module install path traversal** — manifest file paths are now validated to stay within the module directory, preventing `../../` writes to system paths
- **Remote execution enabled** — added `remote_exec` and `remote_res` to the TRUSTED trust-level permission table (previously missing, making the entire remote shell module non-functional)

### Bug Fixes

#### Critical
- **User security config scoping** — `MAX_FAILED_ATTEMPTS`, `LOCKOUT_AUTO`, and `SESSION_TIMEOUT` were declared `local` *after* `users.init()`, so config overrides (custom max login attempts, session timeout, lockout policy) silently wrote to globals instead of the locals used by the authentication code — **all custom security settings from config were being ignored**. Declarations moved before `init()` so config values now take effect.
- **`users.init()` crypto nil crash** — `crypto.init()` was called unconditionally; now guarded with a nil check to prevent boot crash when the crypto module is unavailable.

#### High
- **Session table iteration safety** — `users.delete()` and `users.sweepSessions()` both modified the `sessions` table during `pairs()` iteration (undefined behavior in Lua). Both now collect keys into a separate list before removing entries.
- **Panels `disk list` silent no-op** — when `F.mounts()` returned data (the normal case on a working system), the entire `disk list` command body was skipped because the `else` branch was missing. Now properly displays all non-root mount points with labels and module/TOS/data status.
- **Panels `wrapLine` character loss** — when word-wrapping found no space to break at, `text:sub(cut + 2)` silently dropped one character at the wrap boundary. Now only skips the extra character when a space break was actually found.

#### Medium
- **Compat buffer `*n` infinite loop** — reading a number (`*n` format) from a non-numeric input stream looped forever accumulating data. Now checks if the first non-whitespace character could start a number and returns `nil` immediately if not, with a 64-byte safety cap.
- **Display `setTheme` derived fields** — calling `display.setTheme({border = 0xFF0000})` updated `THEME.border` but left derived fields (`panel_active`, `sel_bg`, `dir`, etc.) stale at their old values. Extracted derived-field sync into `syncDerivedTheme()` and call it automatically after every `setTheme()`.
- **Serializer `\0` escape** — removed special-case `\0` handler that conflicted with multi-digit decimal escapes (e.g., `\000` followed by `9`); `\0` now correctly falls through to the generic `\DDD` digit parser
- **Serializer `-inf` parsing** — `-inf` is now correctly parsed as a keyword instead of being misrouted to the number parser (which would error on the `i` character)
- **Screen manager** — added `ensureInit()` calls to `get()`, `setActive()`, `next()`, `gpu()`, and `getResolution()`; `next()` now guards against division by zero when no displays exist
- **Event listener dispatch** — one-shot listeners (`event.once`) no longer cause other listeners to be skipped during the same dispatch cycle (iteration now uses a snapshot)
- **User config values respected** — `users.lua` now reads `maxAttempts`, `autoLockout`, and `sessionTimeout` from config instead of using hardcoded values; `getUser()` returns a shallow copy to protect internal state
- **Filesystem mount matching** — `resolve()` now requires a path boundary after the mount prefix (`/mnt/data` no longer matches `/mnt/data2`); parent directory creation in `writeFile` fixed for pcall error case
- **Display status bar** — right-aligned text now correctly placed at `W - #right + 1` (was off by one, leaving a gap at the right edge)
- **Display writeWrapped** — empty lines are now preserved instead of being silently skipped; dialog message splitting also fixed
- **Process manager** — removed unnecessary `function(...) return func(...) end` wrapper in `coroutine.create`; dead processes now have their coroutine reference cleared immediately for earlier GC
- **Compat proxyCache** — `component.__index` proxy cache is now properly weak-referenced (`__mode = "v"`) so removed-component proxies get garbage collected (comment said weak, code wasn't)
- **Compat buffer `*n` pattern** — fixed invalid Lua pattern (`--` range inside character class) that caused incorrect numeric reading
- **Compat filesystem.get** — now returns the longest-prefix mount match instead of the first (shortest) match
- **Compat shell.resolve** — alias resolution now has a recursion depth limit of 8, preventing infinite loops from self-referencing aliases; non-existent absolute paths now return `nil` instead of the path
- **Robot slot default** — `robot.count()` and `robot.space()` now default to the currently selected slot instead of invalid slot 0
- **Net global leaks** — `logMessage` and `dispatchToListeners` are now properly declared as `local` with forward declarations instead of leaking into `_G`
- **Protocol depth check** — off-by-one fixed (`d > 8` changed to `d >= 8`) to correctly enforce 8-level nesting limit
- **Modules stopAll** — now collects module names before iterating, preventing undefined behavior from modifying `active` table during `pairs()` iteration
- **Trust forget nil guard** — `trust.forget()` now checks for nil address and missing peer before proceeding
- **Trust getPendingRequests** — now returns a shallow copy instead of the internal mutable table
- **Tape-storage `--overwrite`** — flag parsing rewritten to correctly handle `tape store <path> --overwrite` and `tape store --overwrite <path>` (was broken: compared flag value against path instead of separating flags from positional args)

#### Low
- **Login nil guard** — `_G._TOS.version` access in the login screen is now nil-safe
- **Ext.lua nil guard** — `_G._TOS.audio` access is now nil-safe; audio volume is clamped to 0-100
- **Crypto salt entropy** — added incrementing counter to salt seed to prevent identical salts when called in quick succession
- **Install randomseed** — `math.randomseed` is now called before generating random hostnames during installation
- **Install pcall guards** — `component.proxy` calls wrapped in pcall; disk free space clamped to non-negative
- **Power warning reset** — critical and low battery warnings now reset independently (critical resets at `CRIT_THRESHOLD + 5`, low at `LOW_THRESHOLD + 5`)
- **RC dead code removed** — unused `proc` module reference removed; confusing double-check for RC_DIR existence simplified
- **`securefs.open` mode check** — now also checks for `+` in file mode (e.g., `r+`) when deciding whether to apply write permission checks
- **`securefs.resolve` tilde** — `~` expansion now only triggers for `~` or `~/path`, not for paths like `~admin`
- **`os.tmpname` uniqueness** — temp file counter now seeded with uptime to avoid collisions across compat reloads
- **Cron sandbox comment** — fixed misleading "read-only" comment when `fs.writeFile` was intentionally included for maintenance jobs


### Architecture
- **Shared serialization module** (`kernel/serialize.lua`) — eliminates four duplicate serialize/deserialize implementations across config, users, trust, and protocol modules
- **Deduplicated file operations** in the panel browser — F-key and context-menu handlers share a single code path for move, delete, and rename
- **Dead code removal** — removed `detectScreenTier()` (always returned nil) from HAL; removed 4 obsolete shell functions from ext.lua that had already been reimplemented in panels.lua
- **Net listener system overhaul** — `net.on()` now returns a listener ID, and `net.off(msgType, id)` enables clean temporary listener registration/teardown used by file transfer and remote shell
- **Ring buffer fix** — network message log `status().messageCount` now correctly reads the ring buffer counter instead of using `#` on a sparse table

### First-Boot Tutorial
A role-aware, skippable walkthrough runs automatically on first login:
- 11 pages covering navigation, commands, tabs, editor, account, admin, networking, and system internals
- Pages filtered by user tier — guests/users see basic content, admins see services and networking, root sees everything
- Navigate with Enter/Backspace/arrows, skip with Ctrl+Q
- Marker file (`/etc/.tutorial_done`) prevents re-showing; re-run anytime via the `tutorial` command (use `tutorial --reset` to clear marker)

### Role-Based Access Control
Commands and help text are now filtered by the user's access tier (GUEST=0, USER=1, ADMIN=2, ROOT=3):
- **Help filtering** — `help` only shows commands the current user can actually run
- **Execution guards** — restricted commands return "Permission denied" instead of running
- Guarded commands include: `verify`, `log`, `flash`, `reboot`, `shutdown`, `service`, `cron`, `component`, `rsh`, `scp`, `useradd`, `userdel`, `usermod`, `deploy`
- File operations (`mkdir`, `touch`, `cp`, `mv`, `rm`) require USER tier or above

### Install Disk Creator (`deploy`)
The `deploy` command (root only) creates a self-contained TOS install disk:
```
deploy /mnt/floppy
```
- Copies all system files + BIOS + installer to the target disk
- Includes `install.lua` — the unified installer that runs on any OpenOS machine
- The installer auto-detects the install disk, creates the full directory structure, copies all files, and offers to flash the TOS BIOS to EEPROM
- On the target machine: insert the disk and run `/mnt/<disk>/install.lua`

### OpenOS Compatibility Layer
TOS now runs OpenOS programs natively (including OPPM). A full compatibility shim layer registers under OpenOS module names in `package.loaded`, so `require("term")`, `require("filesystem")`, `require("event")`, etc. all transparently resolve to TOS implementations.

Supported shims: `sides`, `colors`, `keyboard`, `text`, `serialization`, `buffer`, `term`, `filesystem`, `event`, `shell`, `io`

### Shell Pipes & Redirects
The command executor now supports Unix-style piping and redirection:
```
ls /tos | grep kernel           -- pipe output between commands
cat /etc/hostname > /tmp/h.txt  -- redirect to file
echo hello >> /tmp/log.txt      -- append to file
```

### Environment Variables
Per-process environment variables with inheritance. System defaults include `PATH`, `HOME`, `SHELL`, `TERM`, `TOS_VERSION`.
```
env                     -- list all variables
env PATH=/usr/bin       -- set a variable
env HOME                -- read a variable
```

### Startup Services (`/etc/rc.d/`)
Scripts placed in `/etc/rc.d/` run automatically on boot. Scripts that return `{start, stop}` tables become manageable services.
```
service                 -- list all services
service start myservice -- start a service
service stop myservice  -- stop a service
```

### Cron Scheduler
Persistent scheduled tasks with configurable intervals, stored in `/etc/cron.dat`.
```
cron list                           -- show all jobs
cron add cleanup 300 os.execute("rm /tmp/*")  -- every 5 min
cron rm 1                           -- remove job #1
```

### Module System & Disk Manager
Install optional programs from floppy disks or other removable media. Modules are self-contained packages with a `module.cfg` manifest.

**Module types**: `command` (registers shell commands), `service` (start/stop lifecycle), `library` (require()-able)

```
mod                             -- list installed modules
mod info <name>                 -- show module details
mod enable <name>               -- activate a module (ADMIN+)
mod disable <name>              -- deactivate a module (ADMIN+)
mod uninstall <name>            -- remove a module (ADMIN+)
mod commands                    -- list commands from modules
```

**Disk manager** auto-detects module disks on insert:
```
disk                            -- list mounted removable disks
disk info <mount>               -- show disk contents (module/TOS/data)
disk install <mount>            -- install module from disk (ADMIN+)
disk export <name> <mount>      -- write module to blank disk (ADMIN+)
disk eject <mount>              -- unmount a disk
```

**Module manifest** (`module.cfg`):
```lua
return {
  name = "example",
  version = "1.0.0",
  description = "Short description",
  author = "PlayerName",
  type = "command",
  commands = { "example" },
  files = { "example.lua" },
}
```

Modules installed under `/usr/modules/`. Enabled modules persist across reboots. Module commands are available in the shell alongside built-in commands.

### Peripheral Control
Direct shell commands for hardware interaction:
- **Redstone** — `redstone` / `rs`: read all sides, `set <side> <0-15>`, `pulse <side> [duration]`
- **Robot** — `robot <forward|back|up|down|left|right|swing|use|detect|inv>`
- **Inventory** — `inventory [side]` / `inv`: inspect inventory controller or transposer contents
- **Component** — `component list`, `component gpu getDepth`: call any OC component method interactively

### Networking Expansion
Built on top of the existing zero-trust network stack:
- **Chat** (`chat`) — real-time TUI messaging between trusted peers with timestamps, target addressing, and encryption
- **Remote Shell** (`rsh <addr> <command>`) — execute Lua code on a trusted peer in a sandboxed environment with captured output
- **File Transfer** (`scp <addr>:<path> <local>`) — download files from trusted peers (6KB limit per transfer, path traversal protection)
- **Multi-Screen** (`screen list|next|N`) — manage multiple GPU+Screen pairs, switch active display

### Editor Enhancements
- **Undo** (`Ctrl+Z`) — snapshot-based undo stack (32 deep) for structural edits
- **Find & Replace** (`Ctrl+H`) — replace all occurrences in the current file
- **Cross-tab Clipboard** — `Ctrl+C` copy, `Ctrl+X` cut, `Ctrl+V` paste lines across editor tabs
- **PATH-based program resolution** — commands not in the built-in table are searched in PATH directories

## System Requirements

| Tier | RAM | Experience |
|------|-----|-----------|
| Minimum | T1 (192KB) | Degraded: minimal auth + emergency shell |
| Recommended | T1.5+ (256KB) | Full: login, CLI shell, panels, multitasking |
| Optimal | T2+ (512KB+) | All modules + compat layer + generous headroom |

- **GPU**: Tier 1 (monochrome), Tier 2 (16-color), Tier 3 (256-color) — auto-detected
- **CPU**: Tier 1+ (Lua 5.3)
- **Disk**: 100KB free minimum

## GPU Tier Support

TOS detects your GPU tier and applies an appropriate color palette:

- **Tier 1 (monochrome)**: Black background, white text, inverse for bars and selections
- **Tier 2 (16-color)**: Exact Minecraft dye palette values to avoid nearest-neighbor surprises
- **Tier 3 (256-color)**: Full RGB palette with distinct colors for all UI elements

All UI code references the theme system (`display.c("name")`) rather than hardcoded hex values, so every screen looks correct on any GPU.

## Features

### Multitasking & Multi-Seat
- Cooperative multitasking via coroutine-based process scheduler
- Keyboard/mouse signals route to foreground process only
- Background processes (TSR) keep running during user interaction
- **Multi-seat**: each GPU+Screen pair gets its own independent shell session
- **Ctrl+T** to cycle between running tasks
- `ps` shows all running processes with CPU time
- `kill <pid>` and `fg <pid>` for process management

### Security (always active, all boot paths)
- Password required on ALL boot paths — removing RAM sticks does NOT bypass login
- SHA-256 (data card) or DJB2+FNV1a dual-hash passwords
- 4-tier access: ROOT / ADMIN / USER / GUEST
- **Role-based command visibility** — help text and command execution filtered by tier
- Account lockout after failed attempts + anti-brute-force delays
- First-boot password change enforced + first-boot tutorial walkthrough
- Emergency shell also requires authentication

### Shell
- Theme-aware prompt: `user@host:/path$`
- Formatted `ls` with tier-correct colors for file types
- RAM usage bar, status bar, F-key bar
- Command history (up/down arrows)
- Pipe (`|`), redirect (`>`), and append (`>>`) support
- PATH-based external program resolution
- Per-process environment variables
- F1 Help, F2 Panels, F5 Clear, Ctrl+T Task Switch, F10 Quit

### Tab-Based File Browser (F2 or `panels`)
- Norton Commander-inspired single-panel navigation with tab multitasking
- Runs as its own process — Ctrl+T switches back to shell
- Tab bar with memory info, menu bar (File | Tools | System | Settings)
- Enter to navigate, Backspace to go up, F3 View, F5 Copy, F6 Move, F7 Mkdir, F8 Delete
- Built-in text editor with undo, find/replace, clipboard, and syntax coloring
- Context menus for files and directories

### Networking (Zero-Trust)
- 4-tier trust: BLOCKED / UNKNOWN / KNOWN / TRUSTED
- Encrypted comms (AES with data card, XOR software fallback)
- Challenge-response anti-spoofing for trusted connections
- Network discovery and peer hostname exchange
- Secure messaging with acknowledgment
- File transfer between trusted peers (`scp`)
- Remote command execution in a sandbox (`rsh`)
- Real-time chat TUI (`chat`)

### OpenOS Compatibility
- Full shim layer for 11 OpenOS standard libraries
- OPPM and other OpenOS programs run natively on TOS
- `require("term")`, `require("filesystem")`, `require("event")`, etc. all work
- `_G.io` global set for standard Lua I/O compatibility
- Loaded conditionally — skipped on low-RAM systems to save memory

### Peripheral Integration
- Redstone I/O (vanilla + bundled cable support)
- Robot/drone movement, interaction, and inventory
- Inventory controller and transposer inspection
- Generic component method caller for any OC component

### Services & Scheduling
- `/etc/rc.d/` startup scripts with start/stop lifecycle
- Cron-like job scheduler with persistent storage
- Multi-screen GPU+Screen binding and runtime switching

## Installation

### From Source
1. Run `install.lua` from OpenOS for guided setup
2. Flash `bios.lua` to EEPROM: `flash bios.lua "TOS BIOS"`
3. Reboot — login as `root` / `root`, set new password on first boot

### From Install Disk
1. On an existing TOS machine: `deploy /mnt/floppy` (root only)
2. Move the floppy to the target OpenOS computer
3. Run `/mnt/<disk>/install.lua` — the installer copies all files, runs setup, and offers to flash the BIOS
4. Reboot — first-boot tutorial guides you through the system

## Shell Commands

### Files & Navigation
```
ls [path]    cd <path>    pwd    mkdir <path>    rm <path>
cp <src> <dst>    mv <src> <dst>    cat <file>    edit <file>
touch <file>    df    du [path]    find <pattern>    grep <pat> <file>
head <file>    wc <file>    flash <file>    programs    history
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

### Modules & Disks
```
mod [list|info|enable|disable|uninstall|commands] [name]
disk [list|info|install|export|eject] [args]
```

### Environment & Services
```
env [KEY=VAL]    service [start|stop <name>]    cron [list|add|rm]
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
net    ping <addr>    hostname [name]    device    config    battery
chat    rsh <addr> <cmd>    scp <addr>:<path> <local>    screen [list|next|N]
```

### Editor Keybindings
```
Ctrl+S  Save       Ctrl+Q  Close tab     Ctrl+F  Find
Ctrl+H  Replace    Ctrl+Z  Undo          Ctrl+G  Go to line
Ctrl+C  Copy line  Ctrl+X  Cut line      Ctrl+V  Paste
```

## File Structure (77 files, ~20,700 lines)

```
bios.lua                          BIOS (4KB EEPROM)
init.lua                          Boot loader + require() system
install.lua                       Interactive installer

tos/kernel/
  init.lua                        Kernel orchestrator (boot, login, shutdown)
  hal.lua                         Hardware abstraction layer
  event.lua                       Event system (listeners, timers, intervals)
  process.lua                     Cooperative process scheduler
  fs.lua                          Virtual filesystem (mount, normalize, R/W)
  display.lua                     TUI engine (tier-aware themes, drawing)
  log.lua                         Rotating file logger
  crypto.lua                      Crypto (AES/data card + software fallback)
  users.lua                       Multi-user auth (hash, lockout, roles)
  securefs.lua                    Filesystem ACLs
  sandbox.lua                     Capability-based program sandbox
  config.lua                      System configuration store
  power.lua                       Battery monitoring (tablets)
  serialize.lua                   Shared serialization (encode/decode/compact)
  env.lua                         Per-process environment variables
  pipe.lua                        Shell pipe/redirect parsing & streams
  rc.lua                          /etc/rc.d/ startup service manager
  cron.lua                        Scheduled task executor
  screen.lua                      Multi-screen GPU+Screen manager + displayProxy
  modules.lua                     User module install/enable/disable manager
  audio.lua                       Audio feedback (beep codes, volume control)

tos/kernel/net/
  init.lua                        Network stack (zero-trust, send/recv/dispatch)
  protocol.lua                    Packet format & message type definitions
  trust.lua                       Trust manager (4-tier, challenge-response)
  transfer.lua                    File transfer (FILE_REQ/FILE_RES)
  remote.lua                      Remote shell execution (sandboxed)

tos/compat/
  init.lua                        OpenOS compatibility layer loader
  sides.lua                       Side name/number constants
  colors.lua                      Minecraft color constants
  keyboard.lua                    Key scan code constants + helpers
  text.lua                        Text utilities (trim, wrap, pad, tokenize)
  serialization.lua               Wraps kernel.serialize for OpenOS API
  buffer.lua                      Buffered stream wrapper
  term.lua                        Terminal API (cursor, read, write)
  filesystem.lua                  Wraps kernel.fs for OpenOS API
  event.lua                       Wraps kernel.event for OpenOS API
  shell_api.lua                   Shell path resolution & execution
  io.lua                          Standard Lua io library replacement

tos/peripheral/
  redstone.lua                    Redstone I/O (vanilla + bundled)
  robot.lua                       Robot/drone movement & interaction
  inventory.lua                   Inventory controller / transposer

tos/shell/
  init.lua                        CLI shell (fallback)
  login.lua                       Login screen
  panels.lua                      Forwarding shim -> panels/init.lua
  ext.lua                         Extended commands (net, ping, etc.)
  syntax.lua                      Syntax highlighting definitions
  chat.lua                        Peer-to-peer chat TUI
  tutorial.lua                    First-boot role-aware tutorial

tos/shell/panels/
  init.lua                        Orchestrator — wires submodules together
  state.lua                       Shared state table for all panels
  helpers.lua                     Path, file, text, permission helpers
  tabs.lua                        Tab create/close/cycle/find
  widgets.lua                     Syntax highlighting + status bar widgets
  dialogs.lua                     Inline input prompts + search dialogs
  draw.lua                        All TUI rendering (tabs, menus, file list, editor)
  filebrowser.lua                 Navigate, copy, move, delete, rename, mkdir
  editor.lua                      View/edit tab opening
  context.lua                     Right-click context menu
  commands.lua                    ~50 built-in shell commands
  executor.lua                    Command executor + pipe/redirect handler
  menus.lua                       Menu bar action handler
  events.lua                      Main event loop + signal dispatch
  keymap.lua                      OC scancode table
```

## Boot Sequence

1. **BIOS** — minimal EEPROM: finds boot disk, loads `/init.lua`
2. **Stage 0** — locate boot filesystem (TOS BIOS pass-through or scan)
3. **Stage 1** — build `require()` system, register `package.loaded`
4. **Stage 2** — GPU + early display for boot messages
5. **Stage 3** — system integrity check (optional, validates all files)
6. **Kernel boot** (13 stages):
   - Core modules (log, HAL, filesystem, config, events, processes, display)
   - Power monitoring (tablets)
   - Security subsystem (crypto, users, securefs)
   - Network stack + file transfer + remote shell handlers
   - Startup services (`/etc/rc.d/`) and cron scheduler
   - OpenOS compatibility layer
7. **Login** — full login screen or minimal auth (low RAM fallback)
8. **First-boot tutorial** — role-filtered walkthrough (auto-skipped after first run)
9. **Shell** — panels TUI or CLI shell depending on available memory

## License

GNU GPL v3.0 — Discover! Interactive
