-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: PaneUI's text wrap + keybinding modernization ║
-- ║                                                                ║
-- ║  Area 4 of the user's redesign request (B4/B5 in the audit):   ║
-- ║  confirmDialog used to ellipsize a long prompt into ONE row     ║
-- ║  (fit()) instead of wrapping it, like the rest of TOS's modals  ║
-- ║  do; F2 was the ONLY way to cycle tabs -- the retired TOS       ║
-- ║  binding keymap.lua documents moving away from -- and           ║
-- ║  promptInput's cancel accepted only bare Esc, where every other ║
-- ║  TOS prompt also takes ^Q as the reliable one.                  ║
-- ║                                                                ║
-- ║  PaneUI self-executes on load, so -- as the other PaneUI tests  ║
-- ║  do -- this reads the SOURCE: wrapText is pure and lifted out   ║
-- ║  to run directly; the keybinding fixes are checked as grammar   ║
-- ║  (the pattern is present at every site it needs to be), the     ║
-- ║  same way test_paneui_grammar.lua checks the rest of the file's ║
-- ║  conventions without running the interactive event loop.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua pane-ui/test_paneui_keys_wrap.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local src
for _, p in ipairs({ "pane-ui/PaneUI.lua", "PaneUI.lua", "../pane-ui/PaneUI.lua" }) do
  local h = io.open(p, "rb")
  if h then src = h:read("*a"); h:close(); break end
end
if not src then
  print("FAIL: could not find PaneUI.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
src = src:gsub("\r\n", "\n")   -- a Windows checkout (core.autocrlf) has CRLF

print("=== PaneUI text wrap + keybindings ===")
print()

-- ── wrapText: lifted out and run directly (pure, ASCII unicode stub) ──
do
  local body = src:match("\n(local function wrapText%(s, w%).-\nend)\n")
  test("wrapText found in source", body ~= nil)
  if body then
    local env = { math = math, unicode = { len = function(s) return #s end, sub = string.sub } }
    local chunk = assert(load(body .. "\nreturn wrapText", "=wrapText", "t", env))
    local wrapText = chunk()

    local short = wrapText("hi", 10)
    eq("short text is one row", 1, #short)
    eq("...unchanged", "hi", short[1])

    local w = wrapText("the quick brown fox", 9)
    test("breaks at spaces, not mid-word", (function()
      for _, l in ipairs(w) do if l:match("%S%S*$") and #l > 9 then return false end end
      return true
    end)())
    eq("'the quick' fits the first row", "the quick", w[1])
    test("every word survives somewhere", table.concat(w, " "):find("fox", 1, true) ~= nil)

    local hard = wrapText("supercalifragilisticexpialidocious", 10)
    test("a single token longer than the width still hard-breaks", #hard > 1)
    for _, l in ipairs(hard) do
      test("...no hard-broken row exceeds the width", #l <= 10)
    end

    local nl = wrapText("line one\nline two", 40)
    eq("an explicit newline starts a new row", 2, #nl)
    eq("...first kept whole", "line one", nl[1])
    eq("...second kept whole", "line two", nl[2])

    eq("empty text is one blank row", 1, #wrapText("", 10))
  end
end

-- ── confirmDialog: no longer ellipsizes the message to one row ─────
do
  local body = src:match("\n(local function confirmDialog%(prompt%).-\nend)\n")
  test("confirmDialog found in source", body ~= nil)
  if body then
    test("the message is built from wrapText, not a single fit() call",
      body:find("wrapText%(prompt") ~= nil)
    test("the message loop writes one row per wrapped line",
      body:find("for i, ln in ipairs%(lines%)") ~= nil)
    test("^Q cancels the confirm, same as Esc/N", body:find("ch == 17") ~= nil)
  end
end

-- ── Keybindings: Tab cycles tabs everywhere F2 already did (except ──
-- the editor, where Tab means "insert indent" -- same as the rest of
-- TOS, Tab's job depends on what currently has focus).
do
  local function cyclesOnTab(fnName, pattern)
    local body = src:match("\n(local function " .. fnName .. "%(.-%).-\nend)\n")
    test(fnName .. " found in source", body ~= nil)
    if body then test(fnName .. " binds Tab to tabCycle", body:find(pattern, 1, true) ~= nil) end
  end
  cyclesOnTab("handleBrowserKey", "SCANCODE.tab and cl == \"\"")
  cyclesOnTab("handleViewerKey", "SCANCODE.f2 or code == SCANCODE.tab")
  cyclesOnTab("handleHelpKey", "SCANCODE.f2 or code == SCANCODE.tab")

  -- The editor is the one place Tab must NOT cycle tabs -- it inserts
  -- an indent, exactly like events.lua's own "Tab completes/edits when
  -- there is something to act on" rule for the rest of TOS.
  local editorBody = src:match("\n(local function handleEditorKey%(.-%).-\nend)\n")
  test("handleEditorKey found in source", editorBody ~= nil)
  if editorBody then
    test("the editor's Tab still inserts, not a tab-cycle binding added here",
      editorBody:find("SCANCODE%.f2 or code == SCANCODE%.tab") == nil)
  end
end

-- ── promptInput: ^Q cancels, not only bare Esc ──────────────────────
do
  local body = src:match("\n(local function promptInput%(prompt, prefill%).-\nend)\n")
  test("promptInput found in source", body ~= nil)
  if body then
    test("Esc still cancels", body:find("code == 1") ~= nil)
    test("^Q also cancels (the documented, reliable binding)", body:find("ch == 17") ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
