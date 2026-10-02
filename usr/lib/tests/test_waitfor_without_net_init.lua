-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: net.waitFor when net.init never ran          ║
-- ║                                                                ║
-- ║  net.waitFor pumps listeners with event.pull from kernel        ║
-- ║  context, but it found event.pull through a module upvalue      ║
-- ║  that only net.init() assigns. A Safe Mode boot skips the       ║
-- ║  network stage ("Skipping network (boot profile)"), so the      ║
-- ║  module is still require-able -- the sandbox's `net` cap,       ║
-- ║  chatpair and the mail/cluster libs all require it lazily --    ║
-- ║  but its waitFor fell through to a raw computer.pullSignal,     ║
-- ║  which pops each signal off the queue and dispatches nothing:   ║
-- ║  the predicate can never come true, and every other listener    ║
-- ║  on the machine loses its signals for the whole wait. The       ║
-- ║  on-box battery caught it on a Safe Mode boot (96-waitfor,      ║
-- ║  2026-09-27: "returned false after 2.0 s").                     ║
-- ║                                                                ║
-- ║  Drives the REAL net/init.lua, event.lua and process.lua, with  ║
-- ║  net.init never called -- the state Safe Mode leaves it in.     ║
-- ║  As in test_inprocess_waitfor, a coroutine stands in for        ║
-- ║  machine.lua's and the host resumes it with the next queued     ║
-- ║  signal on every yield, as OpenComputers does.                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_waitfor_without_net_init.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local clock = 0
local queue = {}
local computer = {
  -- Time passes on every read, so a deadline is always reached.
  uptime = function() clock = clock + 0.01; return clock end,
  freeMemory = function() return 1e6 end,
  totalMemory = function() return 2e6 end,
  pushSignal = function(...) queue[#queue + 1] = table.pack(...); return true end,
  pullSignal = function()
    local s = table.remove(queue, 1)
    if s then return table.unpack(s, 1, s.n) end
  end,
}
package.loaded["computer"] = computer
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end,
}

-- The kernel's own event loop and scheduler, as a Safe Mode boot has them.
local event = dofile("tos/kernel/event.lua")
package.loaded["kernel.event"] = event
local proc = dofile("tos/kernel/process.lua")
package.loaded["kernel.process"] = proc

local net = dofile("tos/kernel/net/init.lua")   -- net.init NOT called
package.loaded["kernel.net"] = net
test("net.waitFor exists before net.init", type(net.waitFor) == "function")

-- Run fn as the kernel: inside a coroutine that is not a process, resumed
-- by a host loop that hands it the next queued signal on every yield.
local function asKernel(fn)
  local lost = 0
  local machine = coroutine.create(fn)
  local ok, res = coroutine.resume(machine)
  local turns = 0
  while coroutine.status(machine) ~= "dead" and turns < 1000 do
    turns = turns + 1
    local s = table.remove(queue, 1)
    if s then
      lost = lost + 1
      ok, res = coroutine.resume(machine, table.unpack(s, 1, s.n))
    else
      ok, res = coroutine.resume(machine)
    end
  end
  return ok, res, lost
end

-- ── The 96-waitfor shape: a listener, its signal, a wait ─────────
do
  queue = {}
  local got, keys = false, 0
  local idP = event.on("probe", function() got = true end, "test")
  -- Something else on the machine is listening too: a keystroke queued
  -- ahead of the probe must reach its listener, not vanish in the wait.
  local idK = event.on("key_down", function() keys = keys + 1 end, "test")
  computer.pushSignal("key_down", "kbd", 0, 28, "player")
  computer.pushSignal("probe")

  local ok, res, lost = asKernel(function()
    return net.waitFor(function() return got end, 2)
  end)
  event.off("probe", idP)
  event.off("key_down", idK)

  test("waitFor lets the listener see what it waits for (returned "
    .. tostring(res) .. (ok and "" or ", raised") .. ")",
    ok and res == true and got == true)
  test("...and the keystroke queued ahead of it reached its own listener ("
    .. keys .. " delivered)", keys == 1)
  test("...and no signal went to the host and was lost (" .. lost .. " lost)", lost == 0)
end

-- ── Early boot: no event module loaded at all ────────────────────
-- The raw pull is the only thing left; it must still time out cleanly
-- rather than raise.
do
  queue = {}
  package.loaded["kernel.event"] = nil
  local ok, res = pcall(net.waitFor, function() return false end, 0.2)
  package.loaded["kernel.event"] = event
  test("with no event module, waitFor still times out cleanly (returned "
    .. tostring(res) .. ")", ok and res == false)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
