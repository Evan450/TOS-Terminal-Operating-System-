-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a BIOS too big for the EEPROM is skipped     ║
-- ║                                                                ║
-- ║  A network install from the dev branch copied and verified 171 ║
-- ║  files, then flashed the dev branch's bios.lua, which is the   ║
-- ║  unminified source: 13,608 bytes against a 4,096 byte EEPROM.  ║
-- ║  set() said "not enough space" and the error ended the         ║
-- ║  installer, with TOS already in place. Lifts biosRefusal out   ║
-- ║  of install.lua and runs it, and checks the write is guarded.  ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_bios_size.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local src = assert(io.open("install.lua", "rb")):read("a"):gsub("\r\n", "\n")
local body = src:match("(local function biosRefusal.-end)%s*%-%-%[%[/TEST%-EXTRACT%]%]")
test("biosRefusal can be lifted out of install.lua", body ~= nil)
local refusal = body and assert(load(body .. "\nreturn biosRefusal", "=extract"))()

if refusal then
  test("the dev branch's 13,608-byte source is refused for a 4 KB EEPROM",
    type(refusal(13608, 4096)) == "string" and refusal(13608, 4096):find("13608 bytes", 1, true) ~= nil)
  test("a release's minified BIOS goes on", refusal(3847, 4096) == nil)
  test("exactly full fits", refusal(4096, 4096) == nil)
  test("one byte over does not", refusal(4097, 4096) ~= nil)
  test("an EEPROM that will not say its size is not refused here", refusal(13608, nil) == nil)
  -- On the headless machine the one-line reason ran to 103 columns and
  -- wrapped mid-word. warn() adds "  ! ", so each line gets 76.
  local widest = 0
  for line in (refusal(13608, 4096) or ""):gmatch("[^\n]+") do widest = math.max(widest, #line) end
  test("each line of the reason fits 80 columns after warn's prefix", widest > 0 and widest + 4 <= 80, widest)
end

local flash = src:match("local function offerBiosFlash.-\nend\n") or ""
test("the size is checked before the operator is asked to type flash",
  (flash:find("biosRefusal(", 1, true) or 1e9) < (flash:find('Type "flash"', 1, true) or 0))
test("the caller warns the reason a line at a time",
  flash:find('refusal:gmatch("[^\\n]+")', 1, true) ~= nil)
test("and a refused write is a warning, not the end of the installer",
  flash:find("pcall(ep.set, biosCode)", 1, true) ~= nil)

-- The release build really is small enough: what the dev branch is not.
local rel = io.open("../TOS-Release/bios.lua", "rb")
if rel then
  local n = #rel:read("a"); rel:close()
  test("the release's bios.lua fits a 4 KB EEPROM (" .. n .. " bytes)", n <= 4096)
else
  print("  (no TOS-Release beside this tree: the built BIOS is not measured)")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
