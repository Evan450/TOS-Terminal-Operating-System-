"""The issue triage bot validates and labels; it never declines.

build/issue_triage.py is the first pass over every public issue. The things
worth pinning are the ones that fail silently or fail badly:

  * it must have NO way to close, lock, delete or hide an issue (the whole
    point of the design: humans/AI are the fallback, never a rejection);
  * issue text is untrusted, so what it echoes into a comment is neutralized;
  * a security-looking report in public goes to a human, not through;
  * the fields the issue form asks for must be the fields the parser reads,
    or a renamed label turns every report into "missing information";
  * re-running on an unchanged verdict writes nothing (a bot that edits its
    own comment on every event is noise).

The matcher tests run against the real CHANGELOG, ROADMAP and errors.lua, not
invented fixtures: a similarity threshold tuned on toy text means nothing.

Run: pytest TOS-Dev/build/test_issue_triage.py
"""

from __future__ import annotations

import importlib.util
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
spec = importlib.util.spec_from_file_location("issue_triage", HERE / "issue_triage.py")
T = importlib.util.module_from_spec(spec)
sys.modules["issue_triage"] = T
spec.loader.exec_module(T)

REAL = (ROOT / "ROADMAP.md").exists() and (ROOT / "tos" / "kernel" / "errors.lua").exists()
FORMS = ROOT.parent.parent / "Working_Dir" / "tos-repo-push" / "github"

ABOUT = """TOS - Terminal Operating System
Version 1.5.0  [Aletheia]
Build 7b56ed0 (release)
GPU T3 | 2048K RAM"""


def bug_body(about=ABOUT, happened="The mesh drops my message", steps="1. send mail\n2. wait", why=""):
    return ("### What happened\n\n%s\n\n### Steps to reproduce\n\n%s\n\n"
            "### Output of `about`\n\n```text\n%s\n```\n\n"
            "### Output of `why`, or the error code\n\n%s\n\n### How is TOS installed?\n\nFrom a release (the main branch)\n"
            % (happened, steps, about, why or "_No response_"))


def issue(body, title="Something broke", labels=("bug",), n=50, author="reporter", state="open"):
    return T.Issue(n, title, body, author, set(labels), state, "2026-10-01T00:00:00Z")


@pytest.fixture
def ctx():
    errors = {401: ("ERR_PERM_DENIED", "your account is not allowed to do that"),
              501: ("ERR_NET_DOWN", "the network is down")}
    return T.Context(version=(1, 5, 0), errors=errors,
                     symbols={v[0]: k for k, v in errors.items()},
                     files=frozenset({"tos/kernel/net/trust.lua", "tos/kernel/pkg.lua"}),
                     repo="o/r")


def run(i, ctx):
    return T.run_checks(i, ctx)


# ---------------------------------------------------------------- the rule

def test_gh_surface_has_no_way_to_decline():
    names = {n for n in dir(T.Gh) if not n.startswith("_")}
    for forbidden in ("close", "lock", "delete", "hide", "minimize", "transfer"):
        assert not [n for n in names if forbidden in n], (forbidden, names)
    cli = {n for n in dir(T.GhCli) if not n.startswith("__")}
    assert not [n for n in cli if any(f in n for f in ("close", "lock", "delete", "hide"))]


def test_no_state_ever_closes():
    # The three outcomes are all labels; there is no fourth state to map to a close.
    assert set(T.STATES) == {T.READY, T.NEEDS_INFO, T.NEEDS_HUMAN}


def test_apply_only_uses_label_and_comment_calls(ctx):
    gh = FakeGh()
    i = issue(bug_body(), "title")
    T.apply(gh, i, run(i, ctx), ctx)
    assert {c[0] for c in gh.calls} <= {"comments", "add_labels", "remove_label", "post_comment", "edit_comment"}


# ------------------------------------------------------------- the checks

def test_complete_bug_report_is_ready(ctx):
    v = run(issue(bug_body()), ctx)
    assert v.state == T.READY
    assert v.facts["version"] == "1.5.0" and v.facts["variant"] == "release"


def test_missing_about_asks_the_reporter(ctx):
    v = run(issue(bug_body(about="(paste here)")), ctx)
    assert v.state == T.NEEDS_INFO
    assert any(n.code == "about" for n in v.notes)


def test_left_over_placeholder_steps_count_as_missing(ctx):
    v = run(issue(bug_body(steps="(paste here)")), ctx)
    assert v.state == T.NEEDS_INFO


def test_old_version_asks_for_a_retest_without_rejecting(ctx):
    v = run(issue(bug_body(about=ABOUT.replace("1.5.0", "1.3.2"))), ctx)
    assert v.state == T.NEEDS_INFO and "old-version" in v.labels


