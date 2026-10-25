return {
hashes = {
["/etc/rc.d/intercom.lua"] = "4bc1ba087a9d6b6a9ee529c6b7f252d2b5df324971a407e81726c30130e59c26",
["/usr/lib/intercom.lua"] = "66145dbcbda928c532e344050f11575c729ee809204594ffd31b8a08824cdd2e",
["/usr/lib/intercomapp.lua"] = "0a2f5ea106945947f23b563c776fa4a483adacd46d93cbbec7571aea49f00d6d",
},
name = "intercom",
version = "1.0.1",
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
