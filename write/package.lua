return {
hashes = {
["/usr/modules/write/doc.lua"] = "831a3e2b47c1f6c04a331d491c6ab3cd19000b812d8bdd20aba84e9c9a6f53a1",
["/usr/modules/write/init.lua"] = "3d32f8b4c2f417f8ca226219511bf8f84c09d834aff0c45341587c030b35f361",
},
name = "write",
version = "1.1.0",
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
