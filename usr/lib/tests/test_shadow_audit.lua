-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the display cache checks its own story       ║
-- ║                                                                ║
-- ║  Five rounds of "the status bar turns black". Each round found ║
-- ║  a real bug in which writer failed to DECLARE that it had      ║
-- ║  moved the glass, fixed it, and the bar went black again for a ║
-- ║  different reason. The last capture from the operator's box:   ║
-- ║                                                                ║
-- ║    row 25 glass ..... 000000                                   ║
-- ║    row 25 shadow .... 336699                                   ║
-- ║    row 25 page ...... 336699                                   ║
-- ║    backbuffer=true  broken=false   (the blit was honest)       ║
-- ║                                                                ║
-- ║  The lesson is not "find the sixth writer". It is that the     ║
-- ║  shadow's belief is an UNVERIFIABLE CLAIM about the screen,    ║
-- ║  and the elision converts any single missed declaration into a ║
-- ║  permanently wrong row: the one row that is wrong is precisely ║
-- ║  the one row that never gets repainted. A GPU that drops a     ║
-- ║  call, an emulator quirk, or a code path nobody has found yet  ║
-- ║  all land the same way, and none of them can be enumerated.    ║
-- ║                                                                ║
-- ║  So the cache spot-checks itself: before skipping a draw, at   ║
-- ║  most once a second, read one cell back and find out whether   ║
-- ║  the screen really holds what is about to not be drawn.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_shadow_audit.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_shadow_audit.lua"
local base = here:gsub("[^/\\]*$", "")

local fixture
for _, p in ipairs({ base .. "fixture_glass.lua",
    "usr/lib/tests/fixture_glass.lua", "TOS-Dev/usr/lib/tests/fixture_glass.lua" }) do
  local chunk = loadfile(p)
  if chunk then fixture = chunk(); break end
