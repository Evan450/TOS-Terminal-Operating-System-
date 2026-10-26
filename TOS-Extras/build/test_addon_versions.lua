-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: add-on versions say the same thing everywhere           ║
-- ║                                                                ║
-- ║  The operator's rule (2026-09-12): MAJOR.MINOR.PATCH, an       ║
-- ║  optional stage suffix, and a package below 1.0.0 does not     ║
-- ║  ship. Three places did not follow it:                         ║
-- ║    • build-disk.lua's SKIP was a list of NAMES, so a new 0.x   ║
-- ║      package shipped unless someone remembered to list it;     ║
-- ║    • a library's _VERSION could drift from its manifest        ║
-- ║      (blockfs said 1.2.0 inside a 1.2.1 package);              ║
-- ║    • the picker gave versions 8 columns and prefixed "v", so   ║
-- ║      v1.10.0-b lost its suffix.                                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua build/test_addon_versions.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("a"); h:close(); return (s:gsub("\r\n", "\n"))
end
local function lift(src, name)
  local i = src and src:find("local function " .. name, 1, true)
  local j = i and src:find("\nend\n", i, true)
  if not (i and j) then return nil end
  local chunk = load(src:sub(i, j + 4) .. "\nreturn " .. name, "=" .. name)
  return chunk and chunk()
end

print("=== build-disk skips a package below 1.0.0 by its version ===")
print()
local bd = readAll("build/build-disk.lua")
local preRelease = lift(bd, "preRelease")
test("build-disk.lua has preRelease", preRelease ~= nil)
if preRelease then
  for _, v in ipairs({ "0.1.0", "0.9.9", "0.9.0-b", "0.0.1" }) do
    test(v .. " is held back", preRelease(v) == true)
  end
  for _, v in ipairs({ "1.0.0", "1.0.0-a", "2.3.1", "10.0.0" }) do
    test(v .. " ships", preRelease(v) == false)
  end
  test("a manifest with no version is held back", preRelease(nil) == true)
  test("...and so is one that is not a version", preRelease("beta") == true)
end
test("build-disk applies it where SKIP is applied",
  bd ~= nil and bd:find("elseif preRelease(m.version) then", 1, true) ~= nil)

print()
print("=== a library's _VERSION is its package's version ===")
print()
local p = io.popen(package.config:sub(1, 1) == "\\" and "dir /b /ad modules 2>nul" or "ls modules")
local checked = 0
for name in p:lines() do
  name = name:gsub("%s+$", "")
  local man = readAll("modules/" .. name .. "/package.lua")
  local lib = readAll("modules/" .. name .. "/usr/lib/" .. name .. ".lua")
  local mv = man and man:match('version%s*=%s*"([^"]+)"')
  local lv = lib and lib:match('[%w_]+%._VERSION%s*=%s*"([^"]+)"')
  if mv and lv then
    checked = checked + 1
    test(name .. ": lib says " .. lv .. ", manifest " .. mv, lv == mv)
  end
end
p:close()
test("found the libraries that carry a _VERSION (blockfs, mail, ...)", checked >= 5, checked)

print()
print("=== the picker shows a suffixed version whole ===")
print()
local picker
for _, path in ipairs({ "../TOS-Dev/tos/shell/pkgpicker.lua", "TOS-Dev/tos/shell/pkgpicker.lua" }) do
  picker = picker or readAll(path)
end
if not picker then
  print("  note: no TOS-Dev beside TOS-Extras; the picker is not checked")
else
  local i = picker:find("local ver = e.version and tostring(e.version)", 1, true)
  local j = i and picker:find("\n", picker:find("if ver ~= \"\"", i, true), true)
  test("the picker builds the version without a fixed \"v\" prefix", i ~= nil and j ~= nil)
  if i and j then
    local f = load("local ulen = function(s) return #s end\nreturn function(e)\n"
      .. picker:sub(i, j) .. "\nreturn ver end")
    local show = f and f()
    test("1.0.1 shows as v1.0.1", show and show({ version = "1.0.1" }) == "v1.0.1")
    test("1.10.0-b shows whole, in 8 cells", show and show({ version = "1.10.0-b" }) == "1.10.0-b")
    test("no version shows nothing", show and show({}) == "")
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
