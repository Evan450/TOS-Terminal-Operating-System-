-- Optional Utilities — RBMK reactor controller (HBM Nuclear Tech Mod).
--
-- Supervises an RBMK console: polls it, evaluates safety limits, owns
-- SCRAM, and broadcasts read-only telemetry to display satellites.
-- Structured like the cluster add-on (see rbmk/Plan.md): the
-- safety-critical controller runs on TOS; dashboards are cheap OpenOS
-- machines whose failure must never matter.
--
-- ── STATUS: the hardware binding is UNVERIFIED ─────────────────────
-- HBM's OC component type names and method surface are Plan.md's open
-- question #1 and can only be answered in-world. Rather than hard-code
-- a guess, method names are DATA in /etc/rbmk.cfg, and `rbmk survey`
-- prints what a real console actually exposes so the operator can fill
-- them in. The SAFETY LOGIC (limits, stale-reading handling, SCRAM
-- latching, frame validation) is pure and fully unit-tested off-box —
-- what needs in-world verification is only the binding.
--
-- v1 is READ-ONLY + SCRAM (Plan.md open question #4): the single write
-- this package will ever perform is the shutdown. Nothing arriving over
-- the network can move a rod — the service registers no receive handler
-- at all.
--
-- Ships DISABLED: a controller that auto-attaches to whatever
-- reactor-ish component it finds on first boot is not a safe default.
-- Survey, configure, then `service start rbmk-controld`.
return {
  name        = "rbmk-control",
  version     = "0.1.0",
  kind        = "service",
  category    = "control",
  description = "RBMK reactor supervisor: safety limits, SCRAM, telemetry. Survey the console first.",
  author      = "Strata Systems",
  files       = {
    "/usr/lib/rbmk/core.lua",        -- pure: binding + safety rules
    "/usr/lib/rbmk-cmd.lua",         -- the `rbmk` operator command
    "/usr/lib/rbmk-controld.lua",    -- the supervising service
    "/etc/rc.d/rbmk-controld.lua",
    "/etc/rbmk.cfg",
  },
  -- The base `rbmk` command stub hands this package the shell context;
  -- no sandboxed command entrypoints (the controller needs kernel.net
  -- for telemetry and raw component access for the console).
  commands     = {},
  capabilities = {},
  requires    = {},
  service      = { defaultState = "disabled" },
}
