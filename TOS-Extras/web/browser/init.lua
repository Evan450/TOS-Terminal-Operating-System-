-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Module: web — a text-mode browser                        ║
-- ║                                                              ║
-- ║  browser-spec-draft.md's build order, steps 1-2: the pure     ║
-- ║  renderer (web.render) is done; this is the local browser --  ║
-- ║  one machine, its own internet card, no proxy. "Useful on     ║
-- ║  its own" per the spec, and shippable alone: no fetch proxy,  ║
-- ║  no cache, no cross-machine trust decision lives here, so      ║
-- ║  there is no security surface beyond the `internet` capability ║
-- ║  grant itself (§9's own reasoning for building these two steps  ║
-- ║  first and reviewing them lightly).                              ║
-- ║                                                              ║
-- ║  §9 steps 3-5 (webproxyd, the cache, the cluster back end) are   ║
-- ║  NOT here -- §10's open questions (proxy discovery, cache trust   ║
-- ║  defaults, the canonical URL key, whether the proxy strips        ║
-- ║  anything) need answering first, and they are trust decisions,    ║
-- ║  not code.                                                         ║
-- ║                                                              ║
-- ║  web.render is pure and unit-tested off-box (test_web.lua, §6.3).  ║
-- ║  This file is fetching, drawing and keys.                           ║
-- ╚══════════════════════════════════════════════════════════════╝

local component = require("component")
local computer  = require("computer")
local render    = require("web.render")

-- `internet` is only present in require()'s table when the package
-- manifest declared the capability and the operator accepted it at
-- install time (tos/kernel/sandbox.lua) -- absent, not an error, so a
-- missing grant reads as "no internet" rather than crashing the program
-- before it can say so.
local okI, internet = pcall(require, "internet")
if not okI then internet = nil end

