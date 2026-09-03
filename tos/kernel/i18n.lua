-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Kernel - i18n (language catalogs)               ║
-- ║                                                      ║
-- ║  Community-translatable UI text WITHOUT touching     ║
-- ║  code. Every call site keeps its English inline:     ║
-- ║                                                      ║
-- ║    i18n.t("login.username", "Username:")             ║
-- ║                                                      ║
-- ║  and a catalog merely overrides keys it knows. So:   ║
-- ║   • no catalog / missing key / corrupt file          ║
-- ║       -> exact current English behaviour, always;    ║
-- ║   • a PARTIAL translation is valid by design         ║
-- ║       (untranslated keys fall back per-key);         ║
-- ║   • translators edit ONE data file, never code.      ║
-- ║                                                      ║
-- ║  Catalogs are DATA at /usr/lang/<code>.lang —        ║
-- ║  kernel.serialize table literals (comments allowed,  ║
-- ║  parsed by the safe decoder, never load()ed):        ║
-- ║                                                      ║
-- ║    return {                                          ║
-- ║      meta = { code = "ru", name = "Русский" },       ║
-- ║      strings = {                                     ║
-- ║        ["login.username"] = "Имя пользователя:",     ║
-- ║      },                                              ║
-- ║    }                                                 ║
-- ║                                                      ║
-- ║  Common packs may ship in the base image; rarer ones ║
-- ║  install as ordinary pkg packages that just drop a   ║
-- ║  file into /usr/lang (no special pkg support).       ║
-- ║                                                      ║
-- ║  Selection: /etc/tos.cfg `language` is the system    ║
-- ║  default (applies from boot, incl. the login         ║
-- ║  screen); a per-user profile `lang` overrides at     ║
-- ║  login. NOTE: the active catalog is currently        ║
-- ║  system-wide — on a multi-seat box the last login's  ║
-- ║  preference wins. Per-seat catalogs are future work. ║
-- ║                                                      ║
-- ║  Draw sites rendering t() output should use          ║
-- ║  kernel.ustr for width math (UTF-8 ≠ bytes).         ║
-- ╚══════════════════════════════════════════════════════╝

local i18n = {}

local fs, log, serialize, config

local LANG_DIR = "/usr/lang"
local MAX_CATALOG_BYTES = 64 * 1024
local MAX_KEY_LEN = 64
local MAX_VAL_LEN = 512
local MAX_STRINGS = 2048

local current = nil    -- active language code, nil = English (no catalog)
local strings = nil    -- active key -> translated string map
local meta    = nil    -- active catalog's meta table

-- Runtime key registry: every (key, default) t() has seen this session.
-- Powers `lang dump` so a translator can start from a real template
-- instead of grepping the source tree.
local seen = {}

-- ============================================================
-- Helpers
-- ============================================================

--- A valid language code: 2+ lowercase letters, then letters/digits/-/_,
--- 8 chars max ("ru", "es", "pt-br"). Also the filename stem, so the
--- pattern doubles as path-traversal protection.
function i18n.validCode(code)
  return type(code) == "string" and #code >= 2 and #code <= 8
    and code:match("^%l%l[%l%d_%-]*$") ~= nil
end

local function catalogPath(code)
  return LANG_DIR .. "/" .. code .. ".lang"
end

-- ============================================================
-- Init
-- ============================================================

function i18n.init(modules)
  modules = modules or {}
  fs        = modules.fs
  log       = modules.log
  serialize = modules.serialize or require("kernel.serialize")
  config    = modules.config
  -- System default language (applies from boot, so the login screen is
  -- already translated). Failure is non-fatal: stay English.
  local sys = config and config.get and config.get("language")
  if type(sys) == "string" and sys ~= "" and sys ~= "en" then
    local ok, err = i18n.setLanguage(sys)
    if not ok and log then
      log.warn("i18n", "System language '" .. tostring(sys) .. "' not applied: " .. tostring(err))
    end
  end
end

-- ============================================================
-- Catalog loading
-- ============================================================

