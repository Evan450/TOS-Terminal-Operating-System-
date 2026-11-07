-- Storage Node package manifest — the Public storage tier (protocol spec
-- §4.5–§5, storage spec §9 step 3): a scratch store the Master spills
-- oversized task lists into, so a 6 KB packet is never worked around
-- with chunking when a scratch tier exists.
--
-- One node over its own disk, or one member of a POOL: the Master's
-- `storage_pool` lists several nodes and places each key itself (storage
-- spec §5), so a node never knows it is in one. `inputs_ref` and
-- `result_sink = "public"` are still dead. Nothing in the Master depends
-- on the node: with none configured, or one that is full or unreachable,
-- jobs fall back to inline payloads.
--
-- 1.1.0 — a pool's shared/ keys carry a version (counter, writer): an
--   older one is refused as stale_version, the same one again is a
--   repeat, and PUB GET and STORE_LIST say which version a node holds.
--
-- DEPENDS on cluster.protocol, which ships inside the cluster-manager
-- package. §4.6's canWrite lives in it and is shared rather than copied:
-- two implementations of one security rule is the drift this tree has
-- already been bitten by. So installing this pulls in a Manager daemon it
-- does not run; a small cluster-protocol package of its own is the real
-- fix (TODO.txt). It names cluster-manager rather than cluster-protocol
-- because `provides` only counts once a provider is installed: neither pkg
-- install nor pkg fetch looks for one, so on a fresh machine this package
-- could not be installed at all.
--
-- Ships DISABLED, and needs a modem that can hold three open ports (the
-- kernel's own, 2101 and 2100): a wired card or a Tier-2 wireless one.
-- A Tier-1 wireless card holds one, and the daemon says so at start.
return {
  name        = "cluster-storage",
  version     = "1.1.0",
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
  requires     = { "cluster-manager" },
  capabilities = {
    "fs.read", "fs.write",      -- /var/cluster-store + its index
    "net",                      -- the TRUSTED write plane
    "component",                -- finding the modems
    "peripheral.modem",         -- opening 2101/2100 and answering reads raw
  },
  service      = { defaultState = "disabled" },
  conflicts    = {},
}
