local computer   = require("computer")
local component  = require("component")
local helpers    = require("shell.panels.helpers")

local coopYield = function() end
do
  local okP, procMod = pcall(require, "kernel.process")
  if okP and procMod and procMod.yieldCooperative then
    coopYield = procMod.yieldCooperative
  end
end

local function homeMod()
  local ok, m = pcall(require, "shell.panels.home")
  return (ok and m) or nil
end
local function cycleKeyLabel(S)
  local h = homeMod()
  return h and h.cycleKeyLabel(S) or "F2"
end
local function viewKeyHelp(S)
  local h = homeMod()
  if h and h.enabled(S) then
    return h.viewKeyLabel(S) .. "  Tiles / files "
  end
  return "F2  Next tab      "
end

local function clipHelpLine(S)
  local h = homeMod()
  local okK, keys = pcall(require, "shell.keys")
  if not (okK and keys) then return "Copy Ctrl+Insert  Cut ^X  Paste ^V" end
  local who = S and S.who or nil
  return "Copy " .. keys.label("copy", who)
    .. "  Cut " .. keys.label("cut", who)
    .. "  Paste " .. keys.label("paste", who)
end

local function cycleKeyHelp(S)
  local k = cycleKeyLabel(S)
  return k .. string.rep(" ", math.max(1, 12 - #k)) .. "Next tab   "
end

return function(C, S, deps)

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
  local adminOnly         = deps.adminOnly
  local makeProgramEnv    = deps.makeProgramEnv
  local fmtSz             = helpers.fmtSz
  local expandBuf         = function(buf) return helpers.expandBuf(S, buf) end
  local promptInput       = deps.promptInput

  C.help = function(args, o)
    local topic = args and args[1] and args[1]:lower()
    if topic == "cp" or topic == "copy" then
      o("cp <source> <dest>", T.title)
      o("  Copy a file. Both paths are required.", T.fg)
      o("  Paths starting with / are absolute; others are relative to cwd.", T.fg)
      o("  Examples:", T.dim)
      o("    cp notes.txt /home/root/notes_bak.txt", T.dim)
      o("    cp /etc/cfg.conf /tmp/cfg.conf", T.dim)
      o("  Tip: Use F5 in the browser for clipboard-style copy.", T.highlight)
    elseif topic == "mv" then
      o("mv <source> <dest>", T.title)
      o("  Move or rename a file.", T.fg)
      o("  Examples:", T.dim)
      o("    mv old.txt new.txt           (rename in cwd)", T.dim)
      o("    mv /tmp/work.lua /home/root/ (move to dir)", T.dim)
    elseif topic == "cd" then
      o("cd [dir]", T.title)
      o("  Change directory. With no argument, prints current directory.", T.fg)
      o("  Special paths:  ..  (parent)   ~  (home dir)", T.fg)
    elseif topic == "find" then
      o("find [path] [-name pattern]", T.title)
      o("  Recursively search for files. Pattern uses Lua patterns.", T.fg)
      o("  Examples:", T.dim)
      o("    find /tos -name *.lua", T.dim)
      o("    find /home", T.dim)
    elseif topic == "grep" then
      o("grep <pattern> <file>", T.title)
      o("  Search file lines for pattern (plain text, not regex).", T.fg)
      o("  Example:  grep function /tos/shell/init.lua", T.dim)
    elseif topic == "flash" then
      o("flash <file>", T.title)
      o("  Write a Lua file to the EEPROM (overwrites BIOS!).", T.fg)
      o("  Prompts for confirmation. Use to install a new BIOS.", T.fg)
      o("  Example:  flash /tos/bios.lua", T.dim)
    elseif topic == "edit" then
      o("edit <file>", T.title)
      o("  Open file in editor tab. Creates the file if it doesn't exist.", T.fg)
      o("  Keys:  Ctrl+S = save   Ctrl+Q = close tab   Ctrl+F = find", T.dim)
      o("  Ctrl+H = find/replace  Ctrl+Z = undo", T.dim)

      o("  Select: Shift+arrows.  " .. clipHelpLine(S), T.dim)
      o("  With nothing selected, copy/cut take the whole line.", T.dim)
      o("  Use " .. cycleKeyLabel(S) .. " to switch tabs, F4 to close.", T.dim)
    elseif topic == "run" then
      o("run <file> [args...]", T.title)
      o("  Execute a Lua file in the current environment.", T.fg)
      o("  Args are passed as a table in the second argument.", T.fg)
    elseif topic == "tape" then
      o("tape [subcommand]", T.title)
      o("  Data storage on Computronics tapes (requires module).", T.fg)
      o("  If the tape package is not installed, shows", T.fg)
      o("  instructions for installing it or building your own.", T.fg)
      o("", T.fg)
      o("  Subcommands (when module is active):", T.dim)
      o("    detect           List tape drives", T.dim)
      o("    info             Tape size, label, format", T.dim)
      o("    label [name]     Get/set tape label", T.dim)
      o("    store <path>     Archive file/dir to tape", T.dim)
      o("    restore [path]   Restore archive from tape", T.dim)
      o("    list             List archived entries", T.dim)
      o("    dump [off] [len] Hex dump of tape bytes", T.dim)
      o("    erase [full]     Quick or full wipe", T.dim)
      o("    raw read/write   Low-level byte I/O", T.dim)
    elseif topic == "net" then
      o("net [subcommand]", T.title)
      o("  Network management (requires modem or linked card).", T.fg)
      o("", T.fg)
      o("  Subcommands:", T.dim)
      o("    status              Show network status", T.dim)
      o("    discover / scan     Broadcast ping to find peers", T.dim)
      o("    peers / list        List known peers and trust levels", T.dim)
      o("    trust <addr> [full] Elevate peer to KNOWN or TRUSTED", T.dim)
      o("    block <addr>        Block a peer", T.dim)
      o("    send <addr> <msg>   Send message to trusted peer", T.dim)
      o("", T.fg)
      o("  Related: ping <addr>, hostname [name], chat", T.dim)
    elseif topic == "pkg" or topic == "mod" or topic == "module" or topic == "modules"
        or topic == "package" or topic == "packages" then
      o("pkg [subcommand]", T.title)
      o("  Package manager — install and manage add-ons. (Replaces the old", T.fg)
      o("  'mod'/module manager, retired in v1.3.1.)", T.fg)
      o("", T.fg)
      o("  Subcommands:", T.dim)
      o("    list                List installed packages", T.dim)
      o("    search              List packages on repos + mounted disks", T.dim)
      o("    info <name>         Show a package's details + status", T.dim)
      o("    install [name|dir]  By name (deps+hashes); a path installs a dir;", T.dim)
      o("                        no arg scans mounted disks and prompts", T.dim)
      o("    enable|disable <n>  Toggle an installed package (admin)", T.dim)
      o("    uninstall <name>    Remove a package (admin)", T.dim)
      o("    commands            List commands provided by packages", T.dim)
      o("    make-disk <mount>   Build an add-on disk from installed packages", T.dim)
      o("", T.fg)
      o("  Insert the Optional Utilities disk, then: pkg install", T.dim)
      o("  Shortcuts: 'install <name>' and 'uninstall <name>' work too.", T.dim)
    elseif topic == "monitor" or topic == "top" then
      o("monitor   (alias: top; also opened with Ctrl+T)", T.title)
      o("  The live System Monitor — one screen showing what TOS is doing.", T.fg)
      o("", T.fg)
      o("  Shows:", T.dim)
      o("    · Every process (kernel AND user), each explained, with owner,", T.dim)
      o("      state, CPU and seat — auto-refreshing.", T.dim)
      o("    · rc.d services and their status (admin).", T.dim)
      o("    · Memory and uptime vitals.", T.dim)
      o("", T.fg)
      o("  Runs as a full-screen tab: scrolls, never truncates, per-seat.", T.dim)
      o("", T.fg)
      o("  Keys:", T.dim)
      o("    up/down move   Enter switch-to   K kill   T suspend/resume (TSR)", T.dim)
      o("    Enter start-stop a service (admin)   R refresh   ^Q close", T.dim)
    elseif topic == "cron" then
      o("cron [subcommand]", T.title)
      o("  Manage scheduled tasks.  (admin+)", T.fg)
      o("", T.fg)
      o("  Subcommands:", T.dim)
      o("    list                Show all cron jobs", T.dim)
      o("    add <interval> <cmd> Schedule a command", T.dim)
      o("    rm <id>             Remove a cron job", T.dim)
    elseif topic == "service" then
      o("service [subcommand]", T.title)
      o("  Manage startup services.  (admin+)", T.fg)
      o("", T.fg)
      o("  Subcommands:", T.dim)
      o("    (none)              List all services and status", T.dim)
      o("    start <name>        Start a service", T.dim)
      o("    stop <name>         Stop a service", T.dim)
    elseif topic == "users" or topic == "useradd" or topic == "userdel" or topic == "usermod" then
      o("User Management  (admin/root)", T.title)
      o("  users                   List all user accounts", T.fg)
      o("  useradd <name>          Create a new user", T.fg)
      o("  userdel <name>          Delete a user", T.fg)
      o("  usermod <user> <action> Modify a user:", T.fg)
      o("    lock / unlock         Lock or unlock an account", T.dim)
      o("    admin / user          Set role to admin or user", T.dim)
      o("  whoami                  Show current user", T.fg)
      o("  passwd                  Change your password", T.fg)
    elseif topic == "disk" then
      o("disk [subcommand]", T.title)
      o("  Manage removable disks (floppies, HDDs).", T.fg)
      o("", T.fg)
      o("  Subcommands:", T.dim)
      o("    list                List removable disks", T.dim)
      o("    info <mount>        Show disk contents", T.dim)
      o("    install <mount>     Install module from disk (admin)", T.dim)
      o("    export <name> <mnt> Write module to disk    (admin)", T.dim)
      o("    eject <mount>       Unmount a disk", T.dim)
    elseif topic == "redstone" or topic == "rs" then
      o("redstone [subcommand]  (alias: rs)", T.title)
      o("  Control redstone I/O on all sides.", T.fg)
      o("", T.fg)
      o("  Subcommands:", T.dim)
      o("    (none)              Show redstone levels", T.dim)
      o("    set <side> <level>  Set output (0-15)", T.dim)
      o("    pulse <side> [dur]  Pulse output (default 0.5s)", T.dim)
    elseif topic == "robot" then
      o("robot <command>", T.title)
      o("  Control robot/drone movement and interaction.", T.fg)
      o("", T.fg)
      o("  Movement: forward, back, up, down, left, right", T.dim)
      o("  Actions:  swing, use, place, suck, drop, detect", T.dim)
      o("  Info:     name, energy, slot <n>", T.dim)
    elseif topic == "audio" or topic == "sound" or topic == "beep" then
      o("audio [subcommand]", T.title)
      o("  Control audio feedback (beeps and notifications).", T.fg)
      o("", T.fg)
      o("  Subcommands:", T.dim)
      o("    (none)              Show audio status", T.dim)
      o("    on                  Enable audio feedback", T.dim)
      o("    off                 Disable audio feedback", T.dim)
      o("    volume <0-100>      Set volume level (shorter/longer beeps)", T.dim)
      o("    test                Play all beep codes", T.dim)
      o("", T.fg)
      o("  Beep codes:", T.dim)
      o("    1 short high        Success / positive action", T.dim)
      o("    2 ascending         Login success / confirm", T.dim)
      o("    1 long low          Error / login failure", T.dim)
      o("    3 short low         Critical error / kernel panic", T.dim)
      o("    2 short             Warning / command not found", T.dim)
      o("    2-tone chime        Chat message received", T.dim)
      o("    2 descending        Shutdown / logout", T.dim)
      o("    3 ascending         Boot complete", T.dim)
    elseif topic and topic ~= "" then

      local Cmds = require("shell.panels.commands")
      local entry = Cmds.entry and Cmds.entry(topic)
      if entry then
        local TIERS = { [0] = "guest", [1] = "user", [2] = "admin", [3] = "root" }
        o(topic, T.title)
        o("  " .. (entry.help or "(no description)"), T.fg)
        o("", T.fg)
        o(string.format("  Minimum tier: %s    Group: %s",
          TIERS[entry.tier or 0] or tostring(entry.tier), entry.category or "?"), T.dim)

        local tip = "  Tip: run '" .. topic .. "' with no args for usage"
        if F.exists("/usr/man/" .. topic .. ".man") then
          tip = tip .. "; 'man " .. topic .. "' for the manual."
        else
          tip = tip .. "."
        end
        o(tip, T.dim)
      else
        o("No such command: '" .. topic .. "'.  Type 'help' for the full list.", T.warning)
      end
    else

      local Cmds = require("shell.panels.commands")
      local function avail(token) return Cmds.needMet and Cmds.needMet(token) end
      o("=== TOS Command Reference ===  (help <cmd> for detail)", T.title)
      o("", T.fg)
      o(" Navigation & Files", T.highlight)
      o("  cd [dir]              Change directory  (~ = home, .. = parent)", T.fg)
      o("  ls [path]             List directory  (dir = alias)", T.fg)
      o("  cat <file>            View file contents  (type = alias)", T.fg)
      o("  more <file>           Open file in view tab", T.fg)
      if S.userTier >= 1 then
      o("  mkdir <dir>           Create directory", T.fg)
      o("  touch <file>          Create empty file", T.fg)
      o("  cp <src> <dst>        Copy file (both paths required)", T.fg)
      o("  mv <src> <dst>        Move or rename file", T.fg)
      o("  rm <path>             Delete file or directory", T.fg)
      end
      o("  find [path] [-name p] Recursive file search", T.fg)
      o("  grep <pat> <file>     Search file for text pattern", T.fg)
      o("  wc <file>             Show line / word / byte counts", T.fg)
      o("  df                    Show disk usage for all mounts", T.fg)
      o("  echo [text]           Print text to output", T.fg)
      o("", T.fg)
      o(" UI & Shortcuts", T.highlight)
      o("  F1  Help      " .. viewKeyHelp(S) .. "  F3  View file", T.fg)

      o("  F4  Close tab F5  Copy file      F6  Move file", T.fg)
      o("  " .. cycleKeyHelp(S) .. " F9  Menu bar", T.fg)
      o("  F7  Mkdir     F8  Delete", T.fg)
      o("  Text: Shift+arrows select.  " .. clipHelpLine(S), T.fg)
      o("  F10 Quit      ^Q  Cancel/Close   ^F  Find", T.fg)
      o("  Enter on file = context menu  |  ^T  System Monitor", T.dim)
      if S.userTier >= 1 then
      o("", T.fg)
      o(" Devices", T.highlight)
      o("  lsdev                 List all connected peripherals", T.fg)
      o("  mount                 List mounted filesystems", T.fg)
      if S.userTier >= 2 then
      o("  mount <dev> <path>    Mount a device at path", T.fg)
      o("  umount <path>         Unmount a device", T.fg)
      end
      end
      o("", T.fg)
      o(" System", T.highlight)
      o("  mem    Show memory usage", T.fg)
      o("  hw     List hardware components", T.fg)
      o("  ps     Show running processes  (snapshot)", T.fg)
      o("  monitor  Live System Monitor: processes/services/memory  (also ^T)", T.fg)
      o("  ver    TOS version info", T.fg)
      o("  about  Changelog and credits", T.fg)
      o("  uptime Show system uptime", T.fg)
      if S.userTier >= 1 then

      o("  srm    System Repair & Maintenance  (status/scan/repair/baseline)", T.fg)
      o("  doctor Runtime health: memory, disk, services, power, security", T.fg)
      end
      if S.userTier >= 2 then
      o("  log [N]       Show last N system log entries", T.fg)
      o("  verify Check all system files for integrity", T.fg)
      end
      if S.userTier >= 1 then
      o("  run <file>    Execute a Lua file", T.fg)
      o("  bg <file>     Run a Lua file in a background tab", T.fg)
      o("  edit <file>   Open in editor tab  (^S save, ^Q close)", T.fg)
      end
      if S.userTier >= 3 then
      o("  lua           Interactive Lua REPL  (exit to quit)", T.fg)
      o("  flash <file>  Flash EEPROM with Lua file  (!CAUTION)", T.fg)
      end
      o("  programs      List executables in /bin and /usr/bin", T.fg)
      o("  history       Show command history", T.fg)
      o("  date [fmt]    Show wall clock  (time = alias)", T.fg)
      o("  tree [path] [depth]  Visual recursive directory listing", T.fg)
      o("  theme [list|set|color|...]  Customize colors  (colors = alias)", T.fg)
      o("  tutorial      Replay the welcome walkthrough", T.fg)
      if S.userTier >= 1 and avail("swap") then
      o("  optimize swap       Disk-swap status ('slow RAM' on /var/swap)", T.fg)
      end
      if S.userTier >= 2 then
      o("  bootsettings [..]   Edit boot profile/verbosity  (or DEL at boot)", T.fg)
      end
      o("", T.fg)
      o(" Session & Power", T.highlight)
      o("  whoami  passwd  logout", T.fg)
      if S.userTier >= 2 then
      o("  users                            List user accounts", T.fg)
      o("  reboot  shutdown", T.fg)
      end
      if S.userTier >= 3 then
      o("", T.fg)
      o(" Administration (root)", T.highlight)
      o("  useradd <user>                   Create a new user", T.fg)
      o("  userdel <user>                   Delete a user", T.fg)
      o("  usermod <user> lock|unlock|admin|user  Modify user", T.fg)
      o("  deploy <mount>                   Copy TOS to another disk", T.fg)
      end
      if S.userTier >= 2 then
      o("", T.fg)
      o(" Environment & Services", T.highlight)
      o("  env [KEY=VAL]   Show/set environment variables", T.fg)
      o("  service [start|stop <n>]  Manage startup services", T.fg)
      o("  cron [list|add|rm]        Scheduled tasks", T.fg)
      end

      local hasRs, hasRobot = avail("component:redstone"), avail("component:robot")
      local hasInv, hasTape = avail("inventory"), avail("module:tape")
      if hasRs or hasRobot or hasInv or hasTape or S.userTier >= 2 then
      o("", T.fg)
      o(" Peripherals", T.highlight)
      if hasRs    then o("  redstone [set|pulse] Control redstone I/O  (rs = alias)", T.fg) end
      if hasRobot then o("  robot <cmd>          Robot/drone movement & interaction", T.fg) end
      if hasInv   then o("  inventory [side]     Inspect inventories  (inv = alias)", T.fg) end
      if hasTape  then o("  tape [subcmd]        Tape drive data storage (module)", T.fg) end
      if S.userTier >= 2 then
      o("  component <type> [method] [args]  Call any component", T.fg)
      end
      end
      if NM then
      o("", T.fg)
      o(" Network", T.highlight)
      o("  net  ping  hostname", T.fg)
      if S.userTier >= 1 then
      o("  chat               Open chat with trusted peers", T.fg)
      end
      if S.userTier >= 2 then
      o("  hostname  config  battery  audio", T.fg)
      o("  rsh <addr> <cmd>   Run command on remote peer", T.fg)
      o("  scp <addr>:<path> <local>  Transfer file from peer", T.fg)
      o("  screen [list|next|N]  Manage multiple displays", T.fg)
      end
      end
      o("", T.fg)
      o(" Packages & Disks", T.highlight)
      o("  pkg list           List installed packages", T.fg)
      o("  pkg search         Show packages on repos + mounted disks", T.fg)
      if S.userTier >= 2 then
      o("  pkg install <name>         Install an add-on (deps + verify)", T.fg)
      o("  pkg enable|disable <name>  Toggle an installed package", T.fg)
      o("  pkg uninstall <name>       Remove a package", T.fg)
      o("  pkg install                Install from an inserted disk (no arg)", T.fg)
      end
      o("  disk [list]        List removable disks", T.fg)
      o("  disk info <mount>  Show disk contents", T.fg)
      if S.userTier >= 2 then
      o("  disk install <mount>          Install module from disk", T.fg)
      o("  disk export <name> <mount>    Write module to disk", T.fg)
      end
      o("  disk eject <mount> Unmount a disk", T.fg)
      if S.userTier >= 2 then
      o("", T.fg)
      o(" Compatibility", T.highlight)
      o("  compat             Show OpenOS compatibility status", T.fg)
      end
      o("", T.fg)
      o(" Pipes & Redirects", T.highlight)
      o("  cmd1 | cmd2        Pipe output of cmd1 into cmd2", T.fg)
      o("  cmd > file         Redirect output to file", T.fg)
      o("  cmd >> file        Append output to file", T.fg)
      o("", T.fg)
      o("Showing only what's installed here. 'man <topic>' for detail; MANUAL.md for the book.", T.dim)
    end
  end

  C.man = function(args, o)
    local MANDIR = "/usr/man"
    local topic = args and args[1]
    if not topic then
      o("Manual pages — usage: man <topic>", T.title)
      local pages = (F.isDirectory and F.isDirectory(MANDIR) and F.list(MANDIR)) or {}
      if type(pages) == "table" and #pages > 0 then
        table.sort(pages)
        for _, p in ipairs(pages) do
          local name = (p:gsub("/$", "")):gsub("%.man$", "")
          if name ~= "" then o("  " .. name, T.fg) end
        end
      else
        o("  (no manual pages installed under " .. MANDIR .. ")", T.dim)
      end
      o("Depth: help (quick) < man (detailed) < MANUAL.md (the full book)", T.dim)
      return
    end

    topic = tostring(topic):gsub("[^%w_%-]", "")
    if topic == "" then o("man: invalid topic", T.error); return end
    local path = F.join(MANDIR, topic .. ".man")
    if not F.exists(path) then path = F.join(MANDIR, topic) end
    if not F.exists(path) then
      o("No manual page for '" .. topic .. "'.", T.error)
      o("Try 'help " .. topic .. "', or open MANUAL.md for the full book.", T.dim)
      return
    end
    local content = F.readFile(path)
    if not content then o("man: cannot read page", T.error); return end
    if openViewTab then
      local buf = {}
      for l in (content .. "\n"):gmatch("([^\n]*)\n") do
        local col = T.fg
        if l:match("^[A-Z][A-Z0-9 /%-]+$") then col = T.title
        elseif l:match("^%s") then col = T.dim end
        buf[#buf + 1] = { l, col }
      end
      openViewTab(buf, "man " .. topic)
    else
      for l in (content .. "\n"):gmatch("([^\n]*)\n") do o(l, T.fg) end
    end
  end

  C.about = function(args, o)

    local tos = _G._TOS or {}
    local vendor, motto, tagline = "Strata Systems LLC", nil, "Terminal Operating System"
    local okL, logo = pcall(require, "kernel.logo")
    if okL and logo then
      vendor  = logo.VENDOR  or vendor
      motto   = logo.MOTTO
      tagline = logo.TAGLINE or tagline
    end
    o("TOS - " .. tagline, T.title)
    o("Version " .. (tos.version or "?") .. "  [" .. (tos.codename or "?") .. "]", T.highlight)
    o("GPU T" .. tier .. " | " ..
      math.floor(computer.totalMemory() / 1024) .. "K RAM", T.dim)
    o(vendor .. "   -   GNU GPL v3.0", T.dim)
    if motto and motto ~= "" then o('"' .. motto .. '"', T.dim) end
    o("", T.fg)
    o("A secure, multi-seat terminal OS for OpenComputers:", T.fg)
    o("  - Sandboxed processes, role-based users, encrypted homes", T.fg)
    o("  - Tabbed file browser + editor, themeable panels UI", T.fg)
    o("  - Zero-trust networking: chat, mesh mail, clustering", T.fg)
    o("  - Package manager + Optional Utilities add-on disk", T.fg)
    o("  - Boot Settings (DEL at POST), swap, backups, OpenOS compat", T.fg)
    o("", T.fg)
    o("'help' lists commands · 'tutorial' walks you through it.", T.dim)
  end

  C.ver = C.about

  C.echo = function(args, o)
    o(table.concat(args, " "), T.fg)
  end

  C.notify = function(args, o)
    local okN, nf = pcall(require, "kernel.notify")
    if not okN or not nf then o("notify unavailable", T.error); return end

    local style, title, rest = "info", nil, {}
    local skip
    for i = 1, #(args or {}) do
      local a = tostring(args[i])
      if i == skip then
      elseif a:sub(1, 2) == "--" then
        local k, v = a:match("^%-%-([%w%-]+)=?(.*)$")
        if k == "style" or k == "title" then
          if v == "" and args[i + 1] and tostring(args[i + 1]):sub(1, 2) ~= "--" then
            v = tostring(args[i + 1]); skip = i + 1
          end
          if k == "style" then style = v else title = v end
        end
      else rest[#rest + 1] = a end
    end
    local message = table.concat(rest, " ")

    if message == "" then
      o("Usage: notify <message> [--style info|warn|danger|error] [--title T]", T.title)
      o("Puts a modal dialog box in front of every seat — the intrusive", T.dim)
      o("counterpart to 'echo', which only writes above the command line.", T.dim)
      o("", T.dim)
      o(string.format("Pending now: %d   (limits: %ds between boxes, %ds per source)",
        nf.depth(), nf.MIN_GAP, nf.MIN_SOURCE_GAP), T.dim)
      return
    end

    local id, why = nf.post({
      message = message, style = style, title = title,

      from = "notify/" .. tostring(S.who or "?"),
    })
    if id then
      o("Raised on every seat (dialog #" .. id .. ").", T.highlight)
    else

      o("Not raised: " .. tostring(why), T.warning)
      o("The message is in the log either way ('log' to see it).", T.dim)
    end
  end

  C.tutorial = function(args, o)
    local ok2, tut = pcall(require, "shell.tutorial")
    if not ok2 then o("Tutorial module unavailable", T.error); return end

    if args[1] == "--reset" then
      local sess = (U and st and U.getSession) and U.getSession(st) or nil
      local mark = tut.markerFor and tut.markerFor(sess)
      if mark and F.exists(mark) then
        F.remove(mark)
        o("Tutorial reset — it will run again at your next login.", T.success or T.fg)
      elseif mark then
        o("Tutorial was not marked done for this account.", T.dim)
      else
        o("This account has no home to remember the tutorial in.", T.dim)
      end
    end
    tut.run({ D = D, F = F, U = U, st = st, W = W, H = H })
    deps.drawAll()
  end

  C.cls = function(args, o)
    D.fill(1, 1, W, H, " ", T.fg, T.bg)
    deps.drawAll()
  end
  C.clear = C.cls
  C.cd = function(args, o)
    if not args[1] then o(S.cwd, T.fg); return end
    local target = args[1]
    if target == ".." then
      S.cwd = S.cwd:match("^(.*)/[^/]+/?$") or "/"
      if S.cwd == "" then S.cwd = "/" end
    else
      local t = rp(target):gsub("//+", "/")
      if t ~= "/" and t:sub(-1) == "/" then t = t:sub(1,-2) end
      if F.isDirectory(t) then S.cwd = t
      else o("Not a directory: " .. target, T.error); return end
    end
    S.browser.path = S.cwd
    S.browser.sel  = 1
    S.browser.scroll = 0
    deps.loadFiles(S.browser)
  end

  C.ls = function(args, o)
    local p  = rp(args[1] or S.cwd)
    if not canRead(p, o) then return end
    local ok2, l = pcall(F.list, p)
    if not ok2 or not l then o("Cannot list: " .. p, T.error); return end
    local e = {}
    if type(l) == "table" then for _, n in ipairs(l) do e[#e+1] = n end
    elseif type(l) == "function" then for n in l do e[#e+1] = n end end
    table.sort(e, function(a, b2)
      local ad, bd = a:sub(-1)=="/", b2:sub(-1)=="/"
      if ad ~= bd then return ad end return a < b2
    end)
    o(string.format(" %-24s %8s", "Name", "Size"), T.title)
    o(string.rep("-", 34), T.border)
    for _, n in ipairs(e) do
      if n:sub(-1) == "/" then
        o(string.format(" %-24s %8s", "["..n:sub(1,-2).."]", "<DIR>"), T.dir or T.highlight)
      else
        local sz = F.size(F.join(p, n))
        local sc = T.fg
        if n:match("%.lua$") then sc = T.file_lua or T.file_exec or T.highlight
        elseif n:match("%.cfg$") or n:match("%.conf$") then sc = T.file_cfg or T.warning
        elseif n:match("%.log$") then sc = T.file_log or T.dim end
        o(string.format(" %-24s %8s", n:sub(1,24), fmtSz(sz)), sc)
      end
    end
    o(#e .. " items", T.dim)
  end
  C.dir = C.ls

  C.cat = function(args, o)
    if not args[1] then o("Usage: cat <file>", T.dim); return end
    local p = rp(args[1])
    if not canRead(p, o) then return end
    local c = F.readFile(p)
    if c then for l in c:gmatch("([^\n]*)\n?") do o(l, T.fg) end
    else o("Cannot read: " .. args[1], T.error) end
  end
  C.type = C.cat

  C.more = function(args, o)
    if not args[1] then o("Usage: more <file>", T.dim); return end
    local path = rp(args[1])
    if not canRead(path, o) then return end
    local content = F.readFile(path)
    if not content then o("Cannot read: " .. args[1], T.error); return end
    local buf = { { " " .. path, T.title } }
    for l in content:gmatch("([^\n]*)\n?") do buf[#buf+1] = {l, T.fg} end
    openViewTab(buf, args[1]:match("[^/]+$") or args[1])
  end

  C.mkdir = function(args, o)
    if not args[1] then o("Usage: mkdir <dir>", T.dim); return end
    local p      = rp(args[1])
    local parent = p:match("^(.*)/[^/]+/?$") or "/"
    if not canWrite(parent, o) then return end
    if F.makeDirectory(p) then
      refreshBrowser()
      o("Created: " .. args[1], T.highlight)
    else o("Failed", T.error) end
  end

  C.touch = function(args, o)
    if not args[1] then o("Usage: touch <file>", T.dim); return end
    local p = rp(args[1])
    if not canWrite(p, o) then return end
    if not F.exists(p) then
      if not F.writeFile(p, "") then o("Failed", T.error); return end
    end
    refreshBrowser()
    o("Touched: " .. args[1], T.highlight)
  end

  local function parseKeep(args)
    local keep, files = false, {}
    for _, a in ipairs(args) do
      if a == "-k" or a == "--keep" then keep = true else files[#files + 1] = a end
    end
    return keep, files
  end

  C.compress = function(args, o)
    local keep, files = parseKeep(args)
    if not files[1] then o("Usage: compress <file> [out]   (-k keeps original)", T.dim); return end
    local cz = K.getCompress and K.getCompress()
    if not cz or not cz.available() then
      o("Compression needs a data card (none detected).", T.error); return
    end
    local src = rp(files[1])
    if not canRead(src, o) then return end
    if not F.exists(src) or (F.isDirectory and F.isDirectory(src)) then
      o("Not a file: " .. files[1], T.error); return
    end
    local data = F.readFile(src)
    if not data then o("Read failed", T.error); return end
    local out = files[2] and rp(files[2]) or (src .. ".tcz")
    if not canWrite(out, o) then return end
    local blob, method, orig, packed = cz.pack(data)
    if not blob then o("Compress failed", T.error); return end
    if not F.writeFile(out, blob) then o("Write failed", T.error); return end
    if not keep and out ~= src then pcall(F.remove, src) end
    refreshBrowser()
    local pct = (orig > 0) and math.floor((orig - packed) * 100 / orig) or 0
    o(string.format("%s -> %s  (%d%% smaller: %s -> %s)",
      files[1], (out:gsub("^.*/", "")), pct, fmtSz(orig), fmtSz(packed)),
      method == "deflate" and T.highlight or T.warning)
    if method == "stored" then
      o("(stored uncompressed — data didn't shrink)", T.dim)
    end
  end

  C.decompress = function(args, o)
    local keep, files = parseKeep(args)
    if not files[1] then o("Usage: decompress <file.tcz> [out]   (-k keeps original)", T.dim); return end
    local src = rp(files[1])
    if not canRead(src, o) then return end
    if not F.exists(src) then o("No such file: " .. files[1], T.error); return end
    local blob = F.readFile(src)
    if not blob then o("Read failed", T.error); return end
    local cz = K.getCompress and K.getCompress()
    if not cz then o("Compression module unavailable", T.error); return end
    if not cz.isPacked(blob) then o("Not a .tcz container: " .. files[1], T.error); return end
    local data, err = cz.unpack(blob)
    if not data then o("Decompress failed: " .. tostring(err), T.error); return end
    local out
    if files[2] then out = rp(files[2])
    elseif src:sub(-4) == ".tcz" then out = src:sub(1, -5)
    else out = src .. ".out" end
    if not canWrite(out, o) then return end
    if not F.writeFile(out, data) then o("Write failed", T.error); return end
    if not keep and out ~= src then pcall(F.remove, src) end
    refreshBrowser()
    o(string.format("%s -> %s  (%s restored)",
      files[1], (out:gsub("^.*/", "")), fmtSz(#data)), T.highlight)
  end

  C.rm = function(args, o)

    local recursive, hard = false, false
    local targets = {}
    for _, a in ipairs(args) do
      if a == "-r" or a == "-rf" or a == "-R" then recursive = true
      elseif a == "--hard" or a == "-H" then hard = true
      else targets[#targets + 1] = a end
    end
    if #targets == 0 then o("Usage: rm [-r] [--hard] <path>", T.dim); return end

    local target = targets[1]
    local p = rp(target)
    if p == "/" then o("Cannot remove root", T.error); return end

    local systemGuards = {
      "^/$", "^/init%.lua$", "^/bios%.lua$",
      "^/tos$", "^/tos/", "^/etc$", "^/etc/",
      "^/boot$", "^/boot/",
    }
    for _, pat in ipairs(systemGuards) do
      if p:match(pat) and not recursive then
        o("Refusing to remove protected path without -r: " .. p, T.error)
        return
      end
    end

    if not canWrite(p, o) then return end

    if F.isDirectory and F.isDirectory(p) then
      if not recursive then
        o("Cannot remove directory without -r: " .. p, T.error)
        return
      end
      local items = F.list and F.list(p)
      if items and #items > 0 then
        o("Removing " .. #items .. " item(s) under " .. p .. "...", T.dim)
      end
    end

    local trashOk = false
    local systemSkip = p:match("^/tos") or p:match("^/etc") or p:match("^/var") or p:match("^/usr")
    if not hard and not systemSkip then
      local okT, trashMod = pcall(require, "kernel.trash")
      if okT and trashMod and trashMod.put then
        local sess = helpers.sessionOf(S)
        local ok2, err2 = trashMod.put(p, sess)
        if ok2 then trashOk = true; o("Trashed: " .. target .. " (use 'restore' to undo)", T.highlight) end
      end
    end

    if not trashOk then
      if F.remove(p) then
        refreshBrowser()
        o("Removed: " .. target, T.highlight)
      else o("Failed", T.error) end
    else
      refreshBrowser()
    end
  end

  C.trash = function(args, o)
    local okT, trashMod = pcall(require, "kernel.trash")
    if not okT or not trashMod then o("Trash unavailable", T.error); return end
    local sub = args[1] or "list"
    local sess = helpers.sessionOf(S)
    if sub == "list" or sub == "ls" then
      local items = trashMod.list(sess)
      if #items == 0 then o("Trash is empty.", T.dim); return end
      o(string.format(" %-20s %-8s %s", "name", "size", "origin"), T.title)
      for _, it in ipairs(items) do
        o(string.format(" %-20s %-8d %s",
          it.name:sub(1, 20), it.size, it.origin), T.fg)
      end
      local u = trashMod.usage(sess)
      if u then
        o(string.format(" %d/%d items, %d/%d bytes used",
          u.count, u.max_count, u.bytes, u.max_bytes), T.dim)
      end
    elseif sub == "empty" then
      local ok2, n = trashMod.empty(sess)
      if ok2 then o("Emptied " .. tostring(n) .. " items.", T.highlight)
      else o(tostring(n or "empty failed"), T.error) end
    elseif sub == "restore" then

      if not args[2] then o("Usage: trash restore <name> [dest] [--force]", T.dim); return end
      local force, dest = false, nil
      for i = 3, #args do
        if args[i] == "--force" or args[i] == "-f" then force = true
        else dest = args[i] end
      end
      local ok2, where = trashMod.restore(args[2],
        { session = sess, dest = dest, force = force })
      if ok2 then
        refreshBrowser()
        o("Restored to " .. tostring(where), T.highlight)
      else
        o(tostring(where or "restore failed"), T.error)
      end
    else
      o("Usage: trash [list|empty|restore <name> [dest] [--force]]", T.dim)
    end
  end

  C.vault = function(args, o)
    local okV, vmod = pcall(require, "kernel.vault")
    if not okV or not vmod then o("vault module unavailable", T.error); return end
    local sub = args[1]

    local sess = helpers.sessionOf(S)
    local secfs = _G._TOS and _G._TOS.securefs

    local function readBytes(path)
      if secfs and secfs.readFile then return secfs.readFile(path, sess) end
      return nil, "securefs unavailable (refusing unchecked read)"
    end
    local function writeBytes(path, data)
      if secfs and secfs.writeFile then return secfs.writeFile(path, data, sess) end
      return false, "securefs unavailable (refusing unchecked write)"
    end

    if sub == "encrypt" or sub == "decrypt" then
      local src, dst, passphrase = args[2], args[3], args[4]
      if not src or not dst or not passphrase then
        o("Usage: vault " .. sub .. " <src> <dst> <passphrase>", T.dim); return
      end
      local data = readBytes(rp(src))
      if not data then o("Cannot read: " .. src, T.error); return end
      local out, info
      if sub == "encrypt" then
        out, info = vmod.encrypt(data, passphrase)
      else
        if not vmod.isEncrypted(data) then
          o("Source is not a TOS vault blob.", T.warning); return
        end
        out, info = vmod.decrypt(data, passphrase)
      end
      if not out then o("Failed: " .. tostring(info), T.error); return end
      local wOk, wErr = writeBytes(rp(dst), out)
      if not wOk then o("Write failed: " .. tostring(wErr), T.error); return end
      o(string.format("%s %d -> %d bytes (algo=%s)",
        sub == "encrypt" and "Encrypted" or "Decrypted",
        #data, #out, tostring(info.algo)), T.highlight)

    elseif sub == "encrypt-in-place" or sub == "decrypt-in-place" then
      local file, passphrase = args[2], args[3]
      if not file or not passphrase then
        o("Usage: vault " .. sub .. " <file> <passphrase>", T.dim); return
      end
      local path = rp(file)
      local data = readBytes(path)
      if not data then o("Cannot read: " .. file, T.error); return end
      local out, info
      if sub:sub(1, 7) == "encrypt" then
        if vmod.isEncrypted(data) then
          o("Already encrypted — refusing to double-encrypt.", T.warning); return
        end
        out, info = vmod.encrypt(data, passphrase)
      else
        if not vmod.isEncrypted(data) then
          o("Not a vault blob — nothing to decrypt.", T.warning); return
        end
        out, info = vmod.decrypt(data, passphrase)
      end
      if not out then o("Failed: " .. tostring(info), T.error); return end
      local wOk, wErr = writeBytes(path, out)
      if not wOk then o("Write failed: " .. tostring(wErr), T.error); return end
      o(string.format("%s in place: %d -> %d bytes",
        sub:sub(1, 7) == "encrypt" and "Encrypted" or "Decrypted",
        #data, #out), T.highlight)

    elseif sub == "info" then
      local file = args[2]
      if not file then o("Usage: vault info <file>", T.dim); return end
      local data = readBytes(rp(file))
      if not data then o("Cannot read: " .. file, T.error); return end
      if not vmod.isEncrypted(data) then
        o("Not a vault blob (no TVAULT1 magic).", T.warning); return
      end

      o(string.format(" file:     %s", file), T.title)
      o(string.format(" size:     %d bytes", #data), T.fg)
      local off = #vmod.MAGIC + 1
      local algo = data:sub(off, off + 3):gsub("\0+$", "")
      o(string.format(" algo:     %s", algo), T.fg)
      o(string.format(" ctLen:    encrypted body inside this blob"), T.dim)
      o(" (decrypt with the right passphrase to access contents)", T.dim)

    elseif sub == "tape" then

      local tapeSub = args[2]
      if tapeSub ~= "encrypt" and tapeSub ~= "decrypt" then
        o("Usage: vault tape encrypt|decrypt <passphrase>", T.dim); return
      end

      local tapeCmd = C.tape
      if not tapeCmd then
        o("Tape module not installed (run `pkg install tape`).", T.warning); return
      end
      tapeCmd({ tapeSub, args[3] }, o)

    else
      o("Usage: vault [encrypt|decrypt|encrypt-in-place|decrypt-in-place|info|tape] ...", T.dim)
      o("  vault encrypt <src> <dst> <passphrase>", T.dim)
      o("  vault decrypt <src> <dst> <passphrase>", T.dim)
      o("  vault encrypt-in-place <file> <passphrase>", T.dim)
      o("  vault decrypt-in-place <file> <passphrase>", T.dim)
      o("  vault info <file>", T.dim)
      o("  vault tape encrypt|decrypt <passphrase>", T.dim)
    end
  end

  C.keychain = function(args, o)
    local km = _G._TOS and _G._TOS.keychain
    if not km then o("keychain module unavailable", T.error); return end
    local sess = helpers.sessionOf(S)
    local sub = args[1] or "status"

    if sub == "status" then
      o(km.isUnlocked(sess) and "unlocked" or "locked", T.fg)

    elseif sub == "unlock" then
      if not promptInput then o("interactive prompt unavailable", T.error); return end
      local master = promptInput("Master password: ", 64, "*") or ""
      if #master == 0 then o("(empty — cancelled)", T.dim); return end
      local ok2, err = km.unlock(master, sess)
      if ok2 then o("Keychain unlocked.", T.highlight)
      else o("Unlock failed: " .. tostring(err), T.error) end

    elseif sub == "lock" then
      km.lock(sess)
      o("Keychain locked.", T.highlight)

    elseif sub == "list" then
      if not km.isUnlocked(sess) then o("Keychain is locked.", T.warning); return end
      local names = km.list(sess)
      if #names == 0 then o("(empty)", T.dim); return end
      for _, n in ipairs(names) do o("  " .. n, T.fg) end

    elseif sub == "set" then
      if not args[2] then o("Usage: keychain set <name>", T.dim); return end
      if not km.isUnlocked(sess) then o("Keychain is locked. Run 'keychain unlock' first.", T.warning); return end
      if not promptInput then o("interactive prompt unavailable", T.error); return end
      local pass = promptInput("Passphrase for '" .. args[2] .. "': ", 256, "*") or ""
      if #pass == 0 then o("(empty — cancelled)", T.dim); return end
      local ok2, err = km.set(args[2], pass, sess)
      if ok2 then o("Slot '" .. args[2] .. "' saved.", T.highlight)
      else o("Save failed: " .. tostring(err), T.error) end

    elseif sub == "get" then
      if not args[2] then o("Usage: keychain get <name>", T.dim); return end
      if not km.isUnlocked(sess) then o("Keychain is locked.", T.warning); return end
      local pass, err = km.get(args[2], sess)
      if pass then o(pass, T.fg)
      else o(tostring(err or "no such slot"), T.error) end

    elseif sub == "remove" or sub == "rm" then
      if not args[2] then o("Usage: keychain remove <name>", T.dim); return end
      if not km.isUnlocked(sess) then o("Keychain is locked.", T.warning); return end
      local ok2, err = km.remove(args[2], sess)
      if ok2 then o("Removed '" .. args[2] .. "'.", T.highlight)
      else o("Remove failed: " .. tostring(err), T.error) end

    else
      o("Usage: keychain [status|unlock|lock|list|set|get|remove] ...", T.dim)
    end
  end

  C.profile = function(args, o)
    local pmod = _G._TOS and _G._TOS.profile
    if not pmod then o("profile module unavailable", T.error); return end
    local sess = helpers.sessionOf(S)
    local sub = args[1] or "show"

    if sub == "show" then
      local p, exists = pmod.load(sess)
      o(string.format(" name:    %s", p.name), T.title)
      o(string.format(" theme:   %s", p.theme or "(unset — uses `theme set` choice or default)"), T.fg)
      o(string.format(" cwd:     %s", p.cwd or "(unset)"), T.fg)
      o(string.format(" prompt:  %s", p.prompt or "(default)"), T.fg)
      local envN = 0; for _ in pairs(p.env) do envN = envN + 1 end
      o(string.format(" env:     %d entries", envN), T.fg)
      o(string.format(" startup: %d commands", #p.startup), T.fg)
      if not exists then o(" (no profile file — showing defaults)", T.dim) end

    elseif sub == "set" then
      if not args[2] or not args[3] then
        o("Usage: profile set <field> <value>", T.dim)
        o("  fields: name, theme, cwd, prompt", T.dim)
        return
      end
      local field, value = args[2], args[3]
      local p = pmod.load(sess)
      if field == "name" or field == "theme" or field == "cwd" or field == "prompt" then

        if field == "theme" then
          local tm = _G._TOS and _G._TOS.theme
          if tm and tm.preset and not tm.preset(value) then
            o("Unknown theme preset: " .. value, T.error)
            if tm.list then
              o("Available: " .. table.concat(tm.list(), ", "), T.dim)
            end
            return
          end
        end
        p[field] = value
        local ok2, err2 = pmod.save(p, sess)
        if ok2 then o("Profile updated. Re-login to apply.", T.highlight)
        else o(tostring(err2 or "save failed"), T.error) end
      else
        o("Unknown field: " .. field, T.error)
      end

    elseif sub == "env" then
      if not args[2] then o("Usage: profile env <KEY> [VALUE]", T.dim); return end
      local p = pmod.load(sess)
      if args[3] then
        p.env[args[2]] = args[3]
        o("env[" .. args[2] .. "] set", T.highlight)
      else
        p.env[args[2]] = nil
        o("env[" .. args[2] .. "] cleared", T.highlight)
      end
      pmod.save(p, sess)

    elseif sub == "startup" then
      local action = args[2] or "list"
      local p = pmod.load(sess)
      if action == "add" then
        local cmd = table.concat(args, " ", 3)
        if #cmd == 0 then o("Usage: profile startup add <cmd>", T.dim); return end
        p.startup[#p.startup + 1] = cmd
        pmod.save(p, sess)
        o("Added.", T.highlight)
      elseif action == "clear" then
        p.startup = {}
        pmod.save(p, sess)
        o("Startup commands cleared.", T.highlight)
      else
        for i, cmd in ipairs(p.startup) do
          o(string.format(" %d. %s", i, cmd), T.fg)
        end
        if #p.startup == 0 then o("(no startup commands)", T.dim) end
      end

    elseif sub == "reset" then
      local pmodSecfs = _G._TOS and _G._TOS.securefs
      if pmodSecfs and sess and sess.home and sess.home ~= "/" then
        pmodSecfs.remove(sess.home .. "/.profile.cfg", sess)
      end
      o("Profile reset to defaults.", T.highlight)

    else
      o("Usage: profile [show|set|env|startup|reset]", T.dim)
    end
  end

  C.cp = function(args, o)
    if not args[2] then o("Usage: cp <src> <dst>", T.dim); return end
    local src, dst = rp(args[1]), rp(args[2])

    if F.isDirectory(dst) then dst = F.join(dst, src:match("[^/]+$") or src) end
    local ok2, err2 = F.copy(src, dst)
    if ok2 then
      refreshBrowser()
      o("Copied: " .. args[2], T.highlight)
    else o(err2 or "Failed", T.error) end
  end
  C.mv = function(args, o)
    if not args[2] then o("Usage: mv <src> <dst>", T.dim); return end
    local src, dst = rp(args[1]), rp(args[2])

    if F.isDirectory(dst) then dst = F.join(dst, src:match("[^/]+$") or src) end
    if not canWrite(src, o) then return end
    if not canWrite(dst, o) then return end

    if F.rename(src, dst) then
      refreshBrowser()
      o("Moved: " .. args[2], T.highlight)
    else
      local cok, cerr = F.copy(src, dst)
      if cok and F.remove(src) then
        refreshBrowser()
        o("Moved: " .. args[2], T.highlight)
      else
        o("Move failed: " .. tostring(cerr or "cross-fs copy failed"), T.error)
      end
    end
  end
  C.find = function(args, o)
    local root    = "/"
    local pattern = nil
    local i = 1
    while i <= #args do
      if args[i] == "-name" and args[i+1] then
        pattern = args[i+1]; i = i + 2
      else
        root = rp(args[i]); i = i + 1
      end
    end

    if pattern then
      local pok, perr = pcall(string.match, "", pattern)
      if not pok then
        o("Invalid pattern: " .. tostring(perr), T.error)
        return
      end
    end
    o("Searching " .. root .. " ...", T.dim)

    local MAX_DEPTH   = 16
    local MAX_RESULTS = 1000
    local results = {}

    local function silentCanRead(p)

      if not U or not U.canAccessAs then return false end
      local sess = helpers.sessionOf(S)
      local ok = U.canAccessAs(sess, p, "r")
      return ok
    end
    local function scan(dir, depth)
      if depth > MAX_DEPTH then return end
      if #results >= MAX_RESULTS then return end
      if not silentCanRead(dir) then return end
      local ok2, list = pcall(F.list, dir)
      if not ok2 or not list then return end
      local fitems = {}
      if type(list) == "table" then fitems = list
      elseif type(list) == "function" then for n in list do fitems[#fitems+1] = n end end
      for _, n in ipairs(fitems) do
        if #results >= MAX_RESULTS then break end
        coopYield()
        local full = F.join(dir, n:gsub("/$",""))
        local isDir = n:sub(-1) == "/"
        local matched = false
        if pattern then
          local okA, ra = pcall(string.match, full, pattern)
          local okB, rb = pcall(string.match, n, pattern)
          matched = (okA and ra) or (okB and rb)
        else
          matched = true
        end
        if matched then
          results[#results+1] = { full .. (isDir and "/" or ""), isDir and (T.dir or T.highlight) or T.fg }
        end
        if isDir and not full:match("^/tos") then scan(full, depth + 1) end
      end
    end
    scan(root, 0)
    if #results == 0 then o("No matches found", T.dim)
    else for _, r in ipairs(results) do o(r[1], r[2]) end end
    local note = #results .. " result(s)"
    if #results >= MAX_RESULTS then note = note .. " (truncated at " .. MAX_RESULTS .. ")" end
    o(note, T.dim)
  end

  C.grep = function(args, o)
    if not args[2] then o("Usage: grep <pattern> <file>", T.dim); return end
    local pat = args[1]
    local path    = rp(args[2])
    if not canRead(path, o) then return end
    local content = F.readFile(path)
    if not content then o("Cannot read: " .. args[2], T.error); return end
    local count = 0
    local ln    = 0
    for line in content:gmatch("([^\n]*)\n?") do
      ln = ln + 1
      if line:find(pat, 1, true) then
        o(string.format("%4d: %s", ln, line), T.fg)
        count = count + 1
      end
    end
    o(count > 0 and (count .. " match(es)") or "No matches", T.dim)
  end

  C.wc = function(args, o)
    if not args[1] then o("Usage: wc <file>", T.dim); return end
    local p = rp(args[1])
    if not canRead(p, o) then return end
    local content = F.readFile(p)
    if not content then o("Cannot read: " .. args[1], T.error); return end
    local wlines, words, bytes = 0, 0, #content
    for line in content:gmatch("([^\n]*)\n?") do
      wlines = wlines + 1
      for _ in line:gmatch("%S+") do words = words + 1 end
    end
    o(string.format(" Lines: %d  Words: %d  Bytes: %d  -- %s",
      wlines, words, bytes, args[1]), T.fg)
  end

  C.pwd = function(_, o)
    o(S.cwd or "/", T.fg)
  end

  C.head = function(args, o)
    if not args[1] then o("Usage: head <file> [lines]", T.dim); return end
    local p = rp(args[1])
    if not canRead(p, o) then return end
    local content = F.readFile(p)
    if not content then o("Cannot read: " .. args[1], T.error); return end
    local n, shown = tonumber(args[2]) or 10, 0
    for line in content:gmatch("([^\n]*)\n?") do
      if shown >= n then break end
      o(line, T.fg); shown = shown + 1
    end
  end

  C.tail = function(args, o)
    if not args[1] then o("Usage: tail <file> [lines]", T.dim); return end
    local p = rp(args[1])
    if not canRead(p, o) then return end
    local content = F.readFile(p)
    if not content then o("Cannot read: " .. args[1], T.error); return end
    local n = tonumber(args[2]) or 10
    if n < 1 then return end
    local lines = {}
    for line in content:gmatch("([^\n]*)\n?") do lines[#lines + 1] = line end

    if #lines > 1 and lines[#lines] == "" then lines[#lines] = nil end
    for i = math.max(1, #lines - n + 1), #lines do
      o(lines[i], T.fg)
    end
  end

  C.which = function(args, o)
    if not args[1] then o("Usage: which <name>", T.dim); return end
    local name = args[1]:lower()
    local found = false

    local aliases = helpers.aliases(S)
    if aliases[name] then
      o(name .. ": alias for '" .. aliases[name] .. "'", T.highlight)
      o("  (expanded before dispatch; the expansion is resolved below)", T.dim)
      name = tostring(helpers.tokenizeSimple(aliases[name])[1] or name):lower()
      found = true
    end

    local cmdsMod = require("shell.panels.commands")
    local meta = cmdsMod.entry and cmdsMod.entry(name) or nil
    if meta then
      local tierN = meta.tier or 0
      o(name .. ": built-in (" .. (meta.category or "?") .. ", needs "
        .. helpers.tierName(tierN) .. ")", T.title)
      if meta.help then o("  " .. meta.help, T.fg) end
      if tierN > helpers.liveTier(S) then
        o("  You do not have the tier to run it — 'why " .. name .. "'.", T.warning)
      end
      found = true
    end

    local okP, pkgMod = pcall(require, "kernel.pkg")
    local owner = okP and pkgMod and pkgMod.ownerOfCommand
      and pkgMod.ownerOfCommand(name) or nil
    if owner then
      o(name .. ": package command from '" .. owner .. "'",
        meta and T.dim or T.title)
      if meta then o("  (shadowed by the built-in above)", T.dim) end
      found = true
    end

    local path, source = helpers.resolveProgram(F, name)
    if path then
      o(name .. ": " .. path .. (source == "path" and "  (via PATH)" or ""),
        found and T.dim or T.title)
      if found then o("  (shadowed by the entry above)", T.dim) end
      found = true
    end

    if not found then
      o(name .. ": not found", T.error)
      o("  Not a built-in, an installed package's command, or a program on", T.dim)
      o("  /bin, /usr/bin or /tos/shell. 'help' lists what this box has.", T.dim)
    end
  end

  C.alias = function(args, o)
    local pmod = _G._TOS and _G._TOS.profile
    if not pmod then o("profile module unavailable", T.error); return end
    local sess = helpers.sessionOf(S)

    if not args[1] then
      local p = pmod.load(sess)
      local names = {}
      for k in pairs(p.aliases or {}) do names[#names + 1] = k end
      table.sort(names)
      if #names == 0 then
        o("(no aliases)", T.dim)
        o("Define one:  alias ll ls -l", T.dim)
        return
      end
      for _, k in ipairs(names) do
        o(string.format(" %-12s %s", k, p.aliases[k]), T.fg)
      end
      return
    end

    local name = args[1]:lower()
    if not name:match("^[%w_%-]+$") then
      o("Bad alias name: " .. args[1], T.error)
      o("Letters, digits, underscore and hyphen only.", T.dim)
      return
    end
    local p = pmod.load(sess)
    if not args[2] then

      if p.aliases and p.aliases[name] then
        o(string.format(" %-12s %s", name, p.aliases[name]), T.fg)
      else
        o(name .. ": not aliased", T.dim)
      end
      return
    end

    local expansion = table.concat(args, " ", 2)

    local firstWord = tostring(helpers.tokenizeSimple(expansion)[1] or ""):lower()
    if firstWord == name then
      o("An alias cannot expand to itself.", T.error)
      o("To add default flags, alias to a different name.", T.dim)
      return
    end
    p.aliases = p.aliases or {}
    p.aliases[name] = expansion
    local ok2, err2 = pmod.save(p, sess)
    if not ok2 then o(tostring(err2 or "save failed"), T.error); return end
    helpers.invalidateAliases(S)
    o("alias " .. name .. " -> " .. expansion, T.highlight)
  end

  C.unalias = function(args, o)
    local pmod = _G._TOS and _G._TOS.profile
    if not pmod then o("profile module unavailable", T.error); return end
    if not args[1] then o("Usage: unalias <name>", T.dim); return end
    local sess = helpers.sessionOf(S)
    local name = args[1]:lower()
    local p = pmod.load(sess)
    if not p.aliases or not p.aliases[name] then
      o(name .. ": not aliased", T.dim); return
    end
    p.aliases[name] = nil
    local ok2, err2 = pmod.save(p, sess)
    if not ok2 then o(tostring(err2 or "save failed"), T.error); return end
    helpers.invalidateAliases(S)
    o("Removed alias '" .. name .. "'.", T.highlight)
  end

  C.du = function(args, o)
    local target = rp(args[1] or (S.cwd or "/"))
    if not canRead(target, o) then return end
    local function join(a, b) return a:sub(-1) == "/" and (a .. b) or (a .. "/" .. b) end
    local function sizeOf(path)
      if F.isDirectory(path) then
        local total, list = 0, F.list(path)
        if type(list) == "table" then
          for _, name in ipairs(list) do
            coopYield()
            total = total + sizeOf(join(path, name:gsub("/$", "")))
          end
        end
        return total
      end
      return (F.size and F.size(path)) or 0
    end
    if F.isDirectory(target) then
      local list = F.list(target)
      if type(list) == "table" then
        for _, name in ipairs(list) do
          local clean = name:gsub("/$", "")
          o(string.format(" %8s  %s", fmtSz(sizeOf(join(target, clean))), clean), T.fg)
        end
      end
    end
    o(string.format(" %8s  %s (total)", fmtSz(sizeOf(target)), target), T.title)
  end

  C.df = function(args, o)
    local okM, mon = pcall(require, "kernel.monitor")
    o(string.format(" %-16s %8s %8s %8s  %s", "Mount", "Total", "Used", "Free", "Use%"), T.title)
    o(string.rep("-", math.min(W, 56)), T.dim)
    local mounts = F.mounts and F.mounts() or {}
    if #mounts == 0 then
      o("(mount info unavailable)", T.dim)
    else
      for _, m in ipairs(mounts) do
        local total = m.total or 0
        local used  = m.used  or 0
        local free  = total - used
        local pct   = total > 0 and math.floor(used * 100 / total) or 0
        local bar   = (okM and mon.memBar) and mon.memBar(used, total, 8) or ""
        local bc    = pct < 80 and T.fg or (pct < 95 and T.warning or T.error)
        o(string.format(" %-16s %8s %8s %8s  [%s] %3d%%",
          (m.mountPoint or "?"):sub(1, 16), fmtSz(total), fmtSz(used), fmtSz(free), bar, pct), bc)
      end
    end

    if _G._TOS_ROOT_READONLY then
      o("", T.dim)
      o("WARNING: the root filesystem is READ-ONLY.", T.error)
      o("Nothing TOS writes will survive a reboot — users, logs, packages,", T.dim)
      o("settings. Install to a writable drive, or unprotect this one.", T.dim)
    end
    o("A path's own size: 'du <path>'.  Removable media + pools: 'disk'.", T.dim)
  end

  C.mem = function(args, o)
    local fr, tot = computer.freeMemory(), computer.totalMemory()
    local used = tot - fr
    local pct  = tot > 0 and math.floor(used * 100 / tot) or 0
    local okM, mon = pcall(require, "kernel.monitor")
    local barW = math.min(24, math.max(8, W - 36))
    local bar  = (okM and mon.memBar) and mon.memBar(used, tot, barW)
      or (string.rep("#", math.floor(pct / 100 * barW)) .. string.rep("-", barW - math.floor(pct / 100 * barW)))
    o("=== Memory ===", T.title)
    o(string.format(" RAM:  %dK used / %dK total   (%d%% used, %dK free)",
      math.floor(used / 1024), math.floor(tot / 1024), pct, math.floor(fr / 1024)), T.fg)
    local bc = pct < 75 and T.highlight or (pct < 90 and T.warning or T.error)
    o(" [" .. bar .. "]", bc)
    local okH, hal = pcall(function() return K.getHAL().systemInfo() end)
    if okH and hal and (hal.memTierName or hal.memTier) then
      o(" Tier: " .. (hal.memTierName or ("T" .. hal.memTier)), T.dim)
    end
    local sw = K.getSwap and K.getSwap()
    if sw and sw.usage then
      local okU, u = pcall(sw.usage)
      if okU and type(u) == "table" then
        o(string.format(" Swap: %dK / %dK on /var/swap   ('slow RAM' overflow)",
          math.floor((u.bytes or 0) / 1024), math.floor((u.max or 0) / 1024)), T.dim)
      end
    else
      o(" Swap: off   (enable in Boot Settings for low-RAM overflow)", T.dim)
    end
    if fr < 16 * 1024 then o(" ! Low memory — near the ~16K danger zone.", T.warning) end
    o("Live usage: 'monitor'.  Hardware tiers: 'hw'.", T.dim)
  end

  C.hw = function(args, o)
    local info = K.getHAL().systemInfo()
    o("=== Hardware ===", T.title)
    o(string.format(" CPU T%d    GPU T%d    RAM %s",
      info.cpuTier or 0, info.gpuTier or 0,
      info.memTierName or ("T" .. (info.memTier or 0))), T.fg)
    local okDC, dc = pcall(require, "kernel.datacard")
    if okDC and dc and dc.detect then
      local d = dc.detect()
      o(" Data card: " .. (d.present and d.name or "none"), d.present and T.fg or T.dim)
    end
    o(string.format(" Components: %d    Network: %s    Tunnel: %s",
      info.components or 0,
      info.canNetwork and "yes" or "no",
      info.hasTunnel and "yes" or "no"), T.dim)
    o("Full component list: 'devices'.  Memory detail: 'mem'.  Live: 'monitor'.", T.dim)
  end
  C.hardware = C.hw

  C.ps = function(args, o)
    local fgPID = P.getForeground(S.displayIdx)
    local sess = helpers.sessionOf(S)
    local viewerTier = (sess and sess.tier) or 0
    local viewerUser = sess and sess.user or "?"

    local verbose = (args[1] == "-v" or args[1] == "--verbose") and viewerTier >= 2

    if verbose then
      o(string.format(" %-4s %-14s %-8s %-3s %-10s %-6s %s",
        "PID", "Name", "State", "DSP", "Owner", "CPU", "Caps"), T.title)
    else
      o(string.format(" %-4s %-16s %-8s %-3s %-10s %s",
        "PID", "Name", "State", "DSP", "Owner", "CPU"), T.title)
    end
    o(string.rep("-", verbose and 70 or 50), T.border)

    for _, proc in ipairs(P.list()) do
      local procUser = proc.principal and proc.principal.user or "?"
      local procTier = proc.principal and proc.principal.tier or 0

      local visible = false
      if viewerTier >= 2 then visible = true
      elseif viewerTier >= 1 and procUser == viewerUser then visible = true
      elseif viewerTier >= 1 then

        visible = "redacted"
      end
      if visible == true then
        local fg2 = T.fg
        local state = proc.state
        if proc.tsr then state = "TSR" end
        if proc.pid == fgPID then
          fg2 = T.highlight; state = state .. " *"
        elseif proc.tsr then
          fg2 = T.dim
        end
        if verbose then
          local capsList = {}
          if proc.caps then
            for k in pairs(proc.caps) do capsList[#capsList + 1] = k end
            table.sort(capsList)
          end
          o(string.format(" %-4d %-14s %-8s %-3s %-10s %-6.1f %s",
            proc.pid, proc.name:sub(1,14), state,
            tostring(proc.display or "-"),
            (procUser):sub(1,10),
            proc.cpuTime or 0,
            #capsList > 0 and table.concat(capsList, ",") or "-"), fg2)
        else
          o(string.format(" %-4d %-16s %-8s %-3s %-10s %.1fs",
            proc.pid, proc.name:sub(1,16), state,
            tostring(proc.display or "-"),
            (procUser):sub(1,10),
            proc.cpuTime or 0), fg2)
        end
      elseif visible == "redacted" then
        o(string.format(" %-4d %-16s %-8s %-3s %-10s   ",
          proc.pid, "(other user)", "?", "?", "?"), T.dim)
      end
    end
    o("", T.dim)
    o(" * = foreground  |  -v for caps (admin+)  |  'monitor' for the live view", T.dim)
  end

  C.monitor = function(args, o)
    local okM, monMod = pcall(require, "shell.panels.monitorapp")
    if not okM then o("Monitor unavailable: " .. tostring(monMod), T.error); return end
    monMod.open(S)
  end
  C.top = C.monitor

  C.watch = function(args, o)
    if not args[1] then
      o("Usage: watch [seconds] <command ...>", T.dim)
      o("  Opens a self-updating tab. e.g.  watch ps  ·  watch 2 df  ·  watch mem", T.dim)
      return
    end
    local idx, interval = 1, tonumber(args[1])
    if interval then idx = 2 else interval = 1 end
    if interval < 1 then interval = 1 end
    if not args[idx] then o("Usage: watch [seconds] <command ...>", T.dim); return end
    local cmdline = table.concat(args, " ", idx)
    local name = (cmdline:match("^(%S+)") or ""):lower()

    local UNSAFE = {
      edit = true, lua = true, monitor = true, top = true, watch = true,
      launcher = true, launch = true, apps = true, kiosk = true, chat = true,
      more = true, man = true, vault = true, keychain = true, passwd = true,
      tutorial = true, bootsettings = true, useradd = true, ["tape-auth"] = true,
    }
    if UNSAFE[name] then
      o("Can't watch '" .. name .. "' — it's interactive/screen-driven.", T.error)
      return
    end
    if not deps.openLiveTab then o("Live tabs aren't available in this shell.", T.error); return end

    local function runOnce()
      local out = {}
      local parts = {}
      for w in cmdline:gmatch("%S+") do parts[#parts + 1] = w end
      if #parts == 0 then return out end
      local cname = parts[1]:lower()
      local cargs = {}
      for i = 2, #parts do cargs[#cargs + 1] = parts[i] end
      local fn = C[cname]
      if not fn then
        local okP, pkgMod = pcall(require, "kernel.pkg")
        if okP and pkgMod and pkgMod.getCommand then fn = pkgMod.getCommand(cname) end
      end
      if not fn then out[#out + 1] = { "Unknown command: " .. cname, T.error }; return out end
      local sink = function(text, color) out[#out + 1] = { tostring(text), color or T.fg } end
      local okR, err = pcall(fn, cargs, sink)
      if not okR then out[#out + 1] = { "Error: " .. tostring(err), T.error } end
      return out
    end
    deps.openLiveTab("watch: " .. cmdline, runOnce, interval)
  end

  C.why = function(args, o)
    local commandsMod = require("shell.panels.commands")
    local have = helpers.liveTier(S)
    local tone = {
      title = T.title or T.highlight or T.fg,
      ok    = T.success or T.highlight or T.fg,
      err   = T.error,
      fix   = T.highlight or T.fg,
      dim   = T.dim,
    }
    local function emit(lines)
      for _, l in ipairs(lines) do o(l.text, tone[l.tone] or T.fg) end
    end
    local target = args and args[1] and args[1]:lower()
    if not target then
      local d = S.lastDenial
      if d and d.cmd then
        emit(helpers.whyExplain(d.cmd, d.need, d.have or have, true))
      elseif d then
        o("Your last blocked action needed " .. helpers.tierName(d.need)
          .. "; you are " .. helpers.tierName(d.have or have) .. ".", T.error)
        o("Fix: run it on an admin/root account, or have an admin grant access.", tone.fix)
      else
        o("why <command>  — explain what a command needs and whether you can run it.", T.dim)
        o("Run `why` with no argument right after a 'Permission denied' to explain it.", T.dim)
      end
      return
    end
    local entry = commandsMod.entry(target)
    emit(helpers.whyExplain(target, entry and entry.tier or 0, have, entry ~= nil))
  end

  C.screendump = function(args, o)
    if not D or not D.dump then o("Screen capture isn't available on this seat.", T.error); return end
    local okCap, cap = pcall(D.dump)
    if not okCap or type(cap) ~= "table" or not cap.lines then
      o("Screen capture failed.", T.error); return
    end
    local path = (args and args[1]) and rp(args[1])
      or rp("screen-" .. math.floor(K.uptime()) .. ".txt")
    local who = (helpers.sessionOf(S) or {}).user or "?"
    local hdr = string.format("TOS screendump — seat %s · user %s · %dx%d · uptime %ds · read from the %s",
      tostring(S.displayIdx or "?"), who, cap.w or 0, cap.h or 0,
      math.floor(K.uptime()), tostring(cap.source or "?"))

    local NL = string.char(10)
    local blob = hdr .. NL .. string.rep("-", #hdr) .. NL
      .. table.concat(cap.lines, NL) .. NL
    if cap.bg then
      blob = blob .. NL .. "--- background colour runs, per row ---" .. NL
      for y = 1, (cap.h or 0) do
        local runs = cap.bg[y]
        if runs then
          local parts = {}
          for _, r in ipairs(runs) do
            parts[#parts + 1] = string.format("%d-%d:%s", r.from, r.to,
              r.c and string.format("%06X", r.c) or "nil")
          end
          blob = blob .. string.format("row %2d  %s", y,
            table.concat(parts, "  ")) .. NL
        end
      end
      local T2 = S.T or {}
      blob = blob .. NL .. "theme: bg=" .. string.format("%06X", T2.bg or 0)
        .. "  statusbar_bg=" .. string.format("%06X", T2.statusbar_bg or 0)
        .. "  menubar_bg=" .. string.format("%06X", T2.menubar_bg or T2.bar_bg or 0)
        .. NL
    end

    local hx = function(c) return c and string.format("%06X", c) or "nil" end
    blob = blob .. NL .. "--- cache vs glass ---" .. NL
    if cap.disagree and #cap.disagree > 0 then
      blob = blob .. "THE SHADOW DISAGREES WITH THE SCREEN on "
        .. #cap.disagree .. " row(s)." .. NL
      for _, m in ipairs(cap.disagree) do
        blob = blob .. string.format(
          "  row %2d col %2d  glass=%s  shadow believes=%s", m.row, m.col,
          hx(m.glass), hx(m.shadow)) .. NL
        local pr = cap.pageBg and cap.pageBg[m.row]
        if pr then
          local parts = {}
          for _, r in ipairs(pr) do
            parts[#parts + 1] = string.format("%d-%d:%s", r.from, r.to, hx(r.c))
          end
          blob = blob .. "    off-screen page holds: "
            .. table.concat(parts, "  ") .. NL
        end
      end
    elseif cap.shadowBg then
      blob = blob .. "none — the shadow matches the glass everywhere." .. NL
    else
      blob = blob .. "(no shadow active on this seat)" .. NL
    end
    local st = cap.state
    if st then
      blob = blob .. NL .. "--- display machinery ---" .. NL
        .. "  shadow=" .. tostring(st.shadow)
        .. "  colour cache: fg=" .. hx(st.lastFg) .. " bg=" .. hx(st.lastBg) .. NL
        .. "  backbuffer=" .. tostring(st.backbuffer)
        .. "  broken=" .. tostring(st.backBroken)
        .. "  frameDepth=" .. tostring(st.frameDepth)
        .. "  pageStale=" .. tostring(st.pageStale) .. NL
        .. "  writerGen=" .. tostring(st.writerGen)
        .. "  mine=" .. tostring(st.myWriterGen)
        .. "  lastWriterIsMe=" .. tostring(st.lastWriterIsMe) .. NL
    end
    local fs = _G._TOS and _G._TOS.fs
    if not (fs and fs.writeFile) then o("No filesystem available to write the dump.", T.error); return end
    local ok, err = fs.writeFile(path, blob)
    if ok then
      o("Screen captured -> " .. path .. "  (" .. (cap.h or 0) .. " rows)", T.success or T.fg)
      o("Attach it to a bug report, or 'cat' it to read it back.", T.dim)
    else
      o("Could not write " .. path .. ": " .. tostring(err), T.error)
    end
  end

  C.crash = function(args, o)
    if not adminOnly(o) then return end
    local fs = _G._TOS and _G._TOS.fs
    if not (fs and fs.list) then o("No filesystem.", T.error); return end
    if args and args[1] then
      local p = args[1]:find("/") and rp(args[1]) or ("/var/crash/" .. args[1])
      local ok, data = pcall(fs.readFile, p)
      if not ok or not data then o("No such crash report: " .. p, T.error); return end
      for line in (tostring(data) .. "\n"):gmatch("(.-)\n") do o(line, T.fg) end
      return
    end
    local ok, entries = pcall(fs.list, "/var/crash")
    local names = {}
    if ok and type(entries) == "table" then
      for _, n in ipairs(entries) do
        n = tostring(n):gsub("/$", "")
        if n ~= "" and n ~= "NEW" then names[#names + 1] = n end
      end
    end
    if #names == 0 then
      o("No crash reports — clean so far.", T.dim)
      o("(TOS saves one here on a panic or an unrecoverable shell, so you", T.dim)
      o(" can read it after rebooting.)", T.dim)
      return
    end
    o("Crash reports in /var/crash:", T.title or T.highlight or T.fg)
    for _, n in ipairs(names) do o("  " .. n, T.fg) end
    o("Read one with:  crash <name>", T.dim)
  end

  C.history = function(args, o)
    for i, cmd in ipairs(S.cmdHistory) do
      o(string.format(" %3d  %s", i, cmd), T.dim)
    end
    if #S.cmdHistory == 0 then o("(no history)", T.dim) end
  end

  C.uptime = function(args, o)
    local up = K.uptime()
    local h2 = math.floor(up / 3600)
    local m2 = math.floor((up % 3600) / 60)
    local s2 = math.floor(up % 60)
    o(string.format("Uptime: %dh %dm %ds (%.1fs total)", h2, m2, s2, up), T.fg)
  end

  C.date = function(args, o)
    local cfg = K.getConfig and K.getConfig() or nil

    if args[1] == "tz" or args[1] == "timezone" or args[1] == "set" then
      local cur = (cfg and cfg.get and cfg.get("timezone")) or 0
      local n = tonumber(args[2])
      if not n then
        o("Timezone offset: " .. cur .. "h", T.fg)
        o("Usage: date tz <hours>   e.g. 'date tz -5'", T.dim)
        o("OpenComputers has no settable clock; this only shifts the", T.dim)
        o("DISPLAYED time relative to the world/host clock.", T.dim)
        return
      end
      if n < -23 or n > 23 then o("Offset must be between -23 and 23.", T.error); return end
      if not (cfg and cfg.set) then o("No writable config available.", T.error); return end
      cfg.set("timezone", n)
      if cfg.save then cfg.save() end
      o("Timezone offset set to " .. n .. "h. (was " .. cur .. "h)", T.highlight)
      return
    end
    local fmt = args[1] or "%Y-%m-%d %H:%M:%S"
    local offset = (cfg and cfg.get and cfg.get("timezone")) or 0
    local t = os.time() + (offset * 3600)
    local ok, out = pcall(os.date, fmt, t)
    if ok and out then o(tostring(out), T.fg) else o(tostring(out or "date error"), T.error) end
  end
  C.time = C.date

  C.keys = function(args, o)
    local okK, K2 = pcall(require, "shell.keys")
    if not okK or not K2 then o("Keybind module unavailable.", T.error); return end
    local sub = (args[1] or "list"):lower()

    local system = false
    for i = 2, #args do
      if args[i] == "--system" then system = true; table.remove(args, i); break end
    end
    local home = (S.who == "root") and "/root" or ("/home/" .. (S.who or ""))
    local path = system and "/etc/keys.cfg" or (home .. "/.keys.cfg")
    local okS, ser = pcall(require, "kernel.serialize")

    local function loadCfg()
      if not (okS and ser and S.F.exists(path)) then return {} end
      local d = S.F.readFile(path)
      if not d then return {} end
      local ok2, t = pcall(ser.decode, d, { maxBytes = 8192 })
      return (ok2 and type(t) == "table") and t or {}
    end
    local function saveCfg(t)
      if not (okS and ser) then return false end
      local ok2 = S.F.writeFile(path, ser.encode(t))
      if ok2 then K2.reload() end
      return ok2
    end

    if sub == "list" or sub == "ls" then
      o("TOS standard shortcuts:", T.title)
      for _, row in ipairs(K2.actions(S.who)) do
        o(string.format("  %-9s %-14s %s", row.action, row.keys, row.help),
          row.isDefault and T.fg or T.highlight)
      end
      o("", T.dim)
      o("Reserved by the kernel — these cannot be rebound:", T.dim)
      for _, r in ipairs(K2.reserved()) do
        o(string.format("  %-9s %s", r.key, r.help), T.dim)
      end
      o("", T.dim)
      o("Change one:  keys set quit F4       (add --system for everyone)", T.dim)
      o("Undo:        keys reset [action]", T.dim)

      o("Every first-party TOS program follows this table.", T.dim)

    elseif sub == "set" then
      local action, keyName = args[2], args[3]
      if not (action and keyName) then
        o("Usage: keys set <action> <key> [<key>...]", T.dim)
        o("  e.g. keys set quit F4      keys set find ^F", T.dim)
        o("Key names are written the way you say them: ^Q, F10, Ctrl+S, /", T.dim)
        return
      end
      if not K2.DEFAULTS[action] then
        o("No such action: " .. action .. "  (see 'keys list')", T.error); return
      end
      local names = {}
      for i = 3, #args do
        local nm = args[i]
        if not K2.parse(nm) then
          o("Not a key name: '" .. nm .. "'  (try ^Q, F10, Ctrl+S, /)", T.error); return
        end

        if K2.isReserved(nm) then
          o(nm .. " is reserved by the kernel and never reaches a program.", T.error)
          o("See 'keys list' for the reserved set.", T.dim); return
        end
        names[#names + 1] = nm
      end
      local cfg = loadCfg()
      cfg[action] = names
      if saveCfg(cfg) then
        o(action .. " is now " .. table.concat(names, " ")
          .. (system and "  (machine-wide)" or ""), T.highlight)
      else
        o("Save failed" .. (system and " (needs admin for /etc)." or "."), T.error)
      end

    elseif sub == "reset" then
      local action = args[2]
      local cfg = loadCfg()
      if action then
        if not K2.DEFAULTS[action] then
          o("No such action: " .. action, T.error); return
        end
        cfg[action] = nil
        if saveCfg(cfg) then o(action .. " is back to the default.", T.highlight)
        else o("Save failed.", T.error) end
      else
        if saveCfg({}) then o("All shortcuts back to the defaults.", T.highlight)
        else o("Save failed.", T.error) end
      end

    else
      o("keys — TOS's standard keyboard shortcuts", T.title)
      o("  keys list                     Show them", T.fg)
      o("  keys set <action> <key>...    Rebind one", T.fg)
      o("  keys reset [action]           Back to the default", T.fg)
      o("Add --system to change them for every user (/etc/keys.cfg, admin).", T.dim)
    end
  end

  C.menu = function(args, o)
    local sub = (args[1] or "list"):lower()

    local system = false
    for i = 2, #args do
      if args[i] == "--system" then system = true; table.remove(args, i); break end
    end
    local home = (S.who == "root") and "/root" or ("/home/" .. (S.who or ""))
    local path = system and "/etc/menu.cfg" or (home .. "/.menu.cfg")
    local okS, ser = pcall(require, "kernel.serialize")
    if not okS or not ser then o("serialize unavailable", T.error); return end
    local function loadList()
      if not S.F.exists(path) then return {} end
      local d = S.F.readFile(path)
      if not d then return {} end
      local ok, list = pcall(ser.decode, d, { maxBytes = 8192 })
      return (ok and type(list) == "table") and list or {}
    end
    local function saveList(list) return S.F.writeFile(path, ser.encode(list)) end
    local function rebuild()
      local okD, dm = pcall(require, "shell.panels.draw")
      if okD and dm and dm.buildMenuDefs then S.menuDefs = dm.buildMenuDefs(S) end
    end

    local function describe(e)
      if e.remove then return "remove " .. tostring(e.remove)
        .. (e.menu == true and " (whole menu)" or "") end
      if e.rename then return "rename " .. tostring(e.rename) .. " -> " .. tostring(e.to) end
      if e.move   then return "move " .. tostring(e.move) .. " -> " .. tostring(e.menu) end
      if e.menu and not e.cmd then return "new menu " .. tostring(e.menu) end
      return string.format("[%s] %s -> %s", e.menu or "Tools",
        e.add or e.label or "?", e.cmd or "?")
    end

    if sub == "list" or sub == "ls" then
      local list = loadList()
      if #list == 0 then
        o("No menu edits in " .. path .. ".", T.dim)
        o("Add one:  menu add <label> <command...> [in <Menu>]", T.dim)
        o("Machine-wide instead of just you:  menu add ... --system", T.dim)
        return
      end
      o("Menu edits (" .. path .. "):", T.title)
      for i, e in ipairs(list) do
        o(string.format("  %d. %s", i, describe(e)), T.fg)
      end

    elseif sub == "show" then
      local okD, dm = pcall(require, "shell.panels.draw")
      if not okD or not dm or not dm.buildMenuDefs then
        o("Menu system unavailable.", T.error); return
      end
      for _, m in ipairs(dm.buildMenuDefs(S)) do
        o(m.label, T.title)
        for _, it in ipairs(m.items) do
          if it.sep then o("    ---", T.dim)
          else
            o(string.format("    %-20s %s", it.label,
              (it.action or ""):match("^run:(.+)$") or (it.action or "")), T.fg)
          end
        end
      end
      o("Change it with: menu add|remove|rename|move  (add --system for everyone)", T.dim)

    elseif sub == "rename" or sub == "move" then

      local a, b = args[2], args[3]
      if not (a and b) then
        o("Usage: menu " .. sub .. " <name> <" .. (sub == "rename" and "new name" or "Menu") .. ">", T.dim)
        return
      end
      local list = loadList()
      list[#list + 1] = (sub == "rename") and { rename = a, to = b } or { move = a, menu = b }
      if saveList(list) then rebuild(); o("Saved. " .. describe(list[#list]), T.highlight)
      else o("Save failed" .. (system and " (needs admin for /etc)." or "."), T.error) end

    elseif sub == "hide" then

      local target = args[2]
      if not target then
        o("Usage: menu hide <item or Menu name>", T.dim)
        o("Hides a built-in entry. 'menu reset' brings everything back.", T.dim)
        return
      end
      local list = loadList()
      list[#list + 1] = { remove = target, menu = (args[3] == "menu") or nil }
      if saveList(list) then rebuild(); o("Hidden: " .. target, T.highlight)
      else o("Save failed" .. (system and " (needs admin for /etc)." or "."), T.error) end

    elseif sub == "reset" then
      if saveList({}) then
        rebuild()
        o("Menu reset to the built-in bar (" .. path .. " cleared).", T.highlight)
      else o("Reset failed" .. (system and " (needs admin for /etc)." or "."), T.error) end

    elseif sub == "add" then
      local label = args[2]
      if not label or not args[3] then
        o("Usage: menu add <label> <command...> [in <Menu>]", T.dim)
        o("  e.g. menu add Tetris tetris   |   menu add Disk df in System", T.dim)
        return
      end
      local cmd = table.concat(args, " ", 3)
      local targetMenu = cmd:match("%s+in%s+(%S+)%s*$")
      if targetMenu then cmd = cmd:gsub("%s+in%s+%S+%s*$", "") end
      if #label > 24 then o("Label too long (max 24).", T.error); return end
      if #cmd == 0 or #cmd > 200 then o("Command empty or too long.", T.error); return end
      local list = loadList()
      list[#list + 1] = { label = label, cmd = cmd, menu = targetMenu or "Tools" }
      if saveList(list) then
        rebuild()
        o(string.format("Added '%s' -> %s  (menu: %s)", label, cmd, targetMenu or "Tools"),
          T.highlight)
      else
        o("Save failed (is your home writable?).", T.error)
      end
    elseif sub == "remove" or sub == "rm" or sub == "del" then
      local n = tonumber(args[2])
      local list = loadList()
      if not n or not list[n] then
        o("Usage: menu remove <#>   (see 'menu list')", T.error); return
      end
      local rem = table.remove(list, n)
      if saveList(list) then
        rebuild()
        o("Removed '" .. (rem.label or "?") .. "'.", T.highlight)
      else o("Save failed.", T.error) end
    else
      o("menu — adjust the menu bar", T.title)
      o("  menu show                     The bar as it is right now", T.fg)
      o("  menu list                     Your edits to it", T.fg)
      o("  menu add <label> <cmd...> [in <Menu>]", T.fg)
      o("  menu hide <item|Menu> [menu]  Hide a built-in entry", T.fg)
      o("  menu rename <name> <new>      Rename a menu or an item", T.fg)
      o("  menu move <item> <Menu>       Move an item to another menu", T.fg)
      o("  menu remove <#>               Undo one of your edits", T.fg)
      o("  menu reset                    Back to the built-in bar", T.fg)
      o("Add --system to any of these to change the bar for EVERY user", T.dim)
      o("(/etc/menu.cfg, admin-only) instead of just yourself.", T.dim)
    end
  end

  C.tree = function(args, o)
    local start = rp(args[1] or S.cwd)
    local maxDepth = tonumber(args[2]) or 3
    local MAX_ENTRIES = 400
    local count, truncated = 0, false
    local function walk(path, prefix, depth)
      if truncated then return end
      if depth > maxDepth then return end
      local entries = F.list(path) or {}
      table.sort(entries, function(a, b)
        local ad = F.isDirectory(path .. "/" .. (a:gsub("/$", "")))
        local bd = F.isDirectory(path .. "/" .. (b:gsub("/$", "")))
        if ad ~= bd then return ad end
        return a < b
      end)
      for i, name in ipairs(entries) do
        if count >= MAX_ENTRIES then truncated = true; return end
        local clean = name:gsub("/$", "")
        local sub = path == "/" and ("/" .. clean) or (path .. "/" .. clean)
        local isDir = F.isDirectory(sub)
        local last = (i == #entries)
        local connector = last and "`-- " or "|-- "
        local color = isDir and T.dir or T.fg
        o(prefix .. connector .. clean .. (isDir and "/" or ""), color)
        count = count + 1
        if isDir then
          walk(sub, prefix .. (last and "    " or "|   "), depth + 1)
        end
      end
    end
    o(start, T.title)
    walk(start, "", 1)
    if truncated then
      o(string.format("(truncated at %d entries; raise the limit or narrow the path)", MAX_ENTRIES), T.dim)
    end
  end
  C.whoami = function(args, o)
    if U then
      local s = U.getSession(st)
      o(s and s.user or "root", T.fg)
    else o(S.who, T.fg) end
  end
  C.passwd = function(args, o)
    if not U then o("No user system", T.error); return end
    local old = promptInput("Current password: ", 64, true)
    if not old then return end
    local new = promptInput("New password: ",     64, true)
    if not new then return end

    local confirm = promptInput("Confirm new password: ", 64, true)
    if confirm ~= new then
      S.lastOut = { "Passwords do not match — unchanged.", T.error }
      return
    end
    if new == "" then
      S.lastOut = { "Password cannot be empty.", T.error }
      return
    end
    local s = U.getSession(st)
    local w2 = s and s.user or "root"
    local ok2, err2 = U.changePassword(w2, w2, old, new)
    if ok2 then S.lastOut = { "Password changed.", T.highlight }
    else        S.lastOut = { tostring(err2), T.error } end
  end

  --! `o` is a PARAMETER, not an upvalue. Every command body receives its own
  --! `o` from the executor (C.sudo = function(args, o)), so this helper had
  --! no `o` in scope and the `o(...)` below read a nil GLOBAL — meaning the
  --! one path that reports a failure ("sudo: <err>") crashed with "attempt to
  --! call a nil value" instead, turning any error thrown by an elevated
  --! command into a second, more confusing error. (test_sudo_report.lua)
  local function sudoRunElevated(elevated, fn, o)
    local origSt = S.st
    local token = U.registerSession and U.registerSession(elevated) or nil
    local okP, procMod = pcall(require, "kernel.process")
    local p = okP and procMod.current and procMod.current()
    local origPrincipal = p and p.principal
    if token then S.st = token end
    if p then p.principal = elevated end
    local ok, err = pcall(fn)

    S.st = origSt
    if p then p.principal = origPrincipal end
    if token and U.logout then pcall(U.logout, token) end
    if not ok then o("sudo: " .. tostring(err), T.error) end
  end

  local function sudoDrop()
    if not S._sudo then return false end
    S.st = S._sudo.origSt
    local okP, procMod = pcall(require, "kernel.process")
    local p = okP and procMod.current and procMod.current()
    if p then p.principal = S._sudo.origPrincipal end
    if S._sudo.token and U.logout then pcall(U.logout, S._sudo.token) end
    S._sudo = nil
    return true
  end
  S.sudoDrop = sudoDrop

  C.sudo = function(args, o)
    if not U then o("No user system", T.error); return end
    local sess = helpers.sessionOf(S)
    local sub = args[1]

    if sub == "setup" then
      if not rootOnly(o) then return end
      local cap = 2
      if args[2] == "root" then cap = 3
      elseif args[2] and args[2] ~= "admin" then
        o("Usage: sudo setup [admin|root]", T.dim); return end
      local pw = promptInput("New elevation password: ", 64, true)
      if not pw or pw == "" then o("Aborted.", T.dim); return end
      if promptInput("Confirm: ", 64, true) ~= pw then
        o("Passwords do not match.", T.error); return end
      local ok2, err2 = U.setElevation(sess, pw, cap)
      if ok2 then o("Elevation configured (cap: " .. helpers.tierName(cap) .. ").", T.highlight)
      else o(tostring(err2), T.error) end
      return
    elseif sub == "off" then
      if not rootOnly(o) then return end
      local ok2, err2 = U.clearElevation and U.clearElevation(sess)
      if ok2 then o("Elevation disabled.", T.highlight)
      else o(tostring(err2 or "unavailable"), T.error) end
      return
    elseif sub == "-k" then
      o(sudoDrop() and "Elevated session dropped." or "No active elevation.", T.dim)
      return
    end

    if not sub then
      o("Usage: sudo <command> | sudo -s | sudo -k | sudo setup [admin|root] | sudo off", T.dim)
      return
    end

    if helpers.liveTier(S) < 1 then o("sudo: guests cannot elevate.", T.error); return end
    local info = U.elevationInfo and U.elevationInfo() or { configured = false }
    if not info.configured then
      o("sudo: elevation is not configured. Root: sudo setup [admin|root]", T.warning); return
    end

    local pw = promptInput("[sudo] elevation password: ", 64, true)
    if pw == nil then o("Aborted.", T.dim); return end
    local elevated, err = U.elevate(sess, pw)
    if not elevated then o("sudo: " .. tostring(err or "elevation failed"), T.error); return end

    if sub == "-s" then

      sudoDrop()
      local token = U.registerSession and U.registerSession(elevated) or nil
      local okP, procMod = pcall(require, "kernel.process")
      local p = okP and procMod.current and procMod.current()
      S._sudo = { origSt = S.st, origPrincipal = p and p.principal, token = token }
      if token then S.st = token end
      if p then p.principal = elevated end
      o("Elevated to " .. helpers.tierName(elevated.tier)
        .. ". 'sudo -k' or 'logout' drops it.", T.highlight)
      return
    end

    local cmdline = table.concat(args, " ")
    sudoRunElevated(elevated, function()
      if not S.execOne then o("sudo: executor unavailable", T.error); return end
      local buf = S.execOne(cmdline)
      if type(buf) == "table" then
        for _, line in ipairs(buf) do
          if type(line) == "table" then o(line[1], line[2] or T.fg)
          else o(tostring(line), T.fg) end
        end
      end
    end, o)
  end

  C.logout   = function(args, o) helpers.logout(S) end

  C.cli = function(args, o)
    if S.isCLI then
      o("You are already at the command line. Type 'tui' for the full interface.", T.dim)
      return
    end
    S._exitTo = "cli"
  end
  C.tui = function(args, o)
    if S.isCLI then

      o("Returning to the full interface…", T.dim)
      S._exitTo = "tui"
      return
    end
    o("You are already in the full interface. Type 'cli' for the command line.", T.dim)
  end

  C.reboot   = function(args, o)
    local ok, reason = helpers.canPowerOff(S)
    if not ok then o(reason, T.error); return end
    K.reboot()
  end
  C.shutdown = function(args, o)
    local ok, reason = helpers.canPowerOff(S)
    if not ok then o(reason, T.error); return end
    K.shutdown()
  end
  C.env = function(args, o)
    local ok2, envMod = pcall(require, "kernel.env")
    if not ok2 then o("Env module unavailable", T.error); return end
    local P2 = K.getProc()
    local cur = P2 and P2.current() or nil
    if args[1] then

      local k, v = args[1]:match("^([%w_]+)=(.*)$")
      if k then
        envMod.write(cur, k, v)
        o(k .. "=" .. v, T.highlight)
      else

        local val = envMod.read(cur, args[1])
        o(args[1] .. "=" .. tostring(val or ""), T.fg)
      end
    else
      local all = envMod.list(cur)
      for k, v in pairs(all) do o("  " .. k .. "=" .. tostring(v), T.fg) end
    end
  end
  C.export = C.env
  C.set = C.env

  C["tape-menu"] = function(args, o)
    local okL, L = pcall(require, "shell.launcher")
    if not okL or not L then o("Menu engine unavailable (low RAM?)", T.error); return end
    if not D or not D.getSize then o("tape-menu needs a screen.", T.error); return end

    local CTable = nil
    local function runLine(line)
      local out = {}
      local parts = {}
      for w in line:gmatch("%S+") do parts[#parts + 1] = w end
      if #parts == 0 then return out end
      local name = parts[1]
      local cargs = {}
      for i = 2, #parts do cargs[#cargs + 1] = parts[i] end
      if not CTable then
        CTable = require("shell.panels.commands").build(S, deps)
      end
      local fn = CTable[name]
      if not fn then
        local okP, pkgMod = pcall(require, "kernel.pkg")
        if okP and pkgMod and pkgMod.getCommand then fn = pkgMod.getCommand(name) end
      end
      if not fn then out[#out + 1] = { "Unknown command: " .. name, T.error }; return out end
      local sink = function(text, color) out[#out + 1] = { tostring(text), color or T.fg } end
      local okR, err = pcall(fn, cargs, sink)
      if not okR then out[#out + 1] = { "Error: " .. tostring(err), T.error } end
      return out
    end

    local addr = component.list and component.list("tape_drive")()
    if not addr then o("No tape drive found.", T.error); return end
    local drive = component.proxy(addr)
    local okR, ready = pcall(function() return drive.isReady() end)
    if not okR or not ready then o("No tape inserted.", T.warning); return end
    local size = (drive.getSize and drive.getSize()) or 0
    if size <= 0 then o("Tape is empty.", T.warning); return end
    local pass = promptInput and promptInput("Tape menu passphrase: ", 64, true) or nil
    if not pass or pass == "" then o("Cancelled.", T.dim); return end
    local okV, vault = pcall(require, "kernel.vault")
    if not okV or not vault then o("vault unavailable", T.error); return end

    local menu, mErr = L.readTapeMenuFromDrive(drive, pass, vault)
    if not menu then o(tostring(mErr), T.error); return end
    L.run({ display = D, profile = menu, runLine = runLine, title = "Tape toolbox" })
    if deps.drawAll then pcall(deps.drawAll) end
  end

  C.clip = function(args, o)
    local okCB, clip = pcall(require, "kernel.clipboard")
    if not okCB or not clip then
      o("Clipboard unavailable: " .. tostring(clip), T.error); return
    end
    local seat = S.displayIdx
    local sub = args[1]

    if not sub then
      o("Clipboard: " .. clip.describe(seat), T.title)
      local lines = clip.get(seat)
      if lines and not clip.isEmpty(seat) then

        local shown = math.min(#lines, 10)
        for i = 1, shown do o("  " .. lines[i], T.fg) end
        if #lines > shown then
          o("  ... " .. (#lines - shown) .. " more line(s)", T.dim)
        end
      end
      o("Usage: clip [set <text> | clear]   Copy: "
        .. (function()
             local okK, keys = pcall(require, "shell.keys")
             return (okK and keys) and keys.label("copy", S.who) or "Ctrl+Insert"
           end)(), T.dim)
      return
    end

    if sub == "clear" then
      clip.clear(seat)
      o("Clipboard cleared.", T.highlight)
      return
    end

    if sub == "set" then
      local text = table.concat(args, " ", 2)
      if text == "" then o("Usage: clip set <text>", T.warning); return end
      local ok, truncated = clip.set(text, seat)
      if not ok then o("Could not set clipboard: " .. tostring(truncated), T.error); return end
      if truncated then
        o("Clipboard set, TRUNCATED at the cap: " .. clip.describe(seat), T.warning)
      else
        o("Clipboard: " .. clip.describe(seat), T.highlight)
      end
      return
    end

    o("Usage: clip [set <text> | clear]", T.warning)
  end

  C.desktop = function(args, o)
    local okD, desktopMod = pcall(require, "shell.panels.desktop")
    if not okD then o("Desktop unavailable: " .. tostring(desktopMod), T.error); return end
    desktopMod.open(S)
  end

  C.settings = function(args, o)
    local okS2, settingsMod = pcall(require, "shell.panels.settingsapp")
    if not okS2 then o("Settings unavailable: " .. tostring(settingsMod), T.error); return end
    settingsMod.open(S)
  end

  C.lang = function(args, o)
    local okI, i18nMod = pcall(require, "kernel.i18n")
    if not okI or not i18nMod then o("i18n unavailable: " .. tostring(i18nMod), T.error); return end
    local sub = args[1]

    if not sub then
      o("Language: " .. i18nMod.language() .. "  (" .. i18nMod.languageName() .. ")", T.title)
      o("Installed catalogs:", T.fg)
      for _, l in ipairs(i18nMod.available()) do
        local mark = (l.code == i18nMod.language()) and " * " or "   "
        o(mark .. string.format("%-8s %s", l.code, l.name), T.fg)
      end
      o("Usage: lang <code> | lang system <code> | lang dump [path]", T.dim)
      o("Catalogs are DATA files at /usr/lang/<code>.lang — see 'man lang'.", T.dim)
      return
    end

    if sub == "system" then
      if not adminOnly(o) then return end
      local code = args[2]
      if not code then o("Usage: lang system <code|en>", T.dim); return end
      local ok, err = i18nMod.setLanguage(code)
      if not ok then o("Cannot set: " .. tostring(err), T.error); return end
      if SC and SC.set then SC.set("language", code); if SC.save then SC.save() end end
      o("System language: " .. i18nMod.language(), T.highlight)
      return
    end

    if sub == "dump" then
      local path = rp(args[2] or "/tmp/lang-template.lang")
      local keys = i18nMod.keysSeen()
      if #keys == 0 then
        o("No keys seen yet — visit a few screens first (log out/in, open the Desktop).", T.warning)
        return
      end
      local lines = {
        "-- TOS language catalog template (every t() key seen this session).",
        "-- Translate the values, set meta.code/name, save as /usr/lang/<code>.lang,",
        "-- then run `lang <code>`. Untranslated keys keep their English default.",
        "return {",
        '  meta = { code = "xx", name = "Language name" },',
        "  strings = {",
      }
      for _, e in ipairs(keys) do
        lines[#lines + 1] = string.format("    [%q] = %q,", e.key, e.default)
      end
      lines[#lines + 1] = "  },"
      lines[#lines + 1] = "}"
      if not canWrite(path) then o("Cannot write: " .. path, T.error); return end
      if F.writeFile(path, table.concat(lines, "\n") .. "\n") then
        o("Template with " .. #keys .. " key(s) -> " .. path, T.highlight)
        refreshBrowser()
      else
        o("Write failed: " .. path, T.error)
      end
      return
    end

    local ok, err = i18nMod.setLanguage(sub)
    if not ok then
      o("Cannot set '" .. tostring(sub) .. "': " .. tostring(err), T.error)
      o("Run 'lang' to list installed catalogs.", T.dim)
      return
    end
    local sess = helpers.sessionOf(S)
    local okP, profileMod = pcall(require, "kernel.profile")
    if okP and profileMod and profileMod.load and profileMod.save then
      local p = profileMod.load(sess)
      p.lang = (i18nMod.language() ~= "en") and i18nMod.language() or nil
      local okSave, sErr = profileMod.save(p, sess)
      if okSave then
        o("Language: " .. i18nMod.language() .. "  (saved to your profile)", T.highlight)
      else
        o("Language set for this session (profile save failed: " .. tostring(sErr) .. ")", T.warning)
      end
    else
      o("Language: " .. i18nMod.language() .. "  (this session)", T.highlight)
    end
  end

end
