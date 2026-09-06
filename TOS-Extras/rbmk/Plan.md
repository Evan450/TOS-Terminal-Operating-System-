# RBMK Controller — plan (v0.2.0 shipped; the in-world survey is still the blocker)

A reactor control + display add-on for HBM's Nuclear Tech Mod RBMK
multiblocks, structured like the cluster add-on: the **safety-critical
controller runs on TOS**, and **non-critical display walls run on
OpenOS** satellites.

## Why this split (mirrors cluster/)

- TOS brings the security model the controller wants: capability
  sandbox, admin-gated commands, trust-bound networking with HMAC +
  replay protection, rc.d service lifecycle. A reactor SCRAM path
  should live here.
- Displays are glorified dashboards. OpenOS machines are cheaper to
  field in bulk, and a crashed display must never matter — they get a
  single-file client like `cluster/openos/cluster-worker.lua`.

## Pieces

| Piece | Where | Kind |
|-------|-------|------|
| `rbmk-controld` | TOS, rc.d service | polls the RBMK console component, evaluates safety rules, broadcasts telemetry, owns SCRAM |
| `rbmk` command | TOS shell | status, limits, manual SCRAM, the SKALA panel, the display wall |
| `rbmk-display.lua` | OpenOS | single-file telemetry renderer; drives every screen on the machine, time-slicing one GPU across several if need be |

## Hardware / capability notes

- HBM exposes RBMK control via OC component(s) (console/logic-adapter
  block). Exact component type names + method surface need an in-game
  survey first — **open question #1**.
- Third-party component types are NOT on the sandbox's base allowlist;
  the package documents an `/etc/component_caps.cfg` entry (FEAT-5)
  gating the RBMK component behind a `peripheral.reactor`-style cap,
  rather than widening the kernel allowlist.
- `net` cap for telemetry broadcast; `peripheral.redstone` for the
  hard-wired AZ-5 backup line (see Safety).

## Safety design (drafting rules)

1. The controller is authoritative; displays are strictly read-only
   consumers. No network input ever moves a rod.
2. SCRAM must work with the network down: local command + a redstone
   AZ-5 input line evaluated in the controld poll loop.
3. Watchdog both ways: controld marks telemetry frames with a sequence
   + uptime; displays render a loud STALE banner when frames stop.
   controld logs (and optionally beeps) when the console component
   disappears.
4. Safety rules (temp/flux limits → auto-SCRAM) evaluate locally per
   poll tick; thresholds in `/etc/rbmk.cfg`, admin-edited only.

## Protocol sketch

Reuse the cluster wire conventions: dedicated port, `magic = "RBMK"`,
kernel.serialize frames, HMAC via existing net trust secrets for
anything that isn't pure telemetry. Telemetry itself can be broadcast
unauthenticated (read-only data; displays are untrusted by design) —
**open question #2**: whether column-level detail fits one 8 KB packet
per tick or needs delta frames.

## Open questions

1. HBM RBMK OC component type names + methods (in-game survey).
2. Telemetry frame size/rate vs OC packet limits (delta encoding?).
3. Multi-reactor: one controld per reactor vs one controld, many
   consoles.
4. Whether rod-target writes belong in v1 at all, or v1 ships
   read-only + SCRAM and earns write control later.

## Status

**v0.2.0 (2026-09-05) — the SKALA panel and the display wall.**
**v0.1.0 (2026-07-19) — controller half, survey-first.**

`controller-skeleton/` is the `rbmk-control` package (`kind="service"`,
installed DISABLED). It is still held off the Optional Utilities disk by
`build/build-disk.lua`'s SKIP list, and correctly so: that rule is "below
1.0.0 is not finished", and open question #1 is still open.

