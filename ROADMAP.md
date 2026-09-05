# TOS Roadmap

What is actually open. Generated from our working notes, which are not published — the notes interleave open work with a long done-history and occasional machine-local paths, so this is the extracted, scrubbed view of it. Do not hand-edit; raise an item in an issue or pull request instead.

**66 open items.** This is the honest list, including the things deliberately *not* done and the reasons why — those entries are often the most useful ones to read before proposing a change.

| Status | Count | Meaning |
|---|---:|---|
| Open bug | 1 | Known broken. Fixing one of these is the most valuable thing you can do. |
| In progress | 2 | Started, unfinished. Ask before duplicating the work. |
| Planned | 47 | Planned or under investigation. Most contributions belong here. |
| Idea / far future | 16 | Idea, no commitment. Discuss before building. |

Items marked *Emulator checklist* need a real OpenComputers install to verify — the off-box suite runs on stock Lua and cannot see that class of bug. Those are good contributions if you play the mod.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request.

## THE ESCAPE HATCH NEEDED THE BROKEN THING (2026-08-24)

### Planned — THE ROOT CAUSE IS STILL THERE

```text
THE ROOT CAUSE IS STILL THERE, and the rescue only makes it
    survivable: commands/core.lua is ~2,650 lines, the biggest file in
    the tree, and loading it needs one large contiguous buffer. That is
    why it -- and not admin.lua or extras.lua -- is the category that
    dies first on a tight box.
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
```

## THE BUDGETS THAT DO NOT EXIST (2026-08-24)

### Planned — OPERATOR DECISION

```text
OPERATOR DECISION, deliberately not made here: should `rsh` REFUSE
    to execute when the step budget cannot be installed?
      FOR: it is arbitrary code from the network with no CPU or
      allocation bound. What actually stops a runaway is OC's machine
      watchdog, which kills the WHOLE COMPUTER -- a far worse outcome
      than the clean "step budget exceeded" this module was written to
      return, and on a multi-seat box it takes everyone down.
      AGAINST: it would disable rsh outright on the only platform TOS
      ships for. The feature already requires a TRUSTED peer AND
      challenge-response per request AND rshd running (default off),
      and CMD_LIMIT / OUTPUT_LIMIT / the entry-time MIN_FREE_MEM check
      all still hold. This is a deliberate, gated feature, not an
      accident.
      A middle option: keep it enabled but make `service start rshd`
      print the loss once, so nobody enables it believing in a budget
      that is not there. The warning added above is the log-level
      version of that; whether it should be louder is the call.
```

### Planned — WORTH CHECKING NEXT

```text
WORTH CHECKING NEXT, same shape: what else in TOS assumes a
    standard-Lua facility that OC's sandbox trims? machine.lua's
    sandbox table is the authoritative list and it is right there in
    the emulator jar. os.* and io.* are the obvious places to look --
    the off-box suite runs on stock Lua 5.4, where everything exists,
    so this entire class is invisible to it by construction. That is
    the same blind spot that hid the byte-vs-column ustr fallback.
```

## THE BLACK STATUS BAR, FIFTH TIME (2026-08-24)

### Planned — NOT CHASED

```text
NOT CHASED, same area, no evidence of a live bug: a forwarded
    display.* draw (statusBar/menuBar/scrollUp/box via
    withContext) that THROWS skips the wrapper's cleanup, because
    withContext re-raises. Both the shadow and the colour cache
    are then stale with nothing to correct them -- the same
    permanent-desync shape as above. No path was found that
    actually throws in there, which is why this is a note; if a
    black bar or a wrong-coloured row ever survives this fix,
    start here. screen.lua ~line 1240.
```

## ACCIDENTAL-GLOBAL / COMPAT SWEEP (2026-08-23)

### Planned — UNVERIFIED

```text
UNVERIFIED, NEEDS A LUA 5.3 BOX: gmatch's empty-match rule
    differs between the two architectures TOS supports. Lua 5.4
    refuses a match that ends where the previous one ended; 5.3
    has no such guard and returns the empty match. ~15 call sites
    split text with  gmatch("([^
]*)
?")  and two with the
    bare  gmatch("[^
]*")  (compat/text.lua's wrap, and the
    crash-dump printer in kernel/init.lua). If the recollection is
    right, every one of them yields ONE EXTRA EMPTY LINE at the
    end on a 5.3 CPU — and the two bare ones yield a blank line
    between EVERY line. That would be a visible difference in
    `cat`, `more`, the editor and the crash dump depending only on
    which CPU is in the machine.
    NOT FIXED, deliberately: only Lua 5.4 is installed on the dev
    box, and 5.4 masks the behaviour completely, so there is no
    way to see the bug or to prove a fix from here. Do NOT rewrite
    fifteen call sites on a memory. Check it first:
        lua5.3 -e 'for s in ("a
b"):gmatch("[^
]*") do print(("%q"):format(s)) end'
    Three lines means 5.4-like and there is nothing to do; four
    (with an empty one in the middle) confirms it, and then the
    fix is one shared splitLines() helper, not fifteen edits.
```

### Planned — WHILE IN THERE

```text
WHILE IN THERE, not chased: kernel/event.lua's timer loop
    pcalls each callback while iterating `timers` in reverse, and
    a callback that cancels or adds a timer mutates that array
    mid-walk. Reverse iteration survives removals ABOVE the
    cursor; a removal BELOW it shifts the entry just processed
    down into the next index. It looked survivable in every case
    traced by hand (a fired one-shot is already gone, an interval
    has had its deadline pushed past `now`), which is why it is a
    note and not a fix — but "survivable by argument" is how the
    pairs() bug above lived for months. Worth a test that
    registers and cancels timers from inside a timer callback.
```

## REAL MINECRAFT ROUND (2026-08-11)

### Planned — OBSERVED

```text
OBSERVED, NOT DIAGNOSED: free memory read 251K in one
    screenshot and 56K a few actions later on what looks like the
    same session. That is a big drop for opening a menu or two.
    Could be the category lazy-load doing its job (core.lua is
    large), could be a leak. Needs a `mem` reading before and
    after a known sequence rather than a guess from two
    screenshots.
```

### Planned — NEXT REAL-MINECRAFT ROUND

