-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: selection + the text clipboard           ║
-- ║                                                            ║
-- ║  Three surfaces select text — the prompt, the editor and a ║
-- ║  read-only view buffer — and all three go through the same ║
-- ║  pure maths in panels/selection.lua and the same per-seat   ║
-- ║  store in kernel/clipboard.lua. This pins both, plus the    ║
-- ║  binding decisions, because those were forced rather than   ║
-- ║  chosen and a later reader will want to know why:           ║
-- ║                                                            ║
-- ║    · copy is Ctrl+Insert because kernel/init.lua CONSUMES  ║
-- ║      char 3 for the foreground interrupt and blanks the    ║
-- ║      signal — ^C cannot reach a program at all             ║
-- ║    · Shift+Delete and Delete are the same scancode, so     ║
-- ║      matchers carry modifier requirements and keys.is is   ║
-- ║      handed the live modifier state                        ║
-- ║    · that state has to EXPIRE, or a Shift held while the   ║
-- ║      player closed the screen GUI wedges selection on      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_clipboard.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.loaded["computer"] = {
  uptime      = function() return 0 end,
  freeMemory  = function() return 900 * 1024 end,
  totalMemory = function() return 1024 * 1024 end,
}
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local keys = require("shell.keys")
local sel  = require("shell.panels.selection")
local clip = require("kernel.clipboard")

print("=== Selection + clipboard Tests ===")
print()

-- ══════════════════════════════════════════════════════════════
-- The bindings, and why they are what they are
-- ══════════════════════════════════════════════════════════════
do
  eq("copy is Ctrl+Insert", "Ctrl+Insert", keys.label("copy"))
  eq("cut is Shift+Delete or ^X", "Shift+Delete / ^X", keys.label("cut"))
  eq("paste is Shift+Insert or ^V", "Shift+Insert / ^V", keys.label("paste"))

  -- The reason copy is not ^C. If this ever stops being true, copy can
  -- move — but until then a ^C binding would be a key that silently
  -- does nothing, which is worse than an unfamiliar one.
  test("^C is reserved by the kernel", keys.isReserved("^C"))
  test("^X is not reserved", not keys.isReserved("^X"))

  -- Modifier+named parsing, both ways.
  local m = keys.parse("Ctrl+Insert")
  test("Ctrl+Insert parses to a code matcher", m and m.code == 210 and m.needCtrl == true)
  eq("...and renders back", "Ctrl+Insert", keys.name(m))
  local d = keys.parse("Shift+Delete")
  test("Shift+Delete parses", d and d.code == 211 and d.needShift == true)
  eq("...and renders back", "Shift+Delete", keys.name(d))
  test("a bare named key carries no requirement",
    keys.parse("Insert").needCtrl == nil)
  test("junk still fails to parse", keys.parse("Hyper+Banana") == nil)
end

-- ══════════════════════════════════════════════════════════════
-- Modifier-aware matching
-- ══════════════════════════════════════════════════════════════
do
  local none  = keys.newMods()
  local ctrl  = keys.newMods(); ctrl.ctrl = true
  local shift = keys.newMods(); shift.shift = true

  test("Ctrl+Insert is copy", keys.is("copy", nil, 210, nil, ctrl))
  test("plain Insert is NOT copy", not keys.is("copy", nil, 210, nil, none))
  test("Shift+Insert is paste", keys.is("paste", nil, 210, nil, shift))
  test("Shift+Delete is cut", keys.is("cut", nil, 211, nil, shift))
  test("plain Delete is NOT cut", not keys.is("cut", nil, 211, nil, none))
  test("^X is cut by character", keys.is("cut", 24, 45, nil, none))
  test("^V is paste by character", keys.is("paste", 22, 47, nil, none))

  -- Back-compat: every call site written before modifiers existed passes
  -- four arguments, and must keep matching exactly as it did.
  test("without mods, a code matcher still matches", keys.is("view", nil, 60))
  test("without mods, quit still matches F10", keys.is("quit", nil, 68))
end

