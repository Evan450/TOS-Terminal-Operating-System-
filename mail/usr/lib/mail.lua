-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Optional Utilities — Mail (mesh mailbox service)            ║
-- ║                                                              ║
-- ║  Stage 5: mail left the base OS. The kernel now provides a   ║
-- ║  generic, service-multiplexed mesh transport (net.meshSend / ║
-- ║  net.meshOn — flood + dedup + TTL, store-and-forward,        ║
-- ║  end-to-end sealed, TRUSTED-only blind relays); this package ║
-- ║  is mail as a TENANT of that transport: mailbox storage at   ║
-- ║  /var/mail/<user>/inbox.dat, subject/body semantics, the     ║
-- ║  inbox/compose UIs (mailui = CLI TUI, mailapp = panels tab), ║
-- ║  and the rc.d service that registers the delivery handler at ║
-- ║  boot so store-and-forward receive works with nobody logged  ║
-- ║  in.                                                         ║
-- ║                                                              ║
-- ║  FULL-PRIV LIBRARY (blockfs precedent): loaded by the base   ║
-- ║  shell / rc via the real require, so it may use kernel.*.    ║
-- ║  The manifest declares no sandboxed command entrypoints.     ║
-- ║                                                              ║
-- ║  #SEC (review holdovers, both live here now):                ║
-- ║   • refuse-plaintext is enforced by the TRANSPORT            ║
-- ║     (net.meshSend); M.send only forwards an explicit         ║
-- ║     allowPlaintext, auto-allowing the "*" bulletin case      ║
-- ║     (a bulletin is public by definition, and the UIs label   ║
-- ║     it PLAINTEXT loudly).                                    ║
-- ║   • inbox access is enforced against the CALLING PROCESS's   ║
-- ║     kernel-stamped principal (users.currentSession), not a   ║
-- ║     caller-supplied session table: owner or ADMIN+ only.     ║
-- ╚══════════════════════════════════════════════════════════════╝

local M = {}

M._VERSION = "1.0.0"

-- Boot-order-proof requires (cluster lesson): rc.d loads this BEFORE the
-- OpenOS compat aliases exist — use the kernel modules directly.
local net       = require("kernel.net")
local fs        = require("kernel.fs")
local serialize = require("kernel.serialize")
local log
do
  local ok, mod = pcall(require, "kernel.log")
  if ok and mod and mod.info then log = mod
  else log = { info = function() end, warn = function() end, error = function() end } end
end

M.MAX_BODY    = 4096    -- chars; keeps a sealed payload under the mesh cap
M.MAX_SUBJECT = 120
M.MAX_BOX     = 200     -- inbox entries retained (oldest pruned)

-- ============================================================
-- Pure helpers (shared by the CLI TUI and the panels tab)
-- ============================================================

--- Display name for a message's sender: the user name if present, else a
--- short form of the network address. Pure.
function M.senderName(m)
  if type(m) ~= "table" then return "?" end
  if type(m.fromUser) == "string" and m.fromUser ~= "" then return m.fromUser end
  return (tostring(m.from or "?")):sub(1, 8)
end

--- One inbox row: unread marker, index, sender, subject — fit to `width`.
--- Unread mail is marked "*". Pure.
function M.inboxRow(m, idx, width)
  local rd   = (type(m) == "table" and m.read) and " " or "*"
  local who  = M.senderName(m):sub(1, 12)
  local subj = (type(m) == "table" and m.subject ~= "" and m.subject) or "(no subject)"
  local line = string.format(" %s %2d  %-12s  %s", rd, idx, who, subj)
  width = width or 60
  if #line > width then line = line:sub(1, width - 1) .. "~" end
  return line
end