What landed in 0.1.0, and why it's shaped this way: open question #1
(HBM's OC component names + methods) can only be answered in-world, so
instead of hard-coding a guess the controller treats method names as
**data**.

| Piece | State |
|-------|-------|
| `rbmk.core` — driver binding + safety rules | **done, 73 assertions** |
| `rbmk.core` — per-channel map + packed wire | **done** (0.2.0) |
| `rbmk.skala` — panel model: layout, bands, cells | **done** (0.2.0) |
| `rbmk.wall` — which screen shows what, alarm override | **done** (0.2.0) |
| `rbmk survey` — enumerate real components + their ACTUAL methods, show how the profile binds | **done** (this is the answer to open question #1) |
| `rbmk status` / `limits` / `scram` | done |
| `rbmk skala [--wall]` / `rbmk wall` | **done** (0.2.0) |
| `rbmk-controld` — poll, evaluate, broadcast, own SCRAM | done, **unverified against the mod** |
| `/etc/rbmk.cfg` — limits, grid, wall, profile | done |
| `openos/rbmk-display.lua` (OpenOS satellite) | **done** (0.2.0), **unverified against the mod** |

Safety rules from §Safety are implemented and unit-tested off-box: a
MISSING or STALE reading is itself a SCRAM (never an "ok"), a typo'd
limit falls back to the DEFAULT rather than to "no limit", the service
REFUSES TO START without a temperature reading and a SCRAM path, the
SCRAM latch never clears itself, and telemetry frames carrying anything
that looks like a control field are refused by the display-side
validator — so the unauthenticated broadcast channel can't become rod
control.

Open question #4 answered for v1: **read-only + SCRAM**. The only write
this package performs is the shutdown.

### 0.2.0 — the panel

`rbmk skala` draws the operator panel: a coordinate-ruled **core map**
of one reading per channel, a rail of lettered parameter keys (N power,
T core temp, X steam, K rod depth, G coolant) that swap what the map is
showing, plus **alarm** and **trend** pages. `rbmk skala --wall` drives
every screen on the machine at once, each with a different page;
`rbmk wall` prints what each would show.

Three things in it are load-bearing rather than cosmetic:

- **The coolant ramp is inverted.** 100% is healthy and `waterMin` is a
  scram, so its colour is measured downward. Drawn on the normal ramp a
  dry loop would render in the same calm blue as a cold core — the
  display would be calmest at the moment it should be loudest. Pinned
  from both directions, and pinned again on the satellite's copy.
- **A SCRAM or stale telemetry takes the wall over.** Unpinned panes
  switch to the alarm page; a wall showing a tidy trend during a scram
  reads as normal, which is worse than a blank one. A *warning* does
  not, because a wall that seized every screen on every advisory would
  train the room to ignore it.
- **A missing reading is drawn as missing.** Never blank (which would
  shrink the visible core every time a reading dropped out) and never
  the bottom colour band (which would make it look cold).

### 0.2.0 — a defect this fixed

Telemetry went out as a TOS protocol `MSG` packet. `net/trust.lua`'s
PERMISSIONS table allows `msg` only at TRUSTED, and displays are
**untrusted by design** (§Protocol) — so every satellite would have
dropped every frame at the trust gate, and an OpenOS satellite could not
have parsed it at all (`net/protocol.lua`: TOS machines only talk to TOS
machines). The broadcast could not reach the audience it was written
for. Nothing caught it because the display half did not exist yet.

It is now a **raw modem broadcast on port 2200** of fixed primitive
arguments — no serialized table, so there is no parser for an
unauthenticated channel to attack. Still strictly one-way: the
controller never opens the port, so the machine that owns SCRAM still
has no inbound network path.

### Open questions, updated

1. **HBM RBMK OC component names + methods — STILL OPEN.** Unchanged,
   and still the blocker. `profile.columns` was added for the core map
   and `rbmk survey` reports it separately from the readings, because a
   console with no column accessor is still fully supervisable — it just
   gets a panel with no per-channel map.
2. **Telemetry frame size — ANSWERED.** A full 15x15 core map of five
   parameters is ~3.6 KB packed, and the whole wire frame ~3.8 KB,
   against `protocol.MAX_SIZE` of 8192. As plain Lua tables the same
   data is roughly 12 KB, which is why the map is a packed base-36
   string. No delta encoding needed. Pinned by test.
3. Multi-reactor: still untouched. The panel takes a reactor `name` from
   the frame, so several controllers on one port would interleave —
   a display would need to filter on it.
4. Answered in v1 (read-only + SCRAM).

### Next
1. **The in-game survey** — run `rbmk survey` against a real console,
   put the true method names in `/etc/rbmk.cfg`, confirm `usable: YES`.
   Everything else is still blocked on this, including whether a core
   map is available at all.
2. Then verify the panel in-world: cell alignment at 15x15 on a tier-3
   screen, the satellite's GPU time-slicing across more screens than
   GPUs, and whether `mapInterval` needs raising on a real console.
3. Multi-reactor (#3) if more than one reactor ever shares a port.