def test_older_patch_is_a_note_not_a_question(ctx):
    v = run(issue(bug_body(about=ABOUT.replace("1.5.0", "1.5.0")), title="x"), T.Context(**{**ctx.__dict__, "version": (1, 5, 2)}))
    assert v.state == T.READY and "old-version" in v.labels


def test_newer_than_source_goes_to_a_human(ctx):
    v = run(issue(bug_body(about=ABOUT.replace("1.5.0", "9.0.0"))), ctx)
    assert v.state == T.NEEDS_HUMAN


def test_security_report_goes_to_a_human_first(ctx):
    v = run(issue(bug_body(happened="I found a sandbox escape that gives root"), "vulnerability"), ctx)
    assert v.state == T.NEEDS_HUMAN and "security" in v.labels
    assert any("Security" in n.text for n in v.notes if n.severity == "human")


def test_ordinary_use_of_the_word_bypass_does_not_trip_security(ctx):
    v = run(issue(bug_body(happened="the screen bypass cable is loose in my base")), ctx)
    assert "security" not in v.labels


def test_error_code_is_resolved_and_sets_the_area(ctx):
    v = run(issue(bug_body(why="mkdir refused [E-401 ERR_PERM_DENIED]")), ctx)
    assert any(n.code == "code" and "your account is not allowed" in n.text for n in v.notes)
    assert "area:access" in v.labels


def test_unknown_error_code_is_noted_not_fatal(ctx):
    v = run(issue(bug_body(why="E-999 happened")), ctx)
    assert v.state == T.READY and any(n.code == "badcode" for n in v.notes)


def test_stack_trace_files_are_checked_and_mapped_to_an_area(ctx):
    v = run(issue(bug_body(why="/tos/kernel/net/trust.lua:44: boom\n tos/kernel/gone.lua:3: x")), ctx)
    assert "area:network" in v.labels
    assert any(n.code == "trace" for n in v.notes) and any(n.code == "trace-missing" for n in v.notes)


def test_free_text_issue_is_not_held_to_the_form(ctx):
    v = run(issue("When I run pkg install calc on a fresh machine it says the disk is full, "
                  "but df shows plenty of room.", labels=()), ctx)
    assert v.state == T.READY


def test_one_line_free_text_asks_for_more(ctx):
    assert run(issue("broken", labels=()), ctx).state == T.NEEDS_INFO


def test_feature_request_form_is_validated(ctx):
    body = "### What problem are you trying to solve\n\n_No response_\n\n### What would you like TOS to do\n\nx\n"
    assert run(issue(body, labels=("enhancement",)), ctx).state == T.NEEDS_INFO


# ----------------------------------------------------------------- safety

def test_neutralize_strips_mentions_links_and_markup():
    out = T.neutralize("@maintainer **see** [click](http://evil.example) <img src=x> `code` http://x.y/z\nnewline", 200)
    assert "@maintainer" not in out and "evil" not in out and "<" not in out
    assert "\n" not in out and "`" not in out


def test_neutralize_bounds_length():
    assert len(T.neutralize("a" * 500, 90)) <= 90


def test_data_block_cannot_close_its_own_comment(ctx):
    i = issue(bug_body(), "--> <script>alert(1)</script>")
    v = run(i, ctx)
    v.related = [(T.Doc("issue", "#9", "--> <script>x</script> @everyone", "t", state="open"), 0.9)]
    c = T.render_comment(i, v, ctx)
    assert "@everyone" not in c.replace("@​everyone", "")
    data_line = c.splitlines()[-1]
    assert data_line.count("-->") == 1 and data_line.endswith("-->")
    json.loads(data_line[len(T.DATA_OPEN):-len(" -->")])


# --------------------------------------------------------------- applying

class FakeGh(T.Gh):
    def __init__(self, existing=None, issues=()):
        self.calls, self.existing, self._issues = [], existing, list(issues)
        self.labels = {}

    def comments(self, n):
        self.calls.append(("comments", n))
        return [self.existing] if self.existing else []

    def add_labels(self, n, labels): self.calls.append(("add_labels", n, set(labels)))
    def remove_label(self, n, label): self.calls.append(("remove_label", n, label))

    def post_comment(self, n, body):
        self.calls.append(("post_comment", n))
        self.existing = {"id": 1, "body": body, "user": {"type": "Bot"}, "created_at": "2026-10-01T00:00:00Z"}

    def edit_comment(self, cid, body):
        self.calls.append(("edit_comment", cid))
        self.existing["body"] = body

    def issues(self, state="all", label=None, cap=300):
        return [i for i in self._issues if (state == "all" or i.state == state) and (not label or label in i.labels)]


