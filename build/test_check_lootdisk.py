"""Tests for build/check_lootdisk.py: is the Irradiated Circuits loot disk
today's release?

Builds a scratch TOS-Release and a scratch radbridge jar (a zip with the
mod's assets/radbridge/loot/tos/ layout) and runs the real script over
them: the same files read OK (line endings aside, as the builders
normalise them), a changed, missing or extra file reads as drift, drift is
advisory unless --strict, and no jar is a quiet skip.

Run: pytest TOS-Dev/build/test_check_lootdisk.py
"""

from __future__ import annotations

import subprocess
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_lootdisk.py"
PREFIX = "assets/radbridge/loot/tos/"

RELEASE = {
    "init.lua": b'local _TOS = { build = "abc1234" }\n',
    "tos/system_manifest.lua": b"return {}\n",
    "tos/kernel/x25519.lua": b"-- x25519\n",
}


def make_release(root: Path, files=RELEASE) -> Path:
    rel = root / "TOS-Release"
    for name, data in files.items():
        p = rel / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
    return rel


def make_jar(root: Path, files: dict, name="radbridge-0.6.0.jar") -> Path:
    jar = root / name
    with zipfile.ZipFile(jar, "w") as z:
        z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n")
        for n, data in files.items():
            z.writestr(PREFIX + n, data)
    return jar


def run(*args, env_jar=None):
    import os
    env = dict(os.environ)
    env.pop("TOS_LOOTDISK_JAR", None)
    if env_jar:
        env["TOS_LOOTDISK_JAR"] = str(env_jar)
    p = subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                       capture_output=True, text=True, env=env, timeout=60)
    return p.returncode, p.stdout + p.stderr


def test_the_same_files_read_ok(tmp_path):
    rel = make_release(tmp_path)
    crlf = {k: v.replace(b"\n", b"\r\n") for k, v in RELEASE.items()}
    jar = make_jar(tmp_path, crlf)
    rc, out = run("--jar", jar, "--release", rel)
    assert rc == 0 and "OK: the loot disk is today's release (3 files)" in out, out


def test_drift_is_named_file_by_file(tmp_path):
    rel = make_release(tmp_path)
    stale = dict(RELEASE)
    stale["init.lua"] = b'local _TOS = { build = "0000000" }\n'
    del stale["tos/kernel/x25519.lua"]
    stale["tos/kernel/gone.lua"] = b"-- removed since\n"
    jar = make_jar(tmp_path, stale)
    rc, out = run("--jar", jar, "--release", rel)
    assert rc == 0, out                                   # advisory by default
    assert "DRIFT: 1 file(s) differ, 1 missing from the jar, 1 the release no longer ships" in out, out
    assert "differs  init.lua" in out and "missing  tos/kernel/x25519.lua" in out
    assert "extra    tos/kernel/gone.lua" in out
    assert "loot disk build 0000000, TOS-Release build abc1234" in out, out
    assert "bump its version" in out


def test_strict_fails_on_drift(tmp_path):
    rel = make_release(tmp_path)
    jar = make_jar(tmp_path, {"init.lua": b"old\n"})
    rc, out = run("--jar", jar, "--release", rel, "--strict")
    assert rc == 1, out


def test_the_environment_names_the_jar(tmp_path):
    rel = make_release(tmp_path)
    jar = make_jar(tmp_path, RELEASE)
    rc, out = run("--release", rel, env_jar=jar)
    assert rc == 0 and "radbridge-0.6.0.jar" in out and "OK" in out, out


def test_no_jar_is_a_quiet_skip(tmp_path):
    rel = make_release(tmp_path)
    rc, out = run("--jar", tmp_path / "nope.jar", "--release", rel)
    assert rc == 0 and out.startswith("SKIP: no radbridge jar found"), out


def test_a_jar_without_a_disk_says_so(tmp_path):
    rel = make_release(tmp_path)
    jar = make_jar(tmp_path, {})
    rc, out = run("--jar", jar, "--release", rel)
    assert rc == 0 and "carries no loot disk" in out, out
