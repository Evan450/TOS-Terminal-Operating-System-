-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `service start` runs the code on disk         ║
-- ║                                                                ║
-- ║  rc loaded /etc/rc.d once, at boot. On the headless machine:    ║
-- ║   * a service package installed after boot answered "Unknown    ║
-- ║     service" to `service start` until a reboot -- right after   ║
-- ║     the picker had said "Start service(s): ...";                ║
-- ║   * after `pkg upgrade`, `service stop` then `service start`    ║
-- ║     ran the version loaded at boot, though the upgrade says     ║
-- ║     "restart them to run the new code". Only a reboot did.     ║
-- ║  rc.start now loads the script from disk, through the same      ║
-- ║  peek, gates and sandbox boot uses -- and a name that would     ║
-- ║  leave /etc/rc.d is refused.                                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_rc_reload.lua   (from TOS-Dev)

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

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

-- Every service gets this env from the stub sandbox; start() records
-- which version of the code ran.
local sharedEnv = {}
package.loaded["kernel.sandbox"] = { build = function() return sharedEnv end }
package.loaded["kernel.users"]   = { kernelSession = function() return {} end }
_G._TOS = { bootSession = {} }

local function makeFs(files)
  return {
    exists        = function(p)
      if files[p] ~= nil then return true end
      local prefix = p:sub(-1) == "/" and p or (p .. "/")
      for k in pairs(files) do if k:sub(1, #prefix) == prefix then return true end end
      return false
    end,
    makeDirectory = function() return true end,
    list          = function(dir)
      local out = {}
      local prefix = dir:sub(-1) == "/" and dir or (dir .. "/")
      for p in pairs(files) do
        local rest = p:sub(#prefix + 1)
        if p:sub(1, #prefix) == prefix and not rest:find("/") then out[#out + 1] = rest end
      end
      table.sort(out)
      return out
    end,
    readFile  = function(p) return files[p] end,
    writeFile = function(p, d) files[p] = d; return true end,
    remove    = function(p) files[p] = nil; return true end,
  }
end

local function svc(version)
  return "return { start = function() RAN = " .. version .. " end, stop = function() end }"
end

print("=== `service start` runs the code on disk ===")

package.loaded["kernel.rc"] = nil
local rc = require("kernel.rc")
local files = {
  ["/etc/rc.d/upsvc.lua"] = svc(1),
  ["/etc/rc.d/gone.lua"]  = svc(1),
  ["/etc/rc.d/plain.lua"] = "PLAIN = (PLAIN or 0) + 1",
}
rc.init({ fs = makeFs(files) })
rc.runAll()

-- An upgrade replaces the file; stop and start must run the new one.
test("boot started the service as installed", 1, sharedEnv.RAN)
rc.stop("upsvc")
files["/etc/rc.d/upsvc.lua"] = svc(2)
local ok, why = rc.start("upsvc")
test("start after an upgrade succeeds", true, ok)
test("...and runs the NEW code", 2, sharedEnv.RAN)

-- A package installed after boot.
files["/etc/rc.d/late.lua"] = svc(7)
sharedEnv.RAN = nil
ok, why = rc.start("late")
test("a service installed after boot can be started", true, ok)
test("...and its code runs", 7, sharedEnv.RAN)
local listed = false
for _, s in ipairs(rc.list()) do if s.name == "late" then listed = s.running end end
test("...and `service` lists it running", true, listed)

-- Its package removed: the file is gone, so it must not start.
rc.stop("gone")
files["/etc/rc.d/gone.lua"] = nil
sharedEnv.RAN = nil
ok, why = rc.start("gone")
test("a service whose file is gone does not start", false, ok)
test("...and nothing ran", nil, sharedEnv.RAN)

-- A plain script is not a service.
ok, why = rc.start("plain")
test("a plain rc.d script is not started as a service", false, ok)

-- #SEC: the name is a path inside /etc/rc.d, never outside it.
files["/tmp/x.lua"] = "return { start = function() ESCAPED = true end, stop = function() end }"
for _, bad in ipairs({ "../tmp/x", "../../tmp/x", "/tmp/x", "a/../../tmp/x" }) do
  ok, why = rc.start(bad)
  test("refuses the name " .. bad, false, ok)
end
test("...and none of them ran", nil, sharedEnv.ESCAPED)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
