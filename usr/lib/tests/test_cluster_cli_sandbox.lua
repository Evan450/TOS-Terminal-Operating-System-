-- ╔══════════════════════════════════════════════════════════════╗
-- ║  [KNOWN GAP] The cluster operator CLIs, in the sandbox the     ║
-- ║  shell actually runs them in                                   ║
-- ║                                                                ║
-- ║  /usr/bin/cluster.lua (cluster-master) and /usr/bin/           ║
-- ║  cluster-manager.lua are PATH programs: the shell runs them    ║
-- ║  through progenv, in a sandbox with fs.read, fs.write and      ║
-- ║  compat.io. Since 8f7b12b (2026-09-11) a library a sandboxed   ║
-- ║  program requires loads INSIDE that sandbox, one instance per  ║
-- ║  sandbox. Both CLIs were written for the opposite: cluster.api ║
-- ║  is "an in-process API ... they share address space" with the  ║
-- ║  running daemon. So neither CLI loads at all (their libraries  ║
-- ║  require `computer`, which a sandbox without the component     ║
-- ║  cap refuses), and if one did it would see a fresh, unbound    ║
-- ║  copy of the daemon's state, not the daemon.                   ║
-- ║                                                                ║
-- ║  Recorded, not endorsed: the fix is a decision about what a    ║
-- ║  trusted service package's own CLI may reach (TODO, "THE       ║
-- ║  CLUSTER CLIs CANNOT RUN IN THE SANDBOX THEY ARE GIVEN"). This ║
-- ║  pins today's behaviour, driving the REAL sandbox and the REAL ║
-- ║  CLI and library files, so the fix fails here and this file   ║
-- ║  gets rewritten to pin the working CLI instead.               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_cli_sandbox.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
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
-- The installed layout, mapped onto the source tree (build-disk's map).
local MAP = {
  ["/usr/bin/cluster.lua"]          = MASTER .. "cluster.lua",
  ["/usr/lib/clusterd.lua"]         = MASTER .. "clusterd.lua",
  ["/usr/bin/cluster-manager.lua"]  = MANAGER .. "usr/bin/cluster-manager.lua",
  ["/usr/lib/cluster-manager.lua"]  = MANAGER .. "usr/lib/cluster-manager.lua",
  ["/usr/lib/cluster/protocol.lua"] = MANAGER .. "usr/lib/cluster/protocol.lua",
  ["/usr/lib/cluster/worker.lua"]   = MANAGER .. "usr/lib/cluster/worker.lua",
}
for _, n in ipairs({ "api", "jobs", "net", "pair", "scheduler", "state", "store_client" }) do
  MAP["/usr/lib/cluster/" .. n .. ".lua"] = MASTER .. "lib/cluster/" .. n .. ".lua"
end
package.loaded["kernel.fs"] = {
  exists = function(p) return MAP[p] ~= nil end,
  isDirectory = function() return false end,
  readFile = function(p) return MAP[p] and readHost(MAP[p]) end,
}
package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 1e6 end,
  totalMemory = function() return 1e6 end, address = function() return "t" end,
  pushSignal = function() end, pullSignal = function() return nil end,
}
package.loaded["component"] = {
  list = function() return function() end end, proxy = function() end,
  type = function() end, isAvailable = function() return false end,
}
local sandbox = require("kernel.sandbox")

-- progenv's PATH-program caps, which is what the shell gives /usr/bin.
local function runPath(target, ...)
  local env = sandbox.build({ name = target,
    caps = { ["fs.read"] = true, ["fs.write"] = true, ["compat.io"] = true },
    stdout = function() end })
  local fn, err = load(readHost(MAP[target]), "=" .. target, "t", env)
  if not fn then return false, "compile: " .. tostring(err) end
  return pcall(fn, ...)
end

print("=== [known gap] the cluster CLIs in their sandbox ===")
print()

local REFUSED = "module 'computer' is not available to sandboxed code"
for _, case in ipairs({
  { "/usr/bin/cluster.lua", "status" },
  { "/usr/bin/cluster-manager.lua", "status" },
}) do
  local ok, err = runPath(case[1], case[2])
  test("[known gap] " .. case[1] .. " " .. case[2] .. " cannot load its library ("
    .. tostring(err):gsub("^.-sandbox: ", "sandbox: "):sub(1, 90) .. ")",
    ok == false and tostring(err):find(REFUSED, 1, true) ~= nil)
end

-- And the reason it cannot simply be granted `component`: the CLI would
-- then load a PRIVATE cluster.api whose state no daemon ever bound.
do
  local env = sandbox.build({ name = "probe",
    caps = { ["fs.read"] = true, ["fs.write"] = true, ["compat.io"] = true, component = true } })
  local okA, api = pcall(env.require, "cluster.api")
  local okS, sErr = false, nil
  if okA and type(api) == "table" and type(api.status) == "function" then
    okS, sErr = pcall(api.status)
  end
  test("[known gap] even with `component`, the CLI's cluster.api is its own unbound copy ("
    .. tostring(sErr):sub(1, 70) .. ")",
    okA and okS == false and tostring(sErr):find("not running", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
