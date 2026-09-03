-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: tape-authenticator menu wire format      ║
-- ║                                                            ║
-- ║  The TAUTH2 image gained an optional MENU region after the ║
-- ║  log (the operator's personal launcher toolbox). build +   ║
-- ║  parse must round-trip every combination, and rewriting    ║
-- ║  one region must not corrupt the other.                    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_tape_menu_format.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- The module requires component/computer at load; stub them (the format
-- functions use neither).
package.loaded["component"] = { list = function() return function() return nil end end,
                                proxy = function() return nil end }
package.loaded["computer"] = { uptime = function() return 0 end, pullSignal = function() end }

local here = (arg and arg[0]) or "usr/lib/tests/test_tape_menu_format.lua"
local base = here:gsub("[^/\\]*$", "")
local mod
for _, p in ipairs({
    base .. "../../../../TOS-Extras/modules/tape-authenticator/init.lua",
    "../TOS-Extras/modules/tape-authenticator/init.lua",
    "TOS-Extras/modules/tape-authenticator/init.lua" }) do
  local chunk = loadfile(p); if chunk then mod = chunk(); break end
end
if not mod or not mod._format then
  print("FAIL: could not load tape-authenticator / _format missing")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local F = mod._format
local MAC = string.rep("a", 64)              -- a 64-hex MAC placeholder
local body = F.makeBody("OP-7", 4242)

print("=== tape menu wire-format Tests ===")
print()

-- Identity only (no log, no menu).
local p1 = F.parseImage(F.buildImage(body, MAC, "", nil))
test("identity: label parses", "OP-7", p1.label)
test("identity: issuedAt parses", 4242, p1.issuedAt)
test("identity: no log", 0, p1.logLen)
test("identity: no menu", 0, p1.menuLen)

-- Log only.
local p2 = F.parseImage(F.buildImage(body, MAC, "LOGDATA", nil))
test("log only: log round-trips", "LOGDATA", p2.logBlob)
test("log only: no menu", 0, p2.menuLen)

-- Menu only (empty log).
local p3 = F.parseImage(F.buildImage(body, MAC, "", "MENUBYTES"))
test("menu only: menu round-trips", "MENUBYTES", p3.menuBlob)
test("menu only: no log", 0, p3.logLen)

-- Both regions present and independent.
local p4 = F.parseImage(F.buildImage(body, MAC, "THE-LOG", "THE-MENU"))
test("both: log round-trips", "THE-LOG", p4.logBlob)
test("both: menu round-trips", "THE-MENU", p4.menuBlob)
test("both: mac round-trips", MAC, p4.mac)

-- "Rewrite the log, keep the menu": the log-write path passes img.menuBlob.
local imgBoth = F.parseImage(F.buildImage(body, MAC, "OLD-LOG", "KEEP-MENU"))
local rewrittenLog = F.buildImage(imgBoth.body, imgBoth.mac, "NEW-LOG", imgBoth.menuBlob)
local p5 = F.parseImage(rewrittenLog)
test("rewrite log keeps the menu intact", "KEEP-MENU", p5.menuBlob)
test("rewrite log updates the log", "NEW-LOG", p5.logBlob)

-- "Rewrite the menu, keep the log": the menu-write path passes img.logBlob.
local rewrittenMenu = F.buildImage(imgBoth.body, imgBoth.mac, imgBoth.logBlob, "NEW-MENU")
local p6 = F.parseImage(rewrittenMenu)
test("rewrite menu keeps the log intact", "OLD-LOG", p6.logBlob)
test("rewrite menu updates the menu", "NEW-MENU", p6.menuBlob)

-- A legacy TAUTH2 image with NO trailing log/menu length prefixes (identity +
-- mac only) must still parse, reporting empty log + menu.
local legacy = F.parseImage(body .. MAC)
test("legacy image parses", "table", type(legacy))
test("legacy has no log",  0, legacy and legacy.logLen)
test("legacy has no menu", 0, legacy and legacy.menuLen)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
