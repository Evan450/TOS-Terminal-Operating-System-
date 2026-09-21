# TOS Roadmap

What is actually open. Generated from our working notes, which are not published — the notes interleave open work with a long done-history and occasional machine-local paths, so this is the extracted, scrubbed view of it. Do not hand-edit; raise an item in an issue or pull request instead.

**109 open items.** This is the honest list, including the things deliberately *not* done and the reasons why — those entries are often the most useful ones to read before proposing a change.

| Status | Count | Meaning |
|---|---:|---|
| Open bug | 6 | Known broken. Fixing one of these is the most valuable thing you can do. |
| In progress | 2 | Started, unfinished. Ask before duplicating the work. |
| Planned | 82 | Planned or under investigation. Most contributions belong here. |
| Idea / far future | 19 | Idea, no commitment. Discuss before building. |

Items marked *Emulator checklist* need a real OpenComputers install to verify — the off-box suite runs on stock Lua and cannot see that class of bug. Those are good contributions if you play the mod.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request.

## THE MOD SOURCE IS THE AUTHORITY (2026-09-20)

### Planned — REBUILD AND RE-SIGN THE OPTIONAL UTILITIES PACK

```text
REBUILD AND RE-SIGN THE OPTIONAL UTILITIES PACK. Needs the
    OPERATOR: TOS-Extras/dist ships package.sig beside every
    package.lua, and signing takes TOS_SIGNING_PASSPHRASE and
    TOS_SIGNING_NAME from the environment — a secret, deliberately
    never in argv or in a file (build/README.md). So the tape fix
    above is in modules/ and NOT in dist/, and
    test_build_disk.lua's "the published pack matches a fresh build"
    check is RED until the pack is rebuilt:
      TOS_SIGNING_PASSPHRASE='...' TOS_SIGNING_NAME='...' \
        lua TOS-Extras/build/build-disk.lua --sign
    That red check is the guard doing its job, not a break. Do NOT
    hand-copy the file into dist/ to silence it: the signature
    covers the manifest, which covers the hashes, which cover the
    files, so a hand-patched dist would carry a signature that no
    longer verifies — strictly worse than a stale one, because pkg
    would reject it.
```

## SECOND PASS: THE COMPAT NUMBER (2026-09-20)

### Planned — PUT THE COMPAT NUMBER IN THE README

```text
PUT THE COMPAT NUMBER IN THE README, or decide not to. The
    shims above make the measured failure rate zero on both corpora,
    so "OpenOS compatibility, so much of what already exists still
    runs" can become a number. It is an EDITORIAL call, deliberately
    left to the operator, because the number needs its caveats
    alongside it or it overstates:
      * a require() that resolves is not a program that works — caps,
        paths and terminal behaviour still differ;
      * the corpora are the nine loot disks (80 programs) and three
        OpenPrograms repos (60 files), which is what exists and is
        still not everything;
      * some community code targets PLAN9K, not OpenOS (magik6k's
        process.rt / process.globalSignals calls are Plan9k's API).
        Those files were never going to run here and are not counted
        as compat gaps.
    Honest phrasing is something like "every program on the nine
    OpenComputers loot disks loads; the OpenOS names we do not provide
    were required by none of them". Then re-run the scan when the
    claim is made, so the number in the README is one somebody can
    reproduce.
```

### Planned — THE HEADLESS BOOT TEST HAS A WORKING RECIPE

```text
THE HEADLESS BOOT TEST HAS A WORKING RECIPE. This is the missing
    half of IN-EMULATOR BOOT SMOKE TEST (OCOS survey, [~]), not a new
    item. OCOS runs the whole thing unattended under ocvm
    (tools/test-boot.sh) and the shape is what our battery already
    produces:
      * wipe every uuid-shaped dir in the emulator instance first, so
        a MISSING log is detectable instead of reading a stale one --
        the same failure sync-emulator.py exists to prevent;
      * stage a real package into the writable fs so the self-test
        exercises a genuine install, not a synthetic one;
      * timeout 240 script -qc tools/run-emu.sh -- `script` gives
        ocvm a REAL PTY, without which the GPU comes up 0x0. That one
        line is what makes headless work;
      * the OS writes /selftest.log and SHUTS ITSELF DOWN, so the
        outer timeout is only a stuck-boot guard;
      * exit 0 pass, 2 if the log has ^FAIL, 1 if no log was written
        at all -- and on 1 it dumps the last 30 lines of the emulator
        log to stderr.
      We already do the wipe, already write /var/selftest.log, and
    already have nine checks. MISSING: an emulator that can be driven
    headlessly (ocvm, not Ocelot's GUI), the script -qc PTY trick, and
    a self-test mode that powers the machine OFF when it finishes.
    The README calls powering on "the one manual step" -- this is how
    it stops being one.
      Their 240 s budget has a reason worth keeping: pure-Lua
    1024-bit RSA verify takes 10-30 s on a simulated T1 CPU. Ed25519
    is cheaper, but budget for crypto on a SIMULATED cpu.
```

### Planned — DRY-RUN CAPABILITY ENFORCEMENT

```text
DRY-RUN CAPABILITY ENFORCEMENT. Upgrades AUDIT LOG FOR CAPABILITY
    DENIALS (OCOS survey, [*]) from an idea to a shape. Their
    cap.check has an `enforce` flag: when false it ALWAYS RETURNS TRUE
    but writes a denial record to the audit log; when true it denies
    and the caller raises EPERM (src/sys/k/cap.lua).
      That is the safe way to tighten a sandbox on a live base: turn
    enforcement off, run the workload, read what WOULD have broken,
    then turn it on. It is also an excellent test fixture -- run the
    OpenOS compat corpus above in audit mode and the log says exactly
    which capabilities real programs need, which is the empirical
    version of guessing.
      SECOND, SMALLER IDEA from the same file: their caps are
    namespaced and GLOB-MATCHED -- syscall:write:/var/log/*,
    component:<type>:<addr> -- so a service is granted write access to
    a PATH PREFIX rather than to the filesystem. Ours are flat
    booleans and write scoping is securefs per USER, which is the
    better answer for humans. For a sandboxed DAEMON with no human
    behind it, a path-scoped write cap is strictly tighter than "can
    write as this user". First use is rc.d services, whose caps are
    already declared and already gated (ALLOWED_SERVICE_CAPS).
```

### Planned — SPLIT THE BIOS

```text
SPLIT THE BIOS: MINIMAL EEPROM, RECOVERY UI IN STAGE 2. Refines
    the item above and the 2026-09-06 BIOS pair. MineOS proves a full
    menu FITS in 4 KiB; OCOS argues you should not put it there
    anyway. Their EFI is 4,164 B of source, 3,109 B minified, and its
    own comment says the boot-mode menu, recovery flows and splash
    "live in /sys/boot.lua, where they have room to breathe". The
    EEPROM does the minimum: find a medium, read config, load stage 2,
    and on ANY failure draw a full-screen panic naming the reason.
      Nearly the shape we already have -- bios.lua is a POST +
    loader, /init.lua is stage 2. The split:
      * EEPROM: timed hotkey, BOOT-DEVICE chooser, panic screen that
        names the reason. Small enough to keep the manifest anchor.
      * Stage 2: the rich recovery menu -- boot profiles, safe mode,
        srm restore, doctor, disk utility -- using the kernel's own
        modules.
      * THE SPLIT'S WEAKNESS, stated plainly: if the DISK is what
        broke, stage 2 is gone and only the EEPROM half is left.
        Which is exactly why the EEPROM half must still be able to
        pick a DIFFERENT disk, and why the emergency terminal stays.
      Two behaviours from the small bootloaders, both cheap: GEBL's
    QUICK BOOT (exactly one bootable OS found -> boot it, no prompt)
    and its INIT FINDER (config missing or unreadable -> search the
    filesystem root for a bootable file instead of giving up). Zorya
    adds the third: a SELECTION TIMEOUT that falls through to the
    default.
```

