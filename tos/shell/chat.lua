-- ╔══════════════════════════════════════╗
-- ║  TOS Shell - Chat TUI                ║
-- ║  Messaging between TRUSTED peers     ║
-- ╚══════════════════════════════════════╝
-- Simple TUI chat interface. Messages are sent as MSG packets
-- (encrypted if shared secrets are configured). Incoming MSG
-- packets are displayed in real-time. Ctrl+Q to exit.

local computer = require("computer")

local chat = {}

-- ============================================================
-- Pure input helpers (unit-tested by test_chat_parse.lua)
-- ============================================================

--- Classify a line of chat input. Returns one of:
---   { kind = "empty" }
---   { kind = "command", name = <lower>, arg = <rest> }     -- "/who", "/mail bob hi"
---   { kind = "group",    group = <name>, text = <msg> }    -- "@ops:status?"
---   { kind = "directed", target = <peer>, text = <msg> }   -- "bob:hello"
---   { kind = "broadcast", text = <msg> }                   -- anything else
---
--- Multi-operator chat is these three addressing modes: one peer, one named
--- group, or everybody trusted. The group form is checked BEFORE the
--- directed one because "@ops:hi" would otherwise parse as a peer literally
--- named "@ops" and fail to resolve — the failure would be a confusing
--- "Unknown peer: @ops" rather than anything about groups.
function chat.parseInput(line)
  line = line or ""
  if line:match("^%s*$") then return { kind = "empty" } end
  local cmd, rest = line:match("^/(%S+)%s*(.*)$")
  if cmd then return { kind = "command", name = cmd:lower(), arg = rest } end
  local grp, gmsg = line:match("^@([%w_%-]+):%s*(.+)$")
  if grp and gmsg then return { kind = "group", group = grp:lower(), text = gmsg } end
  -- A target is a single token (no spaces) before the first colon, so a
  -- sentence that merely contains a colon stays a broadcast.
  local target, msg = line:match("^([^:%s]+):%s*(.+)$")
  if target and msg then return { kind = "directed", target = target, text = msg } end
  return { kind = "broadcast", text = line }
end

-- ============================================================
-- Groups (multi-operator addressing)
-- ============================================================
-- A group is a NAME for a set of peer tokens — the same tokens you would
-- type before a colon, so "@ops:" is exactly "send this to each of these
-- peers" and nothing more. Deliberately not a protocol: there is no group
-- membership on the wire, no group key, and no server. Each member gets an
-- ordinary directed message, so a group works between any peers that
-- already trust each other and needs no agreement about who "ops" is.
--
-- Stored per-MACHINE at /etc/chat-groups.cfg (admin-managed, like the other
-- /etc cfgs) rather than per-user: an operator team is a property of the
-- installation, and the announcement system routes to groups from a service
-- context where no user is logged in.

chat.GROUPS_PATH = "/etc/chat-groups.cfg"
chat.MAX_GROUPS  = 32
chat.MAX_MEMBERS = 32

--- Is this a syntactically valid group name? Pure.
--- Kept to the same character class the parser accepts, so a name that can
--- be created can always be typed.
function chat.validGroupName(name)
  return type(name) == "string" and name ~= "" and #name <= 24
    and name:match("^[%w_%-]+$") ~= nil
end

