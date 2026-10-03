"""docs/API.md is current, and every tier mark agrees with its gate.

The reference is generated (build/make_apiref.py) so it cannot silently
disagree with the kernel; this is what makes that true. And the `@tier`
marks are only worth writing if something holds them to the code: a public
function whose body calls an admin gate must carry `--- @tier admin`, and a
function that carries one must call a gate.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import make_apiref  # noqa: E402


def test_tier_marks_agree_with_gates():
    assert make_apiref.disagreements() == []


def test_api_reference_is_current():
    current = make_apiref.OUT.read_text(encoding="utf-8").replace("\r\n", "\n")
    assert current == make_apiref.render(), (
        "docs/API.md is stale: run  python build/make_apiref.py")


def test_the_check_catches_both_directions(tmp_path, monkeypatch):
    kernel = tmp_path / "tos" / "kernel"
    kernel.mkdir(parents=True)
    (kernel / "m.lua").write_text("\n".join([
        "local m = {}",
        "local function adminGate(opts) return true end",
        "--- Marked and gated: fine.",
        "--- @tier admin",
        "function m.good(opts)",
        "  local g = adminGate(opts)",
        "end",
        "--- Gated, not marked.",
        "function m.unmarked(opts)",
        "  local g = adminGate(opts)",
        "end",
        "--- @tier admin",
        "function m.ungated(opts)",
        "  return 1",
        "end",
        "function m.oneLiner(p) return p end",
        "return m",
    ]), encoding="utf-8")
    monkeypatch.setattr(make_apiref, "ROOT", tmp_path)
    monkeypatch.setattr(make_apiref, "KERNEL", kernel)
    bad = make_apiref.disagreements()
    assert len(bad) == 2, bad
    assert any("m.unmarked calls adminGate()" in b for b in bad)
    assert any("m.ungated is marked @tier admin but calls none" in b for b in bad)
    text = make_apiref.render()
    assert "`m.good(opts)` — **admin**" in text
    assert "`m.oneLiner(p)`" in text
    assert "Marked and gated: fine." in text
