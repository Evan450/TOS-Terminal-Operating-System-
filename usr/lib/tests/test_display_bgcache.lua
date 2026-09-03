-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: the GPU colour cache cannot go stale     ║
-- ║                                                            ║
-- ║  display._setFg/_setBg skip the gpu call when the colour   ║
-- ║  already matches the last one set — each call crosses the  ║
-- ║  OC bridge and a full redraw issues 50-100 of them.        ║
-- ║                                                            ║
-- ║  That optimisation is only correct while the cache tells   ║
-- ║  the truth. display.scrollUp set the GPU to black DIRECTLY ║
-- ║  (gpu.setBackground(0x000000)) without updating _lastBg,   ║
-- ║  so afterwards the cache claimed a colour the hardware was ║
-- ║  no longer at. The next fill in that same colour was then  ║
-- ║  SKIPPED, and painted on black.                            ║
-- ║                                                            ║
-- ║  Observed as: the status bar's widgets (Disk/Clock/User/   ║
-- ║  Uptime/View) drawing on black instead of statusbar_bg,    ║
-- ║  while the menu bar — whose colour differed from the stale ║
-- ║  value, so its call still fired — stayed correct.          ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_display_bgcache.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1
    print("  PASS: " .. name .. "  (got " .. tostring(actual) .. ")")
  else failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")") end
end

