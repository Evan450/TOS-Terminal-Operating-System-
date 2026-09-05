local M = {}

local REGISTRY = {

  help     = { category = "core", tier = 0, help = "Quick help (install-aware); 'man' for detail" },
  man      = { category = "core", tier = 0, help = "Detailed manual page for a command/topic" },
  why      = { category = "core", tier = 0, help = "Explain a 'permission denied' (or what a command needs)" },
  screendump = { category = "core", tier = 1, help = "Capture this screen to a text file (for bug reports)" },
  crash    = { category = "core", tier = 2, help = "List/read crash post-mortems saved in /var/crash" },
  about    = { category = "core", tier = 0, help = "OS info: version, codename, hardware summary" },

  ver      = { category = "core", tier = 0, help = "TOS version info", alias = "about" },
  echo     = { category = "core", tier = 0, help = "Print arguments" },

  notify   = { category = "core", tier = 1, help = "Raise a dialog box on every seat (the intrusive 'echo')" },
  tutorial = { category = "core", tier = 0, help = "Replay the welcome walkthrough (--reset to see it again at login)" },
  cls      = { category = "core", tier = 0, help = "Clear the screen" },
  clear    = { category = "core", tier = 0, help = "Clear the screen", alias = "cls" },
  cd       = { category = "core", tier = 0, help = "Change directory" },
  ls       = { category = "core", tier = 0, help = "List directory entries" },
  dir      = { category = "core", tier = 0, help = "List directory entries", alias = "ls" },
  pwd      = { category = "core", tier = 0, help = "Print working directory" },
  cat      = { category = "core", tier = 0, help = "Print file contents" },
  type     = { category = "core", tier = 0, help = "Print file contents", alias = "cat" },
  more     = { category = "core", tier = 0, help = "Page through a file" },
  head     = { category = "core", tier = 0, help = "Print the first lines of a file" },
  tail     = { category = "core", tier = 0, help = "Print the last lines of a file (watch tail <log> to follow it)" },
  mkdir    = { category = "core", tier = 1, help = "Make a directory" },
  touch    = { category = "core", tier = 1, help = "Create an empty file" },
  compress   = { category = "core", tier = 1, help = "Compress a file with the data card (-> .tcz)" },
  decompress = { category = "core", tier = 1, help = "Restore a .tcz file compressed by 'compress'" },
  rm       = { category = "core", tier = 1, help = "Remove a file (--hard skips trash)" },
  trash    = { category = "core", tier = 1, help = "Per-user trash: list/empty/restore" },
  vault    = { category = "core", tier = 1, help = "Encrypt/decrypt files, tapes, or in-place (passphrase-based)" },
  keychain = { category = "core", tier = 1, help = "Per-user passphrase stash (unlocked with login password)" },
  cp       = { category = "core", tier = 1, help = "Copy a file" },
  mv       = { category = "core", tier = 1, help = "Move/rename a file" },
  find     = { category = "core", tier = 0, help = "Find files by name" },
  grep     = { category = "core", tier = 0, help = "Search a file for a pattern" },
  wc       = { category = "core", tier = 0, help = "Count lines/words/bytes" },
  df       = { category = "core", tier = 0, help = "Disk space per mount (with usage bars)" },
  du       = { category = "core", tier = 0, help = "Size of a path on disk (recursive)" },
  mem      = { category = "core", tier = 0, help = "Memory report: RAM + swap usage, tier, danger zone" },
  hw       = { category = "core", tier = 0, help = "Hardware inventory: tiers, data card, components" },
  hardware = { category = "core", tier = 0, help = "Hardware inventory", alias = "hw" },
  ps       = { category = "core", tier = 0, help = "List processes (-v for caps)" },
  monitor  = { category = "core", tier = 0, help = "Live System Monitor: processes, services, memory (also Ctrl+T)" },
  top      = { category = "core", tier = 0, help = "Live System Monitor", alias = "monitor" },
  watch    = { category = "core", tier = 0, help = "Open a live, self-updating tab for a command (e.g. watch ps)" },
  history  = { category = "core", tier = 0, help = "Show command history" },
  uptime   = { category = "core", tier = 0, help = "Show kernel uptime" },
  date     = { category = "core", tier = 0, help = "Show date/time (date tz <h> to set offset)" },
  time     = { category = "core", tier = 0, help = "Show date/time", alias = "date" },
  menu     = { category = "core", tier = 1, help = "Adjust the menu bar (show/add/hide/rename/move/reset)" },
  keys     = { category = "core", tier = 0, help = "Show or change TOS's standard keyboard shortcuts" },

  ["tape-menu"] = { category = "core", tier = 1, help = "Personal command menu from your identity tape (keycard)" },
  desktop  = { category = "core", tier = 0, help = "Open the Desktop: app tiles for built-ins + installed packages" },
  clip     = { category = "core", tier = 0, help = "Show, set or clear the text clipboard" },
  settings = { category = "core", tier = 0, help = "Open the Settings app (theme, status bar, desktop, system)" },
  lang     = { category = "core", tier = 0, help = "Show or set the UI language (data catalogs in /usr/lang)" },
  tree     = { category = "core", tier = 0, help = "Show directory tree" },
  whoami   = { category = "core", tier = 0, help = "Show current user" },
  passwd   = { category = "core", tier = 0, help = "Change own password" },

  sudo     = { category = "core", tier = 1, help = "Run a command with elevated privileges (sudo <cmd> | -s | -k | setup)" },
  logout   = { category = "core", tier = 0, help = "Log out of this session" },

  cli      = { category = "core", tier = 0, help = "Drop to the command-line shell (same commands, no panels)" },
  tui      = { category = "core", tier = 0, help = "Return to the full panels interface" },
  reboot   = { category = "core", tier = 2, help = "Reboot the system" },
  shutdown = { category = "core", tier = 2, help = "Shut the system down" },

  which    = { category = "core", tier = 0, help = "Show what a command name resolves to (built-in, package, or program)" },
  alias    = { category = "core", tier = 0, help = "Per-user command aliases: 'alias' lists, 'alias ll ls -l' defines" },
  unalias  = { category = "core", tier = 0, help = "Remove a command alias" },
  env      = { category = "core", tier = 0, help = "Show environment variables" },
  export   = { category = "core", tier = 0, help = "Set an environment variable" },
  set      = { category = "core", tier = 0, help = "Set an environment variable", alias = "export" },

  kill     = { category = "admin", tier = 2, help = "Kill a process by PID" },
  fg       = { category = "admin", tier = 2, help = "Bring a process to foreground" },

  srm      = { category = "admin", tier = 1, help = "System Repair & Maintenance: status/scan/repair/baseline (front door for doctor+verify)" },
  verify   = { category = "admin", tier = 2, help = "File integrity vs the manifest (vs 'doctor' = runtime health)" },
  doctor   = { category = "admin", tier = 1, help = "Runtime health: memory/disk/services/power/security ('verify' = files)" },
  backup   = { category = "admin", tier = 2, help = "Snapshot/inspect/restore a directory tree" },
  pkg      = { category = "admin", tier = 2, help = "Package manager: list/search/install/upgrade/outdated/uninstall/enable/disable/make-disk" },
  install  = { category = "admin", tier = 2, help = "Install a package (shortcut for 'pkg install')", alias = "pkg" },
  uninstall = { category = "admin", tier = 2, help = "Remove a package (shortcut for 'pkg uninstall')", alias = "pkg" },
  diag     = { category = "admin", tier = 1, help = "Runtime health", alias = "doctor" },
  optimize = { category = "admin", tier = 1, help = "Optimizations: swap (status/clear/keys/on/off), display buffer" },
  bootsettings = { category = "admin", tier = 2, help = "Edit boot profile/verbosity/toggles (DEL during boot = visual editor)" },
  kiosk    = { category = "admin", tier = 2, help = "Kiosk-mode info (log in as 'kiosk' to activate)" },
  profile  = { category = "core",  tier = 0, help = "Per-user profile (theme, env, startup, prompt)" },
  programs = { category = "admin", tier = 2, help = "List installed executables" },
  log      = { category = "admin", tier = 1, help = "Show recent kernel log (filtered by tier)" },
  bg       = { category = "admin", tier = 2, help = "Run a script in the background" },
  run      = { category = "admin", tier = 2, help = "Run a Lua file directly" },
  lua      = { category = "admin", tier = 3, help = "Open the Lua REPL (root only)" },
  edit     = { category = "admin", tier = 2, help = "Open a file in the editor" },
  flash    = { category = "admin", tier = 3, help = "Flash a BIOS to EEPROM (root only)" },
  protect  = { category = "admin", tier = 3, help = "Stand down protected-path guards for this session (root only)" },
  reclaim  = { category = "admin", tier = 3, help = "Remove leftover OpenOS files after installing over it (root only)" },
  users    = { category = "admin", tier = 2, help = "List users (tier-filtered)" },
  useradd  = { category = "admin", tier = 2, help = "Create a new user" },
  userdel  = { category = "admin", tier = 2, help = "Delete a user" },
  usermod  = { category = "admin", tier = 2, help = "Modify a user" },
  lsdev    = { category = "admin", tier = 1, help = "List connected components (devices)" },
  devices  = { category = "admin", tier = 1, help = "List connected components", alias = "lsdev" },
  mount    = { category = "admin", tier = 2, help = "Mount a disk" },
  umount   = { category = "admin", tier = 2, help = "Unmount a path" },
  jbod     = { category = "admin", tier = 2, help = "Disk pooling: combine several disks into one mount (opt-in)" },
  netfs    = { category = "admin", tier = 2, help = "Remote shares: mount a directory exported by another TOS machine" },
  theme    = { category = "admin", tier = 1, help = "Pick a preset theme for yourself (custom colours admin-only)" },
  colors   = { category = "admin", tier = 1, help = "Pick a theme", alias = "theme" },
  service  = { category = "admin", tier = 2, help = "Start/stop/list rc.d services" },
  cron     = { category = "admin", tier = 2, help = "Manage cron jobs" },

  redstone = { category = "extras", tier = 1, help = "Redstone I/O (requires peripheral.redstone cap)" },
  rs       = { category = "extras", tier = 1, help = "Redstone I/O", alias = "redstone" },
  robot    = { category = "extras", tier = 1, help = "Robot control (requires peripheral.robot cap)" },
  inventory = { category = "extras", tier = 1, help = "Inventory control (requires peripheral.inventory cap)" },
  inv      = { category = "extras", tier = 1, help = "Inventory control", alias = "inventory" },
  component = { category = "extras", tier = 2, help = "Generic component invocation" },
  compat   = { category = "extras", tier = 0, help = "OpenOS compat layer status" },
  disk     = { category = "extras", tier = 2, help = "Removable disks: list/info/install/eject (pooling = 'jbod', space = 'df')" },
  drive    = { category = "extras", tier = 1, help = "Unmanaged (raw) drives: list/info/format/mount/check/defrag (needs 'blockfs')" },
  tape     = { category = "extras", tier = 1, help = "Tape archive (via the tape package)" },
  deploy   = { category = "extras", tier = 3, help = "Create install disk from running system" },
  chat     = { category = "extras", tier = 1, help = "Network chat" },
  mail     = { category = "extras", tier = 1, help = "Mesh email (needs the 'mail' add-on): 'mail' opens the inbox; mail send/read/delete" },
  intercom = { category = "extras", tier = 1, help = "Announcement system (needs the 'intercom' add-on): say/play a tape cue + broadcast it" },

  ["cluster-setup"] = { category = "extras", tier = 3, help = "Set this machine up as a cluster Master or Manager (guided; works before anything is installed)" },
  rbmk     = { category = "extras", tier = 1, help = "RBMK reactor supervisor (needs the 'rbmk-control' add-on): survey/status/limits/scram" },
  rsh      = { category = "extras", tier = 2, help = "Remote shell client" },
  scp      = { category = "extras", tier = 1, help = "Network file copy" },
  screen   = { category = "extras", tier = 1, help = "Seat/screen info; 'screen res <auto|max|WxH>' sets resolution" },

  net      = { category = "extras", tier = 1, help = "Network admin (trust, peers, servers, ports)" },
  ping     = { category = "extras", tier = 1, help = "Network ping" },
  hostname = { category = "extras", tier = 0, help = "Show device type + hostname; set the name with 'hostname <name>'" },
  config   = { category = "extras", tier = 2, help = "Edit /etc/tos.cfg" },
  battery  = { category = "extras", tier = 0, help = "Power management info" },
  internet = { category = "extras", tier = 1, help = "Internet card: status, a test fetch, and the machine-wide on/off" },
  audio    = { category = "extras", tier = 1, help = "Audio feedback controls" },
}

