return {
hashes = {
["/etc/rc.d/intercom.lua"] = "4bc1ba087a9d6b6a9ee529c6b7f252d2b5df324971a407e81726c30130e59c26",
["/usr/lib/intercom.lua"] = "c3a905b83d765fc9e9862365b3b8f67bc487a19db2aa110d418c7b3a169e382f",
["/usr/lib/intercomapp.lua"] = "4ec63c3e9f8805d11479871b6a47f7cc18123ef66c84d3d24fff067e627cebf7",
},
name = "intercom",
version = "1.0.2",
kind = "service",
category = "network",
description = "Announcement system: plays cataloged tape messages and broadcasts the same words to the network.",
author = "Strata Systems",
files = {
"/usr/lib/intercom.lua",
"/usr/lib/intercomapp.lua",
"/etc/rc.d/intercom.lua",
},
commands = {},
capabilities = {},
requires = {},
recommends = { "tape" },
service = { defaultState = "disabled" },
}
