-- ╔══════════════════════════════════════════════════════╗
-- ║  OpenOS RBMK Display Satellite                       ║
-- ║  Renders the SKALA core map from the controller's    ║
-- ║  telemetry broadcast. Read-only. Never transmits.    ║
-- ╚══════════════════════════════════════════════════════╝
--
-- Deploy to: /home/rbmk-display.lua on each OpenOS display machine.
-- Config:    /etc/rbmk-display.cfg — a Lua table literal:
--              return {
--                port  = 2200,
--                pages = {                  -- one entry per SCREEN
--                  { page = "map",    param = "T" },
--                  { page = "alarms" },
--                },
--              }
--
-- Run it directly:  rbmk-display
-- Autostart it by appending that line to /home/.shrc, which OpenOS runs
-- when the shell comes up. NOT via /etc/rc.cfg: rc expects a module
-- returning start/stop functions, and this is a foreground program that
-- owns the screens for as long as it runs.
--
-- ── WHY THIS IS A SEPARATE, SELF-CONTAINED FILE ───────────────────
-- OpenOS cannot speak the TOS protocol (TOS/tos/kernel/net/protocol.lua
-- says so in its own header), and cannot require the controller's
-- libraries. So the handful of constants that MUST match — the
-- parameter table, the colour bands, the column-kind characters, the
-- port and the wire argument order — are copied below.
--
-- Copies drift. This one cannot, quietly: rbmk/test_rbmk_skala.lua
-- reads THIS FILE and pins every copied constant against the real
-- rbmk.skala / rbmk.core. That is the same guard pane-ui uses for its
-- copy of the TOS glyph table, and it exists because a display that
-- disagrees with the controller about which band is "alarm" is worse
-- than no display at all.
--
-- ── SAFETY ────────────────────────────────────────────────────────
-- This machine is UNTRUSTED by design and strictly one-way: it opens
-- the telemetry port, it never broadcasts, and there is no code path
-- from anything received to anything actuated. A frame carrying a
-- control-shaped field is REFUSED outright rather than ignored
-- field-by-field, so the unauthenticated channel cannot become reactor
-- control by accident.

local component     = require("component")
local computer      = require("computer")
local event         = require("event")
local fs            = require("filesystem")

local DEFAULT_PORT  = 2200        -- == rbmk.core.TELEMETRY_PORT
local WIRE_ARGS     = 9           -- == rbmk.core.WIRE_ARGS
local STALE_AFTER   = 5           -- seconds; == DEFAULT_LIMITS.staleAfter
local CFG_PATH      = "/etc/rbmk-display.cfg"

-- ── Copied from rbmk.skala (pinned by test) ───────────────────────
local PARAMS = {
  { key = "N", label = "POWER",     field = "flux",     unit = "",
    full = 10000, limit = "fluxScram", step = 4 },
  { key = "T", label = "CORE TEMP", field = "temp",     unit = "C",
    full = 1000,  limit = "tempScram", step = 1 },
  { key = "X", label = "STEAM",     field = "steam",    unit = "%",
    full = 100,   step = 0.01 },
  { key = "K", label = "ROD DEPTH", field = "rodDepth", unit = "%",
    full = 100,   step = 0.01 },
  { key = "G", label = "COOLANT",   field = "water",    unit = "%",
    full = 100,   limit = "waterMin", invert = true, step = 0.01 },
}
local BANDS = {
  { 0.00, 0x0080FF, "cold"   },
  { 0.40, 0x00FF00, "normal" },
  { 0.70, 0xFFFF00, "high"   },
  { 0.85, 0xFF8000, "warn"   },
  { 1.00, 0xFF0000, "alarm"  },
}
local COLOR_MISSING = 0x666666
local KIND_ABSENT   = "."
-- Only the reverse map is needed here (character -> name), and only for
-- the status line, so the full KINDS table is not duplicated.
local KIND_NAME = {
  ["_"] = "blank", F = "fuel", C = "control", M = "moderator",
  R = "reflector", A = "absorber", W = "coolant", B = "boiler",
  O = "outgasser", D = "breeder", S = "storage", H = "heatex",
  K = "cooler", ["?"] = "unknown",
}
local LIMITS = { tempScram = 1000, fluxScram = 10000, waterMin = 10 }

local function param(key)
  if type(key) ~= "string" then return nil end
  key = key:upper()
  for _, p in ipairs(PARAMS) do if p.key == key then return p end end
end

local function fractionOf(value, p)
  if type(value) ~= "number" or value ~= value or not p then return nil end
  local top = p.full
  if p.limit and LIMITS[p.limit] then top = LIMITS[p.limit] end
  if p.invert then
    local healthy = p.full or 100
    if not top or top >= healthy then top = healthy * 0.1 end
    if value >= healthy then return 0 end
    if value <= top then return 1 end
    return (healthy - value) / (healthy - top)
  end
  if not top or top <= 0 then return nil end
  local f = value / top
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return f
end

