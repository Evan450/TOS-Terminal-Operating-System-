-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the frame and the glass hold the same thing ║
-- ║                                                                ║
-- ║  TWO OPERATOR BUGS, ONE CAUSE.                                 ║
-- ║    "the status bar turns black, the same colour as the         ║
-- ║     background"                                                ║
-- ║    "the cursor duplicates into an inert one"                   ║
-- ║                                                                ║
-- ║  A seat proxy keeps a dirty-cell shadow describing THE GLASS:  ║
-- ║  "this cell already reads like that, skip the repaint". A GPU  ║
-- ║  with video RAM also gets an off-screen PAGE: drawMod.all      ║
-- ║  opens a frame, every draw lands on the page, and one bitblt   ║
-- ║  puts the finished picture up without tearing.                 ║
-- ║                                                                ║
-- ║  Those two are only the same surface for as long as nothing    ║
-- ║  has drawn since the last blit — and in TOS most drawing does  ║
-- ║  NOT happen inside a frame. drawMod.all is the only thing that ║
-- ║  opens one; applyDraw levels 1 and 2, the once-a-second status ║
-- ║  bar tick, the file-list fast path and every dialog paint      ║
-- ║  straight to the glass.                                        ║
-- ║                                                                ║
-- ║  So the elision inverts. The frame's redraw skips every cell   ║
-- ║  whose GLASS content already matches — meaning those cells are ║
-- ║  never written to the PAGE — and then the closing blit paints  ║
-- ║  the page's version over them. On a page that was just         ║
-- ║  allocated, the page's version is blank black.                 ║
-- ║                                                                ║
-- ║  And it never heals: the shadow still says those cells are     ║
-- ║  correct, so the 1 Hz status-bar repaint that would fix it is  ║
-- ║  skipped as redundant, every second, forever.                  ║
-- ║                                                                ║
-- ║  The fix is to make the page hold what the glass holds before  ║
-- ║  drawing into it. This test models a GPU with REAL PAGES and   ║
-- ║  reads the pixels back, because a call-count assertion cannot  ║
-- ║  tell a correct blit from a wrong one. The call PATTERN is     ║
-- ║  pinned separately in test_screen_shadow.lua.                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_screen_frame.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end
local function hex(n) return string.format("0x%06X", n or 0) end

local here = (arg and arg[0]) or "usr/lib/tests/test_screen_frame.lua"
local base = here:gsub("[^/\\]*$", "")

-- ============================================================
-- A GPU with video RAM that actually stores pixels
-- ============================================================
local W, H = 80, 25
local BLACK = 0x000000

local pages   = {}          -- [0] = the glass, [n] = an allocated page
local nextBuf = 0
local active  = 0
local curFg, curBg = 0xFFFFFF, BLACK

local function newPage()
  -- What OpenComputers hands back from allocateBuffer: a blank page.
  -- Getting THIS wrong is what made the bug invisible to a mock that
  -- only counted calls.
  local cells = {}
  for k = 1, W * H do cells[k] = { " ", 0xFFFFFF, BLACK } end
  return cells
end
pages[0] = newPage()

local gpu = {
  address       = "gpu-frame-test",
  getScreen     = function() return "screen-frame-test" end,
  bind          = function() return true end,
  getResolution = function() return W, H end,
  setResolution = function() return true end,
  maxResolution = function() return W, H end,
  getDepth      = function() return 8 end,
  maxDepth      = function() return 8 end,
  setForeground = function(c) curFg = c; return true end,
  setBackground = function(c) curBg = c; return true end,
  getForeground = function() return curFg end,
  getBackground = function() return curBg end,
  set = function(x, y, text)
    local p = pages[active]; if not p then return false end
    for i = 1, #text do
      local cx = x + i - 1
      if cx >= 1 and cx <= W and y >= 1 and y <= H then
        p[(y - 1) * W + cx] = { text:sub(i, i), curFg, curBg }
      end
    end
    return true
  end,
  fill = function(x, y, w, h, ch)
    local p = pages[active]; if not p then return false end
    for yy = y, y + h - 1 do
      for xx = x, x + w - 1 do
        if xx >= 1 and xx <= W and yy >= 1 and yy <= H then
          p[(yy - 1) * W + xx] = { ch, curFg, curBg }
        end
      end
    end
    return true
  end,
  allocateBuffer  = function() nextBuf = nextBuf + 1; pages[nextBuf] = newPage(); return nextBuf end,
  freeBuffer      = function(i) pages[i] = nil; return true end,
  setActiveBuffer = function(i) active = i; return true end,
  getActiveBuffer = function() return active end,
  bitblt = function(dst, dx, dy, w, h, src, sx, sy)
    local s, d = pages[src], pages[dst]
    if not s or not d then return false end
    for yy = 0, h - 1 do
      for xx = 0, w - 1 do
        local c = s[(sy + yy - 1) * W + (sx + xx)]
        if c then d[(dy + yy - 1) * W + (dx + xx)] = { c[1], c[2], c[3] } end
      end
    end
    return true
  end,
}

