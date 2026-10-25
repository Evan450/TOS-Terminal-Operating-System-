return {
hashes = {
["/usr/modules/snake/init.lua"] = "23eeee95d3a0750a6deaca305a850ef47ab382d452500d5eadaa5bf5bb3c6e8a",
["/usr/modules/snake/logic.lua"] = "995998ca1f7737fd88d1c55adead30a8f99b9eca082cde40a9e64172bbe111cd",
},
name = "snake",
version = "1.0.1",
kind = "command",
category = "games",
description = "Classic snake with per-user high scores. Requires a T2+ screen.",
author = "Strata Systems",
files = {
"/usr/modules/snake/init.lua",
"/usr/modules/snake/logic.lua",
},
fullscreen = true,
background = "freeze",
commands = { snake = "/usr/modules/snake/init.lua" },
capabilities = { "fs.read", "fs.write", "component" },
requires = {},
}
