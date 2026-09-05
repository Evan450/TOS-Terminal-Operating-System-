# selftest — checks that only mean anything on real OpenComputers

Source for the TOS self-test battery. These files are **not** part of the
base image: they go on a test disk, and `kernel/selftest.lua` discovers
any mounted `/mnt/<label>/selftest/*.lua`.

To run a round:

1. Put `checks/` onto a disk as `selftest/`.
2. Put a `selftest.on` file on that same disk — either at its root or inside
   `selftest/`. `selftest.on.example` here is a ready-made one.
3. Boot with the disk inserted. Results land in `/var/selftest.log`, beside
   `kernel.log`, which on Ocelot and ocvm is an ordinary host directory you
   can read directly.

That is the whole procedure: **no shell, no root, nothing to type.** The
disk that carries the checks is the disk that says "run them".

`/etc/selftest.on` also arms it, but do not reach for that first. `/etc` is
securefs-protected, so `echo > /etc/selftest.on` is DENIED — and the shell
reports the write as successful while no file appears, which is exactly how
the first real round was lost. There is now a `WRITE_PROTECTED_EXEMPT` entry
so an admin *can* create it, but a marker needing an exemption to create is
a worse marker than one that rides in on the disk.

Add `shutdown=true` to the marker to power the machine off when the run
finishes, which is what makes it usable from CI.

## What belongs here

Only checks whose answer depends on **real hardware or a real booted
kernel**. Anything that is a pure function of its inputs belongs in
`TOS-Dev/usr/lib/tests/`, where it runs in a second on every commit —
`sha256` and `ed25519` are proven by FIPS and RFC vectors off-box and
gain nothing from a Minecraft round.

The useful test is the inverse: **does the real thing behave the way our
stubs said it would?** Every off-box test mocks a GPU, a filesystem or a
modem. This is where those mocks get audited.
