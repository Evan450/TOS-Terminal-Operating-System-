local computer = require("computer")
local ui       = require("shell.panels.ui")
local tabsMod  = require("shell.panels.tabs")
local chatCore = require("shell.chat")

local M = {}

local MAX_MESSAGES = 128

function M.label(unread)
  if (unread or 0) > 0 then return "Chat(" .. unread .. ")" end
  return "Chat"
end

function M.addMessage(tab, text, color)
  local msgs = tab.messages
  msgs[#msgs + 1] = { text = text, color = color,
    time = computer.uptime and computer.uptime() or 0 }
  if #msgs > MAX_MESSAGES then
    local trimmed = {}
    for i = #msgs - MAX_MESSAGES + 1, #msgs do trimmed[#trimmed + 1] = msgs[i] end
    tab.messages = trimmed
  end
end

local function fmtTime(t)
  t = math.floor(t or 0)
  return string.format("%02d:%02d:%02d",
    math.floor(t / 3600), math.floor((t % 3600) / 60), t % 60)
end

local function trustedPeers(trustMgr)
  local out = {}
  for _, p in ipairs((trustMgr and trustMgr.listPeers and trustMgr.listPeers()) or {}) do
    if (p.level or 0) >= ((trustMgr.LEVEL and trustMgr.LEVEL.TRUSTED) or 2) then
      out[#out + 1] = p
    end
  end
  return out
end

local function groupIO()
  local okF, fsMod = pcall(require, "kernel.fs")
  local okS, ser   = pcall(require, "kernel.serialize")
  if okF and okS then return fsMod, ser end
end
local function loadGroups()
  local fsMod, ser = groupIO()
  return chatCore.loadGroups(fsMod, ser)
end
local function saveGroups(groups)
  local fsMod, ser = groupIO()
  if not fsMod then return false, "filesystem unavailable" end
  return chatCore.saveGroups(fsMod, ser, groups)
end

function M.open(S)
  local idx = tabsMod.find(S, "chat")
  if idx then
    local tab = S.tabs[idx]
    S.activeTab = idx
    return tab
  end
  local tab = tabsMod.create(S, "chat", "Chat",
    { messages = {}, input = "", unread = 0, scroll = 0,
      live = true, interval = 0.3 })
  local T = S.T
  local NM = S.NM

  if not NM then
    M.addMessage(tab, "Chat unavailable: no network module.", T.error)
    return tab
  end

  M.addMessage(tab, "Chat started. Send messages to TRUSTED peers.", T.title)
  M.addMessage(tab, "  peer:message   to one peer (addr prefix or hostname)", T.dim)
  M.addMessage(tab, "  message        broadcast to all trusted peers", T.dim)
  M.addMessage(tab, "  /who  /mail peer text  /clear  /help   ^Q closes the tab", T.dim)
  M.addMessage(tab, "", T.dim)
  local peers = trustedPeers(NM.getTrust and NM.getTrust())
  for _, p in ipairs(peers) do
    M.addMessage(tab, "  " .. tostring(p.address):sub(1, 8) .. "  "
      .. (p.hostname or "?"), T.highlight)
  end
  if #peers == 0 then M.addMessage(tab, "  (no trusted peers)", T.warning) end

  local protocol = NM.getProtocol and NM.getProtocol()
  local trustMgr = NM.getTrust and NM.getTrust()
  if protocol and trustMgr and NM.on then
    tab._listenerId = NM.on(protocol.TYPE.MSG, function(packet, fromAddr)
      local level = (trustMgr.getLevel and trustMgr.getLevel(fromAddr)) or 0
      if level < trustMgr.LEVEL.TRUSTED then return end
      local payload = packet.payload or {}
      local text = type(payload.text) == "string" and payload.text or ""
      local peer = trustMgr.getPeer and trustMgr.getPeer(fromAddr)
      local sender = (peer and peer.hostname) or tostring(fromAddr):sub(1, 8)
      M.addMessage(tab, "[" .. sender .. "] " .. text, S.T.border)
      tab._dirty = true
      if S.tabs[S.activeTab] ~= tab then
        tab.unread = (tab.unread or 0) + 1
        tab.label = M.label(tab.unread)
      end
      if _G._TOS and _G._TOS.audio then pcall(_G._TOS.audio.chat) end
      if NM.send and protocol.makePacket then
        pcall(function()
          NM.send(fromAddr, protocol.makePacket(protocol.TYPE.MSG_ACK, {},
            { to = fromAddr }))
        end)
      end
    end)
  end
  return tab
end

function M.onClose(S, tab)
  local NM = S.NM
  if tab._listenerId and NM and NM.off and NM.getProtocol then
    local protocol = NM.getProtocol()
    if protocol then pcall(NM.off, protocol.TYPE.MSG, tab._listenerId) end
    tab._listenerId = nil
  end
end

function M.draw(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  D.fill(1, 2, W, H - 1, " ", T.fg, T.bg)

  local hostname = (S.NM and S.NM.getHostname and S.NM.getHostname()) or "local"
  local peers = #trustedPeers(S.NM and S.NM.getTrust and S.NM.getTrust())
  ui.drawRail(D, T, 2, W, {
    { label = "§ Chat — " .. hostname },
    { text = "peers:" .. peers },
  }, { labelFg = T.title or T.fg })

  local msgTop, msgBot = 3, H - 2
  local msgH = msgBot - msgTop + 1
  local msgs = tab.messages or {}
  local maxScroll = math.max(0, #msgs - msgH)
  if (tab.scroll or 0) > maxScroll then tab.scroll = maxScroll end
  local startIdx = math.max(1, #msgs - msgH + 1 - (tab.scroll or 0))
  for row = 0, msgH - 1 do
    local m = msgs[startIdx + row]
    if m then
      local y = msgTop + row
      local prefix = fmtTime(m.time) .. " "
      D.set(1, y, prefix, T.dim, T.bg)
      local textW = W - #prefix
      local line = m.text
      if #line > textW then line = line:sub(1, math.max(1, textW - 1)) .. "~" end
      D.set(#prefix + 1, y, line, m.color or T.fg, T.bg)
    end
  end

  D.set(1, H - 1, "> ", T.highlight, T.bg)
  local maxW = W - 3
  local shown = tab.input or ""
  if #shown > maxW then shown = shown:sub(#shown - maxW + 1) end
  D.set(3, H - 1, shown .. "_", T.fg, T.bg)

  ui.drawRampBar(D, T, H, W,
    "Enter Send · peer:msg Direct · /help · PgUp/Dn Scroll · ^Q Close",
    nil, T.statusbar_fg or T.bar_fg, T.statusbar_bg or T.bar_bg)

  tab.unread = 0
  tab.label = M.label(0)
  tab._dirty = false
end

local function doSend(S, tab)
  local T, NM = S.T, S.NM
  local line = tab.input or ""
  tab.input = ""
  local act = chatCore.parseInput(line)
  if act.kind == "empty" then return end
  if not NM then M.addMessage(tab, "No network.", T.error); return end
  local trustMgr = NM.getTrust and NM.getTrust()
  local hostname = (NM.getHostname and NM.getHostname()) or "local"

  if act.kind == "command" then
    local name, arg = act.name, act.arg or ""
    if name == "quit" or name == "exit" then
      tabsMod.close(S)
    elseif name == "clear" then
      tab.messages = {}
    elseif name == "help" or name == "?" then
      M.addMessage(tab, "Commands:", T.title)
      M.addMessage(tab, "  peer:msg          send to one peer (addr-prefix or hostname)", T.dim)
      M.addMessage(tab, "  @group:msg        send to everyone in a group", T.dim)
      M.addMessage(tab, "  msg               broadcast to all trusted peers", T.dim)
      M.addMessage(tab, "  /who              list trusted peers", T.dim)
      M.addMessage(tab, "  /group            list groups (new/add/rm/del to edit)", T.dim)
      M.addMessage(tab, "  /mail peer text   send a store-and-forward mesh mail", T.dim)
      M.addMessage(tab, "  /clear  /help  ^Q closes the tab", T.dim)

    elseif name == "group" then

      local verb, gargs = arg:match("^(%S*)%s*(.*)$")
      verb = (verb or ""):lower()
      local gname, members = gargs:match("^(%S*)%s*(.*)$")
      local groups = loadGroups()

      local function memberList()
        local out = {}
        for tok in (members or ""):gmatch("%S+") do out[#out + 1] = tok end
        return out
      end
      local function persist(msg)
        local ok, err = saveGroups(groups)
        if ok then M.addMessage(tab, msg, T.title)
        else M.addMessage(tab, "Could not save groups: " .. tostring(err), T.error) end
      end

      if verb == "" or verb == "list" then
        local names = {}
        for n in pairs(groups) do names[#names + 1] = n end
        table.sort(names)
        if #names == 0 then
          M.addMessage(tab, "No groups yet.  /group new <name> <peer...>", T.warning)
        else
          for _, n in ipairs(names) do
            local mem = groups[n]
            M.addMessage(tab, "  @" .. n .. "  (" .. #mem .. ")  "
              .. table.concat(mem, " "), T.highlight)
          end
          M.addMessage(tab, "Send to one with  @<name>: your message", T.dim)
        end

      elseif not chatCore.validGroupName(gname or "") then
        M.addMessage(tab, "Group names are letters, digits, _ and - (max 24).", T.error)

      elseif verb == "new" then
        if groups[gname:lower()] then
          M.addMessage(tab, "@" .. gname:lower() .. " already exists.", T.warning)
        else
          groups[gname:lower()] = memberList()
          persist("Created @" .. gname:lower() .. ".")
        end

      elseif verb == "add" or verb == "rm" or verb == "remove" then
        local g = groups[gname:lower()]
        if not g then
          M.addMessage(tab, "No such group: @" .. gname:lower(), T.error)
        else
          local toks = memberList()
          if #toks == 0 then
            M.addMessage(tab, "Usage: /group " .. verb .. " <name> <peer...>", T.warning)
          else
            local changed = 0
            for _, tok in ipairs(toks) do
              if verb == "add" then
                local dup = false
                for _, m in ipairs(g) do if m == tok then dup = true end end
                if not dup then g[#g + 1] = tok; changed = changed + 1 end
              else
                for i = #g, 1, -1 do
                  if g[i] == tok then table.remove(g, i); changed = changed + 1 end
                end
              end
            end
            persist(string.format("@%s: %d member(s) %s.", gname:lower(), changed,
              verb == "add" and "added" or "removed"))
          end
        end

      elseif verb == "del" or verb == "delete" then
        if not groups[gname:lower()] then
          M.addMessage(tab, "No such group: @" .. gname:lower(), T.error)
        else
          groups[gname:lower()] = nil
          persist("Deleted @" .. gname:lower() .. ".")
        end

      else
        M.addMessage(tab, "Usage: /group [list|new|add|rm|del] ...", T.warning)
      end

    elseif name == "who" then
      local peers = trustedPeers(trustMgr)
      for _, p in ipairs(peers) do
        M.addMessage(tab, "  " .. tostring(p.address):sub(1, 8) .. "  "
          .. (p.hostname or "?"), T.highlight)
      end
      if #peers == 0 then M.addMessage(tab, "  (no trusted peers)", T.warning) end
    elseif name == "mail" then

      local mp, mtext = arg:match("^(%S+)%s+(.+)$")
      local dest = mp and trustMgr and chatCore.resolveTarget(
        trustMgr.listPeers(), mp, trustMgr.LEVEL.TRUSTED)
      local okLib, mailLib = pcall(require, "mail")
      if not mp or not mtext then
        M.addMessage(tab, "Usage: /mail <peer> <message>", T.warning)
      elseif not dest then
        M.addMessage(tab, "Unknown peer: " .. tostring(mp), T.error)
      elseif not (okLib and type(mailLib) == "table" and mailLib.send) then
        M.addMessage(tab, "Mail add-on not installed (pkg install mail).", T.error)
      else
        local id, sealed = mailLib.send({ to = dest, fromUser = hostname,
          subject = "(via chat)", body = mtext })
        if id then
          M.addMessage(tab, "Mail queued to " .. mp
            .. (sealed and "" or " (plaintext)"), T.title)
        else
          M.addMessage(tab, "Mail failed: " .. tostring(sealed), T.error)
        end
      end
    else
      M.addMessage(tab, "Unknown command: /" .. name .. "  (try /help)", T.warning)
    end

  elseif act.kind == "group" then

    local groups = loadGroups()
    local addrs, missing = chatCore.resolveGroup(groups, act.group,
      (trustMgr and trustMgr.listPeers()) or {},
      trustMgr and trustMgr.LEVEL.TRUSTED or 2)
    if not addrs then
      M.addMessage(tab, "No such group: @" .. act.group .. "  (/group to list)", T.error)
    elseif #addrs == 0 then
      M.addMessage(tab, "@" .. act.group .. " has nobody reachable right now.", T.warning)
      for _, m in ipairs(missing) do
        M.addMessage(tab, "  unreachable: " .. m, T.dim)
      end
    else
      local sent = 0
      for _, a in ipairs(addrs) do
        if NM.sendMessage(a, "@" .. act.group .. " " .. act.text) then sent = sent + 1 end
      end
      M.addMessage(tab, "[" .. hostname .. " -> @" .. act.group .. "] " .. act.text, T.title)
      if sent < #addrs or #missing > 0 then
        M.addMessage(tab, string.format("  delivered to %d of %d member(s)",
          sent, #addrs + #missing), T.warning)
        for _, m in ipairs(missing) do
          M.addMessage(tab, "  unreachable: " .. m, T.dim)
        end
      end
    end

  elseif act.kind == "directed" then
    local destAddr = trustMgr and chatCore.resolveTarget(
      trustMgr.listPeers(), act.target, trustMgr.LEVEL.TRUSTED)
    if destAddr then
      local ok, err = NM.sendMessage(destAddr, act.text)
      if ok then M.addMessage(tab, "[" .. hostname .. "] " .. act.text, T.title)
      else M.addMessage(tab, "Send failed: " .. tostring(err), T.error) end
    else
      M.addMessage(tab, "Unknown peer: " .. act.target, T.error)
    end

  else
    local peers = trustedPeers(trustMgr)
    if #peers == 0 then
      M.addMessage(tab, "No trusted peers to send to.", T.warning)
    else

      local sent, firstErr = 0, nil
      for _, p in ipairs(peers) do
        local ok, err = NM.sendMessage(p.address, act.text)
        if ok then sent = sent + 1
        elseif not firstErr then firstErr = err end
      end
      if sent > 0 then
        M.addMessage(tab, "[" .. hostname .. "] " .. act.text, T.title)
      end
      if sent < #peers then
        M.addMessage(tab, string.format("  delivered to %d of %d peer(s)",
          sent, #peers), T.warning)
        if firstErr then
          M.addMessage(tab, "  " .. tostring(firstErr), T.error)

          if tostring(firstErr):find("shared secret", 1, true) then
            M.addMessage(tab, "  run: net trust gen <addr>   (as admin)", T.dim)
          end
        end
      end
    end
  end
end

function M.handleKey(S, tab, ch, co, deps)
  if ch == 17 then
    tabsMod.close(S)
    return 3
  elseif co == 28 then
    doSend(S, tab)
    tab.scroll = 0
    return 3
  elseif co == 14 then
    if #(tab.input or "") > 0 then tab.input = tab.input:sub(1, -2) end
    return 3
  elseif co == 201 then
    tab.scroll = (tab.scroll or 0) + math.max(1, S.H - 5)
    return 3
  elseif co == 209 then
    tab.scroll = math.max(0, (tab.scroll or 0) - math.max(1, S.H - 5))
    return 3
  elseif ch and ch >= 32 and ch < 127 then
    if #(tab.input or "") < 200 then
      tab.input = (tab.input or "") .. string.char(ch)
    end
    return 3
  end
  return 0
end

function M.handleScroll(S, tab, ev)
  local dir = (ev.dir or 0) > 0 and 1 or -1
  local newScroll = math.max(0, (tab.scroll or 0) + dir * 2)
  if newScroll == tab.scroll then return 0 end
  tab.scroll = newScroll
  return 3
end

local ANN_COLOR = { critical = "error", alert = "error",
                    warn = "warning", notice = "highlight", info = "dim" }

local function drainAnnouncements(S, tab)
  local okI, ic = pcall(require, "intercom")
  if not (okI and type(ic) == "table" and ic.since) then return false end
  local T = S.T

  if tab._annSeen == nil then
    local okH, high = pcall(ic.highWater)
    tab._annSeen = (okH and high) or 0
    return false
  end
  local okS, list, high = pcall(ic.since, tab._annSeen)
  if not okS or type(list) ~= "table" then return false end
  if #list == 0 then return false end
  tab._annSeen = high
  for _, ann in ipairs(list) do
    M.addMessage(tab, "*** " .. ic.formatLine(ann),
      T[ANN_COLOR[ann.severity or "info"] or "dim"] or T.fg)
  end
  return true
end

function M.tick(S, tab)
  local newAnn = drainAnnouncements(S, tab)
  if tab._dirty or newAnn then return 3 end
  return 0
end

return M
