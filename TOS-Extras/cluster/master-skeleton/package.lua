-- CLUSTER-2 — installable manifest for the cluster Master daemon.
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
  version     = "1.0.0",
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
    "/usr/bin/cluster.lua",
    "/etc/rc.d/clusterd.lua",
    "/etc/cluster-master.cfg",
  },
  -- No `commands` map: the operator CLI ships as /usr/bin/cluster.lua and is
  -- run from PATH at full shell privilege (it needs the live kernel net/
  -- component surface, which the package sandbox would withhold). Declaring it
  -- as a package command would either be malformed (array form) or sandbox the
  -- CLI — so it is intentionally omitted, exactly like /usr/bin/servers, ssh.
  capabilities = {
    "fs.read", "fs.write",      -- /etc/cluster-master.cfg + /var/cluster/state.dat
    "component",                -- modem listing
    "peripheral.modem",         -- C4 split: cluster needs raw modem access
    "net",                      -- TOS net stack
    "load",                     -- evaluating job specs at submit time
  },
  -- The rc.d hook starts the daemon. defaultState=disabled so a fresh
  -- install doesn't auto-start a service on every machine that gets
  -- the package — operator decides per-host.
  service = { defaultState = "disabled" },
  requires    = {},
  -- FEAT-14: no license needed; this is the open control-plane.
}
