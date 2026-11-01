#!/usr/bin/env python3
"""How much of what OpenComputers ships finds its libraries on TOS?

The number the README quotes comes from here, so anyone can run it again. It
reads the loot disks out of the emulator's jar, the same files a player finds
in a dungeon, and asks one question of every Lua file on them: does each
require() name something a sandboxed TOS program can get?

That is a lower bound on nothing. A require that resolves is not a program that
works: capabilities, paths and terminal behaviour still differ. OpenOS and
Plan9k are left out because they are operating systems, not programs for one,
and OpenOS's own bin/ does not run here (TODO, OPENOS'S OWN bin/).

    python build/compat_scan.py [--jar PATH] [--verbose]
"""

from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_JAR = Path.home() / "Documents" / "Ocelot Destop Emulator" / "ocelot-desktop-v1.14.2.jar"
LOOT = "assets/opencomputers/loot/"
NOT_PROGRAMS = {"openos", "plan9k"}
# Lua's own libraries, and OC's globals a program may also require by name.
BUILTIN = {"string", "table", "math", "os", "coroutine", "unicode", "bit32", "utf8",
           "component", "computer", "package"}
REQUIRE = re.compile(r"""\brequire\s*\(?\s*["']([\w.\-/]+)["']""")


def provided(sandbox: str) -> set[str]:
    """The OpenOS names sandbox.lua maps to compat modules."""
    table = re.search(r"local OPENOS_NAMES = \{(.*?)\n\}", sandbox, re.S)
    if not table:
        raise SystemExit("error: OPENOS_NAMES is not in tos/kernel/sandbox.lua")
    return set(re.findall(r"(\w+)\s*=\s*\"compat\.", table.group(1)))


def looks_like_lua(name: str, data: bytes) -> bool:
    if "/man/" in name:
        return False
    if name.endswith(".lua"):
        return True
    if "." in Path(name).name:
        return False
    return data[:2] == b"--" or b"local " in data[:2000] or b"require" in data[:2000]


def scan(jar: Path, have: set[str], verbose: bool) -> tuple[int, int, int, dict]:
    disks: dict[str, dict[str, bytes]] = {}
    with zipfile.ZipFile(jar) as z:
        for entry in z.namelist():
            if not entry.startswith(LOOT) or entry.endswith("/"):
                continue
            parts = entry[len(LOOT):].split("/")
            if len(parts) < 2 or parts[0] in NOT_PROGRAMS:
                continue
            data = z.read(entry)
            if looks_like_lua(entry, data):
                disks.setdefault(parts[0], {})["/".join(parts[1:])] = data

    files = found = 0
    missing: dict[str, list[str]] = {}
    for disk, members in sorted(disks.items()):
        # A disk's own libraries count: a program can carry what it needs.
        own = {Path(p).stem for p in members}
        for path, data in sorted(members.items()):
            files += 1
            names = set(REQUIRE.findall(data.decode("utf-8", "replace")))
            gaps = sorted(n for n in names if n not in have | BUILTIN | own)
            if gaps:
                for n in gaps:
                    missing.setdefault(n, []).append(f"{disk}/{path}")
            else:
                found += 1
            if verbose:
                print(f"  {'ok ' if not gaps else 'GAP'} {disk}/{path}"
                      + (f"  needs {', '.join(gaps)}" if gaps else ""))
    return len(disks), files, found, missing


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--jar", default=str(DEFAULT_JAR))
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args(argv)
    jar = Path(args.jar)
    if not jar.is_file():
        print(f"no jar at {jar}: pass --jar", file=sys.stderr)
        return 2
    have = provided((HERE.parent / "tos" / "kernel" / "sandbox.lua").read_text(encoding="utf-8"))
    disks, files, found, missing = scan(jar, have, args.verbose)
    print(f"{found} of {files} Lua files on {disks} loot disks find every library they require")
    for name, who in sorted(missing.items()):
        print(f"  missing {name}: {', '.join(who)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
