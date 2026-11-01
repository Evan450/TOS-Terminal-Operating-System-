-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a service answers to the name the docs use   ║
-- ║                                                                ║
-- ║  The shipped services carry a load-order prefix (20-netfsd),   ║
-- ║  and netfs.man says `service start netfsd`, which answered     ║
-- ║  "Unknown service". fullName is LIFTED from rc.lua.            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_rc_short_name.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local h = assert(io.open("tos/kernel/rc.lua", "rb"))
local src = h:read("a"):gsub("\r\n", "\n"); h:close()
local from = src:find("local function fullName", 1, true)
local to = from and src:find("\nend\n", from, true)
test("found fullName in rc.lua", from ~= nil and to ~= nil)
if not (from and to) then
  print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***"); os.exit(1)
end

local services = { ["20-netfsd"] = {}, ["20-rshd"] = {}, ["clusterd"] = {} }
local env = { services = services, pairs = pairs }
local fullName = assert(load(src:sub(from, to + 4) .. "\nreturn fullName", "=fullName", "t", env))()

print("=== the short name ===")
test("netfsd finds 20-netfsd", fullName("netfsd") == "20-netfsd", fullName("netfsd"))
test("rshd finds 20-rshd", fullName("rshd") == "20-rshd", fullName("rshd"))
test("the full name still works", fullName("20-netfsd") == "20-netfsd")
test("a service with no prefix still works", fullName("clusterd") == "clusterd")
test("an unknown name stays as typed, for the error to name it", fullName("nothing") == "nothing")
test("a part of a name is not a match", fullName("netfs") == "netfs")
test("the number alone is not a match", fullName("20") == "20")
test("an exact name wins over a prefixed one", (function()
  services["netfsd"] = {}
  local got = fullName("netfsd")
  services["netfsd"] = nil
  return got == "netfsd"
end)())

print("=== both ways use it ===")
test("rc.start asks", src:match("function rc%.start%(name%)%s+name = fullName%(name%)") ~= nil)
test("rc.stop asks", src:match("function rc%.stop%(name%)%s+name = fullName%(name%)") ~= nil)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