local function bandOf(value, p)
  local f = fractionOf(value, p)
  if f == nil then return COLOR_MISSING, "missing" end
  local col, name = BANDS[1][2], BANDS[1][3]
  for _, b in ipairs(BANDS) do if f >= b[1] then col, name = b[2], b[3] end end
  return col, name
end

-- Bounds are asymmetric: a minus sign costs a column, so the widest
-- printable integer is 9999 up and -999 down. Pinned against the
-- controller's own cellText by test_rbmk_skala.lua.
local function cellText(v)
  if type(v) ~= "number" or v ~= v then return "----" end
  if v > -999.5 and v < 9999.5 then return string.format("%4d", math.floor(v + 0.5))
  elseif v > -99500 and v < 999500 then return string.format("%3.0fk", v / 1000)
  elseif v >= 999500 and v < 999500000 then return string.format("%3.0fM", v / 1000000) end
  return v < 0 and "-BIG" or "+BIG"
end

-- ── Wire decode (copied from rbmk.core; pinned by test) ───────────
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function fromB36(s)
  local n = 0
  for i = 1, #s do
    local c = B36:find(s:sub(i, i), 1, true)
    if not c then return nil end
    n = n * 36 + (c - 1)
  end
  return n
end

local FORBIDDEN = { "cmd", "command", "setRod", "rod", "scram", "exec" }
local SCALARS = { temp = true, flux = true, rodDepth = true,
                  steam = true, water = true, fuel = true }

--- Decode the 9 modem arguments. Returns a frame or nil.
--- Strict about shape, because this is the only place network data
--- enters this program and there is no authentication behind it.
local function decodeWire(...)
  local a = table.pack(...)
  if a.n < WIRE_ARGS or a[1] ~= "RBMK" then return nil end
  local v = tonumber(a[2])
  if v ~= 1 and v ~= 2 then return nil end
  local f = { v = v, name = tostring(a[3]):sub(1, 32),
              seq = tonumber(a[4]), uptime = tonumber(a[5]) or 0,
              level = tostring(a[6]) }
  if type(f.seq) ~= "number" then return nil end
  if type(a[7]) == "string" then
    for k, val in a[7]:gmatch("([%a]+)=([%-%d%.eE+]+)") do
      local n = tonumber(val)
      if n and SCALARS[k] then f[k] = n end
    end
  end
  if type(a[8]) == "string" and #a[8] > 0 then f.cols = a[8] end
  if type(a[9]) == "string" and #a[9] > 0 then
    f.why = {}
    for r in a[9]:gmatch("[^|]+") do
      if #f.why < 8 then f.why[#f.why + 1] = r:sub(1, 120) end
    end
  end
  --! A telemetry frame has no business carrying a control field. One
  --! that does is refused whole -- not sanitised -- so there is never a
  --! partially-trusted frame in play.
  for _, bad in ipairs(FORBIDDEN) do if f[bad] ~= nil then return nil end end
  return f
end

