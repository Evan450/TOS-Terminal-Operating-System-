-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a service that needs a network is not loaded  ║
-- ║  on a machine without one                                       ║
-- ║                                                                ║
-- ║  All five base services are network daemons. On a machine     ║
-- ║  with no network card each one returned from start() at once   ║
-- ║  -- after boot had compiled and run its script, and after      ║
-- ║  20-netfsd had pulled in kernel.netfs and (as a root service)  ║
-- ║  kernel.sandbox. The boot memory profile charged ~115K to the  ║
-- ║  services stage of a machine that could use none of them, and  ║
-- ║  `service` called all four "running". A service now declares   ║
-- ║  `needs = "net"`; rc reads it without running the script and   ║
-- ║  registers it as not loaded, with the reason.                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_rc_needs.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path

local function readSrc(rel)
  for _, p in ipairs({ rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "rb")
    if f then local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n")) end
  end
end

-- A root-tier service's env comes from kernel.sandbox: count the builds,
-- so the test can see the sandbox was never needed.
local builds = 0
local sharedEnv = setmetatable({}, { __index = _G })
package.loaded["kernel.sandbox"] = { build = function() builds = builds + 1; return sharedEnv end }
package.loaded["kernel.users"]   = { kernelSession = function() return {} end,
                                     sessionFor    = function() return {} end }

local function makeFs(files)
  return {
    exists = function(p)
      if files[p] ~= nil then return true end
      local prefix = p:sub(-1) == "/" and p or (p .. "/")
      for k in pairs(files) do if k:sub(1, #prefix) == prefix then return true end end
      return false
    end,
    makeDirectory = function() return true end,
    list = function(dir)
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

local function freshRc(files, net)
  _G._TOS = { bootSession = {}, net = net }
  package.loaded["kernel.rc"] = nil
  local rc = require("kernel.rc")
  rc.init({ fs = makeFs(files) })
  return rc
end

local function byName(rc)
  local t = {}
  for _, s in ipairs(rc.list()) do t[s.name] = s end
  return t
end

-- `LOADED` counts runs of the script body, `STARTED` calls of start().
local function svc(extra)
  return "LOADED = (LOADED or 0) + 1\n"
    .. "return { start = function() STARTED = (STARTED or 0) + 1 end,\n"
    .. "  stop = function() end, restart = true, user = \"root\"" .. (extra or "") .. " }"
end

print("=== a service that needs a network ===")
print()

do -- no network
  sharedEnv.LOADED, sharedEnv.STARTED, builds = nil, nil, 0
  local files = {
    ["/etc/rc.d/netd.lua"]     = svc(', needs = "net"'),
    ["/etc/rc.d/single.lua"]   = svc(", needs = 'net'"),
  }
  local rc = freshRc(files, nil)
  rc.runAll()
  local s = byName(rc)
  test("no network: its script is never run", sharedEnv.LOADED == nil, sharedEnv.LOADED)
  test("...so a root service never builds a sandbox env", builds == 0, builds)
  test("...but it is still registered, not running",
    s.netd ~= nil and s.netd.running == false)
  test("...and the list says why", s.netd and s.netd.unavailable == "needs network hardware",
    s.netd and s.netd.unavailable)
  test("single quotes are read too", s.single and s.single.unavailable ~= nil)

  local ok, why = rc.start("netd")
  test("`service start` refuses it", ok == false)
  test("...naming the reason and the fix",
    type(why) == "string" and why:find("needs network hardware", 1, true) ~= nil
    and why:find("reboot", 1, true) ~= nil, why)
  test("...without running the script", sharedEnv.LOADED == nil, sharedEnv.LOADED)

  local sok, serr = pcall(rc.supervise)
  test("the supervisor leaves it alone", sok and byName(rc).netd.running == false, serr)
  test("...and never starts it", sharedEnv.STARTED == nil, sharedEnv.STARTED)
  test("stopping it is the ordinary 'Not running'", select(2, rc.stop("netd")) == "Not running")
end

do -- what does not count as a need
  sharedEnv.LOADED, sharedEnv.STARTED = nil, nil
  local files = {
    ["/etc/rc.d/plain.lua"]   = svc(),
    ["/etc/rc.d/comment.lua"] = '-- needs = "net"\n' .. svc(),
    ["/etc/rc.d/future.lua"]  = svc(', needs = "holoprojector"'),
  }
  local rc = freshRc(files, nil)
  rc.runAll()
  local s = byName(rc)
  test("a service with no need starts as before", s.plain and s.plain.running == true)
  test("a need written in a comment is not a need", s.comment and s.comment.running == true)
  test("an unknown need is ignored (a newer service on an older kernel)",
    s.future and s.future.running == true and s.future.unavailable == nil)
  test("all three scripts ran", sharedEnv.LOADED == 3, sharedEnv.LOADED)
end

do -- a network present
  sharedEnv.LOADED, sharedEnv.STARTED, builds = nil, nil, 0
  local rc = freshRc({ ["/etc/rc.d/netd.lua"] = svc(', needs = "net"') }, {})
  rc.runAll()
  local s = byName(rc)
  test("with a network it loads and starts", s.netd and s.netd.running == true
    and sharedEnv.LOADED == 1 and sharedEnv.STARTED == 1)
  test("...with nothing marked unavailable", s.netd and s.netd.unavailable == nil)
end

do -- the base services, as shipped
  local names = { "10-discoveryd", "20-chatrelay", "20-fileshare", "20-netfsd", "20-rshd" }
  local files = { ["/etc/rc.d/20-rshd.disabled"] = "" }
  for _, n in ipairs(names) do
    files["/etc/rc.d/" .. n .. ".lua"] = assert(readSrc("etc/rc.d/" .. n .. ".lua"), n)
  end
  builds = 0
  local rc = freshRc(files, nil)
  rc.runAll()
  local s = byName(rc)
  for _, n in ipairs(names) do
    test(n .. " is not loaded without a network",
      s[n] and s[n].unavailable == "needs network hardware" and s[n].running == false)
  end
  test("20-rshd still reads as disabled too", s["20-rshd"] and s["20-rshd"].enabled == false)
  test("no sandbox env was built for 20-netfsd", builds == 0, builds)
end

do -- what the operator sees
  local admin = readSrc("tos/shell/panels/commands/admin.lua") or ""
  test("`service` shows a not-loaded service's reason",
    admin:find('"not loaded: " .. s.unavailable', 1, true) ~= nil)
  test("...and a disabled one as disabled, not stopped",
    admin:find('s.enabled == false and "disabled"', 1, true) ~= nil)
  local diag = readSrc("tos/kernel/diag.lua") or ""
  test("diag reports it as info, not a warning",
    diag:find('"not loaded: " .. s.unavailable', 1, true) ~= nil)
end

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
