-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what the sandbox refuses is written down     ║
-- ║                                                                ║
-- ║  securefs logs a refused path. A capability the sandbox        ║
-- ║  withheld went out as an error a program could swallow, so     ║
-- ║  "the package installed and does nothing" left no trail. This  ║
-- ║  is the log half of survey item 3. A mode that logs instead    ║
-- ║  of refusing is the other half, and how that is switched on    ║
-- ║  is the operator's call.                                       ║
-- ║                                                                ║
-- ║  Drives the real sandbox.                                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_denial_log.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 1e6 end,
  totalMemory = function() return 1e6 end, address = function() return "t" end,
  pushSignal = function() end, pullSignal = function() return nil end,
}
package.loaded["component"] = {
  list = function() return function() end end, proxy = function() end,
  type = function() return "disk_drive" end, isAvailable = function() return false end,
  invoke = function() end,
}
package.loaded["kernel.fs"] = {
  exists = function() return false end, isDirectory = function() return false end,
  readFile = function() return nil end,
}

local lines = {}
package.loaded["kernel.log"] = {
  info = function() end, error = function() end, debug = function() end,
  warn = function(src, m) lines[#lines + 1] = src .. ": " .. m end,
}

local sandbox = require("kernel.sandbox")

local function count(pat)
  local n = 0
  for _, l in ipairs(lines) do if l:find(pat, 1, true) then n = n + 1 end end
  return n
end

print("=== a refusal leaves a line ===")
do
  local env = sandbox.build({ name = "p1", pkgName = "rogue", caps = { ["fs.read"] = true } })
  local ok, err = pcall(env.require, "kernel.fs")
  test("the program is still refused", ok == false, err)
  test("the log names the package and what it wanted",
    count("denied: rogue wanted module kernel.fs") == 1, lines[1])
  test("from the sandbox", (lines[1] or ""):find("^sandbox: ") ~= nil, lines[1])
  local okI = pcall(env.require, "compat.internet")
  test("a missing capability is named as one", okI == false and count("rogue wanted capability internet") == 1, lines[2])
end

print("=== it cannot fill the log ===")
do
  local env = sandbox.build({ name = "p2", pkgName = "noisy", caps = { ["fs.read"] = true } })
  for _ = 1, 50 do pcall(env.require, "kernel.users") end
  test("the same refusal is said once", count("noisy wanted module kernel.users") == 1,
    count("noisy wanted module kernel.users"))
  for i = 1, 400 do pcall(env.require, "kernel.made" .. i) end
  test("a program inventing names hits a cap", #lines < 140, #lines)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
