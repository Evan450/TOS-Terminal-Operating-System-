#!/usr/bin/env python3
"""Boot TOS with everything outside the manifest's floor deleted.

The floor is what TOS must keep if it strips itself: `floor = true` in
tos/system_manifest.lua. test_manifest_floor.lua proves it is closed under
require, which is the half that needs no machine. This is the other half: a
static scan cannot say that the machine comes up, so delete the rest and boot
it, on the headless machine, through First Boot Setup to a working command
line. Nothing here deletes anything from the real tree.

    python TOS-Dev/build/floorboot.py [--keep]
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent.parent / "TOS-Release"

SCRIPT = r"""wait 40 New password
type Passw0rd77\n
sleep 1
type Passw0rd77\n
wait 30 root:/\$
type echo floor-ok > /tmp/x\n
sleep 2
type cat /tmp/x\n
wait 10 floor-ok\n
type ls /etc\n
wait 10 users.dat
type doctor\n
sleep 8
snap doctor
"""


def floor_paths(manifest: str) -> tuple[list[str], list[str]]:
    keep, drop = [], []
    for entry in re.findall(r"\{[^{}]*path\s*=\s*\"[^\"]+\"[^{}]*\}", manifest):
        path = re.search(r"path\s*=\s*\"([^\"]+)\"", entry).group(1)
        (keep if re.search(r"floor\s*=\s*true", entry) else drop).append(path)
    return keep, drop


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--keep", action="store_true", help="keep the stripped tree and the run")
    args = ap.parse_args(argv)
    if not (RELEASE / "init.lua").is_file():
        print("error: TOS-Release not found -- run `python tos.py build` first", file=sys.stderr)
        return 1

    keep, drop = floor_paths((RELEASE / "tos" / "system_manifest.lua").read_text(encoding="utf-8"))
    if not keep:
        print("error: the manifest marks no floor", file=sys.stderr)
        return 1

    work = Path(tempfile.mkdtemp(prefix="tos-floor-"))
    tree = work / "release"
    shutil.copytree(RELEASE, tree)
    for path in drop:
        target = tree / path.lstrip("/")
        if target.is_file():
            target.unlink()

    # The size is the point: this is what a stripped machine costs on disk.
    size = sum((RELEASE / p.lstrip("/")).stat().st_size for p in keep)
    cost = size + 512 * len(keep)
    print(f"floor: {len(keep)} of {len(keep) + len(drop)} files, {size // 1024} KB "
          f"({cost // 1024} KB on a managed disk)")

    script = work / "script.txt"
    script.write_text(SCRIPT, encoding="utf-8")
    cmd = [sys.executable, str(HERE / "headless-session.py"), str(script),
           "--release", str(tree), "--timeout", "120"]
    done = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if done.returncode != 0:
        print(done.stdout[-3000:])
        print("FAILED: the floor did not reach a working command line")
    else:
        print("passed: a floor-only machine set a password, wrote and read a file, and ran doctor")
    if args.keep:
        print(f"kept: {work}")
    else:
        shutil.rmtree(work, ignore_errors=True)
    return 0 if done.returncode == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
