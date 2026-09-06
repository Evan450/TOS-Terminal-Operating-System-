-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a video-RAM page has its OWN colour state    ║
-- ║                                                                ║
-- ║  THE BLACK STATUS BAR, SEVENTH TIME -- and the first time the  ║
-- ║  glass, not the shadow, is what was lied about.                ║
-- ║                                                                ║
-- ║  In OpenComputers every GPU buffer -- the screen (index 0) and ║
-- ║  each page allocateBuffer hands out -- is a separate TextBuffer ║
-- ║  with its own foreground and background. setBackground while a ║
-- ║  page is active sets THE PAGE's colour; buffer 0 keeps whatever ║
-- ║  it had. bitblt copies cells, never that state.                ║
-- ║                                                                ║
-- ║  The seat proxy kept ONE colour cache. drawMod.all opens a     ║
-- ║  frame, paints everything onto the page -- the status bar last ║
-- ║  -- and closes it, leaving the cache saying "the GPU is at     ║
-- ║  statusbar_bg". True of the page. The screen is still at the   ║
-- ║  colour of whatever was last drawn OUTSIDE a frame: the prompt ║
-- ║  row's black. The 1 Hz tick then repaints the bar's changed     ║
-- ║  cells, SKIPS setBackground as redundant, and every one of     ║
-- ║  them lands black. The shadow records statusbar_bg. Exactly    ║
-- ║  the operator's log line: screen=000000, cache=<statusbar_bg>. ║
-- ║                                                                ║
-- ║  "Sometimes" because it needs the page's last colour to equal  ║
-- ║  the next outside draw's colour while the glass differs; a     ║
-- ║  theme change reorders every colour and can leave the pair     ║
-- ║  agreeing. Four rounds of declaration fixes could not see it:  ║
-- ║  nothing drew outside the proxy. The proxy's own arithmetic    ║
-- ║  was wrong about what a buffer switch does.                    ║
-- ║                                                                ║
-- ║  test_screen_frame.lua models pages with real pixels but ONE   ║
-- ║  shared colour state, which is why it stays green against the  ║
-- ║  bug. This mock gives each page its own, as the hardware does. ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_screen_page_colors.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_screen_page_colors.lua"
local base = here:gsub("[^/\\]*$", "")

-- ============================================================
-- A GPU whose buffers each carry their own colours
-- ============================================================
local W, H = 80, 25
local BLACK, WHITE = 0x000000, 0xFFFFFF

local pages, nextBuf, active = {}, 0, 0
local function newPage()
  local cells = {}
  for k = 1, W * H do cells[k] = { " ", WHITE, BLACK } end
  -- OC's TextBuffer: cells PLUS a current foreground/background.
  return { cells = cells, fg = WHITE, bg = BLACK }
end
pages[0] = newPage()

local bgCalls = 0   -- setBackground issued (any buffer)
local gpu = {
  address       = "gpu-page-colours",
  getScreen     = function() return "screen-page-colours" end,
  bind          = function() return true end,
  getResolution = function() return W, H end,
  setResolution = function() return true end,
  maxResolution = function() return W, H end,
  getDepth      = function() return 8 end,
  maxDepth      = function() return 8 end,
  setForeground = function(c) pages[active].fg = c; return true end,
  setBackground = function(c) bgCalls = bgCalls + 1; pages[active].bg = c; return true end,
  getForeground = function() return pages[active].fg end,
  getBackground = function() return pages[active].bg end,
  get = function(x, y)
    local c = pages[active].cells[(y - 1) * W + x]
    if not c then return nil end
    return c[1], c[2], c[3]
  end,
  set = function(x, y, text)
    local p = pages[active]; if not p then return false end
    -- One cell per CHARACTER, as the hardware does. Splitting by byte
    -- smears a ramp glyph over three cells, and the proxy's audit then
    -- "repairs" a mismatch that is the mock's, not the code's -- which
    -- hides exactly the bug this file exists to catch.
    local i = 0
    for ch in text:gmatch("[\0-\127\194-\255][\128-\191]*") do
      local cx = x + i
      if cx >= 1 and cx <= W and y >= 1 and y <= H then
        p.cells[(y - 1) * W + cx] = { ch, p.fg, p.bg }
      end
      i = i + 1
    end
    return true
  end,
  fill = function(x, y, w, h, ch)
    local p = pages[active]; if not p then return false end
    for yy = y, y + h - 1 do
      for xx = x, x + w - 1 do
        if xx >= 1 and xx <= W and yy >= 1 and yy <= H then
          p.cells[(yy - 1) * W + xx] = { ch, p.fg, p.bg }
        end
      end
    end
    return true
  end,
  allocateBuffer  = function() nextBuf = nextBuf + 1; pages[nextBuf] = newPage(); return nextBuf end,
  freeBuffer      = function(i) pages[i] = nil; return true end,
  setActiveBuffer = function(i) if not pages[i] then return false end; active = i; return true end,
  getActiveBuffer = function() return active end,
  bitblt = function(dst, dx, dy, w, h, src, sx, sy)
    local s, d = pages[src], pages[dst]
    if not s or not d then return false end
    for yy = 0, h - 1 do
      for xx = 0, w - 1 do
        local c = s.cells[(sy + yy - 1) * W + (sx + xx)]
        if c then d.cells[(dy + yy - 1) * W + (dx + xx)] = { c[1], c[2], c[3] } end
      end
    end
    return true   -- cells only; each buffer keeps its own colours
  end,
}

