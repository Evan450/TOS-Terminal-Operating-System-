-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: addressable local IPC                        ║
-- ║                                                                ║
-- ║  A call crosses from sandboxed code into a service that runs   ║
-- ║  through the kernel loader, so this is a privilege boundary    ║
-- ║  and the tests are about what cannot cross it: a metatable, a  ║
-- ║  function, a live table in either direction, a forged user, a  ║
-- ║  name the program holds no capability for, or a squatted name. ║
-- ║                                                                ║
-- ║  Drives the real kernel.ipc through the real sandbox.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_ipc.lua   (from TOS-Dev)

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
  type = function() end, isAvailable = function() return false end,
}
package.loaded["kernel.fs"] = {
  exists = function() return false end, isDirectory = function() return false end,
  readFile = function() return nil end,
}

local ipc = require("kernel.ipc")
local sandbox = require("kernel.sandbox")

print("=== registering ===")
do
  test("a service registers", ipc.register("echo", function(_, ...) return ... end, "svc-a") == true)
  local ok, why = ipc.register("echo", function() end, "svc-b")
  test("someone else cannot take the name", ok == false and tostring(why):find("svc-a", 1, true), why)
  test("the owner can again, after a restart", ipc.register("echo", function(_, ...) return ... end, "svc-a") == true)
  test("a bad name is refused", ipc.register("Bad Name", function() end, "x") == false)
  test("a name is lowercase", ipc.register("ECHO", function() end, "x") == false)
  test("a handler must be a function", ipc.register("h", "nope", "x") == false)
  test("someone else cannot give it up", ipc.unregister("echo", "svc-b") == false)
  test("the owner can", ipc.unregister("echo", "svc-a") == true)
  local a, b = ipc.call("echo", nil)
  test("then it is not running", a == nil and b == "not running", b)
  ipc.register("echo", function(_, ...) return ... end, "svc-a")
end

print("=== who is calling ===")
do
  local seen
  ipc.register("who", function(caller) seen = caller; return true end, "svc")
  ipc.call("who", { user = "ann", tier = 2, secret = "tok" })
  test("the handler is told the user and tier", seen.user == "ann" and seen.tier == 2)
  test("and nothing else from the session", seen.secret == nil)
  ipc.call("who", nil)
  test("no session is tier 0", seen.tier == 0 and seen.user == nil)
end

print("=== only plain data crosses ===")
do
  local a, b, c = ipc.call("echo", nil, 1, "two", { three = 3 })
  test("values come back", a == 1 and b == "two" and c.three == 3)
  local x, y, z = ipc.call("echo", nil, nil, false, nil)
  test("nils in a list are kept", x == nil and y == false and z == nil)

  local mine = { n = 1 }
  local out = ipc.call("echo", nil, mine)
  test("a table is copied going in and out", out ~= mine and out.n == 1)

  local ran = false
  local evil = setmetatable({}, {
    __index = function() ran = true end,
    __pairs = function() ran = true; return next, {}, nil end,
    __gc = function() end,
  })
  local got = ipc.call("echo", nil, evil)
  test("a metatable does not cross, and is never consulted",
    not ran and got ~= evil and getmetatable(got) == nil)

  local r1, r2 = ipc.call("echo", nil, print)
  test("a function is refused", r1 == nil and tostring(r2):find("function", 1, true), r2)
  local t1, t2 = ipc.call("echo", nil, { f = print })
  test("inside a table too", t1 == nil and tostring(t2):find("function", 1, true), t2)
  local c1, c2 = ipc.call("echo", nil, coroutine.create(print))
  test("a thread is refused", c1 == nil and tostring(c2):find("thread", 1, true), c2)

  local k1 = ipc.call("echo", nil, { [{}] = 1 })
  test("a table key is refused", k1 == nil)

  local loop = {}; loop.self = loop
  local l1, l2 = ipc.call("echo", nil, loop)
  test("a cycle is refused", l1 == nil and tostring(l2):find("cycle", 1, true), l2)

  local shared = { 1 }
  local s1 = ipc.call("echo", nil, { a = shared, b = shared })
  test("the same table twice is not a cycle", s1 and s1.a[1] == 1 and s1.b[1] == 1)

  local deep = {}
  local at = deep
  for _ = 1, 40 do at.next = {}; at = at.next end
  local d1, d2 = ipc.call("echo", nil, deep)
  test("a table too deep is refused", d1 == nil and tostring(d2):find("deep", 1, true), d2)

  local huge = {}
  for i = 1, 9000 do huge[i] = i end
  local h1, h2 = ipc.call("echo", nil, huge)
  test("a table too large is refused", h1 == nil and tostring(h2):find("large", 1, true), h2)
end

print("=== a service cannot hand out its state ===")
do
  local live = { count = 1 }
  ipc.register("state", function() return live end, "svc")
  local got = ipc.call("state", nil)
  got.count = 99
  test("what comes back is a copy", live.count == 1)
  ipc.register("leak", function() return function() end end, "svc")
  local a, b = ipc.call("leak", nil)
  test("a function handed back is refused", a == nil and tostring(b):find("function", 1, true), b)
end

print("=== a handler's failure stays a failure ===")
do
  ipc.register("boom", function() error("broken", 0) end, "svc")
  local a, b = ipc.call("boom", nil)
  test("an error comes back as nil, message", a == nil and b == "broken", b)
end

print("=== through the real sandbox ===")
do
  local seen
  ipc.register("mail", function(caller, x) seen = caller; return x end, "svc")
  local session = { user = "bob", tier = 1 }
  local env = sandbox.build({ name = "p", session = session,
    caps = { ["ipc:mail"] = true, ["fs.read"] = true } })
  test("a program with the cap has ipc.call", type(env.ipc) == "table" and type(env.ipc.call) == "function")
  test("and no way to register", env.ipc.register == nil and env.ipc.unregister == nil)
  test("it gets its answer", env.ipc.call("mail", 7) == 7)
  test("as its own session", seen.user == "bob" and seen.tier == 1)

  env.ipc.call("mail", { user = "root", tier = 3 })
  test("what it passes cannot change who it is", seen.user == "bob" and seen.tier == 1)

  local a, b = env.ipc.call("echo", 1)
  test("a name it has no cap for is refused", a == nil and tostring(b):find("may not reach", 1, true), b)

  local plainEnv = sandbox.build({ name = "q", session = session, caps = { ["fs.read"] = true } })
  test("a program without the cap has no ipc at all", plainEnv.ipc == nil)

  local okR = pcall(function() return plainEnv.require("kernel.ipc") end)
  test("and cannot require the kernel module", okR == false)
  local okW = pcall(function() return env.require("kernel.ipc") end)
  test("nor can the one with the cap", okW == false)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
