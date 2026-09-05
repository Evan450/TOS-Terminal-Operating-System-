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

You need a `lua` interpreter (5.3 or 5.4) and Python 3 for the test runner. One Python test (`build/test_sync_emulator.py`) needs **pytest** — `pip install pytest`. Without it that single test fails; everything else runs.

### One command for everything: `tos.py`

The individual tools live in different directories and different runtimes. `tos.py` finds them, runs them from the right place, and prints exactly what it ran — so you can learn the underlying commands, and reproduce a failure without it:

```
python tos.py test [--serial]     the whole suite
python tos.py build               strip TOS-Dev -> TOS-Release
python tos.py pack [--sign]       build the add-on disks + repo index
python tos.py sign <dir>|--all    sign package manifests in place
python tos.py key                 print the public key you sign as
python tos.py check               fast drift checks, without the full suite
python tos.py roadmap             regenerate the queue and ROADMAP.md
```

Every path resolves from the script, not from your shell, so it works from any directory. `check` is the one worth knowing: it runs only the checks that catch a *generated* file drifting from its source — release digests, manifest completeness, release excludes, the add-on repo index — which is the mistake this project makes most often.

`roadmap` is maintainer-only and says so; the notes it reads are not published.

```bash
git clone --branch dev https://github.com/Evan450/TOS-Terminal-Operating-System-.git
cd TOS-Terminal-Operating-System-
python run_tests.py
```

The suite is ~185 files of pure Lua plus a few Python build tests. It touches no GPU and needs no Minecraft — everything runs off-box against fakes. It should be green before you start and green when you finish.

One clone gives you everything: the OS in `tos/`, and the add-on source in `TOS-Extras/`. The full suite should be green — roughly `PASS=187 FAIL=0`.

> **Windows note.** Clone somewhere short, like `C:\src\tos`. Some package paths run to ~255 characters, and Windows' 260-character `MAX_PATH` will make the disk builder fail on a write with a path that *looks* fine.

## Writing an add-on

Add-ons live under `TOS-Extras/`, install through `pkg`, and run in the capability sandbox. A package is a directory with a `package.lua` manifest and the files it installs:

```
TOS-Extras/modules/mything/
  package.lua          the manifest: name, version, kind, files, capabilities
  init.lua             your code
  test_mything.lua     picked up automatically by run_tests.py
```

Build the pick-and-choose disks, which also computes each file's SHA-256 into the manifest:

```bash
cd TOS-Extras
lua build/build-disk.lua
lua build/test_manifests.lua      # manifest lint: capability and shape errors
```

`test_manifests.lua` catches the mistakes that are otherwise silent: `commands` declared as an array instead of a name→path map (which `pkg.commands` drops without a word), sandboxed code using `crypto` or `vault` without declaring the capability, declaring a capability the sandbox will not grant, and a `kind = "service"` package with no `/etc/rc.d/<name>.lua`.

Two rules the tooling enforces rather than trusts:

- **Below 1.0.0 does not ship.** `build-disk.lua`'s `SKIP` table holds pre-1.0 packages off the public pack, and the tests fail if one rejoins. An unfinished add-on that installs cleanly is worse than one nobody can reach.
- **Hashes are not optional.** `pkg.install` refuses a package whose manifest does not declare a SHA-256 for every file, unless the operator explicitly passes `--allow-unverified`. The builder writes them; you should never have to.

## Signing a package

`pkg` supports Ed25519 publisher signatures. An operator adds your public key once (`pkg trust add <label> <key>`), and from then on your packages verify as yours — and with `pkg trust require on` they can refuse anything unsigned.

The passphrase **is** the private key — the key is derived from it, not stored — so it is never a command-line flag. `tos.py` prompts for it without echoing, or reads `TOS_SIGNING_PASSPHRASE` if you have already exported it:

```
python tos.py key                      print your public key; signs nothing
python tos.py pack --sign              build a signed pack  <- to PUBLISH
python tos.py sign modules/mything     sign one source package, in place
python tos.py sign --all               every discovered source package
```

**`pack --sign` is the one that publishes.** The other two sign the *source* manifests, which is what you want when handing someone a package directory to `pkg install` directly — but those signatures never reach the pack and cannot. The disk builder rewrites every manifest as it assembles, injecting the `hashes` block, so the shipped bytes differ from the source bytes; a signature over the source verifies as **invalid** against the shipped copy. `--sign` therefore signs the assembled manifests itself and ignores anything signed in the source tree.

It must be at least 20 characters and use at least 10 distinct ones. **Generate it; do not invent one.** The key is derived by SHA-512 over `TOS-pkg-signing-key-v2`, your publisher label, and the passphrase, iterated 4096 times. That is deliberately cheap — it has to run on a 192 KB machine sharing one CPU — and cheap means *the passphrase's own entropy is the whole defence*. A KDF that could genuinely protect a memorable phrase needs on the order of 10⁵–10⁶ rounds, which is not reachable here, so the length floor is enforced rather than advised. Whoever recovers your passphrase signs as you.

**Your publisher label is part of your key.** It salts the derivation, so the same passphrase under `acme` and under `Acme Corp` are two different identities with two different public keys. Pick one label and keep using it. Case and surrounding whitespace are normalised (`Discover` and `discover` agree); anything else does not. The label is public — it is printed in the repo README beside the key — so unlike the passphrase it is fine on a command line.

What the salt does and does not buy: it means one precomputed passphrase→key table cannot yield every publisher's key at once, so each identity has to be attacked separately. It adds no secrecy of its own and does nothing against someone targeting you specifically.

Generate and store it in a password manager **before** you sign. It is never written to disk, so there is no keyfile to back up — the passphrase is the only copy. Lose it and every operator who trusted your key has to re-trust a new one.

```bash
# a generated passphrase, never typed from memory
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

Signing a package writes `package.sig` beside its `package.lua`. To ship, run `tos.py pack --sign` — which signs `dist/` itself, as above, rather than carrying anything across from the source tree.

`programs.cfg` advertises each `package.sig`, so signatures travel over `pkg fetch` as well as on a floppy. That matters: `pkgremote` downloads only what the index lists, so an unadvertised signature means a package that is signed on the disk and arrives **unsigned** over the network — and with `pkg trust require on`, that is the difference between installing and being refused.

To publish the key people should trust, print it without signing anything. On a TOS machine:

```
pkg trust key <publisher-label>       prints the public key you sign as
pkg sign <directory> --as <name>      signs a package tree on-box
```

Both ask for the passphrase without echoing it. The argument is your *label*, which is public; the passphrase is never accepted on a command line, because the line is echoed as you type it and stays in the recall buffer for anyone at that seat. `--as` is required for the same reason it is required off-box: it salts the key, so signing without it would quietly produce a different identity.

Publish the key it prints; never the passphrase.

Lose the passphrase and you lose the identity: there is no recovery, and the only remedy is to publish a new key and ask people to re-trust it. Use something long, keep it somewhere you would keep a password, and do not reuse it.

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
