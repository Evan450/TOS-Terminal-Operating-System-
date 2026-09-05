-- Optional Utilities — calc: a spreadsheet for TOS.
--
-- Grid + formulas + save/load + CSV export, in the TOS visual grammar.
--
-- The formula engine is a hand-written TOKENIZER + RECURSIVE-DESCENT
-- PARSER, deliberately NOT `load()`-based. The usual shortcut is to
-- rewrite "=A1*2" into Lua and execute it; that would make every saved
-- sheet an executable file and the sandbox the only thing between a
-- shared .calc and the machine. Nothing a cell contains is ever
-- executed here — a hostile formula's worst outcome is #SYNTAX!. It is
-- also why this package does NOT request the `load` capability.
--
-- Runs fully inside the pkg sandbox: draws through the sandboxed
-- `component` GPU proxy, pulls raw signals, and reads/writes through the
-- session-bound `fs` — so a sheet is always saved with the calling
-- user's permissions.
--
-- The model + engine (calc/sheet.lua) are pure and unit-tested off-box
-- by modules/calc/test_calc.lua.
return {
  name        = "calc",
  version     = "1.0.0",
  kind        = "command",
  category    = "productivity",
  description = "Spreadsheet: cells, formulas (SUM/IF/ranges…), save/load, CSV export.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/calc/init.lua",
    "/usr/modules/calc/sheet.lua",
  },
  -- Full-screen program: the shell hands it the seat as its own
  -- process, so Ctrl+B can push it to the background and Ctrl+T
  -- brings it back instead of it owning the terminal until it exits.
  fullscreen  = true,
  -- Background policy (drowsy): let an in-flight recalc finish if you glance away.
  background  = "drowsy",

  commands     = { calc = "/usr/modules/calc/init.lua" },
  -- No `load` cap on purpose (see above). fs for sheets, component for
  -- the GPU. Nothing else.
  capabilities = { "fs.read", "fs.write", "component" },
  requires    = {},
  -- Soft suggestion, never installed behind your back: calc has real
  -- mouse support (click a cell, drag a selection), which the panels
  -- shell only enables when the mouse driver is present.
  recommends  = { "mouse" },
}
