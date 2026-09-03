# TOS Optional Utilities

Add-ons that run on TOS but are not TOS itself. This branch is a **package
repository**: a TOS machine with an internet card installs from it directly,
no floppy required.

## Install over the network

On the TOS machine, as an admin:

```
pkg repo add utils https://raw.githubusercontent.com/Evan450/TOS-Terminal-Operating-System-/optional-utilities
pkg search
pkg fetch calc
```

`pkg fetch` downloads the package into a staging directory and then runs the
**ordinary local install** against it, so hash verification, write-root
confinement and the unverified-package gate are the same code as installing
from a disk. The configured repo list is the allowlist: TOS reaches only
hosts an admin wrote down, and there is no default repo.

## Install from a floppy instead

`optutil-set.lua` describes the whole set. To build physical disks, use
`build/build-disk.lua` on the `dev` branch and copy each `diskN/`'s contents
onto its own floppy, then run `pkg install` on the target machine to pick
add-ons from the menu.

## What is here

Every package is a directory holding a `package.lua` manifest and the files
it installs. `programs.cfg` is the index `pkg fetch` reads; it is generated
from the manifests, so it cannot advertise a file the installer would reject.

Packages below version 1.0.0 are deliberately **not** published here — an
unfinished add-on that installs cleanly is worse than one you cannot reach.

## Contributing

Add-on source lives on the `dev` branch under `TOS-Extras/`. See
`CONTRIBUTING.md` there. This branch is generated; do not edit it by hand.
