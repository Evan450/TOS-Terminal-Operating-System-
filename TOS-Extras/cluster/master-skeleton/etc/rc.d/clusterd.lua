-- ╔══════════════════════════════════════════════════════════════╗
-- ║  /etc/rc.d/clusterd.lua — TOS service shim                   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Placed under /etc/rc.d/ so TOS's rc manager starts and stops the
-- cluster daemon at boot/shutdown. TOS's rc loader expects a table
-- with `start` and `stop` functions — see tos/kernel/rc.lua.

local clusterd = require("clusterd")

return {
  start = clusterd.start,
  stop  = clusterd.stop,
}