### Planned — IF WE BUILD THE ARCHIVE MOUNT

```text
IF WE BUILD THE ARCHIVE MOUNT, USE mtar -- DO NOT INVENT A
    FORMAT. Refines MOUNT PACKAGES AS READ-ONLY ARCHIVES above. mtar
    is ~100 lines and the header is trivial:
      \255\255 <version:u8> <nameLen> <name> <fileLen>
    version 0 uses >I2 for the length, version 1 >I8. Entries stream,
    so an iterator walks the archive without loading it, and
    cleanPath strips . and .. segments AT PARSE TIME -- a traversal
    guard we would otherwise have to write.
      The reason beyond saving work: four implementations already
    read it (PsychOS' libmtar, ULOS 2's mtarldr boots FROM one,
    Zorya's reader, plus the writers), so a TOS package archive would
    be readable by other systems and we could read theirs. This is
    the one place we lose nothing by being compatible: a package
    archive has no trust properties of its own -- the Ed25519
    signature over it is where the security lives, and that stays
    ours.
```

### Planned — rc.lua: TWO NARROW THINGS, AND A CORRECTED ASSUMPTION. OCOS'

```text
rc.lua: TWO NARROW THINGS, AND A CORRECTED ASSUMPTION. OCOS'
    service framework (declarative units, topo-sorted startup,
    supervised restart, per-service caps) reads like a clear lead.
    IT IS NOT -- rc.lua has all of it: topoSort at :135,
    dependency-ordered start at :423, restart supervision at :516,
    per-service caps and user. Recorded so the next survey does not
    re-raise it. The DETAILS are worth having:
      * SERVICE METADATA IS RECOVERED BY REGEX OVER SOURCE TEXT.
        rc.lua:237 does src:match("restart%s*=%s*true"). The returned
        table is consulted too (:403 uses result.restart), so this is
        a pre-scan rather than the only path -- but a COMMENT that
        mentions restart = true, or a value computed rather than
        written literally, is read wrong. Fix that fits our idiom:
        keep the file, drop the regex, have the pre-scan load the
        table in a bare environment.
      * restartCount NEVER DECAYS. tryRestart stops at maxRestart and
        logs -- good, no thrash -- but the count is per-LIFETIME, so
        a service that crashes once a week eventually exhausts its
        budget and stays down with a log line as the only trace.
        Could be as small as resetting the count after the service
        has stayed up N minutes. OCOS' answer is exponential backoff
        plus a tri-state policy (always / on_failure / one_shot), and
        their one_shot comment names the case worth stealing: a
        missing GPU should not make the supervisor thrash.
```

### Planned — A PROVENANCE LINT

```text
A PROVENANCE LINT. KittenOS' compliance.lua walks the repository
    and prints "File wasn't accounted for" for anything not claimed
    by an author manifest. We have the same SHAPE for runtime files
    (test_manifest_completeness.lua) and an accidental-global lint
    besides; what is missing is the LICENSING half. We are GPL v3,
    we vendor an OpenOS tree under Reference/, and Extras ships
    separately authored modules. A lint that every .lua under tos/
    and TOS-Extras/modules/ carries a license header, and that
    nothing under Reference/ is reachable from a release manifest, is
    cheap and protects the part of the project that is hardest to
    repair after the fact.
```

### Idea / far future — MESH

```text
MESH: THE ROUTE INFORMATION IS ALREADY IN THE PACKETS. Plan9k
    does real networking -- IPv4, subnets, RIP v2 in `routed`,
    address autoconfiguration in ohcp that installs routes on lease.
    We deliberately do not: no routing table, neighbours only,
    controlled flooding with DEFAULT_TTL 8, MAX_TTL 16, a 512-id
    dedup cache and store-and-forward retries. That is the right
    trade for OC-sized networks and the module is already hardened
    against flood amplification. NOT A GAP.
      The one thing worth writing down: flooding costs scale with
    network size, and our own packets already carry the fix. Every
    mesh message has a `path` field -- the node addresses it has
    traversed -- so a node that relays a message ALREADY KNOWS a
    working route back to the origin, for free, with no protocol
    change. If a base ever gets big enough that flooding hurts,
    opportunistic route learning from `path` (try the learned next
    hop, fall back to flooding) is available without adopting
    anyone's routing protocol. Not now; recorded so it is not
    re-derived under pressure.
```

### Idea / far future — LINE DISCIPLINES -- direction, not a task, and expensive. Their

```text
LINE DISCIPLINES -- direction, not a task, and expensive. Their
    comment is the clearest statement of it (Cynosure 2,
    src/disciplines/main.lua): a line discipline is "a middle layer
    between the raw stream and the character device... the TTY line
    discipline is what makes ctrl-C, ctrl-\, and ctrl-Z work. This
    line discipline can be put over a network socket, a serial
    connection, or a virtual TTY provided by the kernel - and the
    application (ideally the user, too) will see no difference in
    behavior."
      THREE OF OUR PROBLEMS ARE ONE PROBLEM IN THAT FRAMING:
      * H-04 (open): term.read() takes signals off the machine-wide
        queue. A per-stream input queue with a discipline in front is
        where that read should get its characters.
      * H-06 (open): two sandboxes share compat.term's cursor. A
        discipline instance per stream owns its own line state.
      * rsh has no pty. A remote shell is a socket; with a discipline
        over it the remote side behaves like a local terminal and rsh
        knows nothing about terminals.
      This is NOT a proposal to rewrite the terminal layer. It is a
    note that the next time one of those is patched, the patch should
    move TOWARD one input-stream abstraction with a discipline,
    instead of adding a fourth special case to compat.term.
      OTHER ROUND-2 NOT-GAPS, recorded so they are not
    re-investigated: OCOS' SEMVER PACKAGE DEPS -- pkg.lua already
    takes { name = ..., version = ">=1.0", optional = ... } and has
    compareVersion (:1072, :1157). OCOS' DOUBLE-BUFFERED COMPOSITOR
    -- our shadow buffer; their README names MineOS as the source.
    Cynosure 2's PLUGGABLE BINFMT (src/exec/{lua,cle,shebang}.lua) --
    we run .lua and that is the whole population. ULOS 2's LUAPOSIX
    COMPATIBILITY PUSH -- their target is *nix programs; ours is
    OpenOS programs, which is the population that actually exists.
```

## WHAT THE REST OF THE FIELD DOES BETTER (2026-09-20)

### Planned — A 4 KiB EEPROM FITS A RECOVERY MENU, AND MineOS PROVES IT

