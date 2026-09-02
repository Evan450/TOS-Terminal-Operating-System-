local launcher = {}

local MAX_LABEL = 60
local MAX_CMD   = 200
local MAX_INFO  = 400
local MAX_ITEMS = 64
local MAX_DEPTH = 5

function launcher.normalizeMenu(raw, depth)
  depth = depth or 1
  local out = { title = "Menu", items = {} }
  if type(raw) ~= "table" then return out end
  if type(raw.title) == "string" and #raw.title >= 1 and #raw.title <= MAX_LABEL then
    out.title = raw.title
  end
  if type(raw.items) ~= "table" then return out end
  for _, it in ipairs(raw.items) do
    if type(it) == "table" and type(it.label) == "string"
       and #it.label >= 1 and #it.label <= MAX_LABEL then
      if type(it.run) == "string" and #it.run >= 1 and #it.run <= MAX_CMD
         and not it.run:find("[\n\r]") then
        out.items[#out.items + 1] = { label = it.label, run = it.run }
      elseif type(it.menu) == "table" and depth < MAX_DEPTH then
        local sub = launcher.normalizeMenu(it.menu, depth + 1)
        if #sub.items > 0 then
          out.items[#out.items + 1] = { label = it.label, menu = sub }
        end
      elseif type(it.info) == "string" and #it.info >= 1 and #it.info <= MAX_INFO then
        out.items[#out.items + 1] = { label = it.label, info = it.info }
      end
    end
    if #out.items >= MAX_ITEMS then break end
  end
  return out
end

function launcher.resolveSelection(menu, idx)
  if type(idx) ~= "number" or not menu or type(menu.items) ~= "table" then
    return { type = "none" }
  end
  local item = menu.items[idx]
  if not item then return { type = "none" } end
  if item.run  then return { type = "run", cmd = item.run, label = item.label } end
  if item.menu then return { type = "submenu", menu = item.menu } end
  if item.info then return { type = "info", text = item.info, label = item.label } end
  return { type = "none" }
end

function launcher.clusterProfile()
  return launcher.normalizeMenu({
    title = "Cluster helper",
    items = {
      { label = "Manager status",          run = "cluster-manager status" },
      { label = "List bridge workers",     run = "cluster-manager workers" },
      { label = "Drain (stop new work)",   run = "cluster-manager drain" },
      { label = "Undrain (resume work)",   run = "cluster-manager undrain" },
      { label = "Command help",            run = "cluster-manager help" },
    },
  })
end

function launcher.readTapeMenu(raw, passphrase, vault)
  if type(raw) ~= "string" or #raw < 7 + 4 + 2 + 64 then return nil, "no keycard tape data" end
  if raw:sub(1, 7) ~= "TAUTH2\0" then return nil, "not a tape-authenticator keycard" end
  local function u16(s, o) return s:byte(o) | (s:byte(o + 1) << 8), o + 2 end
  local function u32(s, o)
    return s:byte(o) | (s:byte(o + 1) << 8) | (s:byte(o + 2) << 16) | (s:byte(o + 3) << 24), o + 4
  end
  local off = 8
  local _; _, off = u32(raw, off)
  local labelLen; labelLen, off = u16(raw, off)
  off = off + labelLen + 64
  if off + 3 > #raw then return nil, "this card has no personal menu" end
  local logLen; logLen, off = u32(raw, off)
  off = off + logLen
  if off + 3 > #raw then return nil, "this card has no personal menu" end
  local menuLen; menuLen, off = u32(raw, off)
  if menuLen == 0 then return nil, "this card's menu is empty" end
  if off + menuLen - 1 > #raw then return nil, "menu region truncated" end
  local blob = raw:sub(off, off + menuLen - 1)
  return launcher.decodeTapeMenuBlob(blob, passphrase, vault)
end

function launcher.decodeTapeMenuBlob(blob, passphrase, vault)
  if not (vault and vault.decrypt and vault.isEncrypted) then return nil, "vault unavailable" end
  if not vault.isEncrypted(blob) then return nil, "menu region corrupt (not a vault blob)" end
  local plain, derr = vault.decrypt(blob, passphrase)
  if not plain then return nil, "cannot decrypt menu (wrong passphrase?): " .. tostring(derr) end

  local items = {}
  for line in plain:gmatch("[^\n]+") do
    local label, cmd = line:match("^(.-)|(.+)$")
    if label and #label > 0 and cmd then
      items[#items + 1] = { label = label, run = cmd }
    end
  end
  if #items == 0 then return nil, "this card's menu is empty" end
  return launcher.normalizeMenu({ title = "Tape toolbox", items = items })
end

local MAX_MENU_BYTES = 64 * 1024

function launcher.readTapeMenuFromDrive(drive, passphrase, vault)
  if not (drive and drive.read and drive.seek and drive.getSize) then
    return nil, "no tape drive"
  end
  local size = drive.getSize() or 0
  if size <= 0 then return nil, "no keycard tape data" end
  if drive.stop then pcall(drive.stop) end
  drive.seek(-size)
  local function readN(n)
    local out, got = {}, 0
    while got < n do
      local ok, c = pcall(drive.read, math.min(8192, n - got))
      if not ok or type(c) ~= "string" or #c == 0 then break end
      out[#out + 1] = c; got = got + #c
    end
    return table.concat(out)
  end
  local function u16(s, o) return s:byte(o) | (s:byte(o + 1) << 8) end
  local function u32(s, o)
    return s:byte(o) | (s:byte(o + 1) << 8) | (s:byte(o + 2) << 16) | (s:byte(o + 3) << 24)
  end

  local head = readN(13)
  if #head < 13 then return nil, "no keycard tape data" end
  if head:sub(1, 7) ~= "TAUTH2\0" then return nil, "not a tape-authenticator keycard" end
  local labelLen = u16(head, 12)
  if labelLen > size then return nil, "label length implausible" end
  drive.seek(labelLen + 64)
  local lenRaw = readN(4)
  if #lenRaw < 4 then return nil, "this card has no personal menu" end
  local logLen = u32(lenRaw, 1)
  if logLen > size then return nil, "log length implausible" end
  drive.seek(logLen)
  lenRaw = readN(4)
  if #lenRaw < 4 then return nil, "this card has no personal menu" end
  local menuLen = u32(lenRaw, 1)
  if menuLen == 0 then return nil, "this card's menu is empty" end
  if menuLen > size or menuLen > MAX_MENU_BYTES then return nil, "menu length implausible" end
  local blob = readN(menuLen)
  if #blob < menuLen then return nil, "menu region truncated" end
  return launcher.decodeTapeMenuBlob(blob, passphrase, vault)
end

local function pull()
  local computer = require("computer")
  return computer.pullSignal(1)
end

function launcher.run(opts)
  opts = opts or {}
  local display = opts.display
  if not display or not display.getSize then return end
  local runLine = opts.runLine
  local root = launcher.normalizeMenu(opts.profile)
  if opts.title then root.title = opts.title end

  local stack = { root }
  local cursor = 1

  local function T() return display.getTheme() end

  local function showLines(header, lines)
    local th = T()
    local W, H = display.getSize()
    display.clear(th.bg)
    display.fill(1, 1, W, 1, " ", th.bar_fg or th.fg, th.bar_bg or th.bg)
    display.set(1, 1, " " .. tostring(header):sub(1, W - 2), th.bar_fg or th.fg, th.bar_bg or th.bg)
    local row = 3
    for _, ln in ipairs(lines or {}) do
      if row > H - 2 then break end
      local txt = type(ln) == "table" and ln[1] or tostring(ln)
      local col = type(ln) == "table" and ln[2] or th.fg
      display.set(2, row, tostring(txt):sub(1, W - 3), col, th.bg)
      row = row + 1
    end

    display.fill(1, H, W, 1, "░", th.dim or th.fg, th.bg)
    display.set(1, H, "▓▒░", th.dim or th.fg, th.bg)
    if W > 6 then display.set(W - 2, H, "░▒▓", th.dim or th.fg, th.bg) end
    display.set(5, H, " Press any key to return. ", th.dim or th.fg, th.bg)
    while true do
      local sig = pull()
      if sig == "key_down" or sig == "touch" then return end
    end
  end

  local function draw()
    local th = T()
    local W, H = display.getSize()
    local menu = stack[#stack]
    display.clear(th.bg)

    local crumb = {}
    for _, m in ipairs(stack) do crumb[#crumb + 1] = m.title end
    local header = " " .. table.concat(crumb, " / ")
    display.fill(1, 1, W, 1, " ", th.bar_fg or th.fg, th.bar_bg or th.bg)
    display.set(1, 1, header:sub(1, W - 1), th.bar_fg or th.fg, th.bar_bg or th.bg)

    local top = 3
    for i, item in ipairs(menu.items) do
      local row = top + i - 1
      if row > H - 2 then break end
      local marker = (i <= 9) and ("[" .. i .. "]") or "   "
      local arrow  = item.menu and "  >" or ""
      local label  = item.label .. arrow
      local fg, bg = th.fg, th.bg
      if i == cursor then fg, bg = th.bar_fg or th.bg, th.bar_bg or th.fg end
      display.fill(2, row, W - 2, 1, " ", fg, bg)
      display.set(2, row, string.format(" %s %s", marker, label):sub(1, W - 3), fg, bg)
    end
    if #menu.items == 0 then
      display.set(2, top, "(this menu is empty)", th.dim or th.fg, th.bg)
    end

    local hint = (#stack > 1)
      and "Up/Down + Enter or click  ·  Backspace: up  ·  Q: quit"
      or  "Up/Down + Enter or click  ·  number keys  ·  Q: quit"

    display.fill(1, H, W, 1, "░", th.dim or th.fg, th.bg)
    display.set(1, H, "▓▒░", th.dim or th.fg, th.bg)
    if W > 6 then display.set(W - 2, H, "░▒▓", th.dim or th.fg, th.bg) end
    display.set(5, H, (" " .. hint .. " "):sub(1, math.max(0, W - 10)), th.dim or th.fg, th.bg)
    return top
  end

  local function activate(idx)
    local menu = stack[#stack]
    local act = launcher.resolveSelection(menu, idx)
    if act.type == "run" then
      local lines
      if runLine then
        local ok, res = pcall(runLine, act.cmd)
        lines = ok and res or { { "error: " .. tostring(res), T().error or T().fg } }
      else
        lines = { { "(no command runner wired)", T().error or T().fg } }
      end
      if type(lines) ~= "table" or #lines == 0 then
        lines = { { act.cmd, T().dim or T().fg }, { "(no output)", T().dim or T().fg } }
      end
      showLines(act.label .. "  —  $ " .. act.cmd, lines)
    elseif act.type == "submenu" then
      stack[#stack + 1] = act.menu
      cursor = 1
    elseif act.type == "info" then
      showLines(act.label, { { act.text, T().fg } })
    end
    return true
  end

  local function back()
    if #stack > 1 then stack[#stack] = nil; cursor = 1; return true end
    return false
  end

  while true do
    local top = draw()
    local sig, _, a, b = pull()
    local menu = stack[#stack]
    if sig == "key_down" then
      local char, code = a, b
      if char == 4 then return
      elseif char and (char == 113 or char == 81) then return
      elseif code == 200 then
        cursor = (cursor > 1) and (cursor - 1) or math.max(1, #menu.items)
      elseif code == 208 then
        cursor = (cursor < #menu.items) and (cursor + 1) or 1
      elseif code == 28 then
        if not activate(cursor) then return end
      elseif code == 14 then
        if not back() then return end
      elseif char and char >= 49 and char <= 57 then
        if not activate(char - 48) then return end
      end
    elseif sig == "touch" then

      local y = b
      if type(y) == "number" then
        local idx = y - top + 1
        if idx >= 1 and idx <= #menu.items then
          cursor = idx
          if not activate(idx) then return end
        end
      end
    end
  end
end

return launcher
