-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Command Executor                 ║
-- ║  Parse and run commands, handle pipes and redirects  ║
-- ╚══════════════════════════════════════════════════════╝

local helpers = require("shell.panels.helpers")
-- The editor is required LAZILY, and only to open a view tab for long
-- output. The CLI runs this same executor and has no tabs — it supplies
-- its own deps.showOutput — so a file-scope require here would drag the
-- whole tab/editor tree into a shell that never opens one, on the box
-- least able to afford it.
local editorMod = nil
local function getEditor()
  if editorMod == nil then
    local ok, m = pcall(require, "shell.panels.editor")
    editorMod = ok and m or false
  end
  return editorMod or nil
end

-- Cooperative slice (#REV multi-seat freeze): kernel.process's throttled
-- yield, resolved once. A no-op if the kernel module is unavailable
-- (off-box tests) or we're not inside a yieldable process.
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
  local C = deps.C  -- command table from commands.lua

  -- #SEC M4 — quote-aware tokenization. The old loop (`%S+`) broke
  -- filenames with spaces and didn't recognize quoted strings. New
  -- behaviour: single-quoted strings are literal; double-quoted strings
  -- preserve embedded spaces; backslash before a delimiter escapes it.
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
        if i <= n then i = i + 1 end  -- consume closing '
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

  -- ── Full-screen hand-off ──────────────────────────────────────────
  -- Spawn `fn` as a seat-bound process that owns the display, and step
  -- the shell aside. Returns true when the program really was handed the
  -- seat; false means "couldn't — run it inline like we always did".
  --
  -- Text the program prints still reaches the operator: it runs in the
  -- same Lua state, so its `o` accumulates into a table that is dropped
  -- into S.outLines when it exits and the shell is told to repaint.
  -- (`ttt help` prints and exits immediately — that path must not
  -- silently eat its output.)
  local function handOff(name, fn, args, screenReq, bgPolicy)
    local okP, proc = pcall(require, "kernel.process")
    if not okP or type(proc) ~= "table" or not proc.spawn then return false end
    local seat = S.displayIdx
    if not seat then return false end                 -- no seat, no hand-off
    local me = proc.current and proc.current()
    local shellPid = me and me.pid
    if not shellPid then return false end             -- not in a process

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
      -- Give the seat back. Restore the resolution policy first so the
      -- shell is laid out for the size it is about to repaint into.
      if fitted and screenMod and screenMod.restore then
        pcall(screenMod.restore, seat)
      end
      S._program = nil
      -- Drop the program's tab chip. Closing by IDENTITY, not by a
      -- remembered index: other tabs may have opened or closed while
      -- the program was in the background.
      local okT, tabsMod = pcall(require, "shell.panels.tabs")
      if okT and tabsMod then
        for i, t in ipairs(S.tabs or {}) do
          if t.type == "program" and t.pid == pid then
            t.pid = nil            -- already dead; don't let onClose kill it
            pcall(tabsMod.close, S, i)
            break
          end
        end
      end
      -- The program drew through a raw GPU proxy, past the seat's
      -- dirty-cell shadow: drop it or the repaint below elides
      -- "unchanged" cells and the shell comes back half-painted.
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

    -- Record it so Ctrl+B (kernel) knows what to suspend and the shell
    -- knows something else owns the screen.
    S._program = { pid = pid, name = name, seat = seat }
    -- Give it a TAB. This is what makes it more than "minimized": once
    -- Ctrl+B brings you back to the shell, the program is a chip in the
    -- top bar like Desktop or Monitor, and F2/clicking it hands the seat
    -- back. The chip brackets itself while the program is still being
    -- scheduled and goes plain once the scheduler freezes it.
    local okT, tabsMod = pcall(require, "shell.panels.tabs")
    if okT and tabsMod then
      pcall(tabsMod.create, S, "program", name,
        { pid = pid, seat = seat, prog = name, live = true })
    end
    -- The SAME suspension the monitor-tab switch uses: the shell keeps
    -- ticking in the background on nil resumes, and must not paint a
    -- status bar over the program. Input arriving (or tos_focus) lifts
    -- it, and events.lua polls kernel.isForeground as a backstop for a
    -- program that dies without signalling.
    S.suspendIdleDraw = true
    if S.D and S.D.invalidate then pcall(S.D.invalidate) end
    proc.setForeground(pid, seat, { kernel = true })
    return true
  end

  local function execSingle(cmdStr, inputData, allowHandOff)
    local parts = tokenize(cmdStr)
    if #parts == 0 then return "" end
    -- Per-user aliases, expanded before dispatch so the expansion meets the
    -- same tier gates as a typed command (helpers.expandAlias).
    parts = helpers.expandAlias(S, parts)
    if #parts == 0 then return "" end
    local name = parts[1]:lower()
    -- Record the command being dispatched so the tier gates (helpers
    -- adminOnly/rootOnly) can name it when they record a denial for `why`.
    S.curCmd = name
    local args = {}
    for i = 2, #parts do args[#args + 1] = parts[i] end

    local buf = {}
    local function o(text, color)
      buf[#buf + 1] = { tostring(text), color or T.fg }
      -- Cooperative slice for other seats (#REV multi-seat freeze):
      -- every command funnels output through here, so long printing
      -- commands (ls -R, du, find, verify) yield for free. Throttled
      -- inside — a no-op until this resume has run >50ms.
      coopYield()
    end

    -- If there's piped input, make it available for stdin-consuming commands
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
    local screenReq = nil
    local foreignDraw = false   -- ran code that may draw RAW to the GPU
    local fullscreen, bgPolicy = false, "drowsy"
    if not fn then
      -- Package-provided command: module-style packages run via pkg's own
      -- sandboxed dispatch (the legacy kernel.modules path was retired).
      local okP, pkgMod = pcall(require, "kernel.pkg")
      if okP and pkgMod and pkgMod.getCommand then
        fn = pkgMod.getCommand(name)
        foreignDraw = fn ~= nil
        -- A packaged program may declare a screen size it needs; fit the
        -- display to it before running and restore the boot policy after.
        if fn and pkgMod.getCommandScreen then screenReq = pkgMod.getCommandScreen(name) end
        if fn and pkgMod.getCommandFullscreen then
          fullscreen = pkgMod.getCommandFullscreen(name)
          if pkgMod.getCommandBackground then
            bgPolicy = pkgMod.getCommandBackground(name)
          end
        end
      end
    end

    -- ── Hand a FULL-SCREEN program the seat as its own process ────────
    -- Until now a package program ran INLINE — pcall(fn, ...) inside the
    -- shell's own coroutine — so the shell could not run again until the
    -- program exited. That is why calc/tetris held the seat: not a
    -- scheduling limit (sandboxed pullSignal yields, other seats stayed
    -- live), just the shell being stuck on its own call stack.
    --
    -- Spawned as a seat-bound process it becomes suspendable: Ctrl+B
    -- hands the seat back to the shell and leaves the program running in
    -- the background under its declared policy (see kernel.process's
    -- background lifecycle), and the Ctrl+T switcher brings it back.
    --
    -- This is the SAME shape the Ctrl+T Monitor has always used
    -- (kernel/init.lua): spawn, setForeground, tos_focus on the way back.
    if fn and fullscreen and allowHandOff then
      if handOff(name, fn, args, screenReq, bgPolicy) then return {} end
      -- Falling through means we could not spawn (no scheduler, no seat):
      -- run it inline exactly as before rather than refusing to run it.
    end

    -- #REV (v1.4.0 emulator round) — a sandboxed package command (tetris)
    -- draws through its `component` capability, straight past the seat's
    -- dirty-cell shadow buffer. The shadow then still believes the OLD
    -- shell screen is on the GPU, so the post-command repaint elides
    -- "unchanged" cells and the operator is left staring at the game's
    -- leftovers with only the rows whose content really changed (hint,
    -- prompt, status bar) repainted — plus menu-bar flicker as later
    -- draws fight the stale shadow. Drop the shadow after any foreign
    -- program runs, so the next full redraw actually reaches the GPU.
    local function invalidateDisplay()
      if S.D and S.D.invalidate then pcall(S.D.invalidate) end
    end
    if fn then
      local fitted = false
      if screenReq then
        -- "min" means the program needs AT LEAST this size; if the screen is
        -- already that big, leave it alone. "exact" always fits to the size.
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
        -- Restore this seat to the boot resolution policy + re-fit the layout.
        local okS, screenMod = pcall(require, "kernel.screen")
        if okS and screenMod and screenMod.restore then pcall(screenMod.restore, S.displayIdx) end
        local okSM, SM = pcall(require, "shell.panels.state")
        if okSM and SM and SM.recomputeLayout then pcall(SM.recomputeLayout, S) end
      end
    else
      -- #SEC H9 — only resolve unqualified names against a fixed set of
      -- system bin directories, with PATH honoured only where its entries
      -- are also safe. The rule itself now lives in helpers.resolveProgram
      -- so `which` reports exactly what this line will run; see the #SEC H9
      -- note there for the full rationale.
      local resolved = helpers.resolveProgram(F, name)
      if resolved then
        local data = F.readFile(resolved)
        if data then
          local fn2, err2 = load(data, "=" .. resolved, "t", makeProgramEnv{ name = resolved, stdout = function(line) o(line, T.fg) end })
          if fn2 then
            local ok2, result = pcall(fn2, table.unpack(args))
            if not ok2 then o("Error: " .. tostring(result), T.error)
            elseif result ~= nil then o(tostring(result), T.fg) end
            -- Same stale-shadow risk as package commands: a /usr/bin
            -- program can draw raw via its sandbox capabilities.
            invalidateDisplay()
          else
            o("Compile error: " .. tostring(err2), T.error)
          end
        end
      else
        -- #FIX (in-game, 2026-08-11) — DISTINGUISH "no such command" from
        -- "the command exists and could not be loaded". Seen on a box at
        -- 56 KB free: `reboot` is a perfectly real core command, but
        -- core.lua would not fit in memory, so the dispatcher returned
        -- nil and this branch called it unknown. The operator was told
        -- their OS had no `reboot`.
        --
        -- The registry knows the difference — it lists every command
        -- statically, whether or not its category has loaded — so ask it
        -- before blaming the name. commands.lua has already put the real
        -- reason in S.lastOut; the old code then overwrote it here.
        local okReg, cmdsMod = pcall(require, "shell.panels.commands")
        local known = okReg and cmdsMod.entry and cmdsMod.entry(name) or nil
        if known then
          o("'" .. name .. "' could not be loaded.", T.error)
          if S.lastOut and S.lastOut[1] then
            o(S.lastOut[1], T.error)
          else
            o("Its command group failed to load — check `log` for the reason.", T.dim)
          end
          o("Free some memory (close tabs, or reboot) and try again.", T.dim)
        else
          o("Unknown command: " .. name, T.error)
          o("Type 'help' for available commands.", T.dim)
        end
        if _G._TOS.audio then _G._TOS.audio.warning() end
      end
    end
    return buf
  end

  -- Route a command's wrapped output to the lightest surface that fits, so a
  -- few lines of result don't open a whole tab the operator then has to close:
  --   0 lines  → clear the area      1 line  → the status row (S.lastOut)
  --   ≤ MAX_INLINE → a transient inline region above the prompt (S.outLines)
  --   longer   → a real scrollable view tab (the only case that warrants one)
  local MAX_INLINE = 8
  -- A shell that has somewhere else to put output supplies it. The CLI
  -- does (it just prints every line); the panels TUI takes the default
  -- below, which is the routing it has always had.
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
      if ed then ed.openViewTab(S, wrapped, label or "output")
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
              if seg.stdout.append then
                F.appendFile(outPath, prevOutput .. "\n")
              else
                F.writeFile(outPath, prevOutput .. "\n")
              end
              helpers.refreshBrowser(S)
              S.lastOut = { "Output written to " .. seg.stdout.path, T.highlight }
            end
            return
          end

          if i == #segments then finalBuf = buf end
        end
        showOutput(helpers.expandBuf(S, finalBuf), "output")
        return
      end
    end

    -- Only the plain single-command path may hand off the seat: a
    -- program inside a pipeline has no stdout to give anyone, and a
    -- redirect wants a buffer to write.
    local buf = execSingle(input, nil, true)
    if S._program then return end   -- a full-screen program owns the seat
    showOutput(helpers.expandBuf(S, buf), input:match("^(%S+)") or "output")
  end

  -- Expose the single-command runner so `sudo <cmd>` can run one command
  -- (elevated) and CAPTURE its output buffer instead of showing it directly
  -- — avoids the double-render that calling the full exec() from inside a
  -- command would cause. No pipe/redirect handling (sudo runs one command).
  S.execOne = execSingle

  return exec
end

return M
