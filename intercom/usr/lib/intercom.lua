
































local M = {}

M._VERSION = "1.0.0"




local function soft(name)
  local ok, mod = pcall(require, name)
  if ok then return mod end
end
local component = soft("component")
local computer  = soft("computer")
local net       = soft("kernel.net")
local fs        = soft("kernel.fs")
local serialize = soft("kernel.serialize")
local event     = soft("kernel.event")
local log = soft("kernel.log") or {}
for _, lvl in ipairs({ "info", "warn", "error" }) do
  if type(log[lvl]) ~= "function" then log[lvl] = function() end end
end





M.SVC        = "intercom"                
M.CUES_PATH  = "/etc/intercom.cues"      
M.CFG_PATH   = "/etc/intercom.cfg"       
M.SPOOL_PATH = "/var/intercom/log.dat"   

M.MAX_TEXT   = 240      
M.MAX_CUES   = 64
M.MAX_SPOOL  = 100      



M.SEVERITIES = { "info", "notice", "warn", "alert", "critical" }
M.RANK = {}
for i, s in ipairs(M.SEVERITIES) do M.RANK[s] = i end

M.DEFAULT_CFG = {
  
  
  popupLevel    = "alert",
  
  
  
  
  
  popupCooldown = 60,
  
  minLevel      = "info",
  
  
  
  echoToTape    = false,
}






function M.validSeverity(sev) return M.RANK[sev or ""] ~= nil end





function M.rank(sev) return M.RANK[sev or ""] or 0 end


function M.atLeast(sev, threshold)
  return M.rank(sev) >= M.rank(threshold)
end
















function M.parseCueLine(line)
  if type(line) ~= "string" then return nil, "not a string" end
  local trimmed = line:match("^%s*(.-)%s*$")
  if trimmed == "" or trimmed:sub(1, 1) == "#" then return nil end   

  local name, startPos, quote, text, stopPos, rest =
    trimmed:match('^(%S+)%s+%[(%d+)%]%s*(["\'])(.-)%3%s*%[(%d+)%]%s*(.*)$')
  if not name then
    return nil, "expected:  <name> [start] \"text\" [end] [severity]"
  end

  startPos, stopPos = tonumber(startPos), tonumber(stopPos)
  if stopPos <= startPos then
    return nil, "end position must be after the start position"
  end
  if #text == 0 then return nil, "the announcement text is empty" end
  if #text > M.MAX_TEXT then
    return nil, "text is longer than " .. M.MAX_TEXT .. " characters"
  end

  local severity = (rest:match("^(%S+)") or "info"):lower()
  if not M.validSeverity(severity) then
    return nil, "unknown severity '" .. severity .. "' (use: "
      .. table.concat(M.SEVERITIES, " ") .. ")"
  end

  return { name = name:lower(), start = startPos, stop = stopPos,
           text = text, severity = severity }
end




function M.formatCueLine(cue)
  
  
  local q = cue.text:find('"', 1, true) and "'" or '"'
  return string.format('%-16s [%04d] %s%s%s [%04d]  %s',
    cue.name, cue.start, q, cue.text, q, cue.stop, cue.severity)
end





