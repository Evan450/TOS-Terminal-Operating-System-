# rc-pilot — drive a robot from the keyboard

Remote control for OpenComputers robots and Computronics drones. Run `rc` on a TOS computer with a wireless modem and the screen becomes a pilot's seat: WASD or the arrow keys drive, Space and Shift climb and descend, and every keystroke goes to the robot as a signed frame on wireless port 7777.

The robot runs no operating system. It carries a small EEPROM program, `robot/eeprom-rc-pilot.lua` in this repository, which checks each frame's signature and turns it into a `robot` or `drone` call. Since 1.2.0 this package installs that program, already minified to fit a 4096-byte chip, as `/usr/share/rc-pilot/eeprom-rc-pilot.lua`.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install rc-pilot`.

## Setting up a robot

Both ends share a secret of at least 16 characters. Every frame carries an HMAC-SHA256 of its contents under that secret, and the robot ignores any frame whose signature does not check out, or that it has already seen.

1. **Burn the chip.** Swap a blank EEPROM into this computer, keeping yours safe, and run `flash /usr/share/rc-pilot/eeprom-rc-pilot.lua` as root. `flash` will warn that the file does not look like a BIOS. It is right, because this is a robot program; type `force`, then `flash`.
2. **Give the chip its secret.** The robot reads its secret from the EEPROM's data field.
3. Swap your own EEPROM back, and build the chip into the robot or drone, with a wireless network card.
4. **Give `rc` the same secret**, in your keychain: `keychain set rc:<first 8 characters of the robot's modem address>`.

> **Not finished yet.** Two steps of this have no tool on TOS today. Nothing on TOS writes an EEPROM's data field: `flash` writes only the code, and the sandbox hides the EEPROM from every program, `lua` included. Until that is fixed, do step 2 from an OpenOS computer, with the chip in it: `lua`, then `component.eeprom.setData("your-shared-secret")`. And the robot does not announce its wireless card's address, which `rc` needs in full. A chip with no secret ignores everything without a sound. Both gaps are on the TOS TODO list.

## Use

```
rc <robot-address>
```

The secret comes from your keychain (slot `rc:` plus the first 8 characters of the address). With no keychain entry, `rc` asks for it without echoing it. `rc <address> --secret <secret>` works for scripts, but says so, because the secret then sits in the seat's command history. A known TOS peer can be given by an address prefix; a robot usually is not one, so give its full address.

| Key | Robot | Drone |
|---|---|---|
| W, Up | forward | south (+Z) |
| S, Down | back | north |
| A, Left | a side-step: turn left, forward, turn right | west |
| D, Right | a side-step: turn right, forward, turn left | east |
| Q, E | turn left, turn right, in place | nothing |
| Space, Left Shift | up, down | up, down |
| F | use: right-click the block ahead | nothing |
| X | swing: break the block ahead | nothing |
| B | place a block from the selected slot | nothing |
| 1 to 9 | select that inventory slot | nothing |
| P | ping: a round-trip check | ping |

A drone has no facing, so it moves along the world's axes. An operation the machine cannot do is simply not done.

Ctrl+Q or F10 leaves pilot mode, and so does Ctrl+C. Esc does not: Minecraft takes it to close the screen and the computer never sees it.

## The wire format

A frame is a Lua-literal string the robot reads by pattern: `{magic="RCPILOT1",op="..",arg=n,nonce="hex",mac="hex"}`, where the MAC is HMAC-SHA256(secret, `op|arg|nonce`). The operations are `move:f/b/l/r`, `turn:l/r`, `up`, `down`, `use:f`, `swing:f`, `place:f`, `select` (with the slot as `arg`), `stop` and `ping`, which the robot answers with a `pong`. The robot compares MACs in constant time and remembers the last 64 nonces, so a recorded frame cannot be replayed.

Size is the constraint on the robot side. A chip holds 4096 bytes and `flash` refuses more, and the program is written for its minified size: the pack build minifies it and refuses to build if the result is over 4096 bytes or does not load.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/rc-pilot/init.lua` | the `rc` command |
| `/usr/share/rc-pilot/eeprom-rc-pilot.lua` | the robot's chip image, minified from `robot/eeprom-rc-pilot.lua` |

It asks for `peripheral.modem` to talk to the robot and `crypto` to sign frames.

## Tests

From `TOS-Extras/`: `lua modules/rc-pilot/test_rc_pilot.lua` drives the real `rc` command against the real EEPROM program with the real `kernel.crypto`. The robot moves for the host's signature and not for a replay, a tampered signature, a changed operation, the wrong magic, a missing signature, or a different or absent secret; ping is answered; and the minified image fits the chip.
