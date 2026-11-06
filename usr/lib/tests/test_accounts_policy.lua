-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: who manages accounts is the operator's       ║
-- ║                                                                ║
-- ║  useradd, userdel and usermod were root only, fixed. The        ║
-- ║  operator now chooses, at install or with `users manage`:       ║
-- ║  root only, the default, or admins as well. An admin is held    ║
-- ║  to ordinary accounts: never another admin or root, and never   ║
-- ║  making one. Runs the real admin.lua against a recording        ║
-- ║  kernel.users, with the seat's tier coming from its session.    ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_accounts_policy.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 10 end,
  totalMemory = function() return 2048 * 1024 end,
  freeMemory = function() return 1024 * 1024 end,
}
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
local helpers = require("shell.panels.helpers")

local function machine(callerTier, adminsAllowed)
  local calls = {}
  local accounts = {
    { username = "root", tier = 3 }, { username = "boss", tier = 2 },
    { username = "alice", tier = 1 },
  }
  local cfg = { accountAdmins = adminsAllowed }
  local saved = false
  local U = {
    getSession = function() return { user = callerTier >= 3 and "root" or "boss", tier = callerTier } end,
    list = function() return accounts end,
    create = function(_, name, _, tier) calls[#calls + 1] = "create " .. name .. " " .. tier; return true end,
    delete = function(_, name) calls[#calls + 1] = "delete " .. name; return true end,
    setTier = function(_, name, t) calls[#calls + 1] = "tier " .. name .. " " .. t; return true end,
    setLocked = function(_, name, v) calls[#calls + 1] = "lock " .. name .. " " .. tostring(v); return true end,
  }
  local S = {
    T = setmetatable({}, { __index = function(_, k) return k end }),
    F = {}, K = {}, U = U, st = "tok",
    SC = { get = function(k) return cfg[k] end, set = function(k, v) cfg[k] = v end,
           save = function() saved = true; return true end },
  }
  local deps = {
    rp = function(p) return p end,
    rootOnly = function(o) return helpers.rootOnly(S, o) end,
    adminOnly = function(o) return helpers.adminOnly(S, o) end,
    promptInput = function() return "Passw0rd99" end,
    confirmBox = function() return true end,
    confirm = function() return true end, confirmTyped = function() return true end,
  }
  local C = {}
  assert(loadfile("tos/shell/panels/commands/admin.lua"))()(C, S, deps)
  local function run(name, ...)
    local out = {}
    C[name]({ ... }, function(line) out[#out + 1] = tostring(line) end)
    return table.concat(out, "\n"), calls
  end
  return run, calls, cfg, function() return saved end
end

print("=== root only, the default ===")
print()
do
  local run, calls = machine(3, false)
  run("useradd", "bob")
  test("root adds an account", calls[#calls] == "create bob 1")
  run("usermod", "alice", "admin")
  test("root makes an admin", calls[#calls] == "tier alice 2")
  run("userdel", "boss")
  test("root removes an admin", calls[#calls] == "delete boss")
end
do
  local run, calls = machine(2, nil)
  local text = run("useradd", "bob")
  test("with nothing set, an admin cannot add an account", #calls == 0)
  test("and is told who can, and how to change it", text:find("users manage admins", 1, true) ~= nil, text)
  run("userdel", "alice")
  test("nor remove one", #calls == 0)
end

print()
print("=== the operator lets admins in ===")
print()
do
  local run, calls = machine(2, true)
  run("useradd", "bob")
  test("an admin adds an ordinary account", calls[#calls] == "create bob 1")
  run("usermod", "alice", "lock")
  test("locks one", calls[#calls] == "lock alice true")
  run("userdel", "alice")
  test("removes one", calls[#calls] == "delete alice")
  local n = #calls
  local text = run("usermod", "alice", "admin")
  test("but never makes an admin", #calls == n and text:find("Only root makes", 1, true) ~= nil, text)
  run("usermod", "alice", "root")
  test("or a root account", #calls == n)
  text = run("userdel", "boss")
  test("and never removes another admin", #calls == n and text:find("ordinary accounts only", 1, true) ~= nil, text)
  run("usermod", "boss", "lock")
  test("or locks one", #calls == n)
  run("userdel", "root")
  test("or touches root", #calls == n)
end
do
  local run, calls = machine(1, true)
  run("useradd", "bob")
  test("an ordinary user still cannot, whatever is set", #calls == 0)
end

print()
print("=== changing it ===")
print()
do
  local run, _, cfg, saved = machine(2, false)
  local text = run("users", "manage", "admins")
  test("an admin cannot widen it", cfg.accountAdmins == false and not saved(), text)
  test("but may read it", run("users", "manage"):find("root only", 1, true) ~= nil)
end
do
  local run, _, cfg, saved = machine(3, false)
  run("users", "manage", "admins")
  test("root can let admins in", cfg.accountAdmins == true and saved())
  run("users", "manage", "root")
  test("and take it back", cfg.accountAdmins == false)
  test("anything else is refused", run("users", "manage", "everyone"):find("Usage", 1, true) ~= nil
    and cfg.accountAdmins == false)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
