# Issue triage

Every issue filed on the public repository gets an automated first pass before a person reads it. The pass validates the report, looks for duplicates and known issues, labels it, and leaves one comment. **It never closes, rejects, locks or hides anything.** A check that cannot decide hands the issue to a human; a report the bot is happy with goes into the queue for a maintainer (or an AI session) to pick up.

The logic is `build/issue_triage.py`, tested by `build/test_issue_triage.py`. The GitHub side (issue forms and the workflow) is generated onto the published branches by `publish.ps1` from `Working_Dir/tos-repo-push/github/`; the workflow lands on `dev` only, because issue events run workflows from the default branch.

## What it checks

| Check | Looks at | If it fails |
|---|---|---|
| Security | words like *exploit*, *sandbox escape*, *privilege escalation*, *bypass the ACL* | `security` + `triage:needs-human`; the comment points to the private Security tab |
| Completeness | the form's fields; a left-over `(paste here)` counts as empty | `triage:needs-info` with the specific missing item |
| Version | the `about` output: version, codename, build, variant, RAM | missing: asked for. Older than the source's minor: asked to retest (`old-version`). Newer than the source: `triage:needs-human` |
| Error codes | `E-401` / `ERR_PERM_DENIED`, resolved against `tos/kernel/errors.lua`; the hundreds digit sets the `area:` label | an unknown code is noted, never fatal |
| Stack traces | `tos/...lua:NN` paths, checked against the checkout; paths set the `area:` label | a missing file is noted (the reported build may differ) |
| Related | issues (open and closed), CHANGELOG entries, ROADMAP entries, MANUAL sections | listed as suggestions; a strong match also adds `possible-duplicate`, `known-issue` or `maybe-fixed-in-dev` |

Matching scores each document by the larger of idf-weighted cosine and how much of the document's *title* the issue covers; cosine alone drowned in long bodies. A shared error code or file path counts as a strong match by itself. The thresholds are pinned by tests against the real CHANGELOG and ROADMAP: real matches scored 0.38 to 1.00 and unrelated text scored 0.00.

## States

| Label | Meaning |
|---|---|
| `triage:ready` | Every check passed. Pick it up. |
| `triage:needs-info` | The reporter can fix something. Re-checks when they edit the issue or reply. After 14 days of silence the daily sweep moves it to `triage:needs-human` + `triage:stalled`, still open. |
| `triage:needs-human` | Read these first: public security reports, versions newer than the source, stalled needs-info. |
| `triage:skip` | You put this on an issue to make the bot leave it alone. |

Only labels the bot manages are ever removed; `wontfix`, `duplicate`, `good first issue` and the rest are yours. An issue with **no** `triage:` label was never seen by the bot (it was off, or it failed), which is why `queue` lists those as their own group.

## Working the queue

```
python build/issue_triage.py queue --repo Evan450/TOS-Terminal-Operating-System-
```

prints open issues grouped: security, needs a human, ready, waiting on the reporter, never triaged. The bot's comment ends with a hidden `tos-triage-data` JSON block (state, labels, version, which checks fired, related items), so an AI session can read the findings from the comment instead of redoing them.

To re-run a single issue by hand: `python build/issue_triage.py triage --issue N --repo ...` prints the verdict and the comment it would post; add `--apply` to write it. The workflow's *Run workflow* button does the same for an issue number.

## First-time setup

Nothing exists on GitHub until the next `publish.ps1 -Dev -Push`. After that the daily sweep creates the labels, or run `python build/issue_triage.py labels --apply` once. Actions must be enabled on the repository.

## Safety

- Issue text is read from the event payload file and never interpolated into a shell or a `${{ }}` expression. The workflow has no `pull_request` trigger, so no fork code and no secrets are involved; its token is `issues: write` and `contents: read`.
- Anything echoed into a comment (related issue titles, error names) goes through `neutralize()`: one line, no mentions, links, HTML or backticks, bounded length.
- A comment from anyone but the reporter does not re-run triage, so a maintainer's labelling is not overwritten.
- `Gh`, the class holding every GitHub call the bot may make, has no close, lock, delete or hide method; `test_gh_surface_has_no_way_to_decline` fails if one appears.

## Not built

- **Reproduction.** The bot cannot run a report. `python tos.py selftest` and `build/headless-session.py` boot a real machine, but turning free text into a script is a judgement call that belongs to a person or an AI session reading the `ready` queue.
- **An AI reviewer in the workflow.** It would need an API key as a repository secret, would spend money on text any stranger can write, and would read untrusted input with write access. If wanted, trigger it on a maintainer applying a label, never on `issues: opened`.
