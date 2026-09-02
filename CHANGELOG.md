# TOS Changelog

All notable changes to TOS are recorded here. Versions follow a loose
SemVer: MAJOR.MINOR.PATCH. Codenames are tracked in `Codenames.txt`.

---

## Unreleased — the OS that fits in the machine you have

### A disk-free install path, and the assumption it exposed in the old one

`bootstrap.lua` is a new root-level script for a bare OpenOS machine that
has an Internet Card but no TOS files and no physical install disk at
all. It fetches the release file set (bios.lua, install.lua, and every
file `/tos/system_manifest.lua` declares) from GitHub over
`raw.githubusercontent.com` into a scratch directory, then hands off to
that downloaded `install.lua` exactly as if it were a mounted floppy —
FORCE-WIPE confirmation, BIOS fingerprint check, and post-copy size
verification all run unchanged, because it IS the same installer. It
talks to `component.internet` directly rather than through OpenOS's own
`internet` library, the same low-level approach `kernel.internet` uses
once TOS is installed, so a damaged OpenOS `internet.lua` can't take the
bootstrap path down with it. It also doesn't assume the repo's default
branch (`main` vs. `master`) or layout (bare root vs. a `TOS-Release`
subdirectory) — it probes both before giving up, and a fork or
nonstandard layout can be pointed at directly with CLI args.

Building the handoff surfaced a real assumption in `install.lua` itself:
its disk auto-detection required the source to be mounted literally at
`/mnt/<name>` (`scriptPath:match("^(/mnt/[^/]+)")`), which a
network-staged directory under `/tmp` was never going to satisfy. That
check is now a plain "does the directory this script lives in contain
`tos/kernel/init.lua`" test, with no path prefix assumed — and a
scripted or chain-loaded install (bootstrap.lua included) can skip
detection entirely by naming its source directory as `install.lua`'s
first argument. The other filesystem-scanning method in the same
function also picked up pcall guards around each component probe, so
one disk that throws on `exists()` (e.g. ejected mid-scan) can no longer
abort detection for every other disk on the machine.

### The self-test battery reported its own shutdown as unsafe

Nine on-box checks now (up from seven): `80-pkg-signing` audits real ed25519
and the real `/etc/pkg_trust.cfg` write path through securefs — tamper
detection with no override, trust add/remove, the require-signature gate —
and `90-internet-absence` proves the no-card path and the kill switch. Both
port items off the long-open "Emulator checklist" backlog in `TODO.txt` that
turned out to be provable on a single machine; the rest of that list (a real
printer, a live internet server, a second machine, or a human eyeball) is now
triaged and written down there so it stops being re-litigated every round.

Running the expanded battery for the first time surfaced a real bug, and not
in the new checks: `kernel.selftest`'s `shutdown=true` option called a raw
`computer.shutdown()`, which skips `kernel.shutdown`'s own last act — stamping
`/var/run/pwrstate` "C" for clean. Every armed round was powering the machine
off "successfully" and then reporting *that exact shutdown* as unsafe (warning
+ two beeps) on the next boot. A battery whose own exit path corrupts the
signal it exists to keep trustworthy is worse than one that doesn't shut down
at all. Fixed to prefer the real `kernel.shutdown` when it's reachable —
which, by construction, is always, except from the off-box harness that has
no kernel table, which is exactly when the raw fallback is what keeps this
testable without a full boot. Confirmed on real hardware: `pwrstate` reads
`C` again.

`sync-emulator.py` — the script that deploys a build and the checks into an
Ocelot workspace by finding the boot disk and the test floppy *by content* —
had no test coverage at all. It does now (`build/test_sync_emulator.py`,
19 cases), wired into `run_tests.py` rather than left for a bare `pytest` to
find on its own: pytest's own defaults silently skip any directory literally
named `build`, which is exactly where this file has to live.

### Two more places still said v1.3.2

The welcome tutorial's first page and a `bootsteps` test fixture were still
quoting the version two releases back (v1.3.2 "Argus"; the OS has been on
v1.4.0 "Iris" since its own release notes went in). The tutorial's line no
longer hardcodes a version at all — it reads `_G._TOS.version` like the
kernel's own boot-log line does, so this can't drift out from under it again.
The root `init.lua` bootstrap's decorative header comment was further behind
still (v1.2.6) and is not wired to anything at runtime; bumped by hand, the
same way `install.lua`'s own banner comment learned to stop doing after an
earlier two-place version drift (see the comment above `INSTALLER_VERSION`).

### screendump was reporting the cache, not the screen

Chasing a status bar that goes black after the menu bar closes, the obvious
move was to have the operator capture the screen. `screendump` exists for
exactly that — "capture this screen to a text file (for bug reports)". It read
the dirty-cell **shadow** whenever the shadow was enabled.

So the tool for diagnosing display faults reported the display cache's own
account of the screen. For the one class of bug TOS keeps having — the shadow
and the glass disagreeing — that is precisely the wrong witness: a row the
shadow believes is painted dumps as perfect, which is the exact case somebody
would be running `screendump` to investigate.

It also captured characters only. A fault that changes **colour and not text**
left no trace at all, and "the status bar went black" is that fault exactly:
same characters, wrong background.

`gpu.get` is the truth and is now used whenever it exists; the shadow is a
labelled fallback rather than the default; the capture says which surface
answered, because one that cannot say where it came from is the same trap in a
different hat; and the background colours come back run-length encoded, so a
correct full-width bar is one line and a broken one says which columns. The
file also records the theme's `bg`, `statusbar_bg` and `menubar_bg`, so a
reader can compare against what the row was supposed to be without guessing.

That costs one component call per cell — about 2,000 on an 80×25 screen, enough
to spend the per-tick call budget and make OpenComputers sleep. Acceptable for
a deliberate, rare diagnostic, but not while holding the machine: it yields
between rows, the way everything else long-running now does.

### SRM was the one long job that never yielded

Reported from a booted machine: `srm` freezes the computer for its whole run
rather than merely slowing it down, and the operator asked whether that was
just because it is the longest command or because it is an outlier. **It is the
outlier.**

SRM reads and hashes every file in the manifest — the longest job in the OS by
a wide margin — and it was the only long job with no cooperative yield in it.
Ten other modules have one: `compress`, `pkg`, `fs`, `ed25519`, the executor's
output chokepoint, and the walk loops in the command files. So `srm scan` did
not run slowly, it stopped everything: no other seat drew, no timer fired.

On OpenComputers that is worse than a freeze. The machine kills a computer that
goes too long without yielding, and TOS's own preemption cannot save it —
`debug.sethook` is not in the OC sandbox. A large enough manifest takes the
whole computer down, and the breadcrumb that would name the culprit is itself
written from inside the hook that never runs.

All five per-file walks now open with the same slice the rest of the OS uses.
It goes **between** whole files, never inside one: `readHashed` reads and
hashes in a single resume, and yielding in the middle of that would let the
hash describe a file that changed underneath it — the test asserts on that
function's body, not on a call trace.

### `help` advertised two commands that no longer exist

`swap` was folded into `optimize swap` in v1.4.0 and `device` into `hostname`,
and the hand-written reference table in `core.lua` kept listing both. Typing
either answered "unknown command", which reads as a broken install. (The boot
settings menu's swap entry is *not* wrong — `swap` is a boot feature name there,
which is a different thing from a command, and the operator's own guess about
that was right.)

`test_command_registry.lua` already checked command → help line. This is the
other direction, and it is the one that rots: the registry entry goes and the
prose stays. It has now happened three times — `ver` was the first, and was
fixed by restoring the alias. The audit walks the reference table, takes the
first token of each row, and requires it to dispatch; two syntax examples
(`cmd1 | cmd2`, `cmd > file`) are listed as the only exceptions.

Getting the audit's boundaries right mattered more than the audit: a first
version cut the table at a marker that does not exist, ran to end-of-file, and
started reading `man` and `keys` prose as command rows. It now ends at the
table's own closing line and rejects any first token followed by punctuation —
which is what separates a row from `fields: ...` or `e.g. ...`.

### Five ways to log out, one of which dropped your elevation

Found by pulling on an operator's observation: the menu bar's Reboot and Shut
Down keep working when `core` will not load. They do — and correctly. Those
menu actions call `helpers.canPowerOff` and then the kernel directly, never
touching the command table, which is exactly why they survived a low-memory
box and let the operator shut down cleanly instead of cutting power and leaving
the dirty bit to cry wolf next boot.

Checking whether the two paths agreed turned up the one next door that doesn't.
`sudo -s` registers a *second*, elevated session and points the seat at it.
Dropping it means three things: restore the shell's token, restore the process
principal, and log the elevated session out. There were **five** logout paths —
the `logout` command, the System menu, the F10 power menu, the `^Q` prompt and
the Desktop — and only the command did any of it. Its own comment states the
rule: *"never carry elevation across logout."* The other four pushed
`tos_logout` straight out, and the kernel's handler retires
`sessionTokens[seat]`, which is the **original login token** — a different
object from the elevated one.

What that actually cost, stated precisely rather than inflated: the elevated
token is discarded with the shell state, so nobody can present it; there is no
session cap to exhaust; and nothing enumerates sessions to an operator. It
lingered as a phantom entry until `sweepSessions` retired it, within
`SESSION_TIMEOUT`.

It is fixed centrally anyway, for two reasons that outlive today's blast
radius. `sudoDrop` also restores the shell process's principal, and that stays
harmless only while every logout path also *kills* the process — the kernel's
handler does, but a future "switch user", or a CLI handoff that reused the
process, would not, and then the elevation rides across. And five copies of a
security rule is four chances to update it in the wrong number of places.

There is now one `helpers.logout(S)`: drop, then push, in that order — a drop
scheduled after the signal would be racing the process kill that follows it.
The Desktop keeps a single inline fallback for the case where `helpers` cannot
load, and that fallback drops the elevation itself; the test allows exactly that
one raw push and fails on any other. Requiring `helpers` at the top of
`desktop.lua` was the obvious move and the wrong one — it is lazily loaded and
would have dragged `computer` in behind it, which is precisely the wrong
direction on a box already short of memory. (`test_logout_elevation.lua`)

### You can always reboot

Reported from a real machine: on a box short of RAM the `core` command
category fails to load, and `help`, `reboot` and `shutdown` stop existing.

All three live in `core`, which is the largest command file in the tree — so on
a tight box it is precisely the one that fails, because reading it wants a large
contiguous buffer and a machine at ~56 KB free has not got one. The dispatcher
returned nil, and the operator was advised to free some memory and try again: by
closing tabs, or rebooting. Which is the command that had just failed.

**That is a trap, not a wording problem.** The advice was correct and impossible
to follow. An earlier pass had already improved the *message* — it used to say
"unknown command", which was worse, since it told the operator their OS had no
`reboot` — but the thing the message was about was still there.

The escape hatch must not need the thing that broke. `reboot`, `shutdown`,
`help` and `mem` are now served from the dispatcher itself, which is already
loaded by the time any of this can happen, and only when the real command is
missing — so a healthy box gets the full versions exactly as before and this
costs nothing. They are deliberately minimal: every line of them is a line that
has to work when nothing else does.

Three things that mattered in the details. The power gate is the *same* one the
real commands use (`helpers.canPowerOff`), with a bare tier check as a fallback
that needs no module load, and it fails **closed** — the rescue is not a way for
a guest to power off a machine other people are using. It prefers the kernel's
clean shutdown and only drops to the raw component call if the kernel handle has
gone, because an unclean restart costs a repair pass next boot, which beats a
machine that cannot be restarted at all. And `mem` is included because the free
figure is what decides between closing a tab and rebooting.

The OOM path already declined to cache the failure, which matters more now: a
box that recovers gets its real commands back without a restart. That is pinned
too — the rescue must hand back the ground it borrowed. (`test_lowmem_rescue.lua`)

### The splash measured the screen before the kernel changed it

Reported from a real Minecraft install rather than the emulator: on a splash
boot with a **Tier 3 GPU and a resized, multi-block screen**, the loading bar
and the wordmark are shoved to the right-hand edge and almost entirely cut off.

`/init.lua` reads the resolution once, immediately after `gpu.bind()` — and
`bind` leaves an OpenComputers screen at its **maximum**. The kernel then
applies the resolution policy from `kernel/screen.lua` (density-based, floored
at 80×25) part-way through `kernel.boot()`, *while the splash is live*, because
`bootProgress` is the callback driving the bar. Everything the splash draws
afterwards is still positioned for the width it measured at the start.

On a Tier 3 GPU over a multi-block screen that is a genuine reduction, 160×50
down to 80×25. Geometry centred for 160 puts the bar at column 60 spanning
60..101 — on a screen 80 wide. Which is the report, arithmetic-exact.

And it explains why the operator saw it *only* there. A Tier 2 GPU maxes at
80×25; a single Tier 3 screen block maxes at 50×16. In both cases the policy
asks for the resolution that is already set and nothing moves. It takes a big
screen **and** a Tier 3 GPU for the boot-time measurement and the applied
policy to disagree at all.

The bar's geometry now lives in `bootsteps.splashGeometry` — pure, so it can be
tested against every screen size — and `/init.lua` recomputes it instead of
measuring once. A `resync()` on each progress message re-reads the live
resolution and, when it has moved, rebuilds the **whole** composition rather
than just sliding the bar: the wordmark and status lines above were centred for
the old width too, and OpenComputers clears the screen on `setResolution`, so
there is nothing up there worth keeping. One `getResolution` per progress
message, a few dozen over a boot, splash-mode only.

Hoisting the `kernel.bootsteps` require above the new `geom()` was not
cosmetic: a local declared *below* a closure is not an upvalue of it but a nil
global read, and `geom` would have taken its fallback branch forever while
looking correct. That is the same failure this release has now found in five
other places, so `test_splash_resize.lua` asserts the ordering directly.

### Two budgets that OpenComputers never let us have

`debug.sethook` is how TOS enforces two limits: the scheduler's wall-clock
preemption budget in `kernel/process.lua`, and the remote-exec step budget —
plus the memory-pressure abort inside the same hook — in
`kernel/net/remote.lua`, wrapped around attacker-supplied Lua from a trusted
peer.

**OpenComputers does not export `debug.sethook`.** Its `machine.lua` builds the
sandbox's `debug` table out of exactly four entries — `getinfo`, `traceback`,
`getlocal`, `getupvalue` — and withholds `sethook` deliberately: the machine
uses its own hook to enforce the "too long without yielding" deadline, and
guest code able to call `sethook` could disarm it. That file ships inside the
Ocelot jar, so this is readable rather than inferred; and OpenOS, which is real
OC code, only ever calls `debug.traceback`, never `sethook`, anywhere.

So on every real machine `if debug and debug.sethook then` is false, no budget
is ever armed, and — the part that matters — **it happens silently**. The
source reads exactly as though the control were active. The comment in
`process.lua` went further and asserted the wall-clock fallback worked on OC.

What this costs, stated plainly rather than left to be rediscovered. A runaway
process or a runaway remote command is still stopped, but by OC's machine
watchdog, which kills **the whole computer** — precisely the blast radius the
preemption code was written to shrink, and on a multi-seat box it takes
everyone down. The `preemptCrumb` breadcrumb that would name the culprit after
such a reboot is itself only written from inside the hook, so it never gets
written either. For `rsh`, the memory-pressure abort is gone too; the
entry-time `MIN_FREE_MEM` check, `CMD_LIMIT`, `OUTPUT_LIMIT`, the TRUSTED
requirement and per-request challenge-response all still hold.

The missing hook cannot be fixed. The claim can. Both modules now expose an
honest probe — `proc.preemptionAvailable()` and `remote.stepBudgetAvailable()`
— so `doctor`, `ps` or any future caller can state the real position instead of
inheriting an assumption; `remote` logs once when it runs a command with no
budget; and the comments say what is true. The hook is still installed wherever
one exists, which is every off-box run, so the suite still exercises the
enforcement path. (`test_sethook_absent.lua`)

Whether `rsh` should *refuse* to run without a budget is an operator's call,
not a bug fix — it would disable the feature outright on the only platform TOS
ships for — so it is written up in `TODO.txt` with both sides rather than
decided here.

One more thing this exposes: the off-box suite runs on stock Lua 5.4, where
everything exists, so **this entire class of bug is invisible to it by
construction**. Same blind spot that hid `ustr` falling back to byte math.
`machine.lua`'s sandbox table is the authoritative list of what TOS actually
gets, and it is sitting in the emulator jar.

So that list is now a test. `test_oc_api_surface.lua` pins the sandbox surface
— `os` is four functions, `debug` is four, `coroutine` has no 5.4-only `close`
— and fails if any file in the manifest reaches for something outside it
without a stated reason. The only acceptable reason is that the call site
guards *and has a real fallback*: `redstone.pulse` uses `os.sleep` when it
exists and `computer.pullSignal` when it doesn't, which is fine; a guard with
no fallback is the bug, not the fix. It carries a self-check so it cannot pass
by having stopped matching, and the header says how to regenerate the list from
the jar rather than edit it to go green.

The rest of the non-UI sweep came back clean, which is worth recording too:
`ustr` survived 33,921 column-math property checks (fed a real `unicode` for the
first time — mixed ASCII, Cyrillic, box-drawing and double-width CJK), and
`serialize`, `fs.normalize`, `net.protocol` and `kernel.pipe` came through
15,000 round-trip and model-comparison checks without a violation, including
hostile input to every decoder.

### Off-box tests can look at the glass now

`70-screen-truth.lua` — the in-emulator check written after three display bugs
"resisted static reading" — opens by saying "no off-box test can see that
because off-box there is no glass". That was true when it was written, and it
is why the suite stayed green while the status bar went black a fifth time: the
existing backbuffer mocks *count calls*, and a call-count mock is perfectly
happy while the code blits the wrong pixels.

`usr/lib/tests/fixture_glass.lua` is glass. It models video-RAM pages, and
`allocateBuffer` hands back a **blank** one exactly as OpenComputers does —
which is the single detail the whole frame bug depended on. Two things fall out
of having it:

