-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: the merged Home surface                  ║
-- ║                                                            ║
-- ║  One tab, two views. Before this, the Desktop was a tab    ║
-- ║  beside the Shell and F2 cycled tabs — so "where is my     ║
-- ║  prompt?" had two answers and F2's meaning depended on     ║
-- ║  which tabs happened to be open. The merge makes tiles and ║
-- ║  files two VIEWS of one tab with the prompt resident in    ║
-- ║  both, and gives F2 to the `view` action in shell/keys.lua ║
-- ║  where an operator can rebind it.                          ║
-- ║                                                            ║
-- ║  Pinned here, because every one of them is a decision that ║
-- ║  a later change could quietly undo:                        ║
-- ║    · F2 is the `view` action, not a tab key                ║
-- ║    · the bottom four rows are identical in both views      ║
-- ║    · every printable key falls through to the prompt —     ║
-- ║      including bare digits, which is why quick-launch is   ║
-- ║      Alt+1-9                                               ║
-- ║    · split mode still has the pre-merge behaviour          ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_home_view.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- ── Fake machine (state.lua requires `computer` at load) ──────
package.loaded["computer"] = {
  uptime      = function() return 0 end,
  freeMemory  = function() return 900 * 1024 end,
  totalMemory = function() return 1024 * 1024 end,
}
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local keys     = require("shell.keys")
local home     = require("shell.panels.home")
local desktop  = require("shell.panels.desktop")
local stateMod = require("shell.panels.state")

print("=== Home (merged surface) Tests ===")
print()

-- ── A display stub that records nothing but accepts everything ──
local function newDisplay()
  return {
    getGpu     = function() return nil end,
    getSize    = function() return 80, 25 end,
    getGpuTier = function() return 3 end,
    getTheme   = function()
      return { bg = 0, fg = 1, dim = 2, title = 3, highlight = 4,
               sel_fg = 5, sel_bg = 6, border = 7, error = 8 }
    end,
    fill = function() end,
    set  = function() end,
  }
end

local function newState(ctx)
  ctx = ctx or {}
  ctx.D = ctx.D or newDisplay()
  ctx.F = ctx.F or { exists = function() return false end }
  ctx.SC = ctx.SC or { get = function() return "tos" end }
  ctx.who = ctx.who or "root"
  return stateMod.new(ctx)
end

