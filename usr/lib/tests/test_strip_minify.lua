-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: build/strip.lua --minify on CRLF sources   ║
-- ║                                                              ║
-- ║  This repo is developed on Windows and checks out CRLF. Every ║
-- ║  minify rule was written against "\n", so on CRLF input NONE  ║
-- ║  of them matched: blank lines were never collapsed, and every  ║
-- ║  surviving line kept its "\r" — which then got burned onto    ║
-- ║  the EEPROM. The BIOS image was carrying ~150 bytes of pure   ║
-- ║  carriage returns against a HARD 4 KiB budget, and nobody     ║
-- ║  noticed because the size test only checked the total.        ║
-- ║                                                              ║
-- ║  Pinned here because the failure is invisible: the build      ║
-- ║  still succeeds, the BIOS still boots, it's just needlessly   ║
-- ║  fatter — until one day it doesn't fit.                       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_strip_minify.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local function readAll(path)
  local h = io.open(path, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function findUp(rel)
  for _, prefix in ipairs({ "", "../", "../../", "../../../" }) do
    local s = readAll(prefix .. rel)
    if s then return s end
  end
end

print("=== strip.lua --minify (CRLF) Tests ===")
print()

local src = findUp("build/strip.lua")
test("build/strip.lua readable", src ~= nil)
if not src then
  print(); print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end
local strip = assert(load((src:gsub("^#[^\n]*", "")), "=strip.lua", "t"))()
test("strip module loads", type(strip) == "table" and type(strip.strip) == "function")

-- A sample with CRLF endings, comment blocks, and blank-line runs —
-- i.e. exactly what bios.lua looks like on a Windows checkout.
local CRLF = table.concat({
  "-- a comment block",
  "-- second line",
  "local a=1",
  "",
  "",
  "-- another comment",
  "local b=2",
  "",
  "return a+b",
}, "\r\n") .. "\r\n"

local out = strip.strip(CRLF, { minify = true })

-- ── The core guarantee: no carriage returns survive minify ──
eq("minify emits NO carriage returns", 0, select(2, out:gsub("\r", "")))

-- ── Blank-line collapsing actually happens on CRLF input ──
test("no run of 3+ newlines survives", out:find("\n\n\n") == nil)
test("does not begin with a blank line", out:sub(1, 1) ~= "\n")

-- ── Semantics preserved: it must still be the same program ──
do
  local fn = load(out, "=minified", "t")
  test("minified output still compiles", fn ~= nil)
  if fn then
    local ok, v = pcall(fn)
    test("minified output still runs", ok)
    eq("...and computes the same result", 3, v)
  end
end

-- ── Comments are gone, code is intact ──
test("comments were stripped", out:find("a comment block", 1, true) == nil)
test("code survived", out:find("local a=1", 1, true) ~= nil
  and out:find("local b=2", 1, true) ~= nil)

-- ── LF input behaves identically (no regression for POSIX checkouts) ──
do
  local LF = CRLF:gsub("\r\n", "\n")
  local outLF = strip.strip(LF, { minify = true })
  eq("CRLF and LF sources minify to the SAME bytes", outLF, out)
end

-- ── A string containing \r\n must NOT be mangled ──
-- Line-ending normalisation operates on the emitted source, so a literal
-- inside quotes has to survive: the BIOS builds wire strings, and silently
-- rewriting one would be a nasty, invisible corruption.
do
  local withStr = 'local s="keep\\r\\nme"\r\nreturn s\r\n'
  local o2 = strip.strip(withStr, { minify = true })
  test("an escaped \\r\\n inside a string literal is untouched",
    o2:find('keep\\r\\nme', 1, true) ~= nil)
  local fn = load(o2, "=s", "t")
  test("...and it still compiles", fn ~= nil)
  if fn then
    local ok, v = pcall(fn)
    eq("...and yields the original string", "keep\r\nme", ok and v)
  end
end

-- ── The real BIOS benefits (end-to-end sanity) ──
do
  local bios = findUp("bios.lua")
  test("bios.lua readable", bios ~= nil)
  if bios then
    local b = strip.strip(bios, { minify = true })
    eq("the shipped BIOS image carries no carriage returns", 0,
      select(2, b:gsub("\r", "")))
    test("the BIOS still fits the 4 KiB EEPROM (" .. #b .. " bytes)", #b <= 4096)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
