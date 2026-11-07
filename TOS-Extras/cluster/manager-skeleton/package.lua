-- CLUSTER-3 — installable manifest for the cluster Manager daemon.
--
-- 1.4.0 — a task list in a storage pool is read from its second member
--   when the first refuses or is silent; a Storage Node on this box reports
--   its free space in the heartbeat (storage spec §10, answer 3).
-- One Manager per "compute node" — the machine that actually runs
-- workers. Registers with the Master at startup and accepts
-- assignments. The Master schedules; the Manager executes.
--
-- Topology:
--   [TOS Master]
--    └ via wireless modem ─► [TOS Manager(s)]
--                              └ via worker port 2001+domain_id ─►
--                                   [OpenOS worker(s)] (or local TOS workers)
--
-- The OpenOS worker code is at TOS-Extras/cluster/openos/cluster-worker.lua
-- — that side is OpenOS-native because OpenOS robots and computers are
-- much more common in OC and worker code wants the wider library
-- surface (printable terminals, easy file I/O).
return {
  name        = "cluster-manager",
  version     = "1.4.0",
  kind        = "service",
  category    = "network",
  description = "Cluster Manager: registers with Master, accepts assignments, dispatches to workers.",
  author      = "Strata Systems",
  files       = {
    "/usr/lib/cluster-manager.lua",
    "/usr/bin/cluster-manager.lua",
    "/etc/rc.d/cluster-manager.lua",
    "/etc/cluster-manager.cfg",
    -- Cluster protocol core + Manager↔OpenOS-Worker bridge. These moved
    -- out of the base kernel (kernel/net/) so the cluster code ships only
    -- with this optional package. worker.lua is wired into the daemon when
    -- the bridge path is enabled (worker_bridge_address set); the daemon
    -- otherwise runs tasks inline.
    "/usr/lib/cluster/protocol.lua",
    "/usr/lib/cluster/worker.lua",
  },
  --! This package ships /usr/lib/cluster/protocol.lua, the wire format a
  --! Storage Node needs too, and cluster-storage requires it by name. A
  --! Storage Node should not have to install a whole Manager daemon to get
  --! that; the real fix is a small `cluster-protocol` package (TODO.txt).
  provides    = { "cluster-protocol" },
  -- No `commands` map: the operator CLI ships as /usr/bin/cluster-manager.lua
  -- and runs from PATH. This is the CLI's capability and nothing else's: the
  -- daemon runs through rc.d, with the caps its own rc.d script declares.
  capabilities = {
    "ipc:cluster-manager",      -- everything it does, through the daemon
  },
  service = { defaultState = "disabled" },
  requires = {},
}
