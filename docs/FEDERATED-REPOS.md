# Federated package repos — design (2026-09-27)

**Status:** agreed in a design interview on 2026-09-27. **Slice 1 is built** (2026-09-27, off-box tests only — not yet seen in-world); slices 2–4 are design only. Every claim about the code below was checked by driving the real modules off-box, not by reading them — the probes are described where each finding is.

## The idea

Any package can optionally say *"here's my repo"*: where it comes from, where its dependencies can be found, and which sibling packages it vouches for. It is Windows' "bring your own dependencies" crossed with Linux's one package manager — except the only thing that spreads is the list of **repos**, so discovery grows by itself while the package manager stays single and unified.

The motivating problem is conflicts. Once more than one source can offer a package called `libX`, the package manager needs a way to know *which* `libX` a package meant. The answer here is that a package's identity is its name **plus the key that signs it**, and every repo is just a mirror. Nothing in this design is mandatory: a package that says nothing about repos behaves exactly as it does today.

## What exists today

`kernel.pkgremote` fetches OPPM-shaped repos (`programs.cfg` at the root) over an internet card. Its header states four rules; the first is *"HOST ALLOWLIST … There is no default repo, no discovery, and no way for an index to introduce another host."* **This design deliberately revises that rule** (see *Trust*): hosts stop carrying trust, signatures carry all of it, and a repo nobody configured can be a mirror but never an authority. Rules 2–4 (vetted paths, bounds, disposable staging) stand unchanged.

The signing machinery the design leans on is already in the tree: Ed25519 `package.sig` beside `package.lua`, a publisher trust store (`/etc/pkg_trust.cfg`, `pkg trust add`), `pkg trust require on`, and the verdict (`trusted` / `unknown` / `unsigned`, plus a hard-refused `invalid`) recorded on every installed manifest as `_sigState` / `_sigKey`. Version constraints (`>=`, `^1.2`, `~1.2.3`) and the table form of `requires` (`{ name=, version=, optional= }`) exist too.

### Findings (verified 2026-09-27)

These were bugs in `pkg` as it stood, found while scoping the design. Findings 1–4 and 7 are fixed by slice 1; 5 and 6 wait for slice 2.

1. **A dependency on another disk never resolves.** `pkg.installByName`'s doc comment says it "resolves deps across all available sources"; `installWithDeps` is handed a single root and looks nowhere else. Probe: `app` on root `/x/a` requires `lib` on root `/x/b` — `pkg.findInRepos("lib")` finds `/x/b/lib`, and `pkg.installByName("app")` fails `resolve failed: unknown package: lib`.
2. **`pkg upgrade` can change who publishes a package.** Probe: `libx 1.0.0` signed by a trusted key (`_sigState = trusted`) upgraded to a `9.9.9` signed by a stranger — accepted, now `unknown`; then to an unsigned `9.9.10` — accepted, now `unsigned`. No refusal and no prompt. `upgrade` picks its candidate with `findInRepos`, which is first-match by name.
3. **`pkg upgrade` checks the signature only after deleting the old version.** It runs the hash, licence, conflict, validation, service and protected-path gates before `uninstall`, but not the signature gate, which only `install` runs. Probe: a trusted `libx 1.0.0`, upgraded to a `2.0.0` whose manifest was edited after signing — `upgrade FAILED after removing libx: … its signature does not verify` — and `libx` is no longer installed at all.
4. **Version constraints are checked after the files are written, as a warning.** `resolveInstallOrder` skips an installed dependency whatever its version, and the only constraint check is `checkRequires` after install (`"Unmet constraints don't fail the install"`). `upgrade` never checks whether the new version breaks an installed package that depends on it.
5. **`pkg fetch` never fetches dependencies.** `installRemote` fetches one package and installs it; its `requires` are left unmet.
6. **An OPPM index signed as a whole loses its signature through `pkg fetch`.** `pkgremote.fetch` stages a *re-encoded* one-package `programs.cfg` and never downloads `programs.sig`. Probe: a `programs.cfg` + `programs.sig` pair signed by a trusted key installs as `unsigned`. TOS's own index format is not affected — Optional Utilities ships each package's `package.lua` and `package.sig` as files, and the same probe in that layout records `trusted`.
7. **An optional requirement that no source has blocked the install.** `resolveInstallOrder` ignored `optional = true` and failed `resolve failed: unknown package`. Found while writing slice 1's tests; reproduced on the code from before it.

## Decisions

### Identity