local function unpackColumns(s)
  if type(s) ~= "string" then return nil end
  local parts = {}
  for seg in (s .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = seg end
  if parts[1] ~= "2" or type(parts[2]) ~= "string" then return nil end
  local gw, gh = parts[2]:match("^(%d+),(%d+)$")
  gw, gh = tonumber(gw), tonumber(gh)
  if not (gw and gh) or gw < 1 or gh < 1 or gw > 64 or gh > 64 then return nil end
  local kinds = parts[3] or ""
  if #kinds ~= gw * gh then return nil end
  local cols, order = {}, {}
  for y = 1, gh do
    for x = 1, gw do
      local ch = kinds:sub((y - 1) * gw + x, (y - 1) * gw + x)
      if ch ~= KIND_ABSENT then
        local c = { x = x, y = y, kind = KIND_NAME[ch] }
        cols[c.x .. "," .. c.y] = c
        order[#order + 1] = c
      end
    end
  end
  for i = 4, #parts do
    local key, body = parts[i]:sub(1, 1), parts[i]:sub(2)
    local p = param(key)
    if p and #body == #order * 3 then
      for j, c in ipairs(order) do
        local t = body:sub((j - 1) * 3 + 1, j * 3)
        if t ~= "---" then
          local n = fromB36(t)
          if n then c[p.field] = n * (p.step or 1) end
        end
      end
    end
  end
  return cols, { w = gw, h = gh }
end

-- ── Config ────────────────────────────────────────────────────────
local function loadCfg()
  local cfg = {}
  if fs.exists(CFG_PATH) then
    local h = io.open(CFG_PATH, "r")
    if h then
      local src = h:read("*a"); h:close()
      -- Text-only load in an EMPTY environment: this is configuration,
      -- not a script.
      local chunk = src and load(src, "=" .. CFG_PATH, "t", {})
      if chunk then
        local ok, res = pcall(chunk)
        if ok and type(res) == "table" then cfg = res end
      end
    end
  end
  return cfg
end

-- ── Screens ───────────────────────────────────────────────────────
-- Pair every GPU with a screen. When there are MORE SCREENS THAN GPUs
-- the spares are still driven: a GPU is re-bound to each of its screens
-- in turn and that screen is redrawn. At one frame per second that is
-- imperceptible, and it is the difference between a display wall
-- costing one graphics card and costing four.
local function seats()
  local gpus, screens = {}, {}
  for addr in component.list("gpu") do gpus[#gpus + 1] = addr end
  for addr in component.list("screen") do screens[#screens + 1] = addr end
  --! Sorted so a seat keeps its identity across reboots. component.list
  --! returns in hash order, so without this the pages shuffle between
  --! screens every restart -- the same bug TOS's screen.lua fixes for
  --! the same reason.
  table.sort(gpus); table.sort(screens)
  local out = {}
  for i, scr in ipairs(screens) do
    local gpu = gpus[((i - 1) % math.max(1, #gpus)) + 1]
    if gpu then
      out[#out + 1] = { gpu = component.proxy(gpu), screen = scr, index = i,
                        shared = (#screens > #gpus) }
    end
  end
  return out, #gpus, #screens
end

local DEFAULT_ROTATION = {
  { page = "map",    param = "T" },
  { page = "panel",  param = "T" },
  { page = "alarms", param = "T" },
  { page = "trend",  param = "T" },
  { page = "map",    param = "N" },
  { page = "trend",  param = "N" },
}
local PAGE_LABEL = { map = "CORE MAP", panel = "PARAMS",
                     alarms = "ALARMS", trend = "TREND" }

local function planFor(n, cfg)
  local out = {}
  local want = (type(cfg.pages) == "table") and cfg.pages or {}
  for i = 1, n do
    local rot = DEFAULT_ROTATION[((i - 1) % #DEFAULT_ROTATION) + 1]
    local w = (type(want[i]) == "table") and want[i] or {}
    local page = PAGE_LABEL[w.page] and w.page or rot.page
    local p = param(w.param) and w.param:upper() or rot.param
    out[i] = { page = page, param = p, pinned = (w.pinned == true) }
  end
  return out
end

-- ── Drawing ───────────────────────────────────────────────────────
local LEVEL_COLOR = { ok = 0x00FF00, warn = 0xFFAA00,
                      scram = 0xFF0000, unknown = 0x888888 }

local function drawSeat(gpu, W, H, st, pane)
  local p = param(pane.param) or PARAMS[1]
  gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, W, H, " ")

  -- Header
  local lvl = (st.level or "unknown"):upper()
  local col = LEVEL_COLOR[st.level] or 0x888888
  if st.stale then lvl, col = "STALE", 0xFF00FF end
  gpu.setForeground(0x00AAFF)
  gpu.set(2, 1, ((st.name or "rbmk"):upper() .. "  INFORMATION OUTPUT"):sub(1, W - 12))
  gpu.setBackground(col); gpu.setForeground(0x000000)
  gpu.set(math.max(1, W - #lvl - 1), 1, " " .. lvl .. " ")
  gpu.setBackground(0x000000); gpu.setForeground(0xAAAAAA)
  gpu.set(2, 2, string.format("%s  %s %s   seq %s",
    PAGE_LABEL[pane.page] or pane.page, p.key, p.label, tostring(st.seq or 0)))

  local top = 4
  if pane.page == "alarms" or st.stale or st.level == "scram" then
    -- The alarm page, and the override: a wall showing a tidy trend
    -- during a scram reads as normal, which is worse than blank.
    local banner = st.stale and "TELEMETRY STALE" or lvl
    local bx = math.max(2, math.floor((W - #banner - 4) / 2))
    gpu.setBackground(col); gpu.setForeground(0x000000)
    gpu.fill(bx, top, #banner + 4, 3, " ")
    gpu.set(bx + 2, top + 1, banner)
    gpu.setBackground(0x000000)
    local y = top + 4
    gpu.setForeground(col)
    if st.why and #st.why > 0 then
      for _, r in ipairs(st.why) do
        if y >= H - 1 then break end
        gpu.set(3, y, ("* " .. r):sub(1, W - 4)); y = y + 1
      end
    else
      gpu.setForeground(0xAAAAAA)
      gpu.set(3, y, st.stale and "No frames are arriving from the controller."
        or "No active warnings.")
    end
    return
  end

  if pane.page == "map" and st.cols and st.grid then
    local gw, gh = st.grid.w, st.grid.h
    local cellW = 5
    local rulerW = #tostring(gh)
    while rulerW + 1 + gw * cellW > W and cellW > 2 do cellW = cellW - 1 end
    local numeric = (cellW >= 5)
    local mapX = rulerW + 2
    gpu.setForeground(0xAAAAAA)
    for x = 1, gw do
      if numeric then gpu.set(mapX + (x - 1) * cellW, top - 1, string.format("%4d", x))
      elseif x % 5 == 0 or x == 1 then gpu.set(mapX + (x - 1) * cellW, top - 1, tostring(x)) end
    end
    for y = 1, gh do
      local py = top + y - 1
      if py > H - 2 then break end
      gpu.setForeground(0xAAAAAA)
      gpu.set(1, py, string.format("%" .. rulerW .. "d", y))
      for x = 1, gw do
        local c = st.cols[x .. "," .. y]
        local px = mapX + (x - 1) * cellW
        if c then
          local cc = bandOf(c[p.field], p)
          gpu.setForeground(cc)
          gpu.set(px, py, numeric and cellText(c[p.field])
            or string.rep("\226\150\136", math.min(cellW, 4)))
        end
      end
    end
    gpu.setForeground(0xFFFFFF)
    return
  end

  -- panel / trend / map-with-no-columns all fall back to the
  -- reactor-wide readings, which every console can report.
  local y = top
  for _, q in ipairs(PARAMS) do
    local v = st[q.field]
    local cc = bandOf(v, q)
    gpu.setForeground(0xFFFFFF)
    gpu.set(3, y, string.format("%s  %-10s", q.key, q.label))
    gpu.setForeground(cc)
    gpu.set(19, y, type(v) == "number" and
      (string.format("%.1f", v) .. " " .. q.unit) or "----")
    y = y + 1
  end
  if pane.page == "map" then
    gpu.setForeground(0xAAAAAA)
    gpu.set(3, y + 1, "(no per-channel core map in this telemetry --")
    gpu.set(3, y + 2, " the console has no column accessor bound)")
  end
end

-- ── Main ──────────────────────────────────────────────────────────
local function main()
  local cfg = loadCfg()
  local port = tonumber(cfg.port) or DEFAULT_PORT
  local staleAfter = tonumber(cfg.staleAfter) or STALE_AFTER

  local modems = {}
  for addr in component.list("modem") do
    local m = component.proxy(addr)
    m.open(port); modems[#modems + 1] = m
  end
  if #modems == 0 then
    io.stderr:write("rbmk-display: no modem; nothing to listen with\n")
    return 1
  end

  local st = { level = "unknown", stale = true, name = "(no signal)",
               why = { "listening on port " .. port .. " -- no frames yet" } }
  local lastAt = nil

  local sats, nGpu, nScr = seats()
  if #sats == 0 then
    io.stderr:write("rbmk-display: no screen\n")
    return 1
  end
  local panes = planFor(#sats, cfg)
  print(string.format("rbmk-display: port %d, %d screen(s) on %d GPU(s)%s",
    port, nScr, nGpu, (nScr > nGpu) and " (time-sliced)" or ""))

  local function onMessage(_, _, _, p, _, ...)
    if p ~= port then return end
    local f = decodeWire(...)
    if not f then return end
    st = { name = f.name, level = f.level, why = f.why, seq = f.seq,
           temp = f.temp, flux = f.flux, steam = f.steam,
           water = f.water, rodDepth = f.rodDepth, fuel = f.fuel }
    if f.cols then st.cols, st.grid = unpackColumns(f.cols) end
    lastAt = computer.uptime()
  end
  event.listen("modem_message", onMessage)

  local running = true
  local function onInterrupt() running = false end
  event.listen("interrupted", onInterrupt)

  while running do
    st.stale = (lastAt == nil) or ((computer.uptime() - lastAt) > staleAfter)
    if st.stale and lastAt then
      st.why = { string.format("no frame for %.0fs", computer.uptime() - lastAt) }
    end
    for i, s in ipairs(sats) do
      --! Rebinding is what lets one GPU serve several screens. `false`
      --! keeps the current resolution: passing the default would reset
      --! the screen on every frame, which flickers and costs a call.
      if s.shared then pcall(s.gpu.bind, s.screen, false) end
      local ok, W, H = pcall(s.gpu.getResolution)
      if ok and W then
        pcall(drawSeat, s.gpu, W, H, st, panes[i])
      end
    end
    os.sleep(1)
  end

  event.ignore("modem_message", onMessage)
  event.ignore("interrupted", onInterrupt)
  for _, m in ipairs(modems) do pcall(m.close, port) end
  return 0
end

main()
