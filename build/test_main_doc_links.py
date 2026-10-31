"""The docs that ship on `main` link only to what `main` carries.

WHY THIS EXISTS. README, MANUAL and friends are copied onto `main`, the
release branch, which has no docs/ and no TOS-Extras/. Both READMEs linked
into those folders with relative paths, which work on `dev`, where people
usually land, and 404 on `main`, where the install URL sends them. Every
link check here ran on the source tree, which has those folders, so none
could see it. A link that has to work on both branches names `dev` in full.

Run: pytest TOS-Dev/build/test_main_doc_links.py
"""

from __future__ import annotations

import re
from pathlib import Path

DEV = Path(__file__).resolve().parent.parent
# What publish.ps1 copies onto main beside the release tree.
MAIN_DOCS = ("README.md", "CHANGELOG.md", "MANUAL.md", "CONTRIBUTING.md", "ROADMAP.md", "SECURITY.md")
# Folders that exist on dev and not on main.
DEV_ONLY = ("docs/", "TOS-Extras/", "build/", "usr/lib/tests/")
LINK = re.compile(r"\]\(([^)\s]+)\)")


def relative_links(text: str) -> list[str]:
    return [m for m in LINK.findall(text) if not re.match(r"[a-z]+:", m) and not m.startswith("#")]


def test_no_doc_on_main_links_into_a_dev_only_folder():
    bad = []
    for name in MAIN_DOCS:
        for link in relative_links((DEV / name).read_text(encoding="utf-8")):
            if link.startswith(DEV_ONLY):
                bad.append(f"{name}: {link}")
    assert bad == []


def test_the_check_sees_a_relative_link():
    assert relative_links("see [a](docs/API.md), [b](#anchor) and [c](https://x.y/z)") == ["docs/API.md"]
