-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: PaneUI's highlighter never splits a character║
-- ║                                                              ║
-- ║  synTokenize is an inline port of /tos/shell/syntax.lua and   ║
-- ║  carried the same bug: in code position every byte >= 0x80    ║
-- ║  became its own `op` token, so the lead byte painted as a     ║
-- ║  garbage glyph and the continuation bytes vanished.           ║
-- ║                                                              ║
-- ║  PaneUI self-executes on load, so -- as the other PaneUI      ║
-- ║  tests do -- this reads the SOURCE and lifts synTokenize out. ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua pane-ui/test_paneui_syntax_utf8.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local src
for _, p in ipairs({ "pane-ui/PaneUI.lua", "PaneUI.lua", "../pane-ui/PaneUI.lua" }) do
  local h = io.open(p, "rb")
  if h then src = h:read("*a"); h:close(); break end
end
-- A Windows checkout (core.autocrlf) has CRLF, and "\nend\n" never matches.
if src then src = src:gsub("\r\n", "\n") end
local kw   = src and src:match("\n(local SYN_KEYWORDS = %b{})\n")
local body = src and src:match("\n(local function synTokenize%(line%).-\nend)\n")
if not (kw and body) then
  print("FAIL: could not find synTokenize in PaneUI.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local synTokenize = assert(load(kw .. "\n" .. body .. "\nreturn synTokenize",
  "=synTokenize", "t", { math = math }))()

-- `invalid`: bytes that are no UTF-8 at all; they must be one token, not
-- one per byte, but cannot be "whole".
local function check(label, line, invalid)
  local toks = synTokenize(line)
  local joined, whole = {}, true
  for _, t in ipairs(toks) do
    joined[#joined + 1] = t.text
    if utf8.len(t.text) == nil and t.text ~= invalid then whole = false end
  end
  test(label .. ": every token is whole UTF-8", whole)
  test(label .. ": the tokens still spell the line", table.concat(joined) == line)
  return toks
end

print("=== PaneUI synTokenize and UTF-8 ===")
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
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
