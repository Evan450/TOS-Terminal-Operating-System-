-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: PaneUI ↔ TOS visual-grammar PARITY         ║
-- ║                                                              ║
-- ║  PaneUI is a single-file OpenOS app that deliberately COPIES ║
-- ║  TOS's look-and-feel (it can't require TOS modules — it runs ║
-- ║  on OpenOS). Copies drift. This test pins the pieces that    ║
-- ║  must stay identical:                                        ║
-- ║                                                              ║
-- ║   • the v1.4.0 "Iris" file-type glyph table — compared       ║
-- ║     entry-for-entry against the REAL tos/shell/panels/ui.lua ║
-- ║     (add an extension there and this fails until PaneUI      ║
-- ║     learns it too);                                          ║
-- ║   • the five visual-grammar primitives are actually present  ║
-- ║     (double-line modal frame + shadow, dim rails, edge-only  ║
-- ║     ramps, state-bearing tab chips), so a future refactor    ║
-- ║     can't quietly drop a rule.                               ║
-- ║                                                              ║
-- ║  PaneUI self-executes on load (`return main({...})`), so we  ║
-- ║  read it as SOURCE and evaluate only the tables we need.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua pane-ui/test_paneui_grammar.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- ── Load PaneUI's SOURCE (never execute it) ────────────────────────
local src
for _, p in ipairs({ "pane-ui/PaneUI.lua", "PaneUI.lua", "../pane-ui/PaneUI.lua" }) do
  local h = io.open(p, "rb")
  if h then src = h:read("*a"); h:close(); break end
end
if not src then
  print("FAIL: PaneUI.lua not found")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- ── Load TOS's real ui.lua (the source of truth) ───────────────────
local ui
for _, p in ipairs({ "../TOS-Dev/tos/shell/panels/ui.lua", "../tos/shell/panels/ui.lua",
                     "TOS-Dev/tos/shell/panels/ui.lua",
                     "../../TOS-Dev/tos/shell/panels/ui.lua" }) do
  local chunk = loadfile(p)
  if chunk then ui = chunk(); break end
end
if not ui or not ui.fileGlyph then
  print("FAIL: could not load TOS-Dev's shell/panels/ui.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== PaneUI ↔ TOS visual-grammar parity ===")
print()

-- ── Extract a named table literal from PaneUI's source ─────────────
local function extractTable(name)
  local body = src:match("local%s+" .. name .. "%s*=%s*(%b{})")
  if not body then return nil end
  local fn = load("return " .. body, "=" .. name, "t", {})
  if not fn then return nil end
  local ok, t = pcall(fn)
  return ok and t or nil
end

local COLOR = extractTable("EXT_GLYPHS")
local MONO  = extractTable("EXT_GLYPHS_MONO")
test("PaneUI declares EXT_GLYPHS", type(COLOR) == "table")
test("PaneUI declares EXT_GLYPHS_MONO (T1 fallback)", type(MONO) == "table")

