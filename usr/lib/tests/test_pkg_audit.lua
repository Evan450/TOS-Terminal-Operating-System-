-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a package under audit                        ║
-- ║                                                                ║
-- ║  Root puts one package under audit: it runs with what it       ║
-- ║  declared and every other auditable capability, and each use   ║
-- ║  of something only an undeclared one supplies is recorded,     ║
-- ║  naming the capability it would need. This builds the REAL     ║
-- ║  sandbox both ways, and holds the lines that make it safe:     ║
-- ║  legacy is never granted, the shared libraries are never        ║
-- ║  written into, the declared environment is unchanged, and only ║
-- ║  root turns it on.                                              ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_audit.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["kernel.fs"] = {
  exists = function() return false end, isDirectory = function() return false end,
  readFile = function() return nil end,
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
package.loaded["kernel.log"] = { info = function() end, warn = function() end,
  error = function() end }
package.loaded["log"] = package.loaded["kernel.log"]

local sandbox = require("kernel.sandbox")

print("=== the environment under audit ===")
print()
local used = {}
local function record(cap, name) used[#used + 1] = cap .. " " .. name end
local declared = sandbox.build({ caps = {}, pkgName = "probe" })
local env = sandbox.buildAudit({ caps = {}, pkgName = "probe" }, record)

test("a package with no caps has no component in its own sandbox", declared.component == nil)
test("under audit it has one", type(env.component) == "table")
local okL = pcall(function() return env.component.list("gpu") end)
test("and using it is recorded, not refused", okL and used[#used] == "component component.list", used[#used])

-- What legacy would hand over: raw os and io. Each sandbox builds its own safe
-- os table, so it is what is in them that counts.
-- What legacy would hand over is the host's own os and io. Under audit, io is
-- compat.io's, TOS's compat layer, which a manifest may ask for; what must
-- never appear is the real one, or os.execute.
test("legacy is never granted, under audit or not",
  (env.os == nil or (env.os ~= os and env.os.execute == nil and env.os.remove == nil))
  and (env.io == nil or (env.io ~= io and env.io.popen ~= io.popen)))
test("and legacy is not on the list", (function()
  for _, c in ipairs(sandbox.AUDITABLE) do if c == "legacy" then return false end end
  return true
end)())

local n = #used
local s = env.string.format("%d", 4)
test("what it declared runs without a record", s == "4" and #used == n)
local function count(t) local c = 0; for _ in pairs(t) do c = c + 1 end; return c end
local before = { string = count(string), math = count(math), table = count(table) }
sandbox.buildAudit({ caps = {}, pkgName = "probe2" }, record)
test("the real string, math and table libraries are unwritten",
  count(string) == before.string and count(math) == before.math and count(table) == before.table)

print()
print("=== a package that declared some ===")
print()
do
  local rec = {}
  local e = sandbox.buildAudit({ caps = { component = true }, pkgName = "half" },
    function(cap, name) rec[#rec + 1] = cap .. " " .. name end)
  pcall(function() return e.component.list("gpu") end)
  test("what it declared is not recorded", #rec == 0, rec[1])
  local plain = sandbox.build({ caps = { component = true }, pkgName = "half" })
  local same = true
  for k, v in pairs(plain) do
    if type(v) ~= type(rawget(e, k)) then same = false end
  end
  test("and everything it declared is there, as declared", same)
end

print()
print("=== the switch ===")
print()
do
  local src = io.open("tos/kernel/pkg.lua", "rb"):read("a")
  test("pkg.audit is root's", src:find('"Insufficient privileges: root required"', 1, true) ~= nil
    and src:gsub("\r\n", "\n"):match("function pkg%.audit%(.-\nend\n"):find("rootGate(opts)", 1, true) ~= nil)
  test("and drops the loaded copy, so the switch takes effect",
    src:find("pkgActive%[name%] = nil", 1) ~= nil)
  local body = src:gsub("\r\n", "\n"):match("function pkg%.audit%(.-\nend\n") or ""
  test("it lives in memory, so a reboot ends it", src:find("local auditing = {}", 1, true) ~= nil
    and #body > 0 and not body:find("write", 1, true) and not body:find("save", 1, true))
  test("a service or a driver cannot be audited",
    src:find("runs outside the sandbox, so there is nothing to audit", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
