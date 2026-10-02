-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: "in a process" is the scheduler's question    ║
-- ║                                                                ║
-- ║  On real OpenComputers the kernel runs inside machine.lua's     ║
-- ║  coroutine, so coroutine.isyieldable() is TRUE in kernel        ║
-- ║  context -- the boot battery measured it (92-term, 2026-09-25). ║
-- ║  A yield there goes to the HOST, which resumes the kernel with  ║
-- ║  the next queued signal. net.waitFor used isyieldable() to pick ║
-- ║  "yield to the scheduler" over "pump listeners with event.pull",║
-- ║  so from a listener (verifyPeer in the netfs / rshd / transfer  ║
-- ║  request handlers) it yielded to the host, the reply it waited  ║
-- ║  for came back as the yield's return value and was dropped, and ║
-- ║  it could only time out.                                        ║
-- ║                                                                ║
-- ║  Desktop Lua's main thread is NOT yieldable, which is why every ║
-- ║  earlier test passed. Here a coroutine stands in for            ║
-- ║  machine.lua's, and a host loop resumes it with the next queued ║
-- ║  signal on every yield, as OpenComputers does.                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_inprocess_waitfor.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local clock = 0
local queue = {}
local computer = {
  -- Time passes on every read, so a deadline is always reached.
  uptime = function() clock = clock + 0.01; return clock end,
  freeMemory = function() return 1e6 end,
  pullSignal = function()
    local s = table.remove(queue, 1)
    if s then return table.unpack(s) end
  end,
}
package.loaded["computer"] = computer
package.loaded["kernel.event"] = { removeSource = function() end }

local function readSrc(path)
  local h = assert(io.open(path, "rb"))
  local s = h:read("*a"); h:close()
  return (s:gsub("\r\n", "\n"))
end

-- ── proc.inProcess, with the real scheduler ─────────────────────
local proc = assert(load(readSrc("tos/kernel/process.lua"), "=process.lua"))()
package.loaded["kernel.process"] = proc
test("process.lua has inProcess()", type(proc.inProcess) == "function")
if type(proc.inProcess) == "function" then
  test("false at top level", proc.inProcess() == false)
  -- The OpenComputers case: yieldable, but no process is running.
  local inCo = coroutine.wrap(function()
    return coroutine.isyieldable(), proc.inProcess()
  end)
  local yieldable, inP = inCo()
  test("false inside a coroutine that is not a process (yieldable: "
    .. tostring(yieldable) .. ")", yieldable == true and inP == false)
  local seen
  proc.spawn("probe", function() seen = proc.inProcess(); coroutine.yield() end)
  proc.tick(nil)
  test("true inside a process that proc.tick resumed", seen == true)
end

-- ── net.waitFor, lifted from source, under OC's semantics ───────
local src = readSrc("tos/kernel/net/init.lua")
local helper = src:match("\n(local function inProcess%(%).-\nend)\n") or ""
local body = src:match("\n(function net%.waitFor%(predicate, timeout%).-\nend)\n")
test("found net.waitFor in net/init.lua", body ~= nil)
if body then
  local listeners = {}
  local event = {
    on = function(name, fn) listeners[name] = fn end,
    pull = function()
      local s = { computer.pullSignal() }
      if s[1] and listeners[s[1]] then listeners[s[1]](table.unpack(s)) end
      return table.unpack(s)
    end,
  }
  local env = { computer = computer, event = event, coroutine = coroutine,
                package = package, type = type, net = {} }
  local waitFor = assert(load(helper .. "\n" .. body .. "\nreturn net.waitFor",
    "=waitFor", "t", env))()

  -- A listener in kernel context waits for a reply that a SECOND listener
  -- records -- verifyPeer's shape. The reply is already queued.
  local got = false
  event.on("reply", function() got = true end)
  queue = { { "reply" } }
  local dropped = 0
  local machine = coroutine.create(function() return waitFor(function() return got end, 1) end)
  local ok, res = coroutine.resume(machine)
  local turns = 0
  while coroutine.status(machine) ~= "dead" and turns < 1000 do
    turns = turns + 1
    -- The kernel yielded to the host: OpenComputers resumes it with the
    -- next queued signal, which is therefore off the queue.
    local s = table.remove(queue, 1)
    if s then
      dropped = dropped + 1
      ok, res = coroutine.resume(machine, table.unpack(s))
    else
      ok, res = coroutine.resume(machine)
    end
  end
  test("from kernel context, waitFor sees the reply arrive (returned "
    .. tostring(res) .. ")", ok and res == true and got == true)
  test("...and no signal went to the host and was lost (" .. dropped .. " lost)", dropped == 0)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
