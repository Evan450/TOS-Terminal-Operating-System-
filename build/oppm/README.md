# The `master` branch (OPPM discovery)

OPPM — the package manager most OpenComputers players already have — reads a
repository's index from **exactly one place**:

```
https://raw.githubusercontent.com/<owner>/<repo>/master/programs.cfg
```

The branch name is hardcoded in `oppm.lua`. TOS's branches are `main`, `dev`
and `optional-utilities`, so `oppm register Evan450/TOS-Terminal-Operating-System-`
finds nothing and fails quietly. This directory is the fix: a two-file `master`
branch whose only job is to be findable.

There is no TOS source on that branch and there should never be. The package
installs the **network bootstrap**, which then downloads the real release from
`main`.

## Assembling the branch

```
git switch --orphan master
git rm -rf .                                   # nothing from another branch
mkdir tos
cp <TOS-Dev>/build/oppm/programs.cfg  programs.cfg
cp <TOS-Dev>/bootstrap.lua            tos/bootstrap.lua
git add programs.cfg tos/bootstrap.lua
git commit -m "OPPM index so oppm can find TOS"
git push -u origin master
```

`bootstrap.lua` is **copied, not linked** — git has no cross-branch symlink —
so a change to `bootstrap.lua` means refreshing this branch. It changes rarely;
`test_oppm_index.lua` pins everything about the index that can be checked
without the network.

## Why the keys look like that

```lua
files = { ["master/tos/bootstrap.lua"] = "/bin" }
```

The `master/` prefix is the **branch segment of the raw URL**, not a directory
called `master` — OPPM fetches `raw.githubusercontent.com/<repo>/<key>`. So the
key above resolves to `tos/bootstrap.lua` *on the master branch*.

The value is a destination **directory**, and OPPM's prefix is `/usr`, so
`/bin` installs to `/usr/bin` — which is on OpenOS's `PATH`. That is why the
OPPM route needs no absolute path, while the `wget` one-liner does.

`bootstrap.lua` deliberately does **not** delete itself when it is installed
here: it reclaims itself only from the filesystem root, because a copy under
`/usr/bin` is one OPPM owns and has a record of. See `selfPathToReclaim` in
`bootstrap.lua` and the cases in `test_install_bootstrap.lua`.

## Getting listed in `oppm list`

Registering the repo locally (`oppm register <owner>/<repo>`) works as soon as
the branch exists. Appearing in the default `oppm list` for everyone else is a
separate step: a pull request adding the repo to
[`OpenPrograms/openprograms.github.io`](https://github.com/OpenPrograms/openprograms.github.io)'s
`repos.cfg`.
