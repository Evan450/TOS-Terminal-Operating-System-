-- ╔══════════════════════════════════════════════════════════════╗
-- ║  /etc/rc.d/rbmk-controld.lua — TOS service shim              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Starts the RBMK supervisor at boot. Ships DISABLED: a controller
-- that auto-attaches to whatever reactor-ish component it finds on
-- first boot is not a safe default — the operator surveys, configures
-- /etc/rbmk.cfg, then runs `service start rbmk-controld`.
--
-- (Cluster lesson: rc.d loads BEFORE the OpenOS compat aliases exist,
-- so this shim requires only the package lib, which uses kernel.*.)

local controld = require("rbmk-controld")

return {
  start = controld.start,
  stop  = controld.stop,
  check = controld.running,
}
