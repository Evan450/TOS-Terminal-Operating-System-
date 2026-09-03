-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what the shell actually leaves on the glass  ║
-- ║                                                                ║
-- ║  Every other panels test checks a decision — which command,    ║
-- ║  which row, which colour. This one runs the REAL renderer      ║
-- ║  against a screen that stores pixels and then LOOKS at it.     ║
-- ║                                                                ║
-- ║  70-screen-truth.lua does this in the emulator and opens with  ║
-- ║  "no off-box test can see that because off-box there is no     ║
-- ║  glass". That was true when it was written. fixture_glass.lua  ║
-- ║  is glass, and this runs on every commit instead of opt-in on  ║
-- ║  a machine somebody has to boot.                               ║
-- ║                                                                ║
-- ║  Two properties, both of which have been broken in the past:   ║
-- ║                                                                ║
-- ║  COVERAGE. A full redraw must leave no cell untouched. A cell  ║
-- ║  the frame does not write keeps whatever was under it — the    ║
-- ║  file-list row that stopped one column short showed up as a    ║
-- ║  cursor "partly in one place and fully in the other".          ║
-- ║                                                                ║
-- ║  SUFFICIENCY. A PARTIAL redraw must repaint everything that    ║
-- ║  changed. Level 1 touches four rows; asking for it after       ║
-- ║  something else moved leaves the operator looking at stale     ║
-- ║  pixels. Tab-completion did exactly that: it clears the inline ║
-- ║  output overlay — which is drawn upward over the file list —   ║
-- ║  and asked for level 1, so up to fifteen rows of the previous  ║
-- ║  command's output stayed on screen over the list.              ║
-- ║                                                                ║
-- ║  The measure for both is the same and needs no golden file:    ║
-- ║  compare against what a FULL redraw of the SAME state paints.  ║
-- ║  Any difference is something the operator can see that is not  ║
-- ║  true any more.                                                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_shell_glass.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_shell_glass.lua"
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
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;TOS-Dev/tos/?/init.lua;" .. package.path

local display  = require("kernel.display")
local screen   = require("kernel.screen")
local stateMod = require("shell.panels.state")
local drawMod  = require("shell.panels.draw")
local T = display.THEME or display.getTheme()

-- Sanity: the fixture's unicode really is in play. Without it every column
-- assertion below measures bytes and the whole file is theatre.
do
  local okU, ustr = pcall(require, "kernel.ustr")
  test("kernel.ustr is measuring COLUMNS, not bytes",
    okU and ustr and ustr.width("F2 \226\150\184 tiles") == 10)
end

local widgetDefs = {
  mem  = function() return "512K" end,
  time = function() return "12:34" end,
  user = function() return "evan" end,
}

local function freshState(w, h, tier)
  G.gpu.setResolution(w, h)
  screen.init()
  local D = screen.displayProxy(1)
  local S = {
    D = D, T = T, W = w, H = h,
    K = { getConfig = function() return nil end, getNet = function() return nil end },
    E = { push = function() end }, P = {}, F = {}, U = nil, SC = nil, NM = nil,
    who = "evan", cwd = "/home/evan", tier = tier or 3, st = "tok",
    tabs = { { type = "shell", label = "Home" } }, activeTab = 1,
    cmdline = "ls -l", cmdCursor = 6, cmdSel = nil, mods = {},
    browser = { path = "/home/evan", sel = 2, scroll = 0, files = {
      { name = "..", dir = true, sz = 0 },
      { name = "notes.txt", dir = false, sz = 1234 },
      { name = "src", dir = true, sz = 0 },
      { name = "a.lua", dir = false, sz = 88 },
    } },
  }
  stateMod.recomputeLayout(S)
  return S
end

-- ============================================================
-- 1. A full redraw leaves no cell untouched
-- ============================================================
print()
print("-- coverage: every cell painted by one full redraw --")

local function coverage(name, w, h, tier, mutate)
  local S = freshState(w, h, tier)
  if mutate then mutate(S) end
  local ok, err = pcall(drawMod.all, S, widgetDefs)
  if not ok then
    test(name .. " -- draw failed: " .. tostring(err):sub(1, 70), false)
    return
  end
  local n, where = G.describe(G.unpainted())
  test(string.format("%s (%dx%d)%s", name, w, h,
    n == 0 and "" or "  -- " .. n .. " unpainted: " .. where:sub(1, 90)), n == 0)
end

coverage("file view", 80, 25, 3)
coverage("file view, tier 1", 80, 25, 1)
coverage("narrow screen", 50, 16, 3)
coverage("tiny screen", 40, 12, 3)
coverage("wide screen", 160, 50, 3)
coverage("empty directory", 80, 25, 3, function(S)
  S.browser.files = {}; S.browser.sel = 1
end)
coverage("with a one-line result", 80, 25, 3, function(S)
  S.lastOut = { "copied 3 files", T.highlight }
end)
coverage("with a 15-line result", 80, 25, 3, function(S)
  local l = {}
  for i = 1, 15 do l[i] = { "line " .. i, T.fg } end
  S.outLines = l
end)
coverage("empty command line", 80, 25, 3, function(S)
  S.cmdline = ""; S.cmdCursor = 1
end)
coverage("over-long command line", 80, 25, 3, function(S)
  S.cmdline = string.rep("abcdefghij", 12); S.cmdCursor = #S.cmdline + 1
end)
coverage("over-long cwd", 80, 25, 3, function(S)
  S.cwd = "/home/evan/a/very/deeply/nested/path/that/goes/on/and/on"
  S.browser.path = S.cwd
end)
coverage("elevated shell", 80, 25, 3, function(S) S._sudo = { origSt = "x" } end)
coverage("scrolled file list", 80, 25, 3, function(S)
  local many = {}
  for i = 1, 60 do many[i] = { name = "file" .. i .. ".txt", dir = false, sz = i * 10 } end
  S.browser.files = many; S.browser.sel = 40; S.browser.scroll = 30
end)

