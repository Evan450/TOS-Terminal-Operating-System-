"""Every GitHub workflow the publisher ships parses, and none is risky.

The workflows are generated onto the published `dev` branch by publish.ps1
from Working_Dir/tos-repo-push/github/, so a mistake in one is invisible
until it is live: the first draft of the triage workflow had an unquoted
colon that made the whole file invalid YAML, and GitHub reports that as a
workflow that silently never runs. This lints them all the way the project
lints its own generated files.

The sources are not on the published branch, so the test skips there.

Run: pytest TOS-Dev/build/test_github_workflows.py
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

SRC = Path(__file__).resolve().parents[3] / "Working_Dir" / "tos-repo-push" / "github"
pytestmark = pytest.mark.skipif(not SRC.exists(), reason="publisher sources are not on the published branch")

WORKFLOWS = sorted((SRC / "workflows").glob("*.yml")) if SRC.exists() else []


def load(path):
    return yaml.safe_load(path.read_text("utf-8"))


def triggers(wf):
    return wf.get("on", wf.get(True))  # YAML 1.1 reads a bare `on` as True


def test_there_are_workflows():
    assert {p.name for p in WORKFLOWS} >= {"ci.yml", "issue-triage.yml"}


@pytest.mark.parametrize("path", WORKFLOWS, ids=lambda p: p.name)
def test_workflow_is_safe(path):
    wf = load(path)
    on = triggers(wf)
    # pull_request_target runs with secrets and a write token against code a
    # stranger controls; nothing here needs it.
    assert "pull_request_target" not in on
    assert "permissions" in wf, "set permissions explicitly, do not inherit the repo default"
    assert wf["permissions"].get("contents") != "write"
    for job in wf["jobs"].values():
        assert "timeout-minutes" in job or "uses" in job
        for step in job["steps"]:
            run = step.get("run", "")
            assert not re.search(r"\$\{\{\s*github\.(event|head_ref)", run), (
                "untrusted event text must reach scripts through env or the payload file, not run:\n" + run)
            if "uses" in step:
                assert re.search(r"@(v\d+(\.\d+)*|[0-9a-f]{40})$", step["uses"]), (
                    "pin actions to a version tag or SHA: " + step["uses"])


def test_ci_runs_the_suite_and_guards_the_base_branch():
    wf = load(SRC / "workflows" / "ci.yml")
    steps = " ".join(s.get("run", "") for s in wf["jobs"]["tests"]["steps"])
    assert "python3 run_tests.py" in steps
    assert "lua5.3" in steps, "tests use Lua 5.3 syntax; do not float to whatever `lua` is"
    assert wf["jobs"]["base-branch"]["if"].count("'main'") == 1
    on = triggers(wf)
    assert on["push"]["branches"] == ["dev"]


def test_dependabot_watches_the_actions_the_workflows_use():
    cfg = load(SRC / "dependabot.yml")
    assert {u["package-ecosystem"] for u in cfg["updates"]} == {"github-actions"}


def test_codeowners_names_someone():
    lines = [l for l in (SRC / "CODEOWNERS").read_text("utf-8").splitlines() if l.strip() and not l.startswith("#")]
    assert lines and all("@" in l for l in lines)
