-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the manifest anchor must NOT eat the boot   ║
-- ║  address (#SEC C1 EEPROM data-field layout)                   ║
-- ║                                                              ║
-- ║  The EEPROM's 256-byte data field is where the BIOS keeps the ║
-- ║  BOOT ADDRESS (`getBootAddress` = `getData`). The manifest    ║
-- ║  anchor shares that field, and the original implementation    ║
-- ║  wrote "TOS1:<hash>" at the FRONT — destroying the address.   ║
-- ║  A machine that anchored its manifest would lose its boot     ║
-- ║  device and prompt "Boot drive changed" on every power-on.    ║
-- ║  `doctor` was actively recommending it; the only reason       ║
-- ║  nobody got bitten is that the function had no shell surface. ║
-- ║                                                              ║
-- ║  Layout now: line 1 = boot address, line 2 = "TOS1:<64 hex>". ║
-- ║  This pins the round-trip from BOTH sides — the writer keeps  ║
-- ║  the address, and the BIOS's reader ignores the anchor.       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_manifest_anchor.lua  (from the TOS-Dev root)

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
  for _, pre in ipairs({ "", "../", "../../", "../../../" }) do
    local s = readAll(pre .. rel); if s then return s end
  end
end

print("=== manifest anchor vs boot address ===")
print()

local ADDR = "e1344d2b-1234-4321-abcd-0123456789ab"
local HASH = string.rep("a1b2", 16)              -- 64 hex chars

-- ── The BIOS reader: only the FIRST LINE is the boot address ──────
-- Extract the real expression from bios.lua so the test tracks the
-- shipped code rather than a copy of it.
do
  local bios = findUp("bios.lua")
  test("bios.lua readable", bios ~= nil)
  if bios then
    local expr = bios:match("p%.getBootAddress=function%(%)return(.-)end")
    test("found the BIOS getBootAddress body", expr ~= nil)
    if expr then
      -- Evaluate it against a fake EEPROM holding address + anchor.
      local data = ADDR .. "\nTOS1:" .. HASH
      local fn = load("local E = ... ; return " .. expr, "=biosread", "t")
      test("the BIOS reader compiles", fn ~= nil)
      if fn then
        local ok, got = pcall(fn, function() return data end)
        test("the BIOS reader runs", ok)
        eq("BIOS reads ONLY the boot address (anchor ignored)", ADDR, got)

        -- Legacy EEPROM: a bare address with no anchor line still reads.
        local ok2, got2 = pcall(fn, function() return ADDR end)
        eq("a legacy bare address still reads unchanged", ADDR, ok2 and got2)

        -- Empty field yields empty, not nil (the BIOS compares to "").
        local ok3, got3 = pcall(fn, function() return nil end)
        eq("a blank EEPROM yields an empty string", "", ok3 and got3)
      end
    end
  end
end

-- ── The writer: anchoring PRESERVES the boot address ──────────────
-- Drive the real kernel.anchorManifestHash against a fake EEPROM.
do
  local stored = ADDR
  package.loaded["component"] = {
    list = function(t)
      local a = (t == "eeprom") and { "eeprom-1" } or {}
      local i = 0; return function() i = i + 1; return a[i] end
    end,
    proxy = function()
      return {
        getData = function() return stored end,
        setData = function(v) stored = v end,
      }
    end,
  }

  -- Pull the two functions out of kernel/init.lua without booting a
  -- kernel: they only close over `fs` (for the manifest) and require
  -- component/crypto at call time.
  local src = findUp("tos/kernel/init.lua")
  test("kernel/init.lua readable", src ~= nil)
  local anchorSrc = src and src:match("(function kernel%.anchorManifestHash%(%).-\nend)")
  test("found anchorManifestHash", anchorSrc ~= nil)

  if anchorSrc then
    local kernel = {}
    -- Stub the hash computation: this test is about the LAYOUT, and the
    -- digest itself is covered by the crypto tests.
    kernel.computeManifestHash = function() return HASH end
    local env = setmetatable({ kernel = kernel, require = require },
      { __index = _G })
    local fn = load(anchorSrc, "=anchor", "t", env)
    test("anchorManifestHash compiles standalone", fn ~= nil)
    if fn then
      fn()   -- defines kernel.anchorManifestHash in env
      local ok, digest = kernel.anchorManifestHash()
      test("anchoring succeeds", ok == true)
      eq("it reports the digest", HASH, digest)

      -- THE REGRESSION: the boot address must survive.
      eq("the boot address is PRESERVED on line 1", ADDR, stored:match("^[^\n]*"))
      test("the anchor is written on its own line",
        stored:find("\nTOS1:" .. HASH, 1, true) ~= nil)
      test("the field does NOT start with the anchor (the old bug)",
        stored:sub(1, 5) ~= "TOS1:")

      -- Re-anchoring is idempotent: it must not stack anchors or
      -- duplicate the address.
      local before = stored
      kernel.anchorManifestHash()
      eq("re-anchoring is idempotent", before, stored)
      local _, anchors = stored:gsub("TOS1:", "")
      eq("exactly one anchor in the field", 1, anchors)

      -- The whole thing has to fit the 256-byte data field.
      test("the payload fits the EEPROM data field (" .. #stored .. " bytes)",
        #stored <= 256)
    end
  end
end

-- ── doctor's advice must name a REAL command ──────────────────────
do
  local diag = findUp("tos/kernel/diag.lua")
  test("kernel/diag.lua readable", diag ~= nil)
  if diag then
    -- Check the REPORTED MESSAGE, not the whole file: the comment above
    -- it legitimately names the old call while explaining the fix.
    local msg = diag:match('R%("security: manifest hash not anchored.-"')
      or diag:match('R%("security: manifest hash NOT anchored.-"') or ""
    test("doctor's message no longer names a kernel function",
      msg:find("kernel.", 1, true) == nil)
    test("doctor names a typeable command instead",
      diag:find("verify anchor", 1, true) ~= nil)
  end
  local admin = findUp("tos/shell/panels/commands/admin.lua")
  test("admin.lua readable", admin ~= nil)
  if admin then
    test("`verify anchor` actually exists as a subcommand",
      admin:find('sub == "anchor"', 1, true) ~= nil)
    test("...and it is admin-gated", admin:find("adminOnly(o)", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
