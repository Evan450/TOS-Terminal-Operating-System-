-- ╔══════════════════════════════════════╗
-- ║  TOS Shell - Kiosk Mode              ║
-- ╚══════════════════════════════════════╝
-- A read-only / locked-down shell wrapper for public terminals. Only
-- pre-configured commands are accepted; everything else is refused
-- with a generic "not available in kiosk mode" message.
--
-- Config lives at /etc/kiosk.cfg (admin-writable). Schema:
--
--   {
--     -- list of commands the kiosk user can run, by name.
--     -- These resolve against the normal shell command table; the
--     -- kiosk dispatcher just gates the dispatch.
--     allowed = { "help", "ls", "cat", "date", "time" },
--
--     -- shown at the top of the kiosk shell every redraw.
--     banner  = "Welcome to the front-desk kiosk — type 'help' for options.",
--
--     -- optional canned "shortcuts": these appear as menu items, and
--     -- when selected (number key or label) the kiosk runs the
--     -- corresponding command line. Lets operators expose curated
--     -- workflows without teaching kiosk users to type commands.
--     menu = {
--       { label = "Show today's date", cmd = "date" },
--       { label = "Building map",      cmd = "cat /public/map.txt" },
--     },
--
--     -- if true, idle timeout returns to the menu screen (default 60s)
--     idleSeconds = 60,
--   }
--
-- Activation: kiosk mode is triggered when the logged-in user is the
-- special account "kiosk" (TIER.GUEST). Alternatively, an admin can
-- launch any user into kiosk via `kiosk start` from a shell — useful
-- for testing the config.
--
-- Security posture:
--   * Kiosk runs under the calling user's session — the C8 session-
--     binding fixes still apply.
--   * The allowed list is consulted BEFORE the registry/dispatcher,
--     so even if a registry entry exists for a privileged command,
--     it won't run unless explicitly listed.
--   * No shell history is preserved across sessions; the kiosk user
--     has no home dir by default (uses /public as home).

local kiosk = {}

local DEFAULT_CFG = {
  allowed = { "help", "ls", "cat", "date", "time", "echo", "whoami", "logout" },
  banner  = "TOS Kiosk Mode",
  menu    = {},
  idleSeconds = 60,
}

local CONFIG_PATH = "/etc/kiosk.cfg"
local MAX_CFG_BYTES = 8192

-- ============================================================
-- Config loading
-- ============================================================

