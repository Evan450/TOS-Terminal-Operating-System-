# Contributing to TOS

Thanks for looking. TOS is a Terminal Operating System for the OpenComputers Minecraft mod, written in Lua 5.3. Every byte it loads comes out of the machine's memory, and TOS already needs 1 MB to start (see the README's requirements) — that constraint shapes most of the rules below.

## The one thing to know first

**Work on `dev`. Never commit to `main`.**

| Branch | What it is | Edit it? |
|---|---|---|
| `main` | The **release build** — what installers download. Comments stripped, dev tests and build tooling removed, blank-line runs collapsed. | **No.** Generated. |
| `dev` | The **source tree**. Full `--!` security/invariant comments, `usr/lib/tests/`, `build/`, and the add-on source in `TOS-Extras/`. One clone, suite green. | **Yes** — all work happens here. |
| `optional-utilities` | The **add-on pack**, laid out as a `pkg` repository so a machine with an internet card installs from it directly. | **No.** Generated from `TOS-Extras/` on `dev`. |
| `master` | A stub carrying only an OPPM index, so `oppm` can find TOS. OPPM hardcodes the branch name. | **No.** Two files. |

`main` is produced from `dev` by `build/strip.lua`. A commit to `main` is not "a fix that skipped review" — it is a change that the next release build silently overwrites. If you have already done it, cherry-pick onto `dev` and open the PR there.

The split exists because comments cost real memory on a machine where every kilobyte counts, and the BIOS is fighting a hard 4 KiB EEPROM budget — roughly a third of `bios.lua` is comments that must not ship, and must not be lost either. `strip.lua` keeps every `--!`-marked comment (security notes, cross-file invariants, license headers) and drops the rest.

Installing from either branch works, since both carry the same tree shape and the same `tos/system_manifest.lua`:

```
bootstrap.lua                                            # main (release)
bootstrap.lua Evan450/TOS-Terminal-Operating-System- dev  # dev (source)
```

## Finding something to work on

[`ROADMAP.md`](ROADMAP.md) is the open queue, grouped by status. Two kinds of entry are especially good to pick up:

- **Open bugs** — known broken, and the entry usually says what was already ruled out.
- **Emulator checklist items** — these need a real OpenComputers install to verify. The off-box suite runs on stock Lua, so it structurally cannot see that class of bug. If you play the mod, this is where you can do something the maintainer's test suite cannot.

Entries marked *idea / far future* are not commitments — discuss before building one.

The roadmap also records work deliberately **not** done, with reasons. Reading the relevant entry before proposing a change will usually tell you whether it has already been considered and rejected, and why.

## Getting set up

You need a `lua` interpreter (5.3 or 5.4) and Python 3 for the test runner. The Python build tests (`build/test_*.py`) need **pytest** — `pip install pytest`. Without it those fail; everything else runs.

`run_tests.py` is the runner to use. `run_tests.sh` beside it is a serial fallback for a machine with no Python: it runs the same Lua tests and skips the Python ones.

### One command for everything: `tos.py`

The individual tools live in different directories and different runtimes. `tos.py` finds them, runs them from the right place, and prints exactly what it ran — so you can learn the underlying commands, and reproduce a failure without it:

```
python tos.py test [--serial]     the whole suite
python tos.py build               strip the source into ../TOS-Release
python tos.py pack [--sign]       build the add-on disks + repo index
python tos.py sign <dir>|--all    sign package manifests in place
python tos.py key                 print the public key you sign as
python tos.py check               fast drift checks, without the full suite
python tos.py selftest            build, then run the boot battery on a real machine
python tos.py roadmap             regenerate the queue and ROADMAP.md
```

Every path resolves from the script, not from your shell, so it works from any directory. `check` is the one worth knowing: it runs only the checks that catch a *generated* file drifting from its source — release digests, manifest completeness, release excludes, the add-on repo index — which is the mistake this project makes most often.

`roadmap` is maintainer-only and says so; the notes it reads are not published.

