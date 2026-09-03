-- ╔══════════════════════════════════════════════════════════╗
-- ║  Convention Test: Esc is not TOS's key                     ║
-- ║                                                            ║
-- ║  FOUND IN REAL MINECRAFT, 2026-08-11. Esc belongs to the   ║
-- ║  GAME: pressing it closes the screen GUI, so the player     ║
-- ║  walks away from the terminal and the keypress never        ║
-- ║  reaches the computer. A program whose only way out is Esc  ║
-- ║  cannot be exited at all — it keeps running and holding     ║
-- ║  the seat, and re-opening the screen finds it still there.  ║
-- ║  `write` shipped exactly that way.                          ║
-- ║                                                            ║
-- ║  THE CONVENTION (see tos/shell/panels/keymap.lua):          ║
-- ║    full-screen quit ........ Q, or ^Q where Q is typed      ║
-- ║    prompt / dialog cancel .. ^Q                             ║
-- ║    F10 ..................... accepted everywhere as quit    ║
-- ║  Esc may still be ACCEPTED — a future OC build or an        ║
-- ║  emulator might deliver it — but never as the only way,     ║
-- ║  and never as the advertised way.                           ║
-- ║                                                            ║
-- ║  This test reads SOURCE. It cannot press keys, so what it   ║
-- ║  can check is that no file offers Esc alone and that no     ║
-- ║  help text tells an operator to press it. That is exactly   ║
-- ║  the shape of the bug that shipped.                         ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_no_esc_exit.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end
local function ok(name, cond) test(name, true, cond and true or false) end

local function readf(p)
  local h = io.open(p, "rb")
  if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end

-- Both trees, from whichever root the harness started in.
local ROOTS = { "", "TOS-Dev/", "../TOS-Dev/" }
local function findFile(rel)
  for _, r in ipairs(ROOTS) do
    local s = readf(r .. rel)
    if s then return s, r .. rel end
  end
end
local function findExtras(rel)
  for _, r in ipairs({ "../TOS-Extras/", "TOS-Extras/", "" }) do
    local s = readf(r .. rel)
    if s then return s, r .. rel end
  end
end

print("=== Esc-is-not-ours Tests ===")
print()

-- ══════════════════════════════════════════════════════════════════════
-- The convention is written down where a implementer will look
-- ══════════════════════════════════════════════════════════════════════
do
  local km = findFile("tos/shell/panels/keymap.lua")
  ok("keymap.lua exists", km ~= nil)
  if km then
    ok("it states the convention", km:find("ESC IS NOT OURS", 1, true) ~= nil)
    ok("it names ^Q as the cancel key", km:find("CTRL_Q", 1, true) ~= nil)
    -- A convention nobody can find is not a convention. The scancode
    -- constants live beside the prose so a program binding a quit key
    -- reads the reason on the way past.
    ok("and exports the constants", km:find("CTRL_Q   = 17", 1, true) ~= nil)
  end
end

-- ══════════════════════════════════════════════════════════════════════
-- No help text tells an operator to press Esc
-- ══════════════════════════════════════════════════════════════════════
-- This is the half that actually reached the operator: `write` drew
-- "Esc quit" on its footer, so even the workaround was hidden.
local HELP_PHRASES = { "Esc quit", "Esc exit", "Esc to quit", "Esc to exit",
                       "Esc: quit", "Esc = quit", "ESC quit" }
local FILES = {
  base = {
    "tos/shell/cli.lua", "tos/shell/pkgpicker.lua", "tos/shell/login.lua",
    "tos/shell/panels/dialogs.lua", "tos/shell/panels/editor.lua",
    "tos/kernel/bootsettings.lua",
  },
  extras = {
    "modules/write/init.lua", "modules/calc/init.lua", "modules/stock/init.lua",
    "modules/snake/init.lua", "modules/ttt/init.lua", "modules/tetris/init.lua",
    "modules/rc-pilot/init.lua", "modules/intercom/init.lua",
    "modules/mouse/usr/modules/mouse/init.lua",
  },
}

