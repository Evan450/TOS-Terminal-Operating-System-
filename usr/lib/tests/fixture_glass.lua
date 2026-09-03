-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test fixture: a screen you can read back                     ║
-- ║                                                                ║
-- ║  NOT a test — the runner globs test_*.lua, so this is only     ║
-- ║  ever loaded by the tests that ask for it.                     ║
-- ║                                                                ║
-- ║  Two pieces, and both exist because of bugs that got through:  ║
-- ║                                                                ║
-- ║  1. A GPU THAT STORES PIXELS, including video-RAM pages. The   ║
-- ║     existing backbuffer mocks count calls, and a call-count    ║
-- ║     mock passes happily while the code blits the WRONG pixels  ║
-- ║     — which is how the status bar went black for a fifth time  ║
-- ║     with the suite green. allocateBuffer hands back a BLANK    ║
-- ║     page, exactly as OpenComputers does, because assuming      ║
-- ║     otherwise was the bug.                                     ║
-- ║                                                                ║
-- ║  2. A `unicode` MODULE. kernel.ustr probes for OC's unicode    ║
-- ║     and falls back to BYTE math when it is absent, which is    ║
-- ║     every off-box run. So off-box, ustr.width("F2 ▸ tiles")    ║
-- ║     answers 12 instead of 10, every column calculation that    ║
-- ║     touches a box-drawing glyph is over by the continuation    ║
-- ║     bytes, and a screen test reports rows short that are fine  ║
-- ║     in-world. It cuts both ways: a REAL column-math bug is     ║
-- ║     equally invisible. Install this before requiring anything  ║
-- ║     that draws.                                                ║
-- ╚══════════════════════════════════════════════════════════════╝

local F = {}

