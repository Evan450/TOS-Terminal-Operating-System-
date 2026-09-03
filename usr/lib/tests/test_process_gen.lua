-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Process Generation Token (M-11)    ║
-- ║  proc.genOf gives a unique, never-reused token per    ║
-- ║  spawn so the event dispatcher can detect PID reuse   ║
-- ║  and refuse to run a stale listener under a new        ║
-- ║  principal.                                            ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_process_gen.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

package.loaded["computer"] = {
  uptime = function() return 0 end,
  freeMemory = function() return 1e6 end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_process_gen.lua"
local base = here:gsub("[^/\\]*$", "")
local proc
for _, p in ipairs({ base .. "../../../tos/kernel/process.lua",
    "tos/kernel/process.lua", "TOS-Dev/tos/kernel/process.lua" }) do
  local chunk = loadfile(p); if chunk then proc = chunk(); break end
end
if not proc or not proc.genOf then
  print("FAIL: could not load process.lua / genOf missing")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== Process Generation Token Tests ===")
print()

test("genOf(unknown pid) is nil", nil, proc.genOf(4242))

local p1 = proc.spawn("alpha", function() end)
local p2 = proc.spawn("beta",  function() end)
local g1 = proc.genOf(p1)
local g2 = proc.genOf(p2)

test("gen is a number", "number", type(g1))
test("distinct spawns get distinct gens", true, g1 ~= g2)
test("genOf is stable for a live pid", g1, proc.genOf(p1))

-- The dispatcher's staleness check: a listener captured (p1, g1). If the
-- pid it holds now reports a different gen (PID reused by another spawn),
-- the captured gen no longer matches and the callback is skipped.
local function listenerStale(capturedPid, capturedGen)
  return proc.genOf(capturedPid) ~= capturedGen
end
test("fresh capture not stale", false, listenerStale(p1, g1))
-- Simulate p1's slot being taken by a different spawn generation.
test("mismatched gen detected as stale", true, listenerStale(p1, g1 - 1))
-- A captured pid that no longer exists is stale (genOf -> nil ~= gen).
test("vanished pid is stale", true, listenerStale(9999, g1))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
