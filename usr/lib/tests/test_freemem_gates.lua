-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: free memory is measured, not merely read    ║
-- ║                                                                ║
-- ║  computer.freeMemory() counts UNCOLLECTED GARBAGE as used, so  ║
-- ║  it only ever UNDERSTATES what is available — never the        ║
-- ║  reverse. From a real machine's kernel.log, three boots in a   ║
-- ║  row:                                                          ║
-- ║                                                                ║
-- ║    [10.3] Boot complete! Free memory: 322KB                    ║
-- ║    [28.5] Seat 1: loading shell (1268KB free)                  ║
-- ║                                                                ║
-- ║  Nothing was freed in between. The first number is the same    ║
-- ║  heap with a boot's worth of garbage still in it.              ║
-- ║                                                                ║
-- ║  A wrong number in a log line is cosmetic. The same number in  ║
-- ║  a GATE is not, and four of them trusted it: whether optional  ║
-- ║  boot stages load, whether to shout LOW MEMORY, what the       ║
-- ║  splash promises the operator, and whether the display's       ║
-- ║  dirty-cell shadow is affordable. Every one of them was free   ║
-- ║  to answer "no" on account of garbage.                         ║
-- ║                                                                ║
-- ║  The error being one-directional is what makes the fix cheap:  ║
-- ║  a reading that ALREADY clears the bar is true and needs no    ║
-- ║  collection. Only a reading that falls short might be an       ║
-- ║  artefact. So the common path pays nothing and the gate stops  ║
-- ║  lying — which is the half that has to be tested, because a    ║
-- ║  helper that is merely correct in isolation is not the bug.    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_freemem_gates.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_freemem_gates.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path

print("=== free memory is measured, not read Tests ===")
print()

-- ── A heap we control ──────────────────────────────────────────────
-- `dirty` is garbage the collector has not got to yet: it is counted as
-- used, and a collection makes it go away. Exactly the real situation.
local heap = { dirty = 0, live = 300 * 1024, collects = 0 }
local function freeRaw() return heap.live - heap.dirty end

local realCollect = _G.collectgarbage
_G.collectgarbage = function(what)
  if what == "collect" or what == nil then
    heap.collects = heap.collects + 1
    heap.dirty = 0
  end
  return 0
end

package.loaded["computer"] = {
  freeMemory  = freeRaw,
  totalMemory = function() return 2 * 1024 * 1024 end,
  uptime      = function() return 100 end,
  getDeviceInfo = function() return {} end,
  pullSignal  = function() return nil end,
  beep        = function() end,
}
package.loaded["component"] = {
  list  = function() return function() return nil end end,
  proxy = function() return nil end,
  type  = function() return nil end,
  invoke = function() return nil end,
  isAvailable = function() return false end,
}

local hal = require("kernel.hal")

-- ── The cheap path stays cheap ─────────────────────────────────────
print("-- a reading that already clears the bar is believed as-is --")
do
  heap.live, heap.dirty, heap.collects = 900 * 1024, 100 * 1024, 0
  local free, collected = hal.freeMemory(400 * 1024)
  eq("it answers with the reading it already had", 800 * 1024, free)
  eq("...without collecting", false, collected)
  eq("...so nothing was collected at all", 0, heap.collects)
end

-- ── The short reading is re-checked, not believed ──────────────────
print()
print("-- a reading that falls short is checked before it is trusted --")
do
  -- 322KB free of a 1268KB heap: the real boot log, in the numbers it used.
  heap.live, heap.dirty, heap.collects = 1268 * 1024, 946 * 1024, 0
  eq("the raw reading really is the misleading one", 322 * 1024, freeRaw())
  local free, collected = hal.freeMemory(640 * 1024)
  eq("it collects and asks again", 1, heap.collects)
  eq("...and reports what is actually free", 1268 * 1024, free)
  eq("...saying that it had to", true, collected)
end

