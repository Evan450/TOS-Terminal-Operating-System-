-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: OpenOS programs can load in the sandbox       ║
-- ║                                                                ║
-- ║  Found 2026-10-09 on the headless machine: the data loot disk's ║
-- ║  base64, installed from an OPPM repo, died on line 1 --         ║
-- ║  "module 'shell' is not available to sandboxed code". The       ║
-- ║  sandbox's require refused every OpenOS name: shell and         ║
-- ║  filesystem as TOS internals, the rest as "not on the allowed   ║
-- ║  list". The compat modules behind them were reachable all along ║
-- ║  as compat.*; nothing mapped the names a program actually uses. ║
-- ║  Nor did a sandbox have unicode, checkArg, os.sleep or os.exit. ║
-- ║                                                                ║
-- ║  Drives the REAL sandbox.build and its require.                 ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_openos_names.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 500000 end,
  pushSignal = function() end, address = function() return "addr" end,
}
package.loaded["kernel.screen"] = {}
package.loaded["kernel.fs"] = { exists = function() return false end }
-- A bus with a GPU (a base type), a data card (in no set unless the
-- operator adds it) and a filesystem (never reachable).
local DEVICES = { gpu1 = "gpu", data1 = "data", fs1 = "filesystem" }
local ORDER = { "gpu1", "data1", "fs1" }
local PROXIES = {}
for a, t in pairs(DEVICES) do PROXIES[a] = { address = a, type = t } end
package.loaded["component"] = {
  list = function(filter, exact)
    local i = 0
    return function()
      while true do
        i = i + 1
        local a = ORDER[i]
        if not a then return nil end
        local t = DEVICES[a]
        if not filter or (exact and t == filter) or (not exact and t:find(filter, 1, true)) then
          return a, t
        end
      end
    end
  end,
  type = function(a) return DEVICES[a] end,
  proxy = function(a) return PROXIES[a] end,
  slot = function() return -1 end,
  -- OC's raw library has no getPrimary until compat.init adds one; the
  -- view must find a device without it.
}
local slept = {}
package.loaded["kernel.process"] = {
  sleep = function(s) slept[#slept + 1] = s end,
  current = function() return nil end,
}

-- The compat modules, as stand-ins that say who they are.
local gpuCapsSeen = nil
local stubs = {
  ["compat.shell_api"] = { who = "shell_api", parse = function(...) return { ... }, {} end },
  ["compat.term"] = { who = "term", _gpuForCaps = function(c) gpuCapsSeen = c; return "gpu" end },
  ["compat.event"] = { who = "event" },
  ["compat.io"] = { who = "io" },
  ["compat.filesystem"] = { who = "filesystem" },
  ["compat.internet"] = { who = "internet" },
  ["compat.serialization"] = { who = "serialization" },
  ["compat.text"] = { who = "text" },
  ["compat.sides"] = { who = "sides" }, ["compat.colors"] = { who = "colors" },
  ["compat.keyboard"] = { who = "keyboard" }, ["compat.buffer"] = { who = "buffer" },
  ["compat.robot"] = { who = "robot" }, ["compat.note"] = { who = "note" },
  ["compat.process"] = { who = "process" },
}
for k, v in pairs(stubs) do package.loaded[k] = v end
-- What the KERNEL's require would load for the bare name "shell": TOS's own
-- shell. The sandbox must never hand this out.
package.loaded["shell"] = { who = "THE TOS SHELL" }
package.loaded["unicode"] = { len = function(s) return #s end, char = string.char }

local sandbox = require("kernel.sandbox")
local function run(caps, src)
  local env = sandbox.build({ caps = caps })
  local fn = assert(load(src, "=probe", "t", env))
  local ok, err = pcall(fn)
  return env, ok, err
end

print("=== OpenOS names in the sandbox ===")
print()

print("-- with the compat surface an OPPM package is granted --")
do
  local env, ok, err = run({ ["compat.io"] = true, ["fs.read"] = true, ["fs.write"] = true }, [[
    shellW   = require("shell").who
    sameSh   = require("shell") == require("compat.shell_api")
    termW    = require("term").who
    sameTerm = require("term") == require("compat.term")
    gpu      = require("term").gpu()
    eventW   = require("event").who
    serW     = require("serialization").who
    textW    = require("text").who
    procW    = require("process").who
    noteW    = require("note").who
    sameIo   = require("io") == io
    sameFs   = require("filesystem") == filesystem
    uni      = require("unicode") == unicode
    hasUni   = type(unicode) == "table" and unicode.len("abc") == 3
  ]])
  test("the probe ran (" .. tostring(err) .. ")", ok)
  test("require('shell') is the compat shell", env.shellW == "shell_api")
  test("...the same view as require('compat.shell_api')", env.sameSh == true)
  test("...and never TOS's own shell", env.shellW ~= "THE TOS SHELL")
  test("require('term') is compat.term", env.termW == "term" and env.sameTerm == true)
  test("...with term.gpu still bound to THIS sandbox's caps",
    env.gpu == "gpu" and type(gpuCapsSeen) == "table" and gpuCapsSeen["compat.io"] == true)
  test("require('event') is compat.event", env.eventW == "event")
  test("serialization, text, process and note resolve",
    env.serW == "serialization" and env.textW == "text" and env.procW == "process"
    and env.noteW == "note")
  test("require('io') is the io global", env.sameIo == true)
  test("require('filesystem') is the filesystem global", env.sameFs == true)
  test("require('unicode') is the unicode global", env.uni == true)
  test("unicode is a global, as OpenComputers gives every program", env.hasUni == true)
end

print("-- the names grant nothing their compat names do not --")
do
  local env = run({}, [[
    local okSh, e1 = pcall(require, "shell");      gotSh, whySh = okSh, tostring(e1)
    local okIo = pcall(require, "io");              gotIo = okIo
    local okFs = pcall(require, "filesystem");      gotFs = okFs
    local okT, t = pcall(require, "term");          gotTerm = okT and t.who
  ]])
  test("no caps: require('shell') is refused", env.gotSh == false)
  test("...naming the OpenOS name and the capability it needs",
    env.whySh:find("require('shell')", 1, true) ~= nil
    and env.whySh:find("compat.io capability", 1, true) ~= nil)
  test("...and io and filesystem are refused too", env.gotIo == false and env.gotFs == false)
  test("term needs no cap, exactly as compat.term did", env.gotTerm == "term")

  local env2 = run({ ["compat.io"] = true }, [[
    local ok = pcall(require, "internet"); gotNet = ok ]])
  test("require('internet') still needs the internet cap", env2.gotNet == false)
  local env3 = run({ internet = true }, [[ gotNet = require("internet").who ]])
  test("...and is served with it", env3.gotNet == "internet")
end

print("-- component, by type, as OpenOS has it --")
do
  local env, ok, err = run({ component = true }, [[
    gpu      = component.gpu
    fsP      = component.filesystem
    dataP    = component.data
    sameReq  = require("component") == component
    sameCmp  = require("compat.component") == component
    listed   = {}
    for a, t in component.list() do listed[#listed + 1] = t end
    wrote    = pcall(function() component.proxy = function() end end)
    meta     = getmetatable(component)
    names    = {}
    local n = 0
    for k in pairs(component) do n = n + 1; names[k] = true end
    nNames   = n
  ]])
  test("the probe ran (" .. tostring(err) .. ")", ok)
  test("component.gpu is the primary GPU", env.gpu == PROXIES.gpu1)
  test("component.filesystem stays nil (the caps refuse it)", env.fsP == nil)
  test("component.data stays nil (no cap or config grants it)", env.dataP == nil)
  test("require('component') is the same view", env.sameReq == true)
  test("require('compat.component') is the same view", env.sameCmp == true)
  test("list() shows only what the caps allow", #env.listed == 1 and env.listed[1] == "gpu")
  test("the view is read-only", env.wrote == false)
  test("its metatable is locked", env.meta == false)
  test("pairs() walks the library's functions",
    env.nNames > 0 and env.names.list == true and env.names.proxy == true)

  local env2 = run({}, [[ local ok = pcall(require, "component"); got = ok; g = component ]])
  test("without the component cap there is no component at all",
    env2.got == false and env2.g == nil)
end

print("-- io.write reaches the runner's stdout --")
do
  -- A compat.io whose file opens are recorded; buffer is the REAL
  -- compat/buffer.lua (package.path), since the sink is built from it.
  local opened = {}
  stubs["compat.io"].open = function(path, mode)
    local f = { path = path, mode = mode, data = "" }
    function f:write(...) for i = 1, select("#", ...) do self.data = self.data .. tostring(select(i, ...)) end; return self end
    function f:close() self.closed = true; return true end
    opened[#opened + 1] = f
    return f
  end
  stubs["compat.io"].stdin = { read = function() return nil end, lines = function() return function() end end }
  package.loaded["compat.buffer"] = nil   -- the real one, not the name stub

  local lines = {}
  local env = sandbox.build({ caps = { ["compat.io"] = true }, stdout = function(l) lines[#lines + 1] = l end })
  local fn = assert(load([[
    io.write("a", "b"); print("c")
    io.write("d\ne"); io.stdout:write("f\n"); io.stderr:write("g\n")
    local same = require("io") == io
    io.write(same and "same" or "different", "\n")
    io.write("tail")
  ]], "=probe", "t", env))
  local ok, err = pcall(fn)
  test("the probe ran (" .. tostring(err) .. ")", ok)
  test("print and io.write share one line, in order", lines[1] == "abc")
  test("a newline inside a write splits the line", lines[2] == "d")
  test("io.stdout:write continues the pending line", lines[3] == "ef")
  test("io.stderr reaches the runner too", lines[4] == "g")
  test("require('io') is the routed io", lines[5] == "same")
  test("the unterminated last line waits...", #lines == 5)
  sandbox.finish(env)
  test("...until the runner finishes the program", lines[6] == "tail")
  sandbox.finish(env)
  test("finish is once", #lines == 6)

  -- io.output(f) belongs to the program that said it.
  local linesA, linesB = {}, {}
  local envA = sandbox.build({ caps = { ["compat.io"] = true }, stdout = function(l) linesA[#linesA + 1] = l end })
  local envB = sandbox.build({ caps = { ["compat.io"] = true }, stdout = function(l) linesB[#linesB + 1] = l end })
  assert(load([[ io.output("/tmp/a.txt"); io.write("to file\n") ]], "=A", "t", envA))()
  assert(load([[ io.write("to screen\n") ]], "=B", "t", envB))()
  test("A's io.output redirected A's writes", opened[1] and opened[1].data == "to file\n")
  test("...and not B's", linesB[1] == "to screen" and #linesA == 0)
  assert(load([[ io.output(io.stdout); io.write("back\n") ]], "=A2", "t", envA))()
  test("restoring io.stdout closes the file and writes to the runner again",
    opened[1].closed == true and linesA[1] == "back")

  -- No stdout given: the env's io is compat.io's own view, as before.
  local env3 = sandbox.build({ caps = { ["compat.io"] = true } })
  test("without a runner stdout, io is compat.io's view", env3.io.who == "io")
end

print("-- Safe Mode --")
do
  _G._TOS = { compatDisabled = true }
  local env = run({ ["compat.io"] = true }, [[
    local ok, e = pcall(require, "term"); got, why = ok, tostring(e) ]])
  _G._TOS = nil
  test("with the compat layer off, require('term') is refused", env.got == false)
  test("...and says why", env.why:find("compat layer is off", 1, true) ~= nil)
end

print("-- checkArg --")
do
  local env = run({}, [[
    okNum = pcall(checkArg, 1, 5, "number")
    okAny = pcall(checkArg, 2, "x", "number", "string")
    local ok, e = pcall(checkArg, 1, 5, "string", "nil"); bad, why = ok, e ]])
  test("checkArg accepts a matching type", env.okNum == true and env.okAny == true)
  test("...and refuses a wrong one", env.bad == false)
  test("...with OpenComputers' wording",
    tostring(env.why):find("bad argument #1 (string or nil expected, got number)", 1, true) ~= nil)
end

print("-- os.sleep and os.exit --")
do
  local env, ok = run({ ["compat.io"] = true }, [[ os.sleep(0.25) ]])
  test("os.sleep yields through kernel.process.sleep", ok and slept[#slept] == 0.25)

  local _, ok0, e0 = run({ ["compat.io"] = true }, [[ os.exit() ]])
  test("os.exit() ends the program with an error...", ok0 == false)
  test("...that sandbox.exitStatus knows as an exit", sandbox.exitStatus(e0) == true)
  test("...and describeEnd reports nothing", sandbox.describeEnd(false, e0) == nil)

  local _, _, e3 = run({ ["compat.io"] = true }, [[ os.exit(3) ]])
  test("os.exit(3) carries its status", sandbox.exitStatus(e3) == 3)
  local text, isErr = sandbox.describeEnd(false, e3)
  test("...and is reported as a status, not an error",
    text == "exited with status 3" and isErr == false)
  local _, _, eT = run({ ["compat.io"] = true }, [[ os.exit(true) ]])
  test("os.exit(true) is clean", sandbox.describeEnd(false, eT) == nil)

  local _, _, eF = run({}, [[ error({ code = 0 }) ]])
  test("a table error is not mistaken for an exit", sandbox.exitStatus(eF) == nil)
  local t2, isErr2 = sandbox.describeEnd(false, "boom")
  test("a real error is still an error", t2 == "boom" and isErr2 == true)
  test("a returned number is shown", sandbox.describeEnd(true, 4) == "4")
  test("...and a string and a boolean",
    sandbox.describeEnd(true, "hi") == "hi" and sandbox.describeEnd(true, false) == "false")
  test("a returned table is not printed as an address", sandbox.describeEnd(true, {}) == nil)
  test("...nor a function", sandbox.describeEnd(true, print) == nil)

  local env4 = run({ ["compat.io"] = true }, [[
    local ok, e = pcall(os.exit, 0)
    mt = getmetatable(e)
    canSet = pcall(setmetatable, e, {})
  ]])
  test("the exit error's metatable is locked", env4.mt == false and env4.canSet == false)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