package.loaded["component"] = {
  list = function(ctype)
    local given = false
    return function()
      if given then return nil end
      given = true
      if ctype == "gpu"    then return "gpu-frame-test", "gpu" end
      if ctype == "screen" then return "screen-frame-test", "screen" end
      return nil
    end
  end,
  proxy  = function() return gpu end,
  invoke = function() return nil end,
  type   = function(a) return a == "gpu-frame-test" and "gpu" or "screen" end,
}
package.loaded["computer"] = {
  uptime     = function() return 0 end,
  freeMemory = function() return 4 * 1024 * 1024 end,   -- plenty: shadow ON
  pullSignal = function() return nil end,
  beep       = function() end,
}

package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local screen = require("kernel.screen")
screen.init()
local p = screen.displayProxy(1)
if not p then
  print("FAIL: no display proxy")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- Read the GLASS (page 0) — what the operator is actually looking at.
local function cellAt(x, y) return pages[0][(y - 1) * W + x] end
local function bgAt(x, y)   return cellAt(x, y)[3] end
local function rowText(y)
  local t = {}
  for x = 1, W do t[x] = cellAt(x, y)[1] end
  return table.concat(t)
end

print("=== frame / glass coherence Tests ===")
print()

-- ============================================================
-- 1. The status bar
-- ============================================================
print("-- the status bar --")

local STAT = H
local BAR_FG, BAR_BG = 0x00FF00, 0x0000AA

-- Exactly the shape of the shell's 1 Hz idle tick: fill the row, write the
-- text, no frame opened. (events.lua's idle branch calls drawStatusBar()
-- directly; only drawMod.all frames.)
local function paintStatusBar(text)
  p.fill(1, STAT, W, 1, " ", BAR_FG, BAR_BG)
  p.set(1, STAT, text, BAR_FG, BAR_BG)
end

-- Forward-declared: drawAll calls it, and it is defined further down with
-- the rest of the cursor code. A `function cmdRowPaint(...)` down there
-- would be a GLOBAL, which is the bug class test_global_leaks.lua exists
-- to catch — so declare the local first and assign to it.
local cmdRowPaint

-- A whole-screen redraw, the shape of drawMod.all: open a frame, repaint
-- every element, close it. Nothing here clears — _allBody paints element by
-- element and leans on the shadow to skip what has not changed.
local function drawAll(statusText, cmdText)
  local framed = p.beginFrame()
  p.fill(1, 1, W, 1, " ", 0xFFFFFF, 0x333333)
  p.set(1, 1, "File  Edit  View", 0xFFFFFF, 0x333333)
  if statusText then paintStatusBar(statusText) end
  if cmdText then cmdRowPaint(cmdText) end
  if framed then p.endFrame() end
end

paintStatusBar("TOS  ok  Mem:512K")
-- Column 60 is bar background the redraw has nothing new to say about, so
-- it is exactly the kind of cell the shadow elides. Column 1 is repainted
-- either way (fill-then-text always differ) and would hide the bug.
local PROBE = 60
eq("the idle paint reaches the glass", hex(BAR_BG), hex(bgAt(PROBE, STAT)))

drawAll("TOS  ok  Mem:512K")
eq("...and SURVIVES a full redraw (this is the black status bar)",
  hex(BAR_BG), hex(bgAt(PROBE, STAT)))
test("the row still reads as the status bar",
  rowText(STAT):find("Mem:512K", 1, true) ~= nil)

