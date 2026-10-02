# selftest — the boot self-test battery

Checks that only mean anything on real OpenComputers, and the `selftest`
command that drives them. The runner is part of the base image
(`tos/kernel/selftest.lua`): an **armed** machine runs every check it finds
at boot, **inside the kernel**, before the shell comes up, and writes the
results to `/var/selftest.log`.

This package exists so a developer can test what they add to TOS on a
booted machine, not just off-box. It installs the shipped checks into
`/usr/lib/selftest/`, which the runner already searches, and gives you a
command for the rest.

## Install

```
pkg install selftest        # as root
```

Root, not admin: a check runs as the kernel, so `pkg` holds any package that
puts a file in `/usr/lib/selftest/` to the same root gate as a service
package.

## Use

```
selftest                    armed?  what will run?  how did the last run go?
selftest arm [shutdown] [screen] [only=<prefix>]    run it at the next boot (root)
selftest disarm             stop running it at boot (root)
selftest list               every check an armed boot would run, and where from
selftest log [all]          the last run: failures, skips and notes (all: every line)
selftest template [file]    a starting point for a check of your own
```

`arm` writes `/etc/selftest.on`. Arming is **root only**, because it lets
every check in `/usr/lib/selftest/` and on any test disk run inside the
kernel at the next boot. Reboot to run the battery. `shutdown` powers the
machine off when the run finishes, which is what makes the battery usable
from CI. `only=20-` runs just the checks whose names start with `20-`.
`screen` lets checks that **draw** on the boot console run (see below).

The battery deliberately **cannot be run from the shell**. Several checks
exist to test kernel context before the TUI is up, so from a shell they
would be testing something else and reporting it as the same thing.

## Writing a check

A check is a `.lua` file that returns one function. `selftest template`
prints a commented starting point. The function receives `t`:

| | |
|---|---|
| `t.ok(name, cond)` | passes when `cond` is true |
| `t.eq(name, expected, got)` | the same, naming both values on a failure |
| `t.skip(name, why)` | the check cannot run here (no card, no printer). A skip is never a failure. |
| `t.note(text)` | an observation for the log, with no verdict |
| `t.cfg.screen` | true when the round allows drawing on the boot console; ask before you draw |

Checks run inside the kernel, at boot: `computer`, `component` and
`require("kernel.*")` are all there. `package.loaded` is snapshotted and
restored around each check, so stub modules freely. Put back anything else
you change on the machine.

Get your check run in one of three ways:

- **a test disk:** put the check in a `selftest/` folder on any disk.
  Every mounted disk's `selftest/` is searched.
- **your own package:** install it under `/usr/lib/selftest/`. That is a
  root install.
- **here**, if it belongs with the battery.

Name checks `NN-what.lua`. They run in name order, and every check writes
`RUN <name>` **before** its body runs, so a run that wedges the machine
leaves a log whose last line names the culprit and has no `SELFTEST END`.
`selftest` reports that as **STALLED**.

## What belongs in the battery

Only checks whose answer depends on **real hardware or a real booted
kernel**. Anything that is a pure function of its inputs belongs in
`TOS-Dev/usr/lib/tests/`, where it runs in a second on every commit.
`sha256` and `ed25519` are proven by FIPS and RFC vectors off-box and gain
nothing from a Minecraft round.

The useful test is the inverse: **does the real thing behave the way our
stubs said it would?** Every off-box test mocks a GPU, a filesystem or a
modem. This is where those mocks get audited.

## What the shipped checks touch

Run the battery on a machine you can reboot. Each check's header says what
it does. The ones with side effects:

- `40-fs-roundtrip` and `94-rename-truth` write and remove temporary files;
- `50-srm` takes and inspects a baseline in a scratch location;
- `80-pkg-signing` swaps the trust policy for the run and restores yours,
  including when it fails;
- `93-audio` beeps;
- `20-display` and `70-screen-truth` draw on the console only with `screen`.

## Without installing it: the emulator workflow

`TOS-Dev/build/sync-emulator.py` copies the release onto an Ocelot boot disk,
copies these checks (`usr/lib/selftest/`) onto a test floppy, and creates
`etc/selftest.on` on the boot disk. A test disk's own `selftest.on` carries
options only (`selftest.on.example` is a ready-made one); it never arms
anything. A disk that could arm the battery would be a floppy that runs code
inside the kernel at the next boot.
