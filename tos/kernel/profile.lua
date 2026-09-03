-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Configuration Profiles ║
-- ╚══════════════════════════════════════╝
-- Per-user "profile" that extends theme persistence to a broader set
-- of preferences: theme preset, environment variables to set at
-- shell start, startup commands to run, and a default working dir.
--
-- Schema (lives at ~/.profile.cfg, serialize-encoded):
--   {
--     name      = "default",        -- profile name (for switching)
--     theme     = "green",          -- a kernel.theme preset, or nil
--     env       = { PATH = "...", EDITOR = "edit" },
--     startup   = { "echo hi", "ps" },     -- commands run after login
--     cwd       = "/home/alice/work",      -- initial cwd override
--     prompt    = "$user@$host $cwd $ ",   -- prompt template
--     landing   = "tiles",                 -- which Home VIEW to land on:
--                                          -- "tiles"|"files" (and the older
--                                          -- "desktop"|"shell", still honoured)
--     lang      = "ru",                    -- UI language (kernel.i18n catalog)
--     aliases   = { ll = "ls -l" },        -- per-user command aliases
--   }
--
-- Storage path is per-user. Reads/writes go through securefs with the
-- caller's session, so a USER can edit only their own profile and an
-- ADMIN can edit anyone's via the regular ACL.
--
-- Profiles are NOT executable code — they're a data file that the
-- shell consults at startup. There's no "profile script" path because
-- that would just be a worse version of a startup command.

local profile = {}

local securefs = nil
local usersmod = nil
local themeMod = nil
local envMod   = nil
local log      = nil
local serialize = nil

local PROFILE_FILE = ".profile.cfg"
local MAX_PROFILE_BYTES = 8192     -- way more than any reasonable profile
local MAX_STARTUP_CMDS  = 16       -- cap to keep boot from hanging
local MAX_ALIASES       = 48       -- generous; the byte cap is the real limit

-- ============================================================
-- Init
-- ============================================================

function profile.init(modules)
  securefs  = modules.securefs
  usersmod  = modules.users
  themeMod  = modules.theme
  envMod    = modules.env
  log       = modules.log
  serialize = modules.serialize or require("kernel.serialize")
end

-- ============================================================
-- Path resolution
-- ============================================================

local function profilePathFor(session)
  if not session or session.isKernel then return nil end
  if not session.home or session.home == "" or session.home == "/" then return nil end
  return session.home .. "/" .. PROFILE_FILE
end

-- ============================================================
-- Defaults — what a missing/blank profile resolves to.
-- ============================================================

local function defaults()
  return {
    name    = "default",
    -- nil = "no preference": profile.apply leaves the theme alone.
    -- (The old defaults() filled in "default" here, so a profile file
    -- saved for any other reason would have force-reset the user's
    -- theme at every login once profile-theme application worked.)
    theme   = nil,
    env     = {},
    startup = {},
    cwd     = nil,
    prompt  = nil,  -- shell falls back to its hardcoded default
    -- nil = "no preference": the panels shell picks its own default
    -- (root lands on the Shell tab, everyone else on the Desktop).
    landing = nil,
    -- nil = "no preference": the system default language stands.
    lang    = nil,
    aliases = {},
  }
end

-- ============================================================
-- Validation
-- ============================================================

local function sanitize(raw)
  local out = defaults()
  if type(raw) ~= "table" then return out end

  -- name: short string
  if type(raw.name) == "string" and #raw.name <= 32
     and raw.name:match("^[%w_%-]+$") then
    out.name = raw.name
  end

  -- theme: must be a known preset (if themeMod is loaded). We don't
  -- enforce the preset name here — themeMod's own preset list does
  -- that on apply.
  if type(raw.theme) == "string" and #raw.theme <= 32
     and raw.theme:match("^[%w_%-]+$") then
    out.theme = raw.theme
  end

  -- env: string -> string map, key/value bounded.
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

  -- startup: array of command strings, each bounded
  if type(raw.startup) == "table" then
    for i, cmd in ipairs(raw.startup) do
      if i > MAX_STARTUP_CMDS then break end
      if type(cmd) == "string" and #cmd <= 200 then
        -- Strip leading whitespace / refuse newlines (one command per slot).
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

  -- landing: which Home VIEW to open on. It named a SURFACE before the
  -- Desktop and the Shell were merged into one tab, and both spellings
  -- are accepted so that no saved profile needs migrating — "desktop"
  -- and "tiles" mean the same view, as do "shell" and "files". Anything
  -- else means "no preference", so a corrupt value can't wedge login
  -- into nowhere.
  if raw.landing == "desktop" or raw.landing == "shell"
     or raw.landing == "tiles" or raw.landing == "files" then
    out.landing = raw.landing
  end

  -- aliases: name -> command-line map, both sides bounded.
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

  -- lang: validated by the i18n module's own code rule when available
  -- (the pattern doubles as path-traversal protection for the catalog
  -- filename); a conservative local copy otherwise.
  if type(raw.lang) == "string" then
    local okI, i18nMod = pcall(require, "kernel.i18n")
    local valid = (okI and i18nMod and i18nMod.validCode)
      and i18nMod.validCode(raw.lang)
      or (#raw.lang >= 2 and #raw.lang <= 8 and raw.lang:match("^%l%l[%l%d_%-]*$") ~= nil)
    if valid then out.lang = raw.lang end
  end

  return out
end

-- ============================================================
-- Public API
-- ============================================================

--- Load the profile for `session`. Returns the (sanitized) profile
--- table, plus a boolean indicating whether a profile file exists.
--- A missing profile returns defaults() (with `exists=false`) so the
--- caller can use the result unconditionally.
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

--- Save a sanitized profile back to disk for `session`.
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

--- Apply a loaded profile at shell start. Sets the theme override,
--- writes env vars into the calling process, and returns the startup
--- commands (the shell runs them itself so they're executed in the
--- shell's command-loop context, not here).
function profile.apply(p, opts)
  opts = opts or {}
  local session = opts.session or (usersmod and usersmod.currentSession()) or nil
  if not p then p = defaults() end

  -- Theme. Resolve themeMod late so we pick up the kernel-loaded
  -- module even if profile.init ran before theme.init.
  -- (REV-2: this previously called liveTheme.applyPreset, a function
  -- kernel.theme never exported — its API is theme.apply — so the
  -- profile's theme field silently never applied.)
  -- Precedence: an explicit `theme set` choice saved as ~/.theme.cfg
  -- (which can carry per-key color overrides) is more specific than
  -- the profile's coarse preset name, and the kernel applies it just
  -- before this runs — so the profile theme only fills the gap when
  -- nothing is saved.
  local liveTheme = themeMod or (_G._TOS and _G._TOS.theme)
  if liveTheme and liveTheme.apply and p.theme then
    local saved = liveTheme.hasSavedTheme
      and liveTheme.hasSavedTheme(session) or false
    if not saved then
      pcall(liveTheme.apply, p.theme)
    end
  end

  -- Language: the per-user preference overrides the system default.
  -- (The active catalog is module-global for now — on a multi-seat box
  -- the last login wins; see the kernel.i18n header.)
  if p.lang and p.lang ~= "" then
    local i18nMod = _G._TOS and _G._TOS.i18n
    if i18nMod and i18nMod.setLanguage then pcall(i18nMod.setLanguage, p.lang) end
  end

  -- Env vars: write into the current process's env so subprocesses
  -- inherit. Don't touch system defaults (would require admin).
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
