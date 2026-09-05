-- ╔══════════════════════════════════════════════════════╗
-- ║  Optional Utilities — Mail App (panels tab)          ║
-- ║                                                      ║
-- ║  The mail inbox as a persistent panels TAB (type     ║
-- ║  "mail"): list + read views, compose/reply, delete,  ║
-- ║  live refresh while front, unread badge on the tab   ║
-- ║  label. Ships with the mail package (stage 5); the   ║
-- ║  panels app registry pcall-requires "mailapp" and    ║
-- ║  simply skips it when the add-on isn't installed.    ║
-- ║                                                      ║
-- ║  Runs INSIDE the panels shell (full-priv), so the    ║
-- ║  shell.panels.* toolkit requires are fine here.      ║
-- ╚══════════════════════════════════════════════════════╝

local computer = require("computer")
local ui       = require("shell.panels.ui")
local tabsMod  = require("shell.panels.tabs")
local mailLib  = require("mail")   -- the package's service lib

local M = {}

local LIST_TOP = 4

local function listHeight(H) return math.max(1, (H - 1) - LIST_TOP) end

-- ── Model ───────────────────────────────────────────────────

function M.label(unread)
  if (unread or 0) > 0 then return "Mail(" .. unread .. ")" end
  return "Mail"
end

local function box(S, tab)
  -- Own inbox only (principal-enforced in the lib).
  return (mailLib.inboxBox(S.who or "user"))
end

--- Re-pump the mesh (retries + arrivals) and refresh the badge.
function M.refresh(S, tab)
  mailLib.tick()
  local b = box(S, tab)
  tab._box = b
  local unread = (b and b.unread and b:unread()) or 0
  tab.unread = unread
  if S.tabs[S.activeTab] == tab then
    tab.label = M.label(0)     -- you're looking at it
  else
    tab.label = M.label(unread)
  end
end

local function msgs(tab)
  local b = tab._box
  return (b and b.list and b:list()) or {}
end

--- Find-or-create the Mail tab and focus it.
function M.open(S)
  local idx = tabsMod.find(S, "mail")
  local tab
  if idx then
    tab = S.tabs[idx]
    S.activeTab = idx
  else
    tab = tabsMod.create(S, "mail", "Mail",
      { mode = "list", sel = 1, scroll = 0, readScroll = 0,
        live = true, interval = 2 })
  end
  M.refresh(S, tab)
  return tab
end

-- ── Reading ─────────────────────────────────────────────────

