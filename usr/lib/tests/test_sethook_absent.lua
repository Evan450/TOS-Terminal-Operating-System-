-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the two budgets that do not exist on OC     ║
-- ║                                                                ║
-- ║  TOS enforces two limits with debug.sethook:                   ║
-- ║    * kernel/process.lua  — the scheduler's wall-clock          ║
-- ║      preemption budget, which kills a process that will not    ║
-- ║      yield;                                                    ║
-- ║    * kernel/net/remote.lua — the remote-exec step budget and   ║
-- ║      its memory-pressure abort, wrapped around attacker-       ║
-- ║      supplied Lua from a trusted peer.                         ║
-- ║                                                                ║
-- ║  OPENCOMPUTERS DOES NOT EXPORT debug.sethook. Its machine.lua  ║
-- ║  builds the sandbox's debug table out of exactly four entries  ║
-- ║  — getinfo, traceback, getlocal, getupvalue — and withholds    ║
-- ║  sethook on purpose: the machine uses its own hook to enforce  ║
-- ║  the "too long without yielding" deadline, and guest code that ║
-- ║  could call sethook could disarm it. OpenOS, which is real OC  ║
-- ║  code, only ever calls debug.traceback.                        ║
-- ║                                                                ║
-- ║  So on every real machine both guards are skipped, and both    ║
-- ║  are skipped SILENTLY — the source reads exactly as though the ║
-- ║  budget were armed. That is the bug this file exists for: not  ║
-- ║  the missing hook, which cannot be helped, but the claim.      ║
-- ║                                                                ║
-- ║  What is pinned here is therefore honesty, not enforcement:    ║
-- ║  both modules can be ASKED whether the budget is real, they    ║
-- ║  answer correctly in both worlds, and the code still installs  ║
-- ║  the hook wherever one does exist (which is every off-box run, ║
-- ║  so the suite still exercises the enforcement path).           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sethook_absent.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_sethook_absent.lua"
local base = here:gsub("[^/\\]*$", "")

package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 4e6 end, totalMemory = function() return 8e6 end,
  pullSignal = function() return nil end, beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
  proxy = function() end, isAvailable = function() return false end }

local proc   = require("kernel.process")
local remote = require("kernel.net.remote")

print("=== debug.sethook availability Tests ===")
print()

-- ── The probes exist at all ────────────────────────────────────────
-- Without these there is no way for anything — doctor, ps, a future
-- caller — to find out whether the guarantee is real.
test("process exposes preemptionAvailable",
  type(proc.preemptionAvailable) == "function")
test("remote exposes stepBudgetAvailable",
  type(remote.stepBudgetAvailable) == "function")
if type(proc.preemptionAvailable) ~= "function"
   or type(remote.stepBudgetAvailable) ~= "function" then
  print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

-- ── This host DOES have sethook, so both must say yes ──────────────
local realDebug = debug
test("the test host really has debug.sethook (else the rest is vacuous)",
  type(debug) == "table" and type(debug.sethook) == "function")
eq("preemption reports available here", true, proc.preemptionAvailable())
eq("step budget reports available here", true, remote.stepBudgetAvailable())

-- ── Now be OpenComputers ───────────────────────────────────────────
-- machine.lua's sandbox debug table, verbatim in shape: the four entries
-- OC exports and nothing else.
debug = {
  getinfo    = realDebug.getinfo,
  traceback  = realDebug.traceback,
  getlocal   = realDebug.getlocal,
  getupvalue = realDebug.getupvalue,
}
test("the OC-shaped debug table has no sethook", debug.sethook == nil)
test("...and no gethook either", debug.gethook == nil)
eq("preemption reports UNAVAILABLE on OC", false, proc.preemptionAvailable())
eq("step budget reports UNAVAILABLE on OC", false, remote.stepBudgetAvailable())
test("traceback is still there (OC does export that one)",
  type(debug.traceback) == "function")
debug = realDebug
eq("restored: preemption available again", true, proc.preemptionAvailable())

