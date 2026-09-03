-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: screendump reports the GLASS                ║
-- ║                                                                ║
-- ║  `screendump` exists to capture a screen for a bug report. It  ║
-- ║  read the dirty-cell SHADOW whenever the shadow was enabled —  ║
-- ║  which is to say the tool for diagnosing display faults        ║
-- ║  reported the display cache's own account of the screen.       ║
-- ║                                                                ║
-- ║  For the one class of bug TOS keeps having — the shadow and    ║
-- ║  the glass disagreeing — that is exactly the wrong witness. A  ║
-- ║  row the shadow believes is painted dumps as perfect, which is ║
-- ║  precisely the case somebody would be running screendump to    ║
-- ║  investigate.                                                  ║
-- ║                                                                ║
-- ║  It also captured characters only. A fault that changes COLOUR ║
-- ║  and not text left no trace at all — and "the status bar went  ║
-- ║  black" is that fault exactly: same characters, wrong          ║
-- ║  background.                                                   ║
-- ║                                                                ║
-- ║  So: gpu.get is the truth and is used whenever it exists, the  ║
-- ║  colours come back with the text, and the capture says which   ║
-- ║  surface answered. A capture that cannot say where it came     ║
-- ║  from is the same trap wearing a different hat.                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_screendump_truth.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_screendump_truth.lua"
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

print("=== screendump reads the glass Tests ===")
print()

-- ── A normal screen ────────────────────────────────────────────────
D.fill(1, 1, 80, 25, " ", T.fg, T.bg)
D.fill(1, STAT, 80, 1, " ", T.statusbar_fg, T.statusbar_bg)
D.set(1, STAT, "Disk:2.4M | Clock:10:24 | User:root", T.statusbar_fg, T.statusbar_bg)