-- ══════════════════════════════════════════════════════════════
-- keys.lua: `view` is the sixth action, and it is F2
-- ══════════════════════════════════════════════════════════════
do
  test("keys: `view` is a known action", keys.DEFAULTS.view ~= nil)
  eq("keys: view defaults to F2", "F2", keys.label("view"))
  test("keys: F2's scancode means view", keys.is("view", nil, 60))
  test("keys: F3 does not mean view", not keys.is("view", nil, 61))
  local listed = false
  for _, row in ipairs(keys.actions()) do
    if row.action == "view" then listed = true; test("keys: view has help", #row.help > 0) end
  end
  test("keys: view appears in the operator listing", listed)
end

-- ══════════════════════════════════════════════════════════════
-- Layout: the bottom four rows do not move between views
-- ══════════════════════════════════════════════════════════════
do
  local S = newState()
  eq("layout: summary rail at H-3", 22, S.SUM_ROW)
  eq("layout: output row at H-2", 23, S.OUT_ROW)
  eq("layout: prompt at H-1", 24, S.CMD_ROW)
  eq("layout: status bar at H", 25, S.STAT_ROW)
  -- Files keeps the 19 rows the browser has always had; tiles spend one
  -- of them on the band rail that carries the page counter.
  eq("layout: file list keeps 19 rows", 19, S.LIST_H)
  eq("layout: band rail at row 3", 3, S.BAND_ROW)
  eq("layout: tiles start at row 4", 4, S.TILE_TOP)
  eq("layout: tiles get 18 rows", 18, S.TILE_H)
end

-- ══════════════════════════════════════════════════════════════
-- The tab itself
-- ══════════════════════════════════════════════════════════════
do
  local S = newState()
  eq("home: the tab is called Home", "Home", S.tabs[1].label)
  test("home: merged by default", home.enabled(S))
  eq("home: lands on files unless told otherwise", "files", home.view(S))

  local T2 = newState({ homeView = "tiles" })
  eq("home: landing preference selects the view", "tiles", home.view(T2))

  test("home: toggle flips to tiles", home.toggle(S) and home.isTiles(S))
  test("home: toggle flips back", home.toggle(S) and not home.isTiles(S))
  test("home: setView to the current view reports no change",
    home.setView(S, "files") == false)
end

-- ══════════════════════════════════════════════════════════════
-- Split mode: the pre-merge behaviour, intact
-- ══════════════════════════════════════════════════════════════
do
  local S = newState({ uiSplit = true })
  eq("split: the tab is still called Shell", "Shell", S.tabs[1].label)
  test("split: not the merged surface", not home.enabled(S))
  eq("split: always the file view", "files", home.view(S))
  test("split: toggle does nothing", home.toggle(S) == false)
  eq("split: F2 still cycles tabs", "F2", home.cycleKeyLabel(S))
  eq("merged: tab cycling moved to Tab", "Tab", home.cycleKeyLabel(newState()))
end

-- ══════════════════════════════════════════════════════════════
-- The tile model: Home drops the Files tile
-- ══════════════════════════════════════════════════════════════
do
  local function has(apps, id)
    for _, a in ipairs(apps) do if a.id == id then return true end end
    return false
  end
  local deps = { entry = function() return nil end,
                 needMet = function() return true end,
                 userTier = 3 }
  local split = desktop.buildApps(deps)
  test("split: the Desktop still has a Files tile", has(split, "files"))

  deps.home = true
  local merged = desktop.buildApps(deps)
  test("home: no Files tile — F2 is the way there", not has(merged, "files"))
  test("home: everything else survives",
    has(merged, "settings") and has(merged, "logout") and has(merged, "help"))
  eq("home: exactly one tile fewer", #split - 1, #merged)
end

-- ══════════════════════════════════════════════════════════════
-- Paging — 5x3 on the 80x25 design target, and the band says so
-- ══════════════════════════════════════════════════════════════
local function tiledState(n)
  local S = newState({ homeView = "tiles" })
  local tab = S.tabs[1]
  tab.apps = {}
  for i = 1, n do
    tab.apps[i] = { id = "pkg:" .. i, label = "app" .. i, cmd = "app" .. i,
                    glyph = "*", hint = "Installed package command" }
  end
  tab.sel = 1
  return S, tab
end

do
  local S, tab = tiledState(27)
  eq("grid: 15 tiles a page at 80x25", 15, home.perPage(S))
  local page, pages, start = home.pageOf(S, tab)
  eq("page: starts on page 1", 1, page)
  eq("page: 27 tiles make 2 pages", 2, pages)
  eq("page: page 1 starts at offset 0", 0, start)

  tab.sel = 16
  page, pages, start = home.pageOf(S, tab)
  eq("page: tile 16 is on page 2", 2, page)
  eq("page: page 2 starts at offset 15", 15, start)

  -- The band rail is what makes perPage visible; it was always computed
  -- and never shown, which is how a tile on page 2 could be invisible
  -- with nothing on screen admitting it.
  home.drawBand(S, tab)
  test("band: records the < > click targets", S._homeBand ~= nil
    and S._homeBand.row == S.BAND_ROW and S._homeBand.pages == 2)

  local sum = home.summaryText(S, tab)
  test("summary: states the total  (" .. sum .. ")", sum:find("27 tiles", 1, true) ~= nil)
  test("summary: states what is on this page", sum:find("12 shown", 1, true) ~= nil)

  local hint = home.hintText(S, tab)
  test("hint: names the flip key  (" .. hint .. ")", hint:find("F2 Files", 1, true) ~= nil)
  test("hint: names the page key", hint:find("PgUp", 1, true) ~= nil)
  test("hint: leads with the selected tile", hint:find("app16", 1, true) ~= nil)

  -- One page: no page counter to draw, and no stale click target left.
  local S1, tab1 = tiledState(4)
  home.drawBand(S1, tab1)
  test("band: no page markers when everything fits", S1._homeBand == nil)
end

-- ══════════════════════════════════════════════════════════════
-- Alt+1-9 vs a bare digit
-- ══════════════════════════════════════════════════════════════
-- The discriminator the whole quick-launch move rests on: OC sends a
-- bare digit with BOTH its character and its scancode, and suppresses
-- the character when a modifier is held. Bare digits belong to the
-- prompt now, so only the modified form may launch anything.
do
  eq("alt: Alt+1 is slot 1", 1, home._altDigit(nil, 2))
  eq("alt: Alt+1 (char 0) is slot 1", 1, home._altDigit(0, 2))
  eq("alt: Alt+9 is slot 9", 9, home._altDigit(0, 10))
  eq("alt: a bare 1 is not a slot", nil, home._altDigit(49, 2))
  eq("alt: a bare 9 is not a slot", nil, home._altDigit(57, 10))
  eq("alt: Alt+0 is not a slot", nil, home._altDigit(0, 11))
  eq("alt: a letter is not a slot", nil, home._altDigit(0, 32))
end

-- ══════════════════════════════════════════════════════════════
-- Input: what the tiles own, and what falls through to the prompt
-- ══════════════════════════════════════════════════════════════
do
  local S, tab = tiledState(27)
  local ran = nil
  local deps = { exec = function(cmd) ran = cmd end }

  -- Anything printable is the prompt's. This is the contract that makes
  -- a resident prompt worth having, so it is tested before anything else.
  eq("input: a letter falls through to the prompt",
    nil, home.handleKey(S, tab, 100, 32, deps))
  eq("input: a bare digit falls through to the prompt",
    nil, home.handleKey(S, tab, 49, 2, deps))
  eq("input: space with a command on the line stays with the prompt",
    nil, (function() S.cmdline = "df"; return home.handleKey(S, tab, 32, 57, deps) end)())
  S.cmdline = ""

  -- Selection.
  home.handleKey(S, tab, nil, 205, deps)
  eq("input: Right moves the selection", 2, tab.sel)
  home.handleKey(S, tab, nil, 208, deps)
  eq("input: Down moves by a row of five", 7, tab.sel)
  home.handleKey(S, tab, nil, 200, deps)
  eq("input: Up moves back", 2, tab.sel)
  home.handleKey(S, tab, nil, 209, deps)
  eq("input: PgDn pages by a full page", 17, tab.sel)
  home.handleKey(S, tab, nil, 201, deps)
  eq("input: PgUp pages back", 2, tab.sel)
  home.handleKey(S, tab, nil, 199, deps)
  eq("input: Home jumps to the first tile", 1, tab.sel)
  home.handleKey(S, tab, nil, 207, deps)
  eq("input: End jumps to the last tile", 27, tab.sel)

  -- Enter: the selection when the line is empty, the command when it is
  -- not. Same rule the file browser has always used.
  tab.sel = 3
  local dl = home.handleKey(S, tab, nil, 28, deps)
  eq("input: Enter on an empty line opens the tile", "app3", ran)
  eq("input: ...and asks for a full redraw", 3, dl)

  ran = nil
  S.cmdline = "df"
  eq("input: Enter with a command on the line is the prompt's",
    nil, home.handleKey(S, tab, nil, 28, deps))
  eq("input: ...and launches nothing", nil, ran)
  S.cmdline = ""

  -- Alt+digit launches within the current page, not the whole list.
  ran = nil
  tab.sel = 16                       -- page 2
  home.handleKey(S, tab, 0, 3, deps) -- Alt+2
  eq("input: Alt+2 opens the second tile ON THIS PAGE", "app17", ran)
end

-- ══════════════════════════════════════════════════════════════
-- Activation of the non-command tile kinds
-- ══════════════════════════════════════════════════════════════
do
  local S = newState({ homeView = "tiles" })
  local tab = S.tabs[1]
  tab.apps = { { id = "files", kind = "tab", label = "Files" } }
  tab.sel = 1
  home.activate(S, tab, 1, {})
  eq("activate: a Files tile flips the view rather than hunting a tab",
    "files", home.view(S))
end

-- ══════════════════════════════════════════════════════════════
-- A flip that cannot load its model refuses, and says why
-- ══════════════════════════════════════════════════════════════
-- desktop.lua is loaded lazily so a tight box does not pay to parse it
-- at shell start — which means the box that most needs the file list is
-- the one where the tile model may not fit. Landing on a blank grid with
-- no explanation would be the worst of both.
do
  local S = newState()
  local saved = package.loaded["shell.panels.desktop"]
  package.loaded["shell.panels.desktop"] = nil
  package.preload["shell.panels.desktop"] = function() error("out of memory") end
  home._forgetDesktop()

  test("degrade: the flip to tiles is refused", home.setView(S, "tiles") == false)
  eq("degrade: and the view is unchanged", "files", home.view(S))
  test("degrade: with a line saying why",
    S.lastOut ~= nil and S.lastOut[1]:find("Tiles unavailable", 1, true) ~= nil)

  package.preload["shell.panels.desktop"] = nil
  package.loaded["shell.panels.desktop"] = saved
  home._forgetDesktop()
  test("degrade: and it works again once the module loads",
    home.setView(S, "tiles") == true)
end

-- ══════════════════════════════════════════════════════════════
-- Click targets for the view flip
-- ══════════════════════════════════════════════════════════════
do
  local S = newState()
  home.markToggle(S, S.RAIL_ROW, 40, 49)
  test("click: the rail legend is clickable", home.hitToggle(S, 45, S.RAIL_ROW))
  test("click: not one column past it", not home.hitToggle(S, 50, S.RAIL_ROW))
  test("click: not on another row", not home.hitToggle(S, 45, S.OUT_ROW))
  home.markToggle(S, S.RAIL_ROW, nil, nil)
  test("click: the target clears with the text", not home.hitToggle(S, 45, S.RAIL_ROW))
end

-- ══════════════════════════════════════════════════════════════
-- The key that flips the view, read through keys.lua
-- ══════════════════════════════════════════════════════════════
do
  local S = newState()
  test("view key: F2 flips", home.isViewKey(S, nil, 60))
  test("view key: F4 does not", not home.isViewKey(S, nil, 62))
  eq("view key: legends read F2 from the bind", "F2", home.viewKeyLabel(S))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
