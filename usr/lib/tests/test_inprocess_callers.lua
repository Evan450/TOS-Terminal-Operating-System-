-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the other "am I in a process?" callers        ║
-- ║                                                                ║
-- ║  On real OpenComputers the kernel runs inside machine.lua's     ║
-- ║  coroutine, so coroutine.isyieldable() is TRUE in kernel        ║
-- ║  context (boot battery, 2026-09-25). net.waitFor was fixed for  ║
-- ║  that in 3757574; these four asked the same wrong question:     ║
-- ║   * pipe read/readLine -- an empty pipe yielded to the HOST     ║
-- ║     forever instead of returning nil;                           ║
-- ║   * sandbox.safePullSignal -- no 3 s ceiling, and its timeout   ║
-- ║     waited on whatever signal came next;                        ║
-- ║   * proc.yield / proc.sleep -- yielded to the host, which       ║
-- ║     resumed them with a signal nobody dispatched.               ║
-- ║                                                                ║
-- ║  A coroutine stands in for machine.lua's and a host loop        ║
-- ║  resumes it as OpenComputers does: with the next queued signal, ║
-- ║  or -- for a bare yield with nothing queued -- after the        ║
-- ║  machine has slept until something happened (30 s here). Real  ║
-- ║  process.lua and pipe.lua; safePullSignal lifted from source.   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_inprocess_callers.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local clock = 0
local queue = {}
local rawPulls = 0
local computer = {
  uptime = function() clock = clock + 0.001; return clock end,
  freeMemory = function() return 1e6 end,
  -- The raw primitive: the next queued signal, else wait out the timeout.
  pullSignal = function(timeout)
    rawPulls = rawPulls + 1
    local s = table.remove(queue, 1)
    if s then return table.unpack(s) end
    clock = clock + (tonumber(timeout) or 0)
    return nil
  end,
}
package.loaded["computer"] = computer