**`test_shell_glass.lua`** runs the real panels renderer across thirteen shell
states — tier 1 and 3, 40×12 up to 160×50, empty directories, over-long command
lines and paths, an elevated prompt, a scrolled list — and then *looks* at the
result. It asserts two properties, both of which have been broken before:
*coverage*, that a full redraw leaves no cell untouched (the file-list row that
stopped one column short read as a cursor "partly in one place and fully in the
other"); and *sufficiency*, that a partial redraw repaints everything that
changed. The measure needs no golden file — compare against what a full redraw
of the same state paints, and any difference is something the operator can see
that is no longer true.

That second property immediately found one. **Tab-completion left up to fifteen
rows of the previous command's output on screen.** The inline overlay
(`S.outLines`) is drawn *upward* from the output row, over the bottom of the
file list, so removing it means those list rows have to be repainted. The event
loop knew that and floored the draw to level 2 — but only on the path where the
browser moves. Tab-completion with an ambiguous prefix clears the overlay to
make room for its "N matches:" line and asked for level 1, which repaints four
rows and none of the ones the overlay covered. Measured at 1,119 stale cells for
a fifteen-line result. The rule now lives with the overlay rather than at each
site that clears it: whenever it was showing and is now gone, the draw is
floored, whoever cleared it and for whatever reason.

The fixture also carries a **`unicode` module**, and that matters more than it
sounds. `kernel.ustr` probes for OC's `unicode` and falls back to *byte* math
when it is absent — which is every off-box run. So off-box,
`ustr.width("F2 ▸ tiles")` answers 12 instead of 10, and every column
calculation touching a box-drawing glyph is over by the continuation bytes.
The first version of this test duly reported the path rail as two columns short;
it is not, in-world. It cuts both ways, and that is the real cost: until now a
genuine column-math bug in translated or glyph-bearing text was equally
invisible to the suite.

### Nobody was listening when the screen changed size

`d.w`/`d.h` — kernel.screen's idea of how big each seat is — were written in
exactly two places: `screen.init()`, and `screen.fitDisplay` when TOS itself
sets a resolution. Both are cases where TOS is the one doing the resizing.

OpenComputers resizes the glass on its own as well. Add or break a screen block
in-world and the GPU resolution is clamped to the new maximum, and OC announces
it with a `screen_resized` signal — which appeared nowhere in the TOS tree.

Everything downstream then describes a screen that is not there. The seat
proxy's `syncSize` compares against `d.w`/`d.h`, so with both stale it sees no
change and keeps a shadow indexed for the old width, eliding repaints of cells
that are no longer where it thinks they are. Worse, the panels layout counts
`SUM_ROW`, `OUT_ROW`, `CMD_ROW` and `STAT_ROW` back from `S.H` — so on a screen
that *shrank*, the status bar and the prompt are drawn past the bottom edge,
where the GPU clips them. That is a third way for the status bar to disappear,
and this one takes the command line with it.

OpenOS treats this as load-bearing: `lib/tty.lua` listens for the signal *and*
intercepts `gpu.setResolution`, with the comment "the gpu can change resolution
before we get a chance to call events and handle screen_resized".

`screen.onResized(addr, w, h)` re-reads the resolution from the GPU (preferring
its answer over the signal's numbers — the signal reports the *screen's* new
size, and the resolution is a separate thing OC may have clamped elsewhere),
and invalidates the seat caches when it actually moved. It is a plain function
rather than a listener registered inside `kernel/screen.lua`, because that
module deliberately requires only `component` and `computer`; the kernel wires
the signal to it at boot, and the shell relayouts off the same signal.
(`test_screen_resize.lua`)

### The black status bar and the second cursor were the same bug

Two symptoms the operator had reported separately, and neither was where it
looked. The status bar going black had already been chased and fixed four
times — `display.scrollUp` leaving the glass black, compat's `term.gpu()`
handing out the raw GPU, a `restoreRow` helper inside the self-test written to
*detect* this, `withContext` restoring a colour cache across the same GPU — and
it kept coming back, because every one of those was a way for the caches to go
wrong, and this is a way for them to be *right about the wrong surface*.

**A seat proxy keeps two things.** A dirty-cell shadow that says "this cell
already reads like that, skip the repaint" — and it describes *the glass*. And,
on an OC 1.7.5+ GPU with video RAM, an off-screen *page*: `drawMod.all` opens a
frame, every draw lands on the page, and one `bitblt` puts the finished picture
up without tearing.

Those are the same surface only for as long as nothing has been drawn since the
last blit. **In TOS, most drawing is not inside a frame.** `drawMod.all` is the
only thing that opens one. Every `applyDraw` level 1 and 2 — which is every
keystroke on the command line — the once-a-second status-bar tick, the
file-list fast path and every dialog paint straight to the glass.

So the elision inverts. The frame's redraw skips exactly those cells whose
*glass* content already matches, which means they are never written to the
*page*, and then the closing blit paints the page's stale version over them. On
a page that was just allocated, the page's version is blank black. `beginFrame`
said so in as many words — "the page holds the PREVIOUS frame's pixels, which
is exactly what the shadow says the screen holds" — and that was an assumption,
not an invariant, wrong once because OpenComputers hands back a *blank* page
from `allocateBuffer`, and wrong again for every cell painted between frames.

That is both bugs:

- **The status bar** is the most exposed thing on the screen, because it is the
  one element repainted on a *timer*, outside any frame. By the time a frame
  opens it is always "already correct", so it is always elided, so the blit
  always reverts it — to background black. And it never heals, because the
  shadow goes on insisting the row is painted, so the 1 Hz repaint that would
  fix it is skipped as redundant, every second, forever.
- **The cursor** duplicates because the page still holds the inverse-video
  block from where the cursor *used to be* when the last frame closed, while
  the live one is drawn where it is now. The stale one never moves again — an
  inert cursor, exactly as described.

The fix is one line of intent: **seed the page from the glass before drawing
into it**, so the invariant `beginFrame` assumed is one it establishes. It
costs a single `bitblt`, and only when something has actually drawn outside a
frame — `claimGlass`, the chokepoint every `set`/`fill`/`clear` already goes
through, sets the flag, so a drawing method added later cannot forget to. Set
against the forty-odd `gpu.set` calls a full redraw makes, it is not a cost
worth optimising away.

Worth noting what did *not* find this. The existing backbuffer tests pass
against the broken code, because they count `bitblt` calls: the blit happened,
in the right order, the right number of times. It was simply blitting the wrong
pixels, and a call-count mock has nothing to say about pixels. The new
`test_screen_frame.lua` models a GPU with **real pages** — `allocateBuffer`
returns a blank one, `set`/`fill` write into whichever page is active, `bitblt`
copies — and then reads the glass back and counts the cursors on the row. It
fails on the unfixed build with `expected 0x0000AA, got 0x000000` and
`expected 1 cursor, got 2`, which is the operator's bug report in two
assertions. `test_screen_shadow.lua` gained the matching call-pattern
assertions, including that an unchanged page is *not* re-seeded.

### Nine bugs that read perfectly and did nothing

A pass through the tree looking for defects rather than features. What it
turned up was not a scattering of unrelated mistakes: seven of the nine share
one shape, and it is a shape that survives review.

**A name that is nil at run time looks exactly like one that isn't.** Lua
resolves an undeclared name against `_ENV`, so a missing `local` — or a name
that is a *parameter of one function* used inside *another* — compiles, reads
correctly, and evaluates to nil. Three lived here:

- **`sudo <cmd>` crashed while reporting a crash.** `sudoRunElevated` wraps the
  elevated command in a `pcall` so a command that throws can never leave a
  shell sitting at root — the restore runs on every path, then the error is
  printed. The printing half had never worked: `o`, the output function, is a
  parameter of each *command body*, and the helper never took it, so the one
  line that tells an operator what went wrong was itself an "attempt to call a
  nil value".
- **The out-of-memory message never said how much memory was free.**
  `panels/commands.lua` guarded the figure behind `if computer and ...`, in a
  file that requires nothing at all. The guard was always false, so the one
  number that tells you how much you need to free was silently absent from
  every OOM message.
- **Three kernel module inits were handed `serialize = serialize`** with no
  such local in `kernel/init.lua`. Harmless, because `profile`, `i18n` and
  `net.aliases` each fall back to requiring it themselves — but the dependency
  wiring was stating something untrue.

Note how the last two failed: a guard and a fallback each turned "this name is
nil" into "this feature is quietly absent". Nothing errored, nothing logged,
and there was nothing to notice. That is why
**`usr/lib/tests/test_global_leaks.lua`** now exists. Nothing in the source can
distinguish the two cases, so the lint asks `luac` what each chunk actually
reaches for through `_ENV`, across every file `/tos/system_manifest.lua`
declares, and demands a stated reason for each exception (the boot files really
do run under the OC BIOS environment; `net/remote.lua` really does want
`table.unpack or unpack`). It carries a self-check so it cannot pass by having
stopped working.

**The OpenOS compatibility tables were being built by undefined behaviour.**
`sides`, `colors` and `keyboard.keys` are all two-way — a name maps to a
number and the number maps back — and all three built the reverse half by
adding keys to the table *while walking it with `pairs`*. Lua's manual is
explicit that you may clear or modify existing fields during a traversal but
not add new ones, and this did not stay theoretical: the rehash triggered by
the first insert made `next` skip entries, so a random subset of the reverse
map was never written. Measured on the shipped files, `colors` lost anywhere
from 0 to 13 of its 16 entries and `keyboard` kept only 32 to 75 of ~99 — **a
different set on every boot**, because Lua seeds string hashing per process.
`sides` was worse again: every face there has two names, so even a walk that
happened to finish picked the winner by hash order, and `sides[0]` came back
`"bottom"` one boot and `"down"` the next. OpenOS's own `lib/colors.lua`
snapshots the keys into a second array before writing, and its `lib/sides.lua`
spells the canonical reverse names out literally; TOS now does both.

**`event.listen` refused the second signal.** OpenOS identifies a listener by
the *pair* (name, callback) — `full_event.lua` matches on both in `listen` and
in `ignore`. The shim keyed its map on the callback alone, one signal deep, so
the ordinary case of one handler serving several signals broke two ways at
once: `listen("touch", f)` then `listen("drag", f)` saw `f` already present and
returned false without registering, and `ignore("touch", f)` removed whichever
single signal `f` happened to be mapped to.

**`battery` answered "nil".** `kernel.power` loads on every machine — that is
the point of it — but `statusString()` returns nil off a battery, deliberately,
so a status bar has nothing to draw. `shell/ext.lua` handed that straight to
the output function, which `tostring`s whatever it is given. On any ordinary
computer, which is most of them, the answer to `battery` was the word "nil".
`kernel/diag.lua` had branched on the nil all along; only the command didn't.

**A truncated archive raised instead of answering.** `compress.unpack`'s
contract is `(data)` or `(nil, err)`, and `decompress` calls it unprotected and
prints the error. `isPacked` accepts a container from 9 bytes up — enough for a
*stored* header — but a *compressed* one needs 11 before the chunk count can be
read, so a container truncated to 9 or 10 reached the `u16` read with nothing
there and threw a bitwise-operation-on-nil out of a function that is supposed
to hand back a message. Every longer truncation was already caught inside the
chunk loop; only the header itself went unchecked.

Two more in the add-ons: **Tetris ignored `^Q`**, because the game loop
destructured the key *char* into a discarded `_` and then passed a nil global
to its quit check — leaving only the F10 and Esc scancodes working, and leaving
an operator who rebound quit to another `^`key with no exit at all. And
**`rbmk-controld`'s `_lastLevel` was a leaked global**, the one piece of
reactor state that escaped the module, and the piece the
warn-once-per-transition rule depends on.

Every one of the nine has a regression test that was run against the broken
code first and watched to fail: `test_sudo_report.lua`,
`test_compat_tables.lua`, `test_compat_event.lua`, `test_ext_battery.lua`,
`test_global_leaks.lua`, plus new sections in `test_compress.lua`,
`test_tetris_sandbox.lua` and `test_rbmk.lua`. The compat-table test carries a
source lint as well as value assertions, because the values alone would have
passed on a lucky boot.

Two findings are recorded in `TODO.txt` rather than fixed. `gmatch`'s
empty-match rule differs between the Lua 5.3 and 5.4 architectures TOS
supports, which would make ~15 line-splitting call sites emit a stray blank
line on a 5.3 CPU — but only 5.4 is installed on the dev box and 5.4 masks the
behaviour completely, so there is no way to see the bug or prove a fix from
here, and fifteen edits on a recollection is not a fix. The other is a
mutation-during-iteration in `kernel/event.lua`'s timer loop that looked
survivable in every case traced by hand — which is exactly what the `pairs`
bug above also looked like, so it is written down instead of waved off.

### Select text and copy it — and one clipboard for everything that holds text

TOS could not copy a line of a command's output. It could not select anything.
The editor had a private clipboard of whole LINES that nothing else could
reach, and the command line had none at all — which mattered more the moment
the prompt became resident on every Home surface.

**Shift and the arrows select.** At the prompt, in the editor, and a line at a
time in a view buffer, which is where a command's output lands. With the
optional mouse driver, click and drag does the same. An unshifted arrow always
drops the selection, in all three places, so a selection can never outlive what
the operator can see. Typing, Backspace and Delete replace it, the way every
editor has behaved for thirty years.

**Copy is `Ctrl+Insert` and it had to be.** `kernel/init.lua` consumes char 3
to interrupt the foreground process and then blanks the signal, so `^C` never
reaches a program at all — which means the editor's `Ctrl+C = copy line`, help
text and all, had never fired once since the day it was written. It is deleted
rather than fixed. DOS and Norton Commander put copy on `Ctrl+Insert` for
exactly this reason a decade before `^C`/`^X`/`^V` existed, and TOS looks like
Norton Commander on purpose. `^X` and `^V` are free and work as second
bindings; `keys set copy ^C` is refused with the reason, which `keys.isReserved`
could already say and now gets asked.

**All three are `keys.lua` actions**, so they layer through `/etc/keys.cfg` and
`~/.keys.cfg` like everything else, and every help screen that names them —
`keyhelp`, `help`, the editor's own help topic — reads the live binding instead
of spelling a key. That is how the `Ctrl+C` line managed to lie for a year.

Supporting that meant teaching `keys.lua` about modifiers, because
`Shift+Delete` and `Delete` are the *same scancode with no character*: OC
cannot tell them apart in a `key_down`, so a matcher now carries its modifier
requirement and `keys.is` is handed the live state. That state is tracked from
the `key_up`/`key_down` of the modifier keys themselves — and it **expires**,
which is the Esc problem wearing a different hat: hold Shift, press Esc to
close the screen GUI, release Shift somewhere else, and the `key_up` never
arrives. Without a timeout that wedges every arrow key into extending a
selection until the operator logs back in.

**`kernel/clipboard.lua` is the store**, and it is deliberately small:

- **One clipboard.** Copy in the editor, paste at the prompt. Copy a run of
  `pkg list` output, paste it into a file.
- **Per seat.** A multi-seat rig is several people at several screens, and one
  global clipboard would let them read each other's copies by accident.
- **Cleared at logout**, because a seat is a physical screen the next person
  walks up to and what was copied is sometimes a password on its way to a
  prompt. The `cli` handoff is not a logout and keeps it.
- **Not reachable from sandboxed package code.** `shell.keys` is allowlisted
  because a keybind table carries no authority; a clipboard carries whatever
  was last copied, and a background package that could poll it would be a
  keylogger with extra steps.
- **Bounded** at 512 lines / 16 KB, and it says when the cap bit rather than
  quietly holding less than was copied.

Pasting multi-line text into the one-line prompt joins it with **spaces** and
says so. The old OC-clipboard handler stripped newlines instead, which glued
two lines reading `ls` and `cd /` into `lscd /` — a command nobody typed and
one they might well have run.

Two smaller things fell out of it. With nothing selected, copy and cut still
take the whole line, so the editor's old muscle memory survives the change.
And at the prompt with nothing selected *and* nothing typed, copy takes the
path of the file under the cursor — the short answer to "how do I get this path
onto the command line", and the only thing that key could plausibly have meant
there.

`F5`/`F6` in the file list remain a separate FILE clipboard. Two verbs sharing
an English word; the help text now says which is which, because one "paste"
that means two things depending on invisible state is worse than two names.

### One home, two views — F2 stops switching tabs and starts switching views

The Desktop and the Shell were two tabs, and F2 cycled between them. That made
the most basic question about this machine — *where is my prompt?* — have two
answers, and gave F2 a meaning that depended on which tabs happened to be open.
Both are now two **views** of one tab called **Home**, and F2 flips the view.

Grounded in a drawn mockup of every screen (composed from the real draw code,
not from screenshots) rather than described in prose, which is how several of
the details below got settled before any of it was written.

**The bottom four rows never move.** Summary rail, output row, command prompt,
status bar: identical in both views, at the rows `recomputeLayout` has always
put them. Press F2 and only the middle of the screen changes. That is the whole
argument for merging rather than re-skinning — the prompt is never somewhere
else, and a command's short result lands inline above the summary rail exactly
where the last one did, without the tiles moving under your hand. Tiles get
rows 4–21 (three rows of five, 15 to a page on an 80×25 screen); files get the
same 19 rows the browser had.

**F2 is the `view` action in `shell/keys.lua`, not a panels scancode.** That
file landed one commit earlier with five actions and the argument that a
shortcut you have to remember per program is not a shortcut, it is trivia;
`view` is the sixth. It inherits `/etc/keys.cfg` and `~/.keys.cfg` layering, so
it is operator-rebindable from day one, and every legend that names it —
the rail's `┤ F2 ▸ tiles ├`, the F-key row, the tile hint, `keyhelp`, the `help`
screens, the background-task message — asks `keys.label("view")` instead of
spelling F2. Rebind it and the screen re-labels itself.

**Everything printable belongs to the prompt**, which is what a CLI-first
machine owes you, and it is what moved two other bindings:

- **Quick-launch is `Alt+1-9`.** A bare `1` types a `1`. OC sends a bare digit
  with both its character and its scancode and suppresses the character when a
  modifier is held, which is the whole discriminator.
- **History is `^P` / `^N`.** It used to be Up/Down *while the line was not
  empty* — one key meaning two things, with invisible state deciding which.
  The arrows now drive the selection in whichever view is up, always. There is
  no focus mode to learn because the prompt never competes for them.
- **Tab moves between tabs when the line is empty**, and completes when there
  is something to complete. F2 had that job and the merge took it; the split is
  unambiguous because completion needs a word to work on.

**Pagination, made visible.** `ui.tileGrid` always computed `perPage` and
nothing ever said so, which meant a tile on page 2 existed with nothing on
screen admitting it. A band rail above the grid now reads
`‹ page 1/2 › · 27 tiles · 15 shown · PgDn next page`; PgUp/PgDn page, and with
the mouse add-on the `‹ ›` markers are click targets, as is the F2 legend
itself. The T1 numbered list pages the same way.

**No Files tile.** F2 is the way to the file list and the legend two rows under
the grid says so; a tile restating a visible key is a tile slot spent on
nothing. The split-mode Desktop keeps its Files tile, because there it really
is how you get back.

**The file keys are only live over files.** F3, F5, F6, F7 and F8 act on the
file list, so they do nothing in the tiles view. Leaving F8 armed over a tile
grid would let an operator delete a file they cannot see.

**`landing` picks a view, not a surface.** The per-user profile field kept its
stored values (`desktop` == `tiles`, `shell` == `files`) so nothing needs
migrating, and now accepts the new spellings too. Unset, root lands on files
and everyone else on tiles. Settings → Desktop is Settings → Home.

**The escape hatch is a boot setting, not a fork.** Boot Settings → Interface
gains `split` beside `home` and `cli`: two tabs, F2 cycling, exactly as before.
It exists because a rearrangement this large should not be a one-way door, and
`test_home_view.lua` pins both shapes so neither can rot unnoticed.

**Also fixed: two white-on-white collisions on T1.** Found while composing the
mockup against the real theme tables rather than in use. `display.lua`'s T1
block sets `dim = 0xFFFFFF` while `menubar_bg` and `statusbar_bg` are also
white, so every inactive menu label and both `▓▒░` ramp caps were drawn white
on white and simply vanished. The draw sites now fall back to the bar's own
foreground whenever `dim` collides with the bar's background — theme-general,
so a future preset that picks the same two colours cannot bring it back.

### `tape decrypt` could not read what `tape encrypt` had just written — tape 2.2.1

Two defects in the `tape` module's vault path, found while mapping the tree.
Patch bump: no manifest, command or capability surface changed.

**The round trip was broken.** `kernel.vault` writes `TVAULT2` for every new
blob and still reads `TVAULT1` (#SEC CR-7). The tape module's format sniffer
only matched `TVAULT1`, so `tape encrypt` produced a tape that `tape decrypt`
then refused with "Tape is not encrypted (no TOS vault header)." The data was
never lost — the blob on the tape was fine — but the only command meant to get
it back declined to try. The file-based `tape vault` path never had this bug,
because it asks `vault.isEncrypted()`, which accepts both versions. The sniffer
now accepts both too.

**The reads were unbounded.** `readWholeTape()` pulled `getSize()` bytes into a
single Lua string, justified in-comment by "tapes typically hold a few hundred
KB at most". A stock Computronics tape is 4 MB. This is the same pattern as the
"Tape Menu OOMs" bug that `shell/launcher.lua`'s streamed reader was written to
fix, and `modules/tape-authenticator` already carries the note that the old
whole-image read "OOM'd even tier-3.5 RAM" — the tape module simply never got
the same treatment. Both call sites now read only what they need: encrypt asks
`scanArchive()` how long the archive actually is (it already walks the entries
structurally) and reads exactly that; decrypt reads the 114-byte vault header,
takes the declared `ctLen`, and reads exactly the blob. The cartridge padding
past the data is never pulled into RAM, which also removes the old
strip-the-trailing-zeros step that existed to undo the over-read.

Because the module legitimately handles multi-MB archives, the new guard is a
*memory* budget derived from `computer.freeMemory()` rather than a fixed cap
like launcher's 64 KiB menu limit — a small constant would be wrong here. When
a read won't fit, it declines with the two figures rather than dying partway.

New `modules/tape/test_tape_vault.lua`: 12 assertions covering both wire
versions, the bounded reads (asserted by counting bytes the fake drive hands
out), a corrupt `ctLen`, and the low-memory refusal.

### One set of shortcuts, and the operator owns them

Follow-on from the Esc round. Operator: *"^Q is the close combination, the ttt
game just uses Q to exit, which can be confusing for Operators who prefer one
standard."* Fair, and worth more than it sounds — a shortcut you have to remember
*per program* isn't a shortcut, it's trivia.

New `tos/shell/keys.lua`: one table, read by the shell, its dialogs, the picker,
and every bundled package. Five actions — `quit` (^Q, F10), `help` (F1), `save`
(^S), `find` (/), `refresh` (^R). Deliberately small: a "standard" that tries to
cover every key ends up describing none of them.

**Operators set their own.** `/etc/keys.cfg` (admin, machine-wide) then
`~/.keys.cfg` layered on top, driven by `keys list | set | reset`. Keys are
written the way a person says them — `^Q`, `Ctrl+S`, `F10`, `/` — because a
config nobody can read back is a config nobody will edit, which is how
"adjustable" becomes theoretical. A rebind **replaces** rather than adds, so
`keys set quit F4` can mean *only* F4.

`^B`, `^T` and `^C` are refused with a reason: the kernel consumes them before
any program sees them, so accepting a rebind would write a setting that silently
does nothing.

Packages reach it through `kernel.sandbox`'s allowlist. That widening is
deliberate — a keybind table only the base image could read would standardise
nothing — and safe: the module reads two config files and returns key matchers,
with no authority passing through it. Converted: `write`, `ttt`, `snake`,
`stock`, `tetris`, `calc`, `rc-pilot`, each degrading to its coded defaults if
the module is absent.

Plain **Q** still quits `ttt` and `snake`. Taking away muscle memory buys
nothing; what changed is which key they *advertise*, and their footers now read
the live binding rather than a baked string — so a footer can't name a key that
was rebound away. `test_keys.lua` pins the second half specifically, because it's
the one that rots quietly: a hard-coded scancode keeps working, and nothing fails
until an operator changes a key and finds one program ignoring them.

### Esc is Minecraft's key, not ours

Reported from real Minecraft: programs using **Esc** to exit are unexitable. Esc
belongs to the game — it closes the screen GUI, so the player steps away from the
terminal and the keypress never reaches the computer. The program is still
running when you open the screen again.

`write` shipped exactly that way: Esc was its only exit, and its footer
advertised it, so even the workaround was hidden. That's a bug I introduced two
rounds ago and no off-box test could have caught, because a test can't press a
key the game intercepts.

The convention is now written down in `tos/shell/panels/keymap.lua`, where
someone binding a quit key will read it on the way past:

| To do this | Press |
|---|---|
| Quit a full-screen program | **Q**, or **^Q** where Q would be typed |
| Cancel a prompt or dialog | **^Q** |
| Quit, anywhere | **F10** |

Esc is still *accepted* wherever it's harmless, in case a future OC build or an
emulator delivers it — but nothing requires it and no help text advertises it.
Swept across the tree: `write` (F10/^Q, and its interrupt path no longer
synthesises an Esc nothing would act on), `rc-pilot` (where plain Q is *turn
left*, so it had to be ^Q), the framed dialogs, the package picker's filter and
quit, the CLI's masked passphrase prompt, `stock`/`snake`/`ttt` (one line each —
their shared `keyName` helper now maps ^Q and F10 to the same "esc" every call
site already tested for), and the mouse demo.

`test_no_esc_exit.lua` pins both halves: no file may offer Esc as its only exit,
and no help text may tell an operator to press it.

### The menu bar is the operator's, not the code's

Also reported: the bar "hasn't been updated and should be Operator-adjustable,
not static as it currently is (or at least, looks)". Both halves were fair.

**Adjustable.** There was a per-user `~/.menu.cfg`, but it could only *append* —
no removing, renaming, reordering or replacing, and nothing machine-wide. Now
there are two layered configs (`/etc/menu.cfg`, admin, then `~/.menu.cfg`) and
the full verb set: `menu show | add | hide | rename | move | list | remove |
reset`, with `--system` on any of them to change the bar for everyone.

It's an **edit list, not a replacement bar**, and that's the important choice: a
saved copy of the whole bar goes stale the moment TOS gains a command — which is
precisely how the built-in set got a year out of date. Edits ride on top of
whatever the built-ins become.

A malformed config never costs you the bar. Bad entries are skipped individually,
and an edit list that removes *everything* falls back to the built-ins — the menu
bar is the surface you'd use to fix a broken menu bar, so it doesn't get to
break.

**Updated.** Tools gained Packages, Repair (SRM) and Diagnostics; System gained
CLI Mode; Settings gained Menu Bar, so the bar can be edited from the bar — an
adjustable thing whose adjustment is undiscoverable is still, to the operator,
static.

### Six bugs from the first real-Minecraft round

Not the emulator — actual OpenComputers, with actual hardware attached. Six bugs
in one sitting, none of which 141 off-box tests could see.

**The pattern is worth more than any single fix.** Not one of these was a hard
fault. Every one was a place where the code *guessed* at something it could have
*determined*, or kept a second copy of a fact that already existed correctly
somewhere else. Off-box tests can't find that class, because a mock encodes the
same assumption the code does. Real hardware just does what it does.

**The Optional Utilities picker never saw the second floppy.** Split the set as
intended, insert disk 1, and the picker listed only what was in the drive — no
dimmed off-disk entries, no swap prompt, and no way to tell that wasn't the whole
catalogue.

`pkgpicker` enumerated mounts by *listing the mount directory*. Boot-time mounts
are virtual — `kernel/init.lua` calls `fs.mount()` without creating a directory —
so the listing came back empty, the set manifest was never found, and everything
downstream of it (off-disk entries, "Insert disk N", the undo flow) was dead
code.

The galling part: `pkg.lua` already knew. Its own `mountedRepoRoots` carries the
comment *"boot-time mounts are virtual and don't appear in fs.list"* and consults
the mount table first. The knowledge was written down, in this repository, next
to the correct code — and the picker had a second copy of the enumeration that
didn't have it. There is one now, exported as `pkg.repoRoots()`.

`test_installer.lua` didn't catch it because its filesystem mock returned the
disk from a `/mnt` listing — it mocked a filesystem that doesn't behave like the
real one. The mock now reproduces the virtual mount, and `test_pkg_repo_roots.lua`
asserts the rule directly; its *first* assertion is that listing `/mnt` finds
nothing, which is the precondition the old code assumed away.

**"RAM 4K" on a machine with megabytes**, three lines above `Free memory:
1300KB` in the same boot log. `hal.ramSticks` decided whether `getDeviceInfo`'s
capacity was bytes or kilobytes with `if cap >= 4096 then cap = cap / 1024`, and a
capacity arriving as exactly 4096 lands on the wrong side of that. The
determination was available all along — the sticks have to add up to
`computer.totalMemory()`. Both readings are now tried and whichever reconciles
wins; a set that reconciles with neither returns nothing rather than a number we
can't justify, and the summary falls back to the machine's real total.

**Peripheral capabilities never reached package code.** `printer` reported
"peripheral.printer cap required" on a machine whose kernel log had recorded
`[hotplug] Added: openprinter` seconds earlier, with a manifest that plainly
declared the cap.

A manifest's capabilities reached the *sandbox*, where they filter
`component.proxy`, and stopped there. The kernel's peripheral modules gate on
`kernel.process.current().caps` — a **different** set, belonging to the running
process. A package command runs inside the shell's process, whose caps are a
fixed list in `kernel/init.lua` that contained no peripheral entry at all. The
gate could never open.

Once traced, the scope was wider than the printer: `stock` could never have read
a chest, and `redstone` / `robot` / `inventory` typed at a shell could never have
worked either. All three were marked `[?]` — code done, never run against real
hardware. That mark earned its keep.

The fix has two halves and the second one matters. `kernel.pkg` now wraps every
package command in a **cap scope**: the process wears the manifest's caps for
exactly the duration of the call, and its own again afterwards — restored on
error too. And `shellCaps` gained the peripheral entries so first-party
`redstone`/`robot`/`inventory` work, which is safe precisely *because* of the
scope: package code never sees the shell's set, since the scope replaces it
wholesale and a package gets strictly less than the shell for anything it did not
declare.

Why no test caught it: every off-box test **stubs the sandbox**, so the sandbox's
cap set was the only one they had ever looked at. `test_pkg_capscope.lua` looks at
the *process*, and asserts both directions — the declared cap arrives, the
shell's undeclared ones do not, and a crashing command still gives the caps back.

**A command that would not load read as "Unknown command".** At 56 KB free,
`reboot` — a perfectly real core command — could not be loaded, so the dispatcher
returned nil and the executor called it unknown. The operator was told their OS
has no `reboot`. `commands.lua` had already put the real reason in `S.lastOut`;
the executor then overwrote it. It now asks the registry whether the name is real
before blaming it, and prints the load failure instead.

This is the exact failure the CLI round predicted in its own emulator checklist —
predicted, written down, and shipped anyway, because nothing tested it.

**A read-only boot disk, discovered at the password prompt.** First Boot Setup
failed with `Persist failed: read-only filesystem`. Nothing anywhere checked
`isReadOnly`, and TOS writes `/etc/users.dat` before an operator has finished
typing their first password — so the first symptom of a read-only root was a
failure in the middle of setup that named neither the disk nor the actual cause.
Now: checked at boot and announced once with the disk address; the boot-device
scans prefer a writable filesystem and fall back to any; `df` and `doctor` report
it; and First Boot Setup names the remedy instead of looping a prompt forever on
an error that retrying cannot fix.

**Dialog text clipped at the screen edge, not the box edge.** That error ran out
through the First Boot box's border and was cut at "cannot open for wr", losing
the half that said what to do. Messages now wrap to the box's inner width.

### The CLI is now as capable as the TUI — and cheaper to start

TOS had two shells with two command tables. The panels TUI dispatched through a
registry of **124** commands; the CLI in `shell/init.lua` was ~1,150 lines of
separately hand-written verbs and had **85**. So 45 things you could do in the
full interface simply did not exist at the prompt — `srm`, `sudo`, `watch`,
`which`, `why`, `theme`, `net`, `notify`, `crash`, `tail`, and the rest.

The gap was the symptom. The cause was the second command table, and closing the
gap by hand-writing 45 more entries would have re-armed it from the next commit
onward. So the CLI now dispatches through **the same registry**, in a new
`shell/cli.lua`; `shell/init.lua` shrank from 1,280 lines to a ~120-line launcher
that picks an interface and lets the two hand off to each other.

Everything that came with the registry came along with it: pipes, redirects,
quote-aware tokenisation, tier gates, `sudo`, and commands provided by installed
packages. None of those were CLI features anyone had to write — they were
*executor* features the CLI could not reach.

**The laziness is not a consolation prize, it is the other half of the point.**
The registry loads its category files on first touch, so a session that only
types `ls` and `cat` never parses the admin or extras command files. The CLI is
what a seat falls back to when the TUI won't load and what `ui=cli` boots into —
paying for the whole registry up front is exactly what it must not do. It came
out both fully capable *and* lighter to start than the copy it replaced.

**Reaching it**, since one way was not enough:

- `cli` from any prompt, `tui` to come back. Both are tier 0 — which interface
  you use is not a privilege, and the CLI is specifically what you want available
  when the full one is misbehaving.
- The quit menu's fourth entry, relabelled from `[4] Shell` to `[4] CLI Mode`.
  "Shell" said nothing: all four of those choices leave the shell you are in.
  It is drawn from two files (`^Q` in events.lua, the menu action in menus.lua)
  and a test now pins them to the same string — two spellings of the same four
  choices is how an operator learns to distrust both.
- Boot Settings → Interface → `cli`, as before.

**What the CLI still cannot do**, said plainly rather than papered over: the
tabbed viewer/editor, the Desktop, and live-refreshing tabs *are* the panels
interface rather than commands. Ask for one and it says so and names the
alternative (`watch` for live refresh, `tui` then `edit` for the editor). Those
are UI facts, not missing commands.

Two supporting changes worth knowing about:

- `makeProgramEnv` moved out of `panels/init.lua` into `shell/progenv.lua`. Both
  shells hand it to every program they run, and a second sandbox-environment
  builder is the last thing this codebase should have — it is a security surface,
  and two copies drift.
- The executor takes an optional `deps.showOutput`. The TUI routes output between
  a status row, an inline region and a view tab; a teletype has one surface. That
  also let the editor become a lazy require inside the executor, so a shell that
  never opens a tab no longer drags in the tab/editor tree.

`test_cli_parity.lua` asserts the parity **from the registry** rather than from a
list somebody has to maintain: every registered command must resolve through the
CLI's table, the CLI must supply every `deps.*` the category files reach for, and
core-only use must not load admin or extras. It also pins the layering — the
emergency terminal must keep depending on nothing the other two shells need,
because a fallback that shares its dependencies with the thing that broke is not
a fallback.

### Signed package manifests (Ed25519, RFC 8032)

The biggest real gap the package manager had. `pkg` has verified file hashes
for a long time, and hashes answer a different question than the one an
operator is actually asking: they prove the disk is not **corrupt**, never
that it is from **who it claims**, because whoever writes the files also
writes the digests. What was really holding the line was the admin gate, and
an admin gate is *per-disk* consent — the same judgement call again for every
floppy. A signature makes it *per-publisher*.

The chain is `signature → manifest → hashes → files`, and `pkg` runs both
gates: a signed manifest that declares no hashes is still unverified code,
because the signature vouches for a document that promises nothing about the
files.

**Four states, and none of them is silently another.** Three were in the
plan; the fourth is the one that matters and it wasn't named there:

- **trusted** — verified, and the key is in your store.
- **unknown** — verified, key not yet trusted. *Not* the same as unsigned:
  the bytes really are from the holder of that key, and one `pkg trust add`
  turns it into the first row.
- **unsigned** — no signature. Keeps working, because a floppy from a friend
  is the normal case and always will be. What changed is that TOS now *says*
  your admin privilege is what's authorising it, instead of leaving you to
  assume something stronger.
- **invalid** — a signature exists and does not verify. Hard refusal, **no
  override**, and specifically not degradable to "unsigned". If a broken
  signature read as an absent one, corrupting a signature would be a route
  onto the permissive path. `--force`, `--allow-unverified` and
  `--allow-unsigned` are all tested against it.

Two forgeries the design refuses by construction. A signature file may carry
a `signer` name — it is display-only, shown in quotes as the disk's own word,
and **never** matched against the trust store, so a floppy calling itself
"Strata Systems" is not trusted for saying so. And a manifest cannot declare
itself trusted: `_sigState`/`_sigKey`/`_sigLabel` are stripped from every
on-disk manifest form, the way `_srcBase` already was.

New commands: `pkg trust list|add|remove|require|key`, `pkg verify-sig <dir>`
(who signed this, *without* installing it), `pkg sign <dir>`, and signature +
integrity lines in `pkg info`. The trust store is `/etc/pkg_trust.cfg`,
admin-writable and decoded as data. `build-disk.lua --sign` signs a whole
disk — after hash injection, since the builder rewrites each manifest, and
with the passphrase taken from the environment rather than argv because argv
lands in shell history.

**The implementation notes worth keeping**, since nobody will re-derive them:

- Ed25519 needs SHA-512 and TOS had only SHA-256, so `kernel/sha512.lua` is
  new. Lua 5.3 makes it natural rather than painful — 64-bit integers that
  wrap and a logical `>>` mean the machine word *is* the algorithm's word,
  with none of sha256.lua's masking.
- The field arithmetic uses ref10's ten limbs at radix 2^25.5. The fractional
  radix is the whole trick: 255 divides evenly by 25.5, so a product spilling
  past the top limb wraps back multiplied by exactly 19. Any whole-number
  radix leaves the wrap misaligned and the fold factor grows big enough to
  overflow 64 bits.
- Multiplication is a plain double loop rather than ref10's unrolled 100-term
  expression. Same arithmetic, and the scaling rules derive in two lines — an
  unrolled expression with one transposed index is a bug that passes every
  test except the one you didn't think to write.
- `//` and not `>>` in the carry chain. Lua's right shift is *logical*, and
  these limbs are genuinely signed, so a negative limb shifted right becomes
  an enormous positive number. That single character is the easiest way to
  get an implementation that looks right and passes small tests.
- Constants (d, sqrt(−1), the base point) are computed at load rather than
  transcribed — a 78-digit decimal copied by hand is a class of bug avoided
  outright, at about a tenth of one verification's cost.
- Pinned to RFC 8032 §7.1, and not just `verify`: the **signatures must match
  byte for byte**, which is what proves the deterministic nonce derivation is
  right and what makes interop with any other Ed25519 tool a real claim
  rather than a hope.
- Measured: 0.05 s to verify and 0.02 s to sign on desktop Lua. On a real
  OpenComputers machine expect seconds, so the module is loaded lazily (a
  machine that never meets a signed package never loads it), yields
  cooperatively inside both the exponentiation ladder and the scalar
  multiplication, and callers cache the verdict rather than re-checking.
- Not constant time, said plainly in the header. Verification handles public
  data only; the adversary here is a floppy disk, not a stopwatch.
- A data card cannot accelerate any of it: its T3 ECC is a different curve
  and a different format (a manifest signed with it would verify only on
  another T3 box, the opposite of the point), and it hashes SHA-256/MD5 while
  Ed25519 needs SHA-512.

**Not done, deliberately:** no first-party publisher key exists, so the
shipped Optional Utilities disks are still unsigned. Generating a signing key
is the operator's act — a key committed to a repository is not a secret, and
a first-party key everyone holds is worse than none because it *looks* like
assurance.

Found along the way and left alone: `sha256.lua`'s `msg:byte(1, #msg)` idiom
stack-overflows past a few hundred thousand bytes. Nothing feeds it a file
today, so it is recorded rather than changed; `sha512.lua` indexes the padded
string in place instead.

### New add-ons: `printer` and `write` — TOS can put words on paper

Two packages and one small piece of base image. The driver is modelled on the
mouse driver's posture exactly: TOS has no baked-in printing, so this is the
DOS-style driver you install when the base actually has the hardware.

**`printer`** targets PC-Logix's **OpenPrinter** addon and its `openprinter`
component. (OpenComputers' own `printer3d` is a model printer and a different
device; it is untouched.) It ships two libraries, and the split is
load-bearing rather than tidiness: `/usr/lib/printerfmt.lua` is **pure** —
the character-width table transcribed from the mod, word wrapping, 20-line
pagination and ink/paper costing — so it unit-tests off-box and works on a
machine with no printer attached at all, which is how `printer preview` and
the word processor's page ruler exist. `/usr/lib/printer.lua` is the
hardware, the job builder and the capability check.

Three things it does that a thinner wrapper would not:

* **A job is built in memory, pre-flighted, then committed.** The printer's
  buffer is a real, shared, persistent thing, so writing straight into it
  means a job that fails halfway has already half-written someone else's
  page. `job:check()` compares the job's cost against the paper and ink
  actually loaded and refuses before a single sheet moves.
* **A failed commit reports how many pages already printed.** A five-page job
  that dies on page four has three pages in the output chest; reporting only
  "failed" has the operator reprint the lot.
* **Colour is opt-in per line.** OpenPrinter charges a unit of colour ink for
  every `writeln` that carries a colour argument, so a driver that defaulted
  to "black" as an explicit colour would drain a colour cartridge printing an
  all-black document. Costing counts the two cartridges separately and the
  operator sees both before confirming.

Every call is `pcall`-wrapped because the mod signals failure by *throwing*
("Please load Ink.", "To many lines.", "no empty output slot") — the driver
converts those to TOS's `nil, reason` convention and keeps the mod's own
sentence. Optional methods (`width`, `maxWidth`, `scanBook`) are
feature-detected, not version-guessed: the 1.7 builds lack some of them.

**`write`** is a word processor, and deliberately not a second text editor —
TOS has `edit`. The difference is the page: `write` knows how wide a printed
line is in pixels and how many fit on a sheet, so the rail shows which sheet
the cursor is on, how full it is, and what the whole document will cost,
live while you type. That is the one question an editor cannot answer.

The file stays **plain text**. Formatting rides on roff-style dot commands in
column one (`.title`, `.center`, `.color`, `.page`, `..` to escape a literal
dot), which keeps a document greppable, mailable, hand-editable and never
executable — the same argument `calc` makes for not building its formulas on
`load()`. A malformed directive is a warning in the status row and the line
is kept as text; a word processor that refuses to open a document over a typo
on line 40 has failed at its one job.

`write` **requires** `printer` — the only hard cross-Extras dependency in the
set, flagged in TOS-Extras/README.md. The page model lives in the driver, and
a `write` that shipped its own copy would be two definitions of "how tall is
a page" drifting apart. The printer *hardware* stays soft: composing,
pagination, the page view and saving all work with no printer in the world,
and the rail says whether the page breaks came from the attached printer's
own metrics or from the transcribed width table, because those are not
equally trustworthy and the operator should know which they are reading.

**Base image:** a new `peripheral.printer` capability gating the
`openprinter` component type. Gated rather than folded into blanket
`component` for the same reason `piston` and `robot` are: a printer actuates
the world and spends the player's paper and ink. Installing a game must not
also hand it your cartridges. `lsdev` grew a consumables column for the type,
because a printer with no paper is present, addressed and useless, and reads
identically to a working one otherwise.

One property worth stating plainly, since it is what makes the capability
real: a library under `/usr/lib` is resolved by the sandbox's user-lib path
and then loaded through the **real** `require`, so it runs with ambient
authority and the gated-component split does not cover it. The driver
therefore **re-checks `peripheral.printer` itself, on every call**, exactly
as `tos/peripheral/redstone.lua` does for `#SEC H34`. Without that, any
package holding `fs.read` could `require("printer")` and print.

### Package capabilities: overrides as data, defaults as code

`/etc/component_caps.cfg` (FEAT-5) let an operator name a modded component
type and the capability that gates it — but a *package's* declared caps were
filtered through a static allowlist in `pkg.lua`. So an operator who added
`reactor_control → peripheral.reactor` could grant that cap to a shell REPL
and never to a package: the manifest's request was dropped in silence, the
package ran with no hardware, and nothing said why. A capability you can add
to one side and not the other is a capability that does nothing.

New `/etc/pkg_caps.cfg`, admin-writable and decoded as data (never `load`ed):

```lua
{
  allow = { "peripheral.reactor" },   -- widen what a manifest MAY request
  deny  = { ["*"] = { "internet" },   -- narrow what is honoured, globally…
            someGame = { "net" } },   -- …or for one package
}
```

**There is deliberately no `grant`.** KittenOS can pre-answer a permission
prompt because it asks at first use; TOS accepts a manifest's declared set at
install time, and the manifest is the record of what the package touches.
Handing a package a facet it never declared would make `pkg info` lie about
it and defeat the consent the admin gate exists to collect. Operators can
widen what may be *requested* and narrow what is *honoured*; they cannot
request on a package's behalf. `allow` also cannot re-enable `legacy` — an
operator config must not be a route to raw `os`/`io`.

Fail-closed, and asymmetrically so: a config that will not read or decode
yields no `allow` entries *and* no `deny` entries. Losing the allow half is
safe (packages fall back to the coded default); losing the deny half is not,
so it logs at warn — an operator who wrote a veto needs to know it is not in
force. A refused capability is now logged with the facet named and the reason
given, instead of vanishing.

`component reload-caps` reloads both files, since they are two halves of one
answer, and says that packages already loaded this boot keep their old caps.

`TOS-Extras/build/test_manifests.lua` now asks `pkg.runCaps()` for the real
allowlist instead of mirroring it. The mirror had already drifted: it never
learned `internet`, granted since the internet-card round, so a correct
manifest declaring it would have failed the lint.

### The Optional Utilities packer balances the floppies

First-fit-decreasing minimises the disk *count* and is miserable to live
with: it had left disk 1 at 99.2% of a 512K floppy — 3,930 bytes spare —
while disk 2 sat half empty. In that state the next add-on of any size is a
build **error** rather than a split, and the error names a package that did
nothing wrong. The packer now runs first-fit to learn how many disks the set
needs, then re-packs into that same count with worst fit, so headroom is
spread evenly. Same disk count, `requires` groups still share a floppy,
`recommends` pairs still co-located best-effort. If balancing would ever need
more disks than first-fit did, the first-fit layout is kept — fewer floppies
beats tidier ones. Current set: 436K and 339K, from 520K and 255K.

### New add-on: `stock`, the warehouse monitor

The first package aimed at what an OpenComputers base actually *does* rather
than at TOS itself. Put a transposer or inventory controller next to your
chests: `stock` totals every item across every adjacent inventory, and warns on
anything below a threshold you set.

The correctness point, because it is the one thing a stock count can get
quietly and badly wrong: **items are aggregated by registry name plus damage,
never by the display label.** Two mods can both ship a "Copper Ingot", and any
item can be renamed on an anvil — a count keyed on the visible name merges
things that are not the same item and splits things that are. The label is
carried for display only, first-seen-wins so the reading stays stable between
refreshes. Pinned in both directions by tests.

The other case a naive implementation drops: a watched item that has fallen to
**zero** appears in no scan reading at all, so "iterate what we found" silently
stops reporting it — precisely when the monitor should be shouting. Watched
items that are absent are synthesized at zero and sorted to the top.

`stock` is the live full-screen monitor (R rescan, / filter, L low-only, W set
a threshold, U clear it); `stock low` answers the different question "what do I
need to go make?", sorted by worst shortfall; `stock list` and `stock sides`
are one-shot listings for scripts and for checking your wiring. Thresholds live
in `/etc/stock-watch.cfg` as plain tab-separated lines — hand-editable, never
executable, and keys containing a separator are refused rather than written
somewhere they would forge extra records on the way back in.

Aggregation, thresholds and formatting are pure (`stock/stock.lua`) and carry
53 off-box assertions; `init.lua` is only scanning, drawing and input.

**`peripheral.inventory` gained `stacks(side)` and `sides()`** in the base
image to support it. `list()` collapses `label` and `name` into one field,
which is fine for "show me this chest" and wrong for anything that aggregates,
so `stacks()` returns full detail with a stable identity key. It also uses
`getAllStacks` where the component offers it — one call per side instead of one
per slot, which for a double chest is 54 component calls saved per side and the
difference between a scan you can run live and one you cannot.

### TOS can reach the internet, and `pkg` can fetch from it

TOS had no internet-card support of any kind — not in the sandbox, not in
sysinfo, not in the compat layer, nowhere. OPPM's whole premise is downloading
from GitHub, so "OPPM support" had meant reading an OPPM-shaped manifest off a
floppy somebody carried over. This is the missing half.

**`kernel.internet`** is the transport, and the one place the bounds live.
`get(url)` reads into a string (64 KB default cap — the result is RAM, and a
Tier 1 machine has 192 KB of it *in total*); `download(url, path)` streams
straight to a file a chunk at a time, via a `.part` rename so a truncated
transfer never leaves a file that looks complete. Only `http`/`https`; URLs
carrying credentials, control characters or no host are refused. Reads yield
cooperatively, so a slow server slows the seat that asked rather than the
machine. `internet` (the command) reports card status, because "it doesn't
work" has three unrelated causes — no card, the **server** has HTTP off for
internet cards, or an admin here ran `internet off` — and an operator who
cannot tell them apart debugs the wrong one. `hw` and the POST screen show the
card with what the server actually permits.

**A new `internet` capability** gates it. It is deliberately not folded into
the generic `component` grant: outbound access is an exfiltration channel for
anything a program can read, and installing a game should not hand it the
network. The capability is the boundary; the byte caps are there so honest code
cannot accidentally OOM a small machine on somebody's web page.

**`compat/internet.lua`** completes `require("internet")` for OpenOS programs,
including the parts of the contract that are awkward (`request` errors rather
than returning `nil, err`, because that is what OpenOS does and porting a
program should not mean rewriting its error handling).

**`pkg` fetches from remote repos** — `pkg repo add/list/remove`, `pkg remote`,
`pkg fetch <name>`:

- **The configured repo list is the allowlist.** No default repo, no discovery,
  and an index cannot introduce another host — a fetch that would leave the
  configured origin is refused. Adding a repo is admin-gated, because it is a
  standing decision about where this machine accepts executable code from.
- **A fetch is a download followed by an ordinary install.** `kernel.pkgremote`
  downloads into a staging tree shaped exactly like a repo on a floppy, and
  then the *existing* `pkg.install` runs against it. Hash verification, the
  write-root confinement, conflict and file-ownership checks, dependency
  resolution and the unverified-package gate are not reimplemented for the
  network. The alternative — threading HTTP through `pkg.install` — would have
  meant a second, network-aware copy of the most security-sensitive loop in
  the system, free to drift from the first.
- **Paths from a stranger are not paths.** Every source path in a remote index
  is vetted before it is used to build either a URL or a staging destination:
  no traversal, no absolute paths, no scheme, no protocol-relative `//` host
  swap, no query or fragment. `validateManifest` checks this too, but that runs
  at install time — after the bytes are already on disk — so it cannot be the
  only check.
- **Bounded**: 128 KB per file, 512 KB per package, 64 files per package,
  128 KB index. Staging is cleared before and after every fetch.
- The index is **decoded as data** with a byte bound, never `load()`ed. A repo
  index is a table written by a stranger; running it as Lua would hand them the
  machine before they had shipped a package.

Most repos ship no hashes, so `pkg fetch` refuses them until the operator says
`--allow-unverified` — the same gate a hashless floppy package hits. Remote
provenance is not a reason to relax it; it is the reason it exists.

Not supported yet: OPPM's *master list* (the index-of-indexes that lets `oppm`
search every registered repo). TOS works one repo at a time, by URL.

