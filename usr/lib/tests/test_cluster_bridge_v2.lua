-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: cluster Manager v2 dispatch logic        ║
-- ║  Pure helpers behind the OpenOS worker bridge wiring:      ║
-- ║   - routeTask    (inline vs bridge)                        ║
-- ║   - aggregateStatus (ok/failed/partial/cancelled)          ║
-- ║   - newCollector (idempotent per-task result collection +  ║
-- ║                   exactly-once finish, incl. cancel races) ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_bridge_v2.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- Stub the manager's module-load requires so it loads off-box.
package.loaded["filesystem"] = { exists = function() return false end }
package.loaded["computer"]   = { uptime = function() return 0 end }
package.loaded["event"]      = { on = function() end, interval = function() end,
  timer = function() end, cancelTimer = function() end }
package.loaded["kernel.net"] = { on = function() return 1 end, send = function() end,
  off = function() end }
package.loaded["kernel.net.protocol"] = {
  TYPE = setmetatable({}, { __index = function(_, k) return "T_" .. k end }),
  makePacket = function(t, p, o) return { type = t, payload = p, to = o and o.to } end,
}
package.loaded["log"] = { info = function() end, warn = function() end, error = function() end }

local mgr
for _, p in ipairs({
    "../TOS-Extras/cluster/manager-skeleton/usr/lib/cluster-manager.lua",
    "TOS-Extras/cluster/manager-skeleton/usr/lib/cluster-manager.lua" }) do
  local chunk = loadfile(p)
  if chunk then mgr = chunk(); break end
end
if not mgr then
  print("FAIL: could not load cluster-manager.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== cluster Manager v2 dispatch Tests ===")
print()

-- ── aggregateStatus ───────────────────────────────────────────────
local agg = mgr._aggregateStatus
test("all ok -> ok",            "ok",        agg(3, 0, 0))
test("all errored -> failed",   "failed",    agg(3, 3, 0))
test("some errored -> partial", "partial",   agg(3, 1, 0))
test("any cancel wins",         "cancelled", agg(3, 1, 1))
test("zero tasks -> ok",        "ok",        agg(0, 0, 0))

-- ── routeTask ─────────────────────────────────────────────────────
local rt = mgr._routeTask
test("no bridge -> inline",        "inline", rt({},                false, "opt-in"))
test("opt-in, no flag -> inline",  "inline", rt({},                true,  "opt-in"))
test("opt-in, via_bridge -> bridge","bridge", rt({ via_bridge = true }, true, "opt-in"))
test("via_bridge but no bridge",   "inline", rt({ via_bridge = true }, false, "opt-in"))
test("prefer mode -> bridge",      "bridge", rt({},                true,  "prefer"))

-- ── newCollector ──────────────────────────────────────────────────
local function collect(total, fn)
  local calls = {}
  local c = mgr._newCollector(total, function(status, outputs, errors, tallies)
    calls[#calls + 1] = { status = status, outputs = outputs, errors = errors, tallies = tallies }
  end)
  if fn then fn(c) end
  return calls, c
end

-- Two successes -> one finish, status ok, outputs preserved.
local okCalls = collect(2, function(c) c.record(1, "a", nil); c.record(2, "b", nil) end)
test("2 ok -> finished once", 1, #okCalls)
test("2 ok -> status ok", "ok", okCalls[1] and okCalls[1].status)
test("2 ok -> outputs kept", "b", okCalls[1] and okCalls[1].outputs[2])

-- Mixed -> partial.
local mixCalls = collect(2, function(c) c.record(1, "a", nil); c.record(2, nil, "boom") end)
test("mixed -> partial", "partial", mixCalls[1] and mixCalls[1].status)
test("mixed -> error recorded", "boom", mixCalls[1] and mixCalls[1].errors[2])

-- Idempotent per index: a duplicate record for the same task is ignored,
-- so the collector neither double-counts nor finishes early/twice.
local dupCalls = collect(2, function(c)
  c.record(1, "a", nil)
  c.record(1, "a-again", "boom")   -- ignored (index 1 already recorded)
  c.record(2, "b", nil)
end)
test("dup ignored -> finished once", 1, #dupCalls)
test("dup ignored -> still ok", "ok", dupCalls[1] and dupCalls[1].status)

-- Cancel race: a worker result lands for task 1, THEN a cancel tries to
-- record task 1 (ignored) and records task 2 as cancelled. Finishes once,
-- cancel wins, the real output for task 1 survives.
local raceCalls = collect(2, function(c)
  c.record(1, "result1", nil)        -- worker result arrived
  c.record(1, nil, "cancelled")      -- cancel for same task — ignored
  c.record(2, nil, "cancelled")      -- task still out on a worker — cancelled
end)
test("cancel race -> finished once", 1, #raceCalls)
test("cancel race -> cancelled", "cancelled", raceCalls[1] and raceCalls[1].status)
test("cancel race -> task1 output kept", "result1", raceCalls[1] and raceCalls[1].outputs[1])

-- Empty assignment finishes immediately with ok.
local emptyCalls = collect(0)
test("empty -> finished immediately", 1, #emptyCalls)
test("empty -> ok", "ok", emptyCalls[1] and emptyCalls[1].status)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