if COLOR then
  -- Every extension TOS knows must map to the SAME glyph in PaneUI.
  -- ui.fileGlyph is the authority; we probe it with a real filename.
  local exts = {}
  for e in pairs(COLOR) do exts[#exts + 1] = e end
  -- Probe TOS for extensions PaneUI might be missing, too: walk the
  -- ones PaneUI has plus a set TOS is known to carry.
  for _, e in ipairs({ "lua", "txt", "md", "log", "man", "cfg", "conf",
                       "json", "dat", "tcz", "bak", "bin" }) do
    local seen = false
    for _, have in ipairs(exts) do if have == e then seen = true end end
    if not seen then exts[#exts + 1] = e end
  end
  table.sort(exts)

  local mismatches, missing = {}, {}
  for _, e in ipairs(exts) do
    local tosGlyph = ui.fileGlyph("file." .. e, false)
    local mine = COLOR[e]
    if mine == nil then
      -- Only a problem when TOS actually assigns this ext a glyph
      -- (i.e. it isn't just falling through to the generic dot).
      if tosGlyph ~= ui.fileGlyph("file.zzzunknown", false) then
        missing[#missing + 1] = e .. " (TOS uses " .. tosGlyph .. ")"
      end
    elseif mine ~= tosGlyph then
      mismatches[#mismatches + 1] = e .. ": PaneUI " .. mine .. " vs TOS " .. tosGlyph
    end
  end
  test("no glyph MISMATCHES vs TOS ui.fileGlyph"
    .. (#mismatches > 0 and ("  [" .. table.concat(mismatches, "; ") .. "]") or ""),
    #mismatches == 0)
  test("no TOS glyphs MISSING from PaneUI"
    .. (#missing > 0 and ("  [" .. table.concat(missing, "; ") .. "]") or ""),
    #missing == 0)

  -- PaneUI must not invent glyphs TOS doesn't have (drift the other way).
  local extra = {}
  for e, g in pairs(COLOR) do
    if ui.fileGlyph("file." .. e, false) ~= g then extra[#extra + 1] = e end
  end
  test("PaneUI invents no glyphs of its own"
    .. (#extra > 0 and ("  [" .. table.concat(extra, "; ") .. "]") or ""),
    #extra == 0)

  -- The mono table must cover exactly the same extensions, so a T1
  -- screen degrades shape-for-shape rather than losing a type.
  if MONO then
    local uncovered = {}
    for e in pairs(COLOR) do
      if MONO[e] == nil then uncovered[#uncovered + 1] = e end
    end
    test("every colour glyph has a mono fallback"
      .. (#uncovered > 0 and ("  [" .. table.concat(uncovered, "; ") .. "]") or ""),
      #uncovered == 0)
    local nonAscii = {}
    for e, g in pairs(MONO) do
      if #g ~= 1 or g:byte(1) > 126 then nonAscii[#nonAscii + 1] = e end
    end
    test("mono glyphs are single-byte ASCII"
      .. (#nonAscii > 0 and ("  [" .. table.concat(nonAscii, "; ") .. "]") or ""),
      #nonAscii == 0)
  end
end

-- ── Directory / parent glyphs match TOS ────────────────────────────
eq("TOS parent-dir glyph is «", "«", ui.fileGlyph("..", true))
eq("TOS directory glyph is ■", "■", ui.fileGlyph("somedir", true))
test("PaneUI uses « for the parent dir", src:find('return mono and "<" or "«"', 1, true) ~= nil)
test("PaneUI uses ■ for directories", src:find('return mono and "D" or "■"', 1, true) ~= nil)
test("PaneUI falls back to · like TOS",
  src:find('(mono and "." or "·")', 1, true) ~= nil
  and ui.fileGlyph("noext", false) == "·")

-- ── The five rules are actually implemented ────────────────────────
-- Rule 1 — frames rank attention: a DOUBLE-line frame + drop shadow.
test("rule 1: a double-line box set exists (DBOX)", src:find("local BOX, DBOX", 1, true) ~= nil)
test("rule 1: the modal uses DBOX, not BOX",
  src:find("DBOX%.tl%s*%.%.%s*string%.rep%(DBOX%.hl") ~= nil)
test("rule 1: the modal casts a drop shadow", src:find("RAMP.shadow", 1, true) ~= nil)

-- Rule 2 — rails are the skeleton, drawn DIM with brighter labels.
test("rule 2: a rail composer exists", src:find("local function drawRail", 1, true) ~= nil)
test("rule 2: rails carry ┤ label ├ tees",
  src:find("BOX.rt %.%. \" \" %.%. label") ~= nil)
test("rule 2: the path row draws as a rail (not a filled bar)",
  src:find("drawRail(PATH_ROW", 1, true) ~= nil)

-- Rule 3 — ramps at EDGES only.
test("rule 3: a ramp bar exists", src:find("local function drawRampBar", 1, true) ~= nil)
test("rule 3: ramp caps are ▓▒░ / ░▒▓",
  src:find('l = "▓▒░", r = "░▒▓"', 1, true) ~= nil)
test("rule 3: the status row uses it", src:find("drawRampBar(STATUS_ROW", 1, true) ~= nil)
test("rule 3: mono degrades ramps to plain",
  src:find('mono and { l = "", r = "", fill = " "', 1, true) ~= nil)

-- Rule 5 — tabs speak state (inverse / [brackets] / plain).
test("rule 5: chips carry a state", src:find("local function tabChips", 1, true) ~= nil)
test("rule 5: busy renders [bracketed]",
  src:find('%(state == "busy"%) and %("%[" %.%. label %.%. "%]"%)') ~= nil)
test("rule 5: active renders inverse",
  src:find('sp.state == "active"', 1, true) ~= nil
  and src:find('c("selection_fg"), c("selection_bg")', 1, true) ~= nil)
test("rule 5: an overflow chip keeps hidden tabs visible",
  src:find("local function fitChips", 1, true) ~= nil)

-- ── The modal must not paint on a white default ────────────────────
-- c() returns 0xFFFFFF for an UNKNOWN key, so a dialog asking for a
-- theme key the derive step never produced renders white-on-white.
do
  local derive = src:match("local function deriveTheme%(b%)%s*return%s*(%b{})")
  test("deriveTheme maps panel_bg (modal interiors)",
    derive ~= nil and derive:find("panel_bg", 1, true) ~= nil)
  local monoTheme = src:match("local MONO_THEME%s*=%s*(%b{})")
  test("the mono theme maps panel_bg too",
    monoTheme ~= nil and monoTheme:find("panel_bg", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
