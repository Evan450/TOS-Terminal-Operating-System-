return {
hashes = {
["/usr/modules/rc-pilot/init.lua"] = "4fdff4794a0e3d101aa9d2d95921465b5854920dde3348ea29c965d3f6ba0ee6",
["/usr/share/rc-pilot/eeprom-rc-pilot.lua"] = "0b1493e28c589a15af822e15eedc5f347a81ae7574e0775df10af6a12a94ef4c",
},
name = "rc-pilot",
version = "1.2.0",
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
