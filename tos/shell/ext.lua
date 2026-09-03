-- TOS Shell Extensions (lazy-loaded)
-- Commands here are loaded on-demand by panels.lua for: net, ping, hostname, config, battery, audio
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

-- (v1.4.0 consolidation: `device` folded in — one identity command.
-- No args: show device type + hostname; with an arg: set the hostname.)
function X.hostname(a,ctx)
  local SC=ctx.K.getConfig() if not SC then ctx.o("No config",0xFF0000) return end
  if a[1] then SC.set("hostname",a[1]) SC.save() end
  ctx.o("Device: "..SC.deviceType().." | Host: "..(SC.get("hostname") or "?"))
end

function X.config(a,ctx)
  local SC=ctx.K.getConfig() if not SC then ctx.o("No config",0xFF0000) return end
  for k,v in pairs(SC.getAll()) do ctx.o(" "..k.." = "..tostring(v),0xC0C0C0) end
end

-- kernel.power loads on EVERY machine, not just tablets, but statusString()
-- deliberately returns nil off a battery ("don't show it on computers" — see
-- kernel/power.lua). Handing that nil straight to ctx.o printed the literal
-- word "nil" as the answer to `battery` on every desktop, which is the common
-- case. kernel/diag.lua already branches on the nil; this now agrees with it.
-- (test_ext_battery.lua)
function X.battery(a,ctx)
  local pm=ctx.K.getPower()
  if not pm then ctx.o("N/A") return end
  local s=pm.statusString()
  if s then ctx.o(s) else ctx.o("AC power (no battery on this device)") end
end

-- #NET-3 — remember the last `net scan` result so subsequent
-- commands can refer to a peer by its index in that list rather
-- than its 36-char UUID. Shared across all X.net invocations in
-- this process.
local _lastScan = nil  -- array of { addr, hostname, device, trust }

-- Pretty-print a peer addr: prefer alias, fall back to short UUID.
local function fmtAddr(addr)
  local A = _G._TOS and _G._TOS.net and _G._TOS.net.aliases
  if A and A.format then return A.format(addr) end
  if type(addr) ~= "string" then return "?" end
  return addr:sub(1, 8) .. "..."
end

-- Resolve a user-supplied identifier (alias / full uuid / scan-index)
-- to a full address. Falls through to the raw string when no helper
-- resolves it, so the existing trust APIs can still reject it.
local function resolvePeer(s)
  if type(s) ~= "string" or s == "" then return s end
  -- Scan-index form: a bare integer references the last scan's nth peer.
  local n = tonumber(s)
  if n and _lastScan and _lastScan[n] then return _lastScan[n].addr end
  local A = _G._TOS and _G._TOS.net and _G._TOS.net.aliases
  if A and A.resolve then
    local addr = A.resolve(s)
    if addr then return addr end
  end
  return s
end

