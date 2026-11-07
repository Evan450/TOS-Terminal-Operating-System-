-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
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

--! Read-only status commands where `-f` means "follow": a live tab. Only
--! these, because -f is NOT free in general -- `trash restore` and admin's
--! user commands read it as --force. `--live` works on any command.
local LIVE_SHORT = { ps = true, df = true, mem = true, uptime = true, log = true,
                     net = true, battery = true, lsdev = true }
M.LIVE_SHORT = LIVE_SHORT

-- #SEC M4 — quote-aware tokenization. The old loop (`%S+`) broke
-- filenames with spaces and didn't recognize quoted strings. Behaviour:
-- single-quoted strings are literal; double-quoted strings preserve
-- embedded spaces; backslash before a delimiter escapes it.
--
-- Hoisted out of M.build (it closed over nothing from there — only its
-- own parameter) because it's the ONE place in the executor that ran a
-- string concatenation PER BYTE of the command line: `cur = cur .. c`,
-- once per character, both for the common unquoted-token case and inside
-- both quote styles. Lua strings are immutable, so that's a fresh
-- allocation on every character — O(n^2) in the length of a single
-- token. Rewritten to accumulate whole SPANS (the run up to the next
-- delimiter, quote-close or escape) via string.sub and only join them
-- with table.concat once, per token. Same external behaviour, verified
-- against the original byte-by-byte version across quoting/escaping/
-- unterminated-input cases. (test_executor_tokenize.lua)
--- $NAME and ${NAME} from this process's environment. Not inside single
--- quotes, and a name that is not set stays as typed, so a stray $ in a
--- message is left alone.
local function expandVars(cmdStr, read)
  if not cmdStr:find("$", 1, true) then return cmdStr end
  local out, i, n, quoted = {}, 1, #cmdStr, false
  while i <= n do
    local c = cmdStr:sub(i, i)
    if c == "'" then quoted = not quoted end
    local name, stop
    if c == "$" and not quoted then
      name = cmdStr:match("^%$([%a_][%w_]*)", i)
      if name then stop = i + #name
      else
        name = cmdStr:match("^%${([%a_][%w_]*)}", i)
        if name then stop = i + #name + 2 end
      end
    end
    local value = name and read(name)
    if value ~= nil then
      out[#out + 1] = tostring(value)
      i = stop + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function tokenize(cmdStr)
  local parts, curParts = {}, nil
  local i, n = 1, #cmdStr
  local function flush(from, to)
    if to >= from then
      curParts = curParts or {}
      curParts[#curParts + 1] = cmdStr:sub(from, to)
    end
  end
  local function push()
    if curParts then
      parts[#parts + 1] = table.concat(curParts)
      curParts = nil
    end
  end
  while i <= n do
    local c = cmdStr:sub(i, i)
    if c == " " or c == "\t" then
      push(); i = i + 1
    elseif c == "'" then
      curParts = curParts or {}
      i = i + 1
      local closeAt = cmdStr:find("'", i, true)
      if closeAt then
        flush(i, closeAt - 1)
        i = closeAt + 1  -- consume closing '
      else
        flush(i, n)
        i = n + 1
      end
    elseif c == '"' then
      curParts = curParts or {}
      i = i + 1
      local segStart = i
      while i <= n and cmdStr:sub(i, i) ~= '"' do
        if cmdStr:sub(i, i) == '\\' and i < n then
          flush(segStart, i - 1)
          flush(i + 1, i + 1)
          i = i + 2
          segStart = i
        else
          i = i + 1
        end
      end
      flush(segStart, i - 1)
      if i <= n then i = i + 1 end
    elseif c == '\\' and i < n then
      curParts = curParts or {}
      flush(i + 1, i + 1)
      i = i + 2
    else
      -- Ordinary run: scan ahead to the next delimiter/quote/backslash
      -- and take the whole span at once instead of one piece per byte.
      -- Starts the scan at i+1 (not i) so a trailing lone backslash at
      -- end-of-string — which falls through to this branch because the
      -- backslash-escape case above requires i < n — still consumes
      -- itself instead of looping forever on the same position.
      curParts = curParts or {}
      local segStart = i
      i = i + 1
      while i <= n do
        local cc = cmdStr:sub(i, i)
        if cc == " " or cc == "\t" or cc == "'" or cc == '"' or cc == "\\" then break end
        i = i + 1
      end
      flush(segStart, i - 1)
    end
  end
  push()
  return parts
end

-- Test hook only: tokenize has no dependency on M.build's closure, so it
-- is testable directly rather than through a full shell session.
M._tokenize = tokenize

function M.build(S, deps)
  local F = S.F
  local T = S.T
  local rp = deps.rp
  local makeProgramEnv = deps.makeProgramEnv
  local C = deps.C  -- command table from commands.lua

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
      -- Clear the record only if it is still OURS: with two programs
      -- backgrounded, the older one's exit must not erase the newer one's.
      if S._program and S._program.pid == pid then S._program = nil end
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

  --! What to do about a command that would not load for memory. Below TOS's
  --! floor, closing tabs or rebooting can never free enough, so the advice
  --! is to add memory. (bootcfg.FLOOR_KB, test_below_floor.lua)
  local function memoryAdvice()
    local bcfg = package.loaded["kernel.bootcfg"]
    local have = type(bcfg) == "table" and bcfg.belowFloor and bcfg.belowFloor()
    if have then
      return string.format("This machine has %d KB and TOS needs %d KB: add memory.",
        have, bcfg.FLOOR_KB)
    end
    return "Free some memory (close tabs, or reboot) and try again."
  end

  local function execSingle(cmdStr, inputData, allowHandOff)
    do
      local okE, envMod = pcall(require, "kernel.env")
      local okP, P = pcall(require, "kernel.process")
      if okE and type(envMod) == "table" and envMod.read then
        local cur = okP and type(P) == "table" and P.current and P.current() or nil
        cmdStr = expandVars(cmdStr, function(name) return envMod.read(cur, name) end)
      end
    end
    local parts = tokenize(cmdStr)
    if #parts == 0 then return "" end
    -- Per-user aliases, expanded before dispatch so the expansion meets the
    -- same tier gates as a typed command (helpers.expandAlias).
    parts = helpers.expandAlias(S, parts)
    if #parts == 0 then return "" end
    local name = parts[1]:lower()
    --! `ps --live` (or `ps -f`, for LIVE_SHORT) IS `watch ps`: the live tab,
    --! reached from the command already being typed. Only on the plain path
    --! (allowHandOff): a pipeline stage's output belongs to the pipe, and
    --! `sudo` runs exactly what it was given. Rewritten BEFORE dispatch, so
    --! it meets the same tier gate typing `watch` would, and watch itself
    --! refuses anything interactive. (test_live_flag.lua)
    if allowHandOff and name ~= "watch" then
      for i = 2, #parts do
        if parts[i] == "--live" or (parts[i] == "-f" and LIVE_SHORT[name]) then
          table.remove(parts, i)
          table.insert(parts, 1, "watch")
          name = "watch"
          break
        end
      end
    end
    -- Record the command being dispatched so the tier gates (helpers
    -- adminOnly/rootOnly) can name it when they record a denial for `why`.
    S.curCmd = name
    -- ...and forget the PREVIOUS command's failure, so `why` explains the
    -- last thing that happened rather than the last thing that ever went
    -- wrong. `why` itself is exempt: clearing here would erase the very
    -- failure it was typed to explain.
    if name ~= "why" then helpers.clearFailure(S) end
    local args = {}
    for i = 2, #parts do args[#args + 1] = parts[i] end

    S._plainPath = allowHandOff
    local buf = {}
    local function o(text, color)
      buf[#buf + 1] = { tostring(text), color or T.fg }
      -- The one place every command's output passes through, which makes
      -- it the one place that can remember what failed for `why`. Colour
      -- is the signal because it is what commands already set: nothing
      -- had to be re-plumbed to report an error, and a command added
      -- tomorrow is covered without knowing `why` exists.
      if color == T.error and name ~= "why" then
        helpers.noteFailure(S, name, text)
      end
      -- Cooperative slice for other seats (#REV multi-seat freeze):
      -- every command funnels output through here, so long printing
      -- commands (ls -R, du, find, verify) yield for free. Throttled
      -- inside — a no-op until this resume has run >50ms.
      coopYield()
    end

    -- If there's piped input, make it available for stdin-consuming commands
    if inputData and #inputData > 0 then
      if name == "cat" and #args == 0 then
        for line in (inputData .. "\n"):gmatch("(.-)\n") do o(line, T.fg) end
        return buf
      elseif name == "grep" and #args >= 1 and (not args[2] or (args[1] == "-i" and not args[3])) then
        local fold = args[1] == "-i"
        local pat = fold and args[2]:lower() or args[1]
        for line in inputData:gmatch("([^\n]*)\n?") do
          if (fold and line:lower() or line):find(pat, 1, true) then o(line, T.fg) end
        end
        return buf
      elseif name == "wc" and #args == 0 then
        local lc, wc2, bc = 0, 0, #inputData
        for _ in inputData:gmatch("\n") do lc = lc + 1 end
        -- A pipeline joins lines with no trailing newline, so the last line
        -- has none to count.
        if inputData:sub(-1) ~= "\n" then lc = lc + 1 end
        for _ in inputData:gmatch("%S+") do wc2 = wc2 + 1 end
        o(string.format(" %d lines  %d words  %d bytes", lc, wc2, bc), T.fg)
        return buf
      elseif name == "head" or name == "tail" then
        local n, file = 10, false
        for i, a in ipairs(args) do
          if a == "-n" then n = tonumber(args[i + 1]) or n
          elseif a:match("^%-%d+$") then n = tonumber(a:sub(2))
          elseif args[i - 1] ~= "-n" then file = true end
        end
        if not file then
          local lines = {}
          for line in (inputData .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
          local first = name == "head" and 1 or math.max(1, #lines - n + 1)
          for i = first, math.min(#lines, first + n - 1) do o(lines[i], T.fg) end
          return buf
        end
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
    local foreignDraw = false   -- ran code that may draw RAW to the GPU
    local fullscreen, bgPolicy = false, "drowsy"
    if not fn then
      -- Package-provided command: module-style packages run via pkg's own
      -- sandboxed dispatch (the legacy kernel.modules path was retired).
      -- Only where a package could be installed: a typo must not load the
      -- package manager (helpers.mayHavePackages).
      local okP, pkgMod = false, nil
      if helpers.mayHavePackages() then okP, pkgMod = pcall(require, "kernel.pkg") end
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
      --! A package command gets S.programIO as well. Its `o` was this buffer,
      --! so everything it said appeared when it ended: rc's "Shared secret
      --! for..." never showed while it waited for the secret, nor did its key
      --! legend or a single pong until the pilot quit. Its env is built once
      --! and shared, so the read hook goes on this shell's process for the
      --! length of the call rather than in the env.
      --! And so does a built-in, on the plain path. `verify` at the command
      --! line showed nothing at all for over a minute on the headless
      --! machine, then 171 lines at once: a slow built-in looked hung, and
      --! one that explains itself before a prompt explained afterwards. The
      --! read hook stays a package's: a built-in reads through promptInput.
      --! (test_builtin_output_live.lua)
      local out, me = o, nil
      if S._plainPath and S.programIO then
        local stdout, beforeRead = S.programIO(o)
        out = stdout
        if foreignDraw then
          local okP, procMod = pcall(require, "kernel.process")
          me = okP and type(procMod) == "table" and procMod.current and procMod.current() or nil
          if me then me.beforeRead = beforeRead end
        end
      end
      local ok2, err2 = pcall(fn, args, out)
      if me then me.beforeRead = nil end
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
        local refused = helpers.safeModeRefusal and helpers.safeModeRefusal(resolved)
        if refused then
          if helpers.fail then helpers.fail(S, refused, o) else o(refused, T.error) end
          return buf
        end
        local data = F.readFile(resolved)
        if data then
          -- A program a package installed runs with what that package was
          -- granted at install (pkg.capsForFile), on top of the usual set --
          -- and AS that package: the name is what notify stamps on its
          -- dialogs and what crypto.secret() is scoped to, exactly as for a
          -- package command.
          local pkgCaps, pkgOwner = nil, nil
          local okPk, pkgMod = false, nil
          if helpers.mayHavePackages() then okPk, pkgMod = pcall(require, "kernel.pkg") end
          if okPk and type(pkgMod) == "table" and pkgMod.capsForFile then
            pkgCaps, pkgOwner = pkgMod.capsForFile(resolved)
          end
          local stdout, beforeRead = S.programIO(o)
          local progEnv = makeProgramEnv{ name = resolved, pkgName = pkgOwner,
            caps = pkgCaps, stdout = stdout, beforeRead = beforeRead }
          local fn2, err2 = load(data, "=" .. resolved, "t", progEnv)
          if fn2 then
            local ok2, result = pcall(fn2, table.unpack(args))
            helpers.reportProgramEnd(S, o, ok2, result, "Error: ", progEnv)
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
        -- The same difference for a package's command, and a package has
        -- only just been asked, so asking again costs nothing new.
        local why = nil
        if not known and helpers.mayHavePackages() then
          local okP, pkgMod = pcall(require, "kernel.pkg")
          if okP and type(pkgMod) == "table" and pkgMod.commandFailure then
            why = pkgMod.commandFailure(name)
          end
        end
        if why then
          o("'" .. name .. "' is installed but could not be loaded.  [E-802 ERR_CMD_UNLOADABLE]", T.error)
          o(tostring(why), T.error)
          o(memoryAdvice(), T.dim)
        elseif known then
          o("'" .. name .. "' could not be loaded.  [E-802 ERR_CMD_UNLOADABLE]", T.error)
          if S.lastOut and S.lastOut[1] then
            o(S.lastOut[1], T.error)
            S.lastOut = nil   -- said once, here; exec would append it again
          else
            o("Its command group failed to load — check `log` for the reason.", T.dim)
          end
          o(memoryAdvice(), T.dim)
        else
          o("Unknown command: " .. name .. "  [E-801 ERR_UNKNOWN_CMD]", T.error)
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
      if ed then ed.openViewTab(S, wrapped, label or "output", true)   -- already wrapped (#MEM)
      else S.outLines = wrapped end
    end
  end

  -- A command can report through S.lastOut instead of o() -- twenty do in
  -- admin.lua alone ("User 'alice' created."). showOutput clears lastOut
  -- before routing the output, so that report was erased whenever the
  -- command printed nothing else: on a headless machine `useradd` created
  -- the account and said nothing. Fold it into the output instead, as its
  -- last line. lastOut is cleared before each command, so only what THIS
  -- command set can be folded in. (test_lastout_kept.lua)
  local function withReport(buf)
    local said = S.lastOut
    if type(said) == "table" and said[1] then
      buf[#buf + 1] = said
      -- Folded in, so spent: the CLI drains lastOut after its own
      -- showOutput, which would say it a second time.
      S.lastOut = nil
    end
    return buf
  end

  --! Where a program started from the prompt sends its output, for both ways
  --! of starting one. On the plain path it reaches the screen as it happens:
  --! buffered to the end, a long job showed nothing until it finished and a
  --! question showed nothing until it was answered. Inside a pipeline or a
  --! redirect the buffer IS the output.
  function S.programIO(o)
    local plain = S._plainPath
    local live = plain and deps.liveLine or nil
    local echo = plain and deps.echoLine or nil
    -- The full interface echoes to its one output row as well as keeping
    -- the line; four times a second is enough to show it is working, and
    -- a 300-line `tree` must not pay a row redraw for every line. The
    -- whole buffer is drawn when the command ends.
    local okC, comp = pcall(require, "computer")
    local clock = okC and type(comp) == "table" and comp.uptime or os.clock
    local lastEcho = -1
    -- `always`: a question about to wait for its answer is echoed even
    -- inside the quarter second, or it would sit unseen while the read waits.
    local function stdout(line, color, always)
      if live then
        --! The live path does not go through execSingle's `o`, which is where a
        --! failure is noted for `why`. So at the command line, since built-ins
        --! print live, `why` after any refusal said "Nothing has failed since
        --! the last command ran" (headless runner, 2026-11-07: `redstone`
        --! with no card, then `why`); the panels echo through `o` and were
        --! fine. Noted here as well. (test_builtin_output_live.lua)
        if color == S.T.error and S.curCmd ~= "why" then
          helpers.noteFailure(S, S.curCmd, line)
        end
        live(line, color)
        coopYield()
      else
        o(line, color or S.T.fg)
        if echo then
          local now = clock()
          if always or now - lastEcho >= 0.25 then lastEcho = now; echo(line) end
        end
      end
    end
    local beforeRead = nil
    if plain and deps.inputRow then
      beforeRead = function(partial)
        if partial ~= "" then stdout(partial, nil, true) end
        local okT, term = pcall(require, "compat.term")
        if okT and type(term) == "table" then term.setCursor(1, deps.inputRow()) end
      end
    end
    return stdout, beforeRead
  end

  --! A line split at && and || outside quotes: { { cmd = "a" },
  --! { op = "&&", cmd = "b" }, ... }, or nil and why when one side of an
  --! operator is empty. Before 2026-11-07 both were refused, because the
  --! shell had neither and both went wrong without a word: `whoami && echo
  --! X` ran whoami, which ignored the rest, and `a || b` split at its bars
  --! into a pipe. The survey's order (TODO, SHELL LEXER + PARSER, item 11)
  --! put them next. A single | is still a pipe inside a part.
  --! (test_no_andor.lua)
  local function splitChain(input)
    local parts, start, q, i, op = {}, 1, nil, 1, nil
    while i <= #input do
      local ch = input:sub(i, i)
      if q then
        if ch == q then q = nil end
        i = i + 1
      elseif ch == '"' or ch == "'" then
        q = ch
        i = i + 1
      else
        local two = input:sub(i, i + 1)
        if two == "&&" or two == "||" then
          local cmd = input:sub(start, i - 1):match("^%s*(.-)%s*$")
          if cmd == "" then return nil, "nothing before " .. two end
          parts[#parts + 1] = { op = op, cmd = cmd }
          op, start, i = two, i + 2, i + 2
        else
          i = i + 1
        end
      end
    end
    local cmd = input:sub(start):match("^%s*(.-)%s*$")
    if op and cmd == "" then return nil, "nothing after " .. op end
    parts[#parts + 1] = { op = op, cmd = cmd }
    return parts
  end

  --! One command line with no && or || in it: pipes, redirects, or a
  --! single command. Returns its output buffer and a label, or nil when a
  --! program took the seat (its output is its own). `plain` is the typed-
  --! at-the-prompt path: live output, and a full-screen program may take
  --! the seat. A refusal or a redirect's report is left in S.lastOut.
  local function runOne(input, plain)
    local hasPipe = input:find("|", 1, true)
    local hasRedirect = input:find("[>]") or input:find("<")

    if hasPipe or hasRedirect then
      local ok2, pipeMod = pcall(require, "kernel.pipe")
      if ok2 then
        local segments = pipeMod.parse(input)
        local prevOutput = nil
        local finalBuf = {}
        for i, seg in ipairs(segments) do
          -- `cmd < file`: the file is what a pipe would have delivered. This
          -- was parsed and then dropped.
          if seg.stdin and seg.stdin.type == "file" then
            local inPath = rp(seg.stdin.path)
            if not helpers.canRead(S, inPath) then
              S.lastOut = { "Cannot read: " .. seg.stdin.path, T.error }
              return {}, "output"
            end
            prevOutput = F.exists(inPath) and F.readFile(inPath) or nil
            if not prevOutput then
              S.lastOut = { "No such file: " .. seg.stdin.path, T.error }
              return {}, "output"
            end
            prevOutput = prevOutput:gsub("\n$", "")
          end
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
            return {}, "output"
          end

          if i == #segments then finalBuf = buf end
        end
        return finalBuf, "output"
      end
    end

    -- Only the plain single-command path may hand off the seat: a
    -- program inside a pipeline has no stdout to give anyone, and a
    -- redirect wants a buffer to write.
    --! Skip the output only when THIS command handed the seat to a
    --! program. It tested "is any program recorded", and the record stays
    --! for the program's whole life -- so once one was backgrounded with
    --! Ctrl+B, every command after it ran and showed nothing: `echo`,
    --! `ps`, all of it, until the program exited (headless machine,
    --! 2026-10-10; `mkdir` there proved the commands were running).
    --! (test_bg_program_output.lua)
    local before = S._program
    local buf = execSingle(input, nil, plain)
    if S._program and S._program ~= before then return nil end   -- it owns the seat now
    return buf, input:match("^(%S+)") or "output"
  end

  local function exec(input)
    S.lastOut = nil
    local parts, why = splitChain(input)
    if not parts then
      S.lastOut = { "Cannot run that line: " .. why .. ".", T.error }
      return
    end

    if #parts == 1 then
      local buf, label = runOne(input, true)
      if not buf then return end
      local term = package.loaded["compat.term"]
      if deps.repaint and term and term._screenTaken and term._screenTaken() then deps.repaint() end
      showOutput(helpers.expandBuf(S, withReport(buf)), label)
      return
    end

    --! A CHAIN, left to right, as a POSIX shell runs one: `a && b` runs b
    --! only if a succeeded, `a || b` only if it failed, and a part that is
    --! skipped leaves the last status as it was, so `a && b || c` runs c
    --! when either a or b failed. A command FAILED when it printed in the
    --! error colour or refused (S.lastFailure, the record `why` reads; a
    --! redirect that could not write counts too). That is the shell's one
    --! notion of failure, so no command had to learn a new one.
    --! Every part runs off the plain path: a full-screen program runs to its
    --! end before the next part, rather than taking the seat and leaving the
    --! chain with nothing to wait on. All the output is shown at the end,
    --! in order, under the first command's name.
    local all, ok, label = {}, true, nil
    for i, p in ipairs(parts) do
      if i == 1 or (p.op == "&&" and ok) or (p.op == "||" and not ok) then
        S.lastOut = nil
        local buf, l = runOne(p.cmd, false)
        buf = buf or {}
        label = label or l
        local said = S.lastOut
        ok = S.lastFailure == nil
          and not (type(said) == "table" and said[2] == T.error)
        withReport(buf)
        for _, e in ipairs(buf) do all[#all + 1] = e end
      end
    end
    local term = package.loaded["compat.term"]
    if deps.repaint and term and term._screenTaken and term._screenTaken() then deps.repaint() end
    showOutput(helpers.expandBuf(S, all), label or "output")
  end

  -- Expose the single-command runner so `sudo <cmd>` can run one command
  -- (elevated) and CAPTURE its output buffer instead of showing it directly
  -- — avoids the double-render that calling the full exec() from inside a
  -- command would cause. No pipe/redirect handling (sudo runs one command).
  S.execOne = execSingle

  return exec
end

return M
