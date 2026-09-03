-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: panels app registry                     ║
-- ║                                                            ║
-- ║  Tabs dispatch render/input to a registered app instead of ║
-- ║  a hardcoded type-chain. Pins register/get/has/types, the  ║
-- ║  lazy built-in registration (Desktop/Settings), and that   ║
-- ║  draw.lua routes an unknown non-core type through the      ║
-- ║  registry (not a dead branch).                             ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_app_registry.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
-- draw.lua (loaded below) pulls in `computer` + a few shell modules at
-- require time; stub the ones the registry path doesn't exercise.
package.loaded["computer"] = { uptime = function() return 0 end }
local apps = require("shell.panels.apps")

print("=== panels app registry Tests ===")
print()

-- ── register / get / has / types ───────────────────────────────────
apps._reset()
test("unknown type not registered", not apps.has("frobnicate"))
local drew = nil
apps.register({ type = "frob", draw = function(S, tab) drew = tab.id end })
test("register then has", apps.has("frob"))
test("get returns the spec", apps.get("frob") ~= nil)
apps.get("frob").draw(nil, { id = 42 })
eq("draw dispatches to the app", 42, drew)
-- register asserts a string type
test("register without type errors", not pcall(apps.register, { draw = function() end }))

-- ── lazy built-ins (Desktop + Settings) + input adapters ───────────
apps._reset()
-- Stub the two app modules with the full existing interface so the
-- ensureBuiltins adapter wires onKey/onMouse/onScroll from handle*.
local dCalls = {}
package.loaded["shell.panels.desktop"] = {
  draw = function() end,
  handleKey = function(S, tab, ch, co, deps)
    dCalls.key = { ch = ch, co = co, exec = deps and deps.exec }; return 2, nil
  end,
  handleClick = function(S, tab, ev) dCalls.click = ev; return 1 end,
  handleScroll = function(S, tab, ev) dCalls.scroll = ev; return 1 end,
}
package.loaded["shell.panels.settingsapp"] = { draw = function() end }
local ticked = false
package.loaded["shell.panels.monitorapp"] = {
  draw = function() end,
  tick = function(S, tab) ticked = true; return 3 end,
}
local closed = false
package.loaded["shell.panels.chatapp"] = {
  draw = function() end,
  onClose = function(S, tab) closed = true end,
}
-- Mail is an ADD-ON since stage 5: its tab app ships as /usr/lib/mailapp.lua
-- with the mail package, so the registry resolves the bare name "mailapp"
-- rather than a shell.panels.* module. Stubbing it under that name proves an
-- add-on can register a tab app exactly like a built-in one.
package.loaded["mailapp"] = { draw = function() end }
apps.ensureBuiltins()
test("desktop app registered", apps.has("desktop"))
test("settings app registered", apps.has("settings"))
test("monitor app registered", apps.has("monitor"))
test("chat app registered", apps.has("chat"))
test("mail app registered from the ADD-ON path", apps.has("mail"))
-- onClose passes through the adapter (tabs.close fires it).
test("chat onClose wired", type(apps.get("chat").onClose) == "function")
apps.get("chat").onClose(nil, {})
test("onClose dispatches to the module", closed)
-- The adapter passes `tick` through (the event loop's live-refresh hook).
local mSpec = apps.get("monitor")
test("monitor tick wired", type(mSpec.tick) == "function")
mSpec.tick(nil, {})
test("monitor tick dispatches to the module", ticked)
test("settings has NO tick (stub lacks one)", apps.get("settings").tick == nil)
test("desktop model defaults inshell", apps.get("desktop").model == "inshell")
-- The adapter exposes onKey/onMouse/onScroll and forwards to handle*.
local d = apps.get("desktop")
test("onKey adapter present", type(d.onKey) == "function")
local dl, res = d.onKey(nil, {}, { ch = 65, co = 30, exec = "E" })
eq("onKey forwards ch", 65, dCalls.key and dCalls.key.ch)
eq("onKey forwards exec via deps", "E", dCalls.key and dCalls.key.exec)
eq("onKey returns the module's draw hint", 2, dl)
eq("onKey returns nil result (no loop-exit)", nil, res)
d.onMouse(nil, {}, { x = 4, y = 5 })
eq("onMouse forwards the event", 5, dCalls.click and dCalls.click.y)
d.onScroll(nil, {}, { dir = 1 })
eq("onScroll forwards the event", 1, dCalls.scroll and dCalls.scroll.dir)
-- A module WITHOUT handle* (settings stub here) gets no adapters.
local sSpec = apps.get("settings")
test("settings has draw", type(sSpec.draw) == "function")
test("settings has NO onKey (stub lacks handleKey)", sSpec.onKey == nil)
-- ensureBuiltins is idempotent + doesn't clobber a custom registration
apps.register({ type = "desktop", draw = function() end, _custom = true })
apps.ensureBuiltins()
test("ensureBuiltins doesn't clobber a custom app", apps.get("desktop")._custom == true)

-- ── draw.lua routes non-core types through the registry ────────────
apps._reset()
local routed = nil
apps.register({ type = "myapp", draw = function(S, tab) routed = tab.type end })
-- Minimal draw.lua deps: topBar + the core renderers are called by type,
-- so stub them and drive M.all with a `myapp` tab.
local draw = require("shell.panels.draw")
-- Neutralize the heavy top bar / core renderers for the test.
draw.topBar  = function() end
draw.shell   = function() end
draw.viewTab = function() end
draw.editTab = function() end
local S = { activeTab = 1, tabs = { { type = "myapp" } } }
draw.all(S, {})
eq("draw.all routes a non-core type to its app", "myapp", routed)
-- A core type still uses the inline path (no app needed).
local shellDrawn = false
draw.shell = function() shellDrawn = true end
S.tabs = { { type = "shell" } }
draw.all(S, {})
test("core 'shell' type still drawn inline", shellDrawn)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