```text
A 4 KiB EEPROM FITS A RECOVERY MENU, AND MineOS PROVES IT.
    This is evidence for the two entries in THE BIOS REFUSED TO
    BOOT ANYTHING BUT TOS (2026-09-06), not a new item: the
    objection there was byte budget, and the objection is wrong.
    MineOS' EFI/Minified.lua is 3,865 bytes -- inside the 4 KiB
    limit with 231 to spare -- and it holds ALL of:
      * a TIMED hotkey (hold Alt for one second) so the recovery
        path costs a healthy boot nothing;
      * a boot-source menu listing every filesystem component with
        label, HDD/FDD/SYS class, read-only flag, used-percent and
        address;
      * per-disk set-bootable / rename / erase;
      * internet recovery and URL boot, both gated on a card;
      * a candidate boot-file list (/OS.lua, then /init.lua) so it
        boots its own OS or an OpenOS-shaped one, and a fallback
        that walks every filesystem when the committed address is
        gone, re-scanning on component_added.
      Fuchas' dualboot_init.lua is the /init.lua half in ~40 lines
    and is the cheaper thing to copy first: a stub that checks for
    /lib/core/boot.lua and /Fuchas/Kernel/boot.lua, boots whichever
    exists ALONE with no prompt, and asks only when both are there.
      OUR CONSTRAINT THEY DO NOT HAVE: the EEPROM data field is
    already spoken for. bios.lua keeps the boot address on line 1
    and the kernel anchors its manifest hash after a newline (#SEC
    C1). A menu that writes the data field must preserve line 2+.
      Internet recovery inherits the pkgsign question -- fetching
    and running a script from a URL is exactly what signing exists
    to stop. Scope it to "download bootstrap.lua and stop", which
    is the documented network install path anyway, or check a
    signature.
      OTHER ROUTE, decide one and not both: ship a loader_tos
    module for Zorya NEO (Extras) instead of growing bios.lua.
    Their loaders are ~40 lines (mods/loader_openos/init.lua
    returns function(addr) that builds an env and loads the OS's
    init) and they already carry loader_openos, loader_fuchas,
    loader_cynosure, loader_monolith, loader_tsuki. But Zorya then
    owns the EEPROM, runs the OS in its own thread under a
    synthesized _G, and offers virtual components -- and our boot
    chain has opinions about all three (the Lua-5.3 feature probe,
    the manifest anchor, component_caps).
```

### Planned — MOUNT PACKAGES AS READ-ONLY ARCHIVES INSTEAD OF EXTRACTING

```text
MOUNT PACKAGES AS READ-ONLY ARCHIVES INSTEAD OF EXTRACTING
    THEM. PsychOS' pkgfs (lib/pkgfs.lua) installs a package by
    REGISTERING its archive: a filesystem-component-shaped table
    over an mtar file, optionally lz16-compressed, with a path
    index, where write/rename/makeDirectory/seek return false.
    activatePackage is one line. Fuchas does the same at boot with
    nitrofs; Zorya reads arcfs/romfs/cpio from the BOOTLOADER.
      WHY IT IS WORTH MORE TO US THAN TO THEM: OC charges fileCost
    (512 B) per file on top of content, and a full install leaves
    ~260 KB free on an empty T2. Measured on
    TOS-Extras/dist/optional-utilities as shipped:
      all 16 packages   76 files   745,015 B   38,912 B fileCost
      cluster-master    13 files   140,631 B    6,656 B
      blockfs            3 files    55,343 B    1,536 B
    Archive-mounting all 16 recovers ~23 KB of pure fileCost before
    compression, and data-card deflate on Lua source usually halves
    the content. Call it 350-400 KB back on a disk with 260 KB to
    give: four installed packages becomes a dozen.
      WE ALREADY OWN THE THREE HARD PARTS:
      * fs.mount(path, proxy) takes anything filesystem-component-
        shaped, and netfs.lua and jbod.lua are existing producers
        of exactly that shape.
      * compress.lua already frames deflate as INDEPENDENTLY
        inflatable chunks (nChunks(u16), then cLen/cData pairs).
        That is random access at chunk granularity, which is what
        an archive mount needs. Written for swap and backups; the
        property generalises for free.
      * OC filesystem handles support seek (Reference/OpenOS:
        lib/devfs.lua:329, lib/core/full_buffer.lua:12), so a mount
        seeks to a chunk instead of reading a 140 KB package whole
        on a 192 KB box.
      SIGNING GETS SIMPLER, NOT HARDER: pkgsign signs a manifest of
    per-file hashes today; one archive is one hash and one
    signature, the archive is immutable after install, and srm scan
    stops walking a package's files. Uninstall becomes one remove.
      COST, and compress.lua's own header already says it: a data-
    card call draws a per-tick budget and can sleep the machine a
    tick, so this is for COLD data. Package code is read once per
    require, which fits; a package whose data files are read in a
    hot loop does not. Per-package flag, not a global mode.
      No data card -> compress.lua falls back to a stored blob, so
    the fileCost win survives without compression.
      securefs must still mediate the mount point, exactly as the
    jbod header says ("a TRANSPORT, not an access layer").
```

### Planned — COPY-ON-WRITE OVERLAY MOUNTS

```text
COPY-ON-WRITE OVERLAY MOUNTS. Plan9k's pipes/06_cowfs.lua is
    ~120 lines: cowfs.new(readfs, writefs) returns one proxy, reads
    fall through to the read-only side unless the write side has
    the file, writes always land on the write side, and deletes are
    recorded as <dir>/.cfsdel.<name> whiteouts so a delete can
    shadow a file that exists only on the read-only side.
      Three things we cannot do today and would get:
      * RUN from read-only media. HEAD already offers to install
        from a read-only boot disk; an overlay is the other answer
        -- run NOW, writes on any writable disk, install later or
        never.
      * A kiosk or LOG WALL appliance that RESETS on reboot. Point
        the write side at a scratch volume and wipe it at boot.
        kiosk.cfg gates commands; the filesystem is still
        permanently mutable. This is the missing half.
      * TRY-BEFORE-COMMIT: pkg install or an srm experiment on an
        overlay, inspect, then merge or drop the write layer. A
        weaker form of `srm baseline --full`, reached without
        media.
      WHITEOUTS ARE A NAMESPACE HAZARD and Plan9k does not guard
    it: a real file named .cfsdel.x must not be able to hide x.
    fs.lua already refuses to mount over a non-empty directory
    (#SEC H27) and refuses to remove mount points, so naming and
    blocking this class is house style. Needs its own test.
```

### Planned — A DRIVER REGISTRY WITH PER-DEVICE PROBING

```text
A DRIVER REGISTRY WITH PER-DEVICE PROBING. Fuchas resolves a
    device to a driver instead of hardcoding one: drivers live at
    Drivers/<component type>/<name>.lua along a DRV_PATH search
    path, each returns a spec with isCompatible(addr),
    findBestDriver(type, addr) probes candidates, changeDriver
    pins a specific driver to a specific address, and in SAFE_MODE
    only a basicDrivers set (drive, gpu) may load at all. Two
    printer drivers ship side by side -- openprinter.lua and
    ccprinter.lua -- which is the whole point.
      WE ARE ALREADY HAND-ROLLING THE SPECIAL CASES THIS
    GENERALISES. The printer checklist in the PRINTER round says
    "a 1.7-era printer: width/maxWidth absent, printer must say
    'older build: no width' and still print" -- that is
    isCompatible(addr) written by hand inside one module. `rbmk
    survey` ("does anything bind") is the same shape again. Third
    instance is coming; the second is where the abstraction gets
    built.
      A NEW DEVICE NEEDS A KERNEL EDIT today: hal.lua is a fixed
    type -> {address, proxy, tier, label} registry and
    tos/peripheral/ is three kernel modules. Extras ships mouse and
    printer as ordinary libraries in a "drivers" category, outside
    the cap system. A pkg-installed driver the kernel FINDS is
    strictly better, and etc/component_caps.cfg + `component
    reload-caps` is already the authority half of the design.
      DO NOT COPY THEIR AUTHORITY RULE: "a process must use drivers
    unless it is admin" means root bypasses the abstraction. Our
    sandbox has no such escape and must not grow one. A driver is a
    BINDING mechanism (which code drives this device); the cap
    check stays where peripheral/redstone.lua:requireCap puts it.
```

### Planned — ADDRESSABLE LOCAL IPC

