-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a long message is not cut off the screen      ║
-- ║                                                                ║
-- ║  Operator screenshot, real emulator. Deleting /usr printed:     ║
-- ║                                                                ║
-- ║    Delete failed: Refused: removing /usr is a protected system  ║
-- ║    path. This guard sit                                         ║
-- ║                                                                ║
-- ║  — stopping mid-word at the right edge. The message exists to   ║
-- ║  explain a refusal, and the explanation is the half that got    ║
-- ║  cut.                                                           ║
-- ║                                                                ║
-- ║  S.lastOut is one row by construction and outRow fits text TO   ║
-- ║  that row. The multi-row region already existed for command     ║
-- ║  output (outLines: grows upward, stops at the top of the        ║
-- ║  content area), so a message that does not fit uses it. Short   ║
-- ║  messages -- nearly all of them -- still take exactly one row.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_out_message_wrap.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local here = (arg and arg[0]) or "usr/lib/tests/test_out_message_wrap.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

local drawMod = require("shell.panels.draw")

-- A display that records what lands on each row.
local W, H = 80, 25
local function newState()
  local rows = {}
  local D = {}
  function D.set(x, y, text, fg, bg)
    rows[y] = rows[y] or {}
    rows[y][#rows[y] + 1] = { x = x, text = text, fg = fg }
  end
  function D.fill() end
  local S = {
    D = D, W = W, H = H,
    OUT_ROW = 22, LIST_TOP = 3, TILE_TOP = 4,
    padW = string.rep(" ", W + 4),
    T = setmetatable({ error = 0xFF0000, dim = 0x888888, fg = 0xFFFFFF, bg = 0 },
                     { __index = function() return 0 end }),
  }
  return S, rows
end
-- Every column of text that reached a row, in order.
local function rowText(rows, y)
  if not rows[y] then return nil end
  local parts = {}
  for _, e in ipairs(rows[y]) do parts[#parts + 1] = e.text end
  return table.concat(parts)
end
local function rowsTouched(rows)
  local n = 0
  for _ in pairs(rows) do n = n + 1 end
  return n
end

print("=== a long message wraps instead of being cut ===")
print()

-- The operator's actual message.
local LONG = "Delete failed: Refused: removing /usr is a protected system path. "
  .. "This guard sits below securefs so even root cannot remove it by accident; "
  .. "turn it off for one session with `protect off`."

-- ── Short messages are unchanged ─────────────────────────────────
print("-- a short message still takes one row --")
do
  local S, rows = newState()
  drawMod.outMessage(S, "Deleted: notes.txt", S.T.dim)
  eq("exactly one row touched", 1, rowsTouched(rows))
  test("...and it is the output row", rows[S.OUT_ROW] ~= nil)
  test("the text is there in full",
    (rowText(rows, S.OUT_ROW) or ""):find("Deleted: notes.txt", 1, true) ~= nil)
end

-- ── The long one is not truncated ────────────────────────────────
print()
print("-- the long one keeps every word --")
do
  local S, rows = newState()
  drawMod.outMessage(S, LONG, S.T.error)
  local touched = rowsTouched(rows)
  test("it used more than one row (" .. touched .. ")", touched > 1)

  -- Reassemble what the operator would read, top row first.
  local ys = {}
  for y in pairs(rows) do ys[#ys + 1] = y end
  table.sort(ys)
  local seen = {}
  for _, y in ipairs(ys) do seen[#seen + 1] = (rowText(rows, y) or "") end
  local joined = table.concat(seen, " "):gsub("%s+", " ")

  test("the sentence that explains the refusal survived",
    joined:find("This guard sits below securefs", 1, true) ~= nil)
  test("...and so does the last word",
    joined:find("protect off", 1, true) ~= nil)
  test("nothing was cut at 'This guard sit'",
    joined:find("This guard sit`", 1, true) == nil)

  -- No row may be wider than the screen.
  local tooWide = nil
  for _, y in ipairs(ys) do
    for _, e in ipairs(rows[y]) do
      if e.x + #e.text - 1 > W + #S.padW then tooWide = y end
    end
  end
  eq("no row was drawn past the screen edge", nil, tooWide)

  -- It grows UPWARD from the output row and stops there.
  eq("the last row used is the output row", S.OUT_ROW, ys[#ys])
  test("it grew upward, not down", ys[1] < S.OUT_ROW)
  test("it never reached the top of the file list", ys[1] >= S.LIST_TOP)
end

-- ── It cannot eat the whole screen ───────────────────────────────
print()
print("-- an absurd message is bounded by the content area --")
do
  local S, rows = newState()
  drawMod.outMessage(S, string.rep("wordy ", 400), S.T.error)
  local ys = {}
  for y in pairs(rows) do ys[#ys + 1] = y end
  table.sort(ys)
  test("it stops at the top of the list, whatever the length",
    ys[1] >= S.LIST_TOP)
  eq("...and still ends on the output row", S.OUT_ROW, ys[#ys])
end

-- ── The colour is kept ───────────────────────────────────────────
print()
print("-- an error still looks like an error --")
do
  local S, rows = newState()
  drawMod.outMessage(S, LONG, S.T.error)
  local allRed = true
  for _, es in pairs(rows) do
    for _, e in ipairs(es) do if e.fg ~= S.T.error then allRed = false end end
  end
  test("every wrapped row carries the message's colour", allRed)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
