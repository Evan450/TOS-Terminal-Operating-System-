-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  Optional Utilities — Intercom (facility announcement system)     ║
-- ║                                                                   ║
-- ║  An intercom says whatever you want it to say: "reactor fuel low",║
-- ║  "we're out of iron", "shift change". Two channels carry the same ║
-- ║  announcement at the same time:                                   ║
-- ║                                                                   ║
-- ║    AUDIO    a Computronics tape drive, seeked to the announcement ║
-- ║             and played. The tape holds the VOICE.                 ║
-- ║    TEXT     the same words, sent over the mesh to every machine   ║
-- ║             willing to hear them. The catalog holds the WORDS.    ║
-- ║                                                                   ║
-- ║  THE CATALOG IS THE WHOLE TRICK. A tape drive cannot tell you     ║
-- ║  what is recorded on it — it is audio, and there is no index. So  ║
-- ║  the operator tells it, once, in the notation they'd use anyway:  ║
-- ║                                                                   ║
-- ║    fuel-low  [0001] "Warning: Reactor fuel low." [0005]  warn     ║
-- ║                                                                   ║
-- ║  Start position, what it says, end position, how loud to shout.   ║
-- ║  From that one line the Intercom knows where to seek, when to     ║
-- ║  stop, what to broadcast, and how urgently to interrupt people.   ║
-- ║  `intercom test <cue>` plays it WITHOUT broadcasting so you can   ║
-- ║  check the positions actually bracket the right recording.        ║
-- ║                                                                   ║
-- ║  Everything on this page that can be pure, is: the catalog codec, ║
-- ║  severity ordering, the popup/cooldown decision and the spool are ║
-- ║  plain functions over plain tables (test_intercom.lua drives them ║
-- ║  with a fake tape and no network at all).                         ║
-- ║                                                                   ║
-- ║  FULL-PRIV LIBRARY (mail/blockfs precedent): loaded by the base   ║
-- ║  shell and by rc via the real require, so it may use kernel.*.    ║
-- ╚══════════════════════════════════════════════════════════════════╝

local M = {}

M._VERSION = "1.0.0"

-- Boot-order-proof requires (cluster lesson): rc.d loads this BEFORE the
-- OpenOS compat aliases exist — use the kernel modules directly, and
-- tolerate their absence so the pure half still loads under a bare test.
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

-- ============================================================
-- Constants
-- ============================================================

M.SVC        = "intercom"                -- mesh service name
M.CUES_PATH  = "/etc/intercom.cues"      -- the catalog (operator notation)
M.CFG_PATH   = "/etc/intercom.cfg"       -- receive policy
M.SPOOL_PATH = "/var/intercom/log.dat"   -- what we've heard

M.MAX_TEXT   = 240      -- an announcement is a sentence, not an essay
M.MAX_CUES   = 64
M.MAX_SPOOL  = 100      -- announcements retained (oldest pruned)

--- Severity ladder, low to high. The ORDER is the API: everything else
--- compares ranks, so adding a level here is the only edit needed.
M.SEVERITIES = { "info", "notice", "warn", "alert", "critical" }
M.RANK = {}
for i, s in ipairs(M.SEVERITIES) do M.RANK[s] = i end

M.DEFAULT_CFG = {
  -- At or above this, an announcement interrupts with a message box.
  -- "alert" by default: warns belong in the log, alerts belong in your face.
  popupLevel    = "alert",
  -- Seconds of quiet enforced after a popup. THE POINT OF THIS FIELD is
  -- that a failing reactor can emit an announcement every few seconds, and
  -- a modal per announcement would make the computer unusable exactly when
  -- the operator most needs to type on it. Announcements never stop being
  -- logged — only the interruption is rate-limited.
  popupCooldown = 60,
  -- Below this, drop on arrival (an "only tell me if it matters" filter).
  minLevel      = "info",
  -- Play received announcements on THIS machine's tape too, if it has the
  -- same catalog. Off by default: the usual layout is one tape at the
  -- announcement post and text everywhere else.
  echoToTape    = false,
}

-- ============================================================
-- Severity helpers (pure)
-- ============================================================

--- Is `sev` a severity we know? Pure.
function M.validSeverity(sev) return M.RANK[sev or ""] ~= nil end

--- Rank of a severity (1..N), or 0 for anything unrecognised. Pure.
--- Unknown severities rank 0 (below everything) rather than raising: a
--- message from a NEWER intercom with a level we don't have must still be
--- logged, just never promoted to a popup we can't reason about.
function M.rank(sev) return M.RANK[sev or ""] or 0 end