function X.net(a,ctx)
  local NM=ctx.K.getNet() if not NM then ctx.o("No network",0xFF0000) return end
  if not a[1] then
    ctx.o("net <subcommand>",0xFFFF00)
    ctx.o("  status                       Show network state",0xAAAAAA)
    ctx.o("  discover (or scan)           Broadcast ping",0xAAAAAA)
    ctx.o("  peers                        List discovered peers",0xAAAAAA)
    ctx.o("  servers                      Discovered hosts w/ device + last-seen",0xAAAAAA)
    ctx.o("  trust <peer> [full]          Elevate peer to KNOWN / TRUSTED",0xAAAAAA)
    ctx.o("  trust gen <peer>             Generate shared secret (admin)",0xAAAAAA)
    ctx.o("  trust setSecret <peer> <hex> Mirror a secret from peer (admin)",0xAAAAAA)
    ctx.o("  trust showSecret <peer>      Show my secret with peer (admin)",0xAAAAAA)
    ctx.o("  block <peer>                 Block a peer",0xAAAAAA)
    ctx.o("  revoke <peer>                Drop peer back to UNKNOWN",0xAAAAAA)
    ctx.o("  forget <peer>                Remove peer record entirely",0xAAAAAA)
    ctx.o("  request <peer>               Ask a peer's admin for trust",0xAAAAAA)
    ctx.o("  requests                     Show pending trust requests",0xAAAAAA)
    ctx.o("  send <peer> <msg>            Send chat message",0xAAAAAA)
    ctx.o("  alias add <name> <peer>      Name a peer (admin)",0xAAAAAA)
    ctx.o("  alias rm  <name>             Remove an alias (admin)",0xAAAAAA)
    ctx.o("  alias list                   Show all aliases",0xAAAAAA)
    ctx.o("  alias show <peer>            Show the alias for a peer",0xAAAAAA)
    ctx.o("  pair start                   Open pairing window (admin)",0xAAAAAA)
    ctx.o("  pair <peer> <code>           Pair with peer using code (admin)",0xAAAAAA)
    ctx.o(" <peer> = alias, full address, prefix, or scan-index (1..N)",0x888888)
    return
  end
  local s=a[1]
  if s=="servers" then
    -- (v1.4.0 consolidation: was the standalone /usr/bin/servers tool.)
    local peers=NM.peers and NM.peers() or {}
    if #peers==0 then
      ctx.o("No peers discovered yet.",0xAAAAAA)
      ctx.o("Run 'net scan' to search the network.",0x888888)
      return
    end
    ctx.o(string.format("%-10s %-8s %-6s %-5s %s",
      "Hostname","Device","Trust","Seen","Address"),0xAAAAAA)
    local trustLabels={[-1]="BLK",[0]="UNK",[1]="KNW",[2]="TRS"}
    local now=computer.uptime()
    for _,peer in ipairs(peers) do
      local age=now-(peer.lastSeen or 0)
      local ageStr
      if age<60 then ageStr=math.floor(age).."s"
      elseif age<3600 then ageStr=math.floor(age/60).."m"
      else ageStr=math.floor(age/3600).."h" end
      ctx.o(string.format("%-10s %-8s %-6s %-5s %s",
        (peer.hostname or "?"):sub(1,10),(peer.device or "?"):sub(1,8),
        trustLabels[peer.trust] or "?",ageStr,(peer.addr or "?"):sub(1,12)))
    end
    ctx.o(#peers.." peer(s) found.",0x888888)
  elseif s=="status" then
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
      -- #NET-3 — sort + index + cache the result so the operator can
      -- refer to peers as `trust 2 full` instead of typing the UUID.
      table.sort(found, function(a2, b2)
        return tostring(a2.addr or "") < tostring(b2.addr or "")
      end)
      _lastScan = found
      if #found > 0 then
        ctx.o(string.format(" %-3s %-20s %-4s %-8s %s",
          "#", "Peer", "Trst", "Device", "Host"), 0xAAAAAA)
        for i, p in ipairs(found) do
          local lvl = p.trust or 0
          local lbl = ({"BLK","UNK","KNW","TRS"})[lvl + 2] or "?"
          local color = (lvl == 2 and 0x55FF55)
                     or (lvl == 1 and 0xFFFF55)
                     or (lvl == -1 and 0xFF5555)
                     or 0xAAAAAA
          ctx.o(string.format(" %2d. %-20s %-4s %-8s %s",
            i, fmtAddr(p.addr), lbl, p.device or "?", p.hostname or ""),
            color)
        end
        ctx.o("Tip: 'net trust 1' references the first peer above.", 0x888888)
      end
      ctx.o(#found .. " peer(s) responded.", 0x00FF00)
    else
      NM.discover()
      ctx.o("Discovery broadcast sent.", 0x00FF00)
    end
  elseif s=="peers" or s=="list" then
    -- Show discovered peers (phase 8) merged with trust data
    local peers = NM.peers and NM.peers() or {}
    if #peers > 0 then
      -- Cache for index-based reference (mirrors `scan` so `peers` is
      -- also a valid source of indices).
      _lastScan = peers
      ctx.o(string.format(" %-3s %-20s %-4s %-8s %s",
        "#", "Peer", "Trst", "Device", "Host"), 0xAAAAAA)
      for i, p in ipairs(peers) do
        local lvl = p.trust or 0
        local lbl = ({"BLK","UNK","KNW","TRS"})[lvl + 2] or "?"
        local color = (lvl == 2 and 0x55FF55)
                   or (lvl == 1 and 0xFFFF55)
                   or (lvl == -1 and 0xFF5555)
                   or 0xAAAAAA
        ctx.o(string.format(" %2d. %-20s %-4s %-8s %s",
          i, fmtAddr(p.addr), lbl, p.device or "?", p.hostname or ""),
          color)
      end
    else
      -- Fallback to trust manager listing
      local tm = NM.getTrust()
      for _, p in ipairs(tm.listPeers()) do
        ctx.o(string.format(" %-20s T%d %s",
          fmtAddr(p.address), p.level, p.hostname or ""))
      end
    end
    if #peers == 0 then ctx.o("  No peers discovered. Run 'net scan' first.", 0xAAAAAA) end
  elseif s=="trust" then
    local tm=NM.getTrust()
    local actor, tier = getActor(ctx)
    local sub2 = a[2]
    -- New form: `net trust <subcommand> <addr> [...]`
    --   net trust gen <addr>          # generate + provision a shared secret
    --   net trust setSecret <addr> <hex|empty>
    --   net trust <addr> [full]       # legacy: elevate to KNOWN/TRUSTED
    if sub2 == "gen" or sub2 == "generate" then
      local addr = resolvePeer(a[3])
      if not addr then ctx.o("Usage: net trust gen <peer>",0xFFFF00) return end
      local secret, gerr = tm.generateSecret(actor, addr, tier)
      if secret then
        ctx.o("Generated shared secret for " .. fmtAddr(addr) .. " ("..#secret.." bytes)",0x00FF00)
        ctx.o("Easier: run 'net pair start' on the peer and 'net pair " ..
              fmtAddr(addr) .. " <code>' here.",0xAAAAAA)
        ctx.o("Or copy: run `net trust setSecret <our-addr> <hex>` on the peer.",0xAAAAAA)
        -- Print as hex so the operator can copy it to the other side.
        local hex = {}
        for i = 1, #secret do hex[i] = string.format("%02x", secret:byte(i)) end
        ctx.o("Secret (hex): " .. table.concat(hex), 0xFFFF55)
      else
        ctx.o("Failed: " .. tostring(gerr or "unknown"),0xFF0000)
      end
    elseif sub2 == "setSecret" or sub2 == "secret" then
      local addr = resolvePeer(a[3])
      local hex  = a[4]
      if not addr then
        ctx.o("Usage: net trust setSecret <peer> <hex-string|->",0xFFFF00)
        ctx.o("       Use - or empty to clear the secret.",0xAAAAAA)
        return
      end
      local secret
      if not hex or hex == "" or hex == "-" then
        secret = nil
      else
        -- Decode hex pairs to bytes. Reject malformed input rather than
        -- silently store half a secret.
        if #hex % 2 ~= 0 or hex:match("[^%x]") then
          ctx.o("Bad hex string (need pairs of 0-9 a-f).",0xFF0000); return
        end
        local bytes = {}
        for i = 1, #hex, 2 do
          bytes[#bytes+1] = string.char(tonumber(hex:sub(i, i+1), 16))
        end
        secret = table.concat(bytes)
      end
      local ok2, err2 = tm.setSecret(actor, addr, secret, tier)
      if ok2 then
        ctx.o(secret and "Secret set." or "Secret cleared.",0x00FF00)
      else
        ctx.o("Failed: " .. tostring(err2 or "unknown"),0xFF0000)
      end
    elseif sub2 == "showSecret" then
      -- Diagnostic: print the secret we have (if any). Audit-logged
      -- by trust.getSecret since the actor goes through the gate.
      local addr = resolvePeer(a[3])
      if not addr then ctx.o("Usage: net trust showSecret <peer>",0xFFFF00) return end
      local secret, gerr = tm.getSecret(actor, addr, tier)
      if not secret then
        ctx.o(gerr or "no secret set",0xAAAAAA); return
      end
      local hex = {}
      for i = 1, #secret do hex[i] = string.format("%02x", secret:byte(i)) end
      ctx.o(table.concat(hex),0xFFFF55)
    elseif sub2 then
      -- Legacy: `net trust <peer>` or `net trust <peer> full` — elevate.
      local addr = resolvePeer(sub2)
      local ok2, err2
      if a[3]=="full" then ok2, err2 = tm.trustFull(actor, addr, tier)
      else ok2, err2 = tm.trustKnown(actor, addr, tier) end
      if ok2 then
        ctx.o("Trust updated for "..fmtAddr(addr)..".",0x00FF00)
        if a[3] == "full" then
          ctx.o("Next: 'net pair start' on the peer + 'net pair "..
                fmtAddr(addr).." <code>' here to install a shared secret.",0x888888)
        end
      else ctx.o(err2 or "Trust update failed",0xFF0000) end
    else
      ctx.o("Usage: net trust <gen|setSecret|showSecret|<addr> [full]>",0xFFFF00)
    end
  elseif s=="block" and a[2] then
    local actor, tier = getActor(ctx)
    local addr = resolvePeer(a[2])
    local ok2, err2 = NM.getTrust().block(actor, addr, tier)
    if ok2 then ctx.o("Blocked "..fmtAddr(addr)..".",0x00FF00)
    else ctx.o(err2 or "Block failed",0xFF0000) end
  elseif s=="revoke" and a[2] then
    local actor, tier = getActor(ctx)
    local addr = resolvePeer(a[2])
    local ok2, err2 = NM.getTrust().revoke(actor, addr, tier)
    if ok2 then ctx.o("Trust revoked for "..fmtAddr(addr).." (now UNKNOWN).",0x00FF00)
    else ctx.o(err2 or "Revoke failed",0xFF0000) end
  elseif s=="forget" and a[2] then
    local actor, tier = getActor(ctx)
    local addr = resolvePeer(a[2])
    local ok2, err2 = NM.getTrust().forget(actor, addr, tier)
    if ok2 then ctx.o("Forgot peer "..fmtAddr(addr).." (record removed).",0x00FF00)
    else ctx.o(err2 or "Forget failed",0xFF0000) end
  elseif s=="request" and a[2] then
    local addr = resolvePeer(a[2])
    local ok2, err2 = NM.requestTrust(addr)
    if ok2 then
      ctx.o("Trust request sent to "..fmtAddr(addr)..".",0x00FF00)
      ctx.o("Their admin sees it under 'net requests'.",0x888888)
    else ctx.o(err2 or "Request failed",0xFF0000) end
  elseif s=="requests" then
    local reqs = NM.getTrust().getPendingRequests()
    local n = 0
    for addr, req in pairs(reqs) do
      n = n + 1
      ctx.o(string.format("  %-38s %s", fmtAddr(addr),
        req.hostname or "(no hostname)"),0xFFFF55)
    end
    if n == 0 then ctx.o("No pending trust requests.",0xAAAAAA)
    else
      ctx.o("Approve: net trust <peer> [full]   Refuse: net block <peer>",0x888888)
    end
  elseif s=="send" and a[2] and a[3] then
    local addr = resolvePeer(a[2])
    local ok2, err2 = NM.sendMessage(addr, table.concat(a, " ", 3))
    if ok2 then ctx.o("Sent.",0x00FF00)
    else ctx.o("Send failed: "..tostring(err2 or "unknown"),0xFF0000) end
  -- ════════════════════════════════════════════════════════════
  -- #NET-1: alias subcommand surface
  -- ════════════════════════════════════════════════════════════
  elseif s == "alias" then
    local A = _G._TOS and _G._TOS.net and _G._TOS.net.aliases
    if not A then ctx.o("aliases module unavailable",0xFF0000) return end
    local sub2 = a[2]
    if sub2 == "add" or sub2 == "set" then
      local name = a[3]
      local addr = resolvePeer(a[4])  -- accept "alias add foo 3" if scan was run
      if not name or not addr then
        ctx.o("Usage: net alias add <name> <peer>",0xFFFF00); return
      end
      local ok2, err2 = A.set(name, addr)
      if ok2 then
        ctx.o(string.format("alias %s -> %s", name, fmtAddr(addr)), 0x00FF00)
      else ctx.o(err2 or "alias failed",0xFF0000) end
    elseif sub2 == "rm" or sub2 == "remove" or sub2 == "del" then
      local name = a[3]
      if not name then ctx.o("Usage: net alias rm <name>",0xFFFF00); return end
      local ok2, err2 = A.remove(name)
      if ok2 then ctx.o("removed.",0x00FF00)
      else ctx.o(err2 or "remove failed",0xFF0000) end
    elseif sub2 == "list" or sub2 == nil then
      local rows = A.list()
      if #rows == 0 then
        ctx.o("No aliases defined.",0xAAAAAA); return
      end
      ctx.o(string.format(" %-16s  %s", "Alias", "Address"),0xAAAAAA)
      for _, r in ipairs(rows) do
        ctx.o(string.format(" %-16s  %s", r.alias, r.address))
      end
    elseif sub2 == "show" then
      local addr = resolvePeer(a[3])
      if not addr then ctx.o("Usage: net alias show <peer>",0xFFFF00); return end
      local name = A.aliasOf(addr)
      if name then ctx.o(name .. " -> " .. addr, 0x00FF00)
      else ctx.o("No alias for " .. addr:sub(1, 12) .. "...", 0xAAAAAA) end
    else
      ctx.o("Usage: net alias <add|rm|list|show>",0xFFFF00)
    end
  -- ════════════════════════════════════════════════════════════
  -- #NET-2: pair subcommand surface
  -- ════════════════════════════════════════════════════════════
  elseif s == "pair" then
    local CP = NM.getChatPair and NM.getChatPair() or nil
    if not CP then ctx.o("chat-pair unavailable",0xFF0000) return end
    local sub2 = a[2]
    if sub2 == "start" then
      local code, expiresAt = CP.startWindow()
      if not code then
        ctx.o("could not open pairing window: " .. tostring(expiresAt), 0xFF0000)
        return
      end
      local secs = math.max(0, math.floor(expiresAt - computer.uptime()))
      ctx.o("Pairing window open for " .. secs .. "s.", 0xFFFF55)
      ctx.o("Type this on the OTHER peer:", 0xAAAAAA)
      ctx.o("  net pair <our-addr-or-alias> " .. code, 0xFFFF00)
      ctx.o("Pre-condition: both peers must already be TRUSTED on both sides.",0x888888)
    elseif sub2 == "status" then
      local info = CP.windowInfo()
      if info then
        ctx.o(string.format("Window open: %ds left, %d peers paired",
          math.floor(info.expires_in), info.paired), 0xFFFF55)
      else
        ctx.o("No pairing window open.", 0xAAAAAA)
      end
    elseif sub2 == "close" or sub2 == "cancel" then
      CP.closeWindow()
      ctx.o("Pairing window closed.", 0x00FF00)
    elseif sub2 and a[3] then
      local addr = resolvePeer(sub2)
      local code = a[3]
      ctx.o("Pairing with " .. fmtAddr(addr) .. "...", 0xFFFF55)
      local ok2, err2 = CP.connect(addr, code, 10)
      if ok2 then
        ctx.o("Paired. Shared secret installed on both sides.", 0x00FF00)
      else
        ctx.o("Pair failed: " .. tostring(err2), 0xFF0000)
      end
    else
      ctx.o("Usage: net pair start | net pair <peer> <code> | net pair status",0xFFFF00)
    end
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
