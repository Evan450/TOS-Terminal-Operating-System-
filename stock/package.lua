return {
hashes = {
["/usr/modules/stock/init.lua"] = "1dc52d0bf9573b292a68b692dc24fe4c55f36381820f4212644473e3431061a3",
["/usr/modules/stock/stock.lua"] = "9d8897dfe31326f9ea4ab841cd1f2e35899cc3126d86c4b0655b6c24600b3165",
},
name = "stock",
version = "1.0.2",
kind = "command",
category = "automation",
description = "Inventory monitor: totals every adjacent chest, warns on low stock.",
author = "Strata Systems",
files = {
"/usr/modules/stock/init.lua",
"/usr/modules/stock/stock.lua",
},
fullscreen = true,
background = "drowsy",
commands = { stock = "/usr/modules/stock/init.lua" },
capabilities = { "fs.read", "fs.write", "component", "peripheral.inventory" },
requires = {},
recommends = { "mouse" },
}
