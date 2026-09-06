-- ╔══════════════════════════════════════════════════════════════╗
-- ║  rbmk.core — driver binding + SAFETY RULES (pure, no I/O)    ║
-- ║                                                              ║
-- ║  Two jobs, both deliberately hardware-free so they can be    ║
-- ║  unit-tested off-box (test_rbmk.lua):                        ║
-- ║                                                              ║
-- ║   1. DRIVER BINDING. HBM's Nuclear Tech Mod exposes its RBMK ║
-- ║      console through an OC component whose type name and     ║
-- ║      method surface we do NOT know for certain — Plan.md's   ║
-- ║      open question #1, answerable only by an in-game survey. ║
-- ║      So method names are DATA (a "profile"), not literals    ║
-- ║      baked into the controller. `rbmk survey` prints what a  ║
-- ║      real component actually offers; bind() then reports     ║
-- ║      exactly which profile entries resolved and which are    ║
-- ║      missing, so a wrong guess is a legible diagnostic       ║
-- ║      instead of a nil-index crash next to a reactor.         ║
-- ║                                                              ║
-- ║   2. SAFETY RULES. Given a telemetry snapshot and limits,    ║
-- ║      decide: ok / warn / SCRAM. This is the safety-critical  ║
-- ║      half of the add-on and it is pure arithmetic — it is    ║
-- ║      tested exhaustively here rather than in-world.          ║
-- ║                                                              ║
-- ║  DESIGN RULE (Plan.md §Safety): the controller is            ║
-- ║  authoritative, displays are strictly read-only, and NOTHING ║
-- ║  that arrives over the network may move a rod. v1 is         ║
-- ║  READ-ONLY + SCRAM (Plan.md open question #4): the only      ║
-- ║  write this code will ever emit is the shutdown.             ║
-- ╚══════════════════════════════════════════════════════════════╝

local C = {}

C.VERSION = "0.2.0"

-- Telemetry wire version. v1 was scalars only; v2 adds the packed core
-- map and the reason strings behind the level. Both are accepted, so a
-- satellite that has not been updated still renders — it simply shows
-- no core map, which is exactly what v1 could always tell it.
C.FRAME_V = 2
C.FRAME_VERSIONS = { [1] = true, [2] = true }

-- How many reason strings a frame may carry. An unbounded list is an
-- unbounded packet, and the packet has a hard 8 KB ceiling the core map
-- is already spending most of.
C.MAX_REASONS = 8

-- ============================================================
-- Driver profiles
-- ============================================================
-- A profile maps the LOGICAL readings the controller needs onto whatever
-- the mod actually calls them. Every field is optional: a console that
-- can't report flux still gets temperature protection.
--
-- The shipped profiles are CANDIDATES, not confirmed API. Run
-- `rbmk survey` against a real console and correct /etc/rbmk.cfg —
-- that survey is the whole point of this indirection.

C.PROFILES = {
  -- Best-guess names, ordered most→least likely. The controller tries
  -- each candidate in turn and uses the first that exists on the proxy.
  ["hbm-generic"] = {
    componentTypes = { "rbmk_console", "rbmk_control", "ntm_rbmk_console" },
    temp     = { "getTemp", "getTemperature", "getCoreTemp" },
    flux     = { "getFlux", "getNeutronFlux" },
    rodDepth = { "getRodDepth", "getControlRodLevel", "getRods" },
    steam    = { "getSteam", "getSteamProduction" },
    water    = { "getWater", "getWaterLevel" },
    fuel     = { "getFuel", "getFuelLevel", "getCoreFuel" },
    -- The only write v1 performs.
    scram    = { "setAZ5", "scram", "az5", "shutdown" },
    -- Some builds expose everything as one table instead of getters.
    bulk     = { "getInfo", "getStats", "getData" },
    -- Per-channel enumeration for the SKALA core map. Display-only —
    -- see bind(): a console without this is still fully supervisable.
    columns  = { "getColumnData", "getColumns", "getFluxData", "getRodData" },
  },
}

-- Default core footprint. HBM's RBMK tops out at a 15x15 grid of
-- columns; `shape = "circle"` in /etc/rbmk.cfg inscribes the round
-- RBMK-1000 core instead, for operators who want the historical
-- outline rather than the mod's square one.
C.DEFAULT_GRID = { w = 15, h = 15, shape = "square" }

--- Merge an operator grid over the default, refusing anything that
--- would make a map that cannot be drawn. Same posture as mergeLimits:
--- a typo falls back to the DEFAULT, never to something degenerate.
function C.mergeGrid(cfg)
  local g = { w = C.DEFAULT_GRID.w, h = C.DEFAULT_GRID.h,
              shape = C.DEFAULT_GRID.shape }
  if type(cfg) ~= "table" then return g end
  local w, h = tonumber(cfg.w), tonumber(cfg.h)
  if w and w >= 1 and w <= 64 and math.floor(w) == w then g.w = w end
  if h and h >= 1 and h <= 64 and math.floor(h) == h then g.h = h end
  if cfg.shape == "circle" or cfg.shape == "square" then g.shape = cfg.shape end
  if type(cfg.mask) == "table" then g.mask = cfg.mask end
  return g
end

--- Resolve a profile against a live proxy's method list.
--- `methods` is a set OR array of method names available on the
--- component. Returns { bound = { logical = methodName }, missing = { … },
--- bulk = methodName|nil }. Pure — no component access.
function C.bind(profile, methods)
  local have = {}
  if type(methods) == "table" then
    for k, v in pairs(methods) do
      if type(k) == "string" then have[k] = true          -- set form
      elseif type(v) == "string" then have[v] = true end  -- array form
    end
  end
  local bound, missing = {}, {}
  local LOGICAL = { "temp", "flux", "rodDepth", "steam", "water", "fuel", "scram" }
  for _, logical in ipairs(LOGICAL) do
    local candidates = profile[logical] or {}
    local found
    for _, name in ipairs(candidates) do
      if have[name] then found = name; break end
    end
    if found then bound[logical] = found else missing[#missing + 1] = logical end
  end
  local bulk
  for _, name in ipairs(profile.bulk or {}) do
    if have[name] then bulk = name; break end
  end
  --! `columns` is resolved like `bulk` and deliberately NOT part of
  --! LOGICAL: it feeds the SKALA core map, which is a display feature.
  --! A console that cannot enumerate its channels is still perfectly
  --! supervisable, so its absence must not show up in `missing` and
  --! must never make a binding unusable.
  local columns
  for _, name in ipairs(profile.columns or {}) do
    if have[name] then columns = name; break end
  end
  return { bound = bound, missing = missing, bulk = bulk, columns = columns }
end

--- Is a binding good enough to run a controller on? Temperature is the
--- floor: without it there is no protection worth the name, and we would
--- rather refuse to start than pretend to supervise a reactor.
--- SCRAM is separately required unless the operator has wired the
--- redstone AZ-5 backup (Plan.md §Safety rule 2).
function C.bindingUsable(binding, hasRedstoneScram)
  if not binding or not binding.bound then return false, "no binding" end
  if not (binding.bound.temp or binding.bulk) then
    return false, "no temperature reading — refusing to supervise blind"
  end
  if not (binding.bound.scram or hasRedstoneScram) then
    return false, "no SCRAM path (no console method and no redstone AZ-5)"
  end
  return true
end

-- ============================================================
-- Telemetry normalization
-- ============================================================

--- Normalize a raw reading table into the canonical shape the rest of
--- the add-on (and the display satellites) speak. Unknown fields are
--- dropped; numbers are coerced; nils stay nil (missing ≠ zero — a
--- missing temperature must never read as a cold reactor).
function C.normalize(raw)
  local t = {}
  local function num(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(v) end
    return nil
  end
  raw = raw or {}
  t.temp     = num(raw.temp)
  t.flux     = num(raw.flux)
  t.rodDepth = num(raw.rodDepth)
  t.steam    = num(raw.steam)
  t.water    = num(raw.water)
  t.fuel     = num(raw.fuel)
  return t
end

-- ============================================================
-- Safety rules
-- ============================================================

C.DEFAULT_LIMITS = {
  tempWarn   = 800,     -- °C — advisory
  tempScram  = 1000,    -- °C — automatic shutdown
  fluxWarn   = 8000,
  fluxScram  = 10000,
  waterMin   = 10,      -- % — starving the loop is a shutdown condition
  staleAfter = 5,       -- s without a fresh reading = lost the console
}

--- Evaluate a snapshot against limits.
--- Returns (level, reasons) where level is "ok" | "warn" | "scram" and
--- reasons is an array of human-readable strings — ALWAYS populated for
--- warn/scram so the log says WHY the reactor was shut down.
---
--- `age` is seconds since the reading was taken. A STALE reading is a
--- scram condition, not an "ok": losing the console while a reactor runs
--- is precisely when you want the rods in (Plan.md §Safety rule 3).
--- `missingTemp` likewise scrams — supervising blind is not supervising.
function C.evaluate(snap, limits, age)
  limits = limits or C.DEFAULT_LIMITS
  local reasons = {}
  local level = "ok"
  local function raise(to, why)
    reasons[#reasons + 1] = why
    if to == "scram" then level = "scram"
    elseif level ~= "scram" then level = "warn" end
  end

  if age ~= nil and limits.staleAfter and age > limits.staleAfter then
    raise("scram", string.format("telemetry stale (%.1fs > %.1fs)",
      age, limits.staleAfter))
  end

  snap = snap or {}
  if snap.temp == nil then
    raise("scram", "no temperature reading")
  else
    if limits.tempScram and snap.temp >= limits.tempScram then
      raise("scram", string.format("core %.0f >= scram limit %.0f",
        snap.temp, limits.tempScram))
    elseif limits.tempWarn and snap.temp >= limits.tempWarn then
      raise("warn", string.format("core %.0f >= warn limit %.0f",
        snap.temp, limits.tempWarn))
    end
  end

  if snap.flux ~= nil then
    if limits.fluxScram and snap.flux >= limits.fluxScram then
      raise("scram", string.format("flux %.0f >= scram limit %.0f",
        snap.flux, limits.fluxScram))
    elseif limits.fluxWarn and snap.flux >= limits.fluxWarn then
      raise("warn", string.format("flux %.0f >= warn limit %.0f",
        snap.flux, limits.fluxWarn))
    end
  end

  if snap.water ~= nil and limits.waterMin and snap.water < limits.waterMin then
    raise("scram", string.format("coolant %.0f%% < minimum %.0f%%",
      snap.water, limits.waterMin))
  end

  return level, reasons
end

--- Merge operator limits over the defaults, dropping anything that isn't
--- a positive number. A typo'd config must not silently disable a limit:
--- an unusable value falls back to the DEFAULT, never to "no limit".
function C.mergeLimits(cfg)
  local out = {}
  for k, v in pairs(C.DEFAULT_LIMITS) do out[k] = v end
  if type(cfg) ~= "table" then return out end
  for k, v in pairs(cfg) do
    if C.DEFAULT_LIMITS[k] ~= nil then
      local n = tonumber(v)
      if n and n > 0 then out[k] = n end
    end
  end
  return out
end

-- ============================================================
-- Per-channel columns (the SKALA core map's data)
-- ============================================================
-- The scalar snapshot above is what the SAFETY RULES run on. This
-- section is for the DISPLAY: a core map wants one reading per channel,
-- and an RBMK has up to 225 of them.
--
-- ── WHY THIS IS A SEPARATE, LOSSY PATH ─────────────────────────────
-- 225 channels x 5 readings as plain Lua tables serialises to roughly
-- 12 KB. protocol.MAX_SIZE is 8192. So the map is quantised into a
-- compact string, and that quantisation is EXACTLY why nothing here
-- feeds a safety decision: evaluate() runs on the controller's own raw
-- local reading, never on anything that has been through this codec.
-- The wire form is a picture; the scram is computed from the source.

-- Column kinds, HBM's RBMK vocabulary. One character each so a whole
-- core footprint costs one byte per cell.
C.KINDS = {
  blank = "_", fuel = "F", control = "C", moderator = "M",
  reflector = "R", absorber = "A", coolant = "W", boiler = "B",
  outgasser = "O", breeder = "D", storage = "S", heatex = "H",
  cooler = "K",
}
C.KIND_UNKNOWN = "?"     -- a channel exists, but the mod named it something new
C.KIND_ABSENT  = "."     -- no channel at this grid position

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local B36_MAX = 36 * 36 * 36 - 1        -- 46655

local function toB36(n)
  local s = ""
  for _ = 1, 3 do
    s = B36:sub((n % 36) + 1, (n % 36) + 1) .. s
    n = math.floor(n / 36)
  end
  return s
end

local function fromB36(s)
  local n = 0
  for i = 1, #s do
    local c = B36:find(s:sub(i, i), 1, true)
    if not c then return nil end
    n = n * 36 + (c - 1)
  end
  return n
end

--- Normalize whatever the console's column accessor returned into the
--- canonical array. Accepts either a flat array of per-column tables
--- carrying x/y, or a row-major array of arrays. Unknown fields are
--- dropped; missing stays missing.
function C.normalizeColumns(raw, grid)
  local out = {}
  if type(raw) ~= "table" then return out end
  grid = grid or {}
  local gw = grid.w or 15
  local function num(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(v) end
    return nil
  end
  local function add(t, x, y)
    if type(t) ~= "table" then return end
    local kind = t.kind or t.type or t.name
    out[#out + 1] = {
      x = num(t.x) or x, y = num(t.y) or y,
      kind = (type(kind) == "string") and kind:lower() or nil,
      temp = num(t.temp or t.heat or t.temperature),
      flux = num(t.flux or t.power or t.neutronFlux),
      steam = num(t.steam), water = num(t.water or t.coolant),
      rodDepth = num(t.rodDepth or t.depth or t.level),
    }
  end
  -- Row-major array-of-arrays.
  if type(raw[1]) == "table" and raw[1][1] ~= nil and type(raw[1][1]) == "table" then
    for y, row in ipairs(raw) do
      for x, cell in ipairs(row) do add(cell, x, y) end
    end
    return out
  end
  for i, t in ipairs(raw) do
    -- A flat list with no coordinates is still usable: index implies
    -- position, which is how a console that just dumps its columns in
    -- order will look.
    add(t, ((i - 1) % gw) + 1, math.floor((i - 1) / gw) + 1)
  end
  return out
end

--- Index a column array by "x,y" for O(1) lookup by the renderer.
function C.columnIndex(cols)
  local ix = {}
  for _, c in ipairs(cols or {}) do
    if c.x and c.y then ix[c.x .. "," .. c.y] = c end
  end
  return ix
end

--- Pack columns for the wire. `params` is the ordered parameter list
--- (rbmk.skala.PARAMS) — passed in so core stays independent of the UI
--- module, and so the two cannot disagree about field order.
---
--- Layout:  2;<w>,<h>;<kinds>;<KEY><triples>;<KEY><triples>;...
--- Values are base-36 triples of `round(value / step)`, SATURATING at
--- both ends; "---" means no reading. Saturation is a display
--- compromise and is safe only because of the note at the top of this
--- section: safety never reads this.
function C.packColumns(cols, grid, params)
  grid = grid or {}
  local gw, gh = grid.w or 15, grid.h or 15
  local ix = C.columnIndex(cols)
  local kinds, present = {}, {}
  for y = 1, gh do
    for x = 1, gw do
      local c = ix[x .. "," .. y]
      if not c then
        kinds[#kinds + 1] = C.KIND_ABSENT
      else
        kinds[#kinds + 1] = (c.kind and C.KINDS[c.kind]) or C.KIND_UNKNOWN
        present[#present + 1] = c
      end
    end
  end
  local parts = { "2", gw .. "," .. gh, table.concat(kinds) }
  for _, p in ipairs(params or {}) do
    local seg = { p.key }
    for _, c in ipairs(present) do
      local v = c[p.field]
      if type(v) ~= "number" or v ~= v then
        seg[#seg + 1] = "---"
      else
        local n = math.floor(v / (p.step or 1) + 0.5)
        if n < 0 then n = 0 elseif n > B36_MAX then n = B36_MAX end
        seg[#seg + 1] = toB36(n)
      end
    end
    parts[#parts + 1] = table.concat(seg)
  end
  return table.concat(parts, ";")
end

--- Unpack. Returns (cols, grid) or (nil, why).
--- Every length is checked before it is trusted: this parses data that
--- arrived over an unauthenticated broadcast, so a malformed frame has
--- to be a nil return and not a crash inside a display's redraw loop.
function C.unpackColumns(s, params)
  if type(s) ~= "string" then return nil, "not a string" end
  local parts = {}
  for seg in (s .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = seg end
  if parts[1] ~= "2" then return nil, "unsupported column format" end
  --! NOT `parts[2] and parts[2]:match(...)`: in a multiple assignment
  --! an `and` expression is truncated to ONE value, so the second
  --! capture silently vanishes and every frame reads as "bad grid
  --! size". Guard first, match on its own line.
  if type(parts[2]) ~= "string" then return nil, "bad grid size" end
  local gw, gh = parts[2]:match("^(%d+),(%d+)$")
  gw, gh = tonumber(gw), tonumber(gh)
  if not (gw and gh) or gw < 1 or gh < 1 or gw > 64 or gh > 64 then
    return nil, "bad grid size"
  end
  local kinds = parts[3] or ""
  if #kinds ~= gw * gh then return nil, "kind map is the wrong length" end
  local byChar = {}
  for name, ch in pairs(C.KINDS) do byChar[ch] = name end

  local cols, order = {}, {}
  for y = 1, gh do
    for x = 1, gw do
      local ch = kinds:sub((y - 1) * gw + x, (y - 1) * gw + x)
      if ch ~= C.KIND_ABSENT then
        local c = { x = x, y = y, kind = byChar[ch] }
        cols[#cols + 1] = c
        order[#order + 1] = c
      end
    end
  end

  for i = 4, #parts do
    local seg = parts[i]
    local key = seg:sub(1, 1)
    local body = seg:sub(2)
    local p
    for _, q in ipairs(params or {}) do if q.key == key then p = q end end
    if p then
      if #body ~= #order * 3 then return nil, "value run for " .. key .. " is the wrong length" end
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

-- ============================================================
-- Telemetry frames (controller -> display satellites)
-- ============================================================

--- Build the broadcast frame. Read-only data by design: displays are
--- untrusted consumers, so this carries no control surface at all.
--- `seq` + `uptime` let a display show a loud STALE banner when frames
--- stop (Plan.md §Safety rule 3, the display half of the watchdog).
--- `cols` is the packed core map from packColumns (a plain string), or
--- nil on a controller that has no per-channel accessor bound. A
--- display must render fine without it — a reactor whose console only
--- reports scalars still deserves a panel.
function C.frame(snap, level, seq, uptime, name, cols, reasons)
  --! Built here rather than passed through, so a frame can never carry
  --! more than MAX_REASONS strings however long the reason list got.
  --! An unbounded list is an unbounded packet, and the packet has a
  --! hard 8 KB ceiling that the core map is already spending.
  local why
  if type(reasons) == "table" and #reasons > 0 then
    why = {}
    for i = 1, math.min(#reasons, C.MAX_REASONS) do
      why[i] = tostring(reasons[i]):sub(1, 120)
    end
  end
  return {
    magic = "RBMK", v = C.FRAME_V,
    name = name or "rbmk",
    seq = seq or 0, uptime = uptime or 0,
    level = level or "ok",
    temp = snap and snap.temp, flux = snap and snap.flux,
    rodDepth = snap and snap.rodDepth, steam = snap and snap.steam,
    water = snap and snap.water, fuel = snap and snap.fuel,
    cols = (type(cols) == "string" and #cols > 0) and cols or nil,
    --! The reasons the level is what it is. A wall that shows ALARM
    --! without saying which limit tripped makes the operator walk to
    --! the console to find out, which is the walk the wall existed to
    --! save. Strings only, and capped — see MAX_REASONS.
    why = why,
  }
end


--- Validate an inbound frame on the display side. Returns (ok, why).
--- Rejects anything that isn't our magic/version, and — importantly —
--- ignores any field that would look like a command: a display that
--- honoured a "setRod" key in a telemetry frame would turn the
--- unauthenticated broadcast channel into reactor control.
function C.validateFrame(f)
  if type(f) ~= "table" then return false, "not a table" end
  if f.magic ~= "RBMK" then return false, "bad magic" end
  if not C.FRAME_VERSIONS[f.v] then
    return false, "unsupported version " .. tostring(f.v)
  end
  if type(f.seq) ~= "number" then return false, "no sequence" end
  --! `cols` and `why` are the only v2 additions and both are rendered,
  --! so both are type-checked here rather than trusted at the draw
  --! site. A broadcast is unauthenticated: anything that reaches a
  --! renderer has to have been shaped on the way in.
  if f.cols ~= nil and type(f.cols) ~= "string" then
    return false, "cols is not a packed string"
  end
  if f.why ~= nil then
    if type(f.why) ~= "table" then return false, "why is not a list" end
    for _, r in ipairs(f.why) do
      if type(r) ~= "string" then return false, "why holds a non-string" end
    end
  end
  for _, forbidden in ipairs({ "cmd", "command", "setRod", "rod", "scram", "exec" }) do
    if f[forbidden] ~= nil then
      return false, "frame carries a control field (" .. forbidden .. ") — refused"
    end
  end
  return true
end

-- ============================================================
-- The telemetry wire
-- ============================================================
-- Telemetry rides a RAW MODEM BROADCAST on its own port, not the TOS
-- protocol. Three reasons, and the first one is a defect this fixes:
--
--  1. kernel.net's trust gate allows `msg` only at TRUSTED
--     (net/trust.lua PERMISSIONS). Telemetry sent as a protocol MSG is
--     therefore dropped by every display that has not been elevated —
--     and displays are UNTRUSTED BY DESIGN (Plan.md §Protocol). The
--     original broadcast could not reach the audience it was written
--     for; nothing noticed because the display half did not exist yet.
--  2. OpenOS satellites cannot speak the TOS protocol at all — see
--     net/protocol.lua's own note that TOS machines only talk to TOS
--     machines. A satellite has to be able to receive this.
--  3. Sending is still one-way. Listening on a port is something the
--     DISPLAY does; the controller never opens it, so this adds no
--     inbound path to the machine that owns SCRAM (§Safety rule 1).
--
-- The frame goes out as FIXED PRIMITIVE ARGUMENTS, never as a
-- serialized table. There is nothing to deserialize, so there is no
-- parser for an unauthenticated broadcast to attack: every value
-- arrives already typed by the modem, and the two string fields are
-- scanned with gmatch + tonumber, never with load().
C.TELEMETRY_PORT = 2200   -- clear of cluster (2001-2004, 2101), rc-pilot (7777)
C.WIRE_ARGS = 9

local function encScalars(f)
  local t = {}
  for _, k in ipairs({ "temp", "flux", "rodDepth", "steam", "water", "fuel" }) do
    if type(f[k]) == "number" then
      t[#t + 1] = k .. "=" .. string.format("%.4g", f[k])
    end
  end
  return table.concat(t, ",")
end

--- Flatten a frame into the 9 modem arguments. Returns them as a list
--- so the caller can unpack it into modem.broadcast.
function C.encodeWire(f)
  return {
    "RBMK",
    f.v or C.FRAME_V,
    tostring(f.name or "rbmk"),
    tonumber(f.seq) or 0,
    tonumber(f.uptime) or 0,
    tostring(f.level or "ok"),
    encScalars(f),
    tostring(f.cols or ""),
    (type(f.why) == "table") and table.concat(f.why, "|") or "",
  }
end

--- Rebuild a frame from modem arguments. Returns nil for anything that
--- is not ours — including a short argument list, which is the shape a
--- stray broadcast on a shared port takes.
---
--- This is the ONLY entry point for network data on a display, so it is
--- strict about types rather than about content: validateFrame does the
--- content check afterwards, and both run before anything is drawn.
function C.decodeWire(...)
  local a = table.pack(...)
  if a.n < C.WIRE_ARGS then return nil, "short frame" end
  if a[1] ~= "RBMK" then return nil, "not ours" end
  local f = {
    magic = "RBMK",
    v = tonumber(a[2]),
    name = tostring(a[3]):sub(1, 32),
    seq = tonumber(a[4]),
    uptime = tonumber(a[5]) or 0,
    level = tostring(a[6]),
  }
  if type(a[7]) == "string" then
    for k, v in a[7]:gmatch("([%a]+)=([%-%d%.eE+]+)") do
      local n = tonumber(v)
      --! Only keys the frame is allowed to have. Without this filter an
      --! attacker on the port could introduce arbitrary field names
      --! into a table the renderer indexes -- which is how a read-only
      --! display grows a control surface by accident.
      if n and (k == "temp" or k == "flux" or k == "rodDepth"
             or k == "steam" or k == "water" or k == "fuel") then
        f[k] = n
      end
    end
  end
  if type(a[8]) == "string" and #a[8] > 0 then f.cols = a[8] end
  if type(a[9]) == "string" and #a[9] > 0 then
    f.why = {}
    for r in a[9]:gmatch("[^|]+") do
      if #f.why < C.MAX_REASONS then f.why[#f.why + 1] = r:sub(1, 120) end
    end
  end
  local ok, err = C.validateFrame(f)
  if not ok then return nil, err end
  return f
end

--- Is a display's newest frame stale? Pure.
function C.frameStale(lastSeq, lastAt, now, staleAfter)
  if lastSeq == nil or lastAt == nil then return true end
  return (now - lastAt) > (staleAfter or C.DEFAULT_LIMITS.staleAfter)
end

return C