def test_rerun_with_unchanged_verdict_writes_nothing(ctx):
    gh = FakeGh()
    i = issue(bug_body())
    T.apply(gh, i, run(i, ctx), ctx)
    i.labels |= {T.READY}
    gh.calls.clear()
    T.apply(gh, i, run(i, ctx), ctx)
    assert [c[0] for c in gh.calls] == ["comments"]


def test_state_label_flips_when_the_reporter_fixes_the_issue(ctx):
    gh = FakeGh()
    i = issue(bug_body(about="(paste here)"))
    T.apply(gh, i, run(i, ctx), ctx)
    i.labels |= {T.NEEDS_INFO}
    i.body = bug_body()
    gh.calls.clear()
    T.apply(gh, i, run(i, ctx), ctx)
    names = [c[0] for c in gh.calls]
    assert ("add_labels", 50, {T.READY}) in gh.calls
    assert ("remove_label", 50, T.NEEDS_INFO) in gh.calls
    assert "edit_comment" in names and "post_comment" not in names


def test_humans_labels_are_never_removed(ctx):
    gh = FakeGh()
    i = issue(bug_body(), labels=("bug", "wontfix", "good first issue", T.NEEDS_INFO))
    T.apply(gh, i, run(i, ctx), ctx)
    removed = {c[2] for c in gh.calls if c[0] == "remove_label"}
    assert removed == {T.NEEDS_INFO}


def test_skip_conditions():
    base = dict(number=1, title="t", body="b", author="a", labels=set())
    assert T.should_skip(T.Issue(**base, state="closed"))
    assert T.should_skip(T.Issue(**{**base, "labels": {T.SKIP}}))
    assert T.should_skip(T.Issue(**{**base, "author": "dependabot[bot]"}))
    assert T.should_skip(T.Issue(**base), {"comment": {"user": {"login": "maintainer"}}})
    assert T.should_skip(T.Issue(**base), {"comment": {"user": {"login": "a"}}}) is None


def test_stale_moves_silent_needs_info_to_humans_and_keeps_it_open():
    now = datetime(2026, 10, 30, tzinfo=timezone.utc)
    old = (now - timedelta(days=20)).isoformat()
    fresh = (now - timedelta(days=3)).isoformat()

    def mk(n, asked, reply=None):
        i = T.Issue(n, "t", "b", "a", {T.NEEDS_INFO}, "open")
        cs = [{"id": n, "body": T.MARKER, "user": {"type": "Bot", "login": "bot"}, "created_at": asked}]
        if reply:
            cs.append({"id": n + 100, "body": "here", "user": {"login": "a"}, "created_at": reply})
        return i, cs

    issues = {1: mk(1, old), 2: mk(2, fresh), 3: mk(3, old, (now - timedelta(days=1)).isoformat())}

    class G(FakeGh):
        def comments(self, n): return issues[n][1]

    gh = G(issues=[v[0] for v in issues.values()])
    moved = T.sweep_stale(gh, now=now, apply_changes=True, log=lambda *_: None)
    assert moved == [1]
    assert ("add_labels", 1, {T.NEEDS_HUMAN, T.STALLED}) in gh.calls
    assert not [c for c in gh.calls if c[0] not in ("add_labels", "remove_label", "post_comment")]


def test_queue_surfaces_issues_the_bot_never_saw():
    now = "2026-10-01T00:00:00Z"
    gh = FakeGh(issues=[T.Issue(1, "a", "", "u", {T.READY}, "open", now),
                        T.Issue(2, "b", "", "u", {"bug"}, "open", now),
                        T.Issue(3, "c", "", "u", {T.NEEDS_HUMAN, "security"}, "open", now)])
    g = T.queue(gh, log=lambda *_: None)
    assert [i.number for i in g["untriaged"]] == [2]
    assert [i.number for i in g["security"]] == [3]


# ----------------------------------------------- against the real repo text

pytestmark_real = pytest.mark.skipif(not REAL, reason="needs the TOS source tree")


@pytest.fixture(scope="module")
def real():
    return T.load_context(ROOT, "Evan450/TOS-Terminal-Operating-System-")


@pytestmark_real
def test_real_context_loads_what_triage_depends_on(real):
    assert real.version >= (1, 5, 0)
    assert 401 in real.errors and real.symbols["ERR_PERM_DENIED"] == 401
    assert "tos/kernel/pkg.lua" in real.files
    kinds = {d.kind for d in real.docs}
    assert {"roadmap", "changelog", "manual"} <= kinds


@pytestmark_real
def test_every_registered_error_code_resolves(real):
    for n, (sym, title) in real.errors.items():
        v = T.run_checks(issue(bug_body(why="saw E-%d" % n)), real)
        assert any(x.code == "code" for x in v.notes), n
        v = T.run_checks(issue(bug_body(why="saw " + sym)), real)
        assert any(x.code == "code" for x in v.notes), sym


