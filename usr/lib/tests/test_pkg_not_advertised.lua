-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: TOS does not advertise packages it lacks    ║
-- ║                                                                ║
-- ║  Reported from a real box: the Mail tile shows on the Home     ║
-- ║  surface of a vanilla install, and clicking it answers "Mail   ║
-- ║  is an add-on and isn't installed on this machine."            ║
-- ║                                                                ║
-- ║  The operator's rule, and it is the right one: the base image  ║
-- ║  should not know or care that a package exists until it is     ║
-- ║  installed. A package brings its own command, its own help and ║
-- ║  optionally its own man page when it arrives. The Book of TOS  ║
-- ║  documents vanilla TOS.                                        ║
-- ║                                                                ║
-- ║  Mail was gated on "net" — the NETWORK, not the package — so   ║
-- ║  every box with a modem advertised it. The gate could not say  ║
-- ║  otherwise, because a command could carry only one dependency  ║
-- ║  token and mail genuinely needs two: the package to exist at   ║
-- ║  all, and a network to be any use.                             ║
-- ║                                                                ║
-- ║  The base stub in extras.lua STAYS. It is the privileged glue  ║
-- ║  that hands the package the shell's display and session, the   ║
-- ║  same relationship `drive` has to blockfs. Not advertising it  ║
-- ║  is a different thing from not having it.                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_not_advertised.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_not_advertised.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 4e6 end, totalMemory = function() return 8e6 end,
  pullSignal = function() return nil end, beep = function() end }
package.loaded["component"] = { list = function() return function() return nil end end,
  proxy = function() return nil end, type = function() return nil end,
  invoke = function() return nil end, isAvailable = function() return false end }

local desktop  = require("shell.panels.desktop")
local commands = require("shell.panels.commands")

print("=== packages are not advertised until installed Tests ===")
print()

-- A machine with a network, a full-tier user, and NO packages at all.
local function deps(installed)
  return {
    entry   = function(name) return { tier = 0, help = name } end,
    needMet = commands.needMet,
    needs   = commands.NEEDS,
    userTier = 3,
    home = true,
    pkgCommands = installed and { mail = "/pkg/mail/mail.lua" } or {},
  }
end

local function hasTile(apps, id)
  for _, a in ipairs(apps) do if a.id == id then return a end end
  return nil
end

-- _TOS.net present (there IS a network), _TOS.pkg reports nothing installed.
_G._TOS = { net = {}, pkg = { info = function() return nil end } }

print("-- a vanilla box with a modem and no packages --")
do
  local apps = desktop.buildApps(deps(false))
  test("some tiles are built at all", #apps > 0)
  eq("...and Mail is NOT one of them", nil, hasTile(apps, "mail"))
  test("Chat still is — it is base, and the modem is present",
    hasTile(apps, "chat") ~= nil)
  test("Settings is still there", hasTile(apps, "settings") ~= nil)
end

print()
print("-- and `help` does not list it either --")
do
  -- helpList walks the live REGISTRY; mail is registered (the stub is base),
  -- so this is the honest end-to-end check that the gate reaches help too.
  local groups = commands.helpList(3)
  local found = false
  for _, g in pairs(groups) do
    for _, row in ipairs(g) do
      if row.name == "mail" or row.name:match("^mail%s") then found = true end
    end
  end
  eq("mail is absent from the command reference", false, found)
end

print()
print("-- install the package and it appears --")
do
  _G._TOS.pkg = { info = function(n) return n == "mail" and { name = "mail" } or nil end }
  local apps = desktop.buildApps(deps(true))
  local tile = hasTile(apps, "mail")
  test("the Mail tile is there now", tile ~= nil)
  if tile then
    eq("...as the proper built-in tile, not a generic package one",
      "Mail", tile.label)
    eq("...with its own glyph", "@", tile.glyph)
  end
  eq("and it is not duplicated by the package-command path",
    nil, hasTile(apps, "pkg:mail"))
end

print()
print("-- installed but no network: still honest --")
do
  _G._TOS.net = nil
  local apps = desktop.buildApps(deps(true))
  eq("no Mail tile without a network to carry it", nil, hasTile(apps, "mail"))
  _G._TOS.net = {}
end

-- ── The mechanism that made it expressible ─────────────────────────
print()
print("-- a command may depend on more than one thing --")
do
  eq("both tokens met", true, commands.needMet({ "module:mail", "net" }))
  _G._TOS.pkg = { info = function() return nil end }
  eq("package missing fails the pair", false, commands.needMet({ "module:mail", "net" }))
  _G._TOS.pkg = { info = function(n) return n == "mail" and {} or nil end }
  _G._TOS.net = nil
  eq("network missing fails the pair", false, commands.needMet({ "module:mail", "net" }))
  _G._TOS.net = {}
  eq("an empty list is no requirement at all", true, commands.needMet({}))
  eq("a single token still works", true, commands.needMet("net"))
  eq("...and an unknown token still fails OPEN (a typo must not hide a command)",
    true, commands.needMet("nonsense:token"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
