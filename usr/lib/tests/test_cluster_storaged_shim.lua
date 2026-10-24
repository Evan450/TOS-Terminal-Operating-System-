-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: the Storage Node's rc.d shim, under the REAL rc.lua     ║
-- ║                                                              ║
-- ║  The daemon has its own tests (storage-skeleton/). This is the ║
-- ║  last seam: the shim rc actually loads at boot. It used to       ║
-- ║  claim the kernel-tier user, which rc grants to four hard-coded    ║
-- ║  services only -- so every boot logged a "refusing kernel-tier       ║
-- ║  service" warning and demoted it -- and wrapped its require in a      ║
-- ║  pcall, so a daemon that failed to load registered as running and       ║
-- ║  did nothing at all.                                                     ║
-- ║                                                                           ║
-- ║  Drives the real kernel/rc.lua over the real shipped shim, with the         ║
-- ║  sandbox stubbed as test_rc_peek_decay does.                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_storaged_shim.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function has(s, sub) return type(s) == "string" and s:find(sub, 1, true) ~= nil end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local function readShim()
  for _, p in ipairs({ "../TOS-Extras/cluster/storage-skeleton/etc/rc.d/cluster-storaged.lua",
                       "TOS-Extras/cluster/storage-skeleton/etc/rc.d/cluster-storaged.lua" }) do
    local h = io.open(p, "rb")
    if h then local s = h:read("*a"); h:close(); return s end
  end
end

local src = readShim()
if not src then
  print("FAIL: could not find the shim"); print("Results: 0 passed, 1 failed")
  print("*** TESTS FAILED ***"); return false
end

local clock = 0
package.loaded["computer"] = { uptime = function() return clock end }
package.loaded["kernel.users"] = { kernelSession = function() return {} end,
                                    sessionFor = function() return {} end }
local daemonCalls = { start = 0, stop = 0 }
local daemon = {
  start = function() daemonCalls.start = daemonCalls.start + 1; return true end,
  stop  = function() daemonCalls.stop  = daemonCalls.stop  + 1; return true end,
}
local requested
package.loaded["kernel.sandbox"] = { build = function()
  return { require = function(n) requested = n; return daemon end }
end }

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
      local out, prefix = {}, dir:sub(-1) == "/" and dir or (dir .. "/")
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

local function boot(shimSrc, hasNet)
  _G._TOS = { bootSession = {}, net = hasNet and {} or nil }
  daemonCalls.start, daemonCalls.stop, requested = 0, 0, nil
  local warnings = {}
  package.loaded["kernel.rc"] = nil
  local rc = require("kernel.rc")
  rc.init({
    fs = makeFs({ ["/etc/rc.d/cluster-storaged.lua"] = shimSrc }),
    log = { info = function() end, debug = function() end, error = function() end,
            warn = function(_, m) warnings[#warnings + 1] = m end },
  })
  rc.runAll()
  for _, s in ipairs(rc.list()) do
    if s.name == "cluster-storaged" then return s, warnings, rc end
  end
  return nil, warnings, rc
end

print("=== cluster-storaged rc.d shim ===")
print()

do
  local svc, warnings = boot(src, true)
  test("the shim registers as a service", svc ~= nil)
  test("...and rc started the daemon at boot", daemonCalls.start == 1)
  test("...through the library the package installs", requested == "cluster-storaged")
  test("...and it is running", svc and svc.running == true)
  test("it is supervised (restart on crash)", svc and svc.restart == true)
  local noisy
  for _, w in ipairs(warnings) do if has(w, "kernel-tier") then noisy = w end end
  test("rc logs no kernel-tier refusal for it (that claim is for four services)", noisy == nil)
  test("it holds rc's default caps (the library needs none of its own)",
    svc and svc.caps and svc.caps.net and svc.caps.component)
end

do
  local svc = boot(src, false)
  test("with no network card it is registered but never started",
    svc ~= nil and daemonCalls.start == 0)
  test("...and rc says why", svc and has(svc.unavailable, "network"))
end

do
  --! A daemon that cannot be loaded has to surface at registration. Under
  --! the old pcall'd shim it registered, ran start() on nothing, and read
  --! as healthy.
  package.loaded["kernel.sandbox"] = { build = function()
    return { require = function() error("module 'cluster-storaged' not found") end }
  end }
  local svc = boot(src, true)
  test("a daemon that fails to load is NOT reported as a running service",
    svc == nil or svc.running ~= true)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
