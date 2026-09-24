-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the highlighter never splits a character     ║
-- ║                                                                ║
-- ║  AUDIT 5. In CODE position every byte >= 0x80 became its own   ║
-- ║  `op` token. kernel.screen draws by character, so the lead byte ║
-- ║  painted as a garbage cell and the continuation bytes (no       ║
-- ║  character on their own) vanished: `local café = 1` lost its é. ║
-- ║                                                                ║
-- ║  Drives the REAL shell.syntax.                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_syntax_utf8.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
local syntax = require("shell.syntax")

-- `invalid`: the line holds bytes that are no UTF-8 at all, so "whole"
-- cannot hold for them; they must still be one token, not one per byte.
local function check(label, line, invalid)
  local toks = syntax.tokenize(line)
  local joined, whole = {}, true
  for _, t in ipairs(toks) do
    joined[#joined + 1] = t.text
    if utf8.len(t.text) == nil and t.text ~= invalid then whole = false end
  end
  test(label .. ": every token is whole UTF-8", whole)
  test(label .. ": the tokens still spell the line", table.concat(joined) == line)
  return toks
end

print("=== syntax.tokenize and UTF-8 ===")
print()
local toks = check("an accented name in code", "local café = 1")
local found = false
for _, t in ipairs(toks) do if t.text == "é" then found = true end end
test("é is one token of its own", found)
check("box drawing in code", "x = ╔══╗")
check("a 4-byte character in code and in a comment", "y = \240\159\152\128 -- \240\159\152\128")
check("inside a string (was fine; still fine)", 's = "naïve ☃"')
check("stray continuation bytes stay one token", "z = \128\129 + 1", "\128\129")
check("plain ASCII is unchanged", "for i = 1, 10 do print(i) end")

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