-- ══════════════════════════════════════════════════════════════
-- Tracking Shift, and recovering when the key_up never comes
-- ══════════════════════════════════════════════════════════════
do
  local m = keys.newMods()
  test("nothing held to begin with", not keys.modDown(m, "shift", 0))

  test("a shift press is reported as a modifier key",
    keys.trackMods(m, "key_down", nil, 42, 1) == true)
  test("...and shift is now down", keys.modDown(m, "shift", 1))
  test("an ordinary key is not a modifier key",
    keys.trackMods(m, "key_down", 97, 30, 2) == false)
  test("...and shift is still down through it", keys.modDown(m, "shift", 2))
  keys.trackMods(m, "key_up", nil, 42, 3)
  test("released", not keys.modDown(m, "shift", 3))

  -- The stuck case: Shift down, then the key_up is lost because the
  -- player closed the screen GUI. Without expiry this wedges every
  -- arrow key into extending a selection until the operator re-logs in.
  local stuck = keys.newMods()
  keys.trackMods(stuck, "key_down", nil, 42, 100)
  test("held at t+1", keys.modDown(stuck, "shift", 101))
  test("still held just before the timeout",
    keys.modDown(stuck, "shift", 100 + keys.STALE_AFTER - 1))
  test("treated as released once stale",
    not keys.modDown(stuck, "shift", 100 + keys.STALE_AFTER + 1))

  -- A printable character proves Ctrl and Alt are not held: both
  -- suppress the character. Cheap self-correction for a lost key_up.
  local c = keys.newMods()
  keys.trackMods(c, "key_down", nil, 29, 1)     -- Ctrl down
  test("ctrl held", keys.modDown(c, "ctrl", 1))
  keys.trackMods(c, "key_down", 97, 30, 2)      -- a plain "a" arrives
  test("a printable char clears ctrl", not keys.modDown(c, "ctrl", 2))
end

-- ══════════════════════════════════════════════════════════════
-- One-line selection maths (the command prompt)
-- ══════════════════════════════════════════════════════════════
do
  eq("range normalises backwards selections", 3, (select(1, sel.range(7, 3))))
  eq("...to the same end", 7, (select(2, sel.range(7, 3))))
  test("an empty selection is not a selection", sel.range(4, 4) == nil)
  test("a nil anchor is not a selection", sel.range(nil, 4) == nil)

  eq("text takes the selected run", "hello", sel.text("hello world", 1, 6))
  eq("text is direction-agnostic", "hello", sel.text("hello world", 6, 1))

  local s, removed, cur = sel.remove("hello world", 1, 6)
  eq("remove cuts it out", " world", s)
  eq("...and hands back what it took", "hello", removed)
  eq("...leaving the cursor where it was", 1, cur)

  local s2, cur2 = sel.insert("ls ", 4, "-l")
  eq("insert places text", "ls -l", s2)
  eq("...and lands after it", 6, cur2)

  eq("replace swaps the run", "goodbye world", (sel.replace("hello world", 1, 6, "goodbye")))

  -- No selection: remove is a no-op, which is what lets the caller run
  -- it unconditionally on "the operator typed a character".
  local s3, r3 = sel.remove("hello", nil, 3)
  eq("no selection leaves the string alone", "hello", s3)
  eq("...and removes nothing", nil, r3)
end