local function wrapBody(text, W)
  local out = {}
  for raw in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    if raw == "" then out[#out + 1] = ""
    else
      while #raw > 0 do out[#out + 1] = raw:sub(1, W - 1); raw = raw:sub(W) end
    end
  end
  return out
end

local function openMessage(S, tab, idx)
  local b = tab._box
  local m = b and b.get and b:get(idx)
  if not m then return false end
  if b.markRead then pcall(function() b:markRead(idx) end) end
  local T = S.T
  tab.openIdx = idx
  tab.bodyLines = {
    { "From:    " .. mailLib.senderName(m)
      .. (m.from and ("  (" .. tostring(m.from):sub(1, 12) .. ")") or ""), T.fg },
    { "Subject: " .. (m.subject ~= "" and m.subject or "(no subject)"), T.title },
  }
  if not m.readable then
    tab.bodyLines[#tab.bodyLines + 1] =
      { "[sealed — no shared secret to open this]", T.warning }
  end
  tab.bodyLines[#tab.bodyLines + 1] = { "", T.fg }
  for _, l in ipairs(wrapBody(m.body, S.W)) do
    tab.bodyLines[#tab.bodyLines + 1] = { l, T.fg }
  end
  tab.readScroll = 0
  tab.mode = "read"
  return true
end

-- ── Compose (blocking field editor, like the old TUI) ───────

local function pullSignal(timeout)
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
  return computer.pullSignal(timeout or 0.1)
end

local function readField(S, label, initial, maxLen, y)
  local D, T, W = S.D, S.T, S.W
  local buf = initial or ""
  while true do
    D.fill(1, y, W, 1, " ", T.fg, T.bg)
    D.set(1, y, label, T.highlight, T.bg)
    local avail = math.max(1, W - #label - 1)
    local shown = #buf > avail and buf:sub(#buf - avail + 1) or buf
    D.set(#label + 1, y, shown .. "_", T.fg, T.bg)
    local sig, _, c, co = pullSignal()
    if sig == "key_down" then
      if co == 28 then return buf
      elseif c == 17 then return nil                       -- ^Q cancels
      elseif co == 14 then if #buf > 0 then buf = buf:sub(1, -2) end
      elseif c and c >= 32 and c < 127 and #buf < (maxLen or 256) then
        buf = buf .. string.char(c)
      end
    elseif sig == "clipboard" and type(c) == "string" then
      buf = buf .. c:gsub("\n", "")
    end
  end
end

local function compose(S, tab, prefillTo, prefillSubject)
  local D, T, W, H, NM = S.D, S.T, S.W, S.H, S.NM
  D.fill(1, 2, W, H - 1, " ", T.fg, T.bg)
  D.set(1, 2, " Compose mail   (Enter = next field/line, ^Q = cancel)", T.title, T.bg)
  local to = readField(S, " To (peer / alias / user@peer / * = all): ", prefillTo, 64, 4)
  if not to or to == "" then return end
  local subj = readField(S, " Subject: ", prefillSubject, 100, 6)
  if subj == nil then return end
  D.set(1, 8, " Body — Enter for a new line, a blank line sends, ^Q cancels:", T.dim, T.bg)
  local lines, y = {}, 10
  while #lines < 64 and y <= H - 1 do
    local ln = readField(S, "  ", "", 200, y)
    if ln == nil then return end
    if ln == "" then break end
    lines[#lines + 1] = ln
    y = y + 1
  end
  local toAddr, ruser = mailLib.resolveRecipient(to,
    NM and NM.aliases and NM.aliases.resolve)
  local id, sealed = mailLib.send({ to = toAddr, user = ruser,
    fromUser = S.who or "user", subject = subj, body = table.concat(lines, "\n") })
  D.fill(1, H, W, 1, " ", T.fg, T.bg)
  if id then
    D.set(1, H, "Queued " .. tostring(id):sub(1, 18)
      .. (sealed and "  (sealed)" or "  (PLAINTEXT bulletin)"),
      sealed and T.highlight or T.warning, T.bg)
  else
    -- Refuse-plaintext lands here for an unpaired unicast peer.
    D.set(1, H, "Send failed: " .. tostring(sealed), T.error, T.bg)
  end
  pullSignal(1.4)
end

-- ── Drawing ─────────────────────────────────────────────────
-- Row 1 top bar · row 2 rail · row 3 counts · rows 4..H-1 list/read ·
-- row H hints.

function M.draw(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  if not tab._box then M.refresh(S, tab) end
  D.fill(1, 2, W, H - 1, " ", T.fg, T.bg)

  ui.drawRail(D, T, 2, W, { { label = "§ Mail — " .. (S.who or "user") } },
    { labelFg = T.title or T.fg })
  local list = msgs(tab)
  local b = tab._box
  local unread = (b and b.unread and b:unread()) or 0
  local pend = mailLib.pending()
  local svcNote = mailLib.running() and "" or "  [service stopped — receive off]"
  D.set(2, 3, string.format("%d message(s), %d unread%s%s", #list, unread,
    pend > 0 and (", " .. pend .. " sending") or "", svcNote),
    svcNote ~= "" and T.warning or T.dim, T.bg)

  local listH = listHeight(H)
  if tab.mode == "read" then
    local body = tab.bodyLines or {}
    for r = 0, listH - 1 do
      local e = body[(tab.readScroll or 0) + r + 1]
      if e then
        D.set(1, LIST_TOP + r, tostring(e[1]):sub(1, W), e[2] or T.fg, T.bg)
      end
    end
    ui.drawRampBar(D, T, H, W,
      "q Back · Arrows Scroll · R Reply · D Delete · ^Q Close",
      nil, T.statusbar_fg or T.bar_fg, T.statusbar_bg or T.bar_bg)
  else
    if #list == 0 then
      D.set(2, LIST_TOP, "(inbox empty)", T.dim, T.bg)
    else
      if tab.sel > #list then tab.sel = #list end
      if tab.sel < 1 then tab.sel = 1 end
      if tab.sel <= tab.scroll then tab.scroll = tab.sel - 1 end
      if tab.sel > tab.scroll + listH then tab.scroll = tab.sel - listH end
      if tab.scroll < 0 then tab.scroll = 0 end
      for r = 0, listH - 1 do
        local idx = tab.scroll + r + 1
        local m = list[idx]
        if m then
          local line = mailLib.inboxRow(m, idx, W - 1)
          local y = LIST_TOP + r
          if idx == tab.sel then
            D.fill(1, y, W, 1, " ", T.sel_fg or T.bg, T.sel_bg or T.highlight)
            D.set(1, y, line:sub(1, W), T.sel_fg or T.bg, T.sel_bg or T.highlight)
          else
            D.set(1, y, line:sub(1, W), m.read and T.dim or T.fg, T.bg)
          end
        end
      end
    end
    ui.drawRampBar(D, T, H, W,
      "Enter Read · C Compose · R Reply · D Delete · ^Q Close",
      nil, T.statusbar_fg or T.bar_fg, T.statusbar_bg or T.bar_bg)
  end
  tab.label = M.label(0)     -- looking at it = seen
end

-- ── Input ───────────────────────────────────────────────────

local function replyTo(m)
  local to = (m.fromUser and m.fromUser ~= "" and m.fromUser)
    or (m.from and tostring(m.from)) or ""
  local subj = (m.subject and not m.subject:match("^[Rr][Ee]:"))
    and ("Re: " .. m.subject) or (m.subject or "")
  return to, subj
end

--- Keyboard. Returns (drawLevel[, result]).
function M.handleKey(S, tab, ch, co, deps)
  if not tab._box then M.refresh(S, tab) end
  local listH = listHeight(S.H)

  if ch == 17 then                                    -- Ctrl+Q: close tab
    tabsMod.close(S)
    return 3
  end

  if tab.mode == "read" then
    local maxScroll = math.max(0, #(tab.bodyLines or {}) - listH)
    if co == 1 or ch == 113 then tab.mode = "list"; return 3   -- Esc/q back
    elseif co == 200 then
      tab.readScroll = math.max(0, (tab.readScroll or 0) - 1); return 3
    elseif co == 208 then
      tab.readScroll = math.min(maxScroll, (tab.readScroll or 0) + 1); return 3
    elseif co == 201 then
      tab.readScroll = math.max(0, (tab.readScroll or 0) - listH); return 3
    elseif co == 209 then
      tab.readScroll = math.min(maxScroll, (tab.readScroll or 0) + listH); return 3
    elseif ch == 114 or ch == 82 then                 -- r = reply
      local b = tab._box
      local m = tab.openIdx and b and b.get and b:get(tab.openIdx)
      if m then
        local to, subj = replyTo(m)
        compose(S, tab, to, subj)
        tab.mode = "list"
        M.refresh(S, tab)
      end
      return 3
    elseif ch == 100 or ch == 68 then                 -- d = delete + back
      local b = tab._box
      if tab.openIdx and b and b.delete then
        pcall(function() b:delete(tab.openIdx) end)
        tab.mode = "list"
        M.refresh(S, tab)
      end
      return 3
    end
    return 0
  end

  -- List mode.
  local list = msgs(tab)
  if co == 200 then tab.sel = math.max(1, tab.sel - 1); return 3
  elseif co == 208 then tab.sel = math.min(math.max(1, #list), tab.sel + 1); return 3
  elseif co == 201 then tab.sel = math.max(1, tab.sel - listH); return 3
  elseif co == 209 then tab.sel = math.min(math.max(1, #list), tab.sel + listH); return 3
  elseif co == 199 then tab.sel = 1; return 3
  elseif co == 207 then tab.sel = math.max(1, #list); return 3
  elseif co == 28 then                                -- Enter = read
    if #list > 0 then openMessage(S, tab, tab.sel) end
    return 3
  elseif ch == 99 or ch == 67 then                    -- c = compose
    compose(S, tab)
    M.refresh(S, tab)
    return 3
  elseif ch == 114 then                               -- r = reply to selected
    local m = list[tab.sel]
    if m then
      local to, subj = replyTo(m)
      compose(S, tab, to, subj)
      M.refresh(S, tab)
    end
    return 3
  elseif ch == 82 then                                -- R = refresh now
    M.refresh(S, tab)
    return 3
  elseif ch == 100 or ch == 68 then                   -- d = delete
    local b = tab._box
    if #list > 0 and b and b.delete then
      pcall(function() b:delete(tab.sel) end)
      M.refresh(S, tab)
    end
    return 3
  end
  return 0
end

--- Mouse: click selects (list mode); click on selected reads.
function M.handleClick(S, tab, ev, deps)
  if tab.mode ~= "list" then return 0 end
  local list = msgs(tab)
  local idx = (tab.scroll or 0) + (ev.y - LIST_TOP + 1)
  if ev.y >= LIST_TOP and list[idx] then
    if idx == tab.sel and ev.button ~= 1 then
      openMessage(S, tab, idx)
    else
      tab.sel = idx
    end
    return 3
  end
  return 0
end

--- Mouse scroll: move the selection (list) / scroll the body (read).
function M.handleScroll(S, tab, ev)
  local dir = (ev.dir or 0) > 0 and -1 or 1
  if tab.mode == "read" then
    local maxScroll = math.max(0, #(tab.bodyLines or {}) - listHeight(S.H))
    local n = math.max(0, math.min(maxScroll, (tab.readScroll or 0) + dir))
    if n == tab.readScroll then return 0 end
    tab.readScroll = n
  else
    local list = msgs(tab)
    local n = math.max(1, math.min(math.max(1, #list), (tab.sel or 1) + dir))
    if n == tab.sel then return 0 end
    tab.sel = n
  end
  return 3
end

--- Live refresh while front: pump the mesh + repaint the list.
function M.tick(S, tab)
  M.refresh(S, tab)
  if tab.mode == "list" then return 3 end
  return 0
end

return M
