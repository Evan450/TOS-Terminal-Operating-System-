#!/usr/bin/env python3
"""tos - one entry point for working on TOS.

The tools were fine; the choreography was not. Building a release, building
the add-on pack, regenerating its index, signing a package and running the
suite all lived in different directories with different runtimes, so any
real task turned into a sequence of `cd`s that you had to remember in the
right order. This does not replace any of them -- it finds them, runs them
from the right place, and tells you what it ran.

    python tos.py test [--serial]     the whole suite
    python tos.py build               strip TOS-Dev -> TOS-Release
    python tos.py pack [--sign]       build the add-on disks + repo index
    python tos.py sign <dir>|--all    sign package manifests
    python tos.py key                 print the public key you sign as
    python tos.py check               the drift-sensitive checks, quickly
    python tos.py roadmap             regenerate the queue + ROADMAP.md
    python tos.py publish [args...]   hand off to the publisher (maintainer)

Run it from anywhere: every path is resolved from this file, not from the
working directory.
"""

from __future__ import annotations

import argparse
import getpass
import os
import shutil
import subprocess
import sys
from pathlib import Path

DEV = Path(__file__).resolve().parent
ROOT = DEV.parent

# TOS-Extras sits in one of two places and both are correct: a SIBLING of
# TOS-Dev in the monorepo, and INSIDE the repo root on the published dev
# branch (a contributor gets one clone, so a sibling would be outside it).
# Same rule run_tests.py follows; they must not disagree about where the
# add-ons are.
_SIBLING = ROOT / "TOS-Extras"
_NESTED = DEV / "TOS-Extras"
EXTRAS = _SIBLING if _SIBLING.is_dir() else _NESTED
RELEASE = ROOT / "TOS-Release"

WINDOWS = os.name == "nt"


class Fail(Exception):
    """A problem worth reporting plainly rather than as a traceback."""


def say(msg: str) -> None:
    print(f"==> {msg}")


def run(cmd: list[str], cwd: Path, env: dict | None = None) -> int:
    """Run a child process, echoing exactly what is being run and where.

    Echoed because the point of this script is to stop people memorising
    the choreography -- printing it means they can still learn it, and can
    reproduce a failure without this wrapper.
    """
    printable = " ".join(cmd)
    print(f"    $ {printable}")
    print(f"      (in {cwd})")
    completed = subprocess.run(cmd, cwd=str(cwd), env=env)
    return completed.returncode


def need(tool: str, hint: str) -> None:
    if shutil.which(tool) is None:
        raise Fail(f"{tool!r} is not on PATH.\n       {hint}")


def need_extras() -> Path:
    if not (EXTRAS / "build" / "build-disk.lua").is_file():
        raise Fail(
            f"no add-on source at {EXTRAS}.\n"
            "       TOS-Extras is a sibling of TOS-Dev in the monorepo and\n"
            "       lives inside the repo root on the dev branch; neither was found."
        )
    return EXTRAS


def passphrase_env() -> dict:
    """Environment carrying the signing passphrase, prompting if needed.

    Never taken from argv, and never echoed. The key is DERIVED from this
    string rather than stored, so it is the private key: argv reaches shell
    history, `ps` output and CI logs. getpass keeps it off the screen too.
    """
    env = dict(os.environ)
    if not env.get("TOS_SIGNING_PASSPHRASE"):
        try:
            entered = getpass.getpass("Signing passphrase (not echoed): ")
        except (EOFError, KeyboardInterrupt):
            raise Fail("no passphrase given.")
        if not entered:
            raise Fail("no passphrase given.")
        env["TOS_SIGNING_PASSPHRASE"] = entered
    return env


# ── Commands ─────────────────────────────────────────────────────────

def cmd_test(args) -> int:
    extra = ["--serial"] if args.serial else []
    return run([sys.executable, "run_tests.py", *extra, *args.rest], cwd=DEV)


def cmd_build(args) -> int:
    if WINDOWS and (DEV / "build" / "build-release.cmd").is_file():
        need("lua", "install with:  winget install DEVCOM.Lua")
        return run(["cmd", "/c", str(DEV / "build" / "build-release.cmd")], cwd=ROOT)
    need("bash", "use Git Bash, or run build/build-release.cmd directly")
    need("lua", "install with:  winget install DEVCOM.Lua")
    return run(["bash", "build/build-release.sh"], cwd=DEV)


def cmd_pack(args) -> int:
    extras = need_extras()
    need("lua", "install with:  winget install DEVCOM.Lua")
    env = passphrase_env() if args.sign else None
    build = ["lua", "build/build-disk.lua"] + (["--sign"] if args.sign else [])
    rc = run(build, cwd=extras, env=env)
    if rc != 0:
        return rc
    # The index is not optional bookkeeping: `pkg fetch` reads it, and a
    # pack whose index was not regenerated advertises the previous build.
    return run(["lua", "build/make-repo-index.lua"], cwd=extras)


