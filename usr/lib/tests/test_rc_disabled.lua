-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: rc.d disabled-by-default services    ║
-- ║  A `<name>.disabled` marker (written by pkg.install for ║
-- ║  defaultState="disabled" packages) must REGISTER the    ║
-- ║  service but keep rc.runAll from auto-starting it. An   ║
-- ║  explicit rc.start clears the marker (persists enable). ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_rc_disabled.lua

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

-- The shared env the stub sandbox hands every service; the service writes a
-- flag into it from start() so the test can observe whether it ran.
local sharedEnv = {}
package.loaded["kernel.sandbox"] = { build = function() return sharedEnv end }
package.loaded["kernel.users"]   = { kernelSession = function() return {} end }
_G._TOS = { bootSession = {} }   -- sessionForUser(nil) returns this

-- In-memory /etc/rc.d.
local function makeFs(files)
  return {
    exists        = function(p)
      if files[p] ~= nil then return true end
      -- A path is also "present" if it's a directory holding known files.
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

local SERVICE_SRC = "return { start = function() STARTED = true end, stop = function() end }"

-- ── Disabled: registered but not started ────────────────────────────
do
  package.loaded["kernel.rc"] = nil
  local rc = require("kernel.rc")
  sharedEnv.STARTED = nil
  local files = {
    ["/etc/rc.d/mysvc.lua"]      = SERVICE_SRC,
    ["/etc/rc.d/mysvc.disabled"] = "1",
  }
  local fs = makeFs(files)
  rc.init({ fs = fs })
  rc.runAll()
  local listed = rc.list()
  local found
  for _, s in ipairs(listed) do if s.name == "mysvc" then found = s end end
  test("disabled service is registered", true, found ~= nil)
  test("disabled service did NOT start", nil, sharedEnv.STARTED)
  test("disabled service reports enabled=false", false, found and found.enabled)
  -- Explicit start runs it AND clears the marker.
  local ok = rc.start("mysvc")
  test("rc.start succeeds", true, ok)
  test("service started after rc.start", true, sharedEnv.STARTED)
  test("marker cleared after start", nil, files["/etc/rc.d/mysvc.disabled"])
end

-- ── The restart supervisor must NOT resurrect a disabled service ────
-- Regression (emulator, 2026-07): rshd ships disabled but is a
-- restart=true daemon; rc.supervise saw restart+not-running and started
-- it ~30s after boot, defeating the security default. supervise must skip
-- a disabledAtBoot service; after a manual start it may restart on crash.
do
  package.loaded["kernel.rc"] = nil
  local rc = require("kernel.rc")
  sharedEnv.STARTED = nil
  local files = {
    ["/etc/rc.d/rshd.lua"]      = "return { restart = true, "
      .. "start = function() STARTED = true end, stop = function() end }",
    ["/etc/rc.d/rshd.disabled"] = "1",
  }
  local fs = makeFs(files)
  rc.init({ fs = fs })
  rc.runAll()
  test("disabled restart-daemon did NOT start at boot", nil, sharedEnv.STARTED)
  rc.supervise()  -- the ~30s tick
  test("supervise did NOT resurrect the disabled daemon", nil, sharedEnv.STARTED)
  -- After a manual start, a crash IS restarted (disabledAtBoot cleared).
  rc.start("rshd")
  test("manual start runs it", true, sharedEnv.STARTED)
  sharedEnv.STARTED = nil
  -- Simulate a crash: mark not running, then supervise should restart.
  for _, s in ipairs(rc.list()) do end   -- (list is a copy; poke internal via stop/start)
  rc.stop("rshd")           -- running=false but NOT disabledAtBoot
  -- stop() sets running=false; supervise sees restart=true, not disabled → restart
  rc.supervise()
  test("supervise DOES restart an operator-enabled crashed daemon",
    true, sharedEnv.STARTED)
end

-- ── Enabled (no marker): auto-starts at boot ────────────────────────
do
  package.loaded["kernel.rc"] = nil
  local rc = require("kernel.rc")
  sharedEnv.STARTED = nil
  local files = { ["/etc/rc.d/autosvc.lua"] = SERVICE_SRC }
  rc.init({ fs = makeFs(files) })
  rc.runAll()
  test("unmarked service auto-starts", true, sharedEnv.STARTED)
end

-- ── pkg marker-path derivation (pure) ───────────────────────────────
-- Mirrors the stem match in pkg.install / the install picker.
local function rcStem(path) return path:match("^/etc/rc%.d/(.+)%.lua$") end
test("clusterd stem", "clusterd", rcStem("/etc/rc.d/clusterd.lua"))
test("cluster-manager stem", "cluster-manager", rcStem("/etc/rc.d/cluster-manager.lua"))
test("non-rc.d path no stem", nil, rcStem("/usr/lib/clusterd.lua"))

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
