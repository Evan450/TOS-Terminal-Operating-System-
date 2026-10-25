return {
hashes = {
["/usr/lib/mouse.lua"] = "59efc24efb29034d3574106a13d5d17fc3e031145f1d1c46ece5830031744e35",
["/usr/modules/mouse/init.lua"] = "311a73ce5e83b6e9b8cc144df59420363aab5fafabb75483b008392f746d4066",
},
name = "mouse",
version = "1.1.0",
kind = "command",
category = "drivers",
description = "Mouse driver: require(\"mouse\") for events + clickable TOS shell UI + `mousetest` demo.",
author = "Strata Systems",
files = {
"/usr/lib/mouse.lua",
"/usr/modules/mouse/init.lua",
},
commands = { mousetest = "/usr/modules/mouse/init.lua" },
capabilities = { "component", "fs.read" },
requires = {},
}
