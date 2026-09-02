local monitor = {}

function monitor.describe(p)
  local name = (p and p.name) or "?"
  local seat = name:match("^login@(%d+)$")
  if seat then return "Login broker — seat " .. seat end
  local shUser, shSeat = name:match("^shell:(.+)@(%d+)$")
  if shUser then return "Shell — " .. shUser .. " (seat " .. shSeat .. ")" end
  if p and (p.user == "_kernel_" or p.source == "kernel") then
    return name .. "  (kernel)"
  end
  return name
end

function monitor.kindTag(p)
  local name = (p and p.name) or ""
  if name:match("^shell:") then return "shell" end
  if name:match("^login@") then return "sys" end
  if p and (p.user == "_kernel_" or p.source == "kernel") then return "sys" end
  return "user"
end

function monitor.memBar(used, total, width)
  width = math.max(1, math.floor(width or 10))
  if not total or total <= 0 then return string.rep("?", width) end
  local frac = (used or 0) / total
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local filled = math.floor(frac * width + 0.5)
  if filled > width then filled = width end
  return string.rep("#", filled) .. string.rep("-", width - filled)
end

function monitor.fmtUptime(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec < 0 then sec = 0 end
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then return string.format("%dh%02dm", h, m) end
  if m > 0 then return string.format("%dm%02ds", m, s) end
  return string.format("%ds", s)
end

function monitor.buildRows(procs, services)
  local rows = {}
  for _, p in ipairs(procs or {}) do rows[#rows + 1] = { kind = "proc", p = p } end
  if services and #services > 0 then
    rows[#rows + 1] = { kind = "header", text = "Services" }
    for _, s in ipairs(services) do rows[#rows + 1] = { kind = "svc", s = s } end
  end
  return rows
end

function monitor.nextSelectable(rows, sel, dir)
  local n = #rows
  if n == 0 then return sel end
  local i = sel
  for _ = 1, n do
    local j = i + dir
    if j < 1 or j > n then return i end
    i = j
    if rows[i] and rows[i].kind ~= "header" then return i end
  end
  return sel
end

function monitor.textRows(procs, services)
  local out = {}
  local function add(t, tone) out[#out + 1] = { text = t, tone = tone } end
  for _, r in ipairs(monitor.buildRows(procs, services)) do
    if r.kind == "proc" then
      local p = r.p
      add(string.format("%-5s %-5s %s",
        tostring(p.pid or "?"), monitor.kindTag(p), monitor.describe(p)), "proc")
    elseif r.kind == "header" then
      add("-- " .. (r.text or "") .. " --", "header")
    elseif r.kind == "svc" then
      local s = r.s or {}
      local status = s.running and "running" or "stopped"
      if s.enabled == false then status = status .. ", disabled" end
      add(string.format("  %-22s [%s]", tostring(s.name or "?"), status), "svc")
    end
  end
  if #out == 0 then add("(no visible processes)", "dim") end
  return out
end

function monitor.canAct(seatTier, seatUser, displayIdx, p)
  if (seatTier or 0) >= 3 then return true end
  if p.user == "_kernel_" then return false end
  if (seatTier or 0) >= 2 then
    return (not p.display) or p.display == displayIdx
  end
  return p.user ~= nil and p.user == seatUser
end

function monitor.firstSelectable(rows)
  for i, r in ipairs(rows) do
    if r.kind ~= "header" then return i end
  end
  return 1
end

return monitor
