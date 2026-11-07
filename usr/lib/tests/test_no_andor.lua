-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: && and || run as a shell runs them           ║
-- ║                                                                ║
-- ║  TOS's shell had neither. `whoami && echo X` ran whoami, which ║
-- ║  ignored the rest of the line, and said nothing; `a || b` was  ║
-- ║  split at its bars into a pipe, so b ran whatever a did, the   ║
-- ║  opposite of ||. From 2026-11-06 both were refused. Since      ║
-- ║  2026-11-07 they work: left to right, `&&` after a success,    ║
-- ║  `||` after a failure, a skipped part leaving the status as it ║
-- ║  was. A command failed when it printed in the error colour or  ║
-- ║  refused -- the record `why` already reads. Quoted, they are   ║
-- ║  just text; a single bar is still a pipe. Drives the real      ║
-- ║  executor.                                                     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_no_andor.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

_G._TOS = _G._TOS or {}
package.path = "tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }
-- The failure record is the real thing's shape: noted by the first error
-- line, cleared at each dispatch.
package.loaded["shell.panels.helpers"] = {
  mayHavePackages = function() return false end,
  routeOutput = function(n) return n == 0 and "clear" or "inline" end,
  expandBuf = function(_, buf) return buf end,
  canWrite = function() return true end,
  refreshBrowser = function() end,
  expandAlias = function(_, parts) return parts end,
  resolveProgram = function() return nil end,
  clearFailure = function(S) S.lastFailure = nil end,
  noteFailure = function(S, cmd, text) if not S.lastFailure then S.lastFailure = { cmd = cmd, text = text } end end,
  liveTier = function() return 3 end,
  tierName = function() return "ROOT" end,
  fail = function(S, msg, o) S.lastFailure = { text = msg }; if o then o(msg, 3) end; return false end,
}
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
package.loaded["kernel.process"] = { current = function() return nil end, inProcess = function() return false end }

local ran = {}
local S
local C = {
  whoami = function(_, o) ran[#ran + 1] = "whoami"; o("root") end,
  echo = function(args, o) ran[#ran + 1] = "echo"; o(table.concat(args, " ")) end,
  good = function(_, o) ran[#ran + 1] = "good"; o("fine") end,
  bad = function(_, o) ran[#ran + 1] = "bad"; o("it broke", 3) end,
  -- Refuses through S.lastOut alone, as twenty admin commands do.
  quiet = function() ran[#ran + 1] = "quiet"; S.lastOut = { "refused", 3 } end,
}
S = {
  W = 80, H = 25, T = { fg = 1, error = 3 }, cwd = "/",
  F = { join = function(a, b) return a .. "/" .. b end, exists = function() return false end },
  D = {}, U = {},
}
local shown
local exec = require("shell.panels.executor").build(S, {
  rp = function(p) return p end, makeProgramEnv = function() return {} end, C = C,
  showOutput = function(wrapped) shown = wrapped end,
})
local function run(line)
  ran, shown = {}, nil
  exec(line)
  local said = type(S.lastOut) == "table" and S.lastOut[1] or tostring(S.lastOut or "")
  local text = {}
  for _, e in ipairs(shown or {}) do text[#text + 1] = type(e) == "table" and e[1] or tostring(e) end
  return said, table.concat(ran, ","), table.concat(text, "|")
end

print("=== && runs the next part after a success, and only then ===")
local said, r, out = run("good && echo X")
test("good && echo X runs both", r == "good,echo", r)
test("showing both outputs, in order", out == "fine|X", out)
said, r = run("bad && echo X")
test("bad && echo X stops after bad", r == "bad", r)
said, r, out = run("whoami&&echo X")
test("without spaces as well", r == "whoami,echo" and out == "root|X", r .. " / " .. out)

print("=== || runs the next part after a failure, and only then ===")
said, r = run("bad || echo X")
test("bad || echo X runs echo", r == "bad,echo", r)
said, r = run("good || echo X")
test("good || echo X does not", r == "good", r)
said, r = run("quiet || echo X")
test("a refusal through lastOut alone is a failure", r == "quiet,echo", r)
said, r, out = run("quiet || echo X")
test("and its words are still shown", out:find("refused", 1, true) ~= nil, out)
said, r = run("nosuch && echo X")
test("an unknown command is a failure", r == "", r)
said, r = run("nosuch || echo X")
test("...so || goes on", r == "echo", r)

print("=== a skipped part leaves the status as it was ===")
said, r = run("bad && echo A || echo B")
test("bad && A || B runs B, not A", r == "bad,echo", r)
said, r, out = run("bad && echo A || echo B")
test("...and B is what is shown", out == "it broke|B", out)
said, r = run("good && bad || echo C")
test("good && bad || C runs all three", r == "good,bad,echo", r)
said, r = run("good || bad && echo D")
test("good || bad && D skips bad and runs D", r == "good,echo", r)

print("=== quoted, they are only text ===")
said, r, out = run('echo "a && b"')
test("a quoted && is echoed", r == "echo" and out == "a && b", out)
said, r, out = run("echo 'x || y'")
test("a quoted || is echoed", r == "echo" and out == "x || y", out)

print("=== a single bar is still a pipe ===")
said, r = run("whoami | echo piped")
test("whoami | echo runs both", r == "whoami,echo", r)
said, r = run("whoami | echo a && echo b")
test("a pipe inside a chain part", r == "whoami,echo,echo", r)

print("=== an empty side is refused, and nothing runs ===")
said, r = run("&& echo X")
test("nothing before && is refused", said:find("nothing before &&", 1, true) ~= nil and r == "", said)
said, r = run("echo X ||")
test("nothing after || is refused", said:find("nothing after ||", 1, true) ~= nil and r == "", said)
said, r = run("echo A && && echo B")
test("two operators in a row are refused", said:find("nothing before &&", 1, true) ~= nil and r == "", said)

_G._TOS = nil
print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
