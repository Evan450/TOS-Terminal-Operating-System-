-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the key bar is measured in COLUMNS, and     ║
-- ║  never cut mid-word                                           ║
-- ║                                                               ║
-- ║  The operator's screenshot showed calc's bottom bar ending in ║
-- ║  "^Q Qui" on an 80-column screen. Two separate faults:        ║
-- ║                                                               ║
-- ║   1. pad() measured BYTES. The bar separates hints with "·",  ║
-- ║      which is 2 bytes in UTF-8, so a 68-COLUMN bar measured   ║
-- ║      73 and was sliced even though it fitted comfortably.     ║
-- ║      Five separators, five phantom columns, "t " lost.        ║
-- ║                                                               ║
-- ║   2. Even on a genuinely narrow screen, slicing mid-word      ║
-- ║      reads as a rendering fault. Whole hints are dropped from ║
-- ║      the right instead — and the way OUT of the program is    ║
-- ║      never one of the casualties.                             ║
-- ║                                                               ║
-- ║  The same byte-vs-column mistake was live in the Optional     ║
-- ║  Utilities picker's rails (see test_installer).               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/calc/test_calc_keybar.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- calc/init.lua requires these at load time; it never touches them here.
package.loaded["component"] = { list = function() return function() return nil end end }
package.loaded["computer"]  = { uptime = function() return 0 end,
                                pullSignal = function() return nil end }

package.path = "modules/?.lua;modules/?/init.lua;"
  .. "../modules/?.lua;../modules/?/init.lua;" .. package.path
local calc = require("calc")
local T = calc.text

print("=== calc key bar: columns, not bytes ===")
print()

test("calc exports its text helpers", type(T) == "table" and type(T.fitHints) == "function")

-- ── ulen counts COLUMNS ───────────────────────────────────────────
local DOT = "\194\183"                     -- U+00B7 MIDDLE DOT, 2 bytes
eq("a middle dot is 2 bytes", 2, #DOT)
eq("...but ONE column", 1, T.ulen(DOT))
eq("ASCII is unchanged", 5, T.ulen("hello"))
eq("mixed text counts columns", 3, T.ulen("a" .. DOT .. "b"))

-- ── usub slices on character boundaries ───────────────────────────
eq("usub never splits a multi-byte character", "a" .. DOT, T.usub("a" .. DOT .. "b", 1, 2))
eq("usub clamps past the end", "ab", T.usub("ab", 1, 99))
eq("usub of an empty range is empty", "", T.usub("abc", 3, 1))

-- ── pad pads to COLUMNS, not bytes ────────────────────────────────
eq("pad measures the dot as one column", 10, T.ulen(T.pad("a" .. DOT .. "b", 10)))
test("pad does not truncate text that fits",
  T.pad("a" .. DOT .. "b", 10):find(DOT, 1, true) ~= nil)
eq("padLeft also lands on the requested width", 8, T.ulen(T.padLeft("x" .. DOT, 8)))

-- ── THE BUG: the real bar on the real screen ──────────────────────
-- calc draws the bar at column 5 with the ramp caps at both ends, so the
-- room it has is W - 9. On an 80-column screen the full hint set must
-- survive intact — that is exactly what byte-measuring broke.
local HINTS = { "Type/Enter Edit", "^S Save", "^O Open",
                "^E CSV", "Del Clear", "^Q Quit" }
do
  local bar = T.fitHints(HINTS, 80 - 9, "^Q Quit")
  test("on an 80-column screen every hint fits", (function()
    for _, h in ipairs(HINTS) do
      if not bar:find(h, 1, true) then return false end
    end
    return true
  end)())
  test("...and Quit is whole, not '^Q Qui'", bar:find("^Q Quit", 1, true) ~= nil)
  test("...and the bar stays inside its room (" .. T.ulen(bar) .. " cols)",
    T.ulen(bar) <= 80 - 9)
  -- The precise regression: measured in BYTES this bar reads as wider
  -- than the space it has, which is why it used to be cut.
  test("the bar is genuinely wider in bytes than in columns (" ..
    #bar .. "B vs " .. T.ulen(bar) .. "c)", #bar > T.ulen(bar))
end

-- ── A narrow screen drops WHOLE hints ─────────────────────────────
do
  local bar = T.fitHints(HINTS, 30, "^Q Quit")
  test("a narrow bar still fits (" .. T.ulen(bar) .. " cols)", T.ulen(bar) <= 30)
  test("a narrow bar keeps the way out", bar:find("^Q Quit", 1, true) ~= nil)
  -- No partial hint may appear: every hint present must be present whole.
  local sliced = false
  for _, h in ipairs(HINTS) do
    for n = 1, #h - 1 do
      local frag = h:sub(1, n)
      -- A fragment counts as sliced only if it ends the bar's text.
      if bar:match("%s" .. frag:gsub("%W", "%%%0") .. " $") and not bar:find(h, 1, true) then
        sliced = true
      end
    end
  end
  test("no hint is left half-written", not sliced)
end

-- ── Degenerate widths don't loop or crash ─────────────────────────
do
  local ok1 = pcall(T.fitHints, HINTS, 1, "^Q Quit")
  test("a 1-column bar terminates", ok1)
  local ok2, bar2 = pcall(T.fitHints, HINTS, 0, "^Q Quit")
  test("a 0-column bar terminates", ok2)
  test("...and pad clips whatever it returns to 0",
    ok2 and T.ulen(T.pad(bar2, 0)) == 0)
  local ok3, bar3 = pcall(T.fitHints, {}, 40, nil)
  eq("an empty hint list is an empty bar", "", ok3 and bar3)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