--- Load + validate a catalog file (pure-ish: touches only fs).
--- Returns { meta = {...}, strings = {...} } or (nil, reason).
function i18n.loadCatalog(code)
  if not i18n.validCode(code) then return nil, "invalid language code" end
  if not fs then return nil, "i18n not initialized" end
  local path = catalogPath(code)
  if not fs.exists(path) then return nil, "no catalog at " .. path end
  local raw = fs.readFile(path)
  if not raw then return nil, "cannot read " .. path end
  if #raw > MAX_CATALOG_BYTES then return nil, "catalog too large (>" .. MAX_CATALOG_BYTES .. " bytes)" end
  local ok, data = pcall(serialize.decode, raw, { maxBytes = MAX_CATALOG_BYTES })
  if not ok or type(data) ~= "table" then return nil, "corrupt catalog (parse failed)" end
  if type(data.strings) ~= "table" then return nil, "corrupt catalog (no strings table)" end
  local out, n = {}, 0
  for k, v in pairs(data.strings) do
    if type(k) == "string" and type(v) == "string"
       and #k > 0 and #k <= MAX_KEY_LEN and #v <= MAX_VAL_LEN then
      out[k] = v
      n = n + 1
      if n >= MAX_STRINGS then break end
    end
  end
  local m = (type(data.meta) == "table") and data.meta or {}
  return { meta = m, strings = out, count = n }
end

--- Switch the active language. "en"/nil/"" resets to English defaults.
function i18n.setLanguage(code)
  if code == nil or code == "" or code == "en" then
    current, strings, meta = nil, nil, nil
    return true
  end
  local cat, err = i18n.loadCatalog(code)
  if not cat then return false, err end
  current, strings, meta = code, cat.strings, cat.meta
  if log then
    log.info("i18n", "Language set: " .. code .. " (" .. tostring(cat.count) .. " strings)")
  end
  return true
end

function i18n.language() return current or "en" end
function i18n.languageName()
  if not current then return "English" end
  return (meta and type(meta.name) == "string" and meta.name) or current
end

--- Scan /usr/lang for installed catalogs. Returns a sorted array of
--- { code, name } (English is always first — it's the built-in default).
function i18n.available()
  local out = { { code = "en", name = "English (built-in)" } }
  if not fs or not fs.exists or not fs.exists(LANG_DIR) then return out end
  local ok, list = pcall(fs.list, LANG_DIR)
  if not ok or not list then return out end
  local names = {}
  if type(list) == "table" then names = list
  elseif type(list) == "function" then for n in list do names[#names + 1] = n end end
  table.sort(names)
  for _, n in ipairs(names) do
    local code = n:match("^(.+)%.lang$")
    if code and i18n.validCode(code) then
      local name = code
      local okC, cat = pcall(i18n.loadCatalog, code)
      if okC and cat and type(cat.meta.name) == "string" then name = cat.meta.name end
      out[#out + 1] = { code = code, name = name }
    end
  end
  return out
end

-- ============================================================
-- Lookup
-- ============================================================

--- Translate. `default` is the inline English text and the guaranteed
--- fallback. Extra args run through string.format — a broken %-spec in
--- a community catalog falls back to formatting the ENGLISH default,
--- and if even that fails, returns the unformatted default (a wrong-
--- language or unformatted string beats a crash in a draw path).
function i18n.t(key, default, ...)
  if type(key) == "string" and type(default) == "string" then
    seen[key] = seen[key] or default
  end
  local s = (strings and type(key) == "string" and strings[key]) or default or key
  if select("#", ...) == 0 then return s end
  local ok, formatted = pcall(string.format, s, ...)
  if ok then return formatted end
  local ok2, f2 = pcall(string.format, default or tostring(key), ...)
  if ok2 then return f2 end
  return default or tostring(key)
end

--- The (key -> English default) registry gathered this session, as a
--- sorted array of { key, default }. Powers `lang dump`.
function i18n.keysSeen()
  local keys = {}
  for k in pairs(seen) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = { key = k, default = seen[k] } end
  return out
end

return i18n
