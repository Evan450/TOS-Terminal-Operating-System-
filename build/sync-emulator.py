#!/usr/bin/env python3
"""Deploy TOS-Release and the self-test checks into an Ocelot workspace.

WHY THIS EXISTS. The on-box battery is the only thing that tests TOS against
a real OpenComputers implementation, and running it was a manual copy of two
trees into UUID-named directories -- so in practice it ran against whatever
happened to be on the disk last. The round that prompted this script found the
boot disk eleven files behind and the self-test floppy one revision behind,
which is how a check that had already been fixed still reported its old
answer.

Ocelot backs each virtual filesystem with an ORDINARY HOST DIRECTORY, so this
is a plain file copy and the report comes back the same way -- no serial port,
no screen scraping. See kernel/selftest.lua's header.

    python TOS-Dev/build/sync-emulator.py [--workspace DIR] [--clear-log]
                                          [--dry-run]

--workspace defaults to $OCELOT_EMULATOR, else the first plausible Ocelot
workspace under ~/Documents. Nothing is hard-coded to one machine.

WHAT IT WILL NOT TOUCH. The boot disk carries the operator's state as well as
the OS: /etc/users.dat is their password database, /home and /root are their
files, /var holds the log this whole exercise is here to read. Those are
PRESERVED. Only the directories TOS-Release actually owns are mirrored, and
'mirrored' means stale files under them are removed -- a module left behind
after a rename is exactly the kind of thing that makes an on-box round lie.
"""

from __future__ import annotations

import argparse
import filecmp
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEV = HERE.parent
ROOT = DEV.parent
RELEASE = ROOT / "TOS-Release"
# The battery is the `selftest` package now, laid out at its install path.
CHECKS = ROOT / "TOS-Extras" / "modules" / "selftest" / "usr" / "lib" / "selftest"

# MIRRORED: TOS-Release owns every byte, so a file it no longer has is stale
# and must go. This is the kernel; a module left behind after a rename is
# exactly what makes an on-box round lie about which code it tested.
MIRROR_DIRS = ["tos"]

# COPIED, never pruned. These carry OPERATOR STATE mixed in with ours:
#   etc/rc.d  -- a service is disabled by RENAMING it to .disabled, so pruning
#                what TOS-Release does not have would silently re-enable a
#                network service somebody deliberately turned off
#   usr/bin   -- an operator's own script can live here
#   usr/man, usr/lang -- an added translation or man page is theirs
# Updating our files there is right; deciding theirs are surplus is not.
COPY_DIRS = ["usr/bin", "usr/man", "usr/lang", "etc/rc.d"]

# Root files TOS-Release owns.
MIRROR_FILES = ["init.lua", "bios.lua", "install.lua", "LICENSE.txt"]

# What ARMS the battery: a marker on the machine's own disk. A selftest.on on
# the floppy only carries the round's options (shutdown=, only=, screen=).
MACHINE_MARKER = Path("etc") / "selftest.on"


def find_workspace(explicit: str | None) -> Path | None:
    if explicit:
        p = Path(explicit)
        return p if p.is_dir() else None
    env = os.environ.get("OCELOT_EMULATOR")
    if env and Path(env).is_dir():
        p = Path(env)
        return p / "Emulator" if (p / "Emulator").is_dir() else p
    home = Path.home()
    for base in (home / "Documents", home / "Desktop", home):
        if not base.is_dir():
            continue
        for cand in sorted(base.glob("*Ocelot*")):
            if (cand / "Emulator").is_dir():
                return cand / "Emulator"
            if cand.is_dir() and any(cand.glob("*/init.lua")):
                return cand
    return None


def classify(workspace: Path) -> tuple[Path | None, Path | None]:
    """Find the TOS boot disk and the self-test floppy by their CONTENTS.

    By UUID would mean hard-coding one person's workspace; by content means a
    rebuilt disk with a new UUID still works.
    """
    boot = floppy = None
    for d in sorted(workspace.iterdir()):
        if not d.is_dir():
            continue
        if (d / "init.lua").is_file() and (d / "tos").is_dir():
            boot = d
        elif (d / "selftest.on").is_file() or any(d.glob("[0-9][0-9]-*.lua")):
            floppy = d
    return boot, floppy


def arm_machine(boot: Path, dry: bool) -> tuple[bool, bool]:
    """Make sure the emulated machine is armed for the battery.

    Only the machine arms it (kernel/selftest.lua's #SEC note): a floppy that
    could arm it would run its .lua files inside the kernel at boot on any
    machine it was put in. This is the operator's own emulator and running
    this script is the request for a round, so it arms it -- with an EMPTY
    marker, so the floppy's options (shutdown=true) stay in force. An existing
    marker is never rewritten: it may carry the operator's own options.

    Returns (already_armed, created).
    """
    marker = boot / MACHINE_MARKER
    if marker.is_file():
        return True, False
    if not dry:
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text("")
    return False, True