```text
NEXT REAL-MINECRAFT ROUND — the point of these four is that
    they were all reachable in one sitting, so the checklist is
    worth more than more off-box tests:
      - attach a printer and run the whole printer/write path
        now that the cap actually arrives
      - `stock` with a transposer, which by the above analysis
        has NEVER worked against real hardware
      - `redstone`/`robot`/`inventory` from a shell, same
      - boot from a read-only disk on purpose and confirm the
        banner, `df` and `doctor` all say so
      - a T1 (192K) box: type `reboot` under memory pressure and
        confirm it now explains itself
      - THE TWO-FLOPPY FLOW END TO END, which has never once run
        correctly: insert disk 1, confirm disk 2's packages are
        listed and dimmed with "On disk 2 (not inserted)", tick
        one, install, swap when asked, confirm it finishes in ONE
        run. Then the same again pressing U at the prompt and
        confirm the already-installed packages are really gone.
      - check the boot banner's RAM line against `mem` — they
        read from the same place now and must agree
      - THE EXIT KEYS, on every full-screen program: open `write`,
        `calc`, `stock`, `snake`, `ttt`, `tetris`, the picker and
        `rc-pilot` and confirm each one can actually be left
        WITHOUT touching Esc. This is the check that would have
        caught #7 and it takes two minutes.
      - press Esc in one of them anyway and confirm the expected
        thing happens: the Minecraft screen closes and the
        program is still there when you re-open it. That is not
        a bug any more, it is the documented behaviour — but it
        is worth seeing once.
      - `keys list`, then `keys set quit F4`, then open ttt,
        calc, write and stock in turn and confirm F4 closes ALL
        of them and ^Q no longer does. That single sequence is
        the whole feature; if one program ignores it, that
        program is still hard-coding a scancode.
      - `keys set quit ^B` must be REFUSED and say why
      - `keys reset`, then confirm ^Q works everywhere again
      - `menu show`, then `menu hide "Flash EEPROM"`, then
        `menu reset`; then the same with --system as root and as
        a non-admin (the second must be refused by securefs)
      - put deliberate junk in ~/.menu.cfg and confirm the bar
        still draws
```

## SIGNED MANIFESTS round (2026-08-11)

### Idea / far future — NOT DONE

```text
NOT DONE, deliberate, and the one bullet from the original
    note that was not followed: no first-party publisher key
    exists and the shipped Optional Utilities disks are still
    UNSIGNED. Generating a signing key is the operator's act,
    not an agent's — a key committed to a repo is not a secret,
    and a first-party key that everyone has is worse than none
    because it looks like assurance. The workflow is built and
    tested; `pkg trust key <passphrase>` prints the public half
    to publish, and `build-disk.lua --sign` uses it.
```

### Planned — Emulator checklist

```text
Emulator checklist:
      - TIME IT. `pkg verify-sig` on a signed floppy, on a T1
        and on a T3. This is the number off-box tests cannot
        give and the one that decides whether the cooperative
        yields are frequent enough. If a seat visibly stalls,
        lower the yield interval in fePow/ptMul.
      - confirm the box does NOT hit OC's 5-second watchdog
        mid-verify, and that a second seat stays responsive
      - a T1 (192K): confirm requiring ed25519 does not OOM.
        This is the real risk — it is ~550 lines plus the
        bignum, loaded on top of an install already in flight.
        If it does, the fix is to verify BEFORE the install
        allocates, not to shrink the module.
      - `pkg trust add` a key, reboot, confirm it persisted and
        that the package now reads trusted
      - hand-edit one byte of an installed package's manifest
        on a signed disk and confirm the refusal names tampering
      - `pkg trust require on` then insert an unsigned disk:
        refusal must name the setting, and --allow-unsigned
        must still work
      - `pkg sign` on-box, then verify from a DIFFERENT machine
        that trusts the key (this is the interop claim)
```

## PRINTER + WORD PROCESSOR round (2026-08-11)

### Planned — Emulator checklist (needs OpenPrinter installed)

```text
Emulator checklist (needs OpenPrinter installed):
      - no printer at all: `printer` says so; `write` still
        opens, paginates and saves, and the rail says
        [estimated widths]
      - with a printer: rail must flip to [printer widths], and
        the two must AGREE on where a long paragraph breaks
        (this is the one thing off-box tests cannot prove — if
        they disagree, the transcribed CharacterWidth table is
        wrong and printerfmt's W table is what to fix)
      - `printer test`: the row of #s must reach the right
        margin and NOT be clipped. A short row means our
        measure and the printer's disagree.
      - empty the paper slot -> a 3-page job must be REFUSED
        with the shortfall named, and print NOTHING
      - pull the paper mid-job -> the error must report how
        many pages already came out, and they must be there
      - an all-black document must leave the colour cartridge
        untouched (read the level before and after)
      - one `.color` line: colour level drops by exactly 1
      - a CENTRED black line still costs a colour unit (the
        alignment arg sits after the colour) — confirm the cost
        line predicted it rather than surprising you
      - `printer scan` on a page printed by TOS -> round-trips
      - a 1.7-era printer if one is available: width/maxWidth
        absent, `printer` must say "older build: no width,..."
        and still print
      - `write` a 25-line document: the page rule must appear
        between lines 20 and 21, and F5 page view must agree
      - put `.title` at the top and confirm the rule does NOT
        move (the directive prints nothing; this is the drift
        regression the unit tests pin)
      - print from `write` (F3) and from `printer file` on the
        same document -> byte-identical pages
```

## FROM THE CYNOSURE 2 SURVEY (2026-08-10)

### In progress — SELF-STRIPPING

```text
SELF-STRIPPING, NOT BUILD-TIME CONFIG — OPERATOR DECISION,
    2026-08-11. Supersedes the build-time item below; keep that
    text for the Cynosure argument it came from, but the shape
    has changed and this is the one to build.
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
      * SAFE MODE always boots. It is what you fall back TO, so
        it cannot be a thing you can strip. Anything Safe Mode
        needs is in the floor by definition.
      * The EMERGENCY TERMINAL always exists. Same reason: it is
        the diagnostic of last resort and a diagnostic you can
        delete is not one.
    Everything else is on the table.

    DESIGN NOTES, so whoever builds it does not re-derive them:
      * The floor must be COMPUTED AND TESTED, never a hand-kept
        list — a hand-kept floor drifts and you find out on the
        boot where you needed it. Shape: system_manifest.lua
        grows `floor = true`, and a test asserts the floor is
        CLOSED UNDER REQUIRE (nothing in the floor requires
        anything outside it). That test is the feature.
      * FEATURE GROUPS, not files. The operator picks cluster /
        internet / tape / blockfs / mesh / i18n / rbmk — the
        axes the build-time note already identified. Nobody
        should be ticking individual .lua files.
      * STRIPPING IS DESTRUCTIVE AND NEEDS MEDIA TO REVERSE, and
        the UI has to say so in those words. `srm baseline
        --full` first is the honest prerequisite: the SRM store
        is what makes an un-strip possible at all, and it
        already exists. Refuse to strip with no baseline unless
        the operator overrides, exactly as `srm repair
        --restore` refuses without one.
      * THE MANIFEST MUST BE UPDATED BY THE SAME OPERATION, or
        `verify` and `srm scan` cry deletion about every removed
        file forever and the operator learns to ignore them —
        which costs more than the disk saved. Stripped entries
        get marked, not deleted, so the difference between
        "removed on purpose" and "missing" survives.
      * BOOT PROFILES AND STRIPPING ARE DIFFERENT LAYERS and now
        interact: a profile gates what LOADS, stripping removes
        what EXISTS. A profile that would load a stripped
        feature must degrade with a clear line in the boot log,
        never panic. Today the load paths pcall-and-warn, which
        is most of the way there — but it has never been tested
        against a file that is genuinely absent rather than
        merely skipped.
      * NOT a package. `pkg uninstall` already covers add-ons;
        this is about the BASE IMAGE, which pkg does not own.
```