```text
ADDRESSABLE LOCAL IPC. Fuchas' Libraries/ipc.lua (OETF #18)
    gives a process a socket to another PID -- ipc.socket(target,
    id) with write/read/closed, async in write, sync in read, built
    on per-process signals rather than the global queue. Plan9k has
    pipes/17_ipc.lua.
      We have two things and neither is this: pipe.create() is an
    anonymous in-memory stream handed to a child at spawn (shell
    pipelines and redirection, 64 KB cap, #SEC M2), and notify.post
    is one-way to whichever human is looking. An rc.d service and
    an unrelated process cannot talk at all -- which is why the LOG
    WALL item has to ask "is the feed LOCAL or REMOTE?", and why
    the mesh gets reached for when both ends are on one machine.
    cluster-manager and mail's inbox tab are the same shape.
      event.lua is most of the way there: it already records the
    registering PID and spawn generation (#SEC H13, H31, M-11) and
    fires each listener under that PID's context. A targeted push
    is a small addition to machinery that already thinks in PIDs.
      IT MUST BE CAPABILITY-GATED, which theirs is not. "Send to
    any PID" is authority a sandboxed program should not have:
    unsolicited messages to a privileged service are an injection
    surface and PID scanning is an information leak. Shape: a
    service REGISTERS a named endpoint, callers hold an
    ipc.connect(<name>) cap. Never raw PIDs.
      Do not build it on the compat event queue: compat/event.lua
    deliberately blocks sensitive signal names, and IPC must not
    become the way around that filter.
      NOT A GAP, recorded so it is not re-investigated: Fuchas'
    PER-PROCESS SIGNAL QUEUES (computer.pushProcessSignal). The
    security half -- one process reading another's events -- is
    already handled at a different layer, where compat/event.lua
    blocks sensitive names outright and names keystroke-logging
    other seats and clipboard sniffing as the attacks. Only the
    addressable-IPC half above is missing.
```

### Planned — GENERATED API REFERENCE

```text
GENERATED API REFERENCE, AND PERMISSION ANNOTATIONS THAT CAN
    BE TESTED. PsychOS generates its reference every build: build.sh
    runs finddesc.lua and gendoc.lua over lib/ and module/ and
    emits doc/*.md plus an all-in-one apidoc.md, from a one-line
    comment on the function line giving arg types, return types and
    a description.
      This is NOT a proposal to replace MANUAL.md. The manual is
    the operator's book and stays written. What is missing is a
    REFERENCE for the kernel API that cannot silently disagree with
    37,054 lines of Lua -- and build/make_roadmap.py already makes
    generated docs an established idiom here.
      THE SHARPER HALF IS FUCHAS': annotate each function with the
    permission it requires, at the definition (-- @permission
    security.revoke). For us: every kernel entry point carries the
    capability it enforces, and then a TEST THAT ANNOTATION AND
    ENFORCEMENT AGREE. That is the missing verification half of
    CONSOLIDATE THE SECURITY POLICY INTO ONE FILE (KittenOS
    survey): one policy function makes the policy readable,
    annotation-vs-enforcement makes it checkable. Fuchas writes the
    annotations and never checks them; we would be the first to.
```

### Planned — STAMP THE BUILD WITH THE COMMIT

```text
STAMP THE BUILD WITH THE COMMIT. PsychOS' build.sh:
    _OSVERSION="PsychOS 2.0a3-$(git rev-parse --short HEAD)-$KVAR".
    We set _TOS.version and codename by hand at init.lua:430 and
    build-release.sh stamps nothing, so a screenshot, a
    selftest.log or a doctor dump from a box that has been up a
    week cannot say which tree produced it -- and telling you what
    the code actually did is the whole point of the on-box battery.
    sync-emulator.py exists because "the boot disk was eleven files
    behind" was a real round that reported a stale answer; a build
    stamp is the cheap detector for that class.
      Add build (short hash + dirty marker) and the strip variant
    to _TOS, set by build-release.sh, printed by colophon and in
    the self-test header. Keep the hand-set version -- the release
    conventions already move version, README and CHANGELOG
    together.
```

### Planned — THE RESERVED-PORT REGISTRY

```text
THE RESERVED-PORT REGISTRY: 42 IS FINE, AND UNDOCUMENTED. The
    ecosystem keeps a list (GERT repo, now GlobalEmpire/OC-
    Programs): 14 Ethernet-over-OC, 148 GUI service, 4096
    MultICE/Minitel, 4378-4379 GERTi, 4662 short messages, 9100
    network print service, 9900 Zorya BIOS LAN boot.
      Our default (config.lua:54, net/init.lua:94) is 42, which is
    unclaimed -- the default needs no change. The gap is the two
    things around it:
      * listenPort is operator-settable with NO advice. An operator
        who sets 4096 puts TOS traffic onto a Minitel network:
        our net rejects their frames cleanly, theirs may not.
        net should refuse, or warn once, when the configured port
        is a registered one, and NAME the protocol it belongs to.
      * 42 should be registered and documented. One message to the
        registry maintainer, one line in the manual -- it is how
        the NEXT OS avoids colliding with us.
      This is also the cheap, correct form of MINITEL: DECIDE,
    DON'T DEFAULT (Cynosure survey): we stay bespoke and DOCUMENT
    the port, so coexistence works without a bridge.
```

### Planned — NAME WHAT IS ON A DRIVE BEFORE ERASING IT

```text
NAME WHAT IS ON A DRIVE BEFORE ERASING IT. TBFS writes its own
    "TBFS" magic at sector 1 and blockfs.format zeroes the metadata
    region unconditionally. The install path does gate this behind
    a danger confirm box ("Anything on it now is gone",
    commands/extras.lua:1405), so nothing is destroyed silently --
    this is calibrated small. What it CANNOT do is say what is
    there: the only answer TBFS can give about a foreign volume is
    "not a TBFS volume".
      * Probe known magics before formatting -- TBFS, OSDI, OCGPT
        (sectors 2-9), MTPT, msdos -- and name the finding in the
        confirmation. "This drive holds an OSDI partition table" is
        a different decision from "this drive looks blank", and
        read-only probing cannot break anything.
      * A READ-ONLY foreign-volume reader is worth a line, not a
        round: recovering files off another OS's disk is a real
        base-admin task and we cannot see such a drive at all.
      Our unmanaged-drive story stays bespoke on purpose -- TBFS'
    boot region, bootBlob and the EEPROM stage-2 loader are tied to
    how we boot. This is about RECOGNISING other formats, not
    adopting one.
```

### Planned — LOCALISE THE INSTALLER

```text
LOCALISE THE INSTALLER, NOT JUST THE OS. MineOS ships ~20
    Localizations/*.lang packs AND a separate
    Installer/Localizations/ set, and the installer asks for a
    language as step one. Their format is what makes community
    translation happen: one file per language, a flat Lua table of
    short keys, no tooling to contribute. Ours (usr/lang/, i18n.lua)
    is already that shape and holds exactly one pack, ru.lang.
      The transferable half is the installer: install.lua and
    bootstrap.lua are English-only and they are the first, and
    sometimes only, screens a new operator reads. Routing their
    strings through i18n and asking for a language first is
    bounded, and it is what turns one ru.lang into a reason for
    someone to send a second pack.
```

### Planned — DECLARED RUNTIME IN THE PACKAGE MANIFEST -- the cheap half of

```text
DECLARED RUNTIME IN THE PACKAGE MANIFEST -- the cheap half of
    VELX. Fuchas' VELX (Libraries/velx.lua, spec in Adorable-
    Catgirl/Random-OC-Docs) is a container: magic \27VelX, format
    version, compression id, LUA VERSION, OS ID with a library
    flag, archive type, then sized program / OS-dependent /
    signature sections and a cpio archive. Zorya can execute one
    from the bootloader.
      WE DO NOT WANT THE CONTAINER. pkg is directory-based, signs
    an Ed25519 manifest and hashes every file, which is stronger
    than VELX as implemented (see the calibration note above).
      WE DO WANT THE DECLARED RUNTIME: a manifest field naming the
    Lua architecture and the OS the package was built for. We
    require the 5.3/5.4 architecture and both the BIOS and
    /init.lua probe for it, but a PACKAGE built against the wrong
    arch fails at load with a syntax error instead of a sentence.
    One field, one check at install time, and the failure becomes
    "this package needs the Lua 5.3 architecture; sneak-click the
    CPU".
```

