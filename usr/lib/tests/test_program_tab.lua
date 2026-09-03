-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: a running full-screen program is a TAB (stage 2)       ║
-- ║                                                              ║
-- ║  apps.lua has documented `model = "process"` since stage 1    ║
-- ║  and only ever built "inshell". This is that missing half.    ║
-- ║                                                              ║
-- ║  The program app is the one app whose `draw` is not a draw:   ║
-- ║  a program owns the real screen, so activating its tab means  ║
-- ║  HANDING THE SEAT OVER — foreground its process, tell it to   ║
-- ║  repaint, and stop painting over it.                          ║
-- ║                                                              ║
-- ║  Driven against the REAL registry and the REAL scheduler, so  ║
-- ║  this is behavioural rather than a source grep.               ║
-- ║                                                              ║
-- ║  The trap this pins: after Ctrl+B the shell must MOVE OFF     ║
-- ║  the program tab. Leaving it active means the next repaint    ║
-- ║  calls the program app's draw, which hands the seat straight  ║
-- ║  back — and the operator can never leave the program.         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_program_tab.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local clock = 0
package.loaded["computer"] = {
  uptime = function() return clock end,
  pullSignal = function() return nil end, pushSignal = function() end,
  freeMemory = function() return 1e6 end, totalMemory = function() return 1e6 end,
  address = function() return "test" end,
}
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end, type = function() return nil end,
}

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local proc  = require("kernel.process")
local apps  = require("shell.panels.apps")
local tabs  = require("shell.panels.tabs")

print("=== a running program is a tab ===")
print()

-- A minimal shell state: just what the program app touches.
local invalidated = 0
local S = {
  tabs = { { type = "shell", label = "Shell" } },
  activeTab = 1,
  displayIdx = 1,
  D = { invalidate = function() invalidated = invalidated + 1 end },
}

test("the program app is registered", apps.has("program"))
local app = apps.get("program")
eq("...as a PROCESS-backed app", "process", app and app.model)

-- ── A running program, and its tab ────────────────────────────────
local runs = 0
local pid = proc.spawn("prog:calc@1", function()
  while true do runs = runs + 1; coroutine.yield() end
end, { background = "drowsy", display = 1 })
test("the program process spawned", pid ~= nil)

tabs.create(S, "program", "calc", { pid = pid, seat = 1, prog = "calc", live = true })
eq("the shell now has two tabs", 2, #S.tabs)
eq("...and the program's tab is the active one", 2, S.activeTab)
eq("the tab is titled after the program", "calc",
  app.title and app.title(S.tabs[2]) or nil)

-- ── Activating the tab hands over the seat ────────────────────────
do
  S.suspendIdleDraw = nil
  local before = invalidated
  app.draw(S, S.tabs[2])
  eq("activating foregrounds the PROGRAM on its seat", pid, proc.getForeground(1))
  test("...tells the shell to stop painting", S.suspendIdleDraw == true)
  test("...and drops the stale dirty-cell shadow", invalidated > before)

  -- The program must be told to repaint: it was frozen/backgrounded and
  -- whatever is on the screen is not its own.
  local p = proc.get(pid)
  local queued = false
  for i = (p.sigHead or 1), (p.sigTail or 0) do
    local s = p.signals[i]
    if type(s) == "table" and s[1] == "tos_focus" then queued = true end
  end
  test("...and the program is told to repaint (tos_focus queued)", queued)
end

-- ── THE TRAP: coming back must not bounce straight out again ──────
-- events.lua moves the active tab off a program tab when tos_focus
-- arrives. Without it, the repaint calls app.draw, which foregrounds
-- the program again, and Ctrl+B can never actually get you out.
do
  local ev
  for _, p in ipairs({ "tos/shell/panels/events.lua",
                       "../../../tos/shell/panels/events.lua" }) do
    local h = io.open(p, "rb"); if h then ev = h:read("*a"); h:close(); break end
  end
  test("events.lua readable", ev ~= nil)
  if ev then
    local blk = ev:match('elseif sig == "tos_focus" then.-\n    elseif')
    test("the tos_focus handler moves off a program tab",
      blk ~= nil and blk:find('at.type == "program"', 1, true) ~= nil)
    test("...onto the shell tab",
      blk ~= nil and blk:find("S.activeTab = shellIdx", 1, true) ~= nil)
  end
end

-- ── The chip stays honest while the program is backgrounded ───────
do
  -- Hand the seat to something else so the program is background.
  local shellPid = proc.spawn("shell@1", function()
    while true do coroutine.yield() end
  end, { display = 1 })
  proc.setForeground(shellPid, 1, { kernel = true })
  for _ = 1, 4 do proc.tick(nil) end

  apps.refreshTabs(S)
  test("a backgrounded-but-running program reads as BUSY (bracketed chip)",
    S.tabs[2].live == true)

  -- Past the grace period the scheduler freezes it, and the chip
  -- should stop claiming to be live.
  clock = clock + proc.BG_GRACE + 1
  proc.tick(nil)
  apps.refreshTabs(S)
  test("a FROZEN program's chip is no longer busy", S.tabs[2].live == false)
  proc.kill(shellPid, { kernel = true })
end

-- ── Closing the tab kills the program ─────────────────────────────
do
  eq("the program is still alive before the close", false,
    proc.get(pid).state == proc.STATE.DEAD)
  tabs.close(S, 2)
  eq("closing the tab removed it", 1, #S.tabs)
  test("...and killed the process",
    proc.get(pid) == nil or proc.get(pid).state == proc.STATE.DEAD)
end

-- ── A dead program's tab closes itself ────────────────────────────
-- A chip that does nothing is worse than no chip.
do
  local pid2 = proc.spawn("prog:ghost@1", function() end,
    { background = "drowsy", display = 1 })
  proc.tick(nil); proc.tick(nil)      -- let the body run to completion
  tabs.create(S, "program", "ghost", { pid = pid2, seat = 1, prog = "ghost" })
  eq("the ghost tab exists", 2, #S.tabs)
  apps.refreshTabs(S)
  eq("a tab whose process is gone closes itself", 1, #S.tabs)
end

-- ── The executor creates and removes the tab ──────────────────────
do
  local ex
  for _, p in ipairs({ "tos/shell/panels/executor.lua",
                       "../../../tos/shell/panels/executor.lua" }) do
    local h = io.open(p, "rb"); if h then ex = h:read("*a"); h:close(); break end
  end
  test("executor.lua readable", ex ~= nil)
  if ex then
    test("the hand-off creates a program tab",
      ex:find('tabsMod.create, S, "program"', 1, true) ~= nil)
    test("...and the exit path removes it",
      ex:find('t.type == "program" and t.pid == pid', 1, true) ~= nil)
    -- Removing by IDENTITY, not a remembered index: other tabs may have
    -- come and gone while the program sat in the background.
    test("...by identity rather than a stale index",
      ex:find("for i, t in ipairs(S.tabs or {})", 1, true) ~= nil)
    -- And the close must not try to kill an already-dead process.
    test("...without onClose killing a corpse",
      ex:find("t.pid = nil", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
