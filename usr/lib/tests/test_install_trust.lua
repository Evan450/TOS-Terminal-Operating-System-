-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the key the installer offers to trust        ║
-- ║                                                                ║
-- ║  install.lua asks whether to trust the Optional Utilities      ║
-- ║  publisher, and writes that key into /etc/pkg_trust.cfg. It is ║
-- ║  a copy, so it can go stale: this keeps it equal to the key    ║
-- ║  bootstrap.lua pins for a release and to the key the pack on   ║
-- ║  disk is really signed with, and checks that what the          ║
-- ║  installer writes is a store pkgsign reads as that key.         ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_trust.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function read(p)
  local h = io.open(p, "rb")
  if not h then return nil end
  local s = h:read("a"); h:close(); return s
end

local inst = read("install.lua") or ""
local key = inst:match('local OFFICIAL_KEY = "(%x+)"')
local label = inst:match('local OFFICIAL_KEY_LABEL = "([%w%-_%.]+)"')
test("install.lua names the key", key ~= nil and #key == 64, key)
test("and a label pkgsign accepts", label ~= nil and #label <= 48, label)

local boot = read("bootstrap.lua") or ""
test("it is the key bootstrap.lua pins for a release",
  key ~= nil and boot:match('RELEASE_KEY = "(%x+)"') == key, boot:match('RELEASE_KEY = "(%x+)"'))

-- The pack, where this tree has one beside it.
local sig = read("../TOS-Extras/dist/optional-utilities/disk1/calc/package.sig")
if sig then
  local signed = sig:match('%["key"%] = "(%x+)"')
  test("and the key the Optional Utilities are signed with", signed == key, signed)
  test("under the label they are signed as", sig:match('%["signer"%] = "([^"]+)"') == label)
else
  print("  (no pack beside this tree: its key is not checked)")
end

-- What the installer writes, read as pkgsign reads it.
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local serialize = dofile("tos/kernel/serialize.lua")
local written = "return {\n  keys = {\n    [\"" .. tostring(label) .. "\"] = \""
  .. tostring(key) .. "\",\n  },\n}\n"
test("install.lua writes the store in this shape",
  inst:find('f:write("return {\\n  keys = {\\n    [\\"" .. OFFICIAL_KEY_LABEL .. "\\"] = \\""', 1, true) ~= nil)
local files = { ["/etc/pkg_trust.cfg"] = written }
local F = {
  exists = function(p) return files[p] ~= nil end,
  readFile = function(p) return files[p] end,
}
local pkgsign = dofile("tos/kernel/pkgsign.lua")
pkgsign.init({ fs = F, serialize = serialize })
local list = pkgsign.listKeys()
local found
for k, v in pairs(list) do
  local entryKey = type(v) == "table" and (v.key or v.pub) or v
  local entryLabel = type(v) == "table" and v.label or k
  if entryKey == key and entryLabel == label then found = true end
end
test("and pkgsign reads it as that key, under that label", found == true)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
