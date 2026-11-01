return {
hashes = {
["/usr/modules/write/doc.lua"] = "e7e3743ca94b75e1d0c1a53d5ccbcc39678610eff550f79c4af90b3e0c6eda01",
["/usr/modules/write/init.lua"] = "6801933cb1493c8be8a212411ed9594a6a33f701aa7d0761aa35d83f92eb787e",
},
name = "write",
version = "1.1.1",
kind = "command",
category = "productivity",
description = "Word processor: live page breaks, ink/paper cost, dot-command formatting, prints via the printer driver.",
author = "Strata Systems",
files = {
"/usr/modules/write/init.lua",
"/usr/modules/write/doc.lua",
},
fullscreen = true,
background = "freeze",
commands = { write = "/usr/modules/write/init.lua" },
handles = {
{ ext = { "wri" }, as = "native" },
{ ext = { "txt", "doc", "text" },
markers = { ".title ", ".page", ".center", ".left", ".color ", ".nf" } },
},
capabilities = { "fs.read", "fs.write", "component", "peripheral.printer" },
requires = { "printer" },
recommends = { "mouse" },
}
