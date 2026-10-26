#!/usr/bin/env python3
"""Is the Irradiated Circuits loot disk today's TOS release?

WHY THIS EXISTS. The radbridge mod (Irradiated Circuits) bundles a copy of
TOS-Release into its jar as a dungeon loot floppy, taken from whatever
TOS-Release held when the mod last built (its build.gradle reads
tos_release_dir). Nothing on this side noticed when that copy went stale:
the 2026-09 audit found radbridge 0.4.0 shipping TOS 1.4.0, and 0.5.0
(built 2026-10-09) carries that day's release, without kernel/x25519.lua or
curve25519field.lua. The fix is in the mod's repo -- rebuild it, and bump
its version, because LootDiskInstaller stamps the extracted disk with the
mod version and an unchanged version never reaches an existing world.

This compares the jar's assets/radbridge/loot/tos/ with TOS-Release, file
by file (line endings normalised, as the builders do), and says what
differs. Advisory: it exits 0 on drift unless --strict, because the mod is
its own repo and a stale loot disk is no reason to hold a TOS publish.
With no jar to find it says so and exits 0.

    python build/check_lootdisk.py [--jar PATH] [--release DIR] [--strict]

The jar is --jar, else $TOS_LOOTDISK_JAR, else the newest
radbridge-X.Y.Z.jar under ~/mcmods/irradiated-circuits/build/libs.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEV = HERE.parent
PREFIX = "assets/radbridge/loot/tos/"
DEFAULT_LIBS = Path.home() / "mcmods" / "irradiated-circuits" / "build" / "libs"
JAR_RE = re.compile(r"^radbridge-(\d+)\.(\d+)\.(\d+)\.jar$")


def find_jar(explicit: str | None) -> Path | None:
    for cand in (explicit, os.environ.get("TOS_LOOTDISK_JAR")):
        if cand:
            p = Path(cand)
            return p if p.is_file() else None
    if not DEFAULT_LIBS.is_dir():
        return None
    best = None
    for p in DEFAULT_LIBS.iterdir():
        m = JAR_RE.match(p.name)          # not -dev / -sources
        if m:
            key = tuple(int(x) for x in m.groups())
            if best is None or key > best[0]:
                best = (key, p)
    return best[1] if best else None


def norm(b: bytes) -> bytes:
    return b.replace(b"\r\n", b"\n")


def stamp(init: bytes | None) -> str:
    if not init:
        return "?"
    m = re.search(rb'build\s*=\s*"([^"]+)"', init)
    return m.group(1).decode("utf-8", "replace") if m else "?"


def compare(jar: Path, release: Path):
    with zipfile.ZipFile(jar) as z:
        bundled = {n[len(PREFIX):]: norm(z.read(n)) for n in z.namelist()
                   if n.startswith(PREFIX) and not n.endswith("/")}
    shipped = {}
    for p in release.rglob("*"):
        if p.is_file():
            shipped[p.relative_to(release).as_posix()] = norm(p.read_bytes())
    differ = sorted(k for k in bundled.keys() & shipped.keys() if bundled[k] != shipped[k])
    missing = sorted(shipped.keys() - bundled.keys())     # in the release, not the jar
    extra = sorted(bundled.keys() - shipped.keys())       # in the jar, gone from the release
    return bundled, shipped, differ, missing, extra


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--jar")
    ap.add_argument("--release", default=str(DEV.parent / "TOS-Release"))
    ap.add_argument("--strict", action="store_true", help="exit 1 when the disk has drifted")
    a = ap.parse_args(argv)

    jar = find_jar(a.jar)
    if jar is None:
        print("SKIP: no radbridge jar found (pass --jar, or set TOS_LOOTDISK_JAR)")
        return 0
    release = Path(a.release)
    if not (release / "tos" / "system_manifest.lua").is_file():
        print(f"SKIP: no built TOS-Release at {release} (python tos.py build)")
        return 0

    bundled, shipped, differ, missing, extra = compare(jar, release)
    if not bundled:
        print(f"{jar.name} carries no loot disk ({PREFIX} is empty).")
        return 1 if a.strict else 0
    print(f"{jar.name}: loot disk build {stamp(bundled.get('init.lua'))}, "
          f"TOS-Release build {stamp(shipped.get('init.lua'))}")
    if not (differ or missing or extra):
        print(f"OK: the loot disk is today's release ({len(bundled)} files)")
        return 0
    print(f"DRIFT: {len(differ)} file(s) differ, {len(missing)} missing from the jar, "
          f"{len(extra)} the release no longer ships")
    for label, names in (("differs", differ), ("missing", missing), ("extra", extra)):
        for n in names[:8]:
            print(f"  {label:8} {n}")
        if len(names) > 8:
            print(f"  {label:8} ... and {len(names) - 8} more")
    print("Rebuild the mod against this TOS-Release and bump its version: the loot")
    print("disk is stamped with the mod version, and an unchanged one never reaches")
    print("an existing world.")
    return 1 if a.strict else 0


if __name__ == "__main__":
    sys.exit(main())
