# TOS Roadmap

What is actually open. Generated from our working notes, which are not published — the notes interleave open work with a long done-history and occasional machine-local paths, so this is the extracted, scrubbed view of it. Do not hand-edit; raise an item in an issue or pull request instead.

**77 open items.** This is the honest list, including the things deliberately *not* done and the reasons why — those entries are often the most useful ones to read before proposing a change.

| Status | Count | Meaning |
|---|---:|---|
| Open bug | 1 | Known broken. Fixing one of these is the most valuable thing you can do. |
| In progress | 2 | Started, unfinished. Ask before duplicating the work. |
| Planned | 53 | Planned or under investigation. Most contributions belong here. |
| Idea / far future | 21 | Idea, no commitment. Discuss before building. |

**By area:** [Testing in the game](#testing-in-the-game) (7) · [Add-ons](#add-ons) (6) · [Packages](#packages) (11) · [Networking](#networking) (8) · [Security and accounts](#security-and-accounts) (8) · [Boot, memory and the kernel](#boot-memory-and-the-kernel) (12) · [Files and storage](#files-and-storage) (4) · [Shell and interface](#shell-and-interface) (10) · [The project](#the-project) (11)

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

### In-world checks the headless runner cannot do

*Planned* · from the round *What nobody wrote down (2026-10-26)*

IN-WORLD CHECKS THE HEADLESS RUNNER CANNOT DO. Belongs with NEXT REAL-MINECRAFT ROUND (REAL MINECRAFT ROUND, below):

- warhead (ce23a0b): no prediction has been compared with a real detonation, and the transposer's view of HBM items (fluid ids read as damage) is unverified.
- rbmk-control's hbm-ntm driver (99535a3): that a linked console answers in the shapes the fake does; what getColumnData's coordinates mean against getRBMKPos; coreTemp's units; the per-tick cost of a 225-call sweep on each CPU tier; real values for fluxWarn / fluxScram (the summed rod flux has no published scale, and the shipped config says so).
- once the mod is rebuilt and version-bumped: a FRESH world, the dungeon floppy, install from it, `about` names today's build.
- `stock` on a transposer, then a slot number from `inventory` against the same stack through inv.stacks().
- `components` with OpenSecurity's readers and door controller, an adapter on an ME controller and on an NTM battery, and the OpenGlasses terminal, recording the exact names the candidates below need.
- after the key-table fix: `keys set quit F4`, then the picker, a delete confirm, both mail UIs, intercom and `rbmk skala`.

### Next real-minecraft round

*Planned* · from the round *Real Minecraft round (2026-08-11)*

NEXT REAL-MINECRAFT ROUND — the point of these four is that they were all reachable in one sitting, so the checklist is worth more than more off-box tests:

- attach a printer and run the whole printer/write path now that the cap actually arrives
- `stock` with a transposer, which by the above analysis has NEVER worked against real hardware
- `redstone`/`robot`/`inventory` from a shell, same
- boot from a read-only disk on purpose and confirm the banner, `df` and `doctor` all say so
- a T1 (192K) box: type `reboot` under memory pressure and confirm it now explains itself
- \[headless 2026-10-09: runs end to end, U too -- MULTI-DISK checklist; still worth seeing in a real world\]
- THE TWO-FLOPPY FLOW END TO END, which has never once run correctly: insert disk 1, confirm disk 2's packages are listed and dimmed with "On disk 2 (not inserted)", tick one, install, swap when asked, confirm it finishes in ONE run. Then the same again pressing U at the prompt and confirm the already-installed packages are really gone.
- check the boot banner's RAM line against `mem` — they read from the same place now and must agree
- THE EXIT KEYS, on every full-screen program: open `write`, `calc`, `stock`, `snake`, `ttt`, `tetris`, the picker and `rc-pilot` and confirm each one can actually be left WITHOUT touching Esc. This is the check that would have caught #7 and it takes two minutes.
- press Esc in one of them anyway and confirm the expected thing happens: the Minecraft screen closes and the program is still there when you re-open it. That is not a bug any more, it is the documented behaviour — but it is worth seeing once.
- `keys list`, then `keys set quit F4`, then open ttt, calc, write and stock in turn and confirm F4 closes ALL of them and ^Q no longer does. That single sequence is the whole feature; if one program ignores it, that program is still hard-coding a scancode.
- `keys set quit ^B` must be REFUSED and say why
- `keys reset`, then confirm ^Q works everywhere again
- `menu show`, then `menu hide "Flash EEPROM"`, then `menu reset`; then the same with --system as root and as a non-admin (the second must be refused by securefs)
- put deliberate junk in \~/.menu.cfg and confirm the bar still draws

HEADLESS 2026-10-09 -- everything here a machine with no mods can show, run on the headless machine with the Optional Utilities pack:

- exit keys: calc, write &lt;file&gt;, stock, snake, ttt play, tetris and the picker all leave on ^Q. stock did NOT -- its footer said "^Q quit" and only plain Q worked (fixed, stock 1.0.1, e212a02, waiting for the pack signing). rc with no address prints its setup help.
- `keys set quit F4`: ^Q no longer leaves ttt, F4 leaves ttt, calc, write and stock; `keys set quit ^B` "is reserved by the kernel and never reaches a program"; `keys reset` brings ^Q back.
- `menu show` / `menu hide "Flash EEPROM"` (one line fewer) / `menu reset`, and the same with --system as root (/etc/menu.cfg); as a USER --system says "Save failed (needs admin for /etc)". A junk \~/.menu.cfg ("junk junk {{{ not lua"): the bar draws.
- RAM: POST "Total Memory: 2048KB", boot banner "1803K free / 2048K total", `mem` "1416K used / 2048K total" -- the totals agree.
- the two-floppy flow: see MULTI-DISK. The 192K `reboot` line is moot: TOS needs 1 MB (THE RAM FLOOR IS 1 MB below).

STILL FOR A REAL WORLD: printer/write, stock on a transposer, redstone/robot/inventory from a shell, a read-only boot disk (a managed hard drive cannot be made read-only here, and TOS does not fit a floppy), Esc closing the Minecraft screen.

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

### The distributed storage pool waits on five operator decisions

*Planned* · from the round *What nobody wrote down (2026-10-26)*

THE DISTRIBUTED STORAGE POOL WAITS ON FIVE OPERATOR DECISIONS. cluster-storage shipped 1.0.0 on 2026-10-23 as ONE node; the pool, inputs\_ref and result\_sink = "public" are not built. TOS-Extras/cluster/storage-spec-draft.md section 10 holds the questions: a coordinator or none; shared/ replication to all members or a quorum; capacity in a contributing Manager's heartbeat; what happens to a lease when its member leaves; and whether netfs read-only exports may go to PAIRED-but-untrusted peers.

### Optional Utilities candidates from the pack's own components

*Idea / far future* · from the round *What nobody wrote down (2026-10-26)*

OPTIONAL UTILITIES CANDIDATES FROM THE PACK'S OWN COMPONENTS. AUDIT 4 read every jar in the pack: nothing drives OpenSecurity, OpenGlasses, holograms, AE2, the geolyzer, printer3d or any NTM energy, radiation or non-RBMK reactor. Ranked value to the pack + value to public TOS users, 0-3 each: access control for OpenSecurity doors and readers on TOS accounts (3+2); an HBM energy monitor (3+2); a watchdog for unattended machines over mesh, notify and intercom (3+2); an AE2 source for stock (2+3); an OpenGlasses HUD (3+1); NTM radiation alarms, small enough to ride in the energy monitor (3+1); a hologram status board (2+2); a 3D-print helper (2+2); an EEPROM kit for microcontrollers and drones (2+2); a text-tools pack -- diff, sort, uniq, cut, tr, sed, hexdump, base64, sha256sum, tee, seq, sleep, yes (1+3); the other NTM reactors once rbmk-control's safety core generalises (3+1). Built since: the RBMK supervisor and the text-mode browser. Each is one package; none belongs in the base image. Confirm OpenSecurity's component names in-world first.

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

### Add-on versioning: decided 2026-09-12, not built

*Planned* · from the round *What nobody wrote down (2026-10-26)*

ADD-ON VERSIONING: DECIDED 2026-09-12, NOT BUILT. The operator's rule: MAJOR.MINOR.PATCH, an optional two-character stage suffix (-a, -b), release notes per package, no codenames. pkg already accepts and orders suffixes (validVersion, compareVersion). Left: build-disk.lua's SKIP (L528) is still a table of NAMES, empty today, so a new 0.x package ships unless someone lists it -- make it compareVersion(v, "1.0.0") &lt; 0, and decide whether a suffixed pre-1.0 package may ship labelled; the picker fits "v" .. version into 8 columns (pkgpicker.lua:584-588), so v1.10.0-b is cut; a `tos.py check` rule that a version bump carries a notes entry; blockfs.lua still says \_VERSION = "1.2.0" against its manifest's 1.2.1. Full write-up on the audit branch.

THREE OF FOUR BUILT 2026-10-26: build-disk holds back any package whose major number is 0 (preRelease), suffix or not, beside the SKIP list; the picker drops the "v" when a version would not fit its 8 cells, so 1.10.0-b shows whole; blockfs's \_VERSION matches (blockfs 1.2.2, pending re-sign), and so do mail's and intercom's, which today's quit-key bumps had made drift too. No package is 0.x today, so the pack's contents do not change. build/ test\_addon\_versions.lua (22; 6 fail on the old files) checks all three and every modules/&lt;pkg&gt;/usr/lib/&lt;pkg&gt;.lua \_VERSION against its manifest. STILL OPEN: the notes rule -- there is no per-package release notes file yet for a `tos.py check` step to look in, so where the notes live comes first; and whether a SUFFIXED pre-1.0 package may ship labelled (operator; held back for now, as every 0.x is).

### Slice 3: resolution

*Planned* · from the round *Federated package repos (2026-09-27)*

SLICE 3: RESOLUTION. Winner order: one shared copy satisfies everyone &gt; higher trust &gt; newer &gt; less disk; a tie asks. Private copies when no shared copy works; consensus and freshness across mirrors (a signature cannot stop a mirror serving an OLD signed version; agreement between repos can).

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
- OC filesystem handles support seek (OpenOS 1.8.9: lib/devfs.lua:329, lib/core/full\_buffer.lua:12), so a mount seeks to a chunk instead of reading a 140 KB package whole on a 192 KB box.

SIGNING GETS SIMPLER, NOT HARDER: pkgsign signs a manifest of per-file hashes today; one archive is one hash and one signature, the archive is immutable after install, and srm scan stops walking a package's files. Uninstall becomes one remove.

COST, and compress.lua's own header already says it: a data- card call draws a per-tick budget and can sleep the machine a tick, so this is for COLD data. Package code is read once per require, which fits; a package whose data files are read in a hot loop does not. Per-package flag, not a global mode.

No data card -&gt; compress.lua falls back to a stored blob, so the fileCost win survives without compression.

securefs must still mediate the mount point, exactly as the jbod header says ("a TRANSPORT, not an access layer").

### Operator decision: `pkg` and `service` read-only subcommands are admin-only

*Planned* · from the round *Planned (near future)*

OPERATOR DECISION: `pkg` AND `service` READ-ONLY SUBCOMMANDS ARE ADMIN-ONLY. The registry gives both tier 2, enforced at dispatch, so `pkg list/search/info` and `service list` refuse a user; the manual used to say only the changing subcommands needed admin. `srm` and `optimize` show the other pattern (tier 1, mutating subcommands gate themselves in-body). Documented as admin now; a deliberate choice either way.

### Get listed in `oppm list`

*Planned* · from the round *Planned (near future)*

Get listed in `oppm list`: a PR adding this repo to OpenPrograms/openprograms.github.io's repos.cfg. The `master` branch (build/oppm/) makes `oppm register` work; repos.cfg is what makes TOS show up for people who never heard of it.

### Install profiles: `install.lua --profile minimal|standard|full`, each writing a trimmed…

*Planned* · from the round *Planned (near future)*

Install profiles: `install.lua --profile minimal|standard|full`, each writing a trimmed system\_manifest.lua. From the 2026-09-10 follow-up review, which measured the release at 1,619 KB of content (1,695 KB on disk with fileCost) and \~353 KB free on a Tier 2 disk -- down \~102 KB in six days with the file count flat, so this is content growth, not new files. The architecture already allows it (41 pcall(require) sites in kernel/init.lua, an 11-file critical set) and it composes with `deploy drive`, which copies exactly what the manifest lists. Their measured cut -- drop the installer, docs, networking, remote pkg, the package manager, compat, peripherals and the `extras` commands -- leaves the full Commander UI at \~1,060 KB. Not urgent this week; the growth curve decides when it becomes so, and this turns a deadline into a knob.

2026-10-09: the curve got there. The release was 2,068.5 KB on disk and a 2 MB drive could not finish First Boot Setup. Minify now drops indentation (1,874 KB, \~150 KB left after first boot) and test\_release\_budget.lua fails past 1,920 KB (1b32fc9) -- the deadline is a test now, but \~46 KB of growth from it. The next lever after this one is the --! comments the release keeps (219 KB), an operator decision; then profiles.

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

### Remote exec can still reach string.dump — operator decision

*Planned* · from the round *What nobody wrote down (2026-10-26)*

REMOTE EXEC CAN STILL REACH string.dump -- OPERATOR DECISION. AUDIT 1, same source. net/remote.lua:356 copies `string` without dump, but ("").dump reaches the real one through the string metatable, which remote.lua does not touch. Harmless while TOS is open source and `load` is not exposed there; both premises can change. Decide: shadow the metatable's \_\_index in the remote environment, or record that the two premises are load-bearing.

### The browser's later steps wait on five operator decisions

*Planned* · from the round *What nobody wrote down (2026-10-26)*

THE BROWSER'S LATER STEPS WAIT ON FIVE OPERATOR DECISIONS. web 1.0.0 (e62839d) is browser-spec-draft.md's first two steps: the renderer and a browser on this machine's own card, no proxy. webproxyd, the shared cache and its cluster back end wait on that spec's section 10: auto-discover a proxy or configure one; whether cache\_read\_trust = "unknown" needs a second confirmation; whether per-call cap raising is enough for kernel.internet; the canonical URL key; and whether the proxy strips anything from a response.

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

### A headless machine keeps its boot session — operator decision

*Planned* · from the round *What nobody wrote down (2026-10-26)*

A HEADLESS MACHINE KEEPS ITS BOOT SESSION -- OPERATOR DECISION. AUDIT 1, from the pentest's "Still recorded, not changed". kernel.headlessMain (kernel/init.lua \~L3487) sets bootSession to the kernel session and never sets bootCompleted (only the screen path does, \~L1690). So on a machine with no screen, securefs.sessionOf() and users.currentSession() answer "kernel" to a caller with no process principal for the whole uptime. Nothing found runs user code there: a missing line of defence, not a hole. Decide: set bootCompleted in headlessMain and make the two agree, or record why not.

### Split the BIOS: minimal EEPROM, recovery UI in stage 2

*Planned* · from the round *Second pass: the compat number (2026-09-20)*

SPLIT THE BIOS: MINIMAL EEPROM, RECOVERY UI IN STAGE 2. Refines the item above and the 2026-09-06 BIOS pair. MineOS proves a full menu FITS in 4 KiB; OCOS argues you should not put it there anyway. Their EFI is 4,164 B of source, 3,109 B minified, and its own comment says the boot-mode menu, recovery flows and splash "live in /sys/boot.lua, where they have room to breathe". The EEPROM does the minimum: find a medium, read config, load stage 2, and on ANY failure draw a full-screen panic naming the reason.

Nearly the shape we already have -- bios.lua is a POST + loader, /init.lua is stage 2. The split:

- EEPROM: timed hotkey, BOOT-DEVICE chooser, panic screen that names the reason. Small enough to keep the manifest anchor.
- Stage 2: the rich recovery menu -- boot profiles, safe mode, srm restore, doctor, disk utility -- using the kernel's own modules.
- THE SPLIT'S WEAKNESS, stated plainly: if the DISK is what broke, stage 2 is gone and only the EEPROM half is left. Which is exactly why the EEPROM half must still be able to pick a DIFFERENT disk, and why the emergency terminal stays. Today K4, I5 and I6 end in "any key reboots" on the same saved disk: a loop. /init.lua's missing-files screen got its way out on 2026-10-02 (bootElsewhere); these are the rest. DONE 2026-10-16, in the EEPROM itself. On K4, I5 or I6 the fault screen offers "d: other disk". d makes the data field "SKP:&lt;that disk&gt;", and the next boot's scan passes it over for any other bootable disk, which goes through H1's approval. If it is the only disk it is offered again, never lost to D2. 156 bytes; the BIOS is 3,966 of 4,096 bytes and keeps test\_bios's 128-byte headroom. Off-box: test\_bios.lua, 10 new checks (4 fail on the old BIOS). Seen on the headless machine: a second bootable disk attached, the kernel moved away from outside, a powercycle, K4, then d. "Boot drive changed: d15c0000", y, and the other disk's TOS reached First Boot Setup.

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

### Build-time feature config

*Idea / far future* · from the round *From the Cynosure 2 survey (2026-08-10)*

BUILD-TIME FEATURE CONFIG. The best idea in that kernel. A .defconfig + a source preprocessor give it Linux menuconfig semantics: COMPONENT\_\* per device type, FS\_\*, NET\_\*, PART\_\*, EXEC\_\* — features compile OUT of the image. Our boot profiles (minimal/normal/full/diagnostic/safe) gate what LOADS at runtime; the code is still in the image, still on disk, still parsed the moment something requires it. On a RAM-bound box compile-time exclusion strictly dominates runtime skipping.

- We already own the machinery — strip.lua plus the manifest auto-pruning already emit a tailored tree. This is a .config on top of what build-release.sh does, not a new build system.
- Natural first axes: cluster, internet, tape, blockfs, mesh, i18n. All optional, all currently unconditional.
- Keep ONE canonical full build as the tested default. A matrix of configs nobody boots is worse than no configs — pick the variants we actually run.

SUPERSEDED (marked \[\*\] 2026-10-26) by SELF-STRIPPING, NOT BUILD-TIME CONFIG above, the operator's 2026-08-11 decision; kept for the Cynosure argument. Scheduled in THE OS-SURVEY SUGGESTIONS.

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

### Six surfaces still ignore the key table

*Planned* · from the round *What nobody wrote down (2026-10-26)*

SIX SURFACES STILL IGNORE THE KEY TABLE. AUDIT 2. shell.keys is read by the panels core, calc, write, warhead, web, stock, rc-pilot and the games. It is not read by the package picker (its legend says "Q Quit", pkgpicker.lua:743; it takes a typed "q", :1024), panels/dialogs.lua, either mail UI (mailapp.lua tests for 17, ^Q), intercomapp.lua or the rbmk SKALA panel. After `keys set quit F4` those six still answer ^Q, which is what the REAL MINECRAFT round's F4 check exists to catch. Severity LOW-MEDIUM. Pin: usr/lib/tests/test\_keys\_readers.lua (audit branch).

BASE HALF FIXED 2026-10-26: the picker and panels/dialogs.lua ask shell.keys for quit (a text field never takes a printable binding as quit). Found on the way, both in the picker: its filter prompt's undo was Esc ALONE, which real Minecraft never delivers, so in-game it had none; and at 80 columns its key bar (86 wide) was cut at "Enter In…", so the way out was never on screen -- it is ordered most-needed first now and packs to 70 when it must. A new test\_keys\_readers.lua on master DRIVES the dialogs on a fake keys.cfg (quit = F4; 8 fail on the old files) and lifts the picker's helpers. SEEN on the runner: `keys set quit F4`, `pkg install` -&gt; bar "Space·Enter Install·F4 Quit·/ Filter·G Group·A All·N None·R +Suggested"; in the filter ^Q did nothing and F4 undid; in the list ^Q did nothing and F4 left. THE PANELS, SAME DAY: the audit's six were not all. 22 hand-written ^Q tests were left in tos/shell: the menus, the power prompt, the cmdline, the viewer, the editor, and the chat, monitor, settings and desktop tabs all ignored the table. They ask keys.isQuit now (new, with keys.quitHint for one-line hints; the power prompt says "\[F4\]Cancel"). One more found on the runner: F4 is the panels' close-tab key and it was swallowed on the SHELL tab too, where it closes nothing, so the manual's own `keys set quit F4` could never clear the command line; it falls through there now. SEEN on the runner with quit = F4: ^Q left "abcdef" on the line and F4 cleared it; F10's prompt read "\[F4\]Cancel", ignored ^Q, closed on F4. test\_keys\_readers.lua (37) lists every ^Q test left in the shell with its reason, so a new one fails. STILL OPEN: (1) the CLI path -- cli.lua's prompt, CLI chat, login's two prompts, the tutorial, and kernel/init.lua's notice viewer. CLI mode never loads shell.keys and requiring it there costs heap on the 1 MB floor, so these wait for a `tos.py floorcheck` run; pinned as exceptions in the test. (2) the add-on half (both mail UIs, intercomapp, rbmk SKALA), which needs the pack re-signed.

ADD-ON HALF BUILT 2026-10-26, AWAITING THE RE-SIGN: mail 1.0.1, intercom 1.0.2 and rbmk-control 1.0.1 ask shell.keys (a local isQuit over keys.is, so they still run on an older base) and their hints name the key. SKALA was worse than listed: it quit on a bare Q or Esc only (^Q is char 17, not "Q"; F10 was never read), so in-game the letter was the only way out. All three are in PENDING\_RESIGN. test\_keys\_readers.lua (57) lifts and runs each one's helper. SEEN on the runner from an unsigned scratch pack (--machines 2, for the network card): the mail tab's bar read "F4 Close", ^Q did nothing, F4 closed it. THE HINTS, SAME DAY: the viewer's and editor's footers, the chat, monitor and settings key bars and the help text still printed ^Q whatever the binding; they call keys.quitHint now. SEEN: after `keys set quit F4`, `help`'s viewer footer read "\[F4\]Close", ^Q did nothing and F4 closed it. Left as is: the desktop's key bar, an i18n string (desktop.keys) whose catalogs would all need the change -- the desktop does close on the quit key.

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

### The release has shipped without its `--!` comments since 2026-10-17, the MIT credit…

*Planned* · from the round *What nobody wrote down (2026-10-26)*

THE RELEASE HAS SHIPPED WITHOUT ITS `--!` COMMENTS SINCE 2026-10-17, THE MIT CREDIT INCLUDED. Found by this sweep. build/strip.lua's contract is "--! Preserve this comment in dist", for #SEC notes, cross-file invariants and licence / attribution headers. --minify-vars (bb6b2e4, the release default) re-emits each file through LuaMinify's formatter, which writes no comments at all, and that commit does not mention it. The shipped sources hold 3,560 `--!` lines (\~217 KB); today's TOS-Release holds 7, all in the rc.d scripts that get the whitespace pass only. So tos/compat/internet.lua's PROVENANCE note -- parts follow OpenOS's lib/internet.lua (MIT licence) line for line, credited for that reason -- is gone from the release and from the published main. test\_provenance.py cannot see it: it checks that the SOURCE carries a `--!` credit, which was enough while `--!` survived. The add-on pack (092df1e) goes through the same pass. This also settles, silently, the operator decision the RAM and storage entries below still list as open ("dropping the --! comments from the release (219 KB)"). OPERATOR DECISION, in effect made by accident: either keep `--!` through the renamer (the release is 1,292 KB raw, so \~217 KB more still fits the 1,920 KB budget), or accept that the release carries no comments, and then move the MIT credit somewhere that ships (a NOTICE file beside LICENSE.txt, or a string) and say so in strip.lua. Either way, a test on the BUILT tree that the credit is there.

THE CREDIT IS FIXED, 2026-10-26; the rest is still the decision. minify\_vars.noticesOf puts back, at the top of the file, every `--!` paragraph whose first word is PROVENANCE., Copyright or SPDX-License-Identifier: (read from the unstripped file -- from the stripped one the credit ran on into the #SEC note after it). strip.lua's marker convention says so. internet.lua's 425 bytes are the only notice shipped today. test\_release\_credits.lua (14) checks the built TOS-Release; its built-tree checks fail on the old build. So the decision left is only whether #SEC notes and invariants ship (\~217 KB), no longer a licence question. Marked \[ \], not \[!\]: nothing is broken while it waits.

### The tier 1 gap, re-measured

*Planned* · from the round *What nobody wrote down (2026-10-26)*

THE TIER 1 GAP, RE-MEASURED. AUDIT 2 put a full install 773 KB over a 1,024 KB drive (1,797 KB on a managed disk). Dedenting and renaming have since happened: today it is 1,354 KB (1,292 KB of files plus 512 B of fileCost for each of 170 files and 15 dirs), so 330 KB over. What is left is profiles (Install profiles, below) and fileCost (the 21 man pages are 49 KB plus 10.5 KB of fileCost). The `--!` lever is spent, see above.

### The loot disk is whatever TOS-Release was when the mod last built

*Planned* · from the round *What nobody wrote down (2026-10-26)*

THE LOOT DISK IS WHATEVER TOS-Release WAS WHEN THE MOD LAST BUILT. AUDIT 1 found Irradiated Circuits (radbridge 0.4.0) bundling TOS 1.4.0. Its newest jar, radbridge-0.5.0 (built 2026-10-09, unreleased), carries that day's release: its kernel/init.lua differs from today's, and kernel/x25519.lua and curve25519field.lua are absent. The fix is in the mod's repo: rebuild, and bump the mod version, because LootDiskInstaller stamps the extracted disk with it and an unchanged version never reaches an existing world. Nothing on this side notices the drift. Wanted: a `tos.py check` step that, when it can find a radbridge jar, compares its bundled system\_manifest.lua with TOS-Release's.

THE CHECK IS BUILT, 2026-10-26: build/check\_lootdisk.py, a step of `tos.py check`. It finds the newest radbridge-X.Y.Z.jar (or --jar / $TOS\_LOOTDISK\_JAR), compares assets/radbridge/loot/tos/ with TOS-Release file by file, and names what differs. Advisory (exit 0; --strict fails): the mod is its own repo, and a stale disk is no reason to hold a TOS publish. build/test\_check\_lootdisk.py (6). Today it says radbridge-0.5.0.jar's disk is build 1448305: 143 files differ and 6 are missing (x25519, curve25519field, pkgops, diskmount, open + its man page). STILL OPEN, in the mod's repo and so not done here: rebuild radbridge against this release and bump its version.

### See the 2026-10-17..24 work run

*Planned* · from the round *What nobody wrote down (2026-10-26)*

SEE THE 2026-10-17..24 WORK RUN. Built and tested off-box only, and each can be checked on the headless runner:

- Diffie-Hellman (e2f2445): SEEN 2026-10-26, once something sent a HELLO (AUTOMATIC DIFFIE-HELLMAN NEVER RAN, above). On the runner's T2 APU both sides had derived, and the sealed send was accepted, within 5 s of the second `net trust`: two X25519s and the HELLO round trip. One X25519 alone is untimed.
- the mesh route cache (279ec4b): learning needs a relay in the middle, three nodes, and the runner does two. Grow it to three, or accept test\_meshctl's three-node simulation.
- cluster-storage (d6963fb): a Master and a Storage Node on two machines exchanging STORE\_PUT and PUB frames -- that commit's own "not verified". The node needs a wired or Tier-2 modem.
- chat's wrapped lines and mail's Sent: line (49dec7a).
- the browser (web 1.0.0): SEEN 2026-10-26, and it had never worked. Its first fetch died: "pkg:web:36: attempt to call a nil value (field 'get')". web took require("internet"), which in the sandbox is OpenOS's library (request/socket/open); the kernel wrapper with get() is the `internet` GLOBAL. Its tests stubbed require("internet") with a get. Fixed in web 1.0.1 (pending re-sign); test\_web\_ui.lua's fake sandbox now has the real shape and fails 10 of 14 on 1.0.0. Then, from an unsigned scratch pack with --internet: http://info.cern.ch/ rendered with its heading, four numbered links and the references list; 1 + Enter opened TheProject.html, b came back, ^Q left. A LOCAL http server is not reachable: the card's filteringRules deny private addresses, and adding "allow 127.0.0.1" to a copy of the config disabled HTTP altogether in this Ocelot build -- so the run used a public page.
- PaneUI (c8a76b9) on OpenOS 1.8.9; the runner booted OpenOS for e33d25c. PaneUI's tests check source grammar only, so its event loop and the new wrapText have never run.
- bootstrap.lua end to end ("nothing ran bootstrap.lua end to end", e33d25c) from a local http server serving a TOS-Release tree.

### GitHub, now that CI has run

*Planned* · from the round *What nobody wrote down (2026-10-26)*

GITHUB, NOW THAT CI HAS RUN. CI, Issue triage and Push on dev have all run green on dev (Actions API, 2026-10-26).

- OPERATOR DECISION: no branch is protected (dev, main, master, optional-utilities all "protected": false, 2026-10-26). The triage round left that for after CI had proved green on GitHub, and it has.
- triage's match thresholds (list 0.35, label 0.60) were tuned on CHANGELOG and ROADMAP text. Re-check them on the first real reports; there are none yet.
- Dependabot opens its PRs against dev, which publish.ps1 replaces whole, so a bump is taken in the workflow source and the PR closed by hand, as PR #1 was. Nothing automates that, by the never-decline rule.

### Build the survey suggestions in this order, after the bugs

*Planned* · from the round *The os-survey suggestions, scheduled (2026-10-26)*

BUILD THE SURVEY SUGGESTIONS IN THIS ORDER, AFTER THE BUGS. Work starts on this list only once the open \[!\] entries and the bug entries in WHAT NOBODY WROTE DOWN are done or waiting on the operator. Each line points at the entry that holds the design; the design stays there, this is only the order and the reason. Ordered by what each unblocks, then by value to an operator against its cost.

1. ADDRESSABLE LOCAL IPC (survey 5; WHAT THE REST OF THE FIELD). First because two open bugs wait on it: the cluster CLIs' option (b) (\[!\] THE CLUSTER CLIs CANNOT RUN IN THE SANDBOX) and rc-pilot hearing its robot (RC-PILOT CANNOT BE SET UP). A registered, cap-gated endpoint per service.
2. SELF-STRIPPING, FIRST STEP ONLY (Cynosure, \[\~\]). The floor: system\_manifest `floor = true` and the test that the floor is closed under require. Buildable and safe on its own (it deletes nothing), and it is what the Tier 1 gap (330 KB over a 1 MB drive, re-measured above) needs before any stripping UI can be honest. The UI and the strip itself come later.
3. DRY-RUN CAPABILITY ENFORCEMENT + AN AUDIT LOG OF DENIALS (survey 16; OCOS \[\*\]). One piece of work: log what the sandbox refuses, then a mode that logs instead of refusing. How the audit mode is exposed is an operator decision already batched; the log half needs none.
4. A RECOVERY MENU IN THE BIOS, VIA THE SPLIT (survey 1 + 17). The split (minimal EEPROM, recovery UI in stage 2) is the shape that fits the 4 KiB budget bios.lua already strains. Needs a real-Minecraft or runner boot round to land.
5. A DRIVER REGISTRY WITH PER-DEVICE PROBING (survey 4).
6. CONSOLIDATE THE SECURITY POLICY INTO ONE FILE (KittenOS). component\_caps.cfg and pkg\_caps.cfg already exist; this is one place that says who may do what.
7. SHARED getopt (OCOS \[\*\]). \~50 commands parse their own flags; pkg's unknownOption refusal is the model to share.
8. LOCALISE THE INSTALLER (survey 10). install.lua has no i18n at all today; the OS has catalogs.
9. MOUNT PACKAGES AS READ-ONLY ARCHIVES, IN mtar (survey 2 + 18). Disk, not RAM; large; wants the floor (2) first.
10. COPY-ON-WRITE OVERLAY MOUNTS (survey 3). Builds on 9.
11. A SHELL LEXER + PARSER for &amp;&amp; and || (OCOS \[\*\]).
12. /proc-STYLE READ-ONLY INTROSPECTION (Cynosure \[\*\]).
13. FAR: RUN-THIS-ONCE CONFINEMENT (survey 11), "ASK" AS A THIRD STATE (KittenOS), LINE DISCIPLINES (survey 19), the LOG WALL appliance (settle its local-or-feed question first).

NOT ON THIS LIST, because they are the operator's to decide, not to build: the boot battery in CI (it runs on the headless runner today; the CI host is the open question), and PUT THE COMPAT NUMBER IN THE README (an editorial call).

### Licence headers — operator decision

*Planned* · from the round *The open queue, worked through (2026-10-01)*

LICENCE HEADERS -- OPERATOR DECISION. The provenance lint's other half (A PROVENANCE LINT, below) wanted every shipped .lua to carry a licence header. Today 0 of the 197 shipped files do; LICENSE.txt at the root is the whole statement. Two calls are the licence holder's, not a session's: (1) GPL-3.0-only or GPL-3.0-or-later; (2) whether the RELEASE carries it. strip.lua keeps `--!` lines (licence headers are one of the three things it keeps), so a one-line `--! SPDX-License-Identifier: GPL-3.0-or-later` costs 46 bytes in each of the 138 release files: about 6.2 KB on a Tier 2 disk the 2026-09 audit already found tight. A plain `--` header would cost nothing in the release and carry the notice in source only. Once decided, the header goes in mechanically and test\_provenance.py grows the check.

### Rc-pilot cannot be set up from its own instructions

*Planned* · from the round *The open queue, worked through (2026-10-01)*

RC-PILOT CANNOT BE SET UP FROM ITS OWN INSTRUCTIONS. Found 2026-10-03 writing the add-on READMEs. Three gaps at the seam between `rc` and the robot's chip, none of them visible to test\_rc\_pilot.lua, which hands the chip its secret directly:

- The chip reads its secret from the EEPROM DATA field, and nothing on TOS wrote that field: `flash` wrote only the code, `component eeprom setData` is refused (flash is the one EEPROM write path), and the sandbox hides the EEPROM from every program, the root `lua` prompt included. DONE 2026-10-03: `flash <file> --data` asks for it twice, masked, before anything is written, and refuses a BIOS, whose boot address and manifest anchor live in that field. test\_flash\_data.lua drives the real flash: 20 checks, 14 fail on the old code.
- The robot never says its wireless card's address, and `rc` needs it in full. A robot runs no OS and usually has no screen, so the operator has no way to read it.
- A chip with no secret ignores every frame without a sound, so a robot set up wrong looks exactly like one out of range.
- `rc` can never HEAR the robot, which blocks the obvious fix for both of the above. Found 2026-10-03 designing it: the package sandbox's pullSignal drops every modem\_message (kernel/sandbox.lua PULL\_DROP, the anti-sniffing rule), and the `net` capability carries only TOS-protocol message types, which a bare-EEPROM robot does not speak. So the pong after `P` has never been shown on a real machine -- test\_rc\_pilot handed the host a raw pullSignal and could not see it -- and a discovery reply would be dropped the same way. Pinned as a \[known gap\] in test\_rc\_pilot.lua through the REAL sandbox pullSignal, so a fix fails that line and it gets rewritten.

OPERATOR DECISION, deliberately not made here, because it changes what a sandboxed package may hear:

(a) a program holding peripheral.modem receives modem\_message

for ports IT opened through its gated modem proxy, and only

those, with every port the kernel uses (TOS net, mesh,

cluster, rbmk telemetry) refused at open(). Narrow, and the

shape OpenOS programs expect; the sandbox must track opens

per process and close them on exit;

(b) the same through ADDRESSABLE LOCAL IPC when that exists (WHAT

THE REST OF THE FIELD DOES BETTER, below);

(c) leave raw receive closed: `rc` stays send-only, the pong

display goes, and the address has to come from the world

(whether an Analyzer shows a robot's network card, or a card

keeps its address when moved from a computer into the

Assembler, is an in-game check). Recommendation: (a). Then, as one pack change riding one signing: the chip answers an unauthenticated {op="who"} broadcast with {op="here", keyed=true|false, kind="robot"|"drone"}, presence only and never a secret; it beeps once at start when it has no secret; and `rc scan` lists what answers. Budget: the image is 3,683 of 4,096 bytes.

### Put the compat number in the README, or decide not to

*Planned* · from the round *Second pass: the compat number (2026-09-20)*

PUT THE COMPAT NUMBER IN THE README, or decide not to. The shims above make the measured failure rate zero on both corpora, so "OpenOS compatibility, so much of what already exists still runs" can become a number. It is an EDITORIAL call, deliberately left to the operator, because the number needs its caveats alongside it or it overstates:

- a require() that resolves is not a program that works — caps, paths and terminal behaviour still differ;
- the corpora are the nine loot disks (80 programs) and three OpenPrograms repos (60 files), which is what exists and is still not everything;
- some community code targets PLAN9K, not OpenOS (magik6k's process.rt / process.globalSignals calls are Plan9k's API). Those files were never going to run here and are not counted as compat gaps.

Honest phrasing is something like "every program on the nine OpenComputers loot disks loads; the OpenOS names we do not provide were required by none of them". Then re-run the scan when the claim is made, so the number in the README is one somebody can reproduce.

### Operator decision: should /usr/lang be admin-writable

*Planned* · from the round *Planned (near future)*

OPERATOR DECISION: SHOULD /usr/lang BE ADMIN-WRITABLE? Language catalogs live there, and /usr is a protected system path, so adding one by hand takes root and `protect off` (found 2026-10-16: `lang dump /usr/lang/xx.lang` was refused for root; the refusal and the route are now shown, 5d62fad). Catalogs are DATA, parsed by the safe decoder and never run, and a bad %-spec falls back to English, so securefs's TREE\_EXEMPT could take "/usr/lang/" the way it takes "/etc/widgets/": admins could then write catalogs and nobody below admin could. The cost is that a tampered admin session could reword the login screen. Either add the exemption, or keep `protect off` and packages as the only routes in.

### Error registry: the rest of the migration

*Planned* · from the round *Planned (near future)*

Error registry: the rest of the migration. The first slice (2026-09-10) gave tos/kernel/errors.lua its codes and tagged the refusals `why` already explained -- protected paths, permissions, the tier gates, rm's guards, the trash, unknown and unloadable commands. Everything else TOS prints in the error colour is still untagged prose: pkg, the network layer, vault, the drive and deploy commands, hardware faults (5xx-7xx are reserved and still empty). Tag them as they are touched, never renumber, and let test\_error\_registry.lua's scan of every shipped file keep each literal tag honest.

2026-10-02, the first 5xx/6xx entries, for `pkg fetch` (touched that day): E-501 ERR\_NET\_NO\_ANSWER (a repo that did not answer whether it signs its index), E-601 ERR\_PKG\_NOT\_FOUND, E-602 ERR\_PKG\_BAD\_NAME, E-603 ERR\_PKG\_DEPENDENCY. A dependency refusal drops the inner lookup's tag so it carries one code, its own. `why` explains all four; Appendix C lists them. Still untagged: the rest of pkg (install/upgrade gates), the network layer proper, vault, the drive and deploy commands, hardware.

Same day, vault and deploy (both touched that day): E-305 ERR\_VAULT\_UNLOCK, tagged at its source in kernel.vault's MAC check so every caller carries it (vault, tape-auth's log/menu, the tape toolbox), and E-306 ERR\_DRIVE\_TOO\_SMALL on deploy's pre-flight refusal. Still untagged: the rest of pkg, the network layer proper, drive format/mount failures, hardware.

2026-10-10, pkg's install copy (touched that day for the floor check): E-604 ERR\_PKG\_FILE\_MISSING and E-605 ERR\_PKG\_FILE\_UNREADABLE. The second is what an install that runs out of memory reading a file now carries. `why` tells it to free memory or add a stick.

2026-10-16, federated slice 2's floor: E-606 ERR\_PKG\_UNTRUSTED\_SOURCE. Same day, the rest of pkg's install and upgrade gates: E-607 unverified (no hashes), E-608 hash mismatch, E-609 a signature that does not verify, E-610 `pkg trust require on`, E-611 the wrong publisher (a pin, or an upgrade's key change), E-612 a protected target, E-613 a conflict (test\_pkg\_refusal\_codes.lua drives each through the real pkg.install). Still untagged: the network layer proper, drive format/mount failures, hardware.
