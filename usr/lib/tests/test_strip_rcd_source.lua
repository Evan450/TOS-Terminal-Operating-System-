-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: --minify-vars leaves rc.d scripts readable   ║
-- ║                                                                ║
-- ║  rc.lua decides a service's caps, user, restart and needs by    ║
-- ║  pattern-matching its SOURCE (peekServiceMeta) before anything  ║
-- ║  runs. --minify-vars renames locals and hoists repeated strings ║
-- ║  into locals, and either one can take a field out of the        ║
-- ║  peek's sight: `local caps = {...}` returned as `caps = caps`,  ║
-- ║  or `user = "operator1"` hoisted to `user = d`. So /etc/rc.d/   ║
-- ║  gets the whitespace pass only (strip.kernelReadsSource), and   ║
-- ║  everything else still gets the full one.                       ║
-- ║                                                                ║
-- ║  Runs the REAL strip.lua CLI over a temporary tree, same shape  ║
-- ║  as test_strip_validates_output.lua.                            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_strip_rcd_source.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function writeAll(p, s)
  local h = assert(io.open(p, "wb")); h:write(s); h:close()
end
local function count(s, plain)
  local n, i = 0, 1
  while true do
    local a, b = s:find(plain, i, true)
    if not a then return n end
    n, i = n + 1, b + 1
  end
end

print("=== --minify-vars leaves rc.d scripts readable ===")
print()

local okLfs, lfs = pcall(require, "lfs")
if not okLfs then
  print("  SKIP: LuaFileSystem is not installed; the CLI walk needs it")
  print()
  print("Results: 0 passed, 0 failed")
  print("All tests passed.")
  return true
end

local WINDOWS = package.config:sub(1, 1) == "\\"
local tmp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")
local base = tmp .. "/tos_strip_rcd_" .. tostring(os.time()) .. "_" .. tostring(math.random(1e6))

local function rmrf(p)
  local mode = lfs.attributes(p, "mode")
  if mode == "directory" then
    for n in lfs.dir(p) do if n ~= "." and n ~= ".." then rmrf(p .. "/" .. n) end end
    lfs.rmdir(p)
  elseif mode then os.remove(p) end
end

local STRIP
for _, prefix in ipairs({ "", "../", "../../" }) do
  if readAll(prefix .. "build/strip.lua") then STRIP = prefix .. "build/strip.lua"; break end
end
test("build/strip.lua found", STRIP ~= nil)
if not STRIP then
  print(); print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

local strip = dofile(STRIP)
test("kernelReadsSource: an rc.d script", strip.kernelReadsSource("/etc/rc.d/20-netfsd.lua"))
test("kernelReadsSource: not a module", not strip.kernelReadsSource("/tos/kernel/rc.lua"))
test("kernelReadsSource: not a file merely named rc.d",
  not strip.kernelReadsSource("/usr/share/etc/rc.d/x.lua"))

-- A service written the two ways the full pass would hide from the peek,
-- and a module that should still get the full pass.
local SERVICE = [[
-- A service whose caps live in a local and whose user name repeats.
local caps = { "network", "fs.read" }
local function start()
  print("operator1", "operator1")
end
return {
  start = start,
  caps  = caps,
  user  = "operator1",
}
]]
local MODULE = [[
-- An ordinary module: long names, a repeated string.
local someDescriptiveLocalName = "repeated literal"
local function describe() return "repeated literal", "repeated literal" end
return { describe = describe, value = someDescriptiveLocalName }
]]

local src, dst = base .. "/src", base .. "/dst"
for _, d in ipairs({ base, src, src .. "/etc", src .. "/etc/rc.d", src .. "/tos" }) do
  lfs.mkdir(d)
end
writeAll(src .. "/etc/rc.d/50-svc.lua", SERVICE)
writeAll(src .. "/tos/mod.lua", MODULE)

local cmd = 'lua "' .. STRIP .. '" "' .. src .. '" "' .. dst .. '" --minify-vars'
  .. (WINDOWS and " >nul 2>nul" or " >/dev/null 2>&1")
local ok, _, code = os.execute(cmd)
if type(ok) == "number" then code = ok; ok = (ok == 0) end
test("strip.lua --minify-vars exits cleanly", ok == true or code == 0)

local svc = readAll(dst .. "/etc/rc.d/50-svc.lua") or ""
local mod = readAll(dst .. "/tos/mod.lua") or ""
test("the service was written", #svc > 0)
test("...its comment is gone", not svc:find("A service whose", 1, true))
test("...its indentation is gone", not svc:find("\n ", 1, true))
test("...`local caps` keeps its name", svc:find("local caps =", 1, true) ~= nil)
test("...the user string is not hoisted (3 copies)", count(svc, '"operator1"') == 3)
test("...`user = \"operator1\"` reads as written", svc:find('user = "operator1"', 1, true) ~= nil)
test("...and it still compiles", load(svc, "=svc", "t") ~= nil)

test("the module still gets the full pass: long local renamed",
  #mod > 0 and not mod:find("someDescriptiveLocalName", 1, true))
test("...and its repeated string hoisted (1 copy)", count(mod, '"repeated literal"') == 1)

rmrf(base)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
