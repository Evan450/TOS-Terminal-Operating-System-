-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what the end of boot settles                 ║
-- ║                                                                ║
-- ║  Two decisions the audits left open, made 2026-11-01:          ║
-- ║   * a headless machine ends boot like one with a screen.       ║
-- ║     headlessMain kept bootSession for the whole uptime, so a   ║
-- ║     caller with no process principal was the kernel there and  ║
-- ║     nobody anywhere else;                                      ║
-- ║   * a manifest that fails its EEPROM anchor is reported at     ║
-- ║     boot, and a machine with no anchor says nothing and        ║
-- ║     hashes nothing.                                            ║
-- ║  The real functions are lifted out of the source and run.      ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_boot_warnings.lua   (from the TOS-Dev root)

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
  local s = h:read("a"):gsub("\r\n", "\n"); h:close(); return s
end
local function findUp(rel)
  for _, pre in ipairs({ "", "TOS-Dev/", "../", "../../", "../../../" }) do
    local s = readAll(pre .. rel); if s then return s end
  end
end
local function lift(src, head)
  local from = src:find(head, 1, true)
  local to = from and src:find("\nend\n", from, true)
  return from and src:sub(from, to + 4)
end

local init = findUp("tos/kernel/init.lua")
assert(init, "tos/kernel/init.lua not found")

print("=== a headless machine ends boot too ===")
print()
do
  local body = lift(init, "function kernel.headlessMain()")
  test("found headlessMain", body ~= nil)
  -- Run it up to the first thing that needs a machine.
  local stop = {}
  local tos = { bootSession = { user = "kernel" }, users = {} }
  local env = setmetatable({
    kernel = {}, running = false,
    log = { info = function() error(stop) end, warn = function() end },
    _G = { _TOS = tos },
  }, { __index = _G })
  local fn = assert(load(body .. "\nreturn kernel.headlessMain", "=headlessMain", "t", env))()
  local ok, err = pcall(fn)
  test("it reached the log line, nothing before it fell over", not ok and err == stop, err)
  test("bootSession is gone", tos.bootSession == nil)
  test("bootCompleted is set, as the screen path sets it", tos.bootCompleted == true)

  local screen = init:find("_G._TOS.bootSession   = nil\n    _G._TOS.bootCompleted = true", 1, true)
  test("the screen path still does the same", screen ~= nil)

  local rc, cron = findUp("tos/kernel/rc.lua"), findUp("tos/kernel/cron.lua")
  test("rc falls back to kernelSession() once bootSession is gone",
    rc:find("if _G._TOS and _G._TOS.bootSession then return _G._TOS.bootSession end\n"
      .. "    if usersmod.kernelSession then return usersmod.kernelSession() end", 1, true) ~= nil)
  test("cron does too",
    cron:find("if _G._TOS and _G._TOS.bootSession then return _G._TOS.bootSession end\n"
      .. "  if usersmod and usersmod.kernelSession then return usersmod.kernelSession() end", 1, true) ~= nil)
end

print()
print("=== the manifest anchor at boot ===")
print()
do
  local body = lift(init, "function kernel.manifestAnchorWarning()")
  test("found manifestAnchorWarning", body ~= nil)
  local kernel = {}
  local fn = assert(load(body .. "\nreturn kernel.manifestAnchorWarning", "=anchor", "t",
    setmetatable({ kernel = kernel }, { __index = _G })))()

  kernel.verifyManifestHash = function() return true end
  test("a match says nothing", fn() == nil)
  kernel.verifyManifestHash = function() return false, "no anchored hash (run `verify anchor` as admin)" end
  test("an unanchored machine says nothing", fn() == nil)
  kernel.verifyManifestHash = function() return false, "no EEPROM" end
  test("nor does one with no EEPROM", fn() == nil)
  kernel.verifyManifestHash = function() error("boom") end
  test("a check that falls over stops nothing", fn() == nil)
  kernel.verifyManifestHash = function() return false, "manifest hash mismatch (live=aa anchored=bb)" end
  test("a mismatch gets its reason out", tostring(fn()):find("mismatch", 1, true) ~= nil, fn())
  kernel.verifyManifestHash = function() return false, "anchored value malformed" end
  test("a damaged anchor does too", tostring(fn()):find("malformed", 1, true) ~= nil, fn())

  -- The call has to be in boot, before the shell takes the screen.
  local call = init:find("kernel.manifestAnchorWarning()\n", 1, true)
  local stop = init:find("log.detachEarlyPrint()", 1, true)
  test("boot asks, while the POST screen still shows the log",
    call and stop and call < stop)
  local verify = init:find("local anchored = existing:match", 1, true)
  local hash = init:find("local live, err = kernel.computeManifestHash()", verify, true)
  local refuse = init:find('return false, "no anchored hash', verify, true)
  test("an unanchored machine leaves before anything is hashed",
    verify and refuse and hash and refuse < hash)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
