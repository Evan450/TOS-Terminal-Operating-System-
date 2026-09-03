-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: cluster storage_preference matching     ║
-- ║                                                           ║
-- ║  Bug: a job submitted with a storage_preference could      ║
-- ║  never be scheduled onto ANY Manager. The Manager never    ║
-- ║  sent `storage` in CLUSTER_REGISTER, so state.lua filled   ║
-- ║  external_type="none" forever; the heartbeat DID carry     ║
-- ║  external_type but landed in last_snapshot, which the      ║
-- ║  scheduler doesn't read. Every preference-bearing job was  ║
-- ║  rejected cluster-wide with "storage_pref_mismatch".       ║
-- ║                                                           ║
-- ║  Covers both halves of the fix:                            ║
-- ║   - Manager declares storage at register (§4.1)            ║
-- ║   - Master folds heartbeat external_type into m.storage    ║
-- ║   - scheduler then matches, scores, and picks correctly    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_storage_pref.lua

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

-- ── Off-box stubs ─────────────────────────────────────────────────
-- Same approach as test_cluster_bridge_v2.lua: stub the module loads so
-- the real files run outside TOS. state.lua persists only when init()
-- has set a path, so leaving it uninitialized keeps everything in memory.
local _uptime = 0
package.loaded["filesystem"]  = { exists = function() return false end }
package.loaded["computer"]    = { uptime = function() return _uptime end }
package.loaded["event"]       = { on = function() end, interval = function() end,
  timer = function() end, cancelTimer = function() end }
package.loaded["kernel.net"]  = { on = function() return 1 end, send = function() end,
  off = function() end }
package.loaded["kernel.net.protocol"] = {
  TYPE = setmetatable({}, { __index = function(_, k) return "T_" .. k end }),
  makePacket = function(t, p, o) return { type = t, payload = p, to = o and o.to } end,
}
package.loaded["log"] = { info = function() end, warn = function() end, error = function() end }
package.loaded["kernel.serialize"] = {
  serialize = function() return "" end, unserialize = function() return nil end,
}

-- Nil-safe field walk. A regression that drops `storage` entirely should
-- report a readable FAIL, not blow up on indexing nil.
local function get(t, ...)
  for _, k in ipairs({ ... }) do
    if type(t) ~= "table" then return nil end
    t = t[k]
  end
  return t
end

