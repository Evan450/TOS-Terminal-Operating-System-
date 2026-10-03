"""Tests for headless-selftest.py's verdict, staging and tool-finding logic.

WHY THIS EXISTS. headless-selftest.py turns a self-test round into an exit
code, and an exit code is only worth anything if it cannot lie. The three
ways it could:

  verdict()    reads /var/selftest.log. A hung boot leaves a log with no
               SELFTEST END, and that must read as STALLED (1) -- never as
               a pass because no FAIL line happened to be written. A FAIL
               line anywhere is 2. No log at all is 1.
  stage()      builds a FRESH machine per round. It must arm the machine
               with /etc/selftest.on on the BOOT disk (only the machine arms
               the battery -- kernel/selftest.lua's #SEC note), put the
               round's OPTIONS on the test disk, and never write into the
               release tree it copies from.
  find_jar()   must find Ocelot's jar beside the Emulator folder sync-
               emulator.py finds, because $OCELOT_EMULATOR may name either.

The machine itself (HeadlessTOS.java on Ocelot Brain) is not run here: it
needs Ocelot's jar and a JVM, and this suite runs anywhere. A real round is
`python tos.py selftest`.

Run: pytest TOS-Dev/build/test_headless_selftest.py
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _load_module():
    spec = importlib.util.spec_from_file_location("headless_selftest", HERE / "headless-selftest.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["headless_selftest"] = mod
    spec.loader.exec_module(mod)
    return mod


hs = _load_module()

PASSING = """SELFTEST BEGIN at=11.6 files=2 version=1.5.0 build=e390c9b variant=minified
RUN  10-boot
PASS 10-boot  pass=6 fail=0 skip=0
RUN  20-display
PASS 20-display  pass=3 fail=0 skip=1
  ~ display :: no GPU
