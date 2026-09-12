-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: showing a file costs the file once, and stops ║
-- ║  before the machine runs out                                    ║
-- ║                                                                ║
-- ║  `cat` read the whole file into one string and made a          ║
-- ║  { line, colour } table per line; the executor wrapped that    ║
-- ║  into a second table per line, and the view tab wrapped THAT   ║
-- ║  into a third. A 32 KB file peaked at 305 KB -- more than a    ║
-- ║  256 KB machine has (Sep 2026 pentest, RAM pass). `more`, the  ║
-- ║  browser's View and the context menu's View read it whole too. ║
-- ║  Drives the REAL helpers, editor and core commands.            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_view_memory.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_view_memory.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path
local function srcOf(rel)
  for _, p in ipairs({ base .. "../../../tos/" .. rel, "tos/" .. rel, "TOS-Dev/tos/" .. rel }) do
    local f = io.open(p, "rb")
    if f then local s = f:read("a"); f:close(); return s end
  end
  return ""
end

local FREE = function() return 1e9 end
package.loaded["computer"] = {
  uptime = function() return 0 end,
  freeMemory = function() return FREE() end,
  totalMemory = function() return 256 * 1024 end,
  pullSignal = function() return nil end, beep = function() end,
  shutdown = function() end,
}
package.loaded["component"] = { list = function() return function() end end,
  proxy = function() end, isAvailable = function() return false end }
local captured
package.loaded["shell.panels.tabs"] = {
  create = function(_, _, _, t) captured = t; return t end,
}

local helpers = require("shell.panels.helpers")
local editor = require("shell.panels.editor")

local T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 }
local S0 = { W = 80, tier = 3, T = T }

-- A file of 800 short lines, served the way securefs serves one.
local LINES, WIDTH = 800, 40
local fileLines = {}
for i = 1, LINES do fileLines[i] = string.format("%05d ", i) .. string.rep("x", WIDTH - 6) end
local FILE = table.concat(fileLines, "\n") .. "\n"
local wholeReads = 0
local fakeF = {
  open = function(p)
    if p ~= "/home/a/big.txt" then return nil, "no such file" end
    local pos = 1
    return {
      read = function(_, n)
        if pos > #FILE then return nil end
        local c = FILE:sub(pos, pos + n - 1); pos = pos + n; return c
      end,
      close = function() end,
    }
  end,
  readFile = function(p)
    if p == "/home/a/big.txt" then wholeReads = wholeReads + 1; return FILE end
    return nil
  end,
  exists = function(p) return p == "/home/a/big.txt" end,
  isDirectory = function() return false end,
  size = function() return #FILE end,
}

local function allocKB(fn)
  collectgarbage(); collectgarbage()
  local before = collectgarbage("count")
  collectgarbage("stop")
  local r = fn()
  local used = collectgarbage("count") - before
  collectgarbage("restart")
  return used, r
end

print("=== showing a file costs the file once ===")
print()
print("-- expandBuf passes a line that fits straight through --")
local raw = {}
for i = 1, LINES do raw[i] = { fileLines[i], T.fg } end
local kb, wrapped = allocKB(function() return helpers.expandBuf(S0, raw) end)
test("every fitting entry is the same table, not a copy", wrapped[1] == raw[1] and wrapped[LINES] == raw[LINES])
test(string.format("wrapping %d lines that fit allocates %.1f KB (a slot each, not a table each)", LINES, kb),
  kb < 40)
local long = helpers.expandBuf(S0, { { string.rep("word ", 40), T.warning }, "plain", { "nocolour" } })
test("a long line still wraps, keeping its colour", #long > 3 and long[1][2] == T.warning and long[2][2] == T.warning)
test("a plain string entry becomes { text, fg }", long[#long - 1][1] == "plain" and long[#long - 1][2] == T.fg)
test("an entry with no colour gets fg", long[#long][1] == "nocolour" and long[#long][2] == T.fg)

print()
print("-- a view tab does not wrap what is already wrapped --")
captured = nil
editor.openViewTab(S0, wrapped, "big", true)
test("openViewTab(..., true) keeps the table it was given", captured and captured.content == wrapped)
test("the executor says its output is already wrapped",
  srcOf("shell/panels/executor.lua"):find('ed.openViewTab(S, wrapped, label or "output", true)', 1, true) ~= nil)
test("so does the context menu's Run",
  srcOf("shell/panels/context.lua"):find("editor.openViewTab(S, wrapped, S.ctxFile.name, true)", 1, true) ~= nil)

print()
print("-- cat and more stream, and stop before the machine runs out --")
local Cmds = require("shell.panels.commands")
local viewed
local deps = {
  rp = function(p) return p end,
  openViewTab = function(buf) viewed = buf end, openEditTab = function() end,
  refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  promptInput = function() return nil end,
}
local function makeState()
  return {
    T = T, W = 80, H = 25, tier = 3, userTier = 3, st = nil, U = nil,
    K = { getLog = function() return nil end }, E = { push = function() end }, P = {},
    F = fakeF, SC = nil, NM = nil, who = "a", cwd = "/home/a",
    tabs = { { type = "shell" } }, activeTab = 1,
    browser = { path = "/home/a", sel = 1, scroll = 0, files = {} },
  }
end
local C = Cmds.build(makeState(), deps)
local out = {}
local function o(text, color) out[#out + 1] = { tostring(text), color } end

wholeReads = 0
C.cat({ "/home/a/big.txt" }, o)
test("cat shows every line", #out == LINES and out[LINES][1] == fileLines[LINES])
test("...without reading the whole file into one string", wholeReads == 0)

-- Memory shrinking as lines are shown: cat must stop, and say so.
out = {}
FREE = function() return 96 * 1024 - #out * 150 end
C.cat({ "/home/a/big.txt" }, o)
local last = out[#out]
test(string.format("with memory running short cat stops (%d of %d lines)", #out - 1, LINES),
  #out < LINES and #out > 64)
test("...and its last line says why and what to use instead",
  last and last[2] == T.warning and last[1]:find("memory is low", 1, true) ~= nil)

viewed = nil
FREE = function() return 20 * 1024 end
wholeReads = 0
C.more({ "/home/a/big.txt" }, o)
test("more under the floor opens a tab that says why it is short",
  viewed and viewed[#viewed][1]:find("memory is low", 1, true) ~= nil and #viewed < LINES)
test("...and does not read the whole file either", wholeReads == 0)
FREE = function() return 1e9 end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
