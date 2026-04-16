-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Shell - Command Table                              ║
-- ║  Extracted from panels/init.lua (lines 1027-2816)       ║
-- ║  All shell commands live here; loaded via M.build(S,deps)║
-- ╚══════════════════════════════════════════════════════════╝

local computer   = require("computer")
local component  = require("component")
local helpers    = require("shell.panels.helpers")

local M = {}

---------------------------------------------------------------------------
-- M.build(S, deps) -> C
--   S    = shared state table (K, E, P, F, D, U, SC, NM, st, W, H, T,
--          tier, cwd, who, userTier, browser, lastOut, cmdHistory, …)
--   deps = UI helpers that live in init.lua:
--          { rp, openViewTab, openEditTab, refreshBrowser,
--            canRead, canWrite, canAccess, rootOnly, adminOnly,
--            makeProgramEnv, promptInput,
--            drawAll, drawOutRow, loadFiles, createTab, tabs,
--            pullSignal }
--   Returns the command table C.
---------------------------------------------------------------------------
function M.build(S, deps)
  -- Immutable / stable references (safe to alias as locals)
  local K, E, P, F, D, U = S.K, S.E, S.P, S.F, S.D, S.U
  local SC, NM, st        = S.SC, S.NM, S.st
  local T                  = S.T
  local tier               = S.tier
  local W, H               = S.W, S.H

  -- Dependency short-hands
  local rp              = deps.rp
  local openViewTab     = deps.openViewTab
  local openEditTab     = deps.openEditTab
  local refreshBrowser  = deps.refreshBrowser
  local canRead         = deps.canRead
  local canWrite        = deps.canWrite
  local canAccess       = deps.canAccess
  local rootOnly        = deps.rootOnly
  local adminOnly       = deps.adminOnly
  local makeProgramEnv  = deps.makeProgramEnv
  local fmtSz           = helpers.fmtSz
  local expandBuf       = function(buf) return helpers.expandBuf(S, buf) end
  local promptInput     = deps.promptInput

  -- Mutable state lives on S and is accessed as S.cwd, S.who,
  -- S.lastOut, S.browser, S.userTier, S.cmdHistory, etc.

  local C = {}

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
      o("  Ctrl+C = copy line  Ctrl+X = cut line  Ctrl+V = paste", T.dim)
      o("  Use F2 to switch tabs, F4 to close.", T.dim)
    elseif topic == "run" then
      o("run <file> [args...]", T.title)
      o("  Execute a Lua file in the current environment.", T.fg)
      o("  Args are passed as a table in the second argument.", T.fg)
    elseif topic == "tape" then
      o("tape [subcommand]", T.title)
      o("  Data storage on Computronics tapes (requires module).", T.fg)
      o("  If the tape-storage module is not installed, shows", T.fg)
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
    elseif topic == "mod" or topic == "module" or topic == "modules" then
      o("mod [subcommand]", T.title)
      o("  Manage installable modules.", T.fg)
      o("", T.fg)
      o("  Subcommands:", T.dim)
      o("    list                List installed modules", T.dim)
      o("    info <name>         Show module details", T.dim)
      o("    enable <name>       Enable a module  (admin)", T.dim)
      o("    disable <name>      Disable a module (admin)", T.dim)
      o("    uninstall <name>    Remove a module  (admin)", T.dim)
      o("    commands            List commands from enabled modules", T.dim)
      o("    scan                Detect unregistered module dirs", T.dim)
      o("", T.fg)
      o("  Install from disk:  disk install <mount>", T.dim)
      o("  Export to disk:     disk export <name> <mount>", T.dim)
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
    else
      -- Role-aware help: only show commands the user can access
      -- TIER: GUEST=0, USER=1, ADMIN=2, ROOT=3
      o("=== TOS Command Reference ===  (help <cmd> for detail)", T.title)
      o("", T.fg)
      o(" Navigation & Files", T.highlight)
      o("  cd [dir]              Change directory  (~ = home, .. = parent)", T.fg)
      o("  ls [path]             List directory  (dir = alias)", T.fg)
      o("  cat <file>            View file contents  (type = alias)", T.fg)
      o("  more <file>           Open file in view tab", T.fg)
      if S.userTier >= 1 then -- USER+
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
      o("  F1  Help      F2  Next tab       F3  View file", T.fg)
      o("  F4  Close tab F5  Copy/Paste     F6  Move", T.fg)
      o("  F7  Mkdir     F8  Delete         F9  Menu bar", T.fg)
      o("  F10 Quit      ^Q  Cancel/Close   ^F  Find", T.fg)
      o("  Enter on file = context menu  |  ^T  Task switcher", T.dim)
      if S.userTier >= 1 then -- USER+ can mount
      o("", T.fg)
      o(" Devices", T.highlight)
      o("  lsdev                 List all connected peripherals", T.fg)
      o("  mount                 List mounted filesystems", T.fg)
      if S.userTier >= 2 then -- ADMIN+ can mount/umount
      o("  mount <dev> <path>    Mount a device at path", T.fg)
      o("  umount <path>         Unmount a device", T.fg)
      end
      end
      o("", T.fg)
      o(" System", T.highlight)
      o("  mem    Show memory usage", T.fg)
      o("  hw     List hardware components", T.fg)
      o("  ps     Show running processes", T.fg)
      o("  ver    TOS version info", T.fg)
      o("  about  Changelog and credits", T.fg)
      o("  uptime Show system uptime", T.fg)
      if S.userTier >= 2 then -- ADMIN+
      o("  log [N]       Show last N system log entries", T.fg)
      o("  verify Check all system files for integrity", T.fg)
      end
      if S.userTier >= 1 then -- USER+
      o("  run <file>    Execute a Lua file", T.fg)
      o("  bg <file>     Run a Lua file in a background tab", T.fg)
      o("  edit <file>   Open in editor tab  (^S save, ^Q close)", T.fg)
      end
      if S.userTier >= 3 then -- ROOT
      o("  lua           Interactive Lua REPL  (exit to quit)", T.fg)
      o("  flash <file>  Flash EEPROM with Lua file  (!CAUTION)", T.fg)
      end
      o("  programs      List executables in /bin and /usr/bin", T.fg)
      o("  history       Show command history", T.fg)
      o("  tutorial      Re-run the first-boot tutorial", T.fg)
      o("", T.fg)
      o(" Session & Power", T.highlight)
      o("  whoami  passwd  logout", T.fg)
      if S.userTier >= 2 then -- ADMIN+
      o("  users                            List user accounts", T.fg)
      o("  reboot  shutdown", T.fg)
      end
      if S.userTier >= 3 then -- ROOT
      o("", T.fg)
      o(" Administration (root)", T.highlight)
      o("  useradd <user>                   Create a new user", T.fg)
      o("  userdel <user>                   Delete a user", T.fg)
      o("  usermod <user> lock|unlock|admin|user  Modify user", T.fg)
      o("  deploy <mount>                   Copy TOS to another disk", T.fg)
      end
      if S.userTier >= 2 then -- ADMIN+
      o("", T.fg)
      o(" Environment & Services", T.highlight)
      o("  env [KEY=VAL]   Show/set environment variables", T.fg)
      o("  service [start|stop <n>]  Manage startup services", T.fg)
      o("  cron [list|add|rm]        Scheduled tasks", T.fg)
      end
      o("", T.fg)
      o(" Peripherals", T.highlight)
      o("  redstone [set|pulse] Control redstone I/O  (rs = alias)", T.fg)
      o("  robot <cmd>          Robot/drone movement & interaction", T.fg)
      o("  inventory [side]     Inspect inventories  (inv = alias)", T.fg)
      o("  tape [subcmd]        Tape drive data storage (module)", T.fg)
      if S.userTier >= 2 then -- ADMIN+
      o("  component <type> [method] [args]  Call any component", T.fg)
      end
      if NM then
      o("", T.fg)
      o(" Network", T.highlight)
      o("  net  ping  hostname", T.fg)
      if S.userTier >= 1 then -- USER+
      o("  chat               Open chat with trusted peers", T.fg)
      end
      if S.userTier >= 2 then -- ADMIN+
      o("  device  config  battery  audio", T.fg)
      o("  rsh <addr> <cmd>   Run command on remote peer", T.fg)
      o("  scp <addr>:<path> <local>  Transfer file from peer", T.fg)
      o("  screen [list|next|N]  Manage multiple displays", T.fg)
      end
      end
      o("", T.fg)
      o(" Modules & Disks", T.highlight)
      o("  mod [list]         List installed modules", T.fg)
      o("  mod info <name>    Show module details", T.fg)
      if S.userTier >= 2 then -- ADMIN+
      o("  mod enable|disable <name>  Toggle module", T.fg)
      o("  mod uninstall <name>       Remove module", T.fg)
      end
      o("  mod commands       List commands from modules", T.fg)
      o("  disk [list]        List removable disks", T.fg)
      o("  disk info <mount>  Show disk contents", T.fg)
      if S.userTier >= 2 then -- ADMIN+
      o("  disk install <mount>          Install module from disk", T.fg)
      o("  disk export <name> <mount>    Write module to disk", T.fg)
      end
      o("  disk eject <mount> Unmount a disk", T.fg)
      if S.userTier >= 2 then -- ADMIN+
      o("", T.fg)
      o(" Compatibility", T.highlight)
      o("  compat             Show OpenOS compatibility status", T.fg)
      end
      o("", T.fg)
      o(" Pipes & Redirects", T.highlight)
      o("  cmd1 | cmd2        Pipe output of cmd1 into cmd2", T.fg)
      o("  cmd > file         Redirect output to file", T.fg)
      o("  cmd >> file        Append output to file", T.fg)
    end
  end

  C.ver = function(args, o)
    o("TOS v" .. (_G._TOS and _G._TOS.version or "?") ..
      " [" .. (_G._TOS and _G._TOS.codename or "?") .. "]", T.title)
    o("GPU T" .. tier .. " | " ..
      math.floor(computer.totalMemory()/1024) .. "K RAM", T.dim)
    o("Type 'about' for changelog.", T.dim)
  end

  C.about = function(args, o)
    o("TOS - Terminal Operating System", T.title)
    o("By Discover Interactive", T.highlight)
    o("License: GNU GPL v3.0", T.dim)
    o("", T.fg)
    o("v0.3.0 [Bastion] - Security & Stability", T.title)
    o("  - Sandbox: run/bg/cron/modules use safe envs", T.fg)
    o("  - Lua REPL restricted to root (no escalation)", T.fg)
    o("  - Safe deserializer (no load(), pure parser)", T.fg)
    o("  - safeRequire blocks kernel.* from user code", T.fg)
    o("  - os.sleep yields to cooperative scheduler", T.fg)
    o("  - Session idle timeout (1h auto-expire)", T.fg)
    o("  - Path traversal fixes (securefs, transfers)", T.fg)
    o("  - Signal queue overflow protection", T.fg)
    o("  - Network pcall guards + trust rate limiting", T.fg)
    o("  - event.ignore properly removes listeners", T.fg)
    o("  - term.write scroll support + GPU buffering", T.fg)
    o("  - fs.copy() + securefs.copy()", T.fg)
    o("  - fs.rename() normalize + mount guard", T.fg)
    o("  - Background task output capped (500 lines)", T.fg)
    o("  - Process GC + HAL pcall improvements", T.fg)
    o("  - OpenOS compat: isAvailable, component.<type>", T.fg)
    o("  - Tape storage module (Computronics)", T.fg)
    o("", T.fg)
    o("v0.2.0 [Genesis] - Initial Release", T.title)
    o("  - Tabbed file browser with built-in editor", T.fg)
    o("  - Role-based user system (Root/Admin/User)", T.fg)
    o("  - Encrypted user data + secure fs layer", T.fg)
    o("  - Kernel: process manager, cron, events", T.fg)
    o("  - Networking: zero-trust peer system", T.fg)
    o("  - Module system with install/remove", T.fg)
    o("  - OpenOS compatibility layer", T.fg)
    o("  - Tiered GPU support (T1/T2/T3)", T.fg)
  end

  C.echo = function(args, o)
    o(table.concat(args, " "), T.fg)
  end

  C.tutorial = function(args, o)
    local ok2, tut = pcall(require, "shell.tutorial")
    if not ok2 then o("Tutorial module unavailable", T.error); return end
    -- Force re-show by deleting marker if --reset flag
    if args[1] == "--reset" and F.exists("/etc/.tutorial_done") then
      F.remove("/etc/.tutorial_done")
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

  C.rm = function(args, o)
    if not args[1] then o("Usage: rm <path>", T.dim); return end
    local p = rp(args[1])
    if p == "/" then o("Cannot remove root", T.error); return end
    if not canWrite(p, o) then return end
    if F.remove(p) then
      refreshBrowser()
      o("Removed: " .. args[1], T.highlight)
    else o("Failed", T.error) end
  end

  C.cp = function(args, o)
    if not args[2] then o("Usage: cp <src> <dst>", T.dim); return end
    local src, dst = rp(args[1]), rp(args[2])
    local ok2, err2 = F.copy(src, dst)
    if ok2 then
      refreshBrowser()
      o("Copied: " .. args[2], T.highlight)
    else o(err2 or "Failed", T.error) end
  end

  C.mv = function(args, o)
    if not args[2] then o("Usage: mv <src> <dst>", T.dim); return end
    local src, dst = rp(args[1]), rp(args[2])
    if not canWrite(src, o) then return end
    if not canWrite(dst, o) then return end
    if F.rename(src, dst) then
      refreshBrowser()
      o("Moved: " .. args[2], T.highlight)
    else o("Failed", T.error) end
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
    o("Searching " .. root .. " ...", T.dim)
    local results = {}
    local function scan(dir)
      local ok2, list = pcall(F.list, dir)
      if not ok2 or not list then return end
      local fitems = {}
      if type(list) == "table" then fitems = list
      elseif type(list) == "function" then for n in list do fitems[#fitems+1] = n end end
      for _, n in ipairs(fitems) do
        local full = F.join(dir, n:gsub("/$",""))
        local isDir = n:sub(-1) == "/"
        if not pattern or full:match(pattern) or n:match(pattern) then
          results[#results+1] = { full .. (isDir and "/" or ""), isDir and (T.dir or T.highlight) or T.fg }
        end
        if isDir and not full:match("^/tos") then scan(full) end
      end
    end
    scan(root)
    if #results == 0 then o("No matches found", T.dim)
    else for _, r in ipairs(results) do o(r[1], r[2]) end end
    o(#results .. " result(s)", T.dim)
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

  C.df = function(args, o)
    o(string.format(" %-20s %8s %8s %8s", "Mount", "Total", "Used", "Free"), T.title)
    o(string.rep("-", 46), T.dim)
    local mounts = F.mounts and F.mounts() or {}
    if #mounts == 0 then
      o("(mount info unavailable)", T.dim)
    else
      for _, m in ipairs(mounts) do
        local total = m.total or 0
        local used  = m.used  or 0
        local free  = total - used
        o(string.format(" %-20s %8s %8s %8s",
          (m.mountPoint or "?"):sub(1,20), fmtSz(total), fmtSz(used), fmtSz(free)), T.fg)
      end
    end
  end

  C.mem = function(args, o)
    local fr, tot = computer.freeMemory(), computer.totalMemory()
    local pct = math.floor(fr / tot * 100)
    local barW = math.min(24, W - 32)
    local fill = math.floor(pct / 100 * barW)
    local bar  = string.rep("#", fill) .. string.rep(".", barW - fill)
    o(string.format("RAM: %dK / %dK (%d%% free)",
      math.floor(fr/1024), math.floor(tot/1024), pct), T.fg)
    local bc = pct > 25 and T.highlight or pct > 10 and T.warning or T.error
    o(" [" .. bar .. "]", bc)
  end

  C.hw = function(args, o)
    local info = K.getHAL().systemInfo()
    o(string.format("CPU T%d | GPU T%d | RAM T%d",
      info.cpuTier, info.gpuTier, info.memTier), T.title)
    o(string.format("Components: %d | Net: %s | Tunnel: %s",
      info.components,
      info.canNetwork and "Yes" or "No",
      info.hasTunnel   and "Yes" or "No"), T.dim)
  end

  C.ps = function(args, o)
    local fgPID = P.getForeground(S.displayIdx)
    o(string.format(" %-4s %-16s %-8s %-3s %s", "PID", "Name", "State", "DSP", "CPU"), T.title)
    o(string.rep("-", 46), T.border)
    for _, proc in ipairs(P.list()) do
      local fg2 = T.fg
      local state = proc.state
      if proc.tsr then state = "TSR" end
      if proc.pid == fgPID then
        fg2 = T.highlight
        state = state .. " *"
      elseif proc.tsr then
        fg2 = T.dim
      end
      o(string.format(" %-4d %-16s %-8s %-3s %.1fs",
        proc.pid, proc.name:sub(1,16), state,
        tostring(proc.display or "-"), proc.cpuTime or 0), fg2)
    end
    o("", T.dim)
    o(" * = foreground  |  bg tasks appear as tabs", T.dim)
  end

  C.kill = function(args, o)
    if not args[1] then o("Usage: kill <pid>", T.dim); return end
    local pid = tonumber(args[1])
    if pid then
      local ok2, err = P.kill(pid)
      if ok2 then o("Killed PID " .. pid, T.highlight) else o(tostring(err), T.error) end
    else o("Invalid PID", T.error) end
  end

  C.fg = function(args, o)
    if not args[1] then o("Usage: fg <pid>", T.dim); return end
    local pid = tonumber(args[1])
    if not pid or not P.get(pid) then o("No such process", T.error); return end
    P.setForeground(pid, S.displayIdx)
    o("Foreground: PID " .. pid, T.highlight)
  end

  C.verify = function(args, o)
    if not adminOnly(o) then return end
    o("Checking system integrity...", T.title)
    o("")
    K.verifySystem(function(t, c) o(t, c) end)
  end

  C.programs = function(args, o)
    local dirs = { "/bin", "/usr/bin", "/home/" .. S.who }
    o("Executables:", T.title)
    for _, dir in ipairs(dirs) do
      if F.isDirectory(dir) then
        local ok2, list = pcall(F.list, dir)
        if ok2 and list then
          local fitems = {}
          if type(list) == "table" then fitems = list
          elseif type(list) == "function" then for n in list do fitems[#fitems+1] = n end end
          local found = {}
          for _, n in ipairs(fitems) do
            if n:match("%.lua$") then found[#found+1] = n end
          end
          if #found > 0 then
            o(" " .. dir .. ":", T.dim)
            for _, n in ipairs(found) do o("   " .. n, T.file_lua or T.file_exec or T.highlight) end
          end
        end
      end
    end
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

  C.log = function(args, o)
    if not adminOnly(o) then return end
    local logMod = K.getLog()
    if not logMod then o("Logger unavailable", T.error); return end
    local count = tonumber(args[1]) or 20
    local entries = logMod.recent(count)
    if #entries == 0 then o("(no log entries)", T.dim); return end
    for _, e in ipairs(entries) do
      local color = T.dim
      if e.level >= 3 then color = T.error
      elseif e.level >= 2 then color = T.warning
      elseif e.level >= 1 then color = T.fg end
      o(logMod.format(e), color)
    end
    o(#entries .. " entries shown", T.dim)
  end

  C.bg = function(args, o)
    if not args[1] then
      o("Usage: bg <script.lua> [args...]", T.dim)
      o("  Runs a Lua script in a background tab.", T.dim)
      return
    end
    local path = rp(args[1])
    local data = F.readFile(path)
    if not data then o("Cannot read: " .. args[1], T.error); return end
    local fn2, err2 = load(data, "=" .. args[1], "t", makeProgramEnv{name=args[1]})
    if not fn2 then o("Compile error: " .. tostring(err2), T.error); return end
    local runArgs = {}
    for i = 2, #args do runArgs[#runArgs+1] = args[i] end
    local name = args[1]:match("[^/]+$") or args[1]
    -- Create an output tab for this background task
    local bgTab = deps.createTab("output", "bg:" .. name, {
      content = { "Background task: " .. name, "PID: (starting...)", "" },
      offset = 0,
      pid = nil,
    })
    local tabIdx = #deps.tabs
    -- Capture output into the tab's content
    local BG_MAX_LINES = 500
    local function bgPrint(...)
      local parts = {}
      for i2 = 1, select("#", ...) do parts[#parts+1] = tostring(select(i2, ...)) end
      local line = table.concat(parts, "\t")
      bgTab.content[#bgTab.content + 1] = line
      -- Trim oldest lines if over limit (keep recent output)
      if #bgTab.content > BG_MAX_LINES then
        local trim = #bgTab.content - BG_MAX_LINES
        for i2 = 1, BG_MAX_LINES do
          bgTab.content[i2] = bgTab.content[i2 + trim]
        end
        for i2 = BG_MAX_LINES + 1, #bgTab.content do
          bgTab.content[i2] = nil
        end
        bgTab.offset = math.max(0, bgTab.offset - trim)
      end
      -- Auto-scroll if user is at the end
      local viewH2 = H - 3
      if bgTab.offset >= #bgTab.content - viewH2 - 2 then
        bgTab.offset = math.max(0, #bgTab.content - viewH2)
      end
    end
    local pid = P.spawn("bg:" .. name, function()
      -- Build sandboxed env with custom print for background output
      local taskEnv = makeProgramEnv{ name = args[1], stdout = bgPrint }
      local taskFn = load(data, "=" .. args[1], "t", taskEnv)
      if taskFn then
        local tok, terr = pcall(taskFn, table.unpack(runArgs))
        if not tok then
          bgPrint("Error: " .. tostring(terr))
        end
      end
      bgPrint("", "--- Task finished ---")
    end, {
      priority = 8,
      source   = "user",
      tsr      = true,
    })
    bgTab.pid = pid
    bgTab.content[2] = "PID: " .. pid
    o("Started background task: " .. name .. " (PID " .. pid .. ")", T.highlight)
    o("Switch to its tab with F2, or use 'kill " .. pid .. "' to stop.", T.dim)
  end

  C.run = function(args, o)
    if not args[1] then o("Usage: run <file.lua>", T.dim); return end
    local path = rp(args[1])
    local data = F.readFile(path)
    if not data then o("Cannot read: " .. args[1], T.error); return end
    local fn2, err2 = load(data, "=" .. args[1], "t", makeProgramEnv{name=args[1], stdout=function(line) o(line, T.fg) end})
    if not fn2 then o("Compile error: " .. tostring(err2), T.error); return end
    local runArgs = {}
    for i = 2, #args do runArgs[#runArgs+1] = args[i] end
    local ok2, result = pcall(fn2, table.unpack(runArgs))
    if not ok2 then o("Runtime error: " .. tostring(result), T.error)
    elseif result ~= nil then o(tostring(result), T.fg) end
  end

  C.lua = function(args, o)
    -- REPL has full _ENV access (debugging tool) — restrict to ROOT
    if S.userTier < 3 then
      o("Lua REPL requires root access.", T.error)
      return
    end
    D.fill(1, 1, W, H, " ", T.fg, T.bg)
    D.fill(1, 1, W, 1, " ", T.bar_fg, T.bar_bg)
    D.set(1, 1, " Lua REPL  type 'exit' to quit", T.bar_fg, T.bar_bg)
    local row   = 2
    local hist  = {}
    local function reout(text, color)
      if row > H - 1 then
        local gpu2 = D.getGpu()
        if gpu2 and gpu2.copy then gpu2.copy(1, 3, W, H-3, 0, -1) end
        D.fill(1, H-1, W, 1, " ", T.fg, T.bg)
        row = H - 1
      end
      D.set(1, row, tostring(text):sub(1,W), color or T.fg, T.bg)
      row = row + 1
    end
    while true do
      if row > H - 1 then
        D.getGpu().copy(1, 3, W, H-3, 0, -1)
        D.fill(1, H-1, W, 1, " ", T.fg, T.bg)
        row = H - 1
      end
      D.fill(1, row, W, 1, " ", T.fg, T.bg)
      D.set(1, row, "> ", T.highlight, T.bg)
      local buf  = ""
      local hidx2 = #hist + 1
      while true do
        D.fill(3, row, W-2, 1, " ", T.fg, T.bg)
        D.set(3, row, buf .. "_", T.fg, T.bg)
        local sig, _, ch2, co2 = deps.pullSignal()
        if sig == "key_down" then
          if co2 == 28 then break
          elseif co2 == 14 then if #buf > 0 then buf = buf:sub(1,-2) end
          elseif co2 == 200 then if hidx2 > 1 then hidx2 = hidx2 - 1 buf = hist[hidx2] or "" end
          elseif co2 == 208 then
            if hidx2 < #hist then hidx2 = hidx2 + 1 buf = hist[hidx2] or ""
            else hidx2 = #hist + 1 buf = "" end
          elseif ch2 and ch2 >= 32 and ch2 < 127 then buf = buf .. string.char(ch2) end
        elseif sig == "clipboard" and type(ch2) == "string" then
          buf = buf .. ch2:gsub("\n","")
        end
      end
      row = row + 1
      if buf == "" then
      elseif buf == "exit" or buf == "quit" then break
      else
        hist[#hist+1] = buf
        local replEnv = makeProgramEnv{
          name = "repl",
          caps = {
            ["fs.read"]=true, ["fs.write"]=true, ["compat.io"]=true,
            ["component"]=true, ["load"]=true, ["net"]=true,
          },
          stdout = function(line) reout(line, T.fg) end,
        }
        local fn3, err3 = load("return " .. buf, "=repl", "t", replEnv)
        if not fn3 then fn3, err3 = load(buf, "=repl", "t", replEnv) end
        if fn3 then
          local ok3, res = pcall(fn3)
          if ok3 then
            if res ~= nil then reout(tostring(res), T.highlight) end
          else reout(tostring(res), T.error) end
        else reout("Error: " .. tostring(err3), T.error) end
      end
    end
  end

  C.edit = function(args, o)
    if not args[1] then o("Usage: edit <file>", T.dim); return end
    local path = rp(args[1])
    openEditTab(path)
  end

  C.flash = function(args, o)
    if not rootOnly(o) then return end
    if not args[1] then
      o("Usage: flash <bios.lua>", T.dim)
      o("Flashes the given file to the system EEPROM.", T.dim)
      return
    end
    local path = rp(args[1])
    local eepromAddr = nil
    for addr in component.list("eeprom") do eepromAddr = addr; break end
    if not eepromAddr then
      o("No EEPROM detected. Insert EEPROM and press any key...", T.warning)
      while not eepromAddr do
        local sig, addr, compType = deps.pullSignal()
        if sig == "component_added" and compType == "eeprom" then
          eepromAddr = addr
        end
      end
      o("EEPROM detected.", T.highlight)
    end
    local eeprom = component.proxy(eepromAddr)
    local data, err = F.readFile(path)
    if not data then o("Cannot read: " .. tostring(err), T.error); return end
    local maxSize = eeprom.getSize()
    if #data > maxSize then
      o(string.format("File too large: %d bytes (EEPROM max: %d)", #data, maxSize), T.error)
      return
    end
    local elabel = eeprom.getLabel and eeprom.getLabel() or "(no label)"
    deps.drawOutRow(string.format("Flash %dB to [%s]? [y/N]: ", #data, elabel), T.warning)
    local confirmed = false
    repeat
      local s2, _, c2 = deps.pullSignal()
      if s2 == "key_down" and c2 ~= 0 then
        confirmed = (c2 == 121 or c2 == 89)
        break
      end
    until false
    if confirmed then
      eeprom.set(data)
      o("EEPROM flashed! " .. #data .. " bytes written.", T.highlight)
      o("Reboot for changes to take effect.", T.dim)
    else
      o("Aborted.", T.dim)
    end
  end

  C.whoami = function(args, o)
    if U then
      local s = U.getSession(st)
      o(s and s.user or "root", T.fg)
    else o(S.who, T.fg) end
  end

  C.users = function(args, o)
    if not adminOnly(o) then return end
    if not U then o("No user system", T.error); return end
    o(string.format(" %-12s %-8s %s", "User", "Tier", "Status"), T.title)
    o(string.rep("-", 34), T.border)
    local list = U.list and U.list() or U.listUsers and U.listUsers() or {}
    for _, u in ipairs(list) do
      local ustat = u.locked and "LOCKED" or "OK"
      o(string.format(" %-12s %-8s %s",
        u.username or u.user or "?",
        tostring(u.tier or u.accessLevel or "?"),
        ustat),
        u.locked and T.error or T.dim)
    end
  end

  C.passwd = function(args, o)
    if not U then o("No user system", T.error); return end
    local old = promptInput("Current password: ", 64, true)
    if not old then return end
    local new = promptInput("New password: ",     64, true)
    if not new then return end
    local s = U.getSession(st)
    local w2 = s and s.user or "root"
    local ok2, err2 = U.changePassword(w2, w2, old, new)
    if ok2 then S.lastOut = { "Password changed.", T.highlight }
    else        S.lastOut = { tostring(err2), T.error } end
  end

  C.useradd = function(args, o)
    if not rootOnly(o) then return end
    if not U then o("No user system", T.error); return end
    local name = args[1]
    if not name then o("Usage: useradd <username>", T.dim); return end
    local pass = promptInput("Password for " .. name .. ": ", 64, true)
    if not pass or pass == "" then o("Aborted.", T.dim); return end
    local pass2 = promptInput("Confirm password: ", 64, true)
    if pass2 ~= pass then o("Passwords do not match.", T.error); return end
    local ok2, err2 = U.create("root", name, pass, 1)
    if ok2 then S.lastOut = { "User '" .. name .. "' created.", T.highlight }
    else      S.lastOut = { tostring(err2), T.error } end
  end

  C.userdel = function(args, o)
    if not rootOnly(o) then return end
    if not U then o("No user system", T.error); return end
    local name = args[1]
    if not name then o("Usage: userdel <username>", T.dim); return end
    local confirm = promptInput("Delete '" .. name .. "'? [y/N]: ", 1, false)
    if confirm ~= "y" and confirm ~= "Y" then o("Aborted.", T.dim); return end
    local ok2, err2 = U.delete("root", name)
    if ok2 then S.lastOut = { "User '" .. name .. "' deleted.", T.highlight }
    else      S.lastOut = { tostring(err2), T.error } end
  end

  C.usermod = function(args, o)
    if not rootOnly(o) then return end
    if not U then o("No user system", T.error); return end
    local name, action = args[1], args[2]
    if not name or not action then
      o("Usage: usermod <username> lock|unlock|admin|user", T.dim); return
    end
    local ok2, err2
    if action == "lock" then
      if U.setLocked then ok2, err2 = U.setLocked("root", name, true)
      else ok2, err2 = false, "setLocked unavailable" end
      if ok2 then S.lastOut = { "'" .. name .. "' locked.", T.highlight }
      else      S.lastOut = { tostring(err2), T.error } end
    elseif action == "unlock" then
      if U.setLocked then ok2, err2 = U.setLocked("root", name, false)
      else ok2, err2 = false, "setLocked unavailable" end
      if ok2 then S.lastOut = { "'" .. name .. "' unlocked.", T.highlight }
      else      S.lastOut = { tostring(err2), T.error } end
    elseif action == "admin" then
      if U.setTier then ok2, err2 = U.setTier("root", name, 2)
      else ok2, err2 = false, "setTier unavailable" end
      if ok2 then S.lastOut = { "'" .. name .. "' promoted to admin.", T.highlight }
      else      S.lastOut = { tostring(err2), T.error } end
    elseif action == "user" then
      if U.setTier then ok2, err2 = U.setTier("root", name, 1)
      else ok2, err2 = false, "setTier unavailable" end
      if ok2 then S.lastOut = { "'" .. name .. "' set to user.", T.highlight }
      else      S.lastOut = { tostring(err2), T.error } end
    else
      o("Unknown action: " .. action, T.error)
      o("Valid: lock, unlock, admin, user", T.dim)
    end
  end

  -- ── Peripheral / mount commands ───────────────────────
  C.lsdev = function(args, o)
    o(string.format(" %-16s %-10s %s", "Type", "Address", "Info"), T.title)
    o(string.rep("-", 46), T.dim)
    local count = 0
    for addr, ctype in component.list() do
      local cinfo = ""
      if ctype == "filesystem" then
        local ok2, px = pcall(component.proxy, addr)
        if ok2 and px then
          local lbl = px.getLabel and px.getLabel() or ""
          local kb  = px.spaceTotal and math.floor(px.spaceTotal()/1024) or 0
          cinfo = (lbl ~= "" and '"'..lbl..'" ' or "") .. kb .. "K"
        end
      elseif ctype == "modem" then
        local ok2, px = pcall(component.proxy, addr)
        if ok2 and px and px.isWireless then
          cinfo = px.isWireless() and "wireless" or "wired"
        end
      end
      o(string.format(" %-16s %s  %s", ctype, addr:sub(1,8).."...", cinfo), T.fg)
      count = count + 1
    end
    if count == 0 then o("  (no peripherals detected)", T.dim) end
  end

  C.mount = function(args, o)
    if args[1] and args[2] then
      local target, mntArg = args[1], args[2]
      local found
      for addr in component.list("filesystem") do
        if addr:sub(1, #target) == target then found = addr; break end
        local ok2, px = pcall(component.proxy, addr)
        if ok2 and px and px.getLabel and px.getLabel() == target then
          found = addr; break
        end
      end
      if not found then o("Device not found: " .. target, T.error); return end
      local mnt = mntArg:sub(1,1) == "/" and mntArg or ("/" .. mntArg)
      local ok2, px2 = pcall(component.proxy, found)
      if not ok2 then o("Cannot proxy device", T.error); return end
      if not F.exists(mnt) then pcall(F.makeDirectory, mnt) end
      F.mount(mnt, px2)
      S.lastOut = { "Mounted at " .. mnt, T.highlight }
    else
      local mnts = F.mounts()
      o(string.format(" %-18s %-14s %s", "Mount", "Label", "Space"), T.title)
      o(string.rep("-", 46), T.dim)
      for _, m in ipairs(mnts) do
        local kb = m.total and math.floor(m.total/1024) or 0
        local used = m.used and math.floor(m.used/1024) or 0
        o(string.format(" %-18s %-14s %dK/%dK",
          (m.mountPoint or "?"):sub(1,18),
          (m.label or ""):sub(1,14),
          used, kb), T.fg)
      end
    end
  end

  C.umount = function(args, o)
    if not args[1] then o("Usage: umount <mountpoint>", T.dim); return end
    local mnt = args[1]:sub(1,1) == "/" and args[1] or ("/" .. args[1])
    local ok2, err2 = F.unmount(mnt)
    if ok2 then S.lastOut = { "Unmounted " .. mnt, T.highlight }
    else      S.lastOut = { tostring(err2 or "Failed to unmount"), T.error } end
  end

  C.logout   = function(args, o) E.push("tos_logout", S.displayIdx) end
  C.reboot   = function(args, o) if not adminOnly(o) then return end; K.reboot() end
  C.shutdown = function(args, o) if not adminOnly(o) then return end; K.shutdown() end

  -- ── Environment variables ─────────────────────────────
  C.env = function(args, o)
    local ok2, envMod = pcall(require, "kernel.env")
    if not ok2 then o("Env module unavailable", T.error); return end
    local P2 = K.getProc()
    local cur = P2 and P2.current() or nil
    if args[1] then
      -- set: env KEY=VALUE
      local k, v = args[1]:match("^([%w_]+)=(.*)$")
      if k then
        envMod.write(cur, k, v)
        o(k .. "=" .. v, T.highlight)
      else
        -- get: env KEY
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

  -- ── Startup services ──────────────────────────────────
  C.service = function(args, o)
    if not adminOnly(o) then return end
    local ok2, rcMod = pcall(require, "kernel.rc")
    if not ok2 then o("RC module unavailable", T.error); return end
    if not args[1] then
      local svcs = rcMod.list()
      if #svcs == 0 then o("No services registered", T.dim); return end
      o(string.format(" %-16s %s", "Service", "Status"), T.title)
      o(string.rep("-", 28), T.dim)
      for _, s in ipairs(svcs) do
        local st2 = s.running and "running" or "stopped"
        o(string.format(" %-16s %s", s.name:sub(1,16), st2),
          s.running and T.highlight or T.dim)
      end
    elseif args[1] == "start" and args[2] then
      local ok3, err = rcMod.start(args[2])
      o(ok3 and "Started: " .. args[2] or tostring(err), ok3 and T.highlight or T.error)
    elseif args[1] == "stop" and args[2] then
      local ok3, err = rcMod.stop(args[2])
      o(ok3 and "Stopped: " .. args[2] or tostring(err), ok3 and T.highlight or T.error)
    else
      o("Usage: service [start|stop <name>]", T.dim)
    end
  end

  -- ── Scheduled tasks ───────────────────────────────────
  C.cron = function(args, o)
    if not adminOnly(o) then return end
    local ok2, cronMod = pcall(require, "kernel.cron")
    if not ok2 then o("Cron module unavailable", T.error); return end
    if not args[1] or args[1] == "list" then
      local jobs = cronMod.list()
      if #jobs == 0 then o("No scheduled jobs", T.dim); return end
      o(string.format(" %-4s %-16s %-8s %s", "ID", "Name", "Every", "Enabled"), T.title)
      for _, j in ipairs(jobs) do
        o(string.format(" %-4d %-16s %-8s %s",
          j.id, j.name:sub(1,16), j.interval.."s", j.enabled and "yes" or "no"),
          j.enabled and T.fg or T.dim)
      end
    elseif args[1] == "add" and args[2] and args[3] and args[4] then
      local name = args[2]
      local interval = tonumber(args[3])
      local script = table.concat(args, " ", 4)
      if not interval then o("Invalid interval", T.error); return end
      local id = cronMod.add(name, interval, script)
      o("Added job #" .. id .. ": " .. name, T.highlight)
    elseif args[1] == "rm" and args[2] then
      local id = tonumber(args[2])
      if id then cronMod.remove(id); o("Removed job #" .. id, T.highlight)
      else o("Invalid ID", T.error) end
    else
      o("Usage: cron [list|add <name> <seconds> <script>|rm <id>]", T.dim)
    end
  end

  -- ── Peripheral commands ───────────────────────────────
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

  -- ── Component shell ───────────────────────────────────
  C.component = function(args, o)
    if not adminOnly(o) then return end
    if not args[1] then
      o("Usage: component <type> [method] [args...]", T.dim)
      o("  component list            List all component types", T.dim)
      o("  component gpu             Show GPU methods", T.dim)
      o("  component gpu getDepth    Call gpu.getDepth()", T.dim)
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
    local proxy = component.proxy(component.list(args[1])() or "")
    if not proxy then o("No component: " .. args[1], T.error); return end
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

  -- ── Module manager ─────────────────────────────────────
  C.mod = function(args, o)
    local ok2, modMgr = pcall(require, "kernel.modules")
    if not ok2 then o("Module system unavailable", T.error); return end
    local sub = args[1]
    if not sub or sub == "list" then
      local mods = modMgr.list()
      if #mods == 0 then
        -- Auto-scan for unregistered module dirs
        local scanned = modMgr.scan()
        if scanned > 0 then
          o("Found " .. scanned .. " unregistered module(s), registering...", T.highlight)
          mods = modMgr.list()
        end
      end
      if #mods == 0 then o("No modules installed", T.dim); return end
      o(string.format(" %-14s %-7s %-8s %s", "Module", "Ver", "Type", "Status"), T.title)
      o(string.rep("-", 44), T.dim)
      for _, m in ipairs(mods) do
        local st2 = m.enabled and "enabled" or "disabled"
        o(string.format(" %-14s %-7s %-8s %s",
          m.name:sub(1,14), m.version:sub(1,7), m.type:sub(1,8), st2),
          m.enabled and T.highlight or T.dim)
      end
    elseif sub == "info" then
      if not args[2] then o("Usage: mod info <name>", T.dim); return end
      local entry = modMgr.get(args[2])
      if not entry then o("Not installed: " .. args[2], T.error); return end
      o(" Module: " .. entry.name, T.title)
      o(" Version:     " .. entry.version, T.fg)
      o(" Type:        " .. entry.type, T.fg)
      o(" Description: " .. (entry.description ~= "" and entry.description or "(none)"), T.fg)
      o(" Author:      " .. (entry.author ~= "" and entry.author or "(unknown)"), T.fg)
      o(" Status:      " .. (entry.enabled and "enabled" or "disabled"), entry.enabled and T.highlight or T.dim)
      if entry.commands and #entry.commands > 0 then
        o(" Commands:    " .. table.concat(entry.commands, ", "), T.fg)
      end
      if entry.files then
        o(" Files:       " .. #entry.files, T.dim)
      end
    elseif sub == "enable" then
      if not adminOnly(o) then return end
      if not args[2] then o("Usage: mod enable <name>", T.dim); return end
      local ok3, err = modMgr.enable(args[2])
      if ok3 then o("Enabled: " .. args[2], T.highlight)
      else o("Failed: " .. tostring(err), T.error) end
    elseif sub == "disable" then
      if not adminOnly(o) then return end
      if not args[2] then o("Usage: mod disable <name>", T.dim); return end
      local ok3, err = modMgr.disable(args[2])
      if ok3 then o("Disabled: " .. args[2], T.highlight)
      else o("Failed: " .. tostring(err), T.error) end
    elseif sub == "uninstall" then
      if not adminOnly(o) then return end
      if not args[2] then o("Usage: mod uninstall <name>", T.dim); return end
      local entry = modMgr.get(args[2])
      if not entry then o("Not installed: " .. args[2], T.error); return end
      local ok3, err = modMgr.uninstall(args[2])
      if ok3 then o("Uninstalled: " .. args[2], T.highlight)
      else o("Failed: " .. tostring(err), T.error) end
    elseif sub == "commands" then
      local cmds = modMgr.getCommands()
      local names = {}
      for n in pairs(cmds) do names[#names + 1] = n end
      if #names == 0 then o("No module commands registered", T.dim); return end
      table.sort(names)
      o(" Commands from modules:", T.title)
      for _, n in ipairs(names) do o("  " .. n, T.fg) end
    elseif sub == "scan" then
      local found = modMgr.scan()
      if found > 0 then
        o("Registered " .. found .. " new module(s).", T.highlight)
      else
        o("No unregistered module directories found.", T.dim)
      end
    else
      o("Usage: mod [list|info|enable|disable|uninstall|scan|commands] [name]", T.dim)
    end
  end

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
            local hasModule = F.exists(F.join(mnt, "module.cfg"))
            local hasTOS = F.exists(F.join(mnt, "tos/kernel/init.lua"))
            local status = hasModule and "module" or (hasTOS and "TOS install" or "data")
            local label = (m.label or ""):sub(1, 10)
            o(string.format(" %-16s %-10s %s", mnt:sub(1,16), label, status),
              hasModule and T.highlight or T.fg)
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
            local mnt = "/mnt/" .. name
            local hasModule = F.exists(F.join(mnt, "module.cfg"))
            local hasTOS = F.exists(F.join(mnt, "tos/kernel/init.lua"))
            local status = hasModule and "module" or (hasTOS and "TOS install" or "data")
            o(string.format(" %-16s %-8s %s", mnt:sub(1,16), "disk", status),
              hasModule and T.highlight or T.fg)
          end
        else
          o("No removable disks mounted", T.dim)
        end
      else
        o("No removable disks mounted", T.dim)
      end
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
      local hasModule = F.exists(F.join(mnt, "module.cfg"))
      local hasTOS = F.exists(F.join(mnt, "tos/kernel/init.lua"))
      if hasModule then
        o(" Contains: Module disk", T.highlight)
        local ok3, modMgr = pcall(require, "kernel.modules")
        if ok3 then
          local manifest, err = modMgr.readManifest(mnt)
          if manifest then
            o("   Name:    " .. manifest.name, T.fg)
            o("   Version: " .. manifest.version, T.fg)
            o("   Type:    " .. manifest.type, T.fg)
            if manifest.description then
              o("   Desc:    " .. manifest.description, T.fg)
            end
          else
            o("   (manifest error: " .. tostring(err) .. ")", T.error)
          end
        end
      elseif hasTOS then
        o(" Contains: TOS install disk", T.highlight)
      else
        o(" Contains: Data / blank disk", T.dim)
      end
    elseif sub == "install" then
      if not adminOnly(o) then return end
      if not args[2] then o("Usage: disk install <mount-point>", T.dim); return end
      local mnt = F.normalize(args[2])
      if not F.exists(F.join(mnt, "module.cfg")) then
        o("No module.cfg found on " .. mnt, T.error)
        o("This disk does not contain a module.", T.dim)
        return
      end
      local ok3, modMgr = pcall(require, "kernel.modules")
      if not ok3 then o("Module system unavailable", T.error); return end
      -- Read manifest first to show what we're installing
      local manifest, merr = modMgr.readManifest(mnt)
      if not manifest then
        o("Invalid module: " .. tostring(merr), T.error); return
      end
      local existing = modMgr.get(manifest.name)
      if existing then
        o("Updating " .. manifest.name .. " (v" .. existing.version .. " -> v" .. manifest.version .. ")", T.highlight)
      else
        o("Installing " .. manifest.name .. " v" .. manifest.version .. " ...", T.title)
      end
      local ok4, result = modMgr.install(mnt)
      if ok4 then
        o("Installed: " .. manifest.name .. " (" .. result .. ")", T.highlight)
        o("Use 'mod enable " .. manifest.name .. "' to activate", T.dim)
      else
        o("Install failed: " .. tostring(result), T.error)
      end
    elseif sub == "export" then
      if not adminOnly(o) then return end
      if not args[2] or not args[3] then
        o("Usage: disk export <module-name> <mount-point>", T.dim); return
      end
      local modName = args[2]
      local mnt = F.normalize(args[3])
      if not F.exists(mnt) or not F.isDirectory(mnt) then
        o("Not a valid mount point: " .. mnt, T.error); return
      end
      local ok3, modMgr = pcall(require, "kernel.modules")
      if not ok3 then o("Module system unavailable", T.error); return end
      local entry = modMgr.get(modName)
      if not entry then o("Module not installed: " .. modName, T.error); return end
      local srcDir = modMgr.getDir(modName)
      if not srcDir then o("Module directory not found", T.error); return end
      -- Copy module.cfg to disk root
      local cfgData = F.readFile(F.join(srcDir, "module.cfg"))
      if not cfgData then o("Cannot read module manifest", T.error); return end
      local ok4 = F.writeFile(F.join(mnt, "module.cfg"), cfgData)
      if not ok4 then o("Failed to write module.cfg", T.error); return end
      -- Copy all module files
      local copied, failed = 0, 0
      for _, file in ipairs(entry.files) do
        local data = F.readFile(F.join(srcDir, file))
        if data then
          -- Ensure subdirectories exist
          local dir = F.split(F.join(mnt, file))
          if dir and dir ~= "/" and not F.exists(dir) then F.makeDirectory(dir) end
          if F.writeFile(F.join(mnt, file), data) then copied = copied + 1
          else failed = failed + 1 end
        else failed = failed + 1 end
      end
      if failed == 0 then
        o("Exported " .. modName .. " to " .. mnt .. " (" .. copied .. " files)", T.highlight)
        o("Disk can be inserted on another TOS machine and installed with:", T.dim)
        o("  disk install " .. mnt, T.dim)
      else
        o(copied .. " copied, " .. failed .. " failed", T.error)
      end
    elseif sub == "eject" then
      if not args[2] then o("Usage: disk eject <mount-point>", T.dim); return end
      local mnt = F.normalize(args[2])
      local ok3, err = F.unmount(mnt)
      if ok3 then o("Ejected: " .. mnt, T.highlight)
      else o("Eject failed: " .. tostring(err), T.error) end
    else
      o("Usage: disk [list|info|install|export|eject] [args]", T.dim)
    end
  end

  -- ── Tape stub (delegates to tape-storage module) ───────
  C.tape = function(args, o)
    -- Check if the tape-storage module is installed and enabled
    local ok2, modMgr = pcall(require, "kernel.modules")
    if ok2 then
      local fn = modMgr.getCommand("tape")
      if fn then
        -- Module is active — delegate entirely
        fn(args, o)
        return
      end
      -- Module exists but may not be enabled
      local entry = modMgr.get("tape-storage")
      if entry then
        if not entry.enabled then
          o("The tape-storage module is installed but not enabled.", T.warning)
          o("Run:  mod enable tape-storage", T.highlight)
        else
          o("The tape-storage module is enabled but its command", T.warning)
          o("did not load. Check 'log' for errors.", T.dim)
        end
        return
      end
    end
    -- Module not installed — show guidance
    o("Tape Storage", T.title)
    o("", T.fg)
    o("No tape module installed. To use tapes for data storage:", T.fg)
    o("", T.fg)
    o(" Option 1: Install the official module", T.highlight)
    o("  Copy tape-storage to a floppy, then:", T.dim)
    o("    disk install /mnt/<floppy>", T.dim)
    o("    mod enable tape-storage", T.dim)
    o("", T.fg)
    o(" Option 2: Build your own", T.highlight)
    o("  Create a module directory with:", T.dim)
    o("    /usr/modules/my-tape/module.cfg", T.dim)
    o("    /usr/modules/my-tape/init.lua", T.dim)
    o("", T.fg)
    o("  module.cfg example:", T.dim)
    o('    { name="my-tape", version="1.0.0",', T.dim)
    o('      type="command", files={"init.lua"},', T.dim)
    o('      commands={"tape"} }', T.dim)
    o("", T.fg)
    o("  init.lua must return:", T.dim)
    o("    { commands = { tape = function(args, o) ... end } }", T.dim)
    o("", T.fg)
    o("  See 'help mod' or the TOS README for module format.", T.dim)
  end

  -- ── Deploy command ─────────────────────────────────────
  C.deploy = function(args, o)
    if not rootOnly(o) then return end
    local target = args[1]
    if not target then
      o("Usage: deploy <mount-point>", T.dim)
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

    -- System files to include on the install disk
    local files = {
      "/init.lua",
      "/tos/kernel/init.lua", "/tos/kernel/hal.lua", "/tos/kernel/event.lua",
      "/tos/kernel/process.lua", "/tos/kernel/fs.lua", "/tos/kernel/display.lua",
      "/tos/kernel/log.lua", "/tos/kernel/crypto.lua", "/tos/kernel/users.lua",
      "/tos/kernel/securefs.lua", "/tos/kernel/config.lua", "/tos/kernel/power.lua",
      "/tos/kernel/serialize.lua", "/tos/kernel/env.lua", "/tos/kernel/pipe.lua",
      "/tos/kernel/rc.lua", "/tos/kernel/cron.lua", "/tos/kernel/screen.lua",
      "/tos/kernel/modules.lua",
      "/tos/kernel/net/init.lua", "/tos/kernel/net/protocol.lua",
      "/tos/kernel/net/trust.lua", "/tos/kernel/net/transfer.lua",
      "/tos/kernel/net/remote.lua",
      "/tos/compat/init.lua", "/tos/compat/sides.lua", "/tos/compat/colors.lua",
      "/tos/compat/keyboard.lua", "/tos/compat/text.lua",
      "/tos/compat/serialization.lua", "/tos/compat/buffer.lua",
      "/tos/compat/term.lua", "/tos/compat/filesystem.lua",
      "/tos/compat/event.lua", "/tos/compat/shell_api.lua", "/tos/compat/io.lua",
      "/tos/peripheral/redstone.lua", "/tos/peripheral/robot.lua",
      "/tos/peripheral/inventory.lua",
      "/tos/shell/init.lua", "/tos/shell/login.lua", "/tos/shell/panels.lua",
      "/tos/shell/ext.lua", "/tos/shell/syntax.lua", "/tos/shell/chat.lua",
      "/tos/shell/tutorial.lua",
    }

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

  -- ── Chat command ──────────────────────────────────────
  C.chat = function(args, o)
    if not NM then o("No network available", T.error); return end
    local ok2, chatMod = pcall(require, "shell.chat")
    if not ok2 then o("Chat module unavailable", T.error); return end
    chatMod.run(K, st)
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
      o("Usage: screen [list|next|<index>]", T.dim)
    end
  end

  -- Lazy-loaded extended commands
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
  for _, n in ipairs({ "net", "ping", "hostname", "device", "config", "battery", "audio" }) do
    C[n] = ext(n)
  end

  return C
end

return M
