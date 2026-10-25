return {
hashes = {
["/usr/modules/ttt/init.lua"] = "860e9c7cc188df43c6da25fb075db48bc70d1d34bf7add5d0bdc43d97a5b202f",
["/usr/modules/ttt/logic.lua"] = "a73b33d46a03d2f61f9d1a52ef30a495d237a42e0be35e42e10cadb60eef3bcb",
},
name = "ttt",
version = "1.0.1",
kind = "command",
category = "games",
description = "Tic-tac-toe vs an unbeatable AI, or 2-player. Requires a T2+ screen.",
author = "Strata Systems",
files = {
"/usr/modules/ttt/init.lua",
"/usr/modules/ttt/logic.lua",
},
fullscreen = true,
background = "drowsy",
commands = { ttt = "/usr/modules/ttt/init.lua" },
capabilities = { "fs.read", "fs.write", "component" },
requires = {},
recommends = { "mouse" },
}
