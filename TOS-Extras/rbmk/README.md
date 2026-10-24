# RBMK reactor supervisor (HBM Nuclear Tech Mod)

Safety supervisor and operator panel for HBM's RBMK multiblocks. The
safety-critical controller runs on TOS; the display walls are cheap and
disposable, which is the same split the cluster add-on uses.

**Bound to the mod's real console, not yet run against it in a world.**
The component is `rbmk_console`; it is read one channel at a time with
`getColumnData(x, y)` and shut down with `pressAZ5()`. Those names, and
the shape of what `getColumnData` returns, were read off the mod's own
bytecode with `javap` (HBM-NTM 1.12), not guessed. What a jar cannot
tell us is how it behaves in play, so **run `rbmk survey` before you
start the service** — it proves the console is linked to a reactor and
that a full scan of the core comes back. Everything that is pure — the
safety rules, the scan's arithmetic, the panel's geometry and colour,
the wire format — is tested off-box. See [Plan.md](Plan.md).

## What's here

| Path | What it is |
|---|---|
| `controller-skeleton/` | The `rbmk-control` package (v1.0.0, `kind="service"`, installed DISABLED). |
| `openos/rbmk-display.lua` | The OpenOS display satellite. Single file, read-only, never transmits. |
| `test_rbmk.lua` | Binding + safety rules (73 assertions). |
| `test_rbmk_skala.lua` | Panel model, display wall, wire format, and the satellite's copied constants (196). |
| `test_rbmk_panel.lua` | End-to-end: console → controller → wire → painted screen (75). |
| `test_rbmk_ntm.lua` | The real-console driver: scan arithmetic, SCRAM result handling, survey, service (120). |

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

## What the console gives us, and what we make of it

`getColumnData(x, y)` takes `x, y` in `0..14` — the console's own frame,
which the mod rotates to the world — and returns a table for a channel
or `nil` where there is none. The keys that matter: `type`, `hullTemp`,
and per kind `coreTemp`/`coreMaxTemp`/`enrichment`/`fluxQuantity`
(fuel), `level` (control), `water`/`steam` (boiler, in mB).
`core.scanCore` folds all 225 positions into the readings the safety
rules use:

| Reading | Is | Why this and not the mean |
|---|---|---|
| `temp` | hottest hull of any column, °C | one column over 1500 melts, whatever the rest are doing |
| `melt` | hottest rod as a **% of its own fuel's melting point** | fuels differ, so one temperature limit would be wrong for most of them |
| `flux` | sum over the rods | first-guess limits — calibrate on a healthy run |
| `rodDepth` | mean insertion of the control rods, % | `level` 0 is fully **in**; that is what AZ-5 sets |
| `water` | the **lowest** boiler feed tank, % of 10000 mB | an average hides the one that ran dry |
| `steam` | mean boiler steam, % of 1,000,000 mB | |

A reading with nothing to read from (no boilers, no control rods) is
`nil`, never `0`. The scan is always the full 15×15 whatever footprint
the panel draws, and the same scan feeds the core map, so a poll costs
225 `direct` component calls and not 450. A channel that raises is
counted as `unread` and warns; a console that returns nothing at all
has no temperature, which the safety rules treat as a SCRAM.

**SCRAM, honestly.** `pressAZ5()` sets the target of every *manual*
control rod within 7 blocks of the core centre to 0. It does not raise
when there are none — it *returns* `"No control rods found"` — so the
controller treats any return value as "that did not shut anything down"
and tries the redstone line too. Automatic control rods are not driven
by it, and the mod's control rods only move while they have power, so a
core that can lose power wants the hard-wired AZ-5 (`az5RedstoneSide`).

## Upgrading from 0.x

Delete any `profile = { ... }` block from `/etc/rbmk.cfg`. It overrides
the new default, its guessed method names do not exist on the real
console, and the service will (safely) refuse to start with it.

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
