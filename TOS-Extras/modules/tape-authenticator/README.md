# tape-authenticator — a tape as a keycard and a notebook

A tape is far bigger than a keycard needs, so this uses the rest of it. The front of the tape carries a signed identity block, "this tape is Operator X's key", which cannot be forged. The space after it holds two things only you can open with your own passphrase: a personal log, a small private notebook, and a personal menu of commands that travels with the card.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install tape-authenticator`. The command it installs is `tape-auth`. The `tape` add-on is recommended alongside it for inspecting and looking after the tapes, though nothing here needs it.

## Use

```
tape-auth init <label>          make the inserted tape a keycard (admin)
tape-auth verify                check the inserted card is genuine (admin)
tape-auth info                  say whose card it is; needs no secret
```

`init` will not wipe a card that already holds a log or a menu: clear those first, or use a fresh tape.

**The personal log**, encrypted with your passphrase:

```
tape-auth log add <pass> <text>      add an entry
tape-auth log list <pass>            read them all
tape-auth log remove <pass> <n>      delete entry n
tape-auth log clear <pass>           wipe the log
tape-auth log passwd <old> <new>     change the passphrase
```

**The personal menu**, your own toolbox of commands:

```
tape-auth menu add <pass> <Label> -- <command>   add an item
tape-auth menu list <pass>
tape-auth menu remove <pass> <n>
tape-auth menu passwd <old> <new>
tape-auth menu clear <pass>
```

`--` separates the label from the command, because an unquoted `|` would be read by the shell as a pipe. Open the menu with the base OS's `tape-menu` command, on any machine with a tape drive.

**Any passphrase can be `-`** (since 1.0.3): it is then asked for without being shown, and stays out of your command history, where a typed one is kept for whoever sits down next. A new passphrase is asked for twice, since a mistyped one you cannot see would lock that part of the card for good. The first `add` to an empty log or menu is what sets its passphrase: pick one that is not your login password.

## How the two halves stay apart

They are deliberately independent.

- **The identity block** is signed (HMAC-SHA256) with a secret that belongs to this package on the issuing machine and is kept by the kernel. Issuing and checking cards is an operator's job on that machine, which is why `init` and `verify` need admin.
- **The log and the menu** are encrypted with *your* passphrase. Editing them never touches the identity block and needs no admin, and the machine's secret cannot read them.

On the tape, the identity block is a `TAUTH2` header, the issue time, the label and its MAC; the encrypted region follows it. Cards from the older identity-only `TAUTH1` format still verify, read-only; `init` upgrades them.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/tape-authenticator/init.lua` | the `tape-auth` command |

It runs inside the package sandbox with `component` and `peripheral.tape` for the drive, `crypto` for signing and checking cards, and `vault` for the passphrase encryption. Both of those are narrow: they take data in and give data out, and neither reaches the kernel.

## Tests

From `TOS-Extras/`: `lua modules/tape-authenticator/test_tape_auth.lua`, against a fake tape drive. It covers the card format, signing and verifying, the log and the menu, `init` refusing to wipe a card with either on it, and passphrases given as `-`.
