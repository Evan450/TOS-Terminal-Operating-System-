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
do
  -- Hoisted in SORTED order, so the output does not depend on the order
  -- pairs() happened to walk the tree in. It did: Lua 5.4 seeds its
  -- string hash per process, and the same release built twice differed
  -- in 6 of 144 files, every difference two hoisted strings that had
  -- swapped names. Six strings used equally often, so the name each one
  -- gets falls entirely to the order they were declared in.
  local names = { "zulu-string", "alpha-string", "mike-string",
                  "echo-string", "kilo-string", "bravo-string" }
  local lines = {}
  for _ = 1, 3 do
    for _, n in ipairs(names) do lines[#lines + 1] = ("print(%q)"):format(n) end
  end
  local src = table.concat(lines, "\n")
  local out = mv.minify(src, "order")
  test("minifies", out ~= nil)
  if out then
    local decl = out:match("^%s*local [%w_,]+=(.-)print")
    local seen = {}
    for s in (decl or ""):gmatch('"([^"]+)"') do seen[#seen + 1] = s end
    local sorted = { table.unpack(names) }
    table.sort(sorted)
    eq("all six are hoisted into one declaration", 6, #seen)
    eq("...in sorted order", table.concat(sorted, ","), table.concat(seen, ","))

    -- And across processes, which is where the seed actually changes. The
    -- interpreter running this test is the one asked; a missing one skips.
    local interp = arg and arg[-1]
    local mvPath = prefix .. "build/minify_vars.lua"
    local tmp = os.tmpname()
    local h = io.open(tmp, "wb")
    if interp and h then
      h:write(src); h:close()
      local cmd = ('"%s" "%s" "%s"'):format(interp, mvPath, tmp)
      if package.config:sub(1, 1) == "\\" then cmd = '"' .. cmd .. '"' end
      local runs = {}
      for i = 1, 3 do
        local p = io.popen(cmd)
        runs[i] = p and p:read("*a") or ""
        if p then p:close() end
      end
      test("three separate processes produce the same bytes",
        runs[1] ~= "" and runs[1] == runs[2] and runs[2] == runs[3])
      eq("...and the same bytes as this one", out, runs[1])
    else
      print("  SKIP: no interpreter path to run a second process with")
    end
    os.remove(tmp)
  end
end

-- ── Tokens that lex as something else once they touch ──────────────
-- FormatMini drops every space it can, and some pairs of tokens are a
-- different token without one: `-` `-` is a comment, `.` `.` runs into
-- `...`, and `[` before a long string opens a long bracket. The comment
-- cases compiled and returned the wrong answer (`a - -b` gave a), and
-- `t[ [=[k]=] ]` compiled as a call. Every case runs both ways and the
-- values are compared.
print()
print("-- token joins that would change meaning --")
local JOIN_CASES = {
  "local a, b = 5, 2 return a - -b",
  "local a = 5 return - -a",
  "local a = 2 return a - - - a",
  "local a = 2 return a - -1e1, 1 - -1",
  "local s = 'abc' return #s - -#s",
  "local t = { 4 } return - -t[1]",
  "local t = { k = 1 } return t[ [[k]] ]",
  "local t = { k = 1 } return t[ [=[k]=] ]",
  "local t = { [ [[k]] ] = 7 } return t.k",
  "local s = 'x' return s .. .5",
  "local function f(...) local s = 'x' return s .. ... end return f('y')",
  "local a = 3 return a .. 1 .. 2",
  -- A statement that opens with `(` reads as a call of whatever ends the
  -- one before it, unless a `;` is kept between them.
  "local n = 0 local function f() n = n + 1 end local y = 'q' local x = 'a' .. y;(f)() return n",
  "local n = 0 local function f() n = n + 1 end local g = function() return 5 end;(f)() return n, g()",
  "local n = 0 local function f() n = n + 1 end local x = 1;(f)() return n, x",
  "local n = 0 local function f() n = n + 1 end local t = {} t.k = f;(t.k)() return n",
  "local s = ('x'):rep(3) local t = {};('y'):rep(2) return s",
}
do
  -- And the same where the formatter breaks its line, which it does every
  -- 150 or so characters: a line break is no separator either.
  local n = 0
  for len = 100, 400 do
    local src = 'local hits = 0 local function f() hits = hits + 1 end '
      .. 'local function g() return true end g("' .. string.rep("a", len) .. '");(f)() return hits'
    local out = mv.minify(src, "break")
    local chunk = out and load(out, "=break", "t")
    local ok, hits = false, nil
    if chunk then ok, hits = pcall(chunk) end
    if not (ok and hits == 1) then n = n + 1 end
  end
  eq("a `;(` survives wherever the line break falls (301 lengths, failures)", 0, n)
end
for _, src in ipairs(JOIN_CASES) do
  local out, err = mv.minify(src, "join")
  local function results(code)
    local chunk, lerr = load(code, "=join", "t")
    if not chunk then return "load error: " .. tostring(lerr) end
    local ok, r = pcall(function() return table.pack(chunk()) end)
    if not ok then return "run error: " .. tostring(r) end
    local parts = {}
    for i = 1, r.n do parts[i] = tostring(r[i]) end
    return r.n .. ":" .. table.concat(parts, ",")
  end
  if out then
    eq(src, results(src), results(out))
  else
    test(src .. " (minify failed: " .. tostring(err) .. ")", false)
  end
end

-- ── The focus switches that shipped as calls on a boolean ──────────
-- Every release from 2026-10-17 to 2026-10-24 minified
--   proc.setForeground(pid, seat, { kernel = true })
--   ;(proc.signalKernel or proc.signal)(pid, "tos_focus")
-- into `setForeground(...)\n(proc.signalKernel or ...)(...)`: one call
-- chain, which calls setForeground's `true` and stops with "attempt to
-- call a boolean value" before the process is told to repaint. Four in
-- kernel/init.lua, one each in the shell's apps.lua and executor.lua.
print()
print("-- the real focus switches keep their `;(` --")
do
  local strip = dofile(prefix .. "build/strip.lua")
  for _, f in ipairs({ { "tos/kernel/init.lua", 4 }, { "tos/shell/panels/apps.lua", 1 },
                       { "tos/shell/panels/executor.lua", 1 } }) do
    local src = readAll(prefix .. f[1])
    if src then
      local out, err = mv.minify(strip.strip(src:gsub("\r\n", "\n"), { minify = true }), f[1])
      test(f[1] .. " minifies (" .. tostring(err) .. ")", out ~= nil)
      if out then
        local _, joined = out:gsub("%)\n%(%w+%.signalKernel", "")
        local _, kept = out:gsub("%);%(%w+%.signalKernel", "")
        eq(f[1] .. ": no signal call chained onto setForeground", 0, joined)
        eq("...and every one kept as its own statement", f[2], kept)
      end
    else
      test(f[1] .. " readable", false)
    end
  end
end

-- ── The round trip refuses a formatter that changes the program ─────
-- minify() parses its own output back and compares how many of each
-- kind of node it has. Proved here on a formatter broken on purpose: a
-- copy of the vendor tree with the `;(` patch switched off, driven
-- through a copy of minify_vars.lua beside it. Needs LuaFileSystem for
-- the scratch directory.
print()
print("-- a formatter that changes the program is refused --")
do
  local okLfs, lfs = pcall(require, "lfs")
  local fmt = readAll(prefix .. "build/vendor/luaminify/FormatMini.lua")
  local guard = "if sep == ';' and b:sub(1, 1) == '(' then"
  if not okLfs then
    print("  SKIP: LuaFileSystem is not installed")
  elseif not (fmt and fmt:find(guard, 1, true)) then
    test("FormatMini.lua carries the `;(` patch this test switches off", false)
  else
    local tmp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")
    local base = tmp .. "/tos_mv_roundtrip_" .. tostring(os.time()) .. "_" .. tostring(math.random(1e6))
    lfs.mkdir(base); lfs.mkdir(base .. "/vendor"); lfs.mkdir(base .. "/vendor/luaminify")
    local function put(p, s) local h = assert(io.open(p, "wb")); h:write(s); h:close() end
    for _, n in ipairs({ "ParseLua", "Scope", "Util", "DedupStrings" }) do
      put(base .. "/vendor/luaminify/" .. n .. ".lua", readAll(prefix .. "build/vendor/luaminify/" .. n .. ".lua"))
    end
    put(base .. "/vendor/luaminify/FormatMini.lua", (fmt:gsub(guard:gsub("%p", "%%%0"), "if false then", 1)))
    put(base .. "/minify_vars.lua", mvSrc)
    local broken = assert(loadfile(base .. "/minify_vars.lua"))()
    local out, err = broken.minify(
      "local function f() end local t = { g = function() return true end }\n"
      .. "t.g()\n;(f)()\n", "broken-formatter")
    test("the broken formatter's output is refused, not returned", out == nil)
    test("...as a different program, naming what changed",
      type(err) == "string" and err:find("different program", 1, true) ~= nil
      and err:find("CallStatement", 1, true) ~= nil)
    for _, n in ipairs({ "ParseLua", "Scope", "Util", "DedupStrings", "FormatMini" }) do
      os.remove(base .. "/vendor/luaminify/" .. n .. ".lua")
    end
    os.remove(base .. "/minify_vars.lua")
    lfs.rmdir(base .. "/vendor/luaminify"); lfs.rmdir(base .. "/vendor"); lfs.rmdir(base)
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
