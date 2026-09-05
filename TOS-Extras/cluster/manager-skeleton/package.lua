-- CLUSTER-3 — installable manifest for the cluster Manager daemon.
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
  version     = "1.0.0",
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
  -- No `commands` map: the operator CLI ships as /usr/bin/cluster-manager.lua
  -- and is run from PATH at full shell privilege (the package sandbox would
  -- withhold the live kernel net/component surface it needs). Omitted on
  -- purpose, like /usr/bin/servers, ssh — not registered as a package command.
  capabilities = {
    "fs.read", "fs.write",
    "component",
    "peripheral.modem",
    "net",
    "load",                     -- evaluating task code from the Master
    "compat.io",                -- worker-bridge writes
  },
  service = { defaultState = "disabled" },
  requires = {},
}
