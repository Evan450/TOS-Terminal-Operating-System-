-- ╔══════════════════════════════════════════════════════╗
-- ║  Test: panels mouse input (shell.panels.mouse)         ║
-- ║                                                        ║
-- ║  The handler is dependency-injected, so it unit-tests   ║
-- ║  off-box against the REAL Extras mouse driver when the  ║
-- ║  sibling TOS-Extras tree is present (an inline fallback  ║
-- ║  parser keeps the test runnable standalone).             ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_panels_mouse.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_panels_mouse.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rels)
  for _, p in ipairs(rels) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

-- The module under test.
local mouseModChunk = tryload({
  base .. "../../../tos/shell/panels/mouse.lua",
  "tos/shell/panels/mouse.lua",
  "TOS-Dev/tos/shell/panels/mouse.lua",
})
if not mouseModChunk then
  print("FAIL: could not load shell/panels/mouse.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local mouseMod = mouseModChunk()

-- ui.lua provides the span composers draw.topBar uses; the test seeds
-- S._menuSpans/S._tabSpans through the SAME functions so the fixture
-- mirrors a real draw.
local uiChunk = tryload({
  base .. "../../../tos/shell/panels/ui.lua",
  "tos/shell/panels/ui.lua",
  "TOS-Dev/tos/shell/panels/ui.lua",
})
if not uiChunk then
  print("FAIL: could not load shell/panels/ui.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local uiMod = uiChunk()

-- The driver: prefer the real Extras lib; fall back to a minimal
-- equivalent so this test has no hard cross-repo dependency.
local driverChunk = tryload({
  base .. "../../../../TOS-Extras/modules/mouse/usr/lib/mouse.lua",
  "../TOS-Extras/modules/mouse/usr/lib/mouse.lua",
  "TOS-Extras/modules/mouse/usr/lib/mouse.lua",
})
local driver
if driverChunk then
  driver = driverChunk()
  print("(using the real TOS-Extras mouse driver v" .. tostring(driver._VERSION) .. ")")
else
  driver = {
    parse = function(name, screen, x, y, k)
      if name == "touch" then return { type = "click", x = x, y = y, button = k or 0 } end
      if name == "scroll" then
        return { type = "scroll", x = x, y = y, dir = (k or 0) >= 0 and 1 or -1 }
      end
      if name == "drag" or name == "drop" then return { type = name, x = x, y = y } end
      return nil
    end,
  }
  print("(TOS-Extras tree not found; using fallback driver stub)")
end
package.loaded["mouse"] = driver

-- ── Fixture ──────────────────────────────────────────────────
local calls
local function record(what) return function(...) calls[#calls + 1] = { what, ... } end end
local function called(what)
  for _, c in ipairs(calls) do if c[1] == what then return c end end
  return nil
end

local S, deps
local function freshState()
  calls = {}
  S = {
    W = 80, H = 25, tier = 2,
    MENU_ROW = 1, RAIL_ROW = 2, LIST_TOP = 3, SUM_ROW = 22,
    OUT_ROW = 23, CMD_ROW = 24, STAT_ROW = 25, LIST_H = 19,
    tabs = { { type = "shell", label = "Shell" } },
    activeTab = 1,
    browser = { path = "/", sel = 1, scroll = 0, files = {
      { name = "..", dir = true },
      { name = "docs", dir = true },
      { name = "a.lua", dir = false, sz = 10 },
      { name = "b.txt", dir = false, sz = 20 },
    } },
    menuFocused = false, menuIdx = 1, menuOpen = nil, menuSel = 1,
    ctxOpen = false, ctxItems = {}, ctxSel = 1, ctxX = 1, ctxY = 1,
    T = { warning = 0xFFFF55 },
    F = { exists = function(p) return p == "/usr/lib/mouse.lua" end },
    -- pre-seed the probe cache with the loaded driver (M.available is
    -- exercised separately below)
    _mouseLib = driver,
  }
  deps = {
    menuDefs = {
      { label = "File", items = {
        { label = "New File", action = "newfile" },
        { sep = true },
        { label = "Quit", action = "quit", key = "F10" },
      }},
      { label = "Tools", items = {
        { label = "Lua REPL", action = "lua" },
      }},
    },
    menuExecute = function(item)
      calls[#calls + 1] = { "menuExecute", item.action }
      S.menuOpen = nil; S.menuFocused = false  -- mirrors menus.execute
      if item.action == "quit" then return "exit" end
    end,
    ctxExecute = function(action)
      calls[#calls + 1] = { "ctxExecute", action }
      S.ctxOpen = false  -- mirrors ctxMod.execute
    end,
    openContextMenu = function()
      calls[#calls + 1] = { "openContextMenu" }
      S.ctxOpen = true
    end,
    viewFile        = record("viewFile"),
    navigateUp      = record("navigateUp"),
    navigateInto    = record("navigateInto"),
    closeTab        = record("closeTab"),
    drawFileListRow = record("drawFileListRow"),
  }
end

-- Mirror draw.topBar: store the row-1 spans the mouse hit-tests against.
local function seedSpans()
  S._menuSpans = uiMod.menuSpans(deps.menuDefs)
  S._tabSpans = uiMod.fitChips(S.tabs, S.activeTab, 74, 40)
end
-- Click the middle of tab chip `idx` on row 1.
local function chipClick(idx, btn)
  seedSpans()
  for _, sp in ipairs(S._tabSpans) do
    if sp.idx == idx then
      return mouseMod.handle(S, deps, "touch", "scr",
        math.floor((sp.s + sp.e) / 2), 1, btn or 0)
    end
  end
  error("no chip span for tab " .. idx)
end

local function click(x, y, btn)
  seedSpans()
  return mouseMod.handle(S, deps, "touch", "scr", x, y, btn or 0)
end
local function scroll(x, y, dir)
  return mouseMod.handle(S, deps, "scroll", "scr", x, y, dir)
end

print("=== panels mouse Tests ===")
print()

-- ── Driver probe ─────────────────────────────────────────────
freshState()
S._mouseLib = nil
S.F.exists = function() return false end  -- driver file absent
test("no driver: handle returns nil", nil, click(3, 1))
test("no driver: probe cached false", false, S._mouseLib)

freshState()
test("non-mouse signal ignored", nil,
  mouseMod.handle(S, deps, "key_down", "kb", 0, 28))

-- ── Menu bar toggle ──────────────────────────────────────────
freshState()
test("menu click opens (draw 3)", 3, click(3, 1))      -- " File " = x 2..7
test("menu 1 open", 1, S.menuOpen)
test("menu focus follows", true, S.menuFocused)
test("same label click toggles closed", 3, click(3, 1))
test("menu closed", nil, S.menuOpen)
test("Tools label opens menu 2", 3, click(10, 1))      -- " Tools " = x 9..15
test("menu 2 open", 2, S.menuOpen)

-- ── Dropdown clicks ──────────────────────────────────────────
freshState()
click(3, 1)  -- open File menu (def._x defaults to 2; dropdown at y=2)
local d1 = click(5, 3)  -- first item row: "New File"
test("dropdown item executes (draw 3)", 3, d1)
test("menuExecute got 'newfile'", "newfile", (called("menuExecute") or {})[2])

freshState()
click(3, 1)
local sepDraw = click(5, 4)  -- separator row
test("separator click: stays open", 3, sepDraw)
test("separator click: no execute", nil, called("menuExecute"))
test("menu still open", 1, S.menuOpen)

freshState()
click(3, 1)
local dq, rq = click(5, 5)   -- "Quit" row
test("quit item draw 3", 3, dq)
test("menu action result propagates ('exit')", "exit", rq)

freshState()
click(3, 1)
test("click outside dropdown closes", 3, click(60, 15))
test("outside click: menu closed", nil, S.menuOpen)
test("outside click: nothing executed", nil, called("menuExecute"))

-- ── Tab chips (right-aligned on the merged row 1) ────────────
freshState()
S.tabs[2] = { type = "view", label = "Help", content = {}, offset = 0 }
test("chip click switches (draw 3)", 3, chipClick(2))
test("active tab is 2", 2, S.activeTab)
test("right-click closes view tab", 3, chipClick(2, 1))
test("closeTab(2) called", 2, (called("closeTab") or {})[2])

freshState()
S.tabs[2] = { type = "edit", label = "x.lua", modified = true,
              lines = { "" }, curRow = 1, curCol = 1, viewTop = 1 }
-- modified edit tab renders as a BUSY chip "[x.lua]" (grammar rule 5)
chipClick(2, 1)
test("right-click on modified edit tab does NOT close", nil, called("closeTab"))
test("...but surfaces the tab", 2, S.activeTab)
test("...and warns", "Unsaved changes — close with F4", (S.lastOut or {})[1])

-- Menu click from a NON-shell tab jumps to the shell tab first (F9 parity).
freshState()
S.tabs[2] = { type = "view", label = "Help", content = {}, offset = 0 }
S.activeTab = 2
test("menu click on non-shell tab opens menu", 3, click(3, 1))
test("...and lands on the shell tab", 1, S.activeTab)
test("...with the menu open", 1, S.menuOpen)

-- «N overflow chip: with more tabs than fit, clicking « pulls the
-- nearest hidden tab into view — repeated clicks reach EVERY tab.
freshState()
for i = 2, 6 do
  S.tabs[i] = { type = "view", label = "Longtabname" .. i, content = {}, offset = 0 }
end
S.activeTab = 6
local function moreSpan()
  seedSpans()
  for _, sp in ipairs(S._tabSpans) do
    if sp.state == "more" then return sp end
  end
  return nil
end
test("overflow: «N chip present with 6 tabs", true, moreSpan() ~= nil)
-- « is previous-tab (wrapping): five clicks from tab 6 reach tab 1,
-- one more wraps to 6 — every tab is mouse-reachable regardless of
-- how many exist.
for _ = 1, 5 do
  local sp = moreSpan()
  if sp then click(sp.s, 1) end
end
test("overflow: five « clicks walk 6 -> 1", 1, S.activeTab)
local sp = moreSpan()
if sp then click(sp.s, 1) end
test("overflow: « wraps from the front to the last tab", 6, S.activeTab)

-- ── File list ────────────────────────────────────────────────
freshState()
local r1 = click(10, S.LIST_TOP + 1)  -- row 2: "docs"
test("list click selects row (fast path draw 0)", 0, r1)
test("selection moved to 2", 2, S.browser.sel)
test("two rows repainted", "drawFileListRow", (calls[1] or {})[1])
test("second click activates dir", 3, click(10, S.LIST_TOP + 1))
test("navigateInto('docs')", "docs", (called("navigateInto") or {})[2])

freshState()
S.browser.sel = 3  -- selection elsewhere, so the first click only selects
test("click on '..' selects it first", 0, click(10, S.LIST_TOP))
test("second click on '..' activates", 3, click(10, S.LIST_TOP))
test("navigateUp called", "navigateUp", (called("navigateUp") or {})[1])

-- Left vs right click on a FILE must differ: left = quick action (view),
-- right = context menu (the regression the operator reported).
freshState()
S.browser.sel = 1                              -- so the first click only selects
test("left-click file selects first", 0, click(10, S.LIST_TOP + 2))  -- a.lua
test("selection moved to file", 3, S.browser.sel)
test("second left-click views the file", 3, click(10, S.LIST_TOP + 2))
test("viewFile called (not the context menu)", "viewFile", (called("viewFile") or {})[1])
test("left-click did NOT open the context menu", nil, called("openContextMenu"))

freshState()
test("right-click row opens context menu", 3, click(10, S.LIST_TOP + 2, 1))
test("selection follows right-click", 3, S.browser.sel)
test("openContextMenu called", "openContextMenu", (called("openContextMenu") or {})[1])
test("right-click did NOT view the file", nil, called("viewFile"))

freshState()
test("click below last file: no-op", 0, click(10, S.LIST_TOP + 10))
test("selection unchanged", 1, S.browser.sel)

-- ── Context menu clicks ──────────────────────────────────────
freshState()
S.ctxOpen = true
S.ctxItems = {
  { label = "View", action = "ctx_view", key = "F3" },
  { sep = true },
  { label = "Delete", action = "ctx_delete", key = "F8" },
}
S.ctxX, S.ctxY = 30, 8
test("ctx item click draw 3", 3, click(32, 9))
test("ctxExecute('ctx_view')", "ctx_view", (called("ctxExecute") or {})[2])

freshState()
S.ctxOpen = true
S.ctxItems = { { label = "View", action = "ctx_view" } }
S.ctxX, S.ctxY = 30, 8
click(5, 20)
test("click outside ctx menu closes it", false, S.ctxOpen)
test("...without executing", nil, called("ctxExecute"))

-- ── Scrolling ────────────────────────────────────────────────
freshState()
test("wheel down moves selection down (fast path)", 0, scroll(10, 10, -1))
test("sel now 2", 2, S.browser.sel)
test("wheel up moves selection up", 0, scroll(10, 10, 1))
test("sel back to 1", 1, S.browser.sel)
test("wheel up at top: no-op", 0, scroll(10, 10, 1))

freshState()
S.tabs[2] = { type = "view", label = "Help", offset = 0, content = {} }
for i = 1, 100 do S.tabs[2].content[i] = { "line " .. i, 0xFFFFFF } end
S.activeTab = 2
test("view scroll down (draw 1)", 1, scroll(10, 10, -1))
test("offset advanced by 3", 3, S.tabs[2].offset)
test("view scroll up", 1, scroll(10, 10, 1))
test("offset back to 0", 0, S.tabs[2].offset)
test("scroll up at top: no-op", 0, scroll(10, 10, 1))

-- ── Editor ───────────────────────────────────────────────────
freshState()
S.tabs[2] = { type = "edit", label = "x.lua", modified = false,
              lines = { "hello", "world line", "third" },
              curRow = 1, curCol = 1, viewTop = 1 }
S.activeTab = 2
-- tier 2 => gutterW = max(#"3", 2) + 1 = 3
test("editor click draw 1", 1, click(6, 3))
test("cursor row from click", 2, S.tabs[2].curRow)
test("cursor col gutter-adjusted", 3, S.tabs[2].curCol)
test("click past line end clamps col", 1, click(70, 3))
test("clamped col = len+1", #S.tabs[2].lines[2] + 1, S.tabs[2].curCol)
test("editor wheel down moves cursor", 1, scroll(10, 10, -1))
test("cursor clamped to last line", 3, S.tabs[2].curRow)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") return true end
