#!/usr/bin/env python3
"""Re-splice TOS-Extras/build/install.lua into kernel/pkg.lua's PICKER_SRC.

The Optional Utilities picker necessarily exists twice: once on the disk
(TOS-Extras/build/install.lua) and once embedded in the kernel as
PICKER_SRC, so in-TOS `pkg make-disk` can write a disk without reaching
this source tree. test_picker_sync.lua fails the suite if they drift; this
script is how you make them agree again after editing the disk copy.

Edit install.lua, run this, run the suite. Never edit PICKER_SRC by hand.

Writes via temp-then-rename: pkg.lua is ~2500 lines of kernel and a
half-written one is worse than no change at all.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEV = os.path.dirname(HERE)
PKG = os.path.join(DEV, "tos", "kernel", "pkg.lua")
DISK = os.path.normpath(os.path.join(DEV, "..", "TOS-Extras", "build", "install.lua"))

OPEN, CLOSE = "local PICKER_SRC = [==[\n", "\n]==]"


def main() -> int:
    with open(PKG, "r", encoding="utf-8", newline="") as fh:
        pkg = fh.read()
    with open(DISK, "r", encoding="utf-8", newline="") as fh:
        disk = fh.read()

    # The test compares against the disk file with one trailing newline
    # trimmed, so splice exactly that.
    body = re.sub(r"\n$", "", disk)

    if "]==]" in body:
        print("ERROR: the picker contains ']==]' — it would close the long "
              "string early. Change the delimiter in BOTH files first.")
        return 2

    start = pkg.find(OPEN)
    if start < 0:
        print("ERROR: PICKER_SRC opening delimiter not found in pkg.lua")
        return 2
    end = pkg.find(CLOSE, start + len(OPEN))
    if end < 0:
        print("ERROR: PICKER_SRC closing delimiter not found in pkg.lua")
        return 2

    current = pkg[start + len(OPEN):end]
    if current == body:
        print("Already in sync (%d bytes)." % len(body))
        return 0

    updated = pkg[:start + len(OPEN)] + body + pkg[end:]
    tmp = PKG + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as fh:
        fh.write(updated)
    if os.path.getsize(tmp) < len(body):     # sanity: never rename a stub
        os.remove(tmp)
        print("ERROR: temp file looks truncated; pkg.lua left untouched.")
        return 2
    os.replace(tmp, PKG)
    print("Re-synced PICKER_SRC: %d -> %d bytes." % (len(current), len(body)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