local NEEDS = {
  net = "net", ping = "net", chat = "net", rsh = "net", scp = "net",

  mail = { "module:mail", "net" },

  intercom = "net",

  audio = "audio", compat = "compat", jbod = "jbod",

  netfs = "net",
  compress = "component:data", decompress = "component:data",
  redstone = "component:redstone", rs = "component:redstone",
  robot = "component:robot",
  inventory = "inventory", inv = "inventory",
  tape = "module:tape",
  ["tape-menu"] = "component:tape_drive",

  internet = "component:internet",
}
M.NEEDS = NEEDS

function M.needMet(token)
  if not token then return true end

  if type(token) == "table" then
    for _, t in ipairs(token) do
      if not M.needMet(t) then return false end
    end
    return true
  end
  local TOS = _G._TOS or {}
  if token == "net"     then return TOS.net     ~= nil end
  if token == "swap"    then return TOS.swap    ~= nil end
  if token == "jbod"    then return TOS.jbod    ~= nil end
  if token == "audio"   then return TOS.audio   ~= nil end
  if token == "compat"  then return TOS.compat  ~= nil end
  if token == "cluster" then return TOS.cluster_worker ~= nil end
  local ctype = token:match("^component:(.+)$")
  if ctype then
    local ok, component = pcall(require, "component")
    if not ok then return false end
    for _ in component.list(ctype) do return true end
    return false
  end
  if token == "inventory" then
    local ok, component = pcall(require, "component")
    if not ok then return false end
    for _, t in ipairs({ "inventory_controller", "transposer", "tank_controller" }) do
      for _ in component.list(t) do return true end
    end
    return false
  end
  local mod = token:match("^module:(.+)$")
  if mod then
    return (TOS.pkg and TOS.pkg.info and TOS.pkg.info(mod)) ~= nil
  end
  return true