```bash
git clone --branch dev https://github.com/Evan450/TOS-Terminal-Operating-System-.git
cd TOS-Terminal-Operating-System-
python run_tests.py
```

The suite is a couple of hundred files of pure Lua plus a few Python build tests. It touches no GPU and needs no Minecraft — everything runs off-box against fakes. It should be green before you start and green when you finish.

One clone gives you everything: the OS in `tos/`, and the add-on source in `TOS-Extras/`. **`FAIL=0` is the contract, not any particular pass count** — the runner prints its own totals, and a number written down here only tells you how long ago someone edited this file. If it is red before you have changed anything, that is a bug in the tree and worth reporting on its own.

### Testing on a real machine

The suite runs against fakes. Two tools boot TOS on a real OpenComputers machine instead: Ocelot Brain, the machine inside Ocelot Desktop's jar, with no window.

- `python tos.py selftest` builds, boots a fresh machine and runs the boot self-test battery. Exit 0 means every check passed.
- `python build/headless-session.py SCRIPT` types at the keyboard and reads the screen back. A script is lines like `firstboot`, `type ls\n`, `wait 30 root@` and `snap after-ls`; `--help` lists them all.

Both need Ocelot Desktop's jar and a JDK (version 9 or later).

To try your change in the game instead, install it over the network onto a bare OpenOS machine with an internet card, pointing the bootstrap at your branch:

```
bootstrap.lua <your-fork> dev
```

> **Windows note.** Clone somewhere short, like `C:\src\tos`. Some package paths run to ~255 characters, and Windows' 260-character `MAX_PATH` will make the disk builder fail on a write with a path that *looks* fine.

## Where things live

| Path | What is there |
|---|---|
| `bios.lua`, `init.lua` | The BIOS (4 KiB EEPROM) and the boot loader that builds `require` |
| `install.lua`, `bootstrap.lua` | The installer, and the network bootstrap that fetches a release and hands off to it |
| `tos/kernel/` | The kernel: users, `securefs`, the scheduler, packages, crypto, display. [`docs/API.md`](docs/API.md) lists every module and public function |
| `tos/kernel/net/` | Networking: trust, the mesh, file transfer, remote execution |
| `tos/shell/` | The two shells: the panels interface (`panels/`) and the command line (`cli.lua`), plus login, the tour and the package picker |
| `tos/shell/panels/commands/` | The commands, in three groups: `core`, `admin`, `extras` |
| `tos/compat/` | The OpenOS library shims |
| `tos/peripheral/` | Redstone, robots, inventories |
| `tos/system_manifest.lua` | Every file a release installs: the list `deploy`, `verify` and the installer read |
| `etc/rc.d/`, `usr/bin/`, `usr/man/`, `usr/lang/` | Startup services, user programs, man pages, language catalogues |
| `usr/lib/tests/` | The test suite (not shipped) |
| `build/` | Release tooling, generators and the headless machine (not shipped) |
| `TOS-Extras/` | The add-ons, and the tools that build their disks |

Every source file starts with a comment saying what it is for.

## Writing an add-on

Add-ons live under `TOS-Extras/`, install through `pkg`, and run in the capability sandbox. A package is a directory with a `package.lua` manifest and the files it installs:

```
TOS-Extras/modules/mything/
  package.lua          the manifest: name, version, kind, files, capabilities
                       (and lua = "5.4" / tos = ">=1.5.0" if it needs them: MANUAL 7.3)
  init.lua             your code
  test_mything.lua     picked up automatically by run_tests.py
```

Build the pick-and-choose disks, which also computes each file's SHA-256 into the manifest:

```bash
cd TOS-Extras
lua build/build-disk.lua
lua build/test_manifests.lua      # manifest lint: capability and shape errors
```

`test_manifests.lua` catches the mistakes that are otherwise silent: `commands` declared as an array instead of a name→path map (which `pkg.commands` drops without a word), sandboxed code using `crypto` or `vault` without declaring the capability, declaring a capability the sandbox will not grant, a `kind = "service"` package with no `/etc/rc.d/<name>.lua`, and a manifest `pkg` cannot read.

