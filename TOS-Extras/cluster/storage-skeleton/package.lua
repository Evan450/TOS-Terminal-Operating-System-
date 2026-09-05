-- Storage Node package manifest.
--
-- DEPENDS on cluster.protocol, which currently ships inside the
-- cluster-manager package. §4.6's canWrite lives there and is shared
-- rather than copied: two implementations of one security rule is the
-- drift this tree has already been bitten by. If the Storage Node ever
-- ships to a box with no Manager on it, protocol.lua needs promoting to
-- a package of its own rather than duplicating.
return {
  name    = "cluster-storage",
  version = "0.1.0",
  kind    = "service",
  files   = {
    "/usr/lib/cluster/store.lua",
    "/usr/lib/cluster-storaged.lua",
    "/etc/cluster-storage.cfg",
    "/etc/rc.d/cluster-storaged.lua",
  },
  requires     = { "cluster-protocol" },
  capabilities = { "net", "fs.read", "fs.write" },
  conflicts    = {},
}
