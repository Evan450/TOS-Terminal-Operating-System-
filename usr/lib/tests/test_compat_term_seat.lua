-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: compat.term per seat, and term.read's input   ║
-- ║                                                                ║
-- ║  AUDIT 5:                                                       ║
-- ║   H-04  term.read() did `computer.pullSignal()`, raw and        ║
-- ║         untimed: it popped keystrokes meant for other seats     ║
-- ║         before the scheduler routed them, and blocked in C so   ║
-- ║         the whole machine froze until a key came.               ║
-- ║   H-06  one cursor for the whole machine: a program's setCursor ║
-- ║         moved every other program's, on every seat.             ║
-- ║   H-07  term.screen() and the GPU fallback answered with the    ║
-- ║         machine's FIRST screen / GPU, whoever asked.            ║
-- ║                                                                ║
-- ║  Drives the REAL compat.term (and, for the cursor, two REAL     ║
-- ║  sandbox.build() environments, as the audit's repro did).       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_compat_term_seat.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local rawPulls, rawPullArgs = 0, {}
local rawQueue = {}
package.loaded["computer"] = {
  uptime = function() return 10 end,
  freeMemory = function() return 1e6 end, totalMemory = function() return 2e6 end,
  pullSignal = function(t)
    rawPulls = rawPulls + 1
    rawPullArgs[#rawPullArgs + 1] = t
    local ev = table.remove(rawQueue, 1)
    if ev then return table.unpack(ev) end
  end,
  pushSignal = function() end, address = function() return "pc" end,
}
-- Two seats' hardware. component.list returns seat 1's FIRST, as a real
-- bus would for whichever device was attached first.
local GPU = { g1 = { tag = "gpu-1" }, g2 = { tag = "gpu-2" } }
for addr, g in pairs(GPU) do
  g.getResolution = function() return g.tag end
end
package.loaded["component"] = {
  list = function(t)
    local order = ({ gpu = { "g1", "g2" }, screen = { "s1", "s2" } })[t] or {}
    local i = 0
    return function() i = i + 1; return order[i], t end
  end,
  proxy = function(addr) return GPU[addr] end,
  type = function(addr) return (GPU[addr] and "gpu") or nil end,
  isAvailable = function() return true end,
}

-- kernel.display: records where things are drawn. getGpu answers nil so
-- the seat fallback (H-07) is what is exercised.
local sets, fills = {}, 0
package.loaded["kernel.display"] = {
  getSize = function() return 80, 25 end,
  set = function(x, y, s) sets[#sets + 1] = { x = x, y = y, s = s } end,
  fill = function() fills = fills + 1 end,
  clear = function() end,
  scrollUp = function() end,
  getGpu = function() return nil end,
  invalidateColors = function() end,
}
local seat = nil
package.loaded["kernel.screen"] = {
  callerSeat = function() return seat end,
  callerDevices = function()
    if seat == nil then return nil end
    return package.loaded["kernel.screen"].seatDevices(seat)
  end,
  seatDevices = function(i)
    if i == 1 then return { gpu = "g1", screen = "s1", keyboards = { "k1" } } end
    if i == 2 then return { gpu = "g2", screen = "s2", keyboards = { "k2" } } end
    return nil
  end,
  invalidateAll = function() end,
}

local term = require("compat.term")

print("=== compat.term: seats and input ===")
print()

-- ── H-06: the cursor ─────────────────────────────────────────────
print("-- H-06: one cursor per seat --")
do
  local sandbox = require("kernel.sandbox")
  local envA = sandbox.build({ caps = { ["compat.io"] = true } })
  local envB = sandbox.build({ caps = { ["compat.io"] = true } })
  local tA, tB = envA.require("compat.term"), envB.require("compat.term")

  seat = 1
  tA.setCursor(40, 12)
  seat = 2
  local bx, by = tB.getCursor()
  test("seat 2's program does not see seat 1's cursor (the audit's repro)", bx == 1 and by == 1)
  sets = {}
  tB.write("B")
  test("...and seat 2's write lands at seat 2's cursor",
    sets[1] and sets[1].x == 1 and sets[1].y == 1 and sets[1].s == "B")
  seat = 1
  local ax, ay = tA.getCursor()
  test("seat 1's cursor is where seat 1 left it", ax == 40 and ay == 12)

  -- Two programs taking turns on ONE seat share its glass, as on a real
  -- terminal: the second continues where the first stopped.
  local tA2 = envB.require("compat.term")
  local sx, sy = tA2.getCursor()
  test("two programs on the same seat share that seat's cursor", sx == 40 and sy == 12)

  seat = nil
  term.setCursor(5, 5)
  seat = 1
  local x1 = term.getCursor()
  test("a seatless caller (kernel, boot) keeps its own single cursor", x1 == 40)
  seat = nil
  local x0, y0 = term.getCursor()
  test("...which is the old shared cursor", x0 == 5 and y0 == 5)

  seat = 2
  term.setCursorBlink(true)
  seat = 1
  test("cursor blink is per seat too", term.getCursorBlink() == false)
  seat = nil
end

-- ── H-04: term.read ─────────────────────────────────────────────
print()
print("-- H-04: term.read yields for its input --")
do
  seat = 1
  term.setCursor(1, 3)
  rawPulls = 0
  local co = coroutine.create(function() return term.read() end)
  local fillsBefore
  local function feed(...) return coroutine.resume(co, ...) end
  assert(feed())                                  -- start: it waits
  fillsBefore = fills
  for _ = 1, 10 do feed() end                     -- idle scheduler ticks
  test("idle resumes do not repaint the input line", fills == fillsBefore)
  feed("modem_message", "local", "remote", 42, 1, "not for you")
  feed("key_down", "k1", string.byte("h"), 35, "player")
  feed("key_down", "k1", string.byte("i"), 23, "player")
  local okR, line = feed("key_down", "k1", 13, 28, "player")
  test("the line arrives through the scheduler's resumes", okR and line == "hi")
  test("...and term.read never pulled a raw signal", rawPulls == 0)
  test("...and it moved to the next line (dobreak)", select(2, term.getCursor()) == 4)
  seat = nil
end
do
  -- No scheduler to yield to: the only case left that pulls, and bounded.
  rawPulls, rawPullArgs = 0, {}
  rawQueue = { {}, { "key_down", "k1", string.byte("x"), 45 }, { "key_down", "k1", 13, 28 } }
  local line = term.read(nil, false)
  test("outside a process it still reads", line == "x")
  local bounded = #rawPullArgs > 0
  for _, t in ipairs(rawPullArgs) do
    if type(t) ~= "number" or t > 1 then bounded = false end
  end
  test("...with a bounded pull, never an untimed one", bounded)
end

-- ── H-07: which screen, which GPU ────────────────────────────────
print()
print("-- H-07: the caller seat's screen and GPU --")
do
  seat = 2
  test("term.screen() on seat 2 is seat 2's screen", term.screen() == "s2")
  test("term.gpu() on seat 2 falls back to seat 2's GPU",
    term.gpu() and term.gpu().getResolution() == "gpu-2")
  seat = 1
  test("...and seat 1's on seat 1", term.screen() == "s1"
    and term.gpu().getResolution() == "gpu-1")
  seat = 9
  test("a seat with no devices gets no screen, not seat 1's", term.screen() == nil)
  test("...and no GPU", term.gpu() == nil)
  seat = nil
  test("a seatless caller keeps the old answer (the first screen)", term.screen() == "s1")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
