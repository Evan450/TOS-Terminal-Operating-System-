-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: command output routing                  ║
-- ║                                                            ║
-- ║  A command's output should land on the LIGHTEST surface    ║
-- ║  that fits — not open a whole tab for a couple of lines.   ║
-- ║   0 → none   1 → status row   ≤MAX → inline   long → tab    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_output_routing.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;" .. package.path
local helpers = require("shell.panels.helpers")

print("=== output routing Tests ===")
print()

eq("0 lines -> none",        "none",   helpers.routeOutput(0, 8))
eq("1 line -> status row",   "status", helpers.routeOutput(1, 8))
eq("2 lines -> inline (no tab)", "inline", helpers.routeOutput(2, 8))
eq("MAX lines -> inline",    "inline", helpers.routeOutput(8, 8))
eq("MAX+1 -> tab",           "tab",    helpers.routeOutput(9, 8))
eq("very long -> tab",       "tab",    helpers.routeOutput(200, 8))
eq("default MAX is 8 (no arg)", "tab", helpers.routeOutput(9))
eq("nil count -> none",      "none",   helpers.routeOutput(nil, 8))

-- The key behaviour the operator asked for: a few lines do NOT open a tab.
test("a 3-line result stays inline (not a tab)", helpers.routeOutput(3, 8) == "inline")
test("only genuinely long output earns a tab", helpers.routeOutput(40, 8) == "tab")

-- The inline draw clamps to the rows between LIST_TOP and OUT_ROW (mirrors
-- draw.outLines) so it can never overrun the file list.
local function clampInline(nLines, listTop, outRow)
  return math.min(nLines, outRow - listTop + 1)
end
eq("inline clamp fits the area", 4, clampInline(4, 5, 23))   -- 4 lines, lots of room
eq("inline clamp never overruns", 3, clampInline(50, 5, 7))  -- tiny area: rows 5..7

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