-- ============================================================
-- 2. The two rows an operator complained about
-- ============================================================
print()
print("-- the status bar and the cursor --")
do
  local S = freshState(80, 25, 3)
  pcall(drawMod.all, S, widgetDefs)
  eq("the status row wears the status bar's background",
    T.statusbar_bg, G.bgAt(40, S.STAT_ROW))

  local cursors = {}
  for x = 1, S.W do
    if G.bgAt(x, S.CMD_ROW) == T.highlight then cursors[#cursors + 1] = x end
  end
  eq("exactly one cursor on the command row", 1, #cursors)

  -- The frame must be idempotent: redrawing the same state twice cannot
  -- move a pixel. This is what the off-screen page got wrong.
  local a = G.snapshot()
  pcall(drawMod.all, S, widgetDefs)
  local n = G.describe(G.diffRuns(a, G.snapshot()))
  eq("an identical second redraw changes nothing", 0, n)
end

-- ============================================================
-- 3. A partial redraw has to be ENOUGH
-- ============================================================
-- applyDraw level 1 paints topBar + output area + cmdRow + statusBar. Level 2
-- adds the rail, the file list and the summary rail. Mirrored here so the
-- test measures the same thing the event loop does.
print()
print("-- sufficiency: a partial redraw leaves nothing stale --")

local function level1(S)
  drawMod.topBar(S)
  if S.outLines and #S.outLines > 0 then drawMod.outLines(S)
  elseif S.lastOut then drawMod.outRow(S, S.lastOut[1], S.lastOut[2])
  else drawMod.idleHint(S) end
  drawMod.cmdRow(S); drawMod.statusBar(S, widgetDefs)
end
local function level2(S)
  drawMod.topBar(S); drawMod.rail(S); drawMod.fileList(S); drawMod.sumRail(S)
  if S.outLines and #S.outLines > 0 then drawMod.outLines(S)
  elseif S.lastOut then drawMod.outRow(S, S.lastOut[1], S.lastOut[2])
  else drawMod.idleHint(S) end
  drawMod.cmdRow(S); drawMod.statusBar(S, widgetDefs)
end

--- settle -> mutate -> partial redraw -> compare against a full redraw of the
--- same state. Returns the number of cells the operator would be seeing wrong.
local function staleAfter(mutate, partial)
  local S = freshState(80, 25, 3)
  pcall(drawMod.all, S, widgetDefs)
  mutate(S, function() pcall(drawMod.all, S, widgetDefs) end)
  partial(S)
  local seen = G.snapshot()
  pcall(drawMod.all, S, widgetDefs)
  return (G.describe(G.diffRuns(seen, G.snapshot()))), S
end

do
  local n = staleAfter(function(S) S.cmdline = "ls -la"; S.cmdCursor = 7 end, level1)
  eq("typing a character needs only level 1", 0, n)
end
do
  local n = staleAfter(function(S) S.lastOut = { "copied 3 files", T.highlight } end, level1)
  eq("a one-line result needs only level 1", 0, n)
end
do
  local n = staleAfter(function(S)
    S.outLines = { { "alpha", T.fg }, { "beta", T.fg }, { "gamma", T.fg } }
  end, level1)
  eq("an overlay APPEARING needs only level 1", 0, n)
end

-- The overlay is drawn upward over the file list, so removing it means those
-- rows have to be repainted — and level 1 does not reach them. This is not a
-- bug to fix in level 1; it is the reason the event loop must floor the draw
-- to 2 when the overlay goes. Pinned as a fact so the rule below has a stated
-- reason rather than being folklore.
do
  local n = staleAfter(function(S, settle)
    local l = {}
    for i = 1, 15 do l[i] = { "line " .. i, T.fg } end
    S.outLines = l; settle(); S.outLines = nil
  end, level1)
  test("an overlay DISAPPEARING is NOT repairable by level 1 ("
    .. n .. " stale cells)", n > 0)
end
do
  local n = staleAfter(function(S, settle)
    local l = {}
    for i = 1, 15 do l[i] = { "line " .. i, T.fg } end
    S.outLines = l; settle(); S.outLines = nil
  end, level2)
  eq("...and level 2 repairs it completely", 0, n)
end

-- ============================================================
-- 4. ...so the event loop must ASK for level 2
-- ============================================================
-- Behavioural coverage would mean standing up the whole event loop with a
-- synthetic key stream. What has to hold is narrow and greppable: whenever
-- the overlay was showing and is now gone, the draw is floored to 2 — stated
-- once, for every handler that clears it, not per site.
print()
print("-- the event loop applies the rule --")
do
  local src
  for _, p in ipairs({ base .. "../../../tos/shell/panels/events.lua",
      "tos/shell/panels/events.lua", "TOS-Dev/tos/shell/panels/events.lua" }) do
    local fh = io.open(p, "r")
    if fh then src = fh:read("*a"); fh:close(); break end
  end
  test("events.lua is readable", src ~= nil)
  if src then
    test("the overlay-gone rule floors the draw to 2",
      src:find("hadOutLines and not S.outLines and draw < 2", 1, true) ~= nil)
    -- Tab-completion is the site that had it wrong; it must still be the
    -- rule that covers it rather than a fix pasted into that branch.
    local tabBranch = src:match("completeCmdline.-draw = 1")
    test("tab-completion still clears the overlay (so the rule is load-bearing)",
      tabBranch ~= nil and tabBranch:find("S.outLines = nil", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
