-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: build/minify_vars.lua (vendored LuaMinify)   ║
-- ║                                                                ║
-- ║  build/vendor/luaminify/ is stravant/LuaMinify, patched to add  ║
-- ║  Lua 5.3 bitwise/shift operators and floor division (upstream   ║
-- ║  hard-errors on all five) and to generate shortest-available    ║
-- ║  local names instead of random ones, plus a TOS addition        ║
-- ║  (DedupStrings.lua) that hoists a string literal repeated often  ║
-- ║  enough in one file into a single shared local. See that        ║
-- ║  directory's README.md for exactly what changed and why each    ║
-- ║  piece is safe. This file is the executable half of that        ║
-- ║  argument: every case here is checked by RUNNING both the       ║
-- ║  original and the minified code and comparing actual return      ║
-- ║  values, not by reading the output and trusting it looks right.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_minify_vars.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function findUp(rel)
  for _, prefix in ipairs({ "", "../", "../../", "../../../" }) do
    local s = readAll(prefix .. rel)
    if s then return s, prefix end
  end
end

print("=== build/minify_vars.lua (vendored LuaMinify) Tests ===")
print()

local mvSrc, prefix = findUp("build/minify_vars.lua")
test("build/minify_vars.lua readable", mvSrc ~= nil)
if not mvSrc then
  print(); print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

package.path = prefix .. "build/?.lua;" .. package.path
local mv = require("minify_vars")
test("minify_vars module loads", type(mv) == "table" and type(mv.minify) == "function")

-- ── Lua 5.3 operators the vendored parser could not read upstream ──
-- Each case is run BOTH ways and the VALUES compared, so a precedence
-- or associativity mistake in the patch shows up as a wrong answer, not
-- just as "it still parses".
print()
print("-- Lua 5.3 bitwise/shift/floor-div operators --")
local OPERATOR_CASES = {
  -- The exact idiom from kernel/sha256.lua's rrot, byte for byte.
  "return ((0xABCD1234 >> 7) | (0xABCD1234 << (32 - 7))) & 0xFFFFFFFF",
  "return (0xF0F0 & 0x0FF0) ~ ((~0xF0F0) & 0x0FF0)",
  "local a,b,c = 7,3,5 return (a & b) ~ (a & c) ~ (b & c)",
  "return 17 // 5, 17 % 5, -17 // 5",
  "local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF end return rrot(0x12345678, 7)",
  "local x = 5 return ~x",                -- unary bitwise not
  "return 1 << 2 << 3",                   -- left-associative shift chain
  "return 2 | 4 & 8",                     -- precedence: & binds tighter than |
  "return (2 | 4) & 8",                   -- same values, explicit parens force the OTHER grouping
  "return 1 < 2 | 4",                     -- | binds tighter than comparison
  "local t = {} t[1] = 3 & 1 return t[1]",
}
for _, src in ipairs(OPERATOR_CASES) do
  local out, err = mv.minify(src, "case")
  test("minifies: " .. src, out ~= nil)
  if out then
    local chunkOrig = assert(load(src, "=orig", "t"))
    local chunkMin, loadErr = load(out, "=min", "t")
    test("...and the minified form still compiles (" .. tostring(loadErr) .. ")",
      chunkMin ~= nil)
    if chunkMin then
      local rOrig = table.pack(chunkOrig())
      local rMin = table.pack(chunkMin())
      local same = rOrig.n == rMin.n
      if same then
        for i = 1, rOrig.n do if rOrig[i] ~= rMin[i] then same = false end end
      end
      test("...and evaluates to the same value(s)", same)
    end
  else
    test("...and evaluates to the same value(s) (skipped: " .. tostring(err) .. ")", false)
  end
end

-- ── Globals are never touched; only self.Locals is ──────────────────
print()
print("-- globals and fields survive untouched --")
do
  local src = "x = 1 local y = 2 return x, y, _G.x"
  local out = mv.minify(src, "globals")
  test("minifies", out ~= nil)
  if out then
    test("the global 'x' keeps its name", out:find("^x=1", 1, false) ~= nil
      or out:find("%f[%w]x%f[%W]") ~= nil)
    local chunk = assert(load(out, "=g", "t"))
    local a, b, c = chunk()
    eq("global x round-trips", 1, a)
    eq("local y still round-trips (renamed, same value)", 2, b)
    eq("_G.x reads the same global the local-renamed code wrote", 1, c)
  end
