-- CLUSTER-2 — installable manifest for the cluster Master daemon.
--
-- 1.2.0 — storage_pool: several Storage Nodes as one Public tier (storage
--   spec §5). job- keys go to two members or stay inline, shared/ stands
--   at a majority with versions and a repair sweep, each member's lease is
--   released there, and a LIST names any member that did not answer.
-- Run `pkg install cluster-master` after copying this directory tree
-- to a TOS repo location. The Master is the control-plane node; each
-- network should have exactly one. Multiple Masters would each accept
-- registrations independently and the cluster would partition.
--
-- Requires:
--   * A wireless modem (or a wired modem connected to every Manager).
--   * ROOT tier to operate the CLI's mutating subcommands.
--   * The `cluster-master` rc.d service stays disabled by default;
--     enable with `service start clusterd` after first install so an
--     accidentally-installed binary doesn't immediately start
--     advertising itself.
return {
  name        = "cluster-master",
  version     = "1.2.0",
  kind        = "service",
  category    = "network",
  description = "Cluster control-plane Master: registers Managers, schedules jobs, owns persistent state.",
  author      = "Strata Systems",
  files       = {
    "/usr/lib/clusterd.lua",
    "/usr/lib/cluster/state.lua",
    "/usr/lib/cluster/scheduler.lua",
    "/usr/lib/cluster/jobs.lua",
    "/usr/lib/cluster/net.lua",
    "/usr/lib/cluster/api.lua",
    "/usr/lib/cluster/pair.lua",
    -- clusterd.lua requires this at load, unguarded. Leaving it out of
    -- the list did not break anything HERE, where it sits beside the
    -- others in the source tree; it broke the INSTALLED package, whose
    -- daemon died on `require("cluster.store_client")`.
    "/usr/lib/cluster/store_client.lua",
    -- store_client places a storage POOL's keys with this, and runs as
    -- one node without it, so a missing copy would quietly ignore
    -- storage_pool. Listed for the reason store_client is.
    "/usr/lib/cluster/placement.lua",
    "/usr/bin/cluster.lua",
    "/etc/rc.d/clusterd.lua",
    "/etc/cluster-master.cfg",
  },
  -- No `commands` map: the operator CLI ships as /usr/bin/cluster.lua and runs
  -- from PATH. These capabilities are the CLI's and nothing else's: the daemon
  -- runs through rc.d, with the caps its own rc.d script declares. Any user can
  -- start a PATH program, and `cluster submit` evaluates a file, so the CLI
  -- holds no more than it needs.
  capabilities = {
    "ipc:cluster",              -- everything it does, through clusterd
    "load",                     -- evaluating job specs at submit time
  },
  -- The rc.d hook starts the daemon. defaultState=disabled so a fresh
  -- install doesn't auto-start a service on every machine that gets
  -- the package — operator decides per-host.
  service = { defaultState = "disabled" },
  requires    = {},
  -- FEAT-14: no license needed; this is the open control-plane.
}
