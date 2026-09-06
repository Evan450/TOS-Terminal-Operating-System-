-- ╔══════════════════════════════════════════════════════════════╗
-- ║  rbmk.wall — the display-wall model (PURE)                   ║
-- ║                                                              ║
-- ║  A control room is not one screen. This decides WHICH PAGE   ║
-- ║  each screen shows — across the several displays wired to    ║
-- ║  the TOS console AND across the OpenOS satellites watching   ║
-- ║  the same broadcast — so that every pane is a different      ║
-- ║  useful view instead of four copies of the same one.         ║
-- ║                                                              ║
-- ║  Modelled on the cluster add-on's split (see rbmk/Plan.md):  ║
-- ║  the controller is authoritative and the panes are cheap and ║
-- ║  disposable. A satellite that crashes must cost nothing.     ║
-- ║                                                              ║
-- ║  ── WHY THE CONTROLLER DOES NOT KNOW ITS OWN WALL ──────────  ║
-- ║  There is deliberately no display registration. Plan.md      ║
-- ║  §Safety rule 1 says the controller registers NO network     ║
-- ║  receive handler, and "let displays announce themselves" is  ║
-- ║  exactly such a handler — it would hand an untrusted pane a  ║
-- ║  channel into the machine that owns SCRAM, to buy a nicer    ║
-- ║  `rbmk wall` listing. So each satellite chooses its own page ║
-- ║  from its own config, and the wall plan below is what a      ║
-- ║  single machine does with the screens it can see itself.     ║
-- ║                                                              ║
-- ║  ── THE OVERRIDE IS THE SAFETY-RELEVANT PART ───────────────  ║
-- ║  See effective(). When the reactor scrams, or when frames    ║
-- ║  stop arriving, panes stop showing what they were asked to   ║
-- ║  show and start showing what is wrong. A video wall          ║
-- ║  displaying a tidy trend during a scram is worse than a      ║
-- ║  blank one, because it reads as normal.                      ║
-- ╚══════════════════════════════════════════════════════════════╝

local W = {}

W.VERSION = "0.2.0"

-- ============================================================
-- Pages
-- ============================================================
W.PAGES = {
  { id = "map",    label = "CORE MAP",  desc = "per-channel readings, one parameter" },
  { id = "panel",  label = "PARAMS",    desc = "reactor-wide scalars and limits" },
  { id = "alarms", label = "ALARMS",    desc = "active warnings and scram reasons" },
  { id = "trend",  label = "TREND",     desc = "recent history of one parameter" },
}

function W.page(id)
  if type(id) ~= "string" then return nil end
  for _, p in ipairs(W.PAGES) do if p.id == id then return p end end
  return nil
end

-- The rotation a wall falls into when nobody has said otherwise. Seat 1
-- gets the map because that is the view an operator walks up to.
W.DEFAULT_ROTATION = {
  { page = "map",    param = "T" },
  { page = "panel",  param = "T" },
  { page = "alarms", param = "T" },
  { page = "trend",  param = "T" },
  { page = "map",    param = "N" },
  { page = "trend",  param = "N" },
}