-- ============================================================
-- unicode
-- ============================================================
local function codepoints(s)
  local cps, i, n = {}, 1, #s
  while i <= n do
    local c = s:byte(i)
    local len, cp
    if c < 0x80 then len, cp = 1, c
    elseif c < 0xE0 then len, cp = 2, c - 0xC0
    elseif c < 0xF0 then len, cp = 3, c - 0xE0
    else len, cp = 4, c - 0xF0 end
    for k = 1, len - 1 do
      local cc = s:byte(i + k)
      if not cc then break end
      cp = cp * 64 + (cc - 0x80)
    end
    cps[#cps + 1] = { cp = cp, s = s:sub(i, i + len - 1) }
    i = i + len
  end
  return cps
end

-- East Asian Wide / Fullwidth: the only things OC renders two cells wide.
-- Box drawing, block elements and arrows are all single-cell, which is what
-- the byte fallback gets wrong.
local function isWide(cp)
  return (cp >= 0x1100 and cp <= 0x115F)
      or (cp >= 0x2E80 and cp <= 0xA4CF and cp ~= 0x303F)
      or (cp >= 0xAC00 and cp <= 0xD7A3)
      or (cp >= 0xF900 and cp <= 0xFAFF)
      or (cp >= 0xFE30 and cp <= 0xFE6F)
      or (cp >= 0xFF00 and cp <= 0xFF60)
      or (cp >= 0xFFE0 and cp <= 0xFFE6)
      or (cp >= 0x20000 and cp <= 0x3FFFD)
end

F.unicode = {}
function F.unicode.len(s) return #codepoints(tostring(s or "")) end
function F.unicode.wlen(s)
  local w = 0
  for _, c in ipairs(codepoints(tostring(s or ""))) do w = w + (isWide(c.cp) and 2 or 1) end
  return w
end
function F.unicode.charWidth(ch)
  local c = codepoints(tostring(ch or ""))[1]
  return (c and isWide(c.cp)) and 2 or 1
end
function F.unicode.isWide(ch) return F.unicode.charWidth(ch) == 2 end
function F.unicode.sub(s, i, j)
  local cps = codepoints(tostring(s or "")); local n = #cps
  i = i or 1; j = j or -1
  if i < 0 then i = n + i + 1 end
  if j < 0 then j = n + j + 1 end
  if i < 1 then i = 1 end
  if j > n then j = n end
  local out = {}
  for k = i, j do out[#out + 1] = cps[k].s end
  return table.concat(out)
end
-- OC semantics: the result is LESS than `count` columns wide.
function F.unicode.wtrunc(s, count)
  local out, used = {}, 0
  for _, c in ipairs(codepoints(tostring(s or ""))) do
    local cw = isWide(c.cp) and 2 or 1
    if used + cw >= count then break end
    out[#out + 1] = c.s; used = used + cw
  end
  return table.concat(out)
end
function F.unicode.upper(s) return tostring(s or ""):upper() end
function F.unicode.lower(s) return tostring(s or ""):lower() end
function F.unicode.char(...)
  local out = {}
  for _, cp in ipairs({ ... }) do
    if cp < 0x80 then out[#out + 1] = string.char(cp)
    elseif cp < 0x800 then
      out[#out + 1] = string.char(0xC0 + cp // 64, 0x80 + cp % 64)
    else
      out[#out + 1] = string.char(0xE0 + cp // 4096, 0x80 + (cp // 64) % 64, 0x80 + cp % 64)
    end
  end
  return table.concat(out)
end

-- ============================================================
-- The glass
-- ============================================================
-- Returns a handle: .gpu (give this to component.proxy), plus readers that
-- look at page 0, which is what the operator sees.
--
-- Unpainted cells hold a SENTINEL rather than a blank, so "this redraw never
-- touched that cell" is distinguishable from "this redraw painted a space".
function F.newGlass(w, h)
  local G = { W = w, H = h, SENT_CH = "\1", SENT_FG = 0xFF00FF, SENT_BG = 0xFF00FF,
              clock = 1234 }
  local pages, nextBuf, active = {}, 0, 0
  local curFg, curBg = 0xFFFFFF, 0x000000

  local function newPage(sentinel)
    local c = {}
    for k = 1, G.W * G.H do
      c[k] = sentinel and { G.SENT_CH, G.SENT_FG, G.SENT_BG } or { " ", 0xFFFFFF, 0x000000 }
    end
    return c
  end
  pages[0] = newPage(true)
  G.pages = pages

  G.gpu = {
    address       = "gpu-glass",
    getScreen     = function() return "screen-glass" end,
    bind          = function() return true end,
    getResolution = function() return G.W, G.H end,
    maxResolution = function() return 160, 50 end,
    setResolution = function(nw, nh)
      G.W, G.H = nw, nh; pages[0] = newPage(true)
      for k in pairs(pages) do if k ~= 0 then pages[k] = nil end end
      nextBuf, active = 0, 0
      return true
    end,
    getDepth      = function() return 8 end,
    maxDepth      = function() return 8 end,
    setForeground = function(c) curFg = c; return true end,
    setBackground = function(c) curBg = c; return true end,
    getForeground = function() return curFg end,
    getBackground = function() return curBg end,
    -- Reads the ACTIVE buffer, not page 0. OpenComputers applies every
    -- gpu operation -- set, get, fill, copy -- to whichever buffer is
    -- active, and a fixture whose `get` always answered from the glass
    -- made "read the off-screen page back" untestable while looking
    -- correct. G.cell() is the one that always means the glass.
    get = function(x, y)
      local p = pages[active]; if not p then return " ", 0xFFFFFF, 0x000000 end
      local c = p[(y - 1) * G.W + x]
      if not c then return " ", 0xFFFFFF, 0x000000 end
      return c[1], c[2], c[3]
    end,
    -- Real overlap semantics: read the whole source rect before writing any
    -- of it, or a downward copy smears its first row over the rest.
    copy = function(x, y, cw, chh, tx, ty)
      local p = pages[active]; if not p then return false end
      local buf = {}
      for yy = 0, chh - 1 do
        for xx = 0, cw - 1 do
          local sx, sy = x + xx, y + yy
          if sx >= 1 and sx <= G.W and sy >= 1 and sy <= G.H then
            buf[yy * cw + xx] = p[(sy - 1) * G.W + sx]
          end
        end
      end
      for yy = 0, chh - 1 do
        for xx = 0, cw - 1 do
          local dx, dy = x + xx + tx, y + yy + ty
          local c = buf[yy * cw + xx]
          if c and dx >= 1 and dx <= G.W and dy >= 1 and dy <= G.H then
            p[(dy - 1) * G.W + dx] = { c[1], c[2], c[3] }
          end
        end
      end
      return true
    end,
    set = function(x, y, text)
      local p = pages[active]; if not p then return false end
      local i = 0
      for ch in tostring(text):gmatch("[\1-\127\194-\244][\128-\191]*") do
        i = i + 1
        local cx = x + i - 1
        if cx >= 1 and cx <= G.W and y >= 1 and y <= G.H then
          p[(y - 1) * G.W + cx] = { ch, curFg, curBg }
        end
      end
      return true
    end,
    fill = function(x, y, fw, fh, ch)
      local p = pages[active]; if not p then return false end
      for yy = y, y + fh - 1 do
        for xx = x, x + fw - 1 do
          if xx >= 1 and xx <= G.W and yy >= 1 and yy <= G.H then
            p[(yy - 1) * G.W + xx] = { ch, curFg, curBg }
          end
        end
      end
      return true
    end,
    -- A freshly allocated page is BLANK. This is the detail the old mocks
    -- did not model and the bug depended on.
    allocateBuffer  = function() nextBuf = nextBuf + 1; pages[nextBuf] = newPage(false); return nextBuf end,
    freeBuffer      = function(i) pages[i] = nil; return true end,
    setActiveBuffer = function(i) active = i; return true end,
    getActiveBuffer = function() return active end,
    bitblt = function(dst, dx, dy, bw, bh, src, sx, sy)
      -- A blit that REPORTS SUCCESS AND COPIES NOTHING. Not hypothetical:
      -- a screendump from a real machine caught the off-screen page holding
      -- a correct status bar, the shadow agreeing, and the glass still
      -- black -- which only happens if the page->screen blit answered yes
      -- and did nothing. Modelled so TOS can be held to detecting it.
      if G.blitLies and dst == 0 then return true end
      local s, d = pages[src], pages[dst]
      if not s or not d then return false end
      for yy = 0, bh - 1 do
        for xx = 0, bw - 1 do
          local c = s[(sy + yy - 1) * G.W + (sx + xx)]
          if c then d[(dy + yy - 1) * G.W + (dx + xx)] = { c[1], c[2], c[3] } end
        end
      end
      return true
    end,
  }

  function G.cell(x, y) return pages[0][(y - 1) * G.W + x] end
  function G.bgAt(x, y) return G.cell(x, y)[3] end
  function G.rowText(y)
    local t = {}
    for x = 1, G.W do t[x] = G.cell(x, y)[1] end
    return table.concat(t)
  end
  function G.snapshot()
    local t = {}
    for k = 1, G.W * G.H do
      local c = pages[0][k]; t[k] = c[1] .. "|" .. c[2] .. "|" .. c[3]
    end
    return t
  end
  --- Runs of cells this redraw never touched, as { y, from, to }.
  function G.unpainted()
    local runs = {}
    for y = 1, G.H do
      local r = nil
      for x = 1, G.W do
        local c = G.cell(x, y)
        if c[1] == G.SENT_CH and c[3] == G.SENT_BG then
          r = r or { y = y, from = x, to = x }; r.to = x
        elseif r then runs[#runs + 1] = r; r = nil end
      end
      if r then runs[#runs + 1] = r end
    end
    return runs
  end
  --- Runs where two snapshots disagree.
  function G.diffRuns(a, b)
    local runs = {}
    for y = 1, G.H do
      local r = nil
      for x = 1, G.W do
        local k = (y - 1) * G.W + x
        if a[k] ~= b[k] then r = r or { y = y, from = x, to = x }; r.to = x
        elseif r then runs[#runs + 1] = r; r = nil end
      end
      if r then runs[#runs + 1] = r end
    end
    return runs
  end
  function G.describe(runs)
    local n, parts = 0, {}
    for _, r in ipairs(runs) do
      n = n + (r.to - r.from + 1)
      parts[#parts + 1] = string.format("row %d cols %d..%d", r.y, r.from, r.to)
    end
    return n, table.concat(parts, "; ")
  end

  --- component/computer stand-ins wired to this glass.
  function G.install()
    package.loaded["unicode"] = F.unicode
    package.loaded["component"] = {
      list = function(ctype)
        local given = false
        return function()
          if given then return nil end
          given = true
          if ctype == "gpu"    then return "gpu-glass", "gpu" end
          if ctype == "screen" then return "screen-glass", "screen" end
          return nil
        end
      end,
      proxy  = function() return G.gpu end,
      invoke = function() return nil end,
      isAvailable = function() return false end,
      type   = function(a) return a == "gpu-glass" and "gpu" or "screen" end,
    }
    package.loaded["computer"] = {
      -- Advanceable, because anything rate-limited by the clock (the
      -- shadow's self-audit) cannot be tested against a frozen one.
      -- Starts where it always did so existing tests see no change.
      uptime = function() return G.clock end,
      freeMemory = function() return 4 * 1024 * 1024 end,
      totalMemory = function() return 8 * 1024 * 1024 end,
      pullSignal = function() return nil end,
      beep = function() end,
      energy = function() return 100 end,
      maxEnergy = function() return 100 end,
      getDeviceInfo = function() return {} end,
    }
    return G
  end

  return G
end

return F
