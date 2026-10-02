# selftest — checks that only mean anything on real OpenComputers

Source for the TOS self-test battery. These files are **not** part of the
base image: they go on a test disk, and `kernel/selftest.lua` discovers
any mounted `/mnt/<label>/selftest/*.lua`.

To run a round:

1. **Arm the test machine, once:** create `/etc/selftest.on` on it. On Ocelot
   and ocvm the machine's disk is an ordinary host directory, so drop an empty
   file there from the host (`build/sync-emulator.py` does this for you); on a
   running TOS box, root can run `echo > /etc/selftest.on`. Only root: arming
   the battery lets whatever is on the test disk run inside the kernel, which
   is more than an admin holds.
2. Put `checks/` onto a disk as `selftest/`.
3. Put a `selftest.on` file on that same disk — either at its root or inside
   `selftest/` — to carry the run's options. `selftest.on.example` here is a
   ready-made one.
4. Boot with the disk inserted. Results land in `/var/selftest.log`, beside
   `kernel.log`, which on Ocelot and ocvm is an ordinary host directory you
   can read directly.

**Why the machine has to be armed.** The battery runs every check it finds
*inside the kernel* — that is the point of it — and TOS mounts every disk in
the drive at boot. When a `selftest.on` on the disk was enough to arm it, any
floppy carrying one plus a `.lua` file was full kernel code execution at the
next boot, with no login. So the machine decides *whether* checks run, and the
disk decides *which* ones and with what options. An unarmed machine that boots
with a test disk inserted says so on the boot console instead of doing nothing
silently.

Add `shutdown=true` to the disk's marker to power the machine off when the run
finishes, which is what makes it usable from CI. For each option, the first
marker that sets it wins, checking `/etc/selftest.on` first — so the usual
empty machine marker leaves the disk's options in force.

## What belongs here

Only checks whose answer depends on **real hardware or a real booted
kernel**. Anything that is a pure function of its inputs belongs in
`TOS-Dev/usr/lib/tests/`, where it runs in a second on every commit —
`sha256` and `ed25519` are proven by FIPS and RFC vectors off-box and
gain nothing from a Minecraft round.

The useful test is the inverse: **does the real thing behave the way our
stubs said it would?** Every off-box test mocks a GPU, a filesystem or a
modem. This is where those mocks get audited.
