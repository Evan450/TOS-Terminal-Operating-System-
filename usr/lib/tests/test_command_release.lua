-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: command categories can be GIVEN BACK        ║
-- ║                                                                ║
-- ║  Loading was already lazy. Nothing ever unloaded: once a       ║
-- ║  category was require()d it sat in package.loaded for the      ║
-- ║  life of the boot. The three of them are 268 KB of SOURCE      ║
-- ║  (admin 112K, core 100K, extras 56K) before Lua compiles       ║
-- ║  them, and anything that iterates the command table -- help,   ║
-- ║  tab-completion, the launcher, via __pairs -- pulls in all     ║
-- ║  three at once.                                                ║
-- ║                                                                ║
-- ║  So a box that ran `help` once carried all three for the rest  ║
-- ║  of the session, and the reported symptom was `help` itself    ║
-- ║  saying "running in rescue mode: the full listing needs        ║
-- ║  memory that is not free".                                     ║
-- ║                                                                ║
-- ║  Eviction is only safe because loading is lazy AND idempotent: ║
-- ║  the cost of being wrong is a reload, not a missing command.   ║
-- ║  That is the property this file exists to hold.                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_command_release.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_command_release.lua"
local base = here:gsub("[^/\\]*$", "")
local root
for _, pre in ipairs({ base .. "../../../", "", "TOS-Dev/" }) do
  local h = io.open(pre .. "tos/shell/panels/commands.lua", "rb")
  if h then h:close(); root = pre; break end
end
if not root then
  print("FAIL: could not locate commands.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

package.loaded["computer"] = {
  freeMemory = function() return 999999 end,
  totalMemory = function() return 2097152 end,
  uptime = function() return 0 end,
}
package.loaded["component"] = { list = function() return function() return nil end end }

local M = dofile(root .. "tos/shell/panels/commands.lua")

print("=== command category eviction ===")
print()

-- Stand in for the three category modules, counting loads so a reload is
-- observable rather than assumed.
local loads = {}
local NAMES = { core = "ls", admin = "flash", extras = "disk" }
for cat, name in pairs(NAMES) do
  package.preload["shell.panels.commands." .. cat] = function()
    loads[cat] = (loads[cat] or 0) + 1
    return function(C) C[name] = function() return cat end end
  end
end

local C = M.build({ T = {}, K = {} }, {})
test("dispatcher builds", type(C) == "table")
test("release is reachable for the shell to call",
  type(M._releaseCategories) == "function")

-- ── Loading is lazy, and stays that way ────────────────────────────
local _ = C.ls
test("touching a core command loads ONLY core",
  loads.core == 1 and loads.admin == nil and loads.extras == nil)
local _ = C.flash
test("touching an admin command loads admin too", loads.admin == 1)

-- ── Eviction ───────────────────────────────────────────────────────
local freed = M._releaseCategories("admin")
test("evicting returns how many categories went (" .. tostring(freed) .. ")", freed >= 1)
test("the evicted category leaves package.loaded",
  package.loaded["shell.panels.commands.core"] == nil)
test("the KEPT category stays -- never evict what was asked for",
  package.loaded["shell.panels.commands.admin"] ~= nil)

--! Dropping package.loaded alone would free nothing: the command table
--! still holds every closure the module registered, and those closures
--! are what pin the compiled chunk in memory.
--!
--! There is no handle on the inner table from out here, so this is
--! asserted through its only observable consequence, below: if the
--! closures had survived, __index would hand one straight back and the
--! category would NEVER reload. "core reloaded exactly once more" is
--! that proof. (An assertion against a table we cannot reach would have
--! been vacuous -- the shape of test that has already slipped through
--! once in this project.)

-- ── ...and the command still works, because it reloads ─────────────
local again = C.ls
test("an evicted command is still reachable", type(again) == "function")
test("...and it is the real function, not a stub", again and again() == "core")
test("...because the category reloaded exactly once more", loads.core == 2)
test("the kept category did NOT reload", loads.admin == 1)

-- ── Idempotence: releasing twice must not error or double-count ────
M._releaseCategories("core")
local okAgain = pcall(M._releaseCategories, "core")
test("releasing again is safe", okAgain)
test("core survives being the keep target", package.loaded["shell.panels.commands.core"] ~= nil)

-- ── The OOM path is what this was built for ────────────────────────
do
  local src = io.open(root .. "tos/shell/panels/commands.lua", "rb"):read("*a")
  test("an out-of-memory load evicts before retrying",
    src:find("releaseCategories(cat)", 1, true) ~= nil)
  --! Order matters: a GC cannot free a live reference, so evicting must
  --! come FIRST. Nudging the collector at a category that is still
  --! reachable frees nothing and the retry fails identically.
  local evictAt = src:find("releaseCategories(cat)", 1, true)
  local gcAt    = src:find("nudgeGC()\n      ok, mod = pcall(require", 1, true)
    or src:find("-- Still short", 1, true)
  test("...and eviction comes before the GC nudge, not after",
    evictAt and gcAt and evictAt < gcAt)
end

-- ══════════════════════════════════════════════════════════════════════
-- Does it actually FREE anything?
-- ══════════════════════════════════════════════════════════════════════
--! Every check above is behavioural, and behaviour cannot see the point
--! of the exercise. Measured instead, with a ballast payload standing in
--! for a real category's compiled chunk and its 60 closures.
--!
--! This is what the measurement established, and it is not obvious:
--! clearing package.loaded ALONE frees ZERO. The command table still
--! holds every closure the module registered, and those closures pin the
--! chunk. Only clearing both frees anything -- 600 KB of 600 KB in this
--! harness, 0 KB when the table half is disabled.
--!
--! Off-box only: collectgarbage is not exposed in the OC sandbox, so
--! this is skipped rather than failed where it is absent.
if type(collectgarbage) ~= "function" then
  print()
  print("  (skip: no collectgarbage here -- memory effect not measurable)")
else
  print()
  print("-- does eviction free memory --")
  -- A second dispatcher, so the measurement is not polluted by the
  -- reloads the tests above performed.
  local BALLAST = 300 * 1024
  local loads2 = {}
  for cat, name in pairs({ core = "ls", admin = "flash", extras = "disk" }) do
    package.loaded["shell.panels.commands." .. cat] = nil
    package.preload["shell.panels.commands." .. cat] = function()
      loads2[cat] = true
      local payload = string.rep("x", BALLAST)
      return function(tbl) tbl[name] = function() return #payload end end
    end
  end
  local C2 = M.build({ T = {}, K = {} }, {})
  -- Touch each WITHOUT keeping a reference: holding one in a local pins
  -- its payload and the measurement reads 0 for the wrong reason.
  do local f = C2.ls;    if f then end end
  do local f = C2.flash; if f then end end
  do local f = C2.disk;  if f then end end
  collectgarbage("collect"); collectgarbage("collect")
  local before = collectgarbage("count")
  M._releaseCategories("admin")
  collectgarbage("collect"); collectgarbage("collect")
  local freedKB = before - collectgarbage("count")
  local expectKB = (BALLAST * 2) / 1024

  test(string.format("evicting 2 categories frees their memory (%.0f KB of %.0f KB)",
    freedKB, expectKB), freedKB > expectKB * 0.8)
  test("...and does not free the one that was kept",
    freedKB < expectKB * 1.4)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
