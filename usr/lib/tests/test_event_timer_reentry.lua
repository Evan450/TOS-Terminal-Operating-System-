-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.event timers mutated from a callback  ║
-- ║                                                                ║
-- ║  event.pull walked `timers` by INDEX, in reverse, and removed  ║
-- ║  a fired one-shot by that index AFTER its callback returned.   ║
-- ║  A callback that cancels a timer registered EARLIER (a lower   ║
-- ║  index) shifts every entry above it down by one, so:           ║
-- ║                                                                ║
-- ║    * the fired one-shot is still in the array, one slot lower  ║
-- ║      -- its deadline is in the past, so it fires AGAIN on the  ║
-- ║      next pull;                                                ║
-- ║    * table.remove(timers, i) then deletes whatever now sits at ║
-- ║      i -- a DIFFERENT timer (already processed this pass), or  ║
-- ║      nothing.                                                  ║
-- ║                                                                ║
-- ║  A cron job that cancels its own retry timer, or a net layer   ║
-- ║  that cancels a resend from inside its ack timer, is exactly   ║
-- ║  this shape. TODO.txt L421 called it "survivable by argument"  ║
-- ║  because "a fired one-shot is already gone" -- it was not;     ║
-- ║  removal happened after the callback, not before.              ║
-- ║                                                                ║
-- ║  The fix collects the due timers first, then removes each      ║
-- ║  one-shot BY IDENTITY before firing it, so a callback may add  ║
-- ║  or cancel anything it likes.                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_event_timer_reentry.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_event_timer_reentry.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

-- A clock the test advances by hand, and a signal source that never
-- has anything to say, so each event.pull is exactly one timer sweep.
local clock = 0
package.loaded["computer"] = {
  uptime = function() return clock end,
  pullSignal = function() return nil end,
  pushSignal = function() end,
}
-- No process module: timers fire under the plain pcall path.
package.loaded["kernel.process"] = false

local event = require("kernel.event")

print("=== kernel.event timer re-entry Tests ===")
print()

-- ── 1. A one-shot that cancels an EARLIER timer from its callback ──
do
  local fired = {}
  local victimId = event.timer(10, function() fired.victim = (fired.victim or 0) + 1 end, "t")
  local keepId   = event.timer(10, function() fired.keep = (fired.keep or 0) + 1 end, "t")
  local shooter
  shooter = event.timer(1, function()
    fired.shooter = (fired.shooter or 0) + 1
    event.cancelTimer(victimId)          -- earlier-registered -> lower index
  end, "t")

  clock = 2
  event.pull(0)
  eq("shooter fired once on the first pull", 1, fired.shooter)
  eq("victim did not fire (it was cancelled)", nil, fired.victim)

  clock = 3
  event.pull(0)
  eq("shooter does NOT fire again on the next pull", 1, fired.shooter)
  eq("cancelling the shooter afterwards finds nothing (it is gone)",
     false, event.cancelTimer(shooter))

  clock = 20
  event.pull(0)
  eq("the uninvolved timer still fires (it was not the one removed)", 1, fired.keep)
  eq("...and the cancelled one never does", nil, fired.victim)
  -- cleanup: keepId is a one-shot, already gone
  event.cancelTimer(keepId)
end

-- ── 2. An interval that cancels an earlier timer keeps its schedule ──
do
  local fired = {}
  local victimId = event.timer(100, function() fired.victim = true end, "t")
  local ticks = 0
  local ivId = event.interval(5, function()
    ticks = ticks + 1
    if ticks == 1 then event.cancelTimer(victimId) end
  end, "t")

  clock = 105
  event.pull(0)
  eq("interval ticked once", 1, ticks)
  clock = 106
  event.pull(0)
  eq("interval did not re-fire before its next deadline", 1, ticks)
  clock = 111
  event.pull(0)
  eq("interval fires again at its rescheduled deadline", 2, ticks)
  eq("victim stayed cancelled", nil, fired.victim)
  event.cancelTimer(ivId)
end

-- ── 3. A callback that ADDS a timer: the new one waits its turn ──
do
  local log = {}
  event.timer(1, function()
    log[#log + 1] = "outer"
    event.timer(0, function() log[#log + 1] = "inner" end, "t")
  end, "t")
  clock = 200
  event.pull(0)
  eq("only the outer one-shot fired in the pass that created the inner",
     "outer", table.concat(log, ","))
  clock = 201
  event.pull(0)
  eq("the inner one fires on the following pull",
     "outer,inner", table.concat(log, ","))
end

-- ── 4. Two due timers, the first cancels the second: it must not fire ──
do
  local log = {}
  local a, b
  a = event.timer(1, function() log[#log + 1] = "a"; event.cancelTimer(b) end, "t")
  b = event.timer(1, function() log[#log + 1] = "b" end, "t")
  clock = 300
  event.pull(0)
  clock = 301
  event.pull(0)
  eq("a timer cancelled by an earlier callback in the same pass never fires",
     "a", table.concat(log, ","))
end

-- ── 5. A rescheduled interval bounds the wait for the next pull ──
do
  -- pullSignal receives the wait; capture it.
  local waits = {}
  package.loaded["computer"].pullSignal = function(w) waits[#waits + 1] = w; return nil end
  local id = event.interval(0.1, function() end, "t")
  clock = 400
  event.pull(0.5)                    -- fires; new deadline = 400.1
  eq("wait after firing a 0.1s interval is bounded by its next deadline",
     true, waits[#waits] ~= nil and waits[#waits] <= 0.1 + 1e-9)
  event.cancelTimer(id)
  package.loaded["computer"].pullSignal = function() return nil end
end

print()
print("Results: " .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then
  print("*** TESTS FAILED ***")
  os.exit(1)
else
  print("All tests passed.")
end
