-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS CLI — the command-line shell                            ║
-- ║                                                              ║
-- ║  AS CAPABLE AS THE TUI, JUST LAZIER. It dispatches through   ║
-- ║  the SAME registry the panels shell uses                     ║
-- ║  (shell/panels/commands.lua) rather than reimplementing the  ║
-- ║  verbs, which is the whole point of this file existing.      ║
-- ║                                                              ║
-- ║  WHAT WAS HERE BEFORE, and why it had to go: shell/init.lua  ║
-- ║  carried its own hand-rolled command table — a second        ║
-- ║  implementation of ls, cat, pkg, useradd and eighty more.    ║
-- ║  Measured on 2026-08-11 it had 85 commands against the TUI's ║
-- ║  124, so 45 things you could do in the TUI simply did not    ║
-- ║  exist at the prompt. That gap was not the disease. The      ║
-- ║  disease was that closing it meant hand-writing 45 more      ║
-- ║  commands, whereupon the two copies would start drifting     ║
-- ║  again from the next commit onward.                          ║
-- ║                                                              ║
-- ║  THE LAZINESS IS NOT A CONSOLATION PRIZE. commands.lua       ║
-- ║  loads its category files (core / admin / extras) on first   ║
-- ║  touch, so a session that only types `ls` and `cat` never    ║
-- ║  parses admin.lua or extras.lua. The CLI is what a low-RAM   ║
-- ║  box falls back to and what `ui=cli` boots into; paying for  ║
-- ║  the whole registry up front is exactly what it must not do. ║
-- ║                                                              ║
-- ║  WHAT THE CLI IS NOT: the emergency terminal. That lives in  ║
-- ║  kernel/init.lua, has seven commands and no dependencies at  ║
-- ║  all, and runs when THIS could not. Three layers, and each   ║
-- ║  one is the fallback for the one above:                      ║
-- ║      panels TUI  →  this  →  emergency terminal              ║
-- ║  So this file may depend on the command registry, and the    ║
-- ║  emergency terminal may depend on nothing.                   ║
-- ╚══════════════════════════════════════════════════════════════╝

local computer = require("computer")

local M = {}

-- ============================================================
-- Shell state
-- ============================================================
-- The registry's command bodies read a shell state `S`. Most of what
-- they touch is plain data (cwd, who, tier, F, T) and applies equally
-- to a CLI; the rest is TUI geometry, which is given sane values rather
-- than left nil so a command that computes a column width does not
-- divide by nothing.
local function newState(ctx)
  local S = {}
  S.K, S.E, S.P, S.F = ctx.K, ctx.E, ctx.P, ctx.F
  S.D, S.U, S.SC, S.NM = ctx.D, ctx.U, ctx.SC, ctx.NM
  S.st = ctx.st
  S.displayIdx = ctx.displayIdx
    or (ctx.K and ctx.K.getDisplayIdx and ctx.K.getDisplayIdx()) or nil
  S.W, S.H = ctx.W, ctx.H
  S.T = S.D.getTheme()
  S.tier = S.D.getGpuTier()
  S.cwd = ctx.cwd or "/"
  S.who = ctx.who or "root"

  -- #SEC — default to GUEST and promote only from a confirmed session,
  -- carried over verbatim from the old cliLoop. A missing or invalid
  -- session must fail CLOSED; the panels state defaults to ROOT because
  -- it is only ever built after a login succeeded, and that assumption
  -- does not hold here (the CLI is also the TUI-failed fallback).
  S.userTier = 0
  if S.U and S.st then
    local sess = S.U.getSession(S.st)
    if sess then S.userTier = sess.tier or 0; S.who = sess.user or S.who end
  end

  -- Layout constants. The CLI is a scrolling teletype, not a panel
  -- layout, but registry commands occasionally read these to size their
  -- output. Point them all at the last row so anything that "draws" to
  -- a chrome row lands somewhere harmless.
  S.MENU_ROW, S.RAIL_ROW, S.LIST_TOP = 1, 2, 3
  S.SUM_ROW, S.OUT_ROW, S.CMD_ROW, S.STAT_ROW = S.H, S.H, S.H, S.H
  S.LIST_H = math.max(1, S.H - 4)
  S.padW = string.rep(" ", S.W)

  S.cmdline, S.cmdCursor = "", 1
  S.cmdHistory, S.cmdHistIdx = {}, 0
  S.lastOut = nil
  -- The FILE clipboard only. Text lives on kernel.clipboard, which is
  -- per-seat and deliberately SURVIVES a panels->CLI handoff: it is the
  -- same operator in the same session, and losing what they just copied
  -- because they typed `cli` would be a bug, not hygiene. It is cleared
  -- on logout instead (see shell/panels/init.lua).
  S.clipboard = nil
  S.browser = { path = S.cwd, sel = 1, scroll = 0, files = {} }
  -- A single pseudo-tab. Some admin commands read S.tabs to report what
  -- is open; an empty list reads as "no shell", which is wrong.
  S.tabs = { { type = "shell", label = "CLI" } }
  S.activeTab = 1
  S.KEYS = require("shell.panels.keymap")
  S.isCLI = true          -- commands may degrade politely; see `edit`
  return S
