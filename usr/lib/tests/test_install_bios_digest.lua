-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the installer really shows the BIOS digest   ║
-- ║                                                                ║
-- ║  #SEC H3 prints a fingerprint of the BIOS before the typed     ║
-- ║  "flash" confirmation. It asked require("kernel.crypto") for   ║
-- ║  it, and the installer runs on OpenOS, where no kernel.* name  ║
-- ║  exists, so every install there has been printed               ║
-- ║  "SHA-256: (unavailable)". Seen on the headless machine with   ║
-- ║  a data card in it, running bootstrap.lua end to end.          ║
-- ║                                                                ║
-- ║  biosDigest is LIFTED from install.lua and run with a fake     ║
-- ║  data card and with none, on the real sha256.lua.              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_bios_digest.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local h = assert(io.open("install.lua", "rb"))
local src = h:read("a"):gsub("\r\n", "\n"); h:close()
local from = src:find("local function biosDigest", 1, true)
local to = from and src:find("\nend\n", from, true)
test("found biosDigest in install.lua", from ~= nil and to ~= nil)
if not (from and to) then
  print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***"); os.exit(1)
end

local CODE = "bios code"
-- SHA-256("abc"), the FIPS 180-4 vector, as raw bytes and as hex.
local ABC_HEX = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
local abcRaw = ABC_HEX:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end)

local function lift(component)
  local chunk = assert(load(src:sub(from, to + 4) .. "\nreturn biosDigest", "=biosDigest", "t",
    setmetatable({ component = component }, { __index = _G })))
  return chunk()
end

print("=== a data card answers ===")
do
  local seen
  local digest = lift({
    isAvailable = function(n) return n == "data" end,
    data = { sha256 = function(s) seen = s; return abcRaw end },
  })(CODE, ".")
  test("the card was handed the image", seen == CODE, seen)
  test("the raw 32 bytes come back as 64 hex digits", digest == ABC_HEX, digest)
end

print("=== no data card: the disk's own hasher ===")
do
  local none = { isAvailable = function() return false end }
  test("SHA-256('abc') from the real tos/kernel/sha256.lua",
    lift(none)("abc", ".") == ABC_HEX, lift(none)("abc", "."))
  test("a disk with no hasher answers nil", lift(none)("abc", "./no/such/disk") == nil)
end

print("=== a card that fails does not end the search ===")
do
  local failing = {
    isAvailable = function(n) return n == "data" end,
    data = { sha256 = function() error("out of energy") end },
  }
  test("a raising card falls through to the disk's hasher",
    lift(failing)("abc", ".") == ABC_HEX)
  local short = {
    isAvailable = function(n) return n == "data" end,
    data = { sha256 = function() return "short" end },
  }
  test("a card's wrong-sized answer is not shown as a digest",
    lift(short)("abc", ".") == ABC_HEX)
end

print("=== the flash prompt uses it ===")
do
  local body = src:match("local function offerBiosFlash.-\nend\n") or ""
  test("offerBiosFlash asks biosDigest", body:find("biosDigest(biosCode, srcDisk)", 1, true) ~= nil)
  test("nothing asks for kernel.crypto any more", not src:find('"kernel.crypto"', 1, true))
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***"); os.exit(1)
end
print("All tests passed.")
