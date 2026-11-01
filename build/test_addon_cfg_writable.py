"""Every add-on config in /etc can really be written.

/etc is a protected path: closed above the permission model, even to root,
except for the files on securefs's WRITE_PROTECTED_EXEMPT list. An add-on's
config missing from it cannot be changed by the admin it is meant for. stock's
thresholds were refused that way on every machine for as long as it shipped,
and the rbmk README told admins to edit a file they could not.

This reads the real list, not a fake of it: two fakes in a row let a path
through that a real machine refused.
"""
import re
from pathlib import Path

import pytest

DEV = Path(__file__).resolve().parent.parent
EXTRAS = DEV.parent / "TOS-Extras"
CFG = re.compile(r"/etc/[\w.-]+\.cfg\b")


def exempt() -> set:
    src = (DEV / "tos" / "kernel" / "securefs.lua").read_text(encoding="utf-8")
    body = src[src.index("local WRITE_PROTECTED_EXEMPT = {"):]
    body = body[:body.index("\n}\n")]
    return set(re.findall(r'\["(/[^"]+)"\]\s*=\s*true', body))


def named_by_addons() -> dict:
    """Every /etc/*.cfg the pack ships as a file, or names in its code or docs."""
    found = {}
    for sub in ("modules", "web", "cluster", "rbmk"):
        for path in sorted((EXTRAS / sub).rglob("*")):
            if not path.is_file() or "dist" in path.parts or path.name.startswith("test_"):
                continue
            # A design for something not built names files that do not exist.
            if path.name.endswith("-draft.md") or path.name == "Plan.md":
                continue
            rel = path.relative_to(EXTRAS).as_posix()
            if path.suffix == ".cfg" and "/etc/" in rel:
                found.setdefault("/etc/" + path.name, rel)
            if path.suffix in (".lua", ".md"):
                for m in CFG.finditer(path.read_text(encoding="utf-8", errors="replace")):
                    found.setdefault(m.group(0), rel)
    return found


# Named by add-ons and belonging to the base, each with its own reason to be
# closed: these are not settings of the add-on's.
NOT_THEIRS = {
    "/etc/pkg-repos.cfg",     # repos are changed through `pkg repo`
    "/etc/rc.cfg",            # OpenOS's, on the machine the cluster installer runs on
    "/etc/cluster-worker.cfg",  # a worker runs OpenOS, where this guard does not exist
}


@pytest.mark.skipif(not EXTRAS.is_dir(), reason="TOS-Extras is not beside this tree")
def test_every_addon_config_can_be_written():
    allowed = exempt()
    missing = {p: where for p, where in named_by_addons().items()
               if p not in allowed and p not in NOT_THEIRS}
    assert not missing, f"not on securefs's WRITE_PROTECTED_EXEMPT list: {missing}"


def test_the_list_is_read_for_real():
    allowed = exempt()
    assert "/etc/users.dat" in allowed
    assert "/etc/stock-watch.cfg" in allowed