### Idea / far future — RUN-THIS-ONCE CONFINEMENT

```text
RUN-THIS-ONCE CONFINEMENT. Plan9k composes namespaces at
    launch from the command line: `sandbox wl fc0 wl fcd component
    spawn /bin/a.lua` (exactly two components), `sandbox module
    spawn ...` (fresh module namespace), quietin/quietout/quieterr.
    Their cgroup kinds are signal, filesystem (a root, i.e.
    chroot), network, module (its own package.loaded/preload) and
    component (whitelist/blacklist, parent-chained allow(addr)),
    inherited from the spawning thread.
      Our caps are declared in a package manifest and accepted by
    an admin at install; progenv.lua already builds a process env
    from an opts.caps table. What is missing is the operator verb:
    run THIS program, right now, with no network -- the thing you
    want when someone hands you a script and you are not installing
    it as a package. A front-end over progenv and the existing cap
    vocabulary, not new mechanism.
      [*] and not [ ] because the one genuinely new primitive in
    their list -- the FILESYSTEM cgroup, a per-process root -- is a
    design question we have not answered. securefs' per-user ACLs
    are a different and mostly better answer; a confined root is
    still the natural thing to hand an untrusted one-off, and it
    composes with the COW overlay above. Decide that before
    building.
      NOT GAPS from this pair, recorded so they are not re-
    investigated: Plan9k's MODULE CGROUPS shadow module tables with
    setmetatable({}, {__index = kernel.modules.x}) per group -- we
    already do that AND lock the metatable, filter pairs(), and (in
    the H-01 work) mask kernel-only hook keys so a sandbox cannot
    reach compat.term._gpuForCaps. Ours is strictly stricter.
    Fuchas' SJF SCHEDULER needs job-length estimates nobody in this
    ecosystem has; our wall-clock + per-resume instruction budget
    (process.lua:960) is a harder guarantee than any scheduling
    policy. MineOS' DOUBLE-BUFFERED GUI is our shadow buffer, and
    the workload-specific second renderer is already scoped in LOG
    WALL. MineOS' desktop, app market, IDE, FTP client and 3D
    library are a different product, as the README already says.
    Plan9k's procfs/sysfs/devfs is the Cynosure survey's decision
    unchanged. MineOS hand-maintains EFI/Full.lua AND
    EFI/Minified.lua; we generate the flashable BIOS through
    strip.lua --minify with a test on the budget -- ours is better,
    do not copy theirs.
```

## AUDIT 5: KERNEL &amp; COMPAT, OFF-BOX (2026-09-18)

### Open bug — H-01

```text
H-01: ANY SANDBOX CAN FORGE A DISPLAY CAPABILITY AND DRIVE THE
    REAL GPU. compat/term.lua:221 exposes _gpuForCaps(caps), which
    returns a MUTATION-capable GPU proxy when the caps table it is
    handed contains gpu or display. sandbox.lua:800 is meant to be
    its only caller: it overrides .gpu on the per-sandbox module
    view with a closure carrying that sandbox's real caps.
      But the view is isolatedModule (sandbox.lua:635), a
    read-through __index onto the real module -- so _gpuForCaps is
    still reachable right beside the overridden .gpu. And
    `compat.` is an allowed require PREFIX (sandbox.lua:41), so
    reaching it needs no capability at all. Reproduced against the
    real sandbox.build with caps = { ["compat.io"] = true } and no
    display cap: term.gpu().setBackground() correctly returned
    false, and term._gpuForCaps({gpu=true}).setBackground() reached
    the hardware.
      test_sandbox_module_isolation.lua:107 already asserts that
    term.gpu() honours caps, which is exactly why this survived --
    nothing ever tried the builder directly.
      Fix: _gpuForCaps must not be reachable from a sandbox. Either
    rawset it under a key the view cannot see, or -- cleaner --
    have sandbox.lua hold the builder and never publish it on the
    module at all. Severity HIGH. Pin: extend
    test_sandbox_module_isolation.lua.
```

### Open bug — CHANGING A LOGIN PASSWORD ORPHANS THE KEYCHAIN

```text
CHANGING A LOGIN PASSWORD ORPHANS THE KEYCHAIN, PERMANENTLY.
    kernel/keychain.lua's header states as fact that
    "users.changePassword fires keychain.rekey if loaded".
    keychain.rekey HAS NO CALLERS. Across TOS-Dev and TOS-Extras
    the only three matches for "rekey" are its own definition, that
    comment, and its own error string; users.changePassword
    (users.lua:627) never touches the keychain.
      So ~/.keychain.vault stays encrypted under the OLD password.
    vault.decrypt MAC-verifies, so the next `keychain unlock` fails
    cleanly and every stored passphrase is gone -- no warning at
    password-change time, no recovery offered. When an ADMIN resets
    another account's password it is unrecoverable even in
    principle: the admin never held the old password.
      Two things to settle before wiring rekey up, both live in it
    today. loadDisk returns a truthy {} when no vault exists, so
    rekey would CREATE an empty vault for users who never used the
    keychain. And saveDisk passes requireStrong = true, so on a box
    with no data card that write fails -- which would make `passwd`
    itself fail, for a feature the user never touched.
      Severity HIGH (silent loss of user secrets). Pin: a test that
    changes a password and then unlocks.
```

### Open bug — H-03

```text
H-03: compat.keyboard.isKeyDown CANNOT WORK, AND RAISES RATHER
    THAN RETURNING false. RE-GRADED: the review reads this as a
    seat-boundary bypass, and the boundary is the smaller half.
      keyboard.lua:39 calls component.keyboard.isKeyDown(code). THE
    OC KEYBOARD COMPONENT HAS NO SUCH METHOD. Checked against
    Ocelot's totoro/ocelot/brain/entity/Keyboard.class: its entire
    surface is signal emission -- keyboard.keyDown -> key_down,
    keyboard.keyUp -> key_up, keyboard.clipboard. Real OpenOS
    tracks it in SOFTWARE from those events, in pressedChars and
    pressedCodes (Reference/OpenOS/openos/lib/keyboard.lua:46).
      So the call indexes nil and RAISES on any machine that has a
    keyboard; the `return false` fallback only ever runs on a
    machine that does not. isAltDown, isControlDown and isShiftDown
    all route through it, and OpenOS's own event.lua uses
    isControlDown() for Ctrl-C -- so a ported program crashes on
    its interrupt path.
      The seat half is real too, and survives that fix:
    component.keyboard is the PRIMARY keyboard, so on a multi-seat
    box a program reads another seat's modifiers. Both go away
    together if pressedCodes is tracked per seat from key_down /
    key_up, the way OpenOS does it. Severity HIGH -- it is broken,
    not merely leaky. Pin: a test asserting isControlDown() returns
    a boolean on a machine that has a keyboard.
```

### Open bug — H-04

```text
H-04: term.read() TAKES SIGNALS OFF THE MACHINE-WIDE QUEUE AND
    FREEZES EVERY OTHER SEAT WHILE IT WAITS. compat/term.lua:260 is
    `local ev = {computer.pullSignal()}` -- raw and untimed.
    compat/term.lua loads OUTSIDE the sandbox, so its `computer`
    upvalue is the real one: term.read() is a hole in
    BLOCKED_MODULE_NAMES["computer"], reachable with no capability
    through the `compat.` prefix.
      Two consequences, and the second is the worse one. The signal
    is popped before proc.tick can route it, so a keystroke meant
    for another seat's foreground is consumed here -- the review's
    "cross-seat impact likely" is certain; that is what the pop
    does. And because pullSignal with no timeout blocks in C INSIDE
    the coroutine, coroutine.resume never returns, proc.tick's loop
    stalls, and nothing else on the machine runs until a key is
    pressed somewhere on it.
      Severity HIGH. Fix: route term.read through kernel.event and
    the scheduler's own pull, as the rest of the shell does. Pin: a
    test that term.read yields instead of calling pullSignal.
```

