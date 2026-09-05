-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Shell - Command Dispatcher                          ║
-- ║                                                          ║
-- ║  Used to be one 2200-line file with 60+ commands inline. ║
-- ║  v1.3 split it into three category modules under         ║
-- ║  /tos/shell/panels/commands/:                            ║
-- ║                                                          ║
-- ║    core.lua    32 frequently-used commands               ║
-- ║                (help, ls, cat, mem, ps, env, ...)        ║
-- ║    admin.lua   21 privileged sysadmin commands           ║
-- ║                (flash, theme, useradd, mount, lua, ...)  ║
-- ║    extras.lua  13 rarely-used / heavy commands           ║
-- ║                (mod, disk, deploy, redstone, chat, ...)  ║
-- ║                                                          ║
-- ║  Lazy-load: a category is `require`d the first time one  ║
-- ║  of its commands is accessed. On a typical session that  ║
-- ║  uses only fs + system commands, admin and extras never  ║
-- ║  parse — saving the Lua compile cost (~600 LOC each) and ║
-- ║  the 60+ closures they would otherwise allocate.         ║
-- ║                                                          ║
-- ║  Aliases (C.dir = C.ls, C.rs = C.redstone, etc.) live in ║
-- ║  the same category as their target so a single load      ║
-- ║  registers both sides.                                   ║
-- ╚══════════════════════════════════════════════════════════╝

local M = {}

-- ============================================================
-- Command → category map
-- ============================================================
-- Every name the shell can dispatch through C[name] must have
-- an entry here, INCLUDING aliases. The values are category file
-- names (without .lua extension) under shell.panels.commands.
--
-- Keep in sync with the actual C.* assignments in each subfile.
-- A self-test in M.preloadAll fires every category to surface a
-- registration error before users hit it via the shell.

