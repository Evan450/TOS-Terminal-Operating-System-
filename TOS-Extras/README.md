# TOS Extras

Optional add-ons for TOS: programs, games, drivers and services that run on TOS but are not part of the OS. None of them is installed with TOS. They ship as the **Optional Utilities** pack, a pick-and-choose set modelled on MS-DOS 6.22's Supplemental Utilities Disk, and each is its own package, so you can take any subset.

## Installing them

On a TOS machine, as admin, insert the Optional Utilities floppy and run `pkg install`. It opens a checkbox picker grouped by category: tick what you want and it installs the lot in one pass. `pkg install <name>` installs one add-on by name. With an internet card, `pkg fetch <name>` gets one from a configured repository instead (TOS manual, §7.9).

The service packages (`mail`, `intercom` and the cluster) and `selftest` need **root**, not just admin: a service runs at boot outside the package sandbox, and a self-test check runs inside the kernel.

The signed pack is published on the repository's `optional-utilities` branch. This directory is the source, and the pack can trail it until its next signing; the picker shows the version of each package it offers.

## The add-ons

Grouped as the picker groups them. Each name links to that add-on's README: what it does, how to use it, and where its files go.

**Productivity**

| Add-on | Command | What it is |
|---|---|---|
| [calc](modules/calc/README.md) | `calc` | A spreadsheet: formulas, ranges, CSV export, and nothing in a cell can ever run as code. |
| [write](modules/write/README.md) | `write` | A word processor that shows where the printed page breaks as you type, and what it will cost in paper and ink. Brings `printer` with it. |

**Games**

| Add-on | Command | What it is |
|---|---|---|
| [snake](modules/snake/README.md) | `snake` | Classic snake, with a high-score board for each player. |
| [tetris](modules/tetris/README.md) | `tetris` | Classic Tetris, with levels and a high-score table for each player. |
| [ttt](modules/ttt/README.md) | `ttt` | Tic-tac-toe against a machine that cannot lose, or two players at one keyboard. |

**Drivers**

| Add-on | Command | What it is |
|---|---|---|
| [mouse](modules/mouse/README.md) | `mousetest` | Makes the TOS shell clickable and scrollable, and gives programs `require("mouse")`. |
| [printer](modules/printer/README.md) | `printer` | Prints on PC-Logix's OpenPrinter, checking the paper and ink before a job starts. |

**Storage**

| Add-on | Command | What it is |
|---|---|---|
| [blockfs](modules/blockfs/README.md) | through `drive` | TBFS, a real filesystem for unmanaged drives, which TOS can even boot from. |
| [tape](modules/tape/README.md) | `tape` | Everything a Computronics tape drive does: file archives, audio, raw bytes and encryption. |

**Security**

| Add-on | Command | What it is |
|---|---|---|
| [tape-authenticator](modules/tape-authenticator/README.md) | `tape-auth` | A tape as an unforgeable keycard, carrying a private log and a personal command menu. |

**Network**

| Add-on | Command | What it is |
|---|---|---|
| [mail](modules/mail/README.md) | `mail` | Store-and-forward email between TOS machines, sealed end to end, with no server. Root. |
| [intercom](modules/intercom/README.md) | `intercom` | Facility announcements: a recorded message plays from tape, and the same words go out over the network. Root. |
| [cluster](cluster/README.md) | `cluster-setup` | Spreads jobs across machines: one Master, any number of Managers, and optional OpenOS workers. Root. Its `cluster` command does not start at present; see its README. |

**Control and automation**

| Add-on | Command | What it is |
|---|---|---|
| [rc-pilot](modules/rc-pilot/README.md) | `rc` | Fly a robot or drone from the keyboard, with every keystroke signed. The robot cannot yet tell you its address; see its README. |
| [stock](modules/stock/README.md) | `stock` | Totals every item in the chests around a transposer, and warns when something runs low. |

**Development**

| Add-on | Command | What it is |
|---|---|---|
| [selftest](modules/selftest/README.md) | `selftest` | The boot self-test battery: checks that run inside the kernel on real hardware, for testing what you add to TOS. Root. |

### Here, but not on the pack

| Path | What it is |
|---|---|
| [rbmk/](rbmk/README.md) | `rbmk-control` 0.2.0, a safety supervisor and operator panel for HBM's RBMK reactors. Held back until its component names are checked against the mod in game. |
| [cluster/storage-skeleton/](cluster/README.md) | `cluster-storage` 0.1.0, an early storage node for the cluster. Held back while its spec is a draft. |
| [pane-ui/](pane-ui/README.md) | PaneUI, the TOS look and file manager for OpenOS machines. One file, copied by hand rather than installed with `pkg`. |
| [robot/](robot/README.md) | The program on the robot's own chip for `rc-pilot`. The rc-pilot package ships it ready to burn. |
| [web/](web/README.md) | A text-mode web browser and a fetch proxy between TOS machines. Design only, no code yet. |

A package below version 1.0.0 is not finished, so it stays off the pack: the builder keeps a list of them and prints each one it skips, and why.

## Building the pack

`build/` holds the builder. Run `build-disk.ps1` from PowerShell, `build-disk.cmd` from cmd.exe or `build-disk.sh` from a POSIX shell: it finds every add-on with a `package.lua` and lays the pack out in `dist/optional-utilities/`, split across as many 512 KB floppies as the set needs (two, today). `--install <dir>` copies the result onto an OpenComputers floppy folder. [build/README.md](build/README.md) explains the packing, the set manifest each disk carries, and signing.

`dist/` is build output: regenerated by every build and safe to delete.

Every add-on's tests run with the OS's own: `python run_tests.py` in the TOS source.

## Conventions

Each top-level entry under `TOS-Extras/` should be a self-contained installable unit, so the picker can offer it as a separate checkbox. Don't introduce cross-Extras dependencies without flagging it: the user should be able to install any subset without surprise. This is why the games ship as **three standalone packages** (`snake`, `ttt`, `tetris`) rather than one bundle: you can take Snake without Tic-Tac-Toe.

**Flagged cross-Extras dependency: `write` → `printer`.** The only hard one in the set, and it is here rather than merged because the two are genuinely separable in use: plenty of machines want the driver and the `printer` command with no word processor anywhere near them. The reverse is not true — the word processor's whole point is the page, the page model lives in the driver's `printerfmt.lua`, and a `write` that shipped its own copy would be two definitions of "how tall is a page" drifting apart. The picker auto-selects `printer` alongside it, marks it `[+]`, and counts it in the install set, so nothing installs behind your back. `requires` also means the packer keeps them on the same floppy.

**Categories.** A manifest may declare `category = "..."` (games, productivity, network, storage, security, drivers, control, or your own). The installer groups the pick-list by category — so related packages browse together while each stays independently installable. Uncategorised packages fall into "misc" / Other. Keep a package's *scope* to one program; use the category to relate it to its neighbours.

When adding a new add-on, give it its own subdirectory, a clear entry point, and a `README.md` saying what it is, how to install and use it, and where its files go. Add a row for it to the catalogue above.