### Open bug — H-06

```text
H-06: TWO SANDBOXES STILL SHARE compat.term's CURSOR. The other
    half of H-05 above, same root cause, NOT fixed this round --
    deliberately, and the reason is worth recording.
      The state is compat/term.lua:39-40 (curX, curY, curBlink),
    read or written at 34 sites. Reproduced with two sandbox.build()
    envs: after A called term.setCursor(40,12), B's term.getCursor()
    returned 40,12 and B's term.write landed at (40,12).
      The fix is NOT the same shape as H-05's. Default streams are a
    process property, like an fd table, so per-process is right
    there. A cursor is a property of the GLASS: there is one
    physical terminal per seat, and two programs on one seat having
    private cursors would be a different lie from the one we have.
    So this wants per-SEAT, keyed on screen.callerSeat() -- which
    already exists and already returns nil (= fall back to today's
    single shared pair) for kernel, boot and off-box contexts.
      Held over because it is 34 sites in the file with the worst
    regression history in the tree -- "the black status bar,
    seventh time" lives in this exact path -- and the payoff cannot
    be confirmed off-box. It should land in a round that ends at an
    Ocelot power-on, not at the end of one. Severity HIGH. Pin:
    extend test_sandbox_module_isolation.lua with two envs and a
    setCursor.
```

### Planned — THE EDITOR COUNTS BYTES WHERE THE SCREEN COUNTS CHARACTERS

```text
THE EDITOR COUNTS BYTES WHERE THE SCREEN COUNTS CHARACTERS.
    kernel/screen.lua's proxy.set is UTF-8 correct: it splits on
    "[\0-\127\194-\255][\128-\191]*" and maps one character to one
    cell (screen.lua:1290). The editor's syntax path does its
    column arithmetic in BYTES -- panels/draw.lua:741-755 uses
    #tokText for token width and tokText:sub() to clip. Driving the
    real modules on  local s = "café"  -- naïve : draw.lua thinks
    the line is 28 columns and screen.lua paints 26. So the clip
    window, the horizontal scroll, the ">" overflow marker and the
    byte-indexed selection overlay are all off from the first
    non-ASCII character onward.
      In CODE position it is worse. Bytes >= 0x80 match none of %a,
    %w, %d or %s, so shell/syntax.lua emits one `op` token per
    BYTE; the lead byte paints as a lone garbage cell, and the
    continuation bytes match nothing in the UTF-8 gmatch, so
    _diffWindow returns nil and proxy.set counts them as SKIPPED --
    they vanish. On  local café = 1 , byte C3 is drawn and A9 is
    dropped. Comments and strings survive as single tokens, which
    is why the box-drawing in our own headers still renders, drift
    and all.
      Fix: have syntax.tokenize return characters rather than
    bytes, and have draw.lua advance by cell count. Severity
    MEDIUM. Pin: a test comparing draw.lua's column total against
    the screen's cell count. [?] the visual half has not been seen
    on hardware.
```

### Planned — EVERY BEEP STOPS THE MACHINE

```text
EVERY BEEP STOPS THE MACHINE, AND THE GAPS BETWEEN THEM BUSY-
    SPIN. kernel/audio.lua:46, gap(), is `while computer.uptime() <
    target do end` for 50 ms. Not calling pullSignal is RIGHT -- it
    would eat the operator's keystrokes -- but it never yields
    either, so on a cooperative scheduler it hard-freezes every
    other seat and burns execution budget where a sleep costs
    nothing.
      The tones block too. Ocelot's Machine.beep(Context,
    Arguments) calls Context.pause(D) with the duration after
    emitting the tone; that is read off the bytecode, not assumed.
    So audio.chat() is 0.18 s on EVERY incoming chat message
    (shell/chat.lua:322), audio.warning() 0.25 s on every
    command-not-found, audio.bootComplete() 0.36 s, and
    audio.critical() 0.55 s -- over the scheduler's own
    PROC_WALL_BUDGET of 0.5 s. A chat flood is a system-wide stall.
      The fix is already in the API: Ocelot shows a beep(String)
    overload, so computer.beep("..-") plays the whole pattern in
    one call, no gaps and no spin.
      Separately, setVolume only scales DURATION, and tone() drops
    anything under 0.01 s -- so setVolume(0.1) silently mutes
    notify, tick and chat while leaving error audible. Severity
    MEDIUM.
```

### Planned — H-07

```text
H-07: term.screen() AND THE GPU FALLBACK ANSWER FOR THE WRONG
    SEAT. compat/term.lua:226 returns component.list("screen")() --
    the first screen on the machine, not the caller's. The same
    pattern is in resolveSeatGpu's fallback (term.lua:165) when
    display.getGpu() returns nil. Agreed with the review on impact:
    LOW standing alone, because component.proxy is blocked, so the
    address by itself buys little. It stops being low the moment
    anything accepts a screen address as a target. Severity LOW.
```

### Planned — A FAILED SAVE LEAVES MEMORY AND DISK DISAGREEING

```text
A FAILED SAVE LEAVES MEMORY AND DISK DISAGREEING. keychain.set
    (keychain.lua:159) and aliases.set / aliases.remove
    (net/aliases.lua:124, :157) mutate the in-memory table and THEN
    persist, returning the save error without rolling back. The
    caller is told it failed; get / list say it worked; the change
    vanishes at reboot. users.changePassword already gets this
    right -- it reverts salt, hash and firstBoot when saveDB fails,
    and says why (users.lua:680) -- so the shape to copy is already
    in the tree. Note this gets MORE likely now, not less: the
    first entry in this round makes a refused write actually report
    itself. Severity LOW.
```

### Planned — THE ACCIDENTAL-GLOBAL LINT DOES NOT COVER TOS-Extras, AND ONE

```text
THE ACCIDENTAL-GLOBAL LINT DOES NOT COVER TOS-Extras, AND ONE
    LEAK IS ALREADY THROUGH. test_global_leaks.lua is good and its
    scope is stated honestly -- system_manifest.lua entries only.
    Running the same luac -p -l -l analysis over everything it
    skips: the TOS-Dev files outside the manifest are clean, but
    TOS-Extras/selftest/checks/80-pkg-signing.lua:128 writes a
    global `_` (`_ = v6`, the mark-as-used idiom). Exactly the
    class the lint exists to catch.
      Widening it is not just a longer file list. Extras module
    code legitimately reads `fs`, `vault` and `crypto`, which the
    sandbox injects per capability (sandbox.lua:1068, :1252,
    :1282), so the lint would have to know the module ENVIRONMENT
    and not only STDLIB. Severity LOW. Pin: the widened lint is its
    own pin.
```

### Planned — THE PACKET MAC HAS NO LENGTH FRAMING

```text
THE PACKET MAC HAS NO LENGTH FRAMING. net/init.lua:482 (send)
    and :669 (receive) tag a \0-joined concat of variable-length,
    attacker-influenced fields: type, to, enc, epoch, seq, nonce,
    payload. Adjacent fields can be re-split without changing the
    joined string, so a captured packet can be reshaped across the
    type/to or nonce/payload boundary and keep a valid tag; moving
    one byte out of nonce into payload defeats the nonce ring.
      NOT currently exploitable -- the H-3 sequence check refuses
    the replay, which is precisely the defence-in-depth it was
    added for. Recorded because the nonce ring is documented as a
    second layer and this quietly removes it. Fix: length-prefix
    each field. Severity LOW, and it rises the day the seq check is
    relaxed.
```

