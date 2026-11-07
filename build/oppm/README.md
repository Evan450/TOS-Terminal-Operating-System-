# The `master` branch (OPPM discovery)

OPPM — the package manager most OpenComputers players already have — reads a repository's index from **exactly one place**:

```
https://raw.githubusercontent.com/<owner>/<repo>/master/programs.cfg
```

The branch name is hardcoded in `oppm.lua`. TOS's branches are `main`, `dev` and `optional-utilities`, so `oppm register Evan450/TOS-Terminal-Operating-System-` finds nothing and fails quietly. This directory is the fix: a `master` branch whose only job is to be findable.

There is no TOS source on that branch and there should never be. The package installs the **network bootstrap** of the current release, which then downloads the rest of that release from `main`.

## Assembling the branch

```
git switch --orphan master
git rm -rf .                                   # nothing from another branch
cp <tos-source>/build/oppm/programs.cfg      programs.cfg
cp <tos-source>/build/oppm/branch-README.md  README.md
cp <tos-source>/LICENSE.txt                  LICENSE.txt
git add programs.cfg README.md LICENSE.txt
git commit -m "OPPM index so oppm can find TOS"
git push -u origin master
```

Nothing on the branch changes when a release does. `test_oppm_index.lua` pins everything about the index that can be checked without the network.

## Why the key names `main`

```lua
files = { ["main/bootstrap.lua"] = "/bin" }
```

The `main/` prefix is the **branch segment of the raw URL**, not a directory called `main` — OPPM fetches `raw.githubusercontent.com/<repo>/<key>` (`oppm.lua`, `installPackage`). So the key resolves to `bootstrap.lua` *on the main branch*: the release build's bootstrap, the same file the README's `wget` one-liner fetches.

Until 2026-11-07 the key was `master/tos/bootstrap.lua`, a copy of the bootstrap kept on this branch, and the copy went stale. It was the source file of 2026-09-07, from before releases were signed, so `oppm install tos` installed TOS without checking the publisher's signature while the `wget` route checked it. A copy on a branch nothing builds is a copy nobody refreshes. Copying today's source file would not do either: only a release build's bootstrap carries the digests of the verifier files it downloads, and a source copy refuses the official release for want of them. So `main`'s file is the only one that can be offered here, and naming it means there is nothing to keep in step.

The value is a destination **directory**, and OPPM's prefix is `/usr`, so `/bin` installs to `/usr/bin` — which is on OpenOS's `PATH`. That is why the OPPM route needs no absolute path, while the `wget` one-liner does.

`bootstrap.lua` deliberately does **not** delete itself when it is installed here: it reclaims itself only from the filesystem root, because a copy under `/usr/bin` is one OPPM owns and has a record of. See `selfPathToReclaim` in `bootstrap.lua` and the cases in `test_install_bootstrap.lua`.

## Getting listed in `oppm list`

Registering the repo locally (`oppm register <owner>/<repo>`) works as soon as the branch exists. Appearing in the default `oppm list` for everyone else is a separate step: a pull request adding the repo to [`OpenPrograms/openprograms.github.io`](https://github.com/OpenPrograms/openprograms.github.io)'s `repos.cfg`.
