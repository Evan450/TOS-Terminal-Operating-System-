-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  Test: compat/process.lua — and why `path` must never be a guess   ║
-- ║                                                                    ║
-- ║  Every real use of this API in the wild is a program looking for    ║
-- ║  its own directory:                                                ║
-- ║      fs.path(process.running())                                    ║
-- ║      fs.concat(fs.path(shell.resolve(process.running())), "/data") ║
-- ║      shell.resolve(process.info().path, "lua")                     ║
-- ║  which makes a plausible-but-wrong path WORSE than nil: nil fails  ║
-- ║  at the call that needed the answer, where a wrong path silently   ║
-- ║  writes the program's state file somewhere nobody will look.       ║
-- ║                                                                    ║
-- ║  So the rules pinned here are: a launch name that is not a path    ║
-- ║  never becomes one, and the process NAME ("prog:tetris@1") is      ║
-- ║  never offered as a path. The sandbox supplies the real path       ║
-- ║  because it is the only thing that knows it.                       ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_compat_process.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. " (expected " .. tostring(expected) ..
          ", got " .. tostring(actual) .. ")")
  end
end

package.path = "tos/?.lua;" .. package.path

local current = { pid = 7, name = "prog:tetris@1" }
package.loaded["kernel.process"] = { current = function() return current end }

local process = require("compat.process")

print("── the unbound module reports what the kernel knows ──")
do
  local info = process.info()
  test("info() returns a table", type(info) == "table")
  eq("command is the process name", "prog:tetris@1", info.command)
  eq("path is nil — a process NAME is not a path", nil, info.path)
  eq("data.vars exists so a caller can index it", "table", type(info.data.vars))
end

print("── running() is the three-value form of info() ──")
do
  local path, env, command = process.running()
  eq("no path", nil, path)
  eq("no env",  nil, env)
  eq("command", "prog:tetris@1", command)
end

print("── no process, no answer ──")
do
  local saved = current
  current = nil
  eq("info() is nil outside a process", nil, process.info())
  eq("running() is nil too", nil, (process.running()))
  current = saved
end

print("── argument checking matches OpenOS ──")
test("a string level raises",        not pcall(process.info, "1"))
test("a table raises",               not pcall(process.info, {}))
test("nil is fine",                  pcall(process.info))
test("a number is fine",             pcall(process.info, 1))
test("a coroutine is fine",          pcall(process.info, coroutine.create(function() end)))

print("── _forProgram: the sandbox binds the launch path ──")
do
  local env = { marker = "this sandbox's globals" }
  local bound = process._forProgram("/usr/bin/oppm.lua", env)
  local info = bound.info()
  eq("path is the launch path", "/usr/bin/oppm.lua", info.path)
  eq("env is the sandbox env",  env, info.env)
  eq("command follows the path", "/usr/bin/oppm.lua", info.command)
  local p, e, c = bound.running()
  eq("running() gives the path", "/usr/bin/oppm.lua", p)
  eq("running() gives the env",  env, e)
  eq("running() gives the command", "/usr/bin/oppm.lua", c)
end

print("── a launch name that is not a path stays out of `path` ──")
do
  eq("a bare command word",    nil, process._forProgram("tetris").info().path)
  eq("the executor's seat name", nil,
     process._forProgram("prog:tetris@1").info().path)
  eq("nil",                    nil, process._forProgram(nil).info().path)
  eq("a number",               nil, process._forProgram(42).info().path)
  test("but a real path gets through",
       process._forProgram("/home/me/x.lua").info().path == "/home/me/x.lua")
  test("a relative path with a slash counts",
       process._forProgram("bin/x.lua").info().path == "bin/x.lua")
end

print("── the deliberate omissions stay omitted ──")
test("no process.load (spawning belongs to kernel.process)",
     process.load == nil)
test("no process.internal", process.internal == nil)
test("no process.list",     process.list == nil)

print("── the sandbox wiring is actually there ──")
do
  local f = io.open("tos/kernel/sandbox.lua", "r")
  local src = f and f:read("*a") or ""
  if f then f:close() end
  test("sandbox.lua masks _forProgram from the sandbox view",
       src:find('%["compat%.process"%]%s*=%s*{%s*_forProgram%s*=%s*true') ~= nil)
  test("sandbox.lua binds info/running for compat.process",
       src:find('real%._forProgram%(opts and opts%.name') ~= nil)
  test("it binds .info",    src:find("mod%.info%s*=%s*bound%.info") ~= nil)
  test("it binds .running", src:find("mod%.running%s*=%s*bound%.running") ~= nil)
end

print("")
print("Results: " .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
print("All tests passed.")
