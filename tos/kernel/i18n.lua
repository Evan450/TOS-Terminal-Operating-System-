local i18n = {}

local fs, log, serialize, config

local LANG_DIR = "/usr/lang"
local MAX_CATALOG_BYTES = 64 * 1024
local MAX_KEY_LEN = 64
local MAX_VAL_LEN = 512
local MAX_STRINGS = 2048

local current = nil
local strings = nil
local meta    = nil

local seen = {}

function i18n.validCode(code)
  return type(code) == "string" and #code >= 2 and #code <= 8
    and code:match("^%l%l[%l%d_%-]*$") ~= nil
end

local function catalogPath(code)
  return LANG_DIR .. "/" .. code .. ".lang"
end

function i18n.init(modules)
  modules = modules or {}
  fs        = modules.fs
  log       = modules.log
  serialize = modules.serialize or require("kernel.serialize")
  config    = modules.config

  local sys = config and config.get and config.get("language")
  if type(sys) == "string" and sys ~= "" and sys ~= "en" then
    local ok, err = i18n.setLanguage(sys)
    if not ok and log then
      log.warn("i18n", "System language '" .. tostring(sys) .. "' not applied: " .. tostring(err))
    end
  end
end

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

function i18n.keysSeen()
  local keys = {}
  for k in pairs(seen) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = { key = k, default = seen[k] } end
  return out
end

return i18n
