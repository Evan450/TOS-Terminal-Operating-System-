-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: SRM really does give the machine back       ║
-- ║                                                                ║
-- ║  test_srm_yields.lua proves SRM CALLS yieldCooperative. It     ║
-- ║  proves it by replacing kernel.process with a stub whose       ║
-- ║  yieldCooperative always succeeds and counts — so it cannot    ║
-- ║  fail for the reason that matters. The operator retested the   ║
-- ║  fix on the real box and reported the freeze unchanged, with   ║
-- ║  the suite green. A test that stubs the mechanism it is        ║
-- ║  testing is not a test of that mechanism.                      ║
-- ║                                                                ║
-- ║  So: the REAL kernel.process, a REAL spawned process, the      ║
-- ║  REAL scheduler, and the question asked the way the operator   ║
-- ║  asks it — while SRM is working, does anything else on this    ║
-- ║  machine get to run?                                           ║
-- ║                                                                ║
-- ║  The real yieldCooperative has three ways to answer "no" that  ║
-- ║  the stub had none of: no current process (kernel context),    ║
-- ║  not inside a yieldable coroutine, and a 50ms slice throttle.  ║
-- ║  Only an end-to-end run exercises them.                        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_srm_responsive.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_srm_responsive.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path

-- A clock that advances as work is done, the way a real one does. The slice
-- throttle in yieldCooperative is measured against it, so a frozen clock
-- would make every yield fall inside its slice and never fire — which would
-- pass or fail this test for entirely the wrong reason.
local clock = 0
package.loaded["computer"] = {
  uptime      = function() clock = clock + 0.03; return clock end,
  freeMemory  = function() return 4e6 end,
  totalMemory = function() return 8e6 end,
  pullSignal  = function() return nil end,
  beep        = function() end,
  getDeviceInfo = function() return {} end,
}
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end, type = function() return nil end,
  invoke = function() return nil end, isAvailable = function() return false end,
}

-- THE REAL ONES. No stub stands between the test and the mechanism.
local proc = require("kernel.process")
local srm  = require("kernel.srm")

print("=== SRM keeps the machine alive (end-to-end) Tests ===")
print()

-- ── An in-memory filesystem with enough files to matter ────────────
local FILES = {}
for i = 1, 24 do FILES["/tos/f" .. i .. ".lua"] = "-- file " .. i .. string.rep("x", 100) end
local store = {}
local fs = {
  exists      = function(p) return FILES[p] ~= nil or store[p] ~= nil end,
  readFile    = function(p) return FILES[p] or store[p] end,
  writeFile   = function(p, d) store[p] = d; return true end,
  writeFileAtomic = function(p, d) store[p] = d; return true end,
  remove      = function(p) store[p] = nil; return true end,
  makeDirectory = function() return true end,
  isDirectory = function() return false end,
  list        = function() return {} end,
  size        = function(p) return #(FILES[p] or store[p] or "") end,
}
local crypto = { hash = function(s) return ("h%d"):format(#s) end }
local paths = {}
for p in pairs(FILES) do paths[#paths + 1] = p end
table.sort(paths)
local deps = { fs = fs, crypto = crypto, serialize = require("kernel.serialize") }

eq("the fixture has files to walk", 24, #paths)
test("yieldCooperative is the real one, not a stub",
  proc.yieldCooperative ~= nil and debug.getinfo(proc.yieldCooperative).short_src:find("process") ~= nil)

-- ── In kernel context it is CORRECTLY a no-op ──────────────────────
-- Called from outside any process there is nothing to slice. SRM's boot-time
-- repair pass runs exactly here, so this must not throw and must not hang.
print()
print("-- outside a process, there is nothing to give back --")
do
  eq("yieldCooperative declines in kernel context", false, proc.yieldCooperative())
  local okBoot = pcall(srm.scan, deps, { paths = paths })
  test("...and SRM completes anyway", okBoot)
end

-- ── THE QUESTION THE OPERATOR ASKED ────────────────────────────────
-- Run SRM inside a real process, with a second process alongside it, and
-- count how many times that second process gets to run while SRM works.
-- On a frozen machine the answer is zero.
print()
print("-- while SRM works, does anything else get to run? --")
do
  -- A scan with no baseline to compare against returns immediately and walks
  -- nothing, which would make this whole measurement vacuous in the other
  -- direction. Lay the baseline down first, and prove it took.
  srm.baseline(deps, { paths = paths, content = false })
  test("a baseline exists for the scan to walk",
    srm.loadIndex(deps) ~= nil)

  local neighbourRuns = 0
  local scanDone = false

  local scanPid = proc.spawn("srm-scan", function()
    srm.scan(deps, { paths = paths })
    scanDone = true
  end)
  local neighbourPid = proc.spawn("neighbour", function()
    while true do neighbourRuns = neighbourRuns + 1; coroutine.yield() end
  end)
  test("both processes spawned", scanPid ~= nil and neighbourPid ~= nil)

  local ticks = 0
  while not scanDone and ticks < 500 do
    ticks = ticks + 1
    proc.tick(nil)
  end

  test("the scan finished", scanDone)
  test("it took more than one scheduler tick (" .. ticks .. " ticks)", ticks > 1)
  test("...so SRM suspended mid-scan rather than running to completion in one go",
    ticks >= 3)
  test("the neighbouring process ran DURING the scan (" .. neighbourRuns
    .. " resumes) — this is the freeze, measured", neighbourRuns > 1)
  test("...roughly once per tick, i.e. the machine kept scheduling",
    neighbourRuns >= ticks - 1)

  pcall(proc.kill, neighbourPid)
end

-- ── The slice throttle is real, and bounded ────────────────────────
-- Yielding on EVERY file would be as wrong as never yielding: the resume
-- overhead would dominate a scan of a large manifest. The throttle means a
-- slice of work happens per resume, so ticks must be well below file count.
print()
print("-- and it slices, rather than yielding on every single file --")
do
  local done = false
  local t = 0
  proc.spawn("srm-scan-2", function()
    srm.scan(deps, { paths = paths }); done = true
  end)
  while not done and t < 500 do t = t + 1; proc.tick(nil) end
  test("the scan finished again", done)
  test("ticks (" .. t .. ") stayed below one-per-file (" .. #paths
    .. ") — the 50ms slice is doing its job", t < #paths)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
