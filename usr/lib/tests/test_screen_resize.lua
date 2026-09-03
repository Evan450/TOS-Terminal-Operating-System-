-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the screen resized and TOS was not asked     ║
-- ║                                                                ║
-- ║  d.w/d.h were written in exactly two places — screen.init(),   ║
-- ║  and screen.fitDisplay when TOS itself sets a resolution. Both  ║
-- ║  are cases where TOS is doing the resizing.                     ║
-- ║                                                                ║
-- ║  OpenComputers resizes the glass on its own too: add or break  ║
-- ║  a screen block in-world and the GPU resolution is clamped to   ║
-- ║  the new maximum. It announces that with `screen_resized`,      ║
-- ║  which NOTHING in TOS was listening for.                        ║
-- ║                                                                ║
-- ║  Everything downstream then describes a screen that is not      ║
-- ║  there:                                                         ║
-- ║   * the seat proxy's syncSize compares against d.w/d.h, so      ║
-- ║     with both stale it sees no change and keeps a shadow        ║
-- ║     indexed for the old width — eliding repaints of cells that  ║
-- ║     are not where it thinks they are;                           ║
-- ║   * the panels layout counts SUM_ROW / OUT_ROW / CMD_ROW /      ║
-- ║     STAT_ROW back from S.H, so on a screen that SHRANK the      ║
-- ║     status bar and the prompt are drawn past the bottom edge    ║
-- ║     and clipped — which reads as both of them vanishing.        ║
-- ║                                                                ║
-- ║  OpenOS treats this as load-bearing: lib/tty.lua listens for    ║
-- ║  the signal AND intercepts gpu.setResolution, because "the gpu  ║
-- ║  can change resolution before we get a chance to call events".  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_screen_resize.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_screen_resize.lua"
local base = here:gsub("[^/\\]*$", "")

-- ============================================================
-- A GPU whose resolution can move without TOS asking
-- ============================================================
local W, H = 80, 25
local sets = 0          -- how many gpu.set calls actually crossed the bridge

local gpu = {
  address       = "gpu-resize",
  getScreen     = function() return "screen-resize" end,
  bind          = function() return true end,
  getResolution = function() return W, H end,
  -- The point of the fixture: OC can move this behind TOS's back.
  setResolution = function(w, h) W, H = w, h; return true end,
  maxResolution = function() return 160, 50 end,
  getDepth      = function() return 8 end,
  maxDepth      = function() return 8 end,
  setForeground = function() return true end,
  setBackground = function() return true end,
  getForeground = function() return 0xFFFFFF end,
  getBackground = function() return 0x000000 end,
  set           = function() sets = sets + 1; return true end,
  fill          = function() sets = sets + 1; return true end,
}

package.loaded["component"] = {
  list = function(ctype)
    local given = false
    return function()
      if given then return nil end
      given = true
      if ctype == "gpu"    then return "gpu-resize", "gpu" end
      if ctype == "screen" then return "screen-resize", "screen" end
      return nil
    end
  end,
  proxy  = function() return gpu end,
  invoke = function() return nil end,
  type   = function(a) return a == "gpu-resize" and "gpu" or "screen" end,
}
package.loaded["computer"] = {
  uptime     = function() return 0 end,
  freeMemory = function() return 4 * 1024 * 1024 end,
  pullSignal = function() return nil end,
  beep       = function() end,
}

package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path
local screen = require("kernel.screen")
screen.init()

print("=== external screen resize Tests ===")
print()

-- ── The starting state ─────────────────────────────────────────────
do
  local w, h = screen.getResolution()
  eq("starts at the GPU's resolution (w)", 80, w)
  eq("starts at the GPU's resolution (h)", 25, h)
end

-- ── OC moves the glass without telling TOS ─────────────────────────
-- A screen block is broken; OpenComputers clamps the resolution down and
-- fires screen_resized. This is the raw setResolution, NOT screen.fitDisplay,
-- precisely because TOS is not the one doing it.
gpu.setResolution(50, 16)
do
  local w, h = screen.getResolution()
  test("before the signal is handled TOS still believes the old size "
    .. "(" .. w .. "x" .. h .. ") — this is the bug", w == 80 and h == 25)
end

