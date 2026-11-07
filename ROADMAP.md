# TOS Roadmap

What is actually open. Generated from our working notes, which are not published — the notes interleave open work with a long done-history and occasional machine-local paths, so this is the extracted, scrubbed view of it. Do not hand-edit; raise an item in an issue or pull request instead.

**45 open items.** This is the honest list, including the things deliberately *not* done and the reasons why — those entries are often the most useful ones to read before proposing a change.

| Status | Count | Meaning |
|---|---:|---|
| Open bug | 0 | Known broken. Fixing one of these is the most valuable thing you can do. |
| In progress | 2 | Started, unfinished. Ask before duplicating the work. |
| Planned | 25 | Planned or under investigation. Most contributions belong here. |
| Idea / far future | 18 | Idea, no commitment. Discuss before building. |

**By area:** [Testing in the game](#testing-in-the-game) (6) · [Add-ons](#add-ons) (5) · [Packages](#packages) (7) · [Networking](#networking) (3) · [Security and accounts](#security-and-accounts) (3) · [Boot, memory and the kernel](#boot-memory-and-the-kernel) (7) · [Files and storage](#files-and-storage) (2) · [Shell and interface](#shell-and-interface) (7) · [The project](#the-project) (5)

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
- docs/screenshots/rbmk.png: the supervisor's core map on a linked console, 640x400 at 80x25 (SHOTS.md has the method). The README shows files.png in its place until it exists.

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

SINCE, ON THE RUNNER (2026-11-01..07): a read-only boot disk (--readonly-boot, 802e916: noticed, and the copy-to-hard-drive offer run end to end); stock on a stand-in transposer (stock 1.0.3); and `redstone` and `inventory` from a shell, which had NEVER worked: the shell held no caps at all (f647ab8), `redstone set` lied about bad levels (c3e5c03), plain `inventory` could not read (c1f5944). The runner gained --redstone for it. LEFT FOR A REAL WORLD, each needing what Ocelot does not have: printer/write (OpenPrinter), `robot` from a shell (TOS running inside a robot body), stock against a real chest with many slots, Esc closing the Minecraft screen.

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

### Run a verification round in real Minecraft OpenComputers

*Planned* · from the round *Planned (near future)*

Run a verification round in REAL Minecraft OpenComputers: the Ocelot emulator has been running at \~6 TPS (cause unknown), which makes testing sluggish and may distort timing-sensitive behaviour (waits, live refresh, cooperative yields). Real-MC results are the ground truth anyway.

## Add-ons

### The distributed storage pool waits on five operator decisions

*Planned* · from the round *What nobody wrote down (2026-10-26)*

THE DISTRIBUTED STORAGE POOL WAITS ON FIVE OPERATOR DECISIONS. cluster-storage shipped 1.0.0 on 2026-10-23 as ONE node; the pool, inputs\_ref and result\_sink = "public" are not built. TOS-Extras/cluster/storage-spec-draft.md section 10 holds the questions: a coordinator or none; shared/ replication to all members or a quorum; capacity in a contributing Manager's heartbeat; what happens to a lease when its member leaves; and whether netfs read-only exports may go to PAIRED-but-untrusted peers.

DRAFT ANSWERS 2026-11-05, as asked: section 10 of the spec now holds a recommendation for each, with its cost. Nothing is built until they are approved or changed.

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

### Sign a release (operator)

*Planned* · from the round *Found by round trips on the runner (2026-11-06)*

SIGN A RELEASE (operator). main is the signed build 07bf795; every fix above reaches a bootstrap install only after `tos.py sign-release` and a main publish. Five of them lose data silently.

### Add-on versioning: decided 2026-09-12, not built

*Planned* · from the round *What nobody wrote down (2026-10-26)*

ADD-ON VERSIONING: DECIDED 2026-09-12, NOT BUILT. The operator's rule: MAJOR.MINOR.PATCH, an optional two-character stage suffix (-a, -b), release notes per package, no codenames. pkg already accepts and orders suffixes (validVersion, compareVersion). Left: build-disk.lua's SKIP (L528) is still a table of NAMES, empty today, so a new 0.x package ships unless someone lists it -- make it compareVersion(v, "1.0.0") &lt; 0, and decide whether a suffixed pre-1.0 package may ship labelled; the picker fits "v" .. version into 8 columns (pkgpicker.lua:584-588), so v1.10.0-b is cut; a `tos.py check` rule that a version bump carries a notes entry; blockfs.lua still says \_VERSION = "1.2.0" against its manifest's 1.2.1. Full write-up on the audit branch.

THREE OF FOUR BUILT 2026-10-26: build-disk holds back any package whose major number is 0 (preRelease), suffix or not, beside the SKIP list; the picker drops the "v" when a version would not fit its 8 cells, so 1.10.0-b shows whole; blockfs's \_VERSION matches (blockfs 1.2.2, pending re-sign), and so do mail's and intercom's, which today's quit-key bumps had made drift too. No package is 0.x today, so the pack's contents do not change. build/ test\_addon\_versions.lua (22; 6 fail on the old files) checks all three and every modules/&lt;pkg&gt;/usr/lib/&lt;pkg&gt;.lua \_VERSION against its manifest. STILL OPEN: the notes rule -- there is no per-package release notes file yet for a `tos.py check` step to look in, so where the notes live comes first; and whether a SUFFIXED pre-1.0 package may ship labelled (operator; held back for now, as every 0.x is).

### Slice 3: resolution

*Planned* · from the round *Federated package repos (2026-09-27)*

SLICE 3: RESOLUTION. Winner order: one shared copy satisfies everyone &gt; higher trust &gt; newer &gt; less disk; a tie asks. Private copies when no shared copy works; consensus and freshness across mirrors (a signature cannot stop a mirror serving an OLD signed version; agreement between repos can).

UPDATES FROM REPOS, BUILT 2026-11-05, ahead of the rest because it was a hole, not a refinement: a package installed with `pkg fetch` was never offered an update, since `pkg outdated` read mounted disks only and `pkg upgrade` could not fetch. Both read configured repos now, and the upgrade runs on the staged copy with every gate it has. SEEN against the real optional-utilities branch: snake 1.0.0 from a disk was listed, then upgraded to the signed 1.0.1.

Still not built: known repos (an upgrade has no floor, so it only reads configured ones), the winner order, private copies, mirror consensus.

WINNER ORDER DRAFTED 2026-11-06, NOT MERGED (the draft is kept apart from the release until it is finished). pkg.plan ranks every root's copy (shared copy in passes, claimed-signer trust, newer, smaller; ties to opts.chooseCopy or the earliest root, recorded in plan.ties), with slice 1's own-disk rule above it; the decisions are in docs/FEDERATED-REPOS.md. The existing package tests pass on it. Before merging: its own test (test\_pkg\_winner\_order.lua, named in the code, not written), the full suite and selftest, ties shown by `pkg install --dry-run`, and the shell passing a chooseCopy that asks.

WINNER ORDER MERGED 2026-11-06 with all four: test\_pkg\_winner\_order.lua (47; 22 of its first 42 fail on the old first-found code), the shell's chooseCopy (a box per other copy, --yes and seats that cannot ask keep the earliest; test\_pkg\_tie\_shell.lua, 26), ties in --dry-run and in every install's output, suite and selftest green. Two things the draft had wrong, both found by running it: the passes asked the operator the same question once per pass (answers are remembered now), and two unhashed copies with one package.lua and different files counted as identical, so a real tie was never asked (the files are compared when the manifest has no hashes). SEEN on the headless runner: --dry-run showed the tie, the box named both paths, "Use other" installed the other disk's file.

Still not built: known repos for upgrades, private copies, mirror consensus, upgrading a shared dependency.

FOUND ON THE WAY, the operator's call: a fresh machine does not trust the Optional Utilities key, so everything fetched from the official repo says "valid, but the key was not trusted at install time". Shipping it trusted would make that read "trusted", and would make the key the one that decides what installs without asking.

ANSWERED 2026-11-05: the installer asks whether to trust the Optional Utilities key, showing its fingerprint, and the operator decides (8bda89c). Seen through real GitHub on 2026-11-06: a signed install answered yes lists discover at 335F F7B2 43C5 1D97.

### Get listed in `oppm list`

*Planned* · from the round *Planned (near future)*

Get listed in `oppm list`: a PR adding this repo to OpenPrograms/openprograms.github.io's repos.cfg. The `master` branch (build/oppm/) makes `oppm register` work; repos.cfg is what makes TOS show up for people who never heard of it.

### Slice 4: discovery and revocation

*Idea / far future* · from the round *Federated package repos (2026-09-27)*

SLICE 4: DISCOVERY AND REVOCATION. Opt-in bounded crawl over index `siblings`; signed revocation/rotation notices (revocations honoured automatically, successors never trusted automatically); in-world repos over the modem network; namespaced names.

### Not done, deliberate: OPPM's master list

*Idea / far future* · from the round *Internet card + remote pkg round (2026-08-04)*

NOT DONE, deliberate: OPPM's MASTER LIST (the index-of- indexes at openprograms.github.io that lets `oppm` search every registered repo). TOS works one repo at a time by URL. Adding it means trusting a list of hosts you did not write down, which is exactly what the allowlist exists to prevent — it needs an operator-facing "add all of these?" step, not a silent federation.

### Later: teach `pkg install` to refresh the baseline for files it replaces, so an upgrade…

*Idea / far future* · from the round *SRM round (2026-07-28)*

Later: teach `pkg install` to refresh the baseline for files it replaces, so an upgrade doesn't leave scan crying drift on every file it legitimately changed. Today that needs a manual `srm baseline` after upgrading (scan says so).

## Networking

### The browser's later steps wait on five operator decisions

*Planned* · from the round *What nobody wrote down (2026-10-26)*

THE BROWSER'S LATER STEPS WAIT ON FIVE OPERATOR DECISIONS. web 1.0.0 (e62839d) is browser-spec-draft.md's first two steps: the renderer and a browser on this machine's own card, no proxy. webproxyd, the shared cache and its cluster back end wait on that spec's section 10: auto-discover a proxy or configure one; whether cache\_read\_trust = "unknown" needs a second confirmation; whether per-call cap raising is enough for kernel.internet; the canonical URL key; and whether the proxy strips anything from a response.

DRAFT ANSWERS 2026-11-05, as asked: section 10 of the spec now holds a recommendation for each, with its cost. Nothing is built until they are approved or changed.

### The canonical number format is still architecture-dependent

*Planned* · from the round *Extras sweep 2: the packaging seam (2026-09-06)*

THE CANONICAL NUMBER FORMAT IS STILL ARCHITECTURE-DEPENDENT. The fix above removes the only float that crosses the wire; it does not make the FORMAT safe for the next one. A field carrying an integral float still canonicalizes differently on 5.2 and 5.3. The fix is one line in each half -- render numbers with a subtype-independent rule ("%d" when the value is integral, else "%.14g") -- but it changes the MAC for every frame, so both sides must be upgraded together AND the OpenOS worker is hand-copied to each worker box. Worth doing at the next protocol version bump, not on its own.

### Later: per-group mesh sealing

*Idea / far future* · from the round *Intercom round (2026-07-28)*

Later: per-group mesh sealing (today a group send is N sealed unicasts, which is correct but O(N) floods); and letting `intercom cue add` write catalog lines from the shell instead of hand-editing /etc/intercom.cues.

## Security and accounts

### Who may manage accounts, read the log, use scp

*Planned* · from the round *Second pass: the compat number (2026-09-20)*

WHO MAY MANAGE ACCOUNTS, READ THE LOG, USE SCP. Found 2026-10-03 walking the README's new "first ten minutes" on the headless machine: five commands' REGISTRY tier disagreed with the gate their own body runs. useradd/userdel/usermod were registered ADMIN (and documented admin in MANUAL 3.3 and ch.14) but call rootOnly; log and scp were registered USER ("log: filtered by tier") but call adminOnly. So `help` offered admins (users) a command that then refused them. Fixed the safe way: the registry and MANUAL now follow the code (no change in who can do what), and test\_command\_gate\_tiers.lua fails on any future mismatch.

DECISION NEEDED, if any should be LOOSER: kernel users.create already accepts an ADMIN creator (effective tier &gt;= ADMIN), so admin account management is a one-word change in admin.lua -- but usermod's admin/root promotions and userdel need checking against users.setTier/delete's own guards first. `log` "filtered by tier" implies a user-visible log that the body has never allowed.

ACCOUNTS DECIDED 2026-11-05, the operator's answer: "up to the Operator with Root being the default". The installer asks, root changes it with `users manage root|admins`, and with admins allowed an admin manages ordinary accounts only and never makes an admin (test\_accounts\_policy). SEEN on the runner both ways. `log` and `scp` are still as found.

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

### Next if still tight: i18n catalogs, and the display-layer work already queued in the OC…

*Planned* · from the round *Memory round (2026-07-24)*

NEXT if still tight: i18n catalogs, and the display-layer work already queued in the OC optimization playbook.

### Support-ceiling policy (design decision, operator-approved direction)

*Planned* · from the round *Polish - operator feedback (round 4)*

Support-ceiling policy (design decision, operator-approved direction): instead of degrading everything for T1 GPUs / tiny RAM, set a floor - refuse to boot (clean message) or fall back to the CLI shell on hardware below it. Sweep the T1/low-RAM special cases once decided.

### Line disciplines — direction, not a task, and expensive

*Idea / far future* · from the round *Second pass: the compat number (2026-09-20)*

LINE DISCIPLINES -- direction, not a task, and expensive. Their comment is the clearest statement of it (Cynosure 2, src/disciplines/main.lua): a line discipline is "a middle layer between the raw stream and the character device... the TTY line discipline is what makes ctrl-C, ctrl-\\, and ctrl-Z work. This line discipline can be put over a network socket, a serial connection, or a virtual TTY provided by the kernel - and the application (ideally the user, too) will see no difference in behavior."

THREE OF OUR PROBLEMS ARE ONE PROBLEM IN THAT FRAMING:

- H-04 (open): term.read() takes signals off the machine-wide queue. A per-stream input queue with a discipline in front is where that read should get its characters.
- H-06 (open): two sandboxes share compat.term's cursor. A discipline instance per stream owns its own line state.
- rsh has no pty. A remote shell is a socket; with a discipline over it the remote side behaves like a local terminal and rsh knows nothing about terminals.

This is NOT a proposal to rewrite the terminal layer. It is a note that the next time one of those is patched, the patch should move TOWARD one input-stream abstraction with a discipline, instead of adding a fourth special case to compat.term.

OTHER ROUND-2 NOT-GAPS, recorded so they are not re-investigated: OCOS' SEMVER PACKAGE DEPS -- pkg.lua already takes { name = ..., version = "&gt;=1.0", optional = ... } and has compareVersion (:1072, :1157). OCOS' DOUBLE-BUFFERED COMPOSITOR -- our shadow buffer; their README names MineOS as the source. Cynosure 2's PLUGGABLE BINFMT (src/exec/{lua,cle,shebang}.lua) -- we run .lua and that is the whole population. ULOS 2's LUAPOSIX COMPATIBILITY PUSH -- their target is \*nix programs; ours is OpenOS programs, which is the population that actually exists.

### A driver registry with per-device probing

*Idea / far future* · from the round *What the rest of the field does better (2026-09-20)*

A DRIVER REGISTRY WITH PER-DEVICE PROBING. Fuchas resolves a device to a driver instead of hardcoding one: drivers live at Drivers/&lt;component type&gt;/&lt;name&gt;.lua along a DRV\_PATH search path, each returns a spec with isCompatible(addr), findBestDriver(type, addr) probes candidates, changeDriver pins a specific driver to a specific address, and in SAFE\_MODE only a basicDrivers set (drive, gpu) may load at all. Two printer drivers ship side by side -- openprinter.lua and ccprinter.lua -- which is the whole point.

WE ARE ALREADY HAND-ROLLING THE SPECIAL CASES THIS GENERALISES. The printer checklist in the PRINTER round says "a 1.7-era printer: width/maxWidth absent, printer must say 'older build: no width' and still print" -- that is isCompatible(addr) written by hand inside one module. `rbmk survey` ("does anything bind") is the same shape again. Third instance is coming; the second is where the abstraction gets built.

A NEW DEVICE NEEDS A KERNEL EDIT today: hal.lua is a fixed type -&gt; {address, proxy, tier, label} registry and tos/peripheral/ is three kernel modules. Extras ships mouse and printer as ordinary libraries in a "drivers" category, outside the cap system. A pkg-installed driver the kernel FINDS is strictly better, and etc/component\_caps.cfg + `component reload-caps` is already the authority half of the design.

DO NOT COPY THEIR AUTHORITY RULE: "a process must use drivers unless it is admin" means root bypasses the abstraction. Our sandbox has no such escape and must not grow one. A driver is a BINDING mechanism (which code drives this device); the cap check stays where peripheral/redstone.lua:requireCap puts it.

PARKED 2026-11-01, by this entry's own rule that the second instance is where the abstraction gets built. There is one printer driver, and printer.lua's feature probe already handles the old builds. A kernel that finds package drivers runs package code with kernel authority, which needs a sandbox answer first, and the disk budget is 330 KB over. Back on the list the day a second driver for one device type exists. Yours to reverse.

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

### Still \~8 sector writes per tiny file

*Planned* · from the round *TBFS: the cost was writes, and a second handle (2026-09-06)*

STILL \~8 SECTOR WRITES PER TINY FILE (inode alloc, directory append + its inode, data block, bitmap, file inode, super). Half of those are per-operation metadata that a "close-time flush" could merge across a create-write-close sequence, at the cost of "written" meaning "on close" -- an operator decision, and not one to make for a filesystem on hardware that vanishes when someone breaks the block.

### A read-only foreign-volume reader

*Idea / far future* · from the round *What the rest of the field does better (2026-09-20)*

A READ-ONLY FOREIGN-VOLUME READER. Split from the entry above: now TOS can NAME another OS's disk, the next step would be listing and copying files off it (OSDI/MTPT partitions, SimpleFS), which is a real base-admin task. A line, not a round.

## Shell and interface

### Smaller, noted in passing

*Planned* · from the round *Found running the 2026-10 work on the runner (2026-10-30)*

SMALLER, NOTED IN PASSING.

- The chat tab repaints in full on every keystroke (handleKey returns 3): about 16 keys a second on the runner's T2 APU. Past human speed, so not a bug, but a pasted line lags.
- DONE 2026-11-01: desktop.keys says the bound key, swapped in where it is drawn, so no catalog changed.
- DONE 2026-11-01: the CLI path follows the key table. shell/quitkey.lua answers ^Q until a keys file exists, and only then loads shell.keys, so a machine that never bound quit pays almost nothing. Floorcheck: every README claim holds, 67K free at 1024K against \~65K. SEEN in CLI mode: after `keys set quit F4` ^Q left "abcdef" on the line and F4 cleared it; after `keys reset` ^Q did. kernel/init.lua's notice viewer stays as it is: `q` closes it whatever quit is bound to.
- DONE 2026-11-01: the 297 test files that reported failure by marker alone exit non-zero now. test\_install\_preinit.lua is the one left: it carries the operator's uncommitted edit, so it was not touched.
- check\_lootdisk.py reports radbridge 0.5.0 stale: rebuild the mod against this release and bump its version.

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

### The loot disk is whatever TOS-Release was when the mod last built

*Planned* · from the round *What nobody wrote down (2026-10-26)*

THE LOOT DISK IS WHATEVER TOS-Release WAS WHEN THE MOD LAST BUILT. AUDIT 1 found Irradiated Circuits (radbridge 0.4.0) bundling TOS 1.4.0. Its newest jar, radbridge-0.5.0 (built 2026-10-09, unreleased), carries that day's release: its kernel/init.lua differs from today's, and kernel/x25519.lua and curve25519field.lua are absent. The fix is in the mod's repo: rebuild, and bump the mod version, because LootDiskInstaller stamps the extracted disk with it and an unchanged version never reaches an existing world. Nothing on this side notices the drift. Wanted: a `tos.py check` step that, when it can find a radbridge jar, compares its bundled system\_manifest.lua with TOS-Release's.

THE CHECK IS BUILT, 2026-10-26: build/check\_lootdisk.py, a step of `tos.py check`. It finds the newest radbridge-X.Y.Z.jar (or --jar / $TOS\_LOOTDISK\_JAR), compares assets/radbridge/loot/tos/ with TOS-Release file by file, and names what differs. Advisory (exit 0; --strict fails): the mod is its own repo, and a stale disk is no reason to hold a TOS publish. build/test\_check\_lootdisk.py (6). Today it says radbridge-0.5.0.jar's disk is build 1448305: 143 files differ and 6 are missing (x25519, curve25519field, pkgops, diskmount, open + its man page). STILL OPEN, in the mod's repo and so not done here: rebuild radbridge against this release and bump its version.

### GitHub, now that CI has run

*Planned* · from the round *What nobody wrote down (2026-10-26)*

GITHUB, NOW THAT CI HAS RUN. CI, Issue triage and Push on dev have all run green on dev (Actions API, 2026-10-26).

- DONE 2026-11-01, the operator's call: main and dev refuse force pushes and deletion. No pull requests or status checks are required, because publish.ps1 pushes directly and that must keep working. master and optional-utilities are unprotected, as asked.
- triage's match thresholds (list 0.35, label 0.60) were tuned on CHANGELOG and ROADMAP text. Re-check them on the first real reports; there are none yet.
- Dependabot opens its PRs against dev, which publish.ps1 replaces whole, so a bump is taken in the workflow source and the PR closed by hand, as PR #1 was. Nothing automates that, by the never-decline rule.

### Build the survey suggestions in this order, after the bugs

*Planned* · from the round *The os-survey suggestions, scheduled (2026-10-26)*

BUILD THE SURVEY SUGGESTIONS IN THIS ORDER, AFTER THE BUGS. Work starts on this list only once the open \[!\] entries and the bug entries in WHAT NOBODY WROTE DOWN are done or waiting on the operator. Each line points at the entry that holds the design; the design stays there, this is only the order and the reason. Ordered by what each unblocks, then by value to an operator against its cost.

1. ADDRESSABLE LOCAL IPC (survey 5; WHAT THE REST OF THE FIELD). DONE 2026-11-01 (kernel/ipc.lua); the cluster CLIs use it. rc-pilot hearing its robot still waits on its own decision.
2. SELF-STRIPPING, FIRST STEP ONLY (Cynosure, \[\~\]). DONE 2026-11-01: 33 of 167 files carry floor = true, test\_manifest\_floor.lua proves them closed under require, and build/floorboot.py deletes the other 134 and boots: password set, a file written and read, doctor run. 472 KB, 488 KB on a managed disk, so the floor fits the 1 MB drive a full install is 330 KB over. The UI and the strip itself come later.
3. DRY-RUN CAPABILITY ENFORCEMENT + AN AUDIT LOG OF DENIALS (survey 16; OCOS \[\*\]). THE LOG HALF DONE 2026-11-01: sandbox refusals reach `log` once per program and refusal, capped so a program cannot fill it. A mode that logs instead of refusing is the other half, and how that is exposed is the operator's. DONE 2026-11-05, the operator's answer "build it, root-only, per package": `pkg audit <pkg>` runs a package under a sandbox that records what it reaches for instead of refusing (0dbc1ee).
4. A RECOVERY MENU IN THE BIOS, VIA THE SPLIT (survey 1 + 17). DONE 2026-11-01 in stage 2 (kernel/recovery.lua), seen restoring a machine that could not boot.
5. A DRIVER REGISTRY WITH PER-DEVICE PROBING (survey 4). PARKED 2026-11-01 until a second driver exists: see its entry.
6. CONSOLIDATE THE SECURITY POLICY INTO ONE FILE (KittenOS). DONE 2026-11-01: kernel/policy.lua, failing closed.
7. SHARED getopt (OCOS \[\*\]). DONE 2026-11-01: helpers.getopt, on the commands where a flag could become a file name.
8. LOCALISE THE INSTALLER (survey 10). DONE 2026-11-01.
9. MOUNT PACKAGES AS READ-ONLY ARCHIVES, IN mtar (survey 2 + 18). DONE 2026-11-01: `pkg compact` / `pkg expand`, kernel/pkgfs.lua.
10. COPY-ON-WRITE OVERLAY MOUNTS (survey 3). DONE 2026-11-01: the `overlay` command, on the root, and the read-only boot offer.
11. A SHELL LEXER + PARSER for &amp;&amp; and || (OCOS \[\*\]). DONE 2026-11-07: both chain as in other shells, in both shells (see its entry).
12. /proc-STYLE READ-ONLY INTROSPECTION (Cynosure \[\*\]).
13. FAR: RUN-THIS-ONCE CONFINEMENT (survey 11), "ASK" AS A THIRD STATE (KittenOS), LINE DISCIPLINES (survey 19), the LOG WALL appliance (settle its local-or-feed question first).

NOT ON THIS LIST, because they are the operator's to decide, not to build: the boot battery in CI (it runs on the headless runner today; the CI host is the open question), and PUT THE COMPAT NUMBER IN THE README (an editorial call).

### Error registry: the rest of the migration

*Planned* · from the round *Planned (near future)*

Error registry: the rest of the migration. The first slice (2026-09-10) gave tos/kernel/errors.lua its codes and tagged the refusals `why` already explained -- protected paths, permissions, the tier gates, rm's guards, the trash, unknown and unloadable commands. Everything else TOS prints in the error colour is still untagged prose: pkg, the network layer, vault, the drive and deploy commands, hardware faults (5xx-7xx are reserved and still empty). Tag them as they are touched, never renumber, and let test\_error\_registry.lua's scan of every shipped file keep each literal tag honest.

2026-10-02, the first 5xx/6xx entries, for `pkg fetch` (touched that day): E-501 ERR\_NET\_NO\_ANSWER (a repo that did not answer whether it signs its index), E-601 ERR\_PKG\_NOT\_FOUND, E-602 ERR\_PKG\_BAD\_NAME, E-603 ERR\_PKG\_DEPENDENCY. A dependency refusal drops the inner lookup's tag so it carries one code, its own. `why` explains all four; Appendix C lists them. Still untagged: the rest of pkg (install/upgrade gates), the network layer proper, vault, the drive and deploy commands, hardware.

Same day, vault and deploy (both touched that day): E-305 ERR\_VAULT\_UNLOCK, tagged at its source in kernel.vault's MAC check so every caller carries it (vault, tape-auth's log/menu, the tape toolbox), and E-306 ERR\_DRIVE\_TOO\_SMALL on deploy's pre-flight refusal. Still untagged: the rest of pkg, the network layer proper, drive format/mount failures, hardware.

