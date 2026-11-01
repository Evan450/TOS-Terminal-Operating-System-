-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the cluster CLIs, in the sandbox the shell   ║
-- ║  actually runs them in                                         ║
-- ║                                                                ║
-- ║  /usr/bin/cluster.lua and /usr/bin/cluster-manager.lua are     ║
-- ║  PATH programs: the shell runs them through progenv, in a      ║
-- ║  sandbox. Since 8f7b12b (2026-09-11) a library a sandboxed     ║
-- ║  program requires loads INSIDE that sandbox, one instance per  ║
-- ║  sandbox, and both CLIs were written to share the running      ║
-- ║  daemon's state. So neither loaded at all, and any `cluster`   ║
-- ║  command answered with a stack trace.                          ║
-- ║                                                                ║
-- ║  They reach the daemon through its ipc endpoint now, and the   ║
-- ║  tier checks moved there with them: the capability says which  ║
-- ║  program may knock, and any user can run the program. This     ║
-- ║  drives the REAL sandbox, CLI files and kernel.ipc, with the   ║
-- ║  real cluster.api bound to the real state/scheduler/jobs, at   ║
-- ║  each tier.                                                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_cli_sandbox.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function readHost(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end

local EXTRAS
for _, p in ipairs({ "../TOS-Extras/", "TOS-Extras/" }) do
  if readHost(p .. "README.md") then EXTRAS = p; break end
end
if not EXTRAS then
  print("  SKIP: TOS-Extras is not beside TOS-Dev")
  print("Results: 0 passed, 0 failed"); return true
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local MASTER  = EXTRAS .. "cluster/master-skeleton/"
local MANAGER = EXTRAS .. "cluster/manager-skeleton/"

-- A job file on the fake disk, for `cluster submit`.
local JOB = "/home/job.lua"
local JOB_SRC = 'return { tasks = {}, name = "probe" }'
local RAN_JOB = 0

package.loaded["kernel.fs"] = {
  exists = function(p) return p == JOB end,
  isDirectory = function() return false end,
  readFile = function(p) return p == JOB and JOB_SRC or nil end,
}
package.loaded["computer"] = {
  uptime = function() return 100 end, freeMemory = function() return 1e6 end,
  totalMemory = function() return 1e6 end, address = function() return "t" end,
  pushSignal = function() end, pullSignal = function() return nil end,
}
package.loaded["component"] = {
  list = function() return function() end end, proxy = function() end,
  type = function() end, isAvailable = function() return false end,
}
package.loaded["filesystem"] = { exists = function() return false end }
package.loaded["event"] = { on = function() end, interval = function() end,
  timer = function() end, cancelTimer = function() end, pull = function() end }
package.loaded["kernel.event"] = package.loaded["event"]
package.loaded["kernel.serialize"] = {
  serialize = function() return "" end, unserialize = function() return nil end,
  encode = function() return "" end, decode = function() return nil end,
}
package.loaded["kernel.log"] = { info = function() end, warn = function() end,
  error = function() end }
package.loaded["log"] = package.loaded["kernel.log"]
package.loaded["cluster.net"] = {
  sendCancel = function() end, sendAssignment = function() return true end,
  sendDrain = function() return true end,
}

local sandbox = require("kernel.sandbox")
local ipc = require("kernel.ipc")

local function lib(rel)
  return assert(load(assert(readHost(MASTER .. rel), rel), "=" .. rel))()
end

-- The daemon's side, as the kernel loader gives it: real and shared.
local state = lib("lib/cluster/state.lua")
local scheduler = lib("lib/cluster/scheduler.lua")
local jobs = lib("lib/cluster/jobs.lua")
local api = lib("lib/cluster/api.lua")
state._data = state._data or {}
state._data.managers = state._data.managers or {}
state._data.jobs = state._data.jobs or {}
local fakeClusterd = { getConfig = function() return { host_thread_budget = 8 } end }

local function caps(pkgFile)
  local m = assert(load(readHost(pkgFile), "=manifest", "t", {}))()
  -- progenv's fixed set, plus what the manifest asks for.
  local c = { ["fs.read"] = true, ["fs.write"] = true, ["compat.io"] = true }
  for _, cap in ipairs(m.capabilities or {}) do
    local facet, scope = cap:match("^([^:]+):(.+)$")
    if facet == "ipc" then c["ipc:" .. scope] = true else c[cap] = true end
  end
  return c, m
end

local TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 }