### Planned — Emulator checklist

```text
Emulator checklist:
      - `cli` from the TUI, `tui` back, several times: confirm no
        state is lost and the seat never ends up in neither
      - F10 -> [4] CLI Mode, and the File menu's Quit -> [4]: both
        must reach the same place
      - boot with ui=cli and confirm the panels tree is NOT parsed
        (watch free RAM at the prompt vs a TUI login)
      - a T1 (192K) box: the whole point. Type `ls`, then `mem`,
        then something from admin (`useradd`) and watch memory
        step down as categories load. If admin.lua cannot load at
        192K the OOM path in commands.lua should SAY so rather
        than reading as "unknown command".
      - run a package fullscreen program (tetris/calc/stock) FROM
        the CLI and confirm the seat comes back cleanly
      - `sudo -s` in the CLI: prompt must show [sudo], and `tui`
        must NOT carry the elevation across
      - a pipeline and a redirect at the CLI prompt (`ls | grep x`,
        `ps > /tmp/p`) — these never worked in the old CLI
      - break shell/panels/init.lua on purpose and confirm the seat
        lands in a WORKING CLI, not a dead one
```

### Planned — STILL OPEN from the decision below: the EMERGENCY TERMINAL is

```text
STILL OPEN from the decision below: the EMERGENCY TERMINAL is
    untouched — still the same seven commands. Growing it toward
    the recovery set (srm, log, df, repair) is its own round, and
    the constraint stands: every dependency it takes on is a
    dependency that might be the thing that broke.
```

### Planned — BUILD-TIME FEATURE CONFIG

```text
BUILD-TIME FEATURE CONFIG. The best idea in that kernel.
    A .defconfig + a source preprocessor give it Linux
    menuconfig semantics: COMPONENT_* per device type, FS_*,
    NET_*, PART_*, EXEC_* — features compile OUT of the image.
    Our boot profiles (minimal/normal/full/diagnostic/safe) gate
    what LOADS at runtime; the code is still in the image, still
    on disk, still parsed the moment something requires it. On a
    RAM-bound box compile-time exclusion strictly dominates
    runtime skipping.
      * We already own the machinery — strip.lua plus the
        manifest auto-pruning already emit a tailored tree. This
        is a .config on top of what build-release.sh does, not
        a new build system.
      * Natural first axes: cluster, internet, tape, blockfs,
        mesh, i18n. All optional, all currently unconditional.
      * Keep ONE canonical full build as the tested default.
        A matrix of configs nobody boots is worse than no
        configs — pick the variants we actually run.
```

### Planned — MINITEL

```text
MINITEL: DECIDE, DON'T DEFAULT. Cynosure ships Minitel in
    the KERNEL beside TCP and HTTP (NET_MTEL), and the partition
    table options name MTPT as "the Minitel partition table used
    by PsychOS". It is the ecosystem's de-facto interop protocol.
    Our mesh is bespoke and SHOULD stay bespoke — you cannot get
    replay-resistant MACs and trust tiers out of someone else's
    protocol. But "TOS machines can only talk to TOS machines"
    should be a position we hold on purpose, not one we backed
    into. If we ever want it, a Minitel bridge is an Extras
    package, not a kernel change.
```

### Idea / far future — /proc-STYLE READ-ONLY INTROSPECTION. Their /proc is a real

```text
/proc-STYLE READ-ONLY INTROSPECTION. Their /proc is a real
    filesystem (proc_config, proc_events, proc_binfmt). We
    expose the same facts as COMMANDS (lsdev, hw, sysinfo,
    doctor), which suits our idiom and shouldn't change. The one
    property worth wanting: a sandboxed program can read a file
    it already has read access to WITHOUT being granted a new
    capability. Today a sandboxed program that wants its own PID
    or free memory needs it handed in. Not urgent; remember it
    if the sandbox ever feels too tight.

    NOT a gap, recorded so it isn't re-investigated: their
    "fastest VT100 in OC" is write batching (accumulate a run,
    one gpu.set per colour run) plus hardware gpu.copy for
    scroll and insert-char. No cell diffing, no shadow, no
    off-screen buffer. Different workload from ours — see the
    LOG WALL item below — and we already use gpu.copy for
    scrolling (display.lua ~585).
```

## FROM THE KITTENOS NEO SURVEY (2026-08-10)

### Planned — CONSOLIDATE THE SECURITY POLICY INTO ONE FILE

```text
CONSOLIDATE THE SECURITY POLICY INTO ONE FILE. Theirs is a
    single readable function returning "allow" / "deny" / "ask",
    prefix-matched over namespaced permission strings, and its
    own header declares it CRITICAL: break it and a failsafe
    leaves the system unable to run user applications at all.
    Ours is correct but SCATTERED — ALLOWED_MODULE_PREFIXES and
    the BASE/GATED component sets in sandbox.lua, adminGate in
    pkg.lua, ALLOWED_SERVICE_CAPS in rc.lua. Each is fine alone;
    together they mean "what is this system allowed to do?" takes
    three files and knowing where to look.
      * Move the DECISIONS into one auditable function. Leave the
        ENFORCEMENT points exactly where they are — this is a
        refactor of policy, not of mechanism, and the enforcement
        sites are where the #SEC history lives.
      * Attach the fail-closed property explicitly: a policy file
        that won't load must deny everything non-kernel, loudly.
        That is a security PROPERTY, so it needs its own test.
      * This is the one place our security STORY is quieter than
        our security POSTURE. The posture is good; you just can't
        read it in one sitting.
```

### Planned — OVERRIDES AS DATA

