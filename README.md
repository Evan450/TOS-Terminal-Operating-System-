# TOS — the `master` branch

**There is no TOS source here.** This branch exists so that OPPM can find the
project, and holds two useful files and nothing else.

OPPM reads a repository's package index from exactly one place:

```
https://raw.githubusercontent.com/<owner>/<repo>/master/programs.cfg
```

The branch name is hardcoded in `oppm.lua`. TOS's real branches are `main`,
`dev` and `optional-utilities`, so without this stub `oppm register` on this
repo finds nothing and fails quietly.

## Install with OPPM

```
oppm register Evan450/TOS-Terminal-Operating-System-
oppm install tos
bootstrap
```

That installs the **network bootstrap** to `/usr/bin`, which then downloads the
real release (~1.5 MB) from the `main` branch. You need an Internet Card, a
Tier 2 disk, OpenComputers 1.7.5+, and a CPU on the Lua 5.3 or 5.4
architecture.

No OPPM? One line does the same thing:

```
wget -f https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/main/bootstrap.lua /bootstrap.lua && /bootstrap.lua
```

## Where everything actually is

| Branch | What it is |
|---|---|
| [`main`](../../tree/main) | The release build — what the bootstrap downloads. |
| [`dev`](../../tree/dev) | The source tree, the tests, the docs. **Start here**, and open pull requests here. |
| [`optional-utilities`](../../tree/optional-utilities) | The signed add-on pack, laid out as a `pkg` repository. |
| `master` | This. An index, a bootstrap, and a license. |
