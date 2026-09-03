-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: the author's-note easter egg (shell/colophon.lua)      ║
-- ║                                                              ║
-- ║  A blank username plus one specific password shows a note    ║
-- ║  and returns to the login screen. The thing actually worth   ║
-- ║  testing is what it must NEVER do: authorise anything. The    ║
-- ║  trigger is a pure predicate returning a boolean, the login   ║
-- ║  branch consults usermod not at all, and run() has no return  ║
-- ║  value other than nil — so there is no shape in which this    ║
-- ║  becomes a credential.                                       ║
-- ║                                                              ║
-- ║  Also pinned: it stays UNDISCOVERABLE. No shipped document    ║
-- ║  and no in-OS help names it, because the point is that only   ║
-- ║  somebody who wonders whether something is there finds it.    ║
-- ║                                                              ║
-- ║  And the photosensitivity rule: the reveal is additive text,  ║
-- ║  never a full-field repaint, so it can't strobe.              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_colophon.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function findUp(rel)
  for _, pre in ipairs({ "", "../", "../../", "../../../" }) do
    local s = readAll(pre .. rel); if s then return s end
  end
end

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local C = require("shell.colophon")

print("=== colophon: the author's note ===")
print()

-- ── The trigger is exact ──────────────────────────────────────────
test("the note opens on a blank name + the passphrase",
  C.isTrigger("", C.PASSPHRASE) == true)
test("nil name counts as blank (Enter on an untouched field)",
  C.isTrigger(nil, C.PASSPHRASE) == true)
test("a real username never opens it", C.isTrigger("root", C.PASSPHRASE) == false)
test("a blank-looking name of spaces does NOT open it",
  C.isTrigger(" ", C.PASSPHRASE) == false)
test("the wrong number does nothing", C.isTrigger("", "65535") == false)
test("an empty password does nothing", C.isTrigger("", "") == false)
test("a nil password does nothing", C.isTrigger("", nil) == false)
test("a non-string password does nothing", C.isTrigger("", 65536) == false)
test("the passphrase is not a substring match",
  C.isTrigger("", C.PASSPHRASE .. "x") == false
  and C.isTrigger("", "x" .. C.PASSPHRASE) == false)

-- The number is the one the takeover cinematic lands on, which is the
-- only place in TOS it is written down.
eq("the passphrase is the cinematic's number", "65536", C.PASSPHRASE)
do
  local egg = findUp("tos/shell/panels/takeover.lua")
  test("takeover.lua is where that number comes from",
    egg ~= nil and egg:find("65,536", 1, true) ~= nil)
end

