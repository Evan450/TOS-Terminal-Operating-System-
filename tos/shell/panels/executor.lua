local helpers = require("shell.panels.helpers")

local editorMod = nil
local function getEditor()
  if editorMod == nil then
    local ok, m = pcall(require, "shell.panels.editor")
    editorMod = ok and m or false
  end
  return editorMod or nil
end

local coopYield = function() end
do
  local okP, procMod = pcall(require, "kernel.process")
  if okP and procMod and procMod.yieldCooperative then
    coopYield = procMod.yieldCooperative
  end
end

local M = {}

function M.build(S, deps)
  local F = S.F
  local T = S.T
  local rp = deps.rp
  local makeProgramEnv = deps.makeProgramEnv
  local C = deps.C

  local function tokenize(cmdStr)
    local parts, cur = {}, nil
    local i, n = 1, #cmdStr
    local function push() if cur then parts[#parts + 1] = cur; cur = nil end end
    while i <= n do
      local c = cmdStr:sub(i, i)
      if c == " " or c == "\t" then
        push(); i = i + 1
      elseif c == "'" then
        cur = cur or ""
        i = i + 1
        while i <= n and cmdStr:sub(i, i) ~= "'" do
          cur = cur .. cmdStr:sub(i, i); i = i + 1
        end
        if i <= n then i = i + 1 end
      elseif c == '"' then
        cur = cur or ""
        i = i + 1
        while i <= n and cmdStr:sub(i, i) ~= '"' do
          if cmdStr:sub(i, i) == '\\' and i < n then
            cur = cur .. cmdStr:sub(i + 1, i + 1); i = i + 2
          else
            cur = cur .. cmdStr:sub(i, i); i = i + 1
          end
        end
        if i <= n then i = i + 1 end
      elseif c == '\\' and i < n then
        cur = (cur or "") .. cmdStr:sub(i + 1, i + 1); i = i + 2
      else
        cur = (cur or "") .. c; i = i + 1
      end
    end
    push()
    return parts
  end

  local function handOff(name, fn, args, screenReq, bgPolicy)
    local okP, proc = pcall(require, "kernel.process")
    if not okP or type(proc) ~= "table" or not proc.spawn then return false end
    local seat = S.displayIdx
    if not seat then return false end
    local me = proc.current and proc.current()
    local shellPid = me and me.pid
    if not shellPid then return false end

    local okS, screenMod = pcall(require, "kernel.screen")
    screenMod = okS and screenMod or nil
    local fitted = false
    if screenReq and screenMod and screenMod.fitDisplay then
      local alreadyEnough = screenReq.mode == "min"
        and (S.W or 0) >= screenReq.width and (S.H or 0) >= screenReq.height
      if not alreadyEnough then
        local w = screenMod.fitDisplay(seat,
          { mode = "size", w = screenReq.width, h = screenReq.height })
        fitted = w ~= nil
      end
    end

    local printed = {}
    local function progOut(text, color)
      printed[#printed + 1] = { tostring(text), color or T.fg }
    end

    local pid
    pid = proc.spawn("prog:" .. name .. "@" .. seat, function()
      local ok, err = pcall(fn, args, progOut)
      if not ok then
        printed[#printed + 1] = { "Error: " .. tostring(err), T.error }
      end

      if fitted and screenMod and screenMod.restore then
        pcall(screenMod.restore, seat)
      end
      S._program = nil

      local okT, tabsMod = pcall(require, "shell.panels.tabs")
      if okT and tabsMod then
        for i, t in ipairs(S.tabs or {}) do
          if t.type == "program" and t.pid == pid then
            t.pid = nil
            pcall(tabsMod.close, S, i)
            break
          end
        end
      end

      if S.D and S.D.invalidate then pcall(S.D.invalidate) end
      if #printed > 0 then S.outLines = helpers.expandBuf(S, printed) end
      local sp = proc.get and proc.get(shellPid)
      if sp and sp.state ~= proc.STATE.DEAD then
        proc.setForeground(shellPid, seat, { kernel = true })
        ;(proc.signalKernel or proc.signal)(shellPid, "tos_focus")
      end
    end, {
      priority   = 3,
      source     = "user",
      principal  = helpers.sessionOf and helpers.sessionOf(S) or nil,
      token      = S.st,
      display    = seat,
      background = bgPolicy,
    })
    if not pid then
      if fitted and screenMod and screenMod.restore then pcall(screenMod.restore, seat) end
      return false
    end

    S._program = { pid = pid, name = name, seat = seat }

    local okT, tabsMod = pcall(require, "shell.panels.tabs")
    if okT and tabsMod then
      pcall(tabsMod.create, S, "program", name,
        { pid = pid, seat = seat, prog = name, live = true })
    end

    S.suspendIdleDraw = true
    if S.D and S.D.invalidate then pcall(S.D.invalidate) end
    proc.setForeground(pid, seat, { kernel = true })
    return true
  end

  local function execSingle(cmdStr, inputData, allowHandOff)
    local parts = tokenize(cmdStr)
    if #parts == 0 then return "" end

    parts = helpers.expandAlias(S, parts)
    if #parts == 0 then return "" end
    local name = parts[1]:lower()

    S.curCmd = name

    if name ~= "why" then helpers.clearFailure(S) end
    local args = {}
    for i = 2, #parts do args[#args + 1] = parts[i] end

    local buf = {}
    local function o(text, color)
      buf[#buf + 1] = { tostring(text), color or T.fg }

      if color == T.error and name ~= "why" then
        helpers.noteFailure(S, name, text)
      end

      coopYield()
    end

    if inputData and #inputData > 0 then
      if name == "grep" and #args >= 1 and not args[2] then
        local pat = args[1]
        for line in inputData:gmatch("([^\n]*)\n?") do
          if line:find(pat, 1, true) then o(line, T.fg) end
        end
        return buf
      elseif name == "wc" and #args == 0 then
        local lc, wc2, bc = 0, 0, #inputData
        for _ in inputData:gmatch("\n") do lc = lc + 1 end
        for _ in inputData:gmatch("%S+") do wc2 = wc2 + 1 end
        o(string.format(" %d lines  %d words  %d bytes", lc, wc2, bc), T.fg)
        return buf
      end
    end

    local fn = C[name]
    --! #SEC (pentest, Sep 2026) — the REGISTRY tier is enforced here, at the
    --! one dispatch point both shells share (cli.lua builds this executor
    --! too). It used to be read only by `help`, so any command whose body
    --! had no adminOnly/rootOnly of its own ran for anyone below its declared
    --! tier: a GUEST, or a first-boot restricted token, could `drive read`
    --! raw sectors, `redstone set`, `robot`, `tape`, `chat`. In-body gates
    --! stay -- they carry the finer per-subcommand rules -- but nothing runs
    --! below the tier the registry declares. Aliases carry their own entry.
    --! Resolved through the seat token (helpers.liveTier), so sudo's swapped
    --! token counts and an expired one drops to GUEST. (test_dispatch_tier.lua)
    if fn then
      local okReg, cmdsMod = pcall(require, "shell.panels.commands")
      local meta = okReg and type(cmdsMod) == "table" and cmdsMod.entry
        and cmdsMod.entry(name) or nil
      local need = meta and tonumber(meta.tier) or 0
      if need > 0 then
        local have = helpers.liveTier and helpers.liveTier(S) or 0
        if have < need then
          local msg = "Permission denied: '" .. name .. "' needs "
            .. (helpers.tierName and helpers.tierName(need) or ("tier " .. need))
            .. "  [E-403 ERR_TIER_REQUIRED]"
          if helpers.fail then helpers.fail(S, msg, o) else o(msg, T.error) end
          S.lastDenial = { cmd = name, need = need, have = have }
          return buf
        end
      end
    end
    local screenReq = nil
    local foreignDraw = false
    local fullscreen, bgPolicy = false, "drowsy"
    if not fn then

      local okP, pkgMod = pcall(require, "kernel.pkg")
      if okP and pkgMod and pkgMod.getCommand then
        fn = pkgMod.getCommand(name)
        foreignDraw = fn ~= nil

        if fn and pkgMod.getCommandScreen then screenReq = pkgMod.getCommandScreen(name) end
        if fn and pkgMod.getCommandFullscreen then
          fullscreen = pkgMod.getCommandFullscreen(name)
          if pkgMod.getCommandBackground then
            bgPolicy = pkgMod.getCommandBackground(name)
          end
        end
      end
    end

    if fn and fullscreen and allowHandOff then
      if handOff(name, fn, args, screenReq, bgPolicy) then return {} end

    end

    local function invalidateDisplay()
      if S.D and S.D.invalidate then pcall(S.D.invalidate) end
    end
    if fn then
      local fitted = false
      if screenReq then

        local alreadyEnough = screenReq.mode == "min"
          and (S.W or 0) >= screenReq.width and (S.H or 0) >= screenReq.height
        if not alreadyEnough then
          local okS, screenMod = pcall(require, "kernel.screen")
          if okS and screenMod and screenMod.fitDisplay then
            local w, h, note = screenMod.fitDisplay(S.displayIdx, {
              mode = "size", w = screenReq.width, h = screenReq.height })
            if w then fitted = true end
            if note then o(note, T.warning) end
          end
        end
      end
      local ok2, err2 = pcall(fn, args, o)
      if not ok2 then o("Error: " .. tostring(err2), T.error) end
      if foreignDraw then invalidateDisplay() end
      if fitted then

        local okS, screenMod = pcall(require, "kernel.screen")
        if okS and screenMod and screenMod.restore then pcall(screenMod.restore, S.displayIdx) end
        local okSM, SM = pcall(require, "shell.panels.state")
        if okSM and SM and SM.recomputeLayout then pcall(SM.recomputeLayout, S) end
      end
    else

      local resolved = helpers.resolveProgram(F, name)
      if resolved then
        local data = F.readFile(resolved)
        if data then
          local fn2, err2 = load(data, "=" .. resolved, "t", makeProgramEnv{ name = resolved, stdout = function(line) o(line, T.fg) end })
          if fn2 then
            local ok2, result = pcall(fn2, table.unpack(args))
            if not ok2 then o("Error: " .. tostring(result), T.error)
            elseif result ~= nil then o(tostring(result), T.fg) end

            invalidateDisplay()
          else
            o("Compile error: " .. tostring(err2), T.error)
          end
        end
      else

        local okReg, cmdsMod = pcall(require, "shell.panels.commands")
        local known = okReg and cmdsMod.entry and cmdsMod.entry(name) or nil
        if known then
          o("'" .. name .. "' could not be loaded.  [E-802 ERR_CMD_UNLOADABLE]", T.error)
          if S.lastOut and S.lastOut[1] then
            o(S.lastOut[1], T.error)
          else
            o("Its command group failed to load — check `log` for the reason.", T.dim)
          end
          o("Free some memory (close tabs, or reboot) and try again.", T.dim)
        else
          o("Unknown command: " .. name .. "  [E-801 ERR_UNKNOWN_CMD]", T.error)
          o("Type 'help' for available commands.", T.dim)
        end
        if _G._TOS.audio then _G._TOS.audio.warning() end
      end
    end
    return buf
  end

  local MAX_INLINE = 8

  local showOutput = deps.showOutput or function(wrapped, label)
    S.lastOut = nil
    S.outLines = nil
    local route = helpers.routeOutput(#wrapped, MAX_INLINE)
    if route == "status" then
      S.lastOut = wrapped[1]
    elseif route == "inline" then
      S.outLines = wrapped
    elseif route == "tab" then
      local ed = getEditor()
      if ed then ed.openViewTab(S, wrapped, label or "output", true)
      else S.outLines = wrapped end
    end
  end

  local function exec(input)
    local hasPipe = input:find("|", 1, true)
    local hasRedirect = input:find("[>]") or input:find("<")

    if hasPipe or hasRedirect then
      local ok2, pipeMod = pcall(require, "kernel.pipe")
      if ok2 then
        local segments = pipeMod.parse(input)
        local prevOutput = nil
        local finalBuf = {}
        for i, seg in ipairs(segments) do
          local buf = execSingle(seg.cmd, prevOutput)
          local textParts = {}
          for _, e in ipairs(buf) do
            textParts[#textParts + 1] = type(e) == "table" and e[1] or tostring(e)
          end
          prevOutput = table.concat(textParts, "\n")

          if seg.stdout and seg.stdout.type == "file" then
            local outPath = rp(seg.stdout.path)
            if helpers.canWrite(S, outPath) then
              --! Say what happened (pentest, Sep 2026). The write's result
              --! was dropped, so a refusal the ACL check above cannot see --
              --! the protected-path guard, a full disk, a directory -- still
              --! reported "Output written" for a file that never changed.
              local okW, werr
              if seg.stdout.append then
                okW, werr = F.appendFile(outPath, prevOutput .. "\n")
              else
                okW, werr = F.writeFile(outPath, prevOutput .. "\n")
              end
              helpers.refreshBrowser(S)
              if okW then
                S.lastOut = { "Output written to " .. seg.stdout.path, T.highlight }
              else
                S.lastOut = { "Not written: " .. tostring(werr or seg.stdout.path), T.error }
              end
            end
            return
          end

          if i == #segments then finalBuf = buf end
        end
        showOutput(helpers.expandBuf(S, finalBuf), "output")
        return
      end
    end

    local buf = execSingle(input, nil, true)
    if S._program then return end
    showOutput(helpers.expandBuf(S, buf), input:match("^(%S+)") or "output")
  end

  S.execOne = execSingle

  return exec
end

return M
