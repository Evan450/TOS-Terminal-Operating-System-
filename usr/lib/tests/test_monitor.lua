-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: System Monitor pure helpers              ║
-- ║  (kernel.monitor) — process labelling, the unified row     ║
-- ║  list, header-skipping navigation, mem bar + uptime fmt.   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_monitor.lua

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

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local m = require("kernel.monitor")

-- ── describe: machine names -> operator-readable ────────────────────
test("describe login broker", "Login broker — seat 2", m.describe({ name = "login@2" }))
test("describe shell", "Shell — root (seat 1)", m.describe({ name = "shell:root@1" }))
test("describe kernel daemon", "sshd  (kernel)", m.describe({ name = "sshd", source = "kernel" }))
test("describe plain user program", "edit", m.describe({ name = "edit", user = "bob" }))

-- ── kindTag ─────────────────────────────────────────────────────────
test("kindTag shell", "shell", m.kindTag({ name = "shell:root@1" }))
test("kindTag login is sys", "sys", m.kindTag({ name = "login@1" }))
test("kindTag kernel source is sys", "sys", m.kindTag({ name = "x", user = "_kernel_" }))
test("kindTag user", "user", m.kindTag({ name = "edit", user = "bob" }))

-- ── memBar ──────────────────────────────────────────────────────────
test("memBar half", "#####-----", m.memBar(50, 100, 10))
test("memBar full", "##########", m.memBar(100, 100, 10))
test("memBar empty", "----------", m.memBar(0, 100, 10))
test("memBar over clamps", "####", m.memBar(999, 100, 4))
test("memBar unknown total", "????", m.memBar(10, 0, 4))

-- ── fmtUptime ───────────────────────────────────────────────────────
test("uptime seconds", "37s", m.fmtUptime(37))
test("uptime minutes", "4m05s", m.fmtUptime(245))
test("uptime hours", "1h23m", m.fmtUptime(3600 + 23 * 60 + 9))
test("uptime negative -> 0s", "0s", m.fmtUptime(-5))

-- ── buildRows: processes + Services header + service rows ───────────
local procs = { { name = "shell:root@1", pid = 2 }, { name = "login@2", pid = 5 } }
local svcs  = { { name = "sshd", running = true }, { name = "clusterd", running = false } }
local rows  = m.buildRows(procs, svcs)
test("rows total (2 proc + header + 2 svc)", 5, #rows)
test("row 1 is proc", "proc", rows[1].kind)
test("row 3 is the Services header", "header", rows[3].kind)
test("row 4 is a service", "svc", rows[4].kind)
-- No services -> no header.
test("no services -> no header row", 2, #m.buildRows(procs, {}))

-- ── nextSelectable / firstSelectable: skip the header row ───────────
test("first selectable is 1", 1, m.firstSelectable(rows))
test("down from 2 skips header to 4", 4, m.nextSelectable(rows, 2, 1))
test("up from 4 skips header to 2", 2, m.nextSelectable(rows, 4, -1))
test("down clamps at end", 5, m.nextSelectable(rows, 5, 1))
test("up clamps at start", 1, m.nextSelectable(rows, 1, -1))
-- A list that starts with a header -> firstSelectable skips it.
test("firstSelectable skips a leading header", 2,
  m.firstSelectable({ { kind = "header" }, { kind = "svc" } }))

-- ── textRows: render rows as { text, tone } for the live monitor tab ─
local tr = m.textRows(procs, svcs)
test("textRows count matches buildRows", 5, #tr)
test("textRows proc tone", "proc", tr[1].tone)
test("textRows proc text has pid + label", true,
  tr[1].text:find("2", 1, true) ~= nil and tr[1].text:find("Shell", 1, true) ~= nil)
test("textRows header tone", "header", tr[3].tone)
test("textRows svc tone", "svc", tr[4].tone)
test("textRows running service labelled", true, tr[4].text:find("running", 1, true) ~= nil)
local trDis = m.textRows({}, { { name = "x", running = false, enabled = false } })
local annotated = false
for _, l in ipairs(trDis) do if l.text:find("disabled", 1, true) then annotated = true end end
test("textRows disabled service annotated", true, annotated)
local trEmpty = m.textRows({}, {})
test("textRows empty -> one placeholder", 1, #trEmpty)
test("textRows empty placeholder is dim", "dim", trEmpty[1].tone)

-- ── canAct: ONE kill/TSR policy for the Ctrl+T switcher AND the Monitor
-- tab (kernel.monitorAct) — pinned here so the surfaces can't drift. ────
test("root acts on anything (even kernel)", true,
  m.canAct(3, "root", 1, { user = "_kernel_", display = 2 }))
test("kernel procs immune below root", false,
  m.canAct(2, "adm", 1, { user = "_kernel_" }))
test("admin: same display ok", true,
  m.canAct(2, "adm", 1, { user = "bob", display = 1 }))
test("admin: other display denied", false,
  m.canAct(2, "adm", 1, { user = "bob", display = 2 }))
test("admin: display-unbound ok", true,
  m.canAct(2, "adm", 1, { user = "bob" }))
test("user: own process ok", true,
  m.canAct(1, "bob", 1, { user = "bob", display = 1 }))
test("user: someone else's denied", false,
  m.canAct(1, "bob", 1, { user = "eve", display = 1 }))
test("anonymous seat can't act on unowned procs", false,
  m.canAct(0, nil, 1, { display = 1 }))

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
