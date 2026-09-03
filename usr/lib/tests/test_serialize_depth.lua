-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Serialize Depth Alignment (M-15)   ║
-- ║  Encoder no longer truncates deep tables to "nil";    ║
-- ║  encode/decode depth limits are aligned; over-limit   ║
-- ║  RAISES instead of silently corrupting the wire form. ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_serialize_depth.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_serialize_depth.lua"
local base = here:gsub("[^/\\]*$", "")
local s
for _, p in ipairs({ base .. "../../../tos/kernel/serialize.lua",
    "tos/kernel/serialize.lua", "TOS-Dev/tos/kernel/serialize.lua" }) do
  local chunk = loadfile(p); if chunk then s = chunk(); break end
end
if not s then
  print("FAIL: could not load serialize.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

local function nest(d)
  local t = { v = 1 }; local cur = t
  for i = 2, d do cur.child = { v = i }; cur = cur.child end
  return t
end
local function leafValue(dec, d)
  local cur = dec
  for _ = 1, d - 1 do if not cur then return nil end cur = cur.child end
  return cur and cur.v
end

print("=== Serialize Depth Alignment Tests ===")
print()

-- A 20-deep table used to truncate at depth 8 (compact); now it round-trips.
local t20 = nest(20)
test("compact 20-deep round-trips to leaf", 20, leafValue(s.decode(s.compact(t20)), 20))
test("encode(pretty) 20-deep round-trips to leaf", 20, leafValue(s.decode(s.encode(t20)), 20))

-- Shallow tables unaffected.
test("shallow round-trip", 2, s.decode(s.compact({ a = 1, b = { c = 2 } })).b.c)

-- Over-limit raises rather than truncating.
local okC = pcall(s.compact, nest(70))
test("compact(70) raises (not truncate)", false, okC)
local okE = pcall(s.encode, nest(70))
test("encode(70) raises (not truncate)", false, okE)

-- Cycles still raise (pre-existing #SEC M1 behaviour preserved).
local cyc = {}; cyc.self = cyc
test("cycle raises", false, (pcall(s.compact, cyc)))

-- #SEC L (L-1) — non-finite numbers must NOT decode (they crash downstream
-- table.sort comparators). decode returns nil on these malformed inputs.
local function decodesNil(lit) return s.decode('{["x"]=' .. lit .. '}') == nil end
test("decode inf -> nil",   true, decodesNil("inf"))
test("decode -inf -> nil",  true, decodesNil("-inf"))
test("decode nan -> nil",   true, decodesNil("nan"))
test("decode 1e999 (overflow) -> nil", true, decodesNil("1e999"))
test("decode finite int ok", 42, s.decode('{["x"]=42}').x)
test("decode finite exp ok", 1000, s.decode('{["x"]=1e3}').x)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
