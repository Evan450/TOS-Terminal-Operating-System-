local computer = require("computer")

local tutorial = {}

local LEGACY_MARKER = "/etc/.tutorial_done"
local MARKER_FILE   = ".tutorial_done"

function tutorial.markerFor(session)
  if type(session) ~= "table" then return nil end
  if session.isGuest or session.user == "guest" then return nil end
  local home = session.home
  if type(home) ~= "string" or home == "" or home == "/" then return nil end
  return (home:gsub("/+$", "")) .. "/" .. MARKER_FILE
end

local pages = {
  { title = "Welcome to TOS", minTier = 0, lines = {
    "",
    "Welcome to TOS v" .. tostring(_G._TOS and _G._TOS.version or "?") .. "!",
    "",
    "TOS is a Terminal Operating System for OpenComputers.",
    "It features a tabbed file browser, built-in editor,",
    "networking, and more.",
    "",
    "This tutorial will walk you through the basics.",
    "Let's get started!",
  }},
  { title = "Navigation Basics", minTier = 0, lines = {
    "",
    "The screen layout (top to bottom):",
    "",
    "  Tab bar       - open tabs across the top",
    "  Menu bar      - actions and menus",
    "  Path bar      - current directory",
    "  File list     - files and folders",
    "  Output line   - command results",
    "  Command prompt - type commands here",
    "  Status bar    - system info at the bottom",
    "",
    "Use arrow keys to browse files.",
    "Press Enter for a context menu.",
    "Type commands at the prompt like a terminal.",
    "Press F1 anytime for command help.",
  }},
  { title = "Essential Commands", minTier = 0, lines = {
    "",
    "File operations:",
    "  ls  cd  cat  mkdir  cp  mv  rm",
    "",
    "Open the built-in editor:",
    "  edit <file>",
    "",
    "Get help:",
    "  help   or press F1",
    "",
    "These work just like a standard terminal.",
  }},
  { title = "Home: two views, one prompt", minTier = 0, lines = {
    "",
    "  F2       - Flip the view: tiles / files",
    "",
    "Home is ONE tab. The tile grid and the file",
    "list are two ways of looking at it, and the",
    "prompt sits on the same row in both -- so it",
    "is never somewhere else, and what you run",
    "prints where the last thing printed.",
    "",
    "  Arrows   - Move the selection, either view",
    "  Enter    - Open it (or run what you typed)",
    "  Alt+1-9  - Launch a tile by its number",
    "",
    "Anything you type goes to the prompt, which",
    "is why quick-launch is Alt+1-9 and history",
    "is Ctrl+P / Ctrl+N.",
  }},
  { title = "Tabs & Multitasking", minTier = 0, lines = {
    "",
    "  Tab      - Next tab (on an empty prompt)",
    "  F4       - Close the current tab",
    "  Ctrl+T   - Switch between shell and panels",
    "",
    "The editor opens in its own tab so you can",
    "switch back and forth between files and code.",
    "",
    "  ps       - Show running processes",
  }},
  { title = "Editor", minTier = 0, lines = {
    "",
    "The built-in editor supports:",
    "",
    "  Ctrl+S           Save",
    "  Ctrl+Q           Close",
    "  Ctrl+F           Find",
    "  Ctrl+H           Find & replace",
    "  Ctrl+Z           Undo",
    "  Ctrl+C / X / V   Copy / Cut / Paste lines",
  }},
  { title = "Your Account", minTier = 1, lines = {
    "",
    "  whoami   - Shows your username",
    "  passwd   - Changes your password",
    "",
    "Your home directory is /home/<username>",
    "",
    "Permissions:",
    "  Read:   /public",
    "  Write:  /home/<you>, /tmp",
  }},
  { title = "Administration", minTier = 2, lines = {
    "",
    "User management:",
    "  useradd  userdel  usermod",
    "",
    "Services & scheduling:",
    "  service  - Manage startup services in /etc/rc.d/",
    "  cron     - Manage scheduled tasks",
    "",
    "System control:",
    "  shutdown   reboot   flash (write BIOS to EEPROM)",
  }},
  { title = "Networking & Security", minTier = 2, lines = {
    "",
    "Zero-trust model: peers start UNKNOWN and",
    "must be elevated to TRUSTED before data flows.",
    "",
    "  net    - Show network status",
    "  ping   - Discover peers",
    "  chat   - Messaging",
    "  rsh    - Remote shell commands",
    "  scp    - Secure file transfer",
    "",
    "All comms are encrypted between TRUSTED peers.",
  }},
  { title = "System Internals", minTier = 3, lines = {
    "",
    "  verify     - Check system file integrity",
    "  log        - Show kernel log",
    "  component <type> [method]",
    "             - Call any OC component directly",
    "  compat     - Show OpenOS compatibility status",
    "",
    "Startup scripts:  /etc/rc.d/",
    "Scheduled tasks:  /etc/cron.dat",
    "",
    "  deploy     - Copy TOS to another disk",
  }},
  { title = "Pipes & Extras", minTier = 0, lines = {
    "",
    "Piping and redirection:",
    "  cmd1 | cmd2    - Pipe output between commands",
    "  cmd > file     - Redirect output to file",
    "  cmd >> file    - Append output to file",
    "",
    "Peripherals:",
    "  redstone   robot   inventory   tape",
    "",
    "  env        - View environment variables",
  }},
  { title = "Ready!", minTier = 0, lines = {
    "",
    "You're ready to use TOS!",
    "",
    "Remember:",
    "  Press F1 anytime for command help.",
    "",

    "  Run 'tutorial' to see this again -- it won't",
    "  interrupt you a second time on its own.",
    "",
    "Press Enter to begin.",
  }},
}

