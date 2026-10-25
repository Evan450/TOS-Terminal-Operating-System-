return {
hashes = {
["/usr/modules/tape/init.lua"] = "51dd71d212bab2b1ec10b027d2964ec3a69aca92520813bc5308b3be79fcc103",
},
name = "tape",
version = "2.3.1",
kind = "command",
category = "storage",
description = "General Computronics tape control: data archive/restore + audio playback + raw I/O + device state.",
author = "Strata Systems",
files = {
"/usr/modules/tape/init.lua",
},
commands = { tape = "/usr/modules/tape/init.lua" },
capabilities = { "fs.read", "fs.write", "component", "peripheral.tape", "vault" },
provides = { "tape-storage" },
requires = {},
}
