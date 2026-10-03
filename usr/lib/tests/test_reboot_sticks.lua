-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `reboot` reboots                             ║
-- ║                                                                ║
-- ║  The shell's `reboot` runs kernel.shutdown(true) INSIDE the    ║
-- ║  shell process. Its first act clears `running`; the moment the ║
-- ║  process yields to the scheduler, the main loop falls out and  ║
-- ║  calls kernel.shutdown() itself, and the killed shell process  ║
-- ║  is never resumed. That second call had no flag, so `reboot`   ║
-- ║  powered the machine OFF -- seen on a headless OpenComputers   ║
-- ║  machine, where the trace read shutdown(true) from the shell,  ║
-- ║  then shutdown(nil) from the main loop 0.25 s later.           ║
-- ║                                                                ║
-- ║  kernel.shutdown is LIFTED from tos/kernel/init.lua and run    ║
-- ║  the way that machine ran it: the shell's call in a coroutine  ║
-- ║  that yields mid-shutdown and is abandoned, then the main      ║
-- ║  loop's call.                                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_reboot_sticks.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local src = assert(io.open("tos/kernel/init.lua", "rb")):read("*a"):gsub("\r\n", "\n")
local body = src:match("(function kernel%.shutdown%(reboot%).-\nend)\n")
test("found kernel.shutdown", body ~= nil)
if not body then print("*** TESTS FAILED ***"); os.exit(1) end

-- A fresh kernel per case: the lifted function's upvalues (running,
-- rebootRequested, ...) become fields of this environment.
local function machine(opts)
  opts = opts or {}
  local m = { powered = {}, logged = {}, shown = {}, killed = {} }
  local env
  env = setmetatable({
    running = true, shuttingDown = false, rebootRequested = false,
    kernel = {},
    log = {
      info = function(_, msg) m.logged[#m.logged + 1] = msg end,
      flush = function() end, detachFile = function() end,
    },
    proc = {
      list = function() return { { pid = 1 }, { pid = 2 } } end,
      kill = function(pid) m.killed[#m.killed + 1] = pid end,
    },
    display = {
      getTheme = function() return setmetatable({}, { __index = function(_, k) return k end }) end,
      clear = function() end,
      set = function(_, _, text) m.shown[#m.shown + 1] = tostring(text) end,
    },
    computer = {
      pullSignal = function() end,
      shutdown = function(r) m.powered[#m.powered + 1] = r end,
    },
    package = { loaded = {} },
    _G = { _TOS = {
      -- Stopping services is where a real shell process yields to the
      -- scheduler; opts.yieldIn makes this one do the same.
      rc = { stopAll = function()
        if opts.yieldIn == "rc" and coroutine.isyieldable() then coroutine.yield("to the scheduler") end
      end },
      fs = { writeFile = function() return true end },
      bootCount = 7,
    } },
  }, { __index = _G })
  assert(load(body, "=kernel.shutdown", "t", env))()
  m.kernel, m.env = env.kernel, env
  return m
end
local function said(list, needle)
  for _, t in ipairs(list) do if t:find(needle, 1, true) then return true end end
  return false
end

print("=== `reboot` reboots ===")
print()

-- ── The race, as the machine ran it ────────────────────────────────
do
  local m = machine({ yieldIn = "rc" })
  -- The shell process: kernel.reboot() -> kernel.shutdown(true), which
  -- yields to the scheduler while stopping services ...
  local shell = coroutine.create(function() m.kernel.shutdown(true) end)
  local ok, why = coroutine.resume(shell)
  test("the shell's shutdown yields mid-way, as on the machine", ok and why == "to the scheduler"
    and coroutine.status(shell) == "suspended", why)
  test("...having already cleared `running`", m.env.running == false)
  test("...and powered nothing yet", #m.powered == 0)
  -- ... and is never resumed: the main loop saw running == false, fell out
  -- of loginAndStartShell, and calls kernel.shutdown() with no flag.
  m.kernel.shutdown()
  test("the main loop's shutdown reboots the machine", m.powered[1] == true, tostring(m.powered[1]))
  test("...exactly once", #m.powered == 1, #m.powered)
  test("...says so in the log", said(m.logged, "Rebooting..."))
  test("...and on the screen", said(m.shown, "Rebooting TOS..."))
end

-- ── The straight paths still do what they say ──────────────────────
do
  local m = machine()
  m.kernel.shutdown(true)
  test("an uninterrupted reboot reboots", m.powered[1] == true and #m.powered == 1)
end
do
  local m = machine()
  m.kernel.shutdown()
  test("a plain shutdown powers off", m.powered[1] == false, tostring(m.powered[1]))
  test("...and says so", said(m.logged, "Shutting down...") and said(m.shown, "TOS shut down."))
end
do
  local m = machine()
  m.kernel.shutdown(false)
  test("shutdown(false) powers off", m.powered[1] == false)
end
do
  local m = machine()
  m.kernel.shutdown(true)
  test("every process is still killed on the way down", #m.killed == 2, #m.killed)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