end

do
  -- Table field names (MemberExpr) are never local variables and must
  -- never be renamed -- they're accessed by string key, including by
  -- any caller outside this file entirely.
  local src = "local M = {} function M.doThing(a) return a + 1 end return M"
  local out = mv.minify(src, "fields")
  test("minifies", out ~= nil)
  if out then
    test("the field name 'doThing' survives", out:find("doThing", 1, true) ~= nil)
    local chunk = assert(load(out, "=f", "t"))
    local M = chunk()
    eq("the renamed-local module still works by its real field name", 43, M.doThing(42))
  end
end

-- ── String-literal deduplication (DedupStrings.lua) ──────────────────
print()
print("-- repeated string literals are hoisted to one shared local --")
do
  -- Long enough (>=8 quoted) and repeated enough (>=3x) to qualify.
  local src = [[
local function warn(msg) print("a message long enough to dedupe", msg) end
warn(1)
warn(2)
local t = { label = "a message long enough to dedupe" }
print("a message long enough to dedupe")
return t.label == "a message long enough to dedupe"
]]
  local out, err = mv.minify(src, "dedup")
  test("minifies (" .. tostring(err) .. ")", out ~= nil)
  if out then
    -- The literal text must appear exactly once in the output (the one
    -- declaration), not four times -- that's the whole point.
    local _, literalCount = out:gsub("a message long enough to dedupe", "")
    eq("the literal appears exactly once in the output", 1, literalCount)
    local chunk = assert(load(out, "=dedup", "t"))
    eq("still evaluates the same", true, chunk())
  end
end
do
  -- Below the count threshold (2 uses): must NOT be hoisted. A single
  -- extra local plus its declaration can cost more than it saves for a
  -- string used only once or twice, so the pass has a floor.
  local src = 'return "used only twice, long enough to qualify by length", '
    .. '"used only twice, long enough to qualify by length"'
  local out = mv.minify(src, "below-count")
  test("minifies", out ~= nil)
  if out then
    local _, n = out:gsub("used only twice, long enough to qualify by length", "")
    test("left inline (not hoisted to a local) below the count floor", n == 2)
  end
end
do
  -- Below the length threshold: even repeated often, a short string
  -- isn't worth a local (the declaration overhead eats the saving).
  local src = 'return "short", "short", "short", "short"'
  local out = mv.minify(src, "below-length")
  test("minifies", out ~= nil)
  if out then
    test("left inline below the length floor", out:find('"short"', 1, true) ~= nil
      and not out:find("local%s+%w+%s*=%s*\"short\""))
  end
end
do
  -- The two cases that must NEVER be touched, even when they'd otherwise
  -- qualify: a string-call-sugar argument (f"str", stored as a raw
  -- token, not a full expression node) and a table constructor's
  -- KeyString key (a bare Lua string, not an expression at all).
  local src = [[
local function f(s) return "x:" .. s end
local a = f"abcdefgh12"
local b = f"abcdefgh12"
local c = f"abcdefgh12"
local t = { abcdefgh12 = 1 }
return a, b, c, t.abcdefgh12
]]
  local out, err = mv.minify(src, "exclusions")
  test("minifies (" .. tostring(err) .. ")", out ~= nil)
  if out then
    local _, sugarCount = out:gsub('"abcdefgh12"', "")
    eq("string-call sugar argument is never hoisted (appears 3x still)", 3, sugarCount)
    test("the table key survives as a bare identifier, not a string",
      out:find("abcdefgh12%s*=%s*1") ~= nil)
    local chunkOrig = assert(load(src, "=o", "t"))
    local chunkMin = assert(load(out, "=m", "t"))
    local a1, b1, c1, d1 = chunkOrig()
    local a2, b2, c2, d2 = chunkMin()
    test("evaluates the same", a1 == a2 and b1 == b2 and c1 == c2 and d1 == d2)
  end
end

