# TOS — Terminal Operating System

**A multi-user operating system for the OpenComputers Minecraft mod.** Logins, per-user permissions, a capability sandbox, signed packages and an encrypted mesh network.

**Requires OpenComputers 1.7.5 or newer, on Minecraft 1.12.2**, with a CPU set to the **Lua 5.3 or 5.4 architecture**, 1 MB of memory and a hard drive with about 1.9 MB free. Details under [Requirements](#requirements).

Current release: **v1.5.0 "Aletheia"** — see [`CHANGELOG.md`](CHANGELOG.md) for what changed.

<!-- SCREENSHOTS -- see docs/screenshots/SHOTS.md for the shot list and how to
     capture them. Delete this comment wrapper once the files exist on `dev`;
     the URLs are absolute so the same README renders on every branch.

<p align="center">
  <img src="https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/dev/docs/screenshots/desktop.png"  alt="The Desktop: a tile home screen" width="49%">
  <img src="https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/dev/docs/screenshots/rbmk.png"     alt="The RBMK reactor supervisor" width="49%">
</p>
<p align="center">
  <img src="https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/dev/docs/screenshots/boot.gif"     alt="Boot to login to Desktop to a theme switch" width="80%">
</p>
-->

**Contents:** [Install it](#install-it) · [Your first ten minutes](#your-first-ten-minutes) · [What's in it](#whats-in-it) · [Why not just use OpenOS?](#why-not-just-use-openos) · [Requirements](#requirements) · [Add-ons](#add-ons) · [Known limitations](#known-limitations) · [Where to go next](#where-to-go-next) · [License](#license)

## Install it

On an OpenOS machine with an Internet Card, type one line:

```
wget -f https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/main/bootstrap.lua /bootstrap.lua && /bootstrap.lua
```

> [!IMPORTANT]
> Keep the leading slash in `/bootstrap.lua`. `wget` saves the file at the root of the drive, and the root is not on OpenOS's search path, so plain `bootstrap.lua` answers "command not found".

The installer asks a few questions — what kind of machine this is, how strict logins should be, whether to encrypt network traffic — and then offers to write the TOS BIOS: type `flash` to accept. No Internet Card, or want to know what each question does? [MANUAL §1.2](MANUAL.md#12-installing-tos) covers installing from a disk and every question.

## Your first ten minutes

1. **Set root's password.** The first boot asks for it before anything else.
2. **Take the tour**, or press Ctrl+Q to skip it. `tutorial` brings it back.
3. **Look around.** The Home tab shows your files, or tiles of everything this machine can do; F2 flips between the two. The prompt sits at the bottom of both.
4. **Ask for help.** `help` lists every command you can use, `help <name>` explains one, and `why` explains the last thing that refused you.
5. **Make an everyday account.** `useradd alice` asks for her password twice; the account starts as a USER, and `usermod alice admin` raises it. `logout`, then log in as her: root is for administration, not for living in.
6. **Pick a look.** `theme list`, then `theme set midnight`.
7. **Install an add-on.** As an admin, see [Add-ons](#add-ons).

## What's in it

- **Accounts and permissions** — real logins, four tiers (guest, user, admin, root), per-user home directories and access lists, `sudo`, session timeouts, lockout with backoff.
- **A capability sandbox** — programs receive only what they declare and are granted: no ambient `_G`, no raw `component`, no back door into the kernel.
- **Signed packages** — `pkg` installs from a floppy, a folder or over the network, checking an Ed25519 signature and a hash for every file on arrival.
- **A zero-trust mesh** — peers are unknown until paired; trusted traffic is encrypted and authenticated, with replay protection.
- **A tile Desktop and a file browser**, nine colour themes, and a full reference manual — [`MANUAL.md`](MANUAL.md), *The Book of TOS*.
- **OpenOS compatibility** — 15 of OpenOS's libraries, so much of what already exists still runs, and OPPM packages install.

## Why not just use OpenOS?

OpenOS gives you a shell. TOS gives you accounts and logins, per-user file permissions, a capability-based sandbox that user programs cannot escape, package signing, and an authenticated encrypted mesh between machines.

It is **keyboard-first and built to run infrastructure**: a base that has to keep working. It runs on a Tier 1 monochrome screen, gives every GPU and screen pair its own independent session, survives power loss without corrupting its own files, and ships a cluster scheduler and an RBMK reactor supervisor for bases that need one. If you want a graphical desktop on a maxed-out machine, MineOS is the better answer, and this is not trying to be it.

## Requirements

| | Memory | What you get |
|---|---|---|
| Minimum | 1 MB (one Tier 3.5 stick) | The command line, which runs every command and loads each one as you use it. TOS starts there by itself on a machine this size. About 35 KB stays free. |
| Recommended | 1.5 MB (two Tier 3 sticks) | The full panels interface, with about 200 KB free after you log in. |
| Comfortable | 2 MB (two Tier 3.5 sticks) | Room for add-ons, themes and the OpenOS compatibility layer: about 730 KB free after you log in. |

Below 1 MB TOS does not reach a usable shell. At 768 KB the main shell cannot load and the boot falls back to the emergency terminal; at 384 KB or less the kernel itself does not fit. (Measured on a fresh install, logged in, after one command.)

- **Drive**: about 1.9 MB free. A Tier 2 drive (2 MB) holds TOS on its own. Installing from OpenOS onto the same drive needs a Tier 3 drive (4 MB), since OpenOS is still there while TOS copies. TOS does not fit on a floppy.
- **CPU**: any tier, on the Lua 5.3 or 5.4 architecture — sneak-click the CPU to switch it. On a 5.2 CPU the BIOS stops and says so.
- **GPU**: any tier, detected automatically. Tier 1 is monochrome, so themes are off there; Tier 2 snaps themes to its 16 colours; Tier 3 shows them exactly.
- **Several screens**: each GPU and screen pair is its own seat, with its own login. One computer has one CPU, so it works best when people take turns — see [MANUAL Chapter 1](MANUAL.md#1-what-tos-is).

## Add-ons

Games, a spreadsheet, mail, a printer driver, tape tools, a filesystem for raw drives, the cluster control plane and more ship separately from the OS as the **Optional Utilities**. With an Internet Card, as an admin:

```
pkg repo add utils https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/optional-utilities
pkg search
pkg fetch calc
```

Or insert an Optional Utilities disk and run `pkg install` to pick from a menu. Every package is signed and its files hash-checked; [`TOS-Extras/README.md`](TOS-Extras/README.md) lists them all.

## Known limitations

- **OpenOS programs run on a best-effort basis.** A program that reaches for raw components or the global environment runs into the sandbox. Programs that use OpenOS's documented libraries generally work.
- **One theme for every seat.** The last person to log in, or to change the theme, sets the colours everyone sees.
- **The remote shell is off by default.** `rshd` is registered but not started; `service start 20-rshd` turns it on, and even then only TRUSTED peers can use it.
- **An unverified package needs a deliberate yes.** `pkg install` refuses a package that does not list a SHA-256 for every file, unless you add `--allow-unverified`. A *service* package's setup runs with the authority it declares, so installing one trusts its author with the machine.
- **Seats are bound at boot.** Swapping or renaming screens while TOS runs can leave a seat without input until the next reboot.
- **TOS cannot stop a runaway program.** OpenComputers keeps the hook that preemption would need, so a program that never yields runs until OpenComputers restarts the computer.
- **The boot files are not signed.** The BIOS checks that `/init.lua` parses, not what it contains, so anyone who can write the boot files (an admin) can run code before login.
- **Without a data card, network encryption is weak.** TOS falls back to XOR with a hashed key. Every packet is still authenticated and protected against replay, but its contents are poorly hidden. A machine with a data card refuses XOR packets.

[MANUAL Chapter 15](MANUAL.md#15-the-security-model-in-one-place) has the whole security model, including these.

## Where to go next

| | |
|---|---|
| [`MANUAL.md`](MANUAL.md) | *The Book of TOS*: installing, every command, the security model, configuration, recovery |
| [`docs/API.md`](docs/API.md) | The kernel's functions, for writing add-ons |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Working on TOS: setup, tests, house rules. Work on `dev`, never `main` |
| [`ROADMAP.md`](ROADMAP.md) | What is still open, including what was deliberately not done |
| [`CHANGELOG.md`](CHANGELOG.md) | What each release changed |
| [`SECURITY.md`](SECURITY.md) | Reporting a security problem |

## License

TOS is licensed under the **GNU General Public License v3.0** — see [`LICENSE.txt`](LICENSE.txt) for the full text.

Copyright © 2026 Strata Systems LLC. This program is free software: you may redistribute it and/or modify it under the terms of the GPLv3. It comes with ABSOLUTELY NO WARRANTY (see sections 15–16 of the license).