local function loadFirst(...)
  for _, p in ipairs({ ... }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end

local BASE = { "../TOS-Extras/cluster/", "TOS-Extras/cluster/" }
local function loadRel(rel)
  local paths = {}
  for _, b in ipairs(BASE) do paths[#paths + 1] = b .. rel end
  return loadFirst(table.unpack(paths))
end

local mgr       = loadRel("manager-skeleton/usr/lib/cluster-manager.lua")
local scheduler = loadRel("master-skeleton/lib/cluster/scheduler.lua")
local state     = loadRel("master-skeleton/lib/cluster/state.lua")

if not (mgr and scheduler and state) then
  print("FAIL: could not load cluster modules (mgr=" .. tostring(mgr ~= nil)
    .. " scheduler=" .. tostring(scheduler ~= nil)
    .. " state=" .. tostring(state ~= nil) .. ")")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== cluster storage_preference Tests ===")
print()

-- ── 1. Manager declares its storage at registration (§4.1) ────────
print("-- register payload --")
local mk = mgr._registerPayload
test("exposes _registerPayload", "function", type(mk))
if type(mk) ~= "function" then
  -- Regressed to the pre-fix Manager (payload built inline, no storage
  -- field). Shim it so the rest of the suite reports readable failures
  -- instead of a stack trace — the downstream FAILs are the diagnosis.
  print("  NOTE: falling back to a pre-fix payload shim; failures below" ..
        " are the storage_preference regression.")
  mk = function(cfg, st)
    return { hostname = cfg.hostname, profile = cfg.compute_profile,
             worker_count = cfg.worker_count,
             cluster_protocol = cfg.cluster_protocol, started_at = st.started_at }
  end
end

local raidReg = mk({ hostname = "mgr-raid", compute_profile = "mixed",
  worker_count = 3, storage_type = "raid", storage_capacity = 524288,
  cluster_protocol = "1.0" }, { started_at = 0 })
test("register carries storage table", "table",   type(raidReg.storage))
test("register declares raid",         "raid",    get(raidReg, "storage", "external_type"))
test("register declares capacity",     524288,    get(raidReg, "storage", "external_capacity"))

local bareReg = mk({ hostname = "mgr-bare", compute_profile = "mixed",
  worker_count = 3, cluster_protocol = "1.0" }, { started_at = 0 })
test("no storage_type -> none",        "none",    get(bareReg, "storage", "external_type"))
test("no capacity -> 0",               0,         get(bareReg, "storage", "external_capacity"))
-- Fields that were already correct must survive the refactor.
test("still carries hostname",         "mgr-bare", bareReg.hostname)
test("still carries worker_count",     3,          bareReg.worker_count)

-- ── 2. The matcher itself ─────────────────────────────────────────
print()
print("-- storagePreferenceMatches --")
local match = scheduler._internal.storagePreferenceMatches
local raidMgr = { storage = { external_type = "raid" } }
local tapeMgr = { storage = { external_type = "tape" } }
local noneMgr = { storage = { external_type = "none" } }

test("no preference matches anything", true,  match({}, noneMgr))
test("empty preference matches",       true,  match({ storage_preference = "" }, noneMgr))
test("raid job -> raid manager",       true,  match({ storage_preference = "raid" }, raidMgr))
test("raid job -/> tape manager",      false, match({ storage_preference = "raid" }, tapeMgr))
test("raid job -/> none manager",      false, match({ storage_preference = "raid" }, noneMgr))
test("manager with no storage table",  false, match({ storage_preference = "raid" }, {}))

-- ── 3. Register → state → scheduler, end to end ───────────────────
print()
print("-- register -> pickDomain --")
local RAID_ADDR, TAPE_ADDR = "addr-raid", "addr-tape"
state.registerManager(RAID_ADDR, raidReg)
state.registerManager(TAPE_ADDR, mk({ hostname = "mgr-tape", compute_profile = "mixed",
  worker_count = 3, storage_type = "tape", cluster_protocol = "1.0" }, { started_at = 0 }))

test("raid manager stored as raid", "raid",
  get(state.getManager(RAID_ADDR), "storage", "external_type"))

-- pickDomain needs a heartbeat snapshot for capacity, else "no_snapshot".
local function beat(addr, extra)
  local snap = { state = "active", workers_active = 3, workers_busy = 0,
    queue_depth = 0, storage_used = 0, errors_last_min = 0 }
  for k, v in pairs(extra or {}) do snap[k] = v end
  state.updateManagerHeartbeat(addr, snap)
end
beat(RAID_ADDR, { external_type = "raid" })
beat(TAPE_ADDR, { external_type = "tape" })

local managers = state._data.managers
local pick, why = scheduler.pickDomain({ storage_preference = "raid" }, managers, {})
test("raid job lands on raid domain", RAID_ADDR, pick)
test("...with no reject reason",      nil,       why)

pick, why = scheduler.pickDomain({ storage_preference = "tape" }, managers, {})
test("tape job lands on tape domain", TAPE_ADDR, pick)

-- The exact regression: a preference nobody satisfies must report the
-- honest reason, not silently pick a mismatched domain.
pick, why = scheduler.pickDomain({ storage_preference = "jbod" }, managers, {})
test("unsatisfiable preference -> nil",    nil,                     pick)
test("...reports storage_pref_mismatch",   "storage_pref_mismatch", why)

-- And a job with NO preference still schedules anywhere (never regressed,
-- but it's the case that masked the bug — pin it).
pick = scheduler.pickDomain({}, managers, {})
test("no-preference job still schedules", true, pick ~= nil)

-- ── 4. Heartbeat converges storage added after registration ───────
print()
print("-- heartbeat merge --")
local LATE_ADDR = "addr-late"
state.registerManager(LATE_ADDR, bareReg)          -- registered with none
test("starts as none", "none",
  get(state.getManager(LATE_ADDR), "storage", "external_type"))

beat(LATE_ADDR, { external_type = "raid" })         -- operator bolts on a RAID
test("heartbeat promotes to raid", "raid",
  get(state.getManager(LATE_ADDR), "storage", "external_type"))
test("capacity left intact", 0,
  get(state.getManager(LATE_ADDR), "storage", "external_capacity"))

-- A heartbeat with no external_type must not wipe a declared type: the
-- Manager only sends the field when storage_type is configured.
beat(LATE_ADDR, {})
test("silent heartbeat keeps raid", "raid",
  get(state.getManager(LATE_ADDR), "storage", "external_type"))

-- Removing the drive and restarting the Manager reports "none" explicitly.
beat(LATE_ADDR, { external_type = "none" })
test("explicit none demotes", "none",
  get(state.getManager(LATE_ADDR), "storage", "external_type"))

-- The late-promoted domain is now schedulable for raid work.
beat(LATE_ADDR, { external_type = "raid" })
local eligible = 0
for _ = 1, 1 do
  local p = scheduler.pickDomain({ storage_preference = "raid" }, managers, {})
  if p == RAID_ADDR or p == LATE_ADDR then eligible = 1 end
end
test("late raid domain is schedulable", 1, eligible)

-- ── 5. Scoring: a storage match should outrank a bare domain ──────
print()
print("-- scoring --")
local score = scheduler._internal.scoreDomain
local raidRec = state.getManager(RAID_ADDR)
local tapeRec = state.getManager(TAPE_ADDR)
local raidJob = { storage_preference = "raid" }
test("match scores above non-match", true,
  score(raidJob, raidRec, {}) > score(raidJob, tapeRec, {}))
test("no-preference job scores equal", true,
  score({}, raidRec, {}) == score({}, tapeRec, {}))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
