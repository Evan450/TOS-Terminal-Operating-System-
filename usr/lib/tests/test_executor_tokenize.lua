-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: the command-line tokenizer (#SEC M4)     ║
-- ║                                                            ║
-- ║  tokenize() used to build each token with `cur = cur .. c`,║
-- ║  one Lua string concatenation per BYTE — immutable-string  ║
-- ║  reallocation on every character, O(n^2) in a token's own  ║
-- ║  length. Rewritten to accumulate whole spans (the run up   ║
-- ║  to the next delimiter/quote-close/escape) and join once   ║
-- ║  per token with table.concat. This file pins the exact     ║
-- ║  same external behaviour as the byte-by-byte original,     ║
-- ║  including the edge cases that behaviour rewrite is most   ║
-- ║  likely to get wrong: empty quoted strings, escaped quotes ║
-- ║  and backslashes, unterminated quotes, and a lone trailing ║
-- ║  backslash at end-of-string (which falls through to the    ║
-- ║  "ordinary run" branch precisely because the in-quote      ║
-- ║  escape case requires a character AFTER it).                ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_executor_tokenize.lua

-- Forward-declared: eqParts below closes over this, and it's only
-- assigned after the module loads. Declaring it after eqParts would make
-- that reference resolve to a global instead of this local.
local tokenize

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function sameParts(expected, actual)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for i, v in ipairs(expected) do if actual[i] ~= v then return false end end
  return true
end
local function describe(parts)
  if type(parts) ~= "table" then return tostring(parts) end
  local out = {}
  for i, p in ipairs(parts) do out[i] = string.format("%q", p) end
  return "{ " .. table.concat(out, ", ") .. " }"
end
local function eqParts(name, expected, cmdStr)
  local actual = tokenize(cmdStr)
  test(name .. "  (input " .. string.format("%q", cmdStr)
    .. ", got " .. describe(actual) .. ")", sameParts(expected, actual))
end

-- Stub executor.lua's module-scope dependency so requiring it doesn't
-- need the real shell panel tree. tokenize() itself touches none of
-- these — it's a pure function of its string argument — but the module
-- can't load without this.
_G._TOS = _G._TOS or {}
package.loaded["shell.panels.helpers"] = {}

package.path = "tos/?.lua;" .. package.path
local executorMod = require("shell.panels.executor")
tokenize = executorMod._tokenize

print("=== command tokenizer (#SEC M4) Tests ===")
print()

test("tokenize is exposed for testing", type(tokenize) == "function")

-- ── Plain, unquoted ──────────────────────────────────────────
eqParts("empty string -> no tokens", {}, "")
eqParts("whitespace only -> no tokens", {}, "   \t  ")
eqParts("single word", { "ls" }, "ls")
eqParts("words split on runs of spaces/tabs", { "cp", "a", "b" }, "cp   a\tb")
eqParts("leading/trailing whitespace trimmed", { "ls" }, "   ls   ")

-- ── Single quotes: literal, no escape processing ────────────
eqParts("single-quoted embeds spaces", { "cp", "a b", "c" }, "cp 'a b' c")
eqParts("single-quoted ignores backslash", { "a\\b" }, "'a\\b'")
eqParts("empty single-quoted string is a real (empty) token",
  { "" }, "''")
eqParts("unterminated single quote takes the rest of the line",
  { "abc" }, "'abc")
eqParts("single quote immediately at end of input", { "" }, "'")

-- ── Double quotes: spaces preserved, \\ escapes ──────────────
eqParts("double-quoted embeds spaces", { "cp", "a b", "c" }, 'cp "a b" c')
eqParts("escaped quote inside double quotes", { 'a"b' }, '"a\\"b"')
eqParts("escaped backslash inside double quotes", { "a\\b" }, '"a\\\\b"')
eqParts("empty double-quoted string is a real (empty) token",
  { "" }, '""')
eqParts("unterminated double quote takes the rest of the line",
  { "abc" }, '"abc')
eqParts("escape run right at the closing quote",
  { 'ab"' }, '"ab\\""')
eqParts("multiple escapes in one quoted token",
  { 'a"b\\c' }, '"a\\"b\\\\c"')

-- ── Backslash escapes outside quotes ─────────────────────────
eqParts("backslash escapes a space outside quotes", { "a b" }, "a\\ b")
eqParts("backslash at absolute end of input is kept literally",
  { "a\\" }, "a\\")
eqParts("lone trailing backslash as the whole token", { "\\" }, "\\")
eqParts("backslash mid-token before more text", { "a\\tb" }, "a\\\\tb")

-- ── Mixed, realistic command lines ───────────────────────────
eqParts("quotes and plain tokens together",
  { "echo", "hello world", "plain" }, 'echo "hello world" plain')
eqParts("adjacent quoted segments concatenate into one token",
  { "it's" }, "'it'\\''s'")
eqParts("path with an escaped space, then a flag",
  { "cp", "my file.txt", "-v" }, "cp my\\ file.txt -v")
eqParts("single then double quote back to back forms one token",
  { "ab" }, "'a'\"b\"")

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