function M.parseCatalog(textBlob)
  local cues, errors, seen = {}, {}, {}
  local n = 0
  for line in tostring(textBlob or ""):gmatch("([^\n]*)\n?") do
    n = n + 1
    if n > 4096 then break end                    
    local cue, why = M.parseCueLine(line)
    if cue then
      if seen[cue.name] then
        errors[#errors + 1] = { line = n, why = "duplicate cue name '"
          .. cue.name .. "' (the earlier one wins)" }
      elseif #cues >= M.MAX_CUES then
        errors[#errors + 1] = { line = n, why = "more than " .. M.MAX_CUES
          .. " cues; ignored" }
      else
        seen[cue.name] = true
        cues[#cues + 1] = cue
      end
    elseif why then
      errors[#errors + 1] = { line = n, why = why }
    end
  end
  return cues, errors
end



function M.formatCatalog(cues)
  local out = {
    "# TOS Intercom announcement catalog",
    "#",
    "#   <name>  [start] \"what the recording says\" [end]  <severity>",
    "#",
    "# Positions are tape byte offsets. Severity is one of:",
    "#   " .. table.concat(M.SEVERITIES, "  "),
    "# Check a cue with:  intercom test <name>   (plays it, sends nothing)",
    "",
  }
  for _, c in ipairs(cues or {}) do out[#out + 1] = M.formatCueLine(c) end
  return table.concat(out, "\n") .. "\n"
end


function M.findCue(cues, name)
  name = tostring(name or ""):lower()
  for _, c in ipairs(cues or {}) do
    if c.name == name then return c end
  end
end






function M.loadCatalog(store)
  store = store or fs
  if not (store and store.exists and store.exists(M.CUES_PATH)) then return {}, {} end
  local raw = store.readFile(M.CUES_PATH)
  if type(raw) ~= "string" then return {}, {} end
  return M.parseCatalog(raw)
end




function M.saveCatalog(cues, store)
  store = store or fs
  if not store then return false, "no filesystem" end
  local blob = M.formatCatalog(cues)
  if store.writeFileAtomic then return store.writeFileAtomic(M.CUES_PATH, blob) end
  return store.writeFile(M.CUES_PATH, blob)
end




function M.normalizeCfg(raw)
  local cfg = {}
  for k, v in pairs(M.DEFAULT_CFG) do cfg[k] = v end
  if type(raw) == "table" then
    if M.validSeverity(raw.popupLevel) then cfg.popupLevel = raw.popupLevel end
    if M.validSeverity(raw.minLevel)   then cfg.minLevel   = raw.minLevel end
    if type(raw.popupCooldown) == "number" and raw.popupCooldown >= 0
       and raw.popupCooldown <= 3600 then
      cfg.popupCooldown = math.floor(raw.popupCooldown)
    end
    if type(raw.echoToTape) == "boolean" then cfg.echoToTape = raw.echoToTape end
  end
  return cfg
end


function M.loadCfg(store, ser)
  store, ser = store or fs, ser or serialize
  if not (store and ser and store.exists and store.exists(M.CFG_PATH)) then
    return M.normalizeCfg(nil)
  end
  local raw = store.readFile(M.CFG_PATH)
  if type(raw) ~= "string" then return M.normalizeCfg(nil) end
  local ok, parsed = pcall(ser.decode, raw, { maxBytes = 8 * 1024 })
  return M.normalizeCfg(ok and parsed or nil)
end


function M.saveCfg(cfg, store, ser)
  store, ser = store or fs, ser or serialize
  if not (store and ser) then return false, "fs/serialize unavailable" end
  return ser.saveFile(store, M.CFG_PATH, M.normalizeCfg(cfg))
end







function M.findDrive(addr)
  if not (component and component.list) then return nil, "no component API" end
  for a in component.list("tape_drive") do
    if not addr or a:sub(1, #addr) == addr then
      local ok, proxy = pcall(component.proxy, a)
      if ok then return proxy end
    end
  end
  return nil, addr and ("no tape drive matching " .. addr) or "no tape drive attached"
end






function M.seekTo(drive, pos)
  if not (drive and drive.seek and drive.getSize) then return false, "no drive" end
  if drive.stop then pcall(drive.stop) end
  local size = drive.getSize() or 0
  if pos < 0 or pos > size then
    return false, string.format("position %d is off the tape (size %d)", pos, size)
  end
  drive.seek(-size)                     
  if pos > 0 then drive.seek(pos) end
  return true
end














M.BYTES_PER_SECOND = 4096

function M.playCue(drive, cue, opts)
  opts = opts or {}
  if not drive then return false, "no tape drive" end
  if drive.isReady and not drive.isReady() then return false, "no tape in the drive" end
  local ok, err = M.seekTo(drive, cue.start)
  if not ok then return false, err end

  if drive.setVolume and opts.volume then pcall(drive.setVolume, opts.volume) end
  if drive.setSpeed and opts.speed then pcall(drive.setSpeed, opts.speed) end

  local okPlay = pcall(drive.play)
  if not okPlay then return false, "the drive refused to play" end

  local rate = opts.bytesPerSecond or M.BYTES_PER_SECOND
  local seconds = (cue.stop - cue.start) / rate

  
  
  
  local timer = opts.timer or (event and event.timer)
  if timer then
    timer(seconds, function()
      pcall(drive.stop)
      if opts.onDone then pcall(opts.onDone) end
    end, "intercom")
  end
  return true, seconds
end







function M.spoolAppend(list, ann)
  list = type(list) == "table" and list or {}
  list[#list + 1] = ann
  while #list > M.MAX_SPOOL do table.remove(list, 1) end
  return list
end

function M.loadSpool(store, ser)
  store, ser = store or fs, ser or serialize
  if not (store and ser and store.exists and store.exists(M.SPOOL_PATH)) then return {} end
  local raw = store.readFile(M.SPOOL_PATH)
  if type(raw) ~= "string" then return {} end
  local ok, parsed = pcall(ser.decode, raw, { maxBytes = 128 * 1024 })
  if ok and type(parsed) == "table" then return parsed end
  return {}
end

function M.saveSpool(list, store, ser)
  store, ser = store or fs, ser or serialize
  if not (store and ser) then return false, "fs/serialize unavailable" end
  if store.makeDirectory and store.exists and not store.exists("/var/intercom") then
    pcall(store.makeDirectory, "/var/intercom")
  end
  return ser.saveFile(store, M.SPOOL_PATH, list)
end










function M.since(seq, store, ser)
  seq = tonumber(seq) or 0
  local out, high = {}, seq
  for _, a in ipairs(M.loadSpool(store, ser)) do
    local s = tonumber(a.rxSeq) or 0
    if s > seq then out[#out + 1] = a end
    if s > high then high = s end
  end
  return out, high
end



function M.highWater(store, ser)
  local _, high = M.since(0, store, ser)
  return high
end











function M.receivePlan(cfg, ann, lastPopupAt, now)
  cfg = M.normalizeCfg(cfg)
  local sev = (type(ann) == "table" and ann.severity) or "info"
  if not M.atLeast(sev, cfg.minLevel) then
    return { accept = false, popup = false, why = "below minLevel" }
  end
  if not M.atLeast(sev, cfg.popupLevel) then
    return { accept = true, popup = false, why = "logged (below popupLevel)" }
  end
  local since = (now or 0) - (lastPopupAt or -math.huge)
  if lastPopupAt and since < cfg.popupCooldown then
    
    
    
    return { accept = true, popup = false,
             why = string.format("popup on cooldown (%ds left)",
               math.ceil(cfg.popupCooldown - since)) }
  end
  return { accept = true, popup = true, why = "interrupting" }
end


function M.formatLine(ann)
  local sev = (type(ann) == "table" and ann.severity) or "info"
  local who = (type(ann) == "table" and ann.from) or "?"
  local txt = (type(ann) == "table" and ann.text) or ""
  return string.format("[%s] %s: %s", sev:upper(), who, txt)
end








function M.newAnnouncement(opts)
  local text = tostring(opts.text or ""):sub(1, M.MAX_TEXT)
  return {
    text     = text,
    severity = M.validSeverity(opts.severity) and opts.severity or "info",
    from     = opts.from or "?",
    cue      = opts.cue,                 
    at       = opts.at or (computer and computer.uptime and computer.uptime()) or 0,
  }
end











function M.announce(opts)
  opts = opts or {}
  local rep = { played = false, sent = false, errors = {} }
  local function fail(s) rep.errors[#rep.errors + 1] = s end

  local cue = opts.cue
  local text = opts.text or (cue and cue.text)
  if not text or text == "" then
    fail("nothing to say"); return rep
  end
  local severity = opts.severity or (cue and cue.severity) or "info"

  
  if cue then
    local drive = opts.drive
    if drive == nil then drive = M.findDrive(opts.driveAddr) end
    if not drive then
      fail("no tape drive — announcing by text only")
    else
      local ok, errOrSecs = M.playCue(drive, cue, opts)
      if ok then rep.played = true; rep.seconds = errOrSecs
      else fail("tape: " .. tostring(errOrSecs)) end
    end
  end

  
  if opts.localOnly then
    rep.localOnly = true
    return rep
  end
  if not (net and net.meshAvailable and net.meshAvailable()) then
    fail("no mesh network — nobody was told")
    return rep
  end
  local ann = M.newAnnouncement({
    text = text, severity = severity, cue = cue and cue.name or nil,
    from = (net.getHostname and net.getHostname()) or "?",
  })
  local to = opts.to or "*"
  
  
  
  local id, err = net.meshSend({
    svc = M.SVC, to = to, payload = ann,
    allowPlaintext = (to == "*") or nil,
  })
  if id then
    rep.sent = true; rep.id = id; rep.announcement = ann
    log.info("intercom", "Announced (" .. severity .. "): " .. text)
  else
    fail("send failed: " .. tostring(err))
  end
  return rep
end





local running = false
local lastPopupAt = nil













function M.raise(ann, notifyMod)
  notifyMod = notifyMod or soft("kernel.notify")
  if not (notifyMod and notifyMod.post) then return nil, "no notify facility" end
  local sev = tostring(ann.severity or "alert")
  return notifyMod.post({
    from    = "intercom",
    
    
    style   = (sev == "critical") and "danger" or "warn",
    title   = "ANNOUNCEMENT \226\128\148 " .. sev:upper(),
    message = tostring(ann.text or "")
      .. (ann.cue and ("\n\n(tape cue: " .. tostring(ann.cue) .. ")") or ""),
    buttons = { "Acknowledge" },
    
    
    ttl     = 120,
  })
end




function M.deliver(ann, now, deps)
  deps = deps or {}
  local store = deps.fs or fs
  local ser   = deps.serialize or serialize
  local cfg   = deps.cfg or M.loadCfg(store, ser)
  now = now or (computer and computer.uptime and computer.uptime()) or 0

  local plan = M.receivePlan(cfg, ann, deps.lastPopupAt or lastPopupAt, now)
  if not plan.accept then return plan end

  
  
  local spool = M.loadSpool(store, ser)
  ann.rxSeq = (tonumber(spool[#spool] and spool[#spool].rxSeq) or 0) + 1
  M.saveSpool(M.spoolAppend(spool, ann), store, ser)

  if plan.popup then
    local id, why = M.raise(ann, deps.notify)
    plan.raised = id ~= nil
    
    
    
    
    
    if not id then plan.why = "popup refused: " .. tostring(why) end
    lastPopupAt = now
    if deps.setLastPopup then deps.setLastPopup(now) end
  end

  
  
  
  if cfg.echoToTape and ann.cue then
    local cues = M.loadCatalog(store)
    local mine = M.findCue(cues, ann.cue)
    if mine then pcall(M.playCue, M.findDrive(), mine) end
  end

  log.info("intercom", "Heard " .. M.formatLine(ann))
  return plan
end


function M.start()
  if running then return true end
  if not (net and net.meshOn) then
    log.warn("intercom", "no mesh transport — the receiver cannot start")
    return false, "mesh unavailable"
  end
  net.meshOn(M.SVC, function(msg, env)
    
    
    
    
    if type(msg) ~= "table" or type(msg.text) ~= "string" then return false end
    msg.from = msg.from or (env and env.from and tostring(env.from):sub(1, 8)) or "?"
    local ok, plan = pcall(M.deliver, msg)
    return ok and plan and plan.accept or false
  end)
  running = true
  log.info("intercom", "Announcement receiver listening")
  return true
end

function M.stop()
  if not running then return true end
  if net and net.meshOff then net.meshOff(M.SVC) end
  running = false
  log.info("intercom", "Announcement receiver stopped")
  return true
end

function M.running() return running end





function M._reset() lastPopupAt = nil end

return M