-- ============================================================
-- Planning
-- ============================================================
--- Build the seat -> pane assignment for `n` screens.
---
--- `cfg` is /etc/rbmk.cfg's optional `wall` table, keyed by seat index:
---   wall = { [2] = { page = "trend", param = "N", pinned = true } }
---
--- Anything unrecognised falls back to the rotation entry rather than
--- to a blank pane: a typo in a display config must not silently turn a
--- screen off. `pinned` exempts a seat from the alarm override — see
--- effective() for why that is an operator decision and not a default.
---
--- `validParam` is injected (rbmk.skala.param) so this file stays free
--- of any dependency: pure model, no requires.
function W.plan(n, cfg, validParam)
  local out = {}
  n = tonumber(n) or 0
  if n < 0 then n = 0 end
  cfg = (type(cfg) == "table") and cfg or {}
  for i = 1, n do
    local rot = W.DEFAULT_ROTATION[((i - 1) % #W.DEFAULT_ROTATION) + 1]
    local want = (type(cfg[i]) == "table") and cfg[i] or {}
    local page = W.page(want.page) and want.page or rot.page
    local param = want.param
    if type(param) ~= "string" or (validParam and not validParam(param)) then
      param = rot.param
    else
      param = param:upper()
    end
    out[i] = {
      seat = i, page = page, param = param,
      pinned = (want.pinned == true),
      --! Records whether the operator's setting was USED or dropped, so
      --! `rbmk wall` can say "seat 3: trend (config said 'trned')"
      --! instead of quietly showing something else than was asked for.
      configured = (type(cfg[i]) == "table") or nil,
      rejected = (type(cfg[i]) == "table"
        and ((want.page ~= nil and not W.page(want.page))
          or (want.param ~= nil and validParam and not validParam(want.param)))) or nil,
    }
  end
  return out
end

--- Apply the operational override to a plan.
---
--- Returns (panes, overridden, reason). On a SCRAM every unpinned pane
--- switches to the alarm page; on STALE telemetry every unpinned pane
--- switches too, because a wall quietly showing the last good frame
--- forever is the failure Plan.md §Safety rule 3 exists to prevent.
---
--- A "warn" level does NOT take the wall over. Warnings are advisory
--- and happen during normal operation; a wall that seized every screen
--- on every advisory would train the operators to ignore it, which is
--- the same as not having it.
---
--- `pinned` seats keep their page in every case. That is why pinning is
--- opt-in and never a default: it is the operator saying "this screen
--- is my working view and I accept that it will not shout at me".
function W.effective(panes, level, stale)
  local reason
  if stale then reason = "TELEMETRY STALE"
  elseif level == "scram" then reason = "SCRAM" end
  if not reason then return panes, false, nil end
  local out = {}
  for i, p in ipairs(panes) do
    if p.pinned then
      out[i] = p
    else
      local q = {}
      for k, v in pairs(p) do q[k] = v end
      q.page, q.overridden = "alarms", reason
      out[i] = q
    end
  end
  return out, true, reason
end

-- ============================================================
-- Trend series
-- ============================================================
--- Append a sample to a bounded ring. `nil` is a legitimate sample: it
--- records that at this instant there was NO reading, and the chart
--- draws a gap there. Collapsing that to zero would draw a cold reactor
--- during exactly the window where the console was unreachable.
function W.push(series, value, cap)
  series = series or {}
  cap = cap or 120
  series[#series + 1] = (type(value) == "number") and value or false
  while #series > cap do table.remove(series, 1) end
  return series
end

--- Range of the real samples, ignoring gaps. Returns (min, max, count).
function W.range(series)
  local lo, hi, n
  for _, v in ipairs(series or {}) do
    if type(v) == "number" then
      n = (n or 0) + 1
      if not lo or v < lo then lo = v end
      if not hi or v > hi then hi = v end
    end
  end
  return lo, hi, n or 0
end

W.SPARK = { "_", "\226\150\129", "\226\150\130", "\226\150\131",
            "\226\150\132", "\226\150\133", "\226\150\134",
            "\226\150\135", "\226\150\136" }   -- "_" then U+2581..U+2588

--- A one-row sparkline of the last `w` samples, scaled to (lo, hi).
--- Gaps render as a space, which is visibly not a low reading.
function W.spark(series, w, lo, hi)
  series = series or {}
  w = math.max(1, math.floor(w or 1))
  local start = math.max(1, #series - w + 1)
  if lo == nil or hi == nil then
    local a, b = W.range(series)
    lo, hi = lo or a, hi or b
  end
  local out = {}
  for i = start, #series do
    local v = series[i]
    if type(v) ~= "number" then
      out[#out + 1] = " "
    elseif not lo or not hi or hi <= lo then
      --! A flat series has no range to scale against. Drawing it at the
      --! bottom would say "zero" and at the top would say "maximum";
      --! mid-height says "steady", which is what it actually means.
      out[#out + 1] = W.SPARK[5]
    else
      local f = (v - lo) / (hi - lo)
      if f < 0 then f = 0 elseif f > 1 then f = 1 end
      out[#out + 1] = W.SPARK[math.floor(f * (#W.SPARK - 1) + 0.5) + 1]
    end
  end
  return table.concat(out)
end

--- A `h`-row column chart of the last `w` samples, top row first.
--- Same gap semantics as spark().
function W.chart(series, w, h, lo, hi)
  series = series or {}
  w = math.max(1, math.floor(w or 1))
  h = math.max(1, math.floor(h or 1))
  if lo == nil or hi == nil then
    local a, b = W.range(series)
    lo, hi = lo or a, hi or b
  end
  local start = math.max(1, #series - w + 1)
  local heights = {}
  for i = start, #series do
    local v = series[i]
    if type(v) ~= "number" then
      heights[#heights + 1] = false
    elseif not lo or not hi or hi <= lo then
      heights[#heights + 1] = math.ceil(h / 2)
    else
      local f = (v - lo) / (hi - lo)
      if f < 0 then f = 0 elseif f > 1 then f = 1 end
      --! At least one row for any real sample: a bar of height zero is
      --! indistinguishable from a gap, and those mean opposite things.
      heights[#heights + 1] = math.max(1, math.floor(f * h + 0.5))
    end
  end
  local rows = {}
  for row = 1, h do
    local fromTop = h - row + 1      -- row 1 is the TOP
    local line = {}
    for i = 1, #heights do
      local bar = heights[i]
      line[i] = (bar and bar >= fromTop) and "\226\150\136" or " "
    end
    rows[row] = table.concat(line)
  end
  return rows
end

return W
