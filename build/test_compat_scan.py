"""The compatibility number is a count, so the counter gets a test."""

from __future__ import annotations

import importlib.util
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("compat_scan", HERE / "compat_scan.py")
scan_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scan_mod)


def jar(tmp_path, files):
    path = tmp_path / "fake.jar"
    with zipfile.ZipFile(path, "w") as z:
        for name, text in files.items():
            z.writestr(scan_mod.LOOT + name, text)
    return path


def test_provided_reads_the_real_table():
    src = (HERE.parent / "tos" / "kernel" / "sandbox.lua").read_text(encoding="utf-8")
    have = scan_mod.provided(src)
    assert {"term", "event", "robot", "process", "note"} <= have


def test_a_file_needing_something_absent_is_a_gap(tmp_path):
    path = jar(tmp_path, {"d/bin/a.lua": 'local t = require("term")',
                          "d/bin/b.lua": 'local p = require("posix")'})
    disks, files, found, missing = scan_mod.scan(path, {"term"}, False)
    assert (disks, files, found) == (1, 2, 1)
    assert missing == {"posix": ["d/bin/b.lua"]}


def test_a_library_on_the_same_disk_counts(tmp_path):
    path = jar(tmp_path, {"d/bin/a.lua": 'require("mine")', "d/lib/mine.lua": "return {}"})
    assert scan_mod.scan(path, set(), False)[2] == 2


def test_operating_systems_and_man_pages_are_not_programs(tmp_path):
    path = jar(tmp_path, {"openos/bin/a.lua": 'require("nope")',
                          "plan9k/bin/b.lua": 'require("nope")',
                          "d/usr/man/thing": "local require text in a manual"})
    assert scan_mod.scan(path, set(), False)[1] == 0
