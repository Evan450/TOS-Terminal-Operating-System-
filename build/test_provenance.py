"""Provenance lint: what TOS ships is TOS's own, or says whose it is.

TOS is GPLv3 and keeps a copy of OpenOS (MIT, the OpenComputers project)
under Minecraft/Reference/ as an API reference for the compat layer. Two
things about that are easy to get wrong and hard to repair after the fact
(TODO: A PROVENANCE LINT):

  1. Nothing that ships may LOAD from Reference/. Release builds are made
     from TOS-Dev/ alone, so this holds by construction today; the check is
     that no shipped file's CODE names the Reference tree.
  2. Nothing that ships may carry a substantial verbatim run of OpenOS code
     without crediting it. Compatibility makes some sameness unavoidable --
     checkArg lines that must match OpenOS's signatures, data tables of side
     names and colours -- so the bar is a run of RUN_LINES consecutive code
     lines (comments and blanks dropped, at least half of them non-trivial).
     A file over the bar must carry a `--!` line naming OpenOS and its MIT
     licence. compat/internet.lua is the one case today, and credits it.

Skipped when Reference/OpenOS is not beside TOS-Dev (a dev-branch clone has
no Reference tree; the check belongs to the maintainer's checkout).
The licence-HEADER half of the TODO item is an operator decision and is not
checked here.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEV = HERE.parent
ROOT = DEV.parent
OPENOS = ROOT / "Reference" / "OpenOS"
EXTRAS = ROOT / "TOS-Extras"

RUN_LINES = 8          # consecutive shared code lines that need a credit
NONTRIVIAL = 10        # chars; a line shorter than this is "end" / "else"


def code_lines(path: Path) -> list[str]:
    out = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        s = raw.strip()
        if not s or s.startswith("--"):
            continue
        out.append(s)
    return out


def shingles(lines: list[str]):
    for i in range(len(lines) - RUN_LINES + 1):
        window = lines[i:i + RUN_LINES]
        if sum(1 for l in window if len(l) >= NONTRIVIAL) * 2 >= RUN_LINES:
            yield i, "\n".join(window)


def shipped_files() -> list[Path]:
    files = []
    for sub in ("tos", "usr/bin", "etc"):
        files += sorted((DEV / sub).rglob("*.lua"))
    files += [DEV / n for n in ("init.lua", "bios.lua", "install.lua", "bootstrap.lua")
              if (DEV / n).is_file()]
    if (EXTRAS / "modules").is_dir():
        files += [p for p in sorted((EXTRAS / "modules").rglob("*.lua"))
                  if not p.name.startswith("test_")]
    return files


def credited(path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("--!") and "OpenOS" in s and "MIT" in s:
            return True
    return False


def main() -> int:
    if not OPENOS.is_dir():
        print("SKIP: Reference/OpenOS is not beside TOS-Dev; provenance not checked")
        return 0

    passed = failed = 0

    def check(name: str, ok: bool, detail: str = "") -> None:
        nonlocal passed, failed
        if ok:
            passed += 1
            print(f"  PASS: {name}")
        else:
            failed += 1
            print(f"  FAIL: {name}" + (f"\n        {detail}" if detail else ""))

    print("=== provenance: what ships is ours, or says whose it is ===")
    files = shipped_files()
    check(f"found the shipped sources ({len(files)} files)", len(files) > 150)

    # 1. Nothing shipped loads from the Reference tree.
    loaders = [str(p.relative_to(ROOT)) for p in files
               if any("Reference/" in l or "Reference\\" in l for l in code_lines(p))]
    check("no shipped file's code names the Reference tree", not loaders,
          ", ".join(loaders))

    # 2. Long verbatim OpenOS runs are credited.
    seen: dict[str, str] = {}
    for ref in sorted(OPENOS.rglob("*.lua")):
        for _, sh in shingles(code_lines(ref)):
            seen.setdefault(sh, str(ref.relative_to(OPENOS)))
    hits: dict[Path, str] = {}
    for p in files:
        for i, sh in shingles(code_lines(p)):
            if sh in seen:
                hits[p] = seen[sh]
                break
    uncredited = [f"{p.relative_to(ROOT)} (shares {RUN_LINES}+ lines with OpenOS {src})"
                  for p, src in hits.items() if not credited(p)]
    check(f"every {RUN_LINES}-line verbatim run from OpenOS is credited "
          f"({len(hits)} file(s) carry one)", not uncredited, "; ".join(uncredited))

    # The lint must be able to fail. A file that copies a window of OpenOS's
    # lib/internet.lua is flagged without a credit line and passes with one.
    import tempfile
    ref = OPENOS / "openos" / "lib" / "internet.lua"
    if ref.is_file():
        window = next((sh for _, sh in shingles(code_lines(ref))), "")
        with tempfile.TemporaryDirectory() as td:
            bare = Path(td) / "copied.lua"
            bare.write_text("local M = {}\n" + window + "\nreturn M\n", encoding="utf-8")
            flagged = any(sh in seen for _, sh in shingles(code_lines(bare)))
            check("a copied run is caught", flagged and not credited(bare))
            bare.write_text("--! from OpenOS lib/internet.lua (MIT)\n"
                            + bare.read_text(encoding="utf-8"), encoding="utf-8")
            check("...and a credited one passes", credited(bare))

    print(f"\nResults: {passed} passed, {failed} failed")
    return 1 if failed else 0


def test_provenance():
    """pytest entry point: run_tests.py runs build/test_*.py through pytest."""
    assert main() == 0


if __name__ == "__main__":
    sys.exit(main())
