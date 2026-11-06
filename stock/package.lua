return {
hashes = {
["/usr/modules/stock/init.lua"] = "6fb1d32f9a87f3869314f106738194a2e6a3775b52fe6a29956d14cd0d461c82",
["/usr/modules/stock/stock.lua"] = "68ecb67b7aed21d1e338fef92127dddf82a015616847b5c1198da25a858658ad",
},
name = "stock",
version = "1.0.3",
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