-- ── The signal is delivered ────────────────────────────────────────
test("screen.onResized exists", type(screen.onResized) == "function")
if type(screen.onResized) ~= "function" then
  print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

local changed = screen.onResized("screen-resize", 50, 16)
test("it reports that something changed", changed == true)
do
  local w, h = screen.getResolution()
  eq("kernel.screen now reports the new width", 50, w)
  eq("kernel.screen now reports the new height", 16, h)
end

-- Idempotent: a repeat signal for a size we already hold is not a change,
-- so it must not churn the caches of every seat on the machine.
eq("a repeat signal reports no change", false, screen.onResized("screen-resize", 50, 16))

-- An address we do not own is somebody else's seat.
eq("a signal for another screen is ignored", false,
  screen.onResized("screen-somewhere-else", 10, 10))

-- ── The seat proxy re-syncs rather than trusting a stale shadow ────
-- The shadow is only correct while its idea of the geometry is. A proxy
-- that kept it across a resize would elide repaints of cells that have
-- moved, which is the invisible half of this bug.
print()
print("-- the proxy drops a shadow that describes the old geometry --")
do
  local p = screen.displayProxy(1)
  test("proxy exists", p ~= nil)
  if p then
    p.set(1, 1, "HELLO", 0xFFFFFF, 0x000000)
    local afterFirst = sets
    p.set(1, 1, "HELLO", 0xFFFFFF, 0x000000)
    eq("an identical redraw is elided while the geometry holds", afterFirst, sets)

    gpu.setResolution(70, 20)
    screen.onResized("screen-resize", 70, 20)
    local before = sets
    p.set(1, 1, "HELLO", 0xFFFFFF, 0x000000)
    test("...but after a resize the same draw is EMITTED again", sets > before)
  end
end

-- ── The panels layout follows the screen ───────────────────────────
-- Every row constant counts back from S.H. recomputeLayout asks the GPU
-- directly, so the shell's handler does not depend on the kernel's having
-- run first.
print()
print("-- the shell's layout follows too --")
do
  local okSM, SM = pcall(require, "shell.panels.state")
  test("shell.panels.state loads", okSM and type(SM) == "table")
  if okSM and SM and SM.recomputeLayout then
    gpu.setResolution(80, 25)
    local S = { D = { getGpu = function() return gpu end,
                      getSize = function() return gpu.getResolution() end } }
    SM.recomputeLayout(S)
    eq("status bar sits on the bottom row", 25, S.STAT_ROW)
    eq("prompt sits just above it", 24, S.CMD_ROW)

    gpu.setResolution(50, 16)
    SM.recomputeLayout(S)
    eq("after a shrink the status bar follows the new bottom", 16, S.STAT_ROW)
    eq("...and so does the prompt", 15, S.CMD_ROW)
    test("the status bar is ON the screen, not clipped past it", S.STAT_ROW <= 16)
    test("the file list still has room", S.LIST_H > 0)

    gpu.setResolution(160, 50)
    SM.recomputeLayout(S)
    eq("after a grow it follows again", 50, S.STAT_ROW)
    eq("width follows as well", 160, S.W)
    eq("the pad string is rebuilt to the new width", 160, #S.padW)
  end
end

-- ── The shell listens for the signal at all ────────────────────────
-- Behavioural coverage of the handler would mean standing up the whole
-- panels event loop; what matters here is that the branch exists and calls
-- recomputeLayout, because a signal nothing handles is the entire bug.
print()
print("-- the handlers are wired --")
local function readFile(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local fh = io.open(p, "r")
    if fh then local s = fh:read("*a"); fh:close(); return s end
  end
end
do
  local ev = readFile("tos/shell/panels/events.lua")
  test("panels/events.lua reads events.lua", ev ~= nil)
  if ev then
    local branch = ev:match('sig == "screen_resized".-draw = 3')
    test("...and has a screen_resized branch", branch ~= nil)
    test("...that recomputes the layout",
      branch ~= nil and branch:find("recomputeLayout", 1, true) ~= nil)
  end
  local ki = readFile("tos/kernel/init.lua")
  test("kernel/init.lua is readable", ki ~= nil)
  if ki then
    test("the kernel registers a screen_resized listener",
      ki:find('event.on("screen_resized"', 1, true) ~= nil)
    test("...which re-syncs kernel.screen",
      ki:find("onResized", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
