-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: shell Tab completion                    ║
-- ║                                                            ║
-- ║  Tab completes the command (first word) or a path (args).  ║
-- ║  Pins the pure core: completeToken (prefix/common-prefix)  ║
-- ║  and completeCmdline (command vs path, trailing space/"/").║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_completion.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got '" .. tostring(actual) .. "')", expected == actual)
end

package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;" .. package.path
local H = require("shell.panels.helpers")

print("=== Tab completion Tests ===")
print()

-- ── completeToken ──────────────────────────────────────────────────
local cmds = { "cat", "cd", "chat", "chmod", "clear", "ls", "mail" }
do
  local comp, m = H.completeToken("ma", cmds)
  eq("unique 'ma' completes to mail", "mail", comp)
  eq("...with one match", 1, #m)
end
do
  local comp, m = H.completeToken("c", cmds)
  -- cat/cd/chat/chmod/clear share only "c"
  eq("ambiguous 'c' → common prefix 'c'", "c", comp)
  eq("...5 matches", 5, #m)
end
do
  local comp, m = H.completeToken("ch", cmds)
  -- chat/chmod share "ch"
  eq("'ch' → common prefix 'ch'", "ch", comp)
  eq("...2 matches (chat, chmod)", 2, #m)
end
do
  local comp, m = H.completeToken("zz", cmds)
  eq("no match leaves prefix", "zz", comp)
  eq("...0 matches", 0, #m)
end

-- ── completeCmdline: command (first word) ──────────────────────────
do
  local cl, m = H.completeCmdline("ma", cmds, nil)
  eq("first word: unique command + trailing space", "mail ", cl)
  eq("...1 match", 1, #m)
end
do
  local cl = H.completeCmdline("ch", cmds, nil)
  eq("first word: ambiguous → common prefix, no space", "ch", cl)
end

-- ── completeCmdline: path argument (fake listDir) ──────────────────
local FS = {
  [""]      = { { name = "notes.txt" }, { name = "docs", dir = true }, { name = "data", dir = true } },
  ["docs/"] = { { name = "readme.md" }, { name = "draft.txt" } },
}
local function listDir(dirPart) return FS[dirPart] or {} end

do
  local cl, m = H.completeCmdline("cat no", cmds, listDir)
  eq("arg: unique file → name + space", "cat notes.txt ", cl)
  eq("...1 match", 1, #m)
end
do
  local cl, m = H.completeCmdline("cd d", cmds, listDir)
  -- docs/ and data/ share "d"
  eq("arg: ambiguous dirs → common prefix", "cd d", cl)
  eq("...2 matches", 2, #m)
end
do
  local cl = H.completeCmdline("cd doc", cmds, listDir)
  eq("arg: unique dir gets a trailing slash", "cd docs/", cl)
end
do
  local cl = H.completeCmdline("cat docs/dr", cmds, listDir)
  eq("arg: completes inside a subdir", "cat docs/draft.txt ", cl)
end
do
  -- Tab on a trailing space lists everything in the dir (common prefix "").
  local _, m = H.completeCmdline("ls ", cmds, listDir)
  eq("arg: empty token lists all entries", 3, #m)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
