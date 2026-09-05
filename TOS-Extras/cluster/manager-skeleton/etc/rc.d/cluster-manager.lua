-- ╔══════════════════════════════════════════════════════════════╗
-- ║  /etc/rc.d/cluster-manager.lua — TOS service shim            ║
-- ╚══════════════════════════════════════════════════════════════╝
local mgr = require("cluster-manager")
return {
  start = mgr.start,
  stop  = mgr.stop,
}
