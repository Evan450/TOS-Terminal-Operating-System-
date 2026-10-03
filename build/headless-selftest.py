#!/usr/bin/env python3
"""Run the boot self-test battery on a headless OpenComputers machine.

WHY THIS EXISTS. The battery (kernel/selftest.lua) is the only thing that
tests TOS against a real OpenComputers implementation, and running it had
one manual step left: pressing the power button in Ocelot's window. Ocelot
Desktop has no headless mode and no power-on flag, and ocvm (what OCOS uses
for the same job) is not on this machine.

But Ocelot Desktop is a window around Ocelot Brain -- OpenComputers' machine
with Minecraft taken out -- and its jar carries Brain whole. HeadlessTOS.java,
beside this file, builds a computer from Brain's own classes, powers it on
and ticks its world with no window at all. It is the same machine.lua, the
same native Lua 5.3 and the same component code the GUI runs.

Each round gets a FRESH machine in a temporary directory: a copy of
TOS-Release as the boot disk (armed with an empty /etc/selftest.on), the
battery's checks on a second disk with the round's options, and a new
workspace. Nothing touches your Ocelot workspace, and no stale log from an
earlier round can be read as this one's.

    python TOS-Dev/build/headless-selftest.py [--ocelot DIR] [--java PATH]
        [--javac PATH] [--checks DIR] [--only PREFIX] [--no-screen] [--internet]
        [--timeout SECS] [--keep]

Exit codes, the shape OCOS's tools/test-boot.sh settled on:
    0   the battery ran to SELFTEST END and nothing failed
    2   the log has a FAIL line
    1   no complete report: no log, a log with no SELFTEST END (STALLED --
        its last RUN line names the check that wedged), or the machine
        crashed or never powered off
On anything but 0 the run directory is kept, and the tail of kernel.log and
the last screen are printed.

Needs Ocelot Desktop's jar (found like sync-emulator.py finds a workspace,
or --ocelot), a JDK to compile the runner once (cached by source hash), and
a Java to run it -- Java 8 preferred, as Ocelot's own launcher prefers it.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEV = HERE.parent
ROOT = DEV.parent
RELEASE = ROOT / "TOS-Release"
RUNNER = HERE / "HeadlessTOS.java"
# TOS-Extras is a sibling of TOS-Dev in the monorepo and nested inside it on
# the published dev branch; tos.py and run_tests.py follow the same rule.
_EXTRAS = ROOT / "TOS-Extras" if (ROOT / "TOS-Extras").is_dir() else DEV / "TOS-Extras"
CHECKS = _EXTRAS / "modules" / "selftest" / "usr" / "lib" / "selftest"


# ── Finding the tools ────────────────────────────────────────────────

def find_jar(explicit: str | None) -> Path | None:
    """Ocelot Desktop's jar: --ocelot (the jar, or the folder holding it),
    then $OCELOT_EMULATOR, then the first *Ocelot* folder under Documents,
    Desktop or home that has one. The newest version wins in a folder."""
    def in_dir(d: Path) -> Path | None:
        for cand in (d, d.parent):
            jars = sorted(cand.glob("ocelot-desktop*.jar")) if cand.is_dir() else []
            if jars:
                return jars[-1]
        return None

    if explicit:
        p = Path(explicit)
        return p if p.is_file() else (in_dir(p) if p.is_dir() else None)
    env = os.environ.get("OCELOT_EMULATOR")
    if env and Path(env).is_dir():
        found = in_dir(Path(env))
        if found:
            return found
    home = Path.home()
    for base in (home / "Documents", home / "Desktop", home):
        if base.is_dir():
            for cand in sorted(base.glob("*Ocelot*")):
                found = in_dir(cand) if cand.is_dir() else None
                if found:
                    return found
    return None


def _java_homes() -> list[Path]:
    homes = []
    jh = os.environ.get("JAVA_HOME")
    if jh:
        homes.append(Path(jh))
    for base in (os.environ.get("ProgramFiles"), os.environ.get("ProgramFiles(x86)")):
        if not base:
            continue
        for vendor in ("Eclipse Adoptium", "Java", "Microsoft", "Zulu", "Amazon Corretto"):
            d = Path(base) / vendor
            if d.is_dir():
                homes += sorted(p for p in d.iterdir() if p.is_dir())
    return homes


def _exe(home: Path, name: str) -> Path | None:
    for n in (name + ".exe", name):
        p = home / "bin" / n
        if p.is_file():
            return p
    return None


def find_java(explicit: str | None) -> str | None:
    """Java 8 first: it is what Ocelot's launcher runs, so a round here runs
    on the same JVM a round in the window does. Any Java runs the runner."""
    if explicit:
        return explicit
    homes = _java_homes()
    eight = [h for h in homes if re.search(r"(jre|jdk)-?1?\.?8", h.name)]
    for h in eight + homes:
        exe = _exe(h, "java")
        if exe:
            return str(exe)
    return shutil.which("java")


def find_javac(explicit: str | None) -> str | None:
    if explicit:
        return explicit
    for h in _java_homes():
        exe = _exe(h, "javac")
        if exe:
            return str(exe)
    return shutil.which("javac")


def compile_runner(javac: str, jar: Path, cache_root: Path | None = None) -> Path:
    """Compile HeadlessTOS.java once per (source, jar) and reuse it.

    --release 8, so the classes run on the Java 8 Ocelot itself prefers. The
    cache lives in the system temp directory, never in the tree.
    """
    key = hashlib.sha256(RUNNER.read_bytes() + jar.name.encode()
                         + str(jar.stat().st_size).encode()).hexdigest()[:16]
    out = (cache_root or Path(tempfile.gettempdir()) / "tos-headless") / key
    if (out / "HeadlessTOS.class").is_file():
        return out
    out.mkdir(parents=True, exist_ok=True)
    cmd = [javac, "--release", "8", "-nowarn", "-cp", str(jar), "-d", str(out), str(RUNNER)]
    done = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    if done.returncode != 0 or not (out / "HeadlessTOS.class").is_file():
        raise RuntimeError("could not compile HeadlessTOS.java:\n" + done.stdout + done.stderr)
    return out


# ── The round ────────────────────────────────────────────────────────

def marker_text(screen: bool = True, only: str | None = None) -> str:
    """The test disk's selftest.on: OPTIONS only (the machine's own empty
    /etc/selftest.on is what arms it). shutdown=true is what lets a round
    end by itself; without it the machine boots on to the login screen."""
    lines = ["shutdown=true"]
    if screen:
        lines.append("screen=true")
    if only:
        lines.append(f"only={only}")
    return "\n".join(lines) + "\n"


def stage(run: Path, release: Path, checks: Path, marker: str) -> tuple[Path, Path, Path]:
    """Lay out a fresh machine under `run`: (boot, disk, work)."""
    boot, disk, work = run / "boot", run / "disk", run / "work"
    shutil.copytree(release, boot)
    (boot / "etc").mkdir(exist_ok=True)
    (boot / "etc" / "selftest.on").write_text("")
    disk.mkdir(parents=True)
    for p in sorted(checks.glob("*.lua")):
        shutil.copy2(p, disk / p.name)
    (disk / "selftest.on").write_text(marker)
    work.mkdir()
    return boot, disk, work


def verdict(log: str | None) -> tuple[int, str]:
    """(exit code, one line) for a selftest.log's text, or None for none."""
    if not log or not log.strip():
        return 1, "no report: /var/selftest.log was never written"
    lines = log.splitlines()
    if not any(l.startswith("SELFTEST END") for l in lines):
        runs = [l for l in lines if l.startswith("RUN ")]
        last = runs[-1][4:].strip() if runs else "(before the first check)"
        return 1, f"STALLED: no SELFTEST END; the last check started was {last}"
    end = next(l for l in lines if l.startswith("SELFTEST END"))
    if any(l.startswith("FAIL") for l in lines):
        return 2, "FAILED: " + end
    return 0, "passed: " + end


