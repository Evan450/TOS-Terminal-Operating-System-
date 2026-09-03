-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the splash after the kernel resizes the glass║
-- ║                                                                ║
-- ║  Reported from a real Minecraft install: on a splash boot with ║
-- ║  a TIER 3 GPU and a RESIZED (multi-block) screen, the loading  ║
-- ║  bar and the wordmark are shoved to the right-hand edge and    ║
-- ║  almost entirely cut off.                                      ║
-- ║                                                                ║
-- ║  /init.lua measures the resolution ONCE, right after           ║
-- ║  gpu.bind() — and bind leaves an OpenComputers screen at its   ║
-- ║  MAXIMUM. The kernel then applies the resolution policy from   ║
-- ║  kernel/screen.lua (density-based, floored at 80x25) part-way  ║
-- ║  through kernel.boot(), while the bar is live, because         ║
-- ║  bootProgress is the callback driving it.                      ║
-- ║                                                                ║
-- ║  On a Tier 3 GPU over a multi-block screen that is a real      ║
-- ║  reduction — 160x50 down to 80x25 — so geometry centred for    ║
-- ║  160 puts the bar at column 60 of a screen 80 wide, spanning   ║
-- ║  60..101 and running off the edge.                             ║
-- ║                                                                ║
-- ║  WHY ONLY THERE, which is what makes the report so specific:   ║
-- ║  a Tier 2 GPU maxes at 80x25 and a single Tier 3 block at      ║
-- ║  50x16, so in both cases the policy asks for what is already   ║
-- ║  set and nothing moves. It takes a big screen AND a Tier 3     ║
-- ║  GPU for the boot-time measurement and the applied policy to   ║
-- ║  disagree.                                                     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_splash_resize.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_splash_resize.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["component"] = { list = function() return function() end end,
  proxy = function() end, invoke = function() end }
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 4e6 end }

local bootsteps = require("kernel.bootsteps")
local screen    = require("kernel.screen")

print("=== splash geometry across a mid-boot resize ===")
print()

test("bootsteps exposes splashGeometry", type(bootsteps.splashGeometry) == "function")
test("bootsteps exposes splashFits", type(bootsteps.splashFits) == "function")
if type(bootsteps.splashGeometry) ~= "function" then
  print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

-- ── The bar fits the screen it is given, at every size ─────────────
print()
print("-- the bar fits, whatever the screen --")
for _, wh in ipairs({ {50,16}, {80,25}, {160,50}, {40,12}, {30,10}, {16,8}, {12,6} }) do
  local w, h = wh[1], wh[2]
  local barRow, barW, barX = bootsteps.splashGeometry(w, h, 6)
  test(string.format("%dx%d: bar spans %d..%d inside %d columns",
    w, h, barX, barX + barW + 1, w), barX >= 1 and barX + barW + 1 <= w)
  test(string.format("%dx%d: row %d is on screen", w, h, barRow),
    barRow >= 1 and barRow <= h)
end

-- ── It is CENTRED for the width it was given ───────────────────────
do
  local _, barW, barX = bootsteps.splashGeometry(80, 25, 6)
  local leftGap  = barX - 1
  local rightGap = 80 - (barX + barW + 1)
  test("centred on an 80-wide screen (gaps " .. leftGap .. "/" .. rightGap .. ")",
    math.abs(leftGap - rightGap) <= 1)
end