end
if not fixture then
  print("FAIL: could not load fixture_glass.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

local G = fixture.newGlass(80, 25).install()
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path

local display = require("kernel.display")
local screen  = require("kernel.screen")
screen.init()
local D = screen.displayProxy(1)
local T = display.THEME or display.getTheme()
local STAT = 25

-- The shell's once-a-second status repaint, exactly as drawRampBar issues it.
local function tickStatusBar()
  D.fill(1, STAT, 80, 1, " ", T.statusbar_fg, T.statusbar_bg)
  D.set(2, STAT, "Disk:2.4M | Clock:10:24 | User:root", T.statusbar_fg, T.statusbar_bg)
end

print("=== the display cache audits itself Tests ===")
print()

-- ── The captured state, rebuilt ────────────────────────────────────
print("-- the operator's screen, reproduced --")
do
  D.fill(1, 1, 80, 25, " ", T.fg, T.bg)
  tickStatusBar()
  eq("the bar starts correct on the glass", T.statusbar_bg, G.bgAt(40, STAT))

  -- Move the glass WITHOUT declaring it. Not via D.getGpu(), which declares
  -- the write and drops the shadow -- that is the case TOS already handles.
  -- This is the one it cannot: a writer that never announces itself.
  G.gpu.setBackground(0x000000)
  G.gpu.fill(1, STAT, 80, 1, " ")
  eq("the glass is black behind the cache's back", 0x000000, G.bgAt(40, STAT))

  -- Within the same second the audit is rate-limited, so the repaint is
  -- still elided -- which is correct: one gpu.get per second, not per draw.
  tickStatusBar()
  eq("inside the rate limit the repaint is still elided (cost stays bounded)",
    0x000000, G.bgAt(40, STAT))
end

-- ── A second later, it catches itself ──────────────────────────────
print()
print("-- one second on, the cache checks and finds itself wrong --")
do
  G.clock = G.clock + 2
  tickStatusBar()
  eq("the bar is repainted", T.statusbar_bg, G.bgAt(40, STAT))
  eq("...across the whole row", T.statusbar_bg, G.bgAt(1, STAT))
  eq("...to the far end", T.statusbar_bg, G.bgAt(80, STAT))
  test("the text came back", G.rowText(STAT):find("Clock:10:24", 1, true) ~= nil)
  test("and the proxy recorded that it caught itself", D.auditHits() >= 1)
end

-- ── It must not cost a call per draw ───────────────────────────────
-- The shadow exists to avoid component calls. An audit on every elision
-- would spend more than the elision saves and make the cure worse.
print()
print("-- and it stays cheap --")
do
  local gets = 0
  local realGet = G.gpu.get
  G.gpu.get = function(x, y) gets = gets + 1; return realGet(x, y) end

  G.clock = G.clock + 5
  for _ = 1, 60 do tickStatusBar() end     -- 60 repaints inside one second
  G.gpu.get = realGet
  test("60 elided repaints cost at most one read-back (" .. gets .. ")", gets <= 1)
end

-- ── Never inside a frame ───────────────────────────────────────────
-- Inside a frame gpu.get reads the PAGE, not the glass, and the two are
-- legitimately different there. Auditing would compare the cache against
-- the wrong surface and throw the shadow away on every frame.
print()
print("-- and never against the wrong surface --")
do
  G.clock = G.clock + 5
  local gets = 0
  local realGet = G.gpu.get
  G.gpu.get = function(x, y) gets = gets + 1; return realGet(x, y) end

  D.beginFrame()
  for _ = 1, 5 do tickStatusBar() end       -- all elided, inside a frame
  local hitsBefore = D.auditHits()
  D.endFrame()
  G.gpu.get = realGet

  eq("no audit fired inside the frame", hitsBefore, D.auditHits())
  test("the frame is intact afterwards", D.hasBackbuffer() == true)
end

-- ── It does not fire when the cache is telling the truth ───────────
print()
print("-- and it does not cry wolf --")
do
  G.clock = G.clock + 5
  local before = D.auditHits()
  tickStatusBar()        -- glass and shadow agree; audit reads, finds nothing
  G.clock = G.clock + 5
  tickStatusBar()
  eq("a correct screen is never dropped", before, D.auditHits())
  eq("...and the bar is still the bar", T.statusbar_bg, G.bgAt(40, STAT))
end

-- ── The other way the caches go wrong, same repair ─────────────────
-- A frame draws into the off-screen PAGE and blits it to the screen. If
-- that blit reports success and copies nothing, the shadow has recorded a
-- screenful of facts that never happened — same broken invariant, arrived
-- at from the opposite direction. One mechanism should cover both, or the
-- next variant needs a sixth round.
print()
print("-- and it recovers from a blit that lies about having worked --")
do
  package.loaded["kernel.screen"] = nil
  package.loaded["kernel.display"] = nil
  local G3 = fixture.newGlass(80, 25).install()
  local screen3 = require("kernel.screen")
  screen3.init()
  local D3 = screen3.displayProxy(1)
  local T3 = require("kernel.display").getTheme()

  local function bar(clockText)
    D3.fill(1, STAT, 80, 1, " ", T3.statusbar_fg, T3.statusbar_bg)
    D3.set(2, STAT, "Disk:2.4M | Clock:" .. clockText, T3.statusbar_fg, T3.statusbar_bg)
  end

  D3.fill(1, 1, 80, 25, " ", T3.fg, T3.bg)
  bar("10:24")
  eq("the bar is on the glass to begin with", T3.statusbar_bg, G3.bgAt(40, STAT))

  -- Black the row behind the cache's back, then let a FRAME "repair" it
  -- through a blit that does nothing.
  G3.gpu.setBackground(0x000000)
  G3.gpu.fill(1, STAT, 80, 1, " ")
  G3.blitLies = true
  D3.beginFrame(); bar("10:25"); D3.endFrame()
  G3.blitLies = false
  eq("the frame did not reach the screen", 0x000000, G3.bgAt(40, STAT))

  -- ...and now the ordinary once-a-second repaint finds the lie.
  G3.clock = G3.clock + 2
  bar("10:26")
  eq("the next repaint repairs the row", T3.statusbar_bg, G3.bgAt(40, STAT))
  eq("...to the far end", T3.statusbar_bg, G3.bgAt(80, STAT))
  test("...and the cache admits it was caught", D3.auditHits() >= 1)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
