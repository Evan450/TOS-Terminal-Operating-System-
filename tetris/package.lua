return {
hashes = {
["/usr/modules/tetris/init.lua"] = "03888296eda2523e017065808eca01d1bf7c4d73b0715dad5a9ebd1a359b07cc",
},
name = "tetris",
version = "1.1.2",
kind = "command",
category = "games",
description = "Classic Tetris with per-user high scores. Requires a T2+ screen.",
author = "Strata Systems",
files = {
"/usr/modules/tetris/init.lua",
},
fullscreen = true,
background = "freeze",
commands = { tetris = "/usr/modules/tetris/init.lua" },
capabilities = { "fs.read", "fs.write", "component" },
requires = {},
recommends = { "mouse" },
}
