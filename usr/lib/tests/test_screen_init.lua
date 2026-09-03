-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: screen.init() seat enumeration          ║
-- ║                                                            ║
-- ║  Guards the multi-seat init path — specifically the        ║
-- ║  #BUG-1 diagnostic-log block, which referenced a nil       ║
-- ║  `screens` global (the local is `screenAddrs`) and         ║
-- ║  panicked the kernel at loginAndStartShell once the log    ║
-- ║  module was up. loadfile() can't catch a nil-global read,  ║
-- ║  so we drive screen.init() with a stub component model and ║
-- ║  a capturing log across mismatched GPU/screen counts.      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_screen_init.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

-- Mutable component inventory the stub reads (swapped per case).
local STATE = { gpu = {}, screen = {}, keyboard = {} }
local LOG = {}

package.loaded["component"] = {
  list = function(ctype)
    local a = STATE[ctype] or {}
    local i = 0
    return function() i = i + 1; return a[i] end
  end,
  slot   = function() return 0 end,          -- everything is local
  invoke = function(_, method)
    if method == "getKeyboards" then return {} end
    if method == "getAspectRatio" then return 1, 1 end
    return nil
  end,
  proxy  = function()
    return {
      bind          = function() return true end,
      getScreen     = function() return nil end,   -- no current binding
      maxResolution = function() return 80, 25 end,
      setResolution = function() return true end,
      getResolution = function() return 80, 25 end,
      getDepth      = function() return 4 end,
    }
  end,
}
package.loaded["computer"] = { uptime = function() return 0 end, pullSignal = function() end }
package.loaded["kernel.display"] = { refreshSize = function() end }
package.loaded["kernel.log"] = {
  info  = function(_, m) LOG[#LOG + 1] = { lvl = "info", msg = m } end,
  warn  = function(_, m) LOG[#LOG + 1] = { lvl = "warn", msg = m } end,
  debug = function() end, error = function() end,
}

package.path = "tos/?.lua;" .. package.path
local screen = require("kernel.screen")

local function logHas(sub)
  for _, e in ipairs(LOG) do if e.msg:find(sub, 1, true) then return true end end
  return false
end

print("=== screen.init() Tests ===")
print()

-- Case A: 1 GPU + 2 screens — exercises the "#gpus < #screenAddrs" warn
-- branch (the exact branch that read the nil global).
STATE.gpu = { "g1" }; STATE.screen = { "s1", "s2" }; LOG = {}
local okA, nA = pcall(screen.init)
test("1 GPU + 2 screens: no panic", okA)
test("returns a display count (number)", type(nA) == "number")
test("logged the seat-init summary", logHas("Seat init:"))
test("summary reports 2 screens (not nil)", logHas("and 2 screens"))
test("warns about the unused screen", logHas("will sit unused"))

-- Case B: 2 GPUs + 1 screen — the "#screenAddrs < #gpus" warn branch.
STATE.gpu = { "g1", "g2" }; STATE.screen = { "s1" }; LOG = {}
local okB = pcall(screen.init)
test("2 GPUs + 1 screen: no panic", okB)
test("warns about the idle GPU", logHas("GPU(s) idle"))

-- Case C: balanced 1 + 1 — info only, no warn.
STATE.gpu = { "g1" }; STATE.screen = { "s1" }; LOG = {}
local okC = pcall(screen.init)
test("1 GPU + 1 screen: no panic", okC)
local warned = false
for _, e in ipairs(LOG) do if e.lvl == "warn" then warned = true end end
test("balanced seats: no mismatch warning", not warned)

-- Case D: the real panic path — screen.count() -> ensureInit() -> init().
STATE.gpu = { "g1" }; STATE.screen = { "s1", "s2" }
local okD, cnt = pcall(screen.count)
test("screen.count() path: no panic", okD)
test("screen.count() returns a number", type(cnt) == "number")

-- ── Stable seat indices across rebuild (round-4 seat-binding fix) ──
-- rebuild() used to renumber survivors (remove screen 1 of 2 → the
-- surviving seat shifted 2→1 while every kernel per-seat table still
-- said 2 → the survivor froze). Indices must now be STABLE: survivors
-- keep their index, removals leave holes, newcomers take the lowest
-- free index.

-- Case E baseline: 2 GPUs + 2 screens → seats 1 and 2.
STATE.gpu = { "g1", "g2" }; STATE.screen = { "s1", "s2" }; LOG = {}
screen.init()
local idxs = screen.indices()
test("2+2 boot: two seats", #idxs == 2 and idxs[1] == 1 and idxs[2] == 2)
local byIdx = {}
for _, e in ipairs(screen.list()) do byIdx[e.index] = e end
local s1Idx, s2Idx
for _, e in ipairs(screen.list()) do
  if e.screen == "s1" then s1Idx = e.index end
  if e.screen == "s2" then s2Idx = e.index end
end
test("2+2 boot: both screens seated", s1Idx ~= nil and s2Idx ~= nil)

-- Case F: unplug s1 → its seat is removed, s2 KEEPS its index (hole stays).
STATE.screen = { "s2" }
local added, removed = screen.rebuild()
test("unplug s1: exactly one seat removed", #removed == 1 and removed[1] == s1Idx)
test("unplug s1: nothing spuriously added", #added == 0)
test("unplug s1: survivor keeps its stable index",
  screen.count() == 1 and screen.indices()[1] == s2Idx)
test("unplug s1: survivor's record intact", screen.get(s2Idx) ~= nil
  and screen.get(s2Idx).screen == "s2")
test("unplug s1: removed seat is a hole", screen.get(s1Idx) == nil)
test("unplug s1: active() snaps to the survivor",
  screen.active() ~= nil and screen.active().screen == "s2")

-- Case G: plug a NEW screen s3 → takes the lowest FREE index (the hole),
-- survivor still untouched.
STATE.screen = { "s2", "s3" }
added, removed = screen.rebuild()
test("plug s3: exactly one seat added", #added == 1)
test("plug s3: nothing removed", #removed == 0)
test("plug s3: newcomer takes the lowest free index", added[1] == s1Idx)
test("plug s3: survivor STILL keeps its index",
  screen.get(s2Idx) ~= nil and screen.get(s2Idx).screen == "s2")

-- Case H: replug s1 later in the SAME boot → it remembers its old index...
-- unless the index was re-used (s3 owns it now): then s1 gets the next free.
STATE.screen = { "s1", "s2", "s3" }
STATE.gpu = { "g1", "g2", "g3" }
added, removed = screen.rebuild()
test("replug s1 (old index now taken): added without evicting anyone",
  #added == 1 and #removed == 0)
test("replug s1: three live seats, all distinct indices",
  screen.count() == 3)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
