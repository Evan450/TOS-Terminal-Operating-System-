-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: command-line cursor scroll            ║
-- ║  helpers.cmdScroll keeps the prompt cursor visible when ║
-- ║  the line is longer than the available columns.         ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cmd_cursor.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- helpers.lua requires "computer" at load time; cmdScroll never calls it.
package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local helpers = require("shell.panels.helpers")

-- ── cmdScroll: when does the line scroll? ───────────────────────────
-- Empty line, cursor at the only position: no scroll.
test("empty line no scroll", 0, helpers.cmdScroll(0, 1, 20))
-- A line that fits entirely: no scroll regardless of cursor.
test("short line, cursor mid", 0, helpers.cmdScroll(5, 3, 20))
test("short line, cursor end", 0, helpers.cmdScroll(5, 6, 20))
-- Line exactly fills the width with the cursor at the end: the cursor cell
-- (one past the last char) needs column `avail`, so we scroll by 1.
test("full-width, cursor at end scrolls 1", 1, helpers.cmdScroll(10, 11, 10))
-- A long line with the cursor at the very end: keep the tail visible.
-- cur0 = 30, avail = 10  ->  hs = 30 - 9 = 21.
test("long line, cursor at end", 21, helpers.cmdScroll(30, 31, 10))
-- Cursor moved back to the start of a long line: scroll back to 0.
test("long line, cursor at start", 0, helpers.cmdScroll(30, 1, 10))
-- Cursor in the middle, just past the right edge: scroll so it sits on the
-- last visible column.  cur0 = 15, avail = 10  ->  hs = 15 - 9 = 6.
test("long line, cursor mid-right", 6, helpers.cmdScroll(30, 16, 10))
-- Cursor within the first `avail` columns: no scroll yet.
test("long line, cursor still on-screen", 0, helpers.cmdScroll(30, 9, 10))

-- ── Degenerate widths ───────────────────────────────────────────────
test("avail < 1 clamps to 1", 4, helpers.cmdScroll(5, 5, 0))
test("nil cursor treated as end", 21, helpers.cmdScroll(30, nil, 10))
-- Cursor out of range is clamped into [0, len].
test("cursor past end clamped", 21, helpers.cmdScroll(30, 999, 10))
test("cursor below 1 clamped", 0, helpers.cmdScroll(30, -3, 10))

-- ── Editing model: insert / backspace / delete at the cursor ────────
-- Mirror the inline event-loop semantics so the slicing math is pinned by a
-- test even though the handlers themselves live in the event loop.
local function insert(s, cur, ch)
  return s:sub(1, cur - 1) .. ch .. s:sub(cur), cur + #ch
end
local function backspace(s, cur)
  if cur <= 1 then return s, cur end
  return s:sub(1, cur - 2) .. s:sub(cur), cur - 1
end
local function del(s, cur)
  if cur > #s then return s, cur end
  return s:sub(1, cur - 1) .. s:sub(cur + 1), cur
end

local s, c = "abc", 2                 -- cursor before "b"
s, c = insert(s, c, "X")              -- "aXbc", cursor 3
test("insert mid value", "aXbc", s)
test("insert mid cursor", 3, c)
s, c = backspace(s, c)                -- removes "X" -> "abc", cursor 2
test("backspace mid value", "abc", s)
test("backspace mid cursor", 2, c)
s, c = del(s, c)                      -- deletes "b" -> "ac", cursor 2
test("delete-at value", "ac", s)
test("delete-at cursor", 2, c)
s, c = backspace("ac", 1)             -- backspace at start: no-op
test("backspace at start no-op", "ac", s)
test("backspace at start cursor", 1, c)
s, c = del("ac", 3)                   -- delete past end: no-op
test("delete past end no-op", "ac", s)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
