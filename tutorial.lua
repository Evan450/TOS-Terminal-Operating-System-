-- ╔══════════════════════════════════════╗
-- ║  TOS First-Boot Tutorial             ║
-- ║  Role-aware, skippable walkthrough   ║
-- ╚══════════════════════════════════════╝

local computer = require("computer")

local tutorial = {}

local MARKER = "/etc/.tutorial_done"

-- ============================================================
-- Page definitions
-- Each page: { title, minTier, lines }
-- minTier: 0=ALL, 1=USER+, 2=ADMIN+, 3=ROOT
-- ============================================================

local pages = {
  { title = "Welcome to TOS", minTier = 0, lines = {
    "",
    "Welcome to TOS v1.2.5!",
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
  { title = "Tabs & Multitasking", minTier = 0, lines = {
    "",
    "  F2       - Open a new tab",
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
    "",
    "",
    "Press Enter to begin.",
  }},
}

-- ============================================================
-- Check whether the tutorial should be shown
-- ============================================================

function tutorial.shouldShow(F)
  return not F.exists(MARKER)
end

-- ============================================================
-- Main tutorial runner
-- ============================================================

function tutorial.run(ctx)
  local D  = ctx.D
  local F  = ctx.F
  local U  = ctx.U
  local st = ctx.st
  local W  = ctx.W or 80
  local H  = ctx.H or 25

  -- Determine the user's tier from session
  local tier = 0
  if U and st then
    local sess = U.getSession(st)
    if sess then tier = sess.tier or 0 end
  end

  -- Build filtered page list for this tier
  local vis = {}
  for i = 1, #pages do
    if tier >= pages[i].minTier then
      vis[#vis + 1] = pages[i]
    end
  end
  if #vis == 0 then
    -- Shouldn't happen, but bail gracefully
    F.writeFile(MARKER, "1")
    return
  end

  local total = #vis
  local cur = 1

  -- Helper: mark tutorial done
  local function finish()
    pcall(F.writeFile, MARKER, "1")
  end

  -- Simple word-wrap helper
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

  -- Helper: draw one page
  local function drawPage()
    local T = D.getTheme()
    local pg = vis[cur]

    -- Box dimensions — fit within the screen, even on T1 (50x16)
    local boxW = math.min(W - 2, 60)
    local boxH = math.min(H - 2, 20)
    local boxX = math.floor((W - boxW) / 2) + 1
    local boxY = math.floor((H - boxH) / 2) + 1

    D.clear(T.bg)

    -- Draw bordered box
    D.dbox(boxX, boxY, boxW, boxH, pg.title, {
      bg     = T.panel_bg,
      border = T.border,
      title  = T.title,
    })

    -- Content area: inside the box, below the title row
    local contentX = boxX + 2
    local contentY = boxY + 2
    local contentW = boxW - 4
    local maxLines = boxH - 4 -- leave room for border top/bottom + nav line

    -- Wrap all page lines to fit within contentW, then render
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

    -- Navigation bar at bottom of box — adaptive to available width
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

  -- Main input loop
  drawPage()

  while true do
    local sig, _, ch, code = computer.pullSignal(0.5)
    if sig == "key_down" then
      -- Ctrl+Q: char value 17
      if ch == 17 then
        finish()
        return
      end
      -- Enter (code 28) or Down arrow (code 208): next page
      if code == 28 or code == 208 then
        if cur >= total then
          finish()
          return
        end
        cur = cur + 1
        drawPage()
      -- Backspace (code 14) or Up arrow (code 200): prev page
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