2026-10-10, pkg's install copy (touched that day for the floor check): E-604 ERR\_PKG\_FILE\_MISSING and E-605 ERR\_PKG\_FILE\_UNREADABLE. The second is what an install that runs out of memory reading a file now carries. `why` tells it to free memory or add a stick.

2026-10-16, federated slice 2's floor: E-606 ERR\_PKG\_UNTRUSTED\_SOURCE. Same day, the rest of pkg's install and upgrade gates: E-607 unverified (no hashes), E-608 hash mismatch, E-609 a signature that does not verify, E-610 `pkg trust require on`, E-611 the wrong publisher (a pin, or an upgrade's key change), E-612 a protected target, E-613 a conflict (test\_pkg\_refusal\_codes.lua drives each through the real pkg.install). Still untagged: the network layer proper, drive format/mount failures, hardware.

2026-11-06, the network layer's two refusals that this week's mesh work touched: E-502 ERR\_NET\_NO\_SECRET (net.send and the mesh, with nothing sent) and E-503 ERR\_NET\_PAIR\_FAILED (no confirmation). `why` explains both and says pairing crosses the mesh. Still untagged: drive format/mount failures, whose text is blockfs's and would cost a re-sign, and hardware.

### A prefab base designer

*Idea / far future* · from the round *Operator notes from testing the published build (2026-10-30)*

A PREFAB BASE DESIGNER. The design pass is done and the first slices are built: docs/PREFAB.md, and `prefab` 0.2.0 in TOS-Extras/modules/prefab, held off the pack because it is 0.x.

BUILT: the blueprint file, the designer (slices along X, Y and Z with the one behind showing faintly, rectangles, copy and paste, undo, keyboard and mouse), and the planner (build order, floating blocks, materials, loads, moves). test\_prefab.lua (91). SEEN on the runner: a 9x4x7 hut drawn, reported, saved, read by `prefab info` and reopened through `open`. The mouse has only been driven in the fake sandbox.

FOUND reading the OC 1.8.10 jar: a geolyzer leaves air at exactly 0 and only adds noise to real blocks, so "is something there?" has no noise at all. A drone holds 8 slots and 4 KB; a robot holds 64.

DECIDED: robots build and drones come later as couriers. The robot gets a generated program on a floppy rather than a live link through rc-pilot, whose wireless setup is unfinished.

SURVEY BUILT 2026-10-31 (test\_prefab.lua 91 -&gt; 142): reads in 4x4x4 cubes and prices a floor at every height. CORRECTED against the bytecode: scan costs 10 energy a CALL, not a block as the config comment and the first draft of the doc said; and its answer is always 64 long, with raw noise past the box. A cave first came out cheapest, so blocks above the building now count against a level. SEEN on the runner through the real sandbox, proxy and Lua VM, against a stand-in geolyzer (--geolyzer) that follows the bytecode: the report matched the Lua simulation line for line. A real geolyzer has not been tried.

EXPORT BUILT 2026-10-31 (test\_prefab\_export.lua, 62): one Lua file for OpenOS, run for real against a simulated world. Facing-independent, so no compass; refills at the corner, saves its place when it stops, resumes; export names the step that needs a hover upgrade, and the simulator stopped at that same step. Blueprint strings go through %q and comments lose control characters: a bare CR would have ended the comment and made the rest code. SEEN on the runner: exported on real TOS, run on real OpenOS against the stand-in robot (--robot): 42 of 42 in the right cells from the right slots, none twice. A real robot has not been tried. Its place is lost on a power cut, and it cannot dig.

CHEST SUPPLY BUILT 2026-10-31 (test\_prefab\_export.lua 62 -&gt; 90): export --chest; an empty robot reads a chest behind its start, takes what the rest of the build needs by name and damage, and returns leftovers. Export's route counts include the trips. SEEN under real OpenOS with an inventory controller stand-in (--robot-chest): took exactly 40 cobblestone and 2 glass past a stack of dirt, 42 of 42 cells right.

LINKS BUILT 2026-10-31 (test\_prefab\_links.lua, against the real stock, printer and calc code): prefab need, watch, print and csv, all optional. There is no package called supply: the operator's "supply package" was taken to be stock. SEEN on real TOS with all three really installed and a stand-in transposer (--transposer): need read a real chest through the kernel's library, watch then `stock low` flagged both shortfalls, and they were still there after a reboot.

OTHER PAIRS WORTH LINKING, not done: web showing &lt;img&gt; through pic; stock's listing through printer, or to CSV for calc; warhead's reports through printer.

CLEARING BUILT 2026-10-31 (test\_prefab\_export.lua 90 -&gt; 124): export --chest --clear empties the building's space top down, digs through its route, leaves replaceable blocks and liquids, empties itself at the chest, and takes spare pickaxes from it. SEEN under real OpenOS with --robot-rubbish: dug 4 blocks, dropped 4, took 40 and 2, 42 of 42 right. It does not fill gaps under the floor.

PARTS BUILT 2026-10-31 (test\_prefab\_base.lua, 88; test\_prefab.lua, 188): 7x7x5 tiles, a door the middle 3 of an edge, 11 parts, turning, your own blueprint as a part with its doors found by looking, a .base layout that compiles to one blueprint, so every command takes it. `prefab base` opens a tile designer with keys and mouse. SEEN on a booted TOS: 5 parts placed and turned by keys, checked, saved, reopened, 21x5x21, 705 blocks, exported. SEEN under real OpenOS: a hall and a room compiled into one, built with the real export: 273 of 273 cells in the right place, no doubles, 482 moves.

NEXT, in order: drones, floors over floors, then a real world. Blocks with a facing (stairs, doors) are an open question, in the doc, and multi-floor bases wait on it.
