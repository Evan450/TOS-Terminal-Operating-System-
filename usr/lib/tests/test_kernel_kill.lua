-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel-authorized process kill           ║
-- ║                                                            ║
-- ║  H13 denies a proc.kill with no attributable caller (fail  ║
-- ║  closed). But the kernel main loop (logout/shutdown/seat   ║
-- ║  reap) HAS no caller and legitimately must reap a shell —  ║
-- ║  the blanket deny left the old shell alive, drawing over   ║
-- ║  the new session (the multi-user status-bar flicker).      ║
-- ║  proc.kill(pid, {kernel=true}) now allows the genuine       ║
-- ║  kernel path; without it the no-caller deny still stands.  ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_kernel_kill.lua

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

package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["kernel.event"] = { removeSource = function() end }

local here = (arg and arg[0]) or "usr/lib/tests/test_kernel_kill.lua"
local base = here:gsub("[^/\\]*$", "")
local proc
for _, p in ipairs({ base .. "../../../tos/kernel/process.lua",
    "tos/kernel/process.lua", "TOS-Dev/tos/kernel/process.lua" }) do
  local chunk = loadfile(p); if chunk then proc = chunk(); break end
end
if not proc or not proc.kill then
  print("FAIL: could not load process.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- proc.list() excludes DEAD processes, so it tells us alive/dead.
local function listed(pid)
  for _, p in ipairs(proc.list()) do if p.pid == pid then return true end end
  return false
end

print("=== kernel-authorized kill Tests ===")
print()

-- No caller (currentPID + listenerPID both nil here, exactly like the kernel
-- main loop). A plain kill must be denied AND leave the process alive.
local victim = proc.spawn("victim", function() end)
test("victim spawns alive", true, listed(victim))
local ok1, err1 = proc.kill(victim)
test("no-caller kill is denied", false, ok1)
test("denial message mentions caller", true,
  type(err1) == "string" and err1:find("caller") ~= nil)
test("denied kill left the victim alive", true, listed(victim))

-- The genuine kernel path (explicit acknowledgement) reaps it.
local ok2 = proc.kill(victim, { kernel = true })
test("kernel-acknowledged kill succeeds", true, ok2)
test("victim is now dead (gone from list)", false, listed(victim))

-- The acknowledgement is opt-in: a fresh victim with a plain kill still dies
-- nowhere (default stays fail-closed).
local v2 = proc.spawn("victim2", function() end)
proc.kill(v2)                         -- denied, no opts
test("default kill still fail-closed", true, listed(v2))
proc.kill(v2, { kernel = true })      -- reaped
test("explicit kernel kill reaps it", false, listed(v2))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