```text
OVERRIDES AS DATA, DEFAULTS AS CODE — for package caps. They
    check two settings before applying the coded default:
      perm|<pkg>|<perm>   then   perm|*|<perm>
    so an operator pre-grants or pre-denies per-package or
    globally without touching policy code. We ALREADY have this
    shape for component TYPES (etc/component_caps.cfg, the
    base/gated split, `component reload-caps`). What's missing is
    the same for package CAPABILITIES. Extending something we
    built, not importing a foreign idea.
```

### Idea / far future — "ASK" AS A THIRD STATE. We are binary and install-time: an

```text
"ASK" AS A THIRD STATE. We are binary and install-time: an
    admin accepts a package's declared caps, all of them, before
    any are used. They defer hardware access to FIRST USE and
    prompt with package name, PID and the permission, offering
    No / Always / Yes — and "Always" writes the grant into
    settings, which is the bit that makes prompting tolerable
    rather than nagging.
      * BLOCKED ON A DESIGN ANSWER, which is why it's [*]:
        KittenOS is single-user, single-seat, GUI. We are
        multi-seat with rc.d services and sandboxed daemons that
        have NO operator attached — that is why notify.lua
        exists at all. A naive port hangs a service forever
        waiting for an answer nobody is there to give.
      * If we do it: "ask" is legal ONLY in an interactive
        session and resolves to DENY everywhere else. Decide that
        first, in writing, before any code.
```

## LOG WALL / STREAMING-CONSOLE APPLIANCE (2026-08-10)

### Planned — The shadow buffer is tuned for TUI redraw — repaint mostly-

```text
The shadow buffer is tuned for TUI redraw — repaint mostly-
    unchanged cells, elide what matches. A scrolling log is the
    opposite profile: nearly every cell is new every frame, so
    the diff scan finds nothing to elide and we pay the scan AND
    the ~W*H*3 table slots for no return. The right renderer
    there is Cynosure's: hardware gpu.copy to scroll, then ONE
    batched gpu.set for the newly exposed line.
      * Half of this already exists — bufferMode = "off" is an
        operator override today (screen.setBuffer). The missing
        half is a streaming-console writer that batches runs
        instead of going cell-by-cell.
      * Which makes the honest framing: not "a new renderer",
        but "our second renderer", picked by workload. Say that
        out loud in the code or someone will try to unify them.
```

### Planned — Mostly COMPOSITION of parts we already have — the work is

```text
Mostly COMPOSITION of parts we already have — the work is
    picking them, not writing them:
      * kiosk.cfg for the lockdown (allowed commands, banner)
      * rc.d service for the feed
      * notify + mesh handlers as the event SOURCE
      * boot profile + (later) a build config to strip the rest
    Deliberately NOT the kernel log ring: it is 64 entries
    (16/32 on low RAM) and it is a KERNEL DIAGNOSTIC, not a
    display feed. A log wall wants to subscribe and append, not
    mirror a debug ring. Pick the source before building the UI.
```

### Planned — Open question worth settling first: is the feed LOCAL (this

```text
Open question worth settling first: is the feed LOCAL (this
    machine's own events) or REMOTE (mesh packets from the whole
    base)? Remote is the interesting one and the one that
    justifies a dedicated machine — but it means the log wall is
    a network endpoint, so it inherits the whole trust-tier
    question. A display that renders whatever any peer sends it
    is an injection surface, not a feature.
```

## FROM THE OCOS SURVEY (2026-08-10)

### Planned — SIGNED PACKAGE MANIFESTS (Ed25519). The biggest real gap we

```text
SIGNED PACKAGE MANIFESTS (Ed25519). The biggest real gap we
    have. pkg.lua:200 is `if m.hashes ~= nil then` — hashes are
    OPTIONAL, so a manifest that declares none installs
    unverified. Worse, even when they ARE declared the manifest
    itself is unsigned: whoever hands you the floppy writes the
    files AND the digests, so the hash proves the disk isn't
    CORRUPT, never that it's from who it claims. CR-5's admin
    gate is what's actually holding the line right now, and an
    admin gate is per-DISK consent. A signature makes it
    per-PUBLISHER: accept a key once, then every package from
    that key verifies without a fresh judgement call.
      * Ed25519 over the serialized manifest; publisher pubkeys
        in a trust store the operator manages (`pkg trust`).
      * Three states, said out loud, never silently equivalent:
        signed-by-known-key / signed-by-unknown-key /
        unsigned. The third keeps working (floppies from a
        friend are the normal case) but must require the admin
        override it requires today, and SAY that's why.
      * Composes with what we already have: keychain holds the
        private key, the data card accelerates, critical.bak
        already established the baseline-hash habit.
      * Do NOT invent the wire format. RFC 8032 is the spec.
```

### In progress — IN-EMULATOR BOOT SMOKE TEST

