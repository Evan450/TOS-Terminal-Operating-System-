#!/usr/bin/env python3
"""Boot TOS at each memory size the README names, and check that it still
does what the README says it does there.

WHY THIS EXISTS. The README promised a 192 KB floor long after TOS had
outgrown it: measured 2026-10-03 on the headless machine, it needed 1 MB
just to reach a usable shell (TODO, THE RAM FLOOR IS 1 MB). Nothing had
re-measured the number since it was written, so nothing noticed it go
stale. And floors move both ways: 2026-10-10's cut (network services are
not loaded on a machine without a network) gave a 1152 KB machine 91 KB
back, and 768 KB went from the emergency terminal to a command line whose
commands do not fit -- which the README still described the old way.

So every README claim about memory is a CASE here: a memory size, the README
text it backs (verbatim), and a session script that passes only while the
claim holds. Both sides of a floor are checked -- what works at a size, and
what does not below it -- because a floor that has dropped is as wrong in
the README as one that has risen. Each case boots a fresh TOS-Release on the
headless machine (headless-session.py) with a T1 CPU, the profile the
README's numbers were measured on: a fresh install, logged in, after one
command.

    python TOS-Dev/build/floorcheck.py [--only 768,1024] [--jobs 3] [--keep]
    python TOS-Dev/tos.py floorcheck        (builds the release first)

It fails when a claim no longer holds, or when the README no longer says
what a case checks: change the two together. Free-memory figures are shown
beside the README's and flagged when far apart, but never fail the run --
one `mem` reading moves by tens of KB with whatever garbage is uncollected.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEV = HERE.parent
README = DEV / "README.md"


@dataclass(frozen=True)
class Case:
    kb: int                      # installed memory
    ram: str                     # the sticks, as headless-session.py --ram takes them
    what: str                    # the claim, in a few words, for the report
    claims: tuple[str, ...]      # README text this case backs, verbatim
    script: tuple[str, ...]      # passes only while the claim holds
    free_claim: str | None = None  # README text giving the free memory, e.g. "about 200 KB free"
    probe_pkg: bool = False      # report (never fail) whether `pkg` loaded
    net: bool = False            # with a network card (a second machine, via a relay)
    # Where nothing should load, running out of memory can take the whole
    # machine down instead of being refused: both prove the claim, once the
    # step matching this has passed (the command line DID start).
    down_after: str | None = None

    @property
    def name(self) -> str:
        return f"{self.kb}K" + (" +net" if self.net else "")

    @property
    def docs_free(self) -> int | None:
        if not self.free_claim:
            return None
        m = re.search(r"(\d+) KB", self.free_claim)
        return int(m.group(1)) if m else None


# One command after login, the README's measuring condition, and the reading
# it gives. `=== Memory ===` is the full report: where the `core` commands
# cannot load, `mem` gives a one-line "rescue reading" instead.
MEM = ("sleep 3", "type mem", "key enter", "wait 20 === Memory ===", "snap mem")
# ...and where the `core` commands do not fit, `mem` says so.
NO_COMMAND = ("firstboot", "wait 30 TOS CLI", "sleep 3", "type mem", "key enter",
              "wait 20 need more memory than is free", "snap mem")

CASES: tuple[Case, ...] = (
    Case(384, "384", "the kernel does not fit",
         ("at 384 KB or less the kernel itself does not fit",),
         ("wait 120 ERR_OUT_OF_MEMORY", "snap stop")),
    Case(768, "768", "the command line starts; no command loads",
         ("At 768 KB the command line starts, but its commands do not load",),
         NO_COMMAND, down_after="TOS CLI"),
    Case(1024, "1024", "the command line, started by itself",
         ("| Minimum | 1 MB (one Tier 3.5 stick) | The command line",
          "TOS starts there by itself on a machine this size"),
         ("firstboot", "wait 30 TOS CLI") + MEM
         + ("type pkg list", "key enter", "sleep 8", "snap pkg"),
         free_claim="About 35 KB stays free", probe_pkg=True),
    Case(1024, "1024", "the command line starts; no command loads",
         ("With one, 1 MB starts the command line but none of its commands load",),
         NO_COMMAND, net=True, down_after="TOS CLI"),
    Case(1280, "1024,256", "the package manager loads",
         ("the package manager, which needs 1.25 MB (add a Tier 1.5 stick)",),
         ("firstboot", "sleep 3", "type pkg list", "key enter",
          "wait 30 No packages installed", "snap pkg")),
    Case(1280, "1024,256", "the command line and the package manager",
         ("so the minimum is 1.25 MB, which also runs the package manager",),
         ("firstboot", "wait 30 TOS CLI") + MEM
         + ("type pkg list", "key enter", "wait 30 No packages installed", "snap pkg"),
         net=True),
    Case(1536, "768,768", "the panels, and their commands load",
         ("| Recommended | 1.5 MB (two Tier 3 sticks) | The full panels interface",),
         ("firstboot", "wait 30 View:") + MEM,
         free_claim="about 280 KB free after you log in"),
    Case(1536, "768,768", "the panels, and their commands load",
         ("The panels still run at 1.5 MB",),
         ("firstboot", "wait 30 View:") + MEM, net=True,
         free_claim="with about 115 KB free"),
    Case(2048, "1024,1024", "the panels, with room for add-ons",
         ("| Comfortable | 2 MB (two Tier 3.5 sticks) |",),
         ("firstboot", "wait 30 View:") + MEM,
         free_claim="about 800 KB free after you log in"),
)


def _flat(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def readme_mismatches(readme: str, cases=CASES) -> list[str]:
    """README text a case checks that the README no longer says."""
    flat = _flat(readme)
    out = []
    for c in cases:
        for claim in c.claims + ((c.free_claim,) if c.free_claim else ()):
            if _flat(claim) not in flat:
                out.append(f"{c.name}: the README no longer says {claim!r}")
    return out


def parse_snaps(output: str) -> dict[str, str]:
    """headless-session.py prints each snap as `--- NAME` and its screen."""
    snaps = {}
    for block in re.split(r"\n(?=--- )", output):
        head, _, body = block.partition("\n")
        if head.startswith("--- "):
            snaps[head[4:].strip()] = body
    return snaps


def free_kb(mem_screen: str) -> int | None:
    m = re.search(r"used, (\d+)K", mem_screen or "")
    return int(m.group(1)) if m else None


def far_apart(measured: int, documented: int) -> bool:
    return abs(measured - documented) > max(30, documented // 4)


@dataclass
class Result:
    case: Case
    holds: bool
    output: str
    free: int | None = None
    pkg_loaded: bool | None = None
    went_down: bool = False
    stamp: str | None = None
    why: list[str] = field(default_factory=list)


def run_case(case: Case, keep: bool, timeout: int) -> Result:
    with tempfile.TemporaryDirectory(prefix="tos-floor-") as tmp:
        script = Path(tmp) / f"floor-{case.kb}.txt"
        script.write_text("\n".join(case.script) + "\n", encoding="utf-8")
        cmd = [sys.executable, str(HERE / "headless-session.py"), str(script),
               "--profile", "t1", "--ram", case.ram, "--timeout", str(timeout)]
        if case.net:
            cmd += ["--machines", "2"]
        if keep:
            cmd.append("--keep")
        try:
            done = subprocess.run(cmd, cwd=DEV, capture_output=True, text=True,
                                  encoding="utf-8", errors="replace",
                                  timeout=timeout + 180)
            code, out = done.returncode, done.stdout + done.stderr
        except subprocess.TimeoutExpired as e:
            code, out = 2, str(e.stdout or "") + "\n(the session had to be killed)"
    snaps = parse_snaps(out)
    r = Result(case, code == 0, out)
    if not r.holds and case.down_after:
        started = re.search(r"^\[step\]\s+\d+ wait \d+ " + re.escape(case.down_after)
                            + r"\s+ok at", out, re.M)
        # OpenComputers says it two ways: "not enough memory" from Lua,
        # "Error.OutOfMemory" from the machine itself.
        if started and re.search(r"went down: (not enough memory|Error\.OutOfMemory)", out):
            r.holds = r.went_down = True
    m = re.search(r"^release: build (\S+)", out, re.M)
    r.stamp = m.group(1) if m else None
    r.free = free_kb(snaps.get("mem", ""))
    if case.probe_pkg and "pkg" in snaps:
        r.pkg_loaded = "No packages installed" in snaps["pkg"]
    if not r.holds:
        steps = [l for l in out.splitlines() if l.startswith("[step]")]
        if steps:
            r.why.append("last step: " + steps[-1].strip())
        if "--- screen when it stopped" in out:
            screen = out.split("--- screen when it stopped", 1)[1].split("\n--- ", 1)[0]
            r.why += ["  | " + l for l in screen.strip().splitlines()[-12:]]
    return r


def report(results: list[Result]) -> int:
    stamp = next((r.stamp for r in results if r.stamp), "?")
    print(f"floor check -- build {stamp}, T1 CPU, fresh install, logged in, one command\n")
    print(f"  {'RAM':>9}  {'README says':<42} {'holds':<6} {'free':>5}  README")
    worst = 0
    notes = []
    for r in results:
        c = r.case
        free = f"{r.free}K" if r.free is not None else ""
        docs = f"~{c.docs_free}K" if c.docs_free is not None else ""
        flag = ""
        if r.free is not None and c.docs_free is not None and far_apart(r.free, c.docs_free):
            flag = "  differs"
            notes.append(f"{c.name}: {r.free} KB free after one command; the README says "
                         f"{c.free_claim!r}. One reading is noisy -- run it again before "
                         "changing the README.")
        print(f"  {c.name:>9}  {c.what:<42} {'yes' if r.holds else 'NO':<6} "
              f"{free:>5}  {docs}{flag}")
        if r.went_down:
            notes.append(f"{c.name}: the first command ran the machine out of memory and "
                         "took it down, rather than being refused. Either proves the claim.")
        if not r.holds:
            worst = 1
            print(f"          the README says: {c.claims[0]!r}")
            for line in r.why:
                print("          " + line)
        if r.pkg_loaded:
            notes.append(f"{c.name}: `pkg list` loaded this time; the README says the "
                         "package manager needs 1.25 MB. It is on the edge here (2026-10-10: "
                         "it loaded after `mem`, and failed as the first command), so this "
                         "is a note, not a failure.")
    for n in notes:
        print("\nnote: " + n)
    print("\n" + ("Every README memory claim holds." if worst == 0 else
                  "A README memory claim no longer holds: fix TOS or the README, then "
                  "this file's CASES to match."))
    return worst


def main(argv: list[str] | None = None) -> int:
    # A failing case prints the machine's screen, which is not all cp1252.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="sizes in KB, comma-separated (e.g. 768,1024)")
    ap.add_argument("--jobs", type=int, default=3, help="machines at once (default 3)")
    ap.add_argument("--timeout", type=int, default=240, help="seconds per machine")
    ap.add_argument("--keep", action="store_true", help="keep every machine's directory")
    args = ap.parse_args(argv)

    stale = readme_mismatches(README.read_text(encoding="utf-8"))
    if stale:
        for line in stale:
            print("error: " + line, file=sys.stderr)
        print("The README and build/floorcheck.py's CASES must change together.",
              file=sys.stderr)
        return 1
    cases = list(CASES)
    if args.only:
        want = {int(x) for x in args.only.split(",") if x.strip()}
        cases = [c for c in CASES if c.kb in want]
        if not cases:
            print(f"error: no case for {args.only}; sizes are "
                  + ", ".join(str(c.kb) for c in CASES), file=sys.stderr)
            return 1
    with ThreadPoolExecutor(max(1, args.jobs)) as ex:
        results = list(ex.map(lambda c: run_case(c, args.keep, args.timeout), cases))
    return report(results)


if __name__ == "__main__":
    sys.exit(main())
