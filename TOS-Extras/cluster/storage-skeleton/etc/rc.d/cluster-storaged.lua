-- ╔══════════════════════════════════════════════════════════════╗
-- ║  /etc/rc.d/cluster-storaged.lua — TOS service shim           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Serves the Public storage tier: writes on 2101 (TRUSTED, namespace
-- checked) and reads on 2100 (open, per §2.2). Stopping the service
-- closes both ports and flushes the index, so the node comes back
-- knowing what it holds.
--
-- The shim is deliberately bare, like clusterd's. It used to claim the
-- kernel-tier user and declare a caps table: rc honours that claim only
-- for four hard-coded services (so this one was demoted, with a warning,
-- on every boot) and the daemon needs nothing from the caps, because
-- a service's own /usr/lib library loads through the kernel loader with
-- the authority of the service. `needs = "net"` leaves the script
-- unloaded on a machine with no network card.
--
-- No pcall around the require: a daemon that fails to load must say so
-- when rc registers it, not start "successfully" and do nothing.

local storaged = require("cluster-storaged")

return {
  start   = storaged.start,
  stop    = storaged.stop,
  restart = true,
  needs   = "net",
}
