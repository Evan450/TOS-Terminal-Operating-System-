-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Cluster Worker Default-Deny (CR-3) ║
-- ║  cworker.setDomainId must refuse to bind without a    ║
-- ║  shared secret installed first.                       ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_worker_secret.lua
--
-- cluster_worker.lua requires computer/component/serialize/cluster at
-- load time; we preload mocks (no modems => no real I/O) and the real
-- cluster module (for workerPort/TIMING).

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

package.loaded["computer"] = { uptime = function() return 0 end }
package.loaded["component"] = {
  list  = function() return function() return nil end end,
  proxy = function() return nil end,
}
package.loaded["kernel.serialize"] = {
  encode = function() return "" end,
  decode = function() return nil end,
  compact = function() return "" end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_cluster_worker_secret.lua"
local base = here:gsub("[^/\\]*$", "")
-- The cluster protocol core + worker bridge moved out of the base kernel
-- into the optional cluster package (TOS-Extras). Load them from there.
local CLDIR = "TOS-Extras/cluster/manager-skeleton/usr/lib/cluster/"
local function loadCl(file)
  for _, p in ipairs({ base .. "../../../../" .. CLDIR .. file,
      CLDIR .. file, "../" .. CLDIR .. file }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
  return nil
end

-- Preload the real cluster module so worker.lua's require("cluster.protocol")
-- resolves it.
local cluster = loadCl("protocol.lua")
if cluster then package.loaded["cluster.protocol"] = cluster end

local cworker = loadCl("worker.lua")
if not cworker or not cluster then
  print("FAIL: could not load cluster_worker.lua / cluster.lua")
  print("Results: 0 passed, 1 failed")
  print("*** TESTS FAILED ***")
  return false
end

cworker.init({ log = nil, event = nil })

print("=== Cluster Worker Default-Deny Tests ===")
print()

-- No secret yet: binding must be refused.
local okBind1 = cworker.setDomainId(0)
test("bind without secret refused", false, okBind1)

-- A too-short secret is rejected by setSecret.
test("setSecret('short') rejected", false, (cworker.setSecret("short")))

-- A valid secret installs.
test("setSecret(16+ bytes) accepted", true, (cworker.setSecret("0123456789abcdef!")))

-- Now binding succeeds.
local okBind2 = cworker.setDomainId(0)
test("bind with secret accepted", true, okBind2)
test("workerPort set after bind", true, type(cworker.workerPort()) == "number")

-- Invalid domain id still rejected even with a secret.
test("invalid domain id rejected", false, (cworker.setDomainId(-1)))

cworker.stop()

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
