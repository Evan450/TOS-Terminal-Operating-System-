local computer = require("computer")

local chat = {}

function chat.parseInput(line)
  line = line or ""
  if line:match("^%s*$") then return { kind = "empty" } end
  local cmd, rest = line:match("^/(%S+)%s*(.*)$")
  if cmd then return { kind = "command", name = cmd:lower(), arg = rest } end
  local grp, gmsg = line:match("^@([%w_%-]+):%s*(.+)$")
  if grp and gmsg then return { kind = "group", group = grp:lower(), text = gmsg } end

  local target, msg = line:match("^([^:%s]+):%s*(.+)$")
  if target and msg then return { kind = "directed", target = target, text = msg } end
  return { kind = "broadcast", text = line }
end

chat.GROUPS_PATH = "/etc/chat-groups.cfg"
chat.MAX_GROUPS  = 32
chat.MAX_MEMBERS = 32

function chat.validGroupName(name)
  return type(name) == "string" and name ~= "" and #name <= 24
    and name:match("^[%w_%-]+$") ~= nil
end

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

        out[lname] = list
        n = n + 1
      end
    end
  end
  return out
end

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

function chat.loadGroups(fs, serialize, path)
  path = path or chat.GROUPS_PATH
  if not (fs and serialize and fs.exists and fs.exists(path)) then return {} end
  local raw = fs.readFile(path)
  if type(raw) ~= "string" then return {} end
  local ok, parsed = pcall(serialize.decode, raw, { maxBytes = 16 * 1024 })
  if not ok then return {} end
  return chat.normalizeGroups(parsed)
end

function chat.saveGroups(fs, serialize, groups, path)
  path = path or chat.GROUPS_PATH
  if not (fs and serialize) then return false, "fs/serialize unavailable" end
  return serialize.saveFile(fs, path, chat.normalizeGroups(groups))
end

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

function chat.run(kernel, sessionToken)
  local D  = kernel.getDisplay()
  local E  = kernel.getEvent()
  local NM = kernel.getNet()

  if not NM then

    if D then
      local W, H = D.getSize()
      local T = D.getTheme()
      D.clear(T.bg)
      D.set(2, 2, "Chat unavailable: no network module", T.error, T.bg)
      D.set(2, 4, "Press any key to return.", T.dim, T.bg)

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

  local HEADER_ROW = 1
  local MSG_TOP    = 2
  local MSG_BOT    = H - 1
  local INPUT_ROW  = H
  local MSG_H      = MSG_BOT - MSG_TOP + 1

  local MAX_MESSAGES = 128
  local messages = {}

  local inputBuf = ""

  local msgListenerID = nil

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

    if #messages > MAX_MESSAGES then
      local trimmed = {}
      for i = #messages - MAX_MESSAGES + 1, #messages do
        trimmed[#trimmed + 1] = messages[i]
      end
      messages = trimmed
    end
  end

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

  local function onMessage(packet, fromAddr)

    local level = (trustMgr.getLevel and trustMgr.getLevel(fromAddr)) or 0
    if level < trustMgr.LEVEL.TRUSTED then return end

    local payload = packet.payload or {}
    local text = type(payload.text) == "string" and payload.text or ""

    local peer = trustMgr.getPeer(fromAddr)
    local senderName = (peer and peer.hostname) or fromAddr:sub(1, 8)

    addMessage("[" .. senderName .. "] " .. text, T.border)
    drawMessages()
    drawInput()

    if _G._TOS and _G._TOS.audio then _G._TOS.audio.chat() end

    local ack = protocol.makePacket(protocol.TYPE.MSG_ACK, {}, { to = fromAddr })
    NM.send(fromAddr, ack)
  end

  if E then
    msgListenerID = NM.on(protocol.TYPE.MSG, onMessage)
  end

  addMessage("Chat started. Send messages to TRUSTED peers.", T.title)
  addMessage("  peer:message   to one peer (addr prefix or hostname)", T.dim)
  addMessage("  message        broadcast to all trusted peers", T.dim)
  addMessage("  /who  /mail peer text  /clear  /help   ^Q=exit", T.dim)
  addMessage("", T.dim)

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

  redraw()

  local running = true
  while running do

    local sig, _, char, code
    if E and E.pull then
      sig, _, char, code = E.pull(0.2)
    else
      sig, _, char, code = computer.pullSignal(0.2)
    end

    if sig == "key_down" then
      if char == 17 then
        running = false

      elseif code == 28 then
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

      elseif code == 14 then
        if #inputBuf > 0 then
          inputBuf = inputBuf:sub(1, -2)
          drawInput()
        end

      elseif char and char >= 32 and char < 127 then
        inputBuf = inputBuf .. string.char(char)
        drawInput()
      end

    elseif sig == "clipboard" then

      local pastedText = char
      if type(pastedText) == "string" then
        inputBuf = inputBuf .. pastedText:gsub("\n", "")
        drawInput()
      end

    elseif sig == "tos_focus" then

      redraw()
    end
  end

  if msgListenerID and NM.off then
    NM.off(protocol.TYPE.MSG, msgListenerID)
  end

  addMessage("Chat ended.", T.dim)
end

return chat