def mirror(src: Path, dst: Path, dry: bool, log: list[str], prune: bool = True) -> None:
    """Copy src over dst. With prune, also delete what src no longer has."""
    if not src.exists():
        return
    dst.mkdir(parents=True, exist_ok=True)
    src_names = {p.name for p in src.iterdir()}
    for p in sorted(src.iterdir()):
        target = dst / p.name
        if p.is_dir():
            mirror(p, target, dry, log, prune)
        else:
            if target.exists() and filecmp.cmp(p, target, shallow=False):
                continue
            log.append(("update " if target.exists() else "add    ") + p.name)
            if not dry:
                shutil.copy2(p, target)
    if prune and dst.exists():
        for p in sorted(dst.iterdir()):
            if p.name not in src_names:
                log.append("remove " + p.name)
                if not dry:
                    if p.is_dir():
                        shutil.rmtree(p)
                    else:
                        p.unlink()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workspace", help="Ocelot Emulator/ directory")
    ap.add_argument("--clear-log", action="store_true",
                    help="truncate /var/selftest.log first, so the next report "
                         "cannot be confused with the last one")
    ap.add_argument("--dry-run", action="store_true", help="say what would change")
    ap.add_argument("--no-arm", action="store_true",
                    help="do not create etc/selftest.on on the boot disk; without "
                         "it the machine ignores the floppy")
    args = ap.parse_args()

    if not RELEASE.is_dir():
        print("error: TOS-Release not found -- run build-release first", file=sys.stderr)
        return 1

    ws = find_workspace(args.workspace)
    if not ws:
        print("error: no Ocelot workspace found. Pass --workspace, or set "
              "OCELOT_EMULATOR to the folder holding the .jar.", file=sys.stderr)
        return 1

    boot, floppy = classify(ws)
    print(f"workspace: {ws}")
    print(f"boot disk: {boot if boot else '(not found)'}")
    print(f"selftest floppy: {floppy if floppy else '(not found)'}")
    if not boot:
        print("error: no directory in the workspace looks like a TOS boot disk "
              "(needs init.lua and tos/).", file=sys.stderr)
        return 1
    print()

    changes: list[str] = []
    for rel in MIRROR_DIRS:
        sub: list[str] = []
        mirror(RELEASE / rel, boot / rel, args.dry_run, sub, prune=True)
        if sub:
            changes.append(f"  {rel}/  (mirrored)")
            changes += [f"    {line}" for line in sub]
    for rel in COPY_DIRS:
        sub = []
        mirror(RELEASE / rel, boot / rel, args.dry_run, sub, prune=False)
        if sub:
            changes.append(f"  {rel}/  (copied, nothing pruned)")
            changes += [f"    {line}" for line in sub]
    for name in MIRROR_FILES:
        s, d = RELEASE / name, boot / name
        if s.is_file() and not (d.is_file() and filecmp.cmp(s, d, shallow=False)):
            changes.append(f"  {name}  ({'update' if d.exists() else 'add'})")
            if not args.dry_run:
                shutil.copy2(s, d)

    if changes:
        print("boot disk:")
        print("\n".join(changes))
    else:
        print("boot disk: already current")

    if floppy and CHECKS.is_dir():
        # The floppy's selftest.on carries the round's OPTIONS -- mirroring
        # the checks directory over it would delete it and silently drop
        # shutdown=true, which would look exactly like a clean run.
        fl: list[str] = []
        for p in sorted(CHECKS.glob("*.lua")):
            t = floppy / p.name
            if not (t.exists() and filecmp.cmp(p, t, shallow=False)):
                fl.append(f"    {'update' if t.exists() else 'add    '} {p.name}")
                if not args.dry_run:
                    shutil.copy2(p, t)
        print()
        if fl:
            print("selftest floppy:")
            print("\n".join(fl))
        else:
            print("selftest floppy: already current")
        marker = floppy / "selftest.on"
        print("  options: " + ((marker.read_text().strip() or "(defaults)")
                               if marker.is_file() else
                               "(defaults) -- a selftest.on here carries shutdown=/only=/screen="))
        if args.no_arm:
            armed = (boot / MACHINE_MARKER).is_file()
            print(f"  machine armed: {armed}"
                  + ("" if armed else "  -- the floppy will be ignored; create "
                     "etc/selftest.on on the boot disk, or drop --no-arm"))
        else:
            already, _ = arm_machine(boot, args.dry_run)
            print("  machine armed: " + ("yes" if already else
                  ("would create etc/selftest.on" if args.dry_run else
                   "yes (created etc/selftest.on)")))
    elif not floppy:
        print()
        print("selftest floppy: not found -- the battery will not run.")
        print("  The floppy is a disk carrying NN-name.lua checks (plus an optional")
        print("  selftest.on with options); etc/selftest.on on the boot disk arms it.")

    logfile = boot / "var" / "selftest.log"
    if args.clear_log and not args.dry_run:
        logfile.parent.mkdir(parents=True, exist_ok=True)
        logfile.write_text("")
        print("\ncleared /var/selftest.log")

    print()
    print("Now power the machine on in Ocelot. The battery runs before the TUI,")
    print("so the report is complete without logging in. Read it with:")
    print(f'  cat "{logfile}"')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