-- The reason a regression here is permanent rather than a flicker: the
-- shadow would go on claiming the row is painted, so the once-a-second
-- repaint that should fix it is skipped instead.
paintStatusBar("TOS  ok  Mem:512K")
eq("a later idle tick leaves it correct", hex(BAR_BG), hex(bgAt(PROBE, STAT)))
drawAll("TOS  ok  Mem:512K")
eq("and so does a second full redraw", hex(BAR_BG), hex(bgAt(PROBE, STAT)))

-- A changing clock must still reach the glass through a frame.
drawAll("TOS  ok  Mem:480K")
test("a CHANGED status line reaches the glass",
  rowText(STAT):find("Mem:480K", 1, true) ~= nil)

-- ============================================================
-- 2. The command-line cursor
-- ============================================================
print()
print("-- the command-line cursor --")

local CMD = H - 1
local PROMPT = "root@tos:/ $ "
local TXT_FG, TXT_BG = 0xC0C0C0, BLACK
local CUR_FG, CUR_BG = BLACK, 0xC0C0C0      -- inverse video, as draw.lua does

-- draw.lua's cmdRow: prompt, then the line across the row's FULL width,
-- then one inverse-video cell overlaid as the cursor.
cmdRowPaint = function(line)
  p.set(1, CMD, PROMPT, 0x00FF00, TXT_BG)
  local px = #PROMPT + 1
  p.set(px, CMD, (line .. string.rep(" ", W)):sub(1, W - #PROMPT), TXT_FG, TXT_BG)
  local cur   = #line + 1
  local col   = px + cur - 1
  local under = (cur <= #line) and line:sub(cur, cur) or "_"
  p.set(col, CMD, under, CUR_FG, CUR_BG)
  return col
end

-- Every cell on the row wearing the cursor's background is a cursor.
local function cursorColumns()
  local cols = {}
  for x = 1, W do
    if bgAt(x, CMD) == CUR_BG then cols[#cols + 1] = x end
  end
  return cols
end

drawAll(nil, "")                       -- a framed redraw with an empty line
local c0 = cursorColumns()
eq("one cursor after the first full redraw", 1, #c0)

-- The operator types. Each keystroke is applyDraw level 1: it repaints the
-- command row WITHOUT opening a frame, so it lands on the glass alone.
for _, line in ipairs({ "l", "ls", "ls ", "ls -", "ls -l" }) do cmdRowPaint(line) end
local c1 = cursorColumns()
eq("still one cursor while typing", 1, #c1)
test("...and it moved right", c1[1] > c0[1])

-- Now anything that asks for a whole-screen redraw: F9, a tab switch, a
-- command that returns draw = 3.
drawAll(nil, "ls -l")
local c2 = cursorColumns()
eq("ONE cursor after the full redraw (this is the duplicate)", 1, #c2)
eq("...and it is the live one, not a leftover", c1[1], c2[1])

-- Typing on must keep moving the one cursor, never strand another.
cmdRowPaint("ls -la")
cmdRowPaint("ls -lah")
local c3 = cursorColumns()
eq("one cursor after typing again", 1, #c3)
test("...still moving", c3[1] > c2[1])

-- ============================================================
-- 3. The general rule, stated as itself
-- ============================================================
-- Anything painted outside a frame must survive the next frame, whatever
-- it is — the status bar and the cursor are the two an operator noticed,
-- not the only two that were being reverted.
print()
print("-- anything drawn outside a frame --")

p.set(5, 10, "OUTSIDE", 0xFF00FF, 0x004400)
eq("a mid-screen direct write lands", "OUTSIDE", rowText(10):sub(5, 11))
drawAll(nil, nil)
eq("...and survives a frame that never mentions it", "OUTSIDE", rowText(10):sub(5, 11))
eq("...with its colours intact", hex(0x004400), hex(bgAt(5, 10)))

-- And the frame must still be doing its job: a draw INSIDE one reaches the
-- glass only when the frame closes, in one blit.
do
  local framed = p.beginFrame()
  p.set(5, 12, "INSIDE", 0xFFFFFF, 0x440000)
  if framed then
    test("a draw inside an open frame has not reached the glass yet",
      rowText(12):sub(5, 10) ~= "INSIDE")
    p.endFrame()
  end
  eq("...and lands when the frame closes", "INSIDE", rowText(12):sub(5, 10))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