do
  local cap = D.dump()
  test("dump returns a table", type(cap) == "table")
  eq("...read from the glass", "glass", cap.source)
  eq("...with the right width", 80, cap.w)
  eq("...and height", 25, cap.h)
  test("it captured the status text",
    (cap.lines[STAT] or ""):find("Clock:10:24", 1, true) ~= nil)
  test("it captured background colours", type(cap.bg) == "table")
  test("...and foreground colours", type(cap.fg) == "table")
  local runs = cap.bg[STAT]
  test("the status row is one run of the bar colour",
    runs and #runs == 1 and runs[1].c == T.statusbar_bg)
  test("...spanning the whole row",
    runs and runs[1].from == 1 and runs[1].to == 80)
end

-- ── The capture NAMES THE GUILTY LAYER ─────────────────────────────
-- Reading the glass shows the fault. It does not say what caused it, and
-- "the shadow believes this row is already painted" is not a detail --
-- it IS the mechanism. A cell the shadow trusts is a cell that never gets
-- repainted, so the fault outlives every redraw and heals only by
-- accident. A capture that shows the symptom without the cache's own
-- account sends you back to reading source and guessing, which is where
-- three rounds of this bug have already gone.
print()
print("-- the shadow's account, alongside the glass --")
do
  D.fill(1, 1, 80, 25, " ", T.fg, T.bg)
  D.fill(1, STAT, 80, 1, " ", T.statusbar_fg, T.statusbar_bg)
  D.set(1, STAT, "Disk:2.4M | Clock:10:24", T.statusbar_fg, T.statusbar_bg)
  -- Give the proxy a page so the capture has one to report on.
  D.beginFrame(); D.endFrame()

  local clean = D.dump()
  test("with nothing wrong, nothing is reported", clean.disagree == nil)
  test("...but the shadow's account is captured anyway",
    type(clean.shadowBg) == "table")

  -- Now move the glass behind the shadow's back. NOT through D.getGpu():
  -- that DECLARES the write and drops the shadow, which is the right thing
  -- for it to do and the exact opposite of the case being modelled. A real
  -- outsider never announces itself.
  G.gpu.setBackground(0x000000)
  G.gpu.fill(1, STAT, 80, 1, " ")

  local cap = D.dump()
  test("the disagreement is reported", type(cap.disagree) == "table")
  local hit
  for _, m in ipairs(cap.disagree or {}) do if m.row == STAT then hit = m end end
  test("...naming the status row", hit ~= nil)
  if hit then
    eq("...saying what the glass actually holds", 0x000000, hit.glass)
    eq("...and what the shadow believed", T.statusbar_bg, hit.shadow)
  end
  test("...and nothing else (no false alarms on the rows that are fine)",
    cap.disagree and #cap.disagree == 1)
  test("the off-screen page's version of that row is reported too",
    cap.pageBg ~= nil and cap.pageBg[STAT] ~= nil)
  eq("and the active buffer is restored — a page left active is a dead seat",
    0, G.gpu.getActiveBuffer())
end

print()
print("-- and the machinery says what state it was in --")
do
  local st = D.dump().state
  test("a state block comes back", type(st) == "table")
  if st then
    test("it says whether the shadow is on", type(st.shadow) == "boolean")
    test("it reports the colour cache", st.lastBg ~= nil or st.lastFg ~= nil)
    eq("it reports the frame depth", 0, st.frameDepth)
    test("it says whether a page exists", type(st.backbuffer) == "boolean")
    test("it says whether the page is stale", type(st.pageStale) == "boolean")
  end
end

-- ── THE POINT: a fault the shadow cannot see ───────────────────────
-- Blank the status row through the raw GPU. The proxy's shadow still
-- believes the row is painted -- that is the whole bug class -- so a dump
-- that trusted the shadow would report a perfect screen.
print()
print("-- a fault behind the cache's back --")
do
  local raw = D.getGpu()
  raw.setBackground(0x000000)
  raw.fill(1, STAT, 80, 1, " ")

  local cap = D.dump()
  eq("still read from the glass", "glass", cap.source)
  local runs = cap.bg[STAT]
  test("the dump SHOWS the row is black",
    runs and #runs == 1 and runs[1].c == 0x000000)
  test("...and black is not the bar colour (so this is a real difference)",
    T.statusbar_bg ~= 0x000000)
  test("the text is gone from the capture too",
    (cap.lines[STAT] or ""):find("Clock", 1, true) == nil)
end

-- ── The fallback is labelled, not silent ───────────────────────────
-- On a GPU with no `get`, the shadow is all there is. That is fine; what
-- is not fine is a capture that does not say so.
print()
print("-- when gpu.get is unavailable --")
do
  local G2 = fixture.newGlass(40, 12)
  G2.gpu.get = nil                       -- a GPU that cannot be read back
  G2.install()
  package.loaded["kernel.screen"] = nil
  package.loaded["kernel.display"] = nil
  local screen2 = require("kernel.screen")
  screen2.init()
  local D2 = screen2.displayProxy(1)
  D2.fill(1, 1, 40, 12, " ", 0xFFFFFF, 0x224466)
  local cap = D2.dump()
  test("a dump still comes back", type(cap) == "table")
  test("...and admits it is not the glass",
    cap.source == "shadow" or cap.source == "empty")
  test("...with the source named, never nil", cap.source ~= nil)
end

-- ── The command writes the colour map ──────────────────────────────
-- The capture is only useful if screendump actually puts the colours in
-- the file. Checked at the source, since driving the command needs the
-- whole shell.
print()
print("-- the command records what the capture holds --")
do
  local src
  for _, p in ipairs({ base .. "../../../tos/shell/panels/commands/core.lua",
      "tos/shell/panels/commands/core.lua",
      "TOS-Dev/tos/shell/panels/commands/core.lua" }) do
    local fh = io.open(p, "r")
    if fh then src = fh:read("*a"); fh:close(); break end
  end
  test("core.lua is readable", src ~= nil)
  if src then
    local body = src:match("C%.screendump = function.-\n  end")
    test("found the screendump command", body ~= nil)
    if body then
      test("it writes the background runs",
        body:find("cap.bg", 1, true) ~= nil)
      test("it records which surface answered",
        body:find("cap.source", 1, true) ~= nil)
      test("it records the theme colours to compare against",
        body:find("statusbar_bg", 1, true) ~= nil)
      test("it writes the cache-vs-glass section",
        body:find("cap.disagree", 1, true) ~= nil)
      test("it writes the machinery state",
        body:find("cap.state", 1, true) ~= nil)
    end
  end
end

-- ── It must not freeze the machine doing it ────────────────────────
-- One component call per cell is ~2000 on an 80x25 screen. Holding the
-- box for that is the mistake SRM had.
print()
print("-- and it yields while it works --")
do
  local src
  for _, p in ipairs({ base .. "../../../tos/kernel/screen.lua",
      "tos/kernel/screen.lua", "TOS-Dev/tos/kernel/screen.lua" }) do
    local fh = io.open(p, "r")
    if fh then src = fh:read("*a"); fh:close(); break end
  end
  test("screen.lua is readable", src ~= nil)
  if src then
    local body = src:match("function proxy%.dump%(%).-\n  end")
    test("found proxy.dump", body ~= nil)
    test("...and it yields between rows",
      body ~= nil and body:find("coopYieldScreen", 1, true) ~= nil)
    test("...preferring gpu.get over the shadow",
      body ~= nil and body:find("d.gpu.get", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
