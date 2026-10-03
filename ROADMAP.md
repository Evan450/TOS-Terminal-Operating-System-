# TOS Roadmap

What is actually open. Generated from our working notes, which are not published — the notes interleave open work with a long done-history and occasional machine-local paths, so this is the extracted, scrubbed view of it. Do not hand-edit; raise an item in an issue or pull request instead.

**90 open items.** This is the honest list, including the things deliberately *not* done and the reasons why — those entries are often the most useful ones to read before proposing a change.

| Status | Count | Meaning |
|---|---:|---|
| Open bug | 2 | Known broken. Fixing one of these is the most valuable thing you can do. |
| In progress | 2 | Started, unfinished. Ask before duplicating the work. |
| Planned | 66 | Planned or under investigation. Most contributions belong here. |
| Idea / far future | 20 | Idea, no commitment. Discuss before building. |

**By area:** [Testing in the game](#testing-in-the-game) (25) · [Add-ons](#add-ons) (4) · [Packages](#packages) (13) · [Networking](#networking) (8) · [Security and accounts](#security-and-accounts) (8) · [Boot, memory and the kernel](#boot-memory-and-the-kernel) (15) · [Files and storage](#files-and-storage) (4) · [Shell and interface](#shell-and-interface) (9) · [The project](#the-project) (4)

The *Testing in the game* items need a real OpenComputers machine to check — the off-box suite runs on stock Lua and cannot see that class of bug. Many can now be run without Minecraft on the headless machine (`build/headless-session.py`); the rest are good contributions if you play the mod.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request.

## Testing in the game

### In-emulator boot smoke test, in CI

*In progress* · from the round *From the OCOS survey (2026-08-10)*

IN-EMULATOR BOOT SMOKE TEST, in CI. The one class of failure our suite structurally cannot see. We have hundreds of tests and every one is off-box pure Lua: nothing in them catches "the kernel does not actually boot on a T1." The EMULATOR CHECK notes scattered through this file are that gap showing — they're manual, so they're done when someone remembers.

- Shape: a boot-time battery loaded ONLY when a marker file is present (so its bytecode never bloats a production boot), running checks, then shutting the machine down with an exit code CI can read. Distinguish pass / fail / STALLED — a hung boot is the failure mode that matters most and it isn't a nonzero exit, it's no exit at all.
- ocvm or Ocelot as the runner; both already boot us.
- \[\~\] BUILT 2026-08-21, shape exactly as specified above. kernel/selftest.lua is gated on /etc/selftest.on EXISTING, and the require sits INSIDE the gate, so a production boot never loads it. Checks live on a test disk (TOS-Extras/selftest/checks) and are discovered from any mounted /mnt/&lt;label&gt;/selftest/, so nothing ships in the base image but the dormant runner.
- STALL detection works as the note demanded. Each check writes `RUN <name>` and flushes BEFORE its body runs, so a wedged machine leaves a file whose last line names the culprit and which has no `SELFTEST END`. Results append line-by-line for that reason -- a buffered report is precisely the report a hang does not give you.
- No exit code needed: results go to /var/selftest.log, beside kernel.log, which on Ocelot and ocvm is an ordinary host directory. `shutdown=true` in the marker powers the machine off for CI.
- Each check runs with package.loaded snapshotted and restored, because a check that stubs kernel.fs the way the off-box tests freely do would otherwise break the machine it is running on.
- REMAINING: wire it to CI. Nine checks now (10 through 90); see the triage note below for what is left of the \~15 "Emulator checklist" items and why most of what remains is not portable into this shape. 2026-10-02: the unattended half is done -- `python tos.py selftest` boots a fresh headless machine (THE HEADLESS BOOT TEST) and exits 0/2/1. What is left is a CI host to run it on, and there is none: the monorepo has no remote, and a hosted runner on the public repo would have to fetch Ocelot's jar each run. Sixteen checks now.
- First four checks: boot invariants, the GPU colour cache after a scroll (the status-bar-goes-black bug), how big an input this machine can actually hash (the sha256 stack overflow, measured on OC's Lua rather than a desktop's), and a filesystem round trip that audits what our mocks claim list()/writeFileAtomic do.
- Three more followed: SRM baseline/scan/repair against real files and real crypto (50), the capability sandbox read -- no raw component/computer, no real \_G, fs.read alone does not expose a writer (60) -- and screen truth: does the glass hold what we drew, on a real GPU, including the forwarded-draw and two-proxies-one-screen cases behind the status-bar-goes-black and selection-fragment bugs (70).
- \[\~\] TRIAGED 2026-08-28: read all 15 "Emulator checklist" items and sorted every bullet into one of four bins -- single-machine-automatable, needs specific hardware (a printer, a live internet card + server, an rbmk block), needs a second machine/seat, or is inherently an eyeball check (timing, layout, "does it look right"). Most of the 15 are the LATTER three, which is exactly why they were still open: they were never a battery's job. Ported the two automatable ones found:
- SIGNED MANIFESTS round (L957): 80-pkg-signing.lua. Real ed25519 + the real /etc/pkg\_trust.cfg write path through securefs -- the off-box test mocks the disk and never exercises that ACL at all. Hand-edit one byte -&gt; INVALID with no override; pkg.\_signGate's require-signature refusal names the setting and --allow-unsigned still works; trust add/remove round- trips through the real store. Snapshots and restores the operator's real policy either way, including on the throw path -- this must never be the round that leaves a stranger's key trusted.
- INTERNET CARD round (L1793): 90-internet-absence.lua. The no-card path and the kill switch, both provable without a live card or server: status()/available() agree and get() fails clean (no throw) when absent; config.internet=false is honoured and the reason names the switch, not the card. Never calls config.save(), so the toggle never reaches disk.

Not portable into this shape, for the record so it is not

re-litigated: PRINTER round (needs real OpenPrinter), STOCK

add-on (needs a real transposer/chest world), most of

INTERNET CARD (needs a live card + server), CLUSTER SETUP

and INTERCOM (need a second machine/seat), NOTIFY's cross-

seat delivery (needs two seats). CLI PARITY, SHELL GAPS,

the PICKER rounds, PKG COMPLETENESS and MULTI-DISK are

mostly shell/session state that assumes an interactive

shell already running -- the battery runs BEFORE the TUI

comes up, so there is no shell here to drive, and their

automatable pieces (alias engine, `which` ordering, PATH

security, pkg conflict/upgrade logic) are already covered

off-box against fakes. PKG COMPLETENESS's "real package

installs and runs" and the PICKER rounds' install flags

are deliberately NOT done here either way: 60-sandbox.lua's

own header already draws this line -- a battery that

installs software on the machine it is auditing is a

different and much worse tool.

### Ocelot check for slice 1: install a package whose library is on a second floppy

*Planned* · from the round *Federated package repos (2026-09-27)*

OCELOT CHECK FOR SLICE 1: install a package whose library is on a SECOND floppy; `pkg upgrade` against a disk carrying a stranger- signed copy (refused, old version intact); an install refused for a version contradiction. And TIME the signed upgrade on a T1: it now verifies Ed25519 twice (before removal, and in install against the bytes install reads).

### Ocelot check for the Keller import: a round through sync-emulator.py

*Planned* · from the round *The Keller import, and the battery's first round (2026-09-25)*

OCELOT CHECK FOR THE KELLER IMPORT: a round through sync-emulator.py (it now creates etc/selftest.on, since a floppy alone no longer arms the battery); installing several packages from media (it should no longer repaint the shell between prompts); and sudo's "try again in Ns" after wrong passwords.

The first of the three is done: two rounds ran through the new arming (etc/selftest.on made by sync-emulator.py) on 2026-09-25.

### Ocelot check for the Fermi import

*Planned* · from the round *The Fermi import: a cloud session's 15 fixes (2026-09-23)*

OCELOT CHECK FOR THE FERMI IMPORT. Two things off-box tests cannot settle. (1) H-06's per-seat cursor: two seats, each running an OpenOS program that writes and reads a line; watch the status bar, since that is where this file regresses. (2) The sealed-traffic gate: a peer with encryptComms OFF talking to one that has it ON and holds a secret for it now has its unsealed packets dropped, with a log line, where they used to be accepted.

The battery now covers what one machine can (selftest 91-95, 2026-09-23): H-03 on a real keyboard; term.read driven through a coroutine against the real GPU, plus what isyieldable() answers in kernel context; beep pauses, the cooldown and the 50 ms floor, timed; rename-over-existing on the host disk; UTF-8 tokens painted and read back. Each was run off-box against the old tree and fails there, except 94, which is a host-behaviour check. Both items above still need hardware this workspace lacks: a second seat, and a second computer.

FIRST ROUND 2026-09-25: 102 pass, 1 fail, 2 skip. 91, 93, 94 and 95 pass on hardware; 93 confirms a 0.3 s beep holds the machine, the premise the cooldown rests on. The one failure was 92's, and it was real: see COMPONENT METHODS ARE CALLABLE TABLES below. isyieldable()'s answer was lost to the report format (fixed by t.note), so it is still to be read at the next round.

SECOND ROUND 2026-09-25: 105 pass, 0 fail, 2 skip, on the rebuilt release. isyieldable() in kernel context: TRUE. See NET.WAITFOR COULD ONLY TIME OUT FROM KERNEL CONTEXT, above.

### Next real-minecraft round

*Planned* · from the round *Real Minecraft round (2026-08-11)*

NEXT REAL-MINECRAFT ROUND — the point of these four is that they were all reachable in one sitting, so the checklist is worth more than more off-box tests:

- attach a printer and run the whole printer/write path now that the cap actually arrives
- `stock` with a transposer, which by the above analysis has NEVER worked against real hardware
- `redstone`/`robot`/`inventory` from a shell, same
- boot from a read-only disk on purpose and confirm the banner, `df` and `doctor` all say so
- a T1 (192K) box: type `reboot` under memory pressure and confirm it now explains itself
- THE TWO-FLOPPY FLOW END TO END, which has never once run correctly: insert disk 1, confirm disk 2's packages are listed and dimmed with "On disk 2 (not inserted)", tick one, install, swap when asked, confirm it finishes in ONE run. Then the same again pressing U at the prompt and confirm the already-installed packages are really gone.
- check the boot banner's RAM line against `mem` — they read from the same place now and must agree
- THE EXIT KEYS, on every full-screen program: open `write`, `calc`, `stock`, `snake`, `ttt`, `tetris`, the picker and `rc-pilot` and confirm each one can actually be left WITHOUT touching Esc. This is the check that would have caught #7 and it takes two minutes.
- press Esc in one of them anyway and confirm the expected thing happens: the Minecraft screen closes and the program is still there when you re-open it. That is not a bug any more, it is the documented behaviour — but it is worth seeing once.
- `keys list`, then `keys set quit F4`, then open ttt, calc, write and stock in turn and confirm F4 closes ALL of them and ^Q no longer does. That single sequence is the whole feature; if one program ignores it, that program is still hard-coding a scancode.
- `keys set quit ^B` must be REFUSED and say why
- `keys reset`, then confirm ^Q works everywhere again
- `menu show`, then `menu hide "Flash EEPROM"`, then `menu reset`; then the same with --system as root and as a non-admin (the second must be refused by securefs)
- put deliberate junk in \~/.menu.cfg and confirm the bar still draws

### Emulator checklist - the RBMK SKALA panel (Extras, v0.2.0)

*Planned* · from the round *Signed manifests round (2026-08-11)*

Emulator checklist - the RBMK SKALA panel (Extras, v0.2.0). NOTE: all of this is blocked behind rbmk/Plan.md open question #1 -- the console's real method names -- which only an in-world survey can answer. Do the survey FIRST; everything below assumes `rbmk survey` reports `usable: YES`.

- `rbmk survey` against a real HBM console: does anything bind to `columns`? If nothing does, the panel is scalars-only and the core map never appears. That is a supported outcome, and the point of this check is to find out WHICH world we are in.
- `rbmk skala` on a tier-3 screen: 15x15 cells must line up with the column ruler. A cell that renders 5 characters shifts its whole row -- the off-box tests pin the formatter, but only a GPU proves the ALIGNMENT.
- the same at 80x25: the rail should be gone and the numbers should have survived (layout drops the rail before the digits, deliberately). Check the header still names the selected parameter, since that is the only place it appears without a rail.
- a screen too small for the core map: must print the SIZE IT NEEDS, not "too small", and still show the scalar readings.
- N/T/X/K/G swap the parameter; arrows move the inspection cursor and the status line follows it; TAB cycles the pages; Q leaves and GIVES THE SCREEN BACK.
- `rbmk skala --wall` on a multi-seat box: each seat shows a DIFFERENT page, and seats keep their identity across a reboot (they are sorted for that reason). Confirm plain `rbmk skala` leaves the other seats alone -- that is the whole reason --wall is opt-in.
- THE OVERRIDE: drive the core to a scram and confirm every unpinned pane switches to the alarm page, a pinned one does not, and a mere WARNING leaves the wall alone. Then pull the controller's modem and confirm every pane goes STALE.
- the OpenOS satellite: rbmk-display.lua on a second machine must render the same picture. Then give it MORE SCREENS THAN GPUs and confirm the time-slicing works and does not flicker or reset resolutions.
- `mapInterval`: watch for per-tick component-budget warnings on a real console. The map read is throttled separately from the safety poll precisely because this is unknown; if a real `getColumnData` is slow, this is the knob.
- colour on a TIER-2 GPU: the bands were chosen to survive 16 colours, unverified in-world.
- off-box tests cover the arithmetic, the wire and the painted CELL CONTENTS (against a fake display that models state); what needs a GPU is alignment, colour on real hardware, and the multi-seat/multi-GPU behaviour.

### Emulator checklist - editor horizontal scrolling

*Planned* · from the round *Signed manifests round (2026-08-11)*

Emulator checklist - editor horizontal scrolling:

- open a file with a line longer than the screen; typing past the right edge must scroll, and the cursor must stay visible (it used to vanish and look like a freeze)
- the "&lt;" and "&gt;" edge markers appear only when there is more text that way, and do not flicker while typing
- a .lua file still highlights correctly once scrolled: a string literal spanning the left edge must not turn everything after it into code-coloured text
- select across a scrolled region and confirm the highlight lands on the characters it claims
- resize the screen narrower with the cursor near the right edge; the next repaint must re-anchor the window
- off-box tests cover the ARITHMETIC only; drawing needs a real GPU

### Emulator checklist - confirmTyped's interactive loop

*Planned* · from the round *Signed manifests round (2026-08-11)*

Emulator checklist - confirmTyped's interactive loop:

- the box draws with the same frame/shadow as every other dialog (it calls drawDialog), at 80x25 and on a resized screen; the line COUNT is constant in both matched and unmatched states so it must not resize while typing
- typing the word letter by letter, backspacing, and pasting it via the clipboard signal all reach Confirm
- Confirm is inert until the word matches: clicking it moves focus rather than firing, Enter on it does nothing
- Esc and ^Q both cancel; Cancel is the FIRST button, so a click-through lands on it
- off-box tests cover the contract around this loop, not the loop -- it needs a real screen and signal stream

### Emulator checklist — key derivation, added with KDF v2

*Planned* · from the round *Signed manifests round (2026-08-11)*

Emulator checklist — key DERIVATION, added with KDF v2:

- TIME IT. `pkg trust key <label>` and `pkg sign` on a T1 and a T3. v2 raised the round count 512 -&gt; 4096, and 4096 rounds of SHA-512 is 0.13 s natively; the on-box figure is the one that decides whether this is usable, and off-box tests cannot give it.
- confirm the 5-second watchdog does NOT fire mid-derive. The loop yields every 256 rounds (16 yields); if a seat still stalls, lower that interval rather than the round count — the rounds are the point.
- derive the SAME label twice on two machines and confirm the key matches, and a different label gives a different one. This is what makes the salt safe to require.

### Emulator checklist: Signed manifests round

*Planned* · from the round *Signed manifests round (2026-08-11)*

Emulator checklist:

- TIME IT. `pkg verify-sig` on a signed floppy, on a T1 and on a T3. This is the number off-box tests cannot give and the one that decides whether the cooperative yields are frequent enough. If a seat visibly stalls, lower the yield interval in fePow/ptMul.
- confirm the box does NOT hit OC's 5-second watchdog mid-verify, and that a second seat stays responsive
- a T1 (192K): confirm requiring ed25519 does not OOM. This is the real risk — it is \~550 lines plus the bignum, loaded on top of an install already in flight. If it does, the fix is to verify BEFORE the install allocates, not to shrink the module.
- `pkg trust add` a key, reboot, confirm it persisted and that the package now reads trusted
- hand-edit one byte of an installed package's manifest on a signed disk and confirm the refusal names tampering
- `pkg trust require on` then insert an unsigned disk: refusal must name the setting, and --allow-unsigned must still work
- `pkg sign` on-box, then verify from a DIFFERENT machine that trusts the key (this is the interop claim)

### Emulator checklist (needs OpenPrinter installed): Printer + word processor round

*Planned* · from the round *Printer + word processor round (2026-08-11)*

Emulator checklist (needs OpenPrinter installed):

- no printer at all: `printer` says so; `write` still opens, paginates and saves, and the rail says \[estimated widths\]
- with a printer: rail must flip to \[printer widths\], and the two must AGREE on where a long paragraph breaks (this is the one thing off-box tests cannot prove — if they disagree, the transcribed CharacterWidth table is wrong and printerfmt's W table is what to fix)
- `printer test`: the row of #s must reach the right margin and NOT be clipped. A short row means our measure and the printer's disagree.
- empty the paper slot -&gt; a 3-page job must be REFUSED with the shortfall named, and print NOTHING
- pull the paper mid-job -&gt; the error must report how many pages already came out, and they must be there
- an all-black document must leave the colour cartridge untouched (read the level before and after)
- one `.color` line: colour level drops by exactly 1
- a CENTRED black line still costs a colour unit (the alignment arg sits after the colour) — confirm the cost line predicted it rather than surprising you
- `printer scan` on a page printed by TOS -&gt; round-trips
- a 1.7-era printer if one is available: width/maxWidth absent, `printer` must say "older build: no width,..." and still print
- `write` a 25-line document: the page rule must appear between lines 20 and 21, and F5 page view must agree
- put `.title` at the top and confirm the rule does NOT move (the directive prints nothing; this is the drift regression the unit tests pin)
- print from `write` (F3) and from `printer file` on the same document -&gt; byte-identical pages

### Emulator checklist: From the Cynosure 2 survey

*Planned* · from the round *From the Cynosure 2 survey (2026-08-10)*

Emulator checklist:

- `cli` from the TUI, `tui` back, several times: confirm no state is lost and the seat never ends up in neither
- F10 -&gt; \[4\] CLI Mode, and the File menu's Quit -&gt; \[4\]: both must reach the same place
- boot with ui=cli and confirm the panels tree is NOT parsed (watch free RAM at the prompt vs a TUI login)
- a T1 (192K) box: the whole point. Type `ls`, then `mem`, then something from admin (`useradd`) and watch memory step down as categories load. If admin.lua cannot load at 192K the OOM path in commands.lua should SAY so rather than reading as "unknown command".
- run a package fullscreen program (tetris/calc/stock) FROM the CLI and confirm the seat comes back cleanly
- `sudo -s` in the CLI: prompt must show \[sudo\], and `tui` must NOT carry the elevation across
- a pipeline and a redirect at the CLI prompt (`ls | grep x`, `ps > /tmp/p`) — these never worked in the old CLI
- break shell/panels/init.lua on purpose and confirm the seat lands in a WORKING CLI, not a dead one

### Emulator checklist: Stock add-on

*Planned* · from the round *Stock add-on (2026-08-04)*

Emulator checklist:

- transposer + 2 chests: `stock sides` lists both; `stock` totals across them and WHERE names both sides
- put the same item in both chests, confirm ONE row
- rename an item on an anvil, confirm it still merges
- W a threshold as root -&gt; persists across a reboot; as a plain USER -&gt; refused out loud, not silently
- empty the watched chest entirely -&gt; the row must still be there, at 0, red, at the top
- L toggles low-only; / filters by both label and mod id
- ^B backgrounds it and the chip comes back with fresh numbers (drowsy, rescans on its 10s timer)
- a BIG inventory (drawers/barrel with many slots): confirm the getAllStacks fast path doesn't stall the seat, and that a component WITHOUT getAllStacks still works

### Emulator checklist (needs a card and a server with HTTP on): Internet card + remote pkg round

*Planned* · from the round *Internet card + remote pkg round (2026-08-04)*

Emulator checklist (needs a card AND a server with HTTP on):

- no card: `internet` says so; `pkg fetch x` fails cleanly
- card with server HTTP off: status must blame the SERVER, not read as "no card"
- `internet off` then `internet get <url>` -&gt; refused; `internet on` -&gt; works
- `pkg repo add oc <url>` -&gt; `pkg remote` lists packages
- `pkg fetch <name>` on a hashless repo must REFUSE, then work with --allow-unverified
- confirm /var/pkg/remote is EMPTY afterwards (both on success and after a deliberate failure)
- a package whose index names ../.. must be refused and must write nothing
- pull the card mid-download; confirm no .part is left and no half-installed package
- a T1 (192K) box: fetch something near the 128K file cap and confirm it does not OOM (this is the one the off-box tests genuinely cannot prove)

### Emulator checklist: Shell gaps + real OPPM round

*Planned* · from the round *Shell gaps + real OPPM round (2026-08-04)*

Emulator checklist:

- `tail /var/log/tos.log`, then `watch tail /var/log/tos.log`
- `alias ll ls -l` then `ll` in the SAME session (no re-login); `alias ls "ls -a"` then `ls` must not hang; `alias` lists, `unalias ll` removes; log out and back in and confirm it persisted
- a USER-tier account: `alias x usermod` then `x` must still be refused (aliases carry no privilege)
- `which ls` (built-in), `which tetris` with the package installed, `which share` (/usr/bin); install a package whose command shadows nothing and check the ordering
- `which` on a package command must NOT start the program
- put a REAL OPPM repo checkout on a floppy (programs.cfg at the root, sources under master/&lt;name&gt;/) and install one package from it; confirm files land where the index said and that `pkg info` shows origin openos with a dependency carrying no bogus version
- a package whose destination is //etc must be REFUSED
- PATH=/tmp with a planted /tmp/foo.lua: `foo` must not run

### Emulator checklist: Picker QoL round

*Planned* · from the round *Picker QoL round (2026-07-29)*

Emulator checklist:

- G on a category, then G again; check the counts rail
- / then type; confirm the list narrows live and the rail shows "N of M match"
- filter + A + Enter installs only the matches
- Esc with a filter clears it; Esc with none quits

### Emulator checklist: Pkg completeness round

*Planned* · from the round *Pkg completeness round (2026-07-29)*

Emulator checklist:

- build a v2 of an add-on, `pkg outdated`, `pkg upgrade`
- confirm a service keeps enabled/disabled across upgrade and that stop/start picks up the new code
- put a real OPPM/loot-disk program on a floppy and check it installs AND runs (this is the one off-box tests cannot really prove — they stub the sandbox)
- two packages shipping the same path: confirm the refusal

### Emulator checklist: Picker off the floppy round

*Planned* · from the round *Picker off the floppy round (2026-07-29)*

Emulator checklist:

- `pkg install` with a disk in: picker opens from the BASE image (no install.lua on the floppy at all)
- the swap prompt should now be a framed modal listing the packages waiting on the next disk
- `pkg install --all --dry-run` then `--all --yes`
- insert a disk built by `pkg make-disk` and confirm it is still announced as an "Optional Utilities disk"

### Emulator checklist: Multi-disk round

*Planned* · from the round *Multi-disk round (2026-07-29)*

Emulator checklist:

- boot with ONLY disk2 inserted: confirm disk1's packages are listed, dimmed, and say "On disk 1 (not inserted)"
- select across both disks, install, swap when asked, confirm it finishes in ONE run
- same again but press U at the prompt: confirm the already-installed packages are really gone afterwards
- confirm tape + tape-authenticator land on one disk

### Emulator checklist: Installer + worker round

*Planned* · from the round *Installer + worker round (2026-07-28)*

Emulator checklist:

- picker on an 80x25 and on a 50x16 screen (two-pane vs fallback); check the panel doesn't overrun the divider
- select `drive` with blockfs NOT installed: confirm \[+\] appears on blockfs and both install
- insert only disk2 and check the From field + the "not on any inserted disk" warning make it obvious
- run cluster-worker-setup ON TOS and confirm the refusal actually names cluster-setup

### Emulator checklist: Cluster setup round

*Planned* · from the round *Cluster setup round (2026-07-28)*

Emulator checklist:

- `cluster-setup` on a box with NOTHING installed: does the explain screen actually make the choice obvious?
- full Master-&gt;Manager pairing on two machines using only what the wizard prints (this is the real test of the address fix)
- answer "no" to boot-start, reboot, confirm the service is NOT running; then `service start clusterd`, reboot, confirm it IS

### Emulator checklist: Notify round

*Planned* · from the round *Notify round (2026-07-28)*

Emulator checklist:

- `notify "test"` from one seat, confirm the box lands on BOTH seats and that answering on one clears both
- hammer `notify` and confirm the 3s quiet window really gives the keyboard back
- confirm a dialog raised while a fullscreen program is backgrounded does NOT paint over it (suspendIdleDraw)

### Emulator checklist for this round: Intercom round

*Planned* · from the round *Intercom round (2026-07-28)*

Emulator checklist for this round:

- record a real tape, note the positions, catalog them, and check `intercom test` brackets the right recording (this is the one thing off-box tests CANNOT prove — 4096 B/s is the assumed rate; if the stop lands early or late, set bytesPerSecond from what you measure)
- two machines: `intercom play` on one, confirm the other shows the chat line and (at alert+) the message box
- hammer alerts and confirm the cooldown keeps the keyboard usable
- `@group:` to 3 peers with one powered off; confirm it says "delivered to 2 of 3" and names the missing one

### Emulator checklist for this round: SRM round

*Planned* · from the round *SRM round (2026-07-28)*

Emulator checklist for this round:

- fail a boot on purpose (rename /tos/kernel/init.lua) and confirm K4 on screen + 4 short beeps, then that the next good boot explains and clears it
- `srm baseline --full` on a fresh install, check the disk cost report is honest, then `srm scan` after an edit
- `srm repair --restore` puts the edited file back
- confirm the store survives a reboot and `srm status` is instant on a slow disk

### Run a verification round in real Minecraft OpenComputers

*Planned* · from the round *Planned (near future)*

Run a verification round in REAL Minecraft OpenComputers: the Ocelot emulator has been running at \~6 TPS (cause unknown), which makes testing sluggish and may distort timing-sensitive behaviour (waits, live refresh, cooperative yields). Real-MC results are the ground truth anyway.

## Add-ons

### The cluster CLIs cannot run in the sandbox they are given

*Open bug* · from the round *The open queue, worked through (2026-10-01)*

THE CLUSTER CLIs CANNOT RUN IN THE SANDBOX THEY ARE GIVEN. Found by the widened global lint (AUDIT 5's TOS-Extras item, below) and then proven by running the real files in the real sandbox. /usr/bin/cluster.lua (cluster-master) and /usr/bin/cluster-manager.lua are PATH programs, so the shell runs them through progenv in a sandbox with fs.read, fs.write and compat.io. Neither loads:

cluster status -&gt; user lib 'cluster.api' failed: api.lua:14:

module 'computer' is not available to sandboxed code

cluster-manager status -&gt; user lib 'cluster-manager' failed:

cluster-manager.lua:38: (the same refusal) THE CAUSE IS A DESIGN CONFLICT, not a typo. Since 8f7b12b (2026-09-11, "every module is the program's own") a library a sandboxed program requires loads INSIDE that sandbox, one instance each. cluster.api's own header says it is "an in-process API ... they share address space" with the running clusterd. So granting the CLI `component` only moves the failure: its private cluster.api is a fresh copy no daemon ever bound ("cluster daemon is not running"). Also dead in the CLI regardless: `cluster submit` uses loadfile, which no sandbox has, and die()/usage() call os.exit, which the sandbox's os omits. THE SERVICES ARE FINE: an rc.d service loads its libraries through the kernel loader (allowUserLibs), into the real \_G, and so clusterd and the manager daemon start. Only the operator CLIs are dead -- which includes `cluster pair start`, so a Manager can only be paired through the base `cluster-setup` wizard. OPERATOR DECISION, deliberately not made here, because it is about what a trusted package may reach:

(a) a SERVICE package's own /usr/bin program gets allowUserLibs,

so its libraries load through the kernel loader and share the

daemon's state. Consistent with "a service package is trusted

with the machine" (installing one is ROOT), but it runs user

input through kernel-loaded code, so the tier checks must move

into cluster.api itself (today they are in the sandboxed CLI);

(b) build ADDRESSABLE LOCAL IPC (WHAT THE REST OF THE FIELD DOES

BETTER, below) and have the CLI talk to the daemon through a

registered, cap-gated endpoint -- the designed answer, and

the larger job. Recommendation: (a) now, with api-side tier checks, and (b) when IPC exists. Pinned as \[known gap\] in test\_cluster\_cli\_sandbox.lua and in test\_global\_leaks.lua's TOS-Extras half, so either fix fails those lines and they get rewritten. Shipping now: cluster-master 1.0.1 and cluster-manager in the published pack carry this.

### Later: the wizard could offer to configure the OpenOS worker bridge

*Idea / far future* · from the round *Cluster setup round (2026-07-28)*

Later: the wizard could offer to configure the OpenOS worker bridge (secret + domain) instead of leaving it to hand-edits; it's the only remaining manual step.

### Specialized per-machine launcher profiles (doors, reactors)

*Idea / far future* · from the round *Far future / ideas*

Specialized per-machine launcher profiles (doors, reactors).

### Tape "personal menu" ecosystem polish

*Idea / far future* · from the round *Far future / ideas*

Tape "personal menu" ecosystem polish.

## Packages

### Slice 2: remote

*Planned* · from the round *Federated package repos (2026-09-27)*

SLICE 2: REMOTE. Dependencies across configured repos; the manifest and per-requires `repos` hints under the floor (trusted installs; unknown key = trust on first use, never for service or driver; unsigned = never auto-pulled from a discovered repo); the operator's strictness knob; a known-repos store kept apart from the admin allowlist.

### Slice 3: resolution

*Planned* · from the round *Federated package repos (2026-09-27)*

SLICE 3: RESOLUTION. Winner order: one shared copy satisfies everyone &gt; higher trust &gt; newer &gt; less disk; a tie asks. Private copies when no shared copy works; consensus and freshness across mirrors (a signature cannot stop a mirror serving an OLD signed version; agreement between repos can).

### Rebuild and re-sign the Optional Utilities pack

*Planned* · from the round *The mod source is the authority (2026-09-20)*

REBUILD AND RE-SIGN THE OPTIONAL UTILITIES PACK. Needs the OPERATOR: TOS-Extras/dist ships package.sig beside every package.lua, and signing takes TOS\_SIGNING\_PASSPHRASE and TOS\_SIGNING\_NAME from the environment — a secret, deliberately never in argv or in a file (build/README.md). So the tape fix above is in modules/ and NOT in dist/, and test\_build\_disk.lua's "the published pack matches a fresh build" check is RED until the pack is rebuilt:

TOS\_SIGNING\_PASSPHRASE='...' TOS\_SIGNING\_NAME='...' \\

lua TOS-Extras/build/build-disk.lua --sign That red check is the guard doing its job, not a break. Do NOT hand-copy the file into dist/ to silence it: the signature covers the manifest, which covers the hashes, which cover the files, so a hand-patched dist would carry a signature that no longer verifies — strictly worse than a stale one, because pkg would reject it.

DONE once on 2026-09-23 (the pack published 09-24 00:18 UTC is signed). CORRECTION 2026-10-02: it was not current with that day's sources. The two cluster Master fixes landed 40 minutes after it; dist/ was re-signed with them at 03:38 UTC and never pushed. RE-OPENED 2026-10-02 for the queue sweep's add-on changes, to be signed ONCE when they are all in. So far: the new `selftest` package, cluster-master 1.0.2 (the fixes, under a number `pkg upgrade` will offer), tape-authenticator 1.0.3, and rc-pilot 1.2.0 (it carries the robot's EEPROM image now). And every package's bytes change once: the pack strips its Lua now. test\_build\_disk.lua is red on them until then. The operator runs, from the TOS source root:

python tos.py pack --sign then publishes the utils branch:  publish.ps1 -Utils -Push

### Mount packages as read-only archives instead of extracting them

*Planned* · from the round *What the rest of the field does better (2026-09-20)*

MOUNT PACKAGES AS READ-ONLY ARCHIVES INSTEAD OF EXTRACTING THEM. PsychOS' pkgfs (lib/pkgfs.lua) installs a package by REGISTERING its archive: a filesystem-component-shaped table over an mtar file, optionally lz16-compressed, with a path index, where write/rename/makeDirectory/seek return false. activatePackage is one line. Fuchas does the same at boot with nitrofs; Zorya reads arcfs/romfs/cpio from the BOOTLOADER.

WHY IT IS WORTH MORE TO US THAN TO THEM: OC charges fileCost (512 B) per file on top of content, and a full install leaves \~260 KB free on an empty T2. Measured on TOS-Extras/dist/optional-utilities as shipped:

```text
  all 16 packages   76 files   745,015 B   38,912 B fileCost
  cluster-master    13 files   140,631 B    6,656 B
  blockfs            3 files    55,343 B    1,536 B
```

Archive-mounting all 16 recovers \~23 KB of pure fileCost before compression, and data-card deflate on Lua source usually halves the content. Call it 350-400 KB back on a disk with 260 KB to give: four installed packages becomes a dozen.

WE ALREADY OWN THE THREE HARD PARTS:

- fs.mount(path, proxy) takes anything filesystem-component- shaped, and netfs.lua and jbod.lua are existing producers of exactly that shape.
- compress.lua already frames deflate as INDEPENDENTLY inflatable chunks (nChunks(u16), then cLen/cData pairs). That is random access at chunk granularity, which is what an archive mount needs. Written for swap and backups; the property generalises for free.
- OC filesystem handles support seek (Reference/OpenOS: lib/devfs.lua:329, lib/core/full\_buffer.lua:12), so a mount seeks to a chunk instead of reading a 140 KB package whole on a 192 KB box.

SIGNING GETS SIMPLER, NOT HARDER: pkgsign signs a manifest of per-file hashes today; one archive is one hash and one signature, the archive is immutable after install, and srm scan stops walking a package's files. Uninstall becomes one remove.

COST, and compress.lua's own header already says it: a data- card call draws a per-tick budget and can sleep the machine a tick, so this is for COLD data. Package code is read once per require, which fits; a package whose data files are read in a hot loop does not. Per-package flag, not a global mode.

No data card -&gt; compress.lua falls back to a stored blob, so the fileCost win survives without compression.

securefs must still mediate the mount point, exactly as the jbod header says ("a TRANSPORT, not an access layer").

### Stage 1b leftover — the runner is verified only off-box

*Planned* · from the round *In progress: multitasking for full-screen programs*

STAGE 1b LEFTOVER — the runner is verified only off-box:

1. executor.lua: when the command comes from pkg.getCommand, spawn it as a seat-bound process (display = S.displayIdx, principal/token from the seat, background = the manifest policy) instead of pcall-ing it inline, then setForeground it.
2. The shell must then NOT draw. Today execSingle returns an output buffer and the shell repaints + reprints the prompt — straight over the program. Needs a "handed off" result so the shell skips its post-command redraw and returns to its event loop; it is not foreground, so it receives no input.
3. A kernel-level SUSPEND HOTKEY, intercepted in the kernel loop exactly like Ctrl+T (kernel/init.lua:1439) so the sandboxed program never sees it: drop the program to the background and hand the seat back to the shell with `tos_focus`. Ctrl+Z (ch 26) is the obvious key — CHECK IT IS UNBOUND FIRST.
4. Resume: the Ctrl+T switcher already lists processes and can foreground one. Needs to signal `tos_focus` on the way in.
5. Programs must repaint on `tos_focus`. It is NOT in the sandbox's PULL\_DROP, so it already reaches sandboxed code — but calc/snake/ttt/tetris currently ignore unknown signals and would show a stale screen (the tick-driven ones self-heal within a frame; the input-driven ones would not). Four small package updates + a documented convention for third parties.
6. On program EXIT: hand the seat back to the shell the same way.

### Operator decision: `pkg` and `service` read-only subcommands are admin-only

*Planned* · from the round *Planned (near future)*

OPERATOR DECISION: `pkg` AND `service` READ-ONLY SUBCOMMANDS ARE ADMIN-ONLY. The registry gives both tier 2, enforced at dispatch, so `pkg list/search/info` and `service list` refuse a user; the manual used to say only the changing subcommands needed admin. `srm` and `optimize` show the other pattern (tier 1, mutating subcommands gate themselves in-body). Documented as admin now; a deliberate choice either way.

### Get listed in `oppm list`

*Planned* · from the round *Planned (near future)*

Get listed in `oppm list`: a PR adding this repo to OpenPrograms/openprograms.github.io's repos.cfg. The `master` branch (build/oppm/) makes `oppm register` work; repos.cfg is what makes TOS show up for people who never heard of it.

### Install profiles: `install.lua --profile minimal|standard|full`, each writing a trimmed…

*Planned* · from the round *Planned (near future)*

Install profiles: `install.lua --profile minimal|standard|full`, each writing a trimmed system\_manifest.lua. From the 2026-09-10 follow-up review, which measured the release at 1,619 KB of content (1,695 KB on disk with fileCost) and \~353 KB free on a Tier 2 disk -- down \~102 KB in six days with the file count flat, so this is content growth, not new files. The architecture already allows it (41 pcall(require) sites in kernel/init.lua, an 11-file critical set) and it composes with `deploy drive`, which copies exactly what the manifest lists. Their measured cut -- drop the installer, docs, networking, remote pkg, the package manager, compat, peripherals and the `extras` commands -- leaves the full Commander UI at \~1,060 KB. Not urgent this week; the growth curve decides when it becomes so, and this turns a deadline into a knob.

### Anchor the network install to a key, not the transport

*Planned* · from the round *Planned (near future)*

Anchor the network install to a KEY, not the transport. bootstrap.lua verifies every download against the manifest, but the manifest comes from the same host, so it proves "these are the bytes that repository is serving" -- not "these are the bytes the publisher released". Its own comment block says exactly that. Pin an Ed25519 public key in bootstrap.lua and sign the release manifest with the machinery `pkg` already has: the root of trust moves from the transport to the one file an operator can read before running it. Every part is in the tree already (2026-09-10 review, §2).

### Slice 4: discovery and revocation

*Idea / far future* · from the round *Federated package repos (2026-09-27)*

SLICE 4: DISCOVERY AND REVOCATION. Opt-in bounded crawl over index `siblings`; signed revocation/rotation notices (revocations honoured automatically, successors never trusted automatically); in-world repos over the modem network; namespaced names.

### Not done, deliberate: OPPM's master list

*Idea / far future* · from the round *Internet card + remote pkg round (2026-08-04)*

NOT DONE, deliberate: OPPM's MASTER LIST (the index-of- indexes at openprograms.github.io that lets `oppm` search every registered repo). TOS works one repo at a time by URL. Adding it means trusting a list of hosts you did not write down, which is exactly what the allowlist exists to prevent — it needs an operator-facing "add all of these?" step, not a silent federation.

### Later, and the reason the OPPM work stops here: OPPM proper downloads from GitHub

*Idea / far future* · from the round *Shell gaps + real OPPM round (2026-08-04)*

Later, and the reason the OPPM work stops here: OPPM proper downloads from GitHub. TOS has NO internet-card support anywhere (zero occurrences of "internet" in the tree), so a repo still has to arrive as a directory. Doing it properly is a chain — compat/internet.lua, an `internet` entry in the sandbox's gated component types, sysinfo/lsdev detection, then remote pkg repos with host allowlisting and hash pinning. That is the first time TOS would fetch executable code from outside the world and wants its own round. Same bucket: the compat layer shims 11 OpenOS libs; `thread` (widely used, maps onto kernel.process) and `uuid` (trivial) are the two most-missed. `thread` needs a decision about what a sandboxed program spawning a process may inherit — it must be exactly the caller's caps, never more.

### Later: teach `pkg install` to refresh the baseline for files it replaces, so an upgrade…

*Idea / far future* · from the round *SRM round (2026-07-28)*

Later: teach `pkg install` to refresh the baseline for files it replaces, so an upgrade doesn't leave scan crying drift on every file it legitimately changed. Today that needs a manual `srm baseline` after upgrading (scan says so).

## Networking

### SSH and share have never worked

*Planned* · from the round *The Keller import, and the battery's first round (2026-09-25)*

SSH AND SHARE HAVE NEVER WORKED. They look for the network where it does not exist inside their sandbox and always print "Network not available". Deliberately left alone: making them work as they stand would let non-admins run remote commands and transfers that rsh / scp keep admin-only. Decide: alias them to rsh / scp, remove them, or document them. (keller session)

### The packet MAC has no length framing

*Planned* · from the round *Audit 5: kernel &amp; compat, off-box (2026-09-18)*

THE PACKET MAC HAS NO LENGTH FRAMING. net/init.lua:482 (send) and :669 (receive) tag a \\0-joined concat of variable-length, attacker-influenced fields: type, to, enc, epoch, seq, nonce, payload. Adjacent fields can be re-split without changing the joined string, so a captured packet can be reshaped across the type/to or nonce/payload boundary and keep a valid tag; moving one byte out of nonce into payload defeats the nonce ring.

NOT currently exploitable -- the H-3 sequence check refuses the replay, which is precisely the defence-in-depth it was added for. Recorded because the nonce ring is documented as a second layer and this quietly removes it. Fix: length-prefix each field. Severity LOW, and it rises the day the seq check is relaxed.

### The canonical number format is still architecture-dependent

*Planned* · from the round *Extras sweep 2: the packaging seam (2026-09-06)*

THE CANONICAL NUMBER FORMAT IS STILL ARCHITECTURE-DEPENDENT. The fix above removes the only float that crosses the wire; it does not make the FORMAT safe for the next one. A field carrying an integral float still canonicalizes differently on 5.2 and 5.3. The fix is one line in each half -- render numbers with a subtype-independent rule ("%d" when the value is integral, else "%.14g") -- but it changes the MAC for every frame, so both sides must be upgraded together AND the OpenOS worker is hand-copied to each worker box. Worth doing at the next protocol version bump, not on its own.

### Operator decision, deliberately not made here

*Planned* · from the round *The budgets that do not exist (2026-08-24)*

OPERATOR DECISION, deliberately not made here: should `rsh` REFUSE to execute when the step budget cannot be installed?

FOR: it is arbitrary code from the network with no CPU or

allocation bound. What actually stops a runaway is OC's machine

watchdog, which kills the WHOLE COMPUTER -- a far worse outcome

than the clean "step budget exceeded" this module was written to

return, and on a multi-seat box it takes everyone down.

AGAINST: it would disable rsh outright on the only platform TOS

ships for. The feature already requires a TRUSTED peer AND

challenge-response per request AND rshd running (default off),

and CMD\_LIMIT / OUTPUT\_LIMIT / the entry-time MIN\_FREE\_MEM check

all still hold. This is a deliberate, gated feature, not an

accident.

A middle option: keep it enabled but make `service start rshd`

print the loss once, so nobody enables it believing in a budget

that is not there. The warning added above is the log-level

version of that; whether it should be louder is the call.

### Minitel: decide, don't default

*Planned* · from the round *From the Cynosure 2 survey (2026-08-10)*

MINITEL: DECIDE, DON'T DEFAULT. Cynosure ships Minitel in the KERNEL beside TCP and HTTP (NET\_MTEL), and the partition table options name MTPT as "the Minitel partition table used by PsychOS". It is the ecosystem's de-facto interop protocol. Our mesh is bespoke and SHOULD stay bespoke — you cannot get replay-resistant MACs and trust tiers out of someone else's protocol. But "TOS machines can only talk to TOS machines" should be a position we hold on purpose, not one we backed into. If we ever want it, a Minitel bridge is an Extras package, not a kernel change.

### Mesh: the route information is already in the packets

*Idea / far future* · from the round *Second pass: the compat number (2026-09-20)*

MESH: THE ROUTE INFORMATION IS ALREADY IN THE PACKETS. Plan9k does real networking -- IPv4, subnets, RIP v2 in `routed`, address autoconfiguration in ohcp that installs routes on lease. We deliberately do not: no routing table, neighbours only, controlled flooding with DEFAULT\_TTL 8, MAX\_TTL 16, a 512-id dedup cache and store-and-forward retries. That is the right trade for OC-sized networks and the module is already hardened against flood amplification. NOT A GAP.

The one thing worth writing down: flooding costs scale with network size, and our own packets already carry the fix. Every mesh message has a `path` field -- the node addresses it has traversed -- so a node that relays a message ALREADY KNOWS a working route back to the origin, for free, with no protocol change. If a base ever gets big enough that flooding hurts, opportunistic route learning from `path` (try the learned next hop, fall back to flooding) is available without adopting anyone's routing protocol. Not now; recorded so it is not re-derived under pressure.

### Operator idea (raised 2026-08-04, deferred)

*Idea / far future* · from the round *Internet card + remote pkg round (2026-08-04)*

OPERATOR IDEA (raised 2026-08-04, deferred): a text-mode WEB BROWSER package over the internet card. Notes on shape before anyone starts — see the discussion, but the short version: the fetch is the easy 10%; HTML -&gt; text layout is the work, and the 80x25 T2 screen is the real constraint. Build it as a PACKAGE declaring `internet` + `fullscreen`, never in the base image. It is also the first thing that would want kernel.internet's caps RAISED (a page is bigger than 64K), which is a good reason to keep that per-call rather than global.

### Later: per-group mesh sealing

*Idea / far future* · from the round *Intercom round (2026-07-28)*

Later: per-group mesh sealing (today a group send is N sealed unicasts, which is correct but O(N) floods); and letting `intercom cue add` write catalog lines from the shell instead of hand-editing /etc/intercom.cues.

## Security and accounts

### Who may manage accounts, read the log, use scp

*Planned* · from the round *Second pass: the compat number (2026-09-20)*

WHO MAY MANAGE ACCOUNTS, READ THE LOG, USE SCP. Found 2026-10-03 walking the README's new "first ten minutes" on the headless machine: five commands' REGISTRY tier disagreed with the gate their own body runs. useradd/userdel/usermod were registered ADMIN (and documented admin in MANUAL 3.3 and ch.14) but call rootOnly; log and scp were registered USER ("log: filtered by tier") but call adminOnly. So `help` offered admins (users) a command that then refused them. Fixed the safe way: the registry and MANUAL now follow the code (no change in who can do what), and test\_command\_gate\_tiers.lua fails on any future mismatch.

DECISION NEEDED, if any should be LOOSER: kernel users.create already accepts an ADMIN creator (effective tier &gt;= ADMIN), so admin account management is a one-word change in admin.lua -- but usermod's admin/root promotions and userdel need checking against users.setTier/delete's own guards first. `log` "filtered by tier" implies a user-visible log that the body has never allowed.

### The manifest anchor is not enforced at boot

*Planned* · from the round *Second pass: the compat number (2026-09-20)*

THE MANIFEST ANCHOR IS NOT ENFORCED AT BOOT. `verify anchor` writes the manifest's hash into the EEPROM's data field and `doctor` (and netrepair) compare it with the live manifest -- but nothing calls kernel.verifyManifestHash at boot. Its own comment said boot refused on a mismatch "unless a held-key recovery override is asserted"; found 2026-10-03 while correcting MANUAL 15 that neither the refusal nor the override exists. Comment fixed, MANUAL says `doctor` reports it. Not a new hole: MANUAL 15 already says an admin who can write the boot files runs code before login.

DECISION NEEDED before building it: enforcing means a machine whose manifest legitimately changed (an upgrade, `pkg` touching a system path, a repair) stops booting until someone clears the anchor -- so it needs (a) every legitimate manifest writer to re-anchor or clear, (b) a recovery path that is not itself a bypass (the held-key idea: a key held at POST, like S for Safe Mode, that boots past a mismatch with a loud warning), and (c) a choice of refuse vs warn. Warn-only at boot (a POST line + the boot log) is cheap and safe; refuse is the real protection and the real cost.

### Dry-run capability enforcement

*Planned* · from the round *Second pass: the compat number (2026-09-20)*

DRY-RUN CAPABILITY ENFORCEMENT. Upgrades AUDIT LOG FOR CAPABILITY DENIALS (OCOS survey, \[\*\]) from an idea to a shape. Their cap.check has an `enforce` flag: when false it ALWAYS RETURNS TRUE but writes a denial record to the audit log; when true it denies and the caller raises EPERM (src/sys/k/cap.lua).

That is the safe way to tighten a sandbox on a live base: turn enforcement off, run the workload, read what WOULD have broken, then turn it on. It is also an excellent test fixture -- run the OpenOS compat corpus above in audit mode and the log says exactly which capabilities real programs need, which is the empirical version of guessing.

SECOND, SMALLER IDEA from the same file: their caps are namespaced and GLOB-MATCHED -- syscall:write:/var/log/\*, component:&lt;type&gt;:&lt;addr&gt; -- so a service is granted write access to a PATH PREFIX rather than to the filesystem. Ours are flat booleans and write scoping is securefs per USER, which is the better answer for humans. For a sandboxed DAEMON with no human behind it, a path-scoped write cap is strictly tighter than "can write as this user". First use is rc.d services, whose caps are already declared and already gated (ALLOWED\_SERVICE\_CAPS).

### Consolidate the security policy into one file

*Planned* · from the round *From the KittenOS Neo survey (2026-08-10)*

CONSOLIDATE THE SECURITY POLICY INTO ONE FILE. Theirs is a single readable function returning "allow" / "deny" / "ask", prefix-matched over namespaced permission strings, and its own header declares it CRITICAL: break it and a failsafe leaves the system unable to run user applications at all. Ours is correct but SCATTERED — ALLOWED\_MODULE\_PREFIXES and the BASE/GATED component sets in sandbox.lua, adminGate in pkg.lua, ALLOWED\_SERVICE\_CAPS in rc.lua. Each is fine alone; together they mean "what is this system allowed to do?" takes three files and knowing where to look.

- Move the DECISIONS into one auditable function. Leave the ENFORCEMENT points exactly where they are — this is a refactor of policy, not of mechanism, and the enforcement sites are where the #SEC history lives.
- Attach the fail-closed property explicitly: a policy file that won't load must deny everything non-kernel, loudly. That is a security PROPERTY, so it needs its own test.
- This is the one place our security STORY is quieter than our security POSTURE. The posture is good; you just can't read it in one sitting.

### Operator decision: who may power off

*Planned* · from the round *Planned (near future)*

OPERATOR DECISION: WHO MAY POWER OFF. helpers.canPowerOff (the #REV #9 policy, 2026-07) lets a SOLE logged-in operator reboot or shut down without being admin; with others logged in it wants admin. But the registry gives reboot and shutdown tier 2, and since b39f4d0 (2026-09-11) dispatch enforces that first, so the sole-operator branch is unreachable and the manual now says admin. b39f4d0 also tightened another power-off path to admin on purpose, so admin-only may be the intent. Either lower reboot/shutdown to tier 1 (users; guests stay out) and let canPowerOff decide, or delete its sole-operator branch as dead code.

### Run-this-once confinement

*Idea / far future* · from the round *What the rest of the field does better (2026-09-20)*

RUN-THIS-ONCE CONFINEMENT. Plan9k composes namespaces at launch from the command line: `sandbox wl fc0 wl fcd component spawn /bin/a.lua` (exactly two components), `sandbox module spawn ...` (fresh module namespace), quietin/quietout/quieterr. Their cgroup kinds are signal, filesystem (a root, i.e. chroot), network, module (its own package.loaded/preload) and component (whitelist/blacklist, parent-chained allow(addr)), inherited from the spawning thread.

Our caps are declared in a package manifest and accepted by an admin at install; progenv.lua already builds a process env from an opts.caps table. What is missing is the operator verb: run THIS program, right now, with no network -- the thing you want when someone hands you a script and you are not installing it as a package. A front-end over progenv and the existing cap vocabulary, not new mechanism.

\[\*\] and not \[ \] because the one genuinely new primitive in their list -- the FILESYSTEM cgroup, a per-process root -- is a design question we have not answered. securefs' per-user ACLs are a different and mostly better answer; a confined root is still the natural thing to hand an untrusted one-off, and it composes with the COW overlay above. Decide that before building.

NOT GAPS from this pair, recorded so they are not re- investigated: Plan9k's MODULE CGROUPS shadow module tables with setmetatable({}, {\_\_index = kernel.modules.x}) per group -- we already do that AND lock the metatable, filter pairs(), and (in the H-01 work) mask kernel-only hook keys so a sandbox cannot reach compat.term.\_gpuForCaps. Ours is strictly stricter. Fuchas' SJF SCHEDULER needs job-length estimates nobody in this ecosystem has; our wall-clock + per-resume instruction budget (process.lua:960) is a harder guarantee than any scheduling policy. MineOS' DOUBLE-BUFFERED GUI is our shadow buffer, and the workload-specific second renderer is already scoped in LOG WALL. MineOS' desktop, app market, IDE, FTP client and 3D library are a different product, as the README already says. Plan9k's procfs/sysfs/devfs is the Cynosure survey's decision unchanged. MineOS hand-maintains EFI/Full.lua AND EFI/Minified.lua; we generate the flashable BIOS through strip.lua --minify with a test on the budget -- ours is better, do not copy theirs.

### "Ask" as a third state

*Idea / far future* · from the round *From the KittenOS Neo survey (2026-08-10)*

"ASK" AS A THIRD STATE. We are binary and install-time: an admin accepts a package's declared caps, all of them, before any are used. They defer hardware access to FIRST USE and prompt with package name, PID and the permission, offering No / Always / Yes — and "Always" writes the grant into settings, which is the bit that makes prompting tolerable rather than nagging.

- BLOCKED ON A DESIGN ANSWER, which is why it's \[\*\]: KittenOS is single-user, single-seat, GUI. We are multi-seat with rc.d services and sandboxed daemons that have NO operator attached — that is why notify.lua exists at all. A naive port hangs a service forever waiting for an answer nobody is there to give.
- If we do it: "ask" is legal ONLY in an interactive session and resolves to DENY everywhere else. Decide that first, in writing, before any code.

### Audit log for capability denials

*Idea / far future* · from the round *From the OCOS survey (2026-08-10)*

AUDIT LOG FOR CAPABILITY DENIALS. When the sandbox refuses a program a cap we log it, but there's no single place an operator can read "what got refused, to whom, when". Worth a dedicated append-only log rather than digging through the general log. (OCOS's permissive-mode flag that logs instead of denying is NOT for us — we're fail-closed by design and that stays. It's the record that's worth having, not the escape hatch.)

## Boot, memory and the kernel

### Open - Safe Mode "unsafe power-off" (operator report)

*Open bug* · from the round *Memory round (2026-07-24)*

OPEN - Safe Mode "unsafe power-off" (operator report). NOT reproduced from code: there is no safe-profile-specific shutdown path (only bootcfg feature gates), and the generic zero-process path stamps /var/run/pwrstate "C" via kernel.shutdown, i.e. a CLEAN power-off. Candidates still to rule out, need the kernel.log + /var/crash from that boot:

(a) shell/login failed -&gt; proc.count()==0 -&gt; 3 respawns -&gt;

emergencyShell -&gt; break -&gt; kernel.shutdown (powers off

rather than staying up);

(b) an actual power cut leaving the stale "R" marker,

which the next boot correctly reports as unsafe.

### Self-stripping, not build-time config — operator decision, 2026-08-11

*In progress* · from the round *From the Cynosure 2 survey (2026-08-10)*

SELF-STRIPPING, NOT BUILD-TIME CONFIG — OPERATOR DECISION, 2026-08-11. Supersedes the build-time item below; keep that text for the Cynosure argument it came from, but the shape has changed and this is the one to build.

THE DECISION: the choice belongs to the OPERATOR, IN GAME,

whenever they want it — TOS strips ITSELF. Not a .config

chosen by whoever built the image, months before the

machine had a job.

WHY IT IS BETTER, and this is the operator's argument

rather than a rationalisation of it: a build-time config

forces the decision at the moment you know LEAST about the

machine. Deciding in-game means deciding after the box has

been doing its actual work, with its real RAM, its real

peripherals and its real disk pressure in front of you.

It also means the decision is REVISITABLE while the

machine is alive.

THE TWO FLOORS, non-negotiable, both operator-set:

- SAFE MODE always boots. It is what you fall back TO, so it cannot be a thing you can strip. Anything Safe Mode needs is in the floor by definition.
- The EMERGENCY TERMINAL always exists. Same reason: it is the diagnostic of last resort and a diagnostic you can delete is not one.

Everything else is on the table.

DESIGN NOTES, so whoever builds it does not re-derive them:

- The floor must be COMPUTED AND TESTED, never a hand-kept list — a hand-kept floor drifts and you find out on the boot where you needed it. Shape: system\_manifest.lua grows `floor = true`, and a test asserts the floor is CLOSED UNDER REQUIRE (nothing in the floor requires anything outside it). That test is the feature.
- FEATURE GROUPS, not files. The operator picks cluster / internet / tape / blockfs / mesh / i18n / rbmk — the axes the build-time note already identified. Nobody should be ticking individual .lua files.
- STRIPPING IS DESTRUCTIVE AND NEEDS MEDIA TO REVERSE, and the UI has to say so in those words. `srm baseline --full` first is the honest prerequisite: the SRM store is what makes an un-strip possible at all, and it already exists. Refuse to strip with no baseline unless the operator overrides, exactly as `srm repair --restore` refuses without one.
- THE MANIFEST MUST BE UPDATED BY THE SAME OPERATION, or `verify` and `srm scan` cry deletion about every removed file forever and the operator learns to ignore them — which costs more than the disk saved. Stripped entries get marked, not deleted, so the difference between "removed on purpose" and "missing" survives.
- BOOT PROFILES AND STRIPPING ARE DIFFERENT LAYERS and now interact: a profile gates what LOADS, stripping removes what EXISTS. A profile that would load a stripped feature must degrade with a clear line in the boot log, never panic. Today the load paths pcall-and-warn, which is most of the way there — but it has never been tested against a file that is genuinely absent rather than merely skipped.
- NOT a package. `pkg uninstall` already covers add-ons; this is about the BASE IMAGE, which pkg does not own.

### The RAM floor is 1 MB, not 192 KB

*Planned* · from the round *Second pass: the compat number (2026-09-20)*

THE RAM FLOOR IS 1 MB, NOT 192 KB. Measured 2026-10-03 on the headless machine (build/headless-session.py --profile t1 --ram, default OpenComputers config, fresh install, `firstboot` then one command). The README said 192 KB minimum and 256 KB for the full interface. On this build:

```text
  RAM      panels (default)       ui=cli               minimal + cli
  <=384K   E-202: the kernel cannot even be compiled
  512K     security skipped; login refuses; reboot loop  minimal auth
  768K     emergency terminal     emergency terminal   prompt, core cmds won't load
  896K     -                      core cmds won't load -
  960K     -                      works, 35K free      -
  1024K    1st command crashes    works, 34-48K free   works, 120K free
  1152K    core cmds won't load   -                    -
  1280K    works, 62K free        works, 220K free     works, 321K free
  1536K    works, 198K free       works, 390K free     -
  2048K    works, 736K free       -                    -
```

CALIBRATION, so this is not the emulator: OpenOS 1.8.9, copied from the Ocelot workspace, boots at 192K on the same machine using \~155K, as it does in-game.

Done the same day: the README, CONTRIBUTING and the installer's warnings state the measured floor, and below 1.5 MB an unset `ui` starts the CLI (bootcfg.PANELS\_MIN\_KB) rather than the panels crashing on the first command.

OPEN, the real work: the footprint itself. The first wall is compiling tos/kernel/init.lua (90 KB even minified), which alone fails at 384K. Start with a per-stage memory profile -- the headless machine can produce one now. Then a floor check in the headless runs, so the documented number cannot drift again: 192 KB was presumably true once, and nothing re-measured it.

### Split the BIOS: minimal EEPROM, recovery UI in stage 2

*Planned* · from the round *Second pass: the compat number (2026-09-20)*

SPLIT THE BIOS: MINIMAL EEPROM, RECOVERY UI IN STAGE 2. Refines the item above and the 2026-09-06 BIOS pair. MineOS proves a full menu FITS in 4 KiB; OCOS argues you should not put it there anyway. Their EFI is 4,164 B of source, 3,109 B minified, and its own comment says the boot-mode menu, recovery flows and splash "live in /sys/boot.lua, where they have room to breathe". The EEPROM does the minimum: find a medium, read config, load stage 2, and on ANY failure draw a full-screen panic naming the reason.

Nearly the shape we already have -- bios.lua is a POST + loader, /init.lua is stage 2. The split:

- EEPROM: timed hotkey, BOOT-DEVICE chooser, panic screen that names the reason. Small enough to keep the manifest anchor.
- Stage 2: the rich recovery menu -- boot profiles, safe mode, srm restore, doctor, disk utility -- using the kernel's own modules.
- THE SPLIT'S WEAKNESS, stated plainly: if the DISK is what broke, stage 2 is gone and only the EEPROM half is left. Which is exactly why the EEPROM half must still be able to pick a DIFFERENT disk, and why the emergency terminal stays. Today K4, I5 and I6 end in "any key reboots" on the same saved disk: a loop. /init.lua's missing-files screen got its way out on 2026-10-02 (bootElsewhere); these are the rest.

Two behaviours from the small bootloaders, both cheap: GEBL's QUICK BOOT (exactly one bootable OS found -&gt; boot it, no prompt) and its INIT FINDER (config missing or unreadable -&gt; search the filesystem root for a bootable file instead of giving up). Zorya adds the third: a SELECTION TIMEOUT that falls through to the default.

### A 4 KiB EEPROM fits a recovery menu, and MineOS proves it

*Planned* · from the round *What the rest of the field does better (2026-09-20)*

A 4 KiB EEPROM FITS A RECOVERY MENU, AND MineOS PROVES IT. This is evidence for the two entries in THE BIOS REFUSED TO BOOT ANYTHING BUT TOS (2026-09-06), not a new item: the objection there was byte budget, and the objection is wrong. MineOS' EFI/Minified.lua is 3,865 bytes -- inside the 4 KiB limit with 231 to spare -- and it holds ALL of:

- a TIMED hotkey (hold Alt for one second) so the recovery path costs a healthy boot nothing;
- a boot-source menu listing every filesystem component with label, HDD/FDD/SYS class, read-only flag, used-percent and address;
- per-disk set-bootable / rename / erase;
- internet recovery and URL boot, both gated on a card;
- a candidate boot-file list (/OS.lua, then /init.lua) so it boots its own OS or an OpenOS-shaped one, and a fallback that walks every filesystem when the committed address is gone, re-scanning on component\_added.

Fuchas' dualboot\_init.lua is the /init.lua half in \~40 lines and is the cheaper thing to copy first: a stub that checks for /lib/core/boot.lua and /Fuchas/Kernel/boot.lua, boots whichever exists ALONE with no prompt, and asks only when both are there.

OUR CONSTRAINT THEY DO NOT HAVE: the EEPROM data field is already spoken for. bios.lua keeps the boot address on line 1 and the kernel anchors its manifest hash after a newline (#SEC C1). A menu that writes the data field must preserve line 2+.

Internet recovery inherits the pkgsign question -- fetching and running a script from a URL is exactly what signing exists to stop. Scope it to "download bootstrap.lua and stop", which is the documented network install path anyway, or check a signature.

OTHER ROUTE, decide one and not both: ship a loader\_tos module for Zorya NEO (Extras) instead of growing bios.lua. Their loaders are \~40 lines (mods/loader\_openos/init.lua returns function(addr) that builds an env and loads the OS's init) and they already carry loader\_openos, loader\_fuchas, loader\_cynosure, loader\_monolith, loader\_tsuki. But Zorya then owns the EEPROM, runs the OS in its own thread under a synthesized \_G, and offers virtual components -- and our boot chain has opinions about all three (the Lua-5.3 feature probe, the manifest anchor, component\_caps).

### A driver registry with per-device probing

*Planned* · from the round *What the rest of the field does better (2026-09-20)*

A DRIVER REGISTRY WITH PER-DEVICE PROBING. Fuchas resolves a device to a driver instead of hardcoding one: drivers live at Drivers/&lt;component type&gt;/&lt;name&gt;.lua along a DRV\_PATH search path, each returns a spec with isCompatible(addr), findBestDriver(type, addr) probes candidates, changeDriver pins a specific driver to a specific address, and in SAFE\_MODE only a basicDrivers set (drive, gpu) may load at all. Two printer drivers ship side by side -- openprinter.lua and ccprinter.lua -- which is the whole point.

WE ARE ALREADY HAND-ROLLING THE SPECIAL CASES THIS GENERALISES. The printer checklist in the PRINTER round says "a 1.7-era printer: width/maxWidth absent, printer must say 'older build: no width' and still print" -- that is isCompatible(addr) written by hand inside one module. `rbmk survey` ("does anything bind") is the same shape again. Third instance is coming; the second is where the abstraction gets built.

A NEW DEVICE NEEDS A KERNEL EDIT today: hal.lua is a fixed type -&gt; {address, proxy, tier, label} registry and tos/peripheral/ is three kernel modules. Extras ships mouse and printer as ordinary libraries in a "drivers" category, outside the cap system. A pkg-installed driver the kernel FINDS is strictly better, and etc/component\_caps.cfg + `component reload-caps` is already the authority half of the design.

DO NOT COPY THEIR AUTHORITY RULE: "a process must use drivers unless it is admin" means root bypasses the abstraction. Our sandbox has no such escape and must not grow one. A driver is a BINDING mechanism (which code drives this device); the cap check stays where peripheral/redstone.lua:requireCap puts it.

### Addressable local IPC

*Planned* · from the round *What the rest of the field does better (2026-09-20)*

ADDRESSABLE LOCAL IPC. Fuchas' Libraries/ipc.lua (OETF #18) gives a process a socket to another PID -- ipc.socket(target, id) with write/read/closed, async in write, sync in read, built on per-process signals rather than the global queue. Plan9k has pipes/17\_ipc.lua.

We have two things and neither is this: pipe.create() is an anonymous in-memory stream handed to a child at spawn (shell pipelines and redirection, 64 KB cap, #SEC M2), and notify.post is one-way to whichever human is looking. An rc.d service and an unrelated process cannot talk at all -- which is why the LOG WALL item has to ask "is the feed LOCAL or REMOTE?", and why the mesh gets reached for when both ends are on one machine. cluster-manager and mail's inbox tab are the same shape.

event.lua is most of the way there: it already records the registering PID and spawn generation (#SEC H13, H31, M-11) and fires each listener under that PID's context. A targeted push is a small addition to machinery that already thinks in PIDs.

IT MUST BE CAPABILITY-GATED, which theirs is not. "Send to any PID" is authority a sandboxed program should not have: unsolicited messages to a privileged service are an injection surface and PID scanning is an information leak. Shape: a service REGISTERS a named endpoint, callers hold an ipc.connect(&lt;name&gt;) cap. Never raw PIDs.

Do not build it on the compat event queue: compat/event.lua deliberately blocks sensitive signal names, and IPC must not become the way around that filter.

NOT A GAP, recorded so it is not re-investigated: Fuchas' PER-PROCESS SIGNAL QUEUES (computer.pushProcessSignal). The security half -- one process reading another's events -- is already handled at a different layer, where compat/event.lua blocks sensitive names outright and names keystroke-logging other seats and clipboard sniffing as the attacks. Only the addressable-IPC half above is missing.

### The root cause is still there, and the rescue only makes it survivable

*Planned* · from the round *The escape hatch needed the broken thing (2026-08-24)*

THE ROOT CAUSE IS STILL THERE, and the rescue only makes it survivable: commands/core.lua is \~2,650 lines, the biggest file in the tree, and loading it needs one large contiguous buffer. That is why it -- and not admin.lua or extras.lua -- is the category that dies first on a tight box.

Splitting it would lower the peak allocation, but it is not

free: the v1.3 split into core/admin/extras exists to make the

COMMON case cheap (a session that never touches admin never

parses it), and cutting core again trades that for more files

to require on a healthy box. Worth measuring before deciding --

what is the actual peak while reading core.lua, and does a

two-way split of it drop the floor enough to matter on a 192K

machine? The `mem` reading before and after a known sequence

(the OTHER open memory item, from the real-Minecraft round) is

the same measurement, so do them together.

### Observed, not diagnosed

*Planned* · from the round *Real Minecraft round (2026-08-11)*

OBSERVED, NOT DIAGNOSED: free memory read 251K in one screenshot and 56K a few actions later on what looks like the same session. That is a big drop for opening a menu or two. Could be the category lazy-load doing its job (core.lua is large), could be a leak. Needs a `mem` reading before and after a known sequence rather than a guess from two screenshots.

### Build-time feature config

*Planned* · from the round *From the Cynosure 2 survey (2026-08-10)*

BUILD-TIME FEATURE CONFIG. The best idea in that kernel. A .defconfig + a source preprocessor give it Linux menuconfig semantics: COMPONENT\_\* per device type, FS\_\*, NET\_\*, PART\_\*, EXEC\_\* — features compile OUT of the image. Our boot profiles (minimal/normal/full/diagnostic/safe) gate what LOADS at runtime; the code is still in the image, still on disk, still parsed the moment something requires it. On a RAM-bound box compile-time exclusion strictly dominates runtime skipping.

- We already own the machinery — strip.lua plus the manifest auto-pruning already emit a tailored tree. This is a .config on top of what build-release.sh does, not a new build system.
- Natural first axes: cluster, internet, tape, blockfs, mesh, i18n. All optional, all currently unconditional.
- Keep ONE canonical full build as the tested default. A matrix of configs nobody boots is worse than no configs — pick the variants we actually run.

### Next if still tight: i18n catalogs, and the display-layer work already queued in the OC…

*Planned* · from the round *Memory round (2026-07-24)*

NEXT if still tight: i18n catalogs, and the display-layer work already queued in the OC optimization playbook.

### Support-ceiling policy (design decision, operator-approved direction)

*Planned* · from the round *Polish - operator feedback (round 4)*

Support-ceiling policy (design decision, operator-approved direction): instead of degrading everything for T1 GPUs / tiny RAM, set a floor - refuse to boot (clean message) or fall back to the CLI shell on hardware below it. Sweep the T1/low-RAM special cases once decided.

### Screenshots

*Planned* · from the round *Planned (near future)*

Screenshots. There is not one image in the repository, and every venue worth posting in is one where the screenshot IS the post. Six stills plus a boot GIF; the shot list, the capture method and the publish prerequisite are in docs/screenshots/SHOTS.md. The README already has the markup, commented out, waiting for the files.

### Line disciplines — direction, not a task, and expensive

*Idea / far future* · from the round *Second pass: the compat number (2026-09-20)*

LINE DISCIPLINES -- direction, not a task, and expensive. Their comment is the clearest statement of it (Cynosure 2, src/disciplines/main.lua): a line discipline is "a middle layer between the raw stream and the character device... the TTY line discipline is what makes ctrl-C, ctrl-\\, and ctrl-Z work. This line discipline can be put over a network socket, a serial connection, or a virtual TTY provided by the kernel - and the application (ideally the user, too) will see no difference in behavior."

THREE OF OUR PROBLEMS ARE ONE PROBLEM IN THAT FRAMING:

- H-04 (open): term.read() takes signals off the machine-wide queue. A per-stream input queue with a discipline in front is where that read should get its characters.
- H-06 (open): two sandboxes share compat.term's cursor. A discipline instance per stream owns its own line state.
- rsh has no pty. A remote shell is a socket; with a discipline over it the remote side behaves like a local terminal and rsh knows nothing about terminals.

This is NOT a proposal to rewrite the terminal layer. It is a note that the next time one of those is patched, the patch should move TOWARD one input-stream abstraction with a discipline, instead of adding a fourth special case to compat.term.

OTHER ROUND-2 NOT-GAPS, recorded so they are not re-investigated: OCOS' SEMVER PACKAGE DEPS -- pkg.lua already takes { name = ..., version = "&gt;=1.0", optional = ... } and has compareVersion (:1072, :1157). OCOS' DOUBLE-BUFFERED COMPOSITOR -- our shadow buffer; their README names MineOS as the source. Cynosure 2's PLUGGABLE BINFMT (src/exec/{lua,cle,shebang}.lua) -- we run .lua and that is the whole population. ULOS 2's LUAPOSIX COMPATIBILITY PUSH -- their target is \*nix programs; ours is OpenOS programs, which is the population that actually exists.

### /Proc-style read-only introspection

*Idea / far future* · from the round *From the Cynosure 2 survey (2026-08-10)*

/proc-STYLE READ-ONLY INTROSPECTION. Their /proc is a real filesystem (proc\_config, proc\_events, proc\_binfmt). We expose the same facts as COMMANDS (lsdev, hw, sysinfo, doctor), which suits our idiom and shouldn't change. The one property worth wanting: a sandboxed program can read a file it already has read access to WITHOUT being granted a new capability. Today a sandboxed program that wants its own PID or free memory needs it handed in. Not urgent; remember it if the sandbox ever feels too tight.

NOT a gap, recorded so it isn't re-investigated: their "fastest VT100 in OC" is write batching (accumulate a run, one gpu.set per colour run) plus hardware gpu.copy for scroll and insert-char. No cell diffing, no shadow, no off-screen buffer. Different workload from ours — see the LOG WALL item below — and we already use gpu.copy for scrolling (display.lua \~585).

## Files and storage

### If we build the archive mount, use mtar — do not invent a format

*Planned* · from the round *Second pass: the compat number (2026-09-20)*

IF WE BUILD THE ARCHIVE MOUNT, USE mtar -- DO NOT INVENT A FORMAT. Refines MOUNT PACKAGES AS READ-ONLY ARCHIVES above. mtar is \~100 lines and the header is trivial:

\\255\\255 &lt;version:u8&gt; &lt;nameLen&gt; &lt;name&gt; &lt;fileLen&gt; version 0 uses &gt;I2 for the length, version 1 &gt;I8. Entries stream, so an iterator walks the archive without loading it, and cleanPath strips . and .. segments AT PARSE TIME -- a traversal guard we would otherwise have to write.

The reason beyond saving work: four implementations already read it (PsychOS' libmtar, ULOS 2's mtarldr boots FROM one, Zorya's reader, plus the writers), so a TOS package archive would be readable by other systems and we could read theirs. This is the one place we lose nothing by being compatible: a package archive has no trust properties of its own -- the Ed25519 signature over it is where the security lives, and that stays ours.

### Copy-on-write overlay mounts

*Planned* · from the round *What the rest of the field does better (2026-09-20)*

COPY-ON-WRITE OVERLAY MOUNTS. Plan9k's pipes/06\_cowfs.lua is \~120 lines: cowfs.new(readfs, writefs) returns one proxy, reads fall through to the read-only side unless the write side has the file, writes always land on the write side, and deletes are recorded as &lt;dir&gt;/.cfsdel.&lt;name&gt; whiteouts so a delete can shadow a file that exists only on the read-only side.

Three things we cannot do today and would get:

- RUN from read-only media. HEAD already offers to install from a read-only boot disk; an overlay is the other answer -- run NOW, writes on any writable disk, install later or never.
- A kiosk or LOG WALL appliance that RESETS on reboot. Point the write side at a scratch volume and wipe it at boot. kiosk.cfg gates commands; the filesystem is still permanently mutable. This is the missing half.
- TRY-BEFORE-COMMIT: pkg install or an srm experiment on an overlay, inspect, then merge or drop the write layer. A weaker form of `srm baseline --full`, reached without media.

WHITEOUTS ARE A NAMESPACE HAZARD and Plan9k does not guard it: a real file named .cfsdel.x must not be able to hide x. fs.lua already refuses to mount over a non-empty directory (#SEC H27) and refuses to remove mount points, so naming and blocking this class is house style. Needs its own test.

### Still \~8 sector writes per tiny file

*Planned* · from the round *TBFS: the cost was writes, and a second handle (2026-09-06)*

STILL \~8 SECTOR WRITES PER TINY FILE (inode alloc, directory append + its inode, data block, bitmap, file inode, super). Half of those are per-operation metadata that a "close-time flush" could merge across a create-write-close sequence, at the cost of "written" meaning "on close" -- an operator decision, and not one to make for a filesystem on hardware that vanishes when someone breaks the block.

### A read-only foreign-volume reader

*Idea / far future* · from the round *What the rest of the field does better (2026-09-20)*

A READ-ONLY FOREIGN-VOLUME READER. Split from the entry above: now TOS can NAME another OS's disk, the next step would be listing and copying files off it (OSDI/MTPT partitions, SimpleFS), which is a real base-admin task. A line, not a round.

## Shell and interface

### Localise the installer, not just the OS

*Planned* · from the round *What the rest of the field does better (2026-09-20)*

LOCALISE THE INSTALLER, NOT JUST THE OS. MineOS ships \~20 Localizations/\*.lang packs AND a separate Installer/Localizations/ set, and the installer asks for a language as step one. Their format is what makes community translation happen: one file per language, a flat Lua table of short keys, no tooling to contribute. Ours (usr/lang/, i18n.lua) is already that shape and holds exactly one pack, ru.lang.

The transferable half is the installer: install.lua and bootstrap.lua are English-only and they are the first, and sometimes only, screens a new operator reads. Routing their strings through i18n and asking for a language first is bounded, and it is what turns one ru.lang into a reason for someone to send a second pack.

### The shadow buffer is tuned for TUI redraw

*Planned* · from the round *Log wall / streaming-console appliance (2026-08-10)*

The shadow buffer is tuned for TUI redraw — repaint mostly- unchanged cells, elide what matches. A scrolling log is the opposite profile: nearly every cell is new every frame, so the diff scan finds nothing to elide and we pay the scan AND the \~W\*H\*3 table slots for no return. The right renderer there is Cynosure's: hardware gpu.copy to scroll, then ONE batched gpu.set for the newly exposed line.

- Half of this already exists — bufferMode = "off" is an operator override today (screen.setBuffer). The missing half is a streaming-console writer that batches runs instead of going cell-by-cell.
- Which makes the honest framing: not "a new renderer", but "our second renderer", picked by workload. Say that out loud in the code or someone will try to unify them.

### Mostly composition of parts we already have — the work is picking them, not writing them

*Planned* · from the round *Log wall / streaming-console appliance (2026-08-10)*

Mostly COMPOSITION of parts we already have — the work is picking them, not writing them:

- kiosk.cfg for the lockdown (allowed commands, banner)
- rc.d service for the feed
- notify + mesh handlers as the event SOURCE
- boot profile + (later) a build config to strip the rest

Deliberately NOT the kernel log ring: it is 64 entries (16/32 on low RAM) and it is a KERNEL DIAGNOSTIC, not a display feed. A log wall wants to subscribe and append, not mirror a debug ring. Pick the source before building the UI.

### Open question worth settling first: is the feed local

*Planned* · from the round *Log wall / streaming-console appliance (2026-08-10)*

Open question worth settling first: is the feed LOCAL (this machine's own events) or REMOTE (mesh packets from the whole base)? Remote is the interesting one and the one that justifies a dedicated machine — but it means the log wall is a network endpoint, so it inherits the whole trust-tier question. A display that renders whatever any peer sends it is an injection surface, not a feature.

### `Service`/`cron` are read-only in the Monitor tab

*Planned* · from the round *Planned (near future)*

`service`/`cron` are read-only in the Monitor tab; consider a dedicated services pane if it earns its keep.

### Shell lexer + parser

*Idea / far future* · from the round *From the OCOS survey (2026-08-10)*

SHELL LEXER + PARSER. Only if we ever want `&&`, `||` or `$?`. Today the executor string-parses through kernel.pipe.parse, which is fine for `|` and redirects and will not stretch to conjunction or exit-status expansion. A real lexer/parser is the honest way to get there. Filed as far-future because nothing is currently ASKING for it — don't build it on spec.

### Shared getopt

*Idea / far future* · from the round *From the OCOS survey (2026-08-10)*

SHARED getopt. \~50 commands each parse their own flags. One helper would shrink all of them. Low value, low risk, good filler work for a quiet round.

### Split tabs — two or more tabs sharing one screen

*Idea / far future* · from the round *Deferred by operator: split tabs (design captured)*

SPLIT TABS — two or more tabs sharing one screen. Operator asked for it and deferred it in the same breath ("probably not as easy as it sounds"), which is right: the blocker is not the splitting, it's that EVERY APP CURRENTLY ASSUMES IT OWNS THE SCREEN. Design sketch so the work starts from a plan rather than a blank file:

1. REGIONS. Add S.regions = { {x,y,w,h, tabs={idx...}, active=n}, ... }; today's behaviour is exactly one region covering the content area. S.activeRegion picks the focused one. Tabs stay a single flat S.tabs list — a region just holds INDICES into it, so nothing about tab identity/lifecycle changes.
2. THE REAL WORK — VIEWPORTS. apps.lua contracts pass (S, tab) and every app draws with S.W/S.H and absolute coordinates. Introduce S.view = {x,y,w,h} set before each app's draw/onMouse, and convert apps to draw relative to it (ui.lua helpers do the offsetting so most app code changes by using S.view.w instead of S.W). This is the bulk of the effort and the reason to do it as its own pass; it is also independently useful (a "preview pane" or a status sidebar becomes possible).
3. INPUT. events.lua routes keys to the FOCUSED region's active tab. New binding to move focus between regions (F6 / Ctrl+arrows), plus split/unsplit verbs (a Window menu entry beats another hotkey to memorize).
4. MOUSE. mouse.lua already reads S.\_tabSpans stored at draw time (the anti-drift contract) — make those PER REGION, and a click inside a region focuses that region first.
5. TICKS. Live apps currently tick only while front; with splits, tick every VISIBLE region's active tab. Watch the cost: two live tabs = two repaints per interval on one CPU (see the multi-seat cooperative-yield lesson).
6. MINIMUM SIZES. 80x25 split vertically is 40 columns — under calc's and Monitor's usable width. Apps need a declared minW/minH in their app spec, and a region too small for its app renders a dim "needs N columns" notice instead of a corrupted layout. T1 (50x16) probably refuses splits outright.
7. PERSISTENCE. Per-user landing already exists; a saved layout would live alongside it. Defer until the rest works.

Verify with: Desktop | Shell side-by-side, then Monitor | Shell (a live tab next to an interactive one), then a too-narrow region showing the notice.

### Translate TOS to other languages by the following priority table

*Idea / far future* · from the round *Far future / ideas*

Translate TOS to other languages by the following priority table:

| Rank | Language                  | Priority                                                |
| ---: | ------------------------- | ------------------------------------------------------- |
|    1 | 🇷🇺 Russian              | **Very high**                                           |
|    2 | 🇨🇳 Simplified Chinese   | **Very high**                                           |
|    3 | 🇩🇪 German               | **Very high**                                           |
|    4 | 🇧🇷 Brazilian Portuguese | **High**                                                |
|    5 | 🇪🇸 Spanish              | **High**                                                |
|    6 | 🇫🇷 French               | **Medium-high**                                         |
|    7 | 🇵🇱 Polish               | **Medium**                                              |
|    8 | 🇯🇵 Japanese             | **Medium**                                              |
|    9 | 🇰🇷 Korean               | **Medium**                                              |
|   10 | 🇺🇦 Ukrainian            | **Lower, but worthwhile if community interest appears** |

## The project

### Licence headers — operator decision

*Planned* · from the round *The open queue, worked through (2026-10-01)*

LICENCE HEADERS -- OPERATOR DECISION. The provenance lint's other half (A PROVENANCE LINT, below) wanted every shipped .lua to carry a licence header. Today 0 of the 197 shipped files do; LICENSE.txt at the root is the whole statement. Two calls are the licence holder's, not a session's: (1) GPL-3.0-only or GPL-3.0-or-later; (2) whether the RELEASE carries it. strip.lua keeps `--!` lines (licence headers are one of the three things it keeps), so a one-line `--! SPDX-License-Identifier: GPL-3.0-or-later` costs 46 bytes in each of the 138 release files: about 6.2 KB on a Tier 2 disk the 2026-09 audit already found tight. A plain `--` header would cost nothing in the release and carry the notice in source only. Once decided, the header goes in mechanically and test\_provenance.py grows the check.

### Rc-pilot cannot be set up from its own instructions

*Planned* · from the round *The open queue, worked through (2026-10-01)*

RC-PILOT CANNOT BE SET UP FROM ITS OWN INSTRUCTIONS. Found 2026-10-03 writing the add-on READMEs. Three gaps at the seam between `rc` and the robot's chip, none of them visible to test\_rc\_pilot.lua, which hands the chip its secret directly:

- The chip reads its secret from the EEPROM DATA field, and nothing on TOS wrote that field: `flash` wrote only the code, `component eeprom setData` is refused (flash is the one EEPROM write path), and the sandbox hides the EEPROM from every program, the root `lua` prompt included. DONE 2026-10-03: `flash <file> --data` asks for it twice, masked, before anything is written, and refuses a BIOS, whose boot address and manifest anchor live in that field. test\_flash\_data.lua drives the real flash: 20 checks, 14 fail on the old code.
- The robot never says its wireless card's address, and `rc` needs it in full. A robot runs no OS and usually has no screen, so the operator has no way to read it.
- A chip with no secret ignores every frame without a sound, so a robot set up wrong looks exactly like one out of range.

Plan for the last two (a pack change, so it rides the re-sign): the chip answers an unauthenticated {op="who"} broadcast with {op="here", keyed=true|false}, presence only and never a secret, and `rc scan` lists what answers: the full address, and whether that chip has a secret. Budget: the image is 3,683 of 4,096 bytes.

### Put the compat number in the README, or decide not to

*Planned* · from the round *Second pass: the compat number (2026-09-20)*

PUT THE COMPAT NUMBER IN THE README, or decide not to. The shims above make the measured failure rate zero on both corpora, so "OpenOS compatibility, so much of what already exists still runs" can become a number. It is an EDITORIAL call, deliberately left to the operator, because the number needs its caveats alongside it or it overstates:

- a require() that resolves is not a program that works — caps, paths and terminal behaviour still differ;
- the corpora are the nine loot disks (80 programs) and three OpenPrograms repos (60 files), which is what exists and is still not everything;
- some community code targets PLAN9K, not OpenOS (magik6k's process.rt / process.globalSignals calls are Plan9k's API). Those files were never going to run here and are not counted as compat gaps.

Honest phrasing is something like "every program on the nine OpenComputers loot disks loads; the OpenOS names we do not provide were required by none of them". Then re-run the scan when the claim is made, so the number in the README is one somebody can reproduce.

### Error registry: the rest of the migration

*Planned* · from the round *Planned (near future)*

Error registry: the rest of the migration. The first slice (2026-09-10) gave tos/kernel/errors.lua its codes and tagged the refusals `why` already explained -- protected paths, permissions, the tier gates, rm's guards, the trash, unknown and unloadable commands. Everything else TOS prints in the error colour is still untagged prose: pkg, the network layer, vault, the drive and deploy commands, hardware faults (5xx-7xx are reserved and still empty). Tag them as they are touched, never renumber, and let test\_error\_registry.lua's scan of every shipped file keep each literal tag honest.

2026-10-02, the first 5xx/6xx entries, for `pkg fetch` (touched that day): E-501 ERR\_NET\_NO\_ANSWER (a repo that did not answer whether it signs its index), E-601 ERR\_PKG\_NOT\_FOUND, E-602 ERR\_PKG\_BAD\_NAME, E-603 ERR\_PKG\_DEPENDENCY. A dependency refusal drops the inner lookup's tag so it carries one code, its own. `why` explains all four; Appendix C lists them. Still untagged: the rest of pkg (install/upgrade gates), the network layer proper, vault, the drive and deploy commands, hardware.

Same day, vault and deploy (both touched that day): E-305 ERR\_VAULT\_UNLOCK, tagged at its source in kernel.vault's MAC check so every caller carries it (vault, tape-auth's log/menu, the tape toolbox), and E-306 ERR\_DRIVE\_TOO\_SMALL on deploy's pre-flight refusal. Still untagged: the rest of pkg, the network layer proper, drive format/mount failures, hardware.
