#!/usr/bin/env python3
"""Triage new GitHub issues before a person (or an AI session) reads them.

An issue arrives, and this runs the checks a maintainer would otherwise do by
hand, in the same order: is it a security report filed in public, did the
reporter say which build they run, does the error code they quote exist, does
the stack trace name files that exist, has this been reported or already
fixed or already on the roadmap. The result is a label, one comment, and a
queue position. Nothing else.

THE RULE THIS FILE EXISTS TO KEEP: automation never declines anything. There
is no code path here that closes, locks, deletes or hides an issue, and
test_issue_triage.py asserts the API surface to keep it that way. A check that
cannot decide hands the issue to a human. Three states, mutually exclusive:

    triage:ready        every check passed; a maintainer/AI can start on it
    triage:needs-info   the reporter can fix something (missing `about`, an
                        old version to retest); it re-runs when they reply
    triage:needs-human  automation should not guess (a public security
                        report, a version newer than this source, a stalled
                        needs-info); read these first

An issue that was never triaged (the bot was down, the workflow was off) has
no triage label at all, which `queue` shows as its own group -- the fallback
when the automation itself is the thing that broke.

Issue text is DATA. It is read from the event file, never interpolated into a
shell, never executed, and anything echoed back into a comment (titles of
related issues, code names) goes through neutralize() so a crafted title
cannot ping people or inject markup.

    python build/issue_triage.py triage --issue 12            dry run, print
    python build/issue_triage.py triage --issue 12 --apply    label + comment
    python build/issue_triage.py triage --event event.json --apply   (Actions)
    python build/issue_triage.py stale --apply                nudge old needs-info
    python build/issue_triage.py labels --apply               create the labels
    python build/issue_triage.py queue                        what is waiting

Reads the checkout it runs in (errors.lua, CHANGELOG.md, ROADMAP.md,
MANUAL.md, init.lua); talks to GitHub only through the `gh` CLI.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

MARKER = "<!-- tos-triage -->"
DATA_OPEN = "<!-- tos-triage-data "
STALE_AFTER = timedelta(days=14)

READY = "triage:ready"
NEEDS_INFO = "triage:needs-info"
NEEDS_HUMAN = "triage:needs-human"
STALLED = "triage:stalled"
SKIP = "triage:skip"  # a maintainer's opt-out: the bot leaves this issue alone
STATES = (READY, NEEDS_INFO, NEEDS_HUMAN)

# name -> (color, description). Only labels in this table are ever REMOVED by
# the bot; a label a human applied (wontfix, duplicate, good first issue) is
# never touched.
LABELS = {
    READY: ("0e8a16", "Automated checks passed; ready for a maintainer or AI"),
    NEEDS_INFO: ("fbca04", "Waiting on the reporter for something specific"),
    NEEDS_HUMAN: ("d93f0b", "Automation will not guess; a person should read this"),
    STALLED: ("b60205", "Asked for information, no reply; moved to the human queue"),
    SKIP: ("ededed", "Maintainer opt-out: the triage bot ignores this issue"),
    "security": ("b60205", "Looks like a security report; see SECURITY.md"),
    "old-version": ("c5def5", "Reported on an older version than the source"),
    "possible-duplicate": ("cfd3d7", "Looks like another issue; a human decides"),
    "known-issue": ("e4e669", "Matches an open item on the ROADMAP"),
    "maybe-fixed-in-dev": ("bfdadc", "Matches a change in the unreleased CHANGELOG"),
    "area:boot": ("5319e7", "Boot, BIOS, installer"),
    "area:kernel": ("5319e7", "Kernel, processes, memory"),
    "area:files": ("5319e7", "Files and storage"),
    "area:access": ("5319e7", "Users, permissions, sandbox"),
    "area:network": ("5319e7", "Networking and the mesh"),
    "area:packages": ("5319e7", "pkg and add-ons"),
    "area:hardware": ("5319e7", "Peripherals and hardware"),
    "area:shell": ("5319e7", "Shells, commands, interface"),
}
MANAGED = set(LABELS) - {SKIP}

SUBSYSTEMS = ("boot", "kernel", "files", "access", "network", "packages",
              "hardware", "shell")

# Source path prefix -> area, longest prefix first.
AREA_PATHS = (
    ("tos/kernel/net/", "network"), ("tos/kernel/netfs", "network"),
    ("tos/kernel/netrepair", "network"), ("tos/kernel/pkg", "packages"),
    ("TOS-Extras/", "packages"), ("tos/kernel/securefs", "access"),
    ("tos/kernel/sandbox", "access"), ("tos/kernel/users", "access"),
    ("tos/kernel/vault", "access"), ("tos/kernel/fs", "files"),
    ("tos/kernel/trash", "files"), ("tos/kernel/backup", "files"),
    ("tos/kernel/swap", "files"), ("tos/peripheral/", "hardware"),
    ("tos/kernel/hal", "hardware"), ("tos/shell/", "shell"),
    ("tos/kernel/", "kernel"), ("bios.lua", "boot"), ("init.lua", "boot"),
    ("install.lua", "boot"), ("bootstrap.lua", "boot"),
)

SECURITY_PATTERNS = [re.compile(p, re.I) for p in (
    r"\bvulnerab", r"\bexploit", r"\bCVE-\d", r"sandbox escape",
    r"escape[sd]? the sandbox", r"privilege escalation", r"\bescalat(e|es|ed)\b.*\b(admin|root)",
    r"remote code execution", r"\bRCE\b",
    r"\bbypass(es|ed|ing)?\b.{0,24}\b(acl|sandbox|permission|auth|signature|trust|securefs|login|password)",
    r"\bforg(e|es|ed|ing)\b.{0,16}\bsignature", r"\bleak(s|ed|ing)?\b.{0,16}\b(key|passphrase|secret|password)",
)]

STOP = frozenset("""the and for are but not you all can had her was one our out has have this
that with they from will would there their what about which when your how why who its any
see but also been then them than into some could should just like does did doesn don get got
use used using one two now off new way only over such very more most other these those here
because after before while where still even much many make made need want please thanks thank
issue bug error problem happen happens happened work works working try tried tos""".split())

ABOUT_VERSION = re.compile(r"Version\s+(\d+)\.(\d+)\.(\d+)(?:\s+\[([^\]]*)\])?")
ABOUT_BUILD = re.compile(r"^\s*Build\s+(\S+)\s+\((\w+)\)", re.M)
ABOUT_RAM = re.compile(r"(\d+)K RAM")
CODE_E = re.compile(r"\bE-(\d{3})\b")
CODE_ERR = re.compile(r"\bERR_[A-Z0-9_]{3,}\b")
TRACE_PATH = re.compile(r"(?<![\w.])/?((?:tos|etc|usr|TOS-Extras)/[\w./-]+?\.lua)(?::(\d+))?")
PLACEHOLDERS = ("(paste here)", "paste here", "_no response_", "n/a", "none", "todo")


# ------------------------------------------------------------------ model

@dataclass
class Issue:
    number: int
    title: str
    body: str
    author: str
    labels: set
    state: str = "open"
    created_at: str = ""
    url: str = ""


@dataclass
class Doc:
    kind: str          # issue | changelog | roadmap | manual
    ref: str           # "#12", "Unreleased", "Open bug", "MANUAL"
    title: str
    text: str
    url: str = ""
    state: str = ""    # issue state, or roadmap status


@dataclass
class Context:
    version: tuple = ()
    errors: dict = field(default_factory=dict)   # 401 -> ("ERR_PERM_DENIED", title)
    symbols: dict = field(default_factory=dict)  # "ERR_PERM_DENIED" -> 401
    files: frozenset = frozenset()
    docs: list = field(default_factory=list)
    repo: str = ""


@dataclass
class Note:
    code: str
    severity: str      # ok | note | info | human
    text: str


@dataclass
class Verdict:
    state: str = READY
    labels: set = field(default_factory=set)
    notes: list = field(default_factory=list)
    related: list = field(default_factory=list)   # (Doc, score)
    facts: dict = field(default_factory=dict)

    def add(self, code, severity, text):
        self.notes.append(Note(code, severity, text))


# ----------------------------------------------------------------- helpers

def neutralize(text, limit=90):
    """Make untrusted text safe to quote in a comment: one line, no mentions,
    no links, no HTML, no backticks, bounded."""
    t = re.sub(r"\s+", " ", str(text))
    t = re.sub(r"<[^>]*>", "", t)
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = t.replace("`", "'").replace("@", "@​").replace("|", "/")
    t = re.sub(r"https?://\S+", "(link)", t)
    t = t.strip()
    return t if len(t) <= limit else t[: limit - 3].rstrip() + "..."


def parse_form(body):
    """Split a GitHub issue-form body into {heading: value}. Returns {} for a
    free-text issue. `_No response_` (an empty optional field) becomes ''."""
    parts = re.split(r"^###\s+(.+?)\s*$", body or "", flags=re.M)
    out = {}
    for i in range(1, len(parts) - 1, 2):
        key = parts[i].strip().lower().replace("`", "")
        val = parts[i + 1].strip()
        out[key] = "" if val.lower() == "_no response_" else val
    return out


def section(form, keyword):
    for k, v in form.items():
        if keyword in k:
            return v
    return None


def is_filled(value):
    """True if a form field holds something other than a left-over placeholder."""
    if value is None:
        return False
    stripped = re.sub(r"```\w*", "", value).strip().lower()
    return stripped not in PLACEHOLDERS and len(stripped) >= 3


def kind_of(issue, form):
    if "bug" in issue.labels or section(form, "about") is not None:
        return "bug"
    if "enhancement" in issue.labels or section(form, "problem") is not None:
        return "feature"
    if "question" in issue.labels:
        return "question"
    return "unstructured"


def tokens(text):
    out = []
    for m in CODE_E.finditer(text):
        out.append("code:E-" + m.group(1))
    for m in CODE_ERR.finditer(text):
        out.append("code:" + m.group(0))
    for m in TRACE_PATH.finditer(text):
        out.append("file:" + m.group(1))
    for w in re.findall(r"[a-z][a-z0-9_]{2,}", text.lower()):
        if w in STOP or w == "lua":
            continue
        if len(w) > 4 and w.endswith("s") and not w.endswith("ss"):
            w = w[:-1]
        out.append(w)
    return out


def weight_of(tok, idf):
    w = idf.get(tok, 1.0)
    return w * 3 if tok.startswith(("code:", "file:")) else w


LIST_AT = 0.35    # shown as "possibly related"
LABEL_AT = 0.60   # strong enough to also add a label


def rank_related(query_text, docs, exclude_ref=None):
    """Score each doc by the larger of two idf-weighted measures: cosine over
    title+body, and how much of the doc's TITLE the issue covers. Cosine alone
    drowns in long bodies (a true match scored 0.18); title coverage separated
    real matches (0.38-1.00) from unrelated text (0.00) on the real CHANGELOG.
    A shared error code or file path counts as a strong match on its own."""
    if not docs:
        return []
    doc_toks = [set(tokens(d.title + " " + d.title + " " + d.text[:2500])) for d in docs]
    title_toks = [set(tokens(d.title)) for d in docs]
    q = set(tokens(query_text))
    if not q:
        return []
    n = len(docs) + 1
    df = {}
    for ts in doc_toks + [q]:
        for t in ts:
            df[t] = df.get(t, 0) + 1
    idf = {t: math.log(1 + n / c) for t, c in df.items()}
    qn = math.sqrt(sum(weight_of(t, idf) ** 2 for t in q))
    scored = []
    for d, ts, title in zip(docs, doc_toks, title_toks):
        if exclude_ref and d.kind == "issue" and d.ref == exclude_ref:
            continue
        shared = q & ts
        if not shared:
            continue
        dn = math.sqrt(sum(weight_of(t, idf) ** 2 for t in ts))
        cosine = sum(weight_of(t, idf) ** 2 for t in shared) / (qn * dn)
        in_title = q & title
        coverage = 0.0
        if len(in_title) >= 2:
            coverage = sum(weight_of(t, idf) for t in in_title) / sum(weight_of(t, idf) for t in title)
        score = max(cosine, coverage)
        if any(t.startswith(("code:", "file:")) for t in shared) and cosine >= 0.10:
            score = max(score, LABEL_AT)
        if score >= LIST_AT:
            scored.append((d, score))
    scored.sort(key=lambda p: -p[1])
    return scored[:3]


# ------------------------------------------------------------------ checks

def check_security(issue, form, ctx, v):
    text = issue.title + "\n" + issue.body
    if any(p.search(text) for p in SECURITY_PATTERNS):
        v.labels.add("security")
        v.add("security", "human",
              "This reads like a security report, and this issue is public. "
              "Please do not post exploit details here: use the repository's "
              "**Security** tab, then **Report a vulnerability** (see SECURITY.md). "
              "You can edit this issue down to a one-line pointer. A maintainer has been "
              "flagged to read it first.")


def check_completeness(issue, form, ctx, v, kind):
    if kind == "unstructured":
        if len(re.sub(r"\s+", " ", issue.body).strip()) < 40:
            v.add("thin", "info",
                  "The description is very short. What did you do, what did you expect, "
                  "and what happened instead?")
        return
    if kind == "bug":
        asks = []
        if not is_filled(section(form, "happened")) and form:
            asks.append("what happened, in a sentence or two")
        if not is_filled(section(form, "steps")) and form:
            asks.append("steps to reproduce")
        if asks:
            v.add("fields", "info", "Still missing: " + "; ".join(asks) + ".")
    elif kind == "feature":
        if form and not is_filled(section(form, "problem")):
            v.add("fields", "info", "What problem would this solve? A use case helps more than a design.")


def check_version(issue, form, ctx, v, kind):
    if kind != "bug":
        return
    text = issue.body
    m = ABOUT_VERSION.search(text)
    if not m:
        v.add("about", "info",
              "Please run `about` on the machine and paste the output; it names the exact "
              "version and build, which is the first thing needed to reproduce this.")
        return
    reported = tuple(int(m.group(i)) for i in (1, 2, 3))
    codename = m.group(4) or "?"
    b = ABOUT_BUILD.search(text)
    build, variant = (b.group(1), b.group(2)) if b else ("?", "?")
    ram = ABOUT_RAM.search(text)
    v.facts.update(version=".".join(map(str, reported)), codename=codename,
                   build=build, variant=variant, ram_k=int(ram.group(1)) if ram else None)
    v.add("about", "ok", "`about` output read: %s \"%s\", %s build" % (
        v.facts["version"], neutralize(codename, 30), neutralize(variant, 20)))
    if build.endswith("-dirty"):
        v.add("dirty", "note", "The build is marked `-dirty`: it was built from a modified source tree.")
    if ram and int(ram.group(1)) < 1024:
        v.add("ram", "note", "That machine has %dK of RAM; TOS needs 1 MB to start, so memory may be the cause." % int(ram.group(1)))
    cur = ctx.version
    if cur:
        if reported > cur:
            v.add("newer", "human",
                  "The reported version is newer than this source (%s). It may be a fork or a "
                  "mistyped version." % ".".join(map(str, cur)))
        elif reported[:2] < cur[:2]:
            v.labels.add("old-version")
            v.add("old", "info",
                  "This was reported on %s; the current source is %s. Could you retest on the "
                  "current release or `dev` and say whether it still happens?"
                  % (v.facts["version"], ".".join(map(str, cur))))
        elif reported < cur:
            v.labels.add("old-version")
            v.add("old-patch", "note", "Reported on %s; the current source is %s." % (
                v.facts["version"], ".".join(map(str, cur))))


def check_codes_and_traces(issue, form, ctx, v):
    text = issue.title + "\n" + issue.body
    areas = []
    seen = set()
    for m in CODE_E.finditer(text):
        n = int(m.group(1))
        seen.add(n)
    for m in CODE_ERR.finditer(text):
        n = ctx.symbols.get(m.group(0))
        if n:
            seen.add(n)
        elif ctx.errors:
            v.add("badcode", "note", "`%s` is not in the error registry (a typo, or a different version)." % neutralize(m.group(0), 40))
    for n in sorted(seen):
        if n in ctx.errors:
            sym, title = ctx.errors[n]
            v.add("code", "ok", "E-%d is `%s`: %s" % (n, sym, neutralize(title, 110)))
            sub = n // 100 - 1
            if 0 <= sub < len(SUBSYSTEMS):
                areas.append(SUBSYSTEMS[sub])
        elif ctx.errors:
            v.add("badcode", "note", "E-%d is not in the error registry (a typo, or a different version)." % n)
    missing, present = [], []
    for m in TRACE_PATH.finditer(text):
        path = m.group(1)
        (present if path in ctx.files else missing).append(path)
        if path in ctx.files:
            for prefix, area in AREA_PATHS:
                if path.startswith(prefix):
                    areas.append(area)
                    break
    if present:
        v.add("trace", "ok", "Stack trace names %d known file(s): %s" % (
            len(set(present)), ", ".join("`%s`" % neutralize(p, 60) for p in sorted(set(present))[:4])))
    if missing and ctx.files:
        v.add("trace-missing", "note",
              "Trace names file(s) that are not in this source: %s. The reported build may differ."
              % ", ".join("`%s`" % neutralize(p, 60) for p in sorted(set(missing))[:3]))
    for a in dict.fromkeys(areas):
        if len([l for l in v.labels if l.startswith("area:")]) < 2:
            v.labels.add("area:" + a)


def check_related(issue, form, ctx, v, kind):
    query = issue.title + " " + issue.title + " " + issue.body
    hits = rank_related(query, ctx.docs, exclude_ref="#%d" % issue.number)
    v.related = hits
    reported_release = v.facts.get("variant") not in (None, "source", "?")
    for d, score in hits:
        if score < LABEL_AT:
            continue
        if d.kind == "issue":
            v.labels.add("possible-duplicate")
        elif d.kind == "roadmap" and d.state.lower() in ("open bug", "in progress"):
            v.labels.add("known-issue")
        elif d.kind == "changelog" and d.ref == "Unreleased" and reported_release:
            v.labels.add("maybe-fixed-in-dev")


def run_checks(issue, ctx):
    form = parse_form(issue.body)
    kind = kind_of(issue, form)
    v = Verdict()
    v.facts["kind"] = kind
    check_security(issue, form, ctx, v)
    check_completeness(issue, form, ctx, v, kind)
    check_version(issue, form, ctx, v, kind)
    check_codes_and_traces(issue, form, ctx, v)
    check_related(issue, form, ctx, v, kind)
    sev = {n.severity for n in v.notes}
    v.state = NEEDS_HUMAN if "human" in sev else NEEDS_INFO if "info" in sev else READY
    return v


# --------------------------------------------------------------- rendering

def render_comment(issue, v, ctx):
    lines = [MARKER, "Thanks for the report. This is an automated first pass; it never closes "
             "or rejects an issue, and a person reads everything it cannot settle.", ""]
    human = [n for n in v.notes if n.severity == "human"]
    info = [n for n in v.notes if n.severity == "info"]
    checked = [n for n in v.notes if n.severity == "ok"]
    notes = [n for n in v.notes if n.severity == "note"]
    if human:
        lines += ["**Flagged for a maintainer**", ""] + ["- " + n.text for n in human] + [""]
    if info:
        lines += ["**Needed from you**", ""] + ["- [ ] " + n.text for n in info]
        lines += ["", "Edit the issue or reply here and this re-checks itself.", ""]
    if checked:
        lines += ["**Checked**", ""] + ["- " + n.text for n in checked] + [""]
    if notes:
        lines += ["**Noted**", ""] + ["- " + n.text for n in notes] + [""]
    if v.related:
        lines += ["**Possibly related** (suggestions, not decisions)", ""]
        for d, score in v.related:
            lines.append("- " + describe_doc(d, ctx))
        lines.append("")
    nxt = {READY: "Everything automation can check passed. This is in the queue for a maintainer.",
           NEEDS_INFO: "Waiting on the items above. If there is no reply in %d days it moves "
                       "to the maintainer queue (still open)." % STALE_AFTER.days,
           NEEDS_HUMAN: "A maintainer will read this next."}[v.state]
    lines += ["**Status:** `%s`. %s" % (v.state, nxt), ""]
    data = {"state": v.state, "labels": sorted(v.labels), "kind": v.facts.get("kind"),
            "version": v.facts.get("version"), "build": v.facts.get("build"),
            "notes": [n.code for n in v.notes],
            "related": [[d.kind, d.ref] for d, _ in v.related]}
    blob = json.dumps(data, separators=(",", ":")).replace("--", "-\\u002d").replace(">", "\\u003e")
    lines.append(DATA_OPEN + blob + " -->")
    return "\n".join(lines)


def describe_doc(d, ctx):
    base = "https://github.com/%s/blob/dev/" % ctx.repo if ctx.repo else ""
    t = neutralize(d.title)
    if d.kind == "issue":
        state = " (%s)" % d.state if d.state else ""
        return "%s%s %s" % (d.ref, state, t)
    if d.kind == "roadmap":
        return "ROADMAP, *%s*: %s" % (neutralize(d.state, 30), t)
    if d.kind == "changelog":
        if d.ref == "Unreleased":
            return "CHANGELOG, on `dev` but not in a release yet: %s" % t
        return "CHANGELOG (%s): %s" % (neutralize(d.ref, 30), t)
    return "MANUAL: %s" % t


# ------------------------------------------------------------ context load

def load_context(root, repo="", issue_docs=()):
    root = Path(root)
    ctx = Context(repo=repo)
    init = root / "init.lua"
    if init.exists():
        m = re.search(r'^\s*version\s*=\s*"(\d+)\.(\d+)\.(\d+)"', init.read_text("utf-8", "replace"), re.M)
        if m:
            ctx.version = tuple(int(x) for x in m.groups())
    err = root / "tos" / "kernel" / "errors.lua"
    if err.exists():
        for m in re.finditer(r'\{\s*(\d{3}),\s*"(ERR_\w+)",\s*"((?:[^"\\]|\\.)*)"', err.read_text("utf-8", "replace")):
            ctx.errors[int(m.group(1))] = (m.group(2), m.group(3))
            ctx.symbols[m.group(2)] = int(m.group(1))
    files = set()
    for top in ("tos", "etc", "usr", "TOS-Extras"):
        for p in (root / top).rglob("*.lua") if (root / top).is_dir() else ():
            files.add(p.relative_to(root).as_posix())
    ctx.files = frozenset(files)
    ctx.docs = _doc_corpus(root) + list(issue_docs)
    return ctx


def _doc_corpus(root):
    docs = []
    rm = root / "ROADMAP.md"
    if rm.exists():
        parts = re.split(r"^### (.+)$", rm.read_text("utf-8", "replace"), flags=re.M)
        for i in range(1, len(parts) - 1, 2):
            body = parts[i + 1]
            m = re.match(r"\s*\*([^*]+)\*", body)
            docs.append(Doc("roadmap", "ROADMAP", parts[i].strip(), body.split("\n## ")[0],
                            state=m.group(1).strip() if m else ""))
    cl = root / "CHANGELOG.md"
    if cl.exists():
        release = ""
        for block in re.split(r"^(## .+)$", cl.read_text("utf-8", "replace"), flags=re.M):
            if block.startswith("## "):
                release = block[3:].strip()
                release = "Unreleased" if release.lower().startswith("unreleased") else release
                continue
            parts = re.split(r"^### (.+)$", block, flags=re.M)
            for i in range(1, len(parts) - 1, 2):
                docs.append(Doc("changelog", release, parts[i].strip(), parts[i + 1]))
    mn = root / "MANUAL.md"
    if mn.exists():
        # Fenced blocks hold shell and Lua, where a leading `#` is a comment,
        # not a heading ("U", "R", "G" were all matched as manual sections).
        text = re.sub(r"^```.*?^```", "", mn.read_text("utf-8", "replace"), flags=re.M | re.S)
        parts = re.split(r"^#{1,3} (.+)$", text, flags=re.M)
        for i in range(1, len(parts) - 1, 2):
            if len(parts[i].strip()) >= 4:
                docs.append(Doc("manual", "MANUAL", parts[i].strip(), parts[i + 1][:800]))
    return docs


# --------------------------------------------------------------- GitHub I/O

class Gh:
    """The ENTIRE surface automation may use on GitHub. There is deliberately
    no close, lock, delete or hide here; the test asserts it."""

    def issue(self, n): raise NotImplementedError
    def issues(self, state="all", label=None, cap=300): raise NotImplementedError
    def comments(self, n): raise NotImplementedError
    def add_labels(self, n, labels): raise NotImplementedError
    def remove_label(self, n, label): raise NotImplementedError
    def post_comment(self, n, body): raise NotImplementedError
    def edit_comment(self, comment_id, body): raise NotImplementedError
    def ensure_label(self, name, color, description): raise NotImplementedError


class GhCli(Gh):
    def __init__(self, repo):
        self.repo = repo

    def _api(self, method, path, payload=None):
        cmd = ["gh", "api", "-X", method, path]
        if payload is not None:
            cmd += ["--input", "-"]
        r = subprocess.run(cmd, input=json.dumps(payload) if payload is not None else None,
                           capture_output=True, text=True, encoding="utf-8")
        if r.returncode != 0:
            raise RuntimeError("gh api %s %s failed: %s" % (method, path, r.stderr.strip()[:300]))
        return json.loads(r.stdout) if r.stdout.strip() else None

    @staticmethod
    def _issue(d):
        return Issue(d["number"], d.get("title") or "", d.get("body") or "",
                     (d.get("user") or {}).get("login", ""),
                     {l["name"] for l in d.get("labels", [])}, d.get("state", "open"),
                     d.get("created_at", ""), d.get("html_url", ""))

    def issue(self, n):
        return self._issue(self._api("GET", "repos/%s/issues/%d" % (self.repo, n)))

    def issues(self, state="all", label=None, cap=300):
        out, page = [], 1
        while len(out) < cap:
            q = "repos/%s/issues?state=%s&per_page=100&page=%d" % (self.repo, state, page)
            if label:
                q += "&labels=" + label
            batch = self._api("GET", q) or []
            out += [self._issue(d) for d in batch if "pull_request" not in d]
            if len(batch) < 100:
                break
            page += 1
        return out[:cap]

    def comments(self, n):
        return self._api("GET", "repos/%s/issues/%d/comments?per_page=100" % (self.repo, n)) or []

    def add_labels(self, n, labels):
        self._api("POST", "repos/%s/issues/%d/labels" % (self.repo, n), {"labels": sorted(labels)})

    def remove_label(self, n, label):
        try:
            self._api("DELETE", "repos/%s/issues/%d/labels/%s" % (self.repo, n, label.replace(":", "%3A")))
        except RuntimeError as e:
            if "Not Found" not in str(e) and "404" not in str(e):
                raise

    def post_comment(self, n, body):
        self._api("POST", "repos/%s/issues/%d/comments" % (self.repo, n), {"body": body})

    def edit_comment(self, comment_id, body):
        self._api("PATCH", "repos/%s/issues/comments/%d" % (self.repo, comment_id), {"body": body})

    def ensure_label(self, name, color, description):
        try:
            self._api("POST", "repos/%s/labels" % self.repo,
                      {"name": name, "color": color, "description": description})
        except RuntimeError as e:
            if "already_exists" in str(e) or "422" in str(e):
                self._api("PATCH", "repos/%s/labels/%s" % (self.repo, name.replace(":", "%3A")),
                          {"color": color, "description": description})
            else:
                raise


def issue_docs(gh, exclude_number=None):
    docs = []
    for i in gh.issues("all"):
        if i.number == exclude_number:
            continue
        docs.append(Doc("issue", "#%d" % i.number, i.title, i.body[:2500], i.url, i.state))
    return docs


def find_bot_comment(comments):
    for c in comments:
        if (c.get("user") or {}).get("type") == "Bot" and (c.get("body") or "").startswith(MARKER):
            return c
    return None


def apply(gh, issue, verdict, ctx):
    """Write the verdict. Idempotent: an unchanged verdict touches nothing."""
    want = set(verdict.labels) | {verdict.state}
    if STALLED in issue.labels and verdict.state != READY:
        want.add(STALLED)
    add = want - issue.labels
    drop = (issue.labels & MANAGED) - want
    if add:
        gh.add_labels(issue.number, add)
    for label in sorted(drop):
        gh.remove_label(issue.number, label)
    body = render_comment(issue, verdict, ctx)
    existing = find_bot_comment(gh.comments(issue.number))
    if existing is None:
        gh.post_comment(issue.number, body)
    elif existing.get("body") != body:
        gh.edit_comment(existing["id"], body)
    return add, drop


def should_skip(issue, event=None):
    if issue.state != "open":
        return "issue is not open"
    if SKIP in issue.labels:
        return "triage:skip label"
    if issue.author.endswith("[bot]"):
        return "authored by a bot"
    if event and event.get("comment"):
        who = (event["comment"].get("user") or {}).get("login", "")
        if who != issue.author:
            return "comment is not from the reporter"
    if event and event.get("sender", {}).get("type") == "Bot":
        return "triggered by a bot"
    return None


# ------------------------------------------------------------------ stale

def sweep_stale(gh, now=None, apply_changes=False, log=print):
    now = now or datetime.now(timezone.utc)
    moved = []
    for issue in gh.issues("open", label=NEEDS_INFO):
        if STALLED in issue.labels or SKIP in issue.labels:
            continue
        comments = gh.comments(issue.number)
        bot = find_bot_comment(comments)
        if not bot:
            continue
        asked = _ts(bot.get("created_at"))
        replied = any(_ts(c.get("created_at")) > asked and (c.get("user") or {}).get("login") == issue.author
                      for c in comments)
        if replied or now - asked < STALE_AFTER:
            continue
        moved.append(issue.number)
        log("#%d: no reply for %d days -> %s" % (issue.number, (now - asked).days, NEEDS_HUMAN))
        if apply_changes:
            gh.add_labels(issue.number, {NEEDS_HUMAN, STALLED})
            gh.remove_label(issue.number, NEEDS_INFO)
            gh.post_comment(issue.number,
                "No reply to the questions above in %d days, so this is moving to the maintainer "
                "queue. It stays **open**; nothing is being declined. Reply any time to continue.\n\n%s"
                % (STALE_AFTER.days, "<!-- tos-triage-stale -->"))
    return moved


def _ts(s):
    return datetime.fromisoformat((s or "1970-01-01T00:00:00Z").replace("Z", "+00:00"))


# ------------------------------------------------------------------- queue

def queue(gh, log=print):
    groups = {"security": [], NEEDS_HUMAN: [], READY: [], NEEDS_INFO: [], "untriaged": []}
    for i in gh.issues("open"):
        if "security" in i.labels:
            groups["security"].append(i)
        elif NEEDS_HUMAN in i.labels:
            groups[NEEDS_HUMAN].append(i)
        elif READY in i.labels:
            groups[READY].append(i)
        elif NEEDS_INFO in i.labels:
            groups[NEEDS_INFO].append(i)
        else:
            groups["untriaged"].append(i)
    titles = {"security": "Security (read first)", NEEDS_HUMAN: "Needs a human",
              READY: "Ready", NEEDS_INFO: "Waiting on the reporter",
              "untriaged": "Never triaged (the bot did not see these)"}
    now = datetime.now(timezone.utc)
    for key, items in groups.items():
        log("\n%s: %d" % (titles[key], len(items)))
        for i in sorted(items, key=lambda x: x.created_at):
            log("  #%-4d %3dd  %s" % (i.number, (now - _ts(i.created_at)).days, neutralize(i.title, 70)))
    return groups


# --------------------------------------------------------------------- CLI

def main(argv=None, gh=None):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace") if hasattr(sys.stdout, "reconfigure") else None
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("command", choices=("triage", "stale", "labels", "queue"))
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--issue", type=int)
    ap.add_argument("--event", help="path to a GitHub Actions event payload")
    ap.add_argument("--apply", action="store_true", help="write labels/comments (default: print only)")
    a = ap.parse_args(argv)
    if gh is None:
        if not a.repo:
            ap.error("--repo (or GITHUB_REPOSITORY) is required")
        gh = GhCli(a.repo)

    if a.command == "labels":
        for name, (color, desc) in LABELS.items():
            print("label", name)
            if a.apply:
                gh.ensure_label(name, color, desc)
        return 0
    if a.command == "queue":
        queue(gh)
        return 0
    if a.command == "stale":
        moved = sweep_stale(gh, apply_changes=a.apply)
        print("%d issue(s) %s" % (len(moved), "moved" if a.apply else "would move"))
        return 0

    event = None
    if a.event:
        event = json.loads(Path(a.event).read_text("utf-8"))
        if "issue" not in event:
            print("event has no issue; nothing to do")
            return 0
        if "pull_request" in event["issue"]:
            print("pull request; nothing to do")
            return 0
        issue = GhCli._issue(event["issue"])
    elif a.issue:
        issue = gh.issue(a.issue)
    else:
        ap.error("triage needs --issue or --event")
    why = should_skip(issue, event)
    if why:
        print("#%d skipped: %s" % (issue.number, why))
        return 0
    ctx = load_context(a.root, a.repo, issue_docs(gh, issue.number))
    verdict = run_checks(issue, ctx)
    print("#%d -> %s  labels=%s" % (issue.number, verdict.state, sorted(verdict.labels)))
    if a.apply:
        apply(gh, issue, verdict, ctx)
    else:
        print("\n" + render_comment(issue, verdict, ctx))
    return 0


if __name__ == "__main__":
    sys.exit(main())
