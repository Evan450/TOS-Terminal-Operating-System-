# The TOS Operator's Guide & Reference

*The Book of TOS — for Terminal Operating System v1.4.0 "Iris"*

---

This is the comprehensive reference for operating a TOS machine. It is meant to
sit beside you (not inside the OS) the way the *MS-DOS User's Guide and
Reference* once did — read a chapter when you want depth, or jump to a section
a `help` command pointed you at.

**`help` vs. this Manual.** Inside TOS, `help` (and `help <command>`) gets you
moving fast and shows only what's installed on *your* machine. This Manual is
for digging deeper: the *why*, the full option lists, examples, and the design.
(Unix-minded operators: `help` is to this Manual roughly as a usage line is to
a `man` page — and yes, "man" is short for "manual".)

## How this Manual is organized

Like the old *MS-DOS User's Guide and Reference*, this Manual is two books bound as one:

- **Book One — The Operator's Guide.** Tutorial chapters that teach TOS by
  doing: booting and logging in, navigating the filesystem, managing files,
  configuring the system, writing Lua scripts, and setting up hardware. Read it
  front to back the first time; it assumes nothing.
- **Book Two — The Reference.** Look-up material: a complete **alphabetical
  command reference** — every command, built-in or installed, with its syntax,
  options, examples, and error messages — plus the security model, the
  configuration files, recovery procedures, and appendices.

There are three depths of help, shallowest to deepest:

1. **`help`** — a one-line, install-aware reminder of what each command does.
2. **`man <topic>`** — a focused manual page (synopsis, options, examples) for a
   single command or concept, read inside TOS.
3. **This Manual** — the long-form explanation and the exhaustive reference.

Page/section numbers are stable (`Chapter.Section`), so a `(Manual 6.3)` flag in
`help` — or a `MANUAL.md (Chapter 7)` line in a man page — always points to the
same place.

---

# BOOK ONE — THE OPERATOR'S GUIDE

*Tutorial chapters. Work through them in order the first time; each builds on the
last.*

# Part I — Getting Started

## 1. What TOS Is

TOS is a Norton-Commander-inspired operating system for OpenComputers
(Minecraft). Its defining traits:

- **Security-first, always on.** A password is required on *every* boot path -
  pulling RAM sticks or using the emergency shell does not bypass login. A
  capability **sandbox** confines user programs, and **securefs** mediates every
  user-level filesystem operation against per-user ACLs.
- **Zero-trust networking.** Every machine starts as `UNKNOWN`; elevated trust
  requires a deliberate local admin action. Sensitive traffic between `TRUSTED`
  peers is encrypted and MAC-authenticated with replay protection.
- **Modular, configurable kernel.** Boot is a spectrum from "nothing" to
  "everything" (Chapter 2). Optional subsystems load by profile + available RAM.
- **Multi-seat.** Each GPU+Screen pair is an independent shell session with its
  own login and foreground. It works best when operators take **turns**, not
  when they work at the same instant — one computer has one CPU, and
  simultaneous users share it (see the note below).

> **Multi-seat is sequential-friendly, not simultaneous-friendly.** OpenComputers
> gives a computer a single CPU: one Lua execution stream and one per-tick call
> budget shared by every seat. So two operators working at the same moment each
> run slower, and a heavy command on one seat (`cp`, `find`, `pkg install`,
> `drive defrag`) briefly slows the others. TOS softens this — long commands
> cooperatively yield so a busy seat *slows* rather than *freezes* the rest, and
> the System Monitor (Ctrl+T) runs as a per-seat tab rather than pausing the
> whole box — but the shared-CPU ceiling is a limit of the mod, not something an
> OS can remove. **Prefer sequential operator use; for truly concurrent work,
> give each person their own computer.** A higher-tier CPU raises the shared
> budget but never makes it per-seat.

**Tiers of hardware** matter. TOS auto-detects GPU tier (1 monochrome / 2
sixteen-color / 3 full RGB), RAM tier, and the data-card tier (which decides
whether you get hardware SHA-256/AES or a software fallback). See the **System
Configuration screen** (2.2) for what your machine has.

## 2. Booting

Boot is two buckets: **B1**, the EEPROM BIOS (tiny, ~4 KiB), and **B2**, the
main `init.lua` + kernel. B1 finds the boot disk, runs power-on self-tests, and
hands off to B2.

### 2.1 The boot spectrum (`/etc/boot.cfg`)

TOS reads `/etc/boot.cfg` very early. A missing or corrupt file is safe — it
falls back to the `normal` profile. Two independent dials:

- **`profile`** — *what loads*:
  - `minimal` — bare shell; every optional subsystem skipped (a tight box's
    everyday profile).
  - `normal` — the default; optional subsystems load if RAM allows (TOS's
    classic behavior).
  - `full` — load every available subsystem (RAM permitting).
  - `diagnostic` — `full` + the integrity check + a verbose boot log.
  - `safe` — **Safe Mode**: kernel + shell only. No rc.d services, no cron
    jobs, no package commands, no net, no themes — nothing third-party runs.
    The `pkg` admin verbs (list/info/install/uninstall/enable/disable) still
    work, so this is the boot for "I installed something and now the machine
    misbehaves": boot safe, remove the culprit, set the profile back, reboot.
    Safe Mode boots loud on purpose (a SAFE MODE banner + text log). You can
    also press **S** at the POST screen for a **one-time** safe boot that
    touches no config at all (2.3).
- **`verbosity`** ("the muter") — *what the boot LOG says*, never *what TOS
  does*: `silent` (no boot-log lines), `splash` (logo + bar), `text` (per-stage
  lines, the default), `verbose` (every line stamped with `[NNNNms]`
  ms-since-boot timings). For operators who prefer a clean startup screen over
  scrolling debug text. Note: verbosity governs only the boot log — it does
  **not** hide the System Configuration screen; that is `showConfig`'s job (see
  2.2), so a `silent` boot can still reach Boot Settings.
- **`ui`** — the startup *interface* for every seat: `panels` (the full TUI,
  default) or `cli` (boot straight to the command line — the lightest possible
  startup, and no loss of capability: the CLI runs the same commands and loads
  them as you use them. `tui` opens the panels interface on demand, so it is a
  default and never a lockout).
- **`repair`** — **one-shot self-repair**: set it (Boot Settings → "Self-repair
  next boot", or `bootsettings repair on`) and the next boot runs a repair pass
  right after the filesystem comes up, then clears the flag — even a crashing
  repair can't loop. It **fixes** what is mechanically safe (finishes
  interrupted atomic writes, removes orphaned temp files, clears stale
  `/var/run` state, trims oversized logs, rewrites a corrupt `boot.cfg`) and
  only **reports** what isn't (a corrupt `users.dat` or missing critical file
  is a warning — the wrong auto-fix there could lock every operator out).

`advanced` per-feature toggles (`net`/`swap`/`power`/`theme`/`compat`/`audio`/
`integrityCheck`/`jbod`/`services`/`cron`/`packages`) override the profile when
you want one thing on or off without leaving your profile — e.g. Safe Mode plus
`net on` for a remote-rescue session. (`jbod` — disk pooling, Chapter 5.3 — is
the one feature that stays *off* in every profile; it loads only via this
toggle.)

**Telling TOS what it has.** Detection is trusted where it's reliable (GPU,
screen, modem — no overrides offered, on purpose) and overridable where it
isn't: `cpuTier` and `dataTier` pin/correct tiers the heuristics can misjudge,
and `ramGate` declares your memory situation for the optional boot stages —
`auto` measures free RAM (default), `plenty` forces the extras to load, `tight`
makes TOS behave like a low-memory box. `showConfig` toggles the POST screen.

### 2.2 The System Configuration screen (POST)

Each boot with `showConfig` on (the default) briefly shows a TOS-ified
BIOS-style screen: your installed hardware, **with tiers** — Processor
(architecture + tier, detected, estimated from RAM, or operator-confirmed),
Memory, Graphics (GPU tier/depth/resolution), Crypto (the data card's
capability tier — `detected`, operator-confirmed `*`, or `tier ? - set in boot
settings` when it can't be probed), Network, Storage (each drive's tier),
EEPROM, and attached Peripherals. It is grouped **System** (what's *in* the
computer) / **Storage** (drives) / **Peripherals** (external blocks).

This screen — and the **DEL → Boot Settings** entry point on it — is gated by
`showConfig` alone, independent of verbosity. A `silent` boot still shows it
(so you can always recover settings); to suppress it as well, turn `showConfig`
off. If TOS can't read your data card's tier (some OC builds/emulators report a
bare `data` proxy), set it manually with `dataTier` (2.3), exactly like the CPU
tier — the POST line then shows your confirmed tier with a `*`.

### 2.3 Boot Settings (press DEL) & one-time Safe Mode (press S)

While the POST screen shows `Press DEL for Boot Settings, S for Safe Mode
(once)...`:

- **Delete** opens the visual editor: arrow keys to select, Left/Right (or
  Space) to change a value, **S** to save, **R** to save and reboot, **A** to
  reveal the advanced overrides, **H** to view hardware, **Q** to cancel.
- **S** boots **Safe Mode for this session only** — services, cron, packages,
  net, and themes stay off, but `/etc/boot.cfg` is untouched and the next boot
  is completely normal. This is the fastest way to a trustworthy shell after
  installing something that breaks boot: no config edit required first.

Missed the window? Run `bootsettings` from the shell — it's a CLI editor
(`bootsettings show`, `bootsettings profile safe`, `bootsettings verbosity
verbose`, `bootsettings ui cli`, `bootsettings repair on`, `bootsettings
cputier 2`, `bootsettings datatier 3`, `bootsettings ramgate tight`,
`bootsettings net off`, `bootsettings reset`). Both write `/etc/boot.cfg`;
changes apply on the next boot.

### 2.4 Fallback boot & one-time boot (security)

If the recorded boot drive is gone or has changed, the BIOS does **not** silently
adopt a new disk (that was a floppy-bootkit lever). It prompts: **Y** updates the
EEPROM permanently, **Shift+Enter** boots once without touching the EEPROM (a
"one-time boot" — shown on the splash, and it suppresses the floppy→HDD migration
offer), any other key or the 30s timeout halts. The same prompt guards **raw
TBFS boot drives** (Chapter 5.4): the BIOS scans managed filesystems first, then
raw drives, and a discovered boot volume of either kind needs this approval.

## 3. Logging In, Users & Tiers

### 3.1 Tiers

| Tier  | Name  | Can do |
|-------|-------|--------|
| 0 | GUEST | read `/public`, no writes |
| 1 | USER  | own home + `/public` + `/tmp` read/write |
| 2 | ADMIN | manage users, system config, mounts, packages |
| 3 | ROOT  | full system access (single rescue account) |

### 3.2 First boot

Log in as `root` / `root`. TOS forces a password change on first boot — the
session is minted at GUEST tier with a *password-change-only* token until you
set a real password, so the default password can't be used to do anything else.
A role-aware tutorial then walks you through the basics.

### 3.3 Passwords, lockout & backoff