```text
IN-EMULATOR BOOT SMOKE TEST, in CI. The one class of failure
    our suite structurally cannot see. We have hundreds of tests
    and every one is off-box pure Lua: nothing in them catches
    "the kernel does not actually boot on a T1." The EMULATOR
    CHECK notes scattered through this file are that gap showing
    — they're manual, so they're done when someone remembers.
      * Shape: a boot-time battery loaded ONLY when a marker
        file is present (so its bytecode never bloats a
        production boot), running checks, then shutting the
        machine down with an exit code CI can read. Distinguish
        pass / fail / STALLED — a hung boot is the failure mode
        that matters most and it isn't a nonzero exit, it's no
        exit at all.
      * ocvm or Ocelot as the runner; both already boot us.
      * [~] BUILT 2026-08-21, shape exactly as specified above.
        kernel/selftest.lua is gated on /etc/selftest.on EXISTING,
        and the require sits INSIDE the gate, so a production boot
        never loads it. Checks live on a test disk
        (TOS-Extras/selftest/checks) and are discovered from any
        mounted /mnt/<label>/selftest/, so nothing ships in the
        base image but the dormant runner.
      * STALL detection works as the note demanded. Each check
        writes `RUN <name>` and flushes BEFORE its body runs, so a
        wedged machine leaves a file whose last line names the
        culprit and which has no `SELFTEST END`. Results append
        line-by-line for that reason -- a buffered report is
        precisely the report a hang does not give you.
      * No exit code needed: results go to /var/selftest.log,
        beside kernel.log, which on Ocelot and ocvm is an ordinary
        host directory. `shutdown=true` in the marker powers the
        machine off for CI.
      * Each check runs with package.loaded snapshotted and
        restored, because a check that stubs kernel.fs the way the
        off-box tests freely do would otherwise break the machine
        it is running on.
      * REMAINING: wire it to CI. Nine checks now (10 through 90);
        see the triage note below for what is left of the ~15
        "Emulator checklist" items and why most of what remains is
        not portable into this shape.
      * First four checks: boot invariants, the GPU colour cache
        after a scroll (the status-bar-goes-black bug), how big an
        input this machine can actually hash (the sha256 stack
        overflow, measured on OC's Lua rather than a desktop's),
        and a filesystem round trip that audits what our mocks
        claim list()/writeFileAtomic do.
      * Three more followed: SRM baseline/scan/repair against real
        files and real crypto (50), the capability sandbox read
        -- no raw component/computer, no real _G, fs.read alone
        does not expose a writer (60) -- and screen truth: does
        the glass hold what we drew, on a real GPU, including the
        forwarded-draw and two-proxies-one-screen cases behind the
        status-bar-goes-black and selection-fragment bugs (70).
      * [~] TRIAGED 2026-08-28: read all 15 "Emulator checklist"
        items and sorted every bullet into one of four bins --
        single-machine-automatable, needs specific hardware (a
        printer, a live internet card + server, an rbmk block),
        needs a second machine/seat, or is inherently an eyeball
        check (timing, layout, "does it look right"). Most of the
        15 are the LATTER three, which is exactly why they were
        still open: they were never a battery's job. Ported the
        two automatable ones found:
          - SIGNED MANIFESTS round (L957): 80-pkg-signing.lua.
            Real ed25519 + the real /etc/pkg_trust.cfg write path
            through securefs -- the off-box test mocks the disk
            and never exercises that ACL at all. Hand-edit one
            byte -> INVALID with no override; pkg._signGate's
            require-signature refusal names the setting and
            --allow-unsigned still works; trust add/remove round-
            trips through the real store. Snapshots and restores
            the operator's real policy either way, including on
            the throw path -- this must never be the round that
            leaves a stranger's key trusted.
          - INTERNET CARD round (L1793): 90-internet-absence.lua.
            The no-card path and the kill switch, both provable
            without a live card or server: status()/available()
            agree and get() fails clean (no throw) when absent;
            config.internet=false is honoured and the reason names
            the switch, not the card. Never calls config.save(),
            so the toggle never reaches disk.
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
```

### Planned — PANIC DUMP VIA RAW component.invoke. Completes the SRM

```text
PANIC DUMP VIA RAW component.invoke. Completes the SRM
    story. The EEPROM fault channel covers failures BEFORE any
    disk code runs. This covers the other end — a panic after
    boot, where kernel.fs / securefs may be exactly what broke,
    so the dump must NOT go through them. Walk component.list
    ("filesystem"), find one that isn't read-only, write the
    trace with raw invokes. SRM reads it on the next boot the
    same way it reads the EEPROM code.
```

### Idea / far future — SHELL LEXER + PARSER. Only if we ever want `&amp;&amp;`, `||` or

```text
SHELL LEXER + PARSER. Only if we ever want `&&`, `||` or
    `$?`. Today the executor string-parses through
    kernel.pipe.parse, which is fine for `|` and redirects and
    will not stretch to conjunction or exit-status expansion. A
    real lexer/parser is the honest way to get there. Filed as
    far-future because nothing is currently ASKING for it —
    don't build it on spec.
```

### Idea / far future — AUDIT LOG FOR CAPABILITY DENIALS

```text
AUDIT LOG FOR CAPABILITY DENIALS. When the sandbox refuses a
    program a cap we log it, but there's no single place an
    operator can read "what got refused, to whom, when". Worth a
    dedicated append-only log rather than digging through the
    general log. (OCOS's permissive-mode flag that logs instead
    of denying is NOT for us — we're fail-closed by design and
    that stays. It's the record that's worth having, not the
    escape hatch.)
```

### Idea / far future — SHARED getopt. ~50 commands each parse their own flags

```text
SHARED getopt. ~50 commands each parse their own flags.
    One helper would shrink all of them. Low value, low risk,
    good filler work for a quiet round.
```

## STOCK add-on (2026-08-04)

### Planned — Emulator checklist

```text
Emulator checklist:
      - transposer + 2 chests: `stock sides` lists both; `stock`
        totals across them and WHERE names both sides
      - put the same item in both chests, confirm ONE row
      - rename an item on an anvil, confirm it still merges
      - W a threshold as root -> persists across a reboot;
        as a plain USER -> refused out loud, not silently
      - empty the watched chest entirely -> the row must still be
        there, at 0, red, at the top
      - L toggles low-only; / filters by both label and mod id
      - ^B backgrounds it and the chip comes back with fresh
        numbers (drowsy, rescans on its 10s timer)
      - a BIG inventory (drawers/barrel with many slots): confirm
        the getAllStacks fast path doesn't stall the seat, and
        that a component WITHOUT getAllStacks still works
```

## INTERNET CARD + REMOTE PKG round (2026-08-04)

### Planned — Emulator checklist (needs a card AND a server with HTTP on)

```text
Emulator checklist (needs a card AND a server with HTTP on):
      - no card: `internet` says so; `pkg fetch x` fails cleanly
      - card with server HTTP off: status must blame the SERVER,
        not read as "no card"
      - `internet off` then `internet get <url>` -> refused;
        `internet on` -> works
      - `pkg repo add oc <url>` -> `pkg remote` lists packages
      - `pkg fetch <name>` on a hashless repo must REFUSE, then
        work with --allow-unverified
      - confirm /var/pkg/remote is EMPTY afterwards (both on
        success and after a deliberate failure)
      - a package whose index names ../.. must be refused and
        must write nothing
      - pull the card mid-download; confirm no .part is left and
        no half-installed package
      - a T1 (192K) box: fetch something near the 128K file cap
        and confirm it does not OOM (this is the one the off-box
        tests genuinely cannot prove)
```

### Idea / far future — NOT DONE

```text
NOT DONE, deliberate: OPPM's MASTER LIST (the index-of-
    indexes at openprograms.github.io that lets `oppm` search
    every registered repo). TOS works one repo at a time by URL.
    Adding it means trusting a list of hosts you did not write
    down, which is exactly what the allowlist exists to prevent
    — it needs an operator-facing "add all of these?" step, not
    a silent federation.
```

### Idea / far future — OPERATOR IDEA (raised 2026-08-04, deferred): a text-mode WEB

```text
OPERATOR IDEA (raised 2026-08-04, deferred): a text-mode WEB
    BROWSER package over the internet card. Notes on shape before
    anyone starts — see the discussion, but the short version:
    the fetch is the easy 10%; HTML -> text layout is the work,
    and the 80x25 T2 screen is the real constraint. Build it as
    a PACKAGE declaring `internet` + `fullscreen`, never in the
    base image. It is also the first thing that would want
    kernel.internet's caps RAISED (a page is bigger than 64K),
    which is a good reason to keep that per-call rather than
    global.
```

