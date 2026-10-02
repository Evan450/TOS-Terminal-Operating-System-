-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the release says which tree built it          ║
-- ║                                                                ║
-- ║  _TOS.version is set by hand and moves with releases, so a      ║
-- ║  screenshot, a selftest.log or a crash dump from a box up for a ║
-- ║  week could not say WHICH tree produced it -- the class of      ║
-- ║  "the boot disk was eleven files behind" that sync-emulator.py  ║
-- ║  exists for. build/strip.lua now stamps the release's init.lua  ║
-- ║  with the commit (build) and the strip mode (variant), and the  ║
-- ║  kernel log, the self-test header and `about` print them.       ║
-- ║                                                                ║
-- ║  Runs the REAL strip.lua CLI over temporary trees: a stamp      ║
-- ║  lands; a missing or doubled placeholder STOPS the build rather ║
-- ║  than shipping an unstamped release that looks stamped.         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_build_stamp.lua   (from TOS-Dev)

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

print("=== the build stamp ===")
print()

-- ── The source carries the placeholders the build rewrites ──
package.path = "build/?.lua;" .. package.path
local strip = dofile("build/strip.lua")
local initSrc = assert(readAll("init.lua"), "init.lua not found")
local stripped = strip.strip((initSrc:gsub("\r\n", "\n")), { minify = true })
local function count(s, pat) return select(2, s:gsub(pat, "")) end
test('init.lua carries build = "source" once (after stripping)',
  count(stripped, 'build%s*=%s*"source"') == 1)
test('...and variant = "source" once', count(stripped, 'variant%s*=%s*"source"') == 1)

-- ── The real CLI, on throwaway trees ────────────────────────
local okLfs, lfs = pcall(require, "lfs")
if not okLfs then
  print("  SKIP: LuaFileSystem is not installed; the CLI walk needs it")
else
  local WINDOWS = package.config:sub(1, 1) == "\\"
  local tmp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")
  local base = tmp .. "/tos_stamp_" .. tostring(os.time()) .. "_" .. tostring(math.random(1e6))
  local function rmrf(p)
    local mode = lfs.attributes(p, "mode")
    if mode == "directory" then
      for n in lfs.dir(p) do if n ~= "." and n ~= ".." then rmrf(p .. "/" .. n) end end
      lfs.rmdir(p)
    elseif mode then os.remove(p) end
  end
  local function runStrip(srcDir, dstDir, extra)
    local cmd = 'lua build/strip.lua "' .. srcDir .. '" "' .. dstDir .. '" --minify ' .. (extra or "")
      .. (WINDOWS and " >nul 2>nul" or " >/dev/null 2>&1")
    local ok, _, code = os.execute(cmd)
    if type(ok) == "number" then code = ok; ok = (ok == 0) end
    return ok == true or code == 0
  end

  lfs.mkdir(base)
  local good, bad, out1, out2, out3 = base .. "/good", base .. "/bad",
    base .. "/out1", base .. "/out2", base .. "/out3"
  lfs.mkdir(good); lfs.mkdir(bad)
  writeAll(good .. "/init.lua", initSrc)
  -- A tree whose init.lua lost a placeholder: the stamp could not land.
  writeAll(bad .. "/init.lua", (initSrc:gsub('variant%s*=%s*"source"', 'variant = "x"', 1)))

  local okGood = runStrip(good, out1, "--stamp abc1234")
  local emitted = readAll(out1 .. "/init.lua") or ""
  test("the build succeeds with an explicit stamp", okGood)
  test('the release init.lua says build = "abc1234"', emitted:find('build = "abc1234"', 1, true) ~= nil)
  test('...and variant = "minified"', emitted:find('variant = "minified"', 1, true) ~= nil)
  test("...and no placeholder is left", not emitted:find('"source"', 1, true))

  local okBad = runStrip(bad, out2, "--stamp abc1234")
  test("a missing placeholder stops the build", not okBad)
  test("...before an unstamped init.lua is written", readAll(out2 .. "/init.lua") == nil)

  -- No --stamp: git answers for THIS repository's commit.
  local okGit = runStrip(".", out3, '--exclude /usr/lib/tests/ --exclude /build/ --exclude /.claude/ --exclude /docs/ '
    .. '--exclude /TOS-Extras/')
  local gitInit = readAll(out3 .. "/init.lua") or ""
  local stamp = gitInit:match('build = "([^"]+)"')
  test("without --stamp the build stamps the commit (" .. tostring(stamp) .. ")",
    okGit and stamp ~= nil and (stamp:match("^%x+$") or stamp:match("^%x+%-dirty$") or stamp == "unknown"))

  rmrf(base)
end

-- ── Where the stamp is read back ────────────────────────────
do
  local k = readAll("tos/kernel/init.lua") or ""
  test("the kernel's first log line carries the build", k:find('" (build "', 1, true) ~= nil
    and k:find("_G._TOS.build", 1, true) ~= nil)
  local c = readAll("tos/shell/panels/commands/core.lua") or ""
  test("`about` prints the build", c:find('o("Build " .. tostring(tos.build', 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