-- kernel.event as a listener table: pull() dispatches what it pulls.
local heard = {}
local EVENT = {
  removeSource = function() end,
  pull = function(timeout)
    local s = { computer.pullSignal(timeout) }
    if s[1] then heard[#heard + 1] = s[1] end
    return table.unpack(s)
  end,
}
package.loaded["kernel.event"] = EVENT

local function readSrc(path)
  local h = assert(io.open(path, "rb"))
  local s = h:read("*a"); h:close()
  return (s:gsub("\r\n", "\n"))
end

local proc = assert(load(readSrc("tos/kernel/process.lua"), "=process.lua"))()
package.loaded["kernel.process"] = proc
local pipe = assert(load(readSrc("tos/kernel/pipe.lua"), "=pipe.lua"))()

-- Run fn as the kernel: inside a coroutine that is not a process, resumed
-- by an OpenComputers-shaped host. Returns the results and how many times
-- it yielded to the host.
local function asKernel(fn, maxTurns)
  local co = coroutine.create(fn)
  local r = table.pack(coroutine.resume(co))
  local hostYields = 0
  while coroutine.status(co) ~= "dead" and hostYields < (maxTurns or 50) do
    hostYields = hostYields + 1
    local s = table.remove(queue, 1)
    if s then r = table.pack(coroutine.resume(co, table.unpack(s)))
    else clock = clock + 30; r = table.pack(coroutine.resume(co)) end
  end
  return { done = coroutine.status(co) == "dead", ok = r[1], r[2], r[3],
           hostYields = hostYields }
end

print("=== kernel context is not a process ===")
print()

-- Sanity: the premise. Yieldable, yet not a process.
local premise = asKernel(function() return coroutine.isyieldable(), proc.inProcess() end)
test("the stand-in is yieldable and not a process", premise[1] == true and premise[2] == false)

print()
print("-- pipe --")
do
  local r = pipe.create()
  local res = asKernel(function() return r:read() end)
  test("an empty pipe read from the kernel returns", res.done)
  test("...nil, without yielding to the host (" .. res.hostYields .. " yields)",
    res.done and res[1] == nil and res.hostYields == 0)
  r = pipe.create()
  res = asKernel(function() return r:readLine() end)
  test("readLine likewise (" .. res.hostYields .. " yields)", res.done and res[1] == nil
    and res.hostYields == 0)

  -- Inside a process an empty pipe still waits for its writer.
  local rd, wr = pipe.create()
  local got
  proc.spawn("reader", function() got = rd:read() end)
  proc.tick(nil)
  test("a process reading an empty pipe waits", got == nil)
  wr:write("hello")
  proc.tick(nil)
  test("...and gets what the writer wrote", got == "hello")
end

print()
print("-- proc.yield / proc.sleep --")
do
  local res = asKernel(function() proc.yield(); return "after" end)
  test("proc.yield from the kernel does not yield to the host (" .. res.hostYields .. ")",
    res.done and res[1] == "after" and res.hostYields == 0)

  queue = { { "modem_message", "peer" } }
  heard = {}
  local start = clock
  res = asKernel(function() proc.sleep(0.5); return "woke" end)
  local took = clock - start
  test("proc.sleep from the kernel returns", res.done and res[1] == "woke")
  test("...without yielding to the host (" .. res.hostYields .. ")", res.hostYields == 0)
  test(string.format("...in about the time asked (%.2f s for 0.5)", took), took >= 0.5 and took < 1.5)
  test("...and a signal arriving meanwhile reaches the event listeners", heard[1] == "modem_message")
  queue = {}

  -- Inside a process, sleep is the scheduler's: it yields and never pulls.
  rawPulls = 0
  local slept
  proc.spawn("sleeper", function() proc.sleep(0.01); slept = true end)
  for _ = 1, 50 do if slept then break end; proc.tick(nil) end
  test("a process's proc.sleep finishes through the scheduler", slept == true)
  test("...without a raw pull (" .. rawPulls .. ")", rawPulls == 0)
end

print()
print("-- sandbox.safePullSignal --")
do
  local src = readSrc("tos/kernel/sandbox.lua")
  local helper = src:match("\n(local function inProcess%(%).-\nend)\n") or ""
  local body = src:match("\n(local function safePullSignal%(timeout%).-\nend)\n")
  test("found safePullSignal in sandbox.lua", body ~= nil)
  if body then
    local env = { computer = computer, coroutine = coroutine, package = package,
                  type = type, table = table, math = math,
                  require = function(n) return package.loaded[n] end,
                  PULL_DROP = { modem_message = true } }
    local spull = assert(load(helper .. "\n" .. body .. "\nreturn safePullSignal",
      "=safePullSignal", "t", env))()

    queue = {}
    local start = clock
    local res = asKernel(function() return spull(0.2) end)
    local took = clock - start
    test("from the kernel, an empty queue returns nil", res.done and res[1] == nil)
    test(string.format("...when its timeout says (%.2f s for 0.2), not when a signal comes", took),
      took < 3)
    test("...without yielding to the host (" .. res.hostYields .. ")", res.hostYields == 0)

    queue = { { "modem_message", "x" }, { "key_down", "kbd", 65, 30 } }
    res = asKernel(function() return spull(1) end)
    test("a dropped signal is skipped and the next one returned",
      res.done and res[1] == "key_down" and res.hostYields == 0)
    queue = {}

    -- Inside a process it yields, and gets the routed signal from tick.
    local seen
    proc.spawn("puller", function() seen = spull(5) end)
    proc.tick(nil)
    test("a process waits in the scheduler", seen == nil)
    -- Not an input signal: input goes only to a display's foreground
    -- process, and this one is bound to no display.
    proc.tick({ "redstone_changed", "rs", 0, 15, n = 4 })
    test("...and receives the signal tick routes to it", seen == "redstone_changed")
  end
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