end

function M.helpList(viewerTier)
  viewerTier = viewerTier or 0

  local aliasesOf = {}
  for name, meta in pairs(REGISTRY) do
    if meta.alias then
      aliasesOf[meta.alias] = aliasesOf[meta.alias] or {}
      table.insert(aliasesOf[meta.alias], name)
    end
  end
  local groups = { core = {}, admin = {}, extras = {} }
  for name, meta in pairs(REGISTRY) do
    if not meta.alias
       and (meta.tier or 0) <= viewerTier and M.needMet(NEEDS[name]) then
      local disp = name
      if aliasesOf[name] then
        table.sort(aliasesOf[name])
        disp = name .. " (" .. table.concat(aliasesOf[name], ", ") .. ")"
      end
      local g = groups[meta.category] or groups.extras
      g[#g + 1] = { name = disp, help = meta.help, manual = meta.manual }
    end
  end
  for _, g in pairs(groups) do
    table.sort(g, function(a, b) return a.name < b.name end)
  end
  return groups
end

function M.entry(name)
  return name and REGISTRY[name] or nil
end

local CATEGORY = setmetatable({}, {
  __index = function(_, k) local e = REGISTRY[k]; return e and e.category or nil end,
  __pairs = function()
    return function(_, k)
      local nk, ne = next(REGISTRY, k)
      while nk and not ne.category do nk, ne = next(REGISTRY, nk) end
      if nk then return nk, ne.category end
    end
  end,
})

function M.build(S, deps)
  local C        = {}
  local loaded   = {}

  local function isOOM(err)
    err = tostring(err or ""):lower()
    return err:find("memory", 1, true) ~= nil or err:find("buffer alloc", 1, true) ~= nil
  end
  local function nudgeGC()

    local K = _G._TOS and _G._TOS.kernel
    if K and K.gc then pcall(K.gc); return end
    if type(collectgarbage) == "function" then pcall(collectgarbage, "collect") end
  end

  local function loadCategory(cat)
    if loaded[cat] then return end
    local ok, mod = pcall(require, "shell.panels.commands." .. cat)
    if not ok and isOOM(mod) then

      nudgeGC()
      ok, mod = pcall(require, "shell.panels.commands." .. cat)
    end
    if not ok then
      local oom = isOOM(mod)
      local logMod = (S.K and S.K.getLog and S.K.getLog()) or nil
      if logMod and logMod.warn then
        logMod.warn("commands", "Failed to load category '" .. cat .. "': " .. tostring(mod))
      end

      if oom then
        local kb = ""

        local okC, computer = pcall(require, "computer")
        if okC and computer and computer.freeMemory then
          kb = string.format(" (%dKB free)", math.floor(computer.freeMemory() / 1024))
        end
        S.lastOut = { "'" .. cat .. "' commands need more memory than is free" .. kb
          .. " — free RAM (close tabs / reboot) and they'll load on next use.",
          (S.T and S.T.error) or nil }
      else
        loaded[cat] = true
      end
      return
    end

    local rok, rerr = pcall(mod, C, S, deps)
    if not rok then
      local logMod = (S.K and S.K.getLog and S.K.getLog()) or nil
      if logMod and logMod.warn then
        logMod.warn("commands", "Category '" .. cat .. "' register error: " .. tostring(rerr))
      end
    end
    loaded[cat] = true
  end

  --! RESCUE COMMANDS -- the escape hatch must not need the thing that broke.
  --!
  --! `reboot`, `shutdown` and `help` all live in the `core` category, which
  --! is the biggest command file in the tree. On a tight box it is exactly
  --! the file that fails to load: reading it wants a large contiguous
  --! buffer, and a machine at ~56 KB free has not got one. The operator was
  --! then told to "free some memory and try again" -- by freeing memory, or
  --! rebooting. Which is the command that just failed. Reported from a real
  --! machine, and it is a trap, not a message problem: the advice was
  --! correct and impossible to follow.
  --!
  --! So these four are served from HERE, out of the dispatcher, which is
  --! already loaded by the time any of this can happen. They are used only
  --! when the real one is absent, so the full versions win whenever they
  --! exist and this costs nothing on a healthy box. Deliberately minimal:
  --! every line of them is a line that has to work when nothing else does.
  --! (test_lowmem_rescue.lua)
  local RESCUE = {}
  do
    local function err(o, msg) o(msg, (S.T and S.T.error) or nil) end
    local function dim(o, msg) o(msg, (S.T and S.T.dim) or nil) end

    local function mayPowerOff(o)
      local okH, helpers = pcall(require, "shell.panels.helpers")
      if okH and helpers and helpers.canPowerOff then
        local ok, reason = helpers.canPowerOff(S)
        if not ok then err(o, tostring(reason)); return false end
        return true
      end
      if ((S and S.tier) or 0) < 2 then
        err(o, "Admin tier required to power off.")
        return false
      end
      return true
    end

    local function power(o, reboot)
      if not mayPowerOff(o) then return end
      dim(o, "(rescue: the core commands could not load, using the built-in)")
      local K = S.K
      if K then
        local fn = reboot and K.reboot or K.shutdown
        if fn then pcall(fn); return end
      end
      local okC, computer = pcall(require, "computer")
      if okC and computer and computer.shutdown then
        dim(o, "(kernel handle missing -- restarting without a clean flush)")
        pcall(computer.shutdown, reboot and true or false)
      else
        err(o, "Cannot reach the power controls at all.")
      end
    end

    RESCUE.reboot   = function(_, o) power(o, true) end
    RESCUE.shutdown = function(_, o) power(o, false) end

    RESCUE.help = function(_, o)
      err(o, "Command help is running in rescue mode: the full listing needs")
      err(o, "memory that is not free. Names only, from the registry.")
      local groups = M.helpList((S and S.tier) or 0)
      for _, cat in ipairs({ "core", "admin", "extras" }) do
        local g = groups[cat]
        if g and #g > 0 then
          local names = {}
          for _, e in ipairs(g) do names[#names + 1] = (e.name:match("^%S+") or e.name) end
          local line, W = "", (S and S.W or 80) - 2
          for _, n in ipairs(names) do
            if #line + #n + 2 > W then dim(o, line); line = "" end
            line = (line == "" ) and ("  " .. n) or (line .. "  " .. n)
          end
          if line ~= "" then dim(o, line) end
        end
      end
      dim(o, "'reboot' and 'shutdown' work from here too.")
    end

    RESCUE.mem = function(_, o)
      local okC, computer = pcall(require, "computer")
      if not (okC and computer and computer.freeMemory) then
        err(o, "Memory figures unavailable."); return
      end
      local free  = computer.freeMemory()
      local total = computer.totalMemory and computer.totalMemory() or 0
      o(string.format("Free: %dK of %dK  (rescue reading)",
        math.floor(free / 1024), math.floor(total / 1024)),
        (S.T and S.T.warning) or nil)
    end
  end

  return setmetatable({}, {
    __index = function(_, name)
      local cat = CATEGORY[name]
      if not cat then return nil end
      loadCategory(cat)

      local fn = C[name]
      if fn then return fn end

      return RESCUE[name]
    end,
    __newindex = function(_, k, v)

      C[k] = v
    end,

    __pairs = function()
      local seen = {}
      for _, cat in pairs(CATEGORY) do
        if not seen[cat] then seen[cat] = true; loadCategory(cat) end
      end
      return pairs(C)
    end,
  })
end

function M.commandNames()
  local out = {}
  for name in pairs(CATEGORY) do out[#out + 1] = name end
  table.sort(out)
  return out
end

function M.preloadAll(S, deps)
  local C = M.build(S, deps)

  local _ = C.help
  _ = C.flash
  _ = C.deploy
  return C
end

return M
