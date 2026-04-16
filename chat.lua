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
      computer.pullSignal(10)
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

  local function drawHeader()
    D.fill(1, HEADER_ROW, W, 1, " ", T.menubar_fg, T.menubar_bg)
    local title = " TOS Chat - " .. hostname .. " "
    local help  = " ^Q=Exit "
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
    local payload = packet.payload or {}
    local text = payload.text or ""

    -- Get sender hostname from trust database
    local peer = trustMgr.getPeer(fromAddr)
    local senderName = (peer and peer.hostname) or fromAddr:sub(1, 8)

    addMessage("[" .. senderName .. "] " .. text, T.border)
    drawMessages()
    drawInput()

    -- Audio notification for incoming message
    if _G._TOS.audio then _G._TOS.audio.chat() end

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
  addMessage("Type an address prefix or hostname, then a colon, then your message.", T.dim)
  addMessage("  Example: abc12345:Hello there!", T.dim)
  addMessage("  Or:      myserver:Hello there!", T.dim)
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
          -- Parse "target:message" format
          local target, msgText = inputBuf:match("^([^:]+):(.+)$")

          if target and msgText then
            -- Resolve target: try as address prefix or hostname
            local destAddr = nil

            for _, p in ipairs(trustMgr.listPeers()) do
              if p.level >= trustMgr.LEVEL.TRUSTED then
                if p.address:sub(1, #target) == target then
                  destAddr = p.address
                  break
                end
                if p.hostname and p.hostname == target then
                  destAddr = p.address
                  break
                end
              end
            end

            if destAddr then
              local ok, err = NM.sendMessage(destAddr, msgText)
              if ok then
                addMessage("[" .. hostname .. "] " .. msgText, T.title)
              else
                addMessage("Send failed: " .. tostring(err), T.error)
              end
            else
              addMessage("Unknown peer: " .. target, T.error)
            end
          else
            -- No target specified - broadcast to all trusted peers
            local sent = 0
            for _, p in ipairs(trustMgr.listPeers()) do
              if p.level >= trustMgr.LEVEL.TRUSTED then
                NM.sendMessage(p.address, inputBuf)
                sent = sent + 1
              end
            end
            if sent > 0 then
              addMessage("[" .. hostname .. "] " .. inputBuf, T.title)
            else
              addMessage("No trusted peers to send to.", T.warning)
            end
          end

          inputBuf = ""
          drawMessages()
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