package.loaded["component"] = {
  list = function(ctype)
    local given = false
    return function()
      if given then return nil end
      given = true
      if ctype == "gpu"    then return "gpu-page-colours", "gpu" end
      if ctype == "screen" then return "screen-page-colours", "screen" end
      return nil
    end
  end,
  proxy  = function() return gpu end,
  invoke = function() return nil end,
  type   = function(a) return a == "gpu-page-colours" and "gpu" or "screen" end,
}
local clock = 0
package.loaded["computer"] = {
  uptime     = function() return clock end,
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

local function cellAt(x, y) return pages[0].cells[(y - 1) * W + x] end
local function rowText(y)
  local t = {}
  for x = 1, W do t[x] = cellAt(x, y)[1] end
  return table.concat(t)
end
-- Every column of a row that is NOT in the given background.
local function offColumns(y, bg)
  local cols = {}
  for x = 1, W do if cellAt(x, y)[3] ~= bg then cols[#cols + 1] = x end end
  return cols
end

print("=== page colour state Tests ===")
print()

local STAT, CMD = H, H - 1
local BAR_FG, BAR_BG = 0x00FF00, 0x0000AA
local CAP_FG = 0x008800
local TXT_FG, TXT_BG = 0xC0C0C0, BLACK
local MENU_BG = 0x333333

-- ui.drawRampBar, to the call: fill the row with the filler glyph, caps,
-- then the label. The label region is re-emitted on EVERY tick because
-- the filler overwrote it, so a stale colour lands there immediately.
local function paintStatusBar(label)
  p.fill(1, STAT, W, 1, "░", CAP_FG, BAR_BG)
  p.set(1, STAT, "▓▒░", CAP_FG, BAR_BG)
  p.set(W - 2, STAT, "░▒▓", CAP_FG, BAR_BG)
  p.set(5, STAT, " " .. label .. " ", BAR_FG, BAR_BG)
end
-- draw.lua's cmdRow, outside any frame (applyDraw level 1 = a keystroke).
local function paintCmdRow(line)
  p.set(1, CMD, "root@tos:/ $ ", 0x00FF00, TXT_BG)
  p.set(14, CMD, (line .. string.rep(" ", W)):sub(1, W - 13), TXT_FG, TXT_BG)
end
-- drawMod.all: one frame, status bar LAST -- so the page is left at the
-- bar's colours.
local function drawAll(label, line)
  local framed = p.beginFrame()
  p.fill(1, 1, W, 1, " ", WHITE, MENU_BG)
  p.set(1, 1, "File  Edit  View", WHITE, MENU_BG)
  paintCmdRow(line)
  paintStatusBar(label)
  if framed then p.endFrame() end
  return framed
end

-- ── 1. The operator's sequence ─────────────────────────────
print("-- the sequence from the operator's machine --")
paintStatusBar("Clock:12:00:00 │ Mem:512K")
paintCmdRow("l")                       -- a keystroke: the glass is now at black
eq("before any frame the bar is intact", 0, #offColumns(STAT, BAR_BG))

test("this GPU has pages (the test is about them)", drawAll("Clock:12:00:01 │ Mem:512K", "l"))
eq("the framed redraw leaves the bar intact", 0, #offColumns(STAT, BAR_BG))
eq("...and buffer 0 still holds the colour of the last OUTSIDE draw",
   hex(TXT_BG), hex(pages[0].bg))

clock = clock + 1
paintStatusBar("Clock:12:00:02 │ Mem:512K")   -- the 1 Hz tick, outside a frame
local off = offColumns(STAT, BAR_BG)
eq("the tick after a frame paints the changed cells in the BAR colour "
   .. "(this is the black status bar)", 0, #off)
if #off > 0 then
  print("      wrong columns: " .. off[1] .. ".." .. off[#off]
    .. "  glass=" .. hex(cellAt(off[1], STAT)[3]) .. " expected=" .. hex(BAR_BG))
end
test("...and the label reads right", rowText(STAT):find("12:00:02", 1, true) ~= nil)
eq("the label's FOREGROUND is the bar's, not the page's leftover",
   hex(BAR_FG), hex(cellAt(6, STAT)[2]))

-- ── 2. It must not become permanent either ─────────────────
print()
print("-- the next frame must not cement a wrong row --")
clock = clock + 1
drawAll("Clock:12:00:03 │ Mem:512K", "ls")
eq("a second framed redraw: bar intact", 0, #offColumns(STAT, BAR_BG))
clock = clock + 1
paintStatusBar("Clock:12:00:04 │ Mem:511K")
eq("and the tick after it: bar intact", 0, #offColumns(STAT, BAR_BG))
eq("the command row is in ITS colours after all that",
   hex(TXT_BG), hex(cellAt(20, CMD)[3]))

-- ── 3. The mirror image: a draw in the GLASS's stale colour ──
-- The page was left at TXT_BG by a frame that painted the prompt last,
-- while buffer 0 sits at BAR_BG from the last tick. Typing must still
-- come out black.
print()
print("-- the mirror image --")
do
  local framed = p.beginFrame()
  paintStatusBar("Clock:12:00:05 │ Mem:511K")
  paintCmdRow("ls -")                  -- prompt LAST: page left at TXT_BG
  if framed then p.endFrame() end
end
paintStatusBar("Clock:12:00:06 │ Mem:511K")  -- glass now at BAR colours
paintCmdRow("ls -l")
eq("typed text lands on the prompt's background", hex(TXT_BG), hex(cellAt(18, CMD)[3]))
eq("...in the prompt's foreground", hex(TXT_FG), hex(cellAt(18, CMD)[2]))

-- ── 4. The cache still saves calls where it legitimately can ─
print()
print("-- the cache is still a cache --")
paintStatusBar("Clock:12:00:07 │ Mem:511K")
local before = bgCalls
paintStatusBar("Clock:12:00:08 │ Mem:511K")
paintStatusBar("Clock:12:00:09 │ Mem:511K")
eq("two more idle ticks on one background cost no setBackground at all",
   0, bgCalls - before)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
