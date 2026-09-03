# Contributing to TOS

Thanks for looking. TOS is a Terminal Operating System for the OpenComputers Minecraft mod, written in Lua 5.3, and it runs on machines with as little as 192 KB of RAM — that constraint shapes most of the rules below.

## The one thing to know first

**Work on `dev`. Never commit to `main`.**

| Branch | What it is | Edit it? |
|---|---|---|
| `main` | The release build. Comments stripped, tests and build tooling removed. This is what installers download. | **No.** Generated. |
| `dev` | The source tree. Full comments, `usr/lib/tests/`, `build/`. | **Yes.** |

`main` is produced from `dev` by `build/strip.lua`. A commit to `main` is not "a fix that skipped review" — it is a change that the next release build silently overwrites. If you have already done it, cherry-pick onto `dev` and open the PR there.

## Finding something to work on

[`ROADMAP.md`](ROADMAP.md) is the open queue, grouped by status. Two kinds of entry are especially good to pick up:

- **Open bugs** — known broken, and the entry usually says what was already ruled out.
- **Emulator checklist items** — these need a real OpenComputers install to verify. The off-box suite runs on stock Lua, so it structurally cannot see that class of bug. If you play the mod, this is where you can do something the maintainer's test suite cannot.

Entries marked *idea / far future* are not commitments — discuss before building one.

The roadmap also records work deliberately **not** done, with reasons. Reading the relevant entry before proposing a change will usually tell you whether it has already been considered and rejected, and why.

## Getting set up

You need a `lua` interpreter (5.3 or 5.4) and Python 3 for the test runner.

```bash
git clone --branch dev https://github.com/Evan450/TOS-Terminal-Operating-System-.git
cd TOS-Terminal-Operating-System-
python run_tests.py
```

The suite is ~185 files of pure Lua plus a few Python build tests. It touches no GPU and needs no Minecraft — everything runs off-box against fakes. It should be green before you start and green when you finish.

To try your change on a real machine, install it over the network onto a bare OpenOS box with an internet card, pointing the bootstrap at your branch:

```
bootstrap.lua <your-fork> dev
```

## Making a change

1. **Read before you edit.** Grep for every caller of a function you are changing. Kernel modules are wired together in `tos/kernel/init.lua`, and the panels shell dispatches through a command registry — changing a signature in one place usually means several.
2. **Add a test.** `usr/lib/tests/test_*.lua` is auto-discovered by `run_tests.py`. Follow the existing shape: a `test(name, cond)` helper, prints `PASS`/`FAIL`, returns false if anything failed. If the thing you fixed had no coverage, a regression test for it is the most valuable part of the PR.
3. **Run the suite.** `python run_tests.py`. Report the result in the PR — do not claim a fix works if you have not run it.
4. **Keep the manifest honest.** If you add a runtime file under `/tos`, `/etc/rc.d`, `/usr/bin` or `/usr/modules`, add it to `tos/system_manifest.lua` as well. `test_manifest_completeness.lua` enforces this — a file missing from the manifest is silently absent from every fresh install and invisible to `verify`.
5. **Update the docs in the same commit.** Version bumps touch `README.md`, `CHANGELOG.md`, and any version constant together. Documentation that contradicts the code is worse than none.

## Comment conventions

The comment markers are load-bearing — `strip.lua` reads them:

| Marker | Meaning | Survives into `main`? |
|---|---|---|
| `--!` | Security note, cross-file invariant, license header | **Yes** |
| `--` | Ordinary explanation, rationale, dev notes | No |

Use `--!` for anything a future reader must not lose: why a check exists, what attack it stops, what invariant another file depends on. Use plain `--` for everything else. Block comments follow the same rule (`--[[!` keeps, `--[[` drops).

Mark security-relevant code with a `#SEC` tag and the finding ID where one exists, matching the existing style.

## Writing for a 192 KB machine

- **Memory is the budget.** Prefer iteration over building intermediate tables. A response held as a Lua string is real RAM. Reading a file with `*a` when you could stream it in 4 KB chunks is how an install OOMs.
- **Yield in long loops.** OpenComputers gives the whole machine one CPU shared across every seat, and a loop that never yields triggers the "too long without yielding" watchdog. Use `proc.yieldCooperative()`.
- **Never truncate a file you might fail to finish writing.** Write to `path.tmp`, verify, then rename. There are atomic helpers (`fs.writeFileAtomic`) for the state files that must survive a power cut.
- **Lua 5.3 syntax is required** — kernel modules use bitwise operators and `string.pack`. Do not add anything that needs 5.4-only features.
- **No spaces in file or directory names.**

## Markdown, for the docs

Two things that break on GitHub and are easy to do by accident:

- **Angle brackets outside backticks disappear.** `<topic>` in prose is parsed as an HTML tag and silently deleted. Always write `` `<topic>` ``.
- **A wrapped line starting with `- `, `+ ` or `* ` becomes a bullet.** Sentences that wrap onto a line beginning with one of those turn into a spurious list item mid-paragraph. Rewrap, or reword.

## Pull requests

Keep them scoped to one thing. In the description, say what changed, why, and what you ran to verify it. If a change is a design decision rather than a fix, say what you considered and rejected — that is the part review actually needs.

Security findings that should not be public first: say so in the PR description without the details, or open an issue asking for a private channel.

## License

TOS is GPL v3.0. Contributions are accepted under the same license, and existing license headers must be preserved.
