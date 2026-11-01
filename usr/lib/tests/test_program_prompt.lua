-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a program can ask a question                 ║
-- ║                                                                ║
-- ║  A program run from the prompt writes through a line sink, and ║
-- ║  a line with no newline waited there until the program ended.  ║
-- ║  A question has no newline, so `io.write("Name: ")` followed   ║
-- ║  by a read showed nothing and the machine looked hung. Before  ║
-- ║  a read the partial line goes out now, and the runner is told, ║
-- ║  so it can say where the typing appears. rc's masked prompt    ║
-- ║  was blank for the same reason.                                ║
-- ║                                                                ║
-- ║  Drives the real sandbox with a stand-in compat.term.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_program_prompt.lua   (from TOS-Dev)

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

local reads, seenAtRead = {}, nil
local events
local stubTerm = {
  read = function() events[#events + 1] = "term.read"; return "typed\n" end,
  _gpuForCaps = function() return {} end,
}
package.loaded["compat.term"] = stubTerm

local sandbox = require("kernel.sandbox")

local function build(extra)
  events = {}
  local opts = {
    name = "p",
    caps = { ["fs.read"] = true, ["compat.io"] = true },
    stdout = function(line) events[#events + 1] = "out:" .. line end,
    beforeRead = function(partial) events[#events + 1] = "before:" .. partial end,
  }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return sandbox.build(opts)
end

print("=== a question reaches the runner before the read ===")
do
  local env = build()
  assert(env.io and env.io.write, "the sandbox has an io")
  env.io.write("Name: ")
  test("nothing is said while the line is open", #events == 0, events[1])
  local term = env.require("compat.term")
  term.read()
  test("the partial line goes out first", events[1] == "before:Name: ", events[1])
  test("then the read", events[2] == "term.read", events[2])
  sandbox.finish(env)
  test("and it is not said again at the end", #events == 2, #events)
end

print("=== full lines still come out as lines ===")
do
  local env = build()
  env.io.write("one\ntwo\npart")
  test("the two whole lines", events[1] == "out:one" and events[2] == "out:two", events[2])
  local term = env.require("compat.term")
  term.read()
  test("the rest before the read", events[3] == "before:part", events[3])
end

print("=== a read with nothing pending still tells the runner ===")
do
  local env = build()
  env.require("compat.term").read()
  test("so it can place the typing", events[1] == "before:", events[1])
end

print("=== a runner with no hook gets the line as output ===")
do
  local env = build({ beforeRead = false })
  env.io.write("Name: ")
  env.require("compat.term").read()
  test("it is not lost", events[1] == "out:Name: ", events[1])
end

print("=== the term view keeps what the sandbox gives it ===")
do
  local env = build()
  test("gpu is still the sandbox's own", type(env.require("compat.term").gpu) == "function")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
