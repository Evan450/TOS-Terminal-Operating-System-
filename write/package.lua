return {
hashes = {
["/usr/modules/write/doc.lua"] = "e7e3743ca94b75e1d0c1a53d5ccbcc39678610eff550f79c4af90b3e0c6eda01",
["/usr/modules/write/init.lua"] = "a4fca618aff72e5bf0cfa668edd51bb129e4877fa60e0777392078da64661b08",
},
name = "write",
version = "1.1.2",
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
