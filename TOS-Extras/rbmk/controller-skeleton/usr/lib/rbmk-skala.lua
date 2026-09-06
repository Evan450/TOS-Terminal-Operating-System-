-- ╔══════════════════════════════════════════════════════════════╗
-- ║  rbmk-skala — the SKALA information panel (TOS renderer)     ║
-- ║                                                              ║
-- ║  Draws the core map, the parameter rail, the alarm list and  ║
-- ║  the trend strip. All the arithmetic lives in rbmk.skala and ║
-- ║  rbmk.wall; this file positions and colours it, reads keys,  ║
-- ║  and owns the multi-screen loop.                             ║
-- ║                                                              ║
-- ║  ── TWO SOURCES, ONE PANEL ─────────────────────────────────  ║
-- ║  localSource() reads the console directly — that is the      ║
-- ║  machine running rbmk-controld. netSource() listens to the   ║
-- ║  telemetry broadcast — that is any other TOS box being used  ║
-- ║  as a display. The panel cannot tell them apart, so both are ║
-- ║  the same picture and there is only one renderer to keep     ║
-- ║  correct.                                                    ║
-- ║                                                              ║
-- ║  ── STILL READ-ONLY ────────────────────────────────────────  ║
-- ║  Plan.md §Safety rule 1. The keys here choose what is        ║
-- ║  DISPLAYED. There is no key that moves a rod, and the one    ║
-- ║  write this package performs (SCRAM) stays in `rbmk scram`   ║
-- ║  and the controller's own poll loop — deliberately not on a  ║
-- ║  panel that an operator leans on the keyboard in front of.   ║
-- ║                                                              ║
-- ║  ── WHY --wall IS OPT-IN ───────────────────────────────────  ║
-- ║  TOS is multi-seat. Painting every attached display by       ║
-- ║  default would take over screens that other logged-in        ║
-- ║  operators are working at. So the default is the seat you    ║
-- ║  invoked it from, and taking the whole wall is something you ║
-- ║  ask for out loud.                                           ║
-- ╚══════════════════════════════════════════════════════════════╝

local core = require("rbmk.core")
local skala = require("rbmk.skala")
local wall = require("rbmk.wall")

local M = {}

local function firstRequire(...)
  for i = 1, select("#", ...) do
    local ok, mod = pcall(require, (select(i, ...)))
    if ok and mod then return mod end
  end
end
local component = firstRequire("component")
local computer  = firstRequire("computer")
local event     = firstRequire("kernel.event", "event")
local screenMod = firstRequire("kernel.screen")

-- ============================================================
-- Sources
-- ============================================================
-- A source answers one question: what is the reactor doing right now?
-- `poll(now)` returns a state table, or nil if nothing has changed
-- since the last call (so a wall of four screens does not re-read a
-- console four times a second).
--
--   { name, level, why = {..}, snap = {..}, cols = {..}, grid = {..},
--     limits = {..}, seq, at, stale }