-- ── A GPU that remembers what it was actually told ─────────────────
-- The point of the whole test: `real` is the hardware's true state, and
-- it only moves when setBackground is genuinely called. A cache that
-- lies shows up as fills landing with the wrong `real` value.
local gpu = { real_bg = 0x000000, real_fg = 0xFFFFFF, fills = {}, bgCalls = 0 }
function gpu.setBackground(c) gpu.real_bg = c; gpu.bgCalls = gpu.bgCalls + 1 end
function gpu.setForeground(c) gpu.real_fg = c end
function gpu.getBackground() return gpu.real_bg end
function gpu.getForeground() return gpu.real_fg end
function gpu.getResolution() return 80, 25 end
function gpu.maxResolution() return 80, 25 end
function gpu.setResolution() return true end
function gpu.getDepth() return 8 end
function gpu.getViewport() return 80, 25 end
function gpu.fill(x, y, w, h, ch)
  gpu.fills[#gpu.fills + 1] = { y = y, bg = gpu.real_bg, fg = gpu.real_fg }
  return true
end
function gpu.set(x, y, s) 
  gpu.fills[#gpu.fills + 1] = { y = y, bg = gpu.real_bg, fg = gpu.real_fg, set = true }
  return true
end
function gpu.copy() return true end
function gpu.bind() return true end
function gpu.getScreen() return "screen-1" end

package.loaded["component"] = {
  list = function() return function() end end,
  proxy = function() return gpu end,
}
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1000000 end, pushSignal = function() end }
package.path = "tos/?.lua;" .. package.path

local display = require("kernel.display")
display.init(gpu)

print("=== display bg-cache Tests ===")
print()

local BLUE = 0x336699        -- stands in for statusbar_bg

-- ── 1. The cache does its job when nothing lies to it ──────────────
print("-- the optimisation itself --")
do
  gpu.fills, gpu.bgCalls = {}, 0
  display.fill(1, 5, 80, 1, " ", 0xFFFFFF, BLUE)
  local firstCalls = gpu.bgCalls
  display.fill(1, 6, 80, 1, " ", 0xFFFFFF, BLUE)
  test("a repeated colour skips the gpu call", gpu.bgCalls == firstCalls)
  eq("...and both rows still landed on it", BLUE, gpu.fills[#gpu.fills].bg)
end

-- ── 2. scrollUp must not leave the cache lying ─────────────────────
-- This is the regression. Draw in BLUE (cache now says BLUE, hardware
-- is BLUE), scroll (hardware goes BLACK), then draw in BLUE again. If
-- the cache still claims BLUE the call is skipped and the row is black.
print()
print("-- after a scroll --")
do
  gpu.fills, gpu.bgCalls = {}, 0
  display.fill(1, 5, 80, 1, " ", 0xFFFFFF, BLUE)
  eq("baseline row is blue", BLUE, gpu.fills[#gpu.fills].bg)

  display.scrollUp(1, 25)
  eq("scroll left the hardware black", 0x000000, gpu.real_bg)

  display.fill(1, 25, 80, 1, " ", 0xFFFFFF, BLUE)
  eq("the status row is STILL blue after a scroll", BLUE,
    gpu.fills[#gpu.fills].bg)
  test("...because the skipped call was re-issued", gpu.real_bg == BLUE)
end

-- ── 3. Foreground has the identical hazard ─────────────────────────
-- scrollUp sets the foreground white by the same direct route, so the
-- same staleness applies to text colour.
print()
print("-- foreground too --")
do
  gpu.fills = {}
  local GOLD = 0xFFD75A
  display.fill(1, 5, 80, 1, " ", GOLD, BLUE)
  eq("baseline fg is gold", GOLD, gpu.fills[#gpu.fills].fg)
  display.scrollUp(1, 25)
  eq("scroll left the hardware fg white", 0xFFFFFF, gpu.real_fg)
  display.fill(1, 25, 80, 1, " ", GOLD, BLUE)
  eq("gold survives the scroll", GOLD, gpu.fills[#gpu.fills].fg)
end

-- ── 4. A scroll that does nothing must not touch the cache either ──
print()
print("-- degenerate scroll --")
do
  display.fill(1, 5, 80, 1, " ", 0xFFFFFF, BLUE)
  display.scrollUp(10, 10)          -- rows < 1, returns early
  gpu.fills = {}
  display.fill(1, 6, 80, 1, " ", 0xFFFFFF, BLUE)
  eq("no-op scroll leaves the row blue", BLUE, gpu.fills[#gpu.fills].bg)
end

-- ── 5. An outsider can write the GPU, and must be able to say so ──
-- scrollUp was ONE way the hardware moves without this module knowing.
-- It is not the only one: the OpenOS-compat term.gpu() proxy hands a
-- program raw set/fill/setBackground for its own drawing, and the
-- package picker paints with raw gpu calls on purpose so it still works
-- when kernel.display is not up. Both leave this cache asserting a
-- colour that stopped being true, and the next fill skips itself.
--
-- The escape hatch is display.invalidateColors(). It has to genuinely
-- force the next call through -- an invalidation that merely LOOKS like
-- one leaves the exact bug in place, one layer further from the fix.
print()
print("-- an outside write, declared --")
do
  display.fill(1, 5, 80, 1, " ", 0xFFFFFF, BLUE)   -- cache: bg is BLUE

  -- Something else drives the hardware. This module is not told.
  gpu.setBackground(0x000000)
  gpu.setForeground(0x00FF00)
  eq("the hardware really moved", 0x000000, gpu.real_bg)

  test("display.invalidateColors exists", type(display.invalidateColors) == "function")
  display.invalidateColors()

  gpu.fills = {}
  display.fill(1, 25, 80, 1, " ", 0xFFFFFF, BLUE)
  eq("the row is blue again", BLUE, gpu.fills[#gpu.fills].bg)
  eq("...and the foreground was re-issued too", 0xFFFFFF, gpu.fills[#gpu.fills].fg)
end

-- ...and the same scenario WITHOUT the declaration still breaks, which
-- is what proves the test above is measuring the fix and not the fake.
print()
print("-- an outside write, undeclared (the bug) --")
do
  display.fill(1, 5, 80, 1, " ", 0xFFFFFF, BLUE)
  gpu.setBackground(0x000000)
  gpu.fills = {}
  display.fill(1, 25, 80, 1, " ", 0xFFFFFF, BLUE)
  eq("stays black -- the call was skipped", 0x000000, gpu.fills[#gpu.fills].bg)
end

-- ── 6. withContext must not restore a cache its callee invalidated ──
-- This is the one that survived four rounds of hardware testing.
--
-- withContext swaps in another GPU, runs a draw, swaps back, and puts
-- the colour cache back the way it found it. That is right when the
-- context really is OTHER hardware: the callee drew somewhere else, so
-- this GPU is still exactly where we left it.
--
-- On a single-seat machine it is not other hardware. screen.displayProxy
-- forwards statusBar/menuBar/scrollUp/box through withContext with the
-- seat's GPU -- which, when there is one GPU, is THIS GPU. The callee
-- moves the glass, and then the restore reinstalls a cache describing a
-- state that no longer exists. The next fill in that colour is skipped
-- and lands on whatever the forwarded draw left. scrollUp leaves BLACK,
-- and the status bar is drawn through exactly this path.
print()
print("-- withContext on the same GPU --")
do
  -- Start honest: the control block above deliberately left the cache
  -- lying, and inheriting that would make this block fail for the wrong
  -- reason.
  display.invalidateColors()
  display.fill(1, 5, 80, 1, " ", 0xFFFFFF, BLUE)      -- cache now says BLUE
  eq("cache is primed to blue", BLUE, gpu.real_bg)

  -- A forwarded draw, on the SAME gpu, that leaves the glass black.
  display.withContext(gpu, 80, 25, function()
    display.fill(1, 6, 80, 1, " ", 0xFFFFFF, 0x000000)
  end)
  eq("the callee left the hardware black", 0x000000, gpu.real_bg)

  gpu.fills = {}
  display.fill(1, 25, 80, 1, " ", 0xFFFFFF, BLUE)
  eq("the status row is blue, not black", BLUE, gpu.fills[#gpu.fills].bg)
end

-- ...and the optimisation must SURVIVE where it is genuinely sound: a
-- real second GPU is untouched by the callee, so restoring its cache is
-- correct and the skip should still happen. A "fix" that just disabled
-- the cache would pass the test above and cost every redraw.
print()
print("-- withContext on a different GPU --")
do
  local other = { real_bg = 0x000000, real_fg = 0xFFFFFF, fills = {} }
  for k, v in pairs(gpu) do if type(v) == "function" then other[k] = v end end
  other.address = "other-gpu"
  gpu.address = "this-gpu"
  function other.setBackground(c) other.real_bg = c end
  function other.setForeground(c) other.real_fg = c end
  function other.fill() return true end
  function other.set() return true end
  function other.getResolution() return 80, 25 end

  display.invalidateColors()
  display.fill(1, 5, 80, 1, " ", 0xFFFFFF, BLUE)      -- cache: BLUE, on gpu
  display.withContext(other, 80, 25, function()
    display.fill(1, 6, 80, 1, " ", 0xFFFFFF, 0x000000)  -- blackens OTHER
  end)
  eq("this GPU was not touched", BLUE, gpu.real_bg)

  gpu.bgCalls = 0
  display.fill(1, 7, 80, 1, " ", 0xFFFFFF, BLUE)
  eq("the skip is still taken for an untouched GPU", 0, gpu.bgCalls)
  gpu.address, other.address = nil, nil
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
