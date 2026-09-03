-- ╔══════════════════════════════════════════════════════╗
-- ║  Optional Utilities — Mail TUI (CLI shell client)    ║
-- ║                                                      ║
-- ║  Full-screen inbox/read/compose client for the mail  ║
-- ║  package — the interactive counterpart to the        ║
-- ║  line-based `mail` subcommands, used by the CLI      ║
-- ║  shell (the panels shell opens the mailapp TAB       ║
-- ║  instead). Owns the screen, runs an input loop,      ║
-- ║  returns on ^Q. Ships with the mail package.         ║
-- ╚══════════════════════════════════════════════════════╝

local computer = require("computer")
local mailLib  = require("mail")

local M = {}

--- Run the mail TUI. opts = { display=D, me=<username>, event=E(optional),
--- aliases=<net.aliases-like resolver holder> (optional) }.
function M.run(opts)
  opts = opts or {}
  local D  = opts.display or opts.D
  local E  = opts.event or opts.E
  local me = opts.me or "user"
  if not D then return end

  local W, H = D.getSize()
  local T    = D.getTheme()

  -- Seat-safe pull (the login.lua lesson): inside a process coroutine the
  -- only correct read is coroutine.yield() — raw pullSignal would drain
  -- the global queue and starve other seats. E.pull/pullSignal are the
  -- non-process fallbacks.
  local function pull(timeout)
    if coroutine.isyieldable and coroutine.isyieldable() then
      return coroutine.yield()
    end
    if E and E.pull then return E.pull(timeout) end
    return computer.pullSignal(timeout)
  end

  local function waitKey(msg, color)
    D.clear(T.bg)
    D.set(2, 2, msg, color or T.fg, T.bg)
    D.set(2, 4, "Press any key to return.", T.dim, T.bg)
    local deadline = computer.uptime() + 10
    while computer.uptime() < deadline do
      local ev = pull(deadline - computer.uptime())
      if ev == "key_down" then break end
    end
  end

  if not mailLib.available() then
    waitKey("Mail unavailable (no network hardware?)", T.error)
    return
  end

  local box = mailLib.inboxBox(me)
  if not box then
    waitKey("Cannot open this inbox (owner or admin only).", T.error)
    return
  end
  local function list() return (box and box.list and box:list()) or {} end
  local function refresh()
    mailLib.tick()
    box = mailLib.inboxBox(me) or box
  end

  local mode       = "list"     -- "list" | "read"
  local sel        = 1
  local scroll     = 0
  local openIdx    = nil        -- index being read
  local bodyLines  = {}         -- wrapped body of the open message
  local readScroll = 0

  local HELP_ROW = H
  local LIST_TOP = 3
  local LIST_H   = HELP_ROW - LIST_TOP

  -- ── small line editor (compose fields) ──────────────────
  local function readField(label, initial, maxLen, y)
    local buf = initial or ""
    while true do
      D.fill(1, y, W, 1, " ", T.fg, T.bg)
      D.set(1, y, label, T.highlight, T.bg)
      local avail = math.max(1, W - #label - 1)
      local shown = #buf > avail and buf:sub(#buf - avail + 1) or buf
      D.set(#label + 1, y, shown .. "_", T.fg, T.bg)
      local sig, _, c, co = pull()
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

  -- ── compose ─────────────────────────────────────────────
  local function compose(prefillTo, prefillSubject)
    D.clear(T.bg)
    D.set(1, 1, " Compose mail   (Enter = next field/line, ^Q = cancel)", T.title, T.bg)
    local to = readField(" To (peer / alias / user@peer / * = all): ", prefillTo, 64, 3)
    if not to or to == "" then return end
    local subj = readField(" Subject: ", prefillSubject, 100, 5)
    if subj == nil then return end
    D.set(1, 7, " Body — Enter for a new line, a blank line sends, ^Q cancels:", T.dim, T.bg)
    local lines, y = {}, 9
    while #lines < 64 and y <= H - 1 do
      local ln = readField("  ", "", 200, y)
      if ln == nil then return end           -- cancelled
      if ln == "" then break end
      lines[#lines + 1] = ln
      y = y + 1
    end
    local toAddr, ruser = mailLib.resolveRecipient(to,
      opts.aliases and opts.aliases.resolve)
    local id, sealed = mailLib.send({ to = toAddr, user = ruser, fromUser = me,
      subject = subj, body = table.concat(lines, "\n") })
    D.fill(1, H, W, 1, " ", T.fg, T.bg)
    if id then
      D.set(1, H, "Queued " .. tostring(id):sub(1, 18)
        .. (sealed and "  (sealed)" or "  (PLAINTEXT bulletin)"),
        sealed and T.highlight or T.warning)
    else
      -- Refuse-plaintext lands here for an unpaired unicast peer.
      D.set(1, H, "Send failed: " .. tostring(sealed), T.error)
    end
    local dl = computer.uptime() + 1.4
    while computer.uptime() < dl do pull(dl - computer.uptime()) end
  end

  -- ── drawing ─────────────────────────────────────────────
  local function header()
    D.fill(1, 1, W, 1, " ", T.menubar_fg, T.menubar_bg)
    local msgs = list()
    local unread = (box and box.unread and box:unread()) or 0
    local pend = mailLib.pending()
    local left = " TOS Mail — " .. me .. " "
    local right = string.format(" %d msg, %d unread%s%s ", #msgs, unread,
      pend > 0 and (", " .. pend .. " sending") or "",
      mailLib.running() and "" or ", RECEIVE OFF")
    D.set(1, 1, left, T.menubar_fg, T.menubar_bg)
    D.set(math.max(1, W - #right + 1), 1, right, T.dim, T.menubar_bg)
  end

  local function drawList()
    header()
    D.fill(1, 2, W, 1, " ", T.fg, T.bg)
    local msgs = list()
    if #msgs == 0 then
      D.set(2, LIST_TOP, "(inbox empty)", T.dim, T.bg)
      for r = LIST_TOP + 1, HELP_ROW - 1 do D.fill(1, r, W, 1, " ", T.fg, T.bg) end
    else
      if sel > #msgs then sel = #msgs end
      if sel < 1 then sel = 1 end
      if sel <= scroll then scroll = sel - 1 end
      if sel > scroll + LIST_H then scroll = sel - LIST_H end
      if scroll < 0 then scroll = 0 end
      for r = 0, LIST_H - 1 do
        local idx = scroll + r + 1
        local y = LIST_TOP + r
        if idx <= #msgs then
          local m = msgs[idx]
          local line = mailLib.inboxRow(m, idx, W - 1)
          if idx == sel then
            D.set(1, y, D.fit and D.fit(line, W) or line, T.sel_fg, T.sel_bg)
          else
            D.set(1, y, line, m.read and T.dim or T.fg, T.bg)
          end
        else
          D.fill(1, y, W, 1, " ", T.fg, T.bg)
        end
      end
    end
    D.fill(1, HELP_ROW, W, 1, " ", T.dim, T.menubar_bg)
    D.set(1, HELP_ROW, " [Enter] read  [c] compose  [r] reply  [d] delete  [R] refresh  ^Q exit",
      T.dim, T.menubar_bg)
  end

  local function wrapBody(text)
    local out = {}
    for raw in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
      if raw == "" then out[#out + 1] = ""
      else
        while #raw > 0 do out[#out + 1] = raw:sub(1, W - 1); raw = raw:sub(W) end
      end
    end
    return out
  end

  local function openMessage(idx)
    local m = box and box.get and box:get(idx)
    if not m then return false end
    if box.markRead then pcall(function() box:markRead(idx) end) end
    openIdx = idx
    local hdr = {
      { "From:    " .. mailLib.senderName(m)
        .. (m.from and ("  (" .. tostring(m.from):sub(1, 12) .. ")") or ""), T.fg },
      { "Subject: " .. (m.subject ~= "" and m.subject or "(no subject)"), T.title },
    }
    if not m.readable then hdr[#hdr + 1] = { "[sealed — no shared secret to open this]", T.warning } end
    bodyLines = {}
    for _, l in ipairs(hdr) do bodyLines[#bodyLines + 1] = l end
    bodyLines[#bodyLines + 1] = { "", T.fg }
    for _, l in ipairs(wrapBody(m.body)) do bodyLines[#bodyLines + 1] = { l, T.fg } end
    readScroll = 0
    mode = "read"
    return true
  end

  local function drawRead()
    header()
    local viewH = HELP_ROW - 2
    for r = 0, viewH - 1 do
      local y = 2 + r
      local idx = readScroll + r + 1
      D.fill(1, y, W, 1, " ", T.fg, T.bg)
      local e = bodyLines[idx]
      if e then D.set(1, y, (type(e) == "table" and e[1] or tostring(e)),
        (type(e) == "table" and e[2]) or T.fg, T.bg) end
    end
    D.fill(1, HELP_ROW, W, 1, " ", T.dim, T.menubar_bg)
    D.set(1, HELP_ROW, " [q/Esc] back  [r] reply  [d] delete  up/down scroll  ^Q exit",
      T.dim, T.menubar_bg)
  end

  local function redraw()
    D.clear(T.bg)
    if mode == "read" then drawRead() else drawList() end
  end

  -- ── input loop ──────────────────────────────────────────
  refresh()
  redraw()
  local lastTick = computer.uptime()

  while true do
    local sig, _, ch, co = pull(0.5)

    if sig == "key_down" then
      if ch == 17 then break                                  -- ^Q exit
      elseif mode == "list" then
        local msgs = list()
        if co == 200 then sel = math.max(1, sel - 1); drawList()           -- up
        elseif co == 208 then sel = math.min(#msgs, sel + 1); drawList()   -- down
        elseif co == 201 then sel = math.max(1, sel - LIST_H); drawList()  -- PgUp
        elseif co == 209 then sel = math.min(#msgs, sel + LIST_H); drawList()
        elseif co == 199 then sel = 1; drawList()                          -- Home
        elseif co == 207 then sel = #msgs; drawList()                      -- End
        elseif co == 28 then                                               -- Enter = read
          if #msgs > 0 and openMessage(sel) then redraw() else drawList() end
        elseif ch == 99 or ch == 67 then                                   -- c = compose
          compose(); refresh(); redraw()
        elseif ch == 114 or ch == 82 then                                  -- r = reply
          local m = msgs[sel]
          if m then
            local rt = (m.fromUser and m.fromUser ~= "" and m.fromUser)
              or (m.from and ("@" .. tostring(m.from))) or ""
            local subj = (m.subject and not m.subject:match("^[Rr][Ee]:"))
              and ("Re: " .. m.subject) or (m.subject or "")
            compose(rt:gsub("^@", ""), subj); refresh(); redraw()
          end
        elseif ch == 100 or ch == 68 then                                  -- d = delete
          if #msgs > 0 and box and box.delete then
            pcall(function() box:delete(sel) end)
            refresh(); drawList()
          end
        end
      else  -- read mode
        local maxScroll = math.max(0, #bodyLines - (HELP_ROW - 2))
        if co == 1 or ch == 113 then mode = "list"; redraw()               -- Esc/q = back
        elseif co == 200 then readScroll = math.max(0, readScroll - 1); drawRead()
        elseif co == 208 then readScroll = math.min(maxScroll, readScroll + 1); drawRead()
        elseif co == 201 then readScroll = math.max(0, readScroll - (HELP_ROW - 2)); drawRead()
        elseif co == 209 then readScroll = math.min(maxScroll, readScroll + (HELP_ROW - 2)); drawRead()
        elseif ch == 114 or ch == 82 then                                  -- r = reply
          local m = openIdx and box and box.get and box:get(openIdx)
          if m then
            local rt = (m.fromUser and m.fromUser ~= "" and m.fromUser) or ""
            local subj = (m.subject and not m.subject:match("^[Rr][Ee]:"))
              and ("Re: " .. m.subject) or (m.subject or "")
            compose(rt, subj); mode = "list"; refresh(); redraw()
          end
        elseif ch == 100 or ch == 68 then                                  -- d = delete + back
          if openIdx and box and box.delete then
            pcall(function() box:delete(openIdx) end)
            mode = "list"; refresh(); redraw()
          end
        end
      end

    elseif sig == "tos_focus" then
      redraw()

    elseif sig == nil then
      -- Idle: pull retries + new mail, refresh the list view live.
      local now = computer.uptime()
      if now - lastTick >= 2 then
        lastTick = now
        refresh()
        if mode == "list" then drawList() end
      end
    end
  end
end

return M
