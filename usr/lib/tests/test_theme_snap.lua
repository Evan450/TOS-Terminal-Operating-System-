-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: display snapToT2 (T2 palette snapping)   ║
-- ║                                                            ║
-- ║  Pins the "greys snap to GREYS" rule. The T2 palette has   ║
-- ║  no mid-grey, and by raw channel distance 0x909090 sits    ║
-- ║  closer to 0xCC66CC (pale magenta) than to 0xCCCCCC — so   ║
-- ║  the default preset's `dim` text rendered PINK on a T2     ║
-- ║  GPU (v1.4.0 emulator round). Near-achromatic input must   ║
-- ║  only ever land on an achromatic palette entry.            ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_theme_snap.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eqx(name, expected, actual)
  test(string.format("%s  (got %06X)", name, actual or -1), expected == actual)
end

package.loaded["component"] = { list = function() return function() end end }
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1000000 end }
package.path = "tos/?.lua;" .. package.path
local display = require("kernel.display")
local snap = display._snapToT2

print("=== display snapToT2 Tests ===")
print()

-- ── The pink-dim regression itself ─────────────────────────────────
eqx("0x909090 (default preset dim) -> light grey, NOT magenta",
  0xCCCCCC, snap(0x909090))

-- ── Greys land on greys across the whole ramp ──────────────────────
local GREYS = { [0xFFFFFF]=true, [0xCCCCCC]=true, [0x333333]=true, [0x000000]=true }
local allGrey = true
for v = 0, 255, 5 do
  local got = snap(v * 0x010101)
  if not GREYS[got] then allGrey = false; break end
end
test("every pure grey 0x000000..0xFFFFFF snaps to an achromatic entry", allGrey)
eqx("near-black -> black", 0x000000, snap(0x141414))
eqx("dark grey -> 0x333333", 0x333333, snap(0x404040))
eqx("soft white (default fg 0xE6E6E6) -> white", 0xFFFFFF, snap(0xE6E6E6))

-- Slightly-tinted greys (spread <= 32) count as achromatic too.
test("slightly tinted grey stays achromatic", GREYS[snap(0x8E929E)] == true)

-- ── Chromatic colors are unaffected by the guard ───────────────────
eqx("teal border -> palette blue", 0x6699FF, snap(0x2FB8C6))
eqx("gold title -> palette gold", 0xFFCC33, snap(0xFFD75A))
eqx("green highlight -> palette green", 0x33CC33, snap(0x42D77D))
-- 0xFF5C57 (salmon) genuinely sits nearer 0xFF6699 than 0xFF3333 —
-- chromatic snapping is untouched by the grey guard; pin the actual value.
eqx("salmon error -> nearest palette red-pink", 0xFF6699, snap(0xFF5C57))

-- ── Palette entries are fixed points ───────────────────────────────
local fixed = true
for _, c in ipairs({ 0xFFFFFF, 0xFFCC33, 0xCC66CC, 0x6699FF, 0xFFFF33,
    0x33CC33, 0xFF6699, 0x333333, 0xCCCCCC, 0x336699, 0x9933CC,
    0x333399, 0x663300, 0x336600, 0xFF3333, 0x000000 }) do
  if snap(c) ~= c then fixed = false; break end
end
test("every palette entry snaps to itself", fixed)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
