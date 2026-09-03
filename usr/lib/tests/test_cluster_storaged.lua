-- ╔══════════════════════════════════════════════════════════╗
-- ║  Unit Test: cluster-storaged — namespace enforcement       ║
-- ║                                                            ║
-- ║  The Storage Node's ACL wiring: peer address → writer       ║
-- ║  identity → §4.6 canWrite. store.lua deliberately does NOT  ║
-- ║  check who may write where, so if this join is wrong there  ║
-- ║  is nothing behind it — the whole namespace model is this   ║
-- ║  one function composition.                                  ║
-- ║                                                            ║
-- ║  Uses the REAL cluster.protocol.canWrite, shared with the   ║
-- ║  Manager, so the test fails if the two ever diverge.        ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_storaged.lua

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

package.loaded["computer"] = { uptime = function() return 0 end }
package.loaded["filesystem"] = { exists = function() return false end }
package.loaded["kernel.fs"] = package.loaded["filesystem"]
package.loaded["event"] = { interval = function() end, cancel = function() end }
package.loaded["kernel.event"] = package.loaded["event"]
package.loaded["kernel.serialize"] = {
  encode = function() return "" end, decode = function() return nil end,
}
package.loaded["kernel.log"] = { info = function() end, warn = function() end,
  error = function() end }
package.loaded["log"] = package.loaded["kernel.log"]
package.loaded["cluster.store"] = { init = function() return true end }

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

local cproto = loadRel("manager-skeleton/usr/lib/cluster/protocol.lua")
local storaged = loadRel("storage-skeleton/usr/lib/cluster-storaged.lua")

if not (cproto and storaged) then
  print("FAIL: could not load modules (cproto=" .. tostring(cproto ~= nil)
    .. " storaged=" .. tostring(storaged ~= nil) .. ")")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

local MASTER, MGR3, MGR7, STRANGER = "addr-master", "addr-m3", "addr-m7", "addr-who"
storaged._internal.setConfig({
  root = "/var/store", master = MASTER,
  managers = { [MGR3] = 3, [MGR7] = 7 },
})

print("=== cluster-storaged Tests ===")
print()

-- ── 1. Writer identity is config-declared, never self-declared ──────
print("-- writer identity --")
do
  local m = storaged.writerFor(MASTER)
  test("master resolves",        "master",  m and m.role)
  local a = storaged.writerFor(MGR3)
  test("manager resolves",       "manager", a and a.role)
  test("...with its domain_id",  3,         a and a.domain_id)
  local b = storaged.writerFor(MGR7)
  test("a second manager",       7,         b and b.domain_id)

  -- The whole namespace model turns on this: an address nobody declared
  -- has no identity, so canWrite is never even consulted for it.
  local u, err = storaged.writerFor(STRANGER)
  test("undeclared peer has no identity", nil, u)
  test("...reported as unknown_writer", "unknown_writer", err)
end

-- ── 2. §4.6, the whole table ────────────────────────────────────────
-- | namespace   | who may write                                 |
-- | job-<id>/   | Master, or the Manager assigned that job       |
-- | domain-<id>/| only the owning Manager                        |
-- | shared/     | only the Master                                |
print()
print("-- namespace rules --")
do
  local function may(addr, key)
    local w = storaged.writerFor(addr)
    if not w then return false end
    return (cproto.canWrite(w, key)) and true or false
  end

  -- shared/ is the Master's alone.
  test("master writes shared/",        true,  may(MASTER, "shared/manifest"))
  test("manager cannot write shared/", false, may(MGR3,   "shared/manifest"))

  -- domain-<id>/ belongs to exactly one Manager, and the Master is NOT
  -- exempt -- this is the rule most likely to be "helpfully" relaxed.
  test("manager writes its own domain",   true,  may(MGR3, "domain-3/scratch/x"))
  test("manager cannot write another's",  false, may(MGR3, "domain-7/scratch/x"))
  test("...nor can the other direction",  false, may(MGR7, "domain-3/scratch/x"))
  test("master cannot write a domain ns", false, may(MASTER, "domain-3/scratch/x"))

  -- job-<id>/ is the Master's in v1. §4.6's own convention says the
  -- Master writes task lists and results there, so nothing legitimate
  -- is blocked by not populating job_assignee yet.
  test("master writes job/",            true,  may(MASTER, "job-104/tasks/a1"))
  test("manager cannot write job/ yet", false, may(MGR3,   "job-104/tasks/a1"))

  -- An undeclared peer writes nowhere at all.
  test("stranger writes nothing", false, may(STRANGER, "shared/x"))
  test("...not even a domain",    false, may(STRANGER, "domain-3/x"))
end

-- ── 3. Malformed keys are refused before the ACL ────────────────────
print()
print("-- malformed keys --")
do
  local w = storaged.writerFor(MASTER)
  local function why(key) local _, r = cproto.canWrite(w, key); return r end
  test("absolute key refused",      true, why("/shared/x") ~= nil)
  test("parent-escape refused",     true, why("shared/../../etc/passwd") ~= nil)
  test("no namespace segment",      true, why("lonely") ~= nil)
  test("unknown namespace refused", true, why("wat-1/x") ~= nil)
  -- A Master is the most privileged identity there is; if traversal got
  -- through for anyone it would get through here.
  test("master cannot escape either", false,
    (cproto.canWrite(w, "shared/../domain-3/x")) and true or false)
end

-- ── 4. parseKey round-trip ──────────────────────────────────────────
print()
print("-- parseKey --")
do
  local p = cproto.parseKey("job-17/tasks/assignment-3")
  test("job ns parsed",     "job", p and p.ns)
  test("...scope",          17,    p and p.scope)
  test("...subpath",        "tasks/assignment-3", p and p.subpath)
  local d = cproto.parseKey("domain-3/scratch/partial-17")
  test("domain ns parsed",  "domain", d and d.ns)
  test("...scope",          3,        d and d.scope)
  local s = cproto.parseKey("shared/manifest")
  test("shared ns parsed",  "shared", s and s.ns)
  test("...has no scope",   nil,      s and s.scope)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
