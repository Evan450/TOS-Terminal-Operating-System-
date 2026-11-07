-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the editor never opens a failed read blank   ║
-- ║                                                                ║
-- ║  openEditTab read the file with `readFile(path) or ""`.        ║
-- ║  readFile answers nil when a read fails -- "not enough memory" ║
-- ║  for a large file on a small machine, among others -- so the   ║
-- ║  editor showed an empty buffer for a file with contents, and   ║
-- ║  saving it wrote that over the real file. Found by sweeping    ║
-- ║  for the same `or ""` that lost files in kernel.backup and     ║
-- ║  tape store.                                                   ║
-- ║                                                                ║
-- ║  Drives the real shell/panels/editor.lua.                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_editor_open_unreadable.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end,
                                freeMemory = function() return 1e6 end,
                                pullSignal = function() return nil end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }
package.loaded["kernel.screen"]  = {}
package.loaded["kernel.display"] = {}

local okE, editor = pcall(require, "shell.panels.editor")
test("editor.lua loads", okE and type(editor) == "table", editor)
if not (okE and type(editor) == "table") then
  print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***"); os.exit(1)
end
local helpers = require("shell.panels.helpers")
-- Nothing here asks for packages: keep the "open with" lookup out of it.
helpers.mayHavePackages = function() return false end

local files = {
  ["/home/big.txt"] = "line one\nline two\n",
  ["/home/empty.txt"] = "",
}
local failRead = {}
local function seat()
  local S = {
    tabs = {}, activeTab = nil, W = 80, H = 25,
    T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
    F = {
      exists = function(p) return files[p] ~= nil end,
      readFile = function(p)
        if failRead[p] then return nil, failRead[p] end
        return files[p]
      end,
      isDirectory = function() return false end,
    },
  }
  return S
end
local function editTabs(S)
  local n, last = 0, nil
  for _, t in ipairs(S.tabs or {}) do
    if t.kind == "edit" or t.type == "edit" then n = n + 1; last = t end
  end
  return n, last
end

print("=== a read that fails opens nothing ===")
do
  local S = seat()
  failRead["/home/big.txt"] = "/tos/kernel/fs.lua:80: not enough memory for buffer allocation"
  editor.openEditTab(S, "/home/big.txt")
  failRead["/home/big.txt"] = nil
  local n = editTabs(S)
  test("no editor tab is opened", n == 0, n)
  local msg = S.lastOut and S.lastOut[1] or ""
  test("the operator is told why", tostring(msg):find("not enough memory", 1, true) ~= nil, msg)
  test("and that nothing can be saved over it",
    tostring(msg):find("nothing can be saved over it", 1, true) ~= nil, msg)
  test("without Lua's file:line in front", not tostring(msg):find("fs.lua:80", 1, true), msg)
  test("tagged so `why` explains it", tostring(msg):find("[E-202 ERR_OUT_OF_MEMORY]", 1, true) ~= nil, msg)
end

print("=== an empty file still opens, empty ===")
do
  local S = seat()
  editor.openEditTab(S, "/home/empty.txt")
  local n, tab = editTabs(S)
  test("one editor tab", n == 1, n)
  local lines = tab and (tab.lines or (tab.data and tab.data.lines))
  test("with one empty line", type(lines) == "table" and #lines == 1 and lines[1] == "",
    lines and #lines)
end

print("=== a readable file opens with its lines ===")
do
  local S = seat()
  editor.openEditTab(S, "/home/big.txt")
  local n, tab = editTabs(S)
  test("one editor tab", n == 1, n)
  local lines = tab and (tab.lines or (tab.data and tab.data.lines))
  test("holding both lines", type(lines) == "table" and lines[1] == "line one"
    and lines[2] == "line two" and #lines == 2, lines and #lines)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