Three rules the tooling enforces rather than trusts:

- **A manifest is data, not code.** `pkg` never runs `package.lua`: it decodes it with the kernel's data-only reader, so a manifest may hold literals and nothing else. No `..` to split a long description, no variables, no function calls. Lua itself runs such a file without complaint, which is why `build-disk.lua` checks with the kernel's reader too and refuses the manifest, naming the line.

- **Below 1.0.0 does not ship.** `build-disk.lua`'s `SKIP` table holds pre-1.0 packages off the public pack, and the tests fail if one rejoins. An unfinished add-on that installs cleanly is worse than one nobody can reach.
- **Hashes are not optional.** `pkg.install` refuses a package whose manifest does not declare a SHA-256 for every file, unless the operator explicitly passes `--allow-unverified`. The builder writes them; you should never have to.

## Signing a package

`pkg` verifies Ed25519 publisher signatures, and an operator can refuse anything unsigned. Most contributors never sign anything: the maintainer signs the Optional Utilities pack. If you publish packages of your own, read [docs/SIGNING.md](docs/SIGNING.md) first. Your passphrase is your private key, and losing it means starting again with a new identity.

## Making a change

1. **Read before you edit.** Grep for every caller of a function you are changing. Kernel modules are wired together in `tos/kernel/init.lua`, and the panels shell dispatches through a command registry — changing a signature in one place usually means several.
2. **Add a test.** `usr/lib/tests/test_*.lua` is auto-discovered by `run_tests.py`. Follow the existing shape: a `test(name, cond)` helper, prints `PASS`/`FAIL`, returns false if anything failed. If the thing you fixed had no coverage, a regression test for it is the most valuable part of the PR.
3. **Run the suite.** `python run_tests.py`. Report the result in the PR — do not claim a fix works if you have not run it. If the change is about what a real machine does (boot, drawing, the keyboard, rebooting), also run `python tos.py selftest` or a headless session.
4. **Keep the manifest honest.** If you add a runtime file under `/tos`, `/etc/rc.d`, `/usr/bin` or `/usr/modules`, add it to `tos/system_manifest.lua` as well. `test_manifest_completeness.lua` enforces this — a file missing from the manifest is silently absent from every fresh install and invisible to `verify`.
5. **Update the docs in the same commit.** Version bumps touch `README.md`, `CHANGELOG.md`, and any version constant together. Documentation that contradicts the code is worse than none. If you add or rename a heading in `MANUAL.md`, run `python build/make_manual_toc.py`; the suite fails while its contents list is stale. In `CHANGELOG.md`, a change goes under `## Unreleased`, in the newest round (a `###` section); a new round also gets a line in the list at the top of `Unreleased`. Releases before v1.5.0 live in `docs/CHANGELOG-ARCHIVE.md`.
6. **Regenerate the API reference** with `python build/make_apiref.py` when you add or change a public kernel function (`function mod.name(` at the top level of a file in `tos/kernel/`) or the `---` comment above it. It rewrites `docs/API.md`, and the suite fails while that is stale.
   - A function that refuses callers below ADMIN (one that calls an admin gate such as `adminGate`) carries `--- @tier admin` in that comment. `build/test_apiref.py` fails on a gate without the mark, or a mark without the gate.

## Comment conventions

The comment markers are load-bearing — `strip.lua` reads them:

| Marker | Meaning | Survives into `main`? |
|---|---|---|
| `--!` | Security note, cross-file invariant, license header | **Yes** |
| `--` | Ordinary explanation, rationale, dev notes | No |

Use `--!` for anything a future reader must not lose: why a check exists, what attack it stops, what invariant another file depends on. Use plain `--` for everything else. Block comments follow the same rule (`--[[!` keeps, `--[[` drops).

Mark security-relevant code with a `#SEC` tag and the finding ID where one exists, matching the existing style.

## Writing for a small machine

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
