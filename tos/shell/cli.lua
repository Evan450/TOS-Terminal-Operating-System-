local computer = require("computer")

local M = {}

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

  S.userTier = 0
  if S.U and S.st then
    local sess = S.U.getSession(S.st)
    if sess then S.userTier = sess.tier or 0; S.who = sess.user or S.who end
  end

  S.MENU_ROW, S.RAIL_ROW, S.LIST_TOP = 1, 2, 3
  S.SUM_ROW, S.OUT_ROW, S.CMD_ROW, S.STAT_ROW = S.H, S.H, S.H, S.H
  S.LIST_H = math.max(1, S.H - 4)
  S.padW = string.rep(" ", S.W)

  S.cmdline, S.cmdCursor = "", 1
  S.cmdHistory, S.cmdHistIdx = {}, 0
  S.lastOut = nil

  S.clipboard = nil
  S.browser = { path = S.cwd, sel = 1, scroll = 0, files = {} }

  S.tabs = { { type = "shell", label = "CLI" } }
  S.activeTab = 1
  S.KEYS = require("shell.panels.keymap")
  S.isCLI = true
  return S
end

function M.run(ctx)
  local S = newState(ctx)
  local D, F, K = S.D, S.F, S.K
  local W, H = S.W, S.H

  local helpers = require("shell.panels.helpers")

  local cy = 3

  local function scroll()
    if cy <= H - 2 then return end

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

  local function pullSignal()
    if coroutine.isyieldable and coroutine.isyieldable() then
      return coroutine.yield()
    end
    return computer.pullSignal(0.25)
  end

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
        if code == 28 then
          D.fill(1, row, W, 1, " ", D.c("fg"), D.c("bg"))
          D.set(1, row, (prompt .. (mask and string.rep("*", #buf) or buf)):sub(1, W),
            D.c("dim"), D.c("bg"))
          cy = row + 1
          return buf
        elseif code == 1 or ch == 17 then

          if mask then return nil end
          buf, cur = "", 1
        elseif code == 14 then
          if cur > 1 then buf = buf:sub(1, cur - 2) .. buf:sub(cur); cur = cur - 1 end
        elseif code == 211 then
          if cur <= #buf then buf = buf:sub(1, cur - 1) .. buf:sub(cur + 1) end
        elseif code == 203 then cur = math.max(1, cur - 1)
        elseif code == 205 then cur = math.min(#buf + 1, cur + 1)
        elseif code == 199 then cur = 1
        elseif code == 207 then cur = #buf + 1
        elseif code == 200 and not mask then
          if histIdx > 1 then
            histIdx = histIdx - 1
            buf = S.cmdHistory[histIdx] or ""
            cur = #buf + 1
          end
        elseif code == 208 and not mask then
          if histIdx <= #S.cmdHistory then
            histIdx = histIdx + 1
            buf = S.cmdHistory[histIdx] or ""
            cur = #buf + 1
          end
        elseif code == 15 and not mask then

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

  local commandsMod = require("shell.panels.commands")
  local executorMod = require("shell.panels.executor")

  local makeProgramEnv = require("shell.progenv").builder(S)

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

    openViewTab    = function(buf, label) viewBuffer(buf, label) end,

    openLiveTab    = function(label, fn, _interval)
      local okL, buf = pcall(fn)
      if okL and type(buf) == "table" then viewBuffer(buf, label) end
      o("(one-shot: live views need the TUI — 'watch " .. tostring(label)
        .. "' repeats it here)", D.c("dim"))
    end,

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

    alert          = function(msg) o(tostring(msg), D.c("warning")); return true end,
    confirm        = function(msg)
      local a = readLine(tostring(msg) .. " [y/N]: ", false, 4)
      return a ~= nil and a:lower():sub(1, 1) == "y"
    end,

    confirmTyped   = function(msg, word)
      if msg then o(tostring(msg), D.c("warning")) end
      local a = readLine('Type "' .. tostring(word) .. '" to confirm: ', false, 32)
      return a == word
    end,
    dialog         = function(opts)
      opts = opts or {}
      if opts.title then o(tostring(opts.title), D.c("title")) end
      for _, line in ipairs(opts.lines or {}) do o(tostring(line)) end
      if opts.text then o(tostring(opts.text)) end
      local a = readLine((opts.prompt or "OK?") .. " [y/N]: ", false, 4)
      return (a ~= nil and a:lower():sub(1, 1) == "y") and 1 or 2
    end,

    drawAll        = function() end,
    drawOutRow     = function(text, color) if text then o(text, color) end end,
  }

  local C = commandsMod.build(S, deps)
  deps.C = C

  local exec = executorMod.build(S, {
    rp             = deps.rp,
    makeProgramEnv = makeProgramEnv,
    C              = C,

    showOutput     = function(wrapped, _label) viewBuffer(wrapped, nil) end,
  })

  local leaving = nil
  local LOCAL_VERBS = {
    tui   = function() leaving = "tui" end,
    exit  = function() leaving = "logout" end,
    cls   = function() redraw() end,
    clear = function() redraw() end,
  }

  redraw()
  o("TOS CLI", D.c("title"))
  o("Every command the full interface has, loaded as you use them.", D.c("dim"))
  o("'help' lists them · 'tui' returns to the full interface · 'exit' logs out", D.c("dim"))
  o("")

  while true do

    local prompt = (S._sudo and "[sudo] " or "")
      .. S.who .. ":" .. S.cwd .. "$ "
    local line = readLine(prompt, false)
    if line == nil then

      line = ""
    end
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" then
      S.cmdHistory[#S.cmdHistory + 1] = line
      S.lastOut = nil
      S.outLines = nil

      local localVerb = LOCAL_VERBS[line]
      if localVerb then
        localVerb()
      else
        local okE, err = pcall(exec, line)
        if not okE then
          o("Error: " .. tostring(err), D.c("error"))
        else

          if S.outLines then
            viewBuffer(S.outLines, nil); S.outLines = nil
          end
          if S.lastOut then
            if type(S.lastOut) == "table" then o(S.lastOut[1], S.lastOut[2])
            else o(tostring(S.lastOut)) end
            S.lastOut = nil
          end

          if S._exitTo == "tui" then leaving = "tui" end
          S._exitTo = nil
        end
      end

      if S._program then S._program = nil; redraw() end
    end

    if leaving then

      if S.sudoDrop then pcall(S.sudoDrop) end
      D.clear(D.c("bg"))
      return leaving
    end
  end
end

return M
