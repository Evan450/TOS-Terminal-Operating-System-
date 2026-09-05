# Optional Utilities — disk builder & installer

The **Optional Utilities** disk is TOS's pick-and-choose add-on installer,
modeled on the MS-DOS 6.22 Supplemental Utilities Disk: insert it on a TOS
machine, tick the add-ons you want, and it installs the selected set.

## Pieces

| File | Role |
|------|------|
| `build-disk.lua` | **Assembler.** Auto-discovers every add-on with a `package.lua` under `modules/`, `cluster/`, and `rbmk/`, assembles them into one or more `pkg` repos laid out the way `kernel.pkg.install` expects, and copies the installer onto each. Splits across multiple disks when the set exceeds `--limit`. Runs anywhere: dev box with LuaFileSystem, plain Lua (shell fallbacks), or under OpenOS. |
| `build-disk.ps1` / `build-disk.cmd` / `build-disk.sh` | **One-command wrappers** (PowerShell / cmd.exe / POSIX). Build with defaults; forward extra flags like `--install`. **Use the one matching your shell** — invoking the `.cmd` *from PowerShell* emits harmless stray `'M' is not recognized` lines before the correct output, which the `.ps1` avoids by calling `lua` directly. Install **LuaFileSystem** (`luarocks install luafilesystem`) for a subprocess-free build: the assembler prefers it for every mkdir/rmdir/listing and only shells out without it, and shell-outs are where cross-shell quoting gremlins come from. |
| `optutil-set.lua` (generated) | **Set manifest**, written onto every disk. Describes the WHOLE set — each package's version, category, description, `requires`, `recommends`, and which disk it is on. The picker reads it so a machine with one floppy in the drive still lists everything and can ask for the right disk; the media detector uses it to tell an Optional Utilities disk from a loose pile of packages. There is **no installer on the disk**: the picker lives in the TOS base image at `tos/shell/pkgpicker.lua` and is reached with `pkg install`. |
| `test_build_disk.lua` | Off-box regression test for the assembler (`lua build/test_build_disk.lua` from the Extras root). |
| `test_manifests.lua` | Lint for source `package.lua` manifests (`lua build/test_manifests.lua` from the Extras root). Guards against real regressions found in review: `commands` declared as an array instead of a name→path map (silently dropped by `pkg.commands`), sandboxed command code using `crypto`/`vault` without declaring the capability, declared capabilities the sandbox doesn't actually grant, and `kind="service"` packages missing their `/etc/rc.d/<name>.lua`. |

## Build

Requires a `lua` interpreter on PATH (e.g. `winget install DEVCOM.Lua`) —
`build-disk.cmd`/`build-disk.sh` hard-fail with an install hint if one
isn't found.

One command:

```
TOS-Extras\build\build-disk.cmd            (Windows)
TOS-Extras/build/build-disk.sh             (POSIX)
```

or directly:

```
lua build/build-disk.lua [<extras-root>] [<out-dir>]
                         [--install <dir>] [--limit <n>[K|M]|0] [--overhead <bytes>]
                         [--sign]
```

### `--sign` — publisher signatures

Signs every emitted manifest with an Ed25519 key, writing `package.sig`
beside each `package.lua`. Recipients trust the key once with
`pkg trust add <name> <key>` and everything from that key then installs
without a fresh judgement call. See MANUAL §7.5a.

```bash
TOS_SIGNING_PASSPHRASE='a long signing passphrase' TOS_SIGNING_NAME='Me' lua build/build-disk.lua --sign
```

Two things about that command line are deliberate:

- **The passphrase comes from the environment, never a flag.** Argv lands in
  shell history, which is a file, which is the one place a signing key must
  never be. The passphrase *is* the private key — the same passphrase always
  derives the same key, on any machine, which is what lets you sign from two
  computers.
- **Signing happens here and not on the source tree.** This builder rewrites
  each manifest to inject the file hashes, so a signature taken over the
  source manifest would attest to a document that no longer exists. The chain
  is signature → manifest → hashes → files, and the hashes have to be final
  first.

The builder drives `TOS-Dev/tos/kernel/pkgsign.lua` over a filesystem shim
rather than reimplementing the record, so a disk built here and a package
signed on-box with `pkg sign` cannot disagree about what a signature is.
Defaults: `extras-root` = the parent of `build/`, `out-dir` =
`<extras-root>/dist/optional-utilities`. The output directory is a build
artifact (wiped and regenerated every run — never hand-edit it) — copy its
**contents** onto a floppy/HDD/drive, or skip the manual copy entirely with
`--install`:

```
build-disk.cmd --install "<saves>\<world>\opencomputers\<floppy-address>"
```

which "burns" the freshly built disk straight into an OpenComputers
filesystem folder.