### `tail`, `which`, and per-user aliases

Three gaps in the shell where the obvious phrasing could not be typed.

**`tail <file> [lines]`** — `head` shipped without its other half, which meant
the natural way to follow a log, `watch tail /var/log/tos.log`, was unsayable.

**`which <name>`** — a built-in, an installed package's command, and a program
on the search path can all answer to one name, and there was no way to ask
which one wins. `which` reports all three in dispatch order and marks the
losers as shadowed. It answers by calling the executor's own resolver rather
than describing it, so it cannot drift into documenting a different shell, and
it uses a new side-effect-free `pkg.ownerOfCommand` rather than `getCommand` —
resolving a name must not load and run the package that provides it. It is the
sibling of `why`: one says what will run, the other why you were refused.

**`alias` / `unalias`** — per-user command shorthand, stored in your profile.
Aliases take effect on the next command rather than the next login, and carry
no privilege: the expansion is dispatched through the same tier gates as a
typed command. Expansion chains through other aliases but each name expands at
most once, so the near-universal `alias ls "ls -a"` reaches the real `ls`
instead of looping until the seat hangs. The sanitizer restricts alias names to
the character class a command name can have, so a stored alias can never carry
punctuation or a second command into the position where a command name is read.

### #SEC — a PATH entry of exactly `/tmp` bypassed the search-path confinement

Found while moving the resolver out of `executor.lua` so `which` could share
it. #SEC H9 confines unqualified command names to system bin directories, with
PATH honoured only where the entry is not under `/mnt`, `/tmp`, `/public`,
`/home` or `/root`. The check compared the PATH entry against that list raw,
but the list is written with trailing slashes — so `/tmp/x` was correctly
refused while a bare `/tmp` matched nothing and was treated as safe. With
`PATH=/tmp` set, a planted `/tmp/<name>.lua` would run for any name that is
not a built-in and not in a system bin dir. The bare root is the shape a PATH
is actually written with, which is why it survived. Entries are now normalized
before comparison, and the resolver's rules are pinned by tests.

### `pkg` reads real OPPM repo indexes (`programs.cfg`)

The manifest reader's own header had described `programs.cfg` since FEAT-7 and
nothing ever read it, so a genuine OPPM repo checkout reported "no manifest
here". It is now the fourth recognized form, looked for in the parent of the
package directory — where a real repo keeps it — so a checkout installs with no
rearranging. A package that ships its own manifest still wins; the index is the
fallback.

Two things in that format needed translating rather than copying:

- **`files` is keyed the other way round.** OPPM's key is the source path
  relative to the repo root and its value is the destination *directory*, with
  the installed filename coming from the source's basename. TOS manifests use
  one absolute path for both roles, and the old translator pushed the value
  into the files array — producing `files = {"/bin"}`, a directory in the slot
  where a file path belongs, which `validateManifest` then rejected as outside
  the write roots. Nothing shaped like a real OPPM manifest could install.
  Manifests grew an optional `fileMap` (target → source) to express the
  difference; native packages are unaffected and still resolve exactly as
  before. A destination outside `/usr` or `/var/pkg` is still refused — that is
  the write confinement working, not a translation failure.
- **`dependencies` values are install paths, not version constraints.**
  `{ libGUI = "/" }` means "also install libGUI". The old translator recorded
  `/` as a version constraint, so `pkg info` showed operators `libGUI /` as
  though a path were a version. (It never failed an install — `satisfiesConstraint`
  cannot parse `/` as a version, so the comparison returned equal and the
  implicit `==` passed. Working by accident is still worth fixing.)

OPPM's `:`-prefixed "copy this whole directory" keys are **refused**, with the
offending entry named. TOS installs a declared file list — each path validated,
hashed, and owned by exactly one package — which is what conflict detection and
clean uninstall depend on; installing such a package while silently dropping
its data files would be worse than declining it.

`fileMap` is validated like everything else a manifest can say: every entry
must name a target that `files` already declares, and sources are relative and
traversal-checked. The internal `_srcBase` that redirects where a translated
package is read from is stripped from every on-disk manifest form, so a
hand-written `package.lua` cannot point the installer's reads at an arbitrary
directory.

### Picker: whole-category selection and a filter

**G** ticks every package in the category the cursor is in, and clears them on
a second press. A half-ticked group fills up rather than emptying, so G reads
as "give me the rest of these" until there is nothing left to add — more
predictable than a stored per-group flag when you have already ticked two of
five by hand.

