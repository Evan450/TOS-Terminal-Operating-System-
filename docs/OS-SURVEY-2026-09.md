# Survey: what other OpenComputers OSes do better (2026-09-20)

Five OSes and four ecosystem standards, read as source, not as marketing. Every
claim below was checked against a clone; the files named are the ones actually
read. Items are ordered by what they would buy TOS, not by how interesting they
are.

**Already surveyed, not repeated here:** Cynosure 2 / ULOS, KittenOS NEO and
OCOS (all 2026-08-10, see `TODO.txt` and the matching `ROADMAP.md` sections).
This round is the rest of the field.

**This round:** Fuchas, Plan9k, PsychOS 2, MineOS, Zorya NEO (plus OpenLoader,
GEBL, Fuchas' `dualboot_init`), and the interop standards TOS is silently
opting out of — OEFI, VELX, OSDI/OCGPT/MTPT partition tables, and the
OpenComputers reserved-port registry.

Each item says what they do, whether it applies to TOS, why, and what it would
cost. Items marked **NOT A GAP** are recorded so nobody re-investigates them.

---

## 1. A BIOS THAT CAN RECOVER — and proof it fits in 4 KiB

**Source:** MineOS `EFI/Full.lua` + `EFI/Minified.lua`; Zorya NEO
(`mods/menu_classic`, `mods/loader_*`); Plan9k `openloader-init/init.lua`;
Fuchas `dualboot_init.lua`.

**Applies: yes, and it closes two open roadmap items** — *A BROKEN TOS INSTALL
ON THE COMMITTED BOOT DEVICE IS A LOOP* and *INSTALLING TOS REPLACES
`/init.lua` AND NOTHING PUTS IT BACK* (both under "THE BIOS REFUSED TO BOOT
ANYTHING BUT TOS", 2026-09-06).

The standing objection to a boot menu has been byte budget: `bios.lua` is 13,015
bytes of source that has to minify into a 4 KiB EEPROM, and `test_bios.lua`
enforces that. **MineOS disproves the objection.** `EFI/Minified.lua` is
**3,865 bytes** — under the limit with 231 bytes spare — and inside that it has:

- a **timed hotkey**: it boots normally unless you hold Alt during a one-second
  window, so the recovery path costs nothing on a healthy boot;
- a **boot-source menu** listing every `filesystem` component with label, HDD /
  FDD / SYS class, read-only flag, used-percent and address;
- per-disk actions: *set as bootable*, *change label*, *erase*;
- **internet recovery** — fetch and run a recovery script — and **URL boot**,
  both gated on an internet card being present;
- a **candidate boot-file list** (`/OS.lua`, then `/init.lua`) so it boots
  either its own OS or an OpenOS-shaped one, and it saves the choice to the
  EEPROM data field;
- a fallback loop: if the committed address is gone, it walks every filesystem
  looking for something bootable and re-scans on `component_added`.

Fuchas' `dualboot_init.lua` is the same idea at 1% of the size and worth copying
first: a stub `/init.lua` that checks for `/lib/core/boot.lua` (OpenOS) and
`/Fuchas/Kernel/boot.lua`, boots whichever exists alone with no prompt, and
prompts only when both are present. That is a ~40-line answer to "installing TOS
replaces `/init.lua`".

**Design notes for TOS:**

- Keep the hotkey *timed and silent*. A menu that always appears is a
  regression for the appliance case TOS is built for.
- **The EEPROM data field is already spoken for.** `bios.lua` puts the boot
  address on line 1 and the kernel anchors its manifest hash after a newline
  (`#SEC C1`). A menu that writes the data field must preserve line 2+ —
  MineOS' does not have this problem because it has nothing to preserve.
- Internet recovery has a trust problem TOS cares about and MineOS does not:
  fetching and running a script from a URL is exactly what `pkgsign` exists to
  prevent. If TOS does this, the recovery blob must be signature-checked, or
  scoped to "download `bootstrap.lua` and stop" — which is already the
  documented network install path.
- Zorya NEO is the *other* option: rather than grow `bios.lua`, ship a
  `loader_tos` module for it in TOS-Extras. Zorya already has
  `loader_openos`, `loader_fuchas`, `loader_cynosure`, `loader_monolith`,
  `loader_tsuki`, `loader_openkernel`; a loader is ~40 lines
  (`mods/loader_openos/init.lua`) returning `function(addr)` that builds an env
  and loads the OS's init. **But** Zorya then owns the EEPROM, runs the OS
  inside its own thread with a synthesized `_G`, and offers virtual components
  — all three of which TOS's boot chain has opinions about (the Lua-5.3 feature
  probe, the manifest anchor, `component_caps`). Cheap interop, real
  integration risk. Decide which, don't do both.

---

## 2. MOUNT PACKAGES AS READ-ONLY ARCHIVES INSTEAD OF EXTRACTING THEM

**Source:** PsychOS 2 `lib/pkgfs.lua` + `lib/libmtar.lua` + `lib/liblz16.lua`;
Fuchas `Fuchas/Filesystems/nitrofs.lua`; Zorya NEO `lib/fs_arcfs`,
`lib/util_romfs`, `lib/util_cpio`.

**Applies: yes. This is the biggest disk-footprint win available, and TOS
already owns every piece it needs.**

PsychOS installs a package by *registering its archive*, not by unpacking it:
`pkgfs.component` is a filesystem-component-shaped table over an mtar file
(optionally lz16-compressed) with a path index, where `write`, `rename`,
`makeDirectory` and `seek` return false and reads come out of the archive.
`pkgman.activatePackage` is one line: `require("pkgfs").add(path, compressed)`.

Why this matters more for TOS than for them: OpenComputers charges `fileCost`
(512 B default) per file *on top of* content. Measured on
`TOS-Extras/dist/optional-utilities` as shipped:

| | files | bytes | fileCost |
|---|---|---|---|
| all 16 packages | 76 | 745,015 | 38,912 |
| `cluster-master` alone | 13 | 140,631 | 6,656 |
| `blockfs` alone | 3 | 55,343 | 1,536 |

A full install leaves **~260 KB free on an empty Tier 2 disk** (README's own
number). Archive-mounting all 16 packages recovers ~23 KB of pure fileCost
(38,912 − 16 × 512) before compression, and the data card's deflate on Lua
source typically halves the content — call it 350–400 KB back on a disk that
has 260 KB to give. That is the difference between four installed packages and
a dozen.

**TOS already has the three hard parts:**

- `fs.mount(path, proxy)` takes anything "filesystem-component-shaped", and
  `netfs.lua` and `jbod.lua` are both existing producers of exactly that shape.
- `compress.lua` already frames deflate as **independently inflatable chunks**
  (`nChunks(u16)` then `cLen/cData` pairs) — that is random access at chunk
  granularity, which is what an archive mount needs. It was written for swap and
  backups; the property generalises for free.
- OC filesystem handles support `seek` (confirmed in `Reference/OpenOS`:
  `lib/devfs.lua:329`, `lib/core/full_buffer.lua:12`), so a mount can seek to a
  chunk instead of reading the file whole — which matters on a 192 KB box where
  the largest package is 140 KB.

**Design notes:**

- **Verification gets simpler, not harder.** `pkgsign` currently signs a
  manifest of per-file hashes; one archive is one hash and one signature, and
  the archive is immutable after install, so `srm scan` stops having to walk a
  package's files. Uninstall becomes one `fs.remove`.
- **Cost is honest and already documented:** `compress.lua`'s own header warns
  that data-card calls draw a per-tick budget and can sleep the machine a tick,
  so this is for cold data. Package code is read once per `require`, which fits;
  a package whose *data files* are read in a hot loop does not. Ship it as a
  per-package flag, not a global mode.
- **No data card, no problem:** `compress.lua` falls back to a "stored" blob, so
  an uncompressed archive mount still collects the fileCost win.
- `securefs` must still mediate the mount point, exactly as documented for
  `jbod` ("it is a TRANSPORT, not an access layer").

---

## 3. COPY-ON-WRITE OVERLAY MOUNTS

**Source:** Plan9k `pipes/06_cowfs.lua`.

**Applies: yes — small, self-contained, and it unlocks three things TOS
currently cannot do.**

Their `cowfs.new(readfs, writefs)` returns one proxy: reads fall through to the
read-only side unless the write side has the file, writes always land on the
write side, and deletes are recorded as `<dir>/.cfsdel.<name>` whiteout files so
a delete can shadow a file that only exists on the read-only side. ~120 lines,
no kernel changes.

What it would give TOS, all currently missing:

1. **Run from read-only media.** HEAD already has "a read-only boot disk offers
   to install itself" (commit 70a5dcf) — an overlay is the other answer: run
   *now*, with writes on any writable disk, and install later or never.
2. **A kiosk or log-wall appliance that resets on reboot.** Point the write side
   at a scratch volume and wipe it at boot. `kiosk.cfg` gates commands today but
   the filesystem is still permanently mutable; this is the missing half of an
   appliance story, and it composes with the LOG WALL item already in the
   roadmap.
3. **Try-before-commit.** `pkg install` or an `srm` experiment on an overlay,
   inspect, then either merge or drop the write layer. This is a weaker form of
   what `srm baseline --full` buys, reached without media.

**Design note:** whiteouts are a namespace hazard — a real file called
`.cfsdel.x` must not be able to hide `x`. Plan9k does not guard this. TOS's
`fs.lua` already refuses to mount over a non-empty directory (`#SEC H27`) and
refuses to delete mount points, so the house style is to name and block this
class; do it here too, with a test.

---

## 4. A DRIVER REGISTRY WITH PER-DEVICE PROBING

**Source:** Fuchas `Fuchas/Libraries/driver.lua`, `Fuchas/Drivers/<type>/<name>.lua`,
`Fuchas/Filesystems/README.md`.

**Applies: yes, and TOS is already hand-rolling the special cases this
generalises.**

Fuchas resolves a device to a driver instead of hardcoding one. Drivers live at
`Drivers/<component type>/<name>.lua` along a `DRV_PATH` search path; each
returns a spec with `isCompatible(addr)`; `findBestDriver(type, addr)` probes
candidates and picks one; `changeDriver(type, addr, path)` lets an operator pin
a specific driver to a specific device; and in `SAFE_MODE` only a `basicDrivers`
set (`drive`, `gpu`) is allowed to load at all. Two printer drivers ship side by
side — `printer/openprinter.lua` and `printer/ccprinter.lua` — which is the
whole point.

TOS today: `hal.lua` is a fixed `type -> {address, proxy, tier, label}` registry
with hand-written tier heuristics; `tos/peripheral/` is three kernel modules
(`inventory`, `redstone`, `robot`) with per-call cap checks; Extras ships
`mouse` and `printer` as ordinary libraries in a `drivers` category. That works,
but:

- **The variant problem is already being solved ad hoc.** The roadmap's printer
  checklist contains "a 1.7-era printer if one is available: `width`/`maxWidth`
  absent, `printer` must say 'older build: no width…' and still print" — that is
  `isCompatible(addr)` written by hand inside one module. The RBMK supervisor's
  `rbmk survey` is the same shape again ("does anything bind"). A third instance
  is coming; the second is where you build the abstraction.
- **A new device needs a kernel edit.** Adding, say, an HBM console or a second
  printer mod means touching `tos/peripheral/` or living as a library outside
  the cap system. A `pkg`-installed driver that the kernel *finds* is strictly
  better, and `etc/component_caps.cfg` + `component reload-caps` already
  supplies the authority half of the design.
- **Safe Mode already exists** and already has a floor; a `basicDrivers`
  equivalent falls out of the self-stripping floor work rather than being new.

**Design note:** the authority model must not follow Fuchas here. Their rule is
"a process must use drivers unless it is admin", i.e. root bypasses the
abstraction. TOS's sandbox has no such escape and should not grow one: a driver
is a *binding* mechanism (which code drives this device), and the capability
check stays exactly where `peripheral/redstone.lua:requireCap` puts it.

---

## 5. ADDRESSABLE LOCAL IPC

**Source:** Fuchas `Fuchas/Libraries/ipc.lua` (implements OETF #18, "Open
Inter-Process Communication"); Plan9k `pipes/17_ipc.lua`.

**Applies: yes — a real gap, and three planned features need it.**

Fuchas gives a process a socket to another *PID*:
`ipc.socket(target, id)` with `write(...)` / `read()` / `closed()`, built on
per-process signals (`computer.pushProcessSignal`) rather than the global queue.
Asynchronous write, synchronous read, no rendezvous needed.

TOS has two things and neither is this: `pipe.create()` is an anonymous
in-memory stream handed to a child at spawn (shell pipelines and redirection,
64 KB cap, `#SEC M2`), and `notify.post` is a one-way queue to whichever human
is looking. There is no way for an `rc.d` service and an unrelated process to
talk — which is why the LOG WALL item has to ask "is the feed LOCAL or REMOTE?"
and why the mesh gets reached for even when both ends are on one machine.
`cluster-manager` and `mail`'s inbox tab are the same shape.

**Design notes:**

- The dispatcher is most of the way there: `event.lua` already records the
  registering PID and spawn generation (`#SEC H13`, `#SEC H31`, `#SEC M-11`) and
  fires each listener under that PID's context. A targeted push is a small
  addition to machinery that already thinks in PIDs.
- **It must be capability-gated**, which Fuchas' is not. "Send to any PID" is an
  authority a sandboxed program should not have by default: unsolicited messages
  to a privileged service are an injection surface, and PID-scanning is an
  information leak. The natural shape is a named endpoint a service *registers*
  and a `ipc.connect(name)` cap per name — not raw PIDs.
- Do not build it on the compat event queue: `compat/event.lua` deliberately
  blocks sensitive signal names, and IPC traffic must not become a way around
  that filter.

---

## 6. GENERATED API DOCS, AND PERMISSION ANNOTATIONS THAT CAN BE TESTED

**Source:** PsychOS 2 `finddesc.lua`, `gendoc.lua`, `build.sh`; Fuchas LDoc
comments (`config.ld`) — in particular `-- @permission security.revoke`.

**Applies: yes, and the second half is more valuable than the first.**

PsychOS generates its API reference as part of every build: `build.sh` runs
`finddesc.lua` and `gendoc.lua` over `lib/` and `module/` and emits `doc/*.md`
plus an all-in-one `apidoc.md` (and a PDF if pandoc is around). Their convention
is a one-line comment on the function line giving argument types, return types
and a description — cheap to write, impossible to drift far.

TOS has 37,054 lines of Lua under `tos/` and a 2,731-line hand-written
`MANUAL.md`. The manual is *good*, and this is not a proposal to replace it with
generated output — it is the operator's book and should stay written. What is
missing is a *reference* for the kernel API that cannot silently disagree with
the code. The repo already generates `ROADMAP.md` from `TODO.txt` via
`build/make_roadmap.py`, so a generator is an established idiom here, not a new
one.

The sharper idea is Fuchas': annotate each function with the permission it
requires, right where it is defined. For TOS that means every kernel entry point
carrying the capability it enforces — and then a **test that the annotations and
the enforcement agree**. That is the missing verification half of the already
planned *CONSOLIDATE THE SECURITY POLICY INTO ONE FILE* (KittenOS survey): a
single policy function makes the policy readable, and annotation-vs-enforcement
makes it *checkable*. Fuchas writes the annotations and never checks them; TOS
would be the first to.

---

## 7. STAMP THE BUILD

**Source:** PsychOS 2 `build.sh`:
`_OSVERSION="PsychOS 2.0a3-$(git rev-parse --short HEAD)-$KVAR"`.

**Applies: yes. Small, and it pays for itself the first time.**

TOS sets `_G._TOS.version = "1.5.0"` and `codename = "Aletheia"` by hand in
`init.lua:430`, and `build-release.sh` stamps nothing. So a screenshot, a
`selftest.log`, or a `doctor` dump from a box that has been running for a week
cannot tell you which tree produced it — and the on-box battery's whole purpose
is telling you what the code actually did. `sync-emulator.py` exists because
"the boot disk was eleven files behind" was a real round that reported a stale
answer; a build stamp is the cheap detector for the same class.

Add `build` (short hash, plus a dirty marker) and the strip variant to `_TOS`,
set by `build-release.sh`, printed by `colophon` and the self-test header. Keep
the hand-set version — the release conventions already require version, README
and CHANGELOG to move together.

---

## 8. THE PORT REGISTRY, AND WHY 42 IS FINE BUT UNDOCUMENTED

**Source:** GERT repo → `Reserved OC network card ports.txt` (list now at
GlobalEmpire/OC-Programs); Minitel; Zorya NEO `mods/net_minitel`.

**Applies: partly — no collision today, but no protection against one either.**

The ecosystem keeps a registry: **14** Ethernet-over-OC, **148** GUI service,
**4096** MultICE/Minitel, **4378–4379** GERTi, **4662** short messages, **9100**
network print service, **9900** Zorya BIOS LAN boot.

TOS defaults to `listenPort = 42` (`config.lua:54`, `net/init.lua:94`), which is
unclaimed — good, no action needed on the default. The gap is the two things
around it:

1. **`listenPort` is operator-settable with no advice.** An operator who sets
   4096 puts TOS traffic onto a Minitel network, where both sides then see
   malformed frames — TOS's own `net` will reject them cleanly, Minitel's may
   not. `net` should refuse, or at minimum warn once, when the configured port
   is a registered one, and name the protocol it belongs to.
2. **42 should be registered and documented.** It costs one message to the
   registry maintainer and one line in the manual, and it is how the *next* OS
   avoids colliding with TOS.

This is also the cheap, correct form of the standing MINITEL decision ("decide,
don't default"): TOS stays bespoke, and *documents* the port so coexistence
works without a bridge.

---

## 9. NAME WHAT IS ON A DRIVE BEFORE ERASING IT

**Source:** OSDI and OCGPT partition-table specs; MTPT (Minitel partition table,
used by PsychOS); Plan9k `plan9k-drivers/17_gpt.lua`,
`plan9k-filesystems/mount.msdos.lua`; Zorya NEO `lib/util_osdi`,
`mods/loader_osdi`.

**Applies: yes, at small scope. Calibrated: the confirmation already exists.**

TBFS (`TOS-Extras/modules/blockfs`) writes its own `"TBFS"` superblock magic at
sector 1 and `blockfs.format` zeroes the metadata region unconditionally. The
`drive`/install path does gate this behind a danger confirm box that says
"Anything on it now is gone" (`commands/extras.lua:1405`), so nothing is
silently destroyed. What it cannot do is tell the operator *what* is there: the
only answer TBFS can give about a foreign volume is "not a TBFS volume".

Two cheap improvements:

- **Probe known magics before formatting** — TBFS itself, OSDI, OCGPT (sectors
  2–9), MTPT, msdos — and name what was found in the confirmation. "This drive
  holds an OSDI partition table" is a different decision from "this drive looks
  blank", and read-only probing cannot break anything.
- **A read-only foreign-volume reader** is worth a line in the roadmap, not a
  round of work: recovering files off another OS's disk is a real base-admin
  task, and TOS currently cannot see such a drive at all.

Worth stating plainly: TOS's unmanaged-drive story is intentionally bespoke and
should stay that way — TBFS's boot region, `bootBlob` and the EEPROM stage-2
loader are tied to how TOS boots. This item is about *recognising* other
formats, not adopting one.

---

## 10. LOCALISATION REACH — AND LOCALISE THE INSTALLER

**Source:** MineOS `Localizations/*.lang` (~20 languages), plus a **separate**
`Installer/Localizations/` set; the installer asks for a language first.

**Applies: partly.** TOS has `i18n.lua` and `usr/lang/` — with exactly one pack
(`ru.lang`). MineOS' format is what makes ~20 community translations happen: one
file per language, a flat Lua table of short keys, no tooling required to
contribute. TOS' is already close to that shape.

The transferable half is the *installer*: MineOS localises the thing a new user
sees before the OS exists and picks language as step one. TOS's `install.lua`
and `bootstrap.lua` are English-only, and they are the first and sometimes only
screens a new operator reads. Routing their strings through `i18n` and asking
for a language first is a bounded change, and it is what turns a single `ru.lang`
into a reason for someone to send a second pack.

---

## 11. A PER-LAUNCH CONFINEMENT COMMAND

**Source:** Plan9k `plan9k-containers/sandbox.lua` and `pipes/19_cgroups.lua`.

**Applies: yes, as a shell front-end over machinery TOS already has.**

Plan9k composes namespaces at launch from the command line:
`sandbox wl fc0 wl fcd component spawn /bin/a.lua` (run with access to exactly
two components), `sandbox module spawn …` (fresh module namespace),
`quietin/quietout/quieterr`. Their cgroup kinds are `signal`, `filesystem` (a
root, i.e. chroot), `network` (interfaces), `module` (its own
`package.loaded`/`preload`) and `component` (whitelist/blacklist with a
parent-chained `allow(addr)`), inherited from the spawning thread.

TOS's capabilities are declared in a package manifest and accepted by an admin
at install time; `progenv.lua` already builds a process env from an
`opts.caps` table. What is missing is the operator-facing verb: *run this
program, right now, with no network* — the thing you want when someone hands you
a script and you are not installing it as a package. That is a front-end over
`progenv` plus the existing cap vocabulary, not new mechanism.

The **filesystem** cgroup is the one genuinely new primitive in their list: a
per-process root. TOS has per-user ACLs via `securefs`, which is a different and
mostly better answer, but a confined root is the natural thing to give an
untrusted one-off program, and it composes with the COW overlay in item 3.

---

## 12. A SINGLE-FILE SIGNED EXECUTABLE (VELX) — the cheap subset

**Source:** Fuchas `Fuchas/Libraries/velx.lua`; spec at
Adorable-Catgirl/Random-OC-Docs `formats/velx/v1.md`; Zorya NEO `lib/exec_velx`,
`mods/util_velx`.

**Applies: partly — take the metadata, skip the container.**

VELX is a container: magic `\27VelX`, format version, compression id, **Lua
version**, **OS id** with a library flag, archive type (`cpio` or none), then
sized program / OS-dependent / **signature** sections and an archive. It is a
published, multi-implementation format — Zorya can execute one from the
bootloader.

TOS does not need the container: `pkg` is directory-based, signs an Ed25519
manifest and hashes every file, which is strictly stronger than VELX as
*implemented* (their parser reads `signatureSection` and never verifies it —
confirmed, `velx.lua` only stores and re-writes those bytes; PsychOS'
`pkgman.lua` has no integrity check at all; MineOS' market has none).

The cheap subset worth stealing is the **declared runtime**: a package manifest
field saying which Lua architecture and which OS it was built for. TOS requires
the Lua 5.3/5.4 architecture and the BIOS and `/init.lua` both probe for it —
but a *package* built against the wrong arch fails at `load` with a syntax
error, not with a sentence. One manifest field and one check at install time
turns that into "this package needs the Lua 5.3 architecture; sneak-click the
CPU".

---

## NOT GAPS — recorded so they are not re-investigated

- **Plan9k's module cgroups vs TOS's `isolatedModule`.** Theirs shadows module
  tables with `setmetatable({}, {__index = kernel.modules.x})` per group. TOS
  already does this *and* locks the metatable, filters `pairs()`, and (in the
  in-flight H-01 work) masks kernel-only hook keys so a sandbox cannot see
  `compat.term._gpuForCaps`. Ours is strictly stricter. Nothing to import.
- **Fuchas' per-process signal queues** (`computer.pushProcessSignal`). The
  security motivation — one process reading another's events — is already
  handled at a different layer: `compat/event.lua` blocks sensitive signal names
  outright, naming keystroke-logging other seats and clipboard sniffing as the
  attacks. The *other* use of per-process queues is addressable IPC, which is
  item 5.
- **MineOS' double-buffered GUI.** TOS has a shadow buffer with an operator
  override (`bufferMode = "off"`), and the workload-specific second renderer is
  already scoped in the LOG WALL item.
- **MineOS' GUI desktop, app market, IDE, FTP client, 3D library.** Explicitly
  not what TOS is for — the README already says MineOS is the better answer for
  a graphical desktop. Not a gap; a different product.
- **procfs / sysfs / devfs** (Plan9k `10_procfs.lua`, `10_sysfs.lua`,
  `10_devfs.lua`; OpenOS `lib/devfs.lua`). Already decided in the Cynosure
  survey: TOS exposes the same facts as commands (`lsdev`, `hw`, `sysinfo`,
  `doctor`). The one property still worth wanting is unchanged — a sandboxed
  program reading its own PID or free memory without a new capability.
- **Minitel in the kernel.** Already decided: the mesh stays bespoke because
  trust tiers and replay-resistant MACs cannot be had from someone else's
  protocol; a bridge is an Extras package if ever. Item 8 is the part of that
  decision that still needs doing.
- **MineOS' hand-maintained `Full.lua` + `Minified.lua`.** TOS generates the
  flashable BIOS from source via `strip.lua --minify` with a test enforcing the
  budget. Ours is better; do not copy theirs.
- **Fuchas' SJF scheduler.** Shortest-job-first needs job length estimates that
  nobody in this ecosystem has. TOS preempts on a wall-clock budget plus a
  per-resume instruction budget (`process.lua:960`, `debug.sethook`), which is a
  harder guarantee than any scheduling policy. Not applicable.
- **Fuchas' "admin bypasses drivers" rule.** An anti-pattern for TOS — see the
  design note in item 4.

---

## WHERE TOS IS ALREADY AHEAD OF THIS FIELD

Recorded because a survey that only lists gaps mis-sets the priorities.

- **Package integrity.** TOS verifies an Ed25519 manifest signature and a
  per-file hash on arrival. Of the five OSes read this round, **none verifies
  anything**: Fuchas' VELX parser stores a signature section it never checks,
  PsychOS' `pkgman` fetches and activates archives with no hash, MineOS installs
  from a market over HTTP(S) with no signing. This was the OCOS survey's "biggest
  real gap we have" and it is now a lead.
- **Preemption.** Everyone else is purely cooperative; a runaway program hangs
  the machine until OC's watchdog kills the *whole computer*. TOS traps it per
  process with a named error.
- **Sandbox depth.** Per-sandbox module views with locked metatables, an
  explicit module whitelist, capability-bound `term.gpu()`, and cap re-checks at
  the peripheral modules. Fuchas' is user-permission-based with a root bypass;
  Plan9k's is namespace-based with no capability vocabulary.
- **The mesh.** Pairing before trust, trust tiers, MAC authentication and replay
  protection. Minitel and GERT are both plaintext routing protocols by design.
- **The on-box battery.** Nine checks that run inside a booted TOS on real
  hardware and write a report the host reads. Nothing else surveyed tests itself
  on the platform it ships for.

---

---

# Round 2 — the deeper pass (2026-09-20, same day)

Round 1 read the systems that had never been looked at. This round goes back
over the ones that had — OpenOS, OCOS, Cynosure 2, KittenOS NEO, Plan9k — with
the source in hand rather than a survey note, and answers two questions that
were open: **is the vendored OpenOS stale?** and **how good is our OpenOS
compatibility, actually?**

Both now have numbers.

---

## 13. IS `Reference/OpenOS` STALE? No — one patch version, three cosmetic files

**Checked against** `MightyPirates/OpenComputers` master (sparse clone of
`src/main/resources/assets/opencomputers/loot`).

| | version | files |
|---|---|---|
| `Reference/OpenOS/openos` | **OpenOS 1.8.9** | 179 (+ `README-LICENSE.md`, `tree.txt`) |
| upstream master | **OpenOS 1.8.10** | 179 |

`diff -rq` over the two trees reports exactly **three** differing files, and all
three are cosmetic:

- `boot/89_rc.lua` — one added blank line.
- `lib/core/boot.lua` — `_OSVERSION` string, `1.8.9` → `1.8.10`.
- `usr/misc/greetings.txt` — `http://ocdoc.cil.li/` → `https://`.

**No API drift.** Nothing TOS's compat layer is written against has changed, so
the reference is safe to keep reading. Re-check any time with:

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/MightyPirates/OpenComputers.git oc && cd oc && git sparse-checkout set src/main/resources/assets/opencomputers/loot
```

then `diff -rq Reference/OpenOS/openos <clone>/…/loot/openos`. Worth doing once
a release rather than on a schedule — OpenOS changes slowly and visibly.

Also worth knowing: that loot directory carries **OpenLoader and Plan9k as
shipped loot disks**, alongside `oppm`, `network`, `irc`, `dig`, `builder`,
`maze`, `generator` and `data`. Those nine disks are the corpus used below.

---

## 14. HOW GOOD IS OUR OpenOS COMPATIBILITY? 95% of shipped programs, and the
## gap is one module we already have

> **Done, 2026-09-20.** All three shims ship — `tos/compat/{robot,process,note}.lua`,
> registered in both shim lists, manifested, and pinned by
> `test_compat_{robot,process,note}.lua` (133 assertions). Two bugs in
> `peripheral/robot.lua` surfaced underneath and are fixed: `use()` put a boolean
> in the mod's `face` slot on every call, and `durability()` called a method
> OpenComputers does not have. See the CHANGELOG and the `[x]` entry in
> `TODO.txt`. The measurement below is left as written, as the evidence that
> chose these three names.

The README claims "OpenOS compatibility, so much of what already exists still
runs". Until now that was an assertion. Here is the measurement.

TOS shims **12** OpenOS module names (`init.lua:579` `OPENOS_SHIMS`, mapped in
`compat/init.lua`): sides, colors, keyboard, text, serialization, buffer, term,
filesystem, event, shell, io, internet. OpenOS ships **25** modules in `lib/`.
The question is which of the missing 13 real programs actually reach for.

**Method:** extract every `require("…")` from a corpus, discount names the
program's own disk ships as a sibling library, discount OC machine globals
(`component`, `computer`, `unicode`), and count what is left.

**Corpus A — the nine OpenComputers loot disks, programs only** (OpenOS's own
`lib/` and `boot/` internals excluded, since TOS replaces them rather than
running them): **80 files, 4 fail (5%)**.

| missing name | files | examples |
|---|---|---|
| `robot` | 4 | `builder/usr/bin/build.lua`, `dig/usr/bin/dig.lua`, `generator/usr/bin/refuel.lua` |
| `process` | 1 | `builder/usr/bin/build.lua` |

**Corpus B — community programs** (OpenPrograms: Vexatos, Magik6k, Gopher):
**60 files, 13 (21%)** touch a non-shimmed name — but after discounting each
repo's own vendored libraries (`lib.morse`, `digest.crc32lua`,
`compress.deflatelua`, which install alongside their program), the real list is
the same three names: `process` (5), `robot` (3), `note` (1).

**So the whole measured gap is three modules**, and one of them we already
wrote:

- **`robot` — the module exists, it is just not reachable under the OpenOS
  name.** `tos/peripheral/robot.lua` already implements forward, back, up, down,
  turnLeft, turnRight, swing, use, place, detect, drop, suck, select, count,
  space, inventorySize, durability, name — with cap checks. It is not in
  `OPENOS_SHIMS`, so `require("robot")` fails.
  **The one real piece of work is API shape, not capability:** OpenOS exposes
  *directional variants as separate functions* — `detectUp`/`detectDown`,
  `swingUp`/`swingDown`, `placeUp`/`placeDown`, `dropUp`/`dropDown`,
  `suckUp`/`suckDown`, `useUp`/`useDown`, `compareUp`/`compareDown`, plus
  `turnAround`, `compareTo`, `transferTo`, `level`, `tankCount`/`tankLevel`/
  `tankSpace`, `getLightColor`/`setLightColor` — where ours takes a `side`
  argument. The shim is a name-to-side adapter of maybe 40 lines, plus
  pass-throughs for the handful we do not implement. (API confirmed against
  Plan9k's `usr/lib/robot.lua`; base OpenOS does not ship one — it arrives with
  the robot.)
- **`process`** — programs use `process.info().path` to find their own path and
  `process.running()`. A partial shim over `kernel.process` covering `path`,
  `command` and `data.vars` would cover every use seen in both corpora.
- **`note`** — pure arithmetic (note name → frequency), ~30 lines in OpenOS's
  `lib/note.lua`, no capability implications at all.

Add those three and the measured failure rate on both corpora goes to **zero**.
That turns the README's claim from a hope into a number, and the number is a
good one — worth saying out loud in the README once it is true.

**Honest caveats:** a `require` succeeding is not a program working (caps,
paths, and term behaviour still differ), and neither corpus contains the
`thread`-heavy daemon style some community code uses. `thread`, `uuid`, `rc`,
`bit32`, `tty`, `sh`, `vt100`, `devfs`, `transforms`, `package`, `pipe` went
unrequired by *any* program in either corpus — which is the argument for not
shimming them until something asks.

---

## 15. A HEADLESS BOOT TEST, AND THE RECIPE IS ALREADY WRITTEN

**Source:** OCOS `tools/test-boot.sh`, `tools/run-emu.sh`, `emulator/instance`.

**Applies: yes — this is the missing half of `[~] IN-EMULATOR BOOT SMOKE TEST,
in CI`, which has been in progress since the August OCOS survey.**

They run the whole thing unattended under **ocvm**, and the shape is exactly
what TOS's battery already produces:

1. Wipe every UUID-shaped directory in the emulator instance, *so a missing log
   is detectable* rather than reading a stale one from the last run — the same
   failure mode `sync-emulator.py` exists to prevent here.
2. Stage a real package into the writable filesystem so the self-test exercises
   a genuine install rather than a synthetic one.
3. `timeout 240 script -qc tools/run-emu.sh …` — **`script` gives ocvm a real
   PTY**, without which the GPU comes up 0×0. That one line is the trick that
   makes headless work.
4. The OS writes `/selftest.log` and **shuts itself down**, so the outer
   `timeout` is only a stuck-boot guard.
5. Exit codes: `0` pass, `2` if the log contains `^FAIL`, `1` if no log was
   written at all — and on `1` it dumps the last 30 lines of the emulator log
   to stderr.

TOS already has (1) in `sync-emulator.py`, already writes `/var/selftest.log`,
and already has nine checks to run. **The missing pieces are: an emulator that
can be driven headlessly (ocvm rather than Ocelot's GUI), the `script -qc` PTY
trick, and a self-test mode that powers the machine off when it finishes.** The
README currently calls powering on "the one manual step"; this is how that step
stops being manual.

Their 240-second budget is worth noting too, with the reason given in the
comment: pure-Lua 1024-bit RSA verification takes 10–30 s on a simulated T1 CPU.
TOS's Ed25519 is cheaper, but the lesson stands — budget for crypto on a
simulated CPU, not a real one.

---

## 16. DRY-RUN CAPABILITY ENFORCEMENT, AND PATH-SCOPED CAPS

**Source:** OCOS `src/sys/k/cap.lua`, `src/sys/k/exec.lua`,
`lib/auth/audit`.

**Applies: yes, and it upgrades `[*] AUDIT LOG FOR CAPABILITY DENIALS` from an
idea into something with a clear shape.**

Two ideas, both small:

1. **An `enforce` flag with an audit trail.** Their `cap.check` has a mode where
   it *always returns true but writes a denial record*: "when false, cap.check
   always returns true but writes a denial record to the audit log; when true,
   cap.check returns false on a deny and the caller raises EPERM." That is a
   dry-run mode, and it is the safe way to tighten a sandbox on a live base:
   turn enforcement off, run the workload, read what *would* have broken, then
   turn it on. For TOS it also makes an excellent test fixture — run the OpenOS
   compat corpus in audit mode and the log tells you exactly which capabilities
   real programs need, which is the empirical version of the guesswork in the
   compat item above.
2. **Namespaced, glob-matched capability strings.** Theirs look like
   `syscall:write:/var/log/*`, `syscall:write:/mnt/*/var/log/*`,
   `component:<type>:<addr>` — so a service is granted write access **to a path
   prefix**, not to the filesystem. Ours are flat booleans on a caps table
   (`caps.gpu`, `caps["peripheral.redstone"]`), and write scoping is done by
   `securefs` per *user*. That is a different and mostly better answer for
   humans — but for a **sandboxed daemon with no human behind it**, a
   path-scoped write cap is strictly tighter than "can write as this user". The
   `logd` unit above is the clean example: it can write `/var/log/*` and
   nothing else.
   Not a wholesale change — the natural first use is the rc.d services, whose
   caps are already declared and already gated (`ALLOWED_SERVICE_CAPS`).

---

## 17. SPLIT THE BIOS: A MINIMAL EEPROM, THE RECOVERY UI IN STAGE 2

**Source:** OCOS `efi/ocos.efi.lua` (4,164 B source → **3,109 B** minified) and
its own comment; GEBL's README; Zorya's selection timeout.

**Refines item 1.** MineOS proves a full menu *fits* in an EEPROM. OCOS argues
you should not put it there anyway: *"the boot-mode menu, recovery flows and
pretty splash all live in `/sys/boot.lua`, where they have room to breathe"* —
the EEPROM does the minimum (find a medium, read config, load stage 2, and on
any failure draw a full-screen panic with the reason and boot info).

That is the better shape for TOS, and it is nearly the shape we already have:
`bios.lua` is already a POST + loader, and `/init.lua` is already stage 2. The
split becomes:

- **EEPROM:** a timed hotkey, a *boot-device* chooser (which disk), and a panic
  screen that names the reason. Small enough to stay inside the budget with
  room for the manifest anchor.
- **Stage 2 on disk:** the rich recovery menu — boot profiles, safe mode, `srm`
  restore, `doctor`, the disk utility. Room to breathe, and it can use the
  kernel's own modules.
- **The split's one weakness, stated plainly:** if the *disk* is the thing that
  is broken, stage 2 is gone and only the EEPROM half is left. That is exactly
  why the EEPROM half must still be able to pick a different disk. It is also
  the argument for the emergency terminal staying where it is.

Two behaviours to copy from the smaller bootloaders, both from GEBL's feature
list: **quick-boot** (if exactly one bootable OS is found, boot it without
prompting) and an **init finder** (if the config is missing or unreadable,
search the filesystem root for a bootable file instead of giving up). Zorya adds
the third: a **selection timeout** that falls through to the default.

---

## 18. USE `mtar`, DO NOT INVENT AN ARCHIVE FORMAT

**Source:** PsychOS `lib/libmtar.lua`; ULOS 2 ships `mtarldr` (a bootloader that
loads the system *from* an mtar); Zorya reads mtar/cpio/romfs/arcfs.

**Refines item 2.** If TOS grows an archive mount, the format should be `mtar`
rather than something new. It is about a hundred lines and the header is
trivial:

```
\255\255  <version:u8>  <nameLen>  <name>  <fileLen>
```

version 0 uses `>I2` for the file length, version 1 `>I8` (the extended-size
format). Entries stream, so an iterator can walk the archive without loading it;
`cleanPath` strips `.` and `..` segments **at parse time**, which is a path
traversal guard TOS would otherwise have to write itself.

Why it matters beyond saving work: four independent implementations already read
it (PsychOS, ULOS's loader, Zorya's reader, plus the writers), so a TOS package
archive would be *readable by other systems*, and a TOS box could read theirs.
That is interop for free in the one place where TOS has nothing to lose by
being compatible — a package archive has no trust properties of its own; the
Ed25519 signature over it is where the security lives, and that stays ours.

---

## 19. LINE DISCIPLINES — the structural answer to two open bugs

**Source:** Cynosure 2 `src/disciplines/{main,tty,null}.lua`.

**Applies: as a direction, not a task. Expensive, and worth writing down before
the next terminal bug gets patched in isolation.**

Their own comment says it best: line disciplines are *"a middle layer between
the raw stream and the character device… the TTY line discipline is what makes
ctrl-C, ctrl-\, and ctrl-Z work. This line discipline can be put over a network
socket, a serial connection, or a virtual TTY provided by the kernel — and the
application (ideally the user, too) will see no difference in behavior."*

Three currently separate TOS problems are the same problem in that framing:

- **`H-04` (open bug):** `term.read()` takes signals off the machine-wide queue.
  A per-stream input queue with a discipline in front is where that read should
  be getting its characters.
- **`H-06` (open bug):** two sandboxes still share `compat.term`'s cursor. A
  discipline instance per stream owns its own line state.
- **`rsh` has no pty.** A remote shell is a socket; with a discipline over it,
  the remote side behaves like a local terminal without `rsh` knowing anything
  about terminals.

This is not a suggestion to rewrite the terminal layer. It is a note that the
next time one of these is patched, the patch should move *toward* one
input-stream abstraction with a discipline, instead of adding a fourth special
case to `compat.term`.

---

## 20. SERVICES: WE ALREADY HAVE THE FEATURES — two narrow findings anyway

**Source:** OCOS `src/etc/services/*.cfg` and its supervisor; TOS
`tos/kernel/rc.lua`.

**Mostly NOT A GAP, and this corrects an assumption worth recording.** OCOS's
service framework reads like a clear lead — declarative units, topo-sorted
startup, supervised restart, per-service caps. TOS's `rc.lua` header claims the
same list, and the code backs it: `topoSort` at `rc.lua:135`, dependency-ordered
start at `:423`, restart supervision at `:516`, per-service `caps` and `user`.
So the comparison is about *detail*, not capability. Two details are worth
having:

1. **Service metadata is recovered by regex over the source text.**
   `rc.lua:237` does `src:match("restart%s*=%s*true")` to decide whether a
   service restarts. The returned table is also consulted (`:403` uses
   `result.restart`), so this is a pre-scan rather than the only path — but a
   comment mentioning `restart = true`, or a value computed rather than
   written literally, will be read wrong. OCOS keeps the metadata in a separate
   `.cfg` that is *data* and cannot be misread. A middle option that fits our
   idiom: keep the file, drop the regex, and have the pre-scan load the table
   in a bare environment.
2. **`restartCount` never decays.** `tryRestart` stops at `maxRestart` and logs
   — good, no thrash — but the count is per-lifetime, so a service that crashes
   once a week eventually exhausts its budget and stays down with only a log
   line to say why. OCOS's answer is exponential backoff plus a tri-state
   policy (`always` / `on_failure` / `one_shot`); ours could be as small as
   resetting the count after a service has stayed up for N minutes. Their
   `one_shot` comment names the case it protects against, which is worth
   stealing verbatim: *a missing GPU should not make the supervisor thrash.*

---

## 21. MESH: THE ROUTE INFORMATION IS ALREADY IN THE PACKETS

**Source:** Plan9k `routed` (RIP v2 over its own IPv4 stack) and `plan9k-ohcp`
(address autoconfiguration, subnet-aware, installs routes on lease);
`tos/kernel/net/mesh.lua`.

**Mostly NOT A GAP.** Plan9k does real networking — addresses, subnets, route
tables, RIP updates, multicast — and TOS deliberately does not: no routing
table, a node knows only its radio neighbours, and messages reach further by
controlled flooding with `DEFAULT_TTL = 8`, `MAX_TTL = 16`, a 512-id dedup cache
and store-and-forward retries. That is the right trade for OC-sized networks,
and the module is already hardened (its comments record a flood-amplification
finding and the clamps that fixed it).

The one thing worth writing down: **flooding costs scale with network size, and
our packets already carry the fix.** Each mesh message has a `path` field —
the node addresses it has traversed. So a node that relays a message already
knows a working route back to the origin, for free, without a protocol change.
If a base ever gets big enough that flooding hurts, opportunistic route learning
from `path` (try the learned next hop first, fall back to flooding) is available
without adopting anyone's routing protocol. Not now — recorded so it is not
re-derived under pressure.

---

## 22. A PROVENANCE LINT

**Source:** KittenOS NEO `compliance.lua`.

**Applies: small, and it fits an existing habit.** Theirs walks the repository
and prints "File wasn't accounted for" for anything not claimed by an author
manifest under `docs/repoauthors`. TOS already has the same *shape* for runtime
files — `test_manifest_completeness.lua` fails when a shipped file is missing
from `system_manifest.lua` — and an accidental-global lint besides.

The gap it would fill is licensing rather than packaging: TOS is GPL v3, vendors
an OpenOS tree under `Reference/`, and ships an Extras pack with separately
authored modules. A lint that every `.lua` under `tos/` and `TOS-Extras/modules/`
carries a license header, and that nothing under `Reference/` is reachable from
a release manifest, is cheap and protects the part of the project that is hard
to repair after the fact.

---

## Round 2 — also confirmed as NOT gaps

- **OCOS's semver package dependencies.** `pkg.lua` already accepts the table
  form `{ name = "tape-storage", version = ">=1.0", optional = false }` and has
  `compareVersion` (`pkg.lua:1072`, `:1157`).
- **OCOS's double-buffered compositor.** Same shadow-buffer idea we have; their
  README even names MineOS as the source.
- **Cynosure 2's pluggable binfmt** (`src/exec/{lua,cle,shebang}.lua`).
  Interesting, but TOS runs `.lua` and that is the whole population; a shebang
  handler buys nothing until there is a second interpreter.
- **Plan9k's full IPv4 + RIP + DHCP stack.** See item 21 — the wrong trade for
  OC, deliberately.
- **ULOS 2's LuaPosix compatibility push.** Their compatibility target is
  *nix programs; ours is OpenOS programs, which is the population that actually
  exists in this ecosystem (item 14 measures it).

---

## Sources

Clones read for this survey (shallow, in scratch):

| Project | URL | Files read |
|---|---|---|
| Fuchas | https://github.com/zenith391/Fuchas | `Fuchas/Libraries/{driver,security,velx,ipc}.lua`, `Fuchas/{bootmgr,permissions.lon}`, `dualboot_init.lua`, `Fuchas/Filesystems/{README.md,nitrofs.lua}`, `README.md` |
| Plan9k | https://github.com/OpenPrograms/Plan9k | `pipes/{06_cowfs,19_cgroups,17_ipc}.lua`, `plan9k-containers/sandbox.lua`, `openloader-init/init.lua`, file inventory |
| PsychOS 2 | https://git.shadowkat.net/izaya/OC-PsychOS2 | `README.md`, `build.sh`, `preproc.lua`, `kcfg/base.cfg`, `lib/{pkgfs,pkgman}.lua` |
| MineOS | https://github.com/IgorTimofeev/MineOS | `README.md`, `EFI/{Full,Minified}.lua`, `Localizations/English.lang` |
| Zorya NEO | https://github.com/lunaboards-dev/Zorya-NEO | `README.md`, `docs/Developing.md`, `mods/loader_openos/init.lua`, module/library inventory |
| GERT | https://github.com/GlobalEmpire/GERT | `README.md`, `Reserved OC network card ports.txt` |
| Minitel | https://github.com/ShadowKatStudios/OC-Minitel | protocol overview |

Added in round 2:

| Project | URL | Files read |
|---|---|---|
| OpenComputers (upstream OpenOS) | https://github.com/MightyPirates/OpenComputers | sparse clone of `…/loot`; full `diff -rq` against `Reference/OpenOS` |
| OCOS | https://github.com/AlexMelanFromRingo/OCOS | `README.md`, `src/sys/k/cap.lua`, `src/sys/k/exec.lua`, `src/etc/services/*.cfg`, `efi/ocos.efi*.lua`, `tools/test-boot.sh` |
| Cynosure 2 | https://github.com/oc-ulos/oc-cynosure-2 | `README.md`, `src/disciplines/*`, `src/exec/*`, tree inventory |
| ULOS 2 | https://github.com/oc-ulos/ulos-2 | `README.md`, component inventory (`upt`, `mtarldr`, `cldr`, `reknit`, `vbls`) |
| KittenOS NEO | https://github.com/20kdc/OC-KittenOS | `compliance.lua`, `claw/C2-Format.md` |
| GEBL | https://github.com/TeamCM/GEBL | `README.md` |
| Community corpus | OpenPrograms: `Vexatos-Programs`, `Magik6k-Programs`, `Gopher-Programs` | 60 `.lua` files, scanned for `require()` names |

The two compat measurements in item 14 came from scripted scans
(`compat_scan2.py`, `compat_scan3.py` in scratch); the method is described in
that item so the numbers can be reproduced or disputed.

Referenced specs: OEFI (Zorya `util_oefiv1`/`v2`), VELX v1 and OSDI 1.0
(Adorable-Catgirl/Random-OC-Docs), OCGPT (https://ocfs.github.io/ocgpt/), OETF
#6 (GERT) and #18 (IPC), and the reserved-port list now kept in
GlobalEmpire/OC-Programs.