--- Does `sev` meet `threshold`? Pure.
function M.atLeast(sev, threshold)
  return M.rank(sev) >= M.rank(threshold)
end

-- ============================================================
-- The catalog (pure codec)
-- ============================================================
-- Line format — deliberately the notation an operator would jot down while
-- recording the tape, not a config-file dialect they'd have to learn:
--
--   <name>  [<start>] "<what it says>" [<end>]  [severity]
--
-- Blank lines and #-comments are ignored. Positions are absolute tape byte
-- offsets (what drive.getPosition() reports), zero-padded or not — both
-- "[0001]" and "[1]" parse, because the leading zeros are how a person
-- writes a cue list and dropping them is how a person types one.

--- Parse ONE catalog line. Returns a cue table, or nil + reason.
--- Pure: no I/O, no globals.
function M.parseCueLine(line)
  if type(line) ~= "string" then return nil, "not a string" end
  local trimmed = line:match("^%s*(.-)%s*$")
  if trimmed == "" or trimmed:sub(1, 1) == "#" then return nil end   -- skip

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

--- Render one cue back to catalog notation. Pure. Round-trips through
--- parseCueLine, which the tests pin — so `intercom cue add` writing the
--- file produces something the operator can still hand-edit.
function M.formatCueLine(cue)
  -- Prefer the double quote, but fall back to a single quote when the text
  -- contains one, so a sentence like: He said "go" — still round-trips.
  local q = cue.text:find('"', 1, true) and "'" or '"'
  return string.format('%-16s [%04d] %s%s%s [%04d]  %s',
    cue.name, cue.start, q, cue.text, q, cue.stop, cue.severity)
end

--- Parse a whole catalog. Returns (cues, errors) where `cues` is an array
--- in file order and `errors` is { {line = N, why = "..."}, ... }.
--- A bad line NEVER aborts the parse: one typo in a 30-cue catalog must
--- not silence the whole announcement system.
function M.parseCatalog(textBlob)
  local cues, errors, seen = {}, {}, {}
  local n = 0
  for line in tostring(textBlob or ""):gmatch("([^\n]*)\n?") do
    n = n + 1
    if n > 4096 then break end                    -- runaway guard
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

--- Render a catalog back to text, with the header an operator will want
--- when they open the file in the editor. Pure.
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

--- Find a cue by name in a parsed catalog. Pure.
function M.findCue(cues, name)
  name = tostring(name or ""):lower()
  for _, c in ipairs(cues or {}) do
    if c.name == name then return c end
  end
end

-- ============================================================
-- Catalog + config I/O
-- ============================================================

--- Load and parse the catalog. Returns (cues, errors).
function M.loadCatalog(store)
  store = store or fs
  if not (store and store.exists and store.exists(M.CUES_PATH)) then return {}, {} end
  local raw = store.readFile(M.CUES_PATH)
  if type(raw) ~= "string" then return {}, {} end
  return M.parseCatalog(raw)
end

--- Write the catalog back. Atomic where the store supports it — this file
--- is the only record of what is on the tape, and a truncating write that
--- died halfway would lose the lot.
function M.saveCatalog(cues, store)
  store = store or fs
  if not store then return false, "no filesystem" end
  local blob = M.formatCatalog(cues)
  if store.writeFileAtomic then return store.writeFileAtomic(M.CUES_PATH, blob) end
  return store.writeFile(M.CUES_PATH, blob)
end

--- Normalize a config table against DEFAULT_CFG, discarding nonsense.
--- Pure. A bad value falls back to the default rather than disabling the
--- feature: a typo in popupLevel must not silently stop alerts appearing.
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

--- Load the receive policy.
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

--- Save the receive policy.
function M.saveCfg(cfg, store, ser)
  store, ser = store or fs, ser or serialize
  if not (store and ser) then return false, "fs/serialize unavailable" end
  return ser.saveFile(store, M.CFG_PATH, M.normalizeCfg(cfg))
end

-- ============================================================
-- The tape
-- ============================================================

--- Find a tape drive: the first one, or the first whose address starts
--- with `addr`. Returns proxy or nil, reason.
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

--- Seek a drive to an ABSOLUTE position. Computronics `seek` is relative
--- and clamps at the ends, so the reliable way to reach a known offset is
--- rewind-then-forward — the same approach the `tape` package uses.
--- Pure w.r.t. TOS: takes any {getSize, seek, stop} table, which is how
--- the tests drive it.
function M.seekTo(drive, pos)
  if not (drive and drive.seek and drive.getSize) then return false, "no drive" end
  if drive.stop then pcall(drive.stop) end
  local size = drive.getSize() or 0
  if pos < 0 or pos > size then
    return false, string.format("position %d is off the tape (size %d)", pos, size)
  end
  drive.seek(-size)                     -- clamps at 0 = rewound
  if pos > 0 then drive.seek(pos) end
  return true
