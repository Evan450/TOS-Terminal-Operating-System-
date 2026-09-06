# RBMK reactor supervisor (HBM Nuclear Tech Mod)

Safety supervisor and operator panel for HBM's RBMK multiblocks. The
safety-critical controller runs on TOS; the display walls are cheap and
disposable, which is the same split the cluster add-on uses.

**Nothing here is verified against the mod yet.** HBM's OpenComputers
component names and method surface can only be learned in-world, so they
are *data* in `/etc/rbmk.cfg` and `rbmk survey` prints what a real
console actually exposes. Everything that is pure — the safety rules,
the panel's geometry and colour, the wire format — is tested off-box.
See [Plan.md](Plan.md).

## What's here

| Path | What it is |
|---|---|
| `controller-skeleton/` | The `rbmk-control` package (v0.2.0, `kind="service"`, installed DISABLED). |
| `openos/rbmk-display.lua` | The OpenOS display satellite. Single file, read-only, never transmits. |
| `test_rbmk.lua` | Binding + safety rules (73 assertions). |
| `test_rbmk_skala.lua` | Panel model, display wall, wire format, and the satellite's copied constants (196). |
| `test_rbmk_panel.lua` | End-to-end: console → controller → wire → painted screen (59). |

Run them from the `TOS-Extras` root: `lua rbmk/test_rbmk.lua`, and so on.

## The commands

```
rbmk survey            what the console REALLY exposes, and how it binds
rbmk status            live reading + safety evaluation
rbmk limits            the active safety limits
rbmk scram             manual shutdown
rbmk skala [--wall]    the SKALA information panel
rbmk wall              what each screen on this machine would show
```

`rbmk skala` draws a coordinate-ruled **core map** of one reading per
channel, with a rail of lettered parameter keys — **N** power, **T**
core temp, **X** steam, **K** rod depth, **G** coolant — that swap what
the map shows, plus **alarm** and **trend** pages. Arrow keys move an
inspection cursor; `Q` leaves.

`--wall` drives *every* screen on the machine, each with a different
page. It is opt-in because TOS is multi-seat: painting every display by
default would take over screens other logged-in operators are working
at.

## Things worth knowing before you change anything here

- **The coolant ramp is inverted.** 100% is healthy, `waterMin` is a
  scram, so its colour is measured downward. On the normal ramp a dry
  loop would draw in the same calm blue as a cold core — the panel would
  be calmest exactly when it should be loudest. Pinned by test in both
  directions, and pinned again against the satellite's copy.
- **Missing is not zero, and not empty.** A channel the console didn't
  report draws as `----` in the missing colour. Blank would shrink the
  visible core whenever a reading dropped out; the bottom colour band
  would make it look cold. Same rule the safety logic already follows.
- **A SCRAM or stale telemetry takes the wall over**, switching unpinned
  panes to the alarm page. A *warning* does not — a wall that seized
  every screen on every advisory would train the room to ignore it.
- **The core map is a lossy, display-only path.** It is quantised into a
  packed base-36 string so a full 15×15 grid of five parameters fits one
  8 KB packet (~3.6 KB; the same data as plain tables is ~12 KB). That
  is safe *only* because no safety decision reads it: `evaluate()` runs
  on the controller's own raw local reading.
- **Telemetry is a raw modem broadcast on port 2200**, not a TOS
  protocol packet, and it carries fixed primitive arguments rather than
  a serialized table. Both are deliberate — see Plan.md §0.2.0 for the
  defect that motivated the first and the reasoning behind the second.
- **The controller never listens.** It broadcasts and nothing else, so
  the machine that owns SCRAM has no inbound network path. That is why
  `rbmk wall` cannot list satellites: displays never register.

## The OpenOS satellite

Copy `openos/rbmk-display.lua` to `/home/rbmk-display.lua` on each
display machine and run it. It needs a modem and at least one screen;
with more screens than GPUs it time-slices a GPU across them, so a
display wall costs one graphics card rather than four. Per-screen pages
go in `/etc/rbmk-display.cfg`.

It cannot `require` any of the controller's libraries — OpenOS doesn't
speak the TOS protocol and doesn't have them — so it carries copies of
the parameter table, the colour bands, the port and the wire format.
`test_rbmk_skala.lua` reads the file and pins every one of those against
the real module, and lifts its `cellText`/`bandOf` out to compare their
*output* too. A display that quietly disagrees with the controller about
which band is "alarm" is worse than no display at all.

## Version control

Part of the `Programs (Scripts)` monorepo; run git from the repo root.
