-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: SRM gives the machine back between files    ║
-- ║                                                                ║
-- ║  Reported from a real box: `srm` freezes the computer for its  ║
-- ║  whole run rather than merely slowing it down. The operator    ║
-- ║  wondered whether it was just the longest command or a genuine ║
-- ║  outlier. It was the outlier.                                  ║
-- ║                                                                ║
-- ║  SRM reads and hashes every file in the manifest — the longest ║
-- ║  job in the OS by a wide margin — and it was the ONLY long job ║
-- ║  that never yielded. Ten other modules do: compress, pkg, fs,  ║
-- ║  ed25519, the executor's output chokepoint, and the walk loops ║
-- ║  in the command files. So `srm scan` did not just run slowly,  ║
-- ║  it stopped everything: no other seat drew, no timer fired.    ║
-- ║                                                                ║
-- ║  It is worse than a freeze on OpenComputers. The machine kills ║
-- ║  a computer that goes too long without yielding, and TOS's own ║
-- ║  preemption cannot save it — debug.sethook is not in the OC    ║
-- ║  sandbox (test_sethook_absent.lua). A big enough manifest      ║
-- ║  takes the whole computer down.                                ║
-- ║                                                                ║
-- ║  Yields go BETWEEN whole files, never mid-file, so a file is   ║
-- ║  still read and hashed inside one resume and SRM's per-file    ║
-- ║  atomicity is unchanged.                                       ║
-- ║                                                                ║
-- ║  READ THIS BEFORE TRUSTING THIS FILE. It replaces              ║
-- ║  kernel.process with a stub whose yieldCooperative always      ║
-- ║  succeeds, so it proves only that SRM CALLS the yield at the   ║
-- ║  right places. It cannot fail for the reason that matters, and ║
-- ║  it did not: the operator retested on the real box and         ║
-- ║  reported no change with this suite green. The real            ║
-- ║  yieldCooperative has three ways to answer "no" the stub has   ║
-- ║  none of — kernel context, a non-yieldable coroutine, and a    ║
-- ║  50ms slice throttle.                                          ║
-- ║                                                                ║
-- ║  The end-to-end proof — real process module, real spawned      ║
-- ║  process, real scheduler, and the question asked the way an    ║
-- ║  operator asks it — is test_srm_responsive.lua. Keep both:     ║
-- ║  this one names the call sites that must not regress, that one ║
-- ║  proves the machine keeps running.                             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_srm_yields.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_srm_yields.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 4e6 end, pullSignal = function() return nil end,
  beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
  proxy = function() end, isAvailable = function() return false end }

-- Count every cooperative yield SRM asks for, by standing in for
-- kernel.process before srm requires it.
local yields = 0
package.loaded["kernel.process"] = {
  yieldCooperative = function() yields = yields + 1; return true end,
  current = function() return nil end,
  genOf = function() return nil end,
}

local srm = require("kernel.srm")

print("=== SRM cooperative yield Tests ===")
print()

-- ── An in-memory filesystem with a known number of files ───────────
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
eq("the fixture has files to walk", 24, #paths)

local deps = { fs = fs, crypto = crypto, log = nil,
               serialize = require("kernel.serialize") }

-- ── baseline: one yield per file, at least ─────────────────────────
do
  yields = 0
  local ok = srm.baseline(deps, { paths = paths, content = false })
  test("baseline ran", ok ~= false)
  test("it yielded while walking (" .. yields .. " times over "
    .. #paths .. " files)", yields >= #paths)
end

-- ── scan: the one the operator actually watched freeze ─────────────
do
  yields = 0
  local rep = srm.scan(deps, { paths = paths })
  test("scan ran", type(rep) == "table")
  test("scan yielded too (" .. yields .. ")", yields >= #paths)
end

-- ── The yield is BETWEEN files, never inside one ────────────
-- Yielding mid-file would break SRM's per-file atomicity: a file must be
-- read and hashed within one resume, or the hash can describe a file that
-- changed underneath it.
--
-- Asserted on the read-and-hash unit itself rather than on a call trace. The
-- first version of this watched for back-to-back yields in a trace and
-- failed -- wrongly: `scan` walks `paths` TWICE (hash, then store check), so
-- consecutive yields with no read between them are perfectly correct. The
-- trace could not tell "two walks" from "yield inside one file".
do
  local src
  for _, p in ipairs({ base .. "../../../tos/kernel/srm.lua",
      "tos/kernel/srm.lua", "TOS-Dev/tos/kernel/srm.lua" }) do
    local fh = io.open(p, "r")
    if fh then src = fh:read("*a"); fh:close(); break end
  end
  test("srm.lua is readable for the atomicity check", src ~= nil)
  -- string.char(10), not an escape: a backslash-n does not survive the
  -- editing path this file was written through.
  local NL = string.char(10)
  if src then
    local body = src:match("local function readHashed.-" .. NL .. "end")
    test("found readHashed, the read-and-hash unit", body ~= nil)
    test("...and it contains no yield",
      body ~= nil and body:find("coopYield", 1, true) == nil)
    local hashBody = src:match("local function hashFile.-" .. NL .. "end")
    test("hashFile contains no yield either",
      hashBody == nil or hashBody:find("coopYield", 1, true) == nil)
  end
end

-- ── It must be a no-op where there is no process ───────────────────
-- SRM's repair pass runs at BOOT, from kernel context, where there is no
-- coroutine to yield from. The real yieldCooperative returns false there;
-- SRM must not care either way.
do
  package.loaded["kernel.process"] = {
    yieldCooperative = function() return false end,
    current = function() return nil end, genOf = function() return nil end,
  }
  local okBoot = pcall(srm.scan, deps, { paths = paths })
  test("scan still completes when yielding is unavailable", okBoot)
end

-- ── And it must survive kernel.process being absent entirely ───────
do
  package.loaded["kernel.process"] = nil
  local okNone = pcall(srm.scan, deps, { paths = paths })
  test("scan still completes with no process module at all", okNone)
end

-- ── The rule, as source ────────────────────────────────────────────
-- SRM is the module this was missing from; the check that it stays
-- present is cheap and names the file that regressed.
print()
print("-- the yield is wired into every per-file walk --")
do
  local src
  for _, p in ipairs({ base .. "../../../tos/kernel/srm.lua",
      "tos/kernel/srm.lua", "TOS-Dev/tos/kernel/srm.lua" }) do
    local fh = io.open(p, "r")
    if fh then src = fh:read("*a"); fh:close(); break end
  end
  test("srm.lua is readable", src ~= nil)
  if src then
    test("it defines a cooperative slice", src:find("local function coopYield", 1, true) ~= nil)
    -- Every `for _, path in ipairs(...)` walk must open with the slice.
    local walks, yielded = 0, 0
    for body in src:gmatch("for _, path in ipairs%b()%s*do%s*\r?\n(%s*[%w_]+%(?)") do
      walks = walks + 1
      if body:find("coopYield", 1, true) then yielded = yielded + 1 end
    end
    test("found the per-file walks (" .. walks .. ")", walks >= 4)
    eq("every one of them yields first", walks, yielded)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