- **A package is name + publisher key.** `libX` signed by key A and `libX` signed by key B are different packages, whatever repo either one came from.
- **Layered signatures.** The publisher signs the package (`package.sig`); a repo may also sign its index (`programs.sig`). A package from a signed index *and* a trusted publisher ranks highest; the publisher signature is the one identity rests on.
- **Pins first, namespaces later.** A dependency can pin the publisher it means (below). Namespaced names (`publisher/libX`) are the long-term form, but they break every existing manifest and OPPM's flat names, so they come last.

### Where "here's my repo" lives

All three places, each with its own meaning:

| Field | Meaning |
|---|---|
| `repos` on the manifest | Repos that carry **this** package — its mirrors and its update source. |
| `repos` on a `requires` entry | Where to find **that dependency**. |
| `recommends` entries in table form | Sibling packages this one **vouches for**. Still soft: never installed behind the operator's back. |
| `siblings` in a repo index | Repos this repo vouches for. What an opt-in crawl follows. |

### What counts as a repo

Anything `pkg` can read — an HTTP(S) URL, an in-world server on the modem network, removable media — but they are not equal (see *Trust*). A floppy can never be re-read to check for news; a URL can.

### Trust: two questions, not one scale

The interview's "chain of how trustworthy it is" separates into two independent questions:

- **Is it authentic?** Only a signature answers this. A package signed by a trusted key is fully authentic even off a floppy nobody can re-check.
- **Is it current?** Re-checkable sources and **consensus across repos** answer this. A signature does not stop a hostile mirror serving an *old*, validly signed version (one with a known hole); several independent repos agreeing on the newest version does. Consensus does **not** prove authenticity — one person can run five mirrors.

Signals that raise trust: signed by a trusted key; re-checkable source; consensus across repos. **"An admin added this repo" is not a trust signal on its own.** The consequence is deliberate: the signature now carries everything the host allowlist used to.

### The floor (default; the operator chooses how strict)

| The package is… | Default behaviour |
|---|---|
| Signed by a trusted key | Installs normally. The admin gate still applies; a `service` still needs root. |
| Signed by an unknown key | Shown once — fingerprint, where it was seen, how current it looks — and the admin pins the key (trust on first use, like SSH). **Never for `service` or `driver` kinds**, which run outside the sandbox: those need an explicit `pkg trust add`. |
| Unsigned | Visible in search. Installable only from a repo an admin added, with `--allow-unverified`, as today. **Never pulled in automatically as a dependency from a discovered repo** — it has no key, so nothing can pin it and identity has nothing to resolve against. |

The operator can tighten this (no trust-on-first-use at all; `pkg trust require on` already exists at the strict end) or loosen it. The knob's exact shape is slice 2.

### Discovery

- **Default: learn on install.** Installing a package records the repos it names as *known* — not trusted. Growth follows what the operator actually uses.
- **Opt-in: bounded crawl.** An explicit command follows index `siblings` a bounded number of hops, with caps on repos and bytes, because these are 192 KB machines with 2 MB disks.
- Sharing known repos between machines over the mesh is later, if at all.

### Conflicts and contradictions

All four kinds are in scope:

1. **Version ranges** — A needs `libX >=2`, B needs `libX <2`.
2. **Repos disagree** — two repos serve `libX 1.4` with different bytes.
3. **Package vs repo claims** — a package says it lives at repo R; R does not carry it, or carries a copy signed by someone else.
4. **Manifest vs installed state** — what an update wants does not match what is installed (orphaned or vanished dependencies).

Every transaction (install, upgrade, rollback) works out its whole plan **before writing a byte**, and reports contradictions in the order the plan meets them. When more than one resolution exists, the winner is decided in this order:

1. one shared copy satisfies everyone;
2. higher trust;
3. newer version;
4. less disk.

A tie after all four means **ask**. When no single shared copy can satisfy everyone, the Windows-style fallback is a **private copy** of the dependency for the package that needs the other version.

### Revocation and rotation

A publisher posts a signed notice to its repos: *key X is retired (or compromised); its successor is Y*. Re-checkable sources spread it — one more reason they rank higher. Two rules keep this from becoming an attack of its own:

- **A revocation is always honoured automatically.** The worst a forged one can do is stop updates, which is loud and recoverable.
- **A successor is never trusted automatically.** A stolen key can sign a "rotation" to the thief's key just as easily as the real owner can. The successor goes through the floor like any unknown key.

## Manifest format

```lua
return {
  name = "mail-client", version = "2.1.0", kind = "command",
  -- Repos that carry this package (slice 2 reads it).
  repos = { "https://example.com/oc/master" },
  requires = {
    "tape-storage >=1.0",                          -- unchanged string form
    { name = "libgui", version = "^3.0",
      -- The publisher meant. 64 hex: the full Ed25519 public key, not the
      -- 16-hex fingerprint -- a pin is read by a machine, and truncating
      -- it only makes it cheaper to collide.
      key = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
      repos = { "https://gui.example/oc" },        -- slice 2 reads it
    },
  },
  recommends = {
    "calc",                                         -- unchanged string form
    { name = "mail-filters", key = "…", repos = { "…" } },   -- slice 2
  },
  -- files, hashes, capabilities, … unchanged
}
```

