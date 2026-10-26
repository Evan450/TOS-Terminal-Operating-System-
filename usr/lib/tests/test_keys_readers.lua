-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a rebound quit key closes the dialogs too    ║
-- ║                                                                ║
-- ║  shell/keys.lua promises ONE table that "the shell, its        ║
-- ║  dialogs, the picker, and every bundled package" read, so      ║
-- ║  `keys set quit F4` has every TOS program follow. The panels   ║
-- ║  core and the full-screen add-ons did; the shell's dialogs and ║
-- ║  the package picker tested ^Q / Esc by hand (2026-09 audit),   ║
-- ║  so after a rebind they still answered only ^Q. The picker's   ║
-- ║  filter prompt was worse: its undo was Esc alone, which real   ║
-- ║  Minecraft never delivers.                                     ║
-- ║                                                                ║
-- ║  The dialogs are DRIVEN here, on a key table read from a fake  ║
-- ║  /etc/keys.cfg, with key_down events fed through the           ║
-- ║  coroutine they wait on. The picker needs kernel.pkg to run,   ║
-- ║  so its two key helpers are lifted from the source and run.    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_keys_readers.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local serialize = dofile("tos/kernel/serialize.lua")
package.loaded["kernel.serialize"] = serialize
package.loaded["kernel.users"] = { currentSession = function() return nil end }
local CFG = nil
package.loaded["kernel.fs"] = {
  exists = function(p) return p == "/etc/keys.cfg" and CFG ~= nil end,
  readFile = function(p) if p == "/etc/keys.cfg" then return CFG end end,
}
local keys = require("shell.keys")
local function bindQuit(spec)
  CFG = spec and serialize.encode({ quit = spec }) or nil
  keys.reload()
end

local dialogs = assert(loadfile("tos/shell/panels/dialogs.lua"))()
local nop = function() end
local S = {
  D = setmetatable({}, { __index = function() return nop end }),
  T = setmetatable({}, { __index = function() return 0 end }),
  W = 80, H = 25, OUT_ROW = 24,
}

-- Run `fn` on a coroutine (dialogs wait with coroutine.yield) and feed it
-- key_down events until it returns. Returns done, the result.
local F4, ENTER = 62, 28
local function drive(fn, events)
  local co = coroutine.create(fn)
  local ok, res = coroutine.resume(co)
  local i = 1
  while coroutine.status(co) ~= "dead" and i <= #events do
    local e = events[i]; i = i + 1
    ok, res = coroutine.resume(co, "key_down", "kbd", e[1], e[2])
    if not ok then return false, res end
  end
  return coroutine.status(co) == "dead", res
end
local function key(ch, code) return { ch, code } end
local CTRL_Q, KEY_F4, KEY_ENTER = key(17, 16), key(0, F4), key(13, ENTER)

print("=== The shell's dialogs follow the quit binding ===")
print()

bindQuit(nil)
local done, res = drive(function() return dialogs.promptInput(S, "Name: ") end, { CTRL_Q })
test("default binding: ^Q cancels a prompt", done and res == nil)
done, res = drive(function()
  return dialogs.dialog(S, { buttons = { "Yes", "No" }, escIndex = 2 })
end, { CTRL_Q })
test("default binding: ^Q picks a dialog's escape button", done and res == 2)

bindQuit("F4")
test("the fake config binds quit to F4", keys.is("quit", 0, F4) and not keys.is("quit", 17, 16))

done, res = drive(function() return dialogs.promptInput(S, "Name: ") end, { KEY_F4 })
test("F4 cancels a prompt", done and res == nil, res)
done, res = drive(function() return dialogs.promptInput(S, "Name: ") end,
  { CTRL_Q, key(97, 30), KEY_ENTER })
test("^Q no longer cancels a prompt: typing carries on", done and res == "a", res)

done, res = drive(function()
  return dialogs.dialog(S, { buttons = { "Yes", "No" }, escIndex = 2 })
end, { KEY_F4 })
test("F4 picks a dialog's escape button", done and res == 2, res)
done = drive(function()
  return dialogs.dialog(S, { buttons = { "Yes", "No" }, escIndex = 2 })
end, { CTRL_Q })
test("^Q no longer closes a dialog", not done)