local checked = 0
for _, rel in ipairs(FILES.base) do
  local src = findFile(rel)
  if src then
    checked = checked + 1
    for _, phrase in ipairs(HELP_PHRASES) do
      test(rel .. " does not advertise '" .. phrase .. "'", nil,
        src:find(phrase, 1, true))
    end
  end
end
for _, rel in ipairs(FILES.extras) do
  local src = findExtras(rel)
  if src then
    checked = checked + 1
    for _, phrase in ipairs(HELP_PHRASES) do
      test(rel .. " does not advertise '" .. phrase .. "'", nil,
        src:find(phrase, 1, true))
    end
  end
end
ok("found files to check (" .. checked .. ")", checked >= 10)

-- ══════════════════════════════════════════════════════════════════════
-- Wherever Esc is honoured, something else is too
-- ══════════════════════════════════════════════════════════════════════
-- A file that tests `code == 1` must also accept ^Q (char 17), plain
-- Q/q, or F10 (68) somewhere. That is coarse — it is a whole-file check,
-- not a per-branch one — but it is the property that failed: `write`
-- tested code == 1 in three places and had no other exit anywhere.
local function acceptsAnAlternative(src)
  return src:find("== 17", 1, true) ~= nil        -- ^Q
      or src:find("== 68", 1, true) ~= nil        -- F10
      or src:find("F10", 1, true) ~= nil
      or src:find('== 113', 1, true) ~= nil       -- 'q'
      or src:find('== "q"', 1, true) ~= nil
      or src:find("K.Q", 1, true) ~= nil
end

local function checkFile(rel, src)
  if not src or not src:find("code == 1", 1, true) then return end
  ok(rel .. ": Esc is not the only way out", acceptsAnAlternative(src))
end
for _, rel in ipairs(FILES.base)   do checkFile(rel, (findFile(rel))) end
for _, rel in ipairs(FILES.extras) do checkFile(rel, (findExtras(rel))) end

-- ══════════════════════════════════════════════════════════════════════
-- write, specifically — it is the one that shipped broken
-- ══════════════════════════════════════════════════════════════════════
do
  local src = findExtras("modules/write/init.lua")
  ok("write's source was found", src ~= nil)
  if src then
    -- It is an EDITOR: plain Q types a Q, so the quit key has to be ^Q
    -- or F10. Both, in practice.
    ok("write binds F10", src:find("F10 = 68", 1, true) ~= nil)
    ok("write binds ^Q", src:find("CTRL_Q = 17", 1, true) ~= nil)
    ok("write routes every exit through one predicate",
      src:find("local function isQuit", 1, true) ~= nil)
    -- The footer is DERIVED from the live binding rather than a baked
    -- string, which is strictly better than the literal this used to
    -- check for: a hard-coded "F10 quit" would still say F10 after an
    -- operator rebound `quit`, and a footer that lies about the key is
    -- the same failure as advertising Esc.
    ok("its footer is derived from the binding, not baked",
      src:find("quitLabel() .. \" quit\"", 1, true) ~= nil)
    ok("and the binding comes from the shared table",
      src:find('"shell.keys"', 1, true) ~= nil)
    -- The interrupt path used to synthesise an Esc, which meant a
    -- kernel interrupt was routed to a key nothing would act on.
    test("an interrupt no longer synthesises Esc", nil,
      src:find("return nil, K.ESC", 1, true))
  end
end

-- ══════════════════════════════════════════════════════════════════════
-- The manual tells operators the truth
-- ══════════════════════════════════════════════════════════════════════
do
  local man = findFile("MANUAL.md")
  ok("MANUAL.md was found", man ~= nil)
  if man then
    ok("it explains that Esc belongs to Minecraft",
      man:find("closes the screen", 1, true) ~= nil
      or man:find("belongs to Minecraft", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
