-- TOS Shell Extensions (lazy-loaded)
-- Commands here are loaded on-demand by panels.lua for: net, ping, hostname, device, config, battery, audio
local computer=require("computer")
local X={}

-- Helper: get current username and tier from session token
local function getActor(ctx)
  local U = ctx.U
  if U and ctx.st then
    local s = U.getSession(ctx.st)
    if s then return s.user, s.tier end
  end
  return "unknown", 0
end

function X.hostname(a,ctx)
  local SC=ctx.K.getConfig() if not SC then ctx.o("No config",0xFF0000) return end
  if a[1] then SC.set("hostname",a[1]) SC.save() end
  ctx.o(SC.get("hostname") or "?")
end

function X.device(a,ctx)
  local SC=ctx.K.getConfig() if not SC then ctx.o("?") return end
  ctx.o("Device: "..SC.deviceType().." | Host: "..(SC.get("hostname") or "?"))
end

function X.config(a,ctx)
  local SC=ctx.K.getConfig() if not SC then ctx.o("No config",0xFF0000) return end
  for k,v in pairs(SC.getAll()) do ctx.o(" "..k.." = "..tostring(v),0xC0C0C0) end
end

function X.battery(a,ctx)
  local pm=ctx.K.getPower()
  if pm then ctx.o(pm.statusString()) else ctx.o("N/A") end
end

