# blockfs — TBFS, a filesystem for unmanaged drives

OpenComputers drives come in two kinds. A *managed* drive is a `filesystem` component with a ready-made file API, and it is what TOS mounts by default. An *unmanaged* drive is a raw `drive` component: read a sector, write a sector, and nothing else. It holds no files until an operating system lays a filesystem onto its bare sectors.

This package is that filesystem, **TBFS**. Install it and the base OS's `drive` command can format, mount, check and defragment unmanaged drives, after which they behave like any other TOS disk: the file browser, `cp` and file permissions all work on them unchanged.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install blockfs`.

TOS always *sees* unmanaged drives without it: `lsdev`, `hw` and the System Configuration screen list them as *Raw Drive*, and `drive list`, `drive info` and `drive read` work on the base image. You need this package only to store files on one.

## Use

All through the base `drive` command; format, mount, check and defrag need admin.

```
drive list                           the unmanaged drives, and what each one holds
drive format <addr> [label]          lay down a fresh TBFS (erases the drive)
drive mount <addr> [path]            mount it, at /mnt/<label> by default
drive unmount <addr>                 unmount it and mark the volume clean
drive check <addr> [--repair]        verify the block map; --repair rebuilds the free counts
drive defrag <addr> [--if-over N]    make each file's blocks contiguous again
```

`drive info` says what a drive holds before you format it: TBFS, a partition table, another filesystem, a blank drive, or data TOS doesn't recognise.

Format, `check --repair` and `defrag` rewrite the block map underneath a mount's cache, so each of them unmounts the volume, does the work and remounts it at the same path. It asks first only when something would be disturbed, such as an open file or a process whose working directory is on the volume, and it remounts even when the work fails.

Unmanaged drives simulate a spinning platter, so a fragmented file costs real seek time. `drive defrag <addr> --if-over 30` acts only when fragmentation reaches 30 percent, which makes it a good `cron` job. `drive info` shows the current figure, and `drive mount` warns when it is high.

**TOS can live on one, too.** `deploy drive <addr>` (root) formats an unmanaged drive as a bootable TBFS volume and copies the whole OS onto it. It checks for this package first and stops, saying so, rather than half-writing a disk. See §5.4 of the TOS manual.

## How TBFS is laid out

```
block 0          the superblock
bitmap region    one bit per block: free or used
inode region     a fixed table of inodes
data region      file and directory blocks
```

A block is one sector. A file finds its blocks through 8 direct pointers, one single-indirect and one double-indirect, so a single file reaches into the megabytes. A directory is a file whose data is a list of names and inode numbers. Allocation tries to keep each file contiguous; fragmentation creeps in only as a full disk is churned.

## Files

| Installed at | What it is |
|---|---|
| `/usr/lib/blockfs.lua` | the whole filesystem: format, check, defragment, and a proxy that speaks the same interface as a managed disk |

The library is pure: the only thing it touches is the drive handed to it, so it carries no capabilities of its own. The privileged parts (finding drives, and the `drive` command that mounts them) are in the base image.

## Tests

From `TOS-Extras/`, against a table-backed fake drive:

- `lua modules/blockfs/test_blockfs.lua`: the whole filesystem, from format through files large enough to need double-indirect blocks, rename and remove, surviving a remount, defragmentation, and check with repair
- `lua modules/blockfs/test_blockfs_enospc.lua`: a write that fails because the drive is full gives back the blocks it had already taken, instead of quietly losing capacity that only a check would recover
- `lua modules/blockfs/test_blockfs_plan.lua`: the two numbers `deploy drive` relies on before it erases a drive, the layout `format` will lay down and what one file really costs, each checked against the real thing
- `lua modules/blockfs/test_blockfs_perf.lua`: every sector call crosses the component bridge, so the number of calls is the filesystem's speed; this pins the budget for each kind of operation