local function loadConfig(securefs, session)
  local cfg = {}
  for k, v in pairs(DEFAULT_CFG) do cfg[k] = v end
  if not securefs or not securefs.exists(CONFIG_PATH, session) then
    return cfg
  end
  local raw = securefs.readFile(CONFIG_PATH, session)
  if not raw or #raw == 0 or #raw > MAX_CFG_BYTES then return cfg end
  local serialize = require("kernel.serialize")
  local ok, parsed = pcall(serialize.decode, raw, { maxBytes = MAX_CFG_BYTES })
  if not ok or type(parsed) ~= "table" then return cfg end

  -- Validate fields.
  if type(parsed.allowed) == "table" then
    cfg.allowed = {}
    for _, name in ipairs(parsed.allowed) do
      if type(name) == "string" and name:match("^[%w_%-]+$") and #name <= 32 then
        cfg.allowed[#cfg.allowed + 1] = name
      end
    end
  end
  if type(parsed.banner) == "string" and #parsed.banner <= 200 then
    cfg.banner = parsed.banner
  end
  if type(parsed.menu) == "table" then
    cfg.menu = {}
    for _, item in ipairs(parsed.menu) do
      if type(item) == "table"
         and type(item.label) == "string" and #item.label <= 60
         and type(item.cmd) == "string"   and #item.cmd <= 200
         and not item.cmd:find("[\n\r]") then
        cfg.menu[#cfg.menu + 1] = { label = item.label, cmd = item.cmd }
      end
      if #cfg.menu >= 12 then break end  -- one screen of menu items
    end
  end
  if type(parsed.idleSeconds) == "number"
     and parsed.idleSeconds >= 10 and parsed.idleSeconds <= 3600 then
    cfg.idleSeconds = parsed.idleSeconds
  end
  return cfg
end

-- ============================================================
-- Allowed-command check
-- ============================================================

local function makeAllowedLookup(list)
  local set = {}
  for _, name in ipairs(list) do set[name:lower()] = true end
  return set
end

-- ============================================================
-- Display rendering
-- ============================================================

local function clearScreen(display, T)
  display.clear(T.bg)
end

local function drawHeader(display, T, banner)
  local W = display.getSize()
  display.fill(1, 1, W, 1, " ", T.bar_fg or T.fg, T.bar_bg or T.bg)
  display.set(1, 1, " " .. banner:sub(1, W - 2), T.bar_fg or T.fg, T.bar_bg or T.bg)
end

local function drawMenu(display, T, menu, banner)
  clearScreen(display, T)
  drawHeader(display, T, banner)
  local row = 3
  display.set(2, row, "Available options:", T.title or T.fg, T.bg)
  row = row + 2
  for i, item in ipairs(menu) do
    display.set(2, row, string.format(" [%d] %s", i, item.label),
      T.fg, T.bg)
    row = row + 1
  end
  if #menu == 0 then
    display.set(2, row, "  (no menu items configured — use the prompt below)",
      T.dim or T.fg, T.bg)
    row = row + 1
  end
  row = row + 1
  display.set(2, row, "Type a command, or press a number for a menu item.",
    T.dim or T.fg, T.bg)
  display.set(2, row + 1, "Press Ctrl+D to log out.",
    T.dim or T.fg, T.bg)
  return row + 3  -- next free row, used by prompt
end

-- ============================================================
-- Public API
-- ============================================================

--- Run the kiosk shell. Returns when the user logs out.
function kiosk.run(kernel, token)
  local display = kernel.getDisplay and kernel.getDisplay() or kernel.D or _G._TOS.display
  local usersmod = _G._TOS.users
  local securefs = _G._TOS.securefs

  local session = usersmod.getSession(token)
  if not session then return end

  local cfg = loadConfig(securefs, session)
  local allowedSet = makeAllowedLookup(cfg.allowed)

  -- Lazy-load the regular command table so we can dispatch into it
  -- when an allowed command fires. The kiosk doesn't define its own
  -- implementations — it just gates which existing implementations
  -- are reachable.
  local commandsMod = require("shell.panels.commands")
  local helpers     = require("shell.panels.helpers")

  -- Build a minimal S/deps table that the regular command modules expect.
  -- The kiosk shell deliberately uses a TRIMMED set of helpers: no
  -- editor, no panels, no background tasks.
  local T = display.getTheme()
  local W, H = display.getSize()
  local kioskOutputs = {}  -- collected lines for current command
  local function outLine(line, color)
    kioskOutputs[#kioskOutputs + 1] = { tostring(line), color or T.fg }
  end

  local S = {
    K = kernel, U = usersmod,
    -- #SEC — use securefs (NOT the raw _G._TOS.fs). The command bodies
    -- call F.readFile/list directly; with the raw fs they bypassed every
    -- ACL, so a default-allowed `cat` let a GUEST kiosk user read
    -- /etc/users.dat, /etc/trust.dat, or any home dir. securefs resolves
    -- the seat's bound session (kiosk runs in a proc spawned with `token`)
    -- and enforces per-user permissions on every op.
    F = securefs or _G._TOS.fs,
    P = _G._TOS.process or _G._TOS.proc,
    D = display, T = T, W = W, H = H,
    SC = _G._TOS.config, NM = _G._TOS.net,
    -- st must be the TOKEN (helpers.sessionOf -> U.getSession(token)), not
    -- the session object — the rest of the command layer assumes a token.
    who = session.user, st = token,
    tier = session.tier, userTier = session.tier,
    cmdHistory = {}, lastOut = nil,
  }
  local deps = {
    rp = function(p)
      -- Resolve relative paths against the kiosk user's home.
      if p:sub(1, 1) == "/" then return p end
      return (session.home or "/") .. "/" .. p
    end,
    -- Real ACL checks against the kiosk session (was: stubbed always-true,
    -- which combined with the raw fs to expose the whole disk).
    canRead   = function(path, o) return helpers.canAccess(S, path, "r", o) end,
    -- Kiosk is read-only regardless of the user's tier: deny writes
    -- outright (defence-in-depth on top of securefs).
    canWrite  = function(_, o)
      if o then o("Kiosk mode is read-only.", T.error or T.fg) end
      return false
    end,
    canAccess = function(path, mode, o)
      if mode == "w" then
        if o then o("Kiosk mode is read-only.", T.error or T.fg) end
        return false
      end
      return helpers.canAccess(S, path, mode, o)
    end,
    adminOnly = function() return false end,  -- no admin commands in kiosk
    rootOnly  = function() return false end,
    refreshBrowser = function() end,
    makeProgramEnv = function() return {} end,
  }
  local CTable = commandsMod.build(S, deps)

  local function runOne(line)
    kioskOutputs = {}
    local parts = {}
    for w in line:gmatch("%S+") do parts[#parts + 1] = w end
    if #parts == 0 then return end
    local name = parts[1]:lower()
    if not allowedSet[name] then
      outLine("Command not available in kiosk mode: " .. name, T.error or T.fg)
      return
    end
    local fn = CTable[name]
    if not fn then
      outLine("Command unavailable.", T.warning or T.fg)
      return
    end
    local args = {}
    for i = 2, #parts do args[#args + 1] = parts[i] end
    local ok, err = pcall(fn, args, outLine)
    if not ok then outLine("Error: " .. tostring(err), T.error or T.fg) end
  end

  -- ── Input loop ──────────────────────────────────────
  local computer = require("computer")
  while true do
    local nextRow = drawMenu(display, T, cfg.menu, cfg.banner)

    -- Render any output lines from the previous command underneath the menu.
    for i, ln in ipairs(kioskOutputs) do
      if nextRow + i > H - 2 then break end
      display.set(2, nextRow + i - 1, ln[1]:sub(1, W - 3), ln[2] or T.fg, T.bg)
    end

    -- Prompt at the very bottom.
    local promptRow = H
    display.fill(1, promptRow, W, 1, " ", T.fg, T.bg)
    display.set(1, promptRow, "kiosk> ", T.prompt or T.fg, T.bg)

    local buf = ""
    local lastInputAt = computer.uptime()
    while true do
      display.fill(8, promptRow, W - 8, 1, " ", T.fg, T.bg)
      display.set(8, promptRow, buf .. "_", T.fg, T.bg)
      local sig, _, char, code = computer.pullSignal(1)
      if sig == "key_down" then
        lastInputAt = computer.uptime()
        if code == 28 then
          break  -- Enter — execute below
        elseif code == 14 then
          if #buf > 0 then buf = buf:sub(1, -2) end
        elseif char == 4 then
          -- Ctrl+D: log out
          if usersmod.logout then usersmod.logout(token) end
          return
        elseif char and char >= 49 and char <= 57 then
          -- Number key → menu item
          local idx = char - 48
          local item = cfg.menu[idx]
          if item then buf = item.cmd; break end
        elseif char and char >= 32 and char < 127 and #buf < 80 then
          buf = buf .. string.char(char)
        end
      else
        -- Idle timeout: bounce back to menu when user wanders off.
        if computer.uptime() - lastInputAt > cfg.idleSeconds then
          buf = ""
          kioskOutputs = {}
          break
        end
      end
    end
    if #buf > 0 then runOne(buf) end
  end
end

return kiosk
