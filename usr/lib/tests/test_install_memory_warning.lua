-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the installer's memory warning knows about   ║
-- ║  network cards                                                 ║
-- ║                                                                ║
-- ║  `tos.py floorcheck` found that every memory figure had been    ║
-- ║  measured without a network card. With one, the network stack  ║
-- ║  and its services take about 170 KB more, and 1 MB starts the  ║
-- ║  command line but no command loads: the floor is 1.25 MB. The  ║
-- ║  installer warned only below 1 MB, so a 1 MB machine with a    ║
-- ║  network card installed without a word.                        ║
-- ║                                                                ║
-- ║  printHardwareReport is LIFTED from install.lua and run on     ║
-- ║  each machine the floor check boots.                           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_memory_warning.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function readSrc(rel)
  for _, p in ipairs({ rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "rb")
    if f then local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n")) end
  end
end

local src = assert(readSrc("install.lua"), "install.lua")
local fn = src:match("(local function printHardwareReport%(hw%).-\nend\n)")
test("printHardwareReport is in install.lua", fn ~= nil)
if not fn then print("*** TESTS FAILED ***"); return false end

-- The warnings a machine gets, joined; everything else is dropped.
local function warningsFor(memKB, card)
  local said = {}
  local env = setmetatable({
    color = function() end,
    print = function() end,
    warn  = function(s) said[#said + 1] = s end,
  }, { __index = _G })
  local chunk = assert(load(fn .. "\nreturn printHardwareReport", "=install", "t", env))
  chunk()({ memKB = memKB, freeMem = 0, diskKB = 0, diskFreeKB = 0,
            hasModem = card == "modem", hasTunnel = card == "tunnel" })
  return table.concat(said, " | ")
end

print("=== the installer's memory warning ===")
print()

local w = warningsFor(768)
test("768 KB: not enough memory", w:find("TOS needs at least 1 MB", 1, true) ~= nil, w)
test("...and it no longer promises the emergency terminal",
  w:find("emergency terminal", 1, true) == nil
  and w:find("its commands do not load", 1, true) ~= nil, w)

w = warningsFor(1024)
test("1 MB, no network card: only the command-line notice",
  w == "TOS will start at the command line: the full interface needs 1.5 MB.", w)

w = warningsFor(1024, "modem")
test("1 MB with a network card: not enough memory, and why",
  w:find("with a network card TOS needs 1.25 MB", 1, true) ~= nil, w)
test("...not the command-line notice as if it would work",
  w:find("will start at the command line", 1, true) == nil, w)
w = warningsFor(1024, "tunnel")
test("a linked card counts as a network card",
  w:find("with a network card TOS needs 1.25 MB", 1, true) ~= nil, w)

w = warningsFor(1280, "modem")
test("1.25 MB with a network card: the command-line notice only",
  w == "TOS will start at the command line: the full interface needs 1.5 MB.", w)
test("1.5 MB with a network card: nothing to warn about", warningsFor(1536, "modem") == "")
test("2 MB: nothing to warn about", warningsFor(2048) == "")

-- The numbers here are the floor check's: change them together.
local fc = readSrc("build/floorcheck.py") or ""
test("the floor check boots 1 MB with a card and expects no command to load",
  fc:find('With one, 1 MB starts the command line but none of its commands load', 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
