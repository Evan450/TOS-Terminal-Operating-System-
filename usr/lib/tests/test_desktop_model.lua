-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: panels.desktop (app model)               ║
-- ║                                                            ║
-- ║  Pure model only: buildApps (registry tier gates, needs    ║
-- ║  gates, package-command tiles, the visible cap) and        ║
-- ║  resolveApp (activation descriptors). The interactive      ║
-- ║  loop is exercised in-emulator.                            ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_desktop_model.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
local desktop = require("shell.panels.desktop")

print("=== panels.desktop Tests ===")
print()

-- A fake command registry: chat/mail/launcher exist with real tiers.
local REG = {
  monitor = { tier = 0 }, chat = { tier = 1 }, mail = { tier = 1 },
  help = { tier = 0 }, tutorial = { tier = 0 },
  ["tape-menu"] = { tier = 1 },
}
local NEEDS = { chat = "net", mail = "net", ["tape-menu"] = "component:tape_drive" }

local function findApp(apps, id)
  for _, a in ipairs(apps) do if a.id == id then return a end end
  return nil
end

-- ── Full-tier operator on a networked box ──────────────────────────
local apps = desktop.buildApps({
  entry = function(n) return REG[n] end,
  needMet = function(tok) return true end,
  needs = NEEDS,
  pkgCommands = { tetris = "/x/tetris.lua", mousetest = "/x/mt.lua" },
  userTier = 3,
})
test("root+net: Files present", findApp(apps, "files") ~= nil)
test("root+net: Chat present", findApp(apps, "chat") ~= nil)
test("root+net: Settings present", findApp(apps, "settings") ~= nil)
test("root+net: Log Out present", findApp(apps, "logout") ~= nil)
test("root+net: pkg tile tetris present", findApp(apps, "pkg:tetris") ~= nil)
test("root+net: pkg tiles sorted", (function()
  local last
  for _, a in ipairs(apps) do
    if a.pkg then
      if last and a.label < last then return false end
      last = a.label
    end
  end
  return true
end)())

-- ── No network: chat/mail tiles disappear ──────────────────────────
local noNet = desktop.buildApps({
  entry = function(n) return REG[n] end,
  needMet = function(tok) return tok ~= "net" end,
  needs = NEEDS,
  pkgCommands = {},
  userTier = 3,
})
test("no net: Chat hidden", findApp(noNet, "chat") == nil)
test("no net: Mail hidden", findApp(noNet, "mail") == nil)
test("no net: Monitor still there", findApp(noNet, "monitor") ~= nil)

-- ── Guest tier: tier-1 commands are hidden ─────────────────────────
local guest = desktop.buildApps({
  entry = function(n) return REG[n] end,
  needMet = function() return true end,
  needs = NEEDS,
  pkgCommands = {},
  userTier = 0,
})
test("guest: tape-menu (tier 1) hidden", findApp(guest, "tapemenu") == nil)
test("launcher tile retired (v1.4.0)", findApp(guest, "launcher") == nil)
test("guest: Help (tier 0) visible", findApp(guest, "help") ~= nil)
test("guest: Files visible", findApp(guest, "files") ~= nil)

-- ── Tape Menu tile follows the tape drive ─────────────────────────
local withTape = desktop.buildApps({
  entry = function(n) return REG[n] end,
  needMet = function(tok) return tok ~= "net" end,   -- no net, has tape
  needs = NEEDS,
  pkgCommands = {},
  userTier = 3,
})
test("tape drive present: Tape Menu tile shown", findApp(withTape, "tapemenu") ~= nil)
local noTape = desktop.buildApps({
  entry = function(n) return REG[n] end,
  needMet = function(tok) return tok == "net" end,   -- net, no tape drive
  needs = NEEDS,
  pkgCommands = {},
  userTier = 3,
})
test("no tape drive: Tape Menu tile hidden", findApp(noTape, "tapemenu") == nil)

-- ── Personal tiles from ~/.launcher.cfg (launcher absorbed) ────────
local withMy = desktop.buildApps({
  entry = function(n) return REG[n] end,
  needMet = function() return true end,
  needs = {},
  pkgCommands = { tetris = "/x/t.lua" },
  personal = {
    { label = "Reactor SCRAM", run = "redstone set 3 off" },
    { label = "Door",          run = "redstone toggle 2" },
  },
  userTier = 3,
})
local myTile = findApp(withMy, "my:Reactor SCRAM")
test("personal: ~/.launcher.cfg entry becomes a tile", myTile ~= nil)
eq("personal: tile carries the command", "redstone set 3 off", myTile and myTile.cmd)
test("personal: label fitted to tile width", myTile and #myTile.label <= 12)
test("personal: resolves as a cmd action", desktop.resolveApp(withMy,
  (function() for i, a in ipairs(withMy) do if a.id == "my:Door" then return i end end end)()).type == "cmd")
test("personal: tiles come before pkg tiles", (function()
  local myIdx, pkgIdx
  for i, a in ipairs(withMy) do
    if a.id == "my:Door" then myIdx = i end
    if a.pkg then pkgIdx = pkgIdx or i end
  end
  return myIdx and pkgIdx and myIdx < pkgIdx
end)())

-- ── Package-tile cap is reported, never silent ─────────────────────
local many = {}
for i = 1, 30 do many["tool" .. string.format("%02d", i)] = "/x/t.lua" end
local capped, dropped = desktop.buildApps({
  entry = function() return nil end,
  needMet = function() return true end,
  needs = {},
  pkgCommands = many,
  userTier = 3,
})
local pkgCount = 0
for _, a in ipairs(capped) do if a.pkg then pkgCount = pkgCount + 1 end end
eq("cap: at most 24 pkg tiles", 24, pkgCount)
eq("cap: dropped count reported", 6, dropped)

-- ── A pkg command that shadows a builtin cmd isn't duplicated ──────
local shadow = desktop.buildApps({
  entry = function(n) return REG[n] end,
  needMet = function() return true end,
  needs = {},
  pkgCommands = { monitor = "/x/monitor.lua" },
  userTier = 3,
})
local monitors = 0
for _, a in ipairs(shadow) do if a.cmd == "monitor" then monitors = monitors + 1 end end
eq("dedupe: one monitor tile only", 1, monitors)

-- ── resolveApp ─────────────────────────────────────────────────────
eq("resolve: files -> tab", "tab", desktop.resolveApp(apps,
  (function() for i, a in ipairs(apps) do if a.id == "files" then return i end end end)()).type)
eq("resolve: settings -> settings", "settings", desktop.resolveApp(apps,
  (function() for i, a in ipairs(apps) do if a.id == "settings" then return i end end end)()).type)
eq("resolve: logout -> logout", "logout", desktop.resolveApp(apps,
  (function() for i, a in ipairs(apps) do if a.id == "logout" then return i end end end)()).type)
local chatIdx = (function() for i, a in ipairs(apps) do if a.id == "chat" then return i end end end)()
local act = desktop.resolveApp(apps, chatIdx)
eq("resolve: chat -> cmd", "cmd", act.type)
eq("resolve: chat carries the command", "chat", act.cmd)
eq("resolve: out-of-range -> none", "none", desktop.resolveApp(apps, 999).type)
eq("resolve: nil apps -> none", "none", desktop.resolveApp(nil, 1).type)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