-- ─────────────────────────────────────────────────────────────
-- Unified registry (CORE 5)
-- ─────────────────────────────────────────────────────────────
-- Single source of truth for every command's metadata:
--   category  — file ownership (drives lazy load)
--   tier      — minimum tier the command requires
--                 0 = GUEST   any logged-in user
--                 1 = USER    regular accounts
--                 2 = ADMIN   sysadmin-only
--                 3 = ROOT    root only
--   help      — one-line description (used by `help`, panels search)
--
-- The dispatcher uses `category` for lazy loading; the help/list
-- system uses `tier` + `help` to render per-tier menus. Adding a new
-- command means ONE edit here AND the function body — no third place
-- to forget to update. Tier guards inside command bodies (helpers
-- adminOnly/rootOnly from #SEC C7) remain belt-and-braces.
local REGISTRY = {
  -- ── core: frequently-used commands + aliases ─────────────
  -- `alias = "<canonical>"` marks a second name for the same command:
  -- it still DISPATCHES (the category file assigns both), but helpList
  -- collapses it onto the canonical row ("ls (dir)") so the visible
  -- command surface stays small. (v1.4.0 consolidation pass.)
  help     = { category = "core", tier = 0, help = "Quick help (install-aware); 'man' for detail" },
  man      = { category = "core", tier = 0, help = "Detailed manual page for a command/topic" },
  why      = { category = "core", tier = 0, help = "Explain a 'permission denied' (or what a command needs)" },
  screendump = { category = "core", tier = 1, help = "Capture this screen to a text file (for bug reports)" },
  crash    = { category = "core", tier = 2, help = "List/read crash post-mortems saved in /var/crash" },
  about    = { category = "core", tier = 0, help = "OS info: version, codename, hardware summary" },
  -- `ver` was folded into `about` in v1.4.0, but help still advertised it
  -- and the lazy-loader no longer knew the name — so typing it said
  -- "unknown command". Restore it as a proper alias (registry entry maps
  -- the name to the core category + collapses it in help; C.ver = C.about
  -- in core.lua does the dispatch).
  ver      = { category = "core", tier = 0, help = "TOS version info", alias = "about" },
  echo     = { category = "core", tier = 0, help = "Print arguments" },
  -- The intrusive counterpart to echo: a modal dialog on every seat. Tier 1
  -- (not guest) — interrupting everyone at the machine is a real action, and
  -- kernel.notify's rate limits are the floor under it.
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
  -- (v1.4.0 consolidation: `launcher`/`apps` retired — the Desktop is
  -- the menu surface now; ~/.launcher.cfg entries appear as tiles and
  -- the tape toolbox lives on as `tape-menu`. The launcher ENGINE
  -- stays in shell/launcher.lua for kiosk mode.)
  ["tape-menu"] = { category = "core", tier = 1, help = "Personal command menu from your identity tape (keycard)" },
  desktop  = { category = "core", tier = 0, help = "Open the Desktop: app tiles for built-ins + installed packages" },
  clip     = { category = "core", tier = 0, help = "Show, set or clear the text clipboard" },
  settings = { category = "core", tier = 0, help = "Open the Settings app (theme, status bar, desktop, system)" },
  lang     = { category = "core", tier = 0, help = "Show or set the UI language (data catalogs in /usr/lang)" },
  tree     = { category = "core", tier = 0, help = "Show directory tree" },
  whoami   = { category = "core", tier = 0, help = "Show current user" },
  passwd   = { category = "core", tier = 0, help = "Change own password" },
  -- sudo is USER+ (guests can't elevate); its own body prompts for the
  -- elevation password and enforces the cap. `sudo setup/off` self-gate root.
  sudo     = { category = "core", tier = 1, help = "Run a command with elevated privileges (sudo <cmd> | -s | -k | setup)" },
  logout   = { category = "core", tier = 0, help = "Log out of this session" },
  -- The two shells, each reachable from the other. Both are tier 0: which
  -- interface you use is not a privilege, and the CLI is specifically what
  -- you want available when the full one is misbehaving.
  cli      = { category = "core", tier = 0, help = "Drop to the command-line shell (same commands, no panels)" },
  tui      = { category = "core", tier = 0, help = "Return to the full panels interface" },
  reboot   = { category = "core", tier = 2, help = "Reboot the system" },
  shutdown = { category = "core", tier = 2, help = "Shut the system down" },
  -- `which` answers "three things could own this name — which one runs?"
  -- (built-in vs package command vs /usr/bin program). Sibling to `why`,
  -- which answers "and why was I refused?".
  which    = { category = "core", tier = 0, help = "Show what a command name resolves to (built-in, package, or program)" },
  alias    = { category = "core", tier = 0, help = "Per-user command aliases: 'alias' lists, 'alias ll ls -l' defines" },
  unalias  = { category = "core", tier = 0, help = "Remove a command alias" },
  env      = { category = "core", tier = 0, help = "Show environment variables" },
  export   = { category = "core", tier = 0, help = "Set an environment variable" },
  set      = { category = "core", tier = 0, help = "Set an environment variable", alias = "export" },

  -- ── admin: privileged commands ───────────────────────────
  kill     = { category = "admin", tier = 2, help = "Kill a process by PID" },
  fg       = { category = "admin", tier = 2, help = "Bring a process to foreground" },
  -- srm is the front door over doctor + verify + the boot fixer pass, and the
  -- only command that can report a POST fault the EEPROM half caught. Tier 1
  -- because status/scan/health are read-only; baseline/repair/restore
  -- self-gate to admin in-body (same split `optimize` uses).
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
  cron     = { category = "admin", tier = 2, help = "Manage cron jobs" },  -- #SEC M-9 — matches in-body adminOnly gate (was 1)

  -- ── extras: rare / heavy commands + aliases ──────────────
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
  -- Base-image wizard, present whether or not either cluster package is: its
  -- first job is telling you WHICH one this machine needs. Not named
  -- `cluster` — a registry name shadows /usr/bin, which would break the
  -- Master's own CLI once cluster-master is installed.
  ["cluster-setup"] = { category = "extras", tier = 3, help = "Set this machine up as a cluster Master or Manager (guided; works before anything is installed)" },
  rbmk     = { category = "extras", tier = 1, help = "RBMK reactor supervisor (needs the 'rbmk-control' add-on): survey/status/limits/scram" },
  rsh      = { category = "extras", tier = 2, help = "Remote shell client" },
  scp      = { category = "extras", tier = 1, help = "Network file copy" },
  screen   = { category = "extras", tier = 1, help = "Seat/screen info; 'screen res <auto|max|WxH>' sets resolution" },
  -- ext stubs (lazy-load via shell.ext on first use):
  net      = { category = "extras", tier = 1, help = "Network admin (trust, peers, servers, ports)" },
  ping     = { category = "extras", tier = 1, help = "Network ping" },
  hostname = { category = "extras", tier = 0, help = "Show device type + hostname; set the name with 'hostname <name>'" },
  config   = { category = "extras", tier = 2, help = "Edit /etc/tos.cfg" },
  battery  = { category = "extras", tier = 0, help = "Power management info" },
  internet = { category = "extras", tier = 1, help = "Internet card: status, a test fetch, and the machine-wide on/off" },
  audio    = { category = "extras", tier = 1, help = "Audio feedback controls" },
}

-- ============================================================
-- Install-aware help: per-command dependency tokens
-- ============================================================
-- A built-in is hidden from `help` (and the run path can warn) when its
-- dependency isn't present on THIS machine — so you never see `chat`
-- without a modem or `tape` without the module. Module/package commands
-- are already dynamic (they only exist when installed), so this table
-- only needs to gate the optional built-ins. Tokens:
--   "net"/"swap"/"audio"/"compat"/"cluster" — that subsystem is loaded
--   "component:<type>"  — an OC component of <type> is attached
--   "module:<name>"     — a module/package providing <name> is installed
--   "inventory"         — any inventory-ish peripheral
local NEEDS = {
  net = "net", ping = "net", chat = "net", rsh = "net", scp = "net",
  -- Mail is an ADD-ON. The base image keeps only the privileged stub that
  -- hands the package the shell's display and session (see extras.lua), and
  -- must not ADVERTISE mail until the package is actually installed — no
  -- tile, no help row, nothing. Both tokens: the package to exist, the
  -- network to carry it.
  mail = { "module:mail", "net" },
  -- The Intercom needs the mesh to tell anyone; a tape drive only adds the
  -- voice, so `net` (not the drive) is what gates the command being useful.
  intercom = "net",
  -- `swap` is gone from here: the command was folded into `optimize swap`
  -- in v1.4.0, so NEEDS.swap keyed a name helpList can never look up. The
  -- "swap" TOKEN is still live -- core.lua's help asks needMet("swap")
  -- directly to decide whether to show the optimize row.
  audio = "audio", compat = "compat", jbod = "jbod",
  -- netfs is useless without a mesh: both halves (serving an export,
  -- mounting someone else's) are network operations.
  netfs = "net",
  compress = "component:data", decompress = "component:data",
  redstone = "component:redstone", rs = "component:redstone",
  robot = "component:robot",
  inventory = "inventory", inv = "inventory",
  tape = "module:tape",
  ["tape-menu"] = "component:tape_drive",
  -- Hidden from `help` on the overwhelming majority of machines, which
  -- have no internet card. `pkg fetch` is gated by the same hardware, but
  -- stays visible under `pkg` because that is where an operator goes
  -- looking for it.
  internet = "component:internet",
}
M.NEEDS = NEEDS

--- Is a `needs` token satisfied on the live system? Fails OPEN on an
--- unknown token so a typo never hides a real command.
function M.needMet(token)
  if not token then return true end
  -- A command can depend on more than one thing at once. `mail` is the case
  -- that forced it: it needs the PACKAGE installed to exist at all, and a
  -- network to be any use. It was gated on the network alone, so vanilla TOS
  -- showed a Mail tile on every networked box and answered a click with "not
  -- installed" — the base image advertising a package it does not have.
  -- Every token in a list must hold.
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

--- Commands visible to `viewerTier` on THIS machine, grouped by category.
--- Filters by tier AND live availability. Each entry: { name, help, manual }.
--- Alias entries collapse onto their canonical row — "ls (dir)" — so a
--- dozen second names stop doubling the visible surface (v1.4.0).
function M.helpList(viewerTier)
  viewerTier = viewerTier or 0
  -- Gather alias names per canonical first.
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

--- A single command's registry metadata: { category, tier, help, manual }, or
--- nil for an unknown name. Used by `help <cmd>` to give EVERY command a focused
--- help entry (one-liner + tier + category) even without a bespoke man page.
function M.entry(name)
  return name and REGISTRY[name] or nil
end

-- Back-compat: derive the old CATEGORY view from REGISTRY so callers
-- that haven't migrated to the registry yet still work.
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

-- ============================================================
-- M.build(S, deps) -> C
-- ============================================================
-- Returns a metatable-backed command table. The first access to
-- C.someCmd triggers loading of the relevant category subfile,
-- which registers all of that category's commands (and aliases).
-- Subsequent accesses hit the underlying table directly.
--
-- If a name isn't in CATEGORY (typo, deleted command, module-
-- registered command), __index returns nil and the shell's exec
-- path can fall through to the modules.getCommand path.

function M.build(S, deps)
  local C        = {}    -- the actual command table (lazy-populated)
  local loaded   = {}    -- category name → true once registered

  -- An out-of-memory failure is TRANSIENT — `core.lua` is a large file and
  -- reading it needs a big contiguous buffer, which can fail on a minimal box
  -- (e.g. a T1 GPU with no data card sitting at ~250KB free). Distinguish it
  -- from a real (code) load error so we can (a) nudge a GC and retry, and
  -- (b) NOT cache the failure: a later access, once RAM frees up, self-heals.
  local function isOOM(err)
    err = tostring(err or ""):lower()
    return err:find("memory", 1, true) ~= nil or err:find("buffer alloc", 1, true) ~= nil
  end
  local function nudgeGC()
    -- Prefer the kernel's guarded GC (it knows whether the host exposes
    -- collectgarbage); fall back to a local guarded call.
    local K = _G._TOS and _G._TOS.kernel
    if K and K.gc then pcall(K.gc); return end
    if type(collectgarbage) == "function" then pcall(collectgarbage, "collect") end
  end

  local function loadCategory(cat)
    if loaded[cat] then return end
    local ok, mod = pcall(require, "shell.panels.commands." .. cat)
    if not ok and isOOM(mod) then
      -- Transient low-memory read failure: free what we can and try once more.
      nudgeGC()
      ok, mod = pcall(require, "shell.panels.commands." .. cat)
    end
    if not ok then
      local oom = isOOM(mod)
      local logMod = (S.K and S.K.getLog and S.K.getLog()) or nil
      if logMod and logMod.warn then
        logMod.warn("commands", "Failed to load category '" .. cat .. "': " .. tostring(mod))
      end
      -- Surface a plain-English reason in the shell so the operator doesn't see
      -- bare "command not found" for every core command and assume the install
      -- is broken. For an OOM, leave the category UNcached so the next command
      -- retries after memory frees (reboot / closing tabs); for a genuine code
      -- error, cache it (retrying won't help) to avoid a per-keystroke retry storm.
      if oom then
        local kb = ""
        -- This file requires nothing at the top (it is the dispatcher, and
        -- staying import-free is what keeps it cheap to load), so `computer`
        -- was a nil GLOBAL here and the `if` never fired: the free-RAM figure
        -- — the one number that tells an operator how much they need to free
        -- — was silently absent from every OOM message. Ask for it here.
        -- (test_global_leaks.lua)
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
    -- Each subfile returns a registration function.
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

    -- The same gate the real commands use, with a fallback that does not
    -- need a module load: helpers is normally already in package.loaded, but
    -- "normally" is not a safety argument when we are here because a load
    -- failed. Never fails OPEN -- an unresolvable tier denies.
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

    -- Prefer the kernel's clean path (it flushes the log and clears the
    -- dirty bit). Fall back to the raw component call only if the kernel
    -- handle has gone: an unclean restart costs a repair pass next boot,
    -- which is a far better outcome than a machine that cannot be restarted.
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

    -- The registry is a plain table in this file, so `help` can list every
    -- command without loading a single category.
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

    -- How bad is it? The number that decides whether to close a tab or
    -- reboot, and it is one component call.
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
      -- After load, the command lives in C. If it didn't (mismatch
      -- between CATEGORY map and actual subfile contents), return
      -- nil — shell handles missing commands gracefully.
      local fn = C[name]
      if fn then return fn end
      -- The category is not there. If this is one of the commands an
      -- operator needs to GET OUT of that, hand back the built-in rather
      -- than nil: nil is what turned a low-memory box into an unrebootable
      -- one. Checked after the real lookup, so a loaded category always wins.
      return RESCUE[name]
    end,
    __newindex = function(_, k, v)
      -- Allow direct sets (e.g. modules registering ad-hoc commands).
      C[k] = v
    end,
    -- Lua 5.3+ honors __pairs; older versions ignore it, in which
    -- case `pairs(C-via-dispatcher)` only sees already-loaded
    -- categories. The shell doesn't rely on full iteration, but
    -- make it correct when supported by force-loading first.
    __pairs = function()
      local seen = {}
      for _, cat in pairs(CATEGORY) do
        if not seen[cat] then seen[cat] = true; loadCategory(cat) end
      end
      return pairs(C)
    end,
  })
end

-- ============================================================
-- M.commandNames() -> array of all known command names
-- ============================================================
-- Static list — doesn't trigger any category loads. Use this for
-- tab completion, help-list rendering, etc., when you need the
-- full set without paying the load cost.

function M.commandNames()
  local out = {}
  for name in pairs(CATEGORY) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- ============================================================
-- M.preloadAll(S, deps) — convenience for tests / verification
-- ============================================================
-- Forces every category to load. Lets tests assert that the
-- registration of each subfile actually succeeds at runtime.

function M.preloadAll(S, deps)
  local C = M.build(S, deps)
  -- Touching one command per category is enough to trigger load.
  local _ = C.help     -- core
  _ = C.flash          -- admin
  _ = C.deploy         -- extras
  return C
end

return M
