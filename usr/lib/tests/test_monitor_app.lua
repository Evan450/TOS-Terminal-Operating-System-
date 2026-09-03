-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: Monitor app tab (shell.panels.monitorapp)║
-- ║                                                            ║
-- ║  The full-screen Ctrl+T replacement. Pins: open is find-   ║
-- ║  or-create, refresh keeps the selection on the same pid,   ║
-- ║  header rows are skipped, actions route through            ║
-- ║  kernel.monitorAct (switch/kill/tsr/svc) with the client-  ║
-- ║  side canAct greying, and a switch suspends idle draws.    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_monitor_app.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }

-- ── Kernel API stub (what _TOS.kernel exposes to the shell) ────────
local kcalls = {}
local canned = {
  vitals = "up 5s  ·  mem [####--------] 100K/512K free 412K  ·  3 proc",
  rows = {
    { kind = "proc", pid = 2, label = "Shell — root (seat 1)", owner = "root",
      state = "running", tsr = false, cpu = 0.1, isFg = true, canAct = true },
    { kind = "proc", pid = 7, label = "sshd  (kernel)", owner = "kernel",
      state = "ready", tsr = false, cpu = 0, isFg = false, canAct = false },
    { kind = "header", text = "Services" },
    { kind = "svc", name = "clusterd", running = false, enabled = true, canAct = true },
  },
}
_G._TOS = {
  kernel = {
    monitorList = function(displayIdx, sess) return canned end,
    monitorAct = function(action, id)
      kcalls[#kcalls + 1] = { action = action, id = id }
      return true
    end,
  },
}

local mon = require("shell.panels.monitorapp")

-- ── Shared state stub ──────────────────────────────────────────────
local function newS()
  local D = {
    sets = {},
    set  = function(x, y, s) end,
    fill = function() end,
  }
  return {
    D = D, W = 80, H = 25, displayIdx = 1,
    T = { fg = 1, bg = 2, dim = 3, title = 4, highlight = 5,
          sel_fg = 6, sel_bg = 7, error = 8, warning = 9 },
    tabs = { { type = "shell", label = "Shell" } },
    activeTab = 1,
  }
end

print("=== Monitor app tab Tests ===")
print()

-- ── open: find-or-create + refresh ─────────────────────────────────
local S = newS()
local tab = mon.open(S)
eq("open creates a monitor tab", "monitor", tab.type)
eq("open focuses it", 2, S.activeTab)
eq("rows populated from kernel.monitorList", 4, #tab.rows)
test("vitals captured", tab.vitals ~= nil)
S.activeTab = 1
local again = mon.open(S)
test("second open reuses the tab", again == tab and #S.tabs == 2)
eq("and refocuses it", 2, S.activeTab)

-- ── selection: headers skipped, clamped at ends ────────────────────
eq("initial selection is first row", 1, tab.sel)
mon.handleKey(S, tab, nil, 208)          -- Down
eq("down moves to row 2", 2, tab.sel)
mon.handleKey(S, tab, nil, 208)          -- Down (skips the Services header)
eq("down skips the header to the svc row", 4, tab.sel)
mon.handleKey(S, tab, nil, 208)          -- Down at end clamps
eq("down clamps at the end", 4, tab.sel)
mon.handleKey(S, tab, nil, 200)          -- Up (skips the header back)
eq("up skips the header back to row 2", 2, tab.sel)

-- ── draw runs against the D stub (smoke) ───────────────────────────
local okDraw, errDraw = pcall(mon.draw, S, tab)
test("draw renders without error" .. (okDraw and "" or ("  (" .. tostring(errDraw) .. ")")), okDraw)

-- ── actions route through kernel.monitorAct ────────────────────────
-- k on a canAct=false row: refused client-side, no kernel call.
tab.sel = 2                               -- the kernel proc (canAct=false)
kcalls = {}
mon.handleKey(S, tab, 107, nil)           -- k
eq("kill on protected row makes NO kernel call", 0, #kcalls)
test("and explains itself", tab.msg ~= nil)

-- Enter on a svc row toggles it.
tab.sel = 4
kcalls = {}
mon.handleKey(S, tab, nil, 28)            -- Enter
eq("svc toggle called", 1, #kcalls)
eq("svc action name", "svc", kcalls[1].action)
eq("svc id is the service name", "clusterd", kcalls[1].id)

-- Enter on a proc row switches to it and suspends idle draws.
tab.sel = 2
kcalls = {}
mon.handleKey(S, tab, nil, 28)            -- Enter
eq("switch called", "switch", kcalls[1] and kcalls[1].action)
eq("switch id is the pid", 7, kcalls[1] and kcalls[1].id)
test("switch suspends idle repaints", S.suspendIdleDraw == true)
S.suspendIdleDraw = nil

-- k on an actionable row kills through the kernel.
tab.sel = 1
kcalls = {}
mon.handleKey(S, tab, 107, nil)           -- k
eq("kill called", "kill", kcalls[1] and kcalls[1].action)
eq("kill id is the pid", 2, kcalls[1] and kcalls[1].id)

-- t toggles TSR.
tab.sel = 1
kcalls = {}
mon.handleKey(S, tab, 116, nil)           -- t
eq("tsr called", "tsr", kcalls[1] and kcalls[1].action)

-- ── refresh keeps the selection on the same ENTRY, not index ───────
tab.sel = 4                               -- clusterd
canned = {
  vitals = "up 6s",
  rows = {
    { kind = "proc", pid = 9, label = "new", owner = "root",
      state = "ready", tsr = false, cpu = 0, isFg = false, canAct = true },
    { kind = "proc", pid = 2, label = "Shell — root (seat 1)", owner = "root",
      state = "running", tsr = false, cpu = 0.1, isFg = true, canAct = true },
    { kind = "header", text = "Services" },
    { kind = "svc", name = "other", running = true, enabled = true, canAct = true },
    { kind = "svc", name = "clusterd", running = false, enabled = true, canAct = true },
  },
}
mon.refresh(S, tab)
eq("selection follows clusterd to its new index", 5, tab.sel)
-- And a vanished selection falls back to the first selectable row.
tab.sel = 5
canned = { vitals = "up 7s", rows = {
  { kind = "header", text = "Services" },
  { kind = "svc", name = "other", running = true, enabled = true, canAct = true },
} }
mon.refresh(S, tab)
eq("vanished selection lands on first selectable", 2, tab.sel)

-- ── kernel API missing: degrade with a message, don't crash ────────
canned = nil
local realList = _G._TOS.kernel.monitorList
_G._TOS.kernel.monitorList = nil
local S2 = newS()
local tab2 = mon.open(S2)
eq("no kernel feed -> empty rows", 0, #tab2.rows)
test("and a visible message", tab2.msg ~= nil)
_G._TOS.kernel.monitorList = realList

-- ── tick refreshes (the event loop's live hook) ────────────────────
canned = { vitals = "up 8s", rows = { { kind = "proc", pid = 1, label = "x",
  owner = "root", state = "ready", tsr = false, cpu = 0, isFg = false, canAct = true } } }
local dl = mon.tick(S, tab)
eq("tick returns a full-draw hint", 3, dl)
eq("tick re-snapshots", 1, #tab.rows)

-- ── Ctrl+Q closes the tab ──────────────────────────────────────────
S.activeTab = 2
mon.handleKey(S, tab, 17, nil)            -- Ctrl+Q
eq("Ctrl+Q closes the monitor tab", 1, #S.tabs)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
