return {
hashes = {
["/usr/modules/tape/init.lua"] = "7d8ad39405405f62b7560575073204ca4d15f108217ad490a0cd5079c7ae1b9b",
},
name = "tape",
version = "2.3.2",
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