## SHELL GAPS + REAL OPPM round (2026-08-04)

### Planned — Emulator checklist

```text
Emulator checklist:
      - `tail /var/log/tos.log`, then `watch tail /var/log/tos.log`
      - `alias ll ls -l` then `ll` in the SAME session (no
        re-login); `alias ls "ls -a"` then `ls` must not hang;
        `alias` lists, `unalias ll` removes; log out and back in
        and confirm it persisted
      - a USER-tier account: `alias x usermod` then `x` must
        still be refused (aliases carry no privilege)
      - `which ls` (built-in), `which tetris` with the package
        installed, `which share` (/usr/bin); install a package
        whose command shadows nothing and check the ordering
      - `which` on a package command must NOT start the program
      - put a REAL OPPM repo checkout on a floppy (programs.cfg
        at the root, sources under master/<name>/) and install
        one package from it; confirm files land where the index
        said and that `pkg info` shows origin openos with a
        dependency carrying no bogus version
      - a package whose destination is //etc must be REFUSED
      - PATH=/tmp with a planted /tmp/foo.lua: `foo` must not run
```

### Idea / far future — Later, and the reason the OPPM work stops here: OPPM proper

```text
Later, and the reason the OPPM work stops here: OPPM proper
    downloads from GitHub. TOS has NO internet-card support
    anywhere (zero occurrences of "internet" in the tree), so a
    repo still has to arrive as a directory. Doing it properly is
    a chain — compat/internet.lua, an `internet` entry in the
    sandbox's gated component types, sysinfo/lsdev detection,
    then remote pkg repos with host allowlisting and hash
    pinning. That is the first time TOS would fetch executable
    code from outside the world and wants its own round.
    Same bucket: the compat layer shims 11 OpenOS libs; `thread`
    (widely used, maps onto kernel.process) and `uuid` (trivial)
    are the two most-missed. `thread` needs a decision about what
    a sandboxed program spawning a process may inherit — it must
    be exactly the caller's caps, never more.
```

## PICKER QoL round (2026-07-29)

### Planned — Emulator checklist

```text
Emulator checklist:
      - G on a category, then G again; check the counts rail
      - / then type; confirm the list narrows live and the rail
        shows "N of M match"
      - filter + A + Enter installs only the matches
      - Esc with a filter clears it; Esc with none quits
```

## PKG COMPLETENESS round (2026-07-29)

### Planned — Emulator checklist

```text
Emulator checklist:
      - build a v2 of an add-on, `pkg outdated`, `pkg upgrade`
      - confirm a service keeps enabled/disabled across upgrade
        and that stop/start picks up the new code
      - put a real OPPM/loot-disk program on a floppy and check
        it installs AND runs (this is the one off-box tests
        cannot really prove — they stub the sandbox)
      - two packages shipping the same path: confirm the refusal
```

## PICKER OFF THE FLOPPY round (2026-07-29)

### Planned — Emulator checklist

```text
Emulator checklist:
      - `pkg install` with a disk in: picker opens from the BASE
        image (no install.lua on the floppy at all)
      - the swap prompt should now be a framed modal listing the
        packages waiting on the next disk
      - `pkg install --all --dry-run` then `--all --yes`
      - insert a disk built by `pkg make-disk` and confirm it is
        still announced as an "Optional Utilities disk"
```

## MULTI-DISK round (2026-07-29)

### Planned — Emulator checklist

```text
Emulator checklist:
      - boot with ONLY disk2 inserted: confirm disk1's packages
        are listed, dimmed, and say "On disk 1 (not inserted)"
      - select across both disks, install, swap when asked,
        confirm it finishes in ONE run
      - same again but press U at the prompt: confirm the
        already-installed packages are really gone afterwards
      - confirm tape + tape-authenticator land on one disk
```

## INSTALLER + WORKER round (2026-07-28)

### Planned — Emulator checklist

```text
Emulator checklist:
      - picker on an 80x25 and on a 50x16 screen (two-pane vs
        fallback); check the panel doesn't overrun the divider
      - select `drive` with blockfs NOT installed: confirm [+]
        appears on blockfs and both install
      - insert only disk2 and check the From field + the
        "not on any inserted disk" warning make it obvious
      - run cluster-worker-setup ON TOS and confirm the refusal
        actually names cluster-setup
```

## CLUSTER SETUP round (2026-07-28)

### Planned — Emulator checklist

```text
Emulator checklist:
      - `cluster-setup` on a box with NOTHING installed: does the
        explain screen actually make the choice obvious?
      - full Master->Manager pairing on two machines using only
        what the wizard prints (this is the real test of the
        address fix)
      - answer "no" to boot-start, reboot, confirm the service
        is NOT running; then `service start clusterd`, reboot,
        confirm it IS
```

### Idea / far future — Later: the wizard could offer to configure the OpenOS worker

```text
Later: the wizard could offer to configure the OpenOS worker
    bridge (secret + domain) instead of leaving it to hand-edits;
    it's the only remaining manual step.
```

## NOTIFY round (2026-07-28)

### Planned — Emulator checklist

```text
Emulator checklist:
      - `notify "test"` from one seat, confirm the box lands on
        BOTH seats and that answering on one clears both
      - hammer `notify` and confirm the 3s quiet window really
        gives the keyboard back
      - confirm a dialog raised while a fullscreen program is
        backgrounded does NOT paint over it (suspendIdleDraw)
```

## INTERCOM round (2026-07-28)

### Planned — Emulator checklist for this round

```text
Emulator checklist for this round:
      - record a real tape, note the positions, catalog them,
        and check `intercom test` brackets the right recording
        (this is the one thing off-box tests CANNOT prove —
        4096 B/s is the assumed rate; if the stop lands early
        or late, set bytesPerSecond from what you measure)
      - two machines: `intercom play` on one, confirm the other
        shows the chat line and (at alert+) the message box
      - hammer alerts and confirm the cooldown keeps the
        keyboard usable
      - `@group:` to 3 peers with one powered off; confirm it
        says "delivered to 2 of 3" and names the missing one
```

### Idea / far future — Later: per-group mesh sealing (today a group send is N

```text
Later: per-group mesh sealing (today a group send is N
    sealed unicasts, which is correct but O(N) floods); and
    letting `intercom cue add` write catalog lines from the
    shell instead of hand-editing /etc/intercom.cues.
```

## SRM round (2026-07-28)

