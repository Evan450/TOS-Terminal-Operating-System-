-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: GPU hot-removal guard (#REV finding #3)  ║
-- ║                                                            ║
-- ║  Pulling the screen/GPU mid-frame used to raise "no        ║
-- ║  screen" out of display.set straight into shell draw code. ║
-- ║  The guard wraps the proxy once in display.init: draws     ║
-- ║  no-op after the first failure, getters return last-known  ║
-- ║  values, a tos_display_lost signal fires exactly once, and ║
-- ║  display.init(newProxy) is the reattach path.              ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_display_lost.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local pushed = {}
package.loaded["component"] = { list = function() return function() end end }
package.loaded["computer"] = {
  uptime = function() return 0 end,
  freeMemory = function() return 1000000 end,
  pushSignal = function(...) pushed[#pushed + 1] = { ... } end,
}
package.path = "tos/?.lua;" .. package.path
local display = require("kernel.display")

print("=== display GPU hot-removal guard Tests ===")
print()

-- A fake GPU whose every method raises "no screen" once killed.
local function fakeGpu(addr)
  local alive = true
  local calls = {}
  local g = { address = addr }
  local function mk(name, ...)
    local rets = { ... }
    g[name] = function(...)
      if not alive then error("no screen") end
      calls[#calls + 1] = name
      return (table.unpack or unpack)(rets)
    end
  end
  mk("setResolution", true)
  mk("getResolution", 80, 25)
  mk("maxResolution", 80, 25)
  mk("getDepth", 8)
  mk("setBackground", true)
  mk("setForeground", true)
  mk("fill", true)
  mk("set", true)
  mk("copy", true)
  return g, function() alive = false end, calls
end

-- ── Healthy init + draw ────────────────────────────────────────────
local g1, kill1, calls1 = fakeGpu("gpu-one")
display.init(g1, 80, 25)
test("init leaves isLost() false", display.isLost() == false)
test("draws reach the raw GPU", #calls1 > 0)
local okDraw = pcall(display.set, 2, 2, "hello", 0xFFFFFF, 0x000000)
test("display.set works while healthy", okDraw)

-- ── Hardware vanishes mid-session ──────────────────────────────────
kill1()
local okLost = pcall(display.set, 2, 3, "after pull", 0xFFFFFF, 0x000000)
test("display.set does NOT raise after GPU pull", okLost)
test("guard tripped: isLost() true", display.isLost() == true)
eq("tos_display_lost pushed once", 1, #pushed)
eq("signal name", "tos_display_lost", pushed[1] and pushed[1][1])

-- Subsequent draws stay quiet and don't re-push.
local okAgain = pcall(function()
  display.set(2, 4, "still quiet", 0xFFFFFF, 0x000000)
  display.clear(0x000000)
end)
test("later draws still no-op cleanly", okAgain)
eq("no duplicate lost signal", 1, #pushed)

-- Getters keep returning numbers (callers do `W,H = getResolution()`).
local gw = display.getGpu()
local rw, rh = gw.getResolution()
test("getResolution still returns numbers", type(rw) == "number" and type(rh) == "number")
eq("getDepth falls back to last-known", 8, gw.getDepth())

-- ── Reattach: display.init(new proxy) clears the lost state ───────
local g2, _, calls2 = fakeGpu("gpu-two")
display.init(g2, 80, 25)
test("re-init clears isLost()", display.isLost() == false)
local before = #calls2
pcall(display.set, 2, 2, "back", 0xFFFFFF, 0x000000)
test("draws reach the NEW GPU after reattach", #calls2 > before)
eq("still only the one historical lost signal", 1, #pushed)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
