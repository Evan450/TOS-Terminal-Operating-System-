-- ╔═══════════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Peer aliases                                    ║
-- ║                                                               ║
-- ║  Human-friendly names for modem addresses. Solves the "type   ║
-- ║  a 36-character UUID every time you want to chat" problem.    ║
-- ║                                                               ║
-- ║  Storage: /etc/peer_aliases.dat (serialize.encode'd table)    ║
-- ║  Scope:   system-wide (one alias table per machine), not      ║
-- ║           per-user. Operators share peer names just like they ║
-- ║           share trust relationships.                          ║
-- ║                                                               ║
-- ║  Tier:   ADMIN to set/remove (mutates /etc); anyone can read. ║
-- ║                                                               ║
-- ║  Alias rules:                                                 ║
-- ║    * 1-32 chars                                               ║
-- ║    * alphanumeric + _ + -                                     ║
-- ║    * case-preserved on display, case-insensitive on lookup    ║
-- ║      (so the operator can type "Tape-vault" or "tape-vault")  ║
-- ║    * one alias per address (forward unique)                   ║
-- ║    * one address per alias (reverse unique)                   ║
-- ║                                                               ║
-- ║  Resolution helper: resolve(s) accepts EITHER an alias OR a   ║
-- ║  full/partial UUID and returns the canonical address. This    ║
-- ║  is what command-line tools should call before passing the    ║
-- ║  identifier to net.send / trust APIs.                         ║
-- ╚═══════════════════════════════════════════════════════════════╝

local aliases = {}

local fs        = nil
local securefs  = nil
local users     = nil
local log       = nil
local serialize = nil

local ALIAS_PATH = "/etc/peer_aliases.dat"

-- forward: name(lower) → { alias = displayName, address = fullAddr }
-- reverse: address → name(lower)
local _byName = {}
local _byAddr = {}

-- ============================================================
-- Init
-- ============================================================

function aliases.init(modules)
  fs        = modules.fs
  securefs  = modules.securefs
  users     = modules.users
  log       = modules.log
  serialize = modules.serialize or require("kernel.serialize")
  aliases._load()
end

-- ============================================================
-- Disk I/O
-- ============================================================

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

-- ============================================================
-- Tier gate
-- ============================================================

local function requireAdmin(opName)
  if not users or not users.currentSession or not users.TIER then
    return true  -- early boot / minimal env: trust the caller
  end
  local sess = users.currentSession()
  if not sess then return false, "no session" end
  if sess.isKernel then return true end
  if (sess.tier or 0) < (users.TIER.ADMIN or 2) then
    return false, "alias " .. opName .. " requires admin tier"
  end
  return true
end

-- ============================================================
-- Validation
-- ============================================================

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
  -- Full UUID is 36 chars (8-4-4-4-12 hex with dashes). We accept
  -- ≥ 16 because some test environments use short addresses; the
  -- caller's resolve() pass will reject ambiguous short prefixes.
  if #s < 8 or #s > 64 then return false, "address looks malformed" end
  if not s:match("^[%w%-]+$") then return false, "address has odd chars" end
  return true
end

-- ============================================================
-- Public API
-- ============================================================

--- Register `alias` → `address`. Replaces any existing mapping for
--- either side (so renaming a host or repointing an alias is one call).
function aliases.set(alias, address)
  local okT, terr = requireAdmin("set")
  if not okT then return false, terr end
  local okA, aerr = validAlias(alias)
  if not okA then return false, aerr end
  local okD, derr = validAddress(address)
  if not okD then return false, derr end
  local key = alias:lower()

  -- If the alias was previously bound to a different address, remove
  -- the stale reverse entry.
  local prev = _byName[key]
  if prev and prev.address ~= address then
    _byAddr[prev.address] = nil
  end
  -- If the address was previously bound to a different alias, drop it.
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

--- Drop an alias by name (case-insensitive).
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

--- Look up an address by alias (case-insensitive). Returns the full
--- address string, or nil.
function aliases.addressOf(alias)
  if type(alias) ~= "string" then return nil end
  local entry = _byName[alias:lower()]
  return entry and entry.address or nil
end

--- Reverse lookup: alias for an address, or nil.
function aliases.aliasOf(address)
  if type(address) ~= "string" then return nil end
  local key = _byAddr[address]
  return key and _byName[key] and _byName[key].alias or nil
end

--- All aliases as an array of { alias, address } records, sorted by
--- alias for stable display.
function aliases.list()
  local out = {}
  for _, entry in pairs(_byName) do
    out[#out + 1] = { alias = entry.alias, address = entry.address }
  end
  table.sort(out, function(a, b) return a.alias:lower() < b.alias:lower() end)
  return out
end

--- Resolution helper used by every network-aware command.
--- Accepts EITHER:
---   * a known alias (case-insensitive) → returns the bound address
---   * a full UUID (36 chars with dashes) → returns it verbatim
---   * a partial UUID prefix that uniquely matches ONE known alias
---     address — returns the canonical full address
--- Returns (nil, reason) when ambiguous or unresolved.
function aliases.resolve(s)
  if type(s) ~= "string" or s == "" then
    return nil, "empty"
  end
  -- 1. Exact alias.
  local viaAlias = aliases.addressOf(s)
  if viaAlias then return viaAlias end
  -- 2. Full UUID address — accept verbatim. #SEC M-5 — require the exact
  -- 8-4-4-4-12 hex UUID shape (matching trust.lua), not any 32+ char
  -- alphanumeric/dash blob. The loose check accepted junk like a 32-char
  -- label as if it were a peer address.
  if s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
    return s
  end
  -- 3. Prefix match against known alias addresses.
  local matches = {}
  for addr in pairs(_byAddr) do
    if addr:sub(1, #s) == s then matches[#matches + 1] = addr end
  end
  if #matches == 1 then return matches[1] end
  if #matches > 1 then return nil, "ambiguous prefix matches multiple aliases" end
  -- 4. No idea.
  return nil, "no alias and no known peer matches '" .. s .. "'"
end

--- Pretty-print an address: returns "<alias> (xxxxxxxx...)" if aliased,
--- else just the truncated address. Used by net/chat/cluster status
--- output for readability.
function aliases.format(address)
  if type(address) ~= "string" then return "?" end
  local short = address:sub(1, 8) .. "..."
  local alias = aliases.aliasOf(address)
  if alias then return alias .. " (" .. short .. ")" end
  return short
end

return aliases