### Idea / far future — `rm`'s SYSTEM-PATH GUARD IS DISABLED BY THE FLAG ITS OWN

```text
`rm`'s SYSTEM-PATH GUARD IS DISABLED BY THE FLAG ITS OWN
    MESSAGE RECOMMENDS. panels/commands/core.lua:832 fires only
    when `p:match(pat) and not recursive`, so `rm -r /tos` skips it
    entirely -- and the comment above it describes a second
    condition ("explicit system path typed out, not a wildcard or
    expansion") that is not implemented at all. securefs's
    REMOVE_PROTECTED is the real backstop and it does hold, so this
    is a confusing two-step error rather than a hole: the shell
    suggests -r, then securefs refuses with a different message.
    Worth tidying next time that file is open; not worth a commit
    of its own.
```

## THE BIOS REFUSED TO BOOT ANYTHING BUT TOS (2026-09-06)

### Planned — A BROKEN TOS INSTALL ON THE COMMITTED BOOT DEVICE IS A LOOP

```text
A BROKEN TOS INSTALL ON THE COMMITTED BOOT DEVICE IS A LOOP.
    Found while fixing the above, not reported. If the EEPROM's saved
    address names a disk whose /init.lua loads but whose kernel is
    gone, the BIOS boots it, init.lua reports the missing files and
    reboots, and the BIOS boots it again. The fallback-approval
    prompt (#SEC H1) only appears when the SAVED address does not
    work at all, so it never offers a way out. Recoverable only by
    moving the disk to another machine or re-flashing from one.
      The fix is an escape hatch at POST -- a held key that forces
    the device-selection prompt even when the saved address is
    bootable. It is the same shape as the S-at-POST safe-mode
    one-shot the kernel already has. Not done here: 153 bytes is
    thin for a key-scan loop, and getting it wrong makes every boot
    slower or, worse, stealable by a stray keypress.
```

### Planned — INSTALLING TOS REPLACES /init.lua AND NOTHING PUTS IT BACK

```text
INSTALLING TOS REPLACES /init.lua AND NOTHING PUTS IT BACK.
    install.lua says so plainly before it starts ("Your /init.lua
    will be replaced"), so this is disclosed rather than hidden --
    but there is no uninstall, so a shared disk that had OpenOS on
    it does not become bootable again by deleting /tos. The BIOS fix
    above means ANOTHER disk now boots; this one is about the disk
    TOS was installed onto. Options if it ever matters: keep the
    displaced /init.lua as /init.lua.pre-tos and have a `tos
    uninstall` restore it, or simply document the state.
```

## EXTRAS SWEEP 2: THE PACKAGING SEAM (2026-09-06)

### Planned — THE CANONICAL NUMBER FORMAT IS STILL ARCHITECTURE-DEPENDENT

```text
THE CANONICAL NUMBER FORMAT IS STILL ARCHITECTURE-DEPENDENT. The
    fix above removes the only float that crosses the wire; it does
    not make the FORMAT safe for the next one. A field carrying an
    integral float still canonicalizes differently on 5.2 and 5.3.
    The fix is one line in each half -- render numbers with a
    subtype-independent rule ("%d" when the value is integral, else
    "%.14g") -- but it changes the MAC for every frame, so both sides
    must be upgraded together AND the OpenOS worker is hand-copied to
    each worker box. Worth doing at the next protocol version bump,
    not on its own.
```

## CLUSTER PAIRING NEVER WORKED, AND A CANCEL RACE (2026-09-06)

### Planned — tape-auth passphrases are positional arguments (`log add &lt;pass&gt;

```text
tape-auth passphrases are positional arguments (`log add <pass>
    <text>`), so every one lands in the seat's command history --
    the same finding as `pkg trust key` and rc-pilot's --secret.
    compat.term's masked read is reachable from a package (rc-pilot
    now uses it). Changing the CLI contract touches every usage
    line, the man page and `launcher tape`, so it is an operator
    decision; a "-" placeholder meaning "prompt me" would keep the
    old form working for scripts.
```

## RC-PILOT NEVER WORKED END TO END (2026-09-06)

### Planned — robot/eeprom-rc-pilot.lua HAS NO BUILD STEP. The source is what

```text
robot/eeprom-rc-pilot.lua HAS NO BUILD STEP. The source is what
    the repo carries; the burnable image is what strip.lua --minify
    makes of it, and nothing produces that automatically -- the README
    now says how. build-disk.lua could emit robot/ into dist alongside
    the disks. Same shape as the "pack ships source unstripped" item.
```

## TBFS: THE COST WAS WRITES, AND A SECOND HANDLE (2026-09-06)

### Planned — THE PACK SHIPS SOURCE UNSTRIPPED

```text
THE PACK SHIPS SOURCE UNSTRIPPED. build-disk.lua copies each
    module's files as-is, comments and all, so blockfs.lua is
    ~50 KB on disk and in RAM when required, and the boot blob
    embeds all of it. strip.lua exists for the release tree and
    keeps every `--!` line; running the same pass over pack
    files would roughly halve the driver. Not done here: the
    hashes and the signature are taken over the shipped bytes,
    so this touches the build and publish chain, and the size
    ceiling in test_blockfs_perf.lua (52 KB) holds the line
    meanwhile. Worth doing before a machine with 192 KB tries to
    boot from TBFS.
```

### Planned — STILL ~8 SECTOR WRITES PER TINY FILE (inode alloc, directory

```text
STILL ~8 SECTOR WRITES PER TINY FILE (inode alloc, directory
    append + its inode, data block, bitmap, file inode, super).
    Half of those are per-operation metadata that a "close-time
    flush" could merge across a create-write-close sequence, at
    the cost of "written" meaning "on close" -- an operator
    decision, and not one to make for a filesystem on hardware
    that vanishes when someone breaks the block.
```

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

## ACCIDENTAL-GLOBAL / COMPAT SWEEP (2026-08-23)

### Planned — UNVERIFIED

