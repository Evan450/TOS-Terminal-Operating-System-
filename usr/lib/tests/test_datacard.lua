-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: shared Data Card detector            ║
-- ║  (kernel.datacard) — tier inference from method set     ║
-- ║  so crypto / compress / sysinfo / POST all agree.       ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_datacard.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_datacard.lua"
local base = here:gsub("[^/\\]*$", "")
local function withCard(card)
  package.loaded["component"] = {
    list = function(t)
      local done = false
      return function()
        if done or t ~= "data" then return nil end
        done = true; return "data-addr", "data"
      end
    end,
    proxy = function() return card end,
  }
  package.loaded["kernel.datacard"] = nil
  local dc
  for _, p in ipairs({ base .. "../../../tos/kernel/datacard.lua",
      "tos/kernel/datacard.lua", "TOS-Dev/tos/kernel/datacard.lua" }) do
    local chunk = loadfile(p); if chunk then dc = chunk(); break end
  end
  return dc
end

local fn = function() end

print("=== Data Card detector Tests ===")
print()

-- Tier 1: hashing/base64/deflate, no AES/ECC.
do
  local dc = withCard({ sha256 = fn, md5 = fn, deflate = fn, inflate = fn, encode64 = fn })
  local i = dc.detect()
  test("T1 present", true, i.present)
  test("T1 tier", 1, i.tier)
  test("T1 has deflate cap", true, i.caps.deflate)
  test("T1 no aes", false, i.caps.aes or false)
end

-- Tier 2: adds AES + random.
do
  local dc = withCard({ sha256 = fn, deflate = fn, inflate = fn, encrypt = fn, decrypt = fn, random = fn })
  local i = dc.detect()
  test("T2 tier", 2, i.tier)
  test("T2 has aes", true, i.caps.aes)
  test("T2 still has deflate", true, i.caps.deflate)
end

-- Tier 3: adds ECC.
do
  local dc = withCard({ sha256 = fn, deflate = fn, inflate = fn, encrypt = fn,
                        decrypt = fn, generateKeyPair = fn, ecdsa = fn })
  local i = dc.detect()
  test("T3 tier", 3, i.tier)
  test("T3 has ecc", true, i.caps.ecc)
end

-- Featureless proxy (some emulators): present but tier 0.
do
  local dc = withCard({})
  local i = dc.detect()
  test("featureless present", true, i.present)
  test("featureless tier 0", 0, i.tier)
  test("featureless deflate false", false, i.caps.deflate or false)
end

-- Ocelot-style: the proxy exposes NO method fields (type(p.sha256) is nil),
-- but component.methods(addr) DOES enumerate them. capsOf must classify by the
-- authoritative method set, not read the card as "unknown tier". This is the
-- exact emulator failure that made every card show tier 0 until pinned.
local function withMethodsCard(methods)
  package.loaded["component"] = {
    list = function(t)
      local done = false
      return function()
        if done or t ~= "data" then return nil end
        done = true; return "data-addr", "data"
      end
    end,
    proxy   = function() return {} end,             -- bare proxy: no method fields
    methods = function(addr) return addr == "data-addr" and methods or nil end,
  }
  package.loaded["kernel.datacard"] = nil
  local dc
  for _, p in ipairs({ base .. "../../../tos/kernel/datacard.lua",
      "tos/kernel/datacard.lua", "TOS-Dev/tos/kernel/datacard.lua" }) do
    local chunk = loadfile(p); if chunk then dc = chunk(); break end
  end
  return dc
end
do
  -- Map form: { name = true, ... }
  local i = withMethodsCard({ sha256 = true, deflate = true, inflate = true,
                              encrypt = true, decrypt = true, random = true }).detect()
  test("methods-enumerated present", true, i.present)
  test("methods-enumerated tier (T2, proxy had no fields)", 2, i.tier)
  test("methods-enumerated has aes", true, i.caps.aes)
end
do
  -- Array form: { "name", ... }  (some implementations return a name list)
  local i = withMethodsCard({ "md5", "crc32", "encode64" }).detect()
  test("methods array-form tier (T1)", 1, i.tier)
end

-- No card at all.
do
  package.loaded["component"] = { list = function() return function() return nil end end }
  package.loaded["kernel.datacard"] = nil
  local dc
  for _, p in ipairs({ base .. "../../../tos/kernel/datacard.lua",
      "tos/kernel/datacard.lua", "TOS-Dev/tos/kernel/datacard.lua" }) do
    local chunk = loadfile(p); if chunk then dc = chunk(); break end
  end
  local i = dc.detect()
  test("no card -> not present", false, i.present)
  test("no card -> tier 0", 0, i.tier)
end

-- capsOf/tierOf are pure helpers.
do
  local dc = withCard({})
  test("tierOf({aes}) = 2", 2, dc.tierOf({ aes = true }))
  test("tierOf({deflate}) = 1", 1, dc.tierOf({ deflate = true }))
  test("tierOf({}) = 0", 0, dc.tierOf({}))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
