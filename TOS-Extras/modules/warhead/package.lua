-- Optional Utilities — warhead: a nuke designer and simulator for HBM's
-- Nuclear Tech Mod.
--
-- Design the best custom nuke for the blast you want, and see what ANY of
-- the mod's warheads would do before it goes off in your world: the
-- crater, the blast and who it kills, the radiation, the fallout, and how
-- thick a wall has to be to stand behind.
--
-- THE NUMBERS ARE THE MOD'S, NOT A WIKI'S. Every table and formula was
-- read out of NTM Community Edition 1.12.2-2.5.0.5 with javap (data.lua
-- names the class for each), and test_warhead.lua checks the arithmetic
-- against a separate Python reference built from the same listings. A
-- server can change most of them in hbm.cfg, so `warhead config` takes
-- that server's values. A different NTM version may differ; the README
-- says how to check.
--
-- Runs inside the pkg sandbox. component for the GPU; fs for the settings
-- file in the caller's home; peripheral.inventory to read a bomb, or a
-- chest of materials, through a transposer. It never moves an item — the
-- inventory library could, which is why the capability is declared here
-- so `pkg info` says so, and why this file says it does not use it.
return {
  name        = "warhead",
  version     = "1.0.0",
  kind        = "command",
  category    = "hbm",
  description = "HBM Nuclear Tech nuke designer + simulator: best custom nuke, blast/fallout/radiation, shelters.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/warhead/init.lua",
    "/usr/modules/warhead/data.lua",
    "/usr/modules/warhead/model.lua",
    "/usr/modules/warhead/best.lua",
    "/usr/modules/warhead/report.lua",
  },
  fullscreen  = true,
  -- Nothing here changes while it is not looked at.
  background  = "freeze",

  commands     = { warhead = "/usr/modules/warhead/init.lua" },
  capabilities = { "fs.read", "fs.write", "component", "peripheral.inventory" },
  requires    = {},
  recommends  = { "mouse" },
}