end

--- Play a cue on `drive`: seek to its start, start playback, and schedule
--- a stop at its end.
---
--- The stop is a TIMER, not a wait loop. Playback is asynchronous — the
--- drive keeps advancing while the computer does other things — so polling
--- getPosition() in the caller would freeze the shell for the length of
--- the announcement, which for the operator triggering an evacuation alarm
--- is precisely the wrong moment to be unable to type. `bytesPerSecond`
--- converts the cue's length into a delay (Computronics tapes run at a
--- fixed byte rate; 4096 B/s is the stock value, overridable for tapes
--- written at another speed).
---
--- Returns (true, seconds) or (false, reason).
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

  -- Stop at the end of the cue so one announcement doesn't run into the
  -- next recording on the tape. If timers aren't available (a bare test
  -- harness) the caller gets the duration back and can stop it itself.
  local timer = opts.timer or (event and event.timer)
  if timer then
    timer(seconds, function()
      pcall(drive.stop)
      if opts.onDone then pcall(opts.onDone) end
    end, "intercom")
  end
  return true, seconds
end

-- ============================================================
-- The spool — what this machine has heard
-- ============================================================

--- Append an announcement to a capped ring. Pure given `list`; returns the
--- new list so callers can't forget to reassign.
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

--- Announcements newer than `seq`, plus the new high-water mark.
--- @return list, highWater
---
--- The cursor is `rxSeq` — a RECEIVE counter this machine stamps on
--- arrival — not the sender's timestamp and not a spool index. The
--- timestamp is the sender's uptime and means nothing here; the index
--- shifts every time the capped spool prunes its oldest entry, so a reader
--- holding one would silently re-show old announcements after the 101st
--- arrives. A monotonic receive counter is stable under both.
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

--- The highest rxSeq on record. A reader that starts mid-life uses this to
--- skip the backlog instead of replaying every announcement since boot.
function M.highWater(store, ser)
  local _, high = M.since(0, store, ser)
  return high
end

-- ============================================================
-- Receive policy (pure)
-- ============================================================

--- Decide what to DO with an arriving announcement. Pure — takes the
--- config, the announcement, the last popup time and the current time, and
--- returns a plan. Keeping this a function of its inputs is what makes the
--- cooldown testable without waiting a real minute.
---
--- @return { accept = bool, popup = bool, why = string }
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
    -- Still accepted and still shown in chat — only the interruption is
    -- suppressed. An operator who dismissed one alarm 10 seconds ago does
    -- not need the modal again; they need their keyboard.
    return { accept = true, popup = false,
             why = string.format("popup on cooldown (%ds left)",
               math.ceil(cfg.popupCooldown - since)) }
  end
  return { accept = true, popup = true, why = "interrupting" }
end

--- One-line rendering of an announcement for a chat/log view. Pure.
function M.formatLine(ann)
  local sev = (type(ann) == "table" and ann.severity) or "info"
  local who = (type(ann) == "table" and ann.from) or "?"
  local txt = (type(ann) == "table" and ann.text) or ""
  return string.format("[%s] %s: %s", sev:upper(), who, txt)
end

-- ============================================================
-- Sending
-- ============================================================

--- Build the wire payload for an announcement. Pure, and the single place
--- that decides what an announcement IS — so the sender, the receiver and
--- the tests can't disagree about the shape.
function M.newAnnouncement(opts)
  local text = tostring(opts.text or ""):sub(1, M.MAX_TEXT)
  return {
    text     = text,
    severity = M.validSeverity(opts.severity) and opts.severity or "info",
    from     = opts.from or "?",
    cue      = opts.cue,                 -- cue name, when it came from tape
    at       = opts.at or (computer and computer.uptime and computer.uptime()) or 0,
  }
end

--- Announce: play the tape (if a cue and a drive are available) AND send
--- the words to everyone willing to hear them.
---
--- opts.text        what to say (required unless opts.cue resolves one)
--- opts.cue         a cue table from the catalog (adds tape playback)
--- opts.severity    overrides the cue's
--- opts.to          a peer address, or "*" for everyone (default "*")
--- opts.drive       tape drive proxy (default: the first one found)
--- opts.localOnly   play without sending — the `intercom test` path
--- @return report table
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

  -- ── Audio ──
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

  -- ── Text ──
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
  -- A bulletin ("*") is public by definition and the transport requires
  -- allowPlaintext for it — same rule mail follows. A unicast announcement
  -- stays sealed, so refuse-plaintext still applies where it can.
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