--- Normalize a decoded groups table: lowercase names, drop malformed
--- entries, de-duplicate members, apply the caps. Pure — takes and returns
--- a plain table, so the loader below is the only thing that touches disk.
function chat.normalizeGroups(raw)
  local out = {}
  if type(raw) ~= "table" then return out end
  local n = 0
  for name, members in pairs(raw) do
    if type(name) == "string" and type(members) == "table" and n < chat.MAX_GROUPS then
      local lname = name:lower()
      if chat.validGroupName(lname) then
        local list, seen = {}, {}
        for _, m in ipairs(members) do
          if type(m) == "string" and m ~= "" and not seen[m]
             and #list < chat.MAX_MEMBERS then
            seen[m] = true; list[#list + 1] = m
          end
        end
        -- An empty group is kept, not dropped: "create it, then add people"
        -- is a normal order of operations and silently losing the group
        -- between those two steps would be baffling.
        out[lname] = list
        n = n + 1
      end
    end
  end
  return out
end

--- Resolve a group's members to trusted addresses. Returns
--- (addresses, unresolved) — both arrays. Pure given `peers`.
--- Unresolved members are REPORTED rather than skipped: a group that
--- silently shrank because a peer went offline would let an operator
--- believe a message reached people it never reached.
function chat.resolveGroup(groups, name, peers, minLevel)
  local members = groups and groups[(name or ""):lower()]
  if not members then return nil end
  local addrs, missing, seen = {}, {}, {}
  for _, tok in ipairs(members) do
    local a = chat.resolveTarget(peers, tok, minLevel)
    if a and not seen[a] then seen[a] = true; addrs[#addrs + 1] = a
    elseif not a then missing[#missing + 1] = tok end
  end
  return addrs, missing
end

--- Load the group table through an injected fs (kernel.fs shape) and
--- serializer. Returns a normalized table — never nil, so callers don't
--- need an "or {}" at every use.
function chat.loadGroups(fs, serialize, path)
  path = path or chat.GROUPS_PATH
  if not (fs and serialize and fs.exists and fs.exists(path)) then return {} end
  local raw = fs.readFile(path)
  if type(raw) ~= "string" then return {} end
  local ok, parsed = pcall(serialize.decode, raw, { maxBytes = 16 * 1024 })
  if not ok then return {} end
  return chat.normalizeGroups(parsed)
end

--- Persist the group table. Normalizes first so a caller can't write
--- something loadGroups would then silently discard.
function chat.saveGroups(fs, serialize, groups, path)
  path = path or chat.GROUPS_PATH
  if not (fs and serialize) then return false, "fs/serialize unavailable" end
  return serialize.saveFile(fs, path, chat.normalizeGroups(groups))
end

--- Find a peer's address by address-prefix or exact hostname, considering
--- only peers at or above `minLevel`. Pure; returns the address or nil.
function chat.resolveTarget(peers, target, minLevel)
  if not target or target == "" then return nil end
  minLevel = minLevel or 0
  for _, p in ipairs(peers or {}) do
    if (p.level or 0) >= minLevel then
      if p.address and p.address:sub(1, #target) == target then return p.address end
      if p.hostname and p.hostname == target then return p.address end
    end
  end
  return nil
end

-- ============================================================
-- Main chat loop
-- ============================================================

--- Run the chat TUI.
-- @param kernel table: The kernel object (provides getDisplay, getEvent, getNet, etc.)
-- @param sessionToken string: Current user session token
function chat.run(kernel, sessionToken)
  local D  = kernel.getDisplay()
  local E  = kernel.getEvent()
  local NM = kernel.getNet()

  if not NM then
    -- No network module - show error and exit
    if D then
      local W, H = D.getSize()
      local T = D.getTheme()
      D.clear(T.bg)
      D.set(2, 2, "Chat unavailable: no network module", T.error, T.bg)
      D.set(2, 4, "Press any key to return.", T.dim, T.bg)
      -- Loop on pullSignal so non-key events (network packets etc.)
      -- don't dismiss the message before the user sees it
      -- (#118/#99/#101). Cap the total wait at 10s.
      local deadline = computer.uptime() + 10
      while computer.uptime() < deadline do
        local ev = computer.pullSignal(deadline - computer.uptime())
        if ev == "key_down" or not ev then break end
      end
    end
    return
  end

  local protocol = NM.getProtocol()
  local trustMgr = NM.getTrust()

  local W, H = D.getSize()
  local T    = D.getTheme()
  local hostname = NM.getHostname() or "local"

  -- Layout
  local HEADER_ROW = 1
  local MSG_TOP    = 2
  local MSG_BOT    = H - 1
  local INPUT_ROW  = H
  local MSG_H      = MSG_BOT - MSG_TOP + 1

  -- Message history (ring buffer)
  local MAX_MESSAGES = 128
  local messages = {}  -- { {text=string, color=number, time=number}, ... }

  -- Input buffer
  local inputBuf = ""

  -- Listener ID for cleanup
  local msgListenerID = nil

  -- ── Helpers ────────────────────────────────────────────

  local function formatTime(uptime)
    local h = math.floor(uptime / 3600)
    local m = math.floor((uptime % 3600) / 60)
    local s = math.floor(uptime % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
  end

  local function addMessage(text, color)
    messages[#messages + 1] = {
      text  = text,
      color = color or T.fg,
      time  = computer.uptime(),
    }
    -- Trim if we exceed the buffer
    if #messages > MAX_MESSAGES then
      local trimmed = {}
      for i = #messages - MAX_MESSAGES + 1, #messages do
        trimmed[#trimmed + 1] = messages[i]
      end
      messages = trimmed
    end
  end

  -- ── Drawing ────────────────────────────────────────────

  -- Count currently-TRUSTED peers (shown live in the header).
  local function trustedPeerCount()
    local n = 0
    for _, p in ipairs(trustMgr.listPeers()) do
      if p.level >= trustMgr.LEVEL.TRUSTED then n = n + 1 end
    end
    return n
  end

  local function drawHeader()
    D.fill(1, HEADER_ROW, W, 1, " ", T.menubar_fg, T.menubar_bg)
    local title = " TOS Chat - " .. hostname .. " "
    local help  = " peers:" .. trustedPeerCount() .. "  /help  ^Q=Exit "
    D.set(1, HEADER_ROW, title, T.menubar_fg, T.menubar_bg)
    D.set(W - #help + 1, HEADER_ROW, help, T.dim, T.menubar_bg)
  end

  local function drawMessages()
    -- Determine which messages to show (last MSG_H)
    local startIdx = math.max(1, #messages - MSG_H + 1)

    for row = 0, MSG_H - 1 do
      local y = MSG_TOP + row
      local idx = startIdx + row

      D.fill(1, y, W, 1, " ", T.fg, T.bg)

      if idx >= 1 and idx <= #messages then
        local msg = messages[idx]
        local timeStr = formatTime(msg.time)
        local prefix = timeStr .. " "
        local textW = W - #prefix
        local line = msg.text
        if #line > textW then
          line = line:sub(1, textW - 1) .. "~"
        end
        D.set(1, y, prefix, T.dim, T.bg)
        D.set(#prefix + 1, y, line, msg.color, T.bg)
      end
    end
  end

  local function drawInput()
    D.fill(1, INPUT_ROW, W, 1, " ", T.fg, T.bg)
    D.set(1, INPUT_ROW, "> ", T.highlight, T.bg)

    local maxW = W - 3
    local shown = inputBuf
    if #shown > maxW then
      shown = shown:sub(#shown - maxW + 1)
    end
    D.set(3, INPUT_ROW, shown, T.fg, T.bg)
    -- Cursor
    local cursorX = 3 + math.min(#inputBuf, maxW)
    if cursorX <= W then
      D.set(cursorX, INPUT_ROW, "_", T.highlight, T.bg)
    end
  end

  local function redraw()
    D.clear(T.bg)
    drawHeader()
    drawMessages()
    drawInput()
  end

  -- ── Incoming message handler ───────────────────────────

  local function onMessage(packet, fromAddr)
    -- #SEC M-3 — only accept chat from TRUSTED peers. Without this gate,
    -- ANY peer on the network could inject text into the chat pane and
    -- force an ACK back — both a content-spoof and a presence oracle.
    local level = (trustMgr.getLevel and trustMgr.getLevel(fromAddr)) or 0
    if level < trustMgr.LEVEL.TRUSTED then return end

    local payload = packet.payload or {}
    local text = type(payload.text) == "string" and payload.text or ""

    -- Get sender hostname from trust database
    local peer = trustMgr.getPeer(fromAddr)
    local senderName = (peer and peer.hostname) or fromAddr:sub(1, 8)

    addMessage("[" .. senderName .. "] " .. text, T.border)
    drawMessages()
    drawInput()

    -- Audio notification for incoming message. #SEC M-3 — guard the
    -- _G._TOS deref (it may be nil in minimal/headless contexts).
    if _G._TOS and _G._TOS.audio then _G._TOS.audio.chat() end

    -- Send acknowledgment
    local ack = protocol.makePacket(protocol.TYPE.MSG_ACK, {}, { to = fromAddr })
    NM.send(fromAddr, ack)
  end

  -- Register listener for MSG packets
  if E then
    msgListenerID = NM.on(protocol.TYPE.MSG, onMessage)
  end

  -- ── System message ─────────────────────────────────────

  addMessage("Chat started. Send messages to TRUSTED peers.", T.title)
  addMessage("  peer:message   to one peer (addr prefix or hostname)", T.dim)
  addMessage("  message        broadcast to all trusted peers", T.dim)
  addMessage("  /who  /mail peer text  /clear  /help   ^Q=exit", T.dim)
  addMessage("", T.dim)

  -- List available TRUSTED peers
  local peers = trustMgr.listPeers()
  local trustedCount = 0
  for _, p in ipairs(peers) do
    if p.level >= trustMgr.LEVEL.TRUSTED then
      trustedCount = trustedCount + 1
      local name = p.hostname or "?"
      local addr = p.address:sub(1, 8)
      addMessage("  " .. addr .. "  " .. name, T.highlight)
    end
  end
  if trustedCount == 0 then
    addMessage("  (no trusted peers)", T.warning)
  end

  -- ── Initial draw ───────────────────────────────────────

  redraw()

  -- ── Main input loop ────────────────────────────────────

  local running = true
  while running do
    -- MUST use E.pull() so the event system dispatches modem_message
    -- events to the net handler, which in turn calls our onMessage listener.
    -- Using computer.pullSignal() directly would bypass event dispatch
    -- and incoming chat messages would never arrive.
    local sig, _, char, code
    if E and E.pull then
      sig, _, char, code = E.pull(0.2)
    else
      sig, _, char, code = computer.pullSignal(0.2)
    end

    if sig == "key_down" then
      if char == 17 then  -- Ctrl+Q = exit
        running = false

      elseif code == 28 then  -- Enter = send message
        if inputBuf ~= "" then
          local act = chat.parseInput(inputBuf)

          if act.kind == "command" then
            local name, arg = act.name, act.arg or ""
            if name == "quit" or name == "exit" then
              running = false
            elseif name == "clear" then
              messages = {}
            elseif name == "help" or name == "?" then
              addMessage("Commands:", T.title)
              addMessage("  peer:msg          send to one peer (addr-prefix or hostname)", T.dim)
              addMessage("  msg               broadcast to all trusted peers", T.dim)
              addMessage("  /who              list trusted peers", T.dim)
              addMessage("  /mail peer text   send a store-and-forward mesh mail", T.dim)
              addMessage("  /clear  /help  ^Q exit", T.dim)
            elseif name == "who" then
              local n = 0
              for _, p in ipairs(trustMgr.listPeers()) do
                if p.level >= trustMgr.LEVEL.TRUSTED then
                  n = n + 1
                  addMessage("  " .. p.address:sub(1, 8) .. "  " .. (p.hostname or "?"), T.highlight)
                end
              end
              if n == 0 then addMessage("  (no trusted peers)", T.warning) end
            elseif name == "mail" then
              -- Bridge to mail: "/mail <peer> <text>". Unlike a chat line,
              -- this is queued + retried until it lands, even if the peer is
              -- a few hops away or briefly offline. Mail is an ADD-ON
              -- (stage 5) — the SENDER needs it installed for mailbox
              -- semantics; the transport itself is in the base kernel.
              local mp, mtext = arg:match("^(%S+)%s+(.+)$")
              local dest = mp and chat.resolveTarget(trustMgr.listPeers(), mp, trustMgr.LEVEL.TRUSTED)
              local okLib, mailLib = pcall(require, "mail")
              if not mp or not mtext then
                addMessage("Usage: /mail <peer> <message>", T.warning)
              elseif not dest then
                addMessage("Unknown peer: " .. tostring(mp), T.error)
              elseif not (okLib and type(mailLib) == "table" and mailLib.send) then
                addMessage("Mail add-on not installed (pkg install mail).", T.error)
              else
                local id, sealed = mailLib.send({ to = dest, fromUser = hostname,
                  subject = "(via chat)", body = mtext })
                if id then
                  addMessage("Mail queued to " .. mp .. (sealed and "" or " (plaintext)"), T.title)
                else
                  addMessage("Mail failed: " .. tostring(sealed), T.error)
                end
              end
            else
              addMessage("Unknown command: /" .. name .. "  (try /help)", T.warning)
            end

          elseif act.kind == "directed" then
            local destAddr = chat.resolveTarget(trustMgr.listPeers(), act.target, trustMgr.LEVEL.TRUSTED)
            if destAddr then
              local ok, err = NM.sendMessage(destAddr, act.text)
              if ok then addMessage("[" .. hostname .. "] " .. act.text, T.title)
              else addMessage("Send failed: " .. tostring(err), T.error) end
            else
              addMessage("Unknown peer: " .. act.target, T.error)
            end

          elseif act.kind == "broadcast" then
            local sent = 0
            for _, p in ipairs(trustMgr.listPeers()) do
              if p.level >= trustMgr.LEVEL.TRUSTED then
                NM.sendMessage(p.address, act.text)
                sent = sent + 1
              end
            end
            if sent > 0 then addMessage("[" .. hostname .. "] " .. act.text, T.title)
            else addMessage("No trusted peers to send to.", T.warning) end
          end

          inputBuf = ""
          redraw()
        end
        drawInput()

      elseif code == 14 then  -- Backspace
        if #inputBuf > 0 then
          inputBuf = inputBuf:sub(1, -2)
          drawInput()
        end

      elseif char and char >= 32 and char < 127 then
        inputBuf = inputBuf .. string.char(char)
        drawInput()
      end

    elseif sig == "clipboard" then
      -- Handle paste (OC clipboard signal)
      local pastedText = char
      if type(pastedText) == "string" then
        inputBuf = inputBuf .. pastedText:gsub("\n", "")
        drawInput()
      end

    elseif sig == "tos_focus" then
      -- Redraw when we regain focus (e.g. from task switcher)
      redraw()
    end
  end

  -- ── Cleanup ────────────────────────────────────────────

  -- Remove our message listener via net.off()
  if msgListenerID and NM.off then
    NM.off(protocol.TYPE.MSG, msgListenerID)
  end

  addMessage("Chat ended.", T.dim)
end

return chat
