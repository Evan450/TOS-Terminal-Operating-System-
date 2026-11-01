-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what a remote chunk can reach                ║
-- ║                                                                ║
-- ║  remote.lua copies `string` without dump, but ("").dump gets   ║
-- ║  the real one through the string metatable. That cannot be     ║
-- ║  shadowed on OpenComputers: machine.lua answers                ║
-- ║  getmetatable(<string>) with nil and there is no               ║
-- ║  debug.setmetatable. It is safe only because a remote chunk    ║
-- ║  has nothing to load bytecode with, so that is what is pinned  ║
-- ║  here, by running chunks through the real handler. Adding      ║
-- ║  `load` to the env, or a way to reach it, fails this file.     ║
-- ║  `service start rshd` also has to say there is no step budget. ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_remote_env.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_remote_env.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 4e6 end, totalMemory = function() return 8e6 end,
  pullSignal = function() return nil end, beep = function() end,
  address = function() return "me" end }
package.loaded["component"] = { list = function() return function() end end,
  proxy = function() end, isAvailable = function() return false end }

local remote = require("kernel.net.remote")

local sent
remote.init({
  net = { on = function() end, send = function(_, pkt) sent = pkt; return true end },
  trust = { getLevel = function() return 2 end, LEVEL = { TRUSTED = 2 } },
})
remote.setEnabled(true)

local function runChunk(code)
  sent = nil
  remote.handleExec({ payload = { cmd = code } }, "peer-address")
  return sent and sent.payload and sent.payload.output
end

print("=== what a remote chunk can reach ===")
print()

test("the handler runs a chunk at all (else the rest is vacuous)",
  runChunk("print(6 * 7)") == "42", runChunk("print(6 * 7)"))

for _, name in ipairs({ "load", "loadstring", "loadfile", "dofile", "require",
    "debug", "getmetatable", "setmetatable", "rawget", "rawset", "package",
    "_G", "io", "component" }) do
  test(name .. " is not in the env",
    runChunk("print(" .. name .. " == nil)") == "true", runChunk("print(" .. name .. ")"))
end

test("string.dump is gone from the copy", runChunk("print(string.dump == nil)") == "true")
test("a global write stays in the chunk's env",
  (function() runChunk("load = 1"); return type(_G.load) == "function" end)())

print()
print("=== service start rshd ===")
print()
do
  local h
  for _, pre in ipairs({ "", base .. "../../../", "TOS-Dev/" }) do
    h = h or io.open(pre .. "tos/shell/panels/commands/admin.lua", "rb")
  end
  local admin = h:read("a"):gsub("\r\n", "\n"); h:close()
  local from = admin:find('elseif args[1] == "start" and args[2] then', 1, true)
  local to = admin:find('elseif args[1] == "stop" and args[2] then', from, true)
  local part = admin:sub(from, to)
  test("found the start branch", from ~= nil and to ~= nil)
  test("it asks the module, not a guess", part:find("remoteMod.stepBudgetAvailable()", 1, true) ~= nil)
  test("only for rshd", part:find('args[2]:find("rshd", 1, true)', 1, true) ~= nil)
  test("and only after a start that worked",
    part:find("if ok3 then", 1, true) < part:find("stepBudgetAvailable", 1, true))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
