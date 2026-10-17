-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: strip.lua refuses to ship unparseable Lua    ║
-- ║                                                                ║
-- ║  build/strip.lua's tokenizer partitions bytes into "comment"   ║
-- ║  vs "not a comment" — it never checks that what it emits is    ║
-- ║  valid Lua, and neither did anything downstream of it. Two     ║
-- ║  ways that bites: a pathological input the byte-level scanner  ║
-- ║  mishandles, or — far more likely in practice — a SOURCE file  ║
-- ║  that was already broken (a syntax slip, a leftover merge-     ║
-- ║  conflict marker) and strips just as happily as a good one,    ║
-- ║  because stripping never looked at syntax either way. Either   ║
-- ║  way the release shipped a file nothing could load, silently.  ║
-- ║                                                                ║
-- ║  strip.lua now compiles every stripped file with load() before ║
-- ║  writing it and hard-stops the build on a failure — the same   ║
-- ║  compiler frontend that will load the file for real, so this   ║
-- ║  is strictly stronger than a visual diff and costs nothing     ║
-- ║  load() was not already going to do.                           ║
-- ║                                                                ║
-- ║  Runs the REAL strip.lua CLI over temporary trees, same shape  ║
-- ║  as test_build_stamp.lua.                                       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_strip_validates_output.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function writeAll(p, s)
  local h = assert(io.open(p, "wb")); h:write(s); h:close()
end

print("=== strip.lua validates its own output ===")
print()

local okLfs, lfs = pcall(require, "lfs")
if not okLfs then
  print("  SKIP: LuaFileSystem is not installed; the CLI walk needs it")
  print()
  print("Results: 0 passed, 0 failed")
  print("All tests passed.")
  return true
end

local WINDOWS = package.config:sub(1, 1) == "\\"
local tmp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")
local base = tmp .. "/tos_strip_validate_" .. tostring(os.time()) .. "_" .. tostring(math.random(1e6))

local function rmrf(p)
  local mode = lfs.attributes(p, "mode")
  if mode == "directory" then
    for n in lfs.dir(p) do if n ~= "." and n ~= ".." then rmrf(p .. "/" .. n) end end
    lfs.rmdir(p)
  elseif mode then os.remove(p) end
end

-- Resolve build/strip.lua relative to wherever this test happens to run
-- from (TOS-Dev root, normally, but match test_build_stamp.lua's leniency).
local STRIP
for _, prefix in ipairs({ "", "../", "../../" }) do
  if readAll(prefix .. "build/strip.lua") then STRIP = prefix .. "build/strip.lua"; break end
end
test("build/strip.lua found", STRIP ~= nil)
if not STRIP then
  print(); print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

local function runStrip(srcDir, dstDir, extra)
  local cmd = 'lua "' .. STRIP .. '" "' .. srcDir .. '" "' .. dstDir .. '" ' .. (extra or "")
    .. (WINDOWS and " >nul 2>nul" or " >/dev/null 2>&1")
  local ok, _, code = os.execute(cmd)
  if type(ok) == "number" then code = ok; ok = (ok == 0) end
  return ok == true or code == 0
end

lfs.mkdir(base)
local good, bad, outGood, outBad =
  base .. "/good", base .. "/bad", base .. "/out_good", base .. "/out_bad"
lfs.mkdir(good); lfs.mkdir(bad)

-- ── A perfectly ordinary file: stripping must still succeed ────────
writeAll(good .. "/mod.lua", table.concat({
  "-- an ordinary module",
  "local mod = {}",
  "function mod.add(a, b)",
  "  return a + b  -- trailing comment",
  "end",
  "return mod",
}, "\n"))

local okGood = runStrip(good, outGood)
local emittedGood = readAll(outGood .. "/mod.lua")
test("an ordinary file strips and the build succeeds", okGood)
test("...and the emitted file is written", emittedGood ~= nil)
if emittedGood then
  test("...and the emitted file still compiles",
    load(emittedGood, "=mod.lua", "t") ~= nil)
end

-- ── A SOURCE file that was already broken ───────────────────────────
-- Not a contrived tokenizer edge case -- the ordinary, human way a repo
-- ends up with a bad .lua file: an unbalanced paren, exactly the kind of
-- thing a merge conflict or a half-finished edit leaves behind. Stripping
-- a comment out of this file could never have been the problem; shipping
-- it anyway, unnoticed, is.
writeAll(bad .. "/broken.lua", table.concat({
  "-- a module someone broke mid-edit",
  "local function f(a, b",  -- missing close-paren
  "  return a + b",
  "end",
  "return f",
}, "\n"))

local okBad = runStrip(bad, outBad)
test("a file that does not compile STOPS the build", not okBad)
test("...and nothing is written for it", readAll(outBad .. "/broken.lua") == nil)

-- ── Same, under --minify: the whitespace rewrite must not itself be
-- what's being validated here (that's test_strip_minify.lua's job) --
-- just confirm the gate still fires with minify on.
local outBadMin = base .. "/out_bad_min"
local okBadMin = runStrip(bad, outBadMin, "--minify")
test("the gate also fires under --minify", not okBadMin)

rmrf(base)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
