-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: cold view-buffer paging (kernel.swap's  ║
-- ║  first real consumer)                                     ║
-- ║                                                            ║
-- ║  kernel.swap shipped complete but UNWIRED — nothing ever   ║
-- ║  called swap.store, so "swap enabled" could never become   ║
-- ║  swap used. View tabs are the first tenant: a `cat` of a   ║
-- ║  big file keeps every line resident in a tab nobody is     ║
-- ║  reading, and the buffer is loss-tolerant.                 ║
-- ║                                                            ║
-- ║  Pins: eligibility rules, that paging actually reaches     ║
-- ║  swap, TRANSPARENT restore on the next read (no reader in  ║
-- ║  draw/events/mouse was changed), pressure gating, and that ║
-- ║  a lost entry degrades instead of crashing.                ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_tab_paging.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- ── Fake machine: controllable free/total memory ──────────────
local freeMem, totalMem = 900 * 1024, 1024 * 1024
package.loaded["computer"] = {
  uptime      = function() return 0 end,
  freeMemory  = function() return freeMem end,
  totalMemory = function() return totalMem end,
}
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

-- ── Fake kernel.swap: a real store, so paging is observable ───
local store, storeFails = {}, false
local swap = {
  store = function(k, v) if storeFails then return false, "swap full" end
                         store[k] = v; return true end,
  fetch = function(k) return store[k] end,
  free  = function(k) store[k] = nil; return true end,
  keys  = function() local t = {} for k in pairs(store) do t[#t+1] = k end return t end,
}
local cfgValue = nil
_G._TOS = {
  kernel = {
    getSwap   = function() return swap end,
    getConfig = function() return { get = function(k)
      if k == "swapPressurePct" then return cfgValue end
    end } end,
  },
}

local tabs = require("shell.panels.tabs")

local function bigContent(n, tag)
  local c = {}
  for i = 1, n do c[i] = { (tag or "line") .. " " .. i } end
  return c
end
local function newState()
  -- Each block starts with an empty store, so a count assertion measures
  -- that block and not what an earlier one left paged.
  for k in pairs(store) do store[k] = nil end
  return { tabs = {}, activeTab = 1 }
end

-- ============================================================
print("\n-- eligibility --")

do
  local S = newState()
  local view  = tabs.create(S, "view", "Big",   { content = bigContent(500) })
  local small = tabs.create(S, "view", "Small", { content = bigContent(10) })
  local live  = tabs.create(S, "view", "Live",  { content = bigContent(500), live = true })
  local shell = tabs.create(S, "shell", "Shell", {})

  test("a large static view buffer pages out", tabs.pageOut(view))
  eq("a small buffer is not worth the disk round-trip", false, tabs.pageOut(small))
  eq("a LIVE tab is skipped (it rebuilds itself)", false, tabs.pageOut(live))
  eq("a shell tab is never paged", false, tabs.pageOut(shell))
  eq("paging an already-paged tab is a no-op", false, tabs.pageOut(view))
  test("the paged tab is marked", tabs.isPaged(view))
  test("its content really reached the swap store", next(store) ~= nil)
end

-- ============================================================
print("\n-- transparent restore --")

do
  local S = newState()
  local tab = tabs.create(S, "view", "Doc", { content = bigContent(300, "row") })
  tabs.pageOut(tab)

  -- The buffer is genuinely out of the tab...
  eq("content is no longer held on the tab", nil, rawget(tab, "content"))
  -- ...and comes back on an ordinary read, with no reader changes anywhere.
  local c = tab.content
  test("reading tab.content restores it", type(c) == "table")
  eq("every line came back", 300, #c)
  eq("contents are intact", "row 1", c[1] and c[1][1])
  eq("...including the last line", "row 300", c[300] and c[300][1])
  eq("the tab is no longer paged after restore", false, tabs.isPaged(tab))
  eq("the swap entry was released on restore", 0, #swap.keys())
  -- A second read is a plain table access, not another fetch.
  test("restored content is now a normal field", rawget(tab, "content") ~= nil)
end

-- ============================================================
print("\n-- pressure gating --")

do
  local S = newState()
  tabs.create(S, "view", "A", { content = bigContent(400) })
  tabs.create(S, "view", "B", { content = bigContent(400) })
  S.activeTab = 1

  -- Roomy: 900K free of 1024K is ~88%, far above the 25% default.
  freeMem = 900 * 1024
  eq("no pressure -> nothing pages (a roomy box pays nothing)", 0,
    tabs.sweepCold(S))

  -- ...but the operator can force it, which is how the wiring is verifiable
  -- on a machine that never gets tight.
  eq("forced sweep pages the cold tab", 1, tabs.sweepCold(S, true))
  eq("the ACTIVE tab is never paged", false, tabs.isPaged(S.tabs[1]))
  test("the inactive tab was paged", tabs.isPaged(S.tabs[2]))
end

do
  local S = newState()
  tabs.create(S, "view", "A", { content = bigContent(400) })
  tabs.create(S, "view", "B", { content = bigContent(400) })
  S.activeTab = 1
  freeMem = 100 * 1024            -- ~10% free: under the 25% default
  eq("under pressure -> cold tabs page automatically", 1, tabs.sweepCold(S))

  local paged, lines = tabs.pagedStats(S)
  eq("pagedStats counts the tab", 1, paged)
  eq("pagedStats counts its lines", 400, lines)
end

do
  -- The threshold is operator-tunable, which is the knob the operator
  -- expected to find in the first place.
  local S = newState()
  tabs.create(S, "view", "A", { content = bigContent(400) })
  tabs.create(S, "view", "B", { content = bigContent(400) })
  S.activeTab = 1
  freeMem = 500 * 1024            -- ~49% free
  cfgValue = 25
  eq("49% free is above a 25% threshold", 0, tabs.sweepCold(S))
  cfgValue = 60
  eq("raising swapPressurePct to 60 makes it page", 1, tabs.sweepCold(S))
  cfgValue = nil
end

-- ============================================================
print("\n-- failure modes degrade, never crash --")

do
  -- A full swap must leave the buffer in RAM, not drop it.
  local S = newState()
  local tab = tabs.create(S, "view", "Full", { content = bigContent(400) })
  storeFails = true
  eq("a full swap refuses to page", false, tabs.pageOut(tab))
  storeFails = false
  test("the buffer is still intact in RAM", rawget(tab, "content") ~= nil)
  eq("...with every line", 400, #tab.content)
end

do
  -- Swap is scratch: an entry can vanish (clear / over-cap / bad decode).
  local S = newState()
  local tab = tabs.create(S, "view", "Lost", { content = bigContent(400) })
  tabs.pageOut(tab)
  for k in pairs(store) do store[k] = nil end       -- entry disappears
  local okRead, c = pcall(function() return tab.content end)
  test("reading a lost buffer does not raise", okRead)
  test("it degrades to a visible notice", type(c) == "table" and c[1] and
    tostring(c[1][1]):find("could not be restored", 1, true) ~= nil)
end

do
  -- Closing a paged tab must release its entry, not page it back to bin it.
  local S = newState()
  local tab = tabs.create(S, "view", "Closing", { content = bigContent(400) })
  tabs.pageOut(tab)
  eq("entry is in the store before close", 1, #swap.keys())
  tabs.close(S, 1)
  eq("closing a paged tab frees its swap entry", 0, #swap.keys())
  eq("the tab is gone", 0, #S.tabs)
end

do
  -- No swap module at all (feature off / older kernel): stay in RAM.
  local savedKernel = _G._TOS.kernel
  _G._TOS.kernel = { getSwap = function() return nil end }
  local S = newState()
  local tab = tabs.create(S, "view", "NoSwap", { content = bigContent(400) })
  eq("with swap unavailable, nothing pages", false, tabs.pageOut(tab))
  eq("the buffer is untouched", 400, #tab.content)
  _G._TOS.kernel = savedKernel
end

-- ============================================================
print("")
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
end
print("*** ALL TESTS PASSED ***")
return true
