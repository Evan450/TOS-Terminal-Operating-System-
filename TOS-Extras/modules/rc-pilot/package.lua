-- FEAT-13 — host-side controller for the rc-pilot EEPROM.
-- Run on a TOS computer with a wireless modem. Captures WASD/arrows/
-- Space/Shift and forwards them to the targeted robot.
-- 1.2.0 — ships the robot's burnable EEPROM image. build-disk.lua minifies
-- robot/eeprom-rc-pilot.lua into it and refuses a build over 4096 bytes.
return {
  name        = "rc-pilot",
  version     = "1.2.0",
  kind        = "command",
  category    = "control",
  description = "WASD remote-control host for OC robots/drones running the rc-pilot EEPROM.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/rc-pilot/init.lua",
    -- The robot side: flash it onto the chip the robot will carry. Built
    -- from robot/eeprom-rc-pilot.lua (see MINIFIED in build-disk.lua).
    "/usr/share/rc-pilot/eeprom-rc-pilot.lua",
  },
  commands     = { rc = "/usr/modules/rc-pilot/init.lua" },
  -- "crypto" injects the narrow hmac/random surface the frame signer needs;
  -- without it the sandbox leaves `crypto` nil and `rc` fails on first use.
  capabilities = { "fs.read", "fs.write", "component", "peripheral.modem", "crypto" },
  requires    = {},
}
