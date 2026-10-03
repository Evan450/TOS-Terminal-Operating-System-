# tape — the Computronics tape drive, all of it

One command for everything a Computronics tape drive does: archive files to a tape and restore them, play audio, read and write raw bytes, and encrypt what is on it.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install tape`. It works on the first tape drive it finds.

It used to be called `tape-storage`, from when it only archived data, and it still answers to that name for any package that `requires` it. **Upgrading from 2.1 or older:** run `pkg uninstall tape` first, because the old build's files live at the old install path, `/usr/modules/tape-storage/`.

## Use

```
tape detect                        the tape drives, and what is in them
tape info                          the tape: label, size, format
tape state                         the head position, speed and volume
tape label [name]                  read or set the tape's label
```

**Archives.** A tape can hold files and folders, like a slow, removable disk.

```
tape store <path> [--overwrite]    add a file or folder to the tape's archive
tape list                          what the archive holds
tape restore [path]                restore it all, under /home unless you say where
```

`store` adds to whatever the archive already holds; `--overwrite` starts the archive again from the beginning of the tape.

**Audio.** Computronics plays DFPWM audio straight off the tape.

```
tape load <file.dfpwm>             rewind and write the audio file onto the tape
tape play                          play from where the head is
tape stop
tape rewind                        stop, and go back to the start
tape speed [0.25-2.0]              set the playback speed
tape volume [0-1]                  set the volume
```

The drive can be told a speed and a volume but cannot be asked for them, so `tape speed`, `tape volume` and `tape state` report the last values set from this machine, and say so.

**Low level.**

```
tape dump [offset] [length]        hex dump, 128 bytes from 0 by default
tape seek <position>               move the head to a byte position
tape erase [full]                  quick erase, or zero the whole tape
tape raw read <offset> <length> <file>
tape raw write <offset> <file>
```

**Encryption.**

```
tape encrypt <passphrase>          encrypt the tape's archive where it is
tape decrypt <passphrase>
tape vault encrypt <src> <dst> <passphrase>   encrypt any file, a floppy's included
tape vault decrypt <src> <dst> <passphrase>
```

A passphrase typed here stays in the seat's command history. To keep it out, use the base OS's `vault tape encrypt` and `vault tape decrypt`, which ask for it without showing it and hand it to `tape` directly.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/tape/init.lua` | the whole command |

It asks for `fs.read` and `fs.write` for archives and raw files, `component` and `peripheral.tape` for the drive, and `vault`, which gives it only encrypt, decrypt and is-this-encrypted on data it hands over.

The keycard tapes that `tape-authenticator` writes are tapes like any other, and this command is how you inspect and look after them.

## Tests

From `TOS-Extras/`, against a fake tape drive:

- `lua modules/tape/test_tape_archive.lua`: the whole store-and-restore round trip, folders included
- `lua modules/tape/test_tape_speed_volume.lua`: speed and volume on a drive that cannot report either
- `lua modules/tape/test_tape_vault.lua`: `tape decrypt` reads what `tape encrypt` wrote, and reads stay bounded rather than loading a whole tape into memory
