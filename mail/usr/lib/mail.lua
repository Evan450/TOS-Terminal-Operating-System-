




























local M = {}

M._VERSION = "1.0.0"



local net       = require("kernel.net")
local fs        = require("kernel.fs")
local serialize = require("kernel.serialize")
local log
do
  local ok, mod = pcall(require, "kernel.log")
  if ok and mod and mod.info then log = mod
  else log = { info = function() end, warn = function() end, error = function() end } end
end

M.MAX_BODY    = 4096    
M.MAX_SUBJECT = 120
M.MAX_BOX     = 200     







function M.senderName(m)
  if type(m) ~= "table" then return "?" end
  if type(m.fromUser) == "string" and m.fromUser ~= "" then return m.fromUser end
  return (tostring(m.from or "?")):sub(1, 8)
end



function M.inboxRow(m, idx, width)
  local rd   = (type(m) == "table" and m.read) and " " or "*"
  local who  = M.senderName(m):sub(1, 12)
  local subj = (type(m) == "table" and m.subject ~= "" and m.subject) or "(no subject)"
  local line = string.format(" %s %2d  %-12s  %s", rd, idx, who, subj)
  width = width or 60
  if #line > width then line = line:sub(1, width - 1) .. "~" end
  return line
end



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
M._mailboxFor = mailboxFor   








local function callerPrincipal()
  local okU, users = pcall(require, "kernel.users")
  if not (okU and users and users.currentSession) then
    
    return nil, 3, true
  end
  local s = users.currentSession()
  if not s then return nil, 0, false end
  return s.user, s.tier or 0, s.isKernel or false
end





function M.inboxBox(user)
  user = (type(user) == "string" and user ~= "") and user or "_node"
  local caller, tier, isKernel = callerPrincipal()
  if not (isKernel or tier >= 2 or (caller ~= nil and caller == user)) then
    return nil, "access denied: inbox '" .. tostring(user)
      .. "' is owner-or-admin only (you are " .. tostring(caller or "nobody") .. ")"
  end
  return mailboxFor(user)
end


function M.inbox(user)
  local box, err = M.inboxBox(user)
  if not box then return nil, err end
  return box:list()
end






function M.available()
  return net.meshAvailable and net.meshAvailable() or false
end






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


function M.pending()
  return net.meshPending and net.meshPending() or 0
end


function M.tick()
  if net.meshTick then pcall(net.meshTick) end
end





local _running = false



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
M._onMeshMail = onMeshMail   


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



function M.stop()
  if not _running then return true end
  if net.meshOff then net.meshOff("mail") end
  _running = false
  log.info("mail", "Mail service stopped")
  return true
end


function M.running()
  return _running
end

return M
