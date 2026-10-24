-- Storage Node package manifest — the Public storage tier (protocol spec
-- §4.5–§5, storage spec §9 step 3): a scratch store the Master spills
-- oversized task lists into, so a 6 KB packet is never worked around
-- with chunking when a scratch tier exists.
--
-- Scope of 1.0.0, stated so nobody expects more: ONE node over its own
-- disk. The distributed pool (storage spec §5, steps 4+) is not built,
-- and `inputs_ref` / `result_sink = "public"` are still dead. Nothing in
-- the Master depends on the node: with none configured, or one that is
-- full or unreachable, jobs fall back to inline payloads.
--
-- DEPENDS on cluster.protocol, which ships inside the cluster-manager
-- package (`provides = { "cluster-protocol" }` there). §4.6's canWrite
-- lives in it and is shared rather than copied: two implementations of
-- one security rule is the drift this tree has already been bitten by.
-- So installing this pulls in a Manager daemon it does not run; a small
-- cluster-protocol package of its own is the real fix (TODO.txt).
--
-- Ships DISABLED, and needs a modem that can hold three open ports (the
-- kernel's own, 2101 and 2100): a wired card or a Tier-2 wireless one.
-- A Tier-1 wireless card holds one, and the daemon says so at start.
return {
  name        = "cluster-storage",
  version     = "1.0.0",
  kind        = "service",
  category    = "network",
  description = "Cluster Storage Node: scratch store for oversized task lists, writes on 2101, reads on 2100.",
  author      = "Strata Systems",
  files       = {
    "/usr/lib/cluster/store.lua",
    "/usr/lib/cluster-storaged.lua",
    "/etc/cluster-storage.cfg",
    "/etc/rc.d/cluster-storaged.lua",
  },
  requires     = { "cluster-protocol" },
  capabilities = {
    "fs.read", "fs.write",      -- /var/cluster-store + its index
    "net",                      -- the TRUSTED write plane
    "component",                -- finding the modems
    "peripheral.modem",         -- opening 2101/2100 and answering reads raw
  },
  service      = { defaultState = "disabled" },
  conflicts    = {},
}
