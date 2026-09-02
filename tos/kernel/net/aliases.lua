local aliases = {}

local fs        = nil
local securefs  = nil
local users     = nil
local log       = nil
local serialize = nil

local ALIAS_PATH = "/etc/peer_aliases.dat"

local _byName = {}
local _byAddr = {}

function aliases.init(modules)
  fs        = modules.fs
  securefs  = modules.securefs
  users     = modules.users
  log       = modules.log
  serialize = modules.serialize or require("kernel.serialize")
  aliases._load()
end

function aliases._load()
  _byName, _byAddr = {}, {}
  if not fs or not fs.exists or not fs.exists(ALIAS_PATH) then return end
  local raw = fs.readFile(ALIAS_PATH)
  if not raw or #raw == 0 then return end
  local ok, data = pcall(serialize.decode, raw, { maxBytes = 16384 })
  if not ok or type(data) ~= "table" then
    if log then log.warn("aliases", "Corrupt alias file at " .. ALIAS_PATH) end
    return
  end
  for k, v in pairs(data) do
    if type(k) == "string" and type(v) == "table"
       and type(v.alias) == "string" and type(v.address) == "string" then
      _byName[k] = v
      _byAddr[v.address] = k
    end
  end
end

local function _save()
  if not fs then return false, "fs unavailable" end
  return fs.writeFile(ALIAS_PATH, serialize.encode(_byName))
end

local function requireAdmin(opName)
  if not users or not users.currentSession or not users.TIER then
    return true
  end
  local sess = users.currentSession()
  if not sess then return false, "no session" end
  if sess.isKernel then return true end
  if (sess.tier or 0) < (users.TIER.ADMIN or 2) then
    return false, "alias " .. opName .. " requires admin tier"
  end
  return true
end

local function validAlias(s)
  if type(s) ~= "string" then return false, "not a string" end
  if #s < 1 or #s > 32 then return false, "alias must be 1-32 chars" end
  if not s:match("^[%w_%-]+$") then
    return false, "alias must be alphanumeric + _ + -"
  end
  return true
end

local function validAddress(s)
  if type(s) ~= "string" then return false, "not a string" end

  if #s < 8 or #s > 64 then return false, "address looks malformed" end
  if not s:match("^[%w%-]+$") then return false, "address has odd chars" end
  return true
end

function aliases.set(alias, address)
  local okT, terr = requireAdmin("set")
  if not okT then return false, terr end
  local okA, aerr = validAlias(alias)
  if not okA then return false, aerr end
  local okD, derr = validAddress(address)
  if not okD then return false, derr end
  local key = alias:lower()

  local prev = _byName[key]
  if prev and prev.address ~= address then
    _byAddr[prev.address] = nil
  end

  local prevKey = _byAddr[address]
  if prevKey and prevKey ~= key then
    _byName[prevKey] = nil
  end

  _byName[key] = { alias = alias, address = address }
  _byAddr[address] = key
  local ok, err = _save()
  if not ok then return false, "persist: " .. tostring(err) end
  if log then
    log.info("aliases", string.format("aliased %s -> %s",
      alias, address:sub(1, 12) .. "..."))
  end
  return true
end

function aliases.remove(alias)
  local okT, terr = requireAdmin("remove")
  if not okT then return false, terr end
  if type(alias) ~= "string" then return false, "alias is not a string" end
  local key = alias:lower()
  local entry = _byName[key]
  if not entry then return false, "no such alias" end
  _byName[key] = nil
  _byAddr[entry.address] = nil
  local ok, err = _save()
  if not ok then return false, "persist: " .. tostring(err) end
  if log then log.info("aliases", "removed alias " .. alias) end
  return true
end

function aliases.addressOf(alias)
  if type(alias) ~= "string" then return nil end
  local entry = _byName[alias:lower()]
  return entry and entry.address or nil
end

function aliases.aliasOf(address)
  if type(address) ~= "string" then return nil end
  local key = _byAddr[address]
  return key and _byName[key] and _byName[key].alias or nil
end

function aliases.list()
  local out = {}
  for _, entry in pairs(_byName) do
    out[#out + 1] = { alias = entry.alias, address = entry.address }
  end
  table.sort(out, function(a, b) return a.alias:lower() < b.alias:lower() end)
  return out
end

function aliases.resolve(s)
  if type(s) ~= "string" or s == "" then
    return nil, "empty"
  end

  local viaAlias = aliases.addressOf(s)
  if viaAlias then return viaAlias end

  if s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
    return s
  end

  local matches = {}
  for addr in pairs(_byAddr) do
    if addr:sub(1, #s) == s then matches[#matches + 1] = addr end
  end
  if #matches == 1 then return matches[1] end
  if #matches > 1 then return nil, "ambiguous prefix matches multiple aliases" end

  return nil, "no alias and no known peer matches '" .. s .. "'"
end

function aliases.format(address)
  if type(address) ~= "string" then return "?" end
  local short = address:sub(1, 8) .. "..."
  local alias = aliases.aliasOf(address)
  if alias then return alias .. " (" .. short .. ")" end
  return short
end

return aliases
