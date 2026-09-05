-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Shell - Commands subfile                            ║
-- ║  Auto-extracted from commands.lua during the v1.3 split  ║
-- ║  to bring per-file size under ~500 lines and enable      ║
-- ║  lazy-loading via the dispatcher.                        ║
-- ║                                                          ║
-- ║  Each subfile exports a single registration function     ║
-- ║  that adds its commands to the shared C table. The       ║
-- ║  dispatcher in commands.lua loads each subfile only on   ║
-- ║  first access to one of its commands.                    ║
-- ╚══════════════════════════════════════════════════════════╝

local computer   = require("computer")
local component  = require("component")
local helpers    = require("shell.panels.helpers")

-- Cooperative slice (#REV multi-seat freeze) for the long silent loops
-- here (deploy-drive file copy, drive check scan). Throttled inside
-- kernel.process; no-op off-box / outside a yieldable process.
local coopYield = function() end
do
  local okP, procMod = pcall(require, "kernel.process")
  if okP and procMod and procMod.yieldCooperative then
    coopYield = procMod.yieldCooperative
  end
end

return function(C, S, deps)
  -- Stable references aliased as locals (avoids per-call S/deps lookup).
  local K, E, P, F, D, U = S.K, S.E, S.P, S.F, S.D, S.U
  local SC, NM, st        = S.SC, S.NM, S.st
  local T                 = S.T
  local tier              = S.tier
  local W, H              = S.W, S.H
  local rp                = deps.rp
  local openViewTab       = deps.openViewTab
  local openEditTab       = deps.openEditTab
  local refreshBrowser    = deps.refreshBrowser
  local canRead           = deps.canRead
  local canWrite          = deps.canWrite
  local canAccess         = deps.canAccess
  local rootOnly          = deps.rootOnly
  local dialog            = deps.dialog
  local adminOnly         = deps.adminOnly
  local makeProgramEnv    = deps.makeProgramEnv
  local fmtSz             = helpers.fmtSz
  local expandBuf         = function(buf) return helpers.expandBuf(S, buf) end
  local promptInput       = deps.promptInput
  --! Framed yes/no box; text mode falls back to a [y/N] line.
  --! Both default to no. See dialogs.M.confirm -- the SAFE
  --! choice is the first button, so a click-through cancels.
  local confirmBox        = deps.confirm

  C.redstone = function(args, o)
    local ok2, rs = pcall(require, "peripheral.redstone")
    if not ok2 then o("No redstone module", T.error); return end
    if not args[1] then
      local st2 = rs.status()
      if not st2 then o("No redstone component", T.error); return end
      o(" Side      In  Out", T.title)
      for _, s in ipairs(st2) do
        o(string.format(" %-9s %2d  %2d", s.name, s.input, s.output), T.fg)
      end
    elseif args[1] == "set" and args[2] and args[3] then
      local ok3, err = rs.setOutput(args[2], tonumber(args[3]) or 15)
      o(ok3 and "Set " .. args[2] .. " = " .. args[3] or tostring(err), ok3 and T.highlight or T.error)
    elseif args[1] == "pulse" and args[2] then
      rs.pulse(args[2], tonumber(args[3]) or 0.5)
      o("Pulsed " .. args[2], T.highlight)
    else
      o("Usage: redstone [set <side> <0-15>|pulse <side> [duration]]", T.dim)
    end
  end
  C.rs = C.redstone

  -- cluster-setup — the ONE front door for standing up a cluster.
  --
  -- Lives in the base image so it can answer "what do I install, and where?"
  -- BEFORE anything is installed, which is the question operators actually
  -- get stuck on. Named `cluster-setup`, not `cluster`: a registry command
  -- shadows /usr/bin (executor.lua), so taking `cluster` would break the
  -- Master's own CLI the moment cluster-master was installed.
  --
  -- The flow itself is shell.clustersetup, which touches nothing directly —
  -- this function supplies every side effect, and the tests supply scripted
  -- answers instead.
  C["cluster-setup"] = function(args, o)
    if not rootOnly(o) then return end
    local okW, wiz = pcall(require, "shell.clustersetup")
    if not okW or not wiz then o("cluster setup module unavailable", T.error); return end

    local fsMod = _G._TOS and _G._TOS.fs
    local function pkgMod()
      local okP, p = pcall(require, "kernel.pkg"); return okP and p or nil
    end

    local SEV = { ok = T.highlight, warn = T.warning, err = T.error,
                  title = T.title }
    local ctx = {}

    ctx.say = function(text, kind) o(text or "", SEV[kind or ""] or T.fg) end

    -- Modal for choices (this is a decision, and the operator should not be
    -- able to walk past it), status-row prompt for free text.
    -- deps.dialog (not dialogs.dialog directly): the shell's wrapper repaints
    -- the screen under the box afterwards, so a wizard that raises several in
    -- a row doesn't leave holes behind.
    ctx.choose = function(title, lines, opts)
      if not dialog then                      -- CLI shell: no modal available
        ctx.say(title, "title")
        for _, l in ipairs(type(lines) == "table" and lines or { lines }) do
          ctx.say(l, nil)
        end
        for i, label in ipairs(opts) do ctx.say("  " .. i .. ". " .. label, nil) end
        local pick = tonumber(promptInput and promptInput("Choice: ", 4) or "")
        return (pick and opts[pick]) and pick or #opts
      end
      local body = type(lines) == "table" and table.concat(lines, "\n") or tostring(lines or "")
      local okD, pick = pcall(dialog, {
        title = title, message = body, buttons = opts, style = "install",
      })
      return okD and pick or #opts
    end
    ctx.ask = function(prompt, default)
      local label = prompt .. (default and (" [" .. default .. "]") or "") .. ": "
      local v = promptInput and promptInput(label, 64) or nil
      if v == nil then return default end          -- Esc with a default = accept it
      v = tostring(v):gsub("^%s+", ""):gsub("%s+$", "")
      if v == "" then return default end
      return v
    end

    ctx.installed = function(name)
      local p = pkgMod()
      return (p and p.info and p.info(name)) ~= nil
    end
    ctx.install = function(name)
      local p = pkgMod()
      if not (p and p.installByName) then return false, "package manager unavailable" end
      return p.installByName(name, { session = helpers.sessionOf(S) })
    end

    -- Atomic: /etc/*.cfg is read at boot by a daemon, and a truncating write
    -- that died halfway would leave an unparseable config on a machine whose
    -- whole job is to come back up on its own.
    ctx.writeFile = function(path, data)
      if not fsMod then return false, "filesystem unavailable" end
      if fsMod.writeFileAtomic then return fsMod.writeFileAtomic(path, data) end
      return fsMod.writeFile(path, data)
    end

    ctx.startService = function(svcName)
      local okR, rc = pcall(require, "kernel.rc")
      if not (okR and rc and rc.start) then return false, "rc unavailable" end
      local okS, err = rc.start(svcName)
      -- "Already running" is success from the operator's point of view.
      if not okS and tostring(err):find("Already running", 1, true) then return true end
      return okS, err
    end

    -- #FIX — the rc BOOT marker is /etc/rc.d/<svc>.disabled, not the
    -- package's `state` byte (that gates command dispatch). rc.start()
    -- already REMOVES the marker to persist an enable, so honouring "no"
    -- means putting it back after starting. The old installer wrote the
    -- wrong file entirely, which is why its "start at boot?" question had
    -- no effect whichever way you answered it.
    ctx.setBootStart = function(svcName, on)
      if not fsMod then return false, "filesystem unavailable" end
      local marker = "/etc/rc.d/" .. svcName .. ".disabled"
      if on then
        if fsMod.exists(marker) then return fsMod.remove(marker) end
        return true
      end
      if fsMod.exists(marker) then return true end
      return fsMod.writeFile(marker, "1")
    end

    ctx.modemCount = function()
      local total, wireless = 0, 0
      for addr, ctype in component.list() do
        if ctype == "modem" then
          total = total + 1
          local okP, prx = pcall(component.proxy, addr)
          if okP and prx and prx.isWireless and prx.isWireless() then
            wireless = wireless + 1
          end
        end
      end
      return total, wireless
    end
    ctx.myModemAddress = function() return (component.list("modem")()) end
    ctx.hostname = function()
      local NMx = _G._TOS and _G._TOS.net
      if NMx and NMx.getHostname then return NMx.getHostname() end
      if fsMod and fsMod.exists("/etc/hostname") then
        local h = fsMod.readFile("/etc/hostname")
        if type(h) == "string" then return (h:match("^[^\n]*")) end
      end
    end

    ctx.startPairing = function()
      local okA, api = pcall(require, "cluster.api")
      if not okA or not api or not api.startPairing then
        return nil, "the Master daemon is not up yet"
      end
      return api.startPairing()
    end
    ctx.pairWith = function(addr, code)
      local okM, mgr = pcall(require, "cluster-manager")
      if not okM or not mgr or not mgr.pair then
        return false, "cluster-manager library not loadable"
      end
      return mgr.pair(addr, code)
    end

    -- `cluster-setup explain` just prints the topology and stops — for an
    -- operator who wants to know what they're in for before committing.
    if (args[1] or ""):lower() == "explain" then
      o("=== What a cluster is made of ===", T.title)
      for _, line in ipairs(wiz.explain()) do o(line, T.fg) end
      return
    end

    local okRun, res = pcall(wiz.run, ctx)
    if not okRun then o("Setup failed: " .. tostring(res), T.error) end
    refreshBrowser()
  end

  -- Intercom — thin BASE stub for the intercom ADD-ON (same shape as the
  -- mail stub below). The package owns the catalog, the tape and the mesh
  -- service; this is the privileged glue that gives it the shell's display.
  C.intercom = function(args, o)
    local okLib, ic = pcall(require, "intercom")
    if not okLib or type(ic) ~= "table" or not ic.announce then
      o("The Intercom is an add-on and isn't installed on this machine.", T.error)
      o("Install it from the Optional Utilities disk:  pkg install intercom", T.dim)
      o("(then `service start intercom` so this box will HEAR announcements)", T.dim)
      return
    end
    local fsMod = _G._TOS and _G._TOS.fs
    local sub = (args[1] or ""):lower()

    -- Flags anywhere; the rest are positional words.
    local flags, rest = {}, {}
    do
      local skip
      for i = 2, #args do
        local a = tostring(args[i])
        if i == skip then                                -- consumed as a value
        elseif a:sub(1, 2) == "--" then
          local k, v = a:match("^%-%-([%w%-]+)=?(.*)$")
          if k then
            if v ~= "" then flags[k] = v
            elseif (k == "severity" or k == "to" or k == "drive") and args[i + 1]
                   and tostring(args[i + 1]):sub(1, 2) ~= "--" then
              flags[k] = tostring(args[i + 1]); skip = i + 1
            else flags[k] = true end
          end
        else rest[#rest + 1] = a end
      end
    end

    local function loadCues()
      local cues, errs = ic.loadCatalog(fsMod)
      for _, e in ipairs(errs) do
        o(string.format("  catalog line %d: %s", e.line, e.why), T.warning)
      end
      return cues
    end
    local function report(rep)
      for _, e in ipairs(rep.errors or {}) do o("  " .. e, T.warning) end
      if rep.played then
        o(string.format("Playing on the tape (%.1fs).", rep.seconds or 0), T.highlight)
      end
      if rep.sent then o("Broadcast to the network.", T.highlight)
      elseif not rep.localOnly then o("Nothing was broadcast.", T.warning) end
    end

    -- No subcommand → the announcement-post TAB (cue list + heard log),
    -- mirroring how bare `mail` opens the inbox tab. `intercom status`
    -- always prints the text summary, which is what a script wants.
    if sub == "" then
      local okA, app = pcall(require, "intercomapp")
      if okA and app and app.open then app.open(S); return end
      sub = "status"   -- app unavailable (CLI shell): fall through to text
    end

    if sub == "status" then
      o("=== Intercom ===", T.title)
      local drive, why = ic.findDrive()
      if drive then
        local sz = (drive.getSize and drive.getSize()) or 0
        local ready = (drive.isReady and drive.isReady()) and "tape loaded" or "NO TAPE"
        o(string.format("  tape drive : %s, %d bytes", ready, sz),
          ready == "NO TAPE" and T.warning or T.fg)
      else
        o("  tape drive : none (" .. tostring(why) .. ") — text-only announcements", T.warning)
      end
      local cues = loadCues()
      o("  catalog    : " .. #cues .. " cue(s) in " .. ic.CUES_PATH, T.fg)
      local cfg = ic.loadCfg(fsMod)
      o("  receiving  : " .. (ic.running() and "listening" or "STOPPED (service start intercom)"),
        ic.running() and T.highlight or T.warning)
      o(string.format("  popups     : at %s and above, at most one per %ds",
        cfg.popupLevel, cfg.popupCooldown), T.fg)
      o(string.format("  filter     : ignore anything below %s", cfg.minLevel), T.dim)
      o("", T.dim)
      o("  intercom say \"...\" [--severity warn]   speak now, text only", T.dim)
      o("  intercom play <cue>                     tape + text", T.dim)
      o("  intercom test <cue>                     play it here, tell nobody", T.dim)
      o("  intercom cues | log | set <k> <v>", T.dim)

    elseif sub == "cues" or sub == "list" then
      local cues = loadCues()
      if #cues == 0 then
        o("No cues catalogued yet.", T.warning)
        o("Edit " .. ic.CUES_PATH .. " and describe what is on the tape:", T.dim)
        o('  fuel-low  [0001] "Warning: Reactor fuel low." [0005]  warn', T.dim)
        return
      end
      o(string.format(" %-16s %-7s %-7s %-8s %s", "name", "start", "end", "severity", "says"), T.title)
      for _, c in ipairs(cues) do
        o(string.format(" %-16s %-7d %-7d %-8s %s",
          c.name, c.start, c.stop, c.severity, c.text), T.fg)
      end

    elseif sub == "say" then
      local text = table.concat(rest, " ")
      if text == "" then
        o('Usage: intercom say "your announcement" [--severity warn] [--to <peer>]', T.dim)
        o("Severities: " .. table.concat(ic.SEVERITIES, " "), T.dim); return
      end
      local sev = type(flags.severity) == "string" and flags.severity or "info"
      if not ic.validSeverity(sev) then
        o("Unknown severity: " .. sev, T.error)
        o("Use one of: " .. table.concat(ic.SEVERITIES, " "), T.dim); return
      end
      o("Announcing (" .. sev .. "): " .. text, T.title)
      report(ic.announce({ text = text, severity = sev,
        to = type(flags.to) == "string" and flags.to or nil }))

    elseif sub == "play" or sub == "test" then
      local name = rest[1]
      if not name then
        o("Usage: intercom " .. sub .. " <cue>   (intercom cues to list them)", T.dim); return
      end
      local cue = ic.findCue(loadCues(), name)
      if not cue then o("No such cue: " .. name, T.error); return end
      if sub == "test" then
        -- The "check it before you trust it" path the operator asked for:
        -- plays the recording so you can hear whether the positions really
        -- bracket it, and tells nobody at all.
        o("Testing cue '" .. cue.name .. "' — playing locally, sending nothing.", T.title)
        o("  should say: " .. cue.text, T.dim)
        o("  tape " .. cue.start .. " -> " .. cue.stop, T.dim)
      else
        o("Announcing cue '" .. cue.name .. "' (" .. cue.severity .. ")", T.title)
        o("  " .. cue.text, T.fg)
      end
      report(ic.announce({ cue = cue, localOnly = (sub == "test"),
        driveAddr = type(flags.drive) == "string" and flags.drive or nil,
        to = type(flags.to) == "string" and flags.to or nil }))

    elseif sub == "log" then
      local spool = ic.loadSpool(fsMod)
      if #spool == 0 then o("Nothing heard yet.", T.dim); return end
      local n = tonumber(rest[1]) or 20
      for i = math.max(1, #spool - n + 1), #spool do
        local a = spool[i]
        local sev = a.severity or "info"
        o("  " .. ic.formatLine(a),
          (sev == "critical" or sev == "alert") and T.error
          or (sev == "warn") and T.warning or T.fg)
      end

    elseif sub == "set" then
      if not adminOnly(o) then return end
      local key, val = rest[1], rest[2]
      local cfg = ic.loadCfg(fsMod)
      if not key then
        o("Usage: intercom set <popuplevel|minlevel|cooldown|echotape> <value>", T.dim)
        o("  popuplevel <sev>   interrupt with a message box at this and above", T.dim)
        o("  minlevel   <sev>   ignore anything quieter than this", T.dim)
        o("  cooldown   <secs>  minimum quiet between message boxes", T.dim)
        o("  echotape   on|off  also play received cues on this box's tape", T.dim)
        return
      end
      key = key:lower()
      if key == "popuplevel" or key == "minlevel" then
        if not ic.validSeverity(val) then
          o("Severities: " .. table.concat(ic.SEVERITIES, " "), T.error); return
        end
        cfg[key == "popuplevel" and "popupLevel" or "minLevel"] = val
      elseif key == "cooldown" then
        local n = tonumber(val)
        if not n or n < 0 or n > 3600 then o("cooldown: 0-3600 seconds", T.error); return end
        cfg.popupCooldown = n
      elseif key == "echotape" then
        cfg.echoToTape = (val == "on" or val == "true" or val == "1")
      else
        o("Unknown setting: " .. key, T.error); return
      end
      local ok2, err = ic.saveCfg(cfg, fsMod)
      if ok2 then o("Saved.", T.highlight) else o("Save failed: " .. tostring(err), T.error) end

    else
      o("Usage: intercom [status|cues|say|play|test|log|set] ...", T.title)
      o("  intercom say \"text\" [--severity <lvl>]  announce text right now", T.dim)
      o("  intercom play <cue>                      play a tape cue AND announce it", T.dim)
      o("  intercom test <cue>                      play it here only, to check it", T.dim)
      o("  intercom cues                            what's catalogued on the tape", T.dim)
      o("  intercom log [N]                         what this box has heard", T.dim)
      o("  intercom set <key> <value>               receive policy (admin)", T.dim)
    end
  end

  -- Mail — the thin BASE stub for the mail ADD-ON (stage 5). Mail left the
  -- base image: the kernel keeps the generic mesh TRANSPORT (net.meshSend /
  -- net.meshOn, shared with chat and anything else), and mailbox semantics
  -- + the UIs live in the `mail` Optional Utilities package. This stub is
  -- the privileged glue that hands the package the shell's display and
  -- session — exactly how the base `drive` command relates to blockfs.
  -- Not installed → an honest install hint, never a broken command.
  C.mail = function(args, o)
    local okLib, mailLib = pcall(require, "mail")
    if not okLib or type(mailLib) ~= "table" or not mailLib.send then
      o("Mail is an add-on and isn't installed on this machine.", T.error)
      o("Install it from the Optional Utilities disk:  pkg install mail", T.dim)
      o("(then `service start mail` so this box can RECEIVE mail)", T.dim)
      return
    end
    if not mailLib.available() then
      o("Mail unavailable (no network hardware?)", T.error); return
    end
    mailLib.tick()                                 -- pump retries on every look
    local me  = S.who or "user"
    local sub = args[1]

    -- No subcommand → the Mail app TAB: inbox / read / compose in a
    -- persistent tab. The send/list/read/delete subcommands stay for
    -- scripting and the minimal CLI shell. `mail ui`/`mail tui` also open
    -- the tab (kept as spellings operators learned).
    if not sub or sub == "ui" or sub == "tui" then
      local okM, mailApp = pcall(require, "mailapp")
      if okM and mailApp and mailApp.open then
        mailApp.open(S)
        return
      end
      -- App unavailable → fall through to the text inbox listing below.
    end

    -- Receiving needs the rc.d service; sending/reading doesn't. Say so
    -- once, up front, instead of letting mail silently never arrive.
    if not mailLib.running() then
      o("Note: the mail service is stopped — this box won't RECEIVE mail.", T.warning)
      o("      Start it with:  service start mail", T.dim)
    end

    if sub == "send" then
      local rcpt = args[2]
      if not rcpt then o("Usage: mail send <peer|alias|user@peer|*> [subject] [body...]", T.dim); return end
      local toAddr, ruser = mailLib.resolveRecipient(rcpt,
        NM and NM.aliases and NM.aliases.resolve)
      local subject = args[3] or ""
      local body
      if args[4] then body = table.concat(args, " ", 4)
      elseif promptInput then body = promptInput("Body: ", 200) end
      if not body then o("Cancelled", T.dim); return end
      local id, sealed = mailLib.send({ to = toAddr, user = ruser, fromUser = me,
        subject = subject, body = body })
      if id then
        o("Queued " .. tostring(id):sub(1, 18) .. (sealed and "  (sealed)"
          or "  (PLAINTEXT bulletin)"),
          sealed and T.highlight or T.warning)
      else
        -- #SEC — refuse-plaintext: an unpaired unicast peer lands here.
        o("Send failed: " .. tostring(sealed), T.error)
      end

    elseif sub == "read" then
      local i   = tonumber(args[2])
      local box = mailLib.inboxBox(me)
      local m   = box and i and box:get(i)
      if not m then o("No message #" .. tostring(args[2]), T.error); return end
      box:markRead(i)
      o(string.rep("-", math.min(W, 50)), T.dim)
      o("From:    " .. (m.fromUser and (m.fromUser .. " @ ") or "") .. tostring(m.from):sub(1, 12), T.fg)
      o("Subject: " .. (m.subject ~= "" and m.subject or "(no subject)"), T.title)
      if not m.readable then o("[sealed - no shared secret to open this]", T.warning) end
      o(string.rep("-", math.min(W, 50)), T.dim)
      for line in (tostring(m.body) .. "\n"):gmatch("(.-)\n") do o(line, T.fg) end

    elseif sub == "delete" or sub == "rm" then
      local i   = tonumber(args[2])
      local box = mailLib.inboxBox(me)
      if box and i and box:delete(i) then o("Deleted #" .. i, T.highlight)
      else o("No message #" .. tostring(args[2]), T.error) end

    else  -- list (default)
      local box, boxErr = mailLib.inbox(me)
      if not box then o(tostring(boxErr), T.error); return end
      if #box == 0 then o("(inbox empty)", T.dim)
      else
        o("Inbox for " .. me .. ":", T.title)
        for i, m in ipairs(box) do
          o(mailLib.inboxRow(m, i, W - 1), m.read and T.dim or T.fg)
        end
      end
      local pend = mailLib.pending()
      if pend and pend > 0 then o(pend .. " outbound awaiting delivery", T.dim) end
      o("Commands: mail send <peer> [subj] [body] | read <n> | delete <n>", T.dim)
    end
  end

  -- RBMK reactor controller — thin BASE stub for the add-on (same
  -- relationship `mail` has with its package, and `drive` with blockfs).
  -- The controller's libraries hold raw console access and the SCRAM
  -- path, so they are deliberately unreachable from sandboxed package
  -- code; this stub is the privileged entry point.
  C.rbmk = function(args, o)
    local okLib, rbmk = pcall(require, "rbmk-cmd")
    if not okLib or type(rbmk) ~= "table" or not rbmk.run then
      o("The RBMK controller add-on isn't installed on this machine.", T.error)
      o("Install it from the Optional Utilities disk:  pkg install rbmk-control", T.dim)
      o("Then:  rbmk survey   (identifies the console's real API)", T.dim)
      return
    end
    rbmk.run(args, o)
  end

  C.robot = function(args, o)
    local ok2, rob = pcall(require, "peripheral.robot")
    if not ok2 then o("No robot module", T.error); return end
    if not rob.available() then o("Not a robot", T.error); return end
    local cmd = args[1]
    if cmd == "forward" or cmd == "fwd" then local ok3, r = rob.forward(); o(ok3 and "Moved forward" or tostring(r), ok3 and T.highlight or T.error)
    elseif cmd == "back" then local ok3, r = rob.back(); o(ok3 and "Moved back" or tostring(r), ok3 and T.highlight or T.error)
    elseif cmd == "up" then local ok3, r = rob.up(); o(ok3 and "Moved up" or tostring(r), ok3 and T.highlight or T.error)
    elseif cmd == "down" then local ok3, r = rob.down(); o(ok3 and "Moved down" or tostring(r), ok3 and T.highlight or T.error)
    elseif cmd == "left" then rob.turnLeft(); o("Turned left", T.highlight)
    elseif cmd == "right" then rob.turnRight(); o("Turned right", T.highlight)
    elseif cmd == "swing" then local ok3, r = rob.swing(args[2]); o(ok3 and "Swing!" or tostring(r), ok3 and T.highlight or T.error)
    elseif cmd == "use" then local ok3, r = rob.use(args[2]); o(ok3 and "Used!" or tostring(r), ok3 and T.highlight or T.error)
    elseif cmd == "detect" then local ok3, r = rob.detect(args[2]); o(ok3 and "Block: " .. tostring(r) or "Nothing", T.fg)
    elseif cmd == "inv" then
      local inv = rob.inventory()
      if inv then
        for _, slot in ipairs(inv) do
          if slot.count > 0 then
            o(string.format(" [%2d] %dx %s", slot.slot, slot.count, slot.name or "?"), T.fg)
          end
        end
      end
    else
      o("Usage: robot <forward|back|up|down|left|right|swing|use|detect|inv>", T.dim)
    end
  end

  C.inventory = function(args, o)
    local ok2, inv = pcall(require, "peripheral.inventory")
    if not ok2 then o("No inventory module", T.error); return end
    if not inv.available() then o("No inventory controller/transposer", T.error); return end
    local side = args[1] and (tonumber(args[1]) or args[1]) or nil
    local items = inv.list(side)
    if items then
      o(string.format(" %-4s %-24s %s", "Slot", "Item", "Count"), T.title)
      for _, item in ipairs(items) do
        if item.count > 0 then
          o(string.format(" %-4d %-24s %d", item.slot, (item.name or "?"):sub(1,24), item.count), T.fg)
        end
      end
    else
      o("Cannot read inventory", T.error)
    end
  end
  C.inv = C.inventory
  C.component = function(args, o)
    if not adminOnly(o) then return end
    if not args[1] then
      o("Usage: component <type> [method] [args...]", T.dim)
      o("  component list            List all component types", T.dim)
      o("  component gpu             Show GPU methods", T.dim)
      o("  component gpu getDepth    Call gpu.getDepth()", T.dim)
      o("  component reload-caps     Reload the cap configs (see below)", T.dim)
      return
    end
    -- FEAT-5 — admin can refresh the runtime component allowlist after
    -- editing /etc/component_caps.cfg. It also reloads the PACKAGE-cap
    -- overrides in /etc/pkg_caps.cfg: the two files are halves of one
    -- answer ("may this code touch that device?") and reloading one
    -- without the other is how an operator ends up with a component type
    -- allowed and the package that drives it still refused.
    if args[1] == "reload-caps" then
      local okS, sandbox = pcall(require, "kernel.sandbox")
      if not okS or not sandbox.reloadComponentConfig then
        o("Sandbox doesn't support reload-caps", T.error); return
      end
      local base, gated = sandbox.reloadComponentConfig()
      local nBase, nGated = 0, 0
      for _ in pairs(base or {}) do nBase = nBase + 1 end
      for _ in pairs(gated or {}) do nGated = nGated + 1 end
      o(string.format("Reloaded: %d extra base, %d extra gated types",
        nBase, nGated), T.highlight)
      local okP, pkgMod = pcall(require, "kernel.pkg")
      if okP and pkgMod and pkgMod.reloadCapConfig then
        local allow, deny = pkgMod.reloadCapConfig()
        local nAllow, nDeny = 0, 0
        for _ in pairs(allow or {}) do nAllow = nAllow + 1 end
        for pkgName, set in pairs(deny or {}) do
          for _ in pairs(set) do nDeny = nDeny + 1 end
          local _ = pkgName
        end
        o(string.format("Reloaded: %d extra package caps, %d denials",
          nAllow, nDeny), T.highlight)
        -- A package already loaded this boot kept the caps it was built
        -- with; say so rather than letting the operator assume otherwise.
        if nAllow > 0 or nDeny > 0 then
          o("Packages already loaded this boot keep their old caps.", T.dim)
        end
      end
      return
    end
    if args[1] == "list" then
      local seen = {}
      for addr, ctype in component.list() do
        if not seen[ctype] then
          seen[ctype] = 0
        end
        seen[ctype] = seen[ctype] + 1
      end
      for ctype, cnt in pairs(seen) do
        o(string.format("  %-20s x%d", ctype, cnt), T.fg)
      end
      return
    end
    -- #SEC H12 — raw component method calls bypass the capability
    -- system and can drive hardware directly (filesystem.remove,
    -- eeprom.set, ...). Restrict all proxy access to root.
    if not rootOnly(o) then return end
    local ctype = args[1]
    local proxy = component.proxy(component.list(ctype)() or "")
    if not proxy then o("No component: " .. ctype, T.error); return end
    if not args[2] then
      -- List methods
      local methods = {}
      for k, v in pairs(proxy) do
        if type(v) == "function" then methods[#methods+1] = k end
      end
      table.sort(methods)
      for _, m in ipairs(methods) do o("  " .. m .. "()", T.fg) end
    else
      -- Call method
      -- Never write the EEPROM from here; the verified `flash` command
      -- must remain the only BIOS-write path.
      if ctype == "eeprom" and (args[2] == "set" or args[2] == "setData"
         or args[2] == "makeReadonly") then
        o("Denied: use the 'flash' command to write EEPROM", T.error)
        return
      end
      local method = proxy[args[2]]
      if not method then o("Unknown method: " .. args[2], T.error); return end
      local callArgs = {}
      for i = 3, #args do
        local v = args[i]
        if v == "true" then callArgs[#callArgs+1] = true
        elseif v == "false" then callArgs[#callArgs+1] = false
        elseif tonumber(v) then callArgs[#callArgs+1] = tonumber(v)
        else callArgs[#callArgs+1] = v end
      end
      local results = table.pack(pcall(method, table.unpack(callArgs)))
      if results[1] then
        for i = 2, results.n do o("  " .. tostring(results[i]), T.fg) end
      else
        o("Error: " .. tostring(results[2]), T.error)
      end
    end
  end

  -- ── OpenOS compat info ────────────────────────────────
  -- Internet card status and a bounded fetch. The status half exists
  -- because "it doesn't work" has three completely different causes — no
  -- card, the server has HTTP off, or an admin here switched it off — and
  -- an operator who cannot tell them apart will debug the wrong one.
  C.internet = function(args, o)
    local okI, inet = pcall(require, "kernel.internet")
    if not okI or not inet then o("internet module unavailable", T.error); return end
    local sub = (args[1] or "status"):lower()

    if sub == "status" then
      local st = inet.status()
      if not st.present then
        o("No internet card installed.", T.warning)
        o("An Internet Card goes in a card slot; the machine needs no", T.dim)
        o("other change. TOS uses it for 'pkg fetch' and nothing else", T.dim)
        o("unless a package asks for the 'internet' capability.", T.dim)
        return
      end
      o("Internet card " .. tostring(st.addr), T.title)
      o("  HTTP:    " .. (st.http and "available" or "DISABLED by the server"),
        st.http and T.highlight or T.warning)
      o("  TCP:     " .. (st.tcp and "available" or "disabled by the server"),
        st.tcp and T.fg or T.dim)
      o("  Machine: " .. (st.enabled and "enabled" or "DISABLED (config: internet)"),
        st.enabled and T.highlight or T.warning)
      if st.reason then o("  -> " .. st.reason, T.warning) end
      if not st.http and st.present then
        o("", T.dim)
        o("HTTP is switched off in the SERVER's OpenComputers config,", T.dim)
        o("not in TOS. Only the server owner can change it.", T.dim)
      end

    elseif sub == "on" or sub == "off" then
      if not adminOnly(o) then return end
      local okC, cfg = pcall(require, "kernel.config")
      if not okC then o("config unavailable", T.error); return end
      cfg.set("internet", sub == "on")
      if cfg.save then pcall(cfg.save) end
      o("Internet access " .. (sub == "on" and "enabled" or "disabled")
        .. " on this machine.", T.highlight)

    elseif sub == "get" then
      if not args[2] then o("Usage: internet get <url>", T.dim); return end
      local body, err, meta = inet.get(args[2])
      if not body then o(tostring(err), T.error); return end
      o(string.format("%d bytes%s", #body,
        (meta and meta.status) and ("  (HTTP " .. tostring(meta.status) .. ")") or ""),
        T.dim)
      -- Print it, but never more than fits a screenful — this is a status
      -- tool, not a pager, and a 64 KB body would bury the shell.
      local shown = 0
      for line in body:gmatch("([^\n]*)\n?") do
        if shown >= 20 then o("... (truncated)", T.dim); break end
        o(line, T.fg); shown = shown + 1
      end

    else
      o("Usage: internet [status|get <url>|on|off]", T.dim)
    end
  end

  C.compat = function(args, o)
    local ok2, compatMod = pcall(require, "compat")
    if not ok2 then o("Compat layer not loaded", T.error); return end
    local mods = compatMod.list()
    o(" OpenOS Compatibility Layer", T.title)
    o(string.format(" %-16s %s", "Module", "Status"), T.dim)
    for _, m in ipairs(mods) do
      o(string.format(" %-16s %s", m.name, m.loaded and "loaded" or "not loaded"),
        m.loaded and T.highlight or T.dim)
    end
  end
  -- (The legacy `mod` command was removed — the module manager it fronted was
  -- retired in v1.3.1. Its unique subcommands, `enable`/`disable`/`commands`,
  -- were folded into `pkg`; use `pkg enable|disable|commands|info` instead.)

  -- ── Disk manager ──────────────────────────────────────
  C.disk = function(args, o)
    local sub = args[1]
    if not sub or sub == "list" then
      -- List all mounted removable disks
      local fsList = F.mounts and F.mounts() or nil
      if fsList and type(fsList) == "table" and #fsList > 0 then
        -- Use mount list from kernel fs
        local removable = {}
        for _, m in ipairs(fsList) do
          if m.mountPoint ~= "/" then
            removable[#removable + 1] = m
          end
        end
        if #removable == 0 then
          o("No removable disks mounted", T.dim)
        else
          o(string.format(" %-16s %-10s %s", "Mount", "Label", "Status"), T.title)
          o(string.rep("-", 42), T.dim)
          for _, m in ipairs(removable) do
            local mnt = m.mountPoint
            local info = helpers.classifyDisk(F, mnt)
            local label = (m.label or ""):sub(1, 10)
            o(string.format(" %-16s %-10s %s", mnt:sub(1,16), label, info.desc),
              info.kind ~= "data" and T.highlight or T.fg)
          end
        end
      elseif F.exists("/mnt") then
        -- Fallback: scan /mnt/
        local entries = F.list("/mnt")
        if entries and #entries == 0 then
          o("No removable disks mounted", T.dim)
        elseif entries then
          o(string.format(" %-16s %-8s %s", "Mount", "Type", "Status"), T.title)
          o(string.rep("-", 42), T.dim)
          for _, name in ipairs(entries) do
            local mnt = "/mnt/" .. name:gsub("/$", "")
            local info = helpers.classifyDisk(F, mnt)
            o(string.format(" %-16s %-8s %s", mnt:sub(1,16), "disk", info.desc),
              info.kind ~= "data" and T.highlight or T.fg)
          end
        else
          o("No removable disks mounted", T.dim)
        end
      else
        o("No removable disks mounted", T.dim)
      end
      --! Raw drives are NOT filesystems, so nothing above can list them:
      --! `disk` and `mount` both walk MOUNTED filesystems, and an
      --! unmanaged drive has none until it is formatted and mounted. That
      --! is correct and completely opaque -- an operator with a raw drive
      --! attached sees "No removable disks mounted", concludes the drive
      --! is not being detected, and has no way to learn that `drive` is
      --! the command that sees it. Say so, but only when there is
      --! actually one attached, so the hint never becomes noise.
      do
        local raw = 0
        for _ in component.list("drive", true) do raw = raw + 1 end
        if raw > 0 then
          o("", T.dim)
          o(raw .. " unmanaged (raw) drive(s) attached — not filesystems, so", T.warning)
          o("they cannot appear above until formatted and mounted.", T.dim)
          o("  drive list          see them, with address and capacity", T.dim)
          o("  drive format <addr> make one a TBFS filesystem", T.dim)
        end
      end
      o("disk info <mnt> for details  ·  df for space  ·  jbod to pool disks", T.dim)
    elseif sub == "info" then
      if not args[2] then o("Usage: disk info <mount-point>", T.dim); return end
      local mnt = F.normalize(args[2])
      if not F.exists(mnt) or not F.isDirectory(mnt) then
        o("Not a valid mount point: " .. mnt, T.error); return
      end
      local total = F.spaceTotal(mnt)
      local free = F.spaceFree(mnt)
      o(" Mount: " .. mnt, T.title)
      if total and total > 0 then
        o(string.format(" Space: %dK free / %dK total",
          math.floor(free / 1024), math.floor(total / 1024)), T.fg)
      end
      local info = helpers.classifyDisk(F, mnt)
      o(" Contains: " .. info.desc, info.kind ~= "data" and T.highlight or T.dim)
      if info.hint then o("   -> " .. info.hint, T.dim) end
    elseif sub == "install" then
      -- (v1.4.0 consolidation: installing is pkg's job — this branch
      -- duplicated `pkg install-dir` / `pkg from-floppy` with a third
      -- syntax. `disk` keeps its real niche: removable media.)
      o("'disk install' folded into the package manager:", T.warning)
      o("  pkg install              scan all mounts, confirm per package", T.dim)
      o("  pkg install <mnt>        install one specific directory", T.dim)
    elseif sub == "export" then
      -- 'disk export' built a module-format disk; that left with the legacy
      -- module system (v1.3.1). Building an install disk is now the Optional
      -- Utilities builder's job.
      o("'disk export' was removed with the legacy module system.", T.warning)
      o("To build an install disk for add-ons, use the Optional Utilities", T.dim)
      o("builder: TOS-Extras/build/build-disk.lua.", T.dim)
      o("For a full TOS image, use 'deploy <mount>' instead.", T.dim)
    elseif sub == "eject" then
      if not args[2] then o("Usage: disk eject <mount-point>", T.dim); return end
      local mnt = F.normalize(args[2])
      local ok3, err = F.unmount(mnt)
      if ok3 then o("Ejected: " .. mnt, T.highlight)
      else o("Eject failed: " .. tostring(err), T.error) end
    else
      o("Usage: disk [list|info <mnt>|eject <mnt>]", T.dim)
      o("  Removable disks + what's on them.  Install packages: 'pkg'.", T.dim)
      o("  Pool several disks into one: 'jbod'.   Free space per mount: 'df'.", T.dim)
    end
  end
  -- ── Unmanaged (raw block) drives ─────────────────────────
  -- Managed disks (`disk`, `df`) present a ready-made file API. UNMANAGED
  -- drives are raw `drive` components (readSector/writeSector) with no
  -- filesystem at all. This command is base — detection + raw inspection
  -- always work — but format/mount/check/defrag need the `blockfs`
  -- package (TBFS), which lays a real hierarchical filesystem onto the
  -- bare sectors so the drive mounts like any other TOS disk.
  C.drive = function(args, o)
    local sub = args[1]
    local function bf()
      local ok, mod = pcall(require, "blockfs")
      return ok and mod or nil
    end
    -- EXACT match (the `true`): OC's component.list filters by SUBSTRING,
    -- so a bare "drive" also returns `tape_drive` and `disk_drive`. This
    -- command formats and writes to what it finds — offering a tape or a
    -- floppy drive as an unmanaged block device would be a genuinely
    -- destructive mistake, not just a mislabel.
    local function proxyFor(prefix)
      local matches = {}
      for addr in component.list("drive", true) do
        if not prefix or addr:sub(1, #prefix) == prefix then matches[#matches + 1] = addr end
      end
      table.sort(matches)
      if #matches == 0 then return nil, "no unmanaged drive found" .. (prefix and (" for '" .. prefix .. "'") or "") end
      if prefix and #matches > 1 then return nil, "ambiguous prefix '" .. prefix .. "' (" .. #matches .. " drives)" end
      local addr = matches[1]
      local okP, px = pcall(component.proxy, addr)
      if not okP or not px then return nil, "cannot proxy drive" end
      return px, addr
    end

    if not sub or sub == "list" then
      o("Unmanaged drives (raw block devices):", T.title)
      local n, lib = 0, bf()
      for addr in component.list("drive", true) do   -- exact: not tape_/disk_drive
        local okP, px = pcall(component.proxy, addr)
        if okP and px then
          n = n + 1
          local ss  = (px.getSectorSize and px.getSectorSize()) or 0
          local cap = (px.getCapacity and px.getCapacity()) or 0
          local pl  = (px.getPlatterCount and px.getPlatterCount()) or 1
          local fsinfo = "unformatted"
          if lib then
            local s = lib.stats(px)
            if s then fsinfo = string.format('TBFS "%s"  %s used  %d%% frag',
              s.label, fmtSz(s.usedBlocks * s.sectorSize), math.floor(s.fragmentation * 100 + 0.5)) end
          end
          o(string.format("  %s  %s  %dB/sector  %d platter(s)  %s",
            addr:sub(1, 8) .. "...", fmtSz(cap), ss, pl, fsinfo), T.fg)
        end
      end
      if n == 0 then
        o("  (none attached)", T.dim)
        o("  Managed disks appear under 'disk' / 'df'; this is for raw drives.", T.dim)
      elseif not lib then
        o("  Install 'blockfs' to format/mount them:  pkg install blockfs", T.dim)
      else
        o("  format | mount | check [--repair] | defrag [--if-over N] | read | write", T.dim)
      end
      return
    end

    if sub == "info" then
      local px, addr = proxyFor(args[2])
      if not px then o(tostring(addr), T.error); return end
      o("Drive " .. addr:sub(1, 8) .. "...", T.title)
      o(string.format("  capacity   %s", fmtSz((px.getCapacity and px.getCapacity()) or 0)), T.fg)
      o(string.format("  sector     %d bytes", (px.getSectorSize and px.getSectorSize()) or 0), T.fg)
      o(string.format("  platters   %d", (px.getPlatterCount and px.getPlatterCount()) or 1), T.fg)
      local lib = bf()
      if lib then
        local s = lib.stats(px)
        if s then
          o("  TBFS volume:", T.highlight)
          o(string.format('    label "%s"   %s / %s used   %d file(s), %d dir(s)',
            s.label, fmtSz(s.usedBlocks * s.sectorSize), fmtSz(s.dataBlocks * s.sectorSize),
            s.files, s.dirs), T.fg)
          o(string.format("    fragmentation %d%%   %s",
            math.floor(s.fragmentation * 100 + 0.5), s.clean and "clean" or "DIRTY (mounted or unclean)"), T.fg)
        else o("  (not a TBFS volume — unformatted or foreign)", T.dim) end
      else o("  (install 'blockfs' to read the filesystem)", T.dim) end
      return
    end

    -- Everything below needs the filesystem driver + admin.
    local lib = bf()
    if not lib then o("The 'blockfs' package is required:  pkg install blockfs", T.error); return end

    if sub == "format" then
      if not adminOnly(o) then return end
      local px, addr = proxyFor(args[2])
      if not px then o(tostring(addr), T.error); return end
      local label = args[3] or ("disk" .. addr:sub(1, 4))
      local okFmt
      if confirmBox then
        okFmt = confirmBox(
          "Format drive " .. addr:sub(1, 8) .. "... as TBFS?" .. "\n\n" ..
          "Every file on it is destroyed. There is no undo and no\n" ..
          "recovery tool in TOS that can bring it back.",
          { title = "Format drive", severity = "danger",
            yes = "Format", no = "Cancel" })
      else
        local ans = promptInput and promptInput("FORMAT " .. addr:sub(1, 8) ..
          "... as TBFS? destroys all data [y/N]: ", 4) or "n"
        okFmt = (ans or ""):lower() == "y"
      end
      if not okFmt then o("Cancelled.", T.dim); return end
      local ok2, err = lib.format(px, { label = label, now = function() return math.floor(K.uptime and K.uptime() or 0) end })
      if ok2 then o('Formatted as TBFS "' .. label .. '". Mount with: drive mount ' .. addr:sub(1, 8), T.highlight)
      else o("Format failed: " .. tostring(err), T.error) end
      return
    end

    if sub == "mount" then
      if not adminOnly(o) then return end
      local px, addr = proxyFor(args[2])
      if not px then o(tostring(addr), T.error); return end
      local nowfn = function() return math.floor(K.uptime and K.uptime() or 0) end
      local proxy, fsOrErr = lib.mount(px, { now = nowfn })
      if not proxy then o("Mount failed: " .. tostring(fsOrErr), T.error); return end
      local label = proxy.getLabel() or ("disk_" .. addr:sub(1, 4))
      local mnt = args[3] or ("/mnt/" .. label)
      if mnt:sub(1, 1) ~= "/" then mnt = "/mnt/" .. mnt end
      if not F.exists("/mnt") then pcall(F.makeDirectory, "/mnt") end
      if not F.exists(mnt) then pcall(F.makeDirectory, mnt) end
      local sess = helpers.sessionOf(S)
      local mok, merr = F.mount(mnt, proxy, sess)
      if mok == false then o(tostring(merr or "mount failed"), T.error); return end
      o("Mounted TBFS at " .. mnt, T.highlight)
      -- Auto-defrag advisory: a heavily fragmented volume seeks a lot on
      -- the simulated head. Nudge (don't force) at mount time.
      local s = lib.stats(px)
      if s and s.fragmentation > 0.30 then
        o(string.format("  Note: %d%% fragmented — 'drive defrag %s' to compact.",
          math.floor(s.fragmentation * 100 + 0.5), addr:sub(1, 8)), T.warning)
      end
      pcall(refreshBrowser)
      return
    end

    if sub == "check" or sub == "fsck" then
      if not adminOnly(o) then return end
      local px, addr = proxyFor(args[2])
      if not px then o(tostring(addr), T.error); return end
      local repair = args[3] == "--repair" or args[3] == "-r"
      local res = lib.check(px, { repair = repair, yield = coopYield })
      if not res then o("Not a TBFS volume.", T.error); return end
      if res.ok then o("TBFS clean: no problems.", T.highlight)
      else
        o((res.repaired and "Repaired. Findings:" or "Problems found:"), res.repaired and T.highlight or T.warning)
        for _, p in ipairs(res.problems) do o("  - " .. p, T.dim) end
        if not repair and not res.ok then o("  Run 'drive check " .. addr:sub(1, 8) .. " --repair' to fix.", T.dim) end
      end
      return
    end

    if sub == "defrag" then
      if not adminOnly(o) then return end
      local px, addr = proxyFor(args[2])
      if not px then o(tostring(addr), T.error); return end
      -- --if-over N : only defrag when fragmentation ≥ N% (cron-friendly
      -- automatic mode). No flag = always (manual mode).
      local threshold = nil
      for i = 3, #args do
        if args[i] == "--if-over" and args[i + 1] then threshold = tonumber(args[i + 1]) end
      end
      if threshold then
        local s = lib.stats(px)
        if s and (s.fragmentation * 100) < threshold then
          o(string.format("Fragmentation %d%% below %d%% — skipped.",
            math.floor(s.fragmentation * 100 + 0.5), threshold), T.dim)
          return
        end
      end
      o("Defragmenting...", T.title)
      local dr, derr = lib.defrag(px, { now = function() return math.floor(K.uptime and K.uptime() or 0) end })
      if not dr then o("Defrag failed: " .. tostring(derr), T.error); return end
      o(string.format("Defragmented %d block(s): %d%% -> %d%% fragmented.",
        dr.moved, math.floor(dr.before * 100 + 0.5), math.floor(dr.after * 100 + 0.5)), T.highlight)
      return
    end

    if sub == "read" then
      local px, addr = proxyFor(args[2])
      if not px then o(tostring(addr), T.error); return end
      local sec = tonumber(args[3])
      if not sec then o("Usage: drive read <addr> <sector>", T.dim); return end
      local ok2, data = pcall(px.readSector, sec + 1)   -- OC sectors 1-indexed
      if not ok2 then o("Read failed: " .. tostring(data), T.error); return end
      -- Hex dump the first 64 bytes (a sector is big; keep it readable).
      local bytes = {}
      for i = 1, math.min(64, #(data or "")) do bytes[#bytes + 1] = string.format("%02X", (data):byte(i)) end
      o("Sector " .. sec .. " (first 64 bytes):", T.title)
      o("  " .. table.concat(bytes, " "), T.dim)
      return
    end

    if sub == "write" then
      if not adminOnly(o) then return end
      o("'drive write' is intentionally not exposed as a one-liner (a stray", T.warning)
      o("sector write corrupts a filesystem). Use the blockfs API from 'lua'", T.dim)
      o("for deliberate raw writes. Format/mount/defrag cover normal use.", T.dim)
      return
    end

    o("Usage: drive [list | info <addr> | format <addr> [label] | mount <addr> [path]", T.dim)
    o("             | check <addr> [--repair] | defrag <addr> [--if-over N] | read <addr> <sec>]", T.dim)
  end

  C.tape = function(args, o)
    -- Delegate to the tape package's command if it's installed + enabled.
    local ok2, pkgMod = pcall(require, "kernel.pkg")
    if ok2 and pkgMod and pkgMod.getCommand then
      local fn = pkgMod.getCommand("tape")
      if fn then fn(args, o); return end
      -- Installed but disabled?
      if pkgMod.info and pkgMod.info("tape") then
        o("The tape package is installed but not enabled.", T.warning)
        o("Enable it with:  pkg enable tape", T.highlight)
        return
      end
    end
    -- Not installed — show guidance
    o("Tape Storage", T.title)
    o("", T.fg)
    o("The 'tape' package isn't installed. To use Computronics tapes:", T.fg)
    o("", T.fg)
    o(" Install from the Optional Utilities disk:", T.highlight)
    o("    pkg install              (with the disk inserted)", T.dim)
    o("  or, if it's in a configured repo:", T.dim)
    o("    pkg install tape", T.dim)
    o("", T.fg)
    o(" Build your own: a /usr/modules/<name>/init.lua returning", T.dim)
    o("   { commands = { tape = function(args, o) ... end } }", T.dim)
    o(" plus a package.lua manifest (kind=\"command\"). See the TOS Manual.", T.dim)
  end

  -- ── Deploy command ─────────────────────────────────────
  C.deploy = function(args, o)
    if not rootOnly(o) then return end

    -- ── Deploy onto an UNMANAGED (raw) drive as a bootable TBFS volume ──
    -- `deploy drive <addr>`: format the raw drive with TBFS + a boot
    -- region, copy the OS onto it, and write the stage-2 boot blob. This
    -- needs the blockfs package (TBFS lives in it); if TOS doesn't have
    -- blockfs, fail LOUDLY with the fix rather than half-writing a disk.
    if args[1] == "drive" then
      local okBF, blockfs = pcall(require, "blockfs")
      if not okBF or not blockfs then
        o("Cannot deploy to a raw drive: TOS doesn't have the 'blockfs' package.", T.error)
        o("blockfs is the filesystem that makes a raw drive usable + bootable.", T.dim)
        o("Install it first, then retry:", T.dim)
        o("    pkg install blockfs", T.highlight)
        return
      end
      -- The driver SOURCE (for embedding in the boot blob). The installed
      -- package puts it here; if it's missing the package is broken.
      local blockfsSrc = F.exists("/usr/lib/blockfs.lua") and F.readFile("/usr/lib/blockfs.lua")
      if not blockfsSrc then
        o("blockfs is loadable but /usr/lib/blockfs.lua is missing — reinstall it:", T.error)
        o("    pkg install blockfs", T.highlight)
        return
      end
      -- Resolve the drive component (prefix match).
      local addrs = {}
      for a in component.list("drive", true) do       -- exact: not tape_/disk_drive
        if not args[2] or a:sub(1, #args[2]) == args[2] then addrs[#addrs + 1] = a end
      end
      table.sort(addrs)
      if #addrs == 0 then o("No unmanaged drive" .. (args[2] and (" matching '" .. args[2] .. "'") or "") .. " found.", T.error); return end
      if args[2] and #addrs > 1 then o("Ambiguous prefix '" .. args[2] .. "' (" .. #addrs .. " drives).", T.error); return end
      local addr = addrs[1]
      local okP, drive = pcall(component.proxy, addr)
      if not okP or not drive then o("Cannot proxy drive " .. addr:sub(1, 8), T.error); return end

      -- Assemble the boot blob NOW so we can size the boot region for it.
      local blob = blockfs.bootBlob(blockfsSrc)
      local bootBytes = #blob + 4096   -- slack for the length header + growth

      local okInst
      if confirmBox then
        okInst = confirmBox(
          "Install TOS onto raw drive " .. addr:sub(1, 8) .. "...?" .. "\n\n" ..
          "The drive is erased and reformatted as bootable TBFS.\n" ..
          "Anything on it now is gone.",
          { title = "Erase and install", severity = "danger",
            yes = "Erase", no = "Cancel" })
      else
        local ans = promptInput and promptInput(
          "Install TOS onto raw drive " .. addr:sub(1, 8) .. "...? ERASES it [y/N]: ", 4) or "n"
        okInst = (ans or ""):lower() == "y"
      end
      if not okInst then o("Cancelled.", T.dim); return end

      local nowfn = function() return math.floor((K.uptime and K.uptime()) or 0) end
      o("Formatting " .. addr:sub(1, 8) .. "... as bootable TBFS...", T.title)
      local okF, ferr = blockfs.format(drive, { label = "tos", bootBytes = bootBytes, now = nowfn })
      if not okF then o("Format failed: " .. tostring(ferr) .. " (drive too small?)", T.error); return end
      local proxy, mErr = blockfs.mount(drive, { now = nowfn })
      if not proxy then o("Mount failed: " .. tostring(mErr), T.error); return end

      -- Copy the OS: every manifest file, creating parent dirs as we go.
      local files = {}
      local okM, manifest = pcall(require, "system_manifest")
      if okM and type(manifest) == "table" then
        for _, e in ipairs(manifest) do
          if type(e) == "table" and type(e.path) == "string" then files[#files + 1] = e.path end
        end
      end
      if #files == 0 then o("system_manifest not loadable — aborting.", T.error); return end
      local copied, failed = 0, 0
      for _, path in ipairs(files) do
        coopYield()   -- whole-OS copy: give other seats a slice per file
        local content = F.readFile(path)
        if content then
          -- Create the parent directory chain.
          local dir = path:match("^(.*)/[^/]+$")
          if dir and dir ~= "" then
            local acc = ""
            for seg in dir:gmatch("[^/]+") do
              acc = acc .. "/" .. seg
              if not proxy.exists(acc) then proxy.makeDirectory(acc) end
            end
          end
          local h = proxy.open(path, "w")
          if h and proxy.write(h, content) then proxy.close(h); copied = copied + 1
          else if h then proxy.close(h) end; failed = failed + 1; o("  FAIL " .. path, T.error) end
        end
      end
      -- Write the stage-2 boot blob into the reserved boot region.
      local wok, werr = blockfs.writeBoot(drive, blob)
      proxy.unmount()
      o("", T.fg)
      if wok and failed == 0 then
        o(string.format("TBFS install written: %d files + boot blob (%s).", copied, fmtSz(#blob)), T.highlight)
        o("The TOS BIOS boots TBFS drives directly. If this box runs an older", T.dim)
        o("EEPROM, reflash first: 'flash /bios.lua'.", T.dim)
        o("The disk also mounts like any volume: 'drive mount " .. addr:sub(1, 8) .. "'.", T.dim)
      else
        o(string.format("Wrote %d files, %d failed; boot blob: %s.", copied, failed,
          wok and "ok" or ("FAILED (" .. tostring(werr) .. ")")), T.error)
      end
      return
    end

    local target = args[1]
    if not target then
      o("Usage: deploy <mount-point>   |   deploy drive <addr>  (raw disk, needs blockfs)", T.dim)
      o("  Creates a TOS install disk on a floppy or drive.", T.dim)
      o("  e.g. deploy /mnt/floppy", T.dim)
      o("  Insert the disk on another OpenOS computer and run:", T.dim)
      o("    # /mnt/<disk>/install.lua", T.dim)
      return
    end
    target = F.normalize(target)
    if #target > 1 and target:sub(-1) == "/" then
      target = target:sub(1, -2)
    end

    -- Refuse to deploy onto the running system. `/`, `/tos`, `/etc`,
    -- etc. would overwrite live files and most likely brick the host.
    -- Require an external mount like /mnt/floppy instead.
    local FORBIDDEN = { "/", "/tos", "/etc", "/var", "/usr", "/home", "/root", "/public" }
    for _, p in ipairs(FORBIDDEN) do
      if target == p or target:sub(1, #p + 1) == p .. "/" then
        o("Refusing to deploy onto '" .. target .. "' (would overwrite system).", T.error)
        o("Deploy only to an external mount such as /mnt/floppy.", T.dim)
        return
      end
    end

    if not F.exists(target) or not F.isDirectory(target) then
      o("Target does not exist or is not a directory: " .. target, T.error)
      return
    end

    o("Creating TOS install disk on " .. target .. " ...", T.title)

    -- Check available space (best-effort)
    local total = F.spaceTotal(target)
    local free  = F.spaceFree(target)
    if total and total > 0 then
      o(string.format(" Target disk: %dK total, %dK free",
        math.floor(total / 1024), math.floor(free / 1024)), T.dim)
    end

    -- Directories to create on install media
    local dirs = {
      "/tos/", "/tos/kernel/", "/tos/kernel/net/", "/tos/shell/",
      "/tos/compat/", "/tos/peripheral/",
    }
    for _, d in ipairs(dirs) do
      F.makeDirectory(target .. d)
    end

    -- System files to include on the install disk (#119/#156 —
    -- sourced from /tos/system_manifest.lua so deploy, verify, and
    -- installer all agree on the canonical file list instead of each
    -- carrying its own hand-maintained copy). Any file present in the
    -- manifest gets copied; if the manifest isn't readable we fall
    -- back to a minimal list that at least produces a bootable disk.
    local files = {}
    do
      local ok1, manifest = pcall(require, "system_manifest")
      if ok1 and type(manifest) == "table" then
        for _, entry in ipairs(manifest) do
          if type(entry) == "table" and type(entry.path) == "string" then
            files[#files + 1] = entry.path
          end
        end
      end
      if #files == 0 then
        o("  WARN: system_manifest not loadable, using minimal file list", T.warning)
        files = {
          "/init.lua",
          "/tos/kernel/init.lua", "/tos/kernel/hal.lua",
          "/tos/kernel/event.lua", "/tos/kernel/process.lua",
          "/tos/kernel/fs.lua", "/tos/kernel/display.lua",
          "/tos/kernel/log.lua", "/tos/kernel/serialize.lua",
          "/tos/shell/init.lua",
        }
      end
    end

    local copied, failed, skipped = 0, 0, 0
    for _, path in ipairs(files) do
      local content = F.readFile(path)
      if content then
        local ok2, werr = F.writeFile(target .. path, content)
        if ok2 then copied = copied + 1
        else o("  FAIL " .. path .. ": " .. tostring(werr), T.error); failed = failed + 1 end
      else skipped = skipped + 1 end
    end

    -- Copy bios.lua
    if F.exists("/bios.lua") then
      local bc = F.readFile("/bios.lua")
      if bc then
        if F.writeFile(target .. "/bios.lua", bc) then copied = copied + 1
        else failed = failed + 1 end
      end
    end

    -- Copy install.lua — the unified installer that auto-detects
    -- the install disk, copies files, runs the setup questionnaire,
    -- and offers to flash the BIOS on the target machine.
    if F.exists("/install.lua") then
      local ic = F.readFile("/install.lua")
      if ic then
        local ok3, werr = F.writeFile(target .. "/install.lua", ic)
        if ok3 then
          copied = copied + 1
          o("  Copied install.lua (automated installer)", T.highlight)
        else
          o("  FAIL writing install.lua: " .. tostring(werr), T.error)
          failed = failed + 1
        end
      end
    else
      o("  WARNING: /install.lua not found on boot drive", T.error)
      o("  The install disk will not have an automated installer.", T.dim)
    end

    o("", T.fg)
    if failed == 0 then
      o("Install disk created: " .. copied .. " files", T.highlight)
      o("", T.fg)
      o("On the target machine (OpenOS), run:", T.dim)
      o("  # " .. target .. "/install.lua", T.fg)
      o("Or insert the disk and run: /mnt/<disk>/install.lua", T.dim)
    else
      o(copied .. " files copied, " .. failed .. " failed", T.error)
    end
  end
  C.chat = function(args, o)
    if not NM then o("No network available", T.error); return end
    -- Chat is an app TAB now (stage 4): it stays open, and messages
    -- keep arriving (unread badge) while you work in other tabs.
    local ok2, chatApp = pcall(require, "shell.panels.chatapp")
    if not ok2 then o("Chat unavailable: " .. tostring(chatApp), T.error); return end
    chatApp.open(S)
  end

  -- ── Remote exec ───────────────────────────────────────
  C.rsh = function(args, o)
    if not adminOnly(o) then return end
    if not args[1] or not args[2] then o("Usage: rsh <address> <command>", T.dim); return end
    if not NM then o("No network available", T.error); return end
    local ok2, remoteMod = pcall(require, "kernel.net.remote")
    if not ok2 then o("Remote module unavailable", T.error); return end
    local addr = args[1]
    local cmd = table.concat(args, " ", 2)
    o("Executing on " .. addr:sub(1,8) .. "...", T.dim)
    local result, err = remoteMod.execute(addr, cmd)
    if result then o(result, T.fg)
    else o("Error: " .. tostring(err), T.error) end
  end

  -- ── File transfer ─────────────────────────────────────
  C.scp = function(args, o)
    if not adminOnly(o) then return end
    if not args[1] or not args[2] then
      o("Usage: scp <address>:<remote_path> <local_path>", T.dim)
      o("   or: scp <local_path> <address>:<remote_path>", T.dim)
      return
    end
    if not NM then o("No network available", T.error); return end
    local ok2, transferMod = pcall(require, "kernel.net.transfer")
    if not ok2 then o("Transfer module unavailable", T.error); return end
    -- Parse address:path format
    local addr, rpath = args[1]:match("^([^:]+):(.+)$")
    if addr then
      -- Download: scp addr:remote local
      local lpath = rp(args[2])
      o("Downloading " .. rpath .. " from " .. addr:sub(1,8) .. "...", T.dim)
      local ok3, err = transferMod.request(addr, rpath, lpath)
      if ok3 then
        refreshBrowser()
        o("Downloaded: " .. rpath .. " -> " .. lpath, T.highlight)
      else o("Transfer failed: " .. tostring(err), T.error) end
    else
      o("Usage: scp <address>:<remote_path> <local_path>", T.dim)
    end
  end

  -- ── Screen switching ──────────────────────────────────
  C.screen = function(args, o)
    local ok2, screenMod = pcall(require, "kernel.screen")
    if not ok2 then o("Screen module unavailable", T.error); return end
    if args[1] == "res" then
      -- Show or change the screen resolution policy. With no value it reports
      -- current/max/blocks + the configured policy. With a value it writes the
      -- policy to config (authoritative next boot) and applies it live now.
      local gpu = D.getGpu and D.getGpu()
      local curW, curH = D.getSize()
      local maxW, maxH = curW, curH
      if gpu then local okM, mw, mh = pcall(gpu.maxResolution); if okM and mw then maxW, maxH = mw, mh end end
      local cfg = K.getConfig and K.getConfig()
      local val = args[2]
      if not val then
        o("=== Screen Resolution ===", T.title)
        o(string.format("Current : %dx%d", curW or 0, curH or 0), T.fg)
        o(string.format("Maximum : %dx%d", maxW or 0, maxH or 0), T.dim)
        if gpu and gpu.getScreen then
          local okS, s = pcall(gpu.getScreen)
          if okS and type(s) == "string" then
            local okA, aw, ah = pcall(require("component").invoke, s, "getAspectRatio")
            if okA and aw then o(string.format("Blocks  : %dx%d (physical)", aw, ah), T.dim) end
          end
        end
        o("Policy  : " .. ((cfg and cfg.get and cfg.get("screenRes")) or "auto"), T.fg)
        o("Set: screen res <auto|max|WxH>   (e.g. screen res 80x25)", T.dim)
        return
      end
      if not adminOnly(o) then return end
      local vl = tostring(val):lower()
      if vl ~= "auto" and vl ~= "max" and not vl:match("^%d+%s*[x×]%s*%d+$") then
        o("Usage: screen res <auto|max|WxH>", T.error); return
      end
      if cfg and cfg.set then cfg.set("screenRes", vl); if cfg.save then cfg.save() end end
      -- Apply live to THIS seat: refresh the policy from config, fit the
      -- display, re-fit the panels layout to the new size, and redraw.
      screenMod.setPolicy(screenMod.specFromConfig(cfg))
      local w, h, note = screenMod.fitDisplay(S.displayIdx)
      local okSM, SM = pcall(require, "shell.panels.state")
      if okSM and SM and SM.recomputeLayout then SM.recomputeLayout(S) end
      if deps.drawAll then pcall(deps.drawAll) end
      o(string.format("Resolution -> %dx%d (policy '%s')", w or curW or 0, h or curH or 0, vl), T.highlight)
      if note then o(note, T.warning) end
      o("Applied now and saved for next boot.", T.dim)
      return
    end
    if args[1] == "list" or not args[1] then
      local screens = screenMod.list()
      if #screens == 0 then o("No displays", T.dim); return end
      for _, s in ipairs(screens) do
        local mark = s.active and " * " or "   "
        o(string.format("%s%d: %s (%dx%d %d-bit)", mark, s.index, s.label, s.w, s.h, s.depth), T.fg)
      end
    elseif args[1] == "next" then
      screenMod.next()
      o("Switched to: " .. screenMod.active().label, T.highlight)
    elseif tonumber(args[1]) then
      if screenMod.setActive(tonumber(args[1])) then
        o("Switched to screen " .. args[1], T.highlight)
      else o("Invalid screen index", T.error) end
    else
      o("Usage: screen [list|next|<index>|res [auto|max|WxH]]", T.dim)
    end
  end
  local function ext(name)
    return function(args, o)
      local ok2, m2 = pcall(require, "shell.ext")
      if ok2 and m2[name] then
        m2[name](args, { K=K, E=E, P=P, F=F, D=D, U=U, o=o, st=st,
                        computer=computer, cwd=S.cwd })
      else
        if name == "logout" then E.push("tos_logout", S.displayIdx)
        else o("Extension unavailable (low RAM?)", T.error) end
      end
    end
  end
  for _, n in ipairs({ "net", "ping", "hostname", "config", "battery", "audio" }) do
    C[n] = ext(n)
  end

end
