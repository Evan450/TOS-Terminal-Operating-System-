"""No add-on reads fs.writeFile through a two-value pcall.

fs.writeFile refuses by RETURNING false and a reason, not by throwing. So
`local ok, err = pcall(fs.writeFile, ...)` sees success on a refused write,
and its second value is only that false. stock reported thresholds as saved
for its whole life that way, and write did the same with documents. Three
values are the shape that can see a refusal: ok, done, why.

A check on the shape rather than on each add-on, because the next add-on will
copy the nearest one that looks right.
"""
import re
from pathlib import Path

import pytest

EXTRAS = Path(__file__).resolve().parent.parent.parent / "TOS-Extras"
TWO_VALUES = re.compile(r"local\s+\w+\s*,\s*\w+\s*=\s*pcall\s*\(\s*fs\s*\.\s*(writeFile|appendFile)\b")


def sources():
    for sub in ("modules", "web", "cluster", "rbmk", "robot", "pane-ui"):
        for path in sorted((EXTRAS / sub).rglob("*.lua")):
            if "dist" in path.parts or path.name.startswith("test_"):
                continue
            yield path


@pytest.mark.skipif(not EXTRAS.is_dir(), reason="TOS-Extras is not beside this tree")
def test_a_refused_write_can_be_seen():
    found = []
    for path in sources():
        text = path.read_text(encoding="utf-8", errors="replace")
        for m in TWO_VALUES.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            found.append(f"{path.relative_to(EXTRAS)}:{line}")
    assert not found, "read fs.writeFile with three values, ok, done, why: " + ", ".join(found)


def test_the_shape_is_what_this_looks_for():
    assert TWO_VALUES.search("local ok, err = pcall(fs.writeFile, p, d)")
    assert TWO_VALUES.search("  local okW, e = pcall( fs.appendFile, p, d)")
    assert not TWO_VALUES.search("local ok, done, why = pcall(fs.writeFile, p, d)")
    assert not TWO_VALUES.search("pcall(fs.writeFile, p, d)")
