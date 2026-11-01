return {
hashes = {
["/usr/lib/printer.lua"] = "112543d55ae9bdf8e0dbe07e6bd45db595bda4aea5fa850df43618e435d69dbb",
["/usr/lib/printerfmt.lua"] = "36a33e9f22d2939126f755fe7e8a5d53b00a87fe39c730875ac7d78ee80d4179",
["/usr/modules/printer/init.lua"] = "1910fa0926eef81043106ca35f5a65c224dbe35a21c408a6e241c4b8b9bec380",
},
name = "printer",
version = "1.0.1",
kind = "command",
category = "drivers",
description = "Printer driver for OpenPrinter: require(\"printer\") + a `printer` command (status, print, preview, scan, tags).",
author = "Strata Systems",
files = {
"/usr/lib/printerfmt.lua",
"/usr/lib/printer.lua",
"/usr/modules/printer/init.lua",
},
commands = { printer = "/usr/modules/printer/init.lua" },
capabilities = { "fs.read", "fs.write", "component", "peripheral.printer" },
requires = {},
recommends = { "mouse" },
}
