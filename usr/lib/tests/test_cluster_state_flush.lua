-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a failed save of the cluster state is kept   ║
-- ║                                                                ║
-- ║  The Master saves on every mutation. A save can fail on memory ║
-- ║  that is only garbage (seen on a 2 MB Master at 90% used: "not ║
-- ║  enough memory for buffer allocation", on every save with a    ║
-- ║  job in it). The last save of a job is the one that says it    ║
-- ║  finished and nothing follows it, so after a reboot a finished ║
-- ║  job came back as running. state.flush retries from the        ║
-- ║  scheduler tick.                                               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_state_flush.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.loaded["computer"] = { uptime = function() return 0 end }
package.loaded["filesystem"] = { exists = function() return false end }
package.loaded["kernel.fs"] = package.loaded["filesystem"]
local warned = {}
package.loaded["kernel.log"] = { info = function() end, error = function() end,
  warn = function(_, m) warned[#warned + 1] = m end }
package.loaded["log"] = package.loaded["kernel.log"]
package.loaded["kernel.serialize"] = { encode = function() return "" end, decode = function() end }

local chunk
for _, p in ipairs({ "../TOS-Extras/cluster/master-skeleton/lib/cluster/state.lua",
                     "TOS-Extras/cluster/master-skeleton/lib/cluster/state.lua" }) do
  chunk = loadfile(p)
  if chunk then break end
end
if not chunk then
  print("  SKIP: TOS-Extras is not beside TOS-Dev")
  print("Results: 0 passed, 0 failed"); return
end
local state = chunk()

state.init("/var/cluster/state.dat")
local saves, failNext = 0, 0
state.save = function()
  saves = saves + 1
  if failNext > 0 then
    failNext = failNext - 1
    error("not enough memory for buffer allocation", 0)
  end
  return true
end

print("=== a save that fails is not forgotten ===")
state.flush()
test("nothing unsaved, nothing to do", saves == 0, saves)

failNext = 1
state.createJob({ tasks = {} })
local afterJob = saves
test("the job's save was tried", afterJob >= 1, afterJob)
test("the failure is said once, as a deferral", #warned == 1
  and tostring(warned[1]):find("save deferred", 1, true) ~= nil, warned[1])

state.flush()
test("the next tick tries again", saves == afterJob + 1, saves)
state.flush()
test("and stops once it has landed", saves == afterJob + 1, saves)

print("=== a run of failures stays quiet and keeps trying ===")
failNext, warned = 3, {}
state.createJob({ tasks = {} })
local base = saves
state.flush()
state.flush()
test("each tick tries", saves == base + 2, saves)
test("one line in the log, not one a second", #warned == 1, #warned)
state.flush()
test("then it lands", saves == base + 3, saves)
state.flush()
test("and is done", saves == base + 3, saves)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