--- Resolve a typed recipient ("peer", "alias", "user@peer", "*") to
--- (toAddr, ruser) using an alias resolver. Pure given `resolve`.
function M.resolveRecipient(to, resolve)
  if not to or to == "" then return nil end
  local ruser, host = to:match("^([^@]+)@(.+)$")
  host = host or to
  local toAddr = host
  if host == "*" then
    toAddr = "*"
  elseif resolve then
    toAddr = resolve(host) or host
  end
  return toAddr, ruser
end

-- ============================================================
-- Mailbox (persisted inbox behind an injected store)
-- ============================================================
-- store = { read(path)->str|nil, write(path,str)->ok[,err], exists(path)->bool }

local Mailbox = {}
Mailbox.__index = Mailbox

function M.newMailbox(store, path)
  return setmetatable({ store = store, path = path, _cache = nil }, Mailbox)
end

function Mailbox:load()
  if self._cache then return self._cache end
  local list = {}
  if self.store.exists(self.path) then
    local data = self.store.read(self.path)
    if data and #data > 0 then
      local ok, parsed = pcall(serialize.decode, data, { maxBytes = 256 * 1024 })
      if ok and type(parsed) == "table" then list = parsed end
    end
  end
  self._cache = list
  return list
end

function Mailbox:save()
  local data = serialize.encode(self._cache or {})
  return self.store.write(self.path, data)
end