SELFTEST END pass=9 fail=0 skip=1 checks=10 secs=1.0
SHUTDOWN requested by marker
"""


# ============================================================
# verdict() -- the exit code must not be able to lie
# ============================================================

def test_a_complete_clean_report_passes():
    code, line = hs.verdict(PASSING)
    assert code == 0
    assert "SELFTEST END pass=9" in line


def test_a_skip_is_not_a_failure():
    # "  ~ " lines are skips; only a line STARTING with FAIL fails a round.
    assert hs.verdict(PASSING)[0] == 0


def test_a_fail_line_is_exit_2():
    log = PASSING.replace("PASS 20-display  pass=3 fail=0", "FAIL 20-display  pass=2 fail=1")
    code, line = hs.verdict(log)
    assert code == 2
    assert line.startswith("FAILED")


def test_a_check_that_could_not_load_is_a_failure():
    log = PASSING.replace("PASS 20-display  pass=3 fail=0 skip=1",
                          "FAIL 20-display :: could not load: [string]:1: syntax error")
    assert hs.verdict(log)[0] == 2


def test_no_selftest_end_is_stalled_and_names_the_check():
    log = "\n".join(PASSING.splitlines()[:4]) + "\n"   # ends at RUN 20-display
    code, line = hs.verdict(log)
    assert code == 1
    assert "STALLED" in line and "20-display" in line


def test_a_stall_with_no_fail_line_still_does_not_pass():
    # The failure mode this whole verdict exists for: nothing failed
    # because nothing finished.
    log = "SELFTEST BEGIN at=1 files=3\nRUN  10-boot\nPASS 10-boot  pass=1 fail=0 skip=0\nRUN  20-x\n"
    assert hs.verdict(log)[0] == 1


def test_a_stall_before_the_first_check_says_so():
    code, line = hs.verdict("SELFTEST BEGIN at=1 files=3\n")
    assert code == 1 and "before the first check" in line


def test_no_log_is_exit_1():
    assert hs.verdict(None)[0] == 1
    assert hs.verdict("")[0] == 1
    assert hs.verdict("   \n")[0] == 1


# ============================================================
# marker_text() -- options for the test disk
# ============================================================

def test_the_marker_always_asks_for_power_off():
    # Without shutdown=true the machine boots on to the login screen and
    # the round only ends at the timeout.
    assert "shutdown=true" in hs.marker_text()
    assert "shutdown=true" in hs.marker_text(screen=False, only="20-")


def test_the_marker_carries_screen_and_only():
    assert "screen=true" in hs.marker_text()
    assert "screen=true" not in hs.marker_text(screen=False)
    assert "only=80-" in hs.marker_text(only="80-")
    assert "only=" not in hs.marker_text()


# ============================================================
# stage() -- a fresh machine, armed the right way
# ============================================================

def _release(tmp: Path) -> Path:
    rel = tmp / "TOS-Release"
    (rel / "tos" / "kernel").mkdir(parents=True)
    (rel / "init.lua").write_text('local x = { build = "abc1234" }\n')
    (rel / "bios.lua").write_text("-- bios\n")
    (rel / "tos" / "kernel" / "selftest.lua").write_text("return {}\n")
    return rel


def _checks(tmp: Path) -> Path:
    c = tmp / "checks"
    c.mkdir()
    (c / "10-boot.lua").write_text("return function(t) end\n")
    (c / "20-display.lua").write_text("return function(t) end\n")
    (c / "README.md").write_text("not a check\n")
    return c


def test_stage_arms_the_boot_disk_not_the_test_disk(tmp_path):
    boot, disk, work = hs.stage(tmp_path / "run", _release(tmp_path), _checks(tmp_path),
                                hs.marker_text())
    armed = boot / "etc" / "selftest.on"
    assert armed.is_file()
    # EMPTY, so the test disk's options (shutdown=true) stay in force:
    # the first marker to set an option wins, and this one sets none.
    assert armed.read_text() == ""
    assert "shutdown=true" in (disk / "selftest.on").read_text()


def test_stage_copies_the_release_and_only_the_checks(tmp_path):
    boot, disk, work = hs.stage(tmp_path / "run", _release(tmp_path), _checks(tmp_path),
                                hs.marker_text())
    assert (boot / "init.lua").is_file()
    assert (boot / "tos" / "kernel" / "selftest.lua").is_file()
    assert sorted(p.name for p in disk.iterdir()) == ["10-boot.lua", "20-display.lua", "selftest.on"]
    assert work.is_dir() and not any(work.iterdir())


def test_stage_never_writes_into_the_release(tmp_path):
    rel = _release(tmp_path)
    before = sorted(str(p.relative_to(rel)) for p in rel.rglob("*"))
    hs.stage(tmp_path / "run", rel, _checks(tmp_path), hs.marker_text())
    after = sorted(str(p.relative_to(rel)) for p in rel.rglob("*"))
    assert before == after
    assert not (rel / "etc" / "selftest.on").exists()


def test_build_stamp_is_read_from_the_release(tmp_path):
    assert hs.build_stamp(_release(tmp_path)) == "abc1234"
    assert hs.build_stamp(tmp_path / "nowhere") is None


# ============================================================
# find_jar() -- the same places sync-emulator.py looks
# ============================================================

def test_find_jar_takes_the_jar_or_its_folder(tmp_path):
    jar = tmp_path / "Ocelot" / "ocelot-desktop-v1.14.2.jar"
    jar.parent.mkdir()
    jar.write_bytes(b"PK")
    assert hs.find_jar(str(jar)) == jar
    assert hs.find_jar(str(jar.parent)) == jar


def test_find_jar_accepts_the_emulator_folder_below_it(tmp_path):
    # $OCELOT_EMULATOR may name the Emulator/ workspace sync-emulator.py
    # writes to; the jar is one level up.
    jar = tmp_path / "Ocelot" / "ocelot-desktop-v1.14.2.jar"
    (tmp_path / "Ocelot" / "Emulator").mkdir(parents=True)
    jar.write_bytes(b"PK")
    assert hs.find_jar(str(tmp_path / "Ocelot" / "Emulator")) == jar


def test_find_jar_prefers_the_newest_version(tmp_path):
    d = tmp_path / "Ocelot"
    d.mkdir()
    for v in ("1.13.0", "1.14.2"):
        (d / f"ocelot-desktop-v{v}.jar").write_bytes(b"PK")
    assert hs.find_jar(str(d)).name == "ocelot-desktop-v1.14.2.jar"


def test_find_jar_explicit_but_missing_is_none(tmp_path):
    assert hs.find_jar(str(tmp_path / "nope.jar")) is None
