#!/usr/bin/env python3
"""Drive a fresh TOS at the keyboard on a headless OpenComputers machine.

WHY THIS EXISTS. Most of TODO's "Emulator checklist" items are not battery
material: they are shell sessions -- type a command, read what the screen
says, reboot, look again -- and the battery runs before the shell exists.
They stayed open because each one meant a person at Ocelot's window. This
runs the same kind of session from a script, on the same headless machine
headless-selftest.py uses (HeadlessTOS.java on Ocelot Brain), and reads the
answers off the real screen.

    python TOS-Dev/build/headless-session.py SCRIPT [--profile t3|t1]
        [--ram KB[,KB]] [--disk DIR] [--put PATH=TEXT] [--timeout SECS]
        [--trace] [--keep] [--internet]
        [--ocelot DIR] [--java PATH] [--javac PATH] [--config FILE]

A script is one step per line (HeadlessTOS.java's runScript lists them):
`wait SECS REGEX`, `gone SECS REGEX`, `type TEXT` (\\n is Enter), `key NAME
[N]` (ctrl+q, f10, up, ...), `paste TEXT`, `click X Y`, `sleep SECS`, `mark
NAME`, `snap NAME`, `off SECS`, `powercycle`. Two more are expanded here:

    firstboot [PASSWORD]   set root's password at First Boot Setup, skip the
                           tutorial, and wait for the shell prompt
    login USER PASSWORD    log in at the login screen of a later boot

Every round boots a FRESH copy of TOS-Release (unarmed: no battery), with
--disk copied in as a second disk. --profile t1 is a T1 CPU, GPU and screen
on one 192K stick with no data card, the smallest box TOS claims to run on.

Prints each step with its time (a `wait` after a `mark` also reports the
time since the mark, which is how timings come back), then every `snap`.
Exit: 0 the script completed, 5 a step failed -- the screen at that moment
is printed with the tail of kernel.log -- anything else the machine itself.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _load_selftest_driver():
    # The tool-finding and compile cache are headless-selftest.py's; one
    # copy, loaded by path because the hyphen rules out `import`.
    spec = importlib.util.spec_from_file_location("headless_selftest", HERE / "headless-selftest.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("headless_selftest", mod)
    spec.loader.exec_module(mod)
    return mod


hs = _load_selftest_driver()

DEFAULT_PASSWORD = "headless1"


def expand(lines: list[str]) -> list[str]:
    """Expand `firstboot` and `login` into the steps they stand for."""
    out: list[str] = []
    for raw in lines:
        line = raw.strip()
        word = line.split(None, 1)[0] if line else ""
        if word == "firstboot":
            parts = line.split()
            pw = parts[1] if len(parts) > 1 else DEFAULT_PASSWORD
            out += [
                "# firstboot: root's password, then skip the tutorial",
                "wait 120 New password:",
                f"type {pw}\\n",
                f"type {pw}\\n",
                "wait 60 Welcome to TOS v",
                "key ctrl+q",
                r"wait 15 Skip tutorial\?",
                "type y",
                # root@tos:/$ in the panels shell, root:/$ in the CLI.
                r"wait 30 root(@\S+)?:\S*\$",
            ]
        elif word == "login":
            parts = line.split()
            if len(parts) != 3:
                raise ValueError(f"login takes USER PASSWORD: {line!r}")
            out += [
                f"# login {parts[1]}",
                "wait 120 (?i)(login|username|user name):",
                f"type {parts[1]}\\n",
                "wait 15 (?i)password:",
                f"type {parts[2]}\\n",
                rf"wait 60 {re.escape(parts[1])}(@\S+)?:\S*[$#]",
            ]
        else:
            out.append(raw.rstrip("\r\n"))
    return out


def stage(run: Path, release: Path, disk: Path | None,
          put: list[str] | None = None) -> tuple[Path, Path | None, Path]:
    """A fresh, UNARMED machine: no /etc/selftest.on, so no battery runs.

    `put` is PATH=TEXT pairs written onto the boot disk first -- a boot.cfg
    to try a profile, a config file a checklist item needs.
    """
    boot, work = run / "boot", run / "work"
    shutil.copytree(release, boot)
    marker = boot / "etc" / "selftest.on"
    if marker.exists():
        marker.unlink()
    for spec in put or []:
        path, sep, text = spec.partition("=")
        if not sep or not path.startswith("/") or ".." in path.split("/"):
            raise ValueError(f"--put takes /ABSOLUTE/PATH=TEXT: {spec!r}")
        target = boot / path.lstrip("/")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
    staged = None
    if disk is not None:
        staged = run / "disk"
        shutil.copytree(disk, staged)
    work.mkdir()
    return boot, staged, work


def main(argv: list[str] | None = None) -> int:
    # Screens are box-drawing and Unicode; a Windows console or pipe defaults
    # to cp1252 and would crash printing the first frame.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("script", help="the steps to run")
    ap.add_argument("--profile", choices=["t3", "t1"], default="t3")
    ap.add_argument("--ram", help="memory sticks in KB, e.g. 256 or 384,384 "
                    "(192/256/384/512/768/1024; default 1024,1024, or 192 for t1)")
    ap.add_argument("--disk", help="a folder to insert as a second disk (copied first)")
    ap.add_argument("--put", action="append", metavar="PATH=TEXT",
                    help="write TEXT to PATH on the boot disk before it boots, e.g. "
                         "--put '/etc/boot.cfg=return { ui = \"cli\" }' (repeatable)")
    ap.add_argument("--timeout", type=float, default=600.0, help="seconds for the whole script (600)")
    ap.add_argument("--trace", action="store_true", help="keep every distinct screen in frames.txt")
    ap.add_argument("--keep", action="store_true", help="keep the run directory even on success")
    ap.add_argument("--internet", action="store_true", help="give the machine an internet card")
    ap.add_argument("--ocelot", help="Ocelot Desktop's jar, or the folder holding it")
    ap.add_argument("--java", help="the java to run the machine on")
    ap.add_argument("--javac", help="the javac to compile the runner with")
    ap.add_argument("--config", help="an OpenComputers.conf (default: the one beside the jar)")
    args = ap.parse_args(argv)

    script = Path(args.script)
    if not script.is_file():
        print(f"error: no script at {script}", file=sys.stderr)
        return 1
    if not (hs.RELEASE / "init.lua").is_file():
        print("error: TOS-Release not found -- run `python tos.py build` first", file=sys.stderr)
        return 1
    jar = hs.find_jar(args.ocelot)
    java, javac = hs.find_java(args.java), hs.find_javac(args.javac)
    if not jar or not java or not javac:
        print("error: needs Ocelot Desktop's jar (--ocelot), a JDK and a Java; "
              "see headless-selftest.py --help", file=sys.stderr)
        return 1
    try:
        steps = expand(script.read_text(encoding="utf-8").splitlines())
        classes = hs.compile_runner(javac, jar)
    except (ValueError, RuntimeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    run = Path(tempfile.mkdtemp(prefix="tos-session-"))
    try:
        boot, disk, work = stage(run, hs.RELEASE, Path(args.disk) if args.disk else None, args.put)
    except ValueError as e:
        shutil.rmtree(run, ignore_errors=True)
        print(f"error: {e}", file=sys.stderr)
        return 1
    (work / "script.txt").write_text("\n".join(steps) + "\n", encoding="utf-8")
    config = Path(args.config) if args.config else jar.parent / "OpenComputers.conf"
    cmd = [java, "-Xmx1G", "-cp", f"{classes}{os.pathsep}{jar}", "HeadlessTOS",
           "--boot", str(boot), "--bios", str(hs.RELEASE / "bios.lua"), "--work", str(work),
           "--timeout", str(args.timeout), "--profile", args.profile,
           "--script", str(work / "script.txt")]
    if disk is not None:
        cmd += ["--disk", str(disk)]
    if args.ram:
        cmd += ["--ram", args.ram]
    if config.is_file():
        shutil.copy2(config, work / "OpenComputers.conf")
        cmd += ["--config", str(work / "OpenComputers.conf")]
    if args.internet:
        cmd.append("--internet")
    if args.trace:
        cmd.append("--trace")
    stamp = hs.build_stamp(hs.RELEASE)
    print(f"release: build {stamp or '?'}   profile: {args.profile}   machine: {run}")

    try:
        done = subprocess.run(cmd, capture_output=True, text=True, errors="replace",
                              timeout=args.timeout + 60)
        code, out = done.returncode, done.stdout + done.stderr
    except subprocess.TimeoutExpired as e:
        code, out = 2, str(e.stdout or "") + "\n(the JVM itself had to be killed)"
    for line in out.splitlines():
        if line.startswith(("[step]", "[headless]")):
            print(line)

    for snap in sorted(work.glob("snap-*.txt"), key=lambda p: p.stat().st_mtime):
        print(f"\n--- {snap.stem[5:]}")
        print(snap.read_text(encoding="utf-8", errors="replace").rstrip())
    if code != 0:
        print("\n--- screen when it stopped")
        print(hs.tail(work / "fail-screen.txt" if (work / "fail-screen.txt").exists()
                      else work / "screen.txt", 60).rstrip())
        print("--- kernel.log (last 30 lines)")
        print(hs.tail(boot / "var" / "log" / "kernel.log", 30))
        other = [l for l in out.splitlines() if not l.startswith(("[step]", "[headless]"))]
        if other:
            print("--- runner output (last 20 lines)")
            print("\n".join(other[-20:]))
    if code == 0 and not args.keep:
        shutil.rmtree(run, ignore_errors=True)
    else:
        print(f"\nkept: {run}")
    return code


if __name__ == "__main__":
    sys.exit(main())
