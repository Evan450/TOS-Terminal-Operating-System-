-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a network install is what the publisher      ║
-- ║  signed                                                        ║
-- ║                                                                ║
-- ║  bootstrap.lua checked every download against a manifest from  ║
-- ║  the same server, with a hasher from the same server, checked  ║
-- ║  against that manifest. Against a hostile server that proved   ║
-- ║  nothing, and its own comment said so. It carries a hasher and ║
-- ║  the publisher's key now, and pins the verifier by digest.     ║
-- ║  This runs the real functions lifted from bootstrap.lua over   ║
-- ║  the real crypto, with a throwaway key.                        ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_release_signature.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 4e6 end,
  totalMemory = function() return 8e6 end, beep = function() end, pullSignal = function() end }
package.loaded["component"] = { list = function() return function() end end,
  isAvailable = function() return false end, proxy = function() end }

local function read(p)
  local h = io.open(p, "rb")
  if not h then return nil end
  local s = h:read("a")
  h:close()
  return s
end
local src = assert(read("bootstrap.lua")):gsub("\r\n", "\n")

local function lift(name)
  local body = src:match("(local function " .. name .. ".-end)%s*%-%-%[%[/TEST%-EXTRACT%]%]")
  test("found " .. name, body ~= nil)
  return assert(load(body .. "\nreturn " .. name, "=" .. name, "t", _G))()
end
local sha256hex = lift("sha256hex")
local verifyRelease = lift("verifyRelease")
local env = assert(load("return " .. src:match("local VERIFIER_ENV = (%b{})"), "=env", "t", _G))()

print("=== the hasher in this file ===")
print()
test("SHA-256 of abc, FIPS 180-4's own vector", sha256hex("abc")
  == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
test("SHA-256 of nothing", sha256hex("")
  == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
do
  local real = require("kernel.sha256")
  local agree = true
  for _, n in ipairs({ 1, 55, 56, 63, 64, 65, 119, 120, 1000, 70000 }) do
    local s = string.rep("x", n)
    agree = agree and sha256hex(s) == real.hex(s)
  end
  test("it agrees with the kernel's at every block boundary", agree)
end

print()
print("=== the chain ===")
print()
local ed = require("kernel.ed25519")
local function hex(b)
  return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
local seed = string.rep("\7", 32)
local pub = ed.publickey(seed)
local KEY = hex(pub)
local other = ed.publickey(string.rep("\9", 32))

local MANIFEST = 'return { { path = "/init.lua", hash = "abc" } }\n'
local files = {
  ["/tos/kernel/sha512.lua"] = assert(read("tos/kernel/sha512.lua")),
  ["/tos/kernel/curve25519field.lua"] = assert(read("tos/kernel/curve25519field.lua")),
  ["/tos/kernel/ed25519.lua"] = assert(read("tos/kernel/ed25519.lua")),
}
local pins = {}
for p, body in pairs(files) do pins[p] = sha256hex(body) end
local function sigFile(msg, s, k)
  return string.format('return { key = %q, sig = %q, signer = "test", v = 1 }',
    k or KEY, hex(ed.sign(msg, s or seed, pub)))
end
local function server(extra)
  local f = {}
  for k, v in pairs(files) do f[k] = v end
  f["/tos/system_manifest.sig"] = sigFile(MANIFEST)
  for k, v in pairs(extra or {}) do
    if v == false then f[k] = nil else f[k] = v end
  end
  return function(path) return f[path] end
end
local function check(manifest, get, key, usePins)
  return verifyRelease(manifest or MANIFEST, get or server(), key or KEY,
    usePins == nil and pins or usePins, env, sha256hex)
end

local ok, why = check()
test("a release signed with the pinned key passes", ok == true, why)

ok, why = check(MANIFEST .. "-- one byte more\n")
test("a changed manifest does not", ok == nil and tostring(why):find("does not match", 1, true), why)

ok, why = check(nil, server({ ["/tos/system_manifest.sig"] = false }))
test("no signature does not", ok == nil and tostring(why):find("no signature", 1, true), why)

ok, why = check(nil, server({ ["/tos/system_manifest.sig"] = "this is not lua (" }))
test("nor does a signature that cannot be read", ok == nil, why)
ok, why = check(nil, server({ ["/tos/system_manifest.sig"] = "return 5" }))
test("nor one that is not a table", ok == nil, why)

ok, why = check(nil, server({ ["/tos/system_manifest.sig"] = sigFile(MANIFEST, string.rep("\9", 32), hex(other)) }))
test("a good signature from someone else does not", ok == nil
  and tostring(why):find("different key", 1, true), why)

ok, why = check(nil, server({ ["/tos/system_manifest.sig"] = sigFile(MANIFEST, string.rep("\9", 32)) }))
test("nor one that claims the pinned key and was made with another", ok == nil
  and tostring(why):find("does not match", 1, true), why)

-- The attack the old chain could not see: a server that serves its own checker.
ok, why = check(nil, server({ ["/tos/kernel/ed25519.lua"] = "return { verify = function() return true end }" }))
test("a verifier that says yes to everything is refused", ok == nil
  and tostring(why):find("not the file this bootstrap", 1, true), why)

ok, why = check(nil, server({ ["/tos/kernel/sha512.lua"] = false }))
test("a missing verifier file does not pass", ok == nil
  and tostring(why):find("could not fetch", 1, true), why)

ok, why = check(nil, nil, nil, "@VERIFIER_PINS@")
test("a copy that did not come from a build vouches for nothing", ok == nil
  and tostring(why):find("not from a release build", 1, true), why)

do
  local ran = false
  _G.__pwned = function() ran = true end
  local evil = 'return { sig = "00", key = "' .. KEY .. '", x = __pwned and __pwned() }'
  check(nil, server({ ["/tos/system_manifest.sig"] = evil }))
  _G.__pwned = nil
  test("the signature file runs with no globals", not ran)
end

do
  local yields = 0
  local real = package.loaded["kernel.process"]
  package.loaded["kernel.process"] = nil
  local okY = verifyRelease(MANIFEST, server(), KEY, pins, env, sha256hex,
    function() yields = yields + 1 end)
  package.loaded["kernel.process"] = real
  test("the verifier yields through what it is given: there is no kernel.process on OpenOS",
    okY == true and yields > 10, yields)
end

print()
print("=== what the installer does with it ===")
print()
test("the published key is pinned", src:find(
  'local RELEASE_KEY = "dcdafa5342333048be0ad519911a6bd1ecffefcffde73879a4e246fc20d7fd8b"', 1, true) ~= nil)
do
  local a = src:find("local official =", 1, true)
  local r = a and src:find("REFUSED", a, true)
  local d = src:find("local stagingDir", 1, true) or src:find("Staging directory", 1, true)
  test("an unsigned official release stops before anything is downloaded",
    a and r and d and r < d)
  test("the hasher is no longer a download", src:find("fetching the hasher", 1, true) == nil)
end
test("--allow-unsigned is the way past it, and it is spelled out",
  src:find("--allow-unsigned goes ahead anyway", 1, true) ~= nil)

print()
print("=== the built release ===")
print()
do
  local built = read("../TOS-Release/bootstrap.lua")
  if built then
    test("the build replaced the placeholder", built:find("@VERIFIER_PINS@", 1, true) == nil)
    for path in pairs(files) do
      local body = read("../TOS-Release" .. path)
      test(path .. "'s digest is pinned", body and built:find(sha256hex(body), 1, true) ~= nil)
    end
  else
    print("  (no TOS-Release here: skipped)")
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
