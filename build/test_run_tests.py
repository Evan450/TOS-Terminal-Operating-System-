"""Tests for run_tests.py's display paths.

WHY THIS EXISTS. run_tests.py prints every test it ran by path, and a
contributor copies that path to re-run one test by hand. The add-on prefix
was hard-coded "../TOS-Extras/", which is right for the maintainer's
monorepo, where TOS-Extras is a SIBLING of TOS-Dev, and wrong for the
published dev branch, where it is NESTED inside the repo: every add-on test
was listed at a path outside the checkout. display_path now reports where
the file really is, relative to TOS-Dev, in both layouts.

run_tests.py is loaded by path (it is a script, not a package), and put in
sys.modules first because its @dataclass needs to find its own module.

Run: pytest TOS-Dev/build/test_run_tests.py
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _load_module():
    # No bytecode: importing run_tests.py would otherwise leave a
    # __pycache__/ at the repo ROOT, which the release scripts do not
    # exclude -- test_release_excludes.lua fails on it, rightly, because a
    # release built from that tree would ship it.
    before = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec = importlib.util.spec_from_file_location("run_tests_mod", HERE.parent / "run_tests.py")
        mod = importlib.util.module_from_spec(spec)
        sys.modules["run_tests_mod"] = mod
        spec.loader.exec_module(mod)
    finally:
        sys.dont_write_bytecode = before
    return mod


rt = _load_module()


def test_a_dev_test_is_shown_from_the_repo_root():
    t = rt.DEV_DIR / "usr" / "lib" / "tests" / "test_x.lua"
    assert rt.display_path(t, rt.DEV_DIR) == "usr/lib/tests/test_x.lua"


def test_a_build_test_is_shown_from_the_repo_root():
    t = rt.DEV_DIR / "build" / "test_sync_emulator.py"
    assert rt.display_path(t, rt.DEV_DIR) == "build/test_sync_emulator.py"


def test_a_nested_extras_test_is_inside_the_checkout():
    # The published dev branch: TOS-Extras lives inside the repo root.
    extras = rt.DEV_DIR / "TOS-Extras"
    t = extras / "modules" / "snake" / "test_snake.lua"
    assert rt.display_path(t, extras) == "TOS-Extras/modules/snake/test_snake.lua"


def test_a_sibling_extras_test_is_beside_the_checkout():
    # The maintainer's monorepo: TOS-Extras is a sibling of TOS-Dev.
    extras = rt.DEV_DIR.parent / "TOS-Extras"
    t = extras / "modules" / "snake" / "test_snake.lua"
    assert rt.display_path(t, extras) == "../TOS-Extras/modules/snake/test_snake.lua"
