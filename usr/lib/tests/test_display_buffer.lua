-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: display buffer optimization toggle      ║
-- ║                                                            ║
-- ║  The operator can enable/disable the dirty-cell shadow     ║
-- ║  buffer (screen.setBuffer): "off" forces direct draws,     ║
-- ║  "auto" is the memory-gated default, "on" enables it       ║
-- ║  whenever it merely fits. Pins setBuffer/bufferMode and    ║
-- ║  the pure gate decision (_shadowWanted).                   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_display_buffer.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.loaded["component"] = { list = function() return function() end end }
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1000000 end }
package.path = "tos/?.lua;" .. package.path
local screen = require("kernel.screen")

print("=== display buffer Tests ===")
print()

-- ── setBuffer / bufferMode ─────────────────────────────────────────
eq("default mode is auto", "auto", screen.bufferMode())
test("setBuffer off ok", (screen.setBuffer("off")))
eq("mode reads back off", "off", screen.bufferMode())
test("setBuffer on ok", (screen.setBuffer("on")))
eq("mode reads back on", "on", screen.bufferMode())
test("setBuffer auto ok", (screen.setBuffer("auto")))
test("invalid mode rejected", not (screen.setBuffer("turbo")))
eq("invalid mode leaves last value", "auto", screen.bufferMode())

-- ── Pure gate decision (_shadowWanted) ─────────────────────────────
local base, reserve = 256 * 1024, 384 * 1024   -- 80x25-ish + the OOM headroom
local plenty = base + reserve + 1               -- comfortably over the auto bar
local tight  = base + 1                          -- fits the shadow, no headroom
local none   = base - 1                          -- doesn't even fit

test("off  → never, even with plenty", not screen._shadowWanted("off", plenty, base, reserve))
test("auto → on with headroom",            screen._shadowWanted("auto", plenty, base, reserve))
test("auto → OFF when only just fits (OOM guard)",
  not screen._shadowWanted("auto", tight, base, reserve))
test("on   → enabled when it merely fits", screen._shadowWanted("on", tight, base, reserve))
test("on   → still off when it can't fit", not screen._shadowWanted("on", none, base, reserve))
test("unknown mode treated as auto",       screen._shadowWanted("???", plenty, base, reserve))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
