-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: displayProxy dirty-cell shadow buffer    ║
-- ║                                                            ║
-- ║  The per-seat proxy skips a gpu.set/fill when the target   ║
-- ║  cells already hold exactly what's being drawn — the main  ║
-- ║  redraw saving. Resets after clear, a resize, getGpu(), or ║
-- ║  a forwarded (withContext) method that draws outside it.   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_screen_shadow.lua

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

local GPU, SCR = "gpu-1", "scr-1"
local mockGpu_real_fg, mockGpu_real_bg = 0xFFFFFF, 0x000000
local calls = { set = 0, fill = 0 }
local mockGpu = {
  bind = function() return true end,
  getScreen = function() return SCR end,
  maxResolution = function() return 80, 25 end,
  setResolution = function() return true end,
  getResolution = function() return 80, 25 end,
  getDepth = function() return 8 end,
  -- The colours are RECORDED, not ignored: `real_bg` is the hardware's
  -- true state, and every set/fill notes the colour it actually painted
  -- with. A cache that lies shows up as a draw landing in the wrong one.
  setForeground = function(c) mockGpu_real_fg = c end,
  setBackground = function(c) mockGpu_real_bg = c end,
  set = function(x, y, s)
    calls.set = calls.set + 1; calls.lastSet = { x, y, s }
    calls.lastSetBg = mockGpu_real_bg
  end,
  fill = function()
    calls.fill = calls.fill + 1
    calls.lastFillBg = mockGpu_real_bg
  end,
}
package.loaded["component"] = {
  list = function(ctype)
    local a = (ctype == "gpu") and { GPU } or (ctype == "screen") and { SCR } or {}
    local i = 0
    return function() i = i + 1; return a[i] end
  end,
  proxy = function(x) if x == GPU then return mockGpu end end,
  slot = function() return 0 end,
  invoke = function(_, m)
    if m == "getKeyboards" then return {} end
    if m == "getAspectRatio" then return 1, 1 end
  end,
}
-- Plenty of free RAM so the memory-gated shadow buffer is enabled.
package.loaded["computer"] = { uptime = function() return 0 end,
                               freeMemory = function() return 8 * 1024 * 1024 end }
