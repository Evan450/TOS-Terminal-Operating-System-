-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: the menu bar is the operator's, not the code's      ║
-- ║                                                            ║
-- ║  Reported from real Minecraft, 2026-08-11: the bar "hasn't ║
-- ║  been updated and should be Operator-adjustable, not       ║
-- ║  static as it currently is (or at least, looks)". Both     ║
-- ║  halves were fair. It had an append-only per-user config    ║
-- ║  and nothing else — you could add an item and never        ║
-- ║  remove, rename, reorder or replace one — and the          ║
-- ║  built-in set had not been touched while a year of new     ║
-- ║  commands arrived.                                          ║
-- ║                                                            ║
-- ║  The config is an EDIT LIST rather than a replacement bar   ║
-- ║  on purpose: a replacement goes stale the moment TOS adds   ║
-- ║  a command, which is precisely how the built-in set got     ║
-- ║  out of date in the first place.                            ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_menu_config.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end
local function ok(name, cond) test(name, true, cond and true or false) end

package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 100000 end,
  totalMemory = function() return 200000 end,
}
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end,
}
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local serialize = require("kernel.serialize")
local draw = require("shell.panels.draw")

print("=== menu bar configuration Tests ===")
print()

-- ── A shell state with two config files ──────────────────────
local function stateWith(files)
  return {
    who = "root",
    F = {
      exists   = function(p) return files[p] ~= nil end,
      readFile = function(p) return files[p] end,
    },
  }
end
local function cfg(list) return serialize.encode(list) end