-- ── THE SECURITY PROPERTY: it grants nothing ──────────────────────
do
  test("isTrigger returns a BOOLEAN, never a token",
    type(C.isTrigger("", C.PASSPHRASE)) == "boolean")

  -- Drive the real run() and prove its return value is nil.
  local drawn, cleared = {}, 0
  local ctx = {
    W = 80, H = 25,
    theme = { fg = 0xC0C0C0, dim = 0x555555, highlight = 0x00AAFF, bg = 0 },
    clear = function() cleared = cleared + 1; drawn = {} end,
    set = function(x, y, s, fg) drawn[#drawn + 1] = { x = x, y = y, text = s, fg = fg } end,
    pull = function() return nil end,          -- nobody presses anything
    sleep = function() end,
    uptime = (function() local t = 0; return function() t = t + 10; return t end end)(),
    width = function(s) return #s end,
  }
  local ok, ret = pcall(C.run, ctx)
  test("run() completes", ok)
  if not ok then print("        " .. tostring(ret)) end
  eq("run() returns nil — there is no success path", nil, ret)
  eq("it cleared the screen exactly once", 1, cleared)
  test("it drew the note", #drawn > 10)
  test("it signs off with the author's name", (function()
    for _, d in ipairs(drawn) do
      if d.text:find(C.AUTHOR, 1, true) then return true end
    end
  end)())
  test("an unattended machine is not stranded on it (timeout escapes)", ok)

  -- The login branch consults NOTHING that could authenticate.
  local src = findUp("tos/shell/colophon.lua")
  test("colophon.lua readable", src ~= nil)
  if src then
    for _, forbidden in ipairs({ "kernel.users", "usermod", "login(",
                                 "registerSession", "getSession", "TIER" }) do
      test("colophon.lua never touches " .. forbidden,
        src:find(forbidden, 1, true) == nil)
    end
  end
end

-- ── The login wiring: blank name never reaches the user DB ────────
do
  local src = findUp("tos/shell/login.lua")
  test("login.lua readable", src ~= nil)
  if src then
    -- The blank-name branch must come BEFORE the real one and must not
    -- contain a usermod.login call.
    local blankAt = src:find('elseif username == "" then', 1, true)
    local realAt  = src:find('elseif username and username ~= "" then', 1, true)
    test("there is a dedicated blank-username branch", blankAt ~= nil)
    test("...ahead of the real login branch", blankAt and realAt and blankAt < realAt)
    if blankAt and realAt then
      local branch = src:sub(blankAt, realAt)
      test("the blank branch never calls usermod.login",
        branch:find("usermod.login", 1, true) == nil)
      test("the blank branch returns no token",
        branch:find("return token", 1, true) == nil)
      test("...and it is pcall-guarded so the egg can never wedge login",
        branch:find("pcall(colophon.run", 1, true) ~= nil)
    end
  end
end

-- ── It stays hidden ───────────────────────────────────────────────
-- Every document that SHIPS, plus the in-OS help surfaces. (README,
-- CHANGELOG, MANUAL and TODO are Release-excluded, so they may discuss
-- it; the operator asked for it to be hard to find in general, and the
-- in-OS surfaces are what "in general" means.)
do
  for _, rel in ipairs({ "tos/shell/panels/commands/core.lua",
                         "tos/shell/panels/commands/admin.lua",
                         "tos/shell/panels/commands/extras.lua" }) do
    local s = findUp(rel)
    if s then
      test(rel .. " does not mention the colophon",
        s:find("colophon", 1, true) == nil)
    end
  end
  local li = findUp("tos/shell/login.lua")
  if li then
    -- The login screen itself must not hint. The only allowed mentions
    -- are the require and the comment explaining the branch.
    local hintish = li:find("author", 1, true) or li:find("easter", 1, true)
      or li:find("65536", 1, true)
    test("the login screen shows no hint (and never spells the number)",
      hintish == nil)
  end
end

-- ── Photosensitivity: the reveal is additive, never a repaint ─────
do
  local drawn, clears = 0, 0
  local ctx = {
    W = 80, H = 25, theme = { fg = 1, dim = 2, highlight = 3, bg = 0 },
    clear = function() clears = clears + 1 end,
    set = function() drawn = drawn + 1 end,
    pull = function() return nil end,
    sleep = function() end,
    uptime = (function() local t = 0; return function() t = t + 10; return t end end)(),
    width = function(s) return #s end,
  }
  pcall(C.run, ctx)
  eq("exactly ONE full-field clear for the whole scene", 1, clears)
  test("every other draw is additive text (" .. drawn .. " sets)", drawn > 0)
  local src = findUp("tos/shell/colophon.lua")
  test("the photosensitivity rule is written down in the file",
    src ~= nil and src:find("PHOTOSENSITIVITY", 1, true) ~= nil)
end

-- ── Layout is pure and degrades ───────────────────────────────────
do
  local rows, footer = C.layout(80, 25, C.NOTE, function(s) return #s end)
  test("the note lays out on 80x25", rows ~= nil and #rows > 0)
  test("...with a footer row on screen", footer and footer <= 25)
  if rows then
    local okBounds = true
    for _, r in ipairs(rows) do
      if r.x < 1 or r.y < 1 or r.y > 25 or (r.x + #r.text - 1) > 80 then
        okBounds = false
      end
    end
    test("every line lands inside the screen", okBounds)
  end
  test("a tiny screen refuses rather than corrupting the layout",
    C.layout(20, 6, C.NOTE, function(s) return #s end) == nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