done, res = drive(function() return dialogs.confirmTyped(S, "Type it", "wipe", {}) end, { KEY_F4 })
test("F4 refuses a typed confirmation", done and res == false, res)

done, res = drive(function() return dialogs.promptSearch(S, "old") end, { KEY_F4 })
test("F4 leaves a search as it was", done and res == "old", res)

bindQuit("q")
done, res = drive(function() return dialogs.promptInput(S, "Name: ") end,
  { key(113, 16), KEY_ENTER })
test("a printable quit binding still types into a prompt", done and res == "q", res)
done, res = drive(function() return dialogs.confirmTyped(S, "Type it", "q", {}) end,
  { key(113, 16), key(9, 15), KEY_ENTER })   -- q, Tab to Confirm, Enter
test("...and into a typed confirmation", done and res == true, res)

print()
print("=== The package picker follows it too ===")
print()

local src = assert(io.open("tos/shell/pkgpicker.lua", "rb")):read("a"):gsub("\r\n", "\n")
test("the picker no longer draws a fixed 'Q Quit'", not src:find("· Q Quit", 1, true))
test("the filter prompt no longer offers Esc alone", not src:find("Esc=undo", 1, true))
-- fitTo cuts the key bar's end; at 80 columns the old order lost the quit
-- hint entirely ("... · Enter In…"). Install and quit come first now.
test("the key bar lists install and quit ahead of everything optional",
  src:find('"Space", "Enter Install", quitLabel()', 1, true) ~= nil)
test("no hand-written ^Q / Esc test is left outside the fallback",
  select(2, src:gsub("ch == 17 or code == 1", "")) == 1)

-- Lift isQuit and quitLabel out of the picker and run them.
local i = src:find("local function isQuit", 1, true)
local j = src:find("\nend\n", src:find("local function quitLabel", 1, true), true)
local lifted = src:sub(i, j + 4) .. "\nreturn isQuit, quitLabel\n"
local isQuit, quitLabel = assert(load(lifted, "=picker-keys"))()
bindQuit("F4")
test("the picker's quit test takes F4", isQuit(0, F4) == true)
test("...and not ^Q once quit is rebound", isQuit(17, 16) == false)
test("the picker's legend says F4", quitLabel() == "F4", quitLabel())
bindQuit("q")
test("a printable binding is not quit inside the filter prompt", isQuit(113, 16, true) == false)
test("...but is in the list", isQuit(113, 16) == true)
bindQuit(nil)
test("default: the legend says ^Q / F10", quitLabel() == "^Q / F10", quitLabel())

print()
print("=== keys.isQuit, and the panels that use it ===")
print()

bindQuit("F4")
test("isQuit takes F4", keys.isQuit(0, F4) == true)
test("isQuit refuses ^Q once rebound", keys.isQuit(17, 16) == false)
test("quitHint is F4", keys.quitHint() == "F4", keys.quitHint())
bindQuit("q")
test("a printable binding is quit outside text", keys.isQuit(113, 16) == true)
test("...and a letter while typing", keys.isQuit(113, 16, true) == false)
bindQuit(nil)
test("default: isQuit takes ^Q", keys.isQuit(17, 16) == true)
test("default: quitHint is ^Q", keys.quitHint() == "^Q", keys.quitHint())

-- F4 is the panels' close-tab key, and it was taken on the shell tab too,
-- where there is nothing to close: the manual's own `keys set quit F4`
-- could never clear the command line (seen on the headless runner).
do
  local h = io.open("tos/shell/panels/events.lua", "rb")
  local ev = h:read("a"); h:close()
  test("close-tab lets F4 through on the shell tab",
    ev:find('co == KEYS.tabClose and not (tab and tab.type == "shell")', 1, true) ~= nil)
end

-- Every hand-written ^Q test left in the shell, and why it stays. A new
-- one fails here until it either asks keys.isQuit or is listed.
local ALLOWED = {
  -- the fallback for when shell.keys cannot be required
  ["tos/shell/panels/dialogs.lua"] = 1, ["tos/shell/pkgpicker.lua"] = 1,
  -- the takeover dialogue reads ^C and ^Q as a refusal, deliberately
  ["tos/shell/panels/takeover.lua"] = 1,
  -- [known gap] CLI-path surfaces: shell.keys is not loaded in CLI mode,
  -- and requiring it there costs heap on the 1 MB floor. Not changed
  -- without a floorcheck run (TODO: SIX SURFACES STILL IGNORE THE KEY TABLE).
  ["tos/shell/cli.lua"] = 1, ["tos/shell/chat.lua"] = 1,
  ["tos/shell/login.lua"] = 2, ["tos/shell/tutorial.lua"] = 1,
}
local listing = io.popen(package.config:sub(1, 1) == "\\"
  and 'dir /s /b tos\\shell\\*.lua 2>nul' or "find tos/shell -name '*.lua' 2>/dev/null")
