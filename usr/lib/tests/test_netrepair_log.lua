-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the online repair logs through the module    ║
-- ║                                                                ║
-- ║  netrepair.deps took `_TOS.log` for its log. On a booted       ║
-- ║  machine that is kernel/init.lua's wrapper, a FUNCTION         ║
-- ║  (src, msg), so `deps.log.warn(...)`, called after each file   ║
-- ║  an applied repair replaces, indexed a function and raised,    ║
-- ║  right after the first file was written. The fake worlds the   ║
-- ║  repair was tested in never set _TOS.log. Found when           ║
-- ║  kernel/strip.lua copied the line and crashed on the headless  ║
-- ║  runner. Both now take the log module.                         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_netrepair_log.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }
local logged = {}
local LOGMOD = { warn = function(src, msg) logged[#logged + 1] = msg end,
                 info = function(src, msg) logged[#logged + 1] = msg end }
package.loaded["kernel.log"] = LOGMOD
-- As kernel/init.lua sets it on a real machine: a function, not the module.
_G._TOS = { log = function(src, msg) end, fs = {} }

for _, mod in ipairs({ "netrepair", "strip" }) do
  local m = dofile("tos/kernel/" .. mod .. ".lua")
  local d = m.deps({ manifest = {} })
  test(mod .. ".deps takes the log module", d.log == LOGMOD, type(d.log))
  test(mod .. ": its warn/info can be called", type(d.log) == "table"
    and type(d.log.warn or d.log.info) == "function")
  local given = { warn = function() end }
  test(mod .. ": a log the caller passes still wins", m.deps({ manifest = {}, log = given }).log == given)
end

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
