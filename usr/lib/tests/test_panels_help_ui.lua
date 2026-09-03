-- ╔══════════════════════════════════════════════════════╗
-- ║  Smoke Test: Panels Help/Hint UI                     ║
-- ║  The Help menu and the idle function-key legend added ║
-- ║  for usability must render within the screen width    ║
-- ║  and stay wired to real, guest-safe actions.          ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_panels_help_ui.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- Stub the modules draw.lua pulls in at load time. None are exercised by the
-- menuDefs table or idleHint(), so empty/no-op stubs are enough.
package.loaded["computer"] = { freeMemory = function() return 4096 end }
package.loaded["shell.panels.helpers"] = setmetatable({}, { __index = function() return function() return "" end end })
package.loaded["shell.panels.widgets"] = { getWidgetList = function() return {} end }
package.loaded["shell.panels.ui"] = { fileGlyph = function() return "·" end }

-- Selection maths: the prompt/editor/view highlight renderers call into
-- it. It is a real module with no dependencies of its own, but this test
-- loads draw.lua by PATH rather than through package.path, so `require`
-- has to be handed it here.
do
  local sel
  for _, p in ipairs({ "tos/shell/panels/selection.lua",
      "TOS-Dev/tos/shell/panels/selection.lua",
      "../../../tos/shell/panels/selection.lua" }) do
    local chunk = loadfile(p); if chunk then sel = chunk(); break end
  end
  package.loaded["shell.panels.selection"] = sel
    or { range = function() return nil end,
         contains = function() return false end,
         lineRange = function() return nil end }
end

local here = (arg and arg[0]) or "usr/lib/tests/test_panels_help_ui.lua"
local base = here:gsub("[^/\\]*$", "")
local draw
for _, p in ipairs({ base .. "../../../tos/shell/panels/draw.lua",
    "tos/shell/panels/draw.lua", "TOS-Dev/tos/shell/panels/draw.lua" }) do
  local chunk = loadfile(p); if chunk then draw = chunk(); break end
end
if not draw or not draw.idleHint then
  print("FAIL: could not load draw.lua / idleHint missing")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== Panels Help/Hint UI Tests ===")
print()

-- ── Help menu wiring ────────────────────────────────────────────────
local helpMenu
for _, m in ipairs(draw.menuDefs) do
  if m.label == "Help" then helpMenu = m end
end
test("Help menu exists in the menu bar", true, helpMenu ~= nil)

local actions = {}
if helpMenu then
  for _, it in ipairs(helpMenu.items) do
    if it.action then actions[it.action] = true end
  end
end
test("Help menu offers Quick Help", true, actions.help == true)
test("Help menu offers Keyboard Shortcuts", true, actions.keyhelp == true)
test("Help menu offers Tutorial", true, actions.tutorial == true)
test("Help menu offers About", true, actions.about == true)

-- ── Idle function-key legend renders within width ───────────────────
-- Fake display: capture the (x, text) drawn on the output row.
local function fakeState(W)
  local drawn = {}
  return {
    W = W, OUT_ROW = 10,
    padW = string.rep(" ", W + 4),
    T = { dim = 1, bg = 0 },
    D = { set = function(x, y, text) drawn[#drawn + 1] = { x = x, text = text } end },
  }, drawn
end

for _, W in ipairs({ 80, 50, 26, 12 }) do
  local S, drawn = fakeState(W)
  draw.idleHint(S)
  local line = drawn[1] and drawn[1].text or ""
  test("idle hint fits width " .. W .. " (len<=W)", true, #line <= W)
  test("idle hint shows F1 Help at width " .. W, true, line:find("F1 Help", 1, true) ~= nil)
end

-- A wide-enough screen exposes the full legend (the rightmost entry); a
-- narrow one drops entries from the right (graceful, never a mid-label
-- truncation). The full legend needs ~81 cols, so an 80-col screen shows
-- 8 of 9 — that's the intended degrade, so assert the full set at 100.
do
  local S, drawn = fakeState(100)
  draw.idleHint(S)
  test("wide screen shows full legend (Tab Complete)", true, (drawn[1].text):find("Tab Complete", 1, true) ~= nil)
  local S2, drawn2 = fakeState(12)
  draw.idleHint(S2)
  test("narrow screen drops later entries", false, (drawn2[1].text):find("Quit", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