function X.net(a,ctx)
  local NM=ctx.K.getNet() if not NM then ctx.o("No network",0xFF0000) return end
  if not a[1] then ctx.o("net status|discover|peers|trust|block|send",0xFFFF00) return end
  local s=a[1]
  if s=="status" then
    local i=NM.status()
    ctx.o("Host: "..(i.hostname or "?"))
    ctx.o("Addr: "..(i.address or "?"))
    local modemCount = NM.modemCount and NM.modemCount() or (i.hasModem and 1 or 0)
    ctx.o("Modem: "..(i.hasModem and "Yes" or "No")..
      (modemCount > 1 and (" (x"..modemCount..")") or "")..
      (i.hasTunnel and " + Tunnel" or ""))
    ctx.o("Encrypted: "..(i.encrypted and "Yes" or "No"))
    local p=i.peers or {}
    local total=(p.unknown or 0)+(p.known or 0)+(p.trusted or 0)+(p.blocked or 0)
    ctx.o("Peers: "..total.." (trusted:".. (p.trusted or 0).." known:"..(p.known or 0).." blocked:"..(p.blocked or 0)..")")
  elseif s=="discover" or s=="scan" then
    ctx.o("Scanning...", 0xFFFF00)
    if NM.scan then
      local found = NM.scan(3)
      ctx.o(#found .. " peer(s) responded.", 0x00FF00)
    else
      NM.discover()
      ctx.o("Discovery broadcast sent.", 0x00FF00)
    end
  elseif s=="peers" or s=="list" then
    -- Show discovered peers (phase 8) merged with trust data
    local peers = NM.peers and NM.peers() or {}
    if #peers > 0 then
      ctx.o(string.format(" %-8s %-4s %-8s %s", "Addr", "Trst", "Device", "Host"), 0xAAAAAA)
      for _, p in ipairs(peers) do
        local lvl = p.trust or 0
        local lbl = ({"BLK","UNK","KNW","TRS"})[lvl + 2] or "?"
        local addr = tostring(p.addr or "?")
        ctx.o(string.format(" %s %-4s %-8s %s",
          addr:sub(1,8), lbl,
          p.device or "?", p.hostname or ""))
      end
    else
      -- Fallback to trust manager listing
      local tm = NM.getTrust()
      for _, p in ipairs(tm.listPeers()) do
        local addr = tostring(p.address or "?")
        ctx.o(string.format(" %s T%d %s", addr:sub(1,8), p.level, p.hostname or ""))
      end
    end
    if #peers == 0 then ctx.o("  No peers discovered. Run 'net scan' first.", 0xAAAAAA) end
  elseif s=="trust" and a[2] then
    local tm=NM.getTrust()
    local actor, tier = getActor(ctx)
    local ok2, err2
    if a[3]=="full" then ok2, err2 = tm.trustFull(actor, a[2], tier)
    else ok2, err2 = tm.trustKnown(actor, a[2], tier) end
    if ok2 then ctx.o("Trust updated.",0x00FF00)
    else ctx.o(err2 or "Trust update failed",0xFF0000) end
  elseif s=="block" and a[2] then
    local actor, tier = getActor(ctx)
    local ok2, err2 = NM.getTrust().block(actor, a[2], tier)
    if ok2 then ctx.o("Blocked.",0x00FF00)
    else ctx.o(err2 or "Block failed",0xFF0000) end
  elseif s=="send" and a[2] and a[3] then
    NM.sendMessage(a[2],table.concat(a," ",3)) ctx.o("Sent.",0x00FF00)
  else ctx.o("Unknown: net "..s,0xFF0000) end
end

function X.ping(a,ctx)
  local NM=ctx.K.getNet() if not NM then ctx.o("No network",0xFF0000) return end
  if a[1] then NM.send(a[1],{type="PING"}) else NM.discover() end
  ctx.o("Ping sent.",0x00FF00)
end

function X.audio(a,ctx)
  local A=_G._TOS and _G._TOS.audio
  if not A then ctx.o("Audio module not available.",0xFF0000) return end
  local s=a[1]
  if not s then
    ctx.o("Audio: "..(A.isEnabled() and "ON" or "OFF").."  Volume: "..string.format("%.0f%%",A.getVolume()*100),0xFFFF00)
    ctx.o("  audio on|off         Enable/disable audio",0xAAAAAA)
    ctx.o("  audio volume <0-100> Set volume level",0xAAAAAA)
    ctx.o("  audio test           Play all beep codes",0xAAAAAA)
    return
  end
  if s=="on" then
    A.setEnabled(true)
    local SC=ctx.K.getConfig()
    if SC then SC.set("audio",true) SC.save() end
    A.success()
    ctx.o("Audio enabled.",0x00FF00)
  elseif s=="off" then
    A.setEnabled(false)
    local SC=ctx.K.getConfig()
    if SC then SC.set("audio",false) SC.save() end
    ctx.o("Audio disabled.",0xAAAAAA)
  elseif s=="volume" or s=="vol" then
    local v=tonumber(a[2])
    if not v then ctx.o("Usage: audio volume <0-100>",0xAAAAAA) return end
    v = math.max(0, math.min(100, v))
    A.setVolume(v/100)
    local SC=ctx.K.getConfig()
    if SC then SC.set("audioVolume",v/100) SC.save() end
    A.success()
    ctx.o("Volume: "..string.format("%.0f%%",A.getVolume()*100),0x00FF00)
  elseif s=="test" then
    ctx.o("Testing beep codes...",0xFFFF00)
    ctx.o("  success (1 beep):",0xAAAAAA) A.success() computer.pullSignal(0.3)
    ctx.o("  confirm (2 ascending):",0xAAAAAA) A.confirm() computer.pullSignal(0.3)
    ctx.o("  warning (2 beeps):",0xAAAAAA) A.warning() computer.pullSignal(0.3)
    ctx.o("  error (1 long low):",0xAAAAAA) A.error() computer.pullSignal(0.3)
    ctx.o("  critical (3 low):",0xAAAAAA) A.critical() computer.pullSignal(0.3)
    ctx.o("  notify (1 quick high):",0xAAAAAA) A.notify() computer.pullSignal(0.3)
    ctx.o("  chat (2-tone chime):",0xAAAAAA) A.chat() computer.pullSignal(0.3)
    ctx.o("  shutdown (2 descending):",0xAAAAAA) A.shutdown() computer.pullSignal(0.3)
    ctx.o("  boot complete (3 ascending):",0xAAAAAA) A.bootComplete() computer.pullSignal(0.3)
    ctx.o("Test complete.",0x00FF00)
  else
    ctx.o("Unknown: audio "..s,0xFF0000)
    ctx.o("Usage: audio [on|off|volume|test]",0xAAAAAA)
  end
end

return X
