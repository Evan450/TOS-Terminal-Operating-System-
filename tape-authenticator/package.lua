return {
hashes = {
["/usr/modules/tape-authenticator/init.lua"] = "21cc887ae68d2d8d379bd0edf1865aa86fcc701a257151fe60872ae07ab7187f",
},
name = "tape-authenticator",
version = "1.0.3",
kind = "command",
category = "security",
description = "Tape keycard + encrypted personal log: HMAC identity for access control, private notes you can edit any time.",
author = "Strata Systems",
files = {
"/usr/modules/tape-authenticator/init.lua",
},
commands = { ["tape-auth"] = "/usr/modules/tape-authenticator/init.lua" },
capabilities = { "component", "peripheral.tape", "crypto", "vault" },
requires = {},
recommends = { "tape" },
}
