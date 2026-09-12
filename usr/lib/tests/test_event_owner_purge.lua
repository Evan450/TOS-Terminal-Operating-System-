-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a dead program's listeners are freed          ║
-- ║                                                                ║
-- ║  kernel.event only ever SKIPPED a dead process's listeners (the ║
-- ║  M-11 generation check) and never removed them, and every entry ║
-- ║  pins its callback -- and with it the whole program. proc.kill  ║
-- ║  removed source "proc:<pid>", which compat.event never uses, and║
-- ║  a natural exit removed nothing. So each run of a program that  ║
-- ║  listened and exited leaked that program for good: a user could ║
-- ║  exhaust the heap with a two-line program in a loop (Sep 2026   ║
-- ║  pentest, RAM pass).                                            ║
-- ║                                                                ║
-- ║  Drives the REAL kernel.process scheduler and kernel.event.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_event_owner_purge.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local clock = 0
local queue = {}
package.loaded["computer"] = {
  uptime = function() return clock end,
  pullSignal = function() local s = table.remove(queue, 1); if s then return table.unpack(s) end end,
  pushSignal = function() end,
  freeMemory = function() return 1e6 end,
  totalMemory = function() return 1e6 end,
  address = function() return "test" end,
}
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end,
  type = function() return nil end,
}
package.path = "tos/?.lua;" .. package.path
local proc = require("kernel.process")
local ev = require("kernel.event")

local function kb() collectgarbage(); collectgarbage(); return collectgarbage("count") end
local BLOB = 256 * 1024
local function settle() for _ = 1, 8 do clock = clock + 0.1; proc.tick(nil) end end

print("=== a dead program's listeners and timers are freed ===")
print()

do
  local base = kb()
  proc.spawn("listens-then-exits", function()
    local blob = string.rep("a", BLOB)
    ev.on("tos_test_signal", function() return #blob end)
  end)
  settle()
  local held = kb() - base
  test(string.format("a program that listened and exited is freed (%.0f KB still held)", held), held < 64)
end

do
  local base = kb()
  proc.spawn("sets-a-far-timer", function()
    local blob = string.rep("t", BLOB)
    ev.timer(1e9, function() return #blob end)
  end)
  settle()
  local held = kb() - base
  test(string.format("a far-future timer from a dead program is freed (%.0f KB held)", held), held < 64)
end

do
  local base = kb()
  local pid = proc.spawn("listens-and-waits", function()
    local blob = string.rep("k", BLOB)
    ev.on("tos_test_signal", function() return #blob end)
    while true do coroutine.yield() end
  end)
  settle()
  proc.kill(pid, { kernel = true })
  settle()
  local held = kb() - base
  test(string.format("a killed program's listener is freed (%.0f KB held)", held), held < 64)
end

do
  local okC, cev = pcall(require, "compat.event")
  test("compat.event loads off-box", okC and type(cev) == "table")
  if okC and type(cev) == "table" then
    local base = kb()
    proc.spawn("compat-listener", function()
      local blob = string.rep("c", BLOB)
      cev.listen("tos_test_signal", function() return #blob end)
    end)
    settle()
    local held = kb() - base
    test(string.format("the compat.event route is freed too (%.0f KB held)", held), held < 64)
  end
end

do
  local fired = 0
  proc.spawn("stays-alive", function()
    ev.on("tos_test_signal2", function() fired = fired + 1 end)
    while true do coroutine.yield() end
  end)
  settle()
  queue[#queue + 1] = { "tos_test_signal2" }
  ev.pull(0)
  test("a LIVE program's listener still fires", fired == 1)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
