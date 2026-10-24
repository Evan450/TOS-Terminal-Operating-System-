






























local W = {}

W.VERSION = "0.2.0"




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



W.DEFAULT_ROTATION = {
  { page = "map",    param = "T" },
  { page = "panel",  param = "T" },
  { page = "alarms", param = "T" },
  { page = "trend",  param = "T" },
  { page = "map",    param = "N" },
  { page = "trend",  param = "N" },
}
















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








function W.push(series, value, cap)
  series = series or {}
  cap = cap or 120
  series[#series + 1] = (type(value) == "number") and value or false
  while #series > cap do table.remove(series, 1) end
  return series
end


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
            "\226\150\135", "\226\150\136" }   



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
    local fromTop = h - row + 1      
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
