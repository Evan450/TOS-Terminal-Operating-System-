-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what a built-in does with a pipe            ║
-- ║                                                               ║
-- ║  On a headless machine `cat f | wc` said "0 lines" for a      ║
-- ║  one-line file, and `cat f | head -n 1` said "Usage: head":   ║
-- ║  the pipeline joins lines with no trailing newline, wc        ║
-- ║  counted newlines, and only grep and wc were ever given the   ║
-- ║  piped text. The manual says pipes work. Drives the REAL      ║
-- ║  executor and the real pipe parser.                           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pipe_stdin.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1048576 end, totalMemory = function() return 2097152 end }
package.loaded["component"] = { list = function() return function() end end }
package.loaded["shell.panels.helpers"] = {
  expandBuf = function(_, buf)
    local out = {}
    for i, e in ipairs(buf) do out[i] = type(e) == "table" and e or { tostring(e), "FG" } end
    return out
  end,
  canWrite = function() return true end, refreshBrowser = function() end,
  expandAlias = function(_, parts) return parts end, resolveProgram = function() return nil end,
  clearFailure = function() end, noteFailure = function() end,
  liveTier = function() return 3 end, tierName = function(n) return "tier " .. n end,
  fail = function(_, msg, o) o(msg, "ERR"); return false end,
}
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
package.loaded["kernel.pkg"] = { getCommand = function() return nil end,
                                 getCommandScreen = function() return nil end }

local executorMod = require("shell.panels.executor")
local S = {
  W = 80, H = 25, T = { error = "ERR", highlight = "HL", fg = "FG" }, cwd = "/",
  F = { join = function(a, b) return a .. "/" .. b end, exists = function() return false end },
  D = {}, U = { getSession = function() return { user = "root", tier = 3 } end }, st = "r",
}
local printed
local fileRead
local exec = executorMod.build(S, {
  rp = function(p) return p end,
  makeProgramEnv = function() return {} end,
  showOutput = function(wrapped) for _, l in ipairs(wrapped) do printed[#printed + 1] = l[1] end end,
  C = {
    one   = function(_, o) o("only line") end,
    three = function(_, o) o("first"); o("second"); o("third") end,
    head  = function(args, o) fileRead = args[#args]; o("from the file") end,
    tail  = function(args, o) fileRead = args[#args]; o("from the file") end,
  },
})
local function run(line)
  printed, fileRead = {}, nil
  exec(line)
  return table.concat(printed, " | ")
end
local function has(line, text)
  local out = run(line)
  return out:find(text, 1, true) ~= nil, out
end

print("=== pipes into built-ins ===")
test("wc counts the last line of a pipe", has("three | wc", " 3 lines"))
test("...and a single line is one line", has("one | wc", " 1 lines"))
test("head takes the first lines of a pipe", run("three | head -n 2") == "first | second", run("three | head -n 2"))
test("head's default is ten", run("three | head") == "first | second | third", run("three | head"))
test("-N is the same as -n N", run("three | head -1") == "first", run("three | head -1"))
test("tail takes the last lines of a pipe", run("three | tail -n 2") == "second | third", run("three | tail -n 2"))
test("tail asked for more than there is gives what there is",
  run("three | tail -n 99") == "first | second | third", run("three | tail -n 99"))
test("zero lines is none", run("three | head -n 0") == "", run("three | head -n 0"))
local out = run("three | head -n 1 /some/file")
test("a file named on the command line still wins", fileRead == "/some/file" and out == "from the file", out)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