-- ── The probe must read the LIVE global, not a boot-time snapshot ──
-- A value captured at require() time would answer for the host that
-- loaded the module, not the one running it.
do
  debug = { traceback = realDebug.traceback }
  local duringA = proc.preemptionAvailable()
  local duringB = remote.stepBudgetAvailable()
  debug = realDebug
  eq("process probe is evaluated per call", false, duringA)
  eq("remote probe is evaluated per call", false, duringB)
end

-- ── The code must still GUARD, and must still say something ────────
-- Behavioural coverage of handleExec would mean standing up net, trust,
-- protocol and a verified peer. What has to hold is narrow: the hook is
-- installed only behind a guard, and its absence is announced rather than
-- passed over in silence — silence is what let this read as a working
-- control.
print()
print("-- the guards and the notice --")
local function readFile(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local fh = io.open(p, "r")
    if fh then local s = fh:read("*a"); fh:close(); return s end
  end
end
do
  local r = readFile("tos/kernel/net/remote.lua")
  test("remote.lua is readable", r ~= nil)
  if r then
    test("the hook is installed only behind a guard",
      r:find("if debug and debug.sethook then", 1, true) ~= nil)
    test("the missing budget is warned about, once",
      r:find("warnBudgetOnce", 1, true) ~= nil)
    test("...and the warning fires on the exec path",
      r:match("handleExec.-warnBudgetOnce") ~= nil)
    test("the notice names OpenComputers as the reason",
      r:find("OpenComputers", 1, true) ~= nil)
  end
  local p = readFile("tos/kernel/process.lua")
  test("process.lua is readable", p ~= nil)
  if p then
    test("preemption is installed only behind a guard",
      p:find("type(debug) == \"table\" and debug.sethook", 1, true) ~= nil)
    -- The old comment asserted the fallback "DOES work on OC". Nothing may
    -- say that again.
    test("nothing claims the wall-clock fallback works on OC",
      p:find("DOES work on OC", 1, true) == nil)
  end
end

-- ── Corroboration from the reference tree, if it is here ───────────
-- OpenOS is real OpenComputers code. If it never reaches for sethook while
-- freely reaching for traceback, that is independent evidence that OC's
-- debug table is real but sethook-less.
--
-- Read in pure Lua from an explicit file list, NOT by shelling out to grep:
-- the first version of this ran `grep` through io.popen, which on Windows
-- silently found nothing and turned "no hits for sethook" into a PASS. A
-- check that cannot tell success from a failed lookup is worse than no
-- check. Every file below is verified readable first, and the traceback
-- assertion is what proves the reads actually happened.
print()
print("-- corroboration: what real OC code uses --")
do
  local REF = {
    "Reference/OpenOS/openos/lib/tty.lua",
    "Reference/OpenOS/openos/lib/process.lua",
    "Reference/OpenOS/openos/lib/package.lua",
    "Reference/OpenOS/openos/init.lua",
  }
  local function readRef(rel)
    for _, p in ipairs({ base .. "../../../../" .. rel, "../" .. rel, rel }) do
      local fh = io.open(p, "r")
      if fh then local s = fh:read("*a"); fh:close(); return s end
    end
  end
  local read, sethook, traceback = 0, 0, 0
  for _, rel in ipairs(REF) do
    local src = readRef(rel)
    if src then
      read = read + 1
      if src:find("debug.sethook", 1, true) then sethook = sethook + 1 end
      if src:find("debug.traceback", 1, true) then traceback = traceback + 1 end
    end
  end
  if read == 0 then
    print("  (skipped: Reference/OpenOS is not in this checkout)")
  else
    eq("all reference files were readable", #REF, read)
    -- This one is the anti-vacuity guard: if it fails, the reads did not
    -- work and the sethook result below means nothing.
    test("OpenOS does use debug.traceback (proves the reads landed)", traceback > 0)
    eq("OpenOS never uses debug.sethook", 0, sethook)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
