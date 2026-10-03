"""MANUAL.md's section numbers are unique, and every citation of one resolves.

WHY THIS EXISTS. The manual promises stable `Chapter.Section` numbers so a
`§7.3` in a man page or a refusal message always lands in the same place.
Nothing checked it, and an outside review (2026-10-03) found it broken: two
sections numbered 7.4, plus 7.45, 7.5a, 4.1a-4.1e (out of order) and 6.1a.
They were renumbered once; this keeps them that way:

  * every numbered heading (### N.M, #### N.M.K) is unique;
  * no lettered numbers (7.5a) come back, and no fractional ones (7.45):
    sections within a chapter count up 1, 2, 3 ... with no gaps;
  * every `§N.M` in the manual itself, and every `MANUAL N.M` / `MANUAL §N.M`
    citation in the README, CONTRIBUTING, the man pages, the add-on docs and
    the Lua source, names a section that exists.

CHANGELOG and ROADMAP are not checked: they quote numbers as they were at
the time, which is history, not a link.

Run: pytest TOS-Dev/build/test_manual_refs.py
"""

from __future__ import annotations

import re
from pathlib import Path

DEV = Path(__file__).resolve().parent.parent
# TOS-Extras is a sibling in the monorepo and nested on the published branch.
EXTRAS = DEV.parent / "TOS-Extras" if (DEV.parent / "TOS-Extras").is_dir() else DEV / "TOS-Extras"
MANUAL = (DEV / "MANUAL.md").read_text(encoding="utf-8")

HEADING = re.compile(r"^(#{2,4}) (\d+)(?:\.(\d+))?(?:\.(\d+))?([a-z]?)\b", re.M)
# A citation keeps a trailing letter, so a stale "7.5a" cannot pass as "7.5".
NUMBER = r"(\d+(?:\.\d+){0,2}[a-z]?)"


def sections() -> list[tuple[str, int, int | None, int | None, str]]:
    out = []
    for m in HEADING.finditer(MANUAL):
        hashes, ch, sec, sub, letter = m.groups()
        out.append((hashes, int(ch), int(sec) if sec else None, int(sub) if sub else None, letter))
    return out


def numbers() -> set[str]:
    have = set()
    for _, ch, sec, sub, letter in sections():
        if sec is None:
            have.add(str(ch))
        elif sub is None:
            have.add(f"{ch}.{sec}{letter}")
        else:
            have.add(f"{ch}.{sec}.{sub}{letter}")
    return have


def test_every_section_number_is_unique():
    seen, dups = set(), []
    for _, ch, sec, sub, letter in sections():
        if sec is None:
            continue
        key = (ch, sec, sub, letter)
        if key in seen:
            dups.append(".".join(str(x) for x in key if x not in (None, "")))
        seen.add(key)
    assert not dups, f"duplicate section numbers: {dups}"


def test_no_lettered_sections():
    bad = [m.group(0) for m in re.finditer(r"^#{3,4} \d+\.\d+[a-z]\b.*$", MANUAL, re.M)]
    assert not bad, bad


def test_sections_count_up_without_gaps():
    by_chapter: dict[int, list[int]] = {}
    for hashes, ch, sec, sub, _ in sections():
        if sec is not None and sub is None and hashes == "###":
            by_chapter.setdefault(ch, []).append(sec)
    gaps = {ch: secs for ch, secs in by_chapter.items() if secs != list(range(1, len(secs) + 1))}
    assert not gaps, f"chapters whose sections do not run 1, 2, 3...: {gaps}"


def _cited_in_manual() -> list[str]:
    return re.findall(r"§" + NUMBER, MANUAL)


def _cited_elsewhere() -> list[tuple[str, str]]:
    files = [DEV / "README.md", DEV / "CONTRIBUTING.md"]
    files += sorted((DEV / "usr" / "man").glob("*.man"))
    files += sorted(DEV.joinpath("tos").rglob("*.lua"))
    files += sorted(DEV.joinpath("usr", "lib", "tests").glob("*.lua"))
    if EXTRAS.is_dir():
        files += [p for p in EXTRAS.rglob("*.md") if "dist" not in p.parts]
    out = []
    for p in files:
        text = p.read_text(encoding="utf-8", errors="replace")
        for m in re.finditer(r"MANUAL(?:\.md)?\s*\(?(?:§|Chapter\s+)?\s*" + NUMBER, text):
            out.append((str(p.relative_to(DEV.parent)), m.group(1)))
    return out


def test_every_section_the_manual_cites_exists():
    have = numbers()
    missing = sorted({n for n in _cited_in_manual() if n not in have})
    assert not missing, f"MANUAL cites sections it does not have: {missing}"


def test_every_manual_citation_elsewhere_exists():
    have = numbers()
    missing = sorted({(f, n) for f, n in _cited_elsewhere() if n not in have})
    assert not missing, f"citations of MANUAL sections that do not exist: {missing}"


def test_the_checks_see_real_citations():
    # Guard against a regex that silently matches nothing.
    assert len(_cited_in_manual()) > 10
    assert any(n == "7.3" for _, n in _cited_elsewhere())
