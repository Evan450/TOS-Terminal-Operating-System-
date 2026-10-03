# intercom — the facility announcement system

Says whatever you need said: the reactor has gone offline, you're low on iron, the shift is over. One announcement goes out on two channels at once. A Computronics tape plays the recorded voice, and the same words go over the mesh to every machine willing to hear them, where they land in the chat tab and, when they matter enough, in a message box on the screen.

## Install

As **root**, with the Optional Utilities disk inserted:

```
pkg install intercom
service start intercom
```

Root because intercom is a service that runs at boot outside the package sandbox. It installs **disabled**: accepting messages that can put a box on your screen is your decision. `service start intercom` lets this machine *hear* announcements; any machine can send them. A machine without the service still relays announcements for its neighbours.

The `tape` add-on is recommended alongside it for looking after the tape itself. Neither the tape nor the `tape` package is needed for text-only announcements.

## The catalogue is the whole trick

A tape drive cannot tell you what is recorded on it: it is audio, with no index. So you tell it once, in `/etc/intercom.cues`, in the notation you would jot down anyway, one line per announcement:

```
fuel-low  [0001] "Warning: Reactor fuel low." [0005]  warn
offline   [0006] "Warning: Reactor offline. Facility on backup power generation." [0010]  alert
evac      [0011] "Evacuate the facility." [0020]  critical
```

That is the start position, what it says, the end position and how urgent it is. From that one line the Intercom knows where to seek, when to stop, what to broadcast and how hard to interrupt people. Positions are tape byte offsets, and `[0001]` and `[1]` both parse. A typo on one line is reported by its line number instead of taking the whole catalogue down.

## Use

```
intercom                         open the Intercom tab: cues and what was heard
intercom status                  the tape drive, the catalogue, whether this machine is listening
intercom cues                    list the catalogue
intercom test evac               play it here only, and tell nobody
intercom play evac               the real thing: the tape plays and everyone is told
intercom say "we are out of iron" --severity warn
intercom log [N]                 the last N announcements heard here (default 20)
intercom set <key> <value>       change how this machine is interrupted (admin)
```

`intercom test` is how you check that hand-written positions really bracket the recording before you trust them. `say` needs no tape at all. `play`, `test` and `say` take `--to <peer>` to address one machine instead of everyone, and `play` and `test` take `--drive <address>` when there is more than one tape drive.

## Severity, and why the cooldown makes it safe

The levels are `info`, `notice`, `warn`, `alert` and `critical`. Below a receiver's popup level an announcement goes to the chat tab and the log. At or above it, a message box appears on their screen whatever they were doing.

A failing reactor can announce itself every few seconds, and a box per announcement would make the computer unusable at exactly the moment someone needs to type on it. So after one box, no further box appears for `cooldown` seconds. Nothing is dropped: only the interruption is held back, and every announcement still reaches chat and `intercom log`.

| `intercom set` | Default | What it does |
|---|---|---|
| `popuplevel <severity>` | `alert` | a message box at this level and above |
| `minlevel <severity>` | `info` | ignore anything quieter than this |
| `cooldown <seconds>` | `60` | the least time between two message boxes, 0 to 3600 |
| `echotape on\|off` | `off` | also play received cues on this machine's tape, when it has the same catalogue |

The settings live in `/etc/intercom.cfg`, which is why changing them needs admin.

## Files

| Installed at | What it is |
|---|---|
| `/usr/lib/intercom.lua` | the catalogue, tape playback, sending and receiving |
| `/usr/lib/intercomapp.lua` | the Intercom tab, found by the panels app registry |
| `/etc/rc.d/intercom.lua` | the boot service that registers the receive handler |

What a machine has heard is kept in `/var/intercom/log.dat`. Like `mail`, intercom is a full-privilege package loaded with the real `require`; the base image keeps only a thin `intercom` command that says how to install it when it is missing.

## Tests

From `TOS-Extras/`: `lua modules/intercom/test_intercom.lua` runs against a fake tape drive and no network. It covers the catalogue in the operator's notation (parsing, round trips, surviving a typo), severity ordering, absolute seeks on a drive that only seeks relatively, a stop scheduled at the cue's end rather than a blocking wait, the receive policy and cooldown, and the log.
