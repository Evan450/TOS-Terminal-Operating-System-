"""Tests for headless-session.py's script expansion and staging.

WHY THIS EXISTS. A session script is only as good as the two things this
driver adds to it:

  expand()   turns `firstboot` and `login` into the exact keystrokes and
             screen waits a fresh TOS needs. A wrong wait regex is not a
             failed test, it is a session that sits at First Boot Setup
             until the timeout and reports the wrong thing.
  stage()    must boot an UNARMED machine. A copy of a release that still
             carried /etc/selftest.on would run the battery at boot and,
             with a test disk's shutdown=true, power off under the script.

The machine itself (HeadlessTOS.java on Ocelot Brain) is not run here: it
needs Ocelot's jar and a JVM. A real session is
`python build/headless-session.py SCRIPT`.

Run: pytest TOS-Dev/build/test_headless_session.py
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent


def _load_module():
    spec = importlib.util.spec_from_file_location("headless_session", HERE / "headless-session.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["headless_session"] = mod
    spec.loader.exec_module(mod)
    return mod


hsess = _load_module()

FIRST_BOOT = """
               ║ Welcome to TOS!                                ║
               ║ Please set a new password for root.            ║
               ║ New password: _                                ║
"""
SHELL = "root@tos:/$ _\n▓▒░░ Memory:904K │ Disk:2.0M │ View:FILES"
LOGIN = "                    ║ Username: _                          ║\n║ Password:     ║"


def waits(steps):
    return [s.split(None, 2) for s in steps if s.startswith("wait ")]


# ============================================================
# expand() -- firstboot and login
# ============================================================

def test_ordinary_steps_pass_through_untouched():
    lines = ["type ls\\n", "key ctrl+q", "# a comment", "", "snap x"]
    assert hsess.expand(lines) == lines


def test_firstboot_types_the_password_twice_then_skips_the_tutorial():
    steps = hsess.expand(["firstboot"])
    typed = [s for s in steps if s.startswith("type ")]
    pw = hsess.DEFAULT_PASSWORD
    assert typed[:2] == [f"type {pw}\\n", f"type {pw}\\n"]
    assert "key ctrl+q" in steps and "type y" in steps
    assert steps.index("key ctrl+q") < steps.index("type y")


def test_firstboot_takes_a_password():
    steps = hsess.expand(["firstboot hunter22"])
    assert "type hunter22\\n" in steps


def test_firstboot_waits_match_the_real_screens():
    # The regexes are matched against real screens captured from a fresh
    # install, so a reworded dialog fails here, not at a session's timeout.
    w = waits(hsess.expand(["firstboot"]))
    assert re.search(w[0][2], FIRST_BOOT, re.M)
    assert re.search(w[-1][2], SHELL, re.M)
    assert not re.search(w[-1][2], FIRST_BOOT, re.M)


def test_login_types_the_user_then_the_password():
    steps = hsess.expand(["login alice s3cret"])
    typed = [s for s in steps if s.startswith("type ")]
    assert typed == ["type alice\\n", "type s3cret\\n"]
    w = waits(steps)
    assert re.search(w[0][2], LOGIN, re.M)
    assert re.search(w[-1][2], "alice@tos:/home/alice$ _", re.M)
    assert not re.search(w[-1][2], SHELL, re.M)   # root's prompt is not alice's


def test_login_needs_both_arguments():
    with pytest.raises(ValueError):
        hsess.expand(["login alice"])


# ============================================================
# stage() -- a fresh machine, NOT armed
# ============================================================

def _release(tmp: Path, armed: bool) -> Path:
    rel = tmp / "TOS-Release"
    (rel / "etc").mkdir(parents=True)
    (rel / "init.lua").write_text('build = "abc1234"\n')
    if armed:
        (rel / "etc" / "selftest.on").write_text("")
    return rel


def test_stage_never_boots_an_armed_machine(tmp_path):
    rel = _release(tmp_path, armed=True)
    boot, disk, work = hsess.stage(tmp_path / "run", rel, None)
    assert not (boot / "etc" / "selftest.on").exists()
    assert (rel / "etc" / "selftest.on").exists()     # the source is left alone
    assert disk is None and work.is_dir()


def test_stage_copies_the_disk_rather_than_lending_it(tmp_path):
    rel = _release(tmp_path, armed=False)
    src = tmp_path / "floppy"
    src.mkdir()
    (src / "programs.cfg").write_text("{}")
    boot, disk, work = hsess.stage(tmp_path / "run", rel, src)
    assert (disk / "programs.cfg").read_text() == "{}"
    (disk / "written-by-tos").write_text("x")
    assert not (src / "written-by-tos").exists()
