-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a keystroke in the chat tab paints one row   ║
-- ║                                                                ║
-- ║  Typing returned draw level 3, and an app tab has one way to   ║
-- ║  draw, so every key cleared the screen and re-wrapped every    ║
-- ║  message: about 16 keys a second on the runner's T2 APU, and a ║
-- ║  pasted line lagged (TODO, SMALLER, NOTED IN PASSING). A key   ║
-- ║  that only edits the input now repaints the input row itself   ║
-- ║  and asks for nothing more. Enter, PgUp and the quit key still ║
-- ║  repaint in full, because they change more than one row.       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_chat_keystroke.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 42 end,
  pullSignal = function() return "key_down", "kb", 17, 16 end }
local chat = require("shell.panels.chatapp")

-- A screen that remembers every row a call touched, and what row 24 says.
local W, H = 80, 25
local touched, row = {}, {}
local function reset() touched = {} end
local D = {
  fill = function(x, y, w, h, ch)
    for yy = y, y + h - 1 do
      touched[yy] = true
      if yy == H - 1 then row = {} end
    end
  end,
  set = function(x, y, s)
    touched[y] = true
    if y == H - 1 then for i = 1, #s do row[x + i - 1] = s:sub(i, i) end end
  end,
}
local function rowText()
  local out = {}
  for i = 1, W do out[i] = row[i] or " " end
  return (table.concat(out):gsub("%s+$", ""))
end
local S = { D = D, W = W, H = H, T = setmetatable({}, { __index = function() return 0 end }), who = "root" }
local tab = { type = "chat", input = "", messages = { { time = 0, text = "hello there" } }, scroll = 0 }

print("=== a typed character ===")
reset()
local lvl = chat.handleKey(S, tab, string.byte("a"), 30)
test("asks for no further redraw", lvl == 0, lvl)
local rows = {}
for y in pairs(touched) do rows[#rows + 1] = y end
test("touches only the input row", #rows == 1 and rows[1] == H - 1, table.concat(rows, ","))
test("which shows what was typed", rowText() == "> a_", rowText())
chat.handleKey(S, tab, string.byte("b"), 48)
test("a second key adds to it", rowText() == "> ab_", rowText())

print("=== Backspace ===")
reset()
lvl = chat.handleKey(S, tab, 0, 14)
test("asks for no further redraw", lvl == 0, lvl)
test("and leaves nothing of the deleted character", rowText() == "> a_", rowText())
chat.handleKey(S, tab, 0, 14)
chat.handleKey(S, tab, 0, 14)   -- past empty: nothing to delete
test("down to an empty prompt", rowText() == "> _", rowText())

print("=== keys that change more still repaint in full ===")
test("PgUp", chat.handleKey(S, tab, 0, 201) == 3)
test("PgDn", chat.handleKey(S, tab, 0, 209) == 3)

print("=== a long line scrolls inside the row ===")
tab.input = string.rep("x", 100)
reset()
chat.drawInput(S, tab)
test("it fits the screen", #rowText() <= W, #rowText())
test("ending at the cursor", rowText():sub(-2) == "x_", rowText():sub(-4))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