### Planned — Emulator checklist for this round

```text
Emulator checklist for this round:
      - fail a boot on purpose (rename /tos/kernel/init.lua) and
        confirm K4 on screen + 4 short beeps, then that the next
        good boot explains and clears it
      - `srm baseline --full` on a fresh install, check the disk
        cost report is honest, then `srm scan` after an edit
      - `srm repair --restore` puts the edited file back
      - confirm the store survives a reboot and `srm status` is
        instant on a slow disk
```

### Idea / far future — Later: teach `pkg install` to refresh the baseline for files

```text
Later: teach `pkg install` to refresh the baseline for files
    it replaces, so an upgrade doesn't leave scan crying drift on
    every file it legitimately changed. Today that needs a manual
    `srm baseline` after upgrading (scan says so).
```

## MEMORY round (2026-07-24)

### Planned — NEXT if still tight: i18n catalogs, and the display-layer

```text
NEXT if still tight: i18n catalogs, and the display-layer
    work already queued in the OC optimization playbook.
```

### Open bug — OPEN - Safe Mode "unsafe power-off" (operator report). NOT

```text
OPEN - Safe Mode "unsafe power-off" (operator report). NOT
    reproduced from code: there is no safe-profile-specific
    shutdown path (only bootcfg feature gates), and the generic
    zero-process path stamps /var/run/pwrstate "C" via
    kernel.shutdown, i.e. a CLEAN power-off. Candidates still to
    rule out, need the kernel.log + /var/crash from that boot:
      (a) shell/login failed -> proc.count()==0 -> 3 respawns ->
          emergencyShell -> break -> kernel.shutdown (powers off
          rather than staying up);
      (b) an actual power cut leaving the stale "R" marker,
          which the next boot correctly reports as unsafe.
```

## POLISH - operator feedback (round 4)

### Planned — Support-ceiling policy (design decision, operator-approved

```text
Support-ceiling policy (design decision, operator-approved
    direction): instead of degrading everything for T1 GPUs /
    tiny RAM, set a floor - refuse to boot (clean message) or
    fall back to the CLI shell on hardware below it. Sweep the
    T1/low-RAM special cases once decided.
```

## IN PROGRESS: multitasking for full-screen programs

### Planned — STAGE 1b LEFTOVER — the runner is verified only off-box

```text
STAGE 1b LEFTOVER — the runner is verified only off-box:
    1. executor.lua: when the command comes from pkg.getCommand,
       spawn it as a seat-bound process (display = S.displayIdx,
       principal/token from the seat, background = the manifest
       policy) instead of pcall-ing it inline, then setForeground it.
    2. The shell must then NOT draw. Today execSingle returns an
       output buffer and the shell repaints + reprints the prompt —
       straight over the program. Needs a "handed off" result so the
       shell skips its post-command redraw and returns to its event
       loop; it is not foreground, so it receives no input.
    3. A kernel-level SUSPEND HOTKEY, intercepted in the kernel loop
       exactly like Ctrl+T (kernel/init.lua:1439) so the sandboxed
       program never sees it: drop the program to the background and
       hand the seat back to the shell with `tos_focus`. Ctrl+Z
       (ch 26) is the obvious key — CHECK IT IS UNBOUND FIRST.
    4. Resume: the Ctrl+T switcher already lists processes and can
       foreground one. Needs to signal `tos_focus` on the way in.
    5. Programs must repaint on `tos_focus`. It is NOT in the
       sandbox's PULL_DROP, so it already reaches sandboxed code —
       but calc/snake/ttt/tetris currently ignore unknown signals and
       would show a stale screen (the tick-driven ones self-heal
       within a frame; the input-driven ones would not). Four small
       package updates + a documented convention for third parties.
    6. On program EXIT: hand the seat back to the shell the same way.
```

### Planned — STAGE 2 LEFTOVER

```text
STAGE 2 LEFTOVER — apps.lua's header still describes stages;
    rewrite it now that both models exist. Cosmetic.
    ORIGINAL SKETCH (kept for reference): apps.lua has documented `model =
    "process"` since stage 1 but ONLY "inshell" was ever built (see
    apps.lua:82) — this is that missing half. A running program gets
    a tab chip beside Desktop/Shell/Monitor; F2 cycles to it, ^W
    closes it (kills the process). Same engine, different surface —
    and it is the same viewport work the split-tabs sketch below
    needs, so do them in that order.
```

## DEFERRED BY OPERATOR: split tabs (design captured)

### Idea / far future — SPLIT TABS

```text
SPLIT TABS — two or more tabs sharing one screen. Operator
    asked for it and deferred it in the same breath ("probably
    not as easy as it sounds"), which is right: the blocker is
    not the splitting, it's that EVERY APP CURRENTLY ASSUMES IT
    OWNS THE SCREEN. Design sketch so the work starts from a
    plan rather than a blank file:

    1. REGIONS. Add S.regions = { {x,y,w,h, tabs={idx...},
       active=n}, ... }; today's behaviour is exactly one region
       covering the content area. S.activeRegion picks the
       focused one. Tabs stay a single flat S.tabs list — a
       region just holds INDICES into it, so nothing about tab
       identity/lifecycle changes.
    2. THE REAL WORK — VIEWPORTS. apps.lua contracts pass (S,
       tab) and every app draws with S.W/S.H and absolute
       coordinates. Introduce S.view = {x,y,w,h} set before each
       app's draw/onMouse, and convert apps to draw relative to
       it (ui.lua helpers do the offsetting so most app code
       changes by using S.view.w instead of S.W). This is the
       bulk of the effort and the reason to do it as its own
       pass; it is also independently useful (a "preview pane"
       or a status sidebar becomes possible).
    3. INPUT. events.lua routes keys to the FOCUSED region's
       active tab. New binding to move focus between regions
       (F6 / Ctrl+arrows), plus split/unsplit verbs (a Window
       menu entry beats another hotkey to memorize).
    4. MOUSE. mouse.lua already reads S._tabSpans stored at draw
       time (the anti-drift contract) — make those PER REGION,
       and a click inside a region focuses that region first.
    5. TICKS. Live apps currently tick only while front; with
       splits, tick every VISIBLE region's active tab. Watch the
       cost: two live tabs = two repaints per interval on one
       CPU (see the multi-seat cooperative-yield lesson).
    6. MINIMUM SIZES. 80x25 split vertically is 40 columns —
       under calc's and Monitor's usable width. Apps need a
       declared minW/minH in their app spec, and a region too
       small for its app renders a dim "needs N columns" notice
       instead of a corrupted layout. T1 (50x16) probably
       refuses splits outright.
    7. PERSISTENCE. Per-user landing already exists; a saved
       layout would live alongside it. Defer until the rest
       works.
    Verify with: Desktop | Shell side-by-side, then Monitor |
    Shell (a live tab next to an interactive one), then a
    too-narrow region showing the notice.
```

