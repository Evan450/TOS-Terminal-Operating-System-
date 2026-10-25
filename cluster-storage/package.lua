return {
hashes = {
["/etc/cluster-storage.cfg"] = "934df9d9efe28c8f9a3e7303eb6f661b6d07b83cf8c49b924581bc2a22716d21",
["/etc/rc.d/cluster-storaged.lua"] = "ce70d6e05cee95ba3b80878bc66aba59cb66b09cb27bf8484014e52bfe2569d8",
["/usr/lib/cluster-storaged.lua"] = "f0c41aea184610e3e4a1ca0607bfa8192fd25f2db2c9d92c89121005c1a43f55",
["/usr/lib/cluster/store.lua"] = "a270076d58d8afa120fd8c85e36828f96e8b12d8ce356207e9365f05d266ae9f",
},
name = "cluster-storage",
version = "1.0.0",
kind = "service",
category = "network",
description = "Cluster Storage Node: scratch store for oversized task lists, writes on 2101, reads on 2100.",
author = "Strata Systems",
files = {
"/usr/lib/cluster/store.lua",
"/usr/lib/cluster-storaged.lua",
"/etc/cluster-storage.cfg",
"/etc/rc.d/cluster-storaged.lua",
},
requires = { "cluster-protocol" },
capabilities = {
"fs.read", "fs.write",
"net",
"component",
"peripheral.modem",
},
service = { defaultState = "disabled" },
conflicts = {},
}
