-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - System Monitor helpers (pure)                ║
-- ║                                                            ║
-- ║  The System Monitor is the grown-up Ctrl+T task switcher:  ║
-- ║  a live view of what TOS is actually doing — every         ║
-- ║  process (kernel AND user, each explained), the rc.d       ║
-- ║  services, and memory/uptime vitals. kernel.taskSwitcher    ║
-- ║  does the drawing + input; the side-effect-free assembly,  ║
-- ║  labelling and formatting live here so they're unit-       ║
-- ║  testable off-box.                                          ║
-- ╚══════════════════════════════════════════════════════════╝

local monitor = {}

-- Human description of a process from its structured name / source / owner.
-- The kernel spawns processes with machine names (login@N, shell:user@N) and
-- source="kernel" — operators shouldn't have to decode those. Pure.
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

-- One-word kind tag, for grouping / colouring:
--   sys   — kernel-owned infrastructure (login brokers, daemons)
--   shell — an interactive shell
--   user  — a user-launched program
function monitor.kindTag(p)
  local name = (p and p.name) or ""
  if name:match("^shell:") then return "shell" end
  if name:match("^login@") then return "sys" end
  if p and (p.user == "_kernel_" or p.source == "kernel") then return "sys" end
  return "user"
end

-- A text memory/▮ bar: `width` cells, filled in proportion to used/total.
-- Returns "????" when total is unknown. Pure.
function monitor.memBar(used, total, width)
  width = math.max(1, math.floor(width or 10))
  if not total or total <= 0 then return string.rep("?", width) end
  local frac = (used or 0) / total
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local filled = math.floor(frac * width + 0.5)
  if filled > width then filled = width end
  return string.rep("#", filled) .. string.rep("-", width - filled)
end

-- Compact uptime: 1h23m / 4m05s / 37s. Pure.
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

-- Build the unified, scrollable row list for the monitor: every process row,
-- then (if any) a "Services" header row followed by one row per service.
-- Header rows are NOT selectable. Pure: given the proc list + service list it
-- returns row descriptors { kind = "proc"|"header"|"svc", ... }.
function monitor.buildRows(procs, services)
  local rows = {}
  for _, p in ipairs(procs or {}) do rows[#rows + 1] = { kind = "proc", p = p } end
  if services and #services > 0 then
    rows[#rows + 1] = { kind = "header", text = "Services" }
    for _, s in ipairs(services) do rows[#rows + 1] = { kind = "svc", s = s } end
  end
  return rows
end

-- Move the selection by `dir` (+1 down / -1 up), skipping non-selectable header
-- rows, clamped to the ends. Returns the new index. Pure.
function monitor.nextSelectable(rows, sel, dir)
  local n = #rows
  if n == 0 then return sel end
  local i = sel
  for _ = 1, n do
    local j = i + dir
    if j < 1 or j > n then return i end       -- clamp at the list ends
    i = j
    if rows[i] and rows[i].kind ~= "header" then return i end
  end
  return sel
end

-- Render the unified row list as plain text for the scrollable `monitor` live
-- tab (the roomy, per-seat counterpart to the Ctrl+T switcher — no truncation,
-- scrolls like any view tab). Returns an array of { text=, tone= } where tone ∈
-- proc/header/svc/dim; the shell maps tone → a theme colour. Pure.
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

-- May a seat principal kill/TSR a given proc.list() entry? One policy for
-- BOTH monitor surfaces (the Ctrl+T switcher and the Monitor app tab), so
-- they can't drift: root → anything; admin → same-display (or unbound);
-- everyone else → their own processes only. Kernel processes are immune
-- unless the caller is root. Pure.
function monitor.canAct(seatTier, seatUser, displayIdx, p)
  if (seatTier or 0) >= 3 then return true end
  if p.user == "_kernel_" then return false end
  if (seatTier or 0) >= 2 then
    return (not p.display) or p.display == displayIdx
  end
  return p.user ~= nil and p.user == seatUser
end

-- Clamp/seed a selection onto the first selectable row (used at open and after
-- a list rebuild drops the selected entry). Pure.
function monitor.firstSelectable(rows)
  for i, r in ipairs(rows) do
    if r.kind ~= "header" then return i end
  end
  return 1
end

return monitor