-- kernel.display: minimal. withContext + a forwarded method exercise the
-- shadow-invalidation path.
package.loaded["kernel.display"] = {
  getTheme = function() return {} end,
  refreshSize = function() end,
  withContext = function(_, _, _, fn) return fn() end,
  box = function() end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_screen_shadow.lua"
local base = here:gsub("[^/\\]*$", "")
local screen
for _, p in ipairs({ base .. "../../../tos/kernel/screen.lua",
    "tos/kernel/screen.lua", "TOS-Dev/tos/kernel/screen.lua" }) do
  local chunk = loadfile(p); if chunk then screen = chunk(); break end
end
if not screen or not screen._spanMatches then
  print("FAIL: could not load screen.lua / _spanMatches missing")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== displayProxy shadow buffer Tests ===")
print()

-- ── Pure span-match decision ──────────────────────────────────────
local shC, shF, shB = {}, {}, {}
test("empty shadow -> mismatch", false, screen._spanMatches(shC, shF, shB, 0, 1, { "A" }, 1, 0, 80))
shC[1], shF[1], shB[1] = "A", 1, 0
test("exact match -> true", true, screen._spanMatches(shC, shF, shB, 0, 1, { "A" }, 1, 0, 80))
test("char differs -> false", false, screen._spanMatches(shC, shF, shB, 0, 1, { "B" }, 1, 0, 80))
test("fg differs -> false", false, screen._spanMatches(shC, shF, shB, 0, 1, { "A" }, 9, 0, 80))
test("off-screen col -> false", false, screen._spanMatches(shC, shF, shB, 0, 81, { "A" }, 1, 0, 80))

-- ── Live dedup through a proxy ────────────────────────────────────
screen.init()
local px = screen.displayProxy(1)
test("proxy built", "table", type(px))

px.set(1, 1, "Hello", 0xFFFFFF, 0x000000)
test("first set draws", 1, calls.set)
px.set(1, 1, "Hello", 0xFFFFFF, 0x000000)
test("identical set is skipped", 1, calls.set)
px.set(1, 1, "World", 0xFFFFFF, 0x000000)
test("changed text draws", 2, calls.set)
px.set(1, 1, "World", 0xFF0000, 0x000000)
test("changed colour draws", 3, calls.set)
px.set(1, 1, "World", 0xFF0000, 0x000000)
test("repeat is skipped again", 3, calls.set)

local f0 = calls.fill
px.fill(1, 5, 80, 1, " ", 0xFFFFFF, 0x000000)
test("first fill draws", f0 + 1, calls.fill)
px.fill(1, 5, 80, 1, " ", 0xFFFFFF, 0x000000)
test("identical fill is skipped", f0 + 1, calls.fill)

-- clear resets the shadow, so the same row must be redrawn afterward.
px.clear(0x000000)
px.set(1, 1, "World", 0xFF0000, 0x000000)
test("set after clear redraws", 4, calls.set)
px.set(1, 1, "World", 0xFF0000, 0x000000)
test("then skips again", 4, calls.set)

-- A forwarded (withContext) method drew outside the shadow -> invalidates it,
-- so the next identical set must redraw.
px.box()
px.set(1, 1, "World", 0xFF0000, 0x000000)
test("set after forwarded method redraws", 5, calls.set)

-- getGpu() hands out the raw GPU -> also invalidates.
local _ = px.getGpu()
px.set(1, 1, "World", 0xFF0000, 0x000000)
test("set after getGpu redraws", 6, calls.set)

-- ── Partial-diff trim (#PERF playbook: changed window only) ────────
-- Pure _diffWindow decisions.
local dC, dF, dB = {}, {}, {}
for i = 1, 10 do dC[i], dF[i], dB[i] = "x", 7, 0 end
local a, b = screen._diffWindow(dC, dF, dB, 0, 1, { "x", "x", "x", "x", "x" }, 7, 0, 80)
test("diff: full match -> nil", nil, a)
a, b = screen._diffWindow(dC, dF, dB, 0, 1, { "x", "Y", "x", "Z", "x" }, 7, 0, 80)
test("diff: window trims matching prefix", 2, a)
test("diff: window trims matching suffix", 4, b)
a, b = screen._diffWindow(dC, dF, dB, 0, 79, { "x", "x", "x" }, 7, 0, 80)
test("diff: off-screen span -> full window (first)", 1, a)
test("diff: off-screen span -> full window (last)", 3, b)

-- Live: redraw a row with a small middle change — the emitted gpu.set
-- must carry ONLY the changed window, at the window's x.
px.set(5, 20, "AAAAAAAAAA", 0xFFFFFF, 0x000000)   -- cells x=5..14
local n0 = calls.set
px.set(5, 20, "AAAABBAAAA", 0xFFFFFF, 0x000000)   -- only cells 9..10 change
test("trim: partial change is one call", n0 + 1, calls.set)
test("trim: emitted at the window's x", 9, calls.lastSet[1])
test("trim: only the changed window sent", "BB", calls.lastSet[3])
-- The trimmed write must still update the shadow: an identical full-row
-- redraw now skips the GPU entirely.
px.set(5, 20, "AAAABBAAAA", 0xFFFFFF, 0x000000)
test("trim: repeat of the full row skips", n0 + 1, calls.set)

-- ── Buffer stats: the elided-vs-emitted counters `optimize` surfaces ──
if screen.resetBufferStats and screen.bufferStats then
  screen.resetBufferStats()
  px.set(10, 10, "STATS", 0xFFFFFF, 0x000000)   -- fresh content -> emitted
  px.set(10, 10, "STATS", 0xFFFFFF, 0x000000)   -- identical     -> skipped
  local st = screen.bufferStats()
  test("stats: one emitted", 1, st.emitted)
  test("stats: one skipped", 1, st.skipped)
  test("stats: total 2", 2, st.total)
  test("stats: ratio 0.5", 0.5, st.ratio)
  -- A fill that changes a fresh row counts as emitted; a repeat as skipped.
  screen.resetBufferStats()
  px.fill(1, 12, 20, 1, " ", 0xFFFFFF, 0x000000)
  px.fill(1, 12, 20, 1, " ", 0xFFFFFF, 0x000000)
  local st2 = screen.bufferStats()
  test("stats: fill emit+skip counted", 2, st2.total)
  test("stats: fill skipped 1", 1, st2.skipped)
end

-- ── Fill trimming (#PERF: changed bounding box only) ───────────────
-- Pure _fillWindow decisions.
local qC, qF, qB = {}, {}, {}
for y = 1, 3 do for x = 1, 10 do qC[(y - 1) * 80 + x] = " "
  qF[(y - 1) * 80 + x] = 7; qB[(y - 1) * 80 + x] = 0 end end
local wx1 = screen._fillWindow(qC, qF, qB, 1, 1, 10, 3, " ", 7, 0, 80)
test("fillwin: whole rect matches -> nil", nil, wx1)
-- Dirty one interior cell: the box collapses to exactly that cell.
qC[(2 - 1) * 80 + 5] = "Z"
local ax1, ay1, ax2, ay2 = screen._fillWindow(qC, qF, qB, 1, 1, 10, 3, " ", 7, 0, 80)
test("fillwin: single dirty cell x1", 5, ax1)
test("fillwin: single dirty cell y1", 2, ay1)
test("fillwin: single dirty cell x2", 5, ax2)
test("fillwin: single dirty cell y2", 2, ay2)
-- Two dirty cells on different rows -> the box spans both.
qC[(3 - 1) * 80 + 8] = "Z"
ax1, ay1, ax2, ay2 = screen._fillWindow(qC, qF, qB, 1, 1, 10, 3, " ", 7, 0, 80)
test("fillwin: spanning box x1", 5, ax1)
test("fillwin: spanning box y1", 2, ay1)
test("fillwin: spanning box x2", 8, ax2)
test("fillwin: spanning box y2", 3, ay2)
-- A wholly-unwritten shadow is all-dirty -> the box is the full rect.
local eC, eF, eB = {}, {}, {}
ax1, ay1, ax2, ay2 = screen._fillWindow(eC, eF, eB, 2, 2, 6, 4, " ", 7, 0, 80)
test("fillwin: empty shadow -> full rect x1", 2, ax1)
test("fillwin: empty shadow -> full rect y2", 4, ay2)

-- Live: a fill whose row is already mostly correct emits a TRIMMED rect.
px.fill(1, 22, 40, 1, "-", 0xFFFFFF, 0x000000)      -- lay down 40 cells
local fillArgs
mockGpu.fill = function(x, y, w, h, c)
  calls.fill = calls.fill + 1; fillArgs = { x, y, w, h, c }
end
px.set(38, 22, "==", 0xFFFFFF, 0x000000)            -- dirty cells 38..39
local fc0 = calls.fill
px.fill(1, 22, 40, 1, "-", 0xFFFFFF, 0x000000)      -- same fill again
test("fill trim: one call", fc0 + 1, calls.fill)
test("fill trim: starts at first dirty col", 38, fillArgs[1])
test("fill trim: only the dirty width", 2, fillArgs[3])
px.fill(1, 22, 40, 1, "-", 0xFFFFFF, 0x000000)      -- now wholly clean
test("fill trim: fully-clean repeat skips", fc0 + 1, calls.fill)

-- ── Hardware backbuffer ────────────────────────────────────────────
-- No buffer methods on the mock yet: begin/end must no-op, not error.
test("backbuffer: unsupported begin -> false", false, px.beginFrame())
test("backbuffer: unpaired end -> false", false, px.endFrame())
test("backbuffer: none allocated", false, px.hasBackbuffer())

local vram = { active = 0, allocated = {}, blits = 0, freed = 0,
               seeds = 0, presents = 0 }
mockGpu.allocateBuffer = function(w, h)
  vram.allocated[#vram.allocated + 1] = { w, h }; return #vram.allocated
end
mockGpu.setActiveBuffer = function(i) vram.active = i; return true end
mockGpu.freeBuffer = function() vram.freed = vram.freed + 1; return true end
-- bitblt does two different jobs and the test has to tell them apart:
--   SEEDING    screen -> page (src == 0), at the top of a frame
--   PRESENTING page -> screen (dst == 0), at the bottom of one
mockGpu.bitblt = function(dst, _, _, _, _, src)
  vram.blits = vram.blits + 1
  if src == 0 then vram.seeds = vram.seeds + 1
  elseif dst == 0 then vram.presents = vram.presents + 1 end
  return true
end

local bp = screen.displayProxy(1)
test("backbuffer: supported begin -> true", true, bp.beginFrame())
test("backbuffer: allocated once", 1, #vram.allocated)
test("backbuffer: drawing redirected off-screen", 1, vram.active)
test("backbuffer: reports allocated", true, bp.hasBackbuffer())
-- A page that was just allocated holds NOTHING (OC hands back a blank one),
-- so the frame has to seed it from the glass before its elisions mean
-- anything. Without that, every cell the redraw skips as "already correct"
-- is a cell the closing blit paints black. test_screen_frame.lua pins the
-- pixels; this pins the call pattern.
test("backbuffer: a fresh page is seeded from the glass", 1, vram.seeds)
test("backbuffer: end blits", true, bp.endFrame())
test("backbuffer: one present", 1, vram.presents)
test("backbuffer: restored to screen", 0, vram.active)
-- Second frame reuses the page rather than reallocating.
bp.beginFrame(); bp.endFrame()
test("backbuffer: page reused", 1, #vram.allocated)
test("backbuffer: two presents", 2, vram.presents)
-- ...and does NOT re-seed: the closing blit left page and glass identical,
-- and nothing has drawn outside a frame since. The seed is a correctness
-- fix, not a per-frame tax.
test("backbuffer: an unchanged page is not re-seeded", 1, vram.seeds)
-- Nesting: only the outermost pair blits.
bp.beginFrame(); bp.beginFrame()
bp.endFrame()
test("backbuffer: inner end does not present", 2, vram.presents)
bp.endFrame()
test("backbuffer: outer end presents", 3, vram.presents)
test("backbuffer: nesting restored buffer 0", 0, vram.active)
-- A draw with no frame open lands on the GLASS alone, so the page is stale
-- again and the next frame MUST re-seed. This is the whole bug: the status
-- bar's once-a-second repaint and every applyDraw level 1/2 take exactly
-- this path.
bp.set(4, 11, "TICK", 0xFFFFFF, 0x000000)
bp.beginFrame()
test("backbuffer: a draw outside a frame forces a re-seed", 2, vram.seeds)
bp.endFrame()
-- A failing bitblt must restore buffer 0 AND invalidate the shadow, so the
-- next identical draw re-emits (the screen never got the last frame).
bp.set(2, 9, "GHOST", 0xFFFFFF, 0x000000)
mockGpu.bitblt = function() error("vram fault") end
bp.beginFrame()
test("backbuffer: failed blit reports false", false, bp.endFrame())
test("backbuffer: still restored to screen", 0, vram.active)
local g0 = calls.set
bp.set(2, 9, "GHOST", 0xFFFFFF, 0x000000)
test("backbuffer: failed blit invalidated shadow", g0 + 1, calls.set)
-- bitblt does two different jobs and the test has to tell them apart:
--   SEEDING    screen -> page (src == 0), at the top of a frame
--   PRESENTING page -> screen (dst == 0), at the bottom of one
mockGpu.bitblt = function(dst, _, _, _, _, src)
  vram.blits = vram.blits + 1
  if src == 0 then vram.seeds = vram.seeds + 1
  elseif dst == 0 then vram.presents = vram.presents + 1 end
  return true
end
-- An allocation failure disables the feature for good instead of retrying.
local bad = screen.displayProxy(1)
mockGpu.allocateBuffer = function() return nil end
test("backbuffer: alloc failure -> false", false, bad.beginFrame())
test("backbuffer: no frame left open", false, bad.endFrame())
mockGpu.allocateBuffer = function(w, h)
  vram.allocated[#vram.allocated + 1] = { w, h }; return #vram.allocated
end
test("backbuffer: failure is sticky per proxy", false, bad.beginFrame())

-- Memory gate: on a tight box the shadow is OFF, so there's no dedup — every
-- write hits the GPU (we trade the saving for not eating scarce RAM).
package.loaded["computer"].freeMemory = function() return 1024 end  -- 1 KB free
local tight = screen.displayProxy(1)
local c0 = calls.set
tight.set(3, 3, "ABC", 0xFFFFFF, 0x000000)
tight.set(3, 3, "ABC", 0xFFFFFF, 0x000000)
test("tight box: shadow off, both writes draw", c0 + 2, calls.set)

-- ── invalidateAll must drop the COLOUR cache, not just the cells ──
-- The proxy keeps TWO caches over one piece of glass: shC/shF/shB
-- ("this cell already reads like that") and lastFg/lastBg ("the GPU is
-- already set to that colour"). invalidateShadow cleared only the first.
--
-- Dropping one and not the other is WORSE than dropping neither. The
-- shadow now says every cell needs repainting, so the fill is emitted --
-- but the colour cache still claims a colour the outsider moved away
-- from, so setBgCached skips its call and the whole repaint lands in the
-- OUTSIDER's colour. The proxy then records the colour it meant to use.
-- Glass and shadow now disagree permanently.
--
-- Measured on hardware: after screen.invalidateAll() a full-row fill in
-- blue put 0 of 80 cells blue. It painted black and filed it as blue.
-- Visible as the menu bar wearing the status bar's colour after a
-- repaint, and as a status bar that goes black on its own schedule.
print()
print("-- invalidateAll and the colour cache --")
do
  -- Install our OWN recorders rather than trusting the ones in the mock
  -- constructor: the fill-trim block above replaces mockGpu.fill outright
  -- and never puts it back, so a recorder written 200 lines earlier is
  -- silently dead by the time we get here. That cost a debugging round --
  -- the assertion failed for a reason that had nothing to do with the
  -- code under test, which is the worst kind of red.
  local hwBg, lastPaintBg = 0x000000, nil
  mockGpu.setForeground = function() end
  mockGpu.setBackground = function(c) hwBg = c end
  mockGpu.fill = function() calls.fill = calls.fill + 1; lastPaintBg = hwBg end
  mockGpu.set  = function() calls.set  = calls.set  + 1; lastPaintBg = hwBg end

  local p = screen.displayProxy(1)
  local A, B = 0x336699, 0x000000

  p.fill(1, 5, 80, 1, " ", 0xFFFFFF, A)
  test("the first fill really landed in A", A, lastPaintBg)

  -- Someone writes the glass and DECLARES it -- the contract every raw
  -- writer in TOS now honours (compat's term.gpu proxy, pkgpicker,
  -- the self-test's own restore).
  mockGpu.setBackground(B)
  screen.invalidateAll()
  p.fill(1, 5, 80, 1, " ", 0xFFFFFF, A)
  test("the repaint after invalidateAll is really in A", A, lastPaintBg)

  -- Same hazard through set().
  mockGpu.setBackground(B)
  screen.invalidateAll()
  p.set(1, 6, "hello", 0xFFFFFF, A)
  test("a set after invalidateAll is really in A", A, lastPaintBg)

  -- And the optimisation must SURVIVE: with nothing declared, a repeat of
  -- the same colour still skips its setBackground. A "fix" that simply
  -- stopped caching colours would pass everything above and cost a pair
  -- of bridge calls on every single draw.
  local marker = 0xABCDEF
  p.fill(1, 7, 80, 1, " ", 0xFFFFFF, A)
  hwBg = marker                      -- if setBackground is re-issued this dies
  p.fill(1, 8, 80, 1, " ", 0xFFFFFF, A)
  test("an undeclared repeat still skips the colour call", marker, lastPaintBg)
end

-- ── Two proxies, one screen ──────────────────────────────────
-- screen.displayProxy builds a FRESH proxy on every call -- private
-- shadow, private colour cache -- and the kernel calls it more than once
-- per display: once for the login process, once for the shell, once more
-- each time the task switcher opens. Those proxies all drive the same
-- glass while believing they are alone on it.
--
-- So one proxy draws, and every other proxy's shadow now describes a
-- screen that stopped existing -- and will happily elide a repaint of
-- cells it believes are already correct. Nothing announced the write,
-- because a proxy drawing normally is not a "foreign write" anyone
-- thought to declare; that machinery was built for raw gpu access.
--
-- The dedup itself must survive: a proxy repeating its OWN draw still
-- skips. What must not survive is skipping after someone else wrote.
print()
print("-- two proxies, one screen --")
do
  -- Plenty of RAM: an earlier block dropped freeMemory to 1 KB to test
  -- the memory gate, and with the shadow OFF every write emits and this
  -- whole block would pass without testing anything.
  package.loaded["computer"].freeMemory = function() return 8 * 1024 * 1024 end
  mockGpu.setForeground = function() end
  mockGpu.setBackground = function() end
  mockGpu.set = function() calls.set = calls.set + 1 end
  mockGpu.fill = function() calls.fill = calls.fill + 1 end

  local A = screen.displayProxy(1)
  local B = screen.displayProxy(1)

  A.set(1, 10, "AAAA", 0xFFFFFF, 0x000000)
  local n0 = calls.set
  A.set(1, 10, "AAAA", 0xFFFFFF, 0x000000)
  test("a proxy still dedups against its own shadow", n0, calls.set)

  -- B takes the glass and writes something else on that very row.
  B.set(1, 10, "BBBB", 0xFFFFFF, 0x000000)

  local n1 = calls.set
  A.set(1, 10, "AAAA", 0xFFFFFF, 0x000000)
  test("A repaints the row after B overwrote it", n1 + 1, calls.set)

  -- ...and B is symmetric: it must not trust its shadow after A wrote.
  local n2 = calls.set
  B.set(1, 10, "BBBB", 0xFFFFFF, 0x000000)
  test("B repaints the row after A overwrote it", n2 + 1, calls.set)

  -- Having re-synced, B is alone again and dedup returns.
  local n3 = calls.set
  B.set(1, 10, "BBBB", 0xFFFFFF, 0x000000)
  test("dedup returns once a proxy is alone again", n3, calls.set)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
