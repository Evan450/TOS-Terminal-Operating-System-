-- Optional Utilities — RBMK reactor controller (HBM Nuclear Tech Mod).
--
-- Supervises an RBMK console: polls it, evaluates safety limits, owns
-- SCRAM, and broadcasts read-only telemetry to display satellites.
-- Structured like the cluster add-on (see rbmk/Plan.md): the
-- safety-critical controller runs on TOS; dashboards are cheap OpenOS
-- machines whose failure must never matter.
--
-- ── 1.0.0: bound to the real console ───────────────────────────────
-- HBM's console is the OC component `rbmk_console`: getColumnData(x, y)
-- per channel, pressAZ5() to shut down, getRBMKPos() for the link. That
-- surface was read off the mod's own bytecode (Plan.md open question
-- #1), and the "hbm-ntm" driver in rbmk.core folds the 225 channels
-- into the readings the safety rules run on. It has NOT been exercised
-- in a world: `rbmk survey` is the first thing to run, and proves the
-- console is linked and the core scans before anything is started.
-- The SAFETY LOGIC (limits, stale-reading handling, SCRAM latching,
-- frame validation) is pure and fully unit-tested off-box.
--
-- Know before relying on it: pressAZ5 drives only the MANUAL control
-- rods within 7 blocks of the core centre, and the rods only move while
-- they have power (the mod's control rod needs 5000 HE to step). Fit
-- the redstone AZ-5 backup (`az5RedstoneSide`) if the rods can lose power.
--
-- v1 is READ-ONLY + SCRAM (Plan.md open question #4): the single write
-- this package will ever perform is the shutdown. Nothing arriving over
-- the network can move a rod — the service registers no receive handler
-- at all.
--
-- ── 0.2.0: the SKALA panel and the display wall ────────────────────
-- `rbmk skala` draws the operator panel modelled on the RBMK
-- information-output console: a coordinate-ruled core map of one
-- reading per channel, a rail of lettered parameter keys, an alarm
-- page and a trend page. `rbmk skala --wall` drives EVERY screen on
-- the machine, each with a different page; OpenOS satellites
-- (rbmk/openos/rbmk-display.lua) render the same picture from the
-- telemetry broadcast, so a control room is not limited to one
-- computer.
--
-- The panel is a consumer, not a control surface: no key it listens
-- for moves a rod, and the wall takes itself over on SCRAM or on stale
-- telemetry rather than continuing to show a calm-looking page.
--
-- Ships DISABLED: a controller that auto-attaches to whatever
-- reactor-ish component it finds on first boot is not a safe default.
-- Survey, configure, then `service start rbmk-controld`.
return {
  name        = "rbmk-control",
  version     = "1.0.0",
  kind        = "service",
  category    = "control",
  description = "RBMK reactor supervisor for HBM's rbmk_console: SKALA panel, display wall, safety limits, SCRAM. Survey first.",
  author      = "Strata Systems",
  files       = {
    "/usr/lib/rbmk/core.lua",        -- pure: binding + safety rules + wire
    "/usr/lib/rbmk/skala.lua",       -- pure: the SKALA panel's model
    "/usr/lib/rbmk/wall.lua",        -- pure: which screen shows what
    "/usr/lib/rbmk-cmd.lua",         -- the `rbmk` operator command
    "/usr/lib/rbmk-skala.lua",       -- the panel renderer (multi-screen)
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