local function labels(menus)
  local out = {}
  for _, m in ipairs(menus) do out[#out + 1] = m.label end
  return table.concat(out, " ")
end
local function itemsOf(menus, menuLabel)
  for _, m in ipairs(menus) do
    if m.label == menuLabel then
      local out = {}
      for _, it in ipairs(m.items) do
        if not it.sep then out[#out + 1] = it.label end
      end
      return out
    end
  end
end
local function has(list, name)
  for _, v in ipairs(list or {}) do if v == name then return true end end
  return false
end

-- ══════════════════════════════════════════════════════════════════════
-- The built-in bar is up to date
-- ══════════════════════════════════════════════════════════════════════
do
  local menus = draw.buildMenuDefs(stateWith({}))
  ok("there is a bar at all", #menus > 0)
  ok("the classic menus are there",
    labels(menus):find("File") and labels(menus):find("System")
    and labels(menus):find("Help"))

  -- The half of the report that was simply "it hasn't been updated".
  -- These commands all shipped after the bar was written and were
  -- reachable only by typing them, which for a DISCOVERY surface is the
  -- whole failure.
  local tools = itemsOf(menus, "Tools")
  ok("Tools offers Packages", has(tools, "Packages"))
  ok("Tools offers Repair (SRM)", has(tools, "Repair (SRM)"))
  ok("Tools offers Diagnostics", has(tools, "Diagnostics"))
  local system = itemsOf(menus, "System")
  ok("System offers CLI Mode", has(system, "CLI Mode"))
  local settings = itemsOf(menus, "Settings")
  -- The bar can be edited from the bar. An adjustable thing whose
  -- adjustment is undiscoverable is still, to the operator, static.
  ok("Settings offers Menu Bar", has(settings, "Menu Bar"))
end

-- ══════════════════════════════════════════════════════════════════════
-- Adding — including the shape that already existed
-- ══════════════════════════════════════════════════════════════════════
do
  -- The legacy per-user shape must keep working byte-for-byte: configs
  -- written before this change exist, and an operator who only ever
  -- wanted "put my command in a drop-down" should not have to relearn.
  local S = stateWith({ ["/root/.menu.cfg"] =
    cfg({ { label = "Tetris", cmd = "tetris", menu = "Tools" } }) })
  local menus = draw.buildMenuDefs(S)
  ok("the legacy add shape still works", has(itemsOf(menus, "Tools"), "Tetris"))
end

do
  local S = stateWith({ ["/root/.menu.cfg"] =
    cfg({ { add = "Reactor", cmd = "rbmk", menu = "Tools" } }) })
  ok("the `add` spelling works too",
    has(itemsOf(draw.buildMenuDefs(S), "Tools"), "Reactor"))
end

do
  -- An unknown target menu collects into "Custom" rather than vanishing.
  local S = stateWith({ ["/root/.menu.cfg"] =
    cfg({ { add = "Thing", cmd = "thing", menu = "Nowhere" } }) })
  local menus = draw.buildMenuDefs(S)
  ok("an unknown menu creates Custom", has(itemsOf(menus, "Custom"), "Thing"))
  -- Convention: Help stays rightmost.
  test("Help is still the last menu", "Help", menus[#menus].label)
end

-- ══════════════════════════════════════════════════════════════════════
-- Removing, renaming, moving — the half that did not exist
-- ══════════════════════════════════════════════════════════════════════
do
  local S = stateWith({ ["/root/.menu.cfg"] =
    cfg({ { remove = "Flash EEPROM" } }) })
  local tools = itemsOf(draw.buildMenuDefs(S), "Tools")
  ok("a built-in item can be hidden", not has(tools, "Flash EEPROM"))
  ok("...without taking its neighbours", has(tools, "Lua REPL"))
end

do
  local S = stateWith({ ["/root/.menu.cfg"] =
    cfg({ { remove = "Help", menu = true } }) })
  ok("a whole menu can be hidden",
    not labels(draw.buildMenuDefs(S)):find("Help"))
end

do
  local S = stateWith({ ["/root/.menu.cfg"] =
    cfg({ { rename = "Tools", to = "Utilities" } }) })
  local menus = draw.buildMenuDefs(S)
  ok("a menu can be renamed", labels(menus):find("Utilities") ~= nil)
  ok("...and the old name is gone", labels(menus):find("Tools") == nil)
  ok("its items came with it", has(itemsOf(menus, "Utilities"), "Lua REPL"))
end

do
  local S = stateWith({ ["/root/.menu.cfg"] =
    cfg({ { rename = "Lua REPL", to = "Lua" } }) })
  ok("an item can be renamed", has(itemsOf(draw.buildMenuDefs(S), "Tools"), "Lua"))
end

do
  local S = stateWith({ ["/root/.menu.cfg"] =
    cfg({ { move = "Desktop", menu = "Tools" } }) })
  local menus = draw.buildMenuDefs(S)
  ok("an item can move between menus", has(itemsOf(menus, "Tools"), "Desktop"))
  ok("...and leaves the old menu", not has(itemsOf(menus, "System"), "Desktop"))
end

do
  local S = stateWith({ ["/root/.menu.cfg"] =
    cfg({ { menu = "Reactor", after = "System" },
          { add = "Scram", cmd = "rbmk scram", menu = "Reactor" } }) })
  local menus = draw.buildMenuDefs(S)
  ok("a new top-level menu can be created", labels(menus):find("Reactor") ~= nil)
  ok("...and filled", has(itemsOf(menus, "Reactor"), "Scram"))
  -- Placement is honoured: `after = "System"` puts it directly after.
  local order = labels(menus)
  ok("...where it was asked to go", order:find("System Reactor") ~= nil)
end

-- ══════════════════════════════════════════════════════════════════════
-- Layering: the machine's bar, then the user's
-- ══════════════════════════════════════════════════════════════════════
do
  local S = stateWith({
    ["/etc/menu.cfg"]    = cfg({ { add = "Base", cmd = "base", menu = "Tools" } }),
    ["/root/.menu.cfg"]  = cfg({ { add = "Mine", cmd = "mine", menu = "Tools" } }),
  })
  local tools = itemsOf(draw.buildMenuDefs(S), "Tools")
  ok("the system config applies", has(tools, "Base"))
  ok("the user config applies on top", has(tools, "Mine"))
end

do
  -- A user can hide something the machine added — their bar, their seat.
  local S = stateWith({
    ["/etc/menu.cfg"]   = cfg({ { add = "Base", cmd = "base", menu = "Tools" } }),
    ["/root/.menu.cfg"] = cfg({ { remove = "Base" } }),
  })
  ok("a user edit can override a system one",
    not has(itemsOf(draw.buildMenuDefs(S), "Tools"), "Base"))
end

-- ══════════════════════════════════════════════════════════════════════
-- A bad config must not cost you the menu bar
-- ══════════════════════════════════════════════════════════════════════
-- The menu bar is the surface an operator would use to FIX a bad menu
-- bar. Every one of these has to degrade rather than break.
do
  local cases = {
    { "unparseable",        "this is not a table" },
    { "not a list",         cfg({ hello = "world" }) },
    { "junk entries",       cfg({ 42, "nonsense", {} }) },
    { "a malformed add",    cfg({ { add = "X" } }) },                 -- no cmd
    { "an over-long label", cfg({ { add = string.rep("x", 99), cmd = "y" } }) },
    { "removing nothing",   cfg({ { remove = "Does Not Exist" } }) },
    { "renaming nothing",   cfg({ { rename = "Nope", to = "Also Nope" } }) },
    { "moving nowhere",     cfg({ { move = "Desktop", menu = "Nope" } }) },
  }
  for _, c in ipairs(cases) do
    local S = stateWith({ ["/root/.menu.cfg"] = c[2] })
    local okBuild, menus = pcall(draw.buildMenuDefs, S)
    ok(c[1] .. ": still builds", okBuild)
    if okBuild then
      ok(c[1] .. ": the bar survives", type(menus) == "table" and #menus > 0)
      ok(c[1] .. ": File is still there", labels(menus):find("File") ~= nil)
    end
  end
end

do
  -- Even an edit list that deletes EVERYTHING falls back to the
  -- built-ins. A machine whose only recovery surface is the thing that
  -- was just emptied is a machine you have to repair from another seat.
  local edits = {}
  for _, m in ipairs({ "File", "View", "Tools", "System", "Settings", "Help" }) do
    edits[#edits + 1] = { remove = m, menu = true }
  end
  local S = stateWith({ ["/root/.menu.cfg"] = cfg(edits) })
  local menus = draw.buildMenuDefs(S)
  ok("emptying the bar falls back to the built-ins", #menus > 0)
  ok("...and it is the real one", labels(menus):find("System") ~= nil)
end

-- ══════════════════════════════════════════════════════════════════════
-- Sessions do not leak into each other
-- ══════════════════════════════════════════════════════════════════════
do
  -- buildMenuDefs must hand back a fresh copy: a per-seat edit that
  -- mutated a shared table would show up on the other seat.
  local a = draw.buildMenuDefs(stateWith({ ["/root/.menu.cfg"] =
    cfg({ { add = "OnlyA", cmd = "a", menu = "Tools" } }) }))
  local b = draw.buildMenuDefs(stateWith({}))
  ok("seat A has its item", has(itemsOf(a, "Tools"), "OnlyA"))
  ok("seat B does not", not has(itemsOf(b, "Tools"), "OnlyA"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
