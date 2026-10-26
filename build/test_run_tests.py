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
    # __pycache__/ at the repo ROOT. The release scripts exclude it now
    # (something importing tos.py left one there on 2026-10-17 and the
    # release shipped it), but a dev tree is no place for a stray cache.
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


# ── Whole-body skips (TODO: A TEST THAT SKIPS ITS WHOLE BODY STILL COUNTS
# AS A PASS). The shape below is test_manifest_digests.lua's with no
# TOS-Release beside it, verbatim. The dev branch carries no TOS-Release,
# so GitHub CI counted this as a passing digest check.
WHOLE_SKIP_OUT = (
    "=== Manifest digests ===\n\n"
    "  SKIP: no built TOS-Release (run build/build-release.sh)\n"
    "Results: 0 passed, 0 failed\n"
    "All tests passed.\n"
)


def test_a_test_that_skipped_its_whole_body_is_a_skip():
    assert rt.classify(WHOLE_SKIP_OUT, 0) == "skip"


def test_a_test_that_skipped_some_checks_and_asserted_others_passes():
    out = WHOLE_SKIP_OUT.replace("0 passed", "4 passed")
    assert rt.classify(out, 0) == "pass"


def test_zero_counted_without_a_skip_line_is_still_a_pass():
    # Not a skip unless the test says so; a test with nothing to check and
    # no SKIP line keeps its old reading rather than guessing.
    out = "Results: 0 passed, 0 failed\nAll tests passed.\n"
    assert rt.classify(out, 0) == "pass"


def test_a_whole_body_skip_that_crashed_is_a_failure():
    assert rt.classify(WHOLE_SKIP_OUT, 1) == "fail"


def test_a_skip_that_failed_something_is_a_failure():
    out = "  SKIP: part\n  FAIL: x\nResults: 0 passed, 1 failed\n*** TESTS FAILED ***\n"
    assert rt.classify(out, 1) == "fail"


def test_the_real_digest_check_skips_with_no_release(tmp_path):
    # Drive the real file from a tree with no TOS-Release beside it, so the
    # verdict above is about the shape the check really prints.
    import shutil
    import subprocess
    lua = shutil.which("lua")
    if not lua:
        import pytest
        pytest.skip("lua not on PATH")
    dev = tmp_path / "TOS-Dev"
    (dev / "usr" / "lib" / "tests").mkdir(parents=True)
    src = rt.DEV_DIR / "usr" / "lib" / "tests" / "test_manifest_digests.lua"
    shutil.copy(src, dev / "usr" / "lib" / "tests" / src.name)
    p = subprocess.run([lua, "usr/lib/tests/" + src.name], cwd=dev,
                       capture_output=True, text=True, timeout=60)
    assert rt.classify(p.stdout + p.stderr, p.returncode) == "skip", p.stdout + p.stderr