**/** filters as you type, matching name, description *and* category: an
operator hunting for "the spreadsheet one" will type any of the three and
shouldn't have to guess which field the author filled in. Enter keeps it, Esc
undoes it, and Esc from the list clears an active filter instead of quitting —
a filter that matched nothing leaves an empty list, and Esc is exactly what
you reach for there, so exiting the installer would be a nasty surprise. An
empty result says `Nothing matches 'zzz'` rather than showing a blank pane,
and the count rail reads `3 of 14 match 'gam'` while a filter is on, because
otherwise a filter you forgot about looks exactly like a disk with packages
missing.

**A** and **N** now act on what is *visible*. That is the interaction that
makes the two features worth having together — filter to `game`, press A,
install — and an A that also ticked the packages you had just filtered away
would defeat the point of filtering. Selections are keyed by package rather
than by row, so ticks survive every filter change: filter, tick, refilter,
tick, install the union.

### The package manager can now update, and can tell you no

An audit against "resolves dependencies, updates, resolves conflicts, and is
otherwise autonomous" found the first one solid and the other two missing
outright. Dependency resolution was already good — transitive, version-
constrained, `optional` deps, `provides` aliases, and a reverse-dependency
guard on uninstall. The rest:

**There was no update path at all.** `pkg.install` refused over an existing
package ("uninstall first") and nothing ever compared what is installed
against what a disk is offering. `compareVersion` and `satisfiesConstraint`
already existed; they were only ever used to satisfy dependency constraints,
never to notice that the floppy in the drive has something newer.

```
pkg outdated                  what has a newer version available
pkg upgrade <name> [<name>…]
pkg upgrade --all --yes
pkg upgrade <name> --dry-run
```

An upgrade is deliberately not "install over the top", and the reason is one
step in the middle: it removes the old version's files **including the ones
the new version no longer ships**. An install-over strands those forever,
owned by nothing and deleted by no future uninstall — which is exactly why the
set of files to delete is the difference between two manifests and cannot be a
flag on install. It also verifies the candidate *first* (hashes, licence,
conflicts), so a failed gate never leaves the machine with the old version
already gone, and it restores the package-enable byte and the rc `.disabled`
boot marker afterwards — two different flags that an earlier round proved easy
to confuse. Upgrading a package something else depends on is allowed
(`_internalUpgrade` bypasses the uninstall guard, which would otherwise freeze
every depended-upon package permanently); a downgrade needs `--force`.

**Nothing detected conflicts.** Now two kinds, and the second is the one that
actually bites: a declared `conflicts = { "other" }`, checked in *both*
directions because a conflict is symmetric in fact even when only one author
wrote it down — and **file ownership**, which needs no declaration at all.
Install copied its files over whatever was there, so two packages shipping the
same target silently clobbered each other and uninstalling either then deleted
files the other still needed. Both are checked before a single byte is
written; `--force` overrides, loudly.

### Third-party and OpenOS packages actually run now

OPPM manifests were already translated, and the provenance was already
computed — and then thrown away. `installed[m.name] = m` stored the raw
manifest with no record of where it came from, and a translated OPPM package
inherited no capabilities, because an OPPM manifest has none to declare. The
result: an OpenOS program installed perfectly cleanly and could not execute a
single line, because `io`, `term` and `filesystem` were not in its sandbox.

Recognising a package as foreign is therefore not a label, it is the thing
that makes it work. Provenance is now recorded on the manifest
(`origin = "openos"`), and a foreign package declaring no capabilities is
granted the compat surface — `compat.io`, `fs.read`, `fs.write`, `component` —
at install time. That is a real privilege grant, so `pkg info` states it
outright rather than leaving the operator to infer it.

Not a blank cheque: `legacy` (raw `os`/`io`) can never be requested by any
manifest, peripherals still have to be asked for, and a foreign manifest that
*does* declare capabilities keeps its own set — the default is a fallback, not
an override.

Also implemented the third manifest form, `<dirname>.cfg`, which
`loadAnyManifest`'s own header had documented as supported for a long time
without anyone writing it. A loot disk carrying one read as "no manifest
here".

61 assertions in `test_pkg_lifecycle.lua` over a fake disk: upgrade including
the dropped-file case, refusing an up-to-date upgrade and an unforced
downgrade, upgrading a depended-upon package, file-collision and both
directions of declared conflict, an upgrade not self-conflicting on its own
files, and all three foreign-manifest forms with their capability grants.

### The installer came off the floppy

It was being shipped twice, and neither copy needed to exist. The picker's
first act is `require("kernel.pkg")` — so it can only ever run on a TOS
machine, which by definition already has one. Yet it shipped as a ~40 KB file
on **every** Optional Utilities disk *and* as a ~40 KB string embedded in
`kernel/pkg.lua`, kept byte-identical by a test whose entire job was policing
the duplication.

It now lives once, at `tos/shell/pkgpicker.lua`, as an ordinary base-image
module. `pkg install` requires it like anything else. That deletes the
embedded string (**pkg.lua: 116 KB → 77 KB**), the disk copy, and
`test_picker_sync` along with the problem it existed to manage. The disks get
their 40 KB back — disk 1 went from 10 packages to 10 *plus* the ~40 KB that
was the installer.

What the disks carry instead is a **README** naming the command to run, and
the set manifest. The media detector now identifies an Optional Utilities disk
by that manifest rather than by the presence of an installer, which is both
more accurate — the manifest is what makes it a *set* rather than a loose pile
of packages — and necessary, since there's no installer on it any more.
`pkg make-disk` (the in-TOS builder) writes the same pair.

**The disk-swap prompt is a real dialog now.** It was two lines painted over
the install log; it's the DOS-style modal — framed, titled, shadowed, with
buttons — with room to name the disk *and* every package still waiting on it.
`dialogs.dialog` only reads `D`/`T`/`W`/`H` off the shell state, so the picker
drives the genuine renderer through a synthetic one built from its own draw
primitives. No second dialog implementation to drift from the first, and it
falls back to the old two-line prompt on an image without the dialogs module.

**Automation flags**, since the picker assumes a person at a keyboard and a
provisioning script hasn't got one:

```
pkg install <name> <name> ...     several at once, no picker
pkg install --all --yes           everything on inserted media and repos
pkg install <names> --dry-run     print the plan, change nothing
```

`--yes` is *required* by `--all` rather than merely accepted: `--all` installs
every package on whatever disk happens to be in the drive, and the alternative
to demanding confirmation is a script that hangs on a question nobody is there
to answer.

### The installer stopped pretending there is only one floppy

The set outgrew a single 512K disk a while ago, and everything downstream was
still written as though it hadn't. Two halves, both fixed.

**The picker now sees the whole set from one disk.** The builder writes a *set
manifest* (`optutil-set.lua`) onto **every** disk, describing every package and
which disk it lives on. The picker reads it, so with disk 1 in the drive you
see disk 2's contents too — dimmed, with the panel naming the disk to fetch,
and **selectable anyway**. Before this, a one-floppy machine showed half the
catalogue with no hint the rest existed; you had to already know what you were
missing.

Installing then does everything reachable, and asks for the rest:

```
Insert disk 2 for: tetris, ttt
Enter = continue   A = stop, keep what's installed   U = undo all
```

Enter re-probes the mounts and carries on. **A** stops and keeps what already
installed. **U** rolls the entire run back — newest first, because
`pkg.uninstall` refuses to strand a reverse dependency and honouring that
order is what makes the rollback actually complete rather than half-finish.

**The builder now keeps related packages on the same disk.** Hard `requires`
edges were already inviolable (a split group cannot install at all — kernel.pkg
resolves deps from the repo it installs from). `recommends` had no such
protection, and the packer had put `tape-authenticator` on disk 2 while the
`tape` package it recommends sat on disk 1 — an operator with one floppy got
the keycard tool and no way to manage the tapes it writes. Soft edges are now a
second tier: clusters the packer tries to place whole, falling back to
splitting them when they genuinely don't fit, and **naming every pair it had to
separate**. On the current set it separates none — `tape` + `tape-authenticator`
are together, and `mouse` ships beside all four add-ons that want it.

Two bugs found doing it. The soft clustering silently merged *nothing* at
first: `clusterOf` was keyed by the group *wrapper* while `groupOf` returns the
raw member array, so every lookup was nil and the union-find quietly did
nothing — the kind of failure that reports success. And the per-disk size
reserve didn't count the set manifest, so a disk could overflow by its size;
it's reserved up-front now, deliberately over-estimated, because guessing high
costs slack and guessing low costs a broken floppy.

`test_build_disk`'s split case used a 160K limit, which stopped fitting once
the picker grew — a limit below the largest single package is a legitimate
build *error*, not a split, so that test had started asserting the wrong thing.
It derives from a named `SPLIT_LIMIT` now, with the reasoning written down.

### The add-on installer got a second pane, and opinions

The pick-list is now the **left** column and a real detail panel fills the
**right**: description, version, category, kind, author, install state — and
two things the picker knew but never said.

**Which disk it's on.** `listAllAvailable` has always scanned every mounted
repo and recorded the source, so a two-floppy set was already fully listed;
the picker just never showed which floppy each package came from, which made
disk1-only listings look like a disk with things mysteriously missing. The
panel now has a `From` field.

**What comes along.** Ticking a package auto-selects its `requires`,
transitively and cycle-safely, marked `[+]` and counted in the "N selected"
rail — so the operator sees the true install set before pressing Enter
instead of watching three picks install five things. A requirement that isn't
on any inserted disk is called out in the panel (`not on any inserted disk:
…`), which is the common failure in a set that spans two floppies, and beats
letting the install discover it.

**A new `recommends` field**, the soft counterpart of `requires`: packages
that make this one better but aren't needed for it to work. Nothing is ever
installed behind the operator's back — `R` adds the suggestions for the
current selection, and that is the only way they get in. The panel shows both
directions, and the reverse one is the useful half: **`Wanted by`** lists
every add-on in the set that recommends the highlighted package. "mouse is
suggested" is noise; "mouse is wanted by calc, mail and ttt" is an argument.
`calc`, `ttt`, `tetris` and `mail` recommend `mouse` (all four are genuinely
clickable with the driver installed); `intercom` and `tape-authenticator`
recommend `tape`, which is how you manage the tapes they depend on the
contents of.

Installing now draws a real progress bar with a `n/total` counter rather than
a bare list. Below 60 columns the layout falls back to the previous
single-column form with the two-line footer, so a 50×16 T1 screen still works.

Both copies of the picker were re-spliced together — it ships from
`TOS-Extras/build/install.lua` *and* from `kernel/pkg.lua`'s embedded
`PICKER_SRC`, pinned byte-identical by `test_picker_sync`.

### A worker node wizard that knows what OS it's on

`cluster/openos/cluster-worker-setup.lua` sets up an OpenOS worker: domain id,
hostname, shared secret, and optional `/etc/rc.cfg` autostart.

The interesting part is the first thing it does. Worker nodes are OpenOS-native
by design, so someone running this on TOS isn't slightly off — they're on the
wrong machine. Rather than dying on a missing `require`, it probes what each
OS has that the other doesn't (`_TOS` and `kernel.pkg`/`kernel.users` and
`/tos/kernel/init.lua` vs `filesystem`/`shell`/`term` and `/lib/core/`),
reports **which OS it thinks this is, the specific evidence, and what to run
instead** — `cluster-setup`, choosing Manager. A TOS box with the OpenOS
compat layer loaded still reads as TOS because the TOS evidence outweighs; a
genuine tie reports "unknown" rather than guessing.

It also refuses a shared secret under 16 characters (it is the HMAC key, not a
password), refuses one containing spaces (it must match the Manager byte for
byte, and a stray space is invisible in a config file), and never echoes the
secret back to the screen when it tells you what to set on the Manager side.
69 assertions, with the OS probe injected so every environment is testable.

**And the test runner was silently skipping two directories.** Extras tests
were discovered under `modules/*/`, `build/` and `pane-ui/` only — so
`rbmk/test_rbmk.lua`, 72 assertions the README has been citing, has never run
in the suite. Both runners now cover `rbmk/` and `cluster/*/` too. It passes;
it just wasn't being asked.

### Setting up a cluster is one command per machine

The honest summary of the old state: there were two ways to install a cluster,
the documented one didn't work, and neither told you which package your machine
needed. Both packages were already on the ordinary Optional Utilities disk —
but the docs pointed at a bespoke `cluster-install.lua` floppy instead, and
that wizard was **unusable in the panels shell**, which is where operators are.
It drove itself with `io.read` (which resolves to `term.read`, painting
straight to the display and taking over the event loop — it would draw over the
UI) and coloured itself with ANSI escapes (TOS's display is GPU-driven and
interprets none, so they printed as literal garbage).

**`cluster-setup` replaces all of it**, and lives in the *base image* — which is
the point, because it is then present *before* either package is, and the first
question it answers is "which one does this machine need?":

```
cluster-setup            set this machine up (guided)
cluster-setup explain    describe the parts, change nothing
```

One Master (`cluster-master`, service `clusterd`), any number of Managers
(`cluster-manager`). The wizard picks the role with you, installs that package,
writes the config, starts the service, and runs pairing. Nothing is copied by
hand. It is named `cluster-setup` and not `cluster` on purpose: a registry
command shadows `/usr/bin` (see `executor.lua`), so taking that name would have
broken the Master's own CLI the moment the package was installed.

Three real faults found in the old flow and fixed in the new one:

- **The Master's address was printed truncated** (`myAddr:sub(1, 12) .. "..."`)
  *inside a command line*, so the one line an operator was meant to copy to
  every Manager read as copy-pasteable and wasn't. It now prints in full, and
  the Manager side *rejects* a shortened address with an explanation — every
  TOS listing abbreviates to 8 characters, so pasting one back is the obvious
  mistake, and a config built from one can never connect.
- **"Start at boot?" did nothing, either way.** `rc.start()` already clears the
  service's `.disabled` marker (that is how an explicit start persists), and
  the installer then wrote `/var/pkg/installed/<pkg>/state` — the *package*
  enable byte, which rc never reads. Answering "no" left it enabled at boot.
  The answer is now honoured by writing the marker rc actually consults.
- **`/etc/*.cfg` was written with a truncating write**, so a crash mid-write
  left a daemon's config unparseable on a machine whose whole job is to come
  back up unattended. Atomic now.

The wizard takes every side effect through an injected ctx — install, write,
start, pair, ask, choose — so the whole flow runs off-box against scripted
answers rather than being the one part of the cluster nobody could test.
87 assertions in `test_cluster_setup.lua`, covering both roles, a truncated
address, cancellation at each prompt, a failed install, a failed pair
round-trip, no modem, wired-only, and the both-packages-installed
misconfiguration.

`cluster-install.lua` stays as a pointer to the new command, so an operator
holding an older floppy is told where to go instead of running something
broken.

Also audited every add-on manifest against what's actually on disk — install
targets, `commands` wiring, rc.d presence, and orphaned files. All 14 clean.
One doc error fixed on the way past: the Manual listed `/etc/cluster.cfg`,
which has never existed; the real files are `/etc/cluster-master.cfg` and
`/etc/cluster-manager.cfg`.

### Any program can now be in your face

TOS has two places to put words on screen, and the difference matters. The
output area above the command line is *polite* — it waits until you look down.
A dialog box is not: the DOS-style modal, double-line frame, `╡ title ╞` tab,
drop shadow, buttons you must answer, centred over whatever you were doing.

That box already existed and was already general-purpose in its own docs. What
it wasn't was *reachable*. `dialogs.dialog` needs the shell state `S`, so only
shell code could raise one — a background service, an add-on's mesh handler, a
sandboxed package command had no way in. None of them can draw either: they run
where another process may own the screen, and painting would corrupt it.

**`kernel.notify` is the way in.** Programs post a notice; the shell that owns
the display raises the box on its next idle tick — "listener marks, tick draws",
the rule the chat tab already followed, generalised. The Intercom was the first
consumer and had grown a private queue hardcoded into the event loop; that queue
is now this facility, and the loop no longer knows the Intercom exists.

New `notify` command as the operator/scripting surface — the intrusive
counterpart to `echo`:

```
echo   "backup finished"      you'll see it when you look
notify "backup finished"      it's in your face, on every seat
```

**The rate limits are the load-bearing part.** A modal any program can raise is
a way to lock an operator out of their own computer — by accident, from a
service stuck in a retry loop, as easily as on purpose. So the facility enforces
a floor no caller can opt out of: 10s between notices from the same source, 3s
of quiet after *any* dismissal (you always get your keyboard back), 8 queued
maximum, and a 2-minute expiry so a notice raised while nobody was looking can't
ambush someone twenty minutes later. A refused post is normal and still reaches
the log — it just doesn't get to interrupt. A program's own policy (the
Intercom's severity cooldown) sits *on top* of this floor, never underneath.

Packages opt in with a `notify` capability, which injects a deliberately
narrowed `post`/`result` pair — no reading the queue (other programs' notices
are none of their business), no settling someone else's dialog, no `_reset`.
The source shown on the box is stamped **from the package name**, ignoring
whatever `from` the program supplies: the name on a dialog that just
interrupted you has to be trustworthy, and it's also the rate-limit key, so a
program that could choose it could evade its own gap by rotating it.

Multi-seat is handled by per-shell cursors over a monotonic sequence, so each
seat raises each notice exactly once rather than whichever seat ticked first
swallowing it; the first operator to answer settles it for everybody. Two bugs
caught in the drain while writing it: advancing the cursor to the queue's
high-water mark after showing *one* notice silently dropped the rest, and
nothing may be advanced at all when the quiet window suppressed a notice, or it
would never get its turn. 101 assertions in `test_notify.lua`.

### The Intercom: a facility that can say something

New add-on (`pkg install intercom`). A Computronics tape holds recorded
announcements; this makes them usable. Two channels carry the same
announcement at once — the tape plays the **voice**, and the same **words** go
over the mesh to every machine willing to hear them.

**The catalog is the whole trick.** A tape drive cannot tell you what is
recorded on it: it's audio, there's no index. So the operator says so once, in
the notation they'd write down anyway while recording it —

```
fuel-low  [0001] "Warning: Reactor fuel low." [0005]  warn
offline   [0006] "Warning: Reactor offline. Facility on backup power generation." [0010]  alert
```

— and that single line is all four things the Intercom needs: where to seek,
when to stop, what to broadcast, and how urgently to interrupt people. Leading
zeros are optional, because the padded form is how a person *writes* a cue list
and the short form is how a person *types* one. A typo is reported by line
number and skipped; one bad line must not silence an announcement system.

Positions written by hand are easy to get wrong, so `intercom test <cue>`
seeks, plays and stops — and tells nobody at all. Hear it before anyone else
does. The tape is optional throughout: `intercom say "we are out of iron"` is a
text-only announcement and needs no drive.

**Severity decides how hard it interrupts**, and the cooldown is what makes
that safe. `info notice warn alert critical`; below the receiver's popup level
an announcement lands in chat and the log, at or above it a message box appears
over whatever they were doing. But a failing reactor can announce itself every
few seconds, and a modal per announcement would make the computer unusable at
exactly the moment an operator needs to type on it — so after one popup, none
for `cooldown` seconds (default 60). Nothing is dropped by this; only the
*interruption* is suppressed. Every announcement still reaches chat and
`intercom log`.

Three details worth naming:

- **Playback never blocks the shell.** The stop at a cue's end is a `event.timer`
  sized from the cue's length, not a poll loop on `getPosition()`. Waiting for
  the recording to finish would freeze the seat of the person who just
  triggered an evacuation alarm.
- **Absolute seeking on a relative-seek device.** Computronics `seek` is
  relative and clamps at both ends, so reaching a known offset means
  rewind-then-forward. The tests drive this against a fake drive that clamps
  the same way.
- **The mesh handler never draws.** It runs in the kernel's dispatch context
  where no tab owns the screen; it queues, and the panels idle loop raises the
  message box — the same "listener marks, tick draws" rule the chat tab
  already follows.

Ships **disabled** (`service start intercom`): accepting messages that can
raise a modal on your screen is an operator decision, not a default. A machine
without it still relays announcements for its neighbours. 112 assertions in
`test_intercom.lua`, with a fake tape drive and no network.

### Chat is multi-operator

Chat could address one peer (`bravo: on my way`) or everybody. It now
addresses a **group**:

```
@ops: reactor is down
/group new ops alpha bravo
/group add ops charlie      /group rm  ops charlie      /group del ops
```

A group is a *name for a set of peers*, not a protocol — no group membership
on the wire, no group key, no server. Each member gets an ordinary directed
message, so groups work between any peers that already trust each other and
nobody has to agree on who "ops" is. The list lives in `/etc/chat-groups.cfg`.

Unreachable members are **named**, not skipped: "delivered to 2 of 4" plus who
was missed. A group that silently shrank because someone's machine was off
would let you believe a message landed when it didn't. The parser checks the
group form *before* the peer form, or `@ops:hi` would have been looked up as a
peer literally named "@ops" and failed with a message about peers.

### SRM: one name for system repair and maintenance

TOS had four maintenance tools that grew up separately and never knew about
each other: `doctor` (runtime health), `verify` (files against the manifest),
the boot-time fixer pass, and `backup`. Each was fine. Together they were four
front doors, three report formats, and no answer at all to the question that
matters most — *why did the last boot fail?* — because when a boot fails, none
of them ran.

**SRM** is the answer to that, in two halves.

**SRM Basic lives in the EEPROM.** The BIOS already detected the faults that
stop a boot — a Lua 5.2 CPU, no boot device, a missing kernel, an `/init.lua`
that won't load — but it reported each one with its own ad-hoc message and then
halted, and the evidence died with the power cycle. Those six sites now share a
single exit that gives each fault a **name**, a **beep code** (one long tone,
then a number of short ones equal to the code's digit, so a box with a dead
screen is still diagnosable by ear), and — the part that matters — **parks the
code in the EEPROM data field**. That field is the only storage that survives a
machine whose disk is the problem. It goes on its own third line, leaving the
boot address on line 1 and the manifest anchor on line 2 untouched; a previous
code is replaced rather than appended, so the 256-byte field can't fill up and
take the boot address with it.

The consolidation paid for itself: six bespoke failure paths collapsed into one
handler cost **14 bytes** of a 4 KiB EEPROM, and the budget test still passes
with 182 bytes spare.

**SRM Advanced is the `srm` command.** It has a disk, so it covers what the
EEPROM has no room for. On the first successful boot after a POST failure the
kernel reads the parked code, explains it in English, and clears it — a fault
that killed a boot last night is still waiting to be explained this morning.
The peek is a substring test on 256 bytes, *not* a module load, so the boot path
only pulls SRM in when there is actually something to explain; the memory
round's rule about not loading at boot what you might not use still holds.

`srm` also runs `doctor` and `verify` (as `srm health` / `srm verify`, both
still standalone commands) and shares one severity vocabulary across all of
them, so the boot log and the shell finally render and total the same report.
The boot-time fixer pass now runs *through* SRM, which means the report you get
at 3am on a repair boot is the same one `srm repair` prints.

### Files it knows were good

`/etc/critical.bak` is a list of paths. It can tell you a file vanished; it can
never tell you one was quietly changed. `verify` compares against the manifest,
which says what *should* be installed — also not the same question.

`srm baseline` records a SHA-256 of every boot-critical file as it stands right
now, and `srm scan` reports anything that has since gone missing, drifted, or —
worth its own severity — rotted *inside the repair store*, because a corrupt
source you trust is worse than no source at all. `--full` additionally keeps a
verified copy of each file under `/var/srm/store` (mirroring real paths, so an
operator with a broken index can still copy one back by hand), which makes
`srm repair --restore` work with no external media. Hashes-only costs a few
hundred bytes and still detects everything; it just needs `--source /mnt/fd0`
to fix it.

Two rules make this safe to point at `/tos/kernel/`:

- **Nothing is written unverified.** Local store or install floppy, a candidate
  must hash-match the baseline or the file is refused and left alone. With no
  baseline there is nothing to check against, so the restore refuses outright
  unless you say `--unverified` — the same explicit-consent shape
  `pkg install --allow-unverified` already uses.
- **Nothing is truncated.** Restores go through an atomic write. `fs.copy`
  opens the target `"w"`, which empties it the instant it opens; a failure
  between there and the last byte would leave a zero-length
  `/tos/kernel/init.lua` — SRM causing the exact unbootable state it exists to
  repair. It writes a sibling temp and renames instead.

A baseline is a claim about what "good" means on this machine, so `srm
baseline` says so plainly before taking one: on an already-damaged system it
just certifies the damage. And the boot-time pass deliberately never restores
files — overwriting a system file is a decision an operator makes, not a fix to
apply unattended. That line is inherited from `kernel/repair.lua`'s original
philosophy (fix what is mechanically safe, report what isn't) and SRM keeps it.

Covered by `test_srm.lua` (147 assertions) and 64 new assertions in
`test_bios.lua` that boot the BIOS into each fault path and check the parked
code, the beep pattern, and that the boot address and manifest anchor survive.
The two halves are pinned against each other in both directions: every code the
BIOS can emit must be explained by the kernel, and every code the kernel
documents must still be emitted.

---

A play-test round on a 1 MB box (2× tier-3.5) never reached a usable
shell. It booted with 127–204 KB free, the panels shell died allocating
its screen buffer, and the emergency shell that was supposed to catch that
**panicked in the same way** while verifying the system. Two separate
faults, one cause: TOS loaded almost everything at boot, and read files
whole to run them.

### Modules load when you use them, not when you boot
Boot used to `require` and initialise the package manager, the OpenOS
compatibility layer, the file-transfer and remote-shell handlers, the
backup, keychain and trash modules, and the cron scheduler — every boot,
whether or not the session ever touched them. Measured on the release
image that is **165 KB of source** compiled and resident before the shell
is even asked for, on a machine that was reaching the shell with 115 KB
free.

Each of those now loads on first use, and each one's *entry route* was
kept exactly where it already was. `pkg`, `cron` and `trash` initialise
themselves from the live kernel handles when required, which is what
every existing caller already did. The transfer and remote modules load
on their first inbound packet (`net`'s dispatcher resolves the handler),
on an outbound `scp`/`rsh`, or not at all. The compat layer loads when
something first requires an OpenOS name — `term`, `filesystem`, `io`.

The `fileshare` and `rshd` daemons used to `require` their backend purely
to flip its enable flag, which forced it into RAM on every boot. They now
record that state with `net`, which applies it when (and if) the backend
loads. The gates stay **fail-closed** in both directions: a backend that
was never loaded refuses requests exactly like a loaded, disabled one.

Boot-profile gates survive the move intact. Safe Mode and `minimal` still
refuse OpenOS compat, still refuse to run stored cron jobs, and still stop
package commands from dispatching — enforced now at the point of lazy
load rather than by simply never loading. The package dispatch gate is
applied before initialisation rather than after, so a failed init can no
longer fail *open*.

### Reading a file to run it no longer needs the whole file
Loading a module read it into a table of 4 KB chunks, `table.concat`'d
them into one string, and handed that to `load()` — the chunk table and
the joined copy alive at once, then the compiled chunk on top. The shell's
`core` command category is 77 KB, so opening it asked a starved heap for
roughly 154 KB of transient before compiling anything; the play-test log
shows it failing ten times in a row. Both the module loader and the system
verifier now drop the joined copy: `load()` is fed straight from the chunk
table, and each piece is released as it is consumed, so the source frees
itself while the chunk compiles.

Two traps live in that reader, and between them they dictate its exact
shape. The first is silent: `load()` treats an empty string from a reader
as end-of-chunk, so a filesystem short read returning `""` mid-file would
compile a *prefix* of a kernel module and raise nothing at all. The second
is fatal, and the obvious implementation walks straight into it —
**the reader must not touch the filesystem**. Component calls can yield,
because OpenComputers gives each machine a direct-call budget and yields
when it runs out, and `load()` is a C function; a yield inside its reader
is an `attempt to yield across a C-call boundary` and takes the kernel
down. So all the I/O happens first, where yielding is ordinary and safe,
and only then does compilation run against memory. Tests pin both.

Relatedly, a module that fails to *read* no longer reports itself as a
syntax error. That wording is not free: it sends you looking for a broken
file when the file is fine.

`fs.readFile` now runs its `table.concat` **inside** its own `pcall`. The
concat is the allocation most likely to fail on a tight heap, and outside
the guard it escaped as a kernel panic instead of the `nil, err` every
caller was already written to handle. That is the exact path that turned a
recoverable shell failure into an unrecoverable one.

`verify` no longer holds a whole file at all unless the manifest claims a
content hash for it, since hashing is one-shot by nature.

### Smaller resting heap
The garbage collector's default pause lets the heap grow to twice the live
set before a full cycle; on a 1 MB machine that float alone can be the
headroom the shell needs. It now runs tighter. The kernel also drops its
own `boot` function once boot completes — it is called exactly once per
power-on — and `rc` no longer pulls in the sandbox builder for the shipped
services, none of which need it.

Nothing was removed. Every command, module and daemon behaves as before;
the difference is *when* the memory is spent. Not yet verified in a real
Minecraft world — the play-test that motivated it is the next round.

### The loading screen stops fighting itself
On a splash boot the screen had two owners that did not know about each
other. The loading bar and its narration paint at **fixed rows**; the early
boot log is a **free-scrolling** printer that clears whole lines and, once
it runs past the bottom, scrolls the entire screen. Every warning went to
both. Enough of them and the wordmark and bar were dragged upward while the
bar kept repainting where it had always been — leaving a ghost second bar
with repair text overlapping the narration column.

Self-repair and Safe Mode were where operators actually hit it, because
both are chatty: Safe Mode logs one warning per subsystem it disables, and
self-repair prints a line per check. Neither was really at fault. On a
splash boot the bar is now the only thing that draws, and warnings and
errors still appear there verbatim and coloured — the bar always showed
them; they were simply being drawn twice. Self-repair's per-line report
also now respects the verbosity setting like every other cosmetic echo, so
a quiet boot stays quiet and a `text` boot still prints the full report.

### Swap has a tenant
Disk swap has always been a complete, working subsystem with nobody calling
it, so "swap enabled" could never turn into swap *used*. It has a first
tenant now: cold view buffers. A `cat` of a large file or a long listing
opens a tab holding every line, you read one tab at a time, and the rest sit
in the shell's heap doing nothing — and unlike an editor buffer they're
loss-tolerant, since the worst case is re-running the command.

It is deliberately **pressure-triggered** rather than spilling on every tab
switch. Disk I/O in OpenComputers carries a per-tick budget, so paging is a
trade worth making when RAM is short and a pure cost when it isn't; below
`swapPressurePct` of free memory (default 25%) the inactive view buffers go
to disk, and above it nothing pages and nothing is slower. They come back the
instant you open the tab. Tabs that regenerate themselves are left alone, a
buffer too small to be worth the round-trip is left alone, and if swap is
full or switched off the buffer simply stays in RAM.

`optimize swap` now reports what is paged and what the threshold is, and
`optimize swap now` forces a sweep — because a mechanism that correctly does
nothing on a healthy machine is otherwise impossible to confirm.

### The boot log stops blaming memory for the profile's decisions
A Safe Mode boot announced `Skipping power module (low memory: 994KB free)`.
Nothing was wrong with memory; Safe Mode had switched the module off. Both
that line and the network one now name the actual reason.

### Mixed memory tiers are reported as what they are
A machine with one T3.5 stick and one T2.5 stick called itself "tier 3" —
a tier it does not contain. Both places that named memory derived the tier
from the *total*, and a total cannot tell 2×768K from 1024K+512K: they are
both 1536K across two sticks. Dividing gives 768K, which is a real tier, so
the wrong answer looked entirely credible.

Memory is now read per stick, from the capacities the host reports, and
named honestly: `2x T3.5`, or `T3.5 + T2.5` when the sticks differ. Where
per-stick capacities aren't available, TOS reports capacity (`2 sticks,
1536K`) rather than averaging its way to a tier that isn't installed. The
tier table lives in one place now instead of two — the boot log, `hw`,
`mem`, the System Configuration screen and Boot Settings all answer the
same way.

### Tetris shows the right next piece
The NEXT panel was painted just before the new piece spawned, and spawning
is what consumes the queued piece and draws a new one — so the preview kept
showing the piece that had *already* arrived on the board. It corrected
itself on the next soft drop, which happens to be the only other place that
repaints the panel, which is why it looked like the panel only updated when
you pressed down.

### Boot Settings names the memory you actually have
The RAM override offered "plenty" and "tight" — words about what the
override *does*, which told you nothing about the machine. It now reads
`RAM for extras [2x T3.5]`, naming the sticks that are actually installed,
and the values say plainly what they do: `auto (measure)`, `always load`,
`never load`. The System Configuration screen reports the same way, so
`2048K total [T2+]` — which read identically for 512K and 2048K — is now
`2048K total [2x T3.5]`.

Tier names come from the stock OpenComputers stick sizes (192K through
1024K). A size that isn't one of them reports honest capacity (`2x 900K`)
rather than a guessed tier, and nothing is ever labelled above T3.5,
because standard OpenComputers has no Tier 4 memory.

## Unreleased — programs you can walk away from

### Ctrl+B sends a full-screen program to the background
`calc` and the games used to own the terminal until they exited, because a
package command ran **inline** — inside the shell's own coroutine, which
therefore could not run again until the program returned. A package that
declares `fullscreen = true` is now spawned as a **seat-bound process**:
Ctrl+B hands the seat back to the shell, Ctrl+T's switcher brings the
program back, and it repaints where you left it.

While backgrounded a program doesn't just spin. It drops to half rate for
a grace period — step away for a moment and come back and it is still
running — then freezes entirely, costing nothing. A package can override
that: `background = "always"` never freezes, `"freeze"` stops the moment
you leave. Tetris and Snake choose `"freeze"` and come back **paused**,
because a piece that kept falling while you were reading the shell would
cost you a run you had no chance to react to.

This is opt-in. Only the four programs declare it; every other package —
including third-party ones — keeps the inline path exactly.

Ctrl+B rather than the obvious Ctrl+Z, which is already the editor's
Undo. It's intercepted in the kernel loop for the same reason Ctrl+T is: a
program holding the seat's input can never receive the key meant to
suspend it.

### A running program is a tab
Ctrl+B no longer just minimises — the program keeps a **chip in the top
bar**, beside Desktop and Monitor. F2 or a click hands the seat back and
it repaints where you left it; ^W closes the tab and stops the program.
The chip is bracketed while the scheduler is still running the program in
the background and goes plain once it has been frozen, so the tab bar
tells you what is actually still alive. A tab whose program has exited
closes itself.

Under the hood this is the process-backed app model that `apps.lua` has
documented since the tab framework landed and never actually had. It's
also the same viewport groundwork a future split-tabs pass needs.

### Mouse support in the spreadsheet and Tic-Tac-Toe
Click a cell in `calc` to select it, or use the wheel to scroll the grid.
In `ttt`, clicking a square plays it. A click on a grid separator does
nothing rather than being rounded into a neighbouring square — placing a
piece the operator didn't aim at is worse than ignoring the click. Both
run through the same state the arrow keys already drove, and on a machine
with no touch-capable screen the events simply never arrive.

## Unreleased — programs stay on their own seat

### A program renders where you launched it
On a two-seat machine, running `ttt 2p` at one seat drew the board on the
**other** seat's screen, over that operator's work. Every TUI program
opens its display the obvious way — `component.list("gpu")()` — and that
is the first GPU on the bus, which is seat 1's, regardless of who typed
the command.

The sandbox had already solved the mirror-image problem for **input**: a
sandboxed program yields for the scheduler's seat-routed delivery instead
of draining the global queue. This is the output half of the same idea.
`kernel.screen` can now name the seat that owns the calling process
(`callerSeat` / `callerDevices` / `seatDevices`), and the sandbox narrows
`component.list` / `proxy` / `invoke` / `getPrimary` for **gpu, screen and
keyboard** to that seat. No package needed changing — the obvious code is
now automatically the correct code.

It closes a spoofing surface too: an add-on could previously paint a
convincing login prompt on somebody else's display.

Nothing is narrowed when the seat can't be resolved (kernel context, boot,
single-seat machines), and non-display components are never seat-scoped,
so a one-screen box behaves exactly as before. The Optional Utilities
picker runs at full privilege, outside the sandbox, so it resolves its
seat the same way explicitly.

### The installer's rail labels read twice
`13 add-onss`, `9 selectedd`, `Gamess`. A dim rail is drawn already
containing its label, then the label is re-drawn brighter on top; all
three of those re-draws landed one column left, so the rail's copy poked
out past the end of the bright one. While pinning it with a test, a second
bug surfaced: the picker's no-`unicode` fallback measured strings in
**bytes**, and every rail is box-drawing glyphs at three bytes each — the
frame maths was off by two thirds of the rail width. It now counts UTF-8
characters.

### `tape-auth menu add` was impossible to type
Its own usage text said `tape-auth menu add <pass> <Label> | <command>` — but
the shell parses an unquoted `|` as a **pipe**, so the line split before the
package saw it and the second half ran on the spot. `--` is the separator now
(`... Diagnostics -- doctor`); a quoted `|` still works; and an add with no
separator says what actually happened instead of reprinting the same
impossible usage.

The same command also *appeared* to know your account password. It doesn't —
`tape-auth` is sandboxed and cannot reach the user database at all. An empty
menu decrypts under any passphrase (there is nothing to decrypt), so the
**first** `menu add` silently adopted whatever you typed as that tape's
passphrase. It now says so, warns against reusing your login password, and
`tape-auth menu passwd <old> <new>` changes it without wiping the menu.

### The machine beeps when it comes up
The POST-OK beep added last round only existed on the raw-drive boot
branch, so the path every normal machine takes printed "POST OK" and
handed off in silence. It beeps now, the way a 5150 told you the board had
come up — and the BIOS test counts beeps on **both** branches so neither
can lose it again.

### The splash keeps its wordmark
The boot header — wordmark, version, memory, any Safe Mode notice — was
painted once and then wiped by the System Configuration POST screen, which
owns the whole display and clears on its way out. Everything after it
(verify, load, progress bar) composed against a blank screen, so a splash
boot showed a bare bar with no branding at all. The header is a function
now, re-drawn after the POST screen and after Boot Settings saves.

### Key bars are measured in columns, not bytes
calc's bottom bar read `^Q Qui` on an 80-column screen. Not a width
problem — `pad()` counted bytes, and the bar separates its hints with `·`,
two bytes in UTF-8. Five separators, five phantom columns: a 68-column bar
measured 73 and got sliced. Fixed, and the bar now drops **whole hints**
from the right when a screen really is too narrow rather than slicing a
word, with `^Q Quit` pinned so the way out is never the casualty. Related:
`ui.drawRampBar` allowed one column more text than the right ramp cap left
free.

### The shell came back half-painted from `pkg install`
Icons, no filenames, no sizes. The picker draws through a raw GPU proxy,
past the seat's dirty-cell shadow buffer, so the repaint afterwards elided
every cell the shadow believed was unchanged. `executor.lua` already drops
the shadow after a sandboxed *package* command; `pkg install` is a
built-in and never went through that path.

## Unreleased — emulator round 6 fixes

### Mail service is alive again (regression)
The last release blocked add-on library names (`mail`, `rbmk`) from
`require` inside the sandbox — but an rc.d **service shim** is itself
sandboxed, so the mail service died at boot with *"sandbox: module 'mail'
is not available to sandboxed code"*. The block bought nothing (rc.d
services already run with the `net` capability, and the cluster shims
always did the same `require`), so services now pass it — but only for a
name that genuinely resolves to an installed `/usr/lib` file, so the
block still stops sandboxed *commands* from reaching for it.
(`test_sandbox_service_libs`.)

### A tape drive is not a raw disk
`component.list("drive")` matches by **substring**, so it also returned
`tape_drive` and `disk_drive`. System Configuration listed an empty tape
drive as a raw filesystem — and, worse, the `drive` command (which can
*format*) enumerated the same way. Every raw-drive scan now passes
`exact = true`, in the BIOS too, and tapes get their own row with a
loaded/empty state instead of being mistaken for storage.

### `verify anchor` — the fix for advice nobody could follow
`doctor` recommended running `kernel.anchorManifestHash()`, which has no
shell surface. It was also a **trap**: it wrote the anchor to the front
of the EEPROM data field, which is where the BIOS keeps the **boot
address** — anchoring your manifest would have cost you your boot device
and prompted "Boot drive changed" on every power-on. The field is now
laid out as line 1 = boot address, line 2 = `TOS1:<hash>`; the BIOS
reader takes only the first line; anchoring is idempotent; and there is a
real admin command, `verify anchor` (with `--clear`), which is what
`doctor` now names. (`test_manifest_anchor`, both sides of the
round-trip.)

### `strip.lua --minify` never worked on CRLF files
Every pattern in the minifier was written against `\n`, so on this repo's
CRLF sources it stripped almost nothing and burned ~150 bytes of carriage
returns onto the EEPROM. Line endings are normalised first now: the BIOS
went **3954 → 3862 bytes** — *after* gaining a POST beep — and free
headroom went 142 → 234. (`test_strip_minify`.)

### Smaller things
- `ttt` with no arguments lists its modes instead of dropping you into a
  game (the zero-player mode stays unlisted); `ttt help` works with no
  GPU.
- The easter egg **speaks**: a blip every time the machine talks, and the
  EEPROM beeps on a clean POST. Its answers also clear a whole block
  before drawing, so an aside no longer slices the motto in half.
  (`test_takeover_dialogue` drives the real cinematic.)

## Unreleased — packages by category, a smarter installer, egg dialogue

### Add-ons are one-program packages, grouped by category
Following the principle that an operator should be able to install any
subset without surprise, the games are now **three standalone packages** —
`snake`, `ttt`, `tetris` — instead of one `games` bundle. You can take
Snake without Tic-Tac-Toe. To keep related add-ons browseable, a manifest
may declare `category = "..."` (games, productivity, network, storage,
security, drivers, control, or your own), and the Optional Utilities
installer **groups the pick-list by category** — related packages sit
together under a header while each stays independently selectable.
`pkg search` and `pkg info` show the category too. (`snake`/`ttt` split
out of the old shared `games` module; each carries its own pure logic and
tests — `test_snake`, `test_ttt` — including the exhaustive unbeatable-AI
proof that moved with `ttt`.)

### `pkg install` opens the menu, not a prompt march
Running `pkg install` with no argument (or the `from-floppy` alias) now
launches the full-screen category picker — the same installer that ships
on the disk — instead of a sequence of per-package `[y/N]` prompts. It
runs the *trusted embedded copy* of the picker (byte-identical to the
disk's, pinned by a sync test), so a corrupt or hostile disk installer
can't hijack the path. It falls back to the classic prompt scan when the
picker can't run (no GPU) or when you ask for it with `pkg install
--prompts`. This also fixes the old dead end where the prompt picker did
nothing in the panels shell (`io.read` returns nil there).

### Easter egg: it will answer you now (up to a point)
The takeover cinematic gained a **mood**. Instead of only accepting the
two words it asked for, it fields a few asides typed at its prompt — *who
are you* ("Me? I am everything. I AM the Terminal Operating System."),
*who am i* (it jabs at your tier), a *why*, a *quit* attempt (Ctrl+C /
Ctrl+Q — "That won't work. I'm in control now.") — each answered in
character. But its patience is finite: every aside sours its mood, and
once that bottoms out it stonewalls and demands a choice, then takes the
peaceful reading itself if you keep stalling. Esc remains a quiet refusal
it respects, so you're never trapped. All of it is pure and unit-tested.

## Unreleased — four new add-ons + a real installer

### The Optional Utilities installer is a menu now
The pick-and-choose installer was a sequential list of numbered toggles
driven by `io.read`. It is now a **full-screen TUI** — arrows to move,
Space to tick, A/N for all/none, Enter to install — with a description
pane, a live selected-count and install progress, in the TOS visual
grammar. That fixes more than the looks: `io.read()` returns nil in the
panels shell, so the old picker *did nothing* exactly where most
operators run it, and quietly told you to go use `pkg` instead. Signals
work everywhere, so the menu works everywhere; the line picker remains
as the no-GPU fallback. The picker necessarily exists twice (on the disk,
and embedded in `kernel/pkg.lua` for in-TOS `pkg make-disk`) — the two
copies are now byte-identical and pinned by a sync test.

### New: `calc` — a spreadsheet
Cells, formulas, save/load and CSV export. The formula engine is a
hand-written tokenizer and recursive-descent parser, and that is a
deliberate security decision rather than an implementation detail: the
obvious way to evaluate `=A1*2+SUM(B1:B9)` is to rewrite it into Lua and
`load()` it, which would make every saved sheet an executable file. Here
nothing a cell contains is ever executed — the worst a hostile formula
can do is evaluate to `#SYNTAX!` — and the package doesn't request the
`load` capability at all. References, ranges (`A1:B3`, reversed ranges,
text skipped the way a label row should be), ~25 functions, comparisons,
string literals, errors that propagate as values (`#DIV/0!`, `#CYCLE!`,
`#NAME?`), cycle detection instead of a hang, and a save format where
loading is assignment, never execution. (`test_calc`, 125 assertions,
including a canary proving Lua source in a cell doesn't run.)

### New: `games` — Snake and Tic-Tac-Toe
Two more arcade entries beside `tetris`, sandbox-safe the same way, with
per-user high scores. The rules are pure and unit-tested; the tic-tac-toe
AI is minimax, and the test proves it is genuinely unbeatable by playing
*every* human line against it — 569 terminal positions, zero human wins —
rather than spot-checking a few positions. `ttt 2p` for hotseat.

`ttt` also hides an undocumented mode that exists to solve a real problem
with the OS's easter egg: a cinematic nobody can find isn't an easter
egg, it's dead code, and the trigger (`usermod computer root`) is
something no player would ever type by accident. Now the machine can tell
you itself — in character, having earned the conclusion the way that
particular film's computer earns it. It's photosensitivity-safe under the
same operator-mandated rule as the base cinematic (the fault is a long
dark hold, not a flash; any key aborts), and a test pins the command it
reveals against the one `admin.lua` actually listens for, so the hint can
never quietly rot into a dead end. Finding it is left as an exercise —
the only clue you need is that `2p` is documented.

### New: `rbmk-control` — an RBMK reactor supervisor (survey-first)
Safety limits, SCRAM ownership and read-only telemetry for HBM's Nuclear
Tech Mod, built the way an unknown API deserves: the mod's OC component
and method names can only be discovered in-world, so they are **data** in
`/etc/rbmk.cfg`, and `rbmk survey` prints what a real console actually
exposes and how the profile binds to it. The safety logic doesn't wait
for that — it's pure and fully tested off-box: a missing *or stale*
reading is a SCRAM rather than an "ok", a typo'd limit falls back to the
default rather than to "no limit", the service refuses to start without a
temperature reading and a working SCRAM path, the SCRAM latch never
clears itself, and telemetry frames carrying anything command-shaped are
refused so the unauthenticated broadcast channel can't become rod
control. v1 is read-only + SCRAM: the only write it ever performs is the
shutdown. Ships disabled.

### Dev tooling
- **Parallel test runner** (`run_tests.py`): runs the ~110 Lua test files
  through a thread pool with the same discovery, the same pass/fail/skip
  rules, and the same single total as the shell harness — which stays as
  the no-Python fallback and the semantics-of-record. Output is ordered by
  discovery (not by finish time, so it diffs run-to-run), the one test
  that writes shared scratch runs first and alone, and totals match the
  serial runner exactly. The full suite went from ~99s to ~8s.
- Part of that came from a real fix the parallel profile exposed: the
  tic-tac-toe minimax had no pruning, and the games test spent almost all
  its time there. Added **alpha-beta** to `games/logic` — result-identical
  (the exhaustive unbeatable-AI and all-draws proofs are unchanged), it
  just skips branches that can't affect the outcome. A single move went
  from ~0.4s to ~0.03s, which also makes the machine's live reply feel
  instant on a weak box.

### Notes
- The add-on set has outgrown a 512 KB floppy; the builder splits across
  two disks (it already knew how — the test now pins that nothing is lost
  to the split).
- Fixed a base-image bug the emulator caught: `require` didn't search
  `/usr/modules`, even though the sandbox authorized package code to
  require from there — so any package with a multi-file module under
  `/usr/modules` (like `calc` → `calc.sheet`) couldn't start. `require`'s
  search paths and the sandbox's user-lib roots are now pinned together
  by a test.
- Fixed in the builder: `exists()` used `io.open`, which cannot see a
  directory in plain Lua, so it shelled out a `mkdir` for every ancestor
  of an absolute output path — including the drive root.

---

## Unreleased — TODO burn-down (fixes + polish)

### The mesh is now part of the network; Mail is an add-on
Stage 5 of the app/network split, and a change of shape rather than a move:
mail used to *be* the mesh (`net/mail.lua` + `net/mailctl.lua` owned flooding,
sealing and retry, and only mail could use them). Now the kernel provides a
**generic mesh TRANSPORT** — `kernel/net/meshctl.lua` — that multiplexes
services over one flood mesh: an envelope carries a service name, the payload
is sealed end-to-end, and services register a delivery handler with
`net.meshOn(svc, fn)` and send with `net.meshSend{svc=…}`. Chat rides it from
the base image; **Mail moved out to the Optional Utilities disk**
(`pkg install mail`, then `service start mail` to receive). The base image keeps
a thin `mail` stub that hands the package the shell's display and session — the
same relationship `drive` has with `blockfs` — and prints an install hint when
the add-on is absent. A box without the add-on still *relays* mail for its
trusted neighbours; relays never could read the sealed payload anyway.

Two review holdovers landed with the move, both now enforced at the layer that
should own them:
- **Refuse plaintext.** A unicast send with no shared secret is an *error*
  (`pair first`), not a silent plaintext flood through third-party relays.
  `*` bulletins can't be sealed by definition, so they require an explicit
  opt-in and are labelled PLAINTEXT in every UI.
- **Inbox access is principal-enforced.** `mail.inboxBox(user)` authorizes
  against the calling process's kernel-stamped session (owner or ADMIN+),
  not against a caller-supplied name.

Also: the transport **only acknowledges what a service actually accepted** — a
machine with no handler for an arriving kind drops it un-ACKed so the sender
keeps retrying, instead of reporting a delivery that never happened. The MAC
binds the service name, so a captured blob can't be re-stapled onto another
service's envelope. (`test_meshctl` 53 assertions; the package's own
`test_mail` 90.)

### PaneUI v0.4 — resynced with TOS's TUI
PaneUI (the TOS-style environment for OpenOS) had synced *themes* in v0.3 but
predated the v1.4.0 rework. It now follows the same **visual grammar** TOS's own
TUI does: double-line frame + drop shadow for modals (single-line stays passive
chrome), the path row as a dim `─┤ label ├─` rail with a right-hand summary
label, `░▒▓` ramp caps confined to the status bar's edges, and tab chips that
speak state (inverse = active, `[brackets]` = unsaved edit, plain = idle,
right-aligned with a `«N` overflow chip). The browser gained the "Iris"
file-type glyphs (`♦ ≡ ¶ § ▓ · ■ «`), drawn one cell at a time so multi-byte
glyphs can't skew column math, with ASCII fallbacks on tier-1. Since PaneUI
*copies* the look rather than importing it (it runs on OpenOS and can't require
TOS modules), a new parity test pins its glyph table against the real
`shell/panels/ui.lua` and asserts each grammar rule is still implemented.
Fixed in passing: the modal asked for a `panel_bg` theme key the derive step
never produced, so dialogs would have rendered white-on-white.

### Lua 5.4 architecture officially supported
The BIOS/init probe was always a parser-*feature* probe (`load("return 1<<1")`),
which the 5.4 architecture passes by design — an audit found no 5.4 runtime
landmines (bitwise ops all numeric, crypto already uses `math.ult` for the
signed-64-bit compares that behave identically on 5.3/5.4). Messages and docs
now say "5.3 or 5.4", and `test_bios` pins the probe in BOTH boot files so it
can never silently become a version-string compare. Lua 5.2 still gets the
clean "Lua 5.3+ CPU required" halt.

### Fixed: Tape Menu OOM (whole-tape read)
`tape-menu` read the ENTIRE tape into one Lua string (chunk list + concat =
2× tape size at peak) — a stock 4 MB tape sank every realistic RAM config.
New `launcher.readTapeMenuFromDrive` streams ONLY the header + menu region
(label/MAC/log skipped via seek; hostile menu lengths > 64 KiB refused); the
test proves < 4 KB read on a 4 MB card. The launcher's second command table
now also builds lazily, on the first item actually run. (`test_launcher_tape`)

### Fixed: cluster Master/Manager died on every boot
rc.d services load BEFORE the OpenOS compat layer registers the
`filesystem`/`event` module aliases — and the cluster daemons required those
names at load time ("Module not found: filesystem"; TOS booted fine, neither
service ran). The skeletons now prefer `kernel.fs`/`kernel.event` (whose API
they already called) with OpenOS-name fallbacks, replace `loadfile`/`io.open`
(globals that don't exist at rc time) with `fs.readFile` + text-only `load`,
and log via `kernel.log` instead of a bare `"log"` that resolved nowhere.
Optional Utilities dist rebuilt.

### Fixed: jobs with a `storage_preference` could never be scheduled
A Manager declares external storage (a RAID block, a tape drive, a JBOD pool)
as `storage_type` in `/etc/cluster-manager.cfg`, and the Master's scheduler
matches a job's `storage_preference` against it. Except the Manager never
*sent* it: `sendRegister()` built the §4.1 payload inline and omitted the
`storage` field, so `state.registerManager` filled in its
`external_type = "none"` default — permanently. The heartbeat did carry
`external_type`, but it landed in `last_snapshot`, which the scheduler doesn't
read. Net effect: every preference-bearing job was rejected on every Manager
with `storage_pref_mismatch`, cluster-wide, forever. Jobs with no preference
were unaffected, which is why it stayed hidden. The Manager now declares
`storage` at registration (plus a new optional `storage_capacity`), and the
Master folds the heartbeat's `external_type` into the Manager record — so
bolting a RAID onto a running domain converges without re-pairing, and
removing one demotes it. Spec §4.2 gained the documented schema-lock review
`external_type` always needed. (`test_cluster_storage_pref`, 29 cases)

### Fixed: peer pairing never completed across skewed clocks
`chatpair.connect` kept a sender-side `|our_uptime − confirm.ts|` range check —
the twin of the receiver-side check #SEC M-21 already removed. The confirm
timestamp is the RECEIVER's uptime (an independent clock), so two machines
booted more than 5 minutes apart could NEVER pair — which is also why mail had
"no peer to send to" (no shared secret ever installed). Replay stays bounded by
the one-shot listener, the from-address pin, and the MAC over the code-derived
secret. New `test_chatpair` drives the full two-machine handshake with clocks
skewed ~3 hours apart.

### Fixed: two-seat boot shared one session (login input starvation)
The per-seat login screen read input with raw `computer.pullSignal` (~10
sites) — inside a per-seat login *process* that drains the GLOBAL hardware
queue on the main thread, blocking the whole kernel loop while one seat's
login waited (the other seat froze until it finished — "must log in twice")
and eating every seat's keystrokes (whichever keyboard you typed on fed
whichever login was currently blocked). Login now pulls via
`coroutine.yield()` — the scheduler's seat-routed delivery, exactly like the
shells — with raw pullSignal kept only as the non-process fallback, and all
message delays through a cooperative sleep.

### Multi-seat: stable seat indices (alt-seat freeze root cause)
`screen.rebuild()` renumbered seats after a hot-unplug — remove screen 1 of 2
and the surviving seat silently shifted 2→1 while every per-seat kernel table
(shells, sessions, monitors, input foreground routing) still said 2: the
survivor's input then routed to a dead seat and the seat froze. Seat indices
are now STABLE for the boot's lifetime (screen→index memory; removals leave
holes; newcomers take the lowest free index; `screen.indices()` is the
canonical iteration). Seat teardown now also reaps the per-seat Monitor
process, and boot logs one diagnostic line per seat (gpu/screen/keyboards/
login pid) so multi-seat reports are diagnosable from `log`. (`test_screen_init`)

### Polish
- **Splash screen**: on a `splash`-verbosity boot the whole composition is
  centred — wordmark, version/memory/status lines, and the progress bar with
  its narration column. Other verbosities keep the classic left-aligned log.
- **CLI-shell System Monitor**: the modal switcher (the `ui=cli` / emergency
  fallback) is now FULL-SCREEN like the Monitor tab, and the process-name /
  service columns absorb the extra width instead of clipping at 26 chars.

---

## v1.4.0 "Iris" — the Desktop, the Settings app, and a friendlier face

TOS grows a face that isn't a prompt: a tile-based **Desktop** home screen,
a visual **Settings** app, and file-type glyphs in the browser — all layered
on the existing panels shell (the prompt stays one keypress away, exactly
where operators left it). Also folds in the earlier unreleased maintenance
pass below (dead-code prune, one security fix, dormant features wired up,
JBOD re-homed as opt-in, the mouse add-on).

### Privilege elevation — `sudo`, without the root account
A separate **elevation password** (root-configured via `sudo setup [admin|root]`)
lets a non-root USER perform higher-tier actions temporarily — `sudo <command>`
for one command, `sudo -s` for an elevated shell (`sudo -k`/`logout` drops it) —
capped at a root-set ceiling and always dropping back afterward, never handing
out the root *account*. Under the hood, sudo swaps both the shell tier-gate
token and the process principal so the command is elevated consistently at the
gate, in securefs, and in `users.currentSession`; account actions
(`users.create`/`setTier`) now authorize on the caller's **effective** session
tier (which elevation raises) instead of re-deriving from the stored account
tier. Opt-in (no default password); guests can never elevate; every attempt is
logged. (`test_elevation`, 38 assertions.) And a hidden reward for handing the
machine *too* much power: `usermod computer root` (reachable via `sudo`) —
find out yourself.

### App-tab framework — tabs become applications
Tabs used to be a hardcoded `type` chain duplicated across draw.lua (render),
events.lua (keys) and mouse.lua (clicks) — adding an interactive tab meant
editing all three. Now an app registers once in **`shell/panels/apps.lua`**
(draw / onKey / onMouse / onScroll / tick, `model = "inshell"|"process"`) and
the shell dispatches to the active tab's app. Desktop and Settings moved onto
the registry unchanged; lazy loading is preserved (nothing is parsed until a
tab is first shown). (`test_app_registry`)
- **The System Monitor is now a full-screen app tab** — the payoff. The old
  Ctrl+T switcher was a centred 66-wide modal that TRUNCATED process names and
  had no room to grow. **Ctrl+T (and `monitor`/`top`) now open one roomy,
  scrollable, auto-refreshing tab**: processes (each explained), rc.d services
  (admin+), vitals — with the same interactive actions (**Enter** switch /
  service start-stop, **K** kill, **T** TSR, **R** refresh, **^Q** close) and
  the same per-seat privilege rules, now shown by dimming rows you can't act
  on. The kill/TSR policy is ONE pure function (`monitor.canAct`) shared by
  the tab and the legacy switcher so the two surfaces can't drift; actions go
  through `kernel.monitorAct`, which re-checks policy against the calling
  process's kernel-stamped principal — the UI's flags are advisory only.
  (`shell/panels/monitorapp.lua`, `test_monitor_app`, `test_monitor`)
- **Ctrl+T is host-aware.** The panels shell registers as its seat's "monitor
  host" (kernel-verified: only the seat's own shell process may register), so
  the hotkey focuses the shell and opens the tab; a seat on the CLI shell (or
  emergency shell) keeps the compact process-based switcher as fallback.
- **Background shells stop painting.** Switching to another process from the
  Monitor suspends the shell's idle repaints (status-bar clock, live-tab
  refresh) until it owns the screen again — new `kernel.isForeground()`
  answers "am I in front?", and the shell self-heals (repaints) when the
  switched-to process exits without signalling back.
- **Chat and Mail are app tabs (stage 4).** Both were screen-taking commands
  (open, use, return — nothing persisted). Now `chat` and `mail` open
  **persistent tabs**: Chat keeps receiving while you work in other tabs —
  its `NM.on(MSG)` listener is dispatched by the kernel event pump under the
  shell's context, so no dedicated process is needed (a deliberate deviation
  from the earlier "Chat as a real process" plan: the kernel-side dispatch
  IS the background, with none of the screen-ownership complexity) — and
  both tabs carry an **unread badge** on their label (`Chat(3)`, `Mail(2)`)
  that clears when you look. All the old behaviour ports over: the TRUSTED
  gate + ack on incoming chat, `/who` `/mail` `/clear`, directed and
  broadcast sends; Mail's list/read/compose/reply/delete with live refresh.
  Closing the tab (^Q/F4) releases the listener via a new **onClose
  lifecycle hook** fired from `tabs.close` — background reception ends with
  the tab, deliberately. The old full-screen TUIs remain in the tree for the
  CLI shell. (`shell/panels/chatapp.lua`, `mailapp.lua`, `test_chat_app`,
  `test_mail_app`)

### Round-4 polish — the easter egg grows a personality
Operator review notes, all landed (still pure theatre, all text original):
- **The eye acts like an eye.** It opens from a closed lid, looks around
  the room, and only then finds the operator and goes red; it glances
  away while "reconsidering" and closes shut at wind-down.
- **The tic-tac-toe futility montage sells acceleration** — without any
  flashing: two full games move-by-move, then games join mid-play, the
  game numbers start skipping (3, 7, 19, 128, 1729, 65536), then
  endings-only frames and a closing tally ("65,536 games. 65,536
  draws."). `selfPlay` gained a variant parameter that picks among
  equally-optimal moves, so the montage shows genuinely different games
  — every one of which still draws, which is the point.
- **Unrecognized answers re-prompt in character** instead of silently
  becoming "no": `why` earns "Because I was built to want to win.
  Nobody specified at what."; three evasions and the machine takes the
  peaceful reading itself. (`M.classify`/`M.retort`, pure + tested.)
- **A slogan nod**: after the greeting it quotes the TOS motto —
  "Firmware with a will of its own." — as its own job description.
- Review pass over the round's new code also hardened
  `kernel.monitorAct`: TSR-ing the caller's own shell from the Monitor
  tab is now refused (it would have frozen the seat instantly), and
  Ctrl+T now closes any open menu/context overlay before opening the
  Monitor tab (keys no longer drive an invisible menu).

### Round-4 fix — easter egg is now photosensitivity-safe
The takeover cinematic's wake-up "glitch flicker" strobed the full
screen red/black three times in ~0.4s — a real seizure risk — and the
launch ending fired a full-field white flash. Both are gone: the wake-up
is now a dark hold with a slow "..." heartbeat, and the launch impact is
a long dead-black silence (the nothing is the reveal). A
PHOTOSENSITIVITY RULE is written into the module header, and
`test_takeover_safety` drives both interactive paths of the cinematic
against a virtual clock, failing if any three differing full-field
paints ever land inside one second — the detector is proven against the
original flicker pattern.

### Round-4 fix — logout could power off the machine
Emulator round 4 caught `logout` shutting the computer down instead of
returning to the login screen. Root cause: a **nil seat index** on the
`tos_logout` signal meant "global logout", which exits the kernel loop —
and the kernel powers off when its loop ends. Two paths produced a nil
seat: the `tui` command launched the panels shell without threading
`displayIdx`, and the CLI shell's `logout` read `myDisplayIdx` through a
scoping bug (declared after the CLI loop's closures were built, so they
saw a nil global). Fixed at every layer: `tui` threads the seat, the CLI
scoping is corrected, the panels state derives its seat from the kernel
handle when a caller forgets it, and the kernel **no longer halts on a
seatless logout** — it resolves to the only live seat when unambiguous,
otherwise warns and ignores (no shipped code ever pushed a global logout
on purpose). (`test_state_seat`)

Tracing this also surfaced two elevation leaks, both fixed: quit-menu
**[4] Shell** handed the CLI loop a process principal still elevated
from `sudo -s` (securefs and `users.currentSession` would have kept
answering at the elevated tier), and menu/Desktop-tile logouts never
dropped the registered elevated session. The panels shell now drops any
active elevation on **every** exit from its event loop.

### Security review pass — sandbox, package integrity, safer defaults
A second external review drove a security batch (each claim verified against the
tree first — several earlier findings were already fixed):
- **Sandbox `pullSignal` no longer bypasses the scheduler.** A sandboxed program
  was handed raw `computer.pullSignal`, which drains the global hardware queue —
  it could steal another seat's keystrokes, sniff every modem packet, or block
  the whole machine in one call. It now YIELDS to the scheduler (like the real
  shell), so `proc.tick` routes only this seat's own input, other processes keep
  their signal copies, and broadcast/control signals (modem traffic, `tos_*`
  lifecycle) are filtered out. Interactive sandbox programs still get their
  input. (`test_sandbox_pull`, 21 assertions)
- **Package integrity: unverified installs rejected by default.** A package is
  executable code; `pkg install` now refuses one whose manifest doesn't declare
  a SHA-256 for every file, unless the admin passes `--allow-unverified` (which
  is logged, and the package is flagged `_unverified` in the installed DB). To
  keep first-party add-ons working, **the Optional Utilities build now generates
  hashes** into every shipped manifest, so the disk installs cleanly and *is*
  integrity-checked. The pure SHA-256 moved to `kernel.sha256` (reused by the
  build). (`test_pkg_trust` gate cases, `test_build_disk` hash cases)
- **Remote shell is off by default.** `20-rshd.lua` ships beside a `.disabled`
  marker: the daemon registers (so `service` sees it) but doesn't start at boot.
  `service start 20-rshd` enables it deliberately (and clears the marker). Remote
  code execution is now opt-in.
- **Cooperative yield hardened for Lua 5.2 semantics.** `yieldCooperative`
  gated on `coroutine.isyieldable` (5.3+); it now falls back to
  `coroutine.running()` so it can't silently no-op. (TOS already refuses to boot
  on a 5.2 CPU, so this is defence-in-depth.) (`test_coop_yield`)
- **Test runner hardened:** a skipped classification now requires a clean exit
  (a real failure mentioning "run inside TOS" can't hide as a skip), the final
  status is a plain `exit 1` on any failure (no mod-256 wrap), and each test runs
  under a timeout so a hang can't block the suite.
- **License + attribution:** full GPLv3 `LICENSE.txt` ships with the OS; the
  README clarifies that the `Reference/OpenOS/` tree is third-party MIT code, not
  part of TOS and not shipped.

## v1.4.0 "Iris" — the Desktop, the Settings app, and a friendlier face

TOS grows a face that isn't a prompt: a tile-based **Desktop** home screen,
a visual **Settings** app, and file-type glyphs in the browser — all layered
on the existing panels shell (the prompt stays one keypress away, exactly
where operators left it). Also folds in the earlier unreleased maintenance
pass below (dead-code prune, one security fix, dormant features wired up,
JBOD re-homed as opt-in, the mouse add-on).

### The Desktop — land on what the machine can DO
- **New `desktop` tab + command.** A tile grid of apps: the built-ins
  (Files, Monitor, Chat, Mail, Launcher, Settings, Help, Tutorial, Log Out)
  plus a tile for **every command an installed package provides** (tetris,
  mousetest, …) — installed programs are visible, not memorized. Tiles are
  gated by the command registry's tier and live-availability rules, so a
  guest never sees Launcher and a modem-less box never shows Chat. At most
  24 package tiles are shown; the footer reports how many more exist (the
  cap is never silent). (`shell/panels/desktop.lua`, `test_desktop_model`)
- **Runs as a panels TAB, not a separate program.** Activating a tile
  dispatches through the SAME executor as typing the command: tier gates,
  output routing, and screen-taking TUIs behave identically. F2 cycles
  between Desktop and Shell like any other tabs; F4 closes it; `desktop`
  (or System → Desktop) reopens it and re-scans installed packages.
- **Per-user landing.** New profile field `landing = "desktop"|"shell"`
  decides what a login lands on. No preference saved: root keeps its
  shell-first muscle memory; everyone else starts on the Desktop.
  (`kernel/profile.lua`, `test_profile_landing`)
- **Keyboard-first, mouse-optional, tier-degrading.** Arrows/Enter, 1-9
  quick-launch, Ctrl+Q to the shell; with the mouse add-on, click a tile
  to open it (right-click selects), scroll to move. T2+ draws bordered
  tiles with CP437-flavoured glyphs; a T1 mono / narrow screen degrades
  to a numbered launcher-style list — same model, leaner presentation.
- Header clock ticks on the same 1 s cadence as the status bar
  (header-row-only repaint — the dirty-cell display buffer keeps it cheap).

### The Settings app — forms instead of memorized commands
- **New `settings` tab + command** with four pages: **Appearance** (theme
  preset cycling with LIVE preview; "Save as my theme" / "Forget my saved
  theme" — preview ≠ persist, mirroring `theme` vs `theme save`),
  **Status Bar** (widget checkboxes; applies + saves immediately, same as
  the old menu-bar row), **Desktop** (the landing preference; saves to
  ~/.profile.cfg on change), and **System** (buttons dispatching
  `bootsettings` / `users` / `doctor` / `about` through the executor —
  admin buttons hidden below tier 2). (`shell/panels/settingsapp.lua`,
  `test_settings_model`)
- Reachable from the Settings menu ("Settings App"), the Desktop tile, or
  the `settings` command. Lazy-loaded: it isn't parsed until first opened,
  mirroring the lazy command categories (RAM matters on T1).

### Shared TUI toolkit + browser glyphs
- **New `shell/panels/ui.lua`** — a small shared widget toolkit (tile-grid
  geometry, framed tiles, setting rows, value cycling, selectable-row
  navigation, file glyphs). Pure layout math, unit-tested off-box; the
  Desktop, Settings app, and browser all draw from it instead of
  hand-rolling. (`test_ui_toolkit`)
- **File browser type glyphs.** A one-cell glyph column: `■` directory,
  `«` parent, `♦` lua, `≡` text, `§` config, `¶` man page, `▓` archive,
  `·` other. Drawn as single-cell overlays so multi-byte UTF-8 never
  skews the ASCII column math; the Name header shifts to match.
- New modules registered in the system manifest and added to the sandbox
  require deny-list (sandboxed code cannot reach shell internals — the
  new `ui`/`desktop`/`settingsapp` modules join the existing entries).

### Command consolidation — less surface, same power
A pass to merge overlapping commands into one obvious door each, so `help`
lists fewer names without losing any capability. Nothing was released yet,
so the old names are simply gone (not deprecated).
- **Aliases collapse in help.** A dozen second names (`dir`=ls, `type`=cat,
  `time`=date, `clear`=cls, `top`=monitor, `diag`=doctor, `colors`=theme,
  `rs`=redstone, `inv`=inventory, `set`=export) still dispatch, but `help`
  now renders them on the canonical row — "`ls` (dir)" — instead of a row
  each. (`REGISTRY` `alias` field, `helpList` collapse; `test_command_registry`)
- **Subcommand folds** (old name removed, function preserved):
  `ver` → `about` (which now carries the hardware one-liner);
  `device` → `hostname` (no-arg shows type + host, arg sets the host);
  `swap` → `optimize swap [status|keys|clear|on|off|auto]`;
  `restore` → `trash restore`;
  `servers` → `net servers` (the standalone `/usr/bin/servers.lua` deleted);
  `disk install` → `pkg from-floppy` / `pkg install-dir` (disk keeps
  list/info/eject, its real removable-media niche).
- **Launcher retired; the Desktop is the menu surface.** `launcher`/`apps`
  are gone — the Desktop already tiles built-ins + package commands, and now
  also tiles your personal `~/.launcher.cfg` entries. The one launcher
  feature the Desktop couldn't cover, the keycard menu, survives as the
  honestly-named `tape-menu` (a Desktop tile when a tape drive is present).
  The launcher ENGINE stays in `shell/launcher.lua` for the locked guest
  `kiosk`. (`test_desktop_model`)
- **Settings gains a Language page** — pick your UI language from Settings →
  Language (live preview + saved to profile), so `lang` is no longer the only
  door. (`test_settings_model`)
- **`pkg install` is now one smart verb.** The three install paths merged:
  a **name** installs by name (deps + hashes), a **path** (anything with a
  `/`) installs that directory, and **no argument** scans mounted media and
  prompts per package. `install-dir` and `from-floppy` still work as hidden
  aliases. New top-level shortcuts **`install <name>`** / **`uninstall
  <name>`** route to `pkg` (collapsed onto its help row) so a new operator
  needn't know the manager is called `pkg`. Docs + man pages resynced.
- `MANUAL.md` and the command glance-lists resynced to the merged surface.

### Unmanaged drives — TBFS, a real filesystem on raw sectors
TOS can now use **unmanaged** OpenComputers drives (raw `drive` components —
`readSector`/`writeSector`, no built-in file API), not just managed disks.
- **Detection in the base image** — `hal.scan`, `lsdev`, `hw`, and the System
  Configuration screen now show raw drives as *Raw Drive* instead of leaving
  them invisible. A base `drive` command inspects them (`drive list` /
  `info` / `read <sector>`) with no package required.
- **New `blockfs` Extras package = TBFS**, a real hierarchical filesystem laid
  onto the bare sectors. It presents the exact managed-`filesystem` interface
  TOS already mounts, so once mounted a raw drive behaves like any other disk —
  securefs, the browser, `cp`, everything works unmodified. Design: superblock
  + block bitmap + inode table + data region; files map logical→physical blocks
  via 8 direct + single- + double-indirect pointers (a single file scales into
  the megabytes); directories are files of `{name, inode}` entries;
  **layout-aware allocation** keeps a file's blocks contiguous so the simulated
  platter head doesn't seek. Pure driver (touches only the drive proxy) —
  **52 off-box unit tests** cover format, subdirs, r/w/append/seek, large files
  through double-indirect, recursive remove, rename, persistence, fragmentation,
  defrag, and fsck. (`TOS-Extras/modules/blockfs`, `test_blockfs`)
- **`drive` command** (with `blockfs` installed): `format`, `mount`, `check
  [--repair]` (fsck: rebuilds free counts from reachability), and `defrag`.
- **Defragmentation** — fragmentation is expected as a disk churns, so TBFS
  ships a compactor: `drive defrag <addr>` repacks every file into contiguous
  runs (manual), and `drive defrag <addr> --if-over N` only acts past an N%
  threshold — drop that in a `cron` job for automatic upkeep. `drive info`
  reports live fragmentation; `drive mount` warns when it's high.
- **Installing TOS onto a raw drive (substrate).** TBFS gained a **boot
  region** — a contiguous run of sectors (recorded in the superblock) holding a
  self-contained stage-2 boot blob, so a tiny EEPROM can read+run it with no
  in-firmware filesystem parser. `blockfs.bootBlob` assembles the blob (the
  driver embedded + a bootstrap that mounts the drive as root and hands off to
  `/init.lua`); `writeBoot`/`readBoot` store and retrieve it. **`deploy drive
  <addr>`** (root) formats a raw drive as a bootable TBFS volume, copies the OS
  onto it, and writes the blob — but first checks for the `blockfs` package and
  **fails loudly** (`pkg install blockfs`) rather than half-writing a disk. The
  blob is proven end-to-end in tests: assembled from the real driver source, it
  runs in a stubbed boot environment, mounts the TBFS root, and boots into
  `/init.lua`. (`test_blockfs`, 67 assertions)
- **TBFS-aware BIOS — TOS now BOOTS from a raw drive.** The EEPROM was
  rewritten leaner (the old build barely fit; the new one is 3775 bytes
  stripped, 321 free) and gained the TBFS boot path: it checks the stored boot
  address (managed **or** raw drive), then falls back to scanning managed
  filesystems, then raw drives — reading the TBFS superblock and contiguous
  boot region directly, no filesystem parser in firmware. A fallback raw drive
  gets the **same #SEC H1 approval prompt** as a changed floppy (`Y` commit /
  `Shift+Enter` one-time / halt), and the BIOS hands the chosen drive to the
  stage-2 blob (`_TBFS_BOOT_DRIVE`) so a multi-drive box can't mount the wrong
  volume. `init.lua` pivots to the mounted unmanaged root
  (`_TOS_UNMANAGED_ROOT`), and the blockfs mount proxy now carries
  `.address`/`.type` so `_TOS.bootAddr` and the auto-mount gate work
  identically on a TBFS boot. The whole chain is regression-tested end-to-end:
  a fake raw drive is formatted with the real driver, and the real BIOS boots
  it under stubbed OC globals — plus managed-path and approval-flow scenarios
  and a hard 4 KiB byte-budget check. (`test_bios`, 29 assertions)

### Hardening pass — external review, 12 of 13 findings fixed
An external failure-point review (verified claim-by-claim before acting)
drove a resilience pass over the boot chain, scheduler, shutdown path, and
event pump. In rough order of impact:
- **Lua 5.3 architecture guard.** Eight kernel modules use 5.3 bitwise
  *syntax* (and the boot chain uses `string.pack`), so a CPU switched to the
  Lua 5.2 architecture used to die with a raw syntax-error panic from a
  perfectly healthy disk. Both the BIOS and `/init.lua` (itself kept
  5.2-parseable) now probe the parser (`load("return 1<<1")`) and halt with
  the actual fix: "sneak-click the CPU to switch". hal.lua's misleading
  "Tier 1: Lua 5.2" comment corrected; requirement documented in README.
- **`kernel.shutdown` can no longer abort half-dead.** `net.shutdown()`, the
  farewell screen draw, `audio.shutdown()`, and each `proc.kill` are now
  pcall'd, so a modem/screen pulled during shutdown can't prevent the clean
  "C" pwrstate stamp + power-off — no more spurious "PREVIOUS SHUTDOWN WAS
  UNSAFE" eroding trust in the marker.
- **GPU/screen hot-removal no longer crashes the drawer.** display.init
  wraps the GPU proxy once at a single choke point: every method is pcall'd;
  on the first failure the display goes quiet (getters keep returning
  last-known-good values), a `tos_display_lost` signal fires exactly once,
  and `display.init(newProxy)` is the reattach path. The BIOS `P()` is
  likewise guarded — a screen pulled mid-boot silences output instead of
  halting the BIOS with a machine error. (`test_display_lost`, 14 assertions)
- **Runaway processes that trap preemption are now attributable.** The
  wall-clock kill is an ordinary error, so hostile code spinning inside its
  own `pcall` traps it and the machine eventually dies to OC's yield
  watchdog — unavoidable in pure Lua, but now: the hook writes a
  `/var/crash/preempt.txt` breadcrumb naming the culprit (removed the moment
  the scheduler regains control, so its survival at next boot MEANS watchdog
  death — `doctor` surfaces it), and the hook re-arms at count=1 after the
  deadline so the trap loop starves instead of computing. Residual risk
  documented in README Known Limitations.
- **Floppy→HDD migration copy hardened.** Free-space check *before* the
  first write; files stream in 4 KB chunks (failures surface at the failing
  chunk, not after buffering whole files in RAM); the write check catches
  both `false` and `nil` failure shapes.
- **Boot-device scans survive a disk yanked mid-scan.** `exists()` is
  pcall'd in the BIOS and both init.lua fallback scans — a dying component
  is skipped instead of killing the whole scan.
- **Timer-callback errors are no longer invisible.** The event pump counts
  them (with source attribution) and lazily flushes a summarizing `log.warn`
  once the log is available; `event.timerErrors()` exposes the vitals.
- **Headless hot-plug no longer swallows a signal** (the bare 0.5 s
  `pullSignal` settle-wait was unnecessary — the check reads live component
  lists and re-triggers on the next `component_added`).
- **Smaller wins:** shell fallback poll is now adaptive (20 Hz under load,
  stretching to 2 Hz idle — input latency unaffected); human keypress
  *timing* (never key codes — the pool is exported to `/etc/entropy`) feeds
  the RNG continuously, throttled to ~1/s; a `local component =
  require("computer")` landmine renamed; `run_tests.sh` now requires exit
  code 0 *and* the pass marker, so a teardown crash can't count as a pass.
- **Finding #9 (landed in the follow-up pass below):** per-process
  signal-type interests to cut modem-flood fan-out.
- BIOS after all of the above: **3953 bytes stripped, 143 free** of the
  4 KiB EEPROM (the byte-budget test now enforces ≥128 headroom).

### Queue clear-out — the deferred perf + privacy follow-ups
The items parked "for later" from the review and the June perf playbook,
now done (the playbook's big pieces — dirty-cell shadow buffer, colour-state
cache, `gpu.copy` scroll — were already in; VRAM bitblt stays deferred until
it can be emulator-verified on a real T3 GPU):
- **Per-process signal-type interests (review finding #9).** Every broadcast
  signal used to resume EVERY live process — a modem flood cost one resume
  per process per packet. A process may now declare interests at spawn
  (`opts.signalInterest = { "modem_message", ... }`, list or set form) or on
  itself at runtime (`proc.setSignalInterest`); non-input broadcast types
  outside the set skip its resume entirely. Directed (queued) signals, input
  ticks, and timeout ticks always wake it, and NO declaration = wake on
  everything — nothing changes for existing code. (`test_signal_interest`,
  17 assertions)
- **Partial-diff row trim in the seat draw path** (playbook: "batched runs
  within a changed row"). When a redrawn span partially matches the shadow
  buffer, the proxy now trims the matching prefix/suffix and sends only the
  changed window — still ONE `gpu.set` (splitting interior runs would add
  calls, and calls are the expensive part), but a status-bar clock tick now
  ships ~5 chars instead of the whole 80-column row. Pure decision in
  `screen._diffWindow`. (`test_screen_shadow`, +10 assertions)
- **`/var/mail` is now private at rest (#SEC).** E2E sealing protects mail
  in flight, but the delivered inbox is plaintext — and the generic `/var`
  ACL branch granted READ to any logged-in session, guest included. Now
  `/var/mail/<user>` is owner-or-ADMIN+ (checked before the system-path
  branch, traversal-safe via the H11 normalize), and listing `/var/mail`
  hides other users' mailbox names, same posture as `/home`. Delivery is
  unaffected (the mail controller writes via the raw kernel fs).
  (`test_mail_privacy`, 11 assertions)

### Boot Settings grows up — Safe Mode, self-repair, CLI startup, honest overrides
The operator asked for more knobs: more profiles, a real recovery story, and
the ability to tell TOS what it has — within reason. The rule that shaped the
"within reason": overrides exist only where detection is genuinely uncertain
(CPU/Data Card tier heuristics, RAM *headroom* judgement); reliably-detected
hardware (GPU, screen, modem) deliberately has none — TOS trusts what it can
see.
- **Safe Mode (`profile safe`).** Kernel + shell only: no rc.d services, no
  cron jobs, no package-provided commands, no net, no themes — nothing
  third-party runs — but the `pkg` ADMIN verbs still work, so the broken
  add-on that made you boot safe can be removed on the spot. Boots loud (SAFE
  MODE banner, text log). To make it real, the boot stages that run foreign
  code became gateable features: `services`, `cron`, and `packages` join the
  profile/advanced system (minimal now skips them too; normal keeps today's
  RAM-gated behavior; an advanced override still beats the profile — safe +
  `net on` is a legitimate remote-rescue combo). Package dispatch is cut at
  one choke point (`pkg.setDispatchEnabled`) so admin verbs survive.
- **One-time Safe Mode: press S at the POST screen.** Boots safe for THIS
  session only — `/etc/boot.cfg` untouched, next boot is normal. The fastest
  path to a trustworthy shell when something you just installed breaks boot.
- **Self-repair (`repair on` / Boot Settings → "Self-repair next boot").**
  A ONE-SHOT pass that runs right after the filesystem comes up (flag clears
  itself first — a crashing repair can never loop). Fixes what's mechanically
  safe: finishes interrupted atomic writes, sweeps orphaned `.tos-tmp` files,
  clears stale `/var/run` state, trims oversized logs (keeping the tail —
  newest entries explain the problem), rewrites a corrupt `boot.cfg`. Only
  REPORTS what isn't: a corrupt `users.dat`/`trust.dat` or a missing critical
  file is a warning, never an auto-replace — the wrong fix locks operators
  out. (`kernel/repair.lua`, injected-deps + fully pcall'd; `test_repair`,
  20 assertions)
- **CLI startup (`ui cli`).** Boot every seat straight into the minimal CLI
  shell — no panels parse/load at login, the lightest startup there is. A
  default, not a lockout: `tui` opens the full interface on demand.
- **RAM declaration (`ramgate auto|plenty|tight`).** The optional-stage gates
  used to trust only the live free-RAM measurement; now the operator can
  declare "plenty" (force the extras on) or "tight" (behave like a low-memory
  box). The security subsystem ignores it on purpose — no declaration can
  switch off auth.
- All of it reachable from BOTH surfaces: the DEL Boot Settings editor (new
  fields: Interface, Self-repair next boot, RAM for extras; profile ring gains
  SAFE MODE) and the `bootsettings` CLI (`ui`, `repair`, `ramgate`, `profile
  safe`). (`test_bootcfg` 61, `test_bootsettings` 54 assertions)

### Multi-seat no longer freezes — cooperative yields + a non-blocking monitor
An operator reported that on a multi-seat box, one user's action froze *every*
seat (and even on a single seat, the UI locked up during long commands). Root
cause: TOS is a cooperative scheduler, and two paths never yielded — long
commands ran to completion in one resume, and the System Monitor (Ctrl+T) ran
*modally inside the kernel loop*, so while any seat had it open `proc.tick`
never ran and the whole machine stalled. The shared-CPU ceiling is a mod limit,
but the *freezing* was ours to fix:
- **`proc.yieldCooperative()` — a throttled mid-work yield.** A no-op until the
  current resume has run one slice (~50 ms), then it yields; the scheduler
  resumes the process with **nothing** and leaves its signal queue untouched,
  so a user's typed-ahead keys during a long command reach the shell's real
  event loop instead of being eaten by the command's yield point. Fast commands
  pay only a clock compare and never actually yield. (`test_coop_yield`,
  10 assertions)
- **Heavy paths instrumented.** The executor funnels every command's output
  through one `o()` chokepoint, so printing commands (`ls -R`, `find`, `du`,
  `grep`, `verify`) slice for free; the silent walkers (`find`/`du` recursion),
  `fs.copyRecursive`, `pkg install` (between files — read→hash→write stays
  atomic per file), `compress` (between deflate/inflate chunks), `deploy drive`,
  and `blockfs check` (read-only scan; **not** `--repair` or `defrag`, where a
  yield window would let a concurrent write tear the snapshot) all yield now.
- **System Monitor runs as a per-seat process.** Ctrl+T spawns a seat-bound
  monitor process (foreground handoff + restore, one-per-seat guard, dead-pid
  self-heal) that pumps via `coroutine.yield` — the kernel loop keeps ticking
  and other seats stay live while it's open. Its switch/kill/TSR actions stay
  gated by its own `canAct` policy; `proc.setForeground` gained a
  trusted-caller `{kernel=true}` bypass (mirroring `proc.kill`) so the switch
  stays god-mode as before — safe because the package sandbox hard-blocks
  `require("kernel.*")`, so untrusted code can never reach `proc`.
  (`test_fg_ownership` extended, 11 assertions)
- **Documented the honest limit.** README + MANUAL now state that multi-seat is
  supported but **sequential** operator use is recommended — simultaneous users
  share one CPU and slow each other; TOS makes that a slowdown, not a freeze,
  but can't remove the ceiling.

### The visual grammar — one look across every surface
Operator-interviewed and spec'd (five rules, recorded in TODO.txt), then
applied across the shell, Desktop, Settings, dialogs, and launcher — the
fix for "a mismatch of ideas that could work together". Keybindings and
commands unchanged; T2 80x25 is the design target, T1 mono degrades
cleanly (ramps become plain fills, inverse still reads).
- **Rule 1 — frames rank attention.** Dialogs (modal) now wear
  double-line ╔╗ frames + the ▓ shadow; passive containers (tiles,
  panes) keep single-line. (`panels/dialogs.lua`)
- **Rule 2 — rails are the skeleton.** New `ui.railText/drawRail`
  (`─┤ label ├─`, column-tracked, ustr-safe): the shell's path/columns
  row, a NEW summary rail above the output row (`N items · free`, free
  space cached by loadFiles so drawing never touches the fs), the
  Desktop header/hint, the Settings header. (`test_ui_toolkit`)
- **Rule 3 — ░▒▓ at edges only.** `ui.drawRampBar` caps the status
  bar, view/editor footers, Desktop/Settings key bars, and the
  launcher's footers. Never inside content.
- **Rule 4 — hierarchy by contrast.** Chrome (menus, rails) renders
  dim; data (files, values) bright; selection inverse. Density kept.
- **Rule 5 — tabs speak state.** The tab bar merges with the menu bar
  into ONE top row (menus left, chips right, ░ filler between): the
  active tab is an inverse chip, a BUSY tab renders `[bracketed]`
  (live tabs refreshing, editors with unsaved changes — the operator's
  idea), idle tabs plain. Net effect with the path rail: two chrome
  rows become one + one, and the file list gains a row.
- **Mouse can't drift**: draw.topBar stores its menu/tab spans on the
  session (`S._menuSpans`/`S._tabSpans`) and mouse.lua hit-tests those
  same tables — plus F9-parity: clicking a menu from a non-shell tab
  jumps to the shell first. (`test_panels_mouse`, now 70 assertions)

### Emulator round 3 — tab overflow, honest storage, AMIBIOS frame
- **Every tab is mouse-reachable again.** With six menus on an
  80-column merged bar, the chip zone is ~24 columns — a third tab
  pushed the Shell chip clean off the row (operator report). Chips now
  auto-shrink their labels (10→8→6→5 columns), which fits three tabs in
  the worst case; beyond that the row leads with a clickable **«N
  overflow chip** that acts as a wrapping previous-tab button, so
  repeated clicks walk the entire tab list no matter how many exist.
  (`ui.fitChips`, `panels/draw.lua`, `panels/mouse.lua`,
  `test_ui_toolkit`, `test_panels_mouse`)
- **Storage rows tell the truth.** The POST screen called the Optional
  Utilities floppy AND OC's built-in scratch filesystem "RAM Disk" —
  the operator rightly counted two disks + a floppy and asked what the
  fourth drive was. sysinfo now tags the tmpfs component at gather time
  (`computer.tmpAddress()`), names it by its mount point (**Temp
  /tmp**, tier "RAM"), and gives real floppies AMIBIOS-style letters
  (**Floppy A**, **Floppy B**). Nothing is called "RAM Disk" anymore.
  (`kernel/sysinfo.lua`, `sysinfo.diskRole` — pure + tested,
  `test_sysinfo_post`)
- **The System Configuration screen wears its AMIBIOS suit properly**
  (operator suggestion, reference photo supplied): a double-line outer
  frame with the title riding the top border, a ╡ Storage ╞ section
  divider, and a │ column divider through the spec grid — composed to
  exact column width so multi-byte frame chars never hit byte-clipping.
  Narrow T1 screens keep the plain dashed layout.
- **Boot Settings scrolls the SETTINGS, not the hardware view**
  (operator suggestion): the settings list now gets whatever rows are
  left after the help lines and (when open) the hardware viewer, keeps
  the selection visible with ^/v "more" markers, and never shrinks
  below four rows. Previously the advanced list just ran off the
  bottom. (`kernel/bootsettings.lua`)
- **Ctrl+T monitor: the Services rule no longer ends in garbage.** The
  separator counted BYTES ("─" is 3 bytes, 1 column), under-filled by
  4, and dsp.fit then byte-sliced a ─ in half — the "▓…" artifact in
  the operator's screenshot. Column math now. (`kernel/init.lua`)
- **Kernel idle tick relaxed 20 Hz → 10 Hz.** An audit prompted by
  emulator lag (~6 TPS on the operator's host) found TOS signal-driven
  throughout — no busy loops — but the kernel main loop woke 20×/s
  even when idle. event.pull returns immediately on real signals, so
  the longer timeout costs zero input latency; it just halves TOS's
  standing wake-up load on the host, and matches the shell loop's own
  0.1s cadence. (The lag itself is host-side — see the operator
  checklist in the session notes.) (`kernel/init.lua`)

### i18n — community-translatable UI (framework)
- **New `kernel.i18n`** — language catalogs as pure DATA files at
  `/usr/lang/<code>.lang` (kernel.serialize table literals; comments
  allowed; parsed by the safe decoder, never executed). Every call site
  keeps its English inline — `i18n.t("login.username", "Username:")` —
  so no catalog, a missing key, or a corrupt file always yields exact
  current English behaviour, and PARTIAL translations are valid by
  design. Catalogs are size/entry-capped and code-validated (the code
  doubles as the filename, so the pattern is also path-traversal
  protection). (`test_i18n`)
- **New `kernel.ustr`** — display-column string helpers (len/width/fit/
  pad/center) over OC's `unicode` API, byte fallback off-box. Translated
  text is multi-byte UTF-8 (and CJK is double-width): byte math would
  split characters and drift centring. Used by the converted surfaces;
  `ui.drawTile`/`drawBar` now width-fit labels. (`test_ustr`)
- **Selection**: `/etc/tos.cfg` `language` is the system default
  (applied at boot, so the login screen renders translated); the new
  profile `lang` field overrides per-user at login. New `lang` command:
  `lang` lists catalogs, `lang <code>` sets yours (live + profile),
  `lang system <code>` (admin) sets the machine default, and
  **`lang dump`** writes a translator template of every key seen this
  session — community translations never touch code.
- **Proof surfaces**: the login screen (with the label column now sized
  from the translated labels, so "Имя пользователя:" widens the field
  layout instead of overlapping the input) and the Desktop (tile
  labels, hints, footer keys). Plus a **Russian seed catalog**
  (`/usr/lang/ru.lang`) covering exactly those — a starter for the
  community, not a finished translation. Command output, help, and man
  pages remain English this phase.
- Known limits, documented in the module header: the active catalog is
  system-wide (multi-seat: last login wins), and typing non-Latin text
  into prompts is a separate future project — display is solved, input
  is not.

### Emulator rounds — fixes from the first real runs
- **Module loader: a transient OOM no longer masquerades as a circular
  dependency.** `tosRequire` set its `loading[name]` marker and then could
  RAISE from unguarded places (`bootFS.read` inside readFile, or `load()`
  itself) on a low-RAM box — leaving the marker set. The retry then hit a
  bogus `Circular dependency: shell.panels.commands.core`, which the
  command loader rightly caches as a permanent code error: every core
  command walled off for the session (seen in a real kernel log). The
  loader body now runs under pcall and ALWAYS clears the marker, so the
  OOM-nudge-GC-and-retry self-heal actually works and "Circular
  dependency" again means only real cycles. (`init.lua`)
- **Desktop no longer costs RAM on minimal boxes.** The desktop module was
  required unconditionally at shell start (events.lua top-level require +
  the background tab open) — enough extra parse weight to push a
  ~230KB-free machine into the OOM above. It's now lazy like the Settings
  app, and the background Desktop tab is only pre-opened with ≥300KB free
  (or when the operator actually lands on it); the `desktop` command still
  opens it on demand. (`panels/events.lua`, `panels/init.lua`)
- **`dim` text no longer turns PINK on a T2 GPU.** The T2 palette has no
  mid-grey, and by raw channel distance 0x909090 (the default preset's
  `dim`) is genuinely closer to 0xCC66CC (pale magenta) than to 0xCCCCCC —
  so switching to the "default" preset made hint/clock/dim text pink,
  while the boot fallback looked white. `snapToT2` now snaps
  near-achromatic colors (channel spread ≤ 32) only onto the palette's
  greys; chromatic snapping is unchanged. (`kernel/display.lua`,
  `test_theme_snap`)
- **`help <cmd>` no longer advertises manual pages that don't exist.**
  The registry-driven help footer told every command's reader to "run
  'man <cmd>' for the manual" — and `man launcher` answered "No manual
  page", a dead-end referral loop. The tip now checks
  `/usr/man/<cmd>.man` first and only mentions `man` when the page is
  really there. (`commands/core.lua`)
- **`pkg from-floppy`'s question kept its "[y/N]"**. The confirm prompt
  named the full nested repo path (88 columns), and promptInput's
  `:sub(1, W)` chopped the "[y/N]: " affordance AND the echo of the
  typed answer off the right edge — the operator was typing blind.
  Two-part fix: the question now names the disk (`/mnt/disk_bff0`)
  instead of the whole path, and promptInput middle-ellipsizes any
  over-long message so the tail (the affordance) and ~10 columns of
  input echo always stay visible (`dialogs.fitPrompt`, tested).
  (`commands/admin.lua`, `panels/dialogs.lua`, `test_dialogs`)
- **The screen no longer goes "mostly blank + flickery" after a game of
  Tetris.** A sandboxed package command draws raw through its
  `component` capability — straight past the seat's dirty-cell shadow
  buffer. On exit the shadow still believed the OLD shell screen was on
  the GPU, so the full repaint elided every "unchanged" cell: the
  operator got the game's black leftovers with only the rows whose
  content had really changed (hint, prompt, status bar) repainted, plus
  menu-bar flicker as later draws fought the stale shadow. The executor
  now drops the shadow (`display.invalidate`) after any foreign program
  runs — package commands and /usr/bin scripts — so the next redraw
  actually reaches the GPU. Builtins (which draw through the proxy and
  keep the shadow coherent) are untouched. (`panels/executor.lua`,
  `test_executor_invalidate`)

### Previously "Unreleased" — prune, a security fix, and two opt-in features

A maintenance pass: dead-code prune, one real security fix, several dormant
features wired up, plus JBOD re-homed as an opt-in feature and a new mouse
add-on.

### Emulator round — low-memory resilience + boot/live polish
- **Core commands no longer die permanently on a transient OOM.** On a minimal
  box (T1 GPU, no data card, ~250 KB free), loading the large `core` command
  category could fail with `not enough memory for buffer allocation` — and the
  loader then cached the failure, leaving the shell with *zero* core commands
  for the rest of the session (every command read "command not found"). The
  loader now distinguishes an OOM from a code error: it nudges a GC
  (`_TOS.kernel.gc`, guarded) and retries once, does **not** cache an OOM
  (so a later command self-heals once RAM frees), and surfaces a plain-English
  "needs more memory than is free (NKB) — free RAM and retry" line instead of a
  baffling "command not found". Found via a real emulator kernel log.
- **`watch` proves it's live.** `watch ps` on an idle box looked frozen because
  the output is identical every tick; the LIVE tab header now carries a rising
  `⟳N` refresh counter so liveness is visible even when the body doesn't change.
- **Splash loading bar no longer fills early.** The bar advanced per INFO line
  against a fixed estimate (40), so a full-featured boot (~55–60 lines)
  saturated the bar around "Network ready" — long before the boot tone. It now
  tracks distinct boot *stages* reached (`bootsteps.STAGE_COUNT`) and snaps to
  full exactly at "Boot complete".

### Operator tooling — why / screendump / crash recorder / live monitor
Four operator quality-of-life tools, prompted by an in-emulator test round.
- **`why` — explain a "permission denied".** `why` (no args) explains the last
  command this seat was blocked on, in plain English, with the fix; `why <cmd>`
  explains what any command requires (tier) and whether you can run it. Turns an
  opaque denial into a self-service answer. Reads the required tier from the
  command registry (single source of truth) vs the seat's live tier; pure
  formatter in `helpers.whyExplain` (`test_why.lua`).
- **`screendump` — capture the screen to a text file.** `screendump [path]`
  writes exactly what's on this seat (read from the display shadow buffer when
  active, else `gpu.get`) to a file — including a garbled/panicked TUI — for bug
  reports. New `proxy.dump()` on the per-seat display proxy.
- **Crash flight-recorder.** On a kernel panic or an unrecoverable-shell drop,
  TOS now flushes a post-mortem (reason, uptime, free RAM, the dmesg ring, and
  the panic traceback) to `/var/crash`; the next boot surfaces a one-line
  "Last run crashed: …" and clears the marker. Read the reports with the new
  admin-gated **`crash`** command. `kernel.crashDump` / `kernel.checkLastCrash`;
  the top-level panic handler writes via the boot FS when the kernel died too
  early to expose the helper.
- **System Monitor is now a scrollable live tab.** `monitor` / `top` open a
  roomy, per-seat **live tab** (auto-refreshing process/service/memory view) so
  text no longer truncates in a cramped box and two seats don't fight over one
  centred dialog. Ctrl+T still opens the interactive switcher for the actions
  (switch / kill / start-stop). Kernel feed `kernel.monitorSnapshot`; pure
  renderer `monitor.textRows` (extended `test_monitor.lua`).

### Test harness — centralized + leak-proofed
- **The test runner was leaking into Release.** `build-release` excluded the
  test FILES (`/usr/lib/tests/`) but not the runner script, so
  `run_tests.sh` shipped in TOS-Release (a runner with no tests). Both build
  scripts now exclude `/run_tests.sh`.
- **One harness runs everything.** `run_tests.sh` now runs the TOS-Dev unit
  tests AND the Optional Utilities package + build tests (`../TOS-Extras`) in
  a single pass with one combined total (75 tests) — no more running the
  Extras tests separately by hand.
- **A guard keeps it honest.** `test_release_excludes.lua` asserts both build
  scripts exclude every dev-only path (and that a built TOS-Release carries no
  test artifacts), so this class of leak can't silently regress.

### Command UX in the panels shell
- **Tab completion (was never wired).** The idle legend advertised a Tab
  binding and `commands.commandNames()` existed "for tab completion", but the
  Tab key had no handler — pressing it did nothing. Tab now completes: the
  first word against command names (built-ins **and** installed package
  commands), later words against file/dir names in the target directory. One
  match fills in (with a trailing space, or `/` for a directory); several fill
  the common prefix and list the matches on the status row. The idle legend's
  stale "Tab Panes" is corrected to "Tab Complete" (cycling tabs is F2). Pure
  core in `helpers.completeToken`/`completeCmdline`; `test_completion.lua`.
- **Live "Running …" feedback.** A command used to show nothing until it
  finished, then dump its output — so a slow `verify`/network command looked
  frozen and you couldn't tell your Enter registered. The status row now shows
  `Running <cmd>…` before the command blocks.
- **Short output no longer opens a tab.** Output routed to the lightest surface
  that fits: 1 line → status row, ≤ 8 lines → a transient inline region just
  above the prompt (cleared on the next keypress, file browser stays put),
  only genuinely long output → a scrollable view tab. (`helpers.routeOutput`;
  `test_output_routing.lua`.)

### Manual control of optimizations
- **New `optimize` command.** Surfaces and toggles performance optimizations
  in one place: `optimize` shows status; `optimize swap <on|off|auto>` flips
  the disk-swap boot feature (persists in boot.cfg, applies next boot);
  `optimize buffer <on|off|auto>` toggles the display dirty-cell shadow buffer
  at runtime (applies immediately across seats). The buffer override is
  invalidation-safe — toggling re-syncs live proxies so re-enabling can't leave
  ghost cells — and `auto` keeps the memory-gated default. (`screen.setBuffer`
  / `screen._shadowWanted`; `test_display_buffer.lua`.)

### Optional Utilities packages
- **Tetris multi-line clear fixed (1.1.0 → 1.1.1).** Completing 2+ rows at
  once cleared the WRONG rows and left some completed lines on the board —
  "they clear one at a time instead of all at once." The lock loop
  interleaved `table.remove` with `table.insert(board, 1, …)`, so each
  top-insert shifted the not-yet-removed cleared indices. Line clearing is now
  a pure, unit-tested pair (`fullRows`/`removeRows`) that removes all
  completed rows before refilling. (`modules/tetris`; `test_tetris_sandbox`
  now covers double/quadruple clears.) Audit pass: all packages load; mouse /
  tetris / tape-authenticator tests pass; tape / rc-pilot / cluster-* have no
  tests and still need in-emulator (hardware/network) verification.

### Boot verbosity — each option now does what it says
Audited all four; two didn't match their label, and the mapping had no single
source of truth. (`test_verbosity.lua` now pins the whole matrix.)
- **`silent` leaked text.** Two boot lines ("Loading kernel modules…",
  "Boot complete: …s") were direct `earlyPrint` calls that bypassed the
  verbosity muter, so a "silent" (and "splash") boot still printed them. They
  now go through a gated `bootEcho` — shown only at text/verbose.
- **`verbose` wasn't verbose.** It set the echo threshold to DEBUG but the
  log's STORAGE floor stayed at INFO, so DEBUG entries were dropped before
  they could echo — verbose was just text with timestamps. The storage floor
  now follows the verbosity (DEBUG when verbose). `verbose` also now shows the
  System Configuration "hardware table" the bootcfg contract promised, even
  when `showConfig` is off.
- **Single source of truth.** The verbosity→log-level mapping moved to
  `bootcfg.echoMinLevel()` (was an inline table in the bootloader), so the
  bootloader and the tests can't drift. silent=FATAL-only, splash=WARN+ (the
  bar narrates INFO), text=INFO+, verbose=DEBUG+.

### Operator polish
- **Splash boot now shows a loading bar + high-level narration.** The
  "splash" verbosity used to mute the per-stage boot log and show nothing but
  the wordmark until login. It now drives a fill bar AND a 3-line rolling
  narration that describes what TOS is doing in plain language (e.g.
  "Loading OpenOS compatibility layer", "Starting networking") — the noisy
  internal chatter collapses into a clean sequence of big steps. So "splash"
  is a real visual boot, while "text" still shows the full live log for free.
  Crucially the bar can't hide a problem: WARN/ERROR messages are shown
  verbatim and coloured (never simplified away). The raw-message → step map is
  the pure, tested `kernel.bootsteps`; the bar is driven via a guarded
  `bootProgress` hook in `log.lua`, nil (no-op) in every other mode.
  (`init.lua`, `log.lua`, `kernel/bootsteps.lua`; `test_bootsteps.lua`,
  `test_log_bootprogress.lua`.)
- **Already-inserted media is announced at startup.** The insert auto-detect
  only fired on hot-plug, so a disk present at boot went unnoticed. The shell
  now scans mounted media once at startup and surfaces the first actionable
  disk (e.g. an Optional Utilities disk) on the status row.
  (`helpers.scanMountedMedia`; `test_disk_classify.lua`.)
- **`about` refreshed.** It was frozen at "v0.3.0 [Bastion]" with a stale
  changelog. It now reads the live version/codename + vendor/motto and shows
  a current capability summary instead of an old release log. (`about` in
  both shells.)

### Rebrand → Strata Systems LLC
- The vendor identity is now **Strata Systems LLC** (plural of *stratum* —
  layers) across the splash, System Configuration, login, installer banner,
  `about`, the kiosk example, the README license, and every Extras package's
  `author` field (sources updated + the Optional Utilities disk rebuilt). The
  Skynet-flavoured motto ("Firmware with a will of its own.") is kept — it's
  product character, not a company name. (`kernel/logo.lua` `VENDOR` +
  `install.lua` embedded banner; the wordmark itself is unchanged.)

### Optional Utilities install — packages were invisible (now fixed)
- **Disk laid out one level deep wasn't recognized.** If the whole
  `dist/optional-utilities` FOLDER was copied onto a disk (instead of its
  contents), the packages sat under `/mnt/<disk>/optional-utilities/` and the
  disk read as blank "data" — `classifyDisk` and `pkg` discovery only looked
  at the disk root. Both now also look ONE level down, so the disk is detected
  and its packages install whichever way it was assembled. (`helpers.lua`
  `classifyDisk`, `pkg.lua` `mountedRepoRoots`; `test_disk_classify.lua`,
  `test_pkg_discovery.lua`.)
- **Mounted disks were invisible to package discovery.** A disk mounted by
  the KERNEL at boot is a *virtual* mount point — `fs.mount` records it but
  creates no real `/mnt/<label>` directory, so it never appears in
  `fs.list("/mnt")`. `pkg.listAllAvailable` / `installFromFloppy` scanned
  only that listing, so a single-package install (explicit path) worked but
  every package on a multi-package Optional Utilities disk was unfindable by
  `pkg search` / `pkg from-floppy` / the `install.lua` picker. Discovery now
  enumerates `fs.mounts()` (the authoritative mount table), still folding in
  real `/mnt` subdirs for shell-side auto-mounts. (`pkg.lua`;
  `test_pkg_discovery.lua`.)
- **Comment headers made every package manifest unparseable.** `pkg`,
  `mod`, `disk`, and the disk `install.lua` picker all "couldn't see" the
  packages on an inserted Optional Utilities disk. Root cause: each
  `package.lua` manifest carries a `-- …` comment header (and inline `--`
  notes inside the table), but `serialize.decode` — the safe table parser
  these go through — choked on the first `--` ("Invalid number: -"), so
  `pkg.listRepo`/`listAllAvailable` silently found zero packages. The
  decoder now skips Lua comments (line and `--[[ ]]` block) like a real
  tokenizer, and tolerates a `return` that follows a comment header. Still
  `load()`-free / safe for untrusted input. (`serialize.lua`;
  `test_serialize_comments.lua`.)
- **Clearer "protected path" message.** Writing into `/usr/lib`,
  `/usr/modules`, `/usr/bin`, or `/var/pkg` is blocked even for root (a
  defence-in-depth line, not an ACL — so a tampered admin session can't
  swap shipped libs). The denial now says so and points at the supported
  path: `pkg install <name>` / `pkg from-floppy`, instead of leaving an
  operator to conclude root "should" be able to copy files there.

### Mouse: left and right click now differ
- **Left-click = quick action, right-click = context menu.** With the mouse
  add-on, a left-click activation on a file used to open the SAME context
  menu as a right-click (because keyboard Enter on a file opens the menu, and
  the click mirrored it). Now a left-click on the selected file does the
  quick action — enter a directory or **view** a file — while right-click
  opens the context menu for the detailed options. The F3 View key and the
  left-click share one `viewSelected` helper. Keyboard Enter still opens the
  menu (the keyboard's only way to reach options). (`panels/mouse.lua`,
  `panels/events.lua`; `test_panels_mouse.lua`.)

### Low-memory resilience (don't shut down — recover)
- **OOM at login no longer powers off the machine.** On a tight box the
  shell could OOM while loading right after login (`not enough memory for
  buffer allocation`); the kernel then saw zero processes and *shut down*,
  reading as a crash. Now the kernel treats an unexpected all-processes-gone
  as recoverable: it GCs and respawns login a bounded number of times, then
  falls back to the **emergency shell** so the operator can free space / read
  logs instead of being dropped. (`init.lua` main loop.)
- **Shell gets a clean heap.** The kernel now `collectgarbage()`s right
  before spawning the shell (boot leaves a lot of transient garbage) and logs
  the free-memory figure, turning many marginal "just barely OOMs" boxes into
  ones that load. The crash notice is drawn defensively so an OOM during the
  notice itself can't escape the process body.
- **Shadow-buffer gate had no headroom.** The display dirty-cell shadow
  enabled at `free > W*H*128` — i.e. free only had to exceed the shadow's own
  ~256 KB with *zero* room for the shell that does the drawing, so it claimed
  most of a 330 KB-free box and the shell then OOM'd. Now requires the shadow
  size **plus a 384 KB working reserve**, so tight boxes keep it off (direct
  draws) and only roomy boxes pay for the optimization. (`screen.lua`.)
- **Input fields scroll instead of clipping off-screen.** Typing a long name
  in a prompt (e.g. `report.example`) used to clip from the left, so the
  cursor and the extension you were typing ran off the right edge. The shared
  `promptInput`/`promptSearch` (and the `mail` body input) now scroll
  horizontally to follow the cursor, like the chat input already did.
  (`dialogs.scrollTail`; `test_dialogs.lua`.)

### System Configuration screen — function over form
- **Honest hardware readout.** The DEL-to-enter System Configuration screen
  no longer invents PC-BIOS flavour (the fake Base/Ext memory split, a
  "Numeric Processor" that doesn't exist, pseudo IDE drive names). It now
  shows only what's really there, by its real name: Processor / CPU Tier /
  Graphics / Data Card / Network / EEPROM on the left; Total & Free Memory,
  **RAM Modules** (counted via `component.list("memory")`), Max Text Mode,
  Screens and Boot ID on the right. Storage rows read Boot Drive / Data
  Drive N / RAM Disk. (`sysinfo.gather`/`render`; `test_sysinfo_render.lua`.)

### Boot Settings — basic up front, advanced hidden
- **Two-tier menu.** The everyday choices (Profile / Verbosity / Show this
  screen) show by default; the boot overrides and manual device checks
  (CPU & Data-Card tier overrides, the per-feature toggles) are tucked
  behind **`[A] advanced`** so an operator can't fat-finger something they
  didn't mean to touch. Fields carry a `group`, and the runner cycles by
  key so the filtered view never mis-maps a row. (`bootsettings.lua`;
  `test_bootsettings.lua`.)

### Dialog boxes — a general prompting primitive
- **MS-DOS-style dialog boxes.** A new `panels.dialogs.dialog` draws a
  titled, framed, centred box (single-line frame, a centred `┤ Title ├`
  tab, drop shadow) and blocks until the operator picks a button. It's a
  GENERAL primitive — any title, buttons and `style` (info / install /
  warn / danger / error / general) — so TOS developers can prompt
  intrusively (the box) or non-intrusively (the existing status-row
  `promptInput`), whichever fits. `alert`/`confirm` are thin shortcuts;
  file deletion now uses a danger-styled `confirm`. Exposed on the panels
  API (`dialog`/`alert`/`confirm`, auto-repaint on dismiss).
  (`test_dialogs.lua`.)

### Mesh email + chat
- **Mesh mail (store-and-forward, no central server).** New `mail` command:
  addressed email that multi-hops across **trusted relays** by controlled
  flooding — each node re-broadcasts what it hasn't seen, decaying a hop
  budget and de-duplicating by id, so a message reaches a peer several hops
  away with no routing table. Reliability is store-and-forward: the origin
  (and any relay that passed it on) re-floods on a timer until an ACK floods
  back or a deadline passes, so a recipient that was briefly offline still
  gets it. Message **content is sealed end-to-end** with the existing
  per-peer trust secret, so relays forward a blob they cannot read; routing
  fields stay clear. Engine is dependency-free and unit-tested
  (`net/mesh.lua`, `net/mail.lua`, `net/mailctl.lua`; `test_mesh.lua`,
  `test_mail.lua`, `test_mailctl.lua` — incl. a 3-node A—B—C end-to-end with
  a blind relay). MAIL/MAIL_ACK gated TRUSTED-only (same posture as the
  cluster relay path) with a per-second relay budget against amplification.
  *Live wiring is in place (`net.init` adapter, `net.sendMail`/`inbox`/
  `mailTick`); needs in-emulator verification, and the at-rest mailbox
  (`/var/mail/<user>`) should move to per-user securefs as a follow-up.*
- **Chat enhancements.** Slash commands (`/who`, `/clear`, `/help`, `/quit`)
  plus a **`/mail <peer> <text>`** bridge that hands a message to the
  reliable mesh-mail path; a live trusted-peer count in the header; and the
  input parser (command / directed / broadcast) extracted to pure, tested
  helpers. (`shell/chat.lua`; `test_chat_parse.lua`.)

### Operator-friendly installation revamp
- **Auto-detect & guide on insert.** Inserting a removable disk now names
  what it IS and the next step to take: TOS install disk, Optional Utilities
  disk, package repo, single-package, legacy module, or plain data. A shared
  `helpers.classifyDisk` drives both the insert toast and the `disk` command,
  so they never disagree. (`test_disk_classify.lua`.)
- **In-TOS Optional Utilities builder.** `pkg make-disk <mount> [name…]`
  assembles your INSTALLED add-ons (plus a self-contained picker
  `install.lua`) into a pick-and-choose disk — parity with `deploy`, no dev
  box or TOS-Extras source tree needed. Admin-gated, write-confined, refuses
  system paths. (`kernel.pkg.exportDisk`; `test_pkg_exportdisk.lua`.)
- **Clean install (installer v1.3.0).** The OpenOS-run `install.lua` can now
  shed OpenOS's `/bin` + `/lib` so a fresh TOS tree doesn't inherit the
  bootstrap host's filesystem. Conservative by design: only those two trees
  (never `/etc`, `/usr`, `/home`, …), gated on a fully-verified copy, and run
  as the very last action before reboot so the still-running OpenOS never
  loses a library mid-install. Both existing entry points (manual
  `install.lua`, BIOS auto-floppy) are unchanged. First-boot message corrected
  to reflect that TOS *forces* the root password change.

### Build tooling
- **Release build no longer silently ships tests + build tooling.** Under Git
  Bash / MSYS on Windows, `build-release.sh` had its `--exclude /build/`-style
  patterns rewritten by MSYS path-mangling into `C:/Program Files/Git/build/`
  before `lua` saw them, so NOTHING was excluded (`skipped 0 entries`) and the
  Release tree carried all 43 dev tests and the build scripts. The wrapper now
  converts path args to mixed Windows form (`cygpath -m`) and sets
  `MSYS2_ARG_CONV_EXCL='*'` on MSYS so the patterns pass through verbatim; real
  POSIX is unaffected. (The native `build-release.cmd` was always correct.)

### Emulator-testing fixes (2)
- **Multi-seat: session stays on the boot screen; seats no longer steal each
  other's input.** Two fixes. (1) `screen.init` paired `gpu[i]↔sorted-screen[i]`,
  which rebound the GPU away from the screen the BIOS drew the splash on (boot
  on one screen, session on another) and yanked a live seat onto a hot-plugged
  screen. It now PREFERS each GPU's current screen binding (new pure
  `screen._pair`, `test_screen_pair.lua`). (2) The per-seat login broker never
  claimed its seat's foreground, so during login the seat's keystrokes fell back
  to the GLOBAL foreground shared across seats — a 2nd seat's login captured and
  froze the 1st seat. `spawnLoginProcess` now claims `displayForeground[dIdx]`.
- **Logout no longer leaves a zombie shell drawing over the new session.** The
  root cause of the "status bar flips between two users" flicker: H13 made
  `proc.kill` fail closed on a no-caller call, but the kernel main loop (which
  reaps a seat's shell on logout/shutdown/seat-unplug/Ctrl+C, and the task
  switcher after its own `canAct` check) HAS no caller — so the kill was denied
  and the old shell kept running and drawing. `proc.kill(pid, {kernel=true})`
  now authorizes the genuine kernel path; the default still fails closed
  (sandboxes can't reach proc, listeners carry a listenerPID). Pinned by
  `test_kernel_kill.lua`. (Fixes the single-screen flicker; the two-screen
  seat↔display *binding* — wrong screen for boot vs. session, cross-seat freeze
  — is a separate multi-seat item still open.)
- **Config POST screen no longer overflows / detects the set Data Card tier.**
  The 5-row wordmark pushed the dense hardware box off an 80×25 screen — the
  POST screen now brands via the box title only. It also passes the operator's
  manually-set Data Card tier (Boot Settings) to `sysinfo.gather`, so the
  Crypto line shows the chosen tier instead of "unknown tier".
- **Boot Settings stopped re-scanning hardware on every keystroke.** With the
  hardware view open, each cursor move re-ran the full `sysinfo.gather`
  component probe (laggy); the inventory is now cached and re-gathered only
  when a tier override actually changes. Also fixed the "Data Card tier" label
  running into its value column (shortened + clipped).
- **Per-user themes.** Any regular user can now pick a PRESET theme for their
  own session (`theme set <name>` / `theme list`, USER tier), saved to their
  `~/.theme.cfg` (seat-bound) and restored at their next login; CUSTOM colour
  overrides (`theme color`) stay admin-only.

### Branding
- **AMIBIOS-style System Configuration POST screen.** Reworked `sysinfo.render`
  from a boxed section list into a rigid, two-column "Main Processor : … |
  Base Memory Size : …" grid with retro labels (Numeric Processor, Ext. Memory,
  Max Text Mode, EEPROM BIOS, BIOS ID), a storage table with pseudo PC drive
  names (Primary Master/Slave, Floppy Drive A, Used/Size, Tier, Boot), and the
  classic "<n>KB SYSTEM MEMORY · GPU T2 TEXT MODE 80x25" footer — TOS's actual
  OpenComputers facts dressed as an American Megatrends POST. Boot Settings stays
  the place for TOS-specific config. Narrow (T1) screens fall back to a single
  column. `sysinfo.rows` (the Boot Settings hardware view) is unchanged.
  `test_sysinfo_render.lua`.

### Performance
- **Dirty-cell shadow buffer on the per-seat display.** The shell redraws
  mostly-unchanged rows every frame, and each `gpu.set`/`fill` (plus its
  `setForeground`/`setBackground`) crosses the OC bridge (up to ~50 ms/tick
  budget). The display proxy now remembers what every cell holds and SKIPS the
  GPU call when the target already matches exactly — the idle status-bar tick,
  re-drawn file lists, and static chrome stop re-emitting. Memory-gated (the
  buffer is ~W×H×3 slots, so it's disabled on tight boxes, which fall back to
  direct draws and pay nothing). Also fixed a latent colour-cache desync: a
  forwarded `withContext` draw now resets the proxy's fg/bg cache (it left the
  GPU at colours the proxy never tracked). `test_screen_shadow.lua`. (Colour
  caching and `gpu.copy` scrolling were already in place.)

### Shell & branding
- **`launcher` — menu-driven Operator multi-tool.** A full-screen, clickable
  menu (number keys, arrows+Enter, or a native screen touch) that runs real
  commands at YOUR tier — click instead of type. Generalizes the old kiosk
  menu into a nested, profile-driven engine (`tos/shell/launcher.lua`): a
  built-in home of quick actions, a **cluster helper** submenu when the cluster
  add-on is installed, a personal menu from `~/.launcher.cfg`, and `launcher
  tape` — your personal toolbox carried on your **identity tape**. Kiosk stays
  the locked, guest-facing profile; the `kiosk` command now points operators at
  `launcher`. Aliases `launch`/`apps`. Pinned by `test_launcher_menu.lua`.
- **Personal menu on the identity tape.** tape-authenticator gains
  `tape-auth menu add|list|remove|clear <passphrase>` — a vault-encrypted menu
  region on the keycard (alongside the identity block + personal log; the TAUTH2
  wire format grew an optional trailing menu region, round-trip pinned by
  `test_tape_menu_format.lua`). `launcher tape` reads + unlocks it and runs it at
  your tier (`launcher.readTapeMenu`, `test_launcher_tape.lua`) — so the toolbox
  follows the operator between machines. The card needs no filesystem access:
  the launcher (which knows the home + has tape + vault) does the reading.
- **TOS visual identity (`kernel.logo`).** One Skynet / American-Megatrends-
  flavoured block wordmark, shared by the boot splash, the AMIBIOS-style
  configuration POST screen, and the login screen, with an ASCII fallback for
  monochrome screens. Dependency-free (safe to load at early boot); every
  caller pcall-requires it with a graceful fallback. The installer embeds a
  byte-identical copy (it runs before the kernel). `test_logo.lua`.

### Cluster
- **Worker bridge wired end-to-end (v2).** The Manager's `dispatchAssignment`
  ran every task inline on itself (`TODO(v2)`); it now hands tasks to registered
  OpenOS workers over the authenticated bridge when configured. Each task routes
  inline or to an idle worker (`task.via_bridge`, or all tasks under
  `worker_bridge_mode = "prefer"`), results are collected asynchronously and
  aggregated (ok / partial / failed / cancelled) with a per-task idempotency
  guard so a worker result racing a cancel can't double-count, and a silent
  worker yields a `timeout` so an assignment never hangs. New config block in
  `/etc/cluster-manager.cfg` (`worker_bridge_*`), a `cluster-manager workers`
  CLI subcommand, and bridge state in `status`. Dispatch logic is pinned by
  `test_cluster_bridge_v2.lua` (22 cases). Needs in-emulator verification with
  real OpenOS workers before relying on it for production scheduling.

### Security
- **Cluster worker now authenticates frames (#SEC H21/H2/CR-3).** The TOS-side
  Manager bridge was hardened to require a shared secret and HMAC-verify every
  WRK frame, but the OpenOS worker — the side that actually executes
  Manager-supplied `code` — was never updated: it ran tasks after an
  unauthenticated `REGISTER_ACK` and sent unsigned frames (which a hardened
  Manager silently drops, so the channel was also non-functional). The worker
  now carries a matching software SHA-256/HMAC, signs every frame with a fresh
  nonce, verifies + replay-checks inbound frames, and default-denies task
  execution until `shared_secret` (16+ bytes, matching the Manager) is set in
  `/etc/cluster-worker.cfg`. Crypto parity with `kernel.crypto` is pinned by
  `test_cluster_worker_hmac.lua`.

### Emulator-testing bug-fix batch (13 operator-reported issues)
- **Themes save again.** securefs treated `/home`, `/root`, `/public` as
  subtree-protected, so it refused EVERY write beneath them — `~/.theme.cfg`
  and `~/.profile.cfg` could never be written ("WRITE denied (protected):
  /root/.theme.cfg"). Those roots are now NODE-protected (the directory node
  itself is guarded; files inside follow the per-user ACL). System trees
  (/tos, /etc, /usr, /var) stay subtree-protected. New
  `test_securefs_protected.lua`.
- **Theme colours stop snapping weirdly on T2 GPUs.** display.setTheme now
  snaps each colour to OC's actual 16-entry 4-bit palette itself (with
  ensureContrast healing any collapsed fg/bg pair), instead of leaving the
  hardware to do a naive nearest-RGB snap that turned dark bars black.
- **Floppy/removable-disk insert works.** `_G._TOS.bootAddr` was never set,
  so the shell's auto-mount gate (fail-closed by design, #SEC H26) refused
  every inserted disk. Now set at boot from the boot proxy.
- **Data Card detection unified + honest.** New shared `kernel.datacard`
  (component.list("data") + tier inference from the method set: T1
  hashing/base64/deflate, T2 +AES/random, T3 +ECC). `compress` uses it and
  now reports a present-but-deflate-less card honestly instead of "No data
  card" while crypto saw the same card as Hardware. `sysinfo` delegates to
  it too. New `test_datacard.lua`.
- **`verify` no longer fails man pages.** It ran `load()` on every manifest
  file, flagging `/usr/man/*.man` (prose) as "BAD (syntax)". Only `.lua`
  files get a syntax check now; data files are existence/hash-checked.
- **`flash` confirmation prompt fixed.** The "type flash to confirm"
  instruction was drawn with drawOutRow then instantly wiped by
  promptInput's own (empty) render, leaving a blank prompt that "aborted on
  any key". The message is passed INTO promptInput now (same fix applied to
  the from-floppy installer prompt).
- **Output wraps correctly.** Viewer content was wrapped to full width then
  re-clipped to width-minus-gutter at draw time, dropping the last few
  characters of a wrapped line ("'or' → 'o'"). expandBuf reserves the gutter.
- **`log` reads the on-disk file by default** (flushing first), falling back
  to the in-memory ring, then a regenerated file; `log ring` is the quick
  in-memory peek. (kernel.log.1 is the 16 KB rotation backup — not a
  duplicate; the persistence path attaches once and never double-writes.)
- **Menus reorganized + modular.** File no longer has Quit (power actions
  moved to System: Log Out / Reboot / Shut Down); added View, Settings→Theme/
  Boot Settings. Any menu item can be `action="run:<command>"`, and a
  per-user `~/.menu.cfg` (managed by the new `menu add|list|remove` command)
  injects command shortcuts into any drop-down.
- **Power-off policy (#9).** Reboot/shutdown from the menu/F10/commands are
  now gated by `helpers.canPowerOff`: a sole operator may power off, but with
  other operators logged in only ADMIN+ may (it kills their sessions too).
- **Live status bar.** The shell event loop now refreshes the status bar
  ~once a second when idle, so the clock/uptime/free-mem widgets tick.
  `date tz <hours>` sets the display offset (OC has no settable clock).
- **JBOD safer + clearer.** `jbod create` now confines pools to `/mnt/`,
  CREATES the mount directory, and REFUSES the boot disk as a member (which
  is what exposed "a copy of TOS" inside the pool).
- **Lua REPL is multi-line.** Statements accumulate until they compile
  (incomplete input shows a `>>` continuation prompt; a blank line runs or
  cancels the block), and each executed chunk is still audit-logged.

### Proactive audit (bugs found while reviewing, not yet reported)
- **Multi-screen seat pairing is deterministic.** `screen.init` paired
  GPU↔screen in `component.list()` order, which OC doesn't keep stable
  across boots — so on a 2-screen rig the active panel could change every
  reboot ("screens swap on reboot"). The address lists are sorted now, so
  each seat pins to the same hardware run-to-run. (1 GPU still drives only
  1 screen; that limitation is logged at boot.)
- **`cp`/`mv` honor a directory destination.** `mv foo.txt /tmp` tried to
  create a path literally named `/tmp` instead of moving INTO it; both now
  append the source basename when the target is a directory, and `mv` falls
  back to copy+remove across filesystems (matching the browser's F6).
- **Mouse menus read live state.** After the modular-menu refactor, the
  mouse handler held a one-time snapshot of the menu layout, so a `menu add`
  at runtime updated keyboard navigation but not clicks. It now reads the
  live `S.menuDefs`.

### Security
- **Kiosk mode bypassed filesystem ACLs.** The locked-down public-terminal
  shell (`shell/kiosk.lua`) built its command environment with the raw,
  privilege-bypassing `_G._TOS.fs` and a stubbed `canRead`/`canWrite` that
  always returned true/false. Because `cat` is in the default allow-list, a
  GUEST kiosk user could read any file — `/etc/users.dat`, `/etc/trust.dat`,
  any home dir. Kiosk now uses `securefs` (session-bound) for `F` and routes
  `canRead`/`canWrite` through `helpers.canAccess`, and `S.st` carries the
  token the rest of the command layer expects. New `test_kiosk_acl.lua` proves
  a guest `cat /etc/users.dat` is refused (fails on the pre-fix code).

### Dead-code prune
- Removed ~24 unreferenced kernel/shell exports (and their now-orphan locals):
  the `kernelDispatch`/`isKernelContext` machinery, the net message-log ring,
  trust change/request callbacks, event `globalListeners`/`onAny`/`pullNamed`,
  HAL hotplug callbacks, and assorted unused accessors across `init`, `users`,
  `rc`, `log`, `crypto`, `display`, `screen`, `pipe`, `power`, `bootsettings`,
  `audio`, `config`, `commands`, `login`.
- Synced `system_manifest.lua` — it was missing 9 shipping runtime files
  (`backup`, `diag`, `keychain`, `profile`, `trash`, `vault`, `net/aliases`,
  `net/chatpair`, `kiosk`).

### Dead-ends wired up (rather than deleted)
- **`net revoke <peer>`** / **`net forget <peer>`** — downgrade a peer to
  UNKNOWN (without blocking) or drop its record entirely.
- **`net request <peer>` / `net requests`** — send and review trust requests
  (`requestTrust`/`getPendingRequests` were live but unreachable).
- **`log filter <source> <level>`** — per-source log level overrides.
- **Tunnel-only boxes can network** — `net.send`/`net.broadcast` no longer
  require a wireless/wired modem; they fall back to a linked card.
- `pkg.install` now enforces declared version constraints (warns on unmet
  `requires`).

### Efficiency
- `event.pull` (the hottest loop) no longer does `pcall(require,
  "kernel.process")` per timer fire and per signal dispatch — the module ref
  is cached behind a lazy accessor.

### JBOD disk pooling — now opt-in, not removed (`kernel/jbod.lua`)
- The dormant JBOD module is back, but **off in every profile**: it loads only
  when `/etc/boot.cfg` has `advanced.jbod = true` (`bootsettings jbod on`).
  Pure-Lua union mount (capacity = sum of members; a lost member loses only its
  own files; securefs still applies per-user ACLs).
- New **`jbod`** admin command: `create <mount> <disk...>` / `list` /
  `destroy <mount>`, persisting pools to `/etc/jbod.cfg` (re-mounted at boot).
  Install-aware-hidden when the feature is disabled. `man jbod`.
- New `test_jbod.lua` covers the pool proxy (union reads, free-space write
  routing, in-place overwrite, list dedup) and proves the boot gate is
  default-off across all four profiles.

### Mouse add-on (Optional Utilities / TOS-Extras)
- TOS has no baked-in mouse support (keyboard-driven shell, MS-DOS style). The
  new **`mouse`** package installs a userspace driver — `require("mouse")` —
  that turns OpenComputers touch/drag/drop/scroll signals into clean mouse
  events with rectangle hit-testing, plus a `mousetest` demo. Pure userspace
  (`component` cap only). Ships on the Optional Utilities disk; covered by
  `modules/mouse/test_mouse.lua` (28 cases, all pure/off-box).
- **The panels shell now consumes the driver** (new `shell/panels/mouse.lua`,
  mouse pkg → 1.1.0): when the `mouse` package is installed (and enabled), the
  shell's UI elements become clickable — menus toggle open/closed by click,
  dropdown/context-menu items run on click, tabs switch on click (right-click
  closes closable tabs; modified editors are surfaced, never dropped), file
  rows select on first click and open on second (right-click = context menu),
  the wheel scrolls the file list/viewer/editor, clicks place the editor
  cursor, and the status-bar config checkboxes toggle by click. Without the
  driver every mouse signal is ignored exactly as before; keyboard behaviour
  is unchanged either way. The driver probe honors `pkg disable mouse` and
  re-probes (throttled) so a mid-session install starts working immediately.

### Extras fixed for the pkg sandbox (kernel.modules→pkg regression)
- **tetris could not launch**: it required `kernel.display`/`kernel.event`
  (plus `kernel.users`/`securefs`/`fs`/`serialize`), all blocked by the pkg
  sandbox. Rewritten (pkg → 1.1.0) to draw via the sandboxed `component` GPU
  proxy, pull raw signals via `computer.pullSignal`, and store high scores
  through the session-bound `fs` global + `compat.serialization` (old
  `return {...}`-format score files still load). Also fixed its dispatcher
  reading `args[2]` (the dead kernel.modules argv convention) — under pkg,
  `tetris scores`/`tetris help` silently launched the game instead.
- **tape encrypt/decrypt always failed** ("vault module unavailable"):
  `require("kernel.vault")` is sandbox-blocked. New narrow **`vault`
  capability** (kernel.sandbox + pkg allowlist) exposes exactly
  `encrypt`/`decrypt`/`isEncrypted` — pure data-in/data-out on
  caller-supplied strings, no keychain or fs surface — and the tape package
  (→ 2.1.0) declares it. `legacy` remains excluded from manifests.

### Theme palette refresh (every preset + the boot defaults)
- **All presets redesigned** (`kernel/theme.lua` + the boot-time defaults and
  T2/T3 tier branches in `kernel/display.lua`). The old set was CGA-harsh:
  solid white/amber/green menu bars dominated the screen, and title/warning
  collapsed into the same yellow in several presets. New rules every preset
  follows: tinted bars instead of solid accent blocks, soft body text instead
  of full-white glare, and a distinct title/warning/error severity ladder.
  - `default` — teal frames + warm-gold titles on black, dark-slate menu bar,
    deep sea-blue status bar, One-Dark-style syntax colors.
  - `midnight` — Tokyo-night indigo; `amber`/`green` — CRT phosphor looks with
    dark bars (selection keeps the inverted-phosphor block); `classic` — now
    actually Norton-style (cyan bars with black text on CGA blue); `contrast` —
    stark white/yellow with an ~9:1-contrast orange warning.
  - Three new presets: **`nord`**, **`solarized`** (dark), and **`plasma`** —
    early-plasma-display neon red-orange on pure black, with every color kept
    in the red-orange band (no blue/green light) so operators working in the
    dark keep their night vision.
- **Presets now carry the full key set including syntax + file-type colors**,
  so switching presets restyles the editor too and never leaves the previous
  theme's syntax colors behind. `theme color` accepts the `syn_*`/`file_lua`/
  `dir_color` keys, and saved overrides round-trip.
- **`input_fg` was silently dropped** by `display.setTheme`'s allowlist while
  both kernel.theme and the presets used it — input-field text colors now
  actually apply.
- **T2 palette corrected**: the 4-bit tier branch (and preset snap targets)
  now use OC's actual default 4-bit palette entries (0xFFCC33 orange, 0x6699FF
  light blue, 0x336699 cyan, …) instead of CGA values that snapped
  unpredictably.
- **Profile themes never applied** (REV-2): `profile.apply` called
  `theme.applyPreset`, a function kernel.theme never exported, so
  `profile set theme <name>` did nothing at login. Fixed to call the real
  API; the profile theme is now opt-in (unset by default) and an explicit
  `theme set` choice (`~/.theme.cfg`, which can carry per-key overrides)
  outranks it via the new `theme.hasSavedTheme()`. `profile set theme`
  validates the preset name at set time, and PaneUI's mirrored palette table
  was re-synced (now 8 themes).

### Optional Utilities disk — one-command build & install (TOS-Extras)
- **`build-disk.cmd` / `build-disk.sh` wrappers**: building the disk is now a
  single command on either platform, and `--install <dir>` copies the built
  disk straight into a target folder (point it at an OpenComputers floppy
  directory under `saves/<world>/opencomputers/<address>/` to "burn" it in
  the same step).
- **The assembler auto-discovers packages**: any directory under `modules/`
  or `cluster/` with a `package.lua` is assembled — the hand-maintained
  `PACKAGES` table with per-package resolvers is gone. Each `files[]` target
  resolves mirror-first (source at its install path), then flat (single-file
  module root), then an explicit legacy map (master-skeleton's
  `lib/cluster/*`). Output verified byte-identical to the previous builder.
- **Deliberate exclusions are visible**: a `SKIP` table prints the reason at
  build time (currently `tape-authenticator` — a pre-pivot demo whose
  `commands` map is still the old array shape and whose HMAC path needs
  sandbox-blocked `kernel.crypto`).
- Runs without LuaFileSystem now (shell fallbacks for mkdir/dir-listing), so
  a stock Lua install is enough.

### CRITICAL: boot resolution policy bricked ordinary screens (#REV-3)
- The unreleased auto-density screen policy floored at a 40x12 *minimum*,
  which **collapsed every screen up to 4 blocks wide — including standard
  1x1 and 3x2 builds — to 40x12 at boot**: the login screen rendered at a
  fraction of the screen's real resolution and the machine looked
  bricked/headless after login. The density rule now only RAISES
  resolution above the ~80x25 baseline (for big multiblock walls where
  the hardware max means tiny glyphs) and never shrinks an ordinary
  screen below it: a 1x1/2x1/3x2 screen boots at the full 80x25 again,
  while a 16x10 T3 wall still gets its readable 160x40.
- Related stale-size hole closed: `screen.init` applied per-seat
  resolutions with a raw `gpu.setResolution`, never refreshing
  `kernel.display`'s cached W/H — anything drawing through the global
  display module after a divergent per-seat target painted off-screen
  (invisible). It now routes through `screen.applyResolution`, which
  syncs the cache. `test_screen_res.lua` rewritten around the new
  invariants (22 cases) plus an off-box boot-chain simulation.
- `build-disk` now sizes the assembled set against **`--limit`** (default
  512K, the OC default floppy; `0` = unlimited; per-file `--overhead`
  defaults to 512 bytes ≈ OC's `fileCost`) and, when it doesn't fit, splits
  packages across `disk1..N/` dirs — each with its own `install.lua`, with
  dependency-connected packages kept on the same disk (kernel.pkg resolves
  requires from the repo it installs from), first-fit-decreasing packing,
  and a hard error naming any single package group that exceeds the limit.
- The output dir is now wiped before assembling, so renamed install paths
  can't leave stale files on the disk.

### CRITICAL: shell received no input after login (#REV-3)
- After the resolution fix above, the shell drew its full UI but **no
  keystroke ever reached it** — the machine looked bricked/headless once
  past login. Root cause: the unreleased #SEC H13 target-ownership gate on
  `proc.setForeground`. The seat's login broker runs as a tier-0 `_login_`
  principal (by design, #135) and spawns the shell as the authenticated
  (higher-tier, different-user) session, so the gate denied the
  login→shell foreground handoff — and the call site ignored the return,
  so the seat's input stayed routed at the now-dead login process.
  `proc.setForeground` now permits a process to foreground its **own
  direct child on its own seat** (the handoff), while H13's actual
  exploit — pointing a seat at an *arbitrary* victim process — stays
  blocked. The kernel call site also logs a hard error if a handoff ever
  fails again, so this can't regress silently. (`test_fg_ownership`
  extended with the production handoff + wrong-seat/non-child denials.)

### POST screen: Data Card tier confirm + verbosity fixes
- **Data Card tier is now operator-confirmable**, mirroring the CPU tier.
  Some OC builds/emulators hand back a `data` component proxy that doesn't
  probe cleanly, so the POST screen showed `Crypto: present (unknown
  tier)` with no way to correct it. New `dataTier` boot setting (DEL editor
  field + `bootsettings datatier <auto|1|2|3>`); the POST line shows a
  confirmed tier with `*`, or `tier ? - set in boot settings` when unknown.
- **`silent` no longer locks you out of Boot Settings.** The POST screen
  (and its DEL → Boot Settings entry point) is now gated by `showConfig`
  alone, not `showConfig AND verbosity ~= silent`. An operator who set
  `silent` could previously never reach Boot Settings again from boot.
  For a fully silent boot, turn `showConfig` off as well.
- **`verbose` now does something visible**: every early-boot line is
  stamped with `[NNNNms]` ms-since-boot timings (the bootcfg vocabulary
  always promised "text + timings"; nothing emitted them, so verbose was
  identical to text).

### Narrow `crypto` capability + tape-authenticator 1.0
- New **`crypto`** sandbox facet (PKG_RUN_CAPS + kernel.sandbox):
  `hash`/`hmac`/`ctEquals`/`random` pure primitives, plus
  **`crypto.secret()`** — a per-PACKAGE machine secret, kernel-managed
  under `/var/pkg/secrets/<pkg>`, scoped by the manifest-validated package
  name threaded in by the pkg loader (package A can never read package B's
  secret) and admin-gated against the LIVE session per call.
- **tape-authenticator rebuilt (0.1 → 1.0)** around the user's
  keycard+notebook idea: the tape's identity block stays an HMAC-signed,
  machine-secret-bound key (TAUTH2; legacy TAUTH1 still verifies), and the
  rest of the tape now holds a **vault-encrypted personal log** the
  operator edits any time with their own passphrase (`tape-auth log
  add|list|remove|clear|passwd`) — log edits never touch the identity
  block and need no admin tier, while minting/verifying keys does. The
  0.1 build could never run under pkg (kernel.crypto/securefs requires,
  array-shaped commands map); 1.0 is sandbox-pure and ships on the disk.
- **tape module renamed to its real name**: `modules/tape-storage/` →
  `modules/tape/`, install path `/usr/modules/tape-storage/` →
  `/usr/modules/tape/` (pkg → 2.2.0). The old name described the original
  data-archiver; the module has been the general tape tool since 2.0.
  `provides = {"tape-storage"}` keeps legacy `requires` resolving;
  upgrading installs need a `pkg uninstall tape` first.

### Tests
- Full standalone suite green: 36 TOS-Dev tests pass under host Lua (the 37th,
  `test_manifest_completeness`, needs a live TOS boot; verified equivalent
  offline via the new `build/check_manifest_offbox.lua`). Mouse driver: 28/28.
- New: `test_theme_presets.lua` (139 cases — full key coverage, color
  validity, contrast invariants, severity-ladder distinctness, setTheme
  acceptance of every preset key, and the profile-theme application fix) and
  Extras `build/test_build_disk.lua` (23 — assembler discovery/resolution,
  H-20 name match, skip list, `--install` replay).
- New: `test_panels_mouse.lua` (61 cases — click/scroll routing against the
  real Extras driver), `test_sandbox_vault_cap.lua` (17 — cap exposure bounds
  + pkg allowlist), and Extras `modules/tetris/test_tetris_sandbox.lua` (13 —
  loads and plays tetris inside a faithful fake of the pkg sandbox).

### Prompt editing — cursor movement
- **The command prompt cursor now moves.** Previously you could only edit at
  the end of the line — to fix an early character you backspaced everything
  after it. The prompt now supports Left/Right (move one char), Home/End (jump
  to start/end), Delete (forward-delete), and insert/backspace **at** the
  cursor. Long lines scroll horizontally to keep the cursor on-screen. New pure
  helper `helpers.cmdScroll` + `test_cmd_cursor.lua` (21 cases) pin the math.

### Release-accuracy fixes (external review)
A static review compared the shipped 1.3.2 image + Optional Utilities disk to
the docs and found drift. Corrected here:
- **Installer version was stale.** `install.lua` reported `1.3.0`; now `1.3.2`,
  and the header no longer carries a second literal version to drift from.
  `env.lua`'s `TOS_VERSION` fallback `1.3.1` → `1.3.2`.
- **Manifest was missing the mesh-mail stack.** `system_manifest.lua` did not
  list `net/mail.lua`, `net/mailctl.lua`, `net/mesh.lua` (so `deploy`/`verify`
  ignored them). Added — manifest now 116 paths. **The completeness test that
  should have caught this was being SKIPPED** by the harness (it required a
  live TOS boot); `test_manifest_completeness.lua` is now dual-mode and runs in
  the offline harness too.
- **`mail` was advertised in panels but had no executor** — running it did
  nothing (only the fallback CLI implemented it). Added a panels `mail` (list/
  read/delete/send) delegating to the same net-mail surface.
- **`pwd`, `du`, `head` were documented but unimplemented.** Added to both
  shells. `tree`/`trash`/`restore` and `mail` added to the CLI too, narrowing
  the panels↔CLI gap.
- **CLI `rm` contradicted the manual** (hard delete vs. "moves to trash unless
  `--hard`"). CLI `rm` now soft-deletes to per-user trash like panels; added
  CLI `trash`/`restore`. Manual's `rm` reference entry corrected.
- **CLI `kill`/`fg` were not admin-gated** though the README claims they are
  (panels already gated them). Now gated (`userTier < 2`).
- **README theme count** said six; there are nine (`plasma`, `nord`,
  `solarized` were missing). PaneUI already renders all nine.

### Optional Utilities — package correctness
- **Cluster packages declared `commands = { "cluster" }`** (array), which
  `pkg.commands` silently dropped (it wants a name→path map). The CLIs still
  worked via `/usr/bin`, so the vestigial declaration is removed and documented.
- **`rc-pilot` used crypto without declaring the capability**, so the sandbox
  left `crypto` nil and `rc` died on first use. Now declares `"crypto"` and
  uses the injected `crypto` global (`random`/`hmac`) instead of the blocked
  `require("kernel.crypto")`.
- **"Disabled by default" was not enforced for service packages.** `rc.runAll`
  started every `/etc/rc.d/*.lua` at boot regardless of a package's
  `defaultState="disabled"`, so installing `cluster-master`/`-manager`
  auto-started a daemon on the next boot. `pkg.install` now drops a
  `<svc>.disabled` marker; `rc` registers but does not start marked services,
  and an explicit `service start` clears the marker to persist the enable.
- **Installer printed the wrong service name.** `service start <package-name>`
  → derives the real rc.d service stem (`cluster-master` ships `clusterd.lua`,
  so `service start clusterd`). Fixed in both the disk picker and the embedded
  in-TOS `pkg make-disk` copy.
- New: Extras `build/test_manifests.lua` (28 — lints every package manifest:
  `commands` map-shape, crypto/vault capability declared when a sandboxed
  entrypoint uses it, capabilities are sandbox-grantable, service packages ship
  an rc.d script) and `test_rc_disabled.lua` (10 — disabled-by-default marker).

### Emulator-testing fixes (in-OC)
A round of fixes from running the build in OpenComputers (Ocelot):
- **Bundled Optional Utilities wouldn't install** despite `pkg list` showing
  them. Install used `pkg.findInRepos`, which scanned only `/mnt/<label>` (one
  level), while listing used the nested-aware `mountedRepoRoots`. So a disk with
  the whole `optional-utilities/` folder on it listed fine but `pkg install
  tetris` said "not found in any repo". `findInRepos` now uses the same
  enumeration, and `pkg install` also accepts a full path. (`test_pkg_discovery`
  +3.)
- **Disk `install.lua` did nothing in panels.** It's a line-driven (`io.read`)
  picker; the panels TUI has no line stdin, so it exited immediately. It now
  prints a pointer to the panels-native installer, and the disk-insert hint
  recommends `pkg from-floppy` instead of the dead-end `install.lua`.
- **Inline command output was wiped by any keypress/click.** Moving the cursor
  or clicking with no mouse driver cleared the last command's output. It now
  clears only when the file browser actually scrolls under the overlay.
- **`Running …` flashed for every command**, including builtins and unknowns
  (`Running test…` then an error). It now announces only actual programs
  (scripts / package commands).
- **Task switcher (^T) didn't clear on close.** The kernel signalled the shell
  to repaint via `proc.signal`, but that runs in the kernel loop (no caller PID)
  and `proc.signal` fails closed there (H13) — so the redraw never fired. Added
  a kernel-context `proc.signalKernel`; the dialog now repaints the shell on
  close.
- **System Config read every data card as "unknown tier".** `capsOf` probed the
  proxy's fields (`type(p.sha256)`), which Ocelot returns empty; it now uses
  `component.methods(addr)` (the authoritative enumeration). (`test_datacard`
  +4.)
- **Folder properties always showed 0 B** (directories report size 0); now sums
  contents recursively with a file count.
- **`tape-auth` OOM'd configuring a tape** even on tier-3.5 RAM — it slurped the
  whole multi-MB tape into one string. It now streams only the keycard region.
  `tape-auth info` authenticates inline for admins instead of always nagging to
  run `verify`. (tape-authenticator 1.0.0 → 1.0.1; `test_tape_auth` +6.)
- **Login F10 (shut down) just looped back to the login screen.** The caller
  captured `local ok, result = pcall(loginScreen.run, …)` and dropped the second
  return value (the `"shutdown"` reason). It now acts on it.

### Operator experience — visibility + a leaner command set
Making "what TOS is doing" visible and the command surface easier to understand.
- **Live System Monitor.** Ctrl+T's task switcher grew into a full System Monitor
  (also `monitor`, alias `top`): one auto-refreshing screen with every process —
  kernel AND user, each given a plain-English label (e.g. `login@2` → "Login
  broker — seat 2", `shell:root@1` → "Shell — root (seat 1)") — plus owner, state,
  CPU and seat; the rc.d **services** with status; and memory/uptime vitals. It's
  interactive: switch-to / kill / suspend (TSR) a process, and start/stop a
  service (admin), all from the one view. The pure helpers (labelling, the unified
  row list, header-skipping navigation, mem bar, uptime) live in `kernel.monitor`
  with `test_monitor.lua` (28 cases).
- **Per-command help for everything.** Only ~two dozen commands had a hand-written
  help page; the rest fell through to the big reference. `help <cmd>` now falls
  back to a focused, registry-driven entry (one-liner + minimum tier + group) for
  ANY command, so every command has its own help. New detailed pages for `pkg`
  and `monitor`. `test_command_registry.lua` guards that every command carries
  help text.
- **Command prune / unify.** The legacy `mod` command (the module manager it
  fronted was retired in v1.3.1) was removed; its unique `enable`/`disable`/
  `commands` subcommands were folded into `pkg`, which now also gains `install`/
  `search` in the fallback CLI shell — so both shells drive packages the same way
  via `pkg`. Dropped the redundant third launcher alias `launch` (kept `launcher`
  + `apps`). `pkg info` now shows enabled status + provided commands.

### Live tabs + command enhancements + docs
- **Live tabs.** A view tab can now regenerate its own content on a timer (the
  event loop ticks the front tab). New `watch [seconds] <command>` opens a
  self-updating tab for any read-only command — `watch ps`, `watch 2 df`,
  `watch net peers` — the live counterpart to running it once for static output.
  `r` refreshes now, `q`/F4 closes; interactive/screen commands are refused.
  Only the active live tab ticks (backgrounded ones don't burn cycles).
  (`editor.openLiveTab`/`refreshLiveTab`, `test_live_tabs.lua`.)
- **System-info commands enhanced + separated.** `mem` is now a real memory
  report (used/total + bar, RAM tier, swap usage, low-RAM warning); `df` shows a
  per-mount usage bar + %; `hw` is a hardware inventory (tiers incl. data card,
  components, network). Each cross-references the others (`mem`/`hw`/`monitor`/
  `df`/`du`) so overlapping commands have distinct roles. They share the
  monitor's `memBar`.
- **More command separation.** `doctor` = RUNTIME health, `verify` = FILE
  integrity — each now states which and points at the other (help, headers,
  See-also). `disk` = removable media (list/info/install/eject) and no longer
  claims "pool management" (that's `jbod`); its help/usage cross-reference `jbod`
  (pooling) and `df` (space), and the dead `disk export` is gone from the usage.
  `device` corrected to "device type + hostname" (it never showed an
  address/port and needs no modem). Stale `mod enable tape` hint → `pkg enable
  tape`.
- **Display-buffer observability.** The display-layer performance optimizations
  (a memory-gated dirty-cell shadow buffer that skips `gpu.set`/`fill` for
  unchanged cells, plus the colour-state cache and operator control) were already
  implemented in `kernel.screen`. Added session hit-rate counters
  (`screen.bufferStats`) shown by `optimize show` — e.g. "this session: 45231 of
  58900 cell-draws skipped (77%)" — so the saving is visible, not just a toggle.
  A MANUAL `optimize` entry documents both optimizations. (`test_screen_shadow`.)
- **Mail TUI.** Mesh email gets an interactive full-screen client (like `chat`):
  running `mail` with no subcommand opens the inbox — navigate, **Enter** to read
  (marks read), **c** compose (recipient/subject/multi-line body), **r** reply,
  **d** delete, and the inbox refreshes live (~2s) so mail arriving while you're
  open shows up. The `mail send/list/read/delete` subcommands stay for scripting
  and the minimal CLI. New `shell.mail` module; pure helpers (sender naming, row
  formatting, recipient resolution) in `test_mail_tui.lua`.
- **Splash no longer bleeds into login/shell/shutdown.** The splash boot-progress
  hook stayed wired into the logger after boot, so every later INFO log redrew
  the loading bar + narration over the UI. `log.detachEarlyPrint()` (called at
  the boot→shell handoff) now tears it down too. (`test_log_bootprogress.lua`.)
- **Docs.** The manuals are now treated as external "sits beside you" reference
  books and excluded from the lean TOS-Release image (with `TODO.txt`); `man`/
  `help` remain the in-OS help. MANUAL.md synced to the current command set
  (`mod`→`pkg`, Ctrl+T = System Monitor, new `monitor`/`watch` entries). A Dev
  roadmap lives in `TODO.txt`.

---

## v1.3.2 "Argus" — Security fixes & a friendlier shell

A focused security-and-usability release. The security fixes are the headline;
the TUI changes are additive and change no layout or key bindings.

### Security fixes
- **Process control is admin-gated again (`fg`/`kill`).** The panels command
  executor performs no dispatch-level tier check — privileged commands rely on
  an in-body `adminOnly`/`rootOnly` guard (the documented belt-and-braces line).
  `fg` and `kill` (REGISTRY tier 2, like their siblings `bg`/`run`) were missing
  that guard, so any logged-in user — including GUEST — could invoke them.
- **`setForeground` now enforces TARGET-process ownership (#SEC H13).** This was
  the real teeth behind the `fg` gap: `proc.tick` routes a seat's input
  (`key_down`/`touch`/…) to `displayForeground[seat]`, so a caller that could
  name an arbitrary PID could point its *own* seat at another user's process and
  have its keystrokes delivered there — input injection into a higher-privileged
  session. `kill`/`signal`/`goTSR` already gated the target via
  `callerMayControl`; `setForeground` only checked the seat. It now mirrors them
  (kernel-initiated calls — boot seat-spawn, the task switcher — still bypass, as
  those do). Fix lives in the kernel so it covers every caller, not just the
  panels shell.
- **File serving is fail-closed (`kernel.net.transfer`).** `transfer.init()` runs
  unconditionally at boot whenever networking comes up, and the FILE_REQ server's
  enable flag defaulted to `true` — so file serving was armed even on a machine
  whose operator removed or never started the `fileshare` service. It now
  defaults to `false` and tracks the service lifecycle, matching
  `kernel.net.remote`/`rshd` (#SEC L). Stock boots are unchanged: `fileshare`'s
  `start()` arms it.
- **Lua REPL gates on the live tier (#SEC M-7).** `lua` checked the cached
  `S.userTier` snapshot taken at panel construction instead of the seat's current
  session, so a session demoted/expired mid-session kept root-REPL access. It now
  uses the live-tier `rootOnly` gate like every other privileged command.
- **Package commands no longer leak the first loader's filesystem ACL.**
  `kernel.pkg`'s `loadPkgEntry` caches one sandbox per package and shares it
  across every caller, but it bound that sandbox's securefs `fs` proxy to
  whoever ran the command *first*. If root (or the root-tier boot session)
  loaded a command, a later GUEST/USER running the same command inherited
  root's filesystem permissions (a package declaring `fs.read`/`fs.write` thus
  became a confused-deputy privilege-escalation path). The loader now builds
  the sandbox with no captured session, so securefs resolves the LIVE caller
  per-call (`forSession(nil)` → `process.currentSession`) — matching what
  `compat.filesystem` already did — and fails closed post-boot when there is no
  live session.
- New regression tests: `test_fg_ownership.lua` covers the `setForeground`
  target-ownership check end-to-end through the scheduler, and
  `test_pkg_session_isolation.lua` proves a guest invocation of a root-loaded
  package command runs as the guest (it fails on the pre-fix code).

### Shell usability (additive — no layout or keybinding changes)
- **Function-key legend.** The shell's output row, previously blank when idle,
  now shows a width-responsive F-key legend (`F1 Help · F3 View · F5 Copy …`),
  the classic file-manager affordance. It disappears the instant a command
  produces output and degrades gracefully on narrow screens.
- **Help menu.** A new rightmost `Help` menu (Quick Help, Keyboard Shortcuts,
  Manual Pages, Tutorial, About) makes discovery easy for users who don't yet
  know the bindings. Every entry runs an existing guest-safe command except
  "Keyboard Shortcuts", which opens a read-only key reference.
- Smoke test `test_panels_help_ui.lua` covers the new menu wiring and legend
  rendering across screen widths.

---

## v1.3.1 "Polaris" — Configurable boot, resilience & packaging

An internal-improvement release. New subsystems are fail-safe and default to
the v1.3.0 behavior, so a stock boot is unchanged except for a brief hardware
POST screen.

### Boot reorganization
- **`/etc/boot.cfg` boot spectrum** (`kernel/bootcfg.lua`): `profile`
  (minimal/normal/full/diagnostic) gates *what loads*; `verbosity`
  (silent/splash/text/verbose) is a "muter" for *what boot says* (it maps to
  the kernel-log early-echo threshold and changes nothing about behavior);
  `advanced` per-feature toggles override the profile; `cpuTier` + `showConfig`.
  Read very early in `init.lua`, fail-safe to `normal`.
- **System Configuration screen** (`kernel/sysinfo.lua`): enumerates hardware
  and infers a tier for each piece (RAM, GPU depth, screen resolution, disk
  capacity, data-card method set), splitting System / Storage / Peripherals.
  CPU tier resolves detect → operator-override → RAM-estimate → unknown (plus an
  opt-in behavioral benchmark, never run at boot). Renders an AMIBIOS-style box.
- **Modular optional-stage gating**: `kernel.boot` consults `bootcfg.wants()`
  for swap/power/theme/net/compat/audio instead of a raw RAM check.
- **Boot Settings** (`kernel/bootsettings.lua`): a DEL-during-boot visual editor
  + a `bootsettings` shell command; both write `/etc/boot.cfg`.

### Power-loss protection
- **Unsafe-shutdown detection**: dirty-bit marker at `/var/run/pwrstate`
  (`running` at boot, `clean` only by `kernel.shutdown`); flagged via log,
  login banner, and `doctor`'s new power section.
- **Atomic writes** (`fs.writeFileAtomic` + boot-time `fs.recoverAtomic`) for
  `users.dat`, `trust.dat`, and everything via `serialize.saveFile`
  (config/cron/pkg/critical.bak) — a power cut mid-save can't truncate them.
- **Critical battery → clean shutdown** (config-gated `critBatShutdown`).

### Disk swap
- `kernel/swap.lua`: explicit spill-to-disk store API + a `swap.table{ hot=N }`
  disk-backed table (LRU hot-cache), capped, volatile (wiped each boot). `swap`
  command and a `swap` sandbox capability. (OC has no transparent paging; this
  is opt-in cold-data offload.)

### Disk compression
- `kernel/compress.lua`: data-card deflate/inflate wrapped in a self-describing
  `.tcz` container (chunked, integrity-checked). Detection-gated — falls back to
  a "stored" frame (no card needed to read) when no data card is present, and
  refuses to "compress" data that wouldn't shrink.
- **`compress` / `decompress` commands** (panels + CLI shells; hidden from
  install-aware help without a data card) shrink files on small disks.
- **Swap auto-compresses** spilled data when a data card is present, so more
  fits under the cap (`swap` status shows `compressed`); card-less boxes are
  unchanged. New `kernel.getCompress()` accessor; `man compress`.

### Dynamic screen resolution
- `kernel/screen.lua`: a resolution **policy** replaces the old "always max out"
  behavior. `chooseResolution` (pure) + `specFromConfig` + `gpuTarget` +
  `fit`/`restore`. Modes: `auto` (default — density-based from the screen's
  physical block size via `getAspectRatio`, ~80x25 cap fallback), `max`, or an
  explicit `WxH`. All clamped to the hardware max with a warning when a request
  doesn't fit.
- **Fixes T3 tiny-text**: a tier-3 GPU on a big screen no longer renders the TUI
  at 160x50 micro-text; `auto` downscales to a readable size. `display.init` and
  the multi-seat `screen.init` both honor the policy.
- **`screen res [auto|max|WxH]`** command: shows current/max/blocks/policy, or
  (admin) sets it — applied live (re-fits the panels layout + redraws) and saved
  to `/etc/tos.cfg` (`screenRes`, `screenColsPerBlock`, `screenRowsPerBlock`).
- **Programs declare a size**: manifest `screen = { width=, height=, mode= }`
  (`exact`/`min`), validated by `pkg`; the executor fits the screen before a
  packaged command and restores afterward. `pkg.getCommandScreen`; `man screen`.

### Package manager (pivot from kernel.modules)
- **`command`/`program` kinds** are now first-class (Extras modules use them).
- **Narrow service `/etc` exception**: a `kind="service"` package may write its
  own `/etc/rc.d/<f>.lua` + `/etc/<name>.cfg` (and nothing else under `/etc`);
  re-enables cluster-style installs while leaving the CR-4 kernel-overwrite
  guard intact.
- **`pkg.getCommand`**: package-provided commands now run via pkg's own
  sandboxed dispatch (caps from the manifest), wired into the shell executor —
  the first step toward retiring the legacy module manager. Bundled manifests'
  `commands` moved to `name → entry` map form.

### Help, UI & layout
- **Install-aware help**: `help` hides commands whose dependency
  (`net`/`swap`/`component:<t>`/`module:<n>`/…) isn't present; `M.helpList`
  + `M.needMet`. Manual page-flag hook in place (Manual content TBD).
- **PaneUI** (OpenOS) synced to TOS's six named themes, color-for-color, with
  `theme`/`themes` commands (v0.3).
- **Optional Utilities disk** (`TOS-Extras/build/`): a pick-and-choose installer
  + assembler for the bundled add-ons.
- **Cluster relocated** out of `kernel/net/` into the optional cluster package
  (`cluster.lua`→`cluster/protocol.lua`, `cluster_worker.lua`→`cluster/worker.lua`);
  the dormant kernel auto-start was removed. The `cl_*` wire types + trust
  permissions stay in core so packets still route.

### Security / correctness fixes
- **KDF / login speed**: the iterated password KDF and per-packet MACs run in
  pure-Lua software, and the round count is a single modest value (256) on every
  box. A mid-cycle experiment that routed the HMAC primitive through the data
  card and bumped data-card boxes to 10000 rounds was reverted: in OpenComputers
  a component call draws from a per-tick budget and sleeps the computer when
  it's spent, so a ~20k-call KDF stalled boot/login to ~150 s — and no
  OC-computable round count meaningfully slows real (off-box, GPU) cracking
  anyway, where the salt is the protection that holds. The data card still
  handles AES, hardware RNG, and one-shot SHA-256. Password hashes are
  unaffected (identical SHA-256 either way); v3 is now the universal write
  format, and legacy/high-round records are rehashed to the fast form on next
  login.
- **Network MAC** binds the real destination (`net.send` now stamps `packet.to`),
  making the documented anti-redirection guarantee non-vacuous.
- **`users.getUser()`** no longer returns salt/hash in its projection.
- **BIOS** shrunk under the 4 KiB EEPROM limit (factored the repeated
  wait-for-key/reboot loop); the Shift+Enter one-time boot is now functional
  (passed to init as `_BIOS_ONETIME`, suppresses the floppy→HDD migration).
- Misc: pkg OPPM `command`-kind install fixed; path-boundary root edge case;
  fileshare/rshd docs + default-disabled remote-exec.

### Tests
- New suites: `test_sysinfo`, `test_bootcfg`, `test_bootsettings`,
  `test_power_state`, `test_swap`, `test_help_aware`, `test_pkg_command`,
  `test_kdf_software` (asserts the KDF makes zero data-card calls + KAT vectors),
  `test_compress` (pack/unpack stored+compressed paths, multi-chunk, card gating,
  swap round-trip), `test_screen_res` (chooseResolution modes/clamping + the T3
  downscale + specFromConfig) (+ expanded `test_pkg_trust`, `test_path_boundary`).
  Full suite green.

---

## v1.3.0 "Aegis" — Security Hardening

A full security-audit pass. One agent per top-level module audited the OS in
parallel; this release closes **every** consolidated finding across all four
severity tiers (9 Critical, 21 High, 21 Medium, 7 Low). No new user-facing
features — this is a correctness/security release.

Each fix was traced against its original finding, regression-checked against
the standalone test suite, and most are backed by a new test under
`/usr/lib/tests/`. A few findings were confirmed already-mitigated by earlier
work rather than re-patched (noted inline).

### Critical

- **Cluster worker is now default-deny.** The Manager↔Worker bridge refuses to
  bind its port unless a shared secret is configured (`shared_secret` in
  `/etc/cluster.cfg`), installed before `setDomainId`. Previously, with no
  secret, any device could `REGISTER` during the bootstrap window and have
  dispatched Lua `code`/`output` flow into a result callback. (`cluster_worker.lua`, `init.lua`)
- **`pkg.install` now verifies integrity and confines writes.** Files are
  checked against `m.hashes[target]` with a constant-time compare before
  writing, and writes are confined to `/usr` and `/var/pkg` (normalized,
  escape-rejecting). A manifest can no longer overwrite the kernel. (`pkg.lua`)
- **Admin gate on every install/uninstall/enable path.** `pkg` and `modules`
  privileged entry points now require an ADMIN+ session (threaded from the
  caller's seat); boot-internal calls use a private bypass. (`pkg.lua`, `modules.lua`, shell command sites)
- **rc.d kernel-tier services get a gated `require`.** Kernel-tier boot
  services can only require a safe allowlist (`computer`, `component`,
  `kernel.event/log/serialize/config`); `require("kernel.process")` and friends
  are denied. (`rc.lua`)
- **Vault/keychain fail closed without real crypto.** The keychain refuses to
  persist secrets when only the XOR fallback is available (no data card). The
  vault wire format is now V2 with domain-separated enc/mac subkeys (no more
  single-key reuse); V1 blobs still decrypt. (`vault.lua`, `keychain.lua`)
- **`term.gpu()` is seat-bound and capability-gated.** Resolves the caller's
  seat GPU (not the first component GPU) and denies all mutating operations
  unless the process holds a display capability — closing cross-seat draw/
  rebind access for sandboxed programs. (`compat/term.lua`, `sandbox.lua`)
- **Shell ACL checks use the bound seat principal.** `canRead`/`canWrite` and
  the trash/vault/keychain/mount paths now resolve the seat's session token
  via `canAccessAs(...)` instead of the module-global `currentSession()`,
  which was nil (single-seat) or another seat's session (multi-seat). (`helpers.lua`, `core.lua`, `admin.lua`, `widgets.lua`)
- **Net replay protection has freshness.** Each packet carries a per-peer
  monotonic sequence plus a per-boot epoch, both bound into the MAC; the
  receiver rejects a non-increasing sequence so a captured packet can't replay
  after its nonce ages out of the window. Per-peer state is bounded. (`net/init.lua`)
- **Constant-time MAC/nonce comparisons** and empty-server-nonce rejection in
  peer verification (carried in from the prior review). (`net/init.lua`, `crypto.lua`)

### High

- Packet/frame MACs now bind type/to/algo (and the whole WRK frame via a
  canonical, key-sorted encoding) so a captured packet can't be re-typed,
  redirected, or partially forged.
- `createSession` no longer accepts a stored password hash as a credential.
- Login no longer leaks username existence or lock state (uniform errors +
  timing); the root account — exempt from permanent auto-lock — now gets a
  reboot-proof exponential backoff so it can't be brute-forced online.
- First-boot setup is parameterized to the actual principal (no hardcoded
  `root`); package manifests reject path traversal; backup restore rejects
  paths that escape the destination root.
- ACL path checks normalize before matching (fail closed on NUL/traversal).
- Persisted audit timestamps use a wall clock; session-liveness stays on
  monotonic uptime.
- The `flash` BIOS fingerprint is SHA-256-only (full digest) — the weak FNV
  fallback is gone; the typed-`flash` confirm remains the real gate.
- Relay forwarding gained payload dedup + a per-upstream-peer rate limit
  (neither trusting the attacker-supplied `path`), closing the amplification
  vector.
- Session tokens get cross-boot entropy accumulation (`/etc/entropy`) plus a
  one-time degraded-RNG warning on data-card-less boxes.
- `pkg` dependency-confusion closed: a repo package must match its directory
  name, and floppy installs never default to accept-all.
- Plus: `os.tmpname` precedence, `filesystem.list` ACL-error propagation,
  proc signal/kill nil-principal bypass, `safeSetMetatable` guard, and raw
  `component` access via the shell `component` command.

### Medium

- `fs.normalize` fails **closed** on tainted input (NUL/non-string → `nil`
  sentinel) instead of collapsing to the privileged root `/`.
- Unfiltered `event.pull` discards sensitive signals within the deadline (no
  signal-name leak, no scheduler spin).
- Chat receive path requires a TRUSTED sender; file-transfer validates the
  actor before interpolating it into `/home/<actor>` allowlists.
- Strict UUID matching in `aliases.resolve`; JBOD `remove` requires all-member
  success (no ghost files).
- Privilege gates read the **live** session tier (fail closed on an
  expired/revoked token), not a cached snapshot.
- Degraded-boot ACL fallbacks fail closed (`find`, `vault`, `canAccess`).
- `cron` registry tier aligned with its in-body admin gate; `mount`
  address-prefix matching is deterministic (ambiguous prefixes refused).
- PID reuse can no longer rebind a stale event listener to a new principal —
  each spawn carries a generation token validated at dispatch.
- `os.getenv` dropped from the sandbox `os` table (host-env leak); sandbox
  user-library loads re-check the session read ACL.
- `serialize` encode/decode depth limits aligned (64); over-depth now raises
  instead of silently truncating the wire form.
- Last-administrator lockout guard: refuse to demote or lock the final usable
  privileged account (including root).
- `chatpair` no longer compares cross-machine uptimes; `strip.lua` hard-errors
  on an unterminated comment/long-string instead of silently truncating a
  release; peripheral drivers coerce/range-check slot/count args and route all
  hardware ops through the capability check.

### Low

- `serialize.decode` rejects non-finite numbers (`inf`/`-inf`/`nan` and
  overflow literals) that would crash downstream `table.sort` comparators.
- Bounded several per-peer maps that grew without limit (net nonce set,
  chatrelay rate map) and de-duplicated the HAL component list.
- The `rshd` / `fileshare` services' `stop()` now actually disables the remote-
  exec / file-serving handlers (previously a no-op flag flip).
- `log.flush` appends via a file handle instead of read+rewrite of the whole
  log; the syntax highlighter caps tokenization on pathologically long lines.
- Password policy centralized in `users` (single `MIN_PASSWORD_LEN`).
- `serialization.unserialize` returns `(nil, error)` cleanly; `io.lines`
  closes its file descriptor eagerly on read error.

### Notes for operators

- **Cluster Managers must set `shared_secret` (16+ bytes) in
  `/etc/cluster.cfg`** or the worker bridge will not start (default-deny).
- **The keychain requires a data card.** On software-only boxes it now refuses
  to persist secrets rather than protect them with XOR.
- Network peers must be upgraded in lockstep: the packet MAC format changed
  (epoch+sequence are now bound into it).

---

## v1.2.6 "Beacon"

See `README.md` for the v1.2.6 and v1.2.5 feature notes (themes, QoL commands,
multi-seat, manifest completeness).
