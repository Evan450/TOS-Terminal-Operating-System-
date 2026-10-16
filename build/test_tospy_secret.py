"""The signing passphrase prompt shows a * per character.

WHY THIS EXISTS. `tos.py pack --sign` asked for the passphrase through
getpass, which echoes nothing: after signing the pack the operator could
not tell whether the passphrase had been typed at all, or whether a paste
had landed. read_masked echoes one * per character and takes them back on
Backspace. These drive it with scripted keys, no terminal needed.

Run: pytest TOS-Dev/build/test_tospy_secret.py
"""

from __future__ import annotations

import importlib.util
import io
import sys
from pathlib import Path

import pytest

DEV = Path(__file__).resolve().parent.parent


def _tos():
    spec = importlib.util.spec_from_file_location("tos_cli", DEV / "tos.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["tos_cli"] = mod
    spec.loader.exec_module(mod)
    return mod


def _run(keys: str):
    it = iter(keys)
    out = io.StringIO()
    # "" once the keys run out, as stdin.read(1) gives at end of input.
    got = _tos().read_masked("Pass: ", lambda: next(it, ""), out)
    return got, out.getvalue()


def test_each_character_shows_as_a_star():
    got, shown = _run("hunter2\r")
    assert got == "hunter2"
    assert shown == "Pass: *******\n"


def test_the_passphrase_itself_never_reaches_the_screen():
    _, shown = _run("s3cret phrase\r")
    assert "s3cret" not in shown and "phrase" not in shown


def test_backspace_takes_a_character_and_its_star_back():
    got, shown = _run("abX\bc\r")
    assert got == "abc"
    assert shown == "Pass: ***\b \b*\n"


def test_backspace_on_an_empty_line_does_nothing():
    got, shown = _run("\b\x7fab\r")
    assert got == "ab"
    assert shown == "Pass: **\n"


def test_a_windows_arrow_key_is_ignored_with_its_second_code():
    # An arrow arrives as "\xe0" then a letter ("H" for up); neither is input.
    got, _ = _run("a\xe0Hb\x00;c\r")
    assert got == "abc"


def test_other_control_keys_are_not_typed():
    got, _ = _run("a\tb\x1bc\r")
    assert got == "abc"


def test_ctrl_c_stops():
    with pytest.raises(KeyboardInterrupt):
        _run("ab\x03")


def test_end_of_input_on_an_empty_line_is_eof():
    with pytest.raises(EOFError):
        _run("")


def test_not_a_terminal_falls_back_to_getpass(monkeypatch):
    tos = _tos()
    monkeypatch.setattr(sys, "stdin", io.StringIO("piped\n"))
    monkeypatch.setattr(tos.getpass, "getpass", lambda prompt: "from-getpass")
    assert tos.ask_secret("Pass: ") == "from-getpass"
