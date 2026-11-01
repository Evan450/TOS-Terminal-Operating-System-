-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: an unknown flag is refused                   ║
-- ║                                                                ║
-- ║  Commands that take paths parsed their own flags, and anything ║
-- ║  they did not recognise fell through as a file name.           ║
-- ║  `mkdir --parent a` made a directory called --parent. A        ║
-- ║  misspelt flag was there to change what happens, so guessing   ║
-- ║  past it is the wrong answer: nothing happens, and it says so. ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_getopt.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 4e6 end,
  totalMemory = function() return 8e6 end, beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
  isAvailable = function() return false end, proxy = function() end }

local helpers = require("shell.panels.helpers")
local T = { error = "E", dim = "D" }
local function run(args, spec, usage)
  local said = {}
  local opts, rest = helpers.getopt(args, spec, function(t) said[#said + 1] = t end, T, usage)
  return opts, rest, table.concat(said, "\n")
end

print("=== the parser ===")
print()
local SPEC = { ["-r"] = "recursive", ["--hard"] = "hard", ["-n"] = { "count" }, number = "count" }
do
  local opts, rest = run({ "a", "-r", "b", "--hard" }, SPEC)
  test("flags land anywhere among the operands", opts.recursive and opts.hard
    and rest[1] == "a" and rest[2] == "b" and #rest == 2)
  opts, rest = run({ "-n", "3", "f" }, SPEC)
  test("a flag can take the next word", opts.count == "3" and rest[1] == "f" and #rest == 1)
  opts = run({ "-5" }, SPEC)
  test("-5 is a count where the command says so", opts.count == 5)
  local _, r, said = run({ "-5" }, { ["-r"] = "r" })
  test("and refused where it does not", r == nil and said:find("-5", 1, true) ~= nil)
  opts, rest = run({ "--", "-r", "--hard" }, SPEC)
  test("-- ends the flags", not opts.recursive and rest[1] == "-r" and rest[2] == "--hard")
  opts, rest = run({ "-" }, SPEC)
  test("a lone - is an operand", rest[1] == "-")
  local o2, r2, said2 = run({ "--hrad", "x" }, SPEC, "Usage: rm")
  test("an unknown flag refuses", o2 == nil and r2 == nil)
  test("names the word", said2:find("--hrad", 1, true) ~= nil, said2)
  test("says nothing happened", said2:find("Nothing was done", 1, true) ~= nil)
  test("and gives the usage", said2:find("Usage: rm", 1, true) ~= nil)
end

print()
print("=== on the real commands ===")
print()
do
  local made, removed, copied = {}, {}, {}
  local okR, register = pcall(require, "shell.panels.commands.core")
  assert(okR and type(register) == "function", tostring(register))
  local S = {
    K = {}, E = { push = function() end }, P = {}, D = {}, U = {},
    T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
    F = {
      exists = function() return true end, isDirectory = function() return false end,
      makeDirectory = function(p) made[#made + 1] = p; return true end,
      remove = function(p) removed[#removed + 1] = p; return true end,
      copy = function(a, b) copied[#copied + 1] = a .. ">" .. b; return true end,
      join = function(a, b) return a .. "/" .. b end,
      readFile = function() return "line\n" end, size = function() return 5 end,
      list = function() return {} end,
    },
    tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
  }
  local deps = {
    rp = function(p) return p end, openViewTab = function() end, openEditTab = function() end,
    refreshBrowser = function() end, canRead = function() return true end,
    canWrite = function() return true end, canAccess = function() return true end,
    rootOnly = function() return true end, adminOnly = function() return true end,
    makeProgramEnv = function() return {} end, promptInput = function() return "" end,
    confirm = function() return true end, confirmTyped = function() return true end,
  }
  local C = {}
  assert(pcall(register, C, S, deps))
  local function run2(fn, ...)
    local out = {}
    local ok, err = pcall(fn, { ... }, function(t) out[#out + 1] = tostring(t) end)
    return table.concat(out, "\n"), ok, err
  end

  local out = run2(C.mkdir, "--parent", "a")
  test("mkdir --parent makes nothing", #made == 0, made[1])
  test("and says why", out:find("--parent", 1, true) ~= nil, out)
  run2(C.mkdir, "--", "-odd")
  test("-- still reaches a name that starts with a dash", made[1] == "-odd", made[1])

  out = run2(C.rm, "--hrad", "x")
  test("rm --hrad removes nothing", #removed == 0 and out:find("--hrad", 1, true) ~= nil, out)

  out = run2(C.cp, "--recursive", "a", "b")
  test("cp --recursive copies nothing", #copied == 0 and out:find("Unknown", 1, true) ~= nil, out)
  local _, ok = run2(C.cp, "-r", "a", "b")
  test("cp -r still copies", ok and copied[1] == "a>b", copied[1])

  out = run2(C.grep, "-v", "x", "f")
  test("grep -v is refused, not searched for", out:find("Unknown", 1, true) ~= nil, out)
  out = run2(C.head, "-z", "f")
  test("head -z is refused", out:find("Unknown", 1, true) ~= nil, out)
  local okC
  out, okC = run2(C.compress, "--kep", "f")
  test("compress --kep is refused, without falling over",
    okC and out:find("Unknown", 1, true) ~= nil, out)
  out, okC = run2(C.decompress, "--kep", "f")
  test("so is decompress", okC and out:find("Unknown", 1, true) ~= nil, out)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