```text
UNVERIFIED, NEEDS A LUA 5.3 BOX: gmatch's empty-match rule
    differs between the two architectures TOS supports. Lua 5.4
    refuses a match that ends where the previous one ended; 5.3
    has no such guard and returns the empty match. (Counted
    2026-09-06: TEN call sites, not ~15 -- core.lua x6, admin.lua,
    extras.lua, context.lua, editor.lua -- and the two bare ones
    named below; everything else already uses [^\n]+, which has
    no empty match to disagree about. Still unverifiable here:
    the emulator's Lua 5.3 lives inside a JNLua DLL that exports
    no C API, so there is no 5.3 interpreter to run the probe.)
    ~15 call sites
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

### Planned — Emulator checklist - the RBMK SKALA panel (Extras, v0.2.0)

```text
Emulator checklist - the RBMK SKALA panel (Extras, v0.2.0).
    NOTE: all of this is blocked behind rbmk/Plan.md open question
    #1 -- the console's real method names -- which only an in-world
    survey can answer. Do the survey FIRST; everything below assumes
    `rbmk survey` reports `usable: YES`.
      - `rbmk survey` against a real HBM console: does anything bind
        to `columns`? If nothing does, the panel is scalars-only and
        the core map never appears. That is a supported outcome, and
        the point of this check is to find out WHICH world we are in.
      - `rbmk skala` on a tier-3 screen: 15x15 cells must line up
        with the column ruler. A cell that renders 5 characters
        shifts its whole row -- the off-box tests pin the formatter,
        but only a GPU proves the ALIGNMENT.
      - the same at 80x25: the rail should be gone and the numbers
        should have survived (layout drops the rail before the
        digits, deliberately). Check the header still names the
        selected parameter, since that is the only place it appears
        without a rail.
      - a screen too small for the core map: must print the SIZE IT
        NEEDS, not "too small", and still show the scalar readings.
      - N/T/X/K/G swap the parameter; arrows move the inspection
        cursor and the status line follows it; TAB cycles the pages;
        Q leaves and GIVES THE SCREEN BACK.
      - `rbmk skala --wall` on a multi-seat box: each seat shows a
        DIFFERENT page, and seats keep their identity across a
        reboot (they are sorted for that reason). Confirm plain
        `rbmk skala` leaves the other seats alone -- that is the
        whole reason --wall is opt-in.
      - THE OVERRIDE: drive the core to a scram and confirm every
        unpinned pane switches to the alarm page, a pinned one does
        not, and a mere WARNING leaves the wall alone. Then pull the
        controller's modem and confirm every pane goes STALE.
      - the OpenOS satellite: rbmk-display.lua on a second machine
        must render the same picture. Then give it MORE SCREENS THAN
        GPUs and confirm the time-slicing works and does not flicker
        or reset resolutions.
      - `mapInterval`: watch for per-tick component-budget warnings
        on a real console. The map read is throttled separately from
        the safety poll precisely because this is unknown; if a real
        `getColumnData` is slow, this is the knob.
      - colour on a TIER-2 GPU: the bands were chosen to survive 16
        colours, unverified in-world.
      - off-box tests cover the arithmetic, the wire and the painted
        CELL CONTENTS (against a fake display that models state);
        what needs a GPU is alignment, colour on real hardware, and
        the multi-seat/multi-GPU behaviour.
```

### Planned — Emulator checklist - editor horizontal scrolling

```text
Emulator checklist - editor horizontal scrolling:
      - open a file with a line longer than the screen; typing
        past the right edge must scroll, and the cursor must
        stay visible (it used to vanish and look like a freeze)
      - the "<" and ">" edge markers appear only when there is
        more text that way, and do not flicker while typing
      - a .lua file still highlights correctly once scrolled:
        a string literal spanning the left edge must not turn
        everything after it into code-coloured text
      - select across a scrolled region and confirm the
        highlight lands on the characters it claims
      - resize the screen narrower with the cursor near the
        right edge; the next repaint must re-anchor the window
      - off-box tests cover the ARITHMETIC only; drawing needs
        a real GPU
```

### Planned — Emulator checklist - confirmTyped's interactive loop

```text
Emulator checklist - confirmTyped's interactive loop:
      - the box draws with the same frame/shadow as every other
        dialog (it calls drawDialog), at 80x25 and on a resized
        screen; the line COUNT is constant in both matched and
        unmatched states so it must not resize while typing
      - typing the word letter by letter, backspacing, and pasting
        it via the clipboard signal all reach Confirm
      - Confirm is inert until the word matches: clicking it moves
        focus rather than firing, Enter on it does nothing
      - Esc and ^Q both cancel; Cancel is the FIRST button, so a
        click-through lands on it
      - off-box tests cover the contract around this loop, not the
        loop -- it needs a real screen and signal stream
```

### Planned — Emulator checklist — key DERIVATION, added with KDF v2

```text
Emulator checklist — key DERIVATION, added with KDF v2:
      - TIME IT. `pkg trust key <label>` and `pkg sign` on a T1
        and a T3. v2 raised the round count 512 -> 4096, and
        4096 rounds of SHA-512 is 0.13 s natively; the on-box
        figure is the one that decides whether this is usable,
        and off-box tests cannot give it.
      - confirm the 5-second watchdog does NOT fire mid-derive.
        The loop yields every 256 rounds (16 yields); if a seat
        still stalls, lower that interval rather than the round
        count — the rounds are the point.
      - derive the SAME label twice on two machines and confirm
        the key matches, and a different label gives a different
        one. This is what makes the salt safe to require.
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

### Planned — OPPM checkout source paths: kernel.pkg's programs.cfg translator keeps

```text
OPPM checkout source paths: kernel.pkg's programs.cfg translator keeps
    the leading branch segment ("master/gui/gui.lua") as an on-disk path,
    so it expects a directory literally named `master` in the repo. A git
    CHECKOUT of an OPPM master branch has no such directory - the segment
    belongs to the raw URL oppm builds, not to the tree. Reading a cloned
    OPPM repo from a floppy therefore looks one level too deep and finds
    nothing. Harmless for OUR published index (oppm fetches by URL, where
    the key is correct), which is why it is recorded rather than rushed:
    confirm whether treating the key literally was deliberate before
    changing it. test_pkg_lifecycle.lua's fixture encodes the same
    assumption ("sources under master/<pkg>/"), and test_oppm_index.lua
    pins the current behaviour as [known gap] so a fix fails loudly.
```

### Planned — Screenshots. There is not one image in the repository, and every venue

```text
Screenshots. There is not one image in the repository, and every venue
    worth posting in is one where the screenshot IS the post. Six stills
    plus a boot GIF; the shot list, the capture method and the publish
    prerequisite are in docs/screenshots/SHOTS.md. The README already has
    the markup, commented out, waiting for the files.
```

### Planned — Get listed in `oppm list`: a PR adding this repo to

```text
Get listed in `oppm list`: a PR adding this repo to
    OpenPrograms/openprograms.github.io's repos.cfg. The `master` branch
    (build/oppm/) makes `oppm register` work; repos.cfg is what makes TOS
    show up for people who never heard of it.
```

### Planned — Install profiles: `install.lua --profile minimal|standard|full`, each

```text
Install profiles: `install.lua --profile minimal|standard|full`, each
    writing a trimmed system_manifest.lua. From the 2026-09-10 follow-up
    review, which measured the release at 1,619 KB of content (1,695 KB on
    disk with fileCost) and ~353 KB free on a Tier 2 disk -- down ~102 KB
    in six days with the file count flat, so this is content growth, not
    new files. The architecture already allows it (41 pcall(require) sites
    in kernel/init.lua, an 11-file critical set) and it composes with
    `deploy drive`, which copies exactly what the manifest lists. Their
    measured cut -- drop the installer, docs, networking, remote pkg, the
    package manager, compat, peripherals and the `extras` commands --
    leaves the full Commander UI at ~1,060 KB. Not urgent this week; the
    growth curve decides when it becomes so, and this turns a deadline
    into a knob.
```

### Planned — Anchor the network install to a KEY, not the transport. bootstrap.lua

```text
Anchor the network install to a KEY, not the transport. bootstrap.lua
    verifies every download against the manifest, but the manifest comes
    from the same host, so it proves "these are the bytes that repository
    is serving" -- not "these are the bytes the publisher released". Its
    own comment block says exactly that. Pin an Ed25519 public key in
    bootstrap.lua and sign the release manifest with the machinery `pkg`
    already has: the root of trust moves from the transport to the one
    file an operator can read before running it. Every part is in the tree
    already (2026-09-10 review, §2).
```

### Planned — Error registry: the rest of the migration. The first slice (2026-09-10)

```text
Error registry: the rest of the migration. The first slice (2026-09-10)
    gave tos/kernel/errors.lua its codes and tagged the refusals `why`
    already explained -- protected paths, permissions, the tier gates, rm's
    guards, the trash, unknown and unloadable commands. Everything else TOS
    prints in the error colour is still untagged prose: pkg, the network
    layer, vault, the drive and deploy commands, hardware faults (5xx-7xx
    are reserved and still empty). Tag them as they are touched, never
    renumber, and let test_error_registry.lua's scan of every shipped file
    keep each literal tag honest.
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