end

-- ============================================================
-- The shell
-- ============================================================
function M.run(ctx)
  local S = newState(ctx)
  local D, F, K = S.D, S.F, S.K
  local W, H = S.W, S.H

  local helpers = require("shell.panels.helpers")

  -- ── Screen ─────────────────────────────────────────────────────
  local cy = 3

  local function scroll()
    if cy <= H - 2 then return end
    -- Hardware scroll where the GPU offers it; a full repaint is the
    -- fallback and looks the same, just slower.
    local g = D.getGpu and D.getGpu()
    if g then
      local ok = pcall(g.copy, 1, 4, W, H - 5, 0, -1)
      if ok then
        pcall(g.fill, 1, H - 2, W, 1, " ")
        cy = H - 2
        return
      end
    end
    D.fill(1, 3, W, H - 4, " ", D.c("fg"), D.c("bg"))
    cy = 3
  end

  local function o(text, color)
    -- Wrap rather than truncate. The old CLI cut at the screen edge with
    -- `:sub(1, W)`, which silently ate the end of any long line — and
    -- the registry's commands were written for a shell that wraps.
    local s = (text == nil) and "" or tostring(text)
    local lines = helpers.wrapLine(s, W)
    for _, line in ipairs(lines) do
      scroll()
      D.fill(1, cy, W, 1, " ", D.c("fg"), D.c("bg"))
      if line ~= "" then D.set(1, cy, line, color or D.c("fg"), D.c("bg")) end
      cy = cy + 1
    end
  end

  local function chrome()
    D.fill(1, 1, W, 1, " ", D.c("bar_fg"), D.c("bar_bg"))
    D.set(2, 1, (" TOS CLI  ·  " .. S.who .. "  ·  type 'tui' for the full interface")
      :sub(1, W - 2), D.c("bar_fg"), D.c("bar_bg"))
    D.fill(1, H, W, 1, " ", D.c("bar_fg"), D.c("bar_bg"))
    D.set(2, H, (" [tui] TUI   [help] Commands   [exit] Log out"):sub(1, W - 2),
      D.c("bar_fg"), D.c("bar_bg"))
  end

  local function redraw()
    D.clear(D.c("bg"))
    chrome()
    cy = 3
  end

  -- ── Input ──────────────────────────────────────────────────────
  local function pullSignal()
    if coroutine.isyieldable and coroutine.isyieldable() then
      return coroutine.yield()
    end
    return computer.pullSignal(0.25)
  end

  --- Read one line, with history, cursor movement and tab completion.
  -- @param prompt  string
  -- @param mask    true to echo asterisks (passwords)
  local function readLine(prompt, mask, maxLen)
    maxLen = maxLen or 256
    local buf, cur = "", 1
    local histIdx = #S.cmdHistory + 1
    local row = math.min(cy, H - 1)

    local function paint()
      scroll()
      row = math.min(cy, H - 1)
      local shown = mask and string.rep("*", #buf) or buf
      local line = prompt .. shown
      local off = 0
      if #line >= W then off = #line - W + 1 end
      D.fill(1, row, W, 1, " ", D.c("fg"), D.c("bg"))
      D.set(1, row, line:sub(off + 1, off + W), D.c("fg"), D.c("bg"))
      -- Cursor as an inverted cell: OC has no hardware caret.
      local cx = #prompt + cur - off
      if cx >= 1 and cx <= W then
        local ch = shown:sub(cur, cur)
        if ch == "" then ch = " " end
        D.set(cx, row, ch, D.c("bg"), D.c("highlight"))
      end
    end

    paint()
    while true do
      local sig, _, ch, code = pullSignal()
      if sig == "key_down" then
        if code == 28 then                              -- Enter
          D.fill(1, row, W, 1, " ", D.c("fg"), D.c("bg"))
          D.set(1, row, (prompt .. (mask and string.rep("*", #buf) or buf)):sub(1, W),
            D.c("dim"), D.c("bg"))
          cy = row + 1
          return buf
        elseif code == 1 or ch == 17 then               -- ^Q / Esc
          -- #FIX (real Minecraft, 2026-08-11) — ^Q, because Esc closes
          -- the screen GUI and never reaches the computer. On a masked
          -- read (a passphrase) this is the only way to back out, so
          -- offering just Esc meant the prompt could not be cancelled.
          if mask then return nil end
          buf, cur = "", 1
        elseif code == 14 then                          -- Backspace
          if cur > 1 then buf = buf:sub(1, cur - 2) .. buf:sub(cur); cur = cur - 1 end
        elseif code == 211 then                         -- Delete
          if cur <= #buf then buf = buf:sub(1, cur - 1) .. buf:sub(cur + 1) end
        elseif code == 203 then cur = math.max(1, cur - 1)
        elseif code == 205 then cur = math.min(#buf + 1, cur + 1)
        elseif code == 199 then cur = 1
        elseif code == 207 then cur = #buf + 1
        elseif code == 200 and not mask then            -- Up: history
          if histIdx > 1 then
            histIdx = histIdx - 1
            buf = S.cmdHistory[histIdx] or ""
            cur = #buf + 1
          end
        elseif code == 208 and not mask then            -- Down
          if histIdx <= #S.cmdHistory then
            histIdx = histIdx + 1
            buf = S.cmdHistory[histIdx] or ""
            cur = #buf + 1
          end
        elseif code == 15 and not mask then             -- Tab: completion
          -- The same completer the TUI prompt uses, over the same command
          -- name list — so completion knows about every command the CLI
          -- can now actually run, including the ones in categories that
          -- have not been loaded yet (commandNames() is static).
          local cmdsMod = require("shell.panels.commands")
          local completed = helpers.completeCmdline(buf, cmdsMod.commandNames(),
            function(dir) return F.list(dir) end)
          if completed and completed ~= buf then buf = completed; cur = #buf + 1 end
        elseif ch and ch >= 32 and ch < 127 and #buf < maxLen then
          buf = buf:sub(1, cur - 1) .. string.char(ch) .. buf:sub(cur)
          cur = cur + 1
        end
        paint()
      elseif sig == "interrupted" then
        return nil
      end
    end
  end

  -- ── Command table + executor ───────────────────────────────────
  -- This is the parity fix in four lines: the CLI builds the SAME
  -- command table and the SAME executor the panels shell does. Pipes,
  -- redirects, quoting, tier gates, package-provided commands and the
  -- sudo path all come along, because they were never CLI features to
  -- reimplement — they were executor features the CLI could not reach.
  local commandsMod = require("shell.panels.commands")
  local executorMod = require("shell.panels.executor")

  local makeProgramEnv = require("shell.progenv").builder(S)

  --- Deps that are TUI-shaped get CLI answers. Everything a command
  --- might do to "open a tab" or "raise a dialog" resolves to printing
  --- or to an inline prompt — which is what those things MEAN in a
  --- teletype, not a degradation.
  local function viewBuffer(buf, label)
    if label and label ~= "output" then o("── " .. tostring(label) .. " ──", D.c("dim")) end
    for _, entry in ipairs(buf or {}) do
      if type(entry) == "table" then o(entry[1], entry[2]) else o(tostring(entry)) end
    end
  end

  local deps
  deps = {
    rp             = function(p) return helpers.resolvePath(S, p) end,
    canRead        = function(path, out) return helpers.canRead(S, path, out) end,
    canWrite       = function(path, out) return helpers.canWrite(S, path, out) end,
    canAccess      = function(path, mode, out) return helpers.canAccess(S, path, mode, out) end,
    rootOnly       = function(out) return helpers.rootOnly(S, out) end,
    adminOnly      = function(out) return helpers.adminOnly(S, out) end,
    makeProgramEnv = makeProgramEnv,
    refreshBrowser = function() return helpers.refreshBrowser(S) end,
    loadFiles      = function(b) return helpers.loadFiles(S, b) end,
    tabs           = S.tabs,
    pullSignal     = pullSignal,

    -- A "view tab" is a scrollback of lines. Printing them IS the CLI's
    -- scrollback.
    openViewTab    = function(buf, label) viewBuffer(buf, label) end,

    -- A "live tab" re-runs a producer on a timer. There is no timer here,
    -- so it runs ONCE and says so — a one-shot is the honest answer, and
    -- `watch` remains the way to ask for repetition.
    openLiveTab    = function(label, fn, _interval)
      local okL, buf = pcall(fn)
      if okL and type(buf) == "table" then viewBuffer(buf, label) end
      o("(one-shot: live views need the TUI — 'watch " .. tostring(label)
        .. "' repeats it here)", D.c("dim"))
    end,

    -- The editor is genuinely a full-screen, tab-hosted program. Rather
    -- than pretending, say what to type instead. This is the one place
    -- the CLI is honestly less capable, and it is a UI fact rather than
    -- a missing command.
    openEditTab    = function(path)
      o("The editor needs the full interface. Type 'tui' then 'edit "
        .. tostring(path) .. "'.", D.c("warning"))
    end,
    createTab      = function()
      o("Tabs need the full interface — type 'tui'.", D.c("warning"))
      return nil
    end,

    promptInput    = function(msg, maxLen, isPw)
      return readLine(tostring(msg or "> "), isPw and true or false, maxLen)
    end,
    -- Dialogs become questions at the prompt. `confirm` defaults to NO on
    -- an interrupted read, matching the framed dialog's Esc behaviour.
    alert          = function(msg) o(tostring(msg), D.c("warning")); return true end,
    confirm        = function(msg)
      local a = readLine(tostring(msg) .. " [y/N]: ", false, 4)
      return a ~= nil and a:lower():sub(1, 1) == "y"
    end,
    dialog         = function(opts)
      opts = opts or {}
      if opts.title then o(tostring(opts.title), D.c("title")) end
      for _, line in ipairs(opts.lines or {}) do o(tostring(line)) end
      if opts.text then o(tostring(opts.text)) end
      local a = readLine((opts.prompt or "OK?") .. " [y/N]: ", false, 4)
      return (a ~= nil and a:lower():sub(1, 1) == "y") and 1 or 2
    end,

    drawAll        = function() end,     -- nothing to repaint; output already scrolled past
    drawOutRow     = function(text, color) if text then o(text, color) end end,
  }

  local C = commandsMod.build(S, deps)
  deps.C = C

  local exec = executorMod.build(S, {
    rp             = deps.rp,
    makeProgramEnv = makeProgramEnv,
    C              = C,
    -- The one executor behaviour the CLI overrides: output routing.
    -- The TUI picks between the status row, an inline region and a view
    -- tab; a teletype has one surface and everything goes to it.
    showOutput     = function(wrapped, _label) viewBuffer(wrapped, nil) end,
  })

  -- ── CLI-local verbs ────────────────────────────────────────────
  -- ONLY the three things that are properties of THIS SHELL rather than
  -- commands: clearing its screen, and the two ways out of it.
  -- Everything else must come from the registry, or the drift starts
  -- over. They are intercepted before dispatch rather than written into
  -- the command table, because the table is metatable-backed: a name it
  -- knows would be overwritten by its own category on first load, and a
  -- name it does not know is never read at all.
  local leaving = nil
  local LOCAL_VERBS = {
    tui   = function() leaving = "tui" end,
    exit  = function() leaving = "logout" end,
    cls   = function() redraw() end,
    clear = function() redraw() end,
  }

  -- ── Greeting ───────────────────────────────────────────────────
  redraw()
  o("TOS CLI", D.c("title"))
  o("Every command the full interface has, loaded as you use them.", D.c("dim"))
  o("'help' lists them · 'tui' returns to the full interface · 'exit' logs out", D.c("dim"))
  o("")

  -- ── Loop ───────────────────────────────────────────────────────
  while true do
    -- `[sudo]` in the prompt for an elevated shell, matching the TUI's
    -- command row (draw.lua ~336). S._sudo is the flag `sudo -s` sets;
    -- an elevated shell that does not LOOK elevated is how someone runs
    -- the wrong thing.
    local prompt = (S._sudo and "[sudo] " or "")
      .. S.who .. ":" .. S.cwd .. "$ "
    local line = readLine(prompt, false)
    if line == nil then
      -- Interrupted (Ctrl+Alt+C / a kernel interrupt). Treat as a blank
      -- line rather than an exit: an accidental interrupt should not log
      -- an operator out of a recovery shell.
      line = ""
    end
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" then
      S.cmdHistory[#S.cmdHistory + 1] = line
      S.lastOut = nil
      S.outLines = nil
      -- A local verb only counts when it is the WHOLE line: `tui` leaves,
      -- but `grep tui /etc/motd` is a grep.
      local localVerb = LOCAL_VERBS[line]
      if localVerb then
        localVerb()
      else
        local okE, err = pcall(exec, line)
        if not okE then
          o("Error: " .. tostring(err), D.c("error"))
        else
          -- Some commands report through S.lastOut / S.outLines instead
          -- of returning a buffer (that is the TUI's status row and its
          -- inline region). Drain both, or their output vanishes here.
          if S.outLines then
            viewBuffer(S.outLines, nil); S.outLines = nil
          end
          if S.lastOut then
            if type(S.lastOut) == "table" then o(S.lastOut[1], S.lastOut[2])
            else o(tostring(S.lastOut)) end
            S.lastOut = nil
          end
          -- `cli` from inside the CLI sets the flag the PANELS loop
          -- reads; nothing here would ever clear it, and it would then
          -- bounce the operator straight back out of the TUI next time
          -- they went there.
          if S._exitTo == "tui" then leaving = "tui" end
          S._exitTo = nil
        end
      end
      -- A full-screen program (tetris, calc, stock…) took the seat and
      -- has given it back; the screen it left is not ours.
      if S._program then S._program = nil; redraw() end
    end

    if leaving then
      -- #SEC — drop any `sudo -s` elevation on the way out, exactly as
      -- the panels loop does. The CLI and the TUI run in the SAME
      -- process, so a swapped principal would otherwise follow the
      -- operator across the handoff.
      if S.sudoDrop then pcall(S.sudoDrop) end
      D.clear(D.c("bg"))
      return leaving
    end
  end
end

return M