-- Run a CLI as a user of a tier. Returns ok, what it printed, what it exited with.
local function run(file, pkgFile, tier, ...)
  local out = {}
  local c = caps(pkgFile)
  local env = sandbox.build({ name = file, caps = c,
    session = { user = "t", tier = TIER[tier] },
    stdout = function(s) out[#out + 1] = tostring(s) end })
  local fn = assert(load(readHost(file), "=" .. file, "t", env))
  local stderr = {}
  if type(env.io) == "table" then
    env.io.stderr = { write = function(_, s) stderr[#stderr + 1] = s end }
  end
  local ok, err = pcall(fn, ...)
  return ok, table.concat(out, "\n"), table.concat(stderr), err
end
local function cluster(tier, ...)
  return run(MASTER .. "cluster.lua", MASTER .. "package.lua", tier, ...)
end
local function manager(tier, ...)
  return run(MANAGER .. "usr/bin/cluster-manager.lua", MANAGER .. "package.lua", tier, ...)
end

print("=== with no daemon ===")
do
  local ok, _, stderr = cluster("ADMIN", "status")
  test("it says clusterd is not running, and how to start it",
    not ok and stderr:find("service start clusterd", 1, true) ~= nil, stderr)
end

ipc.register("cluster", api.endpoint, "clusterd")

print("=== the library loaded, the daemon stopped ===")
do
  local ok, _, stderr = cluster("ADMIN", "status")
  test("the same answer", not ok and stderr:find("service start clusterd", 1, true) ~= nil, stderr)
end

api.bind(state, scheduler, jobs, fakeClusterd)

print("=== reading, as ADMIN ===")
do
  local ok, out, stderr = cluster("ADMIN", "status")
  test("cluster status runs", ok, stderr)
  test("and prints the daemon's answer", out:find("thread", 1, true) ~= nil, out)
  local okM, _, errM = cluster("ADMIN", "managers")
  test("cluster managers runs", okM, errM)
  local okJ, _, errJ = cluster("ADMIN", "jobs")
  test("cluster jobs runs", okJ, errJ)
  local okL, _, errL = cluster("ADMIN", "log")
  test("cluster log runs", okL, errL)
end

print("=== the gate is the daemon's ===")
do
  local ok, _, stderr = cluster("USER", "status")
  test("a USER is refused, by name", not ok and stderr:find("need ADMIN, have USER", 1, true) ~= nil, stderr)
  local okD, _, errD = cluster("ADMIN", "drain", "1")
  test("an ADMIN may not mutate", not okD and errD:find("need ROOT, have ADMIN", 1, true) ~= nil, errD)
  -- A program that skips the CLI gets the same answer.
  local res = api.endpoint({ tier = 1 }, "status")
  test("calling the endpoint directly changes nothing", res == false)
  local a, b = api.endpoint({ tier = 3 }, "bind")
  test("a name not in the table cannot be reached, even by root",
    a == false and tostring(b):find("unknown call", 1, true) ~= nil, b)
  local c = api.endpoint({ tier = 3 }, "endpoint")
  test("nor the endpoint itself", c == false)
end

print("=== submitting a job ===")
do
  local ok, _, stderr = cluster("ADMIN", "submit", JOB)
  test("an ADMIN is refused before the file is touched",
    not ok and stderr:find("need ROOT", 1, true) ~= nil, stderr)
  local src = readHost(MASTER .. "cluster.lua")
  local a = src:find('ipc.call("cluster", "may", "submit")', 1, true)
  local b = src:find('load(src, "=" .. path, "t")', 1, true)
  test("the daemon is asked before the file is evaluated", a and b and a < b)
end

print("=== the CLI holds only what it uses ===")
do
  local c = caps(MASTER .. "package.lua")
  test("cluster has its endpoint", c["ipc:cluster"] == true)
  test("cluster holds no network", not c.net and not c.component and not c["peripheral.modem"])
  local mc = caps(MANAGER .. "package.lua")
  test("cluster-manager has its endpoint", mc["ipc:cluster-manager"] == true)
  test("cluster-manager holds no network", not mc.net and not mc.component and not mc["peripheral.modem"])
  test("neither reaches the other's endpoint", not c["ipc:cluster-manager"] and not mc["ipc:cluster"])
end

print("=== cluster-manager ===")
do
  local ok, _, stderr = manager("ADMIN", "status")
  test("with no library loaded it says how to start",
    not ok and stderr:find("service start cluster-manager", 1, true) ~= nil, stderr)

  -- The endpoint table is the real library's; the daemon itself needs a modem.
  local src = assert(readHost(MANAGER .. "usr/lib/cluster-manager.lua"))
  local from = src:find("-- Every call the CLI may make", 1, true)
  local to = src:find("-- Registered as the library loads", from, true)
  local fake = { calls = {} }
  function fake.status() return { running = false } end
  function fake.workers() return {} end
  function fake.drain() fake.calls.drain = true; return true end
  function fake.undrain() return true end
  function fake.pair(a, b) fake.calls.pair = { a, b }; return true, "paired" end
  assert(load("local mgr = ...\n" .. src:sub(from, to - 1), "=endpoint"))(fake)
  ipc.register("cluster-manager", fake.endpoint, "cluster-manager")

  local okS, out, errS = manager("ADMIN", "status")
  test("status runs and says the daemon is stopped",
    okS and out:find("not running", 1, true) ~= nil, errS)
  local okW, outW = manager("ADMIN", "workers")
  test("workers runs", okW and outW:find("No OpenOS workers", 1, true) ~= nil, outW)
  local okU, _, errU = manager("USER", "status")
  test("a USER is refused", not okU and errU:find("need ADMIN", 1, true) ~= nil, errU)
  local okD, _, errD = manager("ADMIN", "drain")
  test("an ADMIN may not drain", not okD and errD:find("need ROOT", 1, true) ~= nil, errD)
  test("and it did not happen", not fake.calls.drain)
  local okD2 = manager("ROOT", "drain")
  test("root may", okD2 and fake.calls.drain)
  local okP, outP = manager("ROOT", "pair", "addr-long-enough-for-the-check", "CODE12345678")
  test("pair goes through the daemon, whose library holds the trust DB",
    okP and fake.calls.pair and fake.calls.pair[1] == "addr-long-enough-for-the-check", outP)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
