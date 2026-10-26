"""`tos.py check` must fail when one of its Lua checks fails.

WHY THIS EXISTS. cmd_check() is the command to run before publishing, and
it keeps the worst EXIT CODE of the checks it runs. Three of its Lua checks
-- the release digests, the release excludes and the add-on repo index --
reported failure with `print("*** TESTS FAILED ***"); return false`, and the
stand-alone lua interpreter ignores a main chunk's return value: it exits 0
unless the chunk errors or calls os.exit. So none of the three could ever
fail the gate, and a run that printed "1 failed / *** TESTS FAILED ***"
still ended "OK". Found by the 2026-09-12 audit, whose pin for it lived on
an unmerged branch; still true on f4ab6d4. run_tests.py was never affected,
because it reads the markers rather than the exit code.

The checks now os.exit(1) on every failure path, as test_manifest_completeness
already did. These tests copy the REAL check files into a temp tree, feed
each one input it must reject, and require a non-zero exit that came from
the check's own verdict (its Results line and failure marker), not from a
crash. Then cmd_check itself is run over such a tree.

Run: pytest TOS-Dev/build/test_tos_py_check.py
"""

from __future__ import annotations

import hashlib
import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

DEV = Path(__file__).resolve().parents[1]
LUA = shutil.which("lua")

pytestmark = pytest.mark.skipif(LUA is None, reason="needs a lua interpreter on PATH")

PASSING = ('print("Results: 1 passed, 0 failed")\n'
           'print("All tests passed.")\n')


def load_tos():
    # No __pycache__ at the TOS-Dev root: the release build would ship it.
    old, sys.dont_write_bytecode = sys.dont_write_bytecode, True
    try:
        spec = importlib.util.spec_from_file_location("tos_cli_check", DEV / "tos.py")
        mod = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = mod
        spec.loader.exec_module(mod)
    finally:
        sys.dont_write_bytecode = old
    return mod


tos = load_tos()


def put(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))   # LF only: the digest check scans for CR


def copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)


def run_lua(script: str, cwd: Path) -> tuple[int, str]:
    proc = subprocess.run([LUA, script], cwd=str(cwd), capture_output=True,
                          text=True, errors="replace", timeout=60)
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


# ── Trees that make each real check fail ────────────────────────────────
# Each builder lays out a temp tree and returns (cwd, script, the FAIL line
# the check must print). Every one is a check the gate exists to catch.

DIGESTS = "usr/lib/tests/test_manifest_digests.lua"
EXCLUDES = "usr/lib/tests/test_release_excludes.lua"
INDEX = "build/test_repo_index.lua"


def digests_tree(tmp: Path, manifest: str, body: bytes = b"print('shipped')\n") -> Path:
    dev = tmp / "TOS-Dev"
    copy(DEV / DIGESTS, dev / DIGESTS)
    copy(DEV / "tos/kernel/sha256.lua", dev / "tos/kernel/sha256.lua")
    rel = tmp / "TOS-Release"
    (rel / "a.lua").parent.mkdir(parents=True, exist_ok=True)
    (rel / "a.lua").write_bytes(body)
    put(rel / "tos/system_manifest.lua", manifest)
    return dev


def manifest_with(hash_hex: str) -> str:
    return ("return {\n"
            f'  {{ path = "/a.lua", hash = "{hash_hex}" }},\n'
            '  { path = "/tos/system_manifest.lua" },\n'
            "}\n")


def digest_mismatch(tmp: Path):
    wrong = hashlib.sha256(b"not what shipped\n").hexdigest()
    return digests_tree(tmp, manifest_with(wrong)), DIGESTS, "FAIL: every digest matches the shipped bytes"


def digest_unparseable(tmp: Path):
    return digests_tree(tmp, "return {\n"), DIGESTS, "FAIL: the Release manifest parses with real Lua"


def digest_not_a_table(tmp: Path):
    return digests_tree(tmp, "return 5\n"), DIGESTS, "FAIL: ...and returns a table"


def excludes_tree(tmp: Path, stray: bool) -> Path:
    dev = tmp / "TOS-Dev"
    copy(DEV / EXCLUDES, dev / EXCLUDES)
    for script in ("build/build-release.sh", "build/build-release.cmd"):
        copy(DEV / script, dev / script)
    # What main ships, so the "saw the shipped entries" sanity check holds,
    # and one top-level dev script for the .py/.sh rule to find.
    for name in ("bios.lua", "bootstrap.lua", "init.lua", "install.lua", "LICENSE.txt", "run_tests.py"):
        put(dev / name, "\n")
    for name in ("tos", "etc"):
        (dev / name).mkdir()
    if stray:
        put(dev / "stray.txt", "a new top-level file neither build script excludes\n")
    return dev


