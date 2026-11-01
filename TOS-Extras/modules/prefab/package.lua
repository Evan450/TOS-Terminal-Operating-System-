-- Optional Utilities — prefab: design a base, a slice at a time.
--
-- A 2.5D blueprint designer: one slice of a building at a time, looking
-- along X, Y or Z, with the slice behind it shown faintly. It counts what a
-- build takes and finds the blocks a robot could not place.
--
-- 0.x, so build-disk.lua keeps it off the pack. What is left is designed in
-- TOS-Dev/docs/PREFAB.md, and nothing here has been tried in a world.
--
-- Runs inside the pkg sandbox. component for the GPU and the geolyzer, and
-- fs for blueprints. peripheral.inventory only reads what is in reach for
-- `prefab need`; it never moves an item. peripheral.printer is for `prefab
-- print`. A library from another package runs in this sandbox with these
-- caps and no others, so each has to be declared here to work at all.
-- A blueprint is data: it is parsed by hand and never executed.
return {
  name        = "prefab",
  version     = "0.7.0",
  kind        = "command",
  category    = "control",
  description = "Base designer: assemble bases from hallways and rooms, or draw blueprints in slices, and have a robot build them.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/prefab/init.lua",
    "/usr/modules/prefab/blueprint.lua",
    "/usr/modules/prefab/plan.lua",
    "/usr/modules/prefab/survey.lua",
    "/usr/modules/prefab/export.lua",
    "/usr/modules/prefab/links.lua",
    "/usr/modules/prefab/tui.lua",
    "/usr/modules/prefab/parts.lua",
    "/usr/modules/prefab/base.lua",
    "/usr/modules/prefab/layout.lua",
  },
  fullscreen  = true,
  -- Nothing here changes while it is not looked at.
  background  = "freeze",

  commands     = { prefab = "/usr/modules/prefab/init.lua" },
  handles      = { { ext = { "bp", "base" }, as = "native" } },
  capabilities = { "fs.read", "fs.write", "component", "peripheral.inventory", "peripheral.printer" },
  requires    = {},
  -- Soft: every action has a key, but painting is what a mouse is for, and
  -- the others each add something when they are there.
  recommends  = { "mouse", "stock", "printer", "calc" },
}
