return {
hashes = {
["/usr/modules/stock/init.lua"] = "90639090a7fa7d3fbc376cd54d099247fbe52b3057c6c7d22fea7b26dea10cd1",
["/usr/modules/stock/stock.lua"] = "5b46a84d5ad0f149cde9135ee19d06054e8060b957e56c23d21311647e8a12b0",
},
name = "stock",
version = "1.0.1",
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
