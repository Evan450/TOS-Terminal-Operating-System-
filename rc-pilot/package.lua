return {
hashes = {
["/usr/modules/rc-pilot/init.lua"] = "545480e6f4f8ade4b1274afe8087a9dd47ac7662cf9ed7618741001684978495",
["/usr/share/rc-pilot/eeprom-rc-pilot.lua"] = "6086026ad0122c88d0b223f2644f32e3e661b38d50ef78c70066834073f4a7eb",
},
name = "rc-pilot",
version = "1.3.0",
kind = "command",
category = "control",
description = "WASD remote-control host for OC robots/drones running the rc-pilot EEPROM.",
author = "Strata Systems",
files = {
"/usr/modules/rc-pilot/init.lua",
"/usr/share/rc-pilot/eeprom-rc-pilot.lua",
},
commands = { rc = "/usr/modules/rc-pilot/init.lua" },
capabilities = { "fs.read", "fs.write", "component", "peripheral.modem", "crypto" },
requires = {},
}
