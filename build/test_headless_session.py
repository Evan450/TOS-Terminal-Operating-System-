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
CLI = "'help' lists them · 'tui' returns to the full\n\nroot:/$\n"
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
    assert re.search(w[-1][2], CLI, re.M)          # ui = "cli" boots to root:/$
    assert not re.search(w[-1][2], FIRST_BOOT, re.M)


def test_login_types_the_user_then_the_password():
    steps = hsess.expand(["login alice s3cret"])
    typed = [s for s in steps if s.startswith("type ")]
    assert typed[:2] == ["type alice\\n", "type s3cret\\n"]


def test_login_skips_a_first_login_tour_only_when_one_appears():
    # An account's first login opens its tour, a later one does not; every
    # key that dismisses the tour must sit behind a `maybe`, or a later
    # login would type them into the shell.
    steps = [s for s in hsess.expand(["login alice s3cret"]) if not s.startswith("#")]
    for i, step in enumerate(steps):
        if step in ("key ctrl+q", "type y"):
            assert steps[i - 1].startswith("maybe "), step
    assert steps[-1].startswith("wait ") and "alice" in steps[-1]
    w = waits(steps)
    assert re.search(w[0][2], LOGIN, re.M)
    assert re.search(w[-1][2], "alice@tos:/home/alice$ _", re.M)
    assert re.search(w[-1][2], "alice:/home/alice$", re.M)   # the CLI's prompt
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


def test_put_writes_a_file_onto_the_boot_disk(tmp_path):
    rel = _release(tmp_path, armed=False)
    boot, _, _ = hsess.stage(tmp_path / "run", rel, None, ['/etc/boot.cfg=return { ui = "cli" }'])
    assert (boot / "etc" / "boot.cfg").read_text() == 'return { ui = "cli" }'
    assert not (rel / "etc" / "boot.cfg").exists()     # the release is left alone


@pytest.mark.parametrize("bad", ["etc/boot.cfg=x", "/etc/../../escape=x", "/etc/boot.cfg"])
def test_put_refuses_relative_climbing_or_valueless_paths(tmp_path, bad):
    # A path that climbs out would write into the host's temp directory,
    # beside the machine rather than on it.
    with pytest.raises(ValueError):
        hsess.stage(tmp_path / "run", _release(tmp_path, armed=False), None, [bad])


# ============================================================
# stage_openos() -- OpenOS from the jar, to install TOS from
# ============================================================

def _fake_jar(tmp: Path) -> Path:
    import zipfile
    jar = tmp / "ocelot-desktop-v0.jar"
    with zipfile.ZipFile(jar, "w") as z:
        z.writestr("assets/opencomputers/loot/openos/init.lua", "-- openos init")
        z.writestr("assets/opencomputers/loot/openos/lib/shell.lua", "-- shell")
        z.writestr("assets/opencomputers/loot/openos/../../escape.lua", "nope")
        z.writestr("assets/opencomputers/lua/bios.lua", "-- the stock Lua BIOS")
        z.writestr("assets/opencomputers/loot/tape/tape.lua", "-- another disk")
    return jar


def test_stage_openos_copies_only_the_openos_tree(tmp_path):
    boot, work, bios = hsess.stage_openos(tmp_path / "run", _fake_jar(tmp_path))
    files = sorted(str(p.relative_to(boot)).replace("\\", "/") for p in boot.rglob("*") if p.is_file())
    assert files == ["init.lua", "lib/shell.lua"]
    assert bios.read_text() == "-- the stock Lua BIOS"
    assert not (tmp_path / "escape.lua").exists()


def test_the_install_disk_address_mounts_at_d15():
    # OpenOS mounts a disk at /mnt/<first three characters of its address>,
    # and every installer script types /mnt/d15/install.lua.
    assert hsess.INSTALL_DISK_ADDRESS[:3] == "d15"
    assert re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",
                        hsess.INSTALL_DISK_ADDRESS)