function tutorial.shouldShow(F, session)
  if not (F and F.exists) then return false end
  --! PASS THE SESSION. securefs resolves the acting principal as
  --! explicit -> process principal -> users.currentSession() -> boot
  --! session, and on the first-boot path every one of those is empty:
  --! login() is called with setCurrent=false (deliberately, so a
  --! multi-seat boot cannot race over the module-global), and the boot
  --! session fallback is switched off once boot completes. So an
  --! un-sessioned check fails closed, and root -- holding a perfectly
  --! good root token -- was told "Root access required" for its own
  --! /root/.tutorial_done.
  --!
  --! The WRITE path below already knew this and passes writeSess, with a
  --! comment explaining it. The read path was never given the same
  --! treatment, so the marker could not be READ by the account that had
  --! just been allowed to write it.
  local path = tutorial.markerFor(session)
  if not path then

    return not F.exists(LEGACY_MARKER, session)
  end
  if F.exists(path, session) then return false end

  if session.user == "root" and F.exists(LEGACY_MARKER, session) then return false end
  return true
end

function tutorial.run(ctx)
  local D  = ctx.D
  local F  = ctx.F
  local U  = ctx.U
  local st = ctx.st
  local W  = ctx.W or 80
  local H  = ctx.H or 25

  local tier = 0
  local writeSess = nil
  local session = nil
  if U and st then
    local sess = U.getSession(st)
    if sess then
      tier = sess.tier or 0
      writeSess = sess
      session = sess
    end
  end

  local marker = tutorial.markerFor(session) or LEGACY_MARKER

  local function markDone()
    local ok, err
    if writeSess then
      ok, err = F.writeFile(marker, "1", writeSess)
    else
      ok, err = F.writeFile(marker, "1")
    end
    if not ok then
      pcall(function()
        local logMod = require("kernel.log")
        if logMod and logMod.warn then
          logMod.warn("tutorial", "markDone failed: " .. tostring(err))
        end
      end)
    end
    return ok, err
  end

  local vis = {}
  for i = 1, #pages do
    if tier >= pages[i].minTier then
      vis[#vis + 1] = pages[i]
    end
  end
  if #vis == 0 then

    pcall(markDone)
    return
  end

  local total = #vis
  local cur = 1

  local function finish()
    pcall(markDone)
  end

  local function wrapText(text, width)
    if #text <= width then return { text } end
    local lines = {}
    while #text > width do
      local cut = width
      local foundSpace = false
      for i = width, math.max(1, width - 20), -1 do
        if text:sub(i, i) == " " then cut = i - 1; foundSpace = true; break end
      end
      lines[#lines + 1] = text:sub(1, cut)
      text = text:sub(cut + (foundSpace and 2 or 1))
    end
    if #text > 0 then lines[#lines + 1] = text end
    return lines
  end

  local function drawPage()
    local T = D.getTheme()
    local pg = vis[cur]

    local boxW = math.min(W - 2, 60)
    local boxH = math.min(H - 2, 20)
    local boxX = math.floor((W - boxW) / 2) + 1
    local boxY = math.floor((H - boxH) / 2) + 1

    D.clear(T.bg)

    D.dbox(boxX, boxY, boxW, boxH, pg.title, {
      bg     = T.panel_bg,
      border = T.border,
      title  = T.title,
    })

    local contentX = boxX + 2
    local contentY = boxY + 2
    local contentW = boxW - 4
    local maxLines = boxH - 4

    local wrapped = {}
    for _, line in ipairs(pg.lines) do
      if #line == 0 then
        wrapped[#wrapped + 1] = ""
      else
        for _, wl in ipairs(wrapText(line, contentW)) do
          wrapped[#wrapped + 1] = wl
        end
      end
    end

    for i = 1, math.min(#wrapped, maxLines) do
      D.set(contentX, contentY + (i - 1), wrapped[i], T.fg, T.panel_bg)
    end

    local navW = boxW - 4
    local nav
    if navW >= 44 then
      nav = cur .. "/" .. total .. " Enter:next Bksp:prev ^Q:skip"
    elseif navW >= 28 then
      nav = cur .. "/" .. total .. " Ent/Bksp:nav ^Q:skip"
    else
      nav = cur .. "/" .. total .. " Ent/Bk/^Q"
    end
    if #nav > navW then nav = nav:sub(1, navW) end
    local navX = boxX + math.floor((boxW - #nav) / 2)
    D.set(math.max(boxX + 1, navX), boxY + boxH - 1, nav, T.dim, T.panel_bg)
  end

  drawPage()

  while true do
    local sig, _, ch, code = computer.pullSignal(0.5)
    if sig == "key_down" then

      if ch == 17 then
        local T = D.getTheme()
        local prompt = "Skip tutorial? [y/N]"
        local px = math.max(1, math.floor((W - #prompt) / 2))
        D.set(px, H, prompt, T.warning or T.fg, T.bg)
        local confirmed = false
        repeat
          local s2, _, c2 = computer.pullSignal(10)
          if s2 == "key_down" then
            if c2 == 121 or c2 == 89 then confirmed = true; break
            elseif c2 ~= 0 then break end
          elseif s2 == nil then
            break
          end
        until false
        if confirmed then
          finish()
          return
        else
          drawPage()
        end
      end

      if code == 28 or code == 208 then
        if cur >= total then
          finish()
          return
        end
        cur = cur + 1
        drawPage()

      elseif code == 14 or code == 200 then
        if cur > 1 then
          cur = cur - 1
          drawPage()
        end
      end
    end
  end
end

return tutorial