Passwords are salted and stretched (SHA-256 via the data card, or a software
KDF). The user DB (`/etc/users.dat`) is admin-readable only and stores no
plaintext. After repeated failures an account auto-locks (except the `root`
rescue account); an **exponential login backoff** applies to *every* account and
survives reboots (so even `root` can't be brute-forced quickly). Login never
reveals whether a username exists or is locked — wrong credentials always get the
same generic error.

Commands: `passwd` (change your own), and (admin) `useradd`, `userdel`,
`usermod <user> lock|unlock|admin|user`, `users`.

---

# Part II — Using TOS

## 4. The Shell

TOS has **two interfaces and one command set**. The **panels** TUI is the
default; the **CLI** is a plain scrolling prompt. They dispatch through the same
command registry, so every command works in both — including pipes, redirects,
quoting, `sudo`, and commands added by installed packages.

Move between them whenever you like:

| From | To the CLI | To the TUI |
|---|---|---|
| a prompt or command line | `cli` | `tui` |
| the quit menu (**F10** or **Ctrl+Q**) | `[4] CLI Mode` | — |
| at boot, for every seat | Boot Settings → Interface → `cli` | → `home` (or `split`) |

The CLI loads command groups **as you use them**, so a session that only touches
files never parses the admin or extras command files at all. That makes it the
lightest way to run TOS, which is why it is also what a seat falls back to if the
panels interface cannot load.

**What the CLI genuinely cannot do** is the handful of things that *are* the
panels interface rather than commands: the tabbed viewer and editor, the Desktop,
and live-refreshing tabs. Ask for one at the prompt and it will say so and tell
you what to type instead (`watch` covers live refresh; `tui` then `edit` covers
the editor). Everything else is the same program.

> Below the CLI there is one more layer you will hopefully never see: the
> **emergency terminal**, which the kernel runs when no shell could start. It has
> seven commands and depends on nothing the other two need — that is the point of
> it. See §9.3.

### 4.1 Layout & keys

Panels opens on **Home**: one tab with two views. The tile grid and the file
list are two ways of looking at the same tab, and **F2 flips between them**.
The bottom four rows — summary rail, output, command prompt, status bar — are
identical in both, so the prompt is never somewhere else and a command's output
lands where the last one did. The status bar carries a `View:` widget saying
which half you are looking at.

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| F1  | Help | F2 | **Flip the view: tiles / files** |
| F3  | View file | F5 | Copy |
| F6  | Move/rename | F7 | Mkdir |
| F8  | Delete | F10 | Quit |
| Tab | Next tab (on an empty command line) | PgUp/PgDn | Page the tiles / the list |
| Alt+1-9 | Quick-launch a tile on this page | Ctrl+P / Ctrl+N | Command history |
| Shift+arrows | Select text | Ctrl+Insert | Copy the selection |
| Shift+Insert / ^V | Paste | Shift+Delete / ^X | Cut |
| Ctrl+T | System Monitor | Ctrl+C | Interrupt foreground |

F2 is the `view` action in `/tos/shell/keys.lua`, so it is rebindable like any
other — see [§4.1d](#41d-one-set-of-shortcuts-and-theyre-yours). Every legend
that names it reads the live binding, so a rebind re-labels the screen too.

**Anything printable goes to the prompt.** That is what a CLI-first machine
owes you, and it is why two bindings moved when Home merged: quick-launch is
`Alt+1-9` (a bare `1` types a `1`), and command history is `Ctrl+P` / `Ctrl+N`
(the arrows drive the selection in whichever view is up, with no focus mode to
learn). Tab still completes when there is something on the line to complete;
on an empty line it moves to the next tab.

The file-operation keys — F3, F5, F6, F7, F8 — act on the file list, so they
are live only in the files view. F8 will not delete something you cannot see.

**F10 / Ctrl+Q** opens the quit prompt: `[1] Reboot · [2] Shut down ·
[3] Log out · [4] CLI Mode · [Ctrl+Q] Cancel`. CLI Mode hands this seat to the
command line without ending your session — `tui` brings the panels back.

The CLI's own keys are the ordinary line-editing ones: **↑/↓** history,
**←/→ Home/End** to move within the line, **Tab** to complete a command name or
path, **Ctrl+Q** to clear the line.

### 4.1b Esc belongs to Minecraft, not to TOS

**Don't press Esc expecting a program to quit.** Esc is the game's key: it
closes the screen GUI, so you step away from the terminal and the keypress never
reaches the computer. The program is still running when you open the screen
again.

Everything in TOS follows one convention instead:

| To do this | Press |
|---|---|
| Quit a full-screen program | **Q** — or **Ctrl+Q** where Q would be typed (the editor, `write`, `calc`) |
| Cancel a prompt or a dialog | **Ctrl+Q** |
| Quit, anywhere, always | **F10** |

Esc is still *accepted* wherever it does no harm, in case a future
OpenComputers build or an emulator delivers it — but nothing in TOS requires it,
and no help text will tell you to press it. If you find one that does, it's a
bug: `usr/lib/tests/test_no_esc_exit.lua` exists to catch exactly that.

### 4.1d One set of shortcuts, and they're yours

Every program TOS ships reads the **same** keybind table, so the combination
that closes one closes all of them:

| Action | Default | Means |
|---|---|---|
| `quit` | **^Q**, F10 | Close the current program, prompt or dialog |
| `help` | **F1** | Show the program's help |
| `save` | **^S** | Save |
| `find` | **/** | Filter or search within a list |
| `refresh` | **^R** | Re-read and redraw |
| `view` | **F2** | Switch the view (on Home: tiles ⇄ files) |
| `copy` | **Ctrl+Insert** | Copy the selection |
| `cut` | **Shift+Delete**, ^X | Cut the selection |
| `paste` | **Shift+Insert**, ^V | Paste the clipboard |

`view` is the sixth and newest action. It arrived with the merged Home
surface, and it is here rather than hard-wired into the shell for the reason
this table exists at all: "flip to the other view" is something an operator
will want to rebind, and one rebind should re-label every screen that mentions
it. It does.

```bash
keys list                # the table, and which entries you've changed
keys set view F12        # give the view flip a different key
keys set quit F4         # rebind one
keys set find ^F
keys reset quit          # back to the default
keys reset               # all of them
```

**Copy is `Ctrl+Insert`, not `Ctrl+C`, and that is not a style choice.** The
kernel takes `Ctrl+C` to interrupt whatever is running and *blanks the signal* —
it never reaches a program at all, which is why the editor's old
"Ctrl+C = copy line" help line had never once worked. DOS and Norton Commander
landed on `Ctrl+Insert` / `Shift+Insert` / `Shift+Delete` for exactly the same
reason, a decade before `^C`/`^X`/`^V` existed. `^X` and `^V` are free, so they
work too. `keys set copy ^C` is refused with the reason.

Add **`--system`** to change them for every user (`/etc/keys.cfg`, admin);
without it they're yours alone in `~/.keys.cfg`. Keys are written the way you'd
say them — `^Q`, `Ctrl+S`, `F10`, `/` — never scancodes.

A rebind **replaces** rather than adds, so `keys set quit F4` means *only* F4;
otherwise you could never take a binding away. Give several to keep several:
`keys set quit ^Q F10 F4`.

**Three chords belong to the kernel** and can't be rebound, because it consumes
them before any program sees them — accepting a rebind would write a setting
that silently does nothing:

| `^B` | background the current program |
| `^T` | switch tasks / open the Monitor |
| `^C` | interrupt the foreground program |

Some programs keep an older key alongside the standard — `ttt` and `snake` still
quit on plain **Q** — because taking away muscle memory buys nothing. What
changed is which one they *advertise*, and their footers read the live binding,
so they can't tell you a key that isn't bound any more.

**This is a convention, not a cage.** A third-party package can bind whatever it
likes and nothing stops it. What being consistent buys is that TOS's own
programs feel like one system.

### 4.1c The menu bar is yours

The bar across the top is a **default, not a fixture**. `menu show` prints it as
it currently stands; everything else edits it.

```bash
menu show                        # the bar as it is right now
menu add Tetris tetris in Tools  # put a command in a drop-down
menu hide "Flash EEPROM"         # hide a built-in entry
menu hide Help menu              # hide a whole top-level menu
menu rename Tools Utilities      # rename a menu, or an item
menu move Desktop Tools          # move an item between menus
menu list                        # your edits, numbered
menu remove 2                    # undo one of them
menu reset                       # back to the built-in bar
```

Add **`--system`** to any of those and the change lands in `/etc/menu.cfg` — the
machine's bar, seen by every user, admin-only. Without it, changes are yours
alone in `~/.menu.cfg`. A user edit is applied *after* the system one, so you can
hide something the machine added.

**It is an edit list, not a replacement bar,** and that is deliberate: a saved
copy of the whole bar goes stale the moment TOS gains a command. Your edits ride
on top of whatever the built-ins become, so an upgrade brings you the new entries
and keeps your changes.

A malformed config never costs you the menu bar — bad entries are skipped, and an
edit list that somehow removes everything falls back to the built-ins. The bar is
the surface you'd use to fix a broken bar, so it doesn't get to break.

### 4.1a Two ways to say something

TOS can put words on screen in two places, and the difference is the point.

The **output area**, above the command line, is *polite*. It waits there until
you next look down. That's right for results — a listing, an answer, a warning
about something you just did. `echo` writes there.

A **dialog box** is not polite. It's the DOS-style modal — double-line frame,
`╡ title ╞` tab, drop shadow, buttons you have to answer — centred over
whatever you were doing, blocking until you deal with it. That's right for
things you cannot be allowed to miss.

```
echo   "backup finished"      you'll see it when you look
notify "backup finished"      it's in your face, on every seat
```

Dialogs were originally reserved for dangerous or important *actions* —
"are you sure", install confirmations. They're now a facility **any program
can reach**: `kernel.notify`. A background service, an add-on's network
handler, a sandboxed package command — none of them can draw (another process
may own the screen), so they *post* a notice and the shell that owns the
display raises the box on its next idle tick. The Intercom rides this: an
announcement at `alert` or above becomes a dialog on every listening machine
(§8.5). A package asks for the `notify` capability to do the same.

**The rate limits are what make that safe.** A modal any program can raise is
a way to lock you out of your own computer — by accident, from a service stuck
in a retry loop, as much as on purpose. So the facility enforces a floor
nobody can opt out of: at least 10s between notices from the same source, at
least 3s of quiet after *any* dialog is dismissed (you always get your keyboard
back), at most 8 waiting, and a 2-minute expiry so a notice raised while nobody
was looking can't ambush someone later. A refused notice is still written to
the log — it just doesn't get to interrupt. Programs layer their own policy on
top of this floor, never underneath it.

On a multi-seat machine every seat raises each notice once, and the first
operator to answer settles it for everybody.

*See also:* `man notify`.

### 4.1e Selecting text, and the clipboard

**Hold Shift and use the arrows.** It works at the command prompt, in the
editor, and — a line at a time — in any view buffer, which is where a command's
output goes. With the mouse add-on installed, click and drag does the same
thing. An arrow *without* Shift always drops the selection, so a selection
never outlives what you can see.

| | |
|---|---|
| `Ctrl+Insert` | Copy |
| `Shift+Delete` or `^X` | Cut |
| `Shift+Insert` or `^V` | Paste |

With **nothing** selected, copy and cut take the whole line — which is what the
editor's old line-clipboard did, so that muscle memory still works. At the
prompt with nothing selected *and* nothing typed, copy takes the **path of the
file under the cursor**, which is the short answer to "how do I get this path
onto the command line".

**One clipboard.** Text copied in the editor pastes at the prompt; a run of
output copied from a view buffer pastes into a file you are editing. It is
**per seat** — two people at two screens do not read each other's copies — and
it is **cleared at logout**, because a seat is a screen the next person walks
up to and what you copied is sometimes a password on its way to a prompt.
Switching to the CLI with `cli` is not a logout and keeps it.

It is bounded (512 lines / 16 KB) because it is RAM on a machine that considers
192 KB of free memory a good day. When a copy hits the cap it says so rather
than quietly holding less than you asked for.

Pasting multi-line text into the **single-line** prompt joins it with spaces and
tells you it did. Concatenating instead would turn two lines reading `ls` and
`cd /` into `lscd /` — a command you never typed and might well run.

```bash
clip                     # what is on the clipboard right now
clip set some text       # put text on it from a script
clip clear
```

**`F5` and `F6` in the file list are a different clipboard.** They mark and copy
*files*. Two verbs that share an English word; keeping them apart is deliberate,
because one "paste" that means two things depending on invisible state is worse
than two names.

### 4.2 The command line

Supports pipes (`cmd1 | cmd2`), redirect (`> file`), append (`>> file`), command
history (up/down), and per-process environment variables (`env`, `export KEY=VAL`).
Unqualified program names resolve only against system bin dirs (`/bin`,
`/usr/bin`, `/tos/shell`) and *safe* `PATH` entries — a disk under `/mnt` can't
shadow a system binary.

### 4.3 The editor

`edit <file>` — **ADMIN** — opens an editor tab with undo, find/replace, clipboard,
Lua syntax coloring. Ctrl+S save, Ctrl+Q close, Ctrl+F find, Ctrl+H replace, Ctrl+Z
undo.

### 4.4 The tiles view & the Settings app

The **tiles view** of Home (F2, or `desktop`, or System → Desktop) is a tile
home screen: the built-in apps (Monitor, Chat, Mail, Settings, Help, Tutorial,
Log Out, and Tape Menu when a tape drive is present) plus one tile per command
an installed package provides, and your personal `~/.launcher.cfg` entries.
Opening a tile runs the command through the normal executor — same tier gates,
same output, and the output lands on the same rows it would have if you had
typed it, without the tiles moving under your hand.

There is no *Files* tile: F2 is the way to the file list, and the legend two
rows under the grid says so. Arrows + Enter move and open, `Alt+1-9`
quick-launches by the numbers on the current page, PgUp/PgDn page. With the
mouse add-on you can click a tile, click the `‹ ›` markers on the band rail to
page, or click the `F2` legend itself. On a Tier-1 mono screen the grid becomes
a numbered list — the same model, degraded presentation, with the band rail
saying which page you are on.

More tiles than fit on a page are **paginated, not dropped**: the band rail
above the grid reads `‹ page 1/2 › · 27 tiles · 15 shown · PgDn next page`, so
the cap is never silent.

What login lands on is per-user: the `landing` profile field, which now picks a
*view* rather than a surface (`tiles` or `files`; the older `desktop` and
`shell` spellings still work and mean the same two things). Unset, root gets
files and everyone else tiles. Change it in **Settings → Home**.

**Want the old two-tab shape back?** Boot Settings → Interface has a `split`
setting: a Shell tab and a separate Desktop tab, with F2 cycling tabs the way
it did before. `home` is the default and everything above describes it.

The **Settings app** (`settings`, or Settings → Settings App) is four pages of
forms: **Appearance** (theme preset with live preview, then "Save as my
theme"), **Status Bar** (widget checkboxes, saved immediately), **Desktop**
(the landing choice), **System** (buttons for `bootsettings`, `users`,
`doctor`, `about`; admin buttons hidden below ADMIN tier). Tab switches page,
Left/Right changes a value, Enter applies.

## 5. Files & the Filesystem

### 5.1 Layout & permissions

`securefs` enforces per-user ACLs on every user-level op:

- `/public` — everyone reads; USER+ writes.
- `/home/<user>` — owner (or admin) only.
- `/root` — root only.
- `/tmp` — everyone read/write.
- `/tos`, `/etc`, `/var`, `/usr` — system; readable by users, writable by ADMIN+
  (and a protected core that even admins can't overwrite via securefs).

Paths are normalized first (`..`, `.`, backslashes, NUL bytes all handled -
tainted paths fail closed), so ACL checks can't be tricked.

### 5.2 Trash, vault & keychain

- **Trash:** `rm` moves files to per-user trash (use `--hard` to skip it);
  `trash` lists/empties/restores (`trash restore <name>` undeletes).
- **`vault`** — passphrase-based encryption of files, tapes, or in place.
- **`keychain`** — a per-user passphrase stash, unlocked with your login password.

### 5.3 Disk pooling (JBOD, opt-in)

When several small disks are more usefully seen as one, **JBOD** ("Just a Bunch
Of Disks") pools them into a single mount: capacity is the sum, a read searches
every member, and a write lands on whichever member already holds the file (or
the emptiest one). It is a union mount — not striping or parity — so losing one
member loses only *that* member's files, leaving the rest of the pool readable.
securefs still applies per-user ACLs to the mount.

JBOD is **off by default** (it reshapes the mount tree, so it's a deliberate
choice). Turn it on with `bootsettings jbod on` and reboot, then manage pools
with the `jbod` command (`jbod create /mnt/pool <disk> <disk>`, `jbod list`,
`jbod destroy /mnt/pool`). Pools persist in `/etc/jbod.cfg` and re-mount each
boot. See `man jbod`.

### 5.4 Unmanaged (raw) drives — TBFS

OpenComputers disks come in two flavours. A **managed** disk is a `filesystem`
component: the mod gives it a ready-made file API, and that's what TOS mounts
by default (every `disk`, `df`, and `/mnt` entry so far). An **unmanaged**
drive is a raw `drive` component — `readSector`/`writeSector` and nothing else,
no files, no directories, and (per the OC config) a simulated spinning-platter
seek penalty. It's the "build your own filesystem" disk.

TOS always **sees** unmanaged drives — `lsdev`, `hw`, and the System
Configuration screen show them as *Raw Drive* so they're never invisible — and
the base `drive` command inspects them (`drive list`, `drive info <addr>`,
`drive read <addr> <sector>`). To actually *store files* on one you install the
**`blockfs`** package (`pkg install blockfs`), which lays **TBFS** — a real
hierarchical filesystem — onto the bare sectors:

- `drive format <addr> [label]` — lay down a fresh TBFS (destroys all data).
- `drive mount <addr> [path]` — mount it at `/mnt/<label>`; from then on it
  behaves like any managed disk (browse, `cp`, securefs ACLs — all unmodified).
- `drive check <addr> [--repair]` — fsck: verify the block map and, with
  `--repair`, rebuild the free counts from what the files actually reference.
- `drive defrag <addr> [--if-over N]` — compact each file's blocks into
  contiguous runs so the simulated head stops seeking. No flag defragments
  now (manual); `--if-over 30` only acts when fragmentation reaches 30% (drop
  that in a `cron` job for automatic upkeep). `drive info` reports the current
  fragmentation, and `drive mount` warns when it's high.

TBFS scales a single file into the megabytes (direct + single- and
double-indirect block pointers) and allocates layout-aware to keep files
contiguous; fragmentation only creeps in as a full disk is churned, which is
what `defrag` is for.

**Installing TOS *onto* a raw drive.** `deploy drive <addr>` (root) formats the
drive as a **bootable** TBFS volume, copies the whole OS onto it, and writes a
self-contained stage-2 boot blob into a reserved boot region (the blob embeds
the TBFS driver, so the disk can read itself before any package loads). Because
TBFS lives in the `blockfs` package, `deploy drive` checks for it first and, if
it's missing, stops loudly and tells you to `pkg install blockfs` — it never
half-writes a disk.

**Booting from a raw drive.** The TOS BIOS understands TBFS boot volumes
natively: at power-on it tries the stored boot address first (managed disk *or*
raw drive), then scans managed filesystems, then raw drives. A discovered TBFS
drive gets the same security prompt as any changed boot disk — `Y` commits it
to the EEPROM, `Shift+Enter` boots it once, anything else halts. If the box
still runs an older EEPROM, reflash with `flash /bios.lua` first. A `deploy
drive` volume is also a complete, mountable TOS disk you can reach with
`drive mount` at any time.

## 6. Commands at a Glance

`help` shows the lean, install-aware list; this chapter is a quick **catalog by
category** so you can find the right command by what you're trying to do. For the
exhaustive per-command entry — syntax, every flag, examples, and error messages -
see the **alphabetical Command Reference in Book Two (Chapter 14)**. Commands are
tier-gated and hidden from `help` if their hardware/package isn't present.

### 6.1 Files & navigation
`ls` `cd` `pwd` `mkdir` `rm` `cp` `mv` `cat` `more` `touch` `df` `du`
`find` `grep` `head` `tail` `wc` `tree` `programs` `trash` `vault` `keychain`

### 6.1a Saying things
`echo` (polite, above the command line) `notify` (a dialog box in the
operator's face, every seat — see §4.1a)

### 6.2 System & session
`desktop` `settings` `mem` `hw` `ps` `monitor` (= `top`, live) `watch` `kill`
`fg` `bg` `about` `uptime` `date` (= `time`) `whoami` `passwd` `logout` `reboot`
`shutdown` `srm` `doctor` (= `diag`) `log` `verify` `menu`

(`srm` is the front door over `doctor` and `verify`, and the only command that
reports a POST fault the BIOS caught — see §9.3.)

### 6.3 Administration
`users` `useradd` `userdel` `usermod` `mount` `umount` `jbod` `flash` `lua` `run`
`edit` `bootsettings` `service` `cron` `deploy` `backup` `kiosk`

(`jbod` — disk pooling — appears only after you enable it with `bootsettings
jbod on`; see Chapter 5 and `man jbod`.)

### 6.4 Packages (see Chapter 7)
`pkg` (`list`/`search`/`info`/`install`/`uninstall`/`enable`/`disable`/`commands`/
`make-disk`); top-level `install` / `uninstall` shortcuts. With an internet card:
`pkg repo`, `pkg remote`, `pkg fetch` (§7.6) and `internet` for card status.

### 6.5 Network (see Chapter 8)
`net` (incl. `net servers`) `ping` `hostname` `config` `chat` `mail` (add-on)
`intercom` (add-on) `rsh` `scp` `screen`

### 6.6 Customization & resilience
`theme` (= `colors`) `lang` `optimize` `battery` `audio` `profile` `tutorial`
`alias` / `unalias` (per-user command shorthand)

### 6.6a Working out what a name means
`which` (what a command resolves to) `why` (why you were refused) `help` `man`

Three things can answer to one name — a built-in, an installed package's command,
and a program on the search path. `which` says which one wins.

### 6.7 Peripherals (see Chapter 11)
`redstone` (= `rs`) `robot` `inventory` (= `inv`) `component` `tape`
`printer` (add-on) `write` (add-on)

---

# Part III — Managing TOS

## 7. Packages

TOS uses one package manager, `pkg` (the legacy "module manager" was retired in
v1.3.1; the `mod` command has since been removed too — its `enable`/`disable`/
`commands` subcommands were folded into `pkg`).

### 7.1 Using pkg
- `pkg list` — installed packages.
- `pkg search` — what's installable in any repo or mounted disk.
- `pkg info <name>` — manifest details.
- `pkg install [arg]` — one smart verb. A **name** resolves dependencies and
  installs from any known source (OPPM-style, native, or a mounted disk),
  verifying SHA-256 hashes when a manifest declares them. A **path** (anything
  with a `/`) installs that single package directory. **No argument** opens the
  full-screen **Optional Utilities picker** — a checkbox menu grouped by
  category (Games, Network, …) where you tick what you want and install the set
  in one pass; add `--prompts` for the classic one-package-at-a-time `[y/N]`
  scan (or when there's no screen for the menu). Shortcuts: `install <name>` and
  `uninstall <name>` work at the top level, so you needn't know the manager is
  called `pkg`. (`install-dir`/`from-floppy` still work as hidden aliases.)
- `pkg make-disk <mount> [name…]` — build an **Optional Utilities disk** from
  your installed add-ons, in-TOS (parity with `deploy`, which builds a whole-OS
  image). Writes one package dir per add-on plus a self-contained picker
  `install.lua`, so you can carry your add-on set to another TOS machine with no
  dev box. Name args limit the export; omit to include every add-on. Targets
  removable media only (system paths are refused).
- `pkg uninstall <name>`.

Installing/uninstalling/enabling requires an **admin** session. Package writes are
confined to `/usr` and `/var/pkg`; a `kind="service"` package may additionally
install exactly one `/etc/rc.d/<f>.lua` and one `/etc/<name>.cfg` — nothing else
under `/etc`, and never `/tos` or `/init.lua`.

### 7.2 The Optional Utilities disk

The bundled add-ons (tetris, tape, rc-pilot, **mouse**, **printer**,
**write**, **stock**, the cluster
packages) ship on the **Optional Utilities** disk — a pick-and-choose installer modeled on
the MS-DOS Supplemental Utilities Disk. Building it is one command -
`TOS-Extras/build/build-disk.cmd` (Windows) or `build-disk.sh` (POSIX) — which
auto-discovers every add-on with a `package.lua`; add
`--install <path-to-OC-floppy-folder>` to "burn" the result straight onto a
floppy. Then insert it and run `install.lua` as admin.

You can also build one **from inside TOS** with `pkg make-disk <mount>` (§7.1) -
it bundles your installed add-ons onto the disk, no dev box required. Either
way, when you insert the finished disk TOS recognizes it and tells you to run
`pkg install`.

**The installer is not on the disk.** It doesn't need to be: the picker only
runs on a TOS machine, and every TOS machine has it in the base image. The
disk carries the packages, a set manifest, and a README saying `pkg install`.
(It used to ship a ~40 KB copy on every floppy *and* a second copy embedded in
the kernel's package manager — 40 KB of installer delivered to a machine that
already had one.)

**Reading the picker.** The list is on the left, grouped by category; the
right-hand panel describes whatever you're resting on.

| Mark | Meaning |
|---|---|
| `[*]` | already installed |
| `[x]` | you selected it |
| `[+]` | pulled in because something you selected needs it |
| `[ ]` | available |

Keys: **Space** toggle · **G** whole category · **/** filter · **A** all ·
**N** none · **R** add what your selection suggests · **Enter** install ·
**Q** quit.

**G** selects every package in the category the cursor is in — press it again
to clear them. Half-ticked groups fill up rather than emptying, so G always
means "give me the rest of these" until there is nothing left to add.

**/** filters the list as you type, matching the name, the description *and*
the category — you'll type any of the three looking for "the spreadsheet one",
and shouldn't have to guess which field the author used. **Enter** keeps the
filter, **Esc** undoes it (and with a filter already active, Esc from the list
clears it rather than quitting). The count rail changes to `3 of 14 match
'gam'` while one is on, because a filter you forgot about otherwise looks
exactly like a disk with packages missing.

**A** and **N** act on what is *visible*, which is what makes the pair worth
having together: filter to `game`, press **A**, install. An **A** that also
ticked the packages you had just filtered away would be the opposite of a
filter's purpose. Ticks survive filtering, so you can filter, tick, refilter,
tick again, and install the union.

**For scripts**, skip the picker entirely:

```
pkg install <name> <name> ...     several at once
pkg install --all --yes           everything on inserted media and repos
pkg install <names> --dry-run     print the plan, change nothing
```

`--yes` is *required* by `--all`, not merely accepted — `--all` takes every
package on whatever disk is in the drive, and a provisioning script that
stopped to ask would just hang.

The panel's `From` field says which disk a package is on — the set spans two
floppies, and everything mounted is listed together, so this is how you tell
them apart. `Needs` is what will be installed alongside (automatically, marked
`[+]`); if a requirement isn't on any inserted disk the panel says so rather
than letting the install fail. `Suggests` is optional — nothing is installed
from it unless you press **R**. `Wanted by` is the reverse view: every add-on
on the disk that recommends the highlighted one, which is usually the better
argument for installing it.

Below 60 columns the panel is dropped and the description moves to a footer,
so the picker still works on a small T1 screen.

**A set can span more than one floppy, and the picker knows it.** The builder
writes a *set manifest* (`optutil-set.lua`) onto every disk describing the
whole set — so with one floppy in the drive you still see the entire
catalogue. Packages on a disk that isn't inserted are dimmed, and their panel
says which disk to fetch, but you can select them anyway.

When you install, it does everything reachable now, then asks for the next
disk:

```
Insert disk 2 for: tetris, ttt
Enter = continue   A = stop, keep what's installed   U = undo all
```

**Enter** re-checks the drive and carries on (swap the floppy first).
**A** stops and keeps whatever already installed. **U** rolls the whole run
back, removing packages newest-first so nothing is stranded. You never have
to plan the install around which floppy happens to be in the drive.

The builder also keeps related packages *together* where it can: hard
`requires` edges are inviolable (a split group simply cannot install), and
`recommends` edges are honoured on a best-effort second pass — so
`tape-authenticator` lands on the same disk as the `tape` package it wants.
When a soft pair genuinely doesn't fit on one disk the build says which pairs
it had to separate rather than leaving you to discover it.

The **mouse** add-on is TOS's MS-DOS-style mouse driver. TOS has no baked-in
mouse support (the shell is keyboard-driven), but OpenComputers screens emit
touch/scroll signals — so installing `mouse` gives programs a
`require("mouse")` library that turns those into clean click/drag/scroll events
(with rectangle hit-testing for clickable buttons), plus a `mousetest` demo.

Installing it also lights up **mouse support in the panels shell** — the shell
auto-detects the driver (like DOS programs probing for MOUSE.COM):

- Click a **menu** to toggle it open/closed; click an item to run it.
- Click a **tab** to switch to it; right-click closes a closable tab
  (an editor with unsaved changes is surfaced instead of closed).
- Click a **file row** to select it; click it again to open it
  (directories navigate, files get the context menu). Right-click opens
  the context menu directly.
- The **scroll wheel** moves the file-list selection and scrolls
  viewer/editor tabs; clicking in the editor places the cursor.
- In *Settings → Status Bar*, click a checkbox to toggle that widget.

No configuration needed; `pkg disable mouse` switches shell mouse support
back off. Uninstalled, every mouse signal is ignored exactly as before -
the driver and the shell hooks are pure opt-in.

The **stock** add-on is the warehouse monitor. Put a transposer or inventory
controller next to your chests and `stock` totals every item across all of
them — one row per item, how many, how many stacks, and which sides it is on.
Press **W** on a row to set a minimum; anything below it turns red, and an item
you are watching that has dropped to **zero** still appears on the list rather
than quietly vanishing from a report of what you have. `stock low` answers the
other question — "what do I need to go make?" — sorted by worst shortfall.
`stock list` and `stock sides` are one-shot listings for scripts and for
checking your wiring.

Items are totalled by their **registry name**, not the name you see. Two mods
can both ship a "Copper Ingot" and any item can be renamed on an anvil, so a
count keyed on the display name would merge things that are not the same item
and split things that are — the one mistake an inventory count must not make.

Thresholds are saved in `/etc/stock-watch.cfg`, one tab-separated line each,
so you can edit them by hand or copy them to another base. Writing that file
needs admin: a base-wide alarm level is a property of the base, not a personal
preference. Setting one as a regular user is refused out loud rather than
silently forgotten.

### 7.3 Writing a package

A package is a directory with a `package.lua` manifest and its files laid out at
their install paths. Minimum manifest:

```lua
return {
  name = "mytool", version = "1.0.0", kind = "command",
  files = { "/usr/modules/mytool/init.lua" },
  commands = { mytool = "/usr/modules/mytool/init.lua" },
  capabilities = { "fs.read", "fs.write", "component" },
}
```

The command entry returns a module table: `return { commands = { mytool =
function(args, o) ... end } }`. It runs in a sandbox built from the *allowlisted*
capabilities (the `legacy` cap — raw os/io — can never be requested by a
manifest). Declare `hashes = { ["/usr/.../init.lua"] = "<64hex>" }` to get
integrity verification at install and run.

A capability the allowlist does not know is **dropped**, and the reason is
logged with the facet named — check `log` if a package installs cleanly and
then behaves as though it has no hardware.

**Widening or narrowing the allowlist: `/etc/pkg_caps.cfg`** (admin-writable).
Defaults stay in code; overrides are data:

```lua
{
  allow = { "peripheral.reactor" },     -- a manifest MAY now request this
  deny  = { ["*"] = { "internet" },     -- no package on this box, ever
            someGame = { "net" } },     -- or just this one
}
```

`allow` is the companion to `/etc/component_caps.cfg`, which names modded
component types and the capability that gates each. Without it you could add
a type there and still not install a package that drives it, because the
manifest's request was filtered out — the two files are halves of one answer,
and `component reload-caps` reloads both.

There is deliberately **no `grant`**: you can widen what a package may *ask
for* and narrow what it is *given*, but you cannot ask on its behalf. The
manifest is the record of what a package touches, and granting an undeclared
facet would make `pkg info` lie about it. `allow` also cannot re-enable
`legacy`. Denials outrank everything, per-package or `*`.

A config that will not decode leaves **no** overrides in force and logs at
warn — losing an `allow` is safe (you fall back to the default), losing a
`deny` is not, so it says so. Packages already loaded this boot keep the caps
they were built with.

By default a package's files sit **at their install paths** inside the package
directory, so `files` names each path once and it serves as both source and
destination. When that isn't true — a repo that keeps sources under
`master/<name>/`, say — an optional `fileMap` maps each declared target to the
path it is read from, relative to the package directory:

```lua
  files   = { "/usr/lib/gui.lua" },
  fileMap = { ["/usr/lib/gui.lua"] = "master/gui/gui.lua" },
```

Every `fileMap` entry must name a target that `files` already declares (that is
where the write confinement is enforced), and sources are relative and
traversal-checked. Translated OPPM manifests get one of these automatically;
hand-written TOS packages rarely need it.

Three optional fields describe relationships to other packages:

```lua
  requires   = { "blockfs" },   -- HARD: installed automatically alongside
  recommends = { "mouse" },     -- SOFT: offered, never installed for you
  conflicts  = { "othertool" }, -- must not be installed at the same time
```

`requires` is resolved and installed transitively — the picker marks them
`[+]` and counts them so you see the real install set first. `recommends` is
a suggestion: the picker shows it, adds it only when the operator presses
**R**, and shows the reverse view (`Wanted by`) on the recommended package, so
a driver wanted by four add-ons makes its own case. A missing recommendation
is never an error.

`conflicts` is checked **both ways** — an install is refused if the incoming
package names an installed one *or* an installed one names the incoming, since
a conflict is symmetric in fact even when only one author wrote it down. TOS
also refuses an install that would **overwrite another package's files**,
which needs no declaration at all: two authors picking the same install path
is enough. `--force` overrides either, loudly.

### 7.4 Updating packages

```
pkg outdated                  what has a newer version on the inserted disks
pkg upgrade <name> [<name>…]  replace those
pkg upgrade --all --yes       replace everything with a newer version
pkg upgrade <name> --dry-run  print the plan, change nothing
```

An upgrade is not "install over the top". TOS verifies the candidate first
(hashes, licence, conflicts) so a failed check never leaves you with the old
version already deleted; remembers whether the package was enabled and whether
its service was set to start at boot; removes the old version's files
**including any the new version no longer ships** — an install-over would
strand those forever, owned by nothing; installs the new one; then puts your
enable and boot-start choices back.

A package something else depends on can still be upgraded (the
reverse-dependency guard that blocks *uninstall* would otherwise freeze it
permanently). A **downgrade** — the disk in the drive being older than what's
installed — needs `--force`, because that is far more often a mistake than an
intention.

Services keep their enabled/disabled state across an upgrade but keep running
the old code until restarted: `service stop <svc>` then `service start <svc>`.

### 7.5 Third-party and OpenOS packages

`pkg` reads four manifest forms, so a loot disk or an OPPM repo installs like
anything else:

| File | Origin |
|---|---|
| `package.lua` | TOS native |
| `package.oppm.lua` | OPPM-style (`dependencies`, outer-name table) |
| `<dirname>.cfg` | the flat config many community repos ship |
| `programs.cfg` | a real OPPM **repo index**, at the repo root |

The last three are translated into the TOS manifest shape and the package is
**recorded as foreign** (`origin = "openos"`, shown by `pkg info`).

`programs.cfg` is how an actual OPPM repository describes itself: one index at
the root listing every package, with the sources under `master/<name>/…` and no
per-package metadata in the package directories at all. `pkg` looks for it in the
parent directory of whatever package directory you point it at, so a repo
checkout on a floppy works with no rearranging. A package that ships its own
manifest keeps using it — the index is the fallback, not an override.

Two things about that format need translating rather than copying:

- **`files` is keyed the other way round.** OPPM's key is the *source* path
  relative to the repo root, and its value is the destination **directory** — the
  installed filename comes from the source's basename. TOS manifests use one
  absolute path for both roles. A destination of `/lib` is relative to the install
  prefix and lands at `/usr/lib`; `//usr/bin` is absolute. An absolute
  destination outside `/usr` or `/var/pkg` is refused, which is the package write
  confinement (§7.1) doing its job rather than a translation failure.
- **`dependencies` values are install paths, not version constraints.**
  `dependencies = { libGUI = "/" }` means "also install libGUI", so the `/` is
  dropped rather than recorded as a version requirement.

One OPPM idiom is deliberately **not** supported: a `:`-prefixed key means "copy
this whole directory", and TOS installs a declared file list — each path
validated, hashed and owned by exactly one package, which is what conflict
detection and clean uninstall depend on. Such a package is refused with the
offending entry named, rather than installed while silently missing its data.

That label does real work rather than decorating the listing. A program
written for OpenOS reaches for `io`, `term`, `filesystem` — the OpenOS
userland, which TOS provides through its compat layer, but only to a sandbox
granted the capabilities for it. An OPPM manifest has no TOS capabilities to
declare, so without this a foreign package installed perfectly and then could
not execute a single line. A foreign package that declares no capabilities is
therefore granted the compat surface (`compat.io`, `fs.read`, `fs.write`,
`component`) at install time, and `pkg info` says so:

```
 origin:      OpenOS/OPPM package (runs on the compat layer)
              declared no capabilities — granted: compat.io, fs.read, ...
```

It is not a blank cheque. `legacy` — raw `os`/`io` — can never be requested by
any manifest, and peripherals (modem, robot, redstone…) still have to be asked
for explicitly. A foreign manifest that *does* declare capabilities keeps its
own set; the default is a fallback, not an override.

Third-party packages are otherwise ordinary: they take part in dependency
resolution, conflict checks and upgrades like first-party ones. Note that
OPPM manifests carry no file hashes, so installing one needs
`--allow-unverified` — you are running unchecked code, and TOS makes you say
so.

### 7.5a Signed packages and the publisher trust store

**What hashes prove, and what they do not.** A manifest's `hashes` prove
the files on the disk are the files the manifest describes — that the disk
is not *corrupt*. They cannot prove who wrote it, because whoever wrote the
files also wrote the digests. Until now the thing actually holding the line
was your admin privilege, and that is **per-disk consent**: you make the
same judgement call again for every floppy someone hands you.

A signature makes it **per-publisher**. Accept a key once, and everything
from that key verifies without a fresh call.

The chain is `signature → manifest → hashes → files`, and it only works
whole. A signed manifest that declares no hashes is still unverified code.
`pkg` runs both gates.

**The four states**, and none of them is quietly another:

| `pkg info` says | What happened | What you can do |
|---|---|---|
| `signed by trusted publisher 'x'` | Verified, key is in your store | Nothing — this is the good case |
| `valid, but the key was not trusted` | Verified, key is unknown to you | `pkg trust add <name> <key>` |
| `none (unsigned)` | No signature at all | Installs on admin privilege, as before |
| *refused* | A signature exists and **does not verify** | Nothing. There is no override |

That last row is the important one. A broken signature is *evidence*, not an
absence — so it is refused outright, and `--force` / `--allow-unverified` /
`--allow-unsigned` do not open it. If a bad signature degraded to "unsigned",
then corrupting a signature would be a way onto the permissive path.

**Trusting a publisher:**

```bash
pkg trust add strata 1f576b3a7c556a6f6701c2b0bd03ed07f290447726342d490173ac6ae64bbb3c
```

The name is **yours**. It has nothing to do with whatever name the disk
claims — a signature file may carry a `signer` label, and TOS shows it in
quotes as the disk's own word, never matches it against your store. A floppy
calling itself "Strata Systems" is not Strata Systems for saying so.

Verify the fingerprint (`pkg trust list`) with the publisher over a channel
that is **not the disk it came on**. A key that arrives with the package it
signs proves nothing at all.

```bash
pkg trust list                 # who this machine trusts, with fingerprints
pkg trust remove <name>        # stop accepting them (installed packages unaffected)
pkg trust require on           # refuse unsigned packages outright
pkg verify-sig /mnt/xx/foo     # who signed this? — without installing it
```

`pkg trust require on` is off by default, deliberately: a floppy from a
friend is the normal case in this ecosystem and always will be. Turn it on
when you want the stricter posture, and note that the shipped Optional
Utilities disks are unsigned unless you signed them yourself.

**Signing your own packages.** The private key is derived from a passphrase,
so there is no key file to lose:

```bash
pkg trust key <your-long-passphrase>    # prints the PUBLIC key to hand out
pkg sign /mnt/xx/mypackage              # prompts for the passphrase, masked
```

Sign **after** the hashes are final — the signature covers the manifest and
the manifest carries the hashes. The passphrase *is* the private key: the
same passphrase always produces the same key on any machine, which is what
lets you sign from two computers, and also why it should be long and kept.
It is never accepted on the command line, because a command line ends up in
shell history.

To sign a whole Optional Utilities disk at build time:

```bash
TOS_SIGNING_PASSPHRASE='…' TOS_SIGNING_NAME='Me' lua build/build-disk.lua --sign
```

**Under the hood**, for the curious: Ed25519 as specified by RFC 8032, in
pure Lua, pinned to the RFC's own test vectors — so a manifest signed by any
other Ed25519 tool verifies here and vice versa. It is loaded lazily, only
when a signature is actually present, and it yields cooperatively while it
works: verification is real arithmetic and takes noticeable time on a small
machine. A data card cannot help (its ECC is a different curve, and Ed25519
needs SHA-512 while the card offers SHA-256).

### 7.6 Remote repositories (internet card)

With an **Internet Card** installed, `pkg` can fetch packages from a repo laid
out the OPPM way — one `programs.cfg` at the root, sources underneath it.

```
pkg repo add oc https://example.com/oc/master    Register a repo
pkg repo list                                     What this machine will fetch from
pkg repo remove oc                                Stop trusting it
pkg remote                                        What the repos offer
pkg fetch <name> [--allow-unverified]             Download it and install it
internet                                          Card status (is it even usable?)
```

**The repo list is the allowlist.** There is no default repository, no
discovery, and no way for a repo's index to introduce another host — a fetch
that would leave the configured origin is refused. Adding a repo is an admin
action and a standing decision about where this machine accepts executable code
from, which is why it is gated exactly like an install.

**A fetch is a download followed by an ordinary install.** `pkg` downloads the
index and the package's files into a staging directory under `/var/pkg/remote`,
laid out exactly like a repo on a floppy, and then runs the *same* install path
against it. Manifest validation, the `/usr` + `/var/pkg` write confinement,
SHA-256 verification, conflict and file-ownership checks, dependency resolution
and the unverified-package gate are not reimplemented for the network — they are
the same code, so they cannot drift. Staging is cleared after every fetch,
successful or not.

**Most repos ship no hashes**, and a package TOS cannot check is unchecked
executable code from a stranger. `pkg fetch` refuses it until you say
`--allow-unverified`, exactly as a hashless floppy package does. That prompt is
the point at which you are deciding to trust the repo — the fetch itself proves
nothing.

Downloads are bounded, because these are Minecraft computers: 128 KB per file,
512 KB per package, 64 files per package, and a 128 KB index. A response that
overruns is abandoned rather than discovered by running the machine out of
memory. `internetMaxKB` and `internetTimeout` in `/etc/tos.cfg` tune the string
fetch used by `internet get`.

> **Not yet supported:** OPPM's *master list* — the index-of-indexes at
> `openprograms.github.io` that lets `oppm` search every registered repo. TOS
> works one repo at a time, by URL. Add the ones you want.

If a fetch fails, run `internet` first: "it doesn't work" has three completely
different causes — no card installed, the **server** has HTTP disabled for
internet cards (nothing TOS can change), or an admin here ran `internet off`.

## 8. Networking (Zero-Trust)

### 8.1 Trust tiers

| Level | Allowed |
|-------|---------|
| BLOCKED | nothing (packets dropped silently) |
| UNKNOWN | ping/pong only (default for everyone) |
| KNOWN | + hostname exchange, public info |
| TRUSTED | + encrypted messaging, file transfer, remote exec |

Elevation requires a deliberate local admin action: `net trust <addr> [full]`,
`net block <addr>`, `net revoke <addr>`. Inspect with `net peers` / `net`.

### 8.2 The wire

Between `TRUSTED` peers (with encryption on), sensitive payloads are encrypted
(AES with a data card; a MAC-protected XOR fallback otherwise) and carry a
per-packet nonce + HMAC over `(type ‖ to ‖ algo ‖ epoch ‖ seq ‖ nonce ‖
ciphertext)`. The receiver verifies the MAC before decrypting, refuses duplicate
nonces and stale sequence numbers (per-peer monotonic + per-boot epoch), and
refuses an XOR downgrade when AES is available. Discovery/handshake packets are
intentionally public.

### 8.3 The mesh transport

Point-to-point packets reach a peer you can *hear*. The **mesh** reaches one you
can't: it is part of the integrated network, and any service can ride it. There
is no central server and no routing table — a node knows only its immediate
radio neighbours, and a message reaches a destination several hops away by
**controlled flooding**: each node re-broadcasts what it hasn't seen before,
decaying a hop budget (TTL) so nothing circulates forever, de-duplicating by
message id so loops collapse.

Reliability is **store-and-forward**. The origin keeps a copy and re-floods on a
timer until an acknowledgement (flooded back the same way) arrives or a deadline
passes; a node that merely *relayed* a message also holds it briefly, so a
recipient that blinks back online still gets a re-flood from the middle of the
mesh. Every hop is between mutually `TRUSTED` neighbours — the same posture as
the relay path — and the **payload is sealed end-to-end** for the final
recipient with your shared secret, so relays forward a blob they cannot read.
A per-second relay budget stops a flood being turned into an amplification
weapon through you.

Messages carry a **service name**, so one mesh serves many tenants: `chat`'s
`/mail` bridge, the `mail` add-on, and anything added later all multiplex over
it, and a service only ever sees its own kind. A machine with no handler for an
arriving kind drops it **without acknowledging** — the sender keeps retrying,
which is honest: nothing stored it there.

**Sealed or refused.** Sending to a peer you have no shared secret with is
*refused*, not silently sent in the clear (pair first — `net pair`). Broadcasts
(`*`) cannot be sealed by definition, so they must be opted into explicitly and
are labelled PLAINTEXT wherever they appear.

### 8.4 Chat: one peer, one group, or everybody

Chat is multi-operator. Three ways to address a line, distinguished by how it
starts:

| You type | Goes to |
|---|---|
| `bravo: on my way` | one peer (address prefix or hostname) |
| `@ops: reactor is down` | everyone in the named group |
| `heading out` | every trusted peer |

Groups are managed from inside chat with `/group`:

```
/group                      list groups and their members
/group new ops alpha bravo  create (optionally populated)
/group add ops charlie      add members
/group rm  ops charlie      remove members
/group del ops              delete the group
```

A group is a **name for a set of peers**, not a protocol. There is no group
membership on the wire, no group key and no server: each member gets an
ordinary directed message, so a group works between any peers that already
trust each other and nobody has to agree about who "ops" is. The list lives
in `/etc/chat-groups.cfg` (per machine, admin-managed).

If some members can't be reached, chat says so — "delivered to 2 of 4" and
names the ones it couldn't reach. A group that silently shrank because
someone's machine was off would let you believe a message landed when it
didn't.

### 8.5 The Intercom (announcement system, add-on)

`pkg install intercom`

The Intercom says whatever you want it to say — the reactor has gone offline,
you're low on iron, the shift is over. Two channels carry the same
announcement at once: a **Computronics tape** plays the recorded voice, and
the same **words** go out over the mesh to every machine willing to hear them.

**The catalog is the whole trick.** A tape drive can't tell you what's
recorded on it — it's audio, there's no index. So you tell it once, in the
notation you'd write down anyway. `/etc/intercom.cues`, one line per
announcement:

```
fuel-low  [0001] "Warning: Reactor fuel low." [0005]  warn
offline   [0006] "Warning: Reactor offline. Facility on backup power generation." [0010]  alert
evac      [0011] "Evacuate the facility." [0020]  critical
```

Start position, what it says, end position, how urgently. From that one line
the Intercom knows where to seek, when to stop, what to broadcast, and how
hard to interrupt people. Positions are tape byte offsets; `[0001]` and `[1]`
both parse, and one typo'd line is reported by number instead of taking the
whole catalog down.

Positions written by hand are easy to get wrong, so check them before you
trust them:

```
intercom test evac      Seeks, plays, stops — and tells nobody at all.
intercom play evac      The real thing: tape plays, everyone is told.
intercom say "we are out of iron" --severity warn
```

The tape is **optional**. `intercom say` is a text-only announcement and
needs no drive.

**Severity decides how hard it interrupts.** `info` `notice` `warn` `alert`
`critical`. Below the receiver's popup level an announcement goes to the chat
tab and the log; at or above it, a message box appears on their screen
whatever they were doing.

**The cooldown is why that's safe.** A failing reactor can announce itself
every few seconds, and a modal per announcement would make the computer
unusable at exactly the moment you need to type on it. After one popup, no
further popup appears for `cooldown` seconds (default 60). Nothing is dropped
— only the *interruption* is suppressed; every announcement still reaches
chat and `intercom log`.

Hearing announcements needs `service start intercom`. It ships disabled:
accepting messages that can raise a modal on your screen is your decision.
A machine without it still relays announcements for its neighbours.

```
intercom                     Open the Intercom tab (cues + heard log)
intercom set popuplevel warn Interrupt me for warnings too
intercom set cooldown 120    Two minutes of quiet after an alarm
intercom log 20              What this box has heard
```

*See also:* `man intercom`.

### 8.6 Tools
`chat` (TUI chat with trusted peers), `rsh <addr> <cmd>` (remote shell — sandboxed,
step-budgeted, TRUSTED + challenge-verified only), `scp <addr>:<path> <local>`
(file transfer, `/public` only by default). Remote exec is **off** until the
`rshd` service starts.

`net` itself carries more ground than the tools above: `net scan`/`discover`
(broadcast ping), `net peers`/`net servers` (discovered hosts), `net trust
<peer> [full]` / `net block <peer>` / `net revoke <peer>` / `net forget <peer>`
(trust-tier changes, admin), `net request <peer>` / `net requests` (ask a peer's
admin for trust / view pending requests), `net send <peer> <msg>` (chat message),
`net alias add/rm/list/show` (name a peer — add/rm admin, list/show anyone), and
`net pair start/status/close/<peer> <code>` (out-of-band shared-secret pairing
window, admin). `<peer>` accepts an alias, a full address, an address prefix, or
a `net scan` result index. *See also:* Chapter 14, `man net`.

## 9. Power & Resilience

### 9.1 Unsafe-shutdown detection

TOS records a dirty bit (`/var/run/pwrstate`): `running` early in boot, flipped to
`clean` only by `shutdown`/`reboot`. If the next boot finds it still `running`
(or corrupt), the previous session was cut off — power toggled, battery died, or
the chunk unloaded. You'll see it in the kernel log, on the login screen, and in
`doctor`'s power section.

### 9.2 Corruption prevention

The critical state files (`users.dat`, `trust.dat`, `tos.cfg`, the cron DB,
`critical.bak`) are written **atomically** (temp file, then replace), so a power
cut mid-save can't truncate them. Interrupted writes are repaired at boot. On a
tablet, a **critical battery** is converted into a clean shutdown (set
`critBatShutdown = false` in `/etc/tos.cfg` to opt out).

### 9.3 SRM — System Repair & Maintenance

TOS grew four maintenance tools separately: `doctor` (runtime health), `verify`
(files vs the manifest), the boot-time fixer pass, and `backup`. `srm` is the
front door over all of them — they still work on their own, but `srm` runs them
together, reports everything on one severity scale, and adds the two things
none of them could do alone.

**SRM has two halves, and the split is the point.**

*SRM Basic* lives in the EEPROM, inside the BIOS. It runs at POST and catches
the faults that stop a boot *before anything on disk can run*: a CPU that can't
execute the kernel, no boot device, a missing kernel, an `/init.lua` that won't
load. When it hits one it names the fault, beeps it — one long tone, then a
number of short ones equal to the code's digit, so a machine with a dead screen
is still diagnosable — and **parks the code in the EEPROM data field**, the one
piece of storage that survives a machine whose disk is the problem.

| Code | Beeps | Meaning |
|------|-------|---------|
| `C1` | 1 | CPU architecture too old — TOS needs a Lua 5.3+ CPU |
| `D2` | 2 | No boot device: no `/init.lua` disk, no TBFS drive |
| `B3` | 3 | The TBFS boot blob would not compile |
| `K4` | 4 | The kernel was missing (`/tos/kernel/init.lua`) |
| `I5` | 5 | `/init.lua` could not be opened |
| `I6` | 6 | `/init.lua` would not compile |

*SRM Advanced* is the `srm` command. It has a disk and room to work, so it
covers everything the 4 KiB EEPROM has no space for. On the first successful
boot after a POST failure it reads the parked code, explains it in English in
the boot log, and clears it — so a fault that killed a boot last night is still
waiting to be explained this morning.

**The known-good baseline.** `verify` checks files against the manifest, which
says what *should* be installed; it cannot tell you a file was quietly changed.
`srm baseline` records a SHA-256 of every boot-critical file as it stands now,
and `srm scan` reports anything that has since gone missing or drifted. With
`--full` it also stores a verified copy of each file under `/var/srm/store`,
which makes local repair possible (`srm repair --restore`). Without it, only
hashes are kept — a few hundred bytes instead of a couple of hundred KB — drift
is still detected, and repair needs an external source (`--source /mnt/fd0`,
e.g. the install floppy).

A restore never writes a copy it hasn't checked: local store or external
source, the candidate must hash-match the baseline or the file is refused and
left alone. With no baseline there is nothing to check against, so the
operation refuses unless you accept that explicitly with `--unverified`.
Restores are written atomically, so a failure mid-repair cannot leave a
zero-length system file — SRM causing the damage it exists to fix would be a
poor joke.

Capturing a baseline is a claim about what "good" means on this machine. Take
one on a system you trust — a fresh install, or one that just passed
`srm verify`. A baseline taken on a damaged system certifies the damage.

```
srm                     Did anything go wrong? (instant — hashes nothing)
srm baseline --full     Record this system as known-good, with copies
srm scan                Has anything changed since?
srm repair              Fix what is mechanically safe to fix
srm repair --restore    ...and put drifted system files back
srm full                Everything, for a bug report
```

`status`, `scan`, `health`, `verify` and `full` are open to any logged-in user;
`baseline`, `repair` and `restore` need ADMIN. See `man srm`.

Some repairs only work at boot, before the files they fix are read — that's
what `bootsettings repair on` schedules (it runs once and clears its own flag,
so a repair that crashes can never loop). It is the same code as `srm repair`
and produces the same report, but it never restores files: overwriting a system
file is a decision an operator makes, not a fix to apply unattended.

### 9.4 Disk swap ("slow RAM")

OpenComputers has no transparent paging, so TOS offers *explicit* spill-to-disk
for cold data, backed by `/var/swap`. A store API (`swap.store/fetch/free`) and a
`swap.table{ hot = N }` proxy (a disk-backed table with a small in-RAM LRU cache)
let a program offload large data and page it back on demand. It's size-capped
(`swapMaxKB`) and volatile (wiped each boot). Inspect it with `optimize swap`.

**The shell uses it for cold view buffers.** A `cat` of a large file, a long
listing or a `watch` snapshot opens a view tab holding *every* line, and you
read one tab at a time — the rest are cold. When free RAM drops below
`swapPressurePct` of total (default 25%), the buffers of inactive view tabs
spill to swap and page back the moment you open the tab again. It is
pressure-triggered on purpose: disk I/O in OC carries a per-tick budget, so
paging on every tab switch would cost more than it saves on a machine with RAM
to spare. Tabs that regenerate themselves (`watch`) are left alone, small
buffers aren't worth the round-trip, and if swap is full or unavailable the
buffer simply stays in RAM.

`optimize swap` reports how many tabs are currently paged and what the
threshold is; `optimize swap now` pages every cold tab immediately, ignoring
the pressure check, so you can see the mechanism work on a roomy machine.

When a **data card** is installed, swapped data is compressed (deflate) on the
way to disk and inflated on the way back, so more fits under the cap — automatic
and detection-gated (a card-less box behaves exactly as before). The same data
card powers the `compress`/`decompress` file commands (Chapter 14) for shrinking
files on small disks.

## 10. Themes & Customization

Nine built-in presets — `default` (teal frames + gold titles on black),
`midnight` (Tokyo-night indigo), `amber` and `green` (CRT phosphor),
`plasma` (neon red-orange like early plasma panels; every color stays in
the red-orange band with no blue/green light, so operators working in the
dark keep their night vision), `classic` (Norton white-on-blue with cyan
bars), `contrast` (high contrast), `nord` (arctic blues), `solarized`
(Solarized dark) — plus per-key overrides. Every preset uses tinted bars instead of solid accent
blocks, keeps title/warning/error visually distinct, and now carries its
own syntax-highlighting colors, so switching presets restyles the editor
too. `theme list|show|set <name>|preview <name>|
color <key> <0xRRGGBB>|reset|clear|keys` (aliased `colors`) — `theme color`
also accepts the `syn_*`, `file_lua`, and `dir_color` keys. Saved per user
(`~/.theme.cfg`) and re-applied at login. On Tier-1 monochrome GPUs themes are
disabled (RGB would be unreadable); on Tier-2 they snap to the dye palette;
Tier-3 is full RGB. (The PaneUI app for OpenOS mirrors the six classic themes.)

A profile can also name a preset (`profile set theme <name>`); it applies at
login only when you have no explicit `theme set` choice saved — the more
specific `~/.theme.cfg` (which can carry per-key overrides) always wins.

### 10.1 Screen resolution

TOS does not force the GPU to its maximum resolution. On a tier-3 GPU + large
screen the maximum is 160×50, which renders the TUI in tiny text — and glyphs
can't be scaled. The fix is to lower the *resolution*: fewer character cells
over the same physical blocks means bigger, readable text. The policy is set by
`screen res` and saved in `/etc/tos.cfg`:

- **`auto`** (default) — density-based: target ~10 columns × 4 rows per physical
  screen block (read via `getAspectRatio`), clamped to the hardware max — but
  never below the ~80×25 baseline, so ordinary screens keep their full
  resolution and only big multiblock walls are scaled for readable text.
  Falls back to an ~80×25 cap when the block
  size can't be read. Tune the density with `screenColsPerBlock` /
  `screenRowsPerBlock`.
- **`max`** — use the hardware maximum (the pre-1.3.1 behavior).
- **`<W>x<H>`** — an explicit resolution (e.g. `80x25`), clamped to the max with
  a warning if it didn't fit.

`screen res` (no value) shows the current/maximum/block sizes and the active
policy; `screen res <value>` (admin) applies it live and saves it. Programs can
declare a size they need in their package manifest (`screen = { width=, height=,
mode="exact"|"min" }`); TOS fits the display before running them and restores the
policy on exit (`man screen`).

### 10.2 Language packs (i18n)

TOS's UI text is community-translatable without touching code. A language
is one DATA file at `/usr/lang/<code>.lang` (a commented table literal,
parsed by the safe decoder — never executed):

```lua
return {
  meta = { code = "ru", name = "Русский" },
  strings = { ["login.username"] = "Имя пользователя:" },
}
```

Every string in converted surfaces keeps its English built in, so a
missing key, an absent catalog, or a corrupt file always falls back to
English — partial translations are valid by design.

- `lang` — current language + installed catalogs
- `lang <code>` / `lang en` — set for yourself (live, saved to your profile)
- `lang system <code>` — machine default (admin; applies from boot, so the
  login screen is translated too)
- `lang dump [path]` — write a translator template of every translatable
  key seen this session (visit the screens you care about first)

Currently translated surfaces: the login screen and the Desktop (a Russian
starter catalog ships in the base image). Command output, `help`, and man
pages are English for now. Rarer languages can ship as ordinary packages
that just install a file into `/usr/lang`.

## 11. Peripherals

- `redstone` / `rs` — vanilla + bundled-cable I/O (`rs set <side> <0-15>`,
  `rs pulse <side> [dur]`). Needs the `peripheral.redstone` capability.
- `robot` — robot/drone movement & interaction (`robot forward|back|up|down|
  swing|use|detect|inv`). Needs `peripheral.robot`.
- `inventory` / `inv` — inventory controller / transposer inspection.
- `component <type> [method] [args]` — call any OC component method directly (admin).

Each is hidden from `help` when the hardware isn't attached.

### 11.1 Printing (add-on)

TOS has no baked-in printing, the same way it has no baked-in mouse support.
Install the **`printer`** package from the Optional Utilities disk (§7.2) and
you get `require("printer")` plus a `printer` command. It drives PC-Logix's
**OpenPrinter** addon — the `openprinter` component. (OpenComputers' own
`printer3d` prints *models*, not pages; it is a different device and this
does not touch it.) The package needs the `peripheral.printer` capability,
gated rather than covered by blanket `component` because a printer actuates
the world and spends your paper and ink.

```
printer                    what is attached, and its paper/ink levels
printer test               one page, to prove the wiring
printer file <path>        print a text file
printer preview <path>     paginate it WITHOUT printing
printer scan [<path>]      read the page in the input slot
printer tag <text>         print a name tag
printer clear              empty the printer's buffer
```

Flags for `file` / `preview`: `--title=T` `--copies=N` `--center`
`--color=0xRRGGBB` `--no-wrap` `--dry-run` `--force`.

Two things worth knowing before you print anything long:

- **`preview` exists because paper is a real resource.** A page holds 20
  lines and 164 pixels of width, so a three-line footer can push a document
  onto a fourth sheet. The way to find that out should not be finding a
  fourth sheet in the output chest.
- **Colour costs colour ink per LINE, not per page.** OpenPrinter charges a
  unit of the colour cartridge for every line that carries a colour, so
  `--color` on a long document is expensive. Leave it off and everything
  goes through the black cartridge. The cost line before each job counts the
  two separately.

A job is checked against the paper and ink actually loaded *before* the first
sheet moves, and refused with the shortfall named. If a job does fail
partway, the error says how many pages already printed — check the output
slots before reprinting.

`lsdev` shows an attached printer's paper and ink levels in its info column.

### 11.2 `write` — the word processor (add-on)

`write <path>` opens a document. This is **not** a second `edit`: the
difference is the page. `write` knows how wide a printed line is and how many
fit on a sheet, so the rail across the top says which sheet the cursor is on,
how full that sheet is, how many words you have written, and what the whole
thing will cost in paper and ink — live, while you type. Page breaks are
drawn across the text where they will fall.

It `requires` the `printer` package (the page model lives there) and the
picker will tick both. A printer itself is optional: composing, pagination,
the page view and saving all work with nothing attached, and the rail says
whether the breaks were measured by a real printer or estimated.

| Key | Does |
|---|---|
| `F1` | help, including the dot-command list |
| `F2` / `^S` | save |
| `F3` | print (asks first, with the cost) |
| `F4` | set the title |
| `F5` | page view — see the sheets as they will print |
| `F6` | insert a page break |
| `F7` | centre from here on |
| `F10` / `^Q` | quit (offers to save) |

F-keys rather than Ctrl chords because the shell already owns `^B`
(background) and `^T` (task switch); `^S` is kept for save because everyone's
hands do it.

**The file is plain text.** Formatting rides on dot commands in column one,
so a document stays greppable, mailable, hand-editable and never executable:

```
.title Reactor Report      the printed page's item name
.center                    centre from here on (.left turns it off)
.color 0xFF0000            colour from here on (.color off ends it)
.page                      start a new sheet
..this line starts with a dot
```

A dot command it does not recognise is a warning in the status row and the
line is kept as ordinary text — a document does not fail to open over a typo.

## 12. Services & Scheduling

- **rc.d:** `/etc/rc.d/` startup scripts with `start`/`stop`. `service [start|
  stop|list] <name>`. The default set: discovery, chat relay, file share, remote
  shell daemon. Kernel-tier (`_kernel_`) services come from a hardcoded allowlist;
  everything else runs sandboxed.
- **cron:** `cron [list|add <interval> <cmd>|rm <id>]` — persistent scheduled tasks.

---

## 13. Lua Scripting & Automation

TOS *is* Lua (the OpenComputers 5.3 dialect; the 5.4 architecture works too), so the same language that runs the
shell runs your scripts. There are three ways to run Lua, from quickest to most
permanent.

### 13.1 One-liners with `lua`

`lua <expression-or-statement>` — **ROOT only** — evaluates a snippet immediately
and prints the result, like a calculator with a whole language behind it. The
REPL has full `_ENV` access (it's a debugging tool, not a sandboxed program
surface), so it's gated to ROOT and every session is logged:

```
lua 2^16
lua print(("hello"):upper())
lua for i=1,3 do print(i) end
```

It runs in the **sandbox of your session** — you get a safe `_G`, `string`,
`table`, `math`, `os.time`/`os.date`, and (if your tier allows) `component`
access through capability-checked wrappers. There is no raw `io`/`os` unless a
program was written to request the `legacy` capability by hand (packages never
can — see 7.3).

### 13.2 Script files with `run`

**ADMIN** — put statements in a `.lua` file and execute it with `run <file>
[args...]`:

```lua
-- /home/me/backup.lua
local fs = require("filesystem")          -- compat API, sandboxed
local args = {...}                         -- command-line arguments
local src = args[1] or "/home/me"
print("backing up " .. src)
```

```
run /home/me/backup.lua /home/me/docs
```

`run` reads the file, compiles it, and runs it in the sandbox with `...` set to
your arguments. Edit scripts with the built-in editor (`edit /home/me/backup.lua`,
Chapter 4.3). Use `man edit` for its keys.

What a script can `require`:

- The **compat APIs** (`filesystem`, `term`, `event`, `serialization`,
  `keyboard`, `io`, `text`, `colors`, `sides`, `component`, `computer`) — these
  are the OpenOS-style names, backed by TOS's sandbox. This is the portable way
  to write tools that also run under OpenOS.
- Nothing under `kernel.*` — that namespace is not reachable from sandboxed code.

### 13.3 Packaging a script as a command

When a script earns a permanent place, wrap it as a **package** so it becomes a
first-class command with a declared capability set and (optionally) hash
verification. The minimal shape:

```lua
-- package.lua
return {
  name = "backup", version = "1.0.0", kind = "command",
  files = { "/usr/modules/backup/init.lua" },
  commands = { backup = "/usr/modules/backup/init.lua" },
  capabilities = { "fs.read", "fs.write" },
}
```

```lua
-- /usr/modules/backup/init.lua
return { commands = { backup = function(args, opts) ... end } }
```

Install with `pkg install`, then `backup` works like any built-in. Full details,
the capability allowlist, and hashing are in Chapter 7 (and `man packages`).

### 13.4 Scheduling scripts

To run a script automatically:

- **At boot** — drop it in `/etc/rc.d/` as a service (Chapter 12); kernel-tier
  names need the allowlist, everything else runs sandboxed.
- **On a timer** — `cron add <interval> "run /home/me/backup.lua"` (Chapter 12).

---

# BOOK TWO — THE REFERENCE

*Look-up material. Start with the alphabetical Command Reference; the chapters
after it cover the security model, configuration, and recovery.*

## 14. Command Reference (Alphabetical)

Every internal and external command, listed A–Z. Each entry gives the syntax, a
short description, the common flags/subcommands, an example, and the errors you
may see. In a syntax line, `<angle>` placeholders are required, `[bracketed]`
ones are optional, and `a|b` means "a or b". Commands marked **(admin)** require
an ADMIN session;
**(tier)** ones are hidden unless the matching hardware/package is present, and
**(pkg)** ones arrive with an installed package, not the base image.

> Tip: `help <cmd>` gives the one-line version and `man <cmd>` the page; this is
> the exhaustive version. If a command isn't listed in your `help`, it's
> install-aware hiding — the hardware or package isn't there (see Chapter 17).

### A

**about** — `about`
Show the product banner, version, codename, and a one-line hardware summary. No
flags. (v1.4.0 folded the old `ver` command in here.) *See also:* `hw`.

**alias** — `alias [<name> [command...]]`
Per-user command shorthand. With no argument, lists your aliases; `alias <name>`
shows one; `alias <name> <command...>` defines one. Aliases are saved in your
profile (`~/.profile.cfg`), take effect on the next command rather than the next
login, and are personal — nobody else's shell sees them. An alias carries **no
privilege**: the expansion is dispatched through the same tier checks as if you
had typed it, so aliasing a name to an admin command does not make it runnable.
Expansion chains (`alias l=ll` where `ll` is itself an alias) but never loops —
each name expands at most once, so the near-universal `alias ls "ls -a"` runs the
real `ls` instead of hanging the seat. *Examples:* `alias ll ls -l`,
`alias log tail /var/log/tos.log`. *See also:* `unalias`, `profile`, `which`.

**audio** — `audio [on|off|volume <0-100>|test]`
Toggle the audio feedback subsystem, set the volume, or play every beep code
(success/confirm/warning/error/critical/notify/chat/shutdown) as a test. With no
argument, shows the current on/off state and volume. Setting persists to
`/etc/tos.cfg`. *See also:* `config`.

### B

**backup** — `backup [snapshot <src> <dest.bak>|inspect <file.bak>|restore <file.bak> [destRoot] [--force]]` **(admin)**
Snapshot a directory tree into a self-contained backup file, inspect one without
restoring, or restore it (optionally to a different destination; `--force`
overwrites). Companion to `trash` (single-file undelete) — `backup` is for
whole-tree snapshots. *See also:* `trash`, `deploy`.

**battery** — `battery`
Show stored/maximum energy and the current charge level. Used by the power
subsystem to warn and clean-shutdown on critical battery (Chapter 9).

**bg** — `bg [job]`
Resume a stopped job in the background. *See also:* `fg`, `ps`, `kill`.

**bootsettings** — `bootsettings [show | <setting> <value> | reset]` **(admin)**
Edit `/etc/boot.cfg` from the shell (the visual editor is **Delete** during
POST). Settings: `profile` (minimal/normal/full/diagnostic/**safe** — Safe
Mode), `verbosity`, `ui` (panels/cli startup interface), `repair` (on = run
self-repair once next boot), `show` (POST screen), `cputier`/`datatier`
(hardware overrides), `ramgate` (auto/plenty/tight — declare your RAM
situation for the optional stages), plus one on/off/auto toggle per optional
feature (`net`, `services`, `cron`, `packages`, ...). `bootsettings show`
prints everything; changes apply on the next boot. *See also:* `man
bootsettings`, Chapter 2.

### C

**cat** — `cat <file>`
Print a file to the screen. *Error:* `no such file`.

**cd** — `cd [dir]`
Change the working directory; `cd` with no argument goes home, `cd -` to the
previous directory. *Error:* `not a directory`.

**chat** — `chat` **(tier: modem)**
Open the encrypted chat client to TRUSTED peers (Chapter 8) as a
**persistent tab**: switch to other tabs and keep working — messages keep
arriving in the background and the tab label shows an unread badge
(`Chat(3)`). Type to talk — `peer:message` for one peer, `@group:message`
for a named group (`/group` creates and edits them; see §8.4), plain text to
broadcast, `/help` for commands, `/mail` to bridge into mesh mail — which
needs the `mail` add-on installed, and says so if it isn't;
Announcements from the `intercom` add-on appear here too, marked `***`;
**PgUp/PgDn** scroll history; **Ctrl+Q closes the tab**, which also stops
the background listening — no invisible chat presence. Chat is part of the
base image and rides the same mesh transport mail does. *See also:* `net`,
`mail`, `man networking`.

**component** — `component <type> [method] [args...]` **(admin; invoking a method: root)**
List a component *type*'s available methods, or call one, through the
capability wrappers (`component list` shows attached types and counts;
`component reload-caps` reloads `/etc/component_caps.cfg`). The whole command —
even `list` — requires ADMIN; actually invoking a method on a component needs
ROOT, since raw method calls bypass the capability system and can drive
hardware directly. `eeprom.set`/`setData`/`makeReadonly` are denied outright —
use `flash`. *See also:* `hw`, `hostname`, `flash`.

**compress** — `compress <file> [out] [-k]` **(tier: data card)**
Deflate a file into a self-describing `.tcz` container using the data card
(works on every card tier). Replaces the source unless `-k`/`--keep` is given;
with no `out`, writes `<file>.tcz`. Tiny/incompressible files are stored
verbatim. *Errors:* `Compression needs a data card`, `Not a file`. *See also:*
`decompress`, `man compress`, `optimize`.

**config** — `config`
Dump every key in `/etc/tos.cfg` (hostname, thresholds, `swapMaxKB`,
`critBatShutdown`, …). Takes no arguments — read-only, no `get`/`set`
subcommands — and has no tier gate. *See also:* Chapter 16.

**cp** — `cp <src> <dst>`
Copy a file or directory (recursively). *Errors:* `no such file`,
`destination exists` (for non-overwrite cases). *See also:* `mv`.

**crash** — `crash [<name>]` **(admin)**
List the crash post-mortems in `/var/crash`, or print one. TOS writes a report
there on a kernel panic or an unrecoverable-shell drop (reason, uptime, free RAM,
the recent log, and any traceback), and the next boot reports "Last run crashed:
…". Read the details after rebooting. *See also:* `log`, `doctor`.

**cron** — `cron [list | add <interval> <cmd> | rm <id>]` **(admin)**
Manage persistent scheduled tasks (Chapter 12). *Example:*
`cron add 300 "run /home/me/backup.lua"`.

### D

**date** — `date [fmt]` | `date tz <hours>`
Print the real host wall-clock time (Lua `os.time`/`os.date`), not in-game time —
OpenComputers' own `os.time()` returns in-game ticks, not a wall clock, so
`date` deliberately bypasses it. `fmt` is an optional `os.date`-style format
string (default `%Y-%m-%d %H:%M:%S`). `date tz <hours>` sets a cosmetic
timezone offset (-23..23) applied to the *displayed* time only — there is no
settable real-time clock to adjust. *Example:* `date tz -5`. *See also:* `time`
(alias).

**decompress** — `decompress <file.tcz> [out] [-k]`
Restore a `.tcz` file made by `compress`. A "stored" container needs no data
card; a truly compressed one needs the card to inflate. Replaces the source
unless `-k`/`--keep`; with no `out`, strips the `.tcz` suffix. *Errors:*
`Not a .tcz container`, `data card required to decompress`. *See also:*
`compress`, `man compress`.

**deploy** — `deploy <mount>` | `deploy drive <addr>` **(root)**
Write the whole-OS system image to a target disk per the manifest (an install
disk you run on another machine). `deploy drive <addr>` instead installs onto an
**unmanaged raw drive** as a bootable TBFS volume (needs the `blockfs` package;
fails loudly if it's absent) — see Chapter 5.4. For the add-on counterpart — a
pick-and-choose disk of your installed extras — use `pkg make-disk <mount>`.
*See also:* `drive`, `verify`, `pkg`, `man packages`.

**desktop** — `desktop`
Open (or focus) the **Desktop** tab — the tile home screen of built-in apps and
installed package commands. Re-opening re-scans installed packages. Tiles honor
command tiers and hardware gates. Your personal `~/.launcher.cfg` entries appear
here as tiles too. *See also:* `settings`, `tape-menu`, Chapter 4.4.

**device** — folded into `hostname` (v1.4.0): `hostname` with no argument shows
the device type + hostname; `hostname <name>` sets the name.

**df** — `df`
Show filesystem space per mount. *See also:* `du`, `mount`.

**diag** — see **doctor** (alias).

**doctor** — `doctor` (alias `diag`)
The **runtime health** check: hardware tiers, memory headroom, power state, disks,
services, security posture, recent log warnings, and unsafe-shutdown repairs. The
first stop when something seems off. (This checks live state, *not* file
integrity — for that, run `verify`.) *See also:* `verify`, `log`, `man memory`.

**drive** — `drive [list | info <addr> | format <addr> [label] | mount <addr> [path] | check <addr> [--repair] | defrag <addr> [--if-over N] | read <addr> <sector>]` **(format/mount/check/defrag: admin)**
Manage **unmanaged (raw) drives** — `drive` components with no filesystem. `list`
and `info`/`read` work on the base image; `format`/`mount`/`check`/`defrag`
need the **`blockfs`** package (TBFS). See Chapter 5.4. *See also:* `disk`
(managed removable media), `df`, `mount`.

**du** — `du [path]`
Show disk usage of a path subtree. *See also:* `df`.

### E

**edit** — `edit <file>`
Open the built-in text editor (undo, find/replace, clipboard, Lua syntax
coloring); creates the file if missing. Keys: Ctrl+S save, Ctrl+Q close, Ctrl+F
find, Ctrl+H replace, Ctrl+Z undo, Ctrl+G go-to-line, Ctrl+C/X/V copy/cut/paste.
*See also:* `man edit`, Chapter 4.3.

### F

**fg** — `fg [job]`
Bring a background/stopped job to the foreground. *See also:* `bg`, `ps`.

**find** — `find [path] <name-pattern>`
Search for files by name under a path. *See also:* `grep`, `tree`.

**flash** — `flash <file>` **(admin)**
Write a new EEPROM (BIOS) image. *Danger:* a bad image can stop the machine
booting — keep a known-good EEPROM. *See also:* Chapter 2.

### G

**grep** — `grep <pattern> <file> [file...]`
Print lines matching a pattern. *See also:* `find`, `more`.

### H

**head** — `head [-n N] <file>`
Print the first N lines (default 10). *See also:* `more`, `cat`, `wc`.

**help** — `help [command]`
The install-aware command list, or one-line help for a single command. The
shallowest of the three help depths (`help` → `man` → this Manual). *See also:*
`man`.

**hostname** — `hostname [name]` **(admin to set)**
With no argument, shows the device type + hostname; `hostname <name>` sets the
name (`/etc/hostname`). (v1.4.0 folded the old `device` command in here.)
*See also:* `hw`, `net`.

**hw** — `hw`
List installed hardware and tiers (a quick form of the System Configuration
screen). *See also:* `doctor`, `component`.

### I

**internet** — `internet [status | get <url> | on | off]` **(tier: internet card; on/off admin)**
Internet-card status and a bounded test fetch. `status` (the default) separates
the three reasons access fails, which are three different problems: no card is
installed; the **server** has HTTP disabled for internet cards, which only the
server owner can change; or an admin here ran `internet off`. `get <url>` fetches
a URL and prints the first 20 lines — a check that the card works, not a pager.
`on`/`off` is the machine-wide kill switch (`internet` in `/etc/tos.cfg`) for a
shared box where the card is wanted for one service and not for everybody.
Reaching the network from a *package* additionally requires the `internet`
capability, which is never implied by `component`. Hidden from `help` on a
machine with no card. *See also:* `pkg` (§7.6), `hw`, `config`.

**inventory** — `inventory` (alias `inv`) **(tier: inventory controller / robot)**
List the contents of an attached inventory. *See also:* `redstone`, `robot`.

**intercom** — `intercom [status | cues | say "…" | play <cue> | test <cue> | log [N] | set <k> <v>]` **(add-on; tier: modem)**
The facility announcement system (§8.5). A Computronics tape holds the
recorded voice; `/etc/intercom.cues` tells the Intercom what is on it and
where, one line per announcement — `fuel-low  [0001] "Warning: Reactor fuel
low." [0005]  warn`. `intercom play <cue>` seeks the tape, plays it, stops at
the end position, and broadcasts those same words to every machine willing to
hear them; `intercom test <cue>` plays it locally and tells nobody, which is
how you check the positions really bracket the recording. `intercom say
"<text>"` announces text with no tape at all. Severity (`info` `notice` `warn`
`alert` `critical`) decides whether a receiver just logs it or gets a message
box; a **cooldown** (default 60s) means an alarm storm can't lock an operator
out of their own keyboard. With no subcommand, opens the Intercom tab.
Receiving needs `service start intercom`. *See also:* `man intercom`, `chat`,
`tape`.

### J

**jbod** — `jbod [list | create <mount> <disk...> | destroy <mount>]` **(admin; opt-in)**
Pool several disks into one mount point (capacity = sum of members; a lost
member loses only its own files). **Off by default** — enable with
`bootsettings jbod on` and reboot; until then it's hidden from `help` and the
module isn't loaded. *Errors:* `JBOD is disabled`, `ambiguous address prefix`,
`no writable pool member`. *See also:* `mount`, `df`, `man jbod`.

### K

**kill** — `kill <job>`
Terminate a job by id. *See also:* `ps`, `fg`, `bg`.

### L

**lang** — `lang [<code> | system <code> | dump [path]]`
Show or set the UI language. Catalogs are data files in `/usr/lang`;
`lang dump` writes a translator template. Per-user via your profile,
machine default via `lang system` (admin). *See also:* Chapter 10.2,
`profile`.

**log** — `log [N | clear]` **(clear: admin)**
Show the last N log lines (kernel + services), or clear the log. *See also:*
`doctor`.

**logout** — `logout`
End the current session and return to the login screen. *See also:* `whoami`,
`passwd`.

**ls** — `ls [-l|-a] [dir]`
List a directory. `-l` long form, `-a` include hidden. *Error:* `no such file`.
*See also:* `cd`, `tree`.

**lua** — `lua <code>`
Evaluate a Lua snippet in the session sandbox (Chapter 13.1). *Example:*
`lua print(math.pi)`. *See also:* `run`.

### M

**mail** — `mail [ui | send <to> [subject] [body…] | list | read <n> | delete <n>]` **(add-on; tier: modem)**
Mesh email — addressed, store-and-forward, end-to-end-sealed mail that hops
across trusted relays with no central server (Chapter 8). With **no subcommand**
it opens the inbox as a **persistent tab** (like `chat`): arrows navigate,
**Enter** reads (marks read), **c** composes (recipient / subject / multi-line
body), **r** replies, **d** deletes, **R** refreshes now, and the inbox
refreshes live while the tab is in front; the tab label shows an unread badge
(`Mail(2)`); **Ctrl+Q closes the tab**. The subcommands are the line/scripting
form; `mail ui` opens the full-screen TUI in the CLI shell. Recipients are a
peer addr-prefix, hostname, `user@peer`, or `*` for all trusted peers.

**Mail is an ADD-ON.** The *mesh transport* it rides is part of the base OS
(see `man networking`), but mailboxes are not: install the package from the
Optional Utilities disk with **`pkg install mail`**, then **`service start
mail`** so the machine can *receive* (the service registers the delivery
handler at boot, which is what makes store-and-forward work with nobody logged
in). Without the add-on, `mail` prints an install hint; a TOS box without it
still *relays* mail for its trusted neighbours — relaying is the transport's
job, and relays can't read the sealed payload anyway. *Sending to an unpaired
peer is refused* rather than silently sent in the clear (pair first with `net
pair`); `*` bulletins are plaintext by definition and labelled as such.
*See also:* `chat`, `net`, `pkg`, `service`, `man networking`.

**man** — `man <topic>`
Open the manual page for a command or concept (`/usr/man/<topic>`). The middle
help depth, between `help` and this Manual. *Error:* `no manual entry for <topic>`
— try `help <topic>` or this Manual. *See also:* `help`.

**mem** — `mem`
The memory report: RAM used/total with a usage bar, the RAM tier, swap usage, and
a warning near the ~16 KB danger zone (Chapter 9, `man memory`). *See also:* `hw`,
`monitor`, `doctor`, `optimize`.

**mkdir** — `mkdir <dir>`
Create a directory (parents as needed). *Error:* `already exists`.

**monitor** — `monitor` (alias `top`; also **Ctrl+T**)
Opens the live System Monitor as a **full-screen app tab**: every process (kernel
and user, each given a plain description), the rc.d services (admin+), and
memory/uptime vitals, auto-refreshing in place. Because it's a tab it never
truncates, scrolls like any view, is per-seat, and you can switch to/from it
freely. It is fully interactive: **Enter** switches to a process (or
starts/stops a selected service), **K** kills, **T** suspends/resumes (TSR),
**R** refreshes now, **Ctrl+Q** closes. Rows you lack the privilege to act on
are dimmed (root acts on anything; admin on this seat's processes; everyone
else on their own). **Ctrl+T** opens the same tab from anywhere in the panels
shell; on the CLI shell Ctrl+T falls back to the compact switcher dialog.
*See also:* `ps`, `watch`, `service`.

**more** — `more <file>`
Page through a file one screen at a time. *See also:* `cat`, `head`.

**mount** — `mount [<address> <path>]` **(admin to mount)**
Show mounts, or mount a filesystem component at a path. *See also:* `umount`,
`df`.

**mv** — `mv <src> <dst>`
Move or rename a file/directory. *Errors:* `no such file`, `destination exists`.
*See also:* `cp`.

### N

**net** — `net [scan|peers|trust <addr> [full]|block <addr>|revoke <addr>|send <addr> <msg>]` **(tier: modem; trust: admin)**
The zero-trust networking front end (Chapter 8). With no argument, shows status.
*Example:* `net trust 3f8a1c2d full`. *See also:* `man net`, `ping`, `chat`.

**notify** — `notify <message> [--style info|warn|danger|error] [--title T]`
The intrusive counterpart to `echo` (§4.1a). Raises a DOS-style modal dialog
box on **every seat**, over whatever the operator was doing, instead of a line
in the output area they'll see when they next look down. Also the operator
surface for `kernel.notify`, the facility any program or service posts to when
it needs the operator *now* — the Intercom's announcements ride it. Rate-limited
by a floor no caller can escape (10s per source, 3s of quiet after every
dismissal, 8 queued, 2-minute expiry), so "any program can interrupt you" never
becomes "any program can lock you out". A refused notice still reaches the log.
With no argument, reports what's pending and the current limits. *See also:*
`man notify`, `echo`, `intercom`.

### O

**optimize** — `optimize [show | swap [status|keys|clear|on|off|auto] | buffer <on|off|auto>]` **(set: admin)**
Show or toggle TOS's two performance optimizations. **swap** is the disk-swap
"slow RAM" feature (Chapter 9.4): `optimize swap` (or `status`/`keys`) shows the
live scratch store, `clear` wipes it now, and `on|off|auto` sets the boot toggle
(applies on next boot). **buffer** is the runtime **dirty-cell display buffer**:
it remembers what every screen cell holds and skips the GPU write when a redraw
would change nothing — a large saving for live views like `monitor` and `watch`.
`auto` (default) enables it only with memory headroom; `on` forces it whenever it
fits; `off` always draws directly. `optimize show` reports each optimization's
state and the buffer's session hit rate (cell-draws skipped). (v1.4.0 folded the
old standalone `swap` command in here.) *See also:* `mem`, `monitor`, Chapter 9.4.

### P

**passwd** — `passwd [user]` **(other users: admin)**
Change your password (or another user's, as admin). First-boot password change is
enforced by the kernel. *See also:* `users`.

**ping** — `ping <addr>` **(tier: modem)**
Probe a peer for reachability. *See also:* `net`, `hostname`.

**sudo** — `sudo <command>` | `sudo -s` | `sudo -k` | `sudo setup [admin|root]` |
`sudo off` **(USER+; guests cannot elevate)**
Run a command with elevated privileges using a **separate elevation password**
— distinct from any account's login password, so a non-root user can perform
higher-tier actions **without the root account**. Root configures it once with
`sudo setup admin` (or `sudo setup root` to allow full-root elevation); `sudo
off` disables it. Then `sudo <cmd>` prompts for the elevation password and runs
that one command elevated (up to the configured ceiling, never above); `sudo -s`
opens an elevated shell until `sudo -k` or `logout`. Every attempt is logged.
The elevation raises your **effective tier** for the action; it never gives you
the root *account*. *See also:* `passwd`, `users`, `whoami`.

**pkg** — `pkg <list|search|info <name>|install [name|dir]|uninstall <name>|enable <name>|disable <name>|commands|make-disk <mount>>` **(install/uninstall/enable/disable/make-disk: admin)**
Top-level `install <name>` / `uninstall <name>` are shortcuts for the same.
The package manager — the one way to add or remove add-ons (Chapter 7). `enable`/
`disable` toggle an installed package without removing it. Installs are sandboxed
by the manifest's declared capabilities; the `legacy` cap is never grantable.
With an internet card, `pkg repo add <name> <url>` / `repo list` / `repo remove`
manage remote repositories, `pkg remote` lists what they offer, and `pkg fetch
<name>` downloads and installs one — the configured repo list is the allowlist,
and a fetch runs the ordinary install against a staging directory rather than a
second, network-aware copy of it (§7.6).
*Errors:* `unknown package`, `capability not allowed`, `hash mismatch`. *See
also:* `man pkg`, `man packages`.

**profile** — `profile [name]`
Show or hint the boot profile (minimal/normal/full/diagnostic). The authoritative
editor is `bootsettings`. *See also:* Chapter 2.

**programs** — `programs`
List runnable programs/commands available to you. *See also:* `help`, `pkg list`.

**ps** — `ps [-v]`
A one-shot snapshot of processes — ids, owner, and state (`-v` adds capabilities,
admin+). For a live, interactive view use **`monitor`** (Ctrl+T) or **`watch
ps`**. *See also:* `monitor`, `watch`, `kill`, `fg`, `bg`.

**pwd** — `pwd`
Print the working directory. *See also:* `cd`.

### R

**reboot** — `reboot`
Cleanly restart the machine (writes the clean-shutdown marker first, so the next
boot won't warn of an unsafe shutdown). *See also:* `shutdown`, Chapter 9.

**redstone** — `redstone [...]` (alias `rs`) **(tier: redstone card)**
Read/set redstone signals on the sides of the machine. *See also:* `inventory`,
`robot`.

**robot** — `robot [...]` **(tier: robot)**
Drive an attached robot (move, turn, interact). *See also:* `inventory`,
`redstone`.

**rm** — `rm [-r] [--hard] <path>`
Remove a file, or a directory with `-r`. By default the target is moved to your
per-user **trash** (recover with `trash restore`, manage with `trash`); pass `--hard`
to unlink immediately. System paths (`/tos`, `/etc`, `/var`, `/usr`) always skip
the trash. Both the panels and CLI shells behave this way. *Errors:* `no such
file`, `is a directory` (without `-r`).

**rsh** — `rsh <addr> <command>` **(tier: modem; TRUSTED peer)**
Run a command on a TRUSTED remote machine (Chapter 8). *See also:* `scp`, `ssh`,
`net`.

**run** — `run <file> [args...]`
Execute a Lua script file in the session sandbox with `...` set to the arguments
(Chapter 13.2). *Errors:* `no such file`, plus any runtime error from the script.
*See also:* `lua`, `edit`.

### S

**scp** — `scp <addr> <src> <dst>` **(tier: modem; TRUSTED peer)**
Copy a file to/from a TRUSTED remote machine (Chapter 8). *See also:* `rsh`,
`share`, `net`.

**screen** — `screen [list | next | <index> | res [auto|max|WxH]]`
Manage display seats (`list`/`next`/`<index>` need multiple screens) and the
screen resolution. `screen res` shows current/max/block sizes + policy;
`screen res <auto|max|WxH>` (admin) sets it live and saves it (fixes tiny text on
a tier-3 GPU + large screen). *See also:* `man screen`, Chapter 10.1.

**service** — `service [start|stop|list] <name>` **(start/stop: admin)**
Manage `/etc/rc.d/` services (Chapter 12). *See also:* `cron`.

**settings** — `settings`
Open (or focus) the **Settings app** tab: Appearance (theme, live preview),
Status Bar (widgets), Desktop (login landing), System (admin shortcuts).
*See also:* `theme`, `profile`, `bootsettings`, Chapter 4.4.

**screendump** — `screendump [<path>]`
Capture exactly what's on this seat's screen to a text file (default
`./screen-<uptime>.txt`) — including a garbled or panicked display — for a bug
report. Reads the display buffer when active, else the GPU directly. *See also:*
`crash`, `log`.

**share** — `share [...]` **(tier: modem)**
Front end to the file-share service (Chapter 8). *See also:* `scp`, `net servers`.

**shutdown** — `shutdown`
Cleanly power off (writes the clean-shutdown marker). *See also:* `reboot`,
Chapter 9.

**ssh** — `ssh <addr>` **(tier: modem; TRUSTED peer)**
Open an interactive remote shell on a TRUSTED machine. *See also:* `rsh`, `scp`.

### T

**tail** — `tail <file> [lines]`
Print the last N lines (default 10) — the other half of `head`. Pair it with
`watch` to follow a file as it grows: `watch tail /var/log/tos.log`. *See also:*
`head`, `more`, `watch`, `log`.

**tape** — `tape [...]` **(pkg: tape; tier: tape drive)**
Control a tape drive (play/write/seek), once the tape package is installed. *See
also:* `pkg`, `man packages`.

**tape-menu** — `tape-menu` **(tier: tape drive)**
Open the personal command menu carried on your **identity tape** (a
tape-authenticator keycard — manage it with `tape-auth menu
add|list|remove|passwd|clear <passphrase>`). To add an item, `--` separates the
label from the command — `tape-auth menu add <pass> Diagnostics -- doctor` —
because an unquoted `|` would be read as a shell pipe and run the second half
immediately. The **first** `menu add` on a tape is what SETS that tape's
passphrase; pick one that is not your login password, and change it later with
`tape-auth menu passwd <old> <new>`. Insert the card, enter your passphrase, and your toolbox runs at
your tier — it follows you between machines. (v1.4.0 retired the standalone
`launcher`/`apps` command: the **Desktop** is TOS's menu surface now — built-in
apps, installed package commands, and your `~/.launcher.cfg` entries all appear
there as tiles. The launcher engine still powers the locked guest `kiosk`.)
*See also:* `desktop`, `kiosk`, `menu`, `tape-auth`.

**theme** — `theme [name]` (alias `colors`)
Show or set the color theme; saved per-user to `~/.theme.cfg` (Chapter 10). *See
also:* `tutorial`.

**touch** — `touch <file>`
Create an empty file or update its timestamp.

**tree** — `tree [path]`
Show a directory as an indented tree. *See also:* `ls`, `find`.

**tutorial** — `tutorial`
Launch the interactive new-operator walkthrough. *See also:* this Manual,
Chapter 1.

### U

**umount** — `umount <path>` **(admin)**
Unmount a filesystem. *See also:* `mount`, `df`.

**unalias** — `unalias <name>`
Remove one of your aliases. *See also:* `alias`.

**uptime** — `uptime`
Show how long the machine has been running.

**useradd** — `useradd <name>` **(admin)**
Create a user account (prompts for a password and tier). *See also:* `users`,
`userdel`, `usermod`.

**userdel** — `userdel <name>` **(admin)**
Delete a user account. *See also:* `users`, `useradd`.

**usermod** — `usermod <name> [...]` **(admin)**
Modify a user (tier, lock state). *See also:* `users`, `passwd`.

**users** — `users` **(admin)**
List user accounts and their tiers (Chapter 3). *See also:* `useradd`,
`userdel`, `usermod`, `passwd`.

### V

**verify** — `verify`
The **file-integrity** check: every file in `/tos/system_manifest.lua` is checked
for presence, Lua syntax, and (where declared) its SHA-256 hash. Only problems
print; a clean system shows just the summary. (This checks files on disk, *not*
runtime health — for that, run `doctor`.) *See also:* `doctor`, `deploy`,
Chapters 16 & 17.

### W

**watch** — `watch [seconds] <command ...>`
Open a **live tab** that re-runs a read-only command on a timer (default 1s) — the
self-updating counterpart to running it once. *Examples:* `watch ps`,
`watch 2 df`, `watch net peers`. Press **r** to refresh now, **q**/F4 to close.
Interactive/screen commands (`edit`, `lua`, `monitor`, …) can't be watched. *See
also:* `monitor`, `ps`.

**wc** — `wc <file>`
Count lines/words/characters. *See also:* `head`, `grep`.

**which** — `which <name>`
Show what a command name actually resolves to. Three different things can answer
to one name — a built-in, a command supplied by an installed package, and a
program in `/bin`, `/usr/bin` or `/tos/shell` — and this reports which one wins,
in dispatch order, marking the losers as shadowed. An alias is reported first and
then its expansion is resolved. It calls the shell's own resolver rather than
describing it, so it cannot drift from what actually runs, and it never loads the
package to find out. `which` answers "what will run?"; `why` answers "and why was
I refused?". *See also:* `why`, `alias`, `programs`, `pkg`.

**whoami** — `whoami`
Print the current user and tier. *See also:* `logout`, `users`.

**why** — `why [<command>]`
Explain a "permission denied". With no argument it explains the LAST command this
seat was blocked on, in plain English, with the fix. `why <command>` explains what
that command needs (which tier) and whether your account can run it. *See also:*
`whoami`, `users`.

---

## 15. The Security Model (in one place)

- **Authentication** on every boot path; first-boot password change enforced at
  the kernel layer; reboot-proof exponential backoff; no user/lock enumeration.
- **Sandbox** (capability-based): user programs see only what was granted -
  no ambient `_G`, no raw `computer`/`component`/`io`, no back-door `require` into
  `kernel.*`. The `legacy` cap (full os/io) is opt-in by hand-written caller code
  only and is *never* grantable from a package manifest.
- **securefs** mediates every user-level FS op; raw component filesystem proxies
  are denied to sandboxed code.
- **Network:** zero-trust tiers, per-packet MAC + nonce + epoch/sequence replay
  protection, challenge-response binding trust to possession of the shared secret
  (not just a modem address), and no XOR downgrade on AES-capable receivers.
- **Crypto:** a data card, when present, provides AES (network encryption),
  hardware RNG (salts/tokens/IVs), and one-shot SHA-256 (checksums, integrity
  verify). The *iterated* password KDF and per-packet MACs deliberately run in
  software — in OpenComputers a component call is the costly operation (it can
  sleep the computer a game-tick when the per-tick call budget is spent), so a
  thousands-of-rounds KDF is far faster in pure Lua than calling the card per
  round. A software-only box gets the same KDF plus a documented crypto
  fallback (and a one-time "degraded RNG" warning).
- **Known limits (honest):** the boot chain (`/init.lua`, the manifest,
  `critical.bak`) is loaded as Lua at boot and is not yet cryptographically
  anchored — anyone with write access to those paths (ADMIN+) has code execution
  before login. Treat third-party packages with the usual caution; prefer
  manifests that declare hashes.

## 16. Configuration Files

| File | Purpose |
|------|---------|
| `/etc/boot.cfg` | Boot spectrum: `profile`, `verbosity`, `advanced`, `cpuTier`, `showConfig` (Ch 2) |
| `/etc/tos.cfg` | System config: device profile, hostname, thresholds, `swapMaxKB`, `critBatShutdown`, … |
| `/etc/users.dat` | User DB (admin-read, atomic-written) |
| `/etc/trust.dat` | Network trust DB + shared secrets |
| `/etc/hostname` | Machine hostname |
| `/etc/rc.d/*.lua` | Startup services |
| `/etc/cluster-master.cfg` | Cluster Master tuning (only with `cluster-master` installed) |
| `/etc/cluster-manager.cfg` | Cluster Manager: which Master, worker count (only with `cluster-manager`) |
| `/etc/jbod.cfg` | JBOD pool table (only when `advanced.jbod` is enabled) |
| `~/.theme.cfg` | Per-user saved theme |
| `/var/run/pwrstate` | Clean/unsafe-shutdown dirty bit |
| `/var/swap/` | Disk-swap scratch (volatile) |

## 17. Recovery & Troubleshooting

- **Forgot the root password / locked out:** boot to the emergency shell (still
  requires authentication) or, as a last resort, reflash a recovery `/init.lua`.
  The `root` account never permanently auto-locks (it throttles instead).
- **"Previous shutdown was unsafe":** expected after a power cut; TOS already
  repaired any interrupted critical write at boot. Run `doctor` to review.
- **Won't boot / missing files:** the BIOS POST lists missing critical files;
  `verify` checks the manifest; `critical.bak` and the hardcoded fallback list
  guard the boot file set.
- **A command vanished from `help`:** that's install-aware help — its hardware or
  package isn't present. Check `pkg list` / attach the peripheral.
- **One slow login after upgrading from an early 1.3.1 build:** if an account's
  password was set by the build that ran the KDF on the data card (10000 rounds),
  the *first* verify after this update re-computes that high-round hash once (a
  few seconds to tens of seconds, depending on CPU), then transparently rehashes
  it to the current fast format — every later login is quick. To skip even that
  one-time cost, just reset the password (`passwd`) or recreate the account.

## Appendix A — Selected key codes (OC / LWJGL)

`Up` 200, `Down` 208, `Left` 203, `Right` 205, `Enter` 28, `Esc` 1, `Space`
char 32, **`Delete` 211** (Boot Settings), Shift 42/54.

## Appendix B — Cluster (advanced add-on)

Distributed compute across several machines. A **Master** holds the cluster's
state and decides who runs what; **Managers** register with it and do the work.
Optionally, OpenOS **worker** boxes can hang off a Manager.

**Setting one up is one command per machine.** Run it as root:

```
cluster-setup
```

It ships in the base image — it is there *before* either cluster package is,
because "which one does this machine need?" is the first thing it answers. It
picks the role with you, installs the right package from the Optional
Utilities disk, writes the config, starts the service, and walks you through
pairing. `cluster-setup explain` describes the parts and changes nothing.

| Machine | Package | Service | How many |
|---|---|---|---|
| Control | `cluster-master` | `clusterd` | exactly one |
| Compute | `cluster-manager` | `cluster-manager` | as many as you like |

You never copy files by hand. A second Master would accept registrations of
its own and silently split the cluster in two, which is why there is one.

**Pairing.** Do the Master first: at the end of setup it prints its full modem
address and a pairing code. Run `cluster-setup` on each Manager and give it
both. (It rejects a shortened address — every TOS listing abbreviates to 8
characters, so pasting one back is the easy mistake, and a config built from
one can never connect.) Watch them arrive with `cluster pair status`; list
them with `cluster managers`. The window lasts five minutes; `cluster pair
start` opens another.

Afterwards: `cluster status`, `cluster managers`, `cluster watch` on the
Master; `cluster-manager status` on a Manager.

**OpenOS workers** are the one part that needs manual copying, because they
run OpenOS and TOS's package manager has no reach into it — and they're
entirely optional, since a Manager runs work inline perfectly well. See
`TOS-Extras/cluster/installer/README.md`.

The protocol uses TOS's trust + encryption, with a required `shared_secret`
(default-deny) on the worker bridge. Full details in
`TOS-Extras/cluster/cluster-protocol-spec-draft.md`.

---

*This Manual tracks TOS and will grow with it. Corrections and additions welcome.
For a quick reminder while you work, use `help` inside TOS; come back here when
you want the full story.*