## FROM AN EXTERNAL REVIEW (2026-09-04)

### Planned — `pkg trust key &lt;passphrase&gt;` TAKES THE PASSPHRASE AS AN

```text
`pkg trust key <passphrase>` TAKES THE PASSPHRASE AS AN
    ARGUMENT, so it lands in the shell history that up-arrow reads
    back. build-disk.lua deliberately refuses a --sign flag for
    exactly this reason ("argv lands in shell history, and this
    passphrase IS the private key") -- the on-box path then does
    the thing the off-box path refuses to. Prompt for it instead,
    the way login does, or read it from an env var. Noted while
    documenting the signing workflow; the doc currently warns the
    reader to clear their history, which is a workaround, not a fix.
```

### Planned — DIGESTS IN system_manifest.lua. Every entry is

```text
DIGESTS IN system_manifest.lua. Every entry is
    { path, critical } and nothing else, so `verify` and the boot
    self-check confirm files are PRESENT, never that they are
    UNMODIFIED. An edited kernel module passes. The asymmetry is
    the embarrassing part: pkg requires a SHA-256 for every file
    in a third-party package and supports ed25519 publisher
    signatures, so add-on code is held to a higher integrity
    standard than the OS itself.
      Everything needed is already in the tree -- kernel/sha256.lua
    was split out precisely so it works without a data card, and
    build-release.sh already walks every emitted file. Shape:
    build-release.sh writes a sha256 field per entry, `verify`
    compares, SRM reports a mismatch as a fault. Watch the cost --
    hashing 152 files at boot is not free on a T1 CPU, so this
    probably wants to stay opt-in at boot (verify on demand,
    critical-only on boot) rather than becoming a startup tax.
```

### Planned — BOOTSTRAP VERIFIES NOTHING IT DOWNLOADS

```text
BOOTSTRAP VERIFIES NOTHING IT DOWNLOADS. bootstrap.lua fetches
    the whole OS over HTTPS and writes it to disk having checked
    only that each file's SIZE matches what install.lua then
    re-checks. No hash, no signature. It trusts TLS and it trusts
    that the GitHub account has not been compromised, and it says
    so nowhere. (What it DOES get right: the manifest is loaded
    with load(src,"=manifest","t",{}) -- text mode, empty env --
    so a hostile manifest cannot execute.)
      Blocked on the digests above: once the manifest carries
    them, fetch it first, verify every subsequent download against
    it, abort loudly on mismatch. Signing the manifest with the
    same ed25519 machinery pkg already uses would make the network
    install strictly stronger than the floppy one, which is a nice
    place to end up given it started as the weaker of the two.
```

### Planned — ONE-SECTOR CACHE IN blockfs. Measured, and the numbers are

```text
ONE-SECTOR CACHE IN blockfs. Measured, and the numbers are
    not close: writing a 4 KB file costs 58 component calls (35
    reads, 23 writes); 64 KB costs 1,389. The equivalent on a
    managed filesystem is three, regardless of size. bitSet does
    a full sector read + a three-way string concat + a full
    sector write for EVERY block allocated, and readBlock builds
    a fresh 512-byte string every call.
      Caching the currently-addressed bitmap sector would collapse
    the read side, and allocation is already locality-biased
    (allocHint, the near+1 preference), so consecutive allocations
    hit the same sector -- a single entry is enough. Do the
    WRITE-THROUGH version first: mutate the cached copy and still
    write it immediately, so crash semantics are unchanged and
    the only thing removed is the redundant read. A write-back
    cache in a filesystem driver is where data loss comes from,
    and check()/defrag() read the drive directly in places, so
    they would need the cache dropped or shared. The 81-assertion
    test_blockfs.lua is the safety net; run it before and after.
```

## PLANNED (near future)

### Planned — PUBLISH THE EXTRAS SOURCE

```text
PUBLISH THE EXTRAS SOURCE, or decide not to. Deferred
    deliberately on 2026-09-03, when the Optional Utilities PACK
    went public as the `optional-utilities` branch: that branch
    carries the BUILT packages, so a machine can `pkg fetch` them,
    but TOS-Extras/ itself is nowhere on GitHub. The consequence
    is that nobody can contribute an add-on -- there is no tree to
    open a pull request against, and CONTRIBUTING.md's "work on
    dev" is a half-truth for anyone whose interest is an add-on
    rather than the kernel.
      Options, none costed yet: fold TOS-Extras/ into the dev
    branch (simplest, one place to work, but roughly doubles what
    a contributor clones); a fourth branch (symmetrical with the
    others, but a fourth thing to keep current); or its own repo
    (cleanest boundary, most overhead, and splits the issue
    tracker). Whichever wins, publish.ps1 grows a mode for it and
    the picker/README wording needs a pass.
```

### Planned — Run a verification round in REAL Minecraft OpenComputers

```text
Run a verification round in REAL Minecraft OpenComputers:
    the Ocelot emulator has been running at ~6 TPS (cause
    unknown), which makes testing sluggish and may distort
    timing-sensitive behaviour (waits, live refresh, cooperative
    yields). Real-MC results are the ground truth anyway.
```

### Planned — Command separation leftovers (low value): config (/etc/

```text
Command separation leftovers (low value): config (/etc/
    tos.cfg) vs bootsettings (/etc/boot.cfg) vs profile
    (per-user) - already distinct, could add cross-refs.
```

### Planned — Per-command `-f`/`--live` shortcut (e.g. `ps -f`) on top of

```text
Per-command `-f`/`--live` shortcut (e.g. `ps -f`) on top of
    the generic `watch`.
```

### Planned — `service`/`cron` are read-only in the Monitor tab; consider a

```text
`service`/`cron` are read-only in the Monitor tab; consider a
    dedicated services pane if it earns its keep.
```

### Planned — Prose sync: MANUAL/README/CHANGELOG version + command lists

```text
Prose sync: MANUAL/README/CHANGELOG version + command lists
    (tests cover files, not prose - drift needs a human eye).
```

## FAR FUTURE / IDEAS

### Idea / far future — Specialized per-machine launcher profiles (doors, reactors)

```text
Specialized per-machine launcher profiles (doors, reactors).
```

### Idea / far future — Tape "personal menu" ecosystem polish

```text
Tape "personal menu" ecosystem polish.
```

### Idea / far future — Translate TOS to other languages by the following priority table

```text
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
```
