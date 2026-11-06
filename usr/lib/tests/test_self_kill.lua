-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a process that kills itself stays dead       ║
-- ║                                                                ║
-- ║  `kill 2` typed in the shell that IS PID 2 printed "Killed     ║
-- ║  PID 2" and froze the seat for good. proc.kill marked the      ║
-- ║  shell DEAD and dropped its seat's foreground, but the shell   ║
-- ║  was the process running at the time: it carried on to its     ║
-- ║  next yield, and the scheduler then set it READY again. Alive  ║
-- ║  to every check (so nothing brought the login back), and with  ║
-- ║  no input to read. Found by the local worker on the headless   ║
-- ║  machine, which read the frozen `ps` as the shell respawning.  ║
-- ║                                                                ║
-- ║  Runs the real scheduler.                                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_self_kill.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local clock = 0
package.loaded["computer"] = {
  uptime = function() return clock end,
  pullSignal = function() return nil end,
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
package.path = "tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local proc = require("kernel.process")
local DEAD = proc.STATE.DEAD
local ROOT = { user = "root", tier = 3 }

local function gone(pid)
  local p = proc.get(pid)
  return p == nil or p.state == DEAD
end

print("=== a process that kills itself ===")
local said, ranOn, resumedAfter = nil, false, 0
local self
self = proc.spawn("shell:root@1", function()
  said = select(1, proc.kill(self))
  ranOn = true                -- what `kill` does next: print, redraw the prompt
  while true do
    coroutine.yield()
    resumedAfter = resumedAfter + 1
  end
end, { principal = ROOT, display = 1, inherit = false })
proc.setForeground(self, 1)
proc.tick(); clock = clock + 1
test("kill says it worked", said == true, said)
test("the rest of the command still runs, as `Killed PID 2` did", ranOn)
test("it is dead once it yields, not READY again", gone(self),
  proc.get(self) and proc.get(self).state)
for _ = 1, 5 do proc.tick(); clock = clock + 1 end
test("it is never resumed again", resumedAfter == 0, resumedAfter)
test("and it is no longer its seat's foreground", proc.getForeground(1) ~= self)

print("=== the cases that already worked still do ===")
local victim = proc.spawn("victim", function() while true do coroutine.yield() end end,
  { principal = ROOT, display = 1, inherit = false })
proc.spawn("killer", function() proc.kill(victim); coroutine.yield() end,
  { principal = ROOT, display = 1, inherit = false })
proc.tick(); clock = clock + 1
test("a process killed by another is dead", gone(victim))
local idle = proc.spawn("idle", function() while true do coroutine.yield() end end,
  { principal = ROOT, display = 1, inherit = false })
proc.tick(); clock = clock + 1; proc.tick()
test("one that only yields stays alive", not gone(idle), proc.get(idle) and proc.get(idle).state)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