@pytestmark_real
def test_a_report_of_a_known_fixed_bug_finds_its_changelog_entry(real):
    i = issue("### What happened\n\nThe cluster storage node never answers; nothing can reach it "
              "on the ports it should be listening on.\n", "storage node unreachable", labels=("bug",))
    hits = T.rank_related(i.title + " " + i.body, real.docs)
    assert any("Storage Node" in d.title for d, _ in hits), [(d.title, round(s, 2)) for d, s in hits]


@pytestmark_real
@pytest.mark.parametrize("report,title_part", [
    ("mesh mail is delivered late and chat messages get cut off in the middle", "mesh message"),
    ("the floor check reports failure on a healthy machine at boot", "floor check"),
    ("rbmk console package does not find the console block", "RBMK console"),
])
def test_known_reports_find_their_changelog_entry(real, report, title_part):
    hits = T.rank_related(report, real.docs)
    assert any(title_part.lower() in d.title.lower() for d, _ in hits), [(d.title, round(s, 2)) for d, s in hits]


@pytestmark_real
@pytest.mark.parametrize("report", [
    "My cat walked across the keyboard and the pizza arrived late",
    "it crashes when I click the button and nothing happens, please fix",
    "minecraft world will not load after I installed the mod, black screen",
    "how do I change my password for the account",
])
def test_unrelated_report_matches_nothing_spurious(real, report):
    # Measured 2026-10-23: these scored 0.00 title coverage and <=0.22 cosine.
    # A threshold that lists them would put noise in every comment.
    assert T.rank_related(report, real.docs) == []


@pytestmark_real
def test_manual_headings_do_not_come_from_code_fences(real):
    assert not [d for d in real.docs if d.kind == "manual" and len(d.title) < 4]


@pytestmark_real
def test_duplicate_of_an_existing_issue_is_suggested_not_decided(real):
    other = T.Doc("issue", "#7", "Mail to a neighbour is never delivered over the mesh",
                  "I send mesh mail to the next machine over and it just sits in the outbox", state="open")
    ctx = T.Context(**{**real.__dict__, "docs": real.docs + [other]})
    # A paraphrase is listed as a suggestion but not labelled: the label is a
    # claim, and 0.39 is not enough to make it.
    v = T.run_checks(issue("### What happened\n\nMesh mail to the machine beside mine stays in my outbox forever\n",
                           "mesh mail stuck in outbox", labels=("bug",)), ctx)
    assert any(d.ref == "#7" for d, _ in v.related)
    assert "possible-duplicate" not in v.labels
    # Near-verbatim is labelled -- and is still only a label, never a close.
    v = T.run_checks(issue("### What happened\n\nMail to a neighbour is never delivered over the mesh\n",
                           "Mail to a neighbour is never delivered over the mesh", labels=("bug",)), ctx)
    assert "possible-duplicate" in v.labels
    assert v.state in T.STATES


# ------------------------------------------------- the form <-> the parser

@pytest.mark.skipif(not FORMS.exists(), reason="publisher templates are not on the published branch")
def test_issue_forms_are_valid_and_match_what_the_parser_reads():
    yaml = pytest.importorskip("yaml")
    bug = yaml.safe_load((FORMS / "ISSUE_TEMPLATE" / "bug_report.yml").read_text("utf-8"))
    labels = [b["attributes"]["label"].lower().replace("`", "")
              for b in bug["body"] if b["type"] != "markdown"]
    form = {l: "x" for l in labels}
    for keyword in ("happened", "steps", "about"):
        assert T.section(form, keyword) is not None, keyword
    assert "bug" in bug["labels"]
    feat = yaml.safe_load((FORMS / "ISSUE_TEMPLATE" / "feature_request.yml").read_text("utf-8"))
    flabels = {b["attributes"]["label"].lower(): "x" for b in feat["body"] if b["type"] != "markdown"}
    assert T.section(flabels, "problem") is not None
    cfg = yaml.safe_load((FORMS / "ISSUE_TEMPLATE" / "config.yml").read_text("utf-8"))
    assert cfg["blank_issues_enabled"] is True, "blank issues are the fallback; do not turn them off"


@pytest.mark.skipif(not FORMS.exists(), reason="publisher templates are not on the published branch")
def test_workflow_keeps_untrusted_text_out_of_the_shell():
    yaml = pytest.importorskip("yaml")
    text = (FORMS / "workflows" / "issue-triage.yml").read_text("utf-8")
    wf = yaml.safe_load(text)
    on = wf.get("on", wf.get(True))
    assert "pull_request" not in on and "pull_request_target" not in on
    assert wf["permissions"] == {"contents": "read", "issues": "write"}
    for job in wf["jobs"].values():
        for step in job["steps"]:
            run = step.get("run", "")
            assert "${{" not in run, run
            assert "github.event.issue" not in run and "github.event.comment" not in run
