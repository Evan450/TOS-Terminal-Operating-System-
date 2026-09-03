#!/usr/bin/env python3
"""TOS centralized test harness — parallel.

Runs EVERY test in one pass and reports one total:
  • TOS-Dev unit tests        usr/lib/tests/test_*.lua
  • Optional Utilities tests  ../TOS-Extras (modules, build, pane-ui)
  • Build tooling tests       build/test_*.py (pytest — see below)

Almost everything here is Lua, spawned as `lua <file>`, because the tests
load and run the real TOS modules. build/sync-emulator.py is plain Python
with no TOS module to load, so its test is plain Python too — run via
`python -m pytest` instead. This is also why it can't just live where a
bare `pytest` from the monorepo root would find it on its own: pytest's
default norecursedirs skips any directory literally named "build", and
sync-emulator.py's test sits in build/ beside the script it tests. Lua
tests have the identical problem for a different reason (pytest cannot
run Lua at all), which is the whole reason this file exists — so a
Python test that needs its own explicit invocation is not a new class
of gap, it is the same one, and this is where it gets closed.

The tests themselves stay in Lua and always will: they load and execute
the real TOS modules (kernel/pkg.lua, panels/ui.lua, calc/sheet.lua, …),
which is the whole point of them. Python is here only as the RUNNER,
because the work is ~110 independent `lua` process spawns and the shell
version ran them one at a time.

Why not just parallelise run_tests.sh? Because correct parallelism needs
three things bash makes awkward: deterministic output ordering regardless
of completion order, per-test timeouts that actually kill the child, and
an isolation rule for the one test that touches shared disk state. Those
are the interesting parts of this file.

Usage:
    python run_tests.py                # all tests, parallel
    python run_tests.py -j 4           # cap workers
    python run_tests.py --serial       # one at a time (bisecting a flake)
    python run_tests.py -k calc -k mesh # only matching names
    python run_tests.py -v             # print each test's output too

Dev-only: excluded from TOS-Release by build-release.{sh,cmd} and guarded
by usr/lib/tests/test_release_excludes.lua — keep it that way.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

DEV_DIR = Path(__file__).resolve().parent
EXTRAS_DIR = DEV_DIR.parent / "TOS-Extras"

DEFAULT_TIMEOUT = int(os.environ.get("TEST_TIMEOUT", "120"))

# A pass needs BOTH the marker AND a clean exit (inherited from the shell
# harness, and it was there for a reason): marker-only matching let a test
# print its success line and then crash in teardown while still counting
# as a pass.
PASS_MARKERS = ("All tests passed.", "*** ALL TESTS PASSED ***")
FAIL_MARKER = "*** TESTS FAILED ***"
# Likewise a skip requires a clean exit, so a real failure whose output
# happens to mention "run inside TOS" isn't misfiled as skipped.
SKIP_PATTERN = re.compile(r"not available; run inside TOS|run inside TOS", re.I)

# ── Isolation ────────────────────────────────────────────────────────
# Almost every test is a pure function of its source tree: it spawns its
# own `lua`, reads files, and writes nothing. `test_build_disk.lua` is the
# exception — it RUNS THE ASSEMBLER into dist/.test-build and
# dist/.test-install, then asserts on what landed there. Two copies racing
# in the same scratch dirs would be a spectacular source of phantom
# failures, and worse, of phantom PASSES.
#
# It's also the slowest single test (it shells out to the builder several
# times), so rather than serialise everything, mark the exclusive tests
# and run them FIRST, alone, before the parallel pool starts. One-off cost,
# zero risk, and the pool still gets the long tail.
EXCLUSIVE = {"test_build_disk.lua"}


@dataclass
class Result:
    path: str          # display path, relative + forward slashes
    status: str        # "pass" | "fail" | "skip" | "timeout"
    seconds: float
    output: str
    returncode: int

    @property
    def ok(self) -> bool:
        return self.status in ("pass", "skip")


def discover() -> list[tuple[Path, Path]]:
    """(test file, working directory) pairs, in a stable order.

    The cwd matters: each suite's tests resolve sibling modules with
    relative paths, so Extras tests must run from the Extras root exactly
    as the shell harness did (`cd "$EXTRAS"`).
    """
    found: list[tuple[Path, Path]] = []

    dev_tests = sorted((DEV_DIR / "usr" / "lib" / "tests").glob("test_*.lua"))
    found += [(t, DEV_DIR) for t in dev_tests]

    # Python-based tests for the build tooling (sync-emulator.py has no TOS
    # module to load, so its test is plain Python — see the module
    # docstring for why pytest can't just find this on its own).
    py_tests = sorted((DEV_DIR / "build").glob("test_*.py"))
    found += [(t, DEV_DIR) for t in py_tests]

    if EXTRAS_DIR.is_dir():
        extras: list[Path] = []
        extras += sorted(EXTRAS_DIR.glob("modules/*/test_*.lua"))
        extras += sorted(EXTRAS_DIR.glob("build/test_*.lua"))
        extras += sorted(EXTRAS_DIR.glob("pane-ui/test_*.lua"))
        # Add-ons that don't live under modules/ still ship tests. These two
        # were written and then silently never run for want of a glob —
        # rbmk/test_rbmk.lua alone is 72 assertions the suite was reporting
        # nothing about. Keep this list in step with run_tests.sh.
        extras += sorted(EXTRAS_DIR.glob("rbmk/test_*.lua"))
        extras += sorted(EXTRAS_DIR.glob("cluster/*/test_*.lua"))
        found += [(t, EXTRAS_DIR) for t in extras]

    return found


def display_path(test: Path, cwd: Path) -> str:
    try:
        rel = test.relative_to(cwd)
    except ValueError:
        rel = test
    prefix = "" if cwd == DEV_DIR else "../TOS-Extras/"
    return prefix + rel.as_posix()


def classify(out: str, rc: int) -> str:
    has_pass = any(m in out for m in PASS_MARKERS)
    has_fail = FAIL_MARKER in out
    has_skip = bool(SKIP_PATTERN.search(out))

    if rc == 0 and has_pass:
        return "pass"
    if rc == 0 and has_skip:
        return "skip"
    # Passed then died in teardown — a real failure the marker would hide.
    if has_pass and rc != 0:
        return "fail"
    if has_fail or rc != 0:
        return "fail"
    # Clean exit, no recognisable marker: surface it rather than assume.
    return "fail"


def classify_py(rc: int) -> str:
    # pytest's own exit code is the whole story: 0 is every test passed,
    # 5 is "no tests were collected" (a renamed test function silently
    # vanishing counts as a failure here, not a quiet no-op), anything
    # else is a real failure or error. There is no skip marker to hunt
    # for the way the Lua harness's SKIP_PATTERN does — a Python test
    # that wants to skip uses pytest's own skip mechanism, which already
    # exits 0.
    return "pass" if rc == 0 else "fail"


def run_one(test: Path, cwd: Path, timeout: int) -> Result:
    started = time.monotonic()
    is_py = test.suffix == ".py"
    cmd = [sys.executable, "-m", "pytest", "-q", str(test)] if is_py else ["lua", str(test)]
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        rc = proc.returncode
        status = classify_py(rc) if is_py else classify(out, rc)
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") if isinstance(e.stdout, str) else ""
        out += f"\n*** TIMED OUT after {timeout}s ***"
        rc, status = 124, "timeout"
    except FileNotFoundError:
        print(f"error: `{cmd[0]}` not found in PATH", file=sys.stderr)
        raise SystemExit(2)
    return Result(display_path(test, cwd), status, time.monotonic() - started, out, rc)


SYMBOL = {"pass": "ok  ", "skip": "skip", "fail": "FAIL", "timeout": "TIME"}


def report(r: Result, verbose: bool) -> None:
    print(f"  {SYMBOL[r.status]}  {r.path}  ({r.seconds:.1f}s)")
    if r.status in ("fail", "timeout"):
        # Show the failing assertions, then a tail for context — the same
        # information the shell harness surfaced, minus the noise.
        lines = r.output.splitlines()
        interesting = [l for l in lines if "FAIL:" in l or "Results:" in l]
        for line in interesting[:20]:
            print(f"        {line.strip()}")
        if not interesting:
            for line in lines[-8:]:
                print(f"        {line.rstrip()}")
        print(f"        (exit {r.returncode})")
    elif verbose:
        for line in r.output.splitlines():
            print(f"        {line.rstrip()}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Run the TOS test suite in parallel.")
    ap.add_argument("-j", "--jobs", type=int, default=0,
                    help="worker count (default: CPU count, capped at 16)")
    ap.add_argument("--serial", action="store_true",
                    help="run one at a time (use when bisecting a flake)")
    ap.add_argument("-k", "--filter", action="append", default=[],
                    help="only tests whose path contains this (repeatable)")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="print every test's output, not just failures")
    ap.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                    help=f"per-test timeout in seconds (default {DEFAULT_TIMEOUT})")
    args = ap.parse_args()

    tests = discover()
    if args.filter:
        tests = [(t, c) for (t, c) in tests
                 if any(f.lower() in display_path(t, c).lower() for f in args.filter)]

    if not tests:
        print("No tests found.")
        return 1

    workers = 1 if args.serial else (args.jobs or min(16, os.cpu_count() or 4))

    exclusive = [(t, c) for (t, c) in tests if t.name in EXCLUSIVE]
    shared = [(t, c) for (t, c) in tests if t.name not in EXCLUSIVE]

    print(f"Running {len(tests)} test file(s) "
          f"with {workers} worker(s), {args.timeout}s timeout")
    if exclusive and not args.serial:
        names = ", ".join(t.name for t, _ in exclusive)
        print(f"  ({names} run first, alone — they write shared scratch dirs)")
    print()

    started = time.monotonic()
    results: list[Result] = []

    # Exclusive first, alone.
    for test, cwd in exclusive:
        r = run_one(test, cwd, args.timeout)
        results.append(r)
        report(r, args.verbose)

    # Then the pool. Results are collected and printed in DISCOVERY order,
    # not completion order — a parallel run whose output reshuffles every
    # time is unreadable, and undiffable against a previous run.
    if shared:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = [pool.submit(run_one, t, c, args.timeout) for t, c in shared]
            for f in futures:
                r = f.result()
                results.append(r)
                report(r, args.verbose)

    elapsed = time.monotonic() - started

    passed = sum(1 for r in results if r.status == "pass")
    skipped = sum(1 for r in results if r.status == "skip")
    failed = [r for r in results if not r.ok]

    print()
    print("-" * 43)
    print(f"PASS={passed} FAIL={len(failed)} SKIP(needs-TOS)={skipped}"
          f"   in {elapsed:.1f}s")
    if failed:
        print("Failed/unclear:")
        for r in failed:
            print(f"  {r.path}  ({r.status})")

    # Slowest few — worth knowing which tests dominate the wall clock.
    if args.verbose or not failed:
        slowest = sorted(results, key=lambda r: r.seconds, reverse=True)[:3]
        if slowest and slowest[0].seconds >= 0.5:
            times = ", ".join(f"{r.path.split('/')[-1]} {r.seconds:.1f}s"
                              for r in slowest)
            print(f"Slowest: {times}")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
