return {
hashes = {
["/etc/cluster-manager.cfg"] = "b063b8763256ff9b1d52466934ce0d472773c3ded43d3466b5bf0bab2464cd0e",
["/etc/rc.d/cluster-manager.lua"] = "90bb8b156da2b57ce4eb995fe459effdf710cce078fb535140a880645d3c21f6",
["/usr/bin/cluster-manager.lua"] = "3eb9ee9cd9e6d84205b5f09ba91274c03f93e4e381c669587548a2ccc89aaa3d",
["/usr/lib/cluster-manager.lua"] = "b22ce31571121d60c47dfc7193cc4283a19c3d25faccee6af82c2969e9108ee8",
["/usr/lib/cluster/protocol.lua"] = "ff181b28aacb59117d68458383084adafdf4f7954af6d41a83f4c2e2cc8f1859",
["/usr/lib/cluster/worker.lua"] = "e75b9ae07bcb63d746ebdbb6dbc42b3da12d90bce3108c408f3fab1959d4d638",
},
name = "cluster-manager",
version = "1.3.0",
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
--! This package ships /usr/lib/cluster/protocol.lua, the wire format a
--! Storage Node needs too, and cluster-storage requires it by name. A
--! Storage Node should not have to install a whole Manager daemon to get
--! that; the real fix is a small `cluster-protocol` package (TODO.txt).
provides = { "cluster-protocol" },
capabilities = {
"ipc:cluster-manager",
},
service = { defaultState = "disabled" },
requires = {},
}
