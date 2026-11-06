-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a built-in command is heard while it runs    ║
-- ║                                                                ║
-- ║  Programs and package commands were made live on 2026-11-01;   ║
-- ║  built-ins still wrote to the executor's buffer. `verify` at   ║
-- ║  the command line on the headless machine showed nothing for   ║
-- ║  over a minute, then 171 lines at once, so a slow built-in     ║
-- ║  looked hung. In the full interface each line is now echoed    ║
-- ║  to the output row too, at most four times a second, except    ║
-- ║  a question about to wait for its answer. Drives the real      ║
-- ║  executor in both shells' shapes.                              ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_builtin_output_live.lua   (from TOS-Dev)

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

local clock = 0
package.loaded["computer"] = { uptime = function() return clock end }
package.loaded["shell.panels.helpers"] = {
  mayHavePackages = function() return true end,
  routeOutput = function(n) return n == 0 and "clear" or "inline" end,
  expandBuf = function(_, buf) return buf end,
  canWrite = function() return true end,
  refreshBrowser = function() end,
  expandAlias = function(_, parts) return parts end,
  resolveProgram = function() return nil end,
  clearFailure = function() end,
  noteFailure = function() end,
  liveTier = function() return 3 end,
  tierName = function() return "ROOT" end,
  fail = function(_, msg, o) o(msg, "ERR"); return false end,
}
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
package.loaded["compat.term"] = { setCursor = function() end }
local me = { name = "shell" }
package.loaded["kernel.process"] = {
  current = function() return me end,
  inProcess = function() return false end,
}

local during = {}
local readHook
package.loaded["kernel.pkg"] = {
  getCommand = function(name)
    if name == "ask" then
      return function(_, o)
        readHook = me.beforeRead
        o("first")
        if me.beforeRead then me.beforeRead("Name: ") end
      end
    end
  end,
  getCommandScreen = function() return nil end,
}

-- A slow built-in: three lines, the clock moving a little between them.
local C = {}
C.slow = function(_, o)
  o("checking 1", 5)
  during.liveAfterFirst = #during.live
  clock = clock + 0.1
  o("checking 2")
  clock = clock + 0.1
  o("Result: 2 OK")
  during.liveAfterLast = #during.live
end

local function shell(shape)
  local S = {
    W = 80, H = 25, T = { fg = 1, error = 3 }, cwd = "/",
    F = { join = function(a, b) return a .. "/" .. b end, exists = function() return false end },
    D = {}, U = {},
  }
  local deps = { rp = function(p) return p end, makeProgramEnv = function() return {} end, C = C,
                  showOutput = function(wrapped) during.shown = wrapped end }
  if shape == "cli" then
    deps.liveLine = function(text, color) during.live[#during.live + 1] = { text, color } end
    deps.inputRow = function() return 20 end
  else
    deps.echoLine = function(text) during.echo[#during.echo + 1] = text end
    deps.inputRow = function() return 20 end
  end
  return require("shell.panels.executor").build(S, deps)
end

local function texts(buf)
  local t = {}
  for _, e in ipairs(buf or {}) do t[#t + 1] = type(e) == "table" and e[1] or tostring(e) end
  return table.concat(t, "|")
end

print("=== at the command line ===")
local cli = shell("cli")
during = { live = {}, echo = {} }
cli("slow")
local buf = during.shown
test("its first line is on screen before the command goes on", during.liveAfterFirst == 1,
  during.liveAfterFirst)
test("and all three are by the time it ends", during.liveAfterLast == 3, during.liveAfterLast)
test("with their colour", during.live[1] and during.live[1][2] == 5)
test("and none is printed a second time from the buffer", not texts(buf):find("checking", 1, true),
  texts(buf))

during = { live = {}, echo = {} }
cli("slow | cat")
local piped = during.shown
test("in a pipe the buffer is still the output", #during.live == 0 and texts(piped):find("Result", 1, true) ~= nil,
  #during.live)

me.beforeRead = nil
during = { live = {}, echo = {} }
cli("slow")
test("a built-in gets no read hook (it reads through promptInput)", me.beforeRead == nil)

print("=== in the full interface ===")
local tui = shell("tui")
clock = 10
during = { live = {}, echo = {} }
tui("slow")
local tbuf = during.shown
test("every line is kept for the output pane", texts(tbuf):find("checking 1|checking 2|Result: 2 OK", 1, true) ~= nil,
  texts(tbuf))
test("the first is echoed to the output row as it happens", during.echo[1] == "checking 1",
  table.concat(during.echo, "|"))
test("and the rest no more than four times a second", #during.echo == 1, #during.echo)
clock = 20
during = { live = {}, echo = {} }
tui("ask")
test("a question about to wait is echoed even inside the quarter second",
  during.echo[#during.echo] == "Name: ", table.concat(during.echo, "|"))
test("(the package still gets its read hook)", type(readHook) == "function")

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
