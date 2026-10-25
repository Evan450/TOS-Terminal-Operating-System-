return {
hashes = {
["/usr/lib/printer.lua"] = "ad8506447b002f907c9f72ab5e8f20d6e19f1fb561ca06e8d8890965bd6a9bd9",
["/usr/lib/printerfmt.lua"] = "36a33e9f22d2939126f755fe7e8a5d53b00a87fe39c730875ac7d78ee80d4179",
["/usr/modules/printer/init.lua"] = "cae3064777227eb037efe1ab7f76a84af2e22a7f1b596accfcb8a6fff322e742",
},
name = "printer",
version = "1.0.0",
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
