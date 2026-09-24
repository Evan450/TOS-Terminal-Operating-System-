-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: proc.yieldCooperative (multi-seat fix)   ║
-- ║                                                            ║
-- ║  A command that runs to completion in one resume freezes   ║
-- ║  every other seat for its whole duration. Long loops call  ║
-- ║  yieldCooperative: it no-ops until the resume has run one  ║
-- ║  slice (~50ms), then yields; the scheduler resumes with    ║
-- ║  NOTHING and leaves the signal queue untouched, so typed-  ║
-- ║  ahead keys reach the shell's real event loop later.       ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_coop_yield.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function eq(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- Controllable clock: the worker advances it to simulate slow work.
local clock = 0
package.loaded["computer"] = { uptime = function() return clock end,
  freeMemory = function() return 1e6 end }
package.loaded["kernel.event"] = { removeSource = function() end }

local here = (arg and arg[0]) or "usr/lib/tests/test_coop_yield.lua"
local base = here:gsub("[^/\\]*$", "")
local proc
for _, p in ipairs({ base .. "../../../tos/kernel/process.lua",
    "tos/kernel/process.lua", "TOS-Dev/tos/kernel/process.lua" }) do
  local chunk = loadfile(p); if chunk then proc = chunk(); break end
end
if not proc or not proc.yieldCooperative then
  print("FAIL: could not load process.lua / yieldCooperative missing")
  print("Results: 0 passed, 1 failed"); return false
end

print("=== cooperative-yield Tests ===")
print()

-- ── Worker A: slow loop (each iteration burns >1 slice) ────────────
local progress, done, gotSignal = 0, false, nil
local pidA = proc.spawn("slow-worker", function()
  while true do
    local a = coroutine.yield()          -- the "event loop" wait
    if a == "go" then
      for i = 1, 5 do
        progress = i
        clock = clock + 0.06             -- this iteration took 60ms
        proc.yieldCooperative()
      end
      done = true
    elseif a ~= nil then
      gotSignal = a
    end
  end
end)
proc.tick(nil)                            -- prime to the event loop

proc.signalKernel(pidA, "go")
proc.tick(nil)                            -- delivers "go", work begins
eq("slice 1: one iteration per tick, not the whole loop", 1, progress)
eq("work not finished after one tick", false, done)

-- Type-ahead arrives MID-WORK: it must be queued, not eaten by the
-- command's yield point.
proc.signalKernel(pidA, "typed-ahead")
proc.tick(nil)
eq("slice 2: work continued exactly where it left off", 2, progress)
eq("queued signal NOT consumed by the coop resume", nil, gotSignal)

-- Slices 3..5 each yield after their iteration, so the loop-exit +
-- `done = true` land on the resume AFTER the fifth slice.
proc.tick(nil); proc.tick(nil); proc.tick(nil); proc.tick(nil)
eq("work completes across slices", true, done)
eq("all iterations ran", 5, progress)

proc.tick(nil)                            -- back at the event loop now
eq("typed-ahead reaches the real event loop afterward", "typed-ahead", gotSignal)

-- ── Worker B: fast loop (never exceeds a slice) → one resume ───────
local fastProgress, fastResumes = 0, 0
proc.spawn("fast-worker", function()
  while true do
    local a = coroutine.yield()
    if a == "go" then
      fastResumes = fastResumes + 1
      for i = 1, 5 do
        fastProgress = i
        proc.yieldCooperative()           -- clock static: must no-op
      end
    end
  end
end)
proc.tick(nil)
local pidB
for _, p in ipairs(proc.list()) do
  if p.name == "fast-worker" then pidB = p.pid end
end
proc.signalKernel(pidB, "go")
proc.tick(nil)
eq("fast work finishes in ONE resume (yield throttled away)", 5, fastProgress)
eq("fast worker resumed once for the whole job", 1, fastResumes)

-- ── A key typed DURING a slice is kept, not dropped ────────────────
-- The "typed-ahead" case above only ever tested a signal that was already
-- QUEUED. A key arriving as the tick's own signal while the foreground
-- process was mid-slice was neither delivered nor queued: it vanished.
local slowKeys, slowDone = {}, false
local pidK = proc.spawn("slow-typist", function()
  while true do
    local a, b = coroutine.yield()
    if a == "go" then
      for _ = 1, 3 do clock = clock + 0.06; proc.yieldCooperative() end
      slowDone = true
    elseif a == "key_down" then
      slowKeys[#slowKeys + 1] = b
    end
  end
end)
proc.tick(nil)
proc.setForeground(pidK, nil, { kernel = true })
proc.signalKernel(pidK, "go")
proc.tick(nil)                                   -- work starts, slices
proc.tick(table.pack("key_down", "kb-typed-mid-work"))
proc.tick(table.pack("modem_message", "noise"))
proc.tick(nil); proc.tick(nil); proc.tick(nil)
eq("the sliced work still completes", true, slowDone)
eq("a key typed mid-slice reaches the process afterwards", "kb-typed-mid-work", slowKeys[1])

-- proc.pause: a wait that takes nothing from the process's input.
local pausedKeys, pauseReturned = {}, nil
local pidP = proc.spawn("pauser", function()
  while true do
    local a, b = coroutine.yield()
    if a == "go" then
      pauseReturned = proc.pause(0.05)
    elseif a == "key_down" then
      pausedKeys[#pausedKeys + 1] = b
    end
  end
end)
proc.tick(nil)
proc.setForeground(pidP, nil, { kernel = true })
proc.signalKernel(pidP, "go")
proc.tick(nil)                                   -- pause begins (yields)
eq("proc.pause yields rather than returning at once", nil, pauseReturned)
proc.tick(table.pack("key_down", "kb-during-pause"))
eq("a key during the pause is not delivered into the pause", 0, #pausedKeys)
clock = clock + 0.06
proc.tick(nil)                                   -- deadline passed: returns
eq("proc.pause returns true once the time is up", true, pauseReturned)
proc.tick(nil)
eq("...and the key typed during it arrives afterwards", "kb-during-pause", pausedKeys[1])
eq("proc.pause outside a process is a no-op", false, proc.pause(0.05))

-- ── Outside any process: harmless no-op ────────────────────────────
eq("kernel-context call is a no-op", false, (proc.yieldCooperative()))

-- ── Lua 5.2 fallback: canYield works when isyieldable is absent ────
-- OC lets players run a 5.2 CPU (TOS refuses to boot there, but the
-- primitive shouldn't silently rot). With isyieldable nil'd, canYield
-- must fall back to coroutine.running()'s is-main flag.
do
  local saved = coroutine.isyieldable
  coroutine.isyieldable = nil
  -- On the main thread → not yieldable.
  eq("5.2 fallback: main thread is NOT yieldable", false, proc._canYield())
  -- Inside a coroutine → yieldable.
  local insideResult
  local co = coroutine.create(function() insideResult = proc._canYield() end)
  coroutine.resume(co)
  eq("5.2 fallback: inside a coroutine IS yieldable", true, insideResult)
  coroutine.isyieldable = saved
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