-- ── A file that does not compile is reported, not silently passed ──
print()
print("-- a broken input is refused, not silently minified --")
do
  local out, err = mv.minify("local function f(a, b\n  return a + b\nend\nreturn f", "broken")
  test("a syntax error returns nil", out == nil)
  test("...with a message", type(err) == "string" and #err > 0)
end

-- ── The real, highest-stakes modules: minify, then re-run their own
-- known-answer test vectors against the minified copy ───────────────
print()
print("-- the real sha256.lua and ed25519.lua, minified, against the originals --")
do
  -- Differential against the real module (which test_sha256.lua already
  -- pins to FIPS 180-2 vectors), not a vector re-typed from memory here.
  local src, p2 = findUp("tos/kernel/sha256.lua")
  if not src then
    test("tos/kernel/sha256.lua readable", false)
  else
    local out, err = mv.minify(src, "sha256.lua")
    test("kernel/sha256.lua minifies (" .. tostring(err) .. ")", out ~= nil)
    if out then
      local chunkMin, loadErr = load(out, "=sha256min", "t")
      test("...and the result compiles (" .. tostring(loadErr) .. ")", chunkMin ~= nil)
      local chunkOrig = loadfile(p2 .. "tos/kernel/sha256.lua")
      test("...and the original loads too (for the comparison)", chunkOrig ~= nil)
      if chunkMin and chunkOrig then
        local shaMin, shaOrig = chunkMin(), chunkOrig()
        for _, msg in ipairs({ "abc", "", string.rep("a", 1000000), "The quick brown fox" }) do
          eq("hex(\"" .. msg:sub(1, 20) .. (#msg > 20 and "..." or "") .. "\") matches the original",
            shaOrig.hex(msg), shaMin.hex(msg))
        end
      end
    end
  end
end
do
  -- Differential, not against a hand-transcribed RFC vector: this file's
  -- own job is "minified behaves like the original", and test_ed25519.lua
  -- already pins the original against RFC 8032 -- duplicating a vector
  -- from memory here risks exactly the kind of transcription slip that
  -- would make this test cry wolf about a perfectly correct minifier.
  -- ed25519.lua requires kernel.sha512 and kernel.curve25519field at
  -- load time; neither this test nor the minified chunk ships one, so
  -- both need them preloaded the same way to load at all.
  for _, dep in ipairs({ "tos/kernel/sha512.lua", "tos/kernel/curve25519field.lua" }) do
    local depSrc = findUp(dep)
    if depSrc then
      local chunk = load(depSrc, "=" .. dep, "t")
      if chunk then
        local ok, mod = pcall(chunk)
        if ok then package.loaded["kernel." .. dep:match("([^/]+)%.lua$")] = mod end
      end
    end
  end

  local src, p2 = findUp("tos/kernel/ed25519.lua")
  if not src then
    test("tos/kernel/ed25519.lua readable", false)
  else
    local out, err = mv.minify(src, "ed25519.lua")
    test("kernel/ed25519.lua minifies (" .. tostring(err) .. ")", out ~= nil)
    if out then
      local chunkMin, loadErr = load(out, "=ed25519min", "t")
      test("...and the result compiles (" .. tostring(loadErr) .. ")", chunkMin ~= nil)
      local chunkOrig = loadfile(p2 .. "tos/kernel/ed25519.lua")
      test("...and the original loads too (for the comparison)", chunkOrig ~= nil)
      if chunkMin and chunkOrig then
        local edMin, edOrig = chunkMin(), chunkOrig()
        local function hex(b) return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
        for _, seedByte in ipairs({ "\0", "\1", "A" }) do
          local seed = string.rep(seedByte, 32)
          local pubOrig = edOrig.publickey(seed)
          local pubMin  = edMin.publickey(seed)
          eq("public key matches the original for seed " .. string.format("%q", seedByte),
            hex(pubOrig), hex(pubMin))
          local sigOrig = edOrig.sign("test message", seed, pubOrig)
          local sigMin  = edMin.sign("test message", seed, pubMin)
          eq("signature matches the original for seed " .. string.format("%q", seedByte),
            hex(sigOrig), hex(sigMin))
          test("...and the minified signature verifies with the minified verify()",
            (edMin.verify("test message", sigMin, pubMin)))
        end
      end
    end
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
