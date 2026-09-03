-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Screen Resolution Policy           ║
-- ║  - chooseResolution: max / explicit / auto-density /  ║
-- ║    auto-cap fallback, clamping + warnings             ║
-- ║  - specFromConfig parsing                             ║
-- ║  - the T3 "tiny text" case downscales                 ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_screen_res.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- screen.lua requires component + computer at load; stub them.
package.loaded["component"] = { list = function() return function() return nil end end,
                                proxy = function() return nil end, invoke = function() end }
package.loaded["computer"] = { uptime = function() return 0 end }

local here = (arg and arg[0]) or "usr/lib/tests/test_screen_res.lua"
local base = here:gsub("[^/\\]*$", "")
local screen
for _, p in ipairs({ base .. "../../../tos/kernel/screen.lua",
    "tos/kernel/screen.lua", "TOS-Dev/tos/kernel/screen.lua" }) do
  local chunk = loadfile(p)
  if chunk then screen = chunk(); break end
end
if not screen then
  print("FAIL: could not load screen.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== Screen Resolution Policy Tests ===")
print()

local function wh(spec, maxW, maxH, bw, bh)
  local w, h = screen.chooseResolution(spec, maxW, maxH, bw, bh)
  return w .. "x" .. h
end

-- max mode: always the hardware max.
test("max -> hardware max", "160x50", wh({ mode = "max" }, 160, 50))

-- explicit size within max: exact, no warning.
do
  local w, h, note = screen.chooseResolution({ mode = "size", w = 80, h = 25 }, 160, 50)
  test("size within max exact", "80x25", w .. "x" .. h)
  test("size within max: no warning", true, note == nil)
end

-- explicit size exceeding max: clamped + warning.
do
  local w, h, note = screen.chooseResolution({ mode = "size", w = 200, h = 80 }, 160, 50)
  test("size over max clamps", "160x50", w .. "x" .. h)
  test("size over max warns", true, type(note) == "string" and note:find("exceeds") ~= nil)
end

-- AUTO density may only RAISE the resolution above the ~80x25 baseline
-- (for big multiblock walls where max = tiny glyphs); it must never
-- shrink an ordinary screen below it.
local autoSpec = { mode = "auto", colsPerBlock = 10, rowsPerBlock = 4,
                   prefW = 80, prefH = 25 }

-- Big walls: density above the baseline is honored (clamped to max).
test("auto density 16x10 wall (T3) uses density", "160x40",
  wh(autoSpec, 160, 50, 16, 10))
test("auto density 12x8 wall (T3)", "120x32", wh(autoSpec, 160, 50, 12, 8))

-- Density below baseline gets floored at 80x25 (clamped to max).
test("auto 8x6 blocks floors rows at baseline", "80x25",
  wh(autoSpec, 160, 50, 8, 6))
test("auto density clamped to T2 max", "80x25", wh(autoSpec, 80, 25, 8, 6))

-- #REV-3 (critical regression) — ordinary screens keep their full
-- baseline resolution. The old 40x12 minimum-floor collapsed every
-- screen up to 4 blocks wide (1x1 and 3x2 included) to 40x12 at boot:
-- login rendered at a fraction of the real resolution and stale-size
-- drawing went off-screen, so the machine looked bricked after login.
test("1x1 screen keeps 80x25 baseline (T2)", "80x25", wh(autoSpec, 80, 25, 1, 1))
test("1x1 screen keeps 80x25 baseline (T3)", "80x25", wh(autoSpec, 160, 50, 1, 1))
test("3x2 screen keeps 80x25 baseline", "80x25", wh(autoSpec, 80, 25, 3, 2))
test("2x1 screen keeps 80x25 baseline", "80x25", wh(autoSpec, 80, 25, 2, 1))

-- AUTO fallback (no block info): ~80x25 cap, clamped to max.
test("auto fallback no blocks (T3)", "80x25", wh(autoSpec, 160, 50))
test("auto fallback no blocks (T1 uses max)", "50x16", wh(autoSpec, 50, 16))

-- specFromConfig parsing. (config.get is called as cfg.get(key) in code.)
local function cfgOf(t) return { get = function(k) return t[k] end } end

do
  local s = screen.specFromConfig(cfgOf({ screenRes = "max" }))
  test("specFromConfig max", "max", s.mode)
end
do
  local s = screen.specFromConfig(cfgOf({ screenRes = "100x40" }))
  test("specFromConfig explicit mode", "size", s.mode)
  test("specFromConfig explicit w", 100, s.w)
  test("specFromConfig explicit h", 40, s.h)
end
do
  local s = screen.specFromConfig(cfgOf({ screenRes = "auto", screenColsPerBlock = 12 }))
  test("specFromConfig auto", "auto", s.mode)
  test("specFromConfig colsPerBlock override", 12, s.colsPerBlock)
end
do
  local s = screen.specFromConfig(nil)
  test("specFromConfig nil-safe defaults to auto", "auto", s.mode)
end

print()
print("Results: " .. passed .. " passed, " .. failed .. " failed")
if failed == 0 then print("*** ALL TESTS PASSED ***"); return true
else print("*** TESTS FAILED ***"); return false end
