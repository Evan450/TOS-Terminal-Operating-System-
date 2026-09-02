local profile = {}

local securefs = nil
local usersmod = nil
local themeMod = nil
local envMod   = nil
local log      = nil
local serialize = nil

local PROFILE_FILE = ".profile.cfg"
local MAX_PROFILE_BYTES = 8192
local MAX_STARTUP_CMDS  = 16
local MAX_ALIASES       = 48

function profile.init(modules)
  securefs  = modules.securefs
  usersmod  = modules.users
  themeMod  = modules.theme
  envMod    = modules.env
  log       = modules.log
  serialize = modules.serialize or require("kernel.serialize")
end

local function profilePathFor(session)
  if not session or session.isKernel then return nil end
  if not session.home or session.home == "" or session.home == "/" then return nil end
  return session.home .. "/" .. PROFILE_FILE
end

local function defaults()
  return {
    name    = "default",

    theme   = nil,
    env     = {},
    startup = {},
    cwd     = nil,
    prompt  = nil,

    landing = nil,

    lang    = nil,
    aliases = {},
  }
end

local function sanitize(raw)
  local out = defaults()
  if type(raw) ~= "table" then return out end

  if type(raw.name) == "string" and #raw.name <= 32
     and raw.name:match("^[%w_%-]+$") then
    out.name = raw.name
  end

  if type(raw.theme) == "string" and #raw.theme <= 32
     and raw.theme:match("^[%w_%-]+$") then
    out.theme = raw.theme
  end

  if type(raw.env) == "table" then
    local n = 0
    for k, v in pairs(raw.env) do
      if type(k) == "string" and type(v) == "string"
         and #k <= 32 and #v <= 1024
         and k:match("^[%w_]+$") then
        out.env[k] = v
        n = n + 1
        if n >= 32 then break end
      end
    end
  end

  if type(raw.startup) == "table" then
    for i, cmd in ipairs(raw.startup) do
      if i > MAX_STARTUP_CMDS then break end
      if type(cmd) == "string" and #cmd <= 200 then

        if not cmd:find("[\n\r]") then
          out.startup[#out.startup + 1] = cmd
        end
      end
    end
  end

  if type(raw.cwd) == "string" and #raw.cwd <= 256 then
    out.cwd = raw.cwd
  end

  if type(raw.prompt) == "string" and #raw.prompt <= 200 then
    out.prompt = raw.prompt
  end

  if raw.landing == "desktop" or raw.landing == "shell"
     or raw.landing == "tiles" or raw.landing == "files" then
    out.landing = raw.landing
  end

  --! The NAME is restricted to the same character class a command name can
  --! have (no spaces, slashes or quotes), so a stored alias can never carry
  --! a second command, a path, or shell punctuation into the position where
  --! the executor reads a command name. The VALUE is free text but must be
  --! a single line — a newline would let one alias define two commands.
  --! Neither side grants privilege: the expansion is dispatched through the
  --! ordinary tier gates (see helpers.expandAlias).
  if type(raw.aliases) == "table" then
    local n = 0
    for k, v in pairs(raw.aliases) do
      if type(k) == "string" and type(v) == "string"
         and #k <= 32 and #v <= 200
         and k:match("^[%w_%-]+$")
         and not v:find("[\n\r]") then
        out.aliases[k:lower()] = v
        n = n + 1
        if n >= MAX_ALIASES then break end
      end
    end
  end

  if type(raw.lang) == "string" then
    local okI, i18nMod = pcall(require, "kernel.i18n")
    local valid = (okI and i18nMod and i18nMod.validCode)
      and i18nMod.validCode(raw.lang)
      or (#raw.lang >= 2 and #raw.lang <= 8 and raw.lang:match("^%l%l[%l%d_%-]*$") ~= nil)
    if valid then out.lang = raw.lang end
  end

  return out
end

function profile.load(session)
  session = session or (usersmod and usersmod.currentSession()) or nil
  if not session then return defaults(), false end
  local path = profilePathFor(session)
  if not path or not securefs then return defaults(), false end
  if not securefs.exists(path, session) then return defaults(), false end
  local data = securefs.readFile(path, session)
  if not data then return defaults(), false end
  if #data > MAX_PROFILE_BYTES then
    if log then log.warn("profile", "Profile file too large for " ..
      session.user .. " (" .. #data .. " bytes); using defaults") end
    return defaults(), false
  end
  local ok, raw = pcall(serialize.decode, data, { maxBytes = MAX_PROFILE_BYTES })
  if not ok or type(raw) ~= "table" then
    if log then log.warn("profile", "Corrupt profile for " .. session.user
      .. "; using defaults") end
    return defaults(), false
  end
  return sanitize(raw), true
end

function profile.save(p, session)
  session = session or (usersmod and usersmod.currentSession()) or nil
  if not session then return false, "no session" end
  local path = profilePathFor(session)
  if not path then return false, "no profile path (guest or no home)" end
  if not securefs then return false, "securefs not available" end
  local clean = sanitize(p or {})
  local encoded = serialize.encode(clean)
  if #encoded > MAX_PROFILE_BYTES then
    return false, "profile too large after sanitization"
  end
  return securefs.writeFile(path, encoded, session)
end

function profile.apply(p, opts)
  opts = opts or {}
  local session = opts.session or (usersmod and usersmod.currentSession()) or nil
  if not p then p = defaults() end

  local liveTheme = themeMod or (_G._TOS and _G._TOS.theme)
  if liveTheme and liveTheme.apply and p.theme then
    local saved = liveTheme.hasSavedTheme
      and liveTheme.hasSavedTheme(session) or false
    if not saved then
      pcall(liveTheme.apply, p.theme)
    end
  end

  if p.lang and p.lang ~= "" then
    local i18nMod = _G._TOS and _G._TOS.i18n
    if i18nMod and i18nMod.setLanguage then pcall(i18nMod.setLanguage, p.lang) end
  end

  if envMod and envMod.write then
    local procMod
    local okP, m = pcall(require, "kernel.process"); if okP then procMod = m end
    local cur = procMod and procMod.current and procMod.current() or nil
    if cur and cur.env then
      for k, v in pairs(p.env or {}) do
        cur.env[k] = v
      end
    end
  end

  return p.startup or {}, p
end

return profile
