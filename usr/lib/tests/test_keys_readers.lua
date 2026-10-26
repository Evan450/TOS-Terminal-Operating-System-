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
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