-- ============================================================
-- Receiving (the rc.d service)
-- ============================================================

local running = false
local lastPopupAt = nil

--- Raise an announcement as a dialog box in the operator's face.
---
--- Goes through kernel.notify rather than drawing: this runs in the mesh
--- handler's context, where no tab owns the screen and painting would
--- corrupt whatever does. notify holds it until a shell's idle tick, and
--- enforces limits underneath the Intercom's own — our severity cooldown
--- decides whether an announcement DESERVES a popup; notify's floor
--- decides whether the operator can stand one right now. Both have to say
--- yes, which is the correct order of authority.
---
--- Exposed so the tests can inject a fake notify and assert what a
--- received announcement would put on screen.
function M.raise(ann, notifyMod)
  notifyMod = notifyMod or soft("kernel.notify")
  if not (notifyMod and notifyMod.post) then return nil, "no notify facility" end
  local sev = tostring(ann.severity or "alert")
  return notifyMod.post({
    from    = "intercom",
    -- Severity maps onto the shell's existing dialog styling, so an alert
    -- LOOKS like an alert rather than like an install prompt.
    style   = (sev == "critical") and "danger" or "warn",
    title   = "ANNOUNCEMENT \226\128\148 " .. sev:upper(),
    message = tostring(ann.text or "")
      .. (ann.cue and ("\n\n(tape cue: " .. tostring(ann.cue) .. ")") or ""),
    buttons = { "Acknowledge" },
    -- An announcement that couldn't be shown for two minutes is stale:
    -- whatever it was about has been resolved or has killed you.
    ttl     = 120,
  })
end

--- Deliver one announcement locally. Exposed (rather than buried in the
--- handler closure) so tests can drive the whole receive path with no
--- network: pass the announcement and a clock, get the plan back.
function M.deliver(ann, now, deps)
  deps = deps or {}
  local store = deps.fs or fs
  local ser   = deps.serialize or serialize
  local cfg   = deps.cfg or M.loadCfg(store, ser)
  now = now or (computer and computer.uptime and computer.uptime()) or 0

  local plan = M.receivePlan(cfg, ann, deps.lastPopupAt or lastPopupAt, now)
  if not plan.accept then return plan end

  -- Always spool. The log is what an operator reads after the fact, and
  -- it must not depend on whether anyone was looking at the time.
  local spool = M.loadSpool(store, ser)
  ann.rxSeq = (tonumber(spool[#spool] and spool[#spool].rxSeq) or 0) + 1
  M.saveSpool(M.spoolAppend(spool, ann), store, ser)

  if plan.popup then
    local id, why = M.raise(ann, deps.notify)
    plan.raised = id ~= nil
    -- A refused raise is normal (notify's floor said the operator is
    -- already being interrupted enough). The announcement is still
    -- spooled and still reaches chat, so nothing is lost — say why in the
    -- plan so a caller/test can see the difference between "we chose not
    -- to interrupt" and "we were not allowed to".
    if not id then plan.why = "popup refused: " .. tostring(why) end
    lastPopupAt = now
    if deps.setLastPopup then deps.setLastPopup(now) end
  end

  -- Echo onto this machine's own tape, if the operator asked for that and
  -- the cue exists in OUR catalog (positions are per-tape, so a cue name
  -- from another machine is only meaningful if we have the same recording).
  if cfg.echoToTape and ann.cue then
    local cues = M.loadCatalog(store)
    local mine = M.findCue(cues, ann.cue)
    if mine then pcall(M.playCue, M.findDrive(), mine) end
  end

  log.info("intercom", "Heard " .. M.formatLine(ann))
  return plan
end

--- rc.d start hook: register the mesh delivery handler.
function M.start()
  if running then return true end
  if not (net and net.meshOn) then
    log.warn("intercom", "no mesh transport — the receiver cannot start")
    return false, "mesh unavailable"
  end
  net.meshOn(M.SVC, function(msg, env)
    -- Return truthy only when we ACCEPTED it: the transport ACKs on that,
    -- and a machine that filtered an announcement out must not claim
    -- delivery (the sender would stop retrying to a listener that would
    -- have wanted it).
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

--- Forget the popup cooldown (test hook; mirrors notify._reset / apps._reset).
--- The cooldown deliberately lives in a module upvalue so it survives across
--- deliveries — which is exactly why a test that wants a clean clock needs a
--- way to say so.
function M._reset() lastPopupAt = nil end

return M
