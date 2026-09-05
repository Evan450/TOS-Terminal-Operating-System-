-- FEAT-13 — host-side controller for the rc-pilot EEPROM.
-- Run on a TOS computer with a wireless modem. Captures WASD/arrows/
-- Space/Shift and forwards them to the targeted robot.
return {
  name        = "rc-pilot",
  version     = "1.0.0",
  kind        = "command",
  category    = "control",
  description = "WASD remote-control host for OC robots/drones running the rc-pilot EEPROM.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/rc-pilot/init.lua",
  },
  commands     = { rc = "/usr/modules/rc-pilot/init.lua" },
  -- "crypto" injects the narrow hmac/random surface the frame signer needs;
  -- without it the sandbox leaves `crypto` nil and `rc` fails on first use.
  capabilities = { "fs.read", "fs.write", "component", "peripheral.modem", "crypto" },
  requires    = {},
}