-- ── THE BUG, as a sequence ─────────────────────────────────────────
-- Boot measures the screen at its post-bind maximum; the kernel then
-- applies the policy. Geometry from the FIRST must not be used against
-- the SECOND.
print()
print("-- the reported sequence: T3 GPU, multi-block screen --")
do
  local MAXW, MAXH = 160, 50                 -- Tier 3 over a big screen
  local appliedW, appliedH =
    screen.chooseResolution({ mode = "auto" }, MAXW, MAXH, 3, 2)
  eq("the kernel's policy asks for 80 columns", 80, appliedW)
  eq("...and 25 rows", 25, appliedH)
  test("which really is a reduction from what bind left us at",
    appliedW < MAXW)

  -- Geometry measured BEFORE the policy ran, used AFTER it did.
  local _, staleW, staleX = bootsteps.splashGeometry(MAXW, MAXH, 6)
  local staleRight = staleX + staleW + 1
  test("stale geometry starts at column " .. staleX
    .. " and ends at " .. staleRight .. " — off a " .. appliedW .. "-column screen",
    staleRight > appliedW)
  eq("...which is exactly the reported symptom: cut off on the right",
    false, bootsteps.splashFits(MAXW, MAXH, 6) and staleRight <= appliedW)

  -- Recomputed against the applied resolution, it fits.
  local freshRow, freshW, freshX = bootsteps.splashGeometry(appliedW, appliedH, 6)
  test("recomputed for the applied size, the bar fits ("
    .. freshX .. ".." .. (freshX + freshW + 1) .. " of " .. appliedW .. ")",
    freshX + freshW + 1 <= appliedW)
  test("...and is centred again",
    math.abs((freshX - 1) - (appliedW - (freshX + freshW + 1))) <= 1)
  test("...on a row that exists", freshRow >= 1 and freshRow <= appliedH)
end

-- ── The combinations that were NEVER broken must stay unbroken ─────
print()
print("-- the cases the operator did not see, and why --")
for _, c in ipairs({
    { "Tier 2, any screen",     80,  25, 1, 1 },
    { "Tier 3, single block",   50,  16, 1, 1 },
}) do
  local name, maxW, maxH, bw, bh = c[1], c[2], c[3], c[4], c[5]
  local aw, ah = screen.chooseResolution({ mode = "auto" }, maxW, maxH, bw, bh)
  eq(name .. ": policy leaves the width alone", maxW, aw)
  test(name .. ": so boot-time geometry was already right",
    bootsteps.splashFits(maxW, maxH, 6))
end

-- ── Degenerate inputs must not produce a bar off the screen ────────
print()
print("-- junk in --")
do
  local r1, w1, x1 = bootsteps.splashGeometry(nil, nil, nil)
  test("nil size falls back to something drawable", x1 >= 1 and w1 >= 10 and r1 >= 1)
  local r2 = select(1, bootsteps.splashGeometry(80, 3, 40))
  test("a header taller than the screen still yields row >= 1", r2 >= 1)
  local _, _, x3 = bootsteps.splashGeometry(8, 6, 2)
  test("a screen narrower than the minimum bar starts at column 1", x3 == 1)
end

-- ── /init.lua must actually recompute ──────────────────────────────
-- The pure function is only half the fix; the boot file has to call it
-- again after the resolution moves. Driving the real boot file needs a
-- whole OC machine, so this is pinned by source.
print()
print("-- the boot file recomputes rather than measuring once --")
do
  local src
  for _, p in ipairs({ base .. "../../../init.lua", "init.lua", "TOS-Dev/init.lua" }) do
    local fh = io.open(p, "r")
    if fh then src = fh:read("*a"); fh:close(); break end
  end
  test("init.lua is readable", src ~= nil)
  if src then
    test("the bar's geometry lives in a function that can be re-run",
      src:find("local function geom()", 1, true) ~= nil)
    test("...and it uses the shared pure helper",
      src:find("bootsteps.splashGeometry", 1, true) ~= nil)
    test("a resync re-reads the live resolution",
      src:find("local function resync()", 1, true) ~= nil)
    test("...and the bar's redraw calls it",
      src:match("local function redraw%(%)%s*\r?\n%s*resync%(%)") ~= nil)
    test("...and a resize rebuilds the header, not just the bar",
      src:match("local function resync%(%).-drawBootHeader%(%)") ~= nil)
    -- The require has to sit ABOVE geom(), or bootsteps is a nil global
    -- inside it and geom silently takes its fallback branch forever.
    local reqAt = src:find('local okSteps, bootsteps = pcall%(require, "kernel%.bootsteps"%)')
    local geomAt = src:find("local function geom()", 1, true)
    test("bootsteps is required before geom() closes over it",
      reqAt ~= nil and geomAt ~= nil and reqAt < geomAt)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
