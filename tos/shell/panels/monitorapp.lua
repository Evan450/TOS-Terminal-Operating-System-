local ui      = require("shell.panels.ui")
local tabsMod = require("shell.panels.tabs")
local helpers = require("shell.panels.helpers")

local M = {}

local function kernelAPI()
  local TOS = _G._TOS
  return TOS and TOS.kernel or nil
end

function M.rowSelectable(row)
  return row ~= nil and row.kind ~= "header"
end

function M.nextSelectable(rows, sel, dir)
  local n = #rows
  if n == 0 then return sel end
  local i = sel
  for _ = 1, n do
    local j = i + dir
    if j < 1 or j > n then return i end
    i = j
    if M.rowSelectable(rows[i]) then return i end
  end
  return sel
end

function M.firstSelectable(rows)
  for i, r in ipairs(rows) do
    if M.rowSelectable(r) then return i end
  end
  return 1
end

function M.refresh(S, tab)
  local k = kernelAPI()
  local snap = nil
  if k and k.monitorList then
    local ok, s = pcall(k.monitorList, S.displayIdx, helpers.sessionOf(S))
    if ok then snap = s end
  end
  local prev = tab.rows and tab.rows[tab.sel or 0] or nil
  tab.rows   = (snap and snap.rows) or {}
  tab.vitals = snap and snap.vitals or nil
  if not snap then
    tab.msg = { "System monitor data unavailable.", S.T.error }
  end

  local sel = nil
  if prev then
    for i, r in ipairs(tab.rows) do
      if (prev.kind == "proc" and r.kind == "proc" and r.pid == prev.pid)
      or (prev.kind == "svc" and r.kind == "svc" and r.name == prev.name) then
        sel = i; break
      end
    end
  end
  tab.sel = sel or math.min(tab.sel or 1, #tab.rows)
  if tab.sel < 1 or not M.rowSelectable(tab.rows[tab.sel]) then
    tab.sel = M.firstSelectable(tab.rows)
  end
end

function M.open(S)
  local idx = tabsMod.find(S, "monitor")
  local tab
  if idx then
    tab = S.tabs[idx]
    S.activeTab = idx
  else
    tab = tabsMod.create(S, "monitor", "Monitor",
      { sel = 1, scroll = 0, live = true, interval = 2 })
  end
  M.refresh(S, tab)
  return tab
end

local LIST_TOP = 5

local function listHeight(H) return math.max(1, H - LIST_TOP - 1) end

local function clampScroll(tab, H)
  local listH = listHeight(H)
  tab.scroll = tab.scroll or 0
  if #tab.rows == 0 then tab.scroll = 0; return end
  if tab.sel <= tab.scroll then tab.scroll = tab.sel - 1 end
  if tab.sel > tab.scroll + listH then tab.scroll = tab.sel - listH end
  local maxScroll = math.max(0, #tab.rows - listH)
  if tab.scroll > maxScroll then tab.scroll = maxScroll end
  if tab.scroll < 0 then tab.scroll = 0 end
end

function M.draw(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  if not tab.rows then M.refresh(S, tab) end
  clampScroll(tab, H)

  D.fill(1, 2, W, H - 1, " ", T.fg, T.bg)
  ui.drawRail(D, T, 2, W, { { label = "§ System Monitor" } },
    { labelFg = T.title or T.fg })
  if tab.vitals then
    D.set(2, 3, tab.vitals:sub(1, W - 2), T.highlight or T.fg, T.bg)
  end
  local hdr = string.format(" %-5s %-30s %-9s %-8s %6s",
    "PID", "Process", "Owner", "State", "CPU")
  D.set(1, 4, hdr:sub(1, W), T.dim, T.bg)

  local listH = listHeight(H)
  for i = 1, listH do
    local idx = tab.scroll + i
    local y = LIST_TOP + i - 1
    local r = tab.rows[idx]
    if r then
      local selected = (idx == tab.sel)
      if r.kind == "header" then

        local prefix = " ── " .. (r.text or "") .. " "
        local pad = math.max(0, W - #prefix)
        D.set(1, y, prefix .. string.rep("─", pad), T.title, T.bg)
      elseif r.kind == "proc" then
        local mark = r.isFg and "*" or " "
        local line = string.format("%s%-5d %-30s %-9s %-8s %5.1fs",
          mark, r.pid, tostring(r.label):sub(1, 30),
          tostring(r.owner):sub(1, 9), tostring(r.state):sub(1, 8), r.cpu or 0)
        if selected then
          D.fill(1, y, W, 1, " ", T.sel_fg or T.bg, T.sel_bg or T.highlight)
          D.set(1, y, line:sub(1, W), T.sel_fg or T.bg, T.sel_bg or T.highlight)
        else
          local color = T.fg
          if r.tsr or not r.canAct then color = T.dim end
          if r.isFg then color = T.highlight or T.fg end
          D.set(1, y, line:sub(1, W), color, T.bg)
        end
      else
        local status = r.running and "running"
          or (r.enabled == false and "disabled" or "stopped")
        local line = string.format("   %-33s %s", tostring(r.name):sub(1, 33), status)
        if selected then
          D.fill(1, y, W, 1, " ", T.sel_fg or T.bg, T.sel_bg or T.highlight)
          D.set(1, y, line:sub(1, W), T.sel_fg or T.bg, T.sel_bg or T.highlight)
        else
          D.set(1, y, line:sub(1, W), r.running and (T.highlight or T.fg) or T.dim, T.bg)
        end
      end
    end
  end

  if tab.msg then
    D.fill(1, H - 1, W, 1, " ", T.fg, T.bg)
    D.set(2, H - 1, tostring(tab.msg[1]):sub(1, W - 2), tab.msg[2] or T.dim, T.bg)
  end
  local r = tab.rows[tab.sel]
  local hints
  if r and r.kind == "svc" then
    hints = "Enter Start/Stop · Arrows Move · R Refresh · ^Q Close"
  else
    hints = "Enter Switch · K Kill · T TSR · Arrows Move · R Refresh · ^Q Close"
  end
  ui.drawRampBar(D, T, H, W, hints,
    nil, T.statusbar_fg or T.bar_fg, T.statusbar_bg or T.bar_bg)
end

local function act(S, tab, action, id, okMsg)
  local k = kernelAPI()
  if not (k and k.monitorAct) then
    tab.msg = { "Monitor actions unavailable.", S.T.error }
    return 3
  end
  local okCall, ok, err = pcall(k.monitorAct, action, id)
  if not okCall then ok, err = false, ok end
  if ok then
    tab.msg = okMsg and { okMsg, S.T.highlight } or nil
    if action == "switch" then

      S.suspendIdleDraw = true
    end
  else
    tab.msg = { tostring(err or "action failed"), S.T.error }
  end
  M.refresh(S, tab)
  return 3
end

local function activate(S, tab)
  local r = tab.rows and tab.rows[tab.sel]
  if not r then return 0 end
  if r.kind == "svc" then
    return act(S, tab, "svc", r.name,
      (r.running and "Stopping " or "Starting ") .. tostring(r.name))
  elseif r.kind == "proc" then
    return act(S, tab, "switch", r.pid)
  end
  return 0
end

function M.handleKey(S, tab, ch, co, deps)
  if not tab.rows then M.refresh(S, tab) end
  local rows = tab.rows
  local listH = listHeight(S.H)

  if ch == 17 then
    tabsMod.close(S)
    return 3
  elseif co == 200 then
    tab.sel = M.nextSelectable(rows, tab.sel, -1); return 3
  elseif co == 208 then
    tab.sel = M.nextSelectable(rows, tab.sel, 1); return 3
  elseif co == 201 then
    for _ = 1, listH do tab.sel = M.nextSelectable(rows, tab.sel, -1) end
    return 3
  elseif co == 209 then
    for _ = 1, listH do tab.sel = M.nextSelectable(rows, tab.sel, 1) end
    return 3
  elseif co == 199 then
    tab.sel = M.firstSelectable(rows); tab.scroll = 0; return 3
  elseif co == 207 then
    tab.sel = #rows
    if not M.rowSelectable(rows[tab.sel]) then
      tab.sel = M.nextSelectable(rows, tab.sel, -1)
    end
    return 3
  elseif ch == 114 or ch == 82 then
    M.refresh(S, tab); return 3
  elseif co == 28 then
    return activate(S, tab)
  elseif ch == 107 or ch == 75 then
    local r = rows[tab.sel]
    if r and r.kind == "proc" then
      if not r.canAct then
        tab.msg = { "Not permitted.", S.T.warning }; return 3
      end
      return act(S, tab, "kill", r.pid, "Killed PID " .. r.pid)
    end
  elseif ch == 116 or ch == 84 then
    local r = rows[tab.sel]
    if r and r.kind == "proc" then
      if not r.canAct then
        tab.msg = { "Not permitted.", S.T.warning }; return 3
      end
      return act(S, tab, "tsr", r.pid)
    end
  end
  return 0
end

function M.handleClick(S, tab, ev, deps)
  if not tab.rows then M.refresh(S, tab) end
  local idx = (tab.scroll or 0) + (ev.y - LIST_TOP + 1)
  local r = tab.rows[idx]
  if ev.y >= LIST_TOP and r and M.rowSelectable(r) then
    if idx == tab.sel and ev.button ~= 1 then
      return activate(S, tab)
    end
    tab.sel = idx
    return 3
  end
  return 0
end

function M.handleScroll(S, tab, ev)
  if not tab.rows then M.refresh(S, tab) end
  local dir = (ev.dir or 0) > 0 and -1 or 1
  local newSel = M.nextSelectable(tab.rows, tab.sel, dir)
  if newSel == tab.sel then return 0 end
  tab.sel = newSel
  return 3
end

function M.tick(S, tab)
  M.refresh(S, tab)
  return 3
end

return M