A pin only ever **narrows** what is acceptable. It never makes an untrusted key trusted and never relaxes `pkg trust require on`: a pinned dependency still goes through every gate an unpinned one does, and additionally has to be signed by exactly that key.

## Slices

### Slice 1 — identity, cross-source dependencies, contradiction detection

**Built 2026-09-27**, one commit per item: `bf472c2` (cross-source), `f3f958d` (signature before removal), `6a448fe` (upgrades keep their publisher), `dc11da1` (pins and `pkg.plan`), `0cc13ce` (version contradictions), `f87ff17` (finding 7). Tests: `test_pkg_cross_source`, `test_pkg_upgrade_identity`, `test_pkg_pins`, `test_pkg_plan`, `test_pkg_optional_requires` — each fails on the code before its commit.

Local sources only (the built-in repo roots, mounted media, `extraRoots`). No network behaviour changes.

- **Dependencies resolve across every source.** The target's own root is searched first, so a self-contained disk behaves exactly as before; then every other root. The H-20 rule (directory name must equal manifest name) applies to every candidate. Fixes finding 1.
- **`key` pins on `requires`.** Validated as 64 hex. When choosing a candidate for a pinned dependency, candidates signed by another key (or unsigned) are skipped, so an impostor on an earlier disk cannot win by being found first. Selection reads the key the signature file *claims* (cheap, no curve arithmetic); **enforcement** is in `pkg.install`, which refuses unless its own verified verdict carries exactly the pinned key. An already-installed dependency is checked against the key recorded when it was installed.
- **Upgrades keep their publisher.** A package installed signed by key K upgrades only to a candidate verified as signed by K. Unsigned or another key is refused, with `--force` as the override (a real key change is what slice 4's rotation notices are for). An installed *unsigned* package may upgrade to a signed one — gaining a signature is fine. Fixes finding 2.
- **Upgrades verify the signature before removing anything.** The signature gate joins the gates `upgrade` already runs up front. Fixes finding 3.
- **A plan before a byte.** `pkg.plan(repoDir, name, opts)` returns the install order, the copy chosen for each package, the key each pinned one must verify as, and every contradiction it finds, with no side effects: a dependency whose available or installed version fails a constraint; two requirers whose constraints no single version meets; two pins that disagree; an installed dependency whose publisher is not the one pinned; a package going in that an installed one needs at another version or from another publisher. It also validates every manifest it would install. `installWithDeps` refuses a plan with contradictions, naming who needs what, unless forced; a copy that meets a constraint is preferred over one that does not. `upgrade` runs the same checks and refuses only contradictions it would *introduce*. Fixes finding 4.

**Limits, left for later slices.** The first requirement to reach a package decides which copy is chosen; a later one that wants a different copy is reported, not re-resolved (re-choosing is slice 3's resolution). An optional package that is found but cannot itself be installed still fails the install. The shell's `pkg install` has no `--force` yet, so a contradiction refusal can only be overridden through the API; `pkg upgrade --force` works. `pkg install --dry-run` does not yet print the plan's contradictions.

### Slice 2 — remote

`pkg fetch` resolves dependencies across configured repos; the manifest and per-dependency `repos` hints are used, under the floor; trust on first use; the operator's strictness knob; a known-repos store separate from the admin allowlist; fix finding 6 by staging the raw index and its `programs.sig`.

### Slice 3 — resolution

The four-step winner order; upgrading a shared dependency when that is the winning resolution; private copies; consensus and freshness checks across mirrors; update checks against a package's own `repos`.

### Slice 4 — discovery and revocation

The opt-in crawl over index `siblings`; revocation and rotation notices; in-world repos over the modem network; namespaced names.

## Open questions

- **Private copies:** where they live (`/usr/lib/<pkg>/deps/`?) and how `require` inside the sandbox finds the right copy for the right package.
- **In-world repos:** the wire protocol, and whether a server on the mesh counts as re-checkable.
- **Crawl budget:** hop, repo and byte caps that a Tier 1 machine can afford.
- **Signature cost:** an upgrade of a signed package now verifies twice (before the old version is removed, and again at install against the bytes install actually read). Ed25519 verification on a T1 machine has never been timed (`ROADMAP.md`, *TIME IT*).
- **CCTOS:** whether the port gets the same model.
