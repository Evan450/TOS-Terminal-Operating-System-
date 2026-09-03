-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.ustr (unicode width helpers)      ║
-- ║                                                            ║
-- ║  Two passes: (1) the byte FALLBACK (no `unicode` module —  ║
-- ║  the off-box / exotic-host path) must behave exactly like  ║
-- ║  plain byte ops for ASCII; (2) with an OC-like `unicode`   ║
-- ║  stub, multi-byte and double-width text must count in      ║
-- ║  display COLUMNS and never split a character.              ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_ustr.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path

print("=== kernel.ustr Tests ===")
print()

-- ── Pass 1: byte fallback (no unicode module present) ──────────────
local ustr = require("kernel.ustr")
eq("fallback: len is bytes for ASCII", 5, ustr.len("hello"))
eq("fallback: width == len", 5, ustr.width("hello"))
eq("fallback: fit truncates", "hel", ustr.fit("hello", 3))
eq("fallback: fit leaves short text", "hi", ustr.fit("hi", 10))
eq("fallback: padR", "hi  ", ustr.padR("hi", 4))
eq("fallback: padL", "  hi", ustr.padL("hi", 4))
eq("fallback: centerOffset", 2, ustr.centerOffset("ab", 6))
eq("fallback: empty/nil safe", 0, ustr.width(nil))

-- ── Pass 2: with an OC-like unicode stub (built on Lua 5.3 utf8) ───
-- OC's API: len (chars), sub (char-indexed), wlen (display columns,
-- wide chars = 2), wtrunc (truncate to LESS than count columns).
local WIDE = {}  -- codepoints we declare double-width for the test
local function charW(cp) return WIDE[cp] and 2 or 1 end
package.loaded["unicode"] = {
  len = function(s) return utf8.len(s) end,
  sub = function(s, i, j)
    local n = utf8.len(s)
    if i < 0 then i = n + i + 1 end
    if j == nil then j = -1 end
    if j < 0 then j = n + j + 1 end
    if i < 1 then i = 1 end
    if j > n then j = n end
    if i > j then return "" end
    local si = utf8.offset(s, i)
    local sj = utf8.offset(s, j + 1)
    return s:sub(si, (sj and sj - 1) or #s)
  end,
  wlen = function(s)
    local w = 0
    for _, cp in utf8.codes(s) do w = w + charW(cp) end
    return w
  end,
  wtrunc = function(s, count)
    local out, w = "", 0
    for _, cp in utf8.codes(s) do
      local cw = charW(cp)
      if w + cw >= count then break end
      out = out .. utf8.char(cp)
      w = w + cw
    end
    return out
  end,
}
package.loaded["kernel.ustr"] = nil          -- re-require against the stub
local u2 = require("kernel.ustr")

local ru = "Пароль:"                          -- 7 chars, 13 bytes, 7 columns
eq("unicode: len counts chars", 7, u2.len(ru))
eq("unicode: width counts columns", 7, u2.width(ru))
test("unicode: width < byte length for Cyrillic", u2.width(ru) < #ru)
eq("unicode: fit whole string untouched", ru, u2.fit(ru, 10))
local cut = u2.fit(ru, 3)
eq("unicode: fit to 3 columns = 3 chars", 3, u2.len(cut))
eq("unicode: fit never splits a character", "Пар", cut)
eq("unicode: padR pads to column width", 10, u2.width(u2.padR(ru, 10)))
eq("unicode: centerOffset uses columns", 1, u2.centerOffset(ru, 9))

-- Double-width (CJK-like) cells: declare 触 wide and check column math.
WIDE[utf8.codepoint("触")] = true
local mixed = "a触b"                          -- columns: 1 + 2 + 1 = 4
eq("wide: width counts double cells", 4, u2.width(mixed))
eq("wide: fit(3) keeps a + wide char only", "a触", u2.fit(mixed, 3))
eq("wide: fit(2) cannot split the wide char", "a", u2.fit(mixed, 2))

package.loaded["unicode"] = nil
package.loaded["kernel.ustr"] = nil

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
