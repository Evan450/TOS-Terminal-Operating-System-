"""Tests for floorcheck.py's cases -- without booting anything.

WHY THIS EXISTS. floorcheck.py is only worth running while its cases check
what the README says and what TOS's own thresholds are, and those drift
apart without a JVM in sight: someone edits the README's Requirements, or
bootcfg.PANELS_MIN_KB, and the check quietly goes on testing the old
claim. These run in the ordinary suite, so that drift fails at once. The
boots themselves are `python tos.py floorcheck`.

Run: pytest TOS-Dev/build/test_floorcheck.py
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
DEV = HERE.parent


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


fc = _load("floorcheck", "floorcheck.py")
hs = _load("headless_session_for_floorcheck", "headless-session.py")
README = (DEV / "README.md").read_text(encoding="utf-8")


def _steps(case):
    return [s for s in hs.expand(list(case.script)) if s.strip() and not s.startswith("#")]


def test_every_case_matches_the_readme():
    assert fc.readme_mismatches(README) == []


def test_a_changed_readme_is_caught():
    out = fc.readme_mismatches(README.replace("about 280 KB free", "about 300 KB free"))
    assert out == ["1536K: the README no longer says 'about 280 KB free after you log in'"]


def test_the_panels_floor_is_bootcfgs():
    src = (DEV / "tos" / "kernel" / "bootcfg.lua").read_text(encoding="utf-8")
    panels_min = int(re.search(r"bootcfg\.PANELS_MIN_KB\s*=\s*(\d+)", src).group(1))
    panels = [c for c in fc.CASES if "wait 30 View:" in c.script]
    cli = [c for c in fc.CASES if "wait 30 TOS CLI" in c.script]
    assert panels and cli
    assert min(c.kb for c in panels) == panels_min
    assert all(c.kb < panels_min for c in cli)


def test_the_package_manager_floor_is_the_one_pkg_reports():
    src = (DEV / "tos" / "shell" / "panels" / "commands" / "admin.lua").read_text(encoding="utf-8")
    pkg_min = int(re.search(r"local PKG_MIN_KB = (\d+)", src).group(1))
    checked = [c.kb for c in fc.CASES
               if not c.net and any("No packages installed" in s for s in c.script)]
    assert checked == [pkg_min]


def test_both_sides_of_each_floor_are_checked():
    # The point of the check: a floor that DROPPED is as wrong in the README
    # as one that rose, so each one needs a case below it that must fail.
    def falls_short(c):
        return c.script == fc.NO_COMMAND or "wait 120 ERR_OUT_OF_MEMORY" in c.script
    for net in (False, True):
        cases = [c for c in fc.CASES if c.net == net]
        works = [c.kb for c in cases if not falls_short(c)]
        fails = [c.kb for c in cases if falls_short(c)]
        assert works and fails, net
        assert max(fails) < min(works), net


def test_ram_is_real_sticks_adding_up_to_the_size():
    sticks = {"192", "256", "384", "512", "768", "1024"}
    for c in fc.CASES:
        parts = c.ram.split(",")
        assert len(parts) <= 2 and set(parts) <= sticks, c.name
        assert sum(int(p) for p in parts) == c.kb, c.name


def test_scripts_use_only_steps_the_runner_knows():
    java = (HERE / "HeadlessTOS.java").read_text(encoding="utf-8")
    verbs = set(re.findall(r'case "(\w+)":', java))
    for c in fc.CASES:
        for step in _steps(c):
            assert step.split()[0] in verbs, (c.name, step)
            if step.split()[0] in ("wait", "gone", "maybe"):
                re.compile(step.split(None, 2)[2])


def test_snaps_and_the_free_reading_parse():
    out = ("release: build abc123\n[step]   1 wait 120 New password:   ok at 17.5s\n\n"
           "--- mem\n=== Memory ===\n RAM:  992K used / 1024K total   (96% used, 31K\nfree)\n\n"
           "--- pkg\nroot:/$ pkg list\nNo packages installed.\n")
    snaps = fc.parse_snaps(out)
    assert set(snaps) == {"mem", "pkg"}
    assert fc.free_kb(snaps["mem"]) == 31
    assert fc.free_kb("Free: 28K of 768K  (rescue reading)") is None


def test_far_apart_allows_a_noisy_reading():
    assert not fc.far_apart(31, 35)
    assert not fc.far_apart(803, 800)
    assert fc.far_apart(280, 200)


def _run(case, monkeypatch, code, stdout):
    monkeypatch.setattr(fc.subprocess, "run",
                        lambda *a, **k: SimpleNamespace(returncode=code, stdout=stdout, stderr=""))
    return fc.run_case(case, keep=False, timeout=10)


SHELL_UP = "[step]   9 wait 30 TOS CLI                                ok at 21.8s, 0.06s\n"


def test_running_out_of_memory_after_the_shell_started_proves_no_command_loads(monkeypatch):
    case = next(c for c in fc.CASES if c.kb == 768)
    r = _run(case, monkeypatch, 5, SHELL_UP
             + "[step]  13 FAILED: the machine went down: not enough memory\n")
    assert r.holds and r.went_down


def test_going_down_before_the_shell_started_does_not(monkeypatch):
    case = next(c for c in fc.CASES if c.kb == 768)
    r = _run(case, monkeypatch, 5, "[step]   1 FAILED: the machine went down: not enough memory\n")
    assert not r.holds


def test_a_command_that_loads_where_none_should_is_a_failure(monkeypatch):
    case = next(c for c in fc.CASES if c.kb == 1024 and c.net)
    r = _run(case, monkeypatch, 5, SHELL_UP
             + "[step]  13 FAILED: wait timed out after 20s: need more memory than is free\n"
             "\n--- screen when it stopped\n=== Memory ===\n RAM: 900K used\n")
    assert not r.holds
    assert any("timed out" in line for line in r.why)


def test_the_pkg_probe_is_reported_not_failed(monkeypatch, capsys):
    case = next(c for c in fc.CASES if c.probe_pkg)
    r = _run(case, monkeypatch, 0, "release: build abc\n\n--- mem\n(96% used, 31K\n\n"
             "--- pkg\nNo packages installed.\n")
    assert r.holds and r.pkg_loaded and r.free == 31
    assert fc.report([r]) == 0
    assert "note: 1024K: `pkg list` loaded" in capsys.readouterr().out