local seen = {}
for line in listing:lines() do
  local rel = line:gsub("\\", "/"):match("(tos/shell/.*)$")
  if rel then
    local h = io.open(rel, "rb")
    local text = h and h:read("a") or ""; if h then h:close() end
    local n = 0
    for _ in text:gmatch("[%w_]+ == 17[^%d]") do n = n + 1 end
    if n > 0 then seen[rel] = n end
  end
end
listing:close()
test("the scan found the shell (dialogs.lua's fallback is in it)", seen["tos/shell/panels/dialogs.lua"] ~= nil)
for rel, n in pairs(seen) do
  test(rel .. ": every hand-written ^Q test is a listed exception (" .. n .. ")",
    ALLOWED[rel] ~= nil and n <= ALLOWED[rel])
end

-- The hints say the key too: a footer that still read "[^Q]Close" after
-- `keys set quit F4` was on the output viewer when the runner looked.
do
  local HINT_FILES = {
    "tos/shell/panels/draw.lua", "tos/shell/panels/chatapp.lua",
    "tos/shell/panels/monitorapp.lua", "tos/shell/panels/settingsapp.lua",
    "tos/shell/panels/commands/core.lua", "tos/shell/panels/events.lua",
    "tos/shell/panels/menus.lua",
  }
  for _, rel in ipairs(HINT_FILES) do
    local h = io.open(rel, "rb")
    local text = h and h:read("a") or ""; if h then h:close() end
    local bad
    for line in text:gmatch("[^\n]+") do
      local code = line:gsub("%-%-.*$", "")      -- comments may say ^Q
      if code:find('"[^"]*%^Q[%] ]+[CcSs]') or code:find('%[%^Q%]') then bad = line; break end
    end
    test(rel .. ": no on-screen hint hard-codes ^Q", bad == nil, bad)
  end
end

print()
print("=== The add-on surfaces follow it too ===")
print()

local EXTRAS
for _, base in ipairs({ "../TOS-Extras/", "TOS-Extras/" }) do
  local h = io.open(base .. "build/build-disk.lua", "rb")
  if h then h:close(); EXTRAS = base; break end
end
if not EXTRAS then
  print("  note: no TOS-Extras tree beside TOS-Dev; add-on surfaces not checked")
else
  for _, rel in ipairs({
    "modules/mail/usr/lib/mailapp.lua", "modules/mail/usr/lib/mailui.lua",
    "modules/intercom/usr/lib/intercomapp.lua",
    "rbmk/controller-skeleton/usr/lib/rbmk-skala.lua",
  }) do
    local h = io.open(EXTRAS .. rel, "rb")
    local text = h and h:read("a"):gsub("\r\n", "\n") or ""
    if h then h:close() end
    local n = 0
    for _ in text:gmatch("[%w_]+ == 17[^%d]") do n = n + 1 end
    test(rel .. ": no ^Q test but the fallback's", n == 1, n)
    test(rel .. ": no hint still says ^Q", not text:find("%^Q[ =]+[CcEe]"), text:match("[^\n]*%^Q[ =]+[CcEe][^\n]*"))
    local i = text:find("local function isQuit", 1, true)
    local j = i and text:find("\nend\n", i, true)
    local chunk = i and j and load(text:sub(i, j + 4) .. "\nreturn isQuit\n", "=" .. rel)
    local q = chunk and chunk()
    bindQuit("F4")
    test(rel .. ": quits on F4 once rebound", q ~= nil and q(0, F4) == true and q(17, 16) == false)
    bindQuit("q")
    test(rel .. ": a printable binding is a letter there", q ~= nil and q(113, 16, true) == false)
    bindQuit(nil)
    test(rel .. ": quits on ^Q by default", q ~= nil and q(17, 16) == true)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