-- Append a received message. De-dups by id (a re-flood of an already
-- delivered message must not pile up duplicate inbox entries). Prunes to
-- MAX_BOX, dropping the oldest. Returns true if it was newly added.
function Mailbox:add(msg)
  local list = self:load()
  for _, m in ipairs(list) do if m.id == msg.id then return false end end
  msg.read = false
  list[#list + 1] = msg
  while #list > M.MAX_BOX do table.remove(list, 1) end
  self:save()
  return true
end

function Mailbox:list() return self:load() end
function Mailbox:get(i) return self:load()[i] end

function Mailbox:unread()
  local n = 0
  for _, m in ipairs(self:load()) do if not m.read then n = n + 1 end end
  return n
end

function Mailbox:markRead(i)
  local m = self:get(i)
  if not m then return false end
  m.read = true
  self:save()
  return true
end

function Mailbox:delete(i)
  local list = self:load()
  if not list[i] then return false end
  table.remove(list, i)
  self:save()
  return true
end

-- ============================================================
-- Storage binding (/var/mail/<user>/inbox.dat, raw kernel fs)
-- ============================================================
-- The DELIVERY path writes via raw fs (kernel context — securefs's
-- /var/mail owner-or-ADMIN ACL protects interactive reads; see
-- test_mail_privacy in the base image). The username is sanitised so it
-- can't escape /var/mail.

local function mailboxFor(user)
  user = (type(user) == "string" and user ~= "") and user or "_node"
  user = user:gsub("[^%w%._%-]", "_")
  local dir = "/var/mail/" .. user
  return M.newMailbox({
    exists = function(p) return fs.exists(p) end,
    read   = function(p) return fs.readFile(p) end,
    write  = function(p, d)
      if not fs.exists(dir) then pcall(fs.makeDirectory, dir) end
      return fs.writeFile(p, d)
    end,
  }, dir .. "/inbox.dat")
end
M._mailboxFor = mailboxFor   -- test hook (not an access path — see inboxBox)

-- ============================================================
-- Inbox access (#SEC — principal-enforced, not caller-claimed)
-- ============================================================

-- Resolve the CALLER's identity from the kernel-stamped process
-- principal. Returns (user, tier, isKernel). Fails closed to guest when
-- the user system is up but no session exists.
local function callerPrincipal()
  local okU, users = pcall(require, "kernel.users")
  if not (okU and users and users.currentSession) then
    -- No user system (early boot / minimal box): kernel-equivalent.
    return nil, 3, true
  end
  local s = users.currentSession()
  if not s then return nil, 0, false end
  return s.user, s.tier or 0, s.isKernel or false
end

--- The Mailbox object for `user` (list/markRead/delete/unread), or
--- (nil, reason). Owner or ADMIN+ only — enforced against the calling
--- process's principal, so a sandboxed program that require()s this lib
--- can't read someone else's inbox by claiming a name.
function M.inboxBox(user)
  user = (type(user) == "string" and user ~= "") and user or "_node"
  local caller, tier, isKernel = callerPrincipal()
  if not (isKernel or tier >= 2 or (caller ~= nil and caller == user)) then
    return nil, "access denied: inbox '" .. tostring(user)
      .. "' is owner-or-admin only (you are " .. tostring(caller or "nobody") .. ")"
  end
  return mailboxFor(user)
end

--- The inbox (array of message records) for `user`. Same enforcement.
function M.inbox(user)
  local box, err = M.inboxBox(user)
  if not box then return nil, err end
  return box:list()
end

-- ============================================================
-- Send / status (thin veneer over the mesh transport)
-- ============================================================

--- True when the mesh transport is up (network hardware present).
function M.available()
  return net.meshAvailable and net.meshAvailable() or false
end

--- Send a mail. `opts` = { to=address|"*", user=, fromUser=, subject=,
--- body=, allowPlaintext= }. Returns (id, sealed) or (nil, reason).
--- Plaintext unicast is refused by the TRANSPORT unless allowPlaintext;
--- "*" bulletins are public by definition, so they auto-allow (the UIs
--- label them PLAINTEXT loudly).
function M.send(opts)
  opts = opts or {}
  return net.meshSend({
    svc = "mail",
    to = opts.to, user = opts.user, fromUser = opts.fromUser,
    payload = {
      subject = tostring(opts.subject or ""):sub(1, M.MAX_SUBJECT),
      body    = tostring(opts.body or ""):sub(1, M.MAX_BODY),
    },
    allowPlaintext = opts.allowPlaintext or (opts.to == "*") or nil,
  })
end

--- Count of our sent mails still awaiting acknowledgement.
function M.pending()
  return net.meshPending and net.meshPending() or 0
end

--- Pump mesh retries (throttled kernel-side; safe to call often).
function M.tick()
  if net.meshTick then pcall(net.meshTick) end
end

-- ============================================================
-- Service (rc.d): the boot-time delivery handler
-- ============================================================

local _running = false

-- Mesh delivery -> inbox record. Returning true ACKs the delivery back
-- to the sender; false (storage refused / duplicate) leaves it unACKed.
local function onMeshMail(msg)
  local p = msg.payload
  local record = {
    id = msg.id, from = msg.from, fromUser = msg.fromUser,
    to = msg.to, user = msg.user,
    subject = (p and p.subject) or "(unreadable)",
    body    = (p and p.body) or "",
    ts = msg.ts, sealed = msg.sealed, readable = msg.readable, how = msg.how,
  }
  local box = mailboxFor(msg.user)
  local added = box and box:add(record)
  if added then
    log.info("mail", "Mail delivered to " .. tostring(msg.user or "_node")
      .. " from " .. tostring(msg.from):sub(1, 8))
  end
  return added and true or false
end
M._onMeshMail = onMeshMail   -- test hook

--- Start receiving: register the "mail" handler on the mesh transport.
function M.start()
  if _running then return true end
  if not (net.meshOn and net.meshAvailable and net.meshAvailable()) then
    return false, "mesh transport not available (no network?)"
  end
  net.meshOn("mail", onMeshMail)
  _running = true
  log.info("mail", "Mail service up (mesh kind 'mail' registered)")
  return true
end

--- Stop receiving: unregister the handler. Queued outbound retries keep
--- flowing (they live in the kernel transport).
function M.stop()
  if not _running then return true end
  if net.meshOff then net.meshOff("mail") end
  _running = false
  log.info("mail", "Mail service stopped")
  return true
end

--- Is the delivery handler registered (i.e. can this box RECEIVE)?
function M.running()
  return _running
end

return M