--- Read the console directly. Used on the controller machine itself.
function M.localSource(cfg)
  local cmd = require("rbmk-cmd")
  cfg = cfg or cmd.loadCfg()
  local limits = core.mergeLimits(cfg.limits)
  local grid   = core.mergeGrid(cfg.grid)
  local profile = cmd.activeProfile(cfg)
  local src = { kind = "local", limits = limits, grid = grid,
                name = cfg.name or "rbmk" }

  local proxy, binding
  local function attach()
    local cands = cmd.candidates(profile)
    if #cands == 0 then return false, "no console found -- run `rbmk survey`" end
    local target = cands[1]
    if cfg.address then
      for _, c in ipairs(cands) do
        if tostring(c.address):sub(1, #cfg.address) == cfg.address then target = c end
      end
    end
    binding = core.bind(profile, cmd.methodsOf(target.address))
    local ok, px = pcall(component.proxy, target.address)
    if not ok or not px then return false, "cannot open the console proxy" end
    proxy = px
    return true
  end

  local seq, lastGood = 0, nil
  function src.poll(now)
    if not proxy then
      local ok, why = attach()
      if not ok then
        --! A console that is not there yet is reported as a MISSING
        --! reading, which evaluate() already treats as a scram
        --! condition. The panel must never render "ok" because it
        --! failed to look.
        return { name = src.name, level = "scram", why = { why },
                 snap = {}, cols = {}, grid = grid, limits = limits,
                 seq = seq, at = now, stale = true }
      end
    end
    seq = seq + 1
    local snap = cmd.read(proxy, binding)
    local age
    if snap.temp ~= nil then lastGood, age = now, 0
    else age = lastGood and (now - lastGood) or (limits.staleAfter + 1) end
    local level, why = core.evaluate(snap, limits, age)
    return {
      name = src.name, level = level, why = why, snap = snap,
      cols = cmd.readColumns(proxy, binding, grid), grid = grid,
      limits = limits, seq = seq, at = now,
      stale = (age > (limits.staleAfter or 5)),
      binding = binding,
    }
  end
  return src
end

--- Listen to the telemetry broadcast. Used on a TOS box that is only a
--- display. Opens the port; never sends.
function M.netSource(cfg)
  cfg = cfg or {}
  local limits = core.mergeLimits(cfg.limits)
  local port = tonumber(cfg.telemetryPort) or core.TELEMETRY_PORT
  local src = { kind = "net", limits = limits, port = port }

  local last, lastAt, handler
  local modems = {}
  for addr in (component and component.list and component.list("modem")
               or function() return nil end) do
    local ok, m = pcall(component.proxy, addr)
    if ok and m and m.open then pcall(m.open, port); modems[#modems + 1] = m end
  end
  src.modems = #modems

  if event and event.on then
    handler = event.on("modem_message", function(_, _, _, p, _, ...)
      if p ~= port then return end
      local f = core.decodeWire(...)
      if not f then return end
      last = f
      lastAt = computer and computer.uptime() or 0
    end, "rbmk.skala")
  end

  function src.close()
    if handler and event and event.off then pcall(event.off, "modem_message", handler) end
    for _, m in ipairs(modems) do pcall(m.close, port) end
  end

  function src.poll(now)
    local stale = core.frameStale(last and last.seq, lastAt, now, limits.staleAfter)
    if not last then
      return { name = "(no signal)", level = "unknown",
               why = { #modems == 0 and "no modem on this machine"
                       or ("listening on port " .. port .. " -- no frames yet") },
               snap = {}, cols = {}, grid = core.mergeGrid(cfg.grid),
               limits = limits, seq = 0, at = now, stale = true }
    end
    local cols, grid = {}, core.mergeGrid(cfg.grid)
    if last.cols then
      local c, g = core.unpackColumns(last.cols, skala.PARAMS)
      if c then cols, grid = c, core.mergeGrid(g) end
    end
    return {
      name = last.name, level = last.level, why = last.why or {},
      snap = { temp = last.temp, flux = last.flux, steam = last.steam,
               water = last.water, rodDepth = last.rodDepth, fuel = last.fuel },
      cols = cols, grid = grid, limits = limits,
      seq = last.seq, at = lastAt, stale = stale,
    }
  end
  return src
end

-- ============================================================
-- Drawing
-- ============================================================
local LEVEL_COLOR = {
  ok = 0x00FF00, warn = 0xFFAA00, scram = 0xFF0000, unknown = 0x888888,
}

local function theme(D)
  local ok, t = pcall(D.getTheme)
  if ok and type(t) == "table" then return t end
  return { bg = 0x000000, fg = 0xFFFFFF, dim = 0xAAAAAA,
           title = 0x00AAFF, error = 0xFF0000, warning = 0xFFAA00 }
end

local function put(D, x, y, s, fg, bg)
  if x < 1 or y < 1 then return end
  pcall(D.set, x, y, s, fg, bg)
end

--- Header: who this is, what state it is in, and which parameter the
--- map is showing. The parameter belongs here and not only on the rail
--- because a narrow screen has no rail (skala.layout drops it first).
local function drawHeader(D, T, L, st, view, srcKind)
  local W = L.W
  put(D, 1, 1, string.rep(" ", W), T.fg, T.bg)
  local title = string.format(" %s  INFORMATION OUTPUT ", (st.name or "rbmk"):upper())
  put(D, 1, 1, title, T.title, T.bg)

  local lvl = (st.level or "unknown"):upper()
  local col = LEVEL_COLOR[st.level] or T.dim
  if st.stale then lvl, col = "STALE", 0xFF00FF end
  local chip = " " .. lvl .. " "
  put(D, math.max(1, W - #chip + 1), 1, chip, 0x000000, col)

  local p = view.param
  local sub = string.format(" %s  %s%s   seq %d   %s",
    wall.page(view.page) and wall.page(view.page).label or view.page,
    p and (p.key .. " ") or "", p and p.label or "",
    st.seq or 0, srcKind == "net" and "REMOTE" or "LOCAL")
  put(D, 1, 2, string.rep(" ", W), T.dim, T.bg)
  put(D, 1, 2, sub:sub(1, W), T.dim, T.bg)
end

--- The core map: coordinate rulers plus one cell per channel.
local function drawMap(D, T, L, st, view)
  local grid = st.grid
  local p = view.param
  local ix = core.columnIndex(st.cols)

  -- Column ruler. At full cell width every column is numbered; when
  -- cells are narrower only every fifth fits, which is still enough to
  -- count from.
  put(D, 1, L.rulerY, string.rep(" ", L.W), T.dim, T.bg)
  for x = 1, L.gridW do
    local px = L.mapX + (x - 1) * L.cellW
    if L.cellW >= 5 then
      put(D, px, L.rulerY, string.format("%4d", x), T.dim, T.bg)
    elseif x % 5 == 0 or x == 1 then
      put(D, px, L.rulerY, tostring(x), T.dim, T.bg)
    end
  end

  for y = 1, L.gridH do
    local py = L.mapY + (y - 1)
    put(D, 1, py, string.format("%" .. L.rulerW .. "d", y), T.dim, T.bg)
    for x = 1, L.gridW do
      local px = L.mapX + (x - 1) * L.cellW
      local cell = ix[x .. "," .. y]
      local isCh = skala.isChannel(x, y, grid)
      local text, fg, bg
      if not isCh then
        text, fg, bg = string.rep(" ", L.cellW), T.dim, T.bg
      elseif not cell then
        --! A channel the console did not report is NOT an empty
        --! position. Drawing it blank would shrink the visible core
        --! every time a reading dropped out.
        text = L.numeric and "----" or string.rep("\226\150\145", math.min(L.cellW, 4))
        fg, bg = skala.COLOR_MISSING, T.bg
      else
        local v = cell[p.field]
        local c = select(1, skala.bandOf(v, p, st.limits))
        if L.numeric then
          text, fg, bg = skala.cellText(v), c, T.bg
        else
          -- No room for digits: the cell becomes a block of its band
          -- colour, and the legend under the rail is what reads it.
          text, fg, bg = string.rep("\226\150\136", math.min(L.cellW, 4)), c, T.bg
        end
      end
      if L.numeric and #text < L.cellW then text = text .. " " end
      put(D, px, py, text, fg, bg)
      -- The inspection cursor.
      if view.cur and view.cur.x == x and view.cur.y == y and isCh then
        put(D, px, py, text:sub(1, L.cellW), 0x000000, fg)
      end
    end
  end
end

--- The rail: parameter keys, then the colour legend that makes the map
--- readable.
local function drawRail(D, T, L, st, view)
  if not L.railX then return end
  local x, w = L.railX, L.railW
  for y = L.rulerY, L.statusY - 1 do
    put(D, x - 1, y, string.rep(" ", w + 1), T.dim, T.bg)
  end
  local y = L.rulerY
  put(D, x, y, ("PARAMETER"):sub(1, w), T.title, T.bg); y = y + 2
  for _, r in ipairs(skala.railRows(L, view.param and view.param.key)) do
    local fg, bg = T.fg, T.bg
    if r.selected then fg, bg = 0x000000, T.title end
    put(D, x, y, (" " .. r.text .. string.rep(" ", w)):sub(1, w), fg, bg)
    y = y + 1
  end
  y = y + 1
  if y + #skala.BANDS + 2 < L.statusY then
    put(D, x, y, ("SCALE"):sub(1, w), T.title, T.bg); y = y + 1
    for _, b in ipairs(skala.legend(view.param, st.limits)) do
      local label = b.name
      if b.at then label = string.format("%-7s%s", b.name, skala.cellText(b.at)) end
      put(D, x, y, "\226\150\136 ", b.color, T.bg)
      put(D, x + 2, y, label:sub(1, w - 2), T.dim, T.bg)
      y = y + 1
    end
  end
end

--- Reactor-wide scalars, the limits behind them, and the binding.
local function drawPanel(D, T, L, st, view)
  local y = L.rulerY
  local x = 3
  put(D, x, y, "REACTOR PARAMETERS", T.title, T.bg); y = y + 2
  for _, r in ipairs(skala.readout(st.snap, nil, view.param, st.limits)) do
    local p = skala.param(r.key)
    put(D, x, y, string.format("  %s  %-10s", r.key, p and p.label or ""), T.fg, T.bg)
    put(D, x + 16, y, r.text:sub(3), r.color, T.bg)
    y = y + 1
  end
  y = y + 1
  put(D, x, y, "LIMITS", T.title, T.bg); y = y + 1
  local keys = {}
  for k in pairs(st.limits or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    if y >= L.statusY - 1 then break end
    put(D, x, y, string.format("  %-12s %s", k, tostring(st.limits[k])), T.dim, T.bg)
    y = y + 1
  end
end

--- What is wrong, in the largest type the screen allows.
local function drawAlarms(D, T, L, st, view)
  local y = L.rulerY + 1
  local col = LEVEL_COLOR[st.level] or T.dim
  if st.stale then col = 0xFF00FF end
  local banner = st.stale and "TELEMETRY STALE" or (st.level or "unknown"):upper()
  local bx = math.max(2, math.floor((L.W - #banner - 4) / 2))
  put(D, bx, y, " " .. string.rep(" ", #banner + 2) .. " ", 0x000000, col)
  put(D, bx, y + 1, "  " .. banner .. "  ", 0x000000, col)
  put(D, bx, y + 2, " " .. string.rep(" ", #banner + 2) .. " ", 0x000000, col)
  y = y + 4
  local why = st.why or {}
  if #why == 0 then
    put(D, 4, y, st.stale and "No frames are arriving from the controller."
      or "No active warnings.", T.dim, T.bg)
  else
    for _, r in ipairs(why) do
      if y >= L.statusY - 1 then break end
      put(D, 4, y, ("* " .. r):sub(1, L.W - 5), col, T.bg)
      y = y + 1
    end
  end
  if st.level == "scram" then
    y = y + 1
    put(D, 4, y, "The SCRAM latch does not clear itself -- restart the service.",
      T.dim, T.bg)
  end
end

--- Recent history of the selected parameter.
local function drawTrend(D, T, L, st, view)
  local y = L.rulerY
  local p = view.param
  local series = view.series and view.series[p.key] or {}
  local lo, hi, n = wall.range(series)
  put(D, 3, y, string.format("TREND  %s %s", p.key, p.label), T.title, T.bg)
  put(D, 3, y + 1, n > 0
    and string.format("%d samples   low %s   high %s",
        n, skala.cellText(lo), skala.cellText(hi))
    or "collecting...", T.dim, T.bg)
  local top = y + 3
  local h = math.max(3, L.statusY - top - 1)
  local w = math.max(10, L.W - 8)
  local rows = wall.chart(series, w, h, lo, hi)
  for i, row in ipairs(rows) do
    local frac = 1 - ((i - 1) / math.max(1, h - 1))
    local col = select(1, skala.bandOf(
      lo and hi and (lo + frac * (hi - lo)) or nil, p, st.limits))
    put(D, 4, top + i - 1, row, col, T.bg)
  end
  if lo and hi then
    put(D, 4 + w + 1, top, skala.cellText(hi), T.dim, T.bg)
    put(D, 4 + w + 1, top + h - 1, skala.cellText(lo), T.dim, T.bg)
  end
end

--- The bottom two rows: the selected channel's readings, then keys.
local function drawStatus(D, T, L, st, view, showKeys)
  local y = L.statusY
  put(D, 1, y, string.rep("\226\148\128", L.W), T.dim, T.bg)
  local line = ""
  if view.page == "map" and view.cur then
    local c = core.columnIndex(st.cols)[view.cur.x .. "," .. view.cur.y]
    line = string.format(" ch %d,%d %s ", view.cur.x, view.cur.y,
      c and (c.kind or "?") or "(not reported)")
    local parts = {}
    for _, r in ipairs(skala.readout(st.snap, c, view.param, st.limits)) do
      parts[#parts + 1] = r.text
    end
    line = line .. table.concat(parts, "  ")
  else
    local parts = {}
    for _, r in ipairs(skala.readout(st.snap, nil, view.param, st.limits)) do
      parts[#parts + 1] = r.text
    end
    line = " " .. table.concat(parts, "  ")
  end
  put(D, 1, y + 1, string.rep(" ", L.W), T.fg, T.bg)
  put(D, 1, y + 1, line:sub(1, L.W), T.fg, T.bg)
  if showKeys and y + 2 <= L.H then
    put(D, 1, y + 2, string.rep(" ", L.W), T.dim, T.bg)
    put(D, 1, y + 2,
      (" N T X K G parameter   TAB page   arrows channel   Q quit"):sub(1, L.W),
      T.dim, T.bg)
  end
end

--- Draw one pane. Public so the wall loop and a single seat share it.
function M.drawPane(D, st, view, opts)
  opts = opts or {}
  local T = theme(D)
  local W, H = D.getSize()
  local L = skala.layout(W, H, st.grid)
  if not L.ok then
    --! The fallback matters as much as the panel. A screen too small
    --! for a core map still has to say what is going on, and say what
    --! size would fix it -- skala.layout computes that number so this
    --! branch can print it instead of "too small".
    pcall(D.clear, T.bg)
    put(D, 1, 1, ((st.name or "rbmk"):upper() .. "  " ..
      (st.stale and "STALE" or (st.level or "?"):upper())):sub(1, W),
      LEVEL_COLOR[st.level] or T.fg, T.bg)
    local y = 3
    for _, r in ipairs(skala.readout(st.snap, nil, view.param, st.limits)) do
      if y > H - 2 then break end
      put(D, 2, y, r.text, r.color, T.bg); y = y + 1
    end
    put(D, 1, H, (L.why or "screen too small"):sub(1, W), T.dim, T.bg)
    return L
  end

  if D.beginFrame then pcall(D.beginFrame) end
  pcall(D.clear, T.bg)
  drawHeader(D, T, L, st, view, opts.srcKind)
  if view.page == "map" then
    drawMap(D, T, L, st, view)
    drawRail(D, T, L, st, view)
  elseif view.page == "panel" then
    drawPanel(D, T, L, st, view)
  elseif view.page == "alarms" then
    drawAlarms(D, T, L, st, view)
  elseif view.page == "trend" then
    drawTrend(D, T, L, st, view)
  end
  drawStatus(D, T, L, st, view, opts.interactive)
  if D.endFrame then pcall(D.endFrame) end
  return L
end

-- ============================================================
-- The panel loop
-- ============================================================
local KEY = { UP = 200, DOWN = 208, LEFT = 203, RIGHT = 205, TAB = 15, ESC = 1 }

--- Run the panel.
--- opts = { display = D, event = E, cfg = <rbmk.cfg>, mode = "auto"
---          | "local" | "net", wallMode = bool, o = <line printer> }
function M.run(opts)
  opts = opts or {}
  local D = opts.display or opts.D
  local E = opts.event or event
  local o = opts.o or function() end
  if not D then o("No display available."); return end

  local cmd = require("rbmk-cmd")
  local cfg = opts.cfg or cmd.loadCfg()

  -- Which source? "auto" prefers the console when this machine has one,
  -- because a controller machine showing its own reading beats the same
  -- machine listening to its own broadcast one poll later.
  local mode = opts.mode or "auto"
  local src
  if mode == "net" then
    src = M.netSource(cfg)
  elseif mode == "local" then
    src = M.localSource(cfg)
  else
    local cands = cmd.candidates(cmd.activeProfile(cfg))
    src = (#cands > 0) and M.localSource(cfg) or M.netSource(cfg)
  end

  -- Panes. Default is THIS seat only; --wall takes every display (see
  -- the header note on multi-seat).
  local panes, displays = {}, {}
  if opts.wallMode and screenMod and screenMod.list and screenMod.displayProxy then
    local seats = screenMod.list()
    panes = wall.plan(#seats, cfg.wall, function(k) return skala.param(k) ~= nil end)
    for i, s in ipairs(seats) do
      --! Built ONCE and held. screen.displayProxy makes a FRESH proxy
      --! per call, each with its own dirty-cell shadow; rebuilding one
      --! every frame would throw that shadow away and re-emit every
      --! cell, which on a wall is the difference between a redraw and
      --! a stall.
      displays[i] = screenMod.displayProxy(s.index) or D
    end
  end
  if #panes == 0 then
    panes = wall.plan(1, cfg.wall, function(k) return skala.param(k) ~= nil end)
    displays = { D }
  end

  -- The seat taking input is the one the operator invoked from: seat 1
  -- of the plan when we own the wall, and the only seat otherwise.
  local view = {
    page = panes[1].page, param = skala.param(panes[1].param) or skala.PARAMS[1],
    cur = { x = 1, y = 1 }, series = {},
  }

  local function pull(timeout)
    if coroutine.isyieldable and coroutine.isyieldable() then
      return coroutine.yield()
    end
    if E and E.pull then return E.pull(timeout) end
    return computer.pullSignal(timeout)
  end

  local interval = math.max(0.25, tonumber(cfg.pollInterval) or 1)
  local running, nextPoll, st = true, 0, nil
  local ok, err = pcall(function()
    while running do
      local now = computer.uptime()
      if now >= nextPoll or not st then
        st = src.poll(now) or st
        nextPoll = now + interval
        for _, p in ipairs(skala.PARAMS) do
          view.series[p.key] = wall.push(view.series[p.key],
            st.snap and st.snap[p.field], 240)
        end
      end

      -- The override is applied HERE, once, and every pane obeys it --
      -- including the interactive one. An operator studying a trend
      -- during a scram is the exact case wall.effective() exists for.
      local eff = wall.effective(panes, st.level, st.stale)
      for i, pane in ipairs(eff) do
        local paneView = {
          page = (i == 1) and (pane.overridden and pane.page or view.page) or pane.page,
          param = (i == 1) and view.param or (skala.param(pane.param) or skala.PARAMS[1]),
          cur = (i == 1) and view.cur or nil,
          series = view.series,
        }
        M.drawPane(displays[i] or D, st, paneView,
          { srcKind = src.kind, interactive = (i == 1) })
      end

      local remaining = math.max(0.05, nextPoll - computer.uptime())
      local ev, _, ch, code = pull(remaining)
      if ev == "key_down" then
        local c = (type(ch) == "number" and ch > 0) and string.char(ch):upper() or ""
        if c == "Q" or code == KEY.ESC then running = false
        elseif skala.param(c) then view.param = skala.param(c)
        elseif code == KEY.TAB then
          for i, pg in ipairs(wall.PAGES) do
            if pg.id == view.page then
              view.page = wall.PAGES[(i % #wall.PAGES) + 1].id; break
            end
          end
        elseif c >= "1" and c <= "4" and wall.PAGES[tonumber(c)] then
          view.page = wall.PAGES[tonumber(c)].id
        elseif code == KEY.LEFT then view.cur.x = math.max(1, view.cur.x - 1)
        elseif code == KEY.RIGHT then view.cur.x = math.min(st.grid.w, view.cur.x + 1)
        elseif code == KEY.UP then view.cur.y = math.max(1, view.cur.y - 1)
        elseif code == KEY.DOWN then view.cur.y = math.min(st.grid.h, view.cur.y + 1)
        end
        nextPoll = 0   -- redraw immediately on any key
      elseif ev == "touch" then
        --! A touch signal is (name, screenAddr, x, y, button, player), so
        --! the two slots `pull` handed back as char/code ARE x and y here.
        local tx, ty = ch, code
        local dw, dh = D.getSize()
        local L = skala.layout(dw, dh, st.grid)
        local cx, cy = skala.cellAt(L, tx, ty, st.grid)
        if cx then view.cur.x, view.cur.y = cx, cy; nextPoll = 0 end
      elseif ev == "interrupted" then
        running = false
      end
    end
  end)

  --! Whatever happened, give the screens back. A panel that errors and
  --! leaves a stale reactor map on four displays is worse than one that
  --! never drew: the numbers stay there looking current.
  if src.close then pcall(src.close) end
  for _, d in ipairs(displays) do
    local T = theme(d)
    pcall(d.clear, T.bg)
  end
  if not ok then o("Panel error: " .. tostring(err)) end
end

return M