Packages are **auto-discovered** — any directory under `modules/`,
`cluster/`, or `rbmk/` containing a `package.lua` is assembled (no builder
edit needed). Each manifest `files[]` target is resolved in order: **mirror**
(source laid out at its install path, like `modules/mouse/usr/lib/mouse.lua`),
**flat** (single-file modules keeping `init.lua` at their root, like
`modules/tetris/`), then an explicit **legacy** map for pre-convention
layouts (`cluster/master-skeleton`'s `lib/cluster/*`). Deliberate exclusions
go in the `SKIP` table with a reason that prints at build time (empty right
now — `tape-authenticator` rejoined the disk with its 1.0.0 rebuild).

### Multi-floppy splitting

The builder sizes the set against `--limit` (default **512K**, the OC
default floppy; `0` = unlimited) using a per-file `--overhead` (default
512 bytes, approximating OC's `fileCost`). If everything fits, you get the
flat single-disk layout below. If not, packages are bin-packed
(first-fit decreasing) into

```
optional-utilities/
  disk1/  README.txt + optutil-set.lua + <packages…>
  disk2/  README.txt + optutil-set.lua + <packages…>
  …
```

— copy each `diskN/`'s contents onto its own floppy. Two guarantees:
packages joined by a non-optional `requires` edge always share a disk (so
`kernel.pkg`'s resolver finds dependencies in the repo it installs from),
and every disk carries the picker. A single package group bigger than the
limit fails the build with the exact size, rather than producing a disk
that can't be written. `--install` only applies to single-disk builds.

A single-disk build produces:
```
optional-utilities/
  README.txt
  optutil-set.lua
  tetris/             package.lua + /usr/modules/tetris/init.lua
  tape/               package.lua + /usr/modules/tape/init.lua
  tape-authenticator/ package.lua + /usr/modules/tape-authenticator/init.lua
  rc-pilot/           package.lua + /usr/modules/rc-pilot/init.lua
  mouse/              package.lua + /usr/lib/mouse.lua + /usr/modules/mouse/init.lua
  cluster-manager/    package.lua + /usr/{lib,bin}/… + /etc/rc.d/… + /etc/…cfg
  cluster-master/     package.lua + /usr/{lib,bin}/… + /etc/rc.d/… + /etc/…cfg
```
Each package dir mirrors its files at their **absolute install paths**, because
`pkg.install(srcDir)` reads every manifest `files[]` entry from `srcDir .. target`.
The dir name equals the manifest `name` (so `pkg`'s H-20 dependency-confusion
check passes).

## Install (on the target TOS machine)

1. Insert the disk — it auto-mounts under `/mnt/<label>/`, and TOS prints what
   it is plus the next step ("Optional Utilities disk → pkg install").
2. Log in as **admin/root** (installing packages is admin-gated, CR-5).
3. Run `pkg install` (the picker is in the TOS base image, not on the disk).
4. Arrows to move, **Space** to tick, **A**/**N** all/none, **R** to add what your
   picks suggest, **Enter** to install, **Q** to quit. A set that spans several
   disks is listed in full — the picker asks you to swap when it needs the next
   one, and can stop-and-keep or undo the whole run.

For scripts: `pkg install <name> ...`, `pkg install --all --yes`, or
`--dry-run` to print the plan without changing anything.

### Building the disk without a dev box

This assembler runs on a dev box from the `TOS-Extras` source tree. To build an
Optional Utilities disk **from inside a running TOS** instead — bundling the
add-ons you already have installed — use `pkg make-disk <mount>` (admin). It
emits the same repo layout (one package dir each, plus the `optutil-set.lua`
set manifest and a README) sourced from `/var/pkg/installed`, so an operator can replicate
their add-on set onto another machine with no dev box and no source tree.

Service packages (`cluster-manager`, `cluster-master`) install **disabled** —
enable per host with `service start <name>` once configured.

## How it's wired to the kernel

The installer is only a front-end; all the real work is `kernel.pkg`:
- dependency resolution + topological install order (`installByName` → `installWithDeps`),
- admin gate (CR-5) via the threaded session,
- SHA-256 hash verification when a manifest declares `hashes`,
- write confinement to `/usr` + `/var/pkg`, plus the **narrow service exception**
  (a `kind="service"` package may also write `/etc/rc.d/<f>.lua` and
  `/etc/<name>.cfg` — nothing else under `/etc`, and never `/tos`/`/init.lua`).

## Adding a new add-on to the disk

1. Give it a directory under `modules/` (or `cluster/`) with a `package.lua`
   at its root: valid `kind` (`command`/`app`/`lib`/`service`/…) and an
   absolute `files[]` list under `/usr` (or, for services, the two allowed
   `/etc` targets).
2. Lay out the sources either **flat** (a single `init.lua` at the package
   root) or **mirrored** at their install paths (`<pkg>/usr/lib/…`) when the
   package ships more than one file.
3. Re-run `build-disk.cmd`/`.sh` — the assembler auto-discovers the package,
   and the installer auto-discovers it on the disk. No builder edit needed.

> **Note:** `pane-ui/` is intentionally not on this disk — it's an OpenOS-side
> app (no TOS `package.lua`), so it installs by copying onto an OpenOS machine
> rather than through `pkg`.