def cmd_sign(args) -> int:
    extras = need_extras()
    need("lua", "install with:  winget install DEVCOM.Lua")
    targets = list(args.targets)
    if args.all:
        targets.append("--all")
    if not targets:
        raise Fail("give a package directory, or --all.\n"
                   "       e.g. python tos.py sign modules/mything")
    return run(["lua", "build/sign-package.lua", *targets],
               cwd=extras, env=passphrase_env())


def cmd_key(args) -> int:
    extras = need_extras()
    need("lua", "install with:  winget install DEVCOM.Lua")
    return run(["lua", "build/sign-package.lua", "--key"],
               cwd=extras, env=passphrase_env())


def cmd_check(args) -> int:
    """The checks that catch a generated artifact drifting from its source.

    Everything here is also in the suite; this is the fast subset for
    "did I forget to regenerate something", which is the failure this
    project keeps having.
    """
    checks: list[tuple[str, list[str], Path]] = [
        ("release manifest digests", ["lua", "usr/lib/tests/test_manifest_digests.lua"], DEV),
        ("manifest completeness", ["lua", "usr/lib/tests/test_manifest_completeness.lua"], DEV),
        ("release excludes", ["lua", "usr/lib/tests/test_release_excludes.lua"], DEV),
    ]
    if (EXTRAS / "build" / "test_repo_index.lua").is_file():
        checks.append(("add-on repo index", ["lua", "build/test_repo_index.lua"], EXTRAS))
    if (DEV / "todo_index.py").is_file():
        checks.append(("open queue freshness", [sys.executable, "todo_index.py", "--check"], DEV))
    if (DEV / "build" / "make_roadmap.py").is_file():
        checks.append(("roadmap freshness", [sys.executable, "build/make_roadmap.py", "--check"], DEV))

    need("lua", "install with:  winget install DEVCOM.Lua")
    worst = 0
    for label, cmd, cwd in checks:
        say(label)
        rc = run(cmd, cwd=cwd)
        worst = worst or rc
        print()
    print("OK" if worst == 0 else "Some checks failed - see above.")
    return worst


def cmd_roadmap(args) -> int:
    # Maintainer-only: TODO.txt and these generators are deliberately not
    # published, so a contributor will not have them. Say that rather than
    # failing with a bare "file not found".
    if not (DEV / "todo_index.py").is_file():
        raise Fail("todo_index.py is not present.\n"
                   "       The working notes it reads are maintainer-only and are\n"
                   "       not published; ROADMAP.md ships already generated.")
    rc = run([sys.executable, "todo_index.py"], cwd=DEV)
    if rc != 0:
        return rc
    return run([sys.executable, "build/make_roadmap.py"], cwd=DEV)


def cmd_publish(args) -> int:
    # The publisher lives outside the repo (it holds the maintainer's
    # workflow, not the project's), so this is a convenience for one person
    # and must degrade clearly for everyone else.
    script = ROOT.parent / "Working_Dir" / "tos-repo-push" / "publish.ps1"
    if not script.is_file():
        raise Fail(f"no publisher at {script}.\n"
                   "       Publishing is a maintainer workflow and is not part of\n"
                   "       this repository.")
    shell = "pwsh" if shutil.which("pwsh") else "powershell"
    return run([shell, "-NoProfile", "-File", str(script), *args.rest],
               cwd=script.parent)


def main() -> int:
    p = argparse.ArgumentParser(
        prog="tos", description="One entry point for working on TOS.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Paths resolve from this file, so it works from any directory.")
    sub = p.add_subparsers(dest="cmd", required=True)

    t = sub.add_parser("test", help="run the whole test suite")
    t.add_argument("--serial", action="store_true", help="no parallelism")
    t.add_argument("rest", nargs="*", help="passed through to run_tests.py")
    t.set_defaults(fn=cmd_test)

    b = sub.add_parser("build", help="strip TOS-Dev into TOS-Release")
    b.set_defaults(fn=cmd_build)

    k = sub.add_parser("pack", help="build the add-on disks and repo index")
    k.add_argument("--sign", action="store_true", help="sign every manifest")
    k.set_defaults(fn=cmd_pack)

    s = sub.add_parser("sign", help="sign package manifests in place")
    s.add_argument("targets", nargs="*", help="package directories")
    s.add_argument("--all", action="store_true", help="every discovered package")
    s.set_defaults(fn=cmd_sign)

    y = sub.add_parser("key", help="print the public key you sign as")
    y.set_defaults(fn=cmd_key)

    c = sub.add_parser("check", help="fast drift checks (generated vs source)")
    c.set_defaults(fn=cmd_check)

    r = sub.add_parser("roadmap", help="regenerate the queue and ROADMAP.md")
    r.set_defaults(fn=cmd_roadmap)

    u = sub.add_parser("publish", help="hand off to the publisher (maintainer)")
    u.add_argument("rest", nargs="*", help="passed through to publish.ps1")
    u.set_defaults(fn=cmd_publish)

    args = p.parse_args()
    try:
        return args.fn(args)
    except Fail as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