-- ══════════════════════════════════════════════════════════════
-- Block selection maths (the editor)
-- ══════════════════════════════════════════════════════════════
do
  local A, B = { row = 1, col = 2 }, { row = 3, col = 3 }
  eq("extract spans lines", "bc|def|gh",
    table.concat(sel.extract({ "abc", "def", "ghi" }, A, B), "|"))
  eq("extract within one line", "b",
    table.concat(sel.extract({ "abc" }, { row = 1, col = 2 }, { row = 1, col = 3 }), "|"))
  test("extract of a point is nil",
    sel.extract({ "abc" }, { row = 1, col = 2 }, { row = 1, col = 2 }) == nil)

  local lines = { "abc", "def", "ghi" }
  local removed, r, c = sel.removeBlock(lines, A, B)
  eq("removeBlock joins the ends", "ai", table.concat(lines, "|"))
  eq("...cursor lands at the start", 1, r)
  eq("...in the right column", 2, c)
  eq("...and returns what it took", "bc|def|gh", table.concat(removed, "|"))

  local L = { "abc" }
  local r2, c2 = sel.insertBlock(L, 1, 2, { "XX", "YY" })
  eq("insertBlock splits the line", "aXX|YYbc", table.concat(L, "|"))
  eq("...ending on the last inserted row", 2, r2)
  eq("...after the inserted text", 3, c2)

  local L2 = { "abc" }
  sel.insertBlock(L2, 1, 2, { "Z" })
  eq("a one-line paste stays on the line", "aZbc", table.concat(L2, "|"))

  -- The renderer's per-cell question.
  test("contains: inside", sel.contains(A, B, 2, 1))
  test("contains: before the start on the first row", not sel.contains(A, B, 1, 1))
  test("contains: at the start", sel.contains(A, B, 1, 2))
  test("contains: past the end on the last row", not sel.contains(A, B, 3, 3))
  test("contains: outside entirely", not sel.contains(A, B, 4, 1))

  -- Removing everything must not leave a buffer with no lines to type on.
  local L3 = { "abc" }
  sel.removeBlock(L3, { row = 1, col = 1 }, { row = 1, col = 4 })
  eq("the buffer keeps one line", 1, #L3)
  eq("...and it is empty", "", L3[1])
end

-- ══════════════════════════════════════════════════════════════
-- Whole-line selection (a read-only view buffer)
-- ══════════════════════════════════════════════════════════════
do
  -- View rows are { text, colour } pairs; only the text comes back.
  local content = { { "one", 1 }, { "two", 1 }, { "three", 1 }, { "four", 1 } }
  eq("lines takes an inclusive run", "two|three",
    table.concat(sel.lines(content, 2, 3), "|"))
  eq("lines is direction-agnostic", "two|three",
    table.concat(sel.lines(content, 3, 2), "|"))
  eq("a single line IS a selection here", "one",
    table.concat(sel.lines(content, 1, 1), "|"))
  eq("plain-string rows work too", "a|b",
    table.concat(sel.lines({ "a", "b" }, 1, 2), "|"))
  test("out of range yields nothing", sel.lines(content, 90, 99) == nil)
end

-- ══════════════════════════════════════════════════════════════
-- The clipboard store
-- ══════════════════════════════════════════════════════════════
do
  clip.clearAll()
  test("starts empty", clip.isEmpty(1))
  eq("...and says so", "empty", clip.describe(1))
  eq("nothing to hand out", nil, clip.get(1))

  clip.set("hello", 1)
  eq("holds one line", 1, clip.count(1))
  eq("text round-trips", "hello", clip.text(1))
  eq("line round-trips", "hello", clip.line(1))

  clip.set("one\ntwo\nthree", 1)
  eq("splits on newlines", 3, clip.count(1))
  eq("text rejoins with newlines", "one\ntwo\nthree", clip.text(1))
  -- The prompt is one line. Concatenating would turn "ls" and "cd" into
  -- "lscd" — a command nobody typed and one they might well run.
  eq("line() joins with SPACES for a single-line target",
    "one two three", clip.line(1))

  clip.set({ "a", "b" }, 1)
  eq("an array of lines works too", 2, clip.count(1))

  -- Per seat. Two people at two screens do not share a clipboard.
  clip.set("seat one", 1)
  clip.set("seat two", 2)
  eq("seat 1 keeps its own", "seat one", clip.text(1))
  eq("seat 2 keeps its own", "seat two", clip.text(2))
  clip.clear(1)
  test("clearing one seat empties it", clip.isEmpty(1))
  test("...and leaves the other alone", not clip.isEmpty(2))

  -- A copy, not the stored table: a caller that mutates what it pasted
  -- must not mutate what is still on the clipboard.
  clip.set({ "x", "y" }, 3)
  local got = clip.get(3)
  got[1] = "MUTATED"
  eq("get hands out a copy", "x", clip.get(3)[1])

  -- Bounded, and it says when the cap bit.
  clip.clearAll()
  local big = {}
  for i = 1, clip.MAX_LINES + 50 do big[i] = "line " .. i end
  local ok, truncated = clip.set(big, 1)
  test("a huge copy succeeds", ok)
  test("...but reports the truncation", truncated)
  test("...and holds no more than the cap", clip.count(1) <= clip.MAX_LINES)
  test("...and admits it out loud",
    clip.describe(1):find("truncated", 1, true) ~= nil)

  clip.clearAll()
  local wide = string.rep("x", clip.MAX_BYTES + 100)
  local ok2, trunc2 = clip.set(wide, 1)
  test("an oversized single line is accepted", ok2)
  test("...truncated", trunc2)
  test("...and bounded", #clip.text(1) <= clip.MAX_BYTES)

  -- Carriage returns and newlines never survive INSIDE a line: a stored
  -- line with a \n in it would break every consumer's line arithmetic.
  clip.clearAll()
  clip.set({ "a\nb" }, 1)
  test("embedded newlines are stripped from a line",
    clip.text(1):find("\n", 1, true) == nil)

  clip.clearAll()
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
