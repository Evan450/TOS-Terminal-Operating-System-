"""Tests for sync-emulator.py's disk-classification and mirroring logic.

WHY THIS EXISTS. sync-emulator.py is the only thing standing between "the
on-box battery ran against this round's code" and "it ran against whatever
was on the disk last" (see its own docstring: the round that prompted it
found the boot disk eleven files behind and the floppy one revision behind).
That script had zero test coverage before this file — a Python script in a
repo whose test culture is otherwise ~180 Lua files deep. The two functions
that matter most:

  classify()  finds the boot disk and the self-test floppy BY CONTENT, never
              by a hard-coded UUID. Get this wrong and the script mirrors
              TOS-Release into the wrong directory, or silently mirrors
              nothing because it found neither.
  mirror()    is a pruning recursive copy. Get the prune logic backwards and
              it either leaves stale files behind (the exact bug this script
              was written to stop) or deletes something it does not own.

sync-emulator.py has a hyphen in its filename, so it cannot be imported with
a normal `import` statement — this loads it by file path instead, which
also means no conftest.py or package layout is needed to run this from
either `pytest TOS-Dev/build/` or a bare `pytest` at the repo root.

Run: pytest TOS-Dev/build/test_sync_emulator.py
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent


def _load_module():
    spec = importlib.util.spec_from_file_location("sync_emulator", HERE / "sync-emulator.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["sync_emulator"] = mod
    spec.loader.exec_module(mod)
    return mod


sync_emulator = _load_module()


@pytest.fixture
def workspace(tmp_path):
    return tmp_path


# ============================================================
# classify() — find the boot disk and the floppy BY CONTENT
# ============================================================

def _touch(path: Path, content: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


class TestClassify:
    def test_finds_the_boot_disk_by_init_and_tos(self, workspace):
        boot = workspace / "b174c1d3"
        _touch(boot / "init.lua")
        (boot / "tos").mkdir()

        found_boot, found_floppy = sync_emulator.classify(workspace)

        assert found_boot == boot
        assert found_floppy is None

    def test_finds_the_floppy_by_selftest_on_at_its_root(self, workspace):
        floppy = workspace / "e1344d2b"
        _touch(floppy / "selftest.on")

        _, found_floppy = sync_emulator.classify(workspace)

        assert found_floppy == floppy

    def test_finds_the_floppy_by_numbered_check_files_alone(self, workspace):
        # A floppy that has the checks but has not been armed yet (no
        # selftest.on) must still be recognised, or the script cannot
        # report "armed: false" to tell the operator to arm it.
        floppy = workspace / "a5b21b10"
        _touch(floppy / "10-boot.lua")
        _touch(floppy / "20-display.lua")

        _, found_floppy = sync_emulator.classify(workspace)

        assert found_floppy == floppy

    def test_does_not_mistake_an_unrelated_data_disk_for_the_floppy(self, workspace):
        # The Optional Utilities disks (a5b21b10 in a real workspace) carry
        # ordinary package trees, not NN-name.lua checks — classify() must
        # not glob-match something like "20-questions.lua" style names that
        # merely happen to start with digits inside a subdirectory, and
        # must not treat every directory as a candidate floppy.
        data_disk = workspace / "optional-utilities"
        _touch(data_disk / "printer" / "package.lua")
        _touch(data_disk / "calc" / "package.lua")

        _, found_floppy = sync_emulator.classify(workspace)

        assert found_floppy is None

    def test_finds_both_at_once_in_a_real_looking_workspace(self, workspace):
        boot = workspace / "b174c1d3"
        _touch(boot / "init.lua")
        (boot / "tos").mkdir()

        floppy = workspace / "e1344d2b"
        _touch(floppy / "selftest.on", "shutdown=true\n")
        _touch(floppy / "10-boot.lua")

        found_boot, found_floppy = sync_emulator.classify(workspace)

        assert found_boot == boot
        assert found_floppy == floppy

    def test_ignores_plain_files_at_the_workspace_root(self, workspace):
        (workspace / "workspace.nbt").write_text("")
        (workspace / "workspace.nbt.bak").write_text("")

        found_boot, found_floppy = sync_emulator.classify(workspace)

        assert found_boot is None
        assert found_floppy is None

    def test_no_boot_disk_present(self, workspace):
        # An empty or not-yet-populated workspace: must report absence
        # rather than raising, since main() is what turns this into the
        # user-facing "no directory in the workspace looks like a TOS boot
        # disk" error.
        found_boot, found_floppy = sync_emulator.classify(workspace)
        assert found_boot is None
        assert found_floppy is None


# ============================================================
# mirror() — pruning recursive copy
# ============================================================

class TestMirror:
    def test_copies_new_files(self, workspace):
        src, dst = workspace / "src", workspace / "dst"
        _touch(src / "a.lua", "A")
        log = []

        sync_emulator.mirror(src, dst, dry=False, log=log)

        assert (dst / "a.lua").read_text() == "A"
        assert any("add" in line for line in log)

    def test_updates_changed_files(self, workspace):
        src, dst = workspace / "src", workspace / "dst"
        _touch(src / "a.lua", "NEW")
        _touch(dst / "a.lua", "OLD")
        log = []

        sync_emulator.mirror(src, dst, dry=False, log=log)

        assert (dst / "a.lua").read_text() == "NEW"
        assert any("update" in line for line in log)

    def test_leaves_identical_files_untouched(self, workspace):
        src, dst = workspace / "src", workspace / "dst"
        _touch(src / "a.lua", "SAME")
        _touch(dst / "a.lua", "SAME")
        before = (dst / "a.lua").stat().st_mtime_ns
        log = []

        sync_emulator.mirror(src, dst, dry=False, log=log)

        assert (dst / "a.lua").stat().st_mtime_ns == before
        assert log == []

    def test_prune_removes_a_file_src_no_longer_has(self, workspace):
        # This is the exact bug that motivated the script: a renamed
        # module lingering on the boot disk and making a round lie about
        # which code it tested.
        src, dst = workspace / "src", workspace / "dst"
        _touch(src / "keep.lua", "K")
        _touch(dst / "keep.lua", "K")
        _touch(dst / "stale.lua", "old module, renamed away in src")
        log = []

        sync_emulator.mirror(src, dst, dry=False, log=log, prune=True)

        assert not (dst / "stale.lua").exists()
        assert (dst / "keep.lua").exists()
        assert any("remove" in line for line in log)

    def test_no_prune_keeps_extra_files(self, workspace):
        # COPY_DIRS (usr/bin, etc/rc.d, ...) call mirror with prune=False
        # specifically because they carry operator state mixed in with
        # ours — an operator's own script in usr/bin must survive.
        src, dst = workspace / "src", workspace / "dst"
        _touch(src / "ours.lua", "O")
        _touch(dst / "theirs.lua", "the operator's own file")
        log = []

        sync_emulator.mirror(src, dst, dry=False, log=log, prune=False)

        assert (dst / "theirs.lua").exists()
        assert (dst / "ours.lua").exists()

    def test_dry_run_changes_nothing_on_disk(self, workspace):
        src, dst = workspace / "src", workspace / "dst"
        _touch(src / "a.lua", "A")
        _touch(dst / "stale.lua", "old")
        log = []

        sync_emulator.mirror(src, dst, dry=True, log=log)

        # The log still reports what WOULD happen...
        assert any("add" in line for line in log)
        assert any("remove" in line for line in log)
        # ...but the filesystem itself is untouched.
        assert not (dst / "a.lua").exists()
        assert (dst / "stale.lua").exists()

    def test_recurses_into_subdirectories(self, workspace):
        src, dst = workspace / "src", workspace / "dst"
        _touch(src / "kernel" / "pkg.lua", "P")
        _touch(dst / "kernel" / "stale_module.lua", "gone in src")
        log = []

        sync_emulator.mirror(src, dst, dry=False, log=log, prune=True)

        assert (dst / "kernel" / "pkg.lua").read_text() == "P"
        assert not (dst / "kernel" / "stale_module.lua").exists()

    def test_missing_source_is_a_silent_noop(self, workspace):
        # COPY_DIRS/MIRROR_DIRS are iterated unconditionally in main(); a
        # release tree that happens not to have e.g. usr/lang must not
        # raise.
        src, dst = workspace / "does-not-exist", workspace / "dst"
        log = []

        sync_emulator.mirror(src, dst, dry=False, log=log)

        assert log == []
        assert not dst.exists()


# ============================================================
# find_workspace() — explicit path and env var resolution
# ============================================================

class TestFindWorkspace:
    def test_explicit_path_wins(self, workspace, monkeypatch):
        monkeypatch.delenv("OCELOT_EMULATOR", raising=False)
        found = sync_emulator.find_workspace(str(workspace))
        assert found == workspace

    def test_explicit_nonexistent_path_is_rejected(self, monkeypatch):
        monkeypatch.delenv("OCELOT_EMULATOR", raising=False)
        found = sync_emulator.find_workspace(str(Path(tempfile.gettempdir()) / "does-not-exist-xyz"))
        assert found is None

    def test_env_var_used_when_no_explicit_path(self, workspace, monkeypatch):
        emulator_dir = workspace / "Emulator"
        emulator_dir.mkdir()
        monkeypatch.setenv("OCELOT_EMULATOR", str(workspace))

        found = sync_emulator.find_workspace(None)

        assert found == emulator_dir

    def test_env_var_pointing_straight_at_the_emulator_dir(self, workspace, monkeypatch):
        # If OCELOT_EMULATOR is set to the Emulator/ folder itself rather
        # than its parent, there is no nested Emulator/ to descend into —
        # the env var's own target must be used as-is.
        monkeypatch.setenv("OCELOT_EMULATOR", str(workspace))

        found = sync_emulator.find_workspace(None)

        assert found == workspace