def excludes_leak(tmp: Path):
    return (excludes_tree(tmp, stray=True), EXCLUDES,
            "FAIL: every top-level entry ships or is excluded by BOTH build scripts")


def index_tree(tmp: Path, programs_cfg: str, with_serialize: bool = True) -> Path:
    extras = tmp / "TOS-Extras"
    copy(tos.EXTRAS / INDEX, extras / INDEX)
    if with_serialize:
        for mod in ("serialize", "sha256"):
            copy(DEV / f"tos/kernel/{mod}.lua", tmp / f"TOS-Dev/tos/kernel/{mod}.lua")
    put(extras / "dist/optional-utilities/programs.cfg", programs_cfg)
    return extras


def index_no_serialize(tmp: Path):
    return (index_tree(tmp, "return {}\n", with_serialize=False), INDEX,
            "FAIL: kernel.serialize loads from the sibling TOS-Dev tree")


def index_not_a_table(tmp: Path):
    return (index_tree(tmp, 'return "not an index"\n'), INDEX,
            "FAIL: the real decoder parses programs.cfg")


def index_advertises_a_ghost(tmp: Path):
    cfg = 'return {\n  ["ghost"] = { ["files"] = { ["ghost/package.lua"] = "/usr/x" } },\n}\n'
    return (index_tree(tmp, cfg), INDEX,
            "FAIL: every advertised file exists in the published tree")


FAILING = [digest_mismatch, digest_unparseable, digest_not_a_table,
           excludes_leak, index_no_serialize, index_not_a_table, index_advertises_a_ghost]


@pytest.mark.parametrize("build", FAILING, ids=lambda f: f.__name__)
def test_a_failing_check_exits_nonzero(tmp_path, build):
    cwd, script, fail_line = build(tmp_path)
    rc, out = run_lua(script, cwd)
    # The check reached its OWN verdict -- a crash would also exit 1, and
    # would prove nothing about the failure path.
    assert fail_line in out, out
    assert "Results:" in out and "*** TESTS FAILED ***" in out, out
    assert rc != 0, f"the check printed its failure and exited {rc}:\n{out}"


# The same trees with the defect taken out pass, so the failures above are
# the defect and not a broken fixture.
def test_the_digest_tree_passes_when_the_digest_is_right(tmp_path):
    right = hashlib.sha256(b"print('shipped')\n").hexdigest()
    cwd = digests_tree(tmp_path, manifest_with(right))
    rc, out = run_lua(DIGESTS, cwd)
    assert rc == 0 and "All tests passed." in out, out


def test_the_excludes_tree_passes_without_the_stray_file(tmp_path):
    cwd = excludes_tree(tmp_path, stray=False)
    rc, out = run_lua(EXCLUDES, cwd)
    assert rc == 0 and "All tests passed." in out, out


# ── cmd_check over those trees ──────────────────────────────────────────

def check_tree(tmp: Path, failing):
    """A DEV/EXTRAS pair where `failing` is real and every other check passes."""
    dev = tmp / "TOS-Dev"
    extras = tmp / "TOS-Extras"
    if failing is not None:
        failing(tmp)
    for rel in (DIGESTS, EXCLUDES, "usr/lib/tests/test_manifest_completeness.lua"):
        if not (dev / rel).is_file():
            put(dev / rel, PASSING)
    return dev, extras


def run_cmd_check(monkeypatch, capfd, dev: Path, extras: Path) -> tuple[int, str]:
    monkeypatch.setattr(tos, "DEV", dev)
    monkeypatch.setattr(tos, "EXTRAS", extras)
    rc = tos.cmd_check(None)
    return rc, capfd.readouterr().out


@pytest.mark.parametrize("failing", [digest_mismatch, excludes_leak, index_not_a_table],
                         ids=lambda f: f.__name__)
def test_cmd_check_fails_when_a_lua_check_fails(tmp_path, monkeypatch, capfd, failing):
    dev, extras = check_tree(tmp_path, failing)
    rc, out = run_cmd_check(monkeypatch, capfd, dev, extras)
    assert "*** TESTS FAILED ***" in out, out
    assert rc != 0
    assert out.rstrip().endswith("Some checks failed - see above."), out


def test_cmd_check_is_ok_when_every_check_passes(tmp_path, monkeypatch, capfd):
    dev, extras = check_tree(tmp_path, None)
    rc, out = run_cmd_check(monkeypatch, capfd, dev, extras)
    assert rc == 0
    assert out.rstrip().endswith("OK"), out