-- Per-call cap (never global -- kernel.internet's own convention, and
-- settled rather than re-argued per the spec's "Starting point" note):
-- a page is routinely bigger than kernel.internet's 64 KB default, and
-- 256 KB matches the ceiling the (not-yet-built) fetch proxy's own
-- config in §3.1 uses, so a page that fits through a future proxy also
-- fits here.
local MAX_PAGE = 256 * 1024

-- ── Screen ────────────────────────────────────────────────────────────
-- Same kit stock/calc/write use, duplicated rather than shared so
-- installing `web` pulls in nothing but this package.
local function screen(o, minW, minH)
  local gpuAddr = component.list and component.list("gpu")()
  if not gpuAddr then o("No GPU found.", 0xFF0000); return nil end
  local okG, gpu = pcall(component.proxy, gpuAddr)
  if not okG or not gpu then o("Cannot open the GPU.", 0xFF0000); return nil end
  local W, H = gpu.getResolution()
  if not W or not H then o("Cannot detect screen size.", 0xFF0000); return nil end
  if W < minW or H < minH then
    o(string.format("Screen too small: need %dx%d, have %dx%d.", minW, minH, W, H), 0xFF6600)
    return nil
  end
  local okD, depth = pcall(gpu.getDepth)
  local tier = (okD and type(depth) == "number")
    and (depth <= 1 and 1 or (depth <= 4 and 2 or 3)) or 1
  local T = (tier == 1) and {
    fg = 0xFFFFFF, dim = 0xFFFFFF, border = 0xFFFFFF, title = 0xFFFFFF,
    hi = 0xFFFFFF, warn = 0xFFFFFF, bg = 0x000000,
  } or {
    fg = 0xFFFFFF, dim = 0xAAAAAA, bg = 0x000000,
    border = tier == 2 and 0x55FFFF or 0x00FFFF,
    title  = tier == 2 and 0xFFFF55 or 0xFFFF00,
    hi     = tier == 2 and 0x55FF55 or 0x00FF00,
    warn   = tier == 2 and 0xFF5555 or 0xFF4040,
  }
  local Dv = { W = W, H = H, tier = tier, T = T, gpu = gpu }
  function Dv.set(x, y, s, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.set, x, y, s)
  end
  function Dv.fill(x, y, w, h, ch, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.fill, x, y, w, h, ch or " ")
  end
  function Dv.clear() Dv.fill(1, 1, W, H, " ", T.fg, T.bg) end
  return Dv
end

local function pad(s, w)
  s = tostring(s or "")
  if #s > w then return s:sub(1, math.max(1, w - 1)) .. "~" end
  return s .. string.rep(" ", math.max(0, w - #s))
end

-- ── Keys ──────────────────────────────────────────────────────────────
local K = {
  ESC = 1, ENTER = 28, BACK = 14,
  UP = 200, DOWN = 208, LEFT = 203, RIGHT = 205,
  PGUP = 201, PGDN = 209, HOME = 199, END = 207, F10 = 68,
}
local CTRL_Q = 17

local KEYS do local okK, m = pcall(require, "shell.keys"); KEYS = okK and m or nil end
local function isQuit(ch, code)
  if KEYS and KEYS.is then return KEYS.is("quit", ch, code) end
  return code == K.F10 or ch == CTRL_Q or code == K.ESC
end

local function pullKey(timeout)
  local e = { computer.pullSignal(timeout) }
  if e[1] == "key_down" then return e[3], e[4] end
  if e[1] == "interrupted" then return CTRL_Q, nil end
  return nil, nil
end

-- ── Fetching ──────────────────────────────────────────────────────────

--- Fetch `url` and return (body) or (nil, message). The message is
-- written to read well on the status line, not as a bare error code --
-- §7's table is the model, cut down to what applies with no proxy: the
-- two real causes here are "no card at all" and whatever the far host
-- or kernel.internet itself said.
local function fetchPage(url)
  if not internet then
    return nil, "this package was not granted the internet capability"
  end
  local okS, st = pcall(internet.status)
  if okS and st and not (st.present and st.http and st.enabled) then
    return nil, "no internet card: " .. tostring(st.reason or "unavailable")
  end
  local body, err = internet.get(url, { maxBytes = MAX_PAGE })
  if not body then
    return nil, tostring(err or "fetch failed")
  end
  return body
end

-- ── Normalizing what the operator typed ─────────────────────────────
-- A bare "example.com" is overwhelmingly what someone means; kernel.
-- internet only speaks http/https (parseUrl refuses anything else), so
-- default the scheme rather than bounce back a parse error for the
-- common case.
local function normalizeUrl(u)
  u = tostring(u or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if u == "" then return u end
  if not u:match("^%a+://") then u = "http://" .. u end
  return u
end

-- ── The program ───────────────────────────────────────────────────────

local function run(initialUrl, o)
  local D = screen(o, 40, 10)
  if not D then return end
  local T = D.T

  local state = {
    url = nil, lines = {}, links = {}, status = nil, statusColor = T.fg,
    scroll = 0, hscroll = 0, history = {},
  }

  local contentTop, contentBot = 2, D.H - 1

  local function load(url, pushHistory)
    url = normalizeUrl(url)
    if url == "" then return end
    state.status = "Loading " .. url .. " ..."
    state.statusColor = T.dim
    -- Paint the status line immediately -- a fetch can take real
    -- seconds (kernel.internet's own timeout is 15s), and a program
    -- that looks frozen is worse than one that is merely slow.
    D.fill(1, D.H, D.W, 1, " ", T.fg, T.bg)
    D.set(2, D.H, pad(state.status, D.W - 2), state.statusColor, T.bg)
    local body, err = fetchPage(url)
    if not body then
      state.lines, state.links = {}, {}
      state.status = "Failed: " .. tostring(err)
      state.statusColor = T.warn
      return
    end
    if pushHistory and state.url then
      state.history[#state.history + 1] = state.url
    end
    state.url = url
    local out = render.render(body, D.W)
    state.lines, state.links = out.lines, out.links
    state.scroll, state.hscroll = 0, 0
    state.status = url
    state.statusColor = T.dim
  end

  local function draw()
    D.fill(1, 1, D.W, 1, " ", T.menubar_fg or T.bg, T.title)
    D.set(2, 1, pad("web -- " .. (state.url or "(no page loaded)"), D.W - 2),
      T.menubar_fg or T.bg, T.title)

    D.fill(1, contentTop, D.W, contentBot - contentTop + 1, " ", T.fg, T.bg)
    local rows = contentBot - contentTop + 1
    local maxScroll = math.max(0, #state.lines - rows)
    if state.scroll > maxScroll then state.scroll = maxScroll end
    if state.scroll < 0 then state.scroll = 0 end
    for i = 0, rows - 1 do
      local l = state.lines[state.scroll + i + 1]
      if l then
        local visible = l:sub(state.hscroll + 1, state.hscroll + D.W)
        D.set(1, contentTop + i, visible, T.fg, T.bg)
      end
    end

    D.fill(1, D.H, D.W, 1, " ", T.fg, T.bg)
    D.set(2, D.H, pad(state.status or "", D.W - 2), state.statusColor, T.bg)
  end

  local function promptLine(label)
    D.fill(1, D.H, D.W, 1, " ", T.fg, T.bg)
    D.set(2, D.H, label, T.hi, T.bg)
    local buf = ""
    local startX = 2 + #label
    while true do
      D.fill(startX, D.H, D.W - startX, 1, " ", T.fg, T.bg)
      D.set(startX, D.H, buf, T.fg, T.bg)
      local ch, code = pullKey(nil)
      if code == K.ENTER then return buf
      elseif isQuit(ch, code) then return nil
      elseif code == K.BACK then
        if #buf > 0 then buf = buf:sub(1, -2) end
      elseif ch and ch >= 32 and ch < 127 then
        if startX + #buf < D.W then buf = buf .. string.char(ch) end
      end
    end
  end

  if initialUrl and initialUrl ~= "" then
    load(initialUrl, false)
  else
    state.status = "o = open a URL   |   F10/^Q = quit"
  end

  D.clear()
  draw()
  local running = true
  while running do
    local ch, code = pullKey(nil)
    if isQuit(ch, code) then
      running = false
    elseif code == K.UP then
      state.scroll = math.max(0, state.scroll - 1); draw()
    elseif code == K.DOWN then
      state.scroll = state.scroll + 1; draw()
    elseif code == K.PGUP then
      state.scroll = math.max(0, state.scroll - (contentBot - contentTop)); draw()
    elseif code == K.PGDN then
      state.scroll = state.scroll + (contentBot - contentTop); draw()
    elseif code == K.HOME then
      state.scroll = 0; draw()
    elseif code == K["END"] then
      state.scroll = math.max(0, #state.lines - (contentBot - contentTop + 1)); draw()
    elseif code == K.LEFT then
      state.hscroll = math.max(0, state.hscroll - 8); draw()
    elseif code == K.RIGHT then
      state.hscroll = state.hscroll + 8; draw()
    elseif ch == 111 or ch == 79 then                       -- o / O: open URL
      local u = promptLine("Open: ")
      if u and u ~= "" then load(u, true) end
      D.clear(); draw()
    elseif ch == 98 or ch == 66 then                        -- b / B: back
      local prev = table.remove(state.history)
      if prev then load(prev, false) end
      D.clear(); draw()
    elseif ch and ch >= 48 and ch <= 57 then                -- 0-9: follow link N
      local digits = string.char(ch)
      while true do
        D.fill(1, D.H, D.W, 1, " ", T.fg, T.bg)
        D.set(2, D.H, "Go to link: " .. digits, T.hi, T.bg)
        local ch2, code2 = pullKey(nil)
        if code2 == K.ENTER then break
        elseif isQuit(ch2, code2) then digits = nil; break
        elseif ch2 and ch2 >= 48 and ch2 <= 57 then digits = digits .. string.char(ch2)
        elseif code2 == K.BACK then
          digits = digits:sub(1, -2)
          if digits == "" then break end
        end
      end
      local n = digits and tonumber(digits)
      local target = n and state.links[n]
      if target then
        load(target.url, true)
      elseif n then
        state.status = "No such link: [" .. n .. "]"
        state.statusColor = T.warn
      end
      D.clear(); draw()
    end
  end

  D.clear()
end

-- ══════════════════════════════════════════════════════════════════════
-- Command entry
-- ══════════════════════════════════════════════════════════════════════
local function webCmd(args, o)
  args = args or {}
  local url = args[1]
  if not url or url == "help" then
    o("web -- a text-mode browser", 0xFFFF55)
    o("  web <url>        Fetch and read a page", 0xFFFFFF)
    o("", 0xFFFFFF)
    o("Needs this machine's own internet card -- no fetch proxy yet", 0xAAAAAA)
    o("(that is a separate, not-yet-built piece; see the README).", 0xAAAAAA)
    o("Inside: o open a url, digits+Enter follow a numbered link,", 0xAAAAAA)
    o("b back, arrows scroll (left/right for a wide <pre> block),", 0xAAAAAA)
    o("F10/^Q quit.", 0xAAAAAA)
    return
  end
  run(url, o)
end

return { commands = { web = webCmd } }
