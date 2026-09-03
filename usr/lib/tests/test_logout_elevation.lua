-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: no logout carries an elevation out with it   ║
-- ║                                                                ║
-- ║  `sudo -s` registers a SECOND, elevated session and points the ║
-- ║  seat at it. Dropping it means three things: put the shell's   ║
-- ║  token back, put the process principal back, and log the       ║
-- ║  elevated session out.                                          ║
-- ║                                                                ║
-- ║  TOS had FIVE ways to log out — the `logout` command, the      ║
-- ║  System menu, the F10 power menu, the ^Q prompt and the        ║
-- ║  Desktop — and only the command did any of it. Its own comment ║
-- ║  states the rule: "never carry elevation across logout". The   ║
-- ║  other four pushed tos_logout straight out, and the kernel's   ║
-- ║  handler retires sessionTokens[seat] — the ORIGINAL login      ║
-- ║  token, a different object from the elevated one.              ║
-- ║                                                                ║
-- ║  WHAT IT COST, stated precisely rather than inflated: the      ║
-- ║  elevated token dies with the shell state, so nobody can       ║
-- ║  present it; there is no session cap to exhaust; and nothing   ║
-- ║  enumerates sessions to an operator. It lingered as a phantom  ║
-- ║  entry until sweepSessions retired it.                         ║
-- ║                                                                ║
-- ║  It is fixed centrally anyway, because sudoDrop ALSO restores  ║
-- ║  the process principal, and that stays harmless only while     ║
-- ║  every logout path also kills the process. The kernel's does   ║
-- ║  today; a "switch user" or a CLI handoff that reused it would  ║
-- ║  not. Five copies of a security rule is four chances to update ║
-- ║  it in the wrong number of places.                             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_logout_elevation.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_logout_elevation.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 4e6 end, pullSignal = function() return nil end,
  beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
  proxy = function() end, isAvailable = function() return false end }

local helpers = require("shell.panels.helpers")

print("=== logout drops the elevation Tests ===")
print()

test("helpers exposes a single logout", type(helpers.logout) == "function")
if type(helpers.logout) ~= "function" then
  print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

-- ── A seat mid-`sudo -s` ───────────────────────────────────────────
local function elevatedSeat()
  local S = { displayIdx = 2, pushed = {}, dropped = false }
  S.E = { push = function(sig, idx) S.pushed[#S.pushed + 1] = { sig, idx } end }
  S._sudo = { origSt = "LOGIN_TOKEN", origPrincipal = { user = "alice", tier = 1 },
              token = "ELEVATED_TOKEN" }
  S.st = "ELEVATED_TOKEN"
  S.sudoDrop = function()
    S.dropped = true
    S.st = S._sudo.origSt
    S._sudo = nil
    return true
  end
  return S
end

do
  local S = elevatedSeat()
  helpers.logout(S)
  test("the elevation was dropped", S.dropped)
  eq("...the seat token is back to the login one", "LOGIN_TOKEN", S.st)
  eq("...and _sudo is cleared", nil, S._sudo)
  eq("the logout signal was still pushed", "tos_logout", S.pushed[1] and S.pushed[1][1])
  eq("...carrying this seat's index", 2, S.pushed[1] and S.pushed[1][2])
  eq("...exactly once", 1, #S.pushed)
end

-- ── Ordering matters: drop BEFORE the signal ───────────────────────
-- The kernel kills the shell process on tos_logout. A drop scheduled after
-- the push would be racing its own death.
do
  local order = {}
  local S = { displayIdx = 1, _sudo = { token = "T" } }
  S.E = { push = function() order[#order + 1] = "push" end }
  S.sudoDrop = function() order[#order + 1] = "drop"; S._sudo = nil; return true end
  helpers.logout(S)
  eq("the elevation is dropped first", "drop", order[1])
  eq("...then the signal goes", "push", order[2])
end

-- ── An ordinary logout is untouched ────────────────────────────────
do
  local S = { displayIdx = 3, pushed = {} }
  S.E = { push = function(sig, idx) S.pushed[#S.pushed + 1] = { sig, idx } end }
  local okCall = pcall(helpers.logout, S)
  test("a seat with no elevation logs out cleanly", okCall)
  eq("...and still pushes the signal", "tos_logout", S.pushed[1] and S.pushed[1][1])
end

-- ── Degenerate states must not throw ───────────────────────────────
-- Logout is the thing an operator reaches for when something is already
-- wrong; it may not be the thing that breaks.
do
  test("no state at all", pcall(helpers.logout, nil))
  test("no event bus", pcall(helpers.logout, { _sudo = { token = "T" },
    sudoDrop = function() end }))
  test("_sudo set but no sudoDrop (core never loaded)",
    pcall(helpers.logout, { displayIdx = 1, _sudo = { token = "T" },
      E = { push = function() end } }))
  local threw = { displayIdx = 1, _sudo = { token = "T" },
    E = { push = function() end } }
  threw.sudoDrop = function() error("boom", 0) end
  test("a sudoDrop that throws does not block the logout",
    pcall(helpers.logout, threw))
end

-- ── Every logout path goes through it ──────────────────────────────
-- The point of the fix is that there is ONE implementation. A future
-- fifth caller that pushes the signal itself would silently reintroduce
-- the divergence, so the sites are checked directly.
print()
print("-- every path uses the shared helper --")
local function readFile(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local fh = io.open(p, "r")
    if fh then local s = fh:read("*a"); fh:close(); return s end
  end
end
local SITES = {
  "tos/shell/panels/menus.lua",
  "tos/shell/panels/events.lua",
  "tos/shell/panels/desktop.lua",
  "tos/shell/panels/commands/core.lua",
}
local totalRaw = 0
for _, rel in ipairs(SITES) do
  local src = readFile(rel)
  test(rel .. " is readable", src ~= nil)
  if src then
    -- Strip comments before counting: a note ABOUT the signal is not a push.
    local code = src:gsub("%-%-[^\n]*", "")
    local raw = 0
    for _ in code:gmatch('push%s*%(%s*"tos_logout"') do raw = raw + 1 end
    -- desktop.lua keeps ONE inline fallback for when helpers cannot load,
    -- and that fallback drops the elevation itself.
    local allowed = (rel:find("desktop", 1, true) and 1) or 0
    totalRaw = totalRaw + raw - allowed
    test(rel .. " pushes tos_logout directly " .. raw .. " time(s), allowed "
      .. allowed, raw <= allowed)
    test(rel .. " calls helpers.logout",
      code:find("helpers.logout", 1, true) ~= nil
      or code:find("S%.sudoDrop") ~= nil)
  end
end
eq("no path pushes the signal without dropping first", 0, totalRaw)

do
  local src = readFile("tos/shell/panels/desktop.lua")
  if src then
    -- The one permitted raw push must sit in the branch that also drops.
    local branch = src:match('act%.type == "logout".-end')
    test("the Desktop's fallback drops the elevation too",
      branch ~= nil and branch:find("sudoDrop", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
