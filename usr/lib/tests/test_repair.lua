-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.repair (one-shot self-repair)     ║
-- ║                                                            ║
-- ║  Fix what's mechanically safe (orphan temps, stale         ║
-- ║  /var/run, oversized logs, corrupt boot.cfg), REPORT what  ║
-- ║  isn't (corrupt users.dat, missing critical files), and    ║
-- ║  never throw — every step is pcall'd.                     ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_repair.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end }
package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local serialize = require("kernel.serialize")
local repair = require("kernel.repair")

print("=== kernel.repair Tests ===")
print()

-- In-memory fake fs: files = { [path] = content }; dirs implied.
local function fakeFS(files)
  local F = { files = files }
  function F.exists(p) return files[p] ~= nil end
  function F.readFile(p) return files[p] end
  function F.writeFile(p, d) files[p] = d; return true end
  F.writeFileAtomic = F.writeFile
  function F.remove(p)
    if files[p] == nil then return false end
    files[p] = nil; return true
  end
  function F.size(p) return files[p] and #files[p] or 0 end
  function F.list(dir)
    local out, seen = {}, {}
    local prefix = dir:sub(-1) == "/" and dir or (dir .. "/")
    for p in pairs(files) do
      if p:sub(1, #prefix) == prefix then
        local rest = p:sub(#prefix + 1)
        local head = rest:match("^([^/]+)/")
        local name = head and (head .. "/") or rest
        if not seen[name] then seen[name] = true; out[#out + 1] = name end
      end
    end
    return out
  end
  F.recoverAtomicCalls = 0
  function F.recoverAtomic() F.recoverAtomicCalls = F.recoverAtomicCalls + 1; return 0 end
  return F
end

-- ── A healthy system: nothing fixed, nothing warned ────────────────
do
  local fs = fakeFS({
    ["/etc/boot.cfg"] = serialize.encode({ profile = "normal" }),
    ["/etc/tos.cfg"] = serialize.encode({ hostname = "box" }),
    ["/etc/critical.bak"] = serialize.encode({ "/init.lua" }),
    ["/init.lua"] = "-- present",
    ["/var/run/pwrstate"] = "R\n1\n0",
    ["/var/log/kernel.log"] = "line\n",
  })
  local rep = repair.run({ fs = fs, serialize = serialize })
  eq("healthy: nothing fixed", 0, rep.fixed)
  eq("healthy: nothing warned", 0, rep.warned)
  test("healthy: atomic sweep ran", fs.recoverAtomicCalls == 1)
  test("healthy: pwrstate kept", fs.files["/var/run/pwrstate"] ~= nil)
end

-- ── The broken box: everything at once ─────────────────────────────
do
  local bigLog = string.rep("x", 40 * 1024) .. "\nLAST-LINE\n"
  local fs = fakeFS({
    ["/etc/boot.cfg"] = "this is not a serialized table {{{",
    ["/etc/users.dat"] = "ALSO corrupt %%%",
    ["/etc/tos.cfg"] = serialize.encode({ ok = true }),
    ["/etc/critical.bak"] = serialize.encode({ "/init.lua", "/tos/kernel/init.lua" }),
    ["/init.lua"] = "-- present",
    -- /tos/kernel/init.lua deliberately MISSING
    ["/etc/users.dat.tos-tmp"] = "orphan temp",
    ["/var/pkg/half.tos-tmp"] = "orphan temp",
    ["/var/run/pwrstate"] = "R\n1\n0",
    ["/var/run/session"] = "stale-token",
    ["/var/run/old.pid"] = "42",
    ["/var/log/kernel.log"] = bigLog,
  })
  local rep = repair.run({ fs = fs, serialize = serialize })

  test("fixes counted (temps+runstate+log+bootcfg)", rep.fixed >= 4)
  -- boot.cfg rewritten clean and parseable now
  local newCfg = serialize.decode(fs.files["/etc/boot.cfg"] or "")
  test("corrupt boot.cfg rewritten to a valid table", type(newCfg) == "table")
  eq("...normalized to the default profile", "normal", newCfg and newCfg.profile)
  -- orphan temps removed
  test("orphan temp under /etc removed", fs.files["/etc/users.dat.tos-tmp"] == nil)
  test("orphan temp under /var/pkg removed", fs.files["/var/pkg/half.tos-tmp"] == nil)
  -- /var/run cleared except pwrstate
  test("stale session file removed", fs.files["/var/run/session"] == nil)
  test("stale pid file removed", fs.files["/var/run/old.pid"] == nil)
  test("pwrstate preserved", fs.files["/var/run/pwrstate"] ~= nil)
  -- log trimmed, tail kept
  local log = fs.files["/var/log/kernel.log"]
  test("oversized log trimmed", #log < 20 * 1024)
  test("log tail (newest entries) kept", log:find("LAST%-LINE") ~= nil)
  test("trim is marked", log:find("trimmed by self%-repair") ~= nil)
  -- report-only warnings
  local warns = table.concat(rep.lines, "\n")
  test("corrupt users.dat WARNED, not touched",
    warns:find("/etc/users%.dat does not parse") ~= nil
    and fs.files["/etc/users.dat"] == "ALSO corrupt %%%")
  test("missing critical file WARNED",
    warns:find("missing critical file: /tos/kernel/init%.lua") ~= nil)
  test("warnings counted", rep.warned >= 2)
end

-- ── Degenerate inputs never throw ───────────────────────────────────
do
  local ok1, rep1 = pcall(repair.run, { fs = nil })
  test("no fs: returns a warning, doesn't throw", ok1 and rep1.warned == 1)
  local ok2, rep2 = pcall(repair.run, { fs = fakeFS({}) })
  test("empty fs: clean run, no throw", ok2 and rep2.fixed == 0)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
