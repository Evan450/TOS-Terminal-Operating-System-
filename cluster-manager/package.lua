return {
hashes = {
["/etc/cluster-manager.cfg"] = "b063b8763256ff9b1d52466934ce0d472773c3ded43d3466b5bf0bab2464cd0e",
["/etc/rc.d/cluster-manager.lua"] = "90bb8b156da2b57ce4eb995fe459effdf710cce078fb535140a880645d3c21f6",
["/usr/bin/cluster-manager.lua"] = "7c17612ed82b215e09e12167039b5e4b16200dff713d32b61ecac1f39632fb17",
["/usr/lib/cluster-manager.lua"] = "d83254b136ed6b06b47df33f9ab1b683642bf3a4e970720d4fced193634fafbe",
["/usr/lib/cluster/protocol.lua"] = "a4781a8391cae87170249df46c3a28dee68da2f74b1d756423e5656f0fad9954",
["/usr/lib/cluster/worker.lua"] = "e75b9ae07bcb63d746ebdbb6dbc42b3da12d90bce3108c408f3fab1959d4d638",
},
name = "cluster-manager",
version = "1.2.1",
kind = "service",
category = "network",
description = "Cluster Manager: registers with Master, accepts assignments, dispatches to workers.",
author = "Strata Systems",
files = {
"/usr/lib/cluster-manager.lua",
"/usr/bin/cluster-manager.lua",
"/etc/rc.d/cluster-manager.lua",
"/etc/cluster-manager.cfg",
"/usr/lib/cluster/protocol.lua",
"/usr/lib/cluster/worker.lua",
},
--! cluster-storage declares `requires = { "cluster-protocol" }`, and no
--! package by that name has ever existed -- so `pkg install
--! cluster-storage` would fail resolution on a dependency nobody could
--! satisfy. It has not bitten yet only because cluster-storage is 0.1.0
--! and the pack excludes anything below 1.0.0.
--!
--! `provides` is the mechanism already used for tape/tape-storage, and
--! it makes the existing declaration resolve to the package that really
--! ships /usr/lib/cluster/protocol.lua -- this one. It is a bandage over
--! a packaging question, not an answer to it: a Storage Node should not
--! have to install a whole Manager daemon to get the wire format. The
--! real fix is a small `cluster-protocol` package, recorded in TODO.txt.
provides = { "cluster-protocol" },
capabilities = {
"fs.read", "fs.write",
"component",
"peripheral.modem",
"net",
"load",
"compat.io",
},
service = { defaultState = "disabled" },
requires = {},
}