-- ── A report always tells the truth ────────────────────────────────
print()
print("-- with no bar to clear, it is a report and always collects --")
do
  heap.live, heap.dirty, heap.collects = 1268 * 1024, 946 * 1024, 0
  local free = hal.freeMemory()
  eq("no `need` means collect unconditionally", 1, heap.collects)
  eq("...and report the honest figure", 1268 * 1024, free)
end

-- ── It can only ever revise UPWARD ─────────────────────────────────
-- A collection cannot produce less free memory. If a host somehow answers
-- lower afterwards, the larger reading is the safe one to keep -- rounding
-- a gate DOWN on a bad reading is how the bug worked in the first place.
print()
print("-- it never revises downward --")
do
  heap.live, heap.dirty, heap.collects = 500 * 1024, 0, 0
  local before = freeRaw()
  package.loaded["computer"].freeMemory = function()
    return heap.collects > 0 and (100 * 1024) or before
  end
  local free = hal.freeMemory(999 * 1024)
  eq("a smaller post-collect answer is discarded", before, free)
  package.loaded["computer"].freeMemory = freeRaw
end

-- ── No collectgarbage on this host ─────────────────────────────────
-- OC sandboxes do not always expose it, and calling it bare where it is
-- absent panics rather than erroring.
print()
print("-- and it survives a host with no collectgarbage --")
do
  heap.live, heap.dirty = 500 * 1024, 200 * 1024
  local saved = _G.collectgarbage
  _G.collectgarbage = nil
  local ok, free = pcall(hal.freeMemory, 999 * 1024)
  _G.collectgarbage = saved
  test("it does not throw", ok)
  eq("...and falls back to the raw reading", 300 * 1024, free)
end

-- ══════════════════════════════════════════════════════════════════
-- THE CONSEQUENCE: the display cache must not be switched off by
-- garbage. This is the half that matters — a helper that is correct in
-- isolation while the gate goes on reading raw is not a fix.
-- ══════════════════════════════════════════════════════════════════
print()
print("-- the shadow gate is not decided by garbage --")
do
  local fixture
  for _, p in ipairs({ base .. "fixture_glass.lua",
      "usr/lib/tests/fixture_glass.lua", "TOS-Dev/usr/lib/tests/fixture_glass.lua" }) do
    local chunk = loadfile(p)
    if chunk then fixture = chunk(); break end
  end
  test("the glass fixture loaded", fixture ~= nil)
  if fixture then
    local G = fixture.newGlass(80, 25).install()
    -- install() supplies its own generous `computer`; put the controlled
    -- heap back over it, and set it where the RAW reading fails the gate
    -- (80*25*128 + 384K = 634K needed) but the collected one clears it.
    heap.live, heap.dirty, heap.collects = 2048 * 1024, 1748 * 1024, 0
    package.loaded["computer"].freeMemory = freeRaw
    eq("the raw reading would fail the gate", 300 * 1024, freeRaw())

    package.loaded["kernel.screen"] = nil
    package.loaded["kernel.display"] = nil
    local screen = require("kernel.screen")
    screen.init()
    local D = screen.displayProxy(1)
    local st = D.dump().state
    test("a state block came back", type(st) == "table")
    eq("the shadow is ON — the shortfall was garbage, not memory",
      true, st and st.shadow)

    -- And it is genuinely working, not merely flagged on: draw the same
    -- row twice and the second must reach the GPU not at all.
    local T = require("kernel.display").getTheme()
    D.fill(1, 25, 80, 1, " ", T.statusbar_fg, T.statusbar_bg)
    screen.resetBufferStats()
    D.fill(1, 25, 80, 1, " ", T.statusbar_fg, T.statusbar_bg)
    local stats = screen.bufferStats()
    eq("the identical repaint is elided", 1, stats.skipped)
    eq("...and nothing was emitted", 0, stats.emitted)
  end
end

_G.collectgarbage = realCollect

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
