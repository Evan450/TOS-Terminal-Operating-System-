# RBMK Controller — plan (idea capture, not started)

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

## Pieces (planned)

| Piece | Where | Kind |
|-------|-------|------|
| `rbmk-controld` | TOS, rc.d service | polls the RBMK console component, evaluates safety rules, broadcasts telemetry, owns SCRAM |
| `rbmk` command | TOS shell | status, rod targets, limits, manual SCRAM, display pairing |
| `rbmk-display.lua` | OpenOS | single-file telemetry renderer (column mimic, temps, graphs) |

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

**v0.1.0 shipped (2026-07-19) — controller half, survey-first.**
`controller-skeleton/` is a real `rbmk-control` package on the Optional
Utilities disk (auto-discovered, `kind="service"`, installed DISABLED).

What landed, and why it's shaped this way: open question #1 (HBM's OC
component names + methods) can only be answered in-world, so instead of
hard-coding a guess the controller treats method names as **data**.

| Piece | State |
|-------|-------|
| `rbmk.core` — driver binding + safety rules | **done, 72 assertions** |
| `rbmk survey` — enumerate real components + their ACTUAL methods, show how the profile binds | **done** (this is the answer to open question #1) |
| `rbmk status` / `limits` / `scram` | done |
| `rbmk-controld` — poll, evaluate, broadcast, own SCRAM | done, **unverified against the mod** |
| `/etc/rbmk.cfg` — limits + the operator-editable profile | done |
| `rbmk-display.lua` (OpenOS satellite) | **not started** |

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

### Next
1. **The in-game survey** — run `rbmk survey` against a real console,
   put the true method names in `/etc/rbmk.cfg`, confirm `usable: YES`.
   Everything else is blocked on this.
2. Open questions #2 (telemetry frame size/rate) and #3 (multi-reactor)
   are untouched.
3. `rbmk-display.lua` for OpenOS satellites, once frames are confirmed
   on real hardware.
