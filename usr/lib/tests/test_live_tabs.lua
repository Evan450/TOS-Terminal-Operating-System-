-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: live tabs (panels editor)                ║
-- ║                                                            ║
-- ║  A live tab is a view tab that regenerates its own content ║
-- ║  from a refresh() closure (the event loop ticks it). Verify ║
-- ║  openLiveTab builds it with the live fields + header, that  ║
-- ║  refreshLiveTab re-runs the closure and clamps scroll, and  ║
-- ║  that a throwing refresh is contained.                      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_live_tabs.lua

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

package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local editor = require("shell.panels.editor")

-- Minimal shell state the editor/helpers touch. tier 1 => no gutter reserve, so
-- short lines never wrap and content counts stay deterministic.
local S = {
  T = { fg = "fg", dim = "dim", error = "err", border = "bd" },
  W = 80, H = 25, tier = 1, tabs = {}, activeTab = 0,
}

-- ── openLiveTab builds a live view tab ──────────────────────────────
local count = 0
local function refresh()
  count = count + 1
  return { { "alpha " .. count, "fg" }, { "beta", "fg" } }
end
local tab = editor.openLiveTab(S, "ps", refresh, 3)

test("tab created + active", true, tab ~= nil and S.tabs[1] == tab)
test("tab is a view tab", "view", tab.type)
test("tab marked live", true, tab.live == true)
test("interval recorded", 3, tab.interval)
test("refresh closure stored", true, tab.refresh == refresh)
test("liveLabel kept", "ps", tab.liveLabel)
test("label carries the name", true, tab.label:find("ps", 1, true) ~= nil)
test("refresh ran once at open", 1, count)
-- content = LIVE header + blank + 2 data lines
test("content = header+blank+2", 4, #tab.content)
test("header line says LIVE", true, tab.content[1][1]:find("LIVE", 1, true) ~= nil)
test("data line 1 present", true, tab.content[3][1]:find("alpha 1", 1, true) ~= nil)

-- ── refreshLiveTab re-runs the closure ──────────────────────────────
editor.refreshLiveTab(S, tab)
test("refresh ran again", 2, count)
test("content updated (alpha 2)", true, tab.content[3][1]:find("alpha 2", 1, true) ~= nil)
-- A rising tick count in the header proves liveness even when the watched
-- command's output is identical refresh-to-refresh (e.g. `watch ps` idle).
test("refresh tick count rises", 2, tab.refreshCount)
test("header carries the tick count", true, tab.content[1][1]:find("2", 1, true) ~= nil)

-- ── scroll offset is clamped to the (short) content ────────────────
tab.offset = 999
editor.refreshLiveTab(S, tab)
local maxOff = math.max(0, #tab.content - (S.H - 2))
test("offset clamped after refresh", maxOff, tab.offset)

-- ── a throwing refresh is contained, not propagated ────────────────
local badTab = editor.openLiveTab(S, "bad", function() error("boom") end, 1)
test("bad refresh didn't crash openLiveTab", true, badTab ~= nil)
test("bad refresh shows an error line", true,
  badTab.content[3] and badTab.content[3][1]:find("refresh error", 1, true) ~= nil)

-- ── guards ──────────────────────────────────────────────────────────
test("openLiveTab needs a function", nil, editor.openLiveTab(S, "x", "not a fn", 1))

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
