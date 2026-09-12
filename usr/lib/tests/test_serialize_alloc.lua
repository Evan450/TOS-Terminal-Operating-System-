-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: decoding costs about what it reads            ║
-- ║                                                                ║
-- ║  serialize.decode built every string one byte per table slot,   ║
-- ║  so it allocated 16-26x its input: ~138 KB for one 8 KB packet, ║
-- ║  on machines with 192-256 KB of RAM, for every packet from every ║
-- ║  peer before its trust was checked (Sep 2026 pentest, RAM pass).║
-- ║  Strings now copy whole runs between escapes.                   ║
-- ║                                                                ║
-- ║  Pins the allocation, then proves nothing broke: random byte    ║
-- ║  strings round-trip through the REAL encoder, and a fixed-seed  ║
-- ║  mutation fuzz must never raise or run long.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_serialize_alloc.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
local s = require("kernel.serialize")

local function allocKB(str, opts)
  collectgarbage(); collectgarbage(); collectgarbage("stop")
  local b = collectgarbage("count")
  local t = s.decode(str, opts)
  local a = collectgarbage("count")
  collectgarbage("restart")
  return a - b, t
end

print("=== serialize.decode: allocation and correctness ===")
print()

do
  local pkt = '{type="chat",payload={msg="' .. string.rep("x", 8000) .. '"}}'
  local kb, t = allocKB(pkt, { maxBytes = 8192 })
  test("an 8 KB one-string packet decodes", t and t.payload and #t.payload.msg == 8000)
  test(string.format("...allocating under 4x its size (%.1f KB for %d bytes)", kb, #pkt), kb * 1024 < 4 * #pkt)
  local many = "{" .. string.rep('"abcdefghij",', 400) .. "}"
  local kb2, t2 = allocKB(many, { maxBytes = 8192 })
  test("a 400-string packet decodes", t2 and #t2 == 400 and t2[400] == "abcdefghij")
  test(string.format("...allocating under 4x its size (%.1f KB for %d bytes)", kb2, #many), kb2 * 1024 < 4 * #many)
end

do
  local cases = {
    { [["a\"b"]], 'a"b' }, { [['a\'b']], "a'b" }, { [["tab\there"]], "tab\there" },
    { [["\65\066\0671"]], "ABC1" }, { [["\x41\x42"]], "AB" }, { [["back\\slash"]], "back\\slash" },
    { [["unknown\qesc"]], "unknownqesc" }, { '""', "" }, { "''", "" },
    { '"line\\\nbreak"', "line\nbreak" },
    -- decode reads ONE value and ignores what follows it; that predates
    -- this change and is pinned so it does not change by accident either.
    { "'it''s'", "it" },
  }
  local bad = 0
  for _, c in ipairs(cases) do
    local got = s.decode(c[1])
    if got ~= c[2] then bad = bad + 1; print("    mismatch for " .. c[1] .. ": " .. tostring(got)) end
  end
  test("every escape form decodes as before", bad == 0)
  test("an unterminated string is an error, not a value", s.decode('"never closed') == nil)
  test("an unterminated escape is an error", s.decode('"ends in \\') == nil)
end

do
  local seed = 12345
  local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
  local bad = 0
  for i = 1, 300 do
    local chars = {}
    for j = 1, rnd(60) do chars[j] = string.char(rnd(256)) end
    local v = { str = table.concat(chars), n = i, nested = { table.concat(chars):reverse() } }
    local back = s.decode(s.encode(v))
    if not (back and back.str == v.str and back.n == i and back.nested[1] == v.nested[1]) then
      bad = bad + 1
    end
  end
  test("300 random byte strings round-trip through encode/decode", bad == 0)
end

do
  local seed = 777
  local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
  local corpus = { '{a=1,b="two",c={3,4,"five"}}', 'return {x="\\65\\x42",[1]=true}',
                   "{['k']='v';n=-2.5e3}", '--c\n{s="a\\"b"}' }
  local alphabet = '{}[]=,;"\'\\-.0123456789eExXabcnrtu \n'
  local raised, slow = 0, 0
  local t0 = os.clock()
  for i = 1, 3000 do
    local base = corpus[(i % #corpus) + 1]
    local p = rnd(#base) + 1
    local ins = alphabet:sub(rnd(#alphabet) + 1, rnd(#alphabet) + 1)
    local m = base:sub(1, p - 1) .. ins .. base:sub(p + rnd(3))
    local st = os.clock()
    local ok = pcall(s.decode, m)
    if not ok then raised = raised + 1 end
    if os.clock() - st > 0.05 then slow = slow + 1 end
  end
  test("3000 mutated inputs: decode never raises (it returns nil, err)", raised == 0)
  test("...and none took over 50 ms", slow == 0)
  print(string.format("    (fuzz ran in %.2f s)", os.clock() - t0))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