def build_stamp(release: Path) -> str | None:
    try:
        m = re.search(r'build\s*=\s*"([^"]+)"', (release / "init.lua").read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return None
    return m.group(1) if m else None


def head_short() -> str | None:
    try:
        out = subprocess.run(["git", "-C", str(DEV), "rev-parse", "--short=7", "HEAD"],
                             capture_output=True, text=True)
    except OSError:
        return None
    return out.stdout.strip() or None


def tail(path: Path, n: int) -> str:
    try:
        return "\n".join(path.read_text(encoding="utf-8", errors="replace").splitlines()[-n:])
    except OSError:
        return "(none)"


def main(argv: list[str] | None = None) -> int:
    # Screens are box-drawing and Unicode; a Windows console or pipe defaults
    # to cp1252 and would crash printing the first frame.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ocelot", help="Ocelot Desktop's jar, or the folder holding it")
    ap.add_argument("--java", help="the java to run the machine on (default: Java 8 if found)")
    ap.add_argument("--javac", help="the javac to compile the runner with (any JDK 9+)")
    ap.add_argument("--config", help="an OpenComputers.conf (default: the one beside the jar)")
    ap.add_argument("--checks", help="a folder of checks to run instead of the battery's "
                    "(a developer's own, say)")
    ap.add_argument("--only", help="run only the checks whose names start with this")
    ap.add_argument("--no-screen", action="store_true",
                    help="skip the checks that draw on the boot console")
    ap.add_argument("--internet", action="store_true",
                    help="give the machine an internet card (real network access)")
    ap.add_argument("--timeout", type=float, default=240.0,
                    help="seconds before a machine still running counts as stuck (240)")
    ap.add_argument("--keep", action="store_true", help="keep the run directory even on a pass")
    args = ap.parse_args(argv)

    if not (RELEASE / "init.lua").is_file():
        print("error: TOS-Release not found -- run `python tos.py build` first", file=sys.stderr)
        return 1
    checks = Path(args.checks) if args.checks else CHECKS
    if not checks.is_dir() or not any(checks.glob("*.lua")):
        print(f"error: no self-test checks at {checks}", file=sys.stderr)
        return 1
    jar = find_jar(args.ocelot)
    if not jar:
        print("error: Ocelot Desktop's jar not found. Pass --ocelot, or set OCELOT_EMULATOR "
              "to the folder holding it.", file=sys.stderr)
        return 1
    java, javac = find_java(args.java), find_javac(args.javac)
    if not java or not javac:
        print("error: needs a JDK to compile the runner (javac) and a Java to run it.\n"
              "  winget install EclipseAdoptium.Temurin.21.JDK", file=sys.stderr)
        return 1

    stamp, head = build_stamp(RELEASE), head_short()
    print(f"jar:     {jar}")
    print(f"java:    {java}")
    print(f"release: build {stamp or '?'}" + (f"  (HEAD is {head})" if head and head != stamp else ""))
    if head and stamp and head != stamp:
        print("warning: TOS-Release was not built from HEAD; this round tests that build, "
              "not your tree. `python tos.py selftest` builds first.")

    try:
        classes = compile_runner(javac, jar)
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    run = Path(tempfile.mkdtemp(prefix="tos-selftest-"))
    boot, disk, work = stage(run, RELEASE, checks,
                             marker_text(screen=not args.no_screen, only=args.only))
    config = Path(args.config) if args.config else jar.parent / "OpenComputers.conf"
    cmd = [java, "-Xmx1G", "-cp", f"{classes}{os.pathsep}{jar}", "HeadlessTOS",
           "--boot", str(boot), "--disk", str(disk), "--bios", str(RELEASE / "bios.lua"),
           "--work", str(work), "--timeout", str(args.timeout)]
    if config.is_file():
        shutil.copy2(config, work / "OpenComputers.conf")   # Brain may write it back
        cmd += ["--config", str(work / "OpenComputers.conf")]
    if args.internet:
        cmd.append("--internet")
    print(f"machine: {run}")
    print()

    try:
        done = subprocess.run(cmd, capture_output=True, text=True, errors="replace",
                              timeout=args.timeout + 60)
        machine_code, out = done.returncode, done.stdout + done.stderr
    except subprocess.TimeoutExpired as e:
        machine_code, out = 2, str(e.stdout or "") + "\n(the JVM itself had to be killed)"
    for line in out.splitlines():
        if line.startswith("[headless]"):
            print(line)

    log_path = boot / "var" / "selftest.log"
    log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else None
    code, summary = verdict(log)
    if code == 0 and machine_code != 0:
        code, summary = 1, f"the report is complete but the machine did not power off cleanly ({machine_code})"
    print()
    print(log.rstrip() if log else "(no /var/selftest.log)")
    print()
    if code != 0:
        print("--- kernel.log (last 30 lines)")
        print(tail(boot / "var" / "log" / "kernel.log", 30))
        print("--- screen")
        print(tail(work / "screen.txt", 60).rstrip())
        print("--- runner output (last 30 lines)")
        print("\n".join(out.splitlines()[-30:]))
        print()
    print(summary)
    if code == 0 and not args.keep:
        shutil.rmtree(run, ignore_errors=True)
    else:
        print(f"kept: {run}")
    return code


if __name__ == "__main__":
    sys.exit(main())
