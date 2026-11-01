-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: install profiles                             ║
-- ║                                                                ║
-- ║  A full install is 330 KB over a 1 MB drive, and the installer ║
-- ║  could only say so. `minimal` installs the floor, which is     ║
-- ║  proven closed and proven to boot, and writes a trimmed        ║
-- ║  manifest so `verify` does not call the rest missing. Lifts    ║
-- ║  the real functions out of install.lua.                        ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_profile.lua   (from TOS-Dev)

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
local function lift(name)
  local body = src:match("(local function " .. name .. ".-end)%s*%-%-%[%[/TEST%-EXTRACT%]%]")
  test("found " .. name, body ~= nil)
  return assert(load(body .. "\nreturn " .. name, "=" .. name, "t", _G))()
end
local classifyArgs = lift("classifyArgs")
local forProfile = lift("forProfile")
local manifestText = lift("manifestText")

print("=== asking for one ===")
print()
test("--profile minimal", classifyArgs({ "--profile", "minimal" }).profile == "minimal")
test("--profile full", classifyArgs({ "--profile", "full" }).profile == "full")
test("no flag means no choice yet, so the installer may offer",
  classifyArgs({}).profile == nil)
test("it sits beside a source dir", classifyArgs({ "/mnt/a", "--profile", "minimal" }).positional[1] == "/mnt/a")
test("a word it does not know is refused, and named",
  classifyArgs({ "--profile", "tiny" }).unknown == "--profile tiny")
test("as is no word at all", classifyArgs({ "--profile" }).unknown ~= nil)
test("-h still helps", classifyArgs({ "-h" }).help == true)
test("--configure still configures", classifyArgs({ "--configure" }).configure == true)

print()
print("=== what each installs ===")
print()
local manifest = {
  { path = "/init.lua", critical = true, floor = true, hash = "abc" },
  { path = "/tos/kernel/init.lua", critical = true, floor = true },
  { path = "/tos/shell/panels.lua", critical = false },
}
test("full is the whole manifest", forProfile(manifest, "full") == manifest)
test("so is no profile at all", forProfile(manifest, nil) == manifest)
local kept = forProfile(manifest, "minimal")
test("minimal is the floor", #kept == 2 and kept[1].path == "/init.lua"
  and kept[2].path == "/tos/kernel/init.lua")

do
  local f = assert(io.open("tos/system_manifest.lua", "rb"))
  local real = assert(load(f:read("a"), "=manifest", "t", {}))(); f:close()
  local floor = forProfile(real, "minimal")
  test("on the real manifest it is a small part of the system",
    #floor > 20 and #floor < #real / 2, #floor)
  local paths = {}
  for _, e in ipairs(floor) do paths[e.path] = true end
  test("the boot file is in it", paths["/init.lua"])
  test("the manifest itself is in it, so there is a file to trim",
    paths["/tos/system_manifest.lua"])
  test("so is the security policy", paths["/tos/kernel/policy.lua"]
    and paths["/tos/kernel/policyload.lua"])
end

print()
print("=== the manifest it leaves behind ===")
print()
do
  local text = manifestText(kept)
  local back = assert(load(text, "=written", "t", {}))()
  test("it parses, as data", type(back) == "table" and #back == 2)
  test("paths survive", back[2].path == "/tos/kernel/init.lua")
  test("critical survives", back[1].critical == true)
  test("floor survives", back[1].floor == true)
  test("a digest survives, so `verify` can still check the file", back[1].hash == "abc")
  test("no entry gains a digest it never had", back[2].hash == nil)
  local odd = manifestText({ { path = '/odd"name.lua' } })
  test("an odd path cannot break out of the string",
    assert(load(odd, "=odd", "t", {}))()[1].path == '/odd"name.lua')
end

print()
print("=== the installer's flow ===")
print()
test("no drive fits: it offers the minimal system",
  src:find('"Try the minimal system instead?"', 1, true) ~= nil)
test("only when nobody chose a profile",
  src:find('chooseWhy == "space" and not profile', 1, true) ~= nil)
test("the trimmed manifest goes through a temp file",
  src:find('path .. ".tmp", "w"', 1, true) ~= nil)
local copied = src:find("copyOk, copyWhy = copyFromDisk", 1, true)
local trimmed = src:find('if copyOk and profile == "minimal"', 1, true)
test("after the copy is verified, which compares that file with the source's",
  copied and trimmed and copied < trimmed)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
